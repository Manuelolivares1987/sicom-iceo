-- ============================================================================
-- SICOM-ICEO | 213 — El vale de bodega se arma POR EQUIPO (patente)
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-09): al emitir el vale la patente salía repetida
-- (una entrada por la OT de origen y otra por la correctiva) y no se podía
-- volver a emitir teniendo un vale abierto.
--
-- rpc_crear_ticket_bodega ahora:
--   1. Junta los ítems de TODAS las OT del equipo (la de hallazgos y la
--      correctiva donde el operador pide durante la ejecución): recursos
--      aprobados/recibidos + materiales de NC del equipo aún no ticketeados.
--   2. Permite emitir un vale NUEVO aunque haya otro abierto: cada vale sale
--      solo con lo que no estaba en un vale anterior (lo "nuevo"). Para
--      re-emitir TODO, se anula el vale abierto (rpc_anular devuelve los
--      recursos a 'aprobado') y se emite de nuevo.
--   3. Los materiales de NC ya incluidos en un vale no anulado NO se repiten.
-- Misma firma (p_ot_id sigue siendo "una OT del equipo" — se resuelve el
-- activo desde ahí). IDEMPOTENTE.
-- ============================================================================

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

    -- Ítems del EQUIPO que todavía no van en ningún vale:
    IF NOT EXISTS (
        SELECT 1 FROM nc_materiales m
          JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
         WHERE nc.activo_id=v_activo AND COALESCE(nc.resuelto,false)=false
           AND NOT EXISTS (
               SELECT 1 FROM bodega_ticket_items bti
                 JOIN bodega_tickets bt ON bt.id=bti.ticket_id AND bt.estado <> 'anulado'
                WHERE bti.nc_material_id = m.id))
       AND NOT EXISTS (
        SELECT 1 FROM ot_recursos_solicitados r
          JOIN ordenes_trabajo o ON o.id=r.ot_id
         WHERE o.activo_id=v_activo AND r.estado IN ('aprobado','recibido')) THEN
        RAISE EXCEPTION 'No hay ítems nuevos para el vale de este equipo (lo aprobado ya está en un vale — imprímelo o anúlalo para re-emitir).'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(),'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)),0)+1 INTO v_sec
      FROM bodega_tickets WHERE folio LIKE 'TKT-'||v_periodo||'-%';
    v_folio := 'TKT-'||v_periodo||'-'||LPAD(v_sec::text,5,'0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-'||v_folio;

    INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, bodega_id, estado, emitido_por, firma_jefe_url, observacion)
    VALUES (v_id, v_folio, v_qr, p_ot_id, v_activo, p_bodega_id, 'emitido', v_user, p_firma_jefe_url, p_observacion);

    -- Materiales de NC del equipo (solo los que no van en un vale vigente)
    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, nc_id, nc_material_id, comentario)
    SELECT v_id, m.producto_id, COALESCE(m.descripcion, pr.nombre), pr.unidad_medida,
           m.cantidad, nc.id, m.id, m.comentario
      FROM nc_materiales m
      JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
      LEFT JOIN productos pr ON pr.id=m.producto_id
     WHERE nc.activo_id=v_activo AND COALESCE(nc.resuelto,false)=false
       AND NOT EXISTS (
           SELECT 1 FROM bodega_ticket_items bti
             JOIN bodega_tickets bt ON bt.id=bti.ticket_id AND bt.estado <> 'anulado'
            WHERE bti.nc_material_id = m.id);

    -- Recursos aprobados/recibidos de TODAS las OT del equipo
    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, recurso_id, comentario)
    SELECT v_id, r.producto_id, COALESCE(r.descripcion, pr.nombre),
           COALESCE(r.unidad, pr.unidad_medida),
           COALESCE(r.cantidad_aprobada, r.cantidad), r.id, r.comentario
      FROM ot_recursos_solicitados r
      JOIN ordenes_trabajo o ON o.id=r.ot_id
      LEFT JOIN productos pr ON pr.id=r.producto_id
     WHERE o.activo_id=v_activo AND r.estado IN ('aprobado','recibido');

    UPDATE ot_recursos_solicitados r
       SET estado='en_vale', ticket_id=v_id, updated_at=NOW()
      FROM ordenes_trabajo o
     WHERE o.id=r.ot_id AND o.activo_id=v_activo AND r.estado IN ('aprobado','recibido');

    SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id=v_id;

    -- La solicitud le llega a bodega (campanita) para preparar la entrega (MIG205)
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
    'rpc_por_equipo', (SELECT prosrc LIKE '%o.activo_id=v_activo%' FROM pg_proc WHERE proname='rpc_crear_ticket_bodega'),
    'sin_bloqueo_ot', (SELECT prosrc NOT LIKE '%Ya existe un ticket abierto%' FROM pg_proc WHERE proname='rpc_crear_ticket_bodega')
) AS resultado;

NOTIFY pgrst, 'reload schema';
