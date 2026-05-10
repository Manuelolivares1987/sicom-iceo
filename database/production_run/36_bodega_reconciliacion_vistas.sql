-- ============================================================================
-- 36_bodega_reconciliacion_vistas.sql
-- ----------------------------------------------------------------------------
-- Vistas de reconciliacion para el modulo Bodega:
--   1. v_bodega_reconciliacion_stock_fifo
--      Compara stock_bodega (legacy CPP) vs inventario_capas (FIFO mig 56).
--      Detecta productos con divergencia en cantidad o valor.
--
--   2. v_bodega_reconciliacion_combustible
--      Compara stock_teorico_lt del estanque vs ultima medicion fisica
--      (combustible_varillaje) vs ultimo kardex valorizado (mig 57).
--
--   3. v_bodega_movimientos_excepcionales
--      Ajustes y mermas de inventario para auditoria operacional.
--
-- DECISION:
--   Solo SELECT. Sin RPC, sin DML, sin tocar tablas. Riesgo cero — solo
--   permite VER el estado actual antes de decidir si activar las RPCs
--   transaccionales mig 55-57.
--
-- IDEMPOTENTE.
-- ============================================================================


-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='stock_bodega') THEN
        RAISE EXCEPTION 'STOP - stock_bodega no existe (mig 02 base)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='inventario_capas') THEN
        RAISE EXCEPTION 'STOP - inventario_capas no existe (mig 56 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_varillaje') THEN
        RAISE EXCEPTION 'STOP - combustible_varillaje no existe (mig 50)';
    END IF;
END $$;


-- ============================================================================
-- ── 1. v_bodega_reconciliacion_stock_fifo ──────────────────────────────────
-- ============================================================================
-- Stock legacy (CPP en stock_bodega) vs FIFO (suma de inventario_capas).
-- Marca:
--   cuadrado            cantidad_legacy = cantidad_fifo (tolerancia 0.001) Y
--                       valor_legacy = valor_fifo (tolerancia $1).
--   desviacion_cantidad cantidades difieren mas de la tolerancia.
--   desviacion_valor    cantidades cuadran pero valor difiere.
--   sin_capa_fifo       hay stock legacy pero no hay capas FIFO (tipico
--                       para productos pre-mig 56 sin sembrado de capas).
--   sin_stock_legacy    hay capas FIFO pero stock_bodega = 0 (raro, indica
--                       capas huerfanas o RPC mig 56 ejecutada sin updated
--                       a stock_bodega).
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_reconciliacion_stock_fifo CASCADE;
CREATE VIEW v_bodega_reconciliacion_stock_fifo AS
WITH fifo_agg AS (
    SELECT
        ic.producto_id,
        ic.bodega_id,
        SUM(ic.cantidad_disponible) AS cantidad_fifo,
        SUM(ic.cantidad_disponible * ic.costo_unitario) AS valor_fifo,
        COUNT(*) FILTER (WHERE ic.cantidad_disponible > 0) AS capas_activas,
        MIN(ic.fecha_recepcion) FILTER (WHERE ic.cantidad_disponible > 0) AS capa_mas_antigua,
        MAX(ic.fecha_recepcion) FILTER (WHERE ic.cantidad_disponible > 0) AS capa_mas_nueva
    FROM inventario_capas ic
    WHERE ic.estado = 'disponible'
    GROUP BY ic.producto_id, ic.bodega_id
),
todos AS (
    SELECT producto_id, bodega_id FROM stock_bodega
    UNION
    SELECT producto_id, bodega_id FROM fifo_agg
)
SELECT
    p.id                                          AS producto_id,
    p.codigo                                      AS producto_codigo,
    p.nombre                                      AS producto_nombre,
    p.categoria                                   AS producto_categoria,
    b.id                                          AS bodega_id,
    b.codigo                                      AS bodega_codigo,
    b.nombre                                      AS bodega_nombre,
    COALESCE(sb.cantidad, 0)                      AS cantidad_legacy,
    COALESCE(sb.costo_promedio, 0)                AS costo_promedio_legacy,
    COALESCE(sb.valor_total, 0)                   AS valor_legacy,
    COALESCE(fa.cantidad_fifo, 0)                 AS cantidad_fifo,
    COALESCE(fa.valor_fifo, 0)                    AS valor_fifo,
    COALESCE(fa.capas_activas, 0)                 AS capas_activas,
    fa.capa_mas_antigua,
    fa.capa_mas_nueva,
    (COALESCE(sb.cantidad, 0) - COALESCE(fa.cantidad_fifo, 0)) AS delta_cantidad,
    (COALESCE(sb.valor_total, 0) - COALESCE(fa.valor_fifo, 0)) AS delta_valor,
    sb.ultimo_movimiento                          AS ultimo_movimiento_legacy,
    CASE
        WHEN COALESCE(sb.cantidad, 0) > 0 AND COALESCE(fa.cantidad_fifo, 0) = 0 THEN 'sin_capa_fifo'
        WHEN COALESCE(sb.cantidad, 0) = 0 AND COALESCE(fa.cantidad_fifo, 0) > 0 THEN 'sin_stock_legacy'
        WHEN ABS(COALESCE(sb.cantidad, 0) - COALESCE(fa.cantidad_fifo, 0)) > 0.001 THEN 'desviacion_cantidad'
        WHEN ABS(COALESCE(sb.valor_total, 0) - COALESCE(fa.valor_fifo, 0)) > 1 THEN 'desviacion_valor'
        ELSE 'cuadrado'
    END                                            AS estado_reconciliacion
