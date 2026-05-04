-- ============================================================================
-- 08C_hotfix_mig56_vistas_fifo.sql  —  HOTFIX MINIMO. Solo CREATE OR REPLACE VIEW.
-- ----------------------------------------------------------------------------
-- Crea las 3 vistas FIFO que el script 07_apply_mig56_fifo_produccion.sql
-- NO incluyó:
--   - public.v_trazabilidad_producto_fifo
--   - public.v_costo_ot_materiales_fifo
--   - public.v_kardex_valorizado_materiales
--
-- La vista v_stock_valorizado_fifo ya existe (creada en 07_apply).
--
-- IDEMPOTENTE: usa CREATE OR REPLACE VIEW.
-- SOLO LECTURA SOBRE DATOS: las vistas no insertan/modifican filas.
-- NO TOCA: tablas, función fn_consumir_inventario_fifo, capas, stock_bodega,
--          mig 57, ni inicia paso 09.
-- ============================================================================


-- ── 1. Precheck: estructura base mig 56 debe existir ─────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name='inventario_capas'
    ) THEN
        RAISE EXCEPTION 'STOP — inventario_capas no existe. Ejecutar primero 07_apply_mig56_fifo_produccion.sql.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name='inventario_consumos_capas'
    ) THEN
        RAISE EXCEPTION 'STOP — inventario_consumos_capas no existe. Ejecutar primero 07_apply_mig56_fifo_produccion.sql.';
    END IF;

    RAISE NOTICE 'Estructura base mig 56 OK. Procediendo a crear las 3 vistas.';
END $$;


-- ── 2. Vista: v_trazabilidad_producto_fifo ──────────────────────────
-- Muestra una fila por capa con datos de producto, bodega, valores y origen.

CREATE OR REPLACE VIEW public.v_trazabilidad_producto_fifo AS
SELECT
    ic.id                                         AS capa_id,
    ic.producto_id,
    p.codigo                                      AS producto_codigo,
    p.nombre                                      AS producto_nombre,
    ic.bodega_id,
    b.codigo                                      AS bodega_codigo,
    ic.cantidad_inicial,
    ic.cantidad_disponible,
    (ic.cantidad_inicial - ic.cantidad_disponible) AS cantidad_consumida,
    ic.costo_unitario,
    (ic.cantidad_inicial    * ic.costo_unitario)  AS valor_inicial,
    (ic.cantidad_disponible * ic.costo_unitario)  AS valor_disponible,
    ic.fecha_recepcion,
    -- Origen derivado de las FKs reales:
    CASE
        WHEN ic.recepcion_bodega_id IS NOT NULL THEN 'recepcion_bodega'
        WHEN ic.orden_compra_id     IS NOT NULL THEN 'orden_compra'
        ELSE 'manual_legacy'
    END                                           AS origen_tipo,
    COALESCE(ic.recepcion_bodega_id, ic.orden_compra_id) AS origen_id,
    ic.folio_recepcion                            AS folio_origen,
    -- Estado derivado:
    CASE
        WHEN ic.cantidad_disponible <= 0                          THEN 'AGOTADA'
        WHEN ic.cantidad_disponible >= ic.cantidad_inicial        THEN 'DISPONIBLE'
        ELSE                                                            'PARCIAL'
    END                                           AS estado_capa,
    ic.proveedor_id,
    ic.lote,
    ic.vencimiento,
    ic.estado                                     AS estado_capa_raw,
    ic.created_at
FROM public.inventario_capas ic
LEFT JOIN public.productos p ON p.id = ic.producto_id
LEFT JOIN public.bodegas   b ON b.id = ic.bodega_id;

COMMENT ON VIEW public.v_trazabilidad_producto_fifo IS
    'FASE 5.4-A — Trazabilidad por capa FIFO: producto, bodega, valores, origen y estado derivado.';


-- ── 3. Vista: v_costo_ot_materiales_fifo ────────────────────────────
-- Filtra solo consumos asociados a una OT (ot_id IS NOT NULL).

CREATE OR REPLACE VIEW public.v_costo_ot_materiales_fifo AS
SELECT
    cc.ot_id                          AS orden_trabajo_id,
    cc.producto_id,
    p.codigo                          AS producto_codigo,
    p.nombre                          AS producto_nombre,
    cc.cantidad_consumida,
    cc.costo_unitario_capa            AS costo_unitario,
    cc.costo_total_consumido          AS valor_consumido,
    cc.fecha_consumo,
    cc.capa_id,
    ic.folio_recepcion                AS folio_origen,
    cc.bodega_id,
    b.codigo                          AS bodega_codigo,
    cc.salida_bodega_id,
    cc.ceco_id,
    cc.consumido_por
FROM public.inventario_consumos_capas cc
LEFT JOIN public.inventario_capas ic ON ic.id = cc.capa_id
LEFT JOIN public.productos p         ON p.id  = cc.producto_id
LEFT JOIN public.bodegas   b         ON b.id  = cc.bodega_id
WHERE cc.ot_id IS NOT NULL;

COMMENT ON VIEW public.v_costo_ot_materiales_fifo IS
    'FASE 5.4-A — Costo real de materiales FIFO consumidos por OT. Una fila por capa consumida.';


-- ── 4. Vista: v_kardex_valorizado_materiales ────────────────────────
-- UNION ALL de entradas (capas) + salidas (consumos).

