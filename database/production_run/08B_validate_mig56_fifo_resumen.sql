-- ============================================================================
-- 08B_validate_mig56_fifo_resumen.sql  —  Solo lectura. Una fila final.
-- ----------------------------------------------------------------------------
-- Devuelve UNA fila con: resultado, detalle y métricas.
--
-- ESTADOS POSIBLES (en orden de prioridad):
--   - STOP_MIG56                       : falta estructura o hay datos invalidos.
--   - WARNING_MIG56_COSTOS_PENDIENTES  : productos con stock sin costo_promedio.
--   - WARNING_MIG56_PENDIENTE_CAPAS    : productos con stock sin capa FIFO.
--   - OK_MIG56                         : todo correcto, listo para mig 57.
--
-- NOTA SOBRE NOMBRES DE COLUMNAS REALES:
--   - inventario_capas: producto_id, bodega_id, cantidad_inicial,
--       cantidad_disponible, costo_unitario, fecha_recepcion.
--     Trazabilidad de origen via FKs separadas (recepcion_bodega_id,
--     orden_compra_id, proveedor_id, folio_recepcion).
--     Valores totales = columnas GENERATED (costo_total_inicial,
--     costo_total_disponible).
--
--   - inventario_consumos_capas: capa_id, cantidad_consumida,
--       costo_unitario_capa, fecha_consumo. Destino via FKs separadas
--     (salida_bodega_id, ot_id, ceco_id).
-- ============================================================================

WITH
-- ── 1. Tablas FIFO (2 esperadas) ────────────────────────────────────
tablas AS (
    SELECT COALESCE(array_agg(table_name::text ORDER BY table_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name::text IN ('inventario_capas','inventario_consumos_capas')
),
tablas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY['inventario_capas','inventario_consumos_capas']::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM tablas)) AS x
    ) s
),

-- ── 2. Columnas críticas inventario_capas (6 reales) ────────────────
cols_capas AS (
    SELECT COALESCE(array_agg(column_name::text ORDER BY column_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name::text='inventario_capas'
      AND column_name::text IN (
        'producto_id','bodega_id','cantidad_inicial','cantidad_disponible',
        'costo_unitario','fecha_recepcion'
      )
),
cols_capas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'producto_id','bodega_id','cantidad_inicial','cantidad_disponible',
            'costo_unitario','fecha_recepcion'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM cols_capas)) AS x
    ) s
),

-- ── 3. Columnas críticas inventario_consumos_capas (4 reales) ───────
cols_consumos AS (
    SELECT COALESCE(array_agg(column_name::text ORDER BY column_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name::text='inventario_consumos_capas'
      AND column_name::text IN (
        'capa_id','cantidad_consumida','costo_unitario_capa','fecha_consumo'
      )
),
cols_consumos_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'capa_id','cantidad_consumida','costo_unitario_capa','fecha_consumo'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM cols_consumos)) AS x
    ) s
),

-- ── 4. Función FIFO ──────────────────────────────────────────────────
fn_fifo AS (
    SELECT COUNT(*)::int AS encontrada
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_consumir_inventario_fifo'
),

-- ── 5. Vistas FIFO (4 esperadas) ────────────────────────────────────
vistas AS (
    SELECT COALESCE(array_agg(viewname::text ORDER BY viewname::text), ARRAY[]::text[]) AS encontradas
    FROM pg_views
    WHERE schemaname='public'
      AND viewname::text IN (
        'v_trazabilidad_producto_fifo','v_costo_ot_materiales_fifo',
        'v_stock_valorizado_fifo','v_kardex_valorizado_materiales'
      )
),
vistas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'v_costo_ot_materiales_fifo','v_kardex_valorizado_materiales',
            'v_stock_valorizado_fifo','v_trazabilidad_producto_fifo'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM vistas)) AS x
    ) s
),

