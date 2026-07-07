-- ============================================================================
-- SICOM-ICEO | 197 — Recursos de reparación pedidos por el operador de taller
--                    y validados por el jefe antes del vale de bodega
-- ============================================================================
-- Pedido Manuel (2026-07-07): durante la ejecución del checklist en /m/taller
-- el operador escoge los recursos (repuestos/materiales) que necesita para
-- reparar. El jefe de taller los valida (aprueba / rechaza / ajusta cantidad /
-- agrega ítems) y genera el vale de bodega.
--
--   * Tabla ot_recursos_solicitados: pedido por OT (producto del catálogo o
--     texto libre + cantidad). client_uuid único para el sync offline.
--   * rpc_ot_recurso_solicitar (operador, offline-safe) + alerta campanita
--     'recurso_solicitado' a jefatura.
--   * rpc_ot_recurso_validar (jefe: aprobar con cantidad ajustada / rechazar).
--   * rpc_ot_recurso_agregar (jefe agrega directo, nace aprobado).
--   * rpc_crear_ticket_bodega (MIG161) ahora TAMBIÉN incluye los recursos
--     aprobados de la OT (además de los nc_materiales); al emitir quedan
--     'en_vale'. rpc_anular_ticket_bodega los devuelve a 'aprobado'.
--   * Vista v_ot_recursos (producto + stock total + nombres + ticket).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='bodega_tickets') THEN
        RAISE EXCEPTION 'STOP — falta bodega_tickets (MIG161).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='productos') THEN
        RAISE EXCEPTION 'STOP — falta productos.';
    END IF;
END $$;


-- ── 1. Tabla ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ot_recursos_solicitados (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid       UUID UNIQUE,                 -- idempotencia del sync offline
    ot_id             UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    producto_id       UUID REFERENCES productos(id),
    descripcion       VARCHAR(200),                -- texto libre si no está en catálogo
    unidad            VARCHAR(20),
    cantidad          NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    cantidad_aprobada NUMERIC(12,2) CHECK (cantidad_aprobada IS NULL OR cantidad_aprobada > 0),
    comentario        TEXT,
    estado            VARCHAR(20) NOT NULL DEFAULT 'solicitado'
        CHECK (estado IN ('solicitado','aprobado','rechazado','en_vale')),
    solicitado_por    UUID REFERENCES usuarios_perfil(id),
    solicitado_nombre VARCHAR(120),                -- mecánico elegido (cuenta compartida)
    agregado_por_jefe BOOLEAN NOT NULL DEFAULT false,
    validado_por      UUID REFERENCES usuarios_perfil(id),
    validado_at       TIMESTAMPTZ,
    nota_jefe         TEXT,
    ticket_id         UUID REFERENCES bodega_tickets(id),
    created_at        TIMESTAMPTZ DEFAULT now(),
    updated_at        TIMESTAMPTZ DEFAULT now(),
    CHECK (producto_id IS NOT NULL OR descripcion IS NOT NULL)
);
COMMENT ON TABLE ot_recursos_solicitados IS
    'Recursos (repuestos/materiales) que el operador de taller pide para reparar una OT; el jefe los valida y emite el vale de bodega. MIG197.';
CREATE INDEX IF NOT EXISTS idx_ot_recursos_ot ON ot_recursos_solicitados(ot_id);
CREATE INDEX IF NOT EXISTS idx_ot_recursos_estado ON ot_recursos_solicitados(estado) WHERE estado = 'solicitado';

ALTER TABLE ot_recursos_solicitados ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_ot_recursos_sel') THEN
        CREATE POLICY pol_ot_recursos_sel ON ot_recursos_solicitados FOR SELECT TO authenticated USING (true);
    END IF;
    -- Escrituras SOLO vía RPCs SECURITY DEFINER (sin política de write).
END $$;


-- ── 2. Campanita: tipo nuevo 'recurso_solicitado' ────────────────────────────
DO $$
DECLARE v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
      FROM pg_constraint
     WHERE conrelid = 'alertas'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%no_conformidad%'
       AND pg_get_constraintdef(oid) NOT LIKE '%recurso_solicitado%';
    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE alertas DROP CONSTRAINT %I', v_conname);
        ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo IN (
            'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
            'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
            'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
            'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
            'no_conformidad','recurso_solicitado'));
    END IF;
END $$;


