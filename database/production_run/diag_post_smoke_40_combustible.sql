-- ============================================================================
-- diag_post_smoke_40_combustible.sql
-- ----------------------------------------------------------------------------
-- Diagnostico read-only POST-smoke MIG40. NO re-ejecuta el smoke (cada
-- corrida del smoke deja +5 lt netos en el estanque elegido). Reconstruye
-- la validacion de los 12 pasos desde evidencia actual en BD.
--
-- Salida: 1 unico resultset con schema dx, ok, detalle, extra_json.
--
-- NO TOCA DATOS.
-- ============================================================================

WITH
-- Snapshot global actual
g AS (
    SELECT
        (SELECT COUNT(*) FROM pg_proc
          WHERE proname='rpc_registrar_ingreso_combustible_valorizado')             AS rpc_ingreso,
        (SELECT COUNT(*) FROM pg_proc
          WHERE proname='rpc_registrar_salida_combustible_valorizada')              AS rpc_salida,
        (SELECT COALESCE(SUM(cantidad), 0) FROM stock_bodega)                       AS stock_bodega_total,
        (SELECT COUNT(*) FROM inventario_capas WHERE estado='disponible')           AS capas_disponibles,
        (SELECT COALESCE(SUM(cantidad_disponible * costo_unitario), 0)
           FROM inventario_capas WHERE estado='disponible')                         AS valor_fifo_total,
        (SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado')
           FROM v_bodega_reconciliacion_stock_fifo)                                 AS reconc_cuadrado,
        (SELECT COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
           FROM v_bodega_reconciliacion_stock_fifo)                                 AS reconc_desviado,
        (SELECT COUNT(*) FROM combustible_movimientos)                              AS comb_mov_legacy,
        (SELECT COUNT(*) FROM combustible_estanques WHERE stock_teorico_lt < 0)     AS estanques_neg,
        (SELECT COUNT(*) FROM combustible_kardex_valorizado
          WHERE observacion ILIKE '%Smoke MIG40%')                                  AS kardex_smoke_total,
        (SELECT COUNT(*) FROM combustible_kardex_valorizado
          WHERE observacion ILIKE '%Smoke MIG40%' AND tipo_movimiento='ingreso_compra') AS kardex_smoke_ingresos,
        (SELECT COUNT(*) FROM combustible_kardex_valorizado
          WHERE observacion ILIKE '%Smoke MIG40%' AND tipo_movimiento='salida_despacho') AS kardex_smoke_salidas,
        (SELECT COUNT(*) FROM combustible_movimientos
          WHERE observaciones ILIKE '%Smoke MIG40%')                                AS comb_mov_legacy_smoke,
        (SELECT COUNT(*) FROM usuarios_perfil
          WHERE rol='administrador' AND activo=true)                                AS admin_count
)

-- ── 01: precheck MIG40 ────────────────────────────────────────────────────
SELECT
    '01_precheck_mig40'::text                                       AS dx,
    (g.rpc_ingreso = 1 AND g.rpc_salida = 1)                        AS ok,
    format('rpc_ingreso=%s rpc_salida=%s (esperado 1 cada uno)',
           g.rpc_ingreso, g.rpc_salida)                             AS detalle,
    jsonb_build_object('rpc_ingreso', g.rpc_ingreso, 'rpc_salida', g.rpc_salida) AS extra_json
FROM g

-- ── 02: reconciliacion productos cuadrada (no se rompio) ──────────────────
UNION ALL SELECT
    '02_snapshot_global'::text,
    (g.reconc_desviado = 0),
    format('reconc_cuadrado=%s reconc_desviado=%s stock_bodega=%s capas_disp=%s valor_fifo=%s',
           g.reconc_cuadrado, g.reconc_desviado, g.stock_bodega_total,
           g.capas_disponibles, g.valor_fifo_total),
    jsonb_build_object(
        'reconc_cuadrado', g.reconc_cuadrado,
        'reconc_desviado', g.reconc_desviado,
        'stock_bodega_total', g.stock_bodega_total,
        'capas_disponibles', g.capas_disponibles,
        'valor_fifo_total', g.valor_fifo_total
    )
FROM g

-- ── 03: admin disponible (impostar funciona) ──────────────────────────────
UNION ALL SELECT
    '03_admin_disponible'::text,
    (g.admin_count > 0),
    format('admins activos: %s', g.admin_count),
    jsonb_build_object('admin_count', g.admin_count)