-- ── 6. Productos con stock SIN capa (warning si > 0) ────────────────
prod_sin_capa AS (
    SELECT COUNT(*)::int AS cantidad
    FROM stock_bodega sb
    WHERE sb.cantidad > 0
      AND NOT EXISTS (
          SELECT 1 FROM inventario_capas ic
           WHERE ic.producto_id = sb.producto_id
             AND ic.bodega_id   = sb.bodega_id
             AND ic.estado      = 'disponible'
             AND ic.cantidad_disponible > 0
      )
),

-- ── 7. Productos con stock SIN costo_promedio (warning si > 0) ──────
prod_sin_costo AS (
    SELECT COUNT(*)::int AS cantidad
    FROM stock_bodega
    WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0)
),

-- ── 8. Capas con cantidad_disponible negativa (STOP) ────────────────
capas_neg AS (
    SELECT COUNT(*)::int AS cantidad
    FROM inventario_capas
    WHERE cantidad_disponible < 0
),

-- ── 9. Capas con costo_unitario NULL o <= 0 (STOP) ──────────────────
capas_costo_inv AS (
    SELECT COUNT(*)::int AS cantidad
    FROM inventario_capas
    WHERE costo_unitario IS NULL OR costo_unitario <= 0
),

-- ── 10. Banderas de decisión ────────────────────────────────────────
flags AS (
    SELECT
        (   array_length((SELECT faltan FROM tablas_faltantes), 1) > 0
         OR array_length((SELECT faltan FROM cols_capas_faltantes), 1) > 0
         OR array_length((SELECT faltan FROM cols_consumos_faltantes), 1) > 0
         OR (SELECT encontrada FROM fn_fifo) = 0
         OR array_length((SELECT faltan FROM vistas_faltantes), 1) > 0
        ) AS falta_estructura,
        (   (SELECT cantidad FROM capas_neg) > 0
         OR (SELECT cantidad FROM capas_costo_inv) > 0
        ) AS hay_datos_invalidos,
        ((SELECT cantidad FROM prod_sin_costo) > 0)  AS hay_costos_pendientes,
        ((SELECT cantidad FROM prod_sin_capa)  > 0)  AS hay_capas_pendientes
),

-- ── 11. Construir detalle ───────────────────────────────────────────
detalle AS (
    SELECT array_to_string(
        array_remove(ARRAY[
            CASE WHEN array_length((SELECT faltan FROM tablas_faltantes), 1) > 0
                 THEN 'Tablas FIFO faltantes: ' || array_to_string((SELECT faltan FROM tablas_faltantes), ', ')
            END,
            CASE WHEN array_length((SELECT faltan FROM cols_capas_faltantes), 1) > 0
                 THEN 'Columnas faltantes en inventario_capas: ' ||
                      array_to_string((SELECT faltan FROM cols_capas_faltantes), ', ')
            END,
            CASE WHEN array_length((SELECT faltan FROM cols_consumos_faltantes), 1) > 0
                 THEN 'Columnas faltantes en inventario_consumos_capas: ' ||
                      array_to_string((SELECT faltan FROM cols_consumos_faltantes), ', ')
            END,
            CASE WHEN (SELECT encontrada FROM fn_fifo) = 0
                 THEN 'Funcion fn_consumir_inventario_fifo NO existe'
            END,
            CASE WHEN array_length((SELECT faltan FROM vistas_faltantes), 1) > 0
                 THEN 'Vistas FIFO faltantes: ' || array_to_string((SELECT faltan FROM vistas_faltantes), ', ') ||
                      ' (ejecutar 08C_hotfix_mig56_vistas_fifo.sql para crearlas)'
            END,
            CASE WHEN (SELECT cantidad FROM capas_neg) > 0
                 THEN 'Capas con cantidad_disponible negativa: ' ||
                      (SELECT cantidad FROM capas_neg)::text
            END,
            CASE WHEN (SELECT cantidad FROM capas_costo_inv) > 0
                 THEN 'Capas con costo_unitario NULL o <= 0: ' ||
                      (SELECT cantidad FROM capas_costo_inv)::text
            END,
            CASE WHEN (SELECT cantidad FROM prod_sin_costo) > 0
                 THEN 'Productos con stock SIN costo_promedio: ' ||
                      (SELECT cantidad FROM prod_sin_costo)::text ||
                      ' (Finanzas debe corregir antes de paso 09)'
            END,
            CASE WHEN (SELECT cantidad FROM prod_sin_capa) > 0
                 THEN 'Productos con stock SIN capa: ' ||
                      (SELECT cantidad FROM prod_sin_capa)::text ||
                      ' (sembrar capas en paso 09 con Finanzas)'
            END
        ]::text[], NULL),
        ' | '
    ) AS texto
)

