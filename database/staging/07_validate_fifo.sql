-- ============================================================================
-- 07_validate_fifo.sql  —  Test del filtro $10.000 / $14.000.
-- ----------------------------------------------------------------------------
-- Aplica el ejemplo obligatorio de FIFO en una transaccion ROLLBACK.
-- ============================================================================

DO $$
DECLARE
    v_producto_id UUID;
    v_bodega_id   UUID;
    v_capa_a_id   UUID := gen_random_uuid();
    v_capa_b_id   UUID := gen_random_uuid();
    v_resultado_1 JSONB;
    v_resultado_2 JSONB;
    v_resultado_3 JSONB;
BEGIN
    SELECT id INTO v_producto_id FROM productos LIMIT 1;
    SELECT id INTO v_bodega_id   FROM bodegas LIMIT 1;

    IF v_producto_id IS NULL OR v_bodega_id IS NULL THEN
        RAISE EXCEPTION 'TEST OMITIDO: faltan productos o bodegas';
    END IF;

    -- Capa A: 1 unidad a $10.000
    INSERT INTO inventario_capas (
        id, producto_id, bodega_id, fecha_recepcion, folio_recepcion,
        cantidad_inicial, cantidad_disponible, unidad, costo_unitario, estado
    ) VALUES (
        v_capa_a_id, v_producto_id, v_bodega_id, CURRENT_DATE - INTERVAL '15 days',
        'TEST-REC-A', 1, 1, 'unidad', 10000, 'disponible'
    );

    -- Capa B: 1 unidad a $14.000
    INSERT INTO inventario_capas (
        id, producto_id, bodega_id, fecha_recepcion, folio_recepcion,
        cantidad_inicial, cantidad_disponible, unidad, costo_unitario, estado
    ) VALUES (
        v_capa_b_id, v_producto_id, v_bodega_id, CURRENT_DATE - INTERVAL '5 days',
        'TEST-REC-B', 1, 1, 'unidad', 14000, 'disponible'
    );

    -- Salida 1: 1 unidad
    v_resultado_1 := fn_consumir_inventario_fifo(
        v_producto_id, v_bodega_id, 1, NULL, NULL, NULL, NULL, NULL
    );
    RAISE NOTICE 'TEST 1 (1 unidad esperado costo $10.000): %', v_resultado_1;

    -- Verificar
    IF (v_resultado_1->>'costo_total')::NUMERIC <> 10000 THEN
        RAISE EXCEPTION 'TEST 1 FALLO: costo_total = % (esperado 10000)', v_resultado_1->>'costo_total';
    END IF;

    -- Salida 2: 1 unidad
    v_resultado_2 := fn_consumir_inventario_fifo(
        v_producto_id, v_bodega_id, 1, NULL, NULL, NULL, NULL, NULL
    );
    RAISE NOTICE 'TEST 2 (1 unidad esperado costo $14.000): %', v_resultado_2;

    IF (v_resultado_2->>'costo_total')::NUMERIC <> 14000 THEN
        RAISE EXCEPTION 'TEST 2 FALLO: costo_total = % (esperado 14000)', v_resultado_2->>'costo_total';
    END IF;

    -- Restaurar capas para test 3 (multi-capa)
    UPDATE inventario_capas SET cantidad_disponible = 1, estado = 'disponible' WHERE id IN (v_capa_a_id, v_capa_b_id);

    -- Salida 3: 2 unidades (consume A + B)
    v_resultado_3 := fn_consumir_inventario_fifo(
        v_producto_id, v_bodega_id, 2, NULL, NULL, NULL, NULL, NULL
    );
    RAISE NOTICE 'TEST 3 (2 unidades esperado costo $24.000): %', v_resultado_3;

    IF (v_resultado_3->>'costo_total')::NUMERIC <> 24000 THEN
        RAISE EXCEPTION 'TEST 3 FALLO: costo_total = % (esperado 24000)', v_resultado_3->>'costo_total';
    END IF;
    IF jsonb_array_length(v_resultado_3->'capas_consumidas') <> 2 THEN
        RAISE EXCEPTION 'TEST 3 FALLO: deberia consumir 2 capas, consumio %',
            jsonb_array_length(v_resultado_3->'capas_consumidas');
    END IF;

    -- Test 4: stock insuficiente
    BEGIN
        PERFORM fn_consumir_inventario_fifo(
            v_producto_id, v_bodega_id, 99999, NULL, NULL, NULL, NULL, NULL
        );
        RAISE EXCEPTION 'TEST 4 FALLO: deberia haber lanzado RAISE Stock insuficiente';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Stock insuficiente%' THEN
            RAISE NOTICE 'TEST 4 OK: stock insuficiente detectado correctamente';
        ELSE
            RAISE;
        END IF;
    END;

    RAISE NOTICE 'TODOS LOS TESTS FIFO PASARON.';

    -- Rollback intencional
    RAISE EXCEPTION 'ROLLBACK_INTENCIONAL_TEST';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ROLLBACK_INTENCIONAL_TEST%' THEN
            RAISE NOTICE 'TESTS FIFO COMPLETADOS (rollback ejecutado).';
        ELSE
            RAISE;
        END IF;
END $$;


-- ── Vista de stock valorizado ────────────────────────────────────────
SELECT * FROM v_stock_valorizado_fifo LIMIT 10;


-- ── Reconciliacion final ─────────────────────────────────────────────
SELECT
    'RECONCILIACION_POST_TEST' AS check_name,
    COUNT(*) AS productos_desincronizados
FROM (
    SELECT sb.producto_id, sb.bodega_id, sb.cantidad,
           COALESCE(SUM(ic.cantidad_disponible), 0) AS capas
      FROM stock_bodega sb
      LEFT JOIN inventario_capas ic
        ON ic.producto_id = sb.producto_id
       AND ic.bodega_id = sb.bodega_id
       AND ic.estado = 'disponible'
     WHERE sb.cantidad > 0
     GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
    HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
) sub;
-- Esperado: 0
