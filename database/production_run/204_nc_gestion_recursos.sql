-- ============================================================================
-- SICOM-ICEO | 204 — Gestión completa de recursos desde la bandeja de NC
-- ============================================================================
-- Pedido Manuel (2026-07-07): en /dashboard/mantenimiento/no-conformidades se
-- debe poder hacer TODA la gestión de los insumos (aprobar/rechazar/agregar y
-- emitir el vale) — si vive solo en el Plan Taller el personal se enreda.
--
-- Único cambio de BD: rpc_ot_recurso_agregar acepta p_instance_item_id para
-- que el ítem que el jefe agrega DESDE LA NC quede amarrado al hallazgo (y
-- aparezca en esa NC). Se elimina la firma anterior para no dejar overloads.
-- IDEMPOTENTE.
-- ============================================================================

DROP FUNCTION IF EXISTS rpc_ot_recurso_agregar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT);

CREATE OR REPLACE FUNCTION rpc_ot_recurso_agregar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_instance_item_id UUID DEFAULT NULL
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
        comentario, estado, solicitado_por, agregado_por_jefe, validado_por, validado_at,
        instance_item_id)
    VALUES (
        p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad),
        p_cantidad, p_cantidad, p_comentario, 'aprobado', v_user, true, v_user, NOW(),
        p_instance_item_id)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_agregar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,UUID) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'una_sola_firma', (SELECT COUNT(*) = 1 FROM pg_proc WHERE proname='rpc_ot_recurso_agregar'),
    'con_item', (SELECT prosrc LIKE '%p_instance_item_id%' FROM pg_proc WHERE proname='rpc_ot_recurso_agregar')
) AS resultado;

NOTIFY pgrst, 'reload schema';