-- ── 12. Resultado final (1 fila) ────────────────────────────────────
SELECT
    CASE
        -- Prioridad 1: estructura o datos invalidos → STOP
        WHEN (SELECT falta_estructura      FROM flags) THEN 'STOP_MIG56'
        WHEN (SELECT hay_datos_invalidos   FROM flags) THEN 'STOP_MIG56'
        -- Prioridad 2: costos pendientes (bloqueante para paso 09)
        WHEN (SELECT hay_costos_pendientes FROM flags) THEN 'WARNING_MIG56_COSTOS_PENDIENTES'
        -- Prioridad 3: solo faltan capas iniciales (paso 09 pendiente)
        WHEN (SELECT hay_capas_pendientes  FROM flags) THEN 'WARNING_MIG56_PENDIENTE_CAPAS'
        ELSE 'OK_MIG56'
    END AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
        '2 tablas + columnas + funcion FIFO + 4 vistas + sin pendientes ni datos invalidos. Listo para paso 10 (mig 57 CPP combustible).'
    ) AS detalle,
    -- Métricas
    COALESCE(array_length((SELECT encontradas FROM tablas), 1), 0)         AS tablas_fifo_encontradas,
    (SELECT encontrada FROM fn_fifo)                                       AS funcion_fifo_existe,
    COALESCE(array_length((SELECT encontradas FROM vistas), 1), 0)         AS vistas_fifo_encontradas,
    (SELECT cantidad FROM prod_sin_capa)                                   AS productos_con_stock_sin_capa,
    (SELECT cantidad FROM prod_sin_costo)                                  AS productos_con_stock_sin_costo,
    (SELECT cantidad FROM capas_neg)                                       AS capas_negativas,
    (SELECT cantidad FROM capas_costo_inv)                                 AS capas_costo_invalido,
    NOW()                                                                  AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- - resultado = 'OK_MIG56':
--     Estructura completa, sin pendientes, sin datos invalidos.
--     Listo para paso 10 (mig 57 combustible CPP).
--
-- - resultado = 'WARNING_MIG56_PENDIENTE_CAPAS':
--     Estructura completa pero hay productos con stock sin capa FIFO.
--     Esto NO bloquea avanzar al paso 10 (mig 57 combustible).
--     Sí bloquea las salidas FIFO de inventario hasta sembrar capas en paso 09.
--
-- - resultado = 'WARNING_MIG56_COSTOS_PENDIENTES':
--     Productos con stock sin costo_promedio. Finanzas debe corregir
--     stock_bodega.costo_promedio antes de ejecutar paso 09 (seed capas
--     iniciales). Si se siembra sin costos, las capas tendran costo 0 y
--     la valorizacion FIFO sera incorrecta.
--
-- - resultado = 'STOP_MIG56':
--     Falta estructura (tabla/columna/función/vista) o datos invalidos.
--     Acciones tipicas:
--       * "Tablas/Columnas/Funcion faltantes" → re-ejecutar 07_apply_mig56_*.
--       * "Vistas FIFO faltantes"             → ejecutar 08C_hotfix_mig56_vistas_fifo.sql.
--       * "Capas con cantidad_disponible negativa" → investigar — la BD tiene
--                                              CHECK >= 0, no deberian existir.
--       * "Capas con costo_unitario NULL o <= 0"   → corregir manualmente
--                                              con Finanzas; afecta valorizacion.
-- ============================================================================
