-- ============================================================================
-- SICOM-ICEO | 216 — Error de stock FIFO con nombres, no UUIDs
-- ============================================================================
-- Reportado por Manuel (2026-07-09) al despachar un vale en /dashboard/bodega/
-- tickets: «Stock insuficiente para producto 783954e5-… en bodega c22c6913-….
-- Disponible: 0, solicitado: 1» — el bodeguero no tiene cómo saber qué
-- producto ni qué bodega son esos UUIDs.
--
-- fn_consumir_inventario_fifo (MIG56) es el único punto que lanza este error
-- (lo consumen salidas de bodega, vales de taller, traspasos, etc.), así que
-- se arregla en la fuente: el RAISE ahora dice el nombre del producto y de la
-- bodega, y orienta qué hacer (entrega parcial / compra-reposición).
-- Cuerpo idéntico al vigente en prod salvo el bloque del RAISE. IDEMPOTENTE.
-- (La UI del vale además valida contra el stock antes de enviar — mismo PR.)
-- ============================================================================

-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_consumir_inventario_fifo') THEN
        RAISE EXCEPTION 'STOP — falta fn_consumir_inventario_fifo (MIG56).';
    END IF;
END $$;


-- ── 1. fn_consumir_inventario_fifo: mismo cuerpo, error con nombres ──────────
CREATE OR REPLACE FUNCTION fn_consumir_inventario_fifo(
    p_producto_id UUID, p_bodega_id UUID, p_cantidad NUMERIC,
    p_salida_bodega_id UUID DEFAULT NULL, p_salida_bodega_item_id UUID DEFAULT NULL,
    p_movimiento_id UUID DEFAULT NULL, p_ot_id UUID DEFAULT NULL,
    p_ceco_id UUID DEFAULT NULL, p_consumido_por UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_pendiente NUMERIC := p_cantidad;
    v_total_disponible NUMERIC;
    v_capa RECORD;
    v_consumir NUMERIC;
    v_costo_total NUMERIC := 0;
    v_capas_detalle JSONB := '[]'::JSONB;
    v_user UUID := COALESCE(p_consumido_por, auth.uid());
    v_producto_nombre TEXT;
    v_bodega_nombre TEXT;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad a consumir debe ser > 0' USING ERRCODE='22023';
    END IF;
    SELECT COALESCE(SUM(cantidad_disponible), 0) INTO v_total_disponible
      FROM inventario_capas
     WHERE producto_id=p_producto_id AND bodega_id=p_bodega_id AND estado='disponible';
    IF v_total_disponible < p_cantidad THEN
        -- [MIG216] Nombres en vez de UUIDs: el bodeguero debe entender el error.
        SELECT nombre INTO v_producto_nombre FROM productos WHERE id = p_producto_id;
        SELECT nombre INTO v_bodega_nombre   FROM bodegas   WHERE id = p_bodega_id;
        RAISE EXCEPTION 'Stock insuficiente de "%" en bodega "%": disponible %, solicitado %. Entrega solo lo disponible (el saldo queda pendiente) o gestiona compra/reposición.',
            COALESCE(v_producto_nombre, p_producto_id::text),
            COALESCE(v_bodega_nombre, p_bodega_id::text),
            v_total_disponible, p_cantidad USING ERRCODE='P0001';
    END IF;
    FOR v_capa IN
        SELECT id, cantidad_disponible, costo_unitario, fecha_recepcion, folio_recepcion
          FROM inventario_capas
         WHERE producto_id=p_producto_id AND bodega_id=p_bodega_id AND estado='disponible' AND cantidad_disponible > 0
         ORDER BY fecha_recepcion ASC, created_at ASC, id ASC FOR UPDATE
    LOOP
        EXIT WHEN v_pendiente <= 0;
        v_consumir := LEAST(v_pendiente, v_capa.cantidad_disponible);
        INSERT INTO inventario_consumos_capas (
            salida_bodega_id, salida_bodega_item_id, movimiento_inventario_id,
            ot_id, ceco_id, producto_id, bodega_id, capa_id,
            cantidad_consumida, costo_unitario_capa, consumido_por
        ) VALUES (
            p_salida_bodega_id, p_salida_bodega_item_id, p_movimiento_id,
            p_ot_id, p_ceco_id, p_producto_id, p_bodega_id, v_capa.id,
            v_consumir, v_capa.costo_unitario, v_user
        );
        UPDATE inventario_capas
           SET cantidad_disponible = cantidad_disponible - v_consumir,
               estado = CASE WHEN cantidad_disponible - v_consumir <= 0 THEN 'agotada' ELSE 'disponible' END,
               updated_at = NOW()
         WHERE id = v_capa.id;
        v_costo_total := v_costo_total + (v_consumir * v_capa.costo_unitario);
        v_pendiente := v_pendiente - v_consumir;
        v_capas_detalle := v_capas_detalle || jsonb_build_object(
            'capa_id', v_capa.id, 'fecha_recepcion', v_capa.fecha_recepcion,
            'folio_recepcion', v_capa.folio_recepcion, 'cantidad', v_consumir,
            'costo_unitario', v_capa.costo_unitario,
            'costo_total', v_consumir * v_capa.costo_unitario
        );
    END LOOP;
    IF v_pendiente > 0 THEN
        RAISE EXCEPTION 'Inconsistencia FIFO: quedan % unidades sin consumir.', v_pendiente USING ERRCODE='P0001';
    END IF;
    RETURN jsonb_build_object(
        'cantidad_consumida', p_cantidad,
        'costo_total', v_costo_total,
        'costo_unitario_promedio', ROUND(v_costo_total / p_cantidad, 4),
        'capas_consumidas', v_capas_detalle,
        'metodo', 'fifo'
    );
END; $$;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'mensaje_con_nombres', (SELECT prosrc LIKE '%Stock insuficiente de%'
        FROM pg_proc WHERE proname = 'fn_consumir_inventario_fifo'),
    'conserva_fifo', (SELECT prosrc LIKE '%inventario_consumos_capas%'
        FROM pg_proc WHERE proname = 'fn_consumir_inventario_fifo')
) AS resultado;

NOTIFY pgrst, 'reload schema';
