-- ============================================================================
-- SICOM-ICEO | 210 — Foto en los ítems que agrega el jefe desde la NC
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-09): desde el modal de NC por equipo el jefe debe
-- poder pedir un repuesto NUEVO (no levantado por el operador) CON FOTO, y esa
-- foto debe llegarle a bodega igual que las del operador.
--
-- Único cambio de BD: rpc_ot_recurso_agregar acepta p_fotos TEXT[] y las
-- guarda en ot_recursos_solicitados.fotos (columna que ya usa el operador —
-- MIG197 — y que ya se ve en v_ot_recursos, seguimiento y la bandeja de NC).
-- Se elimina la firma anterior (MIG204) para no dejar overloads.
--
-- Las solicitudes a bodega (fn_solicitar_material_bodega, MIG144) ya aceptan
-- p_foto_url y bodega ya la muestra: la UI ahora la envía por material.
-- IDEMPOTENTE.
-- ============================================================================

DROP FUNCTION IF EXISTS rpc_ot_recurso_agregar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,UUID);

CREATE OR REPLACE FUNCTION rpc_ot_recurso_agregar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_instance_item_id UUID DEFAULT NULL,
    p_fotos TEXT[] DEFAULT NULL
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
        instance_item_id, fotos)
    VALUES (
        p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad),
        p_cantidad, p_cantidad, p_comentario, 'aprobado', v_user, true, v_user, NOW(),
        p_instance_item_id, NULLIF(p_fotos, ARRAY[]::TEXT[]))
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_agregar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,UUID,TEXT[]) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'una_sola_firma', (SELECT COUNT(*) = 1 FROM pg_proc WHERE proname='rpc_ot_recurso_agregar'),
    'con_fotos', (SELECT prosrc LIKE '%p_fotos%' FROM pg_proc WHERE proname='rpc_ot_recurso_agregar')
) AS resultado;

NOTIFY pgrst, 'reload schema';
