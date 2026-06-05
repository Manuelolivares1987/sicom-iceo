-- ============================================================================
-- 122_combustible_demanda_todas_las_ventas.sql
-- ----------------------------------------------------------------------------
-- Ajuste de la DEMANDA que alimenta la proyeccion de stock de combustible.
--
-- ANTES (MIG88): la demanda solo consideraba despachos a las empresas externas
--   'MYG' y 'LISSET LOPEZ G' (filtro hardcodeado). El panel de combustible
--   mostraba unicamente esas dos empresas.
--
-- AHORA (peticion de Manuel 2026-06-05): la demanda debe considerar TODAS las
--   ventas a clientes, sin importar la empresa. "Solo importa la venta":
--     INCLUYE: salida_venta  (venta externa a cliente identificado)
--              salida_externa (despacho a vehiculo externo autorizado, cualquier empresa)
--     EXCLUYE: salida_equipo / salida_despacho (consumo propio / faena / ceco / ot)
--              recirculacion  (operacion neutra)
--              traspaso_salida / traspaso_entrada (movimiento interno entre estanques)
--              ingreso / ajuste / varillaje / stock_inicial
--
-- Redefine las 3 vistas de MIG88 (diaria, resumen, proyeccion) con la nueva
-- regla. ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Demanda diaria por cliente (todas las ventas) ───────────────────────
DROP VIEW IF EXISTS v_combustible_demanda_externa_diaria CASCADE;
CREATE VIEW v_combustible_demanda_externa_diaria AS
SELECT
    k.fecha_movimiento::DATE                                          AS fecha,
    COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)')    AS empresa,
    k.estanque_id,
    e.codigo                                                          AS estanque_codigo,
    e.nombre                                                          AS estanque_nombre,
    COUNT(*)                                                          AS despachos,
    SUM(k.litros_salida)                                             AS litros
FROM combustible_kardex_valorizado k
LEFT JOIN vehiculos_autorizados_externos ve ON ve.id = k.vehiculo_externo_id
JOIN combustible_estanques e            ON e.id = k.estanque_id
WHERE k.tipo_movimiento IN ('salida_venta','salida_externa')
  AND k.litros_salida > 0
  AND k.fecha_movimiento >= NOW() - INTERVAL '90 days'
GROUP BY k.fecha_movimiento::DATE,
         COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)'),
         k.estanque_id, e.codigo, e.nombre;

COMMENT ON VIEW v_combustible_demanda_externa_diaria IS
    'Demanda diaria por cliente: TODAS las ventas (salida_venta + salida_externa, cualquier empresa). Excluye consumo propio, recirculaciones y traspasos. Ultimos 90 dias. MIG122.';


-- ── 2. Resumen promedio diario por estanque (ventanas) ──────────────────────
DROP VIEW IF EXISTS v_combustible_demanda_externa_resumen CASCADE;
CREATE VIEW v_combustible_demanda_externa_resumen AS
WITH ventanas AS (
    SELECT
        k.estanque_id,
        -- Ultimos 7 dias
        SUM(CASE WHEN k.fecha_movimiento >= NOW() - INTERVAL '7 days'
                 THEN k.litros_salida ELSE 0 END)         AS litros_7d,
        COUNT(*) FILTER (WHERE k.fecha_movimiento >= NOW() - INTERVAL '7 days') AS despachos_7d,
        -- Ultimos 30 dias
        SUM(CASE WHEN k.fecha_movimiento >= NOW() - INTERVAL '30 days'
                 THEN k.litros_salida ELSE 0 END)         AS litros_30d,
        COUNT(*) FILTER (WHERE k.fecha_movimiento >= NOW() - INTERVAL '30 days') AS despachos_30d,
        -- Hoy
        SUM(CASE WHEN k.fecha_movimiento::DATE = CURRENT_DATE
                 THEN k.litros_salida ELSE 0 END)         AS litros_hoy,
        COUNT(*) FILTER (WHERE k.fecha_movimiento::DATE = CURRENT_DATE) AS despachos_hoy
    FROM combustible_kardex_valorizado k
    WHERE k.tipo_movimiento IN ('salida_venta','salida_externa')
      AND k.litros_salida > 0
    GROUP BY k.estanque_id
)
SELECT
    e.id                                  AS estanque_id,
    e.codigo                              AS estanque_codigo,
    e.nombre                              AS estanque_nombre,
    e.capacidad_lt,
    e.stock_teorico_lt                    AS stock_actual,
    e.stock_minimo_alerta_lt              AS stock_minimo,
    COALESCE(v.litros_hoy, 0)             AS litros_hoy,
    COALESCE(v.despachos_hoy, 0)          AS despachos_hoy,
    COALESCE(v.litros_7d, 0)              AS litros_ultimos_7d,
    COALESCE(v.despachos_7d, 0)           AS despachos_ultimos_7d,
    COALESCE(v.litros_30d, 0)             AS litros_ultimos_30d,
    COALESCE(v.despachos_30d, 0)          AS despachos_ultimos_30d,
    ROUND(COALESCE(v.litros_7d, 0) / 7.0, 1)   AS promedio_diario_7d,
    ROUND(COALESCE(v.litros_30d, 0) / 30.0, 1) AS promedio_diario_30d