FROM g

-- ── 04: estado actual del estanque tocado (EST-15K) ───────────────────────
UNION ALL SELECT
    '04_estado_estanque_smoke'::text,
    (ckv.estado IN ('cuadrado','varillaje_atrasado','desviacion_fisica')
     AND ckv.stock_teorico_lt > 0),
    format('estanque=%s stock=%s lt cpp=%s valor=%s estado=%s dias_varilla=%s',
           ckv.estanque_codigo, ckv.stock_teorico_lt, ckv.cpp_actual,
           ckv.valor_teorico_clp, ckv.estado, ckv.dias_desde_varilla),
    jsonb_build_object(
        'estanque_codigo', ckv.estanque_codigo,
        'stock_teorico_lt', ckv.stock_teorico_lt,
        'cpp_actual', ckv.cpp_actual,
        'valor_teorico_clp', ckv.valor_teorico_clp,
        'estado', ckv.estado,
        'dias_desde_varilla', ckv.dias_desde_varilla,
        'capacidad_lt', ckv.capacidad_lt
    )
FROM v_combustible_control_kardex_varillaje ckv
WHERE ckv.estanque_codigo = 'EST-15K'

-- ── 05: kardex tiene ingresos del smoke ──────────────────────────────────
UNION ALL SELECT
    '05_kardex_smoke_ingresos'::text,
    (g.kardex_smoke_ingresos > 0),
    format('ingresos smoke en kardex: %s (cada corrida agrega 1)', g.kardex_smoke_ingresos),
    jsonb_build_object('count', g.kardex_smoke_ingresos)
FROM g

-- ── 06: ultima fila ingreso smoke ─────────────────────────────────────────
UNION ALL SELECT
    '06_ultimo_kardex_ingreso'::text,
    (ckv.tipo_movimiento = 'ingreso_compra'
     AND ckv.litros_entrada = 10
     AND ckv.costo_unitario_movimiento > 0),
    format('folio=%s tipo=%s litros_entrada=%s costo_unit=%s stock_despues=%s cpp_despues=%s',
           ckv.folio_movimiento, ckv.tipo_movimiento, ckv.litros_entrada,
           ckv.costo_unitario_movimiento, ckv.stock_lt_despues, ckv.costo_promedio_lt_despues),
    jsonb_build_object(
        'folio', ckv.folio_movimiento,
        'tipo', ckv.tipo_movimiento,
        'litros_entrada', ckv.litros_entrada,
        'costo_unit', ckv.costo_unitario_movimiento,
        'stock_despues', ckv.stock_lt_despues,
        'cpp_despues', ckv.costo_promedio_lt_despues,
        'fecha', ckv.fecha_movimiento
    )
FROM (
    SELECT * FROM combustible_kardex_valorizado
     WHERE observacion ILIKE '%Smoke MIG40 ingreso%'
       AND tipo_movimiento = 'ingreso_compra'
     ORDER BY created_at DESC LIMIT 1
) ckv

-- ── 07: kardex tiene salidas del smoke ────────────────────────────────────
UNION ALL SELECT
    '07_kardex_smoke_salidas'::text,
    (g.kardex_smoke_salidas > 0),
    format('salidas smoke en kardex: %s', g.kardex_smoke_salidas),
    jsonb_build_object('count', g.kardex_smoke_salidas)
FROM g

-- ── 08: ultima fila salida smoke ──────────────────────────────────────────
UNION ALL SELECT
    '08_ultimo_kardex_salida'::text,
    (ckv.tipo_movimiento = 'salida_despacho'
     AND ckv.litros_salida = 5
     AND ckv.costo_unitario_movimiento > 0),
    format('folio=%s tipo=%s litros_salida=%s costo_unit=%s stock_despues=%s cpp_despues=%s (CPP no cambio)',
           ckv.folio_movimiento, ckv.tipo_movimiento, ckv.litros_salida,
           ckv.costo_unitario_movimiento, ckv.stock_lt_despues, ckv.costo_promedio_lt_despues),
    jsonb_build_object(
        'folio', ckv.folio_movimiento,
        'tipo', ckv.tipo_movimiento,
        'litros_salida', ckv.litros_salida,
        'costo_unit', ckv.costo_unitario_movimiento,
        'stock_despues', ckv.stock_lt_despues,
        'cpp_despues', ckv.costo_promedio_lt_despues,
        'fecha', ckv.fecha_movimiento
    )
