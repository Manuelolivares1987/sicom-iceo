-- ============================================================================
-- 09_seed_capas_iniciales_fifo_produccion.sql  —  Seed capas iniciales FIFO.
-- ----------------------------------------------------------------------------
-- IDEMPOTENTE: el INSERT excluye productos que ya tienen capa disponible.
-- Re-ejecutable sin riesgo. NO duplica capas existentes.
--
-- COMPORTAMIENTO:
--   - Solo crea capas para stock_bodega.cantidad > 0 que NO tenga ya capa.
--   - Solo si stock_bodega.costo_promedio > 0 (Finanzas debe completar antes
--     productos con costo NULL/0; este script los excluye automáticamente).
--   - NO modifica stock_bodega.
--   - NO modifica movimientos_inventario historicos.
--   - NO modifica datos de capas existentes.
--   - Folio: 'STOCK-INICIAL-FIFO-YYYYMMDD'.
--   - origen_tipo (derivado en v_trazabilidad_producto_fifo): 'manual_legacy'
--     porque las capas iniciales no tienen recepcion_bodega_id ni
--     orden_compra_id (es lo correcto — son partidas legacy de apertura).
--
-- REQUIERE: tabla operacion_migraciones_log creada (paso 03).
-- ============================================================================


-- ── 1. PRECHECK informativo: productos a procesar ────────────────────
SELECT
    p.codigo AS producto_codigo,
    p.nombre AS producto_nombre,
    b.codigo AS bodega_codigo,
    sb.cantidad,
    sb.costo_promedio,
    (CASE
        WHEN sb.costo_promedio IS NULL OR sb.costo_promedio = 0 THEN '⚠️ SE OMITIRA - SIN COSTO'
        ELSE 'SE PROCESARA'
     END) AS accion
FROM stock_bodega sb
JOIN productos p ON p.id = sb.producto_id
JOIN bodegas b   ON b.id = sb.bodega_id
WHERE sb.cantidad > 0
  AND NOT EXISTS (
    SELECT 1 FROM inventario_capas ic
     WHERE ic.producto_id = sb.producto_id
       AND ic.bodega_id   = sb.bodega_id
       AND ic.estado      = 'disponible'
  )
ORDER BY (CASE WHEN sb.costo_promedio IS NULL OR sb.costo_promedio = 0 THEN 0 ELSE 1 END),
         sb.cantidad DESC;


-- ── 2. WARNING si hay productos sin costo ────────────────────────────
DO $$
DECLARE v_sin_costo INTEGER; v_negativos INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_sin_costo FROM stock_bodega
     WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0);

    SELECT COUNT(*) INTO v_negativos FROM stock_bodega WHERE cantidad < 0;

    IF v_negativos > 0 THEN
        RAISE EXCEPTION 'STOP — % productos con cantidad NEGATIVA en stock_bodega. Investigar antes de continuar.', v_negativos;
    END IF;

    IF v_sin_costo > 0 THEN
        RAISE WARNING '⚠️ HAY % PRODUCTOS CON STOCK SIN COSTO_PROMEDIO. Seran OMITIDOS del INSERT. Coordinar con Finanzas para completar costos y re-ejecutar.', v_sin_costo;
    ELSE
        RAISE NOTICE 'OK — todos los productos con stock tienen costo_promedio > 0.';
    END IF;
END $$;


-- ── 3. EJECUCION DEL SEED (idempotente + transaccional + con métricas) ──
-- Hace todo en un DO block para capturar conteos antes/después y registrar log.

DO $$
DECLARE
    v_capas_antes               INTEGER;
    v_capas_despues             INTEGER;
    v_capas_creadas             INTEGER;
    v_productos_con_stock       INTEGER;
    v_productos_a_procesar      INTEGER;
    v_productos_omitidos        INTEGER;
    v_valor_total_inicial       NUMERIC;
    v_log_detalle               TEXT;
    v_resumen                   TEXT;