FROM combustible_estanques e
LEFT JOIN ventanas v ON v.estanque_id = e.id
WHERE e.activo = true;

COMMENT ON VIEW v_combustible_demanda_externa_resumen IS
    'Resumen demanda por estanque: litros hoy / 7d / 30d. TODAS las ventas a clientes. Excluye consumo propio, recirculaciones y traspasos. MIG122.';


-- ── 3. Proyeccion: dias de cobertura + fecha estimada de agotamiento ───────
DROP VIEW IF EXISTS v_combustible_proyeccion_stock CASCADE;
CREATE VIEW v_combustible_proyeccion_stock AS
SELECT
    r.*,
    -- Usar el promedio de 7 dias como base (mas representativo de la tendencia reciente).
    -- Si 7d=0 pero 30d>0, usar 30d para no devolver NULL infinito.
    CASE
        WHEN r.promedio_diario_7d > 0  THEN ROUND(r.stock_actual / r.promedio_diario_7d,  1)
        WHEN r.promedio_diario_30d > 0 THEN ROUND(r.stock_actual / r.promedio_diario_30d, 1)
        ELSE NULL
    END                                                       AS dias_cobertura,
    CASE
        WHEN r.promedio_diario_7d > 0  THEN (CURRENT_DATE + (r.stock_actual / r.promedio_diario_7d)::INT)
        WHEN r.promedio_diario_30d > 0 THEN (CURRENT_DATE + (r.stock_actual / r.promedio_diario_30d)::INT)
        ELSE NULL
    END                                                       AS fecha_agotamiento_estimada,
    -- Cuanto falta para llegar al stock_minimo de alerta
    CASE
        WHEN r.promedio_diario_7d > 0 AND r.stock_minimo > 0 AND r.stock_actual > r.stock_minimo
            THEN ROUND((r.stock_actual - r.stock_minimo) / r.promedio_diario_7d, 1)
        ELSE NULL
    END                                                       AS dias_hasta_minimo,
    -- Demanda promedio que usa la proyeccion (para que la UI muestre cual ventana)
    COALESCE(r.promedio_diario_7d, r.promedio_diario_30d, 0)  AS demanda_base_diaria,
    CASE
        WHEN r.promedio_diario_7d > 0  THEN '7d'
        WHEN r.promedio_diario_30d > 0 THEN '30d'
        ELSE 'sin_datos'
    END                                                       AS ventana_usada,
    -- Severidad para colorear UI
    CASE
        WHEN r.stock_actual <= 0                                              THEN 'agotado'
        WHEN r.stock_actual <= r.stock_minimo                                 THEN 'critico'
        WHEN r.promedio_diario_7d > 0
             AND (r.stock_actual / r.promedio_diario_7d) <= 3                 THEN 'urgente'
        WHEN r.promedio_diario_7d > 0
             AND (r.stock_actual / r.promedio_diario_7d) <= 7                 THEN 'atencion'
        ELSE                                                                       'ok'
    END                                                       AS severidad
FROM v_combustible_demanda_externa_resumen r;

COMMENT ON VIEW v_combustible_proyeccion_stock IS
    'Proyeccion: dias_cobertura, fecha_agotamiento_estimada, dias_hasta_minimo. Basado en TODAS las ventas a clientes (no solo MYG+LISSET). MIG122.';


GRANT SELECT ON v_combustible_demanda_externa_diaria   TO authenticated;
GRANT SELECT ON v_combustible_demanda_externa_resumen  TO authenticated;
GRANT SELECT ON v_combustible_proyeccion_stock         TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
SELECT * FROM v_combustible_proyeccion_stock ORDER BY severidad, estanque_codigo;

NOTIFY pgrst, 'reload schema';