FROM todos t
JOIN productos p ON p.id = t.producto_id
JOIN bodegas b ON b.id = t.bodega_id
LEFT JOIN stock_bodega sb ON sb.producto_id = t.producto_id AND sb.bodega_id = t.bodega_id
LEFT JOIN fifo_agg fa ON fa.producto_id = t.producto_id AND fa.bodega_id = t.bodega_id;

COMMENT ON VIEW v_bodega_reconciliacion_stock_fifo IS
    'Reconciliacion stock_bodega (CPP legacy) vs inventario_capas (FIFO mig 56). estado_reconciliacion = cuadrado | desviacion_cantidad | desviacion_valor | sin_capa_fifo | sin_stock_legacy.';


-- ============================================================================
-- ── 2. v_bodega_reconciliacion_combustible ─────────────────────────────────
-- ============================================================================
-- Por estanque: stock teorico actual vs ultimo varillaje fisico vs ultimo
-- kardex valorizado (si existe — depende de mig 57 RPCs activas).
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_reconciliacion_combustible CASCADE;
CREATE VIEW v_bodega_reconciliacion_combustible AS
WITH ultima_varilla AS (
    SELECT DISTINCT ON (estanque_id)
        estanque_id,
        fecha                       AS varilla_fecha,
        medicion_fisica_lt          AS varilla_fisico_lt,
        stock_teorico_snapshot_lt   AS varilla_teorico_snapshot_lt,
        diferencia_lt               AS varilla_diferencia_snapshot_lt,
        ajuste_movimiento_id        AS varilla_ajuste_movimiento_id,
        observaciones               AS varilla_observaciones
    FROM combustible_varillaje
    ORDER BY estanque_id, fecha DESC, created_at DESC
),
ultimo_kardex AS (
    SELECT DISTINCT ON (estanque_id)
        estanque_id,
        fecha_movimiento            AS kardex_fecha,
        tipo_movimiento             AS kardex_tipo,
        stock_lt_despues            AS kardex_stock_lt,
        costo_promedio_lt_despues   AS kardex_cpp_lt,
        valor_stock_despues         AS kardex_valor_total
    FROM combustible_kardex_valorizado
    ORDER BY estanque_id, fecha_movimiento DESC, created_at DESC
)
SELECT
    e.id                            AS estanque_id,
    e.codigo                        AS estanque_codigo,
    e.nombre                        AS estanque_nombre,
    e.faena_id,
    e.capacidad_lt,
    e.stock_teorico_lt              AS estanque_stock_teorico_lt,
    e.costo_promedio_lt             AS estanque_cpp_lt,
    e.valor_total_stock             AS estanque_valor_total,
    e.activo                        AS estanque_activo,
    uv.varilla_fecha,
    uv.varilla_fisico_lt,
    uv.varilla_teorico_snapshot_lt,
    uv.varilla_diferencia_snapshot_lt,
    uv.varilla_ajuste_movimiento_id,
    uv.varilla_observaciones,
    -- delta actual: estanque vs ultima medicion fisica.
    CASE WHEN uv.varilla_fisico_lt IS NOT NULL
         THEN ROUND((uv.varilla_fisico_lt - e.stock_teorico_lt)::numeric, 2)
         ELSE NULL END                AS delta_fisico_vs_teorico_lt,
    CASE WHEN uv.varilla_fecha IS NOT NULL
         THEN (CURRENT_DATE - uv.varilla_fecha)
         ELSE NULL END                AS dias_desde_ultima_varilla,
    uk.kardex_fecha,
    uk.kardex_tipo,
    uk.kardex_stock_lt,
    uk.kardex_cpp_lt,
    uk.kardex_valor_total,
    -- delta entre stock teorico y ultimo kardex (deberia ser 0 si mig 57
    -- estuviera 100% activa). Si NULL, kardex no tiene movimientos aun.
    CASE WHEN uk.kardex_stock_lt IS NOT NULL
         THEN ROUND((e.stock_teorico_lt - uk.kardex_stock_lt)::numeric, 2)
         ELSE NULL END                AS delta_estanque_vs_kardex_lt,
    -- alerta si:
    --  a) hace > 7 dias sin varillaje
    --  b) delta_fisico_vs_teorico > 50 lt en valor absoluto
    --  c) kardex desactualizado (delta_estanque_vs_kardex != 0)
    CASE
        WHEN uv.varilla_fecha IS NULL THEN 'sin_varillaje'
        WHEN (CURRENT_DATE - uv.varilla_fecha) > 7 THEN 'varillaje_atrasado'
        WHEN uv.varilla_fisico_lt IS NOT NULL
             AND ABS(uv.varilla_fisico_lt - e.stock_teorico_lt) > 50 THEN 'desviacion_fisica'
        WHEN uk.kardex_stock_lt IS NOT NULL
             AND ABS(e.stock_teorico_lt - uk.kardex_stock_lt) > 0.01 THEN 'kardex_divergente'
        ELSE 'cuadrado'
    END                                AS estado_reconciliacion
