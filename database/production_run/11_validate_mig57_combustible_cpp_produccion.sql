-- ============================================================================
-- 11_validate_mig57_combustible_cpp_produccion.sql  —  Solo lectura + ROLLBACK.
-- ============================================================================

-- 1. Tablas
SELECT 'TABLAS_57' AS check_name, COUNT(*) AS encontradas
FROM information_schema.tables WHERE table_schema='public'
AND table_name IN ('combustible_stock_inicial','combustible_kardex_valorizado');
-- Esperado: 2

-- 2. Columnas en estanques
SELECT 'COLUMNAS_ESTANQUES_CPP' AS check_name, COUNT(*) AS encontradas
FROM information_schema.columns WHERE table_name='combustible_estanques'
AND column_name IN ('costo_promedio_lt','valor_total_stock');
-- Esperado: 2

-- 3. RPC y vista
SELECT 'RPC_STOCK_INICIAL' AS check_name, COUNT(*) AS encontradas
FROM pg_proc WHERE proname='rpc_registrar_stock_inicial_combustible';
SELECT 'VISTA_CPP' AS check_name, COUNT(*) AS encontradas
FROM pg_views WHERE viewname='v_combustible_stock_valorizado_actual';

-- 4. Estanques con stock pero SIN stock_inicial
SELECT
    'ESTANQUES_PENDIENTE_INICIAL' AS check_name,
    COUNT(*) AS cantidad
FROM combustible_estanques e
WHERE e.activo = true
  AND e.stock_teorico_lt > 0
  AND NOT EXISTS (
    SELECT 1 FROM combustible_stock_inicial si
     WHERE si.estanque_id = e.id AND si.anulado = false
  );
-- ⚠️ Si > 0, esos estanques requieren stock inicial (paso 12).

-- 5. Reconciliación estanque vs último kardex
SELECT
    e.codigo,
    e.stock_teorico_lt AS estanque_stock,
    (SELECT stock_lt_despues FROM combustible_kardex_valorizado
      WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_stock,
    e.valor_total_stock AS estanque_valor,
    (SELECT valor_stock_despues FROM combustible_kardex_valorizado
      WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_valor
FROM combustible_estanques e
WHERE e.activo = true
ORDER BY e.codigo;

-- 6. Vista stock valorizado actual
SELECT * FROM v_combustible_stock_valorizado_actual;

-- 7. Resultado
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') = 1
         AND (SELECT COUNT(*) FROM pg_proc WHERE proname='rpc_registrar_stock_inicial_combustible') = 1
        THEN
            CASE
                WHEN (SELECT COUNT(*) FROM combustible_estanques e WHERE e.activo=true AND e.stock_teorico_lt > 0
                       AND NOT EXISTS (SELECT 1 FROM combustible_stock_inicial si
                                        WHERE si.estanque_id=e.id AND si.anulado=false)) > 0
                THEN 'OK MIG57 — PENDIENTE STOCK INICIAL (paso 12)'
                ELSE 'OK MIG57'
            END
        ELSE 'STOP MIG57'
    END AS resultado;

-- Log
SELECT fn_log_operacion_migracion('PROD_MIG57_VALIDATE', 'Validacion CPP movil ejecutada.', 'ok', NULL);
