-- ============================================================================
-- SICOM-ICEO | 162 — CECO por patente (cada vehículo tiene su propio CECO)
-- ============================================================================
-- Cada patente tiene su CECO (Excel "ceco x patente.xlsx"). El pedido de bodega
-- es por OT, que está asociada a una patente -> la salida debe cargarse al CECO
-- de esa patente. Aquí: columna activos.ceco_id + la entrega del ticket resuelve
-- el CECO desde el activo de la OT (fallback faena, luego CECO-BODEGA).
--
-- La carga de datos (crear los CECO en centros_costo + setear activos.ceco_id
-- por patente) la hace database/scripts/cargar-ceco-patente.mjs desde el Excel.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS ceco_id UUID REFERENCES centros_costo(id);
COMMENT ON COLUMN activos.ceco_id IS 'CECO propio de la patente (Excel ceco x patente). MIG162.';

CREATE INDEX IF NOT EXISTS idx_activos_ceco ON activos(ceco_id) WHERE ceco_id IS NOT NULL;


-- Entrega del ticket: CECO desde la patente de la OT.
CREATE OR REPLACE FUNCTION rpc_entregar_ticket_bodega(
    p_ticket_id UUID, p_bodega_id UUID, p_entregas JSONB,
    p_entregado_a VARCHAR DEFAULT NULL, p_firma_bodeguero_url TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_tk RECORD; v_ti RECORD; e RECORD; v_activo UUID; v_faena UUID; v_ceco UUID;
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

    -- CECO: 1) el de la patente (activos.ceco_id) de la OT; 2) por faena; 3) CECO-BODEGA.
    SELECT activo_id, faena_id INTO v_activo, v_faena FROM ordenes_trabajo WHERE id=v_tk.ot_id;
    SELECT ceco_id INTO v_ceco FROM activos WHERE id = v_activo;
    IF v_ceco IS NULL THEN
        SELECT id INTO v_ceco FROM centros_costo
         WHERE faena_id = v_faena AND COALESCE(activo,true)=true ORDER BY created_at LIMIT 1;
    END IF;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE codigo='CECO-BODEGA' LIMIT 1; END IF;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE COALESCE(activo,true)=true ORDER BY created_at LIMIT 1; END IF;

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

    IF jsonb_array_length(v_items) = 0 THEN RAISE EXCEPTION 'No hay cantidades a entregar'; END IF;

    v_salida := rpc_registrar_salida_bodega(
        'ot', p_bodega_id, v_ceco, v_tk.ot_id,
        'Despacho ticket '||v_tk.folio, v_items,
        p_entregado_a, NULL, v_tk.emitido_por, p_firma_bodeguero_url,
        'Ticket bodega '||v_tk.folio);
    v_folio := v_salida->>'folio';

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
        'estado', CASE WHEN v_falta=0 THEN 'entregado' ELSE 'parcial' END,
        'ceco_id', v_ceco);
END $$;
GRANT EXECUTE ON FUNCTION rpc_entregar_ticket_bodega(UUID,UUID,JSONB,VARCHAR,TEXT) TO authenticated;

SELECT jsonb_build_object(
    'col_ceco', (SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='activos' AND column_name='ceco_id'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
