-- ============================================================================
-- 39_bodega_reportes_financieros.sql
-- ----------------------------------------------------------------------------
-- 6 vistas read-only para reportes financieros del modulo Bodega:
--   1. v_bodega_stock_valorizado_actual    (alias semantico sobre reconciliacion)
--   2. v_bodega_costo_salidas_por_ot       (agrega salidas_bodega por OT)
--   3. v_bodega_costo_salidas_por_ceco     (agrega salidas_bodega por CECO)
--   4. v_bodega_kardex_valorizado_producto (kardex simple sin saldo acumulado)
--   5. v_bodega_mermas_ajustes             (alias semantico)
--   6. v_bodega_resumen_financiero         (1 fila con KPIs globales)
--
-- IDEMPOTENTE. NO TOCA STOCK. NO INVOCA RPCs. SOLO SELECT.
--
-- Decisiones:
--   - Kardex SIN saldo acumulado (calculo costoso por window function;
--     se difiere a iteracion posterior si se necesita).
--   - Mermas/ajustes reusan v_bodega_movimientos_excepcionales (MIG36).
--   - Solo salidas estado='registrada' (excluyen anuladas).
--   - Resumen financiero usa una sola fila con KPIs del mes actual.
-- ============================================================================


-- ── Prechecks ───────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_bodega_reconciliacion_stock_fifo') THEN
        RAISE EXCEPTION 'STOP - v_bodega_reconciliacion_stock_fifo no existe (MIG36 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_bodega_movimientos_excepcionales') THEN
        RAISE EXCEPTION 'STOP - v_bodega_movimientos_excepcionales no existe (MIG36)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='salidas_bodega') THEN
        RAISE EXCEPTION 'STOP - salidas_bodega no existe (MIG37)';
    END IF;
END $$;


-- ============================================================================
-- 1. v_bodega_stock_valorizado_actual
-- ----------------------------------------------------------------------------
-- Alias semantico sobre v_bodega_reconciliacion_stock_fifo con renombres
-- consistentes con el contexto financiero (no tecnico).
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_stock_valorizado_actual CASCADE;
CREATE VIEW v_bodega_stock_valorizado_actual AS
SELECT
    producto_id,
    producto_codigo,
    producto_nombre,
    producto_categoria        AS categoria,
    bodega_id,
    bodega_codigo,
    bodega_nombre,
    cantidad_legacy           AS cantidad_stock,
    costo_promedio_legacy,
    valor_legacy,
    cantidad_fifo,
    valor_fifo,
    delta_cantidad,
    delta_valor,
    estado_reconciliacion
FROM v_bodega_reconciliacion_stock_fifo;

COMMENT ON VIEW v_bodega_stock_valorizado_actual IS
'Stock valorizado actual por producto/bodega con CPP legacy y FIFO en paralelo. MIG39.';


-- ============================================================================
-- 2. v_bodega_costo_salidas_por_ot
-- ----------------------------------------------------------------------------
-- Agrega salidas_bodega + items por OT. Costo total real (FIFO) viene de
-- salidas_bodega_items.costo_total_clp.
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_costo_salidas_por_ot CASCADE;
CREATE VIEW v_bodega_costo_salidas_por_ot AS
WITH salidas_ot AS (
    SELECT sb.id AS salida_id, sb.ot_id, sb.ceco_id, sb.created_at
      FROM salidas_bodega sb
     WHERE sb.estado = 'registrada' AND sb.ot_id IS NOT NULL
)
SELECT
    so.ot_id,
    ot.folio                                              AS ot_folio,
    ot.estado::text                                       AS ot_estado,
    ot.faena_id,
    f.nombre                                              AS faena,
    so.ceco_id,
    cc.codigo                                             AS ceco_codigo,
    cc.nombre                                             AS ceco_nombre,
    COUNT(DISTINCT so.salida_id)                          AS cantidad_salidas,
    COUNT(sbi.id)                                         AS cantidad_items,
    ROUND(COALESCE(SUM(sbi.costo_total_clp), 0)::numeric, 0) AS costo_total_fifo,
    MIN(so.created_at)                                    AS fecha_primera_salida,
    MAX(so.created_at)                                    AS fecha_ultima_salida