-- ── 3. RPC: el operador solicita un recurso ──────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_solicitar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_solicitado_nombre VARCHAR DEFAULT NULL, p_client_uuid UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_ot RECORD; v_id UUID; v_unidad VARCHAR; v_nombre_prod TEXT; v_u RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para solicitar recursos (rol: %)', v_rol; END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el producto del catálogo o una descripción'; END IF;

    -- Idempotencia del sync offline: mismo client_uuid ⇒ misma solicitud.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM ot_recursos_solicitados WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', true, 'recurso_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    SELECT id, folio, estado, preparacion_ok_at, activo_id INTO v_ot
      FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_ot.id IS NULL THEN RAISE EXCEPTION 'OT no existe'; END IF;
    IF v_ot.preparacion_ok_at IS NULL OR v_ot.estado NOT IN ('asignada','en_ejecucion','pausada') THEN
        RAISE EXCEPTION 'La OT % no está liberada a ejecución', v_ot.folio; END IF;

    IF p_producto_id IS NOT NULL THEN
        SELECT unidad_medida, nombre INTO v_unidad, v_nombre_prod FROM productos WHERE id = p_producto_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        client_uuid, ot_id, producto_id, descripcion, unidad, cantidad,
        comentario, solicitado_por, solicitado_nombre)
    VALUES (
        p_client_uuid, p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad), p_cantidad,
        p_comentario, v_user, NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''))
    RETURNING id INTO v_id;

    -- Campanita a la jefatura (nunca bloquear la solicitud por la alerta).
    BEGIN
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','jefe_mantenimiento','supervisor')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('recurso_solicitado',
                    'Recursos solicitados: ' || v_ot.folio,
                    COALESCE(NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''), 'Operador de taller')
                      || ' pide ' || p_cantidad || ' ' || COALESCE(v_unidad, p_unidad, 'un')
                      || ' de ' || COALESCE(v_nombre_prod, p_descripcion, 'material')
                      || ' para reparar',
                    'info', 'recurso_ot', p_ot_id, v_u.id, false, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID) TO authenticated;


-- ── 4. RPC: el jefe valida (aprueba / rechaza / ajusta cantidad) ─────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_validar(
    p_recurso_id UUID, p_accion TEXT,
    p_cantidad_aprobada NUMERIC DEFAULT NULL, p_nota TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_r RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Solo la jefatura valida recursos (rol: %)', v_rol; END IF;
    IF p_accion NOT IN ('aprobar','rechazar') THEN
        RAISE EXCEPTION 'Acción inválida: % (aprobar|rechazar)', p_accion; END IF;

    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id FOR UPDATE;
    IF v_r.id IS NULL THEN RAISE EXCEPTION 'Recurso no existe'; END IF;
    IF v_r.estado = 'en_vale' THEN
        RAISE EXCEPTION 'El recurso ya está en un vale de bodega'; END IF;

    UPDATE ot_recursos_solicitados
       SET estado            = CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END,
           cantidad_aprobada = CASE WHEN p_accion = 'aprobar'
                                    THEN COALESCE(p_cantidad_aprobada, cantidad_aprobada, cantidad)
                                    ELSE NULL END,
           validado_por = v_user, validado_at = NOW(),
           nota_jefe = COALESCE(p_nota, nota_jefe),
           updated_at = NOW()
     WHERE id = p_recurso_id;

    RETURN jsonb_build_object('success', true, 'recurso_id', p_recurso_id,
        'estado', CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_validar(UUID,TEXT,NUMERIC,TEXT) TO authenticated;


-- ── 5. RPC: el jefe agrega un recurso directo (nace aprobado) ────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_agregar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_id UUID; v_unidad VARCHAR;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Solo la jefatura agrega recursos (rol: %)', v_rol; END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el producto del catálogo o una descripción'; END IF;
    IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN
        RAISE EXCEPTION 'OT no existe'; END IF;
    IF p_producto_id IS NOT NULL THEN
        SELECT unidad_medida INTO v_unidad FROM productos WHERE id = p_producto_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        ot_id, producto_id, descripcion, unidad, cantidad, cantidad_aprobada,
        comentario, estado, solicitado_por, agregado_por_jefe, validado_por, validado_at)
    VALUES (
        p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad),
        p_cantidad, p_cantidad, p_comentario, 'aprobado', v_user, true, v_user, NOW())
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_agregar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT) TO authenticated;