BEGIN
    -- Snapshot ANTES
    SELECT COUNT(*) INTO v_capas_antes FROM inventario_capas;

    -- Métricas previas
    SELECT COUNT(*) INTO v_productos_con_stock
      FROM stock_bodega WHERE cantidad > 0;

    SELECT COUNT(*) INTO v_productos_a_procesar
      FROM stock_bodega sb
     WHERE sb.cantidad > 0
       AND sb.costo_promedio IS NOT NULL
       AND sb.costo_promedio > 0
       AND NOT EXISTS (
           SELECT 1 FROM inventario_capas ic
            WHERE ic.producto_id=sb.producto_id
              AND ic.bodega_id=sb.bodega_id
              AND ic.estado='disponible'
       );

    SELECT COUNT(*) INTO v_productos_omitidos
      FROM stock_bodega sb
     WHERE sb.cantidad > 0
       AND (sb.costo_promedio IS NULL OR sb.costo_promedio = 0)
       AND NOT EXISTS (
           SELECT 1 FROM inventario_capas ic
            WHERE ic.producto_id=sb.producto_id
              AND ic.bodega_id=sb.bodega_id
              AND ic.estado='disponible'
       );

    -- ── INSERT IDEMPOTENTE ──
    INSERT INTO inventario_capas (
        producto_id, bodega_id, fecha_recepcion, folio_recepcion,
        cantidad_inicial, cantidad_disponible, unidad, costo_unitario,
        estado
    )
    SELECT
        sb.producto_id, sb.bodega_id, CURRENT_DATE,
        'STOCK-INICIAL-FIFO-' || TO_CHAR(NOW(), 'YYYYMMDD'),
        sb.cantidad, sb.cantidad,
        COALESCE(p.unidad_medida, 'unidad'),
        sb.costo_promedio,
        'disponible'
      FROM stock_bodega sb
      JOIN productos p ON p.id = sb.producto_id
     WHERE sb.cantidad > 0
       AND sb.costo_promedio IS NOT NULL
       AND sb.costo_promedio > 0
       AND NOT EXISTS (
           SELECT 1 FROM inventario_capas ic
            WHERE ic.producto_id = sb.producto_id
              AND ic.bodega_id   = sb.bodega_id
              AND ic.estado      = 'disponible'
       );

    -- Snapshot DESPUÉS
    SELECT COUNT(*) INTO v_capas_despues FROM inventario_capas;
    v_capas_creadas := v_capas_despues - v_capas_antes;

    -- Valor total inicial sembrado en esta ejecución
    SELECT COALESCE(SUM(cantidad_inicial * costo_unitario), 0)
      INTO v_valor_total_inicial
      FROM inventario_capas
     WHERE folio_recepcion = 'STOCK-INICIAL-FIFO-' || TO_CHAR(NOW(), 'YYYYMMDD');

    -- Log
    v_log_detalle :=
        'capas_creadas=' || v_capas_creadas::TEXT ||
        ' | productos_a_procesar=' || v_productos_a_procesar::TEXT ||
        ' | productos_omitidos_sin_costo=' || v_productos_omitidos::TEXT ||
        ' | valor_total_inicial=' || v_valor_total_inicial::TEXT;

    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_FIFO_SEED_CAPAS',
            'Seed capas iniciales FIFO desde stock_bodega (excluyendo productos sin costo).',
            current_user,
            NOW(), NOW(),
            CASE WHEN v_productos_omitidos > 0 THEN 'warning' ELSE 'ok' END,
            v_log_detalle
        );
    END IF;

    -- Mensajes amigables
    RAISE NOTICE '';
    RAISE NOTICE '════════════════ RESUMEN SEED CAPAS FIFO ════════════════';
    RAISE NOTICE 'Capas antes:                  %', v_capas_antes;
    RAISE NOTICE 'Capas despues:                %', v_capas_despues;
    RAISE NOTICE 'Capas creadas en esta corrida:%', v_capas_creadas;
    RAISE NOTICE 'Productos con stock total:    %', v_productos_con_stock;
    RAISE NOTICE 'Productos procesados:         %', v_productos_a_procesar;
    RAISE NOTICE 'Productos omitidos sin costo: %', v_productos_omitidos;
    RAISE NOTICE 'Valor total inicial sembrado: %', v_valor_total_inicial;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;


-- ── 4. RECONCILIACION POST-SEED ──────────────────────────────────────
SELECT
    'RECONCILIACION_FIFO_POST' AS check_name,
    COUNT(*) AS productos_desincronizados
FROM (
    SELECT sb.producto_id, sb.bodega_id, sb.cantidad,
           COALESCE(SUM(ic.cantidad_disponible), 0) AS capas
      FROM stock_bodega sb
      LEFT JOIN inventario_capas ic
        ON ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
     WHERE sb.cantidad > 0
       AND sb.costo_promedio IS NOT NULL
       AND sb.costo_promedio > 0
     GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
    HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
) sub;
-- Esperado tras INSERT: 0 (productos con costo).