FROM salidas_ot so
LEFT JOIN salidas_bodega_items sbi ON sbi.salida_id = so.salida_id
JOIN ordenes_trabajo ot ON ot.id = so.ot_id
LEFT JOIN faenas f       ON f.id = ot.faena_id
LEFT JOIN centros_costo cc ON cc.id = so.ceco_id
GROUP BY so.ot_id, ot.folio, ot.estado, ot.faena_id, f.nombre,
         so.ceco_id, cc.codigo, cc.nombre
ORDER BY MAX(so.created_at) DESC;

COMMENT ON VIEW v_bodega_costo_salidas_por_ot IS
'Costo total FIFO de salidas agrupadas por OT. Solo salidas registradas con OT. MIG39.';


-- ============================================================================
-- 3. v_bodega_costo_salidas_por_ceco
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_bodega_costo_salidas_por_ceco CASCADE;
CREATE VIEW v_bodega_costo_salidas_por_ceco AS
SELECT
    cc.id                                                 AS ceco_id,
    cc.codigo                                             AS ceco_codigo,
    cc.nombre                                             AS ceco_nombre,
    cc.area                                               AS ceco_area,
    COUNT(DISTINCT sb.id)                                 AS cantidad_salidas,
    COUNT(sbi.id)                                         AS cantidad_items,
    ROUND(COALESCE(SUM(sbi.costo_total_clp), 0)::numeric, 0) AS costo_total_fifo,
    MIN(sb.created_at)                                    AS fecha_primera,
    MAX(sb.created_at)                                    AS fecha_ultima
FROM centros_costo cc
LEFT JOIN salidas_bodega sb ON sb.ceco_id = cc.id AND sb.estado = 'registrada'
LEFT JOIN salidas_bodega_items sbi ON sbi.salida_id = sb.id
WHERE cc.activo = true
GROUP BY cc.id, cc.codigo, cc.nombre, cc.area;

COMMENT ON VIEW v_bodega_costo_salidas_por_ceco IS
'Costo total FIFO de salidas agrupadas por CECO. Solo CECOs activos. MIG39.';


-- ============================================================================
-- 4. v_bodega_kardex_valorizado_producto
-- ----------------------------------------------------------------------------
-- Kardex simple: cada movimiento_inventario en orden cronologico DESC con
-- entradas y salidas separadas. Sin saldo acumulado (se difiere a iteracion
-- posterior por costo del window function en queries con filtros).
--
-- tipos:
--   entradas: 'entrada', 'ajuste_positivo', 'transferencia_entrada', 'devolucion'
--   salidas:  'salida',  'ajuste_negativo', 'transferencia_salida', 'merma'
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_kardex_valorizado_producto CASCADE;
CREATE VIEW v_bodega_kardex_valorizado_producto AS
SELECT
    mi.id                                AS movimiento_id,
    mi.producto_id,
    p.codigo                             AS producto_codigo,
    p.nombre                             AS producto_nombre,
    mi.bodega_id,
    b.codigo                             AS bodega_codigo,
    b.nombre                             AS bodega_nombre,
    mi.created_at                        AS fecha_movimiento,
    mi.tipo::text                        AS tipo_movimiento,
    mi.documento_referencia              AS referencia,
    CASE WHEN mi.tipo::text IN ('entrada','ajuste_positivo','transferencia_entrada','devolucion')
         THEN mi.cantidad ELSE NULL END  AS entrada_cantidad,
    CASE WHEN mi.tipo::text IN ('entrada','ajuste_positivo','transferencia_entrada','devolucion')
         THEN ROUND(mi.costo_total::numeric, 0) ELSE NULL END AS entrada_valor,
    CASE WHEN mi.tipo::text IN ('salida','ajuste_negativo','transferencia_salida','merma')
         THEN mi.cantidad ELSE NULL END  AS salida_cantidad,
    CASE WHEN mi.tipo::text IN ('salida','ajuste_negativo','transferencia_salida','merma')
         THEN ROUND(mi.costo_total::numeric, 0) ELSE NULL END AS salida_valor,
    mi.costo_unitario,
    mi.ot_id,
    ot.folio                             AS ot_folio,
    mi.motivo
