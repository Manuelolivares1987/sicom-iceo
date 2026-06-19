-- ============================================================================
-- SICOM-ICEO | 161 — Ticket de bodega (firma jefe → escaneo bodeguero → rebaja)
-- ============================================================================
-- Fase C (Manuel, 2026-06-18):
--   El jefe de taller emite un TICKET por camión/OT con los materiales de las
--   NC de ese equipo, firmado. El bodeguero lo escanea, marca lo que tiene en
--   stock y entrega: rebaja FIFO real (reusa rpc_registrar_salida_bodega).
--   Entrega TOTAL -> ticket 'entregado' (no se puede reusar, anti-robo).
--   Entrega PARCIAL -> 'parcial', sale solo lo entregado y se puede completar
--   después (re-escaneo) hasta cubrir lo solicitado.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tablas ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bodega_tickets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio           VARCHAR(30) UNIQUE NOT NULL,
    qr_code         VARCHAR(120),
    ot_id           UUID REFERENCES ordenes_trabajo(id),
    activo_id       UUID REFERENCES activos(id),
    bodega_id       UUID REFERENCES bodegas(id),
    estado          VARCHAR(20) NOT NULL DEFAULT 'emitido',  -- emitido|parcial|entregado|anulado
    emitido_por     UUID REFERENCES usuarios_perfil(id),
    firma_jefe_url  TEXT,
    observacion     TEXT,
    entregado_por   UUID REFERENCES usuarios_perfil(id),
    entregado_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bodega_ticket_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES bodega_tickets(id) ON DELETE CASCADE,
    producto_id         UUID REFERENCES productos(id),
    descripcion         VARCHAR(200),
    unidad              VARCHAR(20),
    cantidad_solicitada NUMERIC(12,2) NOT NULL,
    cantidad_entregada  NUMERIC(12,2) NOT NULL DEFAULT 0,
    nc_id               UUID REFERENCES no_conformidades(id),
    nc_material_id      UUID REFERENCES nc_materiales(id),
    comentario          TEXT,
    created_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bodega_ticket_items_ticket ON bodega_ticket_items(ticket_id);
CREATE INDEX IF NOT EXISTS idx_bodega_tickets_ot ON bodega_tickets(ot_id);

ALTER TABLE bodega_tickets       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bodega_ticket_items  ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_bodega_tickets_sel') THEN
        CREATE POLICY pol_bodega_tickets_sel ON bodega_tickets FOR SELECT TO authenticated USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_bodega_ticket_items_sel') THEN
        CREATE POLICY pol_bodega_ticket_items_sel ON bodega_ticket_items FOR SELECT TO authenticated USING (true);
    END IF;
END $$;


-- ── 2. Permitir al rol 'bodeguero' registrar salidas (reemplazo en vivo) ─────
DO $mig161$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_bodega' LIMIT 1;
    IF v_def IS NULL THEN RAISE EXCEPTION 'rpc_registrar_salida_bodega no existe'; END IF;
    IF position('''bodeguero''' IN v_def) = 0
       AND position('''operador_abastecimiento''' IN v_def) > 0 THEN
        v_def := replace(v_def, '''operador_abastecimiento''', '''operador_abastecimiento'',''bodeguero''');
        EXECUTE v_def;
        RAISE NOTICE 'rpc_registrar_salida_bodega: rol bodeguero habilitado';
    ELSE
        RAISE NOTICE 'rpc_registrar_salida_bodega: sin cambios (ya permite bodeguero o patron distinto)';
    END IF;
END $mig161$;


-- ── 2b. Permitir retiro de material con OT 'pausada' (multi-día) ─────────────
-- El bodeguero despacha mientras el mecánico pausó la jornada para ir por
-- repuestos; sin esto, la salida se bloquea en pausada.
DO $mig161b$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_inventario' LIMIT 1;
    IF v_def IS NOT NULL
       AND position('''pausada''' IN v_def) = 0
       AND position('NOT IN (''asignada'', ''en_ejecucion'')' IN v_def) > 0 THEN
        v_def := replace(v_def, 'NOT IN (''asignada'', ''en_ejecucion'')',
                                'NOT IN (''asignada'', ''en_ejecucion'', ''pausada'')');
        EXECUTE v_def;
        RAISE NOTICE 'rpc_registrar_salida_inventario: estado pausada permitido';
    ELSE
        RAISE NOTICE 'rpc_registrar_salida_inventario: sin cambios';
    END IF;