CREATE OR REPLACE VIEW public.v_kardex_valorizado_materiales AS
-- ENTRADAS (cada capa = una entrada)
SELECT
    ic.fecha_recepcion::TIMESTAMPTZ                  AS fecha_movimiento,
    ic.producto_id,
    p.codigo                                          AS producto_codigo,
    p.nombre                                          AS producto_nombre,
    ic.bodega_id,
    b.codigo                                          AS bodega_codigo,
    'ENTRADA'                                         AS tipo_movimiento,
    ic.cantidad_inicial                               AS cantidad,
    ic.costo_unitario,
    (ic.cantidad_inicial * ic.costo_unitario)         AS valor_movimiento,
    CASE
        WHEN ic.recepcion_bodega_id IS NOT NULL THEN 'recepcion_bodega'
        WHEN ic.orden_compra_id     IS NOT NULL THEN 'orden_compra'
        ELSE 'manual_legacy'
    END                                               AS referencia_tipo,
    COALESCE(ic.recepcion_bodega_id, ic.orden_compra_id) AS referencia_id,
    ic.folio_recepcion                                AS folio_referencia,
    ic.id                                             AS capa_id
FROM public.inventario_capas ic
LEFT JOIN public.productos p ON p.id = ic.producto_id
LEFT JOIN public.bodegas   b ON b.id = ic.bodega_id

UNION ALL

-- SALIDAS (cada consumo = una salida)
SELECT
    cc.fecha_consumo                                  AS fecha_movimiento,
    cc.producto_id,
    p.codigo                                          AS producto_codigo,
    p.nombre                                          AS producto_nombre,
    cc.bodega_id,
    b.codigo                                          AS bodega_codigo,
    'SALIDA'                                          AS tipo_movimiento,
    cc.cantidad_consumida                             AS cantidad,
    cc.costo_unitario_capa                            AS costo_unitario,
    cc.costo_total_consumido                          AS valor_movimiento,
    CASE
        WHEN cc.salida_bodega_id IS NOT NULL THEN 'salida_bodega'
        WHEN cc.ot_id            IS NOT NULL THEN 'ot'
        WHEN cc.movimiento_inventario_id IS NOT NULL THEN 'movimiento_inventario'
        ELSE 'consumo'
    END                                               AS referencia_tipo,
    COALESCE(cc.salida_bodega_id, cc.ot_id, cc.movimiento_inventario_id) AS referencia_id,
    sb.folio_salida                                   AS folio_referencia,
    cc.capa_id
FROM public.inventario_consumos_capas cc
LEFT JOIN public.inventario_capas ic_consumo ON ic_consumo.id = cc.capa_id
LEFT JOIN public.productos p ON p.id = cc.producto_id
LEFT JOIN public.bodegas   b ON b.id = cc.bodega_id
LEFT JOIN public.salidas_bodega sb ON sb.id = cc.salida_bodega_id;

COMMENT ON VIEW public.v_kardex_valorizado_materiales IS
    'FASE 5.4-A — Kardex valorizado FIFO: entradas (capas) + salidas (consumos) con saldos por movimiento.';


-- ── 5. GRANT SELECT a authenticated (seguir patrón mig 56) ──────────
GRANT SELECT ON public.v_trazabilidad_producto_fifo  TO authenticated;
GRANT SELECT ON public.v_costo_ot_materiales_fifo    TO authenticated;
GRANT SELECT ON public.v_kardex_valorizado_materiales TO authenticated;


-- ── 6. Verificación post: ¿las 4 vistas FIFO existen? ───────────────
SELECT
    'VISTAS_FIFO_TOTAL' AS check_name,
    COUNT(*) AS encontradas,
    array_agg(viewname::text ORDER BY viewname::text) AS vistas
FROM pg_views
WHERE schemaname = 'public'
  AND viewname::text IN (
    'v_stock_valorizado_fifo',
    'v_trazabilidad_producto_fifo',
    'v_costo_ot_materiales_fifo',
    'v_kardex_valorizado_materiales'
  );
-- Esperado: encontradas = 4


-- ── 7. Test funcional (solo lectura) ────────────────────────────────
SELECT 'TEST_TRAZABILIDAD' AS test, COUNT(*)::int AS filas FROM public.v_trazabilidad_producto_fifo;
SELECT 'TEST_COSTO_OT'     AS test, COUNT(*)::int AS filas FROM public.v_costo_ot_materiales_fifo;
SELECT 'TEST_KARDEX'       AS test, COUNT(*)::int AS filas FROM public.v_kardex_valorizado_materiales;


-- ── 8. Insertar log SOLO si la tabla existe (no fallar si falta) ────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_HOTFIX_MIG56_VISTAS',
            'Hotfix: creadas 3 vistas FIFO faltantes (v_trazabilidad_producto_fifo, v_costo_ot_materiales_fifo, v_kardex_valorizado_materiales).',
            current_user,
            NOW(), NOW(), 'ok',
            'Complementa 07_apply_mig56_fifo_produccion.sql. NO toca tablas/funcion/datos.'
        );
        RAISE NOTICE 'Log registrado en operacion_migraciones_log.';
    ELSE
        RAISE NOTICE 'Tabla operacion_migraciones_log no existe. Se omite log.';
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK MANUAL (si fuera necesario)
-- ----------------------------------------------------------------------------
-- DROP VIEW IF EXISTS public.v_trazabilidad_producto_fifo;
-- DROP VIEW IF EXISTS public.v_costo_ot_materiales_fifo;
-- DROP VIEW IF EXISTS public.v_kardex_valorizado_materiales;
-- (v_stock_valorizado_fifo NO se toca — la creó 07_apply_mig56_fifo_produccion.sql)
-- ============================================================================