FROM movimientos_inventario mi
JOIN productos p ON p.id = mi.producto_id
JOIN bodegas   b ON b.id = mi.bodega_id
LEFT JOIN ordenes_trabajo ot ON ot.id = mi.ot_id;

COMMENT ON VIEW v_bodega_kardex_valorizado_producto IS
'Kardex valorizado simple por producto/bodega. Entradas y salidas separadas. Sin saldo acumulado (iteracion posterior). MIG39.';


-- ============================================================================
-- 5. v_bodega_mermas_ajustes
-- ----------------------------------------------------------------------------
-- Alias semantico sobre v_bodega_movimientos_excepcionales (MIG36) con
-- nombres consistentes para el modulo de reportes financieros.
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_mermas_ajustes CASCADE;
CREATE VIEW v_bodega_mermas_ajustes AS
SELECT
    movimiento_id,
    fecha,
    tipo,
    bodega_id,
    bodega_codigo,
    bodega_nombre,
    producto_id,
    producto_codigo,
    producto_nombre,
    producto_categoria                  AS categoria,
    cantidad,
    costo_unitario,
    costo_total,
    motivo,
    usuario_id,
    usuario_nombre,
    usuario_rol,
    ot_id,
    ot_folio
FROM v_bodega_movimientos_excepcionales;

COMMENT ON VIEW v_bodega_mermas_ajustes IS
'Mermas y ajustes (negativos y positivos) ultimos 60 dias. Alias sobre v_bodega_movimientos_excepcionales (MIG36). MIG39.';


-- ============================================================================
-- 6. v_bodega_resumen_financiero
-- ----------------------------------------------------------------------------
-- 1 fila con KPIs financieros. Mes en curso = desde date_trunc('month', NOW()).
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_resumen_financiero CASCADE;
CREATE VIEW v_bodega_resumen_financiero AS
SELECT
    (SELECT COALESCE(SUM(cantidad_disponible * costo_unitario), 0)::numeric
       FROM inventario_capas WHERE estado='disponible')         AS valor_total_stock_fifo,
    (SELECT COALESCE(SUM(valor_total), 0)::numeric
       FROM stock_bodega)                                       AS valor_total_stock_legacy,
    (SELECT COUNT(*)::int FROM salidas_bodega
      WHERE created_at >= date_trunc('month', NOW())
        AND estado = 'registrada')                              AS total_salidas_mes,
    (SELECT COALESCE(SUM(sbi.costo_total_clp), 0)::numeric
       FROM salidas_bodega_items sbi
       JOIN salidas_bodega sb ON sb.id = sbi.salida_id
      WHERE sb.created_at >= date_trunc('month', NOW())
        AND sb.estado = 'registrada')                           AS costo_salidas_mes,
    (SELECT COUNT(*)::int FROM movimientos_inventario
      WHERE tipo::text IN ('merma','ajuste_negativo')
        AND created_at >= date_trunc('month', NOW()))           AS total_mermas_mes,
    (SELECT COALESCE(SUM(costo_total), 0)::numeric
       FROM movimientos_inventario
      WHERE tipo::text IN ('merma','ajuste_negativo')
        AND created_at >= date_trunc('month', NOW()))           AS costo_mermas_mes,
    (SELECT COUNT(*)::int FROM v_bodega_reconciliacion_stock_fifo
      WHERE estado_reconciliacion <> 'cuadrado')                AS productos_con_desviacion,
    (SELECT COUNT(*)::int FROM stock_bodega
      WHERE cantidad <= 0)                                      AS productos_sin_stock,
    (SELECT COUNT(*)::int FROM stock_bodega sb
       JOIN productos p ON p.id = sb.producto_id
      WHERE sb.cantidad <= p.stock_minimo AND p.stock_minimo > 0) AS productos_bajo_minimo,
    NOW()                                                       AS calculado_en;

