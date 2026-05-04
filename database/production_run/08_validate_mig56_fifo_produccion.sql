-- ============================================================================
-- 08_validate_mig56_fifo_produccion.sql  —  Solo lectura + ROLLBACK.
-- ============================================================================

-- 1. Tablas FIFO
SELECT 'TABLAS_FIFO' AS check_name, COUNT(*) AS encontradas
FROM information_schema.tables
WHERE table_schema='public' AND table_name IN ('inventario_capas','inventario_consumos_capas');

-- 2. Función FIFO
SELECT 'FN_FIFO' AS check_name, COUNT(*) FROM pg_proc WHERE proname='fn_consumir_inventario_fifo';

-- 3. Vista
SELECT 'VISTA_FIFO' AS check_name, COUNT(*) FROM pg_views WHERE viewname='v_stock_valorizado_fifo';

-- 4. Reconciliación stock_bodega vs capas
SELECT
    'RECONCILIACION_FIFO' AS check_name,
    COUNT(*) AS productos_desincronizados
FROM (
    SELECT sb.producto_id, sb.bodega_id, sb.cantidad,
           COALESCE(SUM(ic.cantidad_disponible), 0) AS capas
    FROM stock_bodega sb
    LEFT JOIN inventario_capas ic
      ON ic.producto_id = sb.producto_id AND ic.bodega_id = sb.bodega_id AND ic.estado='disponible'
    WHERE sb.cantidad > 0
    GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
    HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
) sub;
-- Esperado:
--   Si AÚN no se sembraron capas → productos_desincronizados = TODOS los productos con stock.
--   Después de paso 09, debe ser 0.

-- 5. Productos con stock SIN capa todavía
SELECT
    'PRODUCTOS_SIN_CAPA' AS check_name,
    COUNT(*) AS cantidad
FROM stock_bodega sb
WHERE sb.cantidad > 0
  AND NOT EXISTS (
    SELECT 1 FROM inventario_capas ic
     WHERE ic.producto_id = sb.producto_id
       AND ic.bodega_id = sb.bodega_id
       AND ic.estado = 'disponible'
  );

-- 6. Productos sin costo_promedio (bloqueante para sembrar capas)
SELECT
    'PRODUCTOS_SIN_COSTO' AS check_name,
    COUNT(*) AS cantidad
FROM stock_bodega
WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0);

-- 7. Test FIFO con ROLLBACK (solo si hay capa)
DO $$
DECLARE v_test JSONB; v_capa_id UUID; v_prod UUID; v_bod UUID;
BEGIN
    SELECT id, producto_id, bodega_id INTO v_capa_id, v_prod, v_bod
      FROM inventario_capas
     WHERE estado='disponible' AND cantidad_disponible >= 1
     LIMIT 1;
    IF v_capa_id IS NULL THEN
        RAISE NOTICE 'TEST OMITIDO — no hay capas todavía (esperado en paso pre-09).';
        RETURN;
    END IF;
    v_test := fn_consumir_inventario_fifo(v_prod, v_bod, 1, NULL, NULL, NULL, NULL, NULL);
    RAISE NOTICE 'TEST FIFO OK: %', v_test;
    RAISE EXCEPTION 'ROLLBACK_TEST';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ROLLBACK_TEST%' THEN
        RAISE NOTICE 'TEST FIFO COMPLETADO (rollback ejecutado).';
    ELSE RAISE; END IF;
END $$;

-- 8. Resultado
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema='public' AND table_name='inventario_capas') = 1
         AND (SELECT COUNT(*) FROM pg_proc WHERE proname='fn_consumir_inventario_fifo') = 1
        THEN
            CASE
                WHEN (SELECT COUNT(*) FROM inventario_capas) = 0
                THEN 'OK MIG56 — PENDIENTE SEMBRAR CAPAS (paso 09)'
                ELSE 'OK MIG56'
            END
        ELSE 'STOP MIG56'
    END AS resultado;

-- Log
SELECT fn_log_operacion_migracion('PROD_MIG56_VALIDATE', 'Validacion FIFO ejecutada.', 'ok', NULL);
