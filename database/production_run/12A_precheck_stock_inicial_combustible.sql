-- ============================================================================
-- 12A_precheck_stock_inicial_combustible.sql  —  SOLO LECTURA. No modifica nada.
-- ----------------------------------------------------------------------------
-- Devuelve, por estanque activo, el detalle necesario para preparar el paso 12.
-- Ejecutar ANTES de tocar 12_seed_stock_inicial_combustible_produccion.sql.
--
-- Estados:
--   - YA_EXISTE     : ya tiene stock_inicial activo. NO requiere accion.
--   - FALTA_LITROS  : stock_teorico_lt <= 0. NO tiene sentido cargar stock inicial.
--   - FALTA_COSTO   : no hay costo_unitario propuesto disponible. Coordinar Finanzas.
--   - LISTO         : tiene litros + costo propuesto. Listo para paso 12.
--
-- "costo_unitario_propuesto" se calcula en este orden:
--   1. e.costo_promedio_lt actual del estanque (si > 0).
--   2. Ultimo ingresos_combustible.costo_unitario_lt registrado (si > 0).
--   3. NULL → FALTA_COSTO.
--
-- Esta consulta NO hace INSERT, UPDATE ni DELETE.
-- ============================================================================

WITH ultimo_ingreso AS (
    SELECT DISTINCT ON (estanque_id)
        estanque_id,
        costo_unitario_lt,
        fecha_documento,
        folio_ingreso
    FROM ingresos_combustible
    WHERE costo_unitario_lt IS NOT NULL
      AND costo_unitario_lt > 0
      AND estado = 'registrado'
    ORDER BY estanque_id, fecha_documento DESC, fecha_recepcion DESC
)
SELECT
    e.codigo                                                        AS estanque_codigo,
    e.nombre                                                        AS estanque_nombre,
    e.stock_teorico_lt                                              AS stock_teorico_lt_actual,
    e.capacidad_lt                                                  AS capacidad_lt,
    (si.id IS NOT NULL)                                             AS tiene_stock_inicial_activo,
    si.id                                                           AS stock_inicial_activo_id,
    NULLIF(e.costo_promedio_lt, 0)                                  AS costo_promedio_actual,
    ui.costo_unitario_lt                                            AS costo_ultimo_ingreso,
    ui.fecha_documento                                              AS fecha_ultimo_ingreso,
    ui.folio_ingreso                                                AS folio_ultimo_ingreso,
    COALESCE(NULLIF(e.costo_promedio_lt, 0), ui.costo_unitario_lt)  AS costo_unitario_propuesto,
    CASE
        WHEN si.id IS NOT NULL
             THEN 'YA_EXISTE'
        WHEN e.stock_teorico_lt IS NULL OR e.stock_teorico_lt <= 0
             THEN 'FALTA_LITROS'
        WHEN COALESCE(NULLIF(e.costo_promedio_lt, 0), ui.costo_unitario_lt) IS NULL
             THEN 'FALTA_COSTO'
        ELSE 'LISTO'
    END                                                             AS estado
FROM combustible_estanques e
LEFT JOIN combustible_stock_inicial si
       ON si.estanque_id = e.id AND si.anulado = false
LEFT JOIN ultimo_ingreso ui
       ON ui.estanque_id = e.id
WHERE e.activo = true
ORDER BY
    CASE
        WHEN si.id IS NOT NULL                                              THEN 4
        WHEN e.stock_teorico_lt IS NULL OR e.stock_teorico_lt <= 0          THEN 3
        WHEN COALESCE(NULLIF(e.costo_promedio_lt, 0), ui.costo_unitario_lt) IS NULL
                                                                            THEN 2
        ELSE                                                                     1
    END,
    e.codigo;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - Estados LISTO  → estos estanques deben configurarse en el paso 12.
-- - Estado FALTA_COSTO → coordinar con Finanzas (ultima factura/guia).
-- - Estado FALTA_LITROS → confirmar con Gustavo (varillaje fisico).
-- - Estado YA_EXISTE → omitir; el paso 12 es idempotente y no los toca.
--
-- Esperado HOY (segun resultado 11B):
--   2 filas LISTO (o FALTA_COSTO si Finanzas aun no entrega) para EST-15K, EST-1K.
-- ============================================================================