COMMENT ON VIEW v_bodega_resumen_financiero IS
'KPIs financieros del mes actual (1 fila): valores stock FIFO/legacy, salidas y mermas del mes, productos desviados/sin stock/bajo minimo. MIG39.';


-- ============================================================================
-- GRANTs
-- ============================================================================
GRANT SELECT ON v_bodega_stock_valorizado_actual    TO authenticated;
GRANT SELECT ON v_bodega_costo_salidas_por_ot       TO authenticated;
GRANT SELECT ON v_bodega_costo_salidas_por_ceco     TO authenticated;
GRANT SELECT ON v_bodega_kardex_valorizado_producto TO authenticated;
GRANT SELECT ON v_bodega_mermas_ajustes             TO authenticated;
GRANT SELECT ON v_bodega_resumen_financiero         TO authenticated;


-- ============================================================================
-- SMOKE TEST
-- ============================================================================
DO $$
DECLARE
    v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM pg_views WHERE schemaname='public'
     AND viewname IN ('v_bodega_stock_valorizado_actual','v_bodega_costo_salidas_por_ot',
                      'v_bodega_costo_salidas_por_ceco','v_bodega_kardex_valorizado_producto',
                      'v_bodega_mermas_ajustes','v_bodega_resumen_financiero');
    IF v_n <> 6 THEN
        RAISE EXCEPTION 'STOP - esperaba 6 vistas nuevas, encontre %', v_n;
    END IF;

    -- Selects de prueba (capturan errores de columna mal nombrada / tipo)
    PERFORM 1 FROM v_bodega_stock_valorizado_actual LIMIT 1;
    PERFORM 1 FROM v_bodega_costo_salidas_por_ot LIMIT 1;
    PERFORM 1 FROM v_bodega_costo_salidas_por_ceco LIMIT 1;
    PERFORM 1 FROM v_bodega_kardex_valorizado_producto LIMIT 1;
    PERFORM 1 FROM v_bodega_mermas_ajustes LIMIT 1;
    PERFORM 1 FROM v_bodega_resumen_financiero LIMIT 1;

    RAISE NOTICE '== MIG39 aplicada OK ==';
    RAISE NOTICE '   6 vistas read-only de reportes financieros creadas';
END $$;


-- Resultset de verificacion
SELECT 'v_bodega_stock_valorizado_actual'    AS vista, COUNT(*)::text AS filas
  FROM v_bodega_stock_valorizado_actual
UNION ALL SELECT 'v_bodega_costo_salidas_por_ot',       COUNT(*)::text FROM v_bodega_costo_salidas_por_ot
UNION ALL SELECT 'v_bodega_costo_salidas_por_ceco',     COUNT(*)::text FROM v_bodega_costo_salidas_por_ceco
UNION ALL SELECT 'v_bodega_kardex_valorizado_producto', COUNT(*)::text FROM v_bodega_kardex_valorizado_producto
UNION ALL SELECT 'v_bodega_mermas_ajustes',             COUNT(*)::text FROM v_bodega_mermas_ajustes
UNION ALL SELECT 'v_bodega_resumen_financiero',         COUNT(*)::text FROM v_bodega_resumen_financiero
UNION ALL SELECT 'reconciliacion_cuadrado',
                 (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion='cuadrado')
UNION ALL SELECT 'reconciliacion_desviado',
                 (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion<>'cuadrado');


-- Log
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG39_END',
            'MIG39 vistas reportes financieros bodega aplicadas',
            'ok',
            'Solo lectura. UI en /dashboard/inventario/reportes'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK
--   DROP VIEW v_bodega_resumen_financiero;
--   DROP VIEW v_bodega_mermas_ajustes;
--   DROP VIEW v_bodega_kardex_valorizado_producto;
--   DROP VIEW v_bodega_costo_salidas_por_ceco;
--   DROP VIEW v_bodega_costo_salidas_por_ot;
--   DROP VIEW v_bodega_stock_valorizado_actual;
-- ============================================================================