-- ── 6. El vale (ticket) incluye los recursos aprobados de la OT ──────────────
ALTER TABLE bodega_ticket_items
    ADD COLUMN IF NOT EXISTS recurso_id UUID REFERENCES ot_recursos_solicitados(id);

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

    -- [MIG197] Fuentes del vale: materiales de NC y/o recursos aprobados de la OT
    IF NOT EXISTS (
        SELECT 1 FROM nc_materiales m JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
         WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false)
       AND NOT EXISTS (
        SELECT 1 FROM ot_recursos_solicitados r WHERE r.ot_id=p_ot_id AND r.estado='aprobado') THEN
        RAISE EXCEPTION 'No hay materiales de NC ni recursos aprobados para esta OT'; END IF;

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

    -- [MIG197] Recursos aprobados del operador (cantidad que validó el jefe)
    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, recurso_id, comentario)
    SELECT v_id, r.producto_id, COALESCE(r.descripcion, pr.nombre),
           COALESCE(r.unidad, pr.unidad_medida),
           COALESCE(r.cantidad_aprobada, r.cantidad), r.id, r.comentario
      FROM ot_recursos_solicitados r
      LEFT JOIN productos pr ON pr.id=r.producto_id
     WHERE r.ot_id=p_ot_id AND r.estado='aprobado';

    UPDATE ot_recursos_solicitados
       SET estado='en_vale', ticket_id=v_id, updated_at=NOW()
     WHERE ot_id=p_ot_id AND estado='aprobado';

    SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id=v_id;
    RETURN jsonb_build_object('success',true,'ticket_id',v_id,'folio',v_folio,'qr',v_qr,'items',v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_crear_ticket_bodega(UUID,TEXT,TEXT,UUID) TO authenticated;

-- Anular ticket devuelve los recursos a 'aprobado' (pueden ir en otro vale)
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
    -- [MIG197] liberar los recursos que iban en este vale
    UPDATE ot_recursos_solicitados
       SET estado='aprobado', ticket_id=NULL, updated_at=NOW()
     WHERE ticket_id=p_ticket_id AND estado='en_vale';
    RETURN jsonb_build_object('success',true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_anular_ticket_bodega(UUID,TEXT) TO authenticated;


-- ── 7. Vista ─────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_ot_recursos;
CREATE VIEW v_ot_recursos AS
SELECT r.id, r.client_uuid, r.ot_id, r.producto_id,
       COALESCE(r.descripcion, pr.nombre)      AS descripcion,
       COALESCE(r.unidad, pr.unidad_medida)    AS unidad,
       r.cantidad, r.cantidad_aprobada, r.comentario, r.estado,
       r.solicitado_por, r.solicitado_nombre, r.agregado_por_jefe,
       r.validado_por, r.validado_at, r.nota_jefe, r.ticket_id, r.created_at,
       pr.codigo AS producto_codigo, pr.nombre AS producto_nombre,
       CASE WHEN r.producto_id IS NULL THEN NULL
            ELSE (SELECT COALESCE(SUM(sb.cantidad),0) FROM stock_bodega sb
                   WHERE sb.producto_id = r.producto_id) END AS stock_total,
       uv.nombre_completo AS validado_por_nombre,
       tk.folio AS ticket_folio, tk.estado AS ticket_estado
FROM ot_recursos_solicitados r
LEFT JOIN productos pr        ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil uv  ON uv.id = r.validado_por
LEFT JOIN bodega_tickets tk   ON tk.id = r.ticket_id;
GRANT SELECT ON v_ot_recursos TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tabla', (SELECT EXISTS (SELECT 1 FROM information_schema.tables
        WHERE table_name='ot_recursos_solicitados')),
    'rpcs', (SELECT array_agg(DISTINCT proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_ot_recurso_solicitar','rpc_ot_recurso_validar','rpc_ot_recurso_agregar')),
    'ticket_con_recursos', (SELECT prosrc LIKE '%ot_recursos_solicitados%' FROM pg_proc
        WHERE proname='rpc_crear_ticket_bodega'),
    'anular_libera', (SELECT prosrc LIKE '%ot_recursos_solicitados%' FROM pg_proc
        WHERE proname='rpc_anular_ticket_bodega'),
    'col_recurso_en_items', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='bodega_ticket_items' AND column_name='recurso_id')),
    'alerta_tipo_ok', (SELECT pg_get_constraintdef(oid) LIKE '%recurso_solicitado%'
        FROM pg_constraint WHERE conrelid='alertas'::regclass AND conname='chk_alertas_tipo'),
    'vista', (SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_ot_recursos'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