FROM combustible_estanques e
LEFT JOIN ultima_varilla uv ON uv.estanque_id = e.id
LEFT JOIN ultimo_kardex uk ON uk.estanque_id = e.id;

COMMENT ON VIEW v_bodega_reconciliacion_combustible IS
    'Reconciliacion combustible: estanque vs ultima varillaje vs ultimo kardex valorizado. estado_reconciliacion = cuadrado | sin_varillaje | varillaje_atrasado | desviacion_fisica | kardex_divergente.';


-- ============================================================================
-- ── 3. v_bodega_movimientos_excepcionales ──────────────────────────────────
-- ============================================================================
-- Ajustes y mermas de los ultimos 60 dias en movimientos_inventario.
-- Para auditoria operacional (overrides admin se reflejan aqui hoy en dia,
-- ya que las RPCs transaccionales mig 55 con override no estan activas).
-- ============================================================================
DROP VIEW IF EXISTS public.v_bodega_movimientos_excepcionales CASCADE;
CREATE VIEW v_bodega_movimientos_excepcionales AS
SELECT
    m.id                            AS movimiento_id,
    m.created_at                    AS fecha,
    m.tipo                          AS tipo,
    m.bodega_id,
    b.codigo                        AS bodega_codigo,
    b.nombre                        AS bodega_nombre,
    m.producto_id,
    p.codigo                        AS producto_codigo,
    p.nombre                        AS producto_nombre,
    p.categoria                     AS producto_categoria,
    m.cantidad,
    m.costo_unitario,
    m.costo_total,
    m.ot_id,
    ot.folio                        AS ot_folio,
    m.activo_id,
    m.lote,
    m.documento_referencia,
    m.motivo,
    m.usuario_id,
    up.nombre_completo              AS usuario_nombre,
    up.rol                          AS usuario_rol