-- ── 5. RESUMEN FINAL ESTRUCTURADO (UNA fila) ─────────────────────────
WITH metricas AS (
    SELECT
        (SELECT COUNT(*) FROM stock_bodega WHERE cantidad > 0)
            AS productos_con_stock_total,
        (SELECT COUNT(*)
           FROM stock_bodega sb
          WHERE sb.cantidad > 0
            AND EXISTS (
                SELECT 1 FROM inventario_capas ic
                 WHERE ic.producto_id=sb.producto_id
                   AND ic.bodega_id=sb.bodega_id
                   AND ic.estado='disponible'
            )) AS productos_con_capa,
        (SELECT COUNT(*)
           FROM stock_bodega
          WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0))
            AS productos_omitidos_sin_costo,
        (SELECT COUNT(*) FROM inventario_capas
          WHERE folio_recepcion LIKE 'STOCK-INICIAL-FIFO-%'
            AND fecha_recepcion = CURRENT_DATE)
            AS capas_creadas_hoy,
        (SELECT COUNT(*) FROM inventario_capas
          WHERE folio_recepcion LIKE 'STOCK-INICIAL-FIFO-%')
            AS capas_seed_total_historico,
        (SELECT COALESCE(SUM(cantidad_inicial * costo_unitario), 0)
           FROM inventario_capas
          WHERE folio_recepcion LIKE 'STOCK-INICIAL-FIFO-%')
            AS valor_total_inicial_historico,
        (SELECT COUNT(*)
           FROM (
               SELECT sb.producto_id, sb.bodega_id, sb.cantidad,
                      COALESCE(SUM(ic.cantidad_disponible), 0) AS capas
                 FROM stock_bodega sb
                 LEFT JOIN inventario_capas ic
                   ON ic.producto_id=sb.producto_id
                  AND ic.bodega_id=sb.bodega_id
                  AND ic.estado='disponible'
                WHERE sb.cantidad > 0
                  AND sb.costo_promedio IS NOT NULL
                  AND sb.costo_promedio > 0
                GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
               HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
           ) sub) AS productos_desincronizados
)
SELECT
    CASE
        WHEN productos_desincronizados > 0
            THEN 'STOP_SEED_CAPAS_FIFO'
        WHEN productos_omitidos_sin_costo > 0
            THEN 'WARNING_SEED_CAPAS_FIFO_COSTOS_PENDIENTES'
        WHEN productos_con_capa = productos_con_stock_total
            THEN 'OK_SEED_CAPAS_FIFO'
        WHEN productos_con_capa < productos_con_stock_total
            THEN 'WARNING_SEED_CAPAS_FIFO_COBERTURA_PARCIAL'
        ELSE 'OK_SEED_CAPAS_FIFO'
    END AS resultado,
    array_to_string(
        array_remove(ARRAY[
            CASE WHEN productos_desincronizados > 0
                 THEN 'Reconciliacion fallo: ' || productos_desincronizados::text ||
                      ' productos con cantidad stock_bodega != suma capas. Investigar.'
            END,
            CASE WHEN productos_omitidos_sin_costo > 0
                 THEN 'Productos OMITIDOS sin costo_promedio: ' || productos_omitidos_sin_costo::text ||
                      ' (Finanzas debe corregir y re-ejecutar paso 09).'
            END,
            CASE WHEN capas_creadas_hoy > 0
                 THEN 'Capas creadas HOY: ' || capas_creadas_hoy::text
            END,
            CASE WHEN capas_creadas_hoy = 0 AND capas_seed_total_historico > 0
                 THEN 'Sin nuevas capas — todas las capas de seed ya existian (' ||
                      capas_seed_total_historico::text || ' historicas).'
            END,
            'Productos con stock cubiertos por capa: ' ||
                productos_con_capa::text || ' de ' || productos_con_stock_total::text,
            'Valor total inicial historico de capas seed: $' ||
                ROUND(valor_total_inicial_historico, 0)::text
        ]::text[], NULL),
        ' | '
    ) AS detalle,
    -- Métricas
    capas_creadas_hoy                AS capas_creadas,
    productos_con_stock_total        AS productos_con_stock_procesados,
    productos_omitidos_sin_costo,
    valor_total_inicial_historico    AS valor_total_inicial,
    productos_con_capa,
    capas_seed_total_historico,
    productos_desincronizados,
    NOW()                            AS chequeado_en
FROM metricas;


-- ============================================================================
-- INTERPRETACION DEL RESULTADO
-- ============================================================================
-- - 'OK_SEED_CAPAS_FIFO':
--     Todos los productos con stock tienen capa, sin pendientes ni desync.
--     Listo para paso 10 (mig 57 combustible CPP).
--
-- - 'WARNING_SEED_CAPAS_FIFO_COSTOS_PENDIENTES':
--     Hay productos con stock sin costo_promedio (omitidos en este seed).
--     Coordinar con Finanzas para completar costos y re-ejecutar este script.
--     SI cobertura parcial es aceptable operativamente, se puede avanzar.
--
-- - 'WARNING_SEED_CAPAS_FIFO_COBERTURA_PARCIAL':
--     No todos los productos quedaron cubiertos por capas (puede ser por costo
--     o por algun otro motivo). Revisar query (1) precheck para ver detalle.
--
-- - 'STOP_SEED_CAPAS_FIFO':
--     Reconciliacion fallo (stock_bodega != suma capas). Investigar — no
--     deberia ocurrir en una ejecucion limpia.
-- ============================================================================