END $mig161b$;


-- ── 3. RPC: emitir ticket (jefe) ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_crear_ticket_bodega(
    p_ot_id UUID, p_firma_jefe_url TEXT, p_observacion TEXT DEFAULT NULL, p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_activo UUID; v_folio TEXT; v_periodo TEXT; v_sec INT; v_id UUID; v_qr TEXT; v_n INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo el jefe de taller emite tickets (rol: %)', v_rol; END IF;
    IF p_firma_jefe_url IS NULL OR length(trim(p_firma_jefe_url))=0 THEN
        RAISE EXCEPTION 'La firma del jefe es obligatoria'; END IF;

    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id=p_ot_id;
    IF v_activo IS NULL THEN RAISE EXCEPTION 'OT no existe'; END IF;

    IF EXISTS (SELECT 1 FROM bodega_tickets WHERE ot_id=p_ot_id AND estado IN ('emitido','parcial')) THEN
        RAISE EXCEPTION 'Ya existe un ticket abierto para esta OT'; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM nc_materiales m JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
         WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false) THEN
        RAISE EXCEPTION 'No hay materiales asignados a las NC de esta OT'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(),'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)),0)+1 INTO v_sec
      FROM bodega_tickets WHERE folio LIKE 'TKT-'||v_periodo||'-%';
    v_folio := 'TKT-'||v_periodo||'-'||LPAD(v_sec::text,5,'0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-'||v_folio;

    INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, bodega_id, estado, emitido_por, firma_jefe_url, observacion)
    VALUES (v_id, v_folio, v_qr, p_ot_id, v_activo, p_bodega_id, 'emitido', v_user, p_firma_jefe_url, p_observacion);

    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, nc_id, nc_material_id, comentario)
    SELECT v_id, m.producto_id, COALESCE(m.descripcion, pr.nombre), pr.unidad_medida,
           m.cantidad, nc.id, m.id, m.comentario
      FROM nc_materiales m
      JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
      LEFT JOIN productos pr ON pr.id=m.producto_id
     WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false;

    SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id=v_id;
    RETURN jsonb_build_object('success',true,'ticket_id',v_id,'folio',v_folio,'qr',v_qr,'items',v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_crear_ticket_bodega(UUID,TEXT,TEXT,UUID) TO authenticated;


-- ── 4. RPC: entregar (bodeguero) — rebaja FIFO total/parcial ─────────────────
CREATE OR REPLACE FUNCTION rpc_entregar_ticket_bodega(
    p_ticket_id UUID, p_bodega_id UUID, p_entregas JSONB,
    p_entregado_a VARCHAR DEFAULT NULL, p_firma_bodeguero_url TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_tk RECORD; v_ti RECORD; e RECORD; v_faena UUID; v_ceco UUID;
    v_items JSONB := '[]'::JSONB; v_salida JSONB; v_folio TEXT; v_falta INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','supervisor','jefe_mantenimiento','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para entregar', v_rol; END IF;

    SELECT * INTO v_tk FROM bodega_tickets WHERE id=p_ticket_id;
    IF v_tk.id IS NULL THEN RAISE EXCEPTION 'Ticket no existe'; END IF;
    IF v_tk.estado IN ('entregado','anulado') THEN
        RAISE EXCEPTION 'Ticket % ya esta % — no se puede volver a usar', v_tk.folio, v_tk.estado; END IF;
    IF p_bodega_id IS NULL THEN RAISE EXCEPTION 'Debe elegir la bodega de despacho'; END IF;

    -- Resolver CECO (obligatorio para la salida): por faena de la OT, si no CECO-BODEGA.
    SELECT faena_id INTO v_faena FROM ordenes_trabajo WHERE id=v_tk.ot_id;
    SELECT id INTO v_ceco FROM centros_costo
     WHERE faena_id = v_faena AND COALESCE(activo,true)=true ORDER BY created_at LIMIT 1;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE codigo='CECO-BODEGA' LIMIT 1; END IF;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE COALESCE(activo,true)=true ORDER BY created_at LIMIT 1; END IF;

    -- Validar y armar items con producto para la salida FIFO
    FOR e IN SELECT * FROM jsonb_to_recordset(p_entregas) AS x(ticket_item_id UUID, cantidad NUMERIC)
    LOOP
        IF e.cantidad IS NULL OR e.cantidad <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_ti FROM bodega_ticket_items WHERE id=e.ticket_item_id AND ticket_id=p_ticket_id;
        IF v_ti.id IS NULL THEN RAISE EXCEPTION 'Item no pertenece al ticket'; END IF;
        IF e.cantidad > (v_ti.cantidad_solicitada - v_ti.cantidad_entregada) THEN
            RAISE EXCEPTION 'Cantidad supera lo pendiente en "%"', COALESCE(v_ti.descripcion,'item'); END IF;
        IF v_ti.producto_id IS NOT NULL THEN
            v_items := v_items || jsonb_build_object('producto_id', v_ti.producto_id, 'cantidad', e.cantidad, 'unidad', v_ti.unidad);
        END IF;
    END LOOP;

    IF jsonb_array_length(v_items) = 0 THEN
        RAISE EXCEPTION 'No hay cantidades a entregar'; END IF;

    -- Rebaja FIFO real (una salida = un despacho)
    v_salida := rpc_registrar_salida_bodega(
        'ot', p_bodega_id, v_ceco, v_tk.ot_id,
        'Despacho ticket '||v_tk.folio, v_items,
        p_entregado_a, NULL, v_tk.emitido_por, p_firma_bodeguero_url,
        'Ticket bodega '||v_tk.folio);
    v_folio := v_salida->>'folio';

    -- Acumular entregado por item
    FOR e IN SELECT * FROM jsonb_to_recordset(p_entregas) AS x(ticket_item_id UUID, cantidad NUMERIC)
    LOOP
        IF e.cantidad IS NULL OR e.cantidad <= 0 THEN CONTINUE; END IF;
        UPDATE bodega_ticket_items SET cantidad_entregada = cantidad_entregada + e.cantidad
         WHERE id=e.ticket_item_id AND ticket_id=p_ticket_id;
    END LOOP;

    SELECT COUNT(*) INTO v_falta FROM bodega_ticket_items
     WHERE ticket_id=p_ticket_id AND cantidad_entregada < cantidad_solicitada;

    IF v_falta = 0 THEN
        UPDATE bodega_tickets SET estado='entregado', entregado_at=NOW(), entregado_por=v_user,
            bodega_id=COALESCE(bodega_id,p_bodega_id), updated_at=NOW() WHERE id=p_ticket_id;
    ELSE
        UPDATE bodega_tickets SET estado='parcial',
            bodega_id=COALESCE(bodega_id,p_bodega_id), updated_at=NOW() WHERE id=p_ticket_id;
    END IF;

    RETURN jsonb_build_object('success',true,'despacho_folio',v_folio,
        'estado', CASE WHEN v_falta=0 THEN 'entregado' ELSE 'parcial' END);
END $$;
GRANT EXECUTE ON FUNCTION rpc_entregar_ticket_bodega(UUID,UUID,JSONB,VARCHAR,TEXT) TO authenticated;


-- ── 5. RPC anular ticket (jefe) ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_anular_ticket_bodega(p_ticket_id UUID, p_motivo TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_estado TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    SELECT estado INTO v_estado FROM bodega_tickets WHERE id=p_ticket_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ticket no existe'; END IF;
    IF v_estado='entregado' THEN RAISE EXCEPTION 'No se puede anular un ticket ya entregado'; END IF;
    UPDATE bodega_tickets SET estado='anulado',
        observacion = COALESCE(observacion,'')||CASE WHEN p_motivo IS NOT NULL THEN ' | Anulado: '||p_motivo ELSE ' | Anulado' END,
        updated_at=NOW() WHERE id=p_ticket_id;
    RETURN jsonb_build_object('success',true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_anular_ticket_bodega(UUID,TEXT) TO authenticated;


-- ── 6. Vistas ────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_bodega_ticket CASCADE;
CREATE VIEW v_bodega_ticket AS
SELECT tk.id, tk.folio, tk.qr_code, tk.ot_id, tk.activo_id, tk.bodega_id, tk.estado,
       tk.emitido_por, tk.firma_jefe_url, tk.observacion, tk.entregado_por, tk.entregado_at,
       tk.created_at,
       ot.folio AS ot_folio, ot.faena_id,
       a.codigo AS activo_codigo, a.nombre AS activo_nombre, a.patente AS activo_patente,
       up.nombre_completo AS emitido_por_nombre,
       ub.nombre_completo AS entregado_por_nombre,
       (SELECT COUNT(*) FROM bodega_ticket_items i WHERE i.ticket_id=tk.id) AS n_items,
       (SELECT COUNT(*) FROM bodega_ticket_items i WHERE i.ticket_id=tk.id
          AND i.cantidad_entregada >= i.cantidad_solicitada) AS n_entregados
FROM bodega_tickets tk
LEFT JOIN ordenes_trabajo ot ON ot.id=tk.ot_id
LEFT JOIN activos a ON a.id=tk.activo_id
LEFT JOIN usuarios_perfil up ON up.id=tk.emitido_por
LEFT JOIN usuarios_perfil ub ON ub.id=tk.entregado_por;
GRANT SELECT ON v_bodega_ticket TO authenticated;

DROP VIEW IF EXISTS v_bodega_ticket_items CASCADE;
CREATE VIEW v_bodega_ticket_items AS
SELECT i.id, i.ticket_id, i.producto_id, i.descripcion, i.unidad,
       i.cantidad_solicitada, i.cantidad_entregada,
       (i.cantidad_solicitada - i.cantidad_entregada) AS pendiente,
       i.nc_id, i.comentario,
       pr.codigo AS producto_codigo, pr.nombre AS producto_nombre, pr.unidad_medida
FROM bodega_ticket_items i
LEFT JOIN productos pr ON pr.id=i.producto_id;
GRANT SELECT ON v_bodega_ticket_items TO authenticated;

-- OTs con materiales de NC pendientes y sin ticket abierto (para emitir)
DROP VIEW IF EXISTS v_bodega_tickets_emitibles CASCADE;
CREATE VIEW v_bodega_tickets_emitibles AS
SELECT ot.id AS ot_id, ot.folio AS ot_folio,
       a.codigo AS activo_codigo, a.nombre AS activo_nombre, a.patente AS activo_patente,
       (SELECT COUNT(*) FROM nc_materiales m JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
          WHERE nc.ot_id=ot.id AND COALESCE(nc.resuelto,false)=false) AS n_materiales
FROM ordenes_trabajo ot
JOIN activos a ON a.id=ot.activo_id
WHERE EXISTS (SELECT 1 FROM nc_materiales m JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
               WHERE nc.ot_id=ot.id AND COALESCE(nc.resuelto,false)=false)
  AND NOT EXISTS (SELECT 1 FROM bodega_tickets tk WHERE tk.ot_id=ot.id AND tk.estado IN ('emitido','parcial'));
GRANT SELECT ON v_bodega_tickets_emitibles TO authenticated;


-- ── 7. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tablas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.tables
        WHERE table_name IN ('bodega_tickets','bodega_ticket_items')),
    'rpcs', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_crear_ticket_bodega','rpc_entregar_ticket_bodega','rpc_anular_ticket_bodega')),
    'vistas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.views
        WHERE table_name IN ('v_bodega_ticket','v_bodega_ticket_items','v_bodega_tickets_emitibles')),
    'salida_permite_bodeguero', (SELECT position('''bodeguero''' IN pg_get_functiondef(p.oid))>0
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_bodega' LIMIT 1)
) AS resultado;

NOTIFY pgrst, 'reload schema';