FROM movimientos_inventario m
JOIN productos p ON p.id = m.producto_id
JOIN bodegas b ON b.id = m.bodega_id
LEFT JOIN ordenes_trabajo ot ON ot.id = m.ot_id
LEFT JOIN usuarios_perfil up ON up.id = m.usuario_id
-- tipo_movimiento_enum (mig 01): entrada, salida, ajuste_positivo,
-- ajuste_negativo, transferencia_entrada, transferencia_salida, merma,
-- devolucion. Filtramos los que requieren auditoria operativa.
WHERE m.tipo IN ('ajuste_positivo','ajuste_negativo','merma')
  AND m.created_at >= NOW() - INTERVAL '60 days'
ORDER BY m.created_at DESC;

COMMENT ON VIEW v_bodega_movimientos_excepcionales IS
    'Ajustes y mermas de movimientos_inventario en los ultimos 60 dias. Para auditoria operacional. Incluye usuario, motivo, OT asociada y costo.';


-- ============================================================================
-- ── 4. PERMISOS ─────────────────────────────────────────────────────────────
-- Vistas accesibles por usuarios authenticated (RLS de tablas subyacentes
-- sigue rigiendo).
-- ============================================================================
GRANT SELECT ON v_bodega_reconciliacion_stock_fifo TO authenticated;
GRANT SELECT ON v_bodega_reconciliacion_combustible TO authenticated;
GRANT SELECT ON v_bodega_movimientos_excepcionales TO authenticated;


-- ============================================================================
-- ── 5. SMOKE TEST ───────────────────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    n1 INT; n2 INT; n3 INT;
BEGIN
    SELECT COUNT(*) INTO n1 FROM v_bodega_reconciliacion_stock_fifo;
    SELECT COUNT(*) INTO n2 FROM v_bodega_reconciliacion_combustible;
    SELECT COUNT(*) INTO n3 FROM v_bodega_movimientos_excepcionales;
    RAISE NOTICE '== Mig 36 ==';
    RAISE NOTICE 'v_bodega_reconciliacion_stock_fifo .... % filas', n1;
    RAISE NOTICE 'v_bodega_reconciliacion_combustible ... % filas', n2;
    RAISE NOTICE 'v_bodega_movimientos_excepcionales .... % filas', n3;
END $$;

-- Resultsets visibles para verificacion manual:
SELECT 'v_bodega_reconciliacion_stock_fifo'  AS vista, COUNT(*) AS filas FROM v_bodega_reconciliacion_stock_fifo
UNION ALL
SELECT 'v_bodega_reconciliacion_combustible', COUNT(*) FROM v_bodega_reconciliacion_combustible
UNION ALL
SELECT 'v_bodega_movimientos_excepcionales',  COUNT(*) FROM v_bodega_movimientos_excepcionales;


-- ============================================================================
-- ROLLBACK
--   DROP VIEW v_bodega_movimientos_excepcionales;
--   DROP VIEW v_bodega_reconciliacion_combustible;
--   DROP VIEW v_bodega_reconciliacion_stock_fifo;
-- ============================================================================
