-- ============================================================================
-- SICOM-ICEO | 205 — Al emitir el vale le llega la solicitud a bodega
-- ============================================================================
-- Pedido Manuel (2026-07-07): al generar el vale de bodega, bodega debe
-- recibir la solicitud (campanita) para preparar la entrega; el operador
-- llega con el vale impreso (QR) a retirar.
--
--   * Tipo de alerta nuevo 'vale_emitido' (a bodeguero / operador_
--     abastecimiento / administrador, entidad ticket_bodega → /bodega/tickets).
--   * rpc_crear_ticket_bodega (cuerpo MIG201) + la alerta al final.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tipo de alerta ────────────────────────────────────────────────────────
DO $$
DECLARE v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
      FROM pg_constraint
     WHERE conrelid = 'alertas'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%recurso_por_comprar%'
       AND pg_get_constraintdef(oid) NOT LIKE '%vale_emitido%';
    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE alertas DROP CONSTRAINT %I', v_conname);
        ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo IN (
            'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
            'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
            'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
            'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
            'no_conformidad','recurso_solicitado','recurso_por_comprar','recurso_recibido',
            'vale_emitido'));
    END IF;
END $$;


-- ── 2. rpc_crear_ticket_bodega: avisar a bodega al emitir ────────────────────
CREATE OR REPLACE FUNCTION rpc_crear_ticket_bodega(
    p_ot_id UUID, p_firma_jefe_url TEXT, p_observacion TEXT DEFAULT NULL, p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_activo UUID; v_folio TEXT; v_periodo TEXT; v_sec INT; v_id UUID; v_qr TEXT; v_n INT;
    v_pat TEXT; v_u RECORD;
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
         WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false)
       AND NOT EXISTS (
        SELECT 1 FROM ot_recursos_solicitados r WHERE r.ot_id=p_ot_id AND r.estado IN ('aprobado','recibido')) THEN
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

    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, recurso_id, comentario)
    SELECT v_id, r.producto_id, COALESCE(r.descripcion, pr.nombre),
           COALESCE(r.unidad, pr.unidad_medida),
           COALESCE(r.cantidad_aprobada, r.cantidad), r.id, r.comentario
      FROM ot_recursos_solicitados r
      LEFT JOIN productos pr ON pr.id=r.producto_id
     WHERE r.ot_id=p_ot_id AND r.estado IN ('aprobado','recibido');

    UPDATE ot_recursos_solicitados
       SET estado='en_vale', ticket_id=v_id, updated_at=NOW()
     WHERE ot_id=p_ot_id AND estado IN ('aprobado','recibido');

    SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id=v_id;

    -- [MIG205] La solicitud le llega a bodega (campanita) para preparar la entrega
    BEGIN
        SELECT COALESCE(a.patente, a.codigo) INTO v_pat FROM activos a WHERE a.id = v_activo;
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('vale_emitido',
                    'Vale de bodega: ' || v_folio,
                    'Preparar entrega para ' || COALESCE(v_pat,'equipo') || ' — ' || v_n ||
                    ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END ||
                    '. El operador retira con el vale (QR ' || v_qr || ').',
                    'info', 'ticket_bodega', v_id, v_u.id, false, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success',true,'ticket_id',v_id,'folio',v_folio,'qr',v_qr,'items',v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_crear_ticket_bodega(UUID,TEXT,TEXT,UUID) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'alerta_tipo', (SELECT pg_get_constraintdef(oid) LIKE '%vale_emitido%' FROM pg_constraint
        WHERE conrelid='alertas'::regclass AND conname='chk_alertas_tipo'),
    'rpc_avisa_bodega', (SELECT prosrc LIKE '%vale_emitido%' FROM pg_proc
        WHERE proname='rpc_crear_ticket_bodega')
) AS resultado;

NOTIFY pgrst, 'reload schema';
