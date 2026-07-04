-- ============================================================================
-- SICOM-ICEO | Diagnóstico: reconciliación de combustible (SOLO LECTURA)
-- ----------------------------------------------------------------------------
-- Dry-run del hallazgo C5 de la auditoría (valor_total_stock inflado) y de la
-- regularización MIG188. No modifica nada. Ejecutar con:
--   node database/scripts/psql-cli.mjs -f database/diagnostics/combustible_reconciliacion.sql
-- ============================================================================

-- 1. Litros y valor teóricos desde el kardex vs lo almacenado, por estanque.
--    diff_* debe ser 0; si diff_valor_columna ≠ 0 es el bug MIG77/78 (C5).
SELECT
    e.codigo,
    e.es_demo,
    e.stock_teorico_lt                                            AS litros_columna,
    COALESCE(k.litros_kardex, 0)                                  AS litros_kardex,
    ROUND((e.stock_teorico_lt - COALESCE(k.litros_kardex,0))::numeric, 2)  AS diff_litros,
    e.valor_total_stock                                           AS valor_columna,
    COALESCE(k.ultimo_valor_kardex, 0)                            AS valor_ultimo_kardex,
    ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2) AS valor_teorico_stock_x_cpp,
    ROUND((e.valor_total_stock
           - e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2) AS diff_valor_columna
FROM combustible_estanques e
LEFT JOIN LATERAL (
    SELECT SUM(litros_entrada - litros_salida) AS litros_kardex,
           (SELECT valor_stock_despues FROM combustible_kardex_valorizado
             WHERE estanque_id = e.id
             ORDER BY fecha_movimiento DESC, created_at DESC LIMIT 1) AS ultimo_valor_kardex
    FROM combustible_kardex_valorizado
    WHERE estanque_id = e.id
) k ON true
WHERE e.activo
ORDER BY ABS(e.valor_total_stock - e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0)) DESC;

-- 2. Qué filas cambiaría MIG188 y en cuánto (dry-run exacto del UPDATE).
SELECT
    e.codigo,
    e.es_demo,
    e.valor_total_stock AS valor_actual,
    ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2) AS valor_regularizado,
    ROUND((ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2)
           - e.valor_total_stock)::numeric, 2) AS cambio
FROM combustible_estanques e
WHERE ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2)
      IS DISTINCT FROM e.valor_total_stock
ORDER BY ABS(ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0))::numeric, 2) - e.valor_total_stock) DESC;

-- 3. Movimientos causantes: salidas/traspasos posteriores a MIG77 (2026-05-23)
--    cuyos RPC no bajaban el valor de la columna. Conteo por estanque y tipo.
SELECT e.codigo, k.tipo_movimiento, count(*) AS movimientos,
       ROUND(SUM(k.litros_salida)::numeric, 1) AS litros_salidos,
       ROUND(SUM(k.litros_salida * k.costo_unitario_movimiento)::numeric, 2) AS valor_no_descontado_estimado
FROM combustible_kardex_valorizado k
JOIN combustible_estanques e ON e.id = k.estanque_id
WHERE k.tipo_movimiento IN ('salida_equipo','salida_externa','salida_venta','salida_despacho','traspaso_salida')
  AND k.fecha_movimiento >= DATE '2026-05-23'
GROUP BY e.codigo, k.tipo_movimiento
ORDER BY e.codigo, valor_no_descontado_estimado DESC;

-- 4. Sanidad general del kardex (debe dar 0 en todo).
SELECT
    (SELECT count(*) FROM combustible_kardex_valorizado WHERE litros_entrada < 0 OR litros_salida < 0) AS litros_negativos,
    (SELECT count(*) FROM combustible_kardex_valorizado WHERE estanque_id IS NULL)                     AS sin_estanque,
    (SELECT count(*) FROM combustible_estanques WHERE stock_teorico_lt < 0)                            AS stock_negativo,
    (SELECT count(*) FROM combustible_estanques WHERE capacidad_lt IS NOT NULL AND stock_teorico_lt > capacidad_lt) AS sobre_capacidad;