FROM (
    SELECT * FROM combustible_kardex_valorizado
     WHERE observacion ILIKE '%Smoke MIG40 salida%'
       AND tipo_movimiento = 'salida_despacho'
     ORDER BY created_at DESC LIMIT 1
) ckv

-- ── 09: NO toco stock_bodega (evidencia indirecta: reconc productos OK) ──
UNION ALL SELECT
    '09_no_toco_stock_bodega'::text,
    (g.reconc_desviado = 0),
    format('reconciliacion productos cuadrada (cuadrado=%s, desviado=%s). MIG40 no toca stock_bodega por diseno.',
           g.reconc_cuadrado, g.reconc_desviado),
    jsonb_build_object(
        'stock_bodega_total_actual', g.stock_bodega_total,
        'reconc_cuadrado', g.reconc_cuadrado,
        'reconc_desviado', g.reconc_desviado
    )
FROM g

-- ── 10: NO toco inventario_capas (evidencia indirecta: reconc OK) ────────
UNION ALL SELECT
    '10_no_toco_inventario_capas'::text,
    (g.reconc_desviado = 0 AND g.capas_disponibles > 0),
    format('capas_disponibles=%s valor_fifo=%s reconc_desviado=%s',
           g.capas_disponibles, g.valor_fifo_total, g.reconc_desviado),
    jsonb_build_object(
        'capas_disponibles', g.capas_disponibles,
        'valor_fifo_total', g.valor_fifo_total
    )
FROM g

-- ── 11: reconciliacion productos intacta ──────────────────────────────────
UNION ALL SELECT
    '11_reconciliacion_productos_intacta'::text,
    (g.reconc_desviado = 0 AND g.reconc_cuadrado >= 40),
    format('cuadrado=%s desviado=%s (esperado cuadrado>=40, desviado=0)',
           g.reconc_cuadrado, g.reconc_desviado),
    jsonb_build_object(
        'cuadrado', g.reconc_cuadrado,
        'desviado', g.reconc_desviado
    )
FROM g

-- ── 12: NO toco combustible_movimientos legacy ───────────────────────────
UNION ALL SELECT
    '12_no_toco_mov_legacy'::text,
    (g.comb_mov_legacy_smoke = 0),
    format('combustible_movimientos legacy total=%s, con tag Smoke MIG40=%s (esperado 0)',
           g.comb_mov_legacy, g.comb_mov_legacy_smoke),
    jsonb_build_object(
        'total_legacy', g.comb_mov_legacy,
        'tagged_smoke', g.comb_mov_legacy_smoke
    )
FROM g

-- ── 13: sanidad estanques (sin stock negativo) ────────────────────────────
UNION ALL SELECT
    '13_no_estanques_negativos'::text,
    (g.estanques_neg = 0),
    format('estanques con stock < 0: %s (esperado 0)', g.estanques_neg),
    jsonb_build_object('estanques_negativos', g.estanques_neg)
FROM g

-- ── 14: huella smoke acumulada ────────────────────────────────────────────
UNION ALL SELECT
    '14_huella_smoke'::text,
    (g.kardex_smoke_total > 0),
    format('Total filas kardex con tag Smoke MIG40: %s (ingresos=%s, salidas=%s). Cada corrida del smoke agrega 2 filas y +5 lt netos al estanque.',
           g.kardex_smoke_total, g.kardex_smoke_ingresos, g.kardex_smoke_salidas),
    jsonb_build_object(
        'total', g.kardex_smoke_total,
        'ingresos', g.kardex_smoke_ingresos,
        'salidas', g.kardex_smoke_salidas
    )
FROM g

ORDER BY 1;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- 14 checks. Si TODOS devuelven ok=true, el smoke pasó y MIG40 es operativo.
-- Diferencias vs el smoke original (12 pasos):
--   - Checks 09/10 ahora se validan por *evidencia indirecta*: si la
--     reconciliacion productos sigue cuadrada (40/0), implica que MIG40
--     no toco stock_bodega ni inventario_capas (esas vistas comparan
--     ambos). Mas el diseno de las RPCs MIG40 garantiza que SOLO operan
--     sobre combustible_estanques y combustible_kardex_valorizado.
--   - Se agregan checks 13 (sin stock negativo) y 14 (huella acumulada).
--
-- HUELLA SMOKE: este diag NO requiere re-ejecutar el smoke (que dejaria
-- otros +5 lt). Es solo lectura.
-- ============================================================================
