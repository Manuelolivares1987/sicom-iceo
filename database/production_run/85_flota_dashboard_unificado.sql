-- ============================================================================
-- 85_flota_dashboard_unificado.sql
-- ----------------------------------------------------------------------------
-- Unifica TODOS los indicadores de flota en una sola vista por activo.
-- Antes: 13 paginas + 3 servicios + 12 tablas + 2 calculos distintos de
-- disponibilidad. Imposible tener vision completa de un activo en un solo
-- vistazo.
--
-- Esta migracion crea:
--   1. v_flota_dashboard_unificado   -- 1 fila por activo con TODO
--   2. v_flota_kpi_resumen           -- KPI agregado de toda la flota
--   3. v_flota_alertas_resumen       -- conteo alertas por activo
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Vista unificada: 1 fila por activo ──────────────────────────────────
DROP VIEW IF EXISTS v_flota_dashboard_unificado CASCADE;
CREATE VIEW v_flota_dashboard_unificado AS
WITH ult_estado AS (
    SELECT DISTINCT ON (activo_id)
        activo_id, fecha, estado_codigo, horas_operativas, km_recorridos
    FROM estado_diario_flota
    ORDER BY activo_id, fecha DESC
),
pm_resumen AS (
    SELECT
        activo_id,
        COUNT(*)                                                      AS planes_total,
        COUNT(*) FILTER (WHERE proxima_ejecucion_fecha < CURRENT_DATE) AS planes_vencidos,
        COUNT(*) FILTER (WHERE proxima_ejecucion_fecha BETWEEN CURRENT_DATE AND CURRENT_DATE + 7) AS planes_proxima_semana,
        MIN(proxima_ejecucion_fecha)                                  AS pm_proxima_fecha
    FROM planes_mantenimiento
    WHERE activo_plan = true
    GROUP BY activo_id
),
ot_correctivas_abiertas AS (
    SELECT activo_id, COUNT(*) AS ots_correctivas_abiertas
    FROM ordenes_trabajo
    WHERE tipo = 'correctivo'
      AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
    GROUP BY activo_id
),
alertas_act AS (
    SELECT entidad_id AS activo_id, COUNT(*) AS alertas_activas,
           COUNT(*) FILTER (WHERE severidad = 'critical') AS alertas_criticas
    FROM alertas
    WHERE leida = false AND entidad_tipo = 'activo' AND entidad_id IS NOT NULL
    GROUP BY entidad_id
),
geo_dentro AS (
    -- Esta dentro de la geocerca esperada (faena_cliente del contrato)?
    SELECT
        v.activo_id,
        v.geocerca_id     AS geocerca_esperada_id,
        v.geocerca_nombre AS geocerca_esperada,
        CASE
            WHEN v.geocerca_lat IS NULL OR g.latitud IS NULL THEN NULL
            ELSE (
                fn_distancia_haversine(g.latitud, g.longitud, v.geocerca_lat, v.geocerca_lng)
                    <= v.geocerca_radio_m
            )
        END AS en_zona_esperada
    FROM v_activo_geocerca_esperada v
    LEFT JOIN gps_estado_actual g ON g.activo_id = v.activo_id
)
SELECT
    a.id                                  AS activo_id,
    a.codigo                              AS activo_codigo,
    a.nombre                              AS activo_nombre,
    a.patente,
    a.tipo                                AS activo_tipo,
    a.estado                              AS estado_operacional,
    a.estado_comercial,
    a.operacion,
    a.modelo_id,
    m.nombre                              AS modelo_nombre,
    ma.nombre                             AS modelo_marca,
    a.contrato_id,
    c.codigo                              AS contrato_codigo,
    c.cliente                             AS contrato_cliente,
    a.faena_id,
    f.nombre                              AS faena_nombre,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.anio_fabricacion,

    -- Estado diario (ultimo registrado)
    ue.fecha                              AS estado_ultima_fecha,
    ue.estado_codigo                      AS estado_codigo_hoy,
    ue.horas_operativas                   AS horas_op_ultimo_dia,
    ue.km_recorridos                      AS km_ultimo_dia,

    -- Plan preventivo
    COALESCE(pm.planes_total, 0)          AS pm_planes_total,
    COALESCE(pm.planes_vencidos, 0)       AS pm_planes_vencidos,
    COALESCE(pm.planes_proxima_semana, 0) AS pm_planes_proxima_semana,
    pm.pm_proxima_fecha,
    CASE
        WHEN pm.planes_total IS NULL THEN 'sin_planes'
        WHEN pm.planes_vencidos > 0    THEN 'vencido'
        WHEN pm.planes_proxima_semana > 0 THEN 'proximo'
        ELSE 'al_dia'
    END                                   AS pm_status,

    -- OT correctivas abiertas
    COALESCE(oc.ots_correctivas_abiertas, 0) AS ots_correctivas_abiertas,

    -- Alertas
    COALESCE(al.alertas_activas, 0)       AS alertas_activas,
    COALESCE(al.alertas_criticas, 0)      AS alertas_criticas,

    -- GPS: ultima senal + posicion + estado
    gm.gps_device_id,
    gm.gps_device_name                    AS gps_device_nombre,
    g.ts_gps                              AS gps_ultima_senal,
    EXTRACT(EPOCH FROM (NOW() - g.ts_gps)) / 60        AS gps_minutos_offline,
    g.latitud                             AS gps_lat,
    g.longitud                            AS gps_lng,
    g.velocidad_kmh                       AS gps_velocidad_kmh,
    g.ignicion                            AS gps_ignicion,
    g.movimiento                          AS gps_movimiento,
    g.conexion                            AS gps_conexion,
    g.bateria_pct                         AS gps_bateria_pct,
    CASE
        WHEN gm.gps_device_id IS NULL                          THEN 'sin_gps'
        WHEN g.ts_gps IS NULL                                  THEN 'sin_datos'
        WHEN g.ts_gps < NOW() - INTERVAL '24 hours'            THEN 'sin_senal_24h'
        WHEN g.conexion = 'offline'                            THEN 'offline'
        WHEN g.velocidad_kmh >= 5                              THEN 'en_ruta'
        WHEN g.ignicion = true                                 THEN 'detenido_motor_on'
        ELSE                                                        'detenido'
    END                                   AS gps_estado_pin,

    -- Geocerca esperada y posicion
    gd.geocerca_esperada_id,
    gd.geocerca_esperada,
    gd.en_zona_esperada,

    a.created_at                          AS activo_creado_at,
    a.updated_at                          AS activo_actualizado_at

FROM activos a
LEFT JOIN modelos m                       ON m.id = a.modelo_id
LEFT JOIN marcas ma                       ON ma.id = m.marca_id
LEFT JOIN contratos c                     ON c.id = a.contrato_id
LEFT JOIN faenas f                        ON f.id = a.faena_id
LEFT JOIN ult_estado ue                   ON ue.activo_id = a.id
LEFT JOIN pm_resumen pm                   ON pm.activo_id = a.id
LEFT JOIN ot_correctivas_abiertas oc      ON oc.activo_id = a.id
LEFT JOIN alertas_act al                  ON al.activo_id = a.id
LEFT JOIN gps_activo_mapeo gm             ON gm.activo_id = a.id AND gm.activo = true
LEFT JOIN gps_estado_actual g             ON g.activo_id = a.id
LEFT JOIN geo_dentro gd                   ON gd.activo_id = a.id
WHERE a.estado != 'dado_baja';

COMMENT ON VIEW v_flota_dashboard_unificado IS
    'Una fila por activo activo con TODOS los indicadores: estado, PM, OT, alertas, GPS, geocerca. MIG85.';


-- ── 2. KPI agregado de la flota completa ───────────────────────────────────
DROP VIEW IF EXISTS v_flota_kpi_resumen CASCADE;
CREATE VIEW v_flota_kpi_resumen AS
WITH base AS (SELECT * FROM v_flota_dashboard_unificado)
SELECT
    COUNT(*)                                                AS total_activos,
    COUNT(*) FILTER (WHERE estado_comercial = 'arrendado')  AS arrendados,
    COUNT(*) FILTER (WHERE estado_comercial = 'disponible') AS disponibles,
    COUNT(*) FILTER (WHERE estado_comercial = 'uso_interno') AS uso_interno,
    COUNT(*) FILTER (WHERE estado_comercial = 'leasing')    AS leasing,
    COUNT(*) FILTER (WHERE estado_operacional = 'en_mantenimiento') AS en_mantenimiento,
    COUNT(*) FILTER (WHERE estado_operacional = 'fuera_servicio')   AS fuera_servicio,

    -- Plan preventivo
    COUNT(*) FILTER (WHERE pm_status = 'sin_planes')        AS pm_sin_planes,
    COUNT(*) FILTER (WHERE pm_status = 'vencido')           AS pm_vencidos,
    COUNT(*) FILTER (WHERE pm_status = 'proximo')           AS pm_proximos_7d,
    COUNT(*) FILTER (WHERE pm_status = 'al_dia')            AS pm_al_dia,
    ROUND(
        COUNT(*) FILTER (WHERE pm_status IN ('al_dia','proximo'))::NUMERIC * 100
        / NULLIF(COUNT(*) FILTER (WHERE pm_planes_total > 0), 0), 1
    )                                                        AS pm_cumplimiento_pct,

    -- OT abiertas
    COALESCE(SUM(ots_correctivas_abiertas), 0)              AS correctivas_abiertas_total,

    -- Alertas
    COALESCE(SUM(alertas_activas), 0)                       AS alertas_activas_total,
    COALESCE(SUM(alertas_criticas), 0)                      AS alertas_criticas_total,
    COUNT(*) FILTER (WHERE alertas_criticas > 0)            AS activos_con_alerta_critica,

    -- GPS
    COUNT(*) FILTER (WHERE gps_device_id IS NOT NULL)       AS gps_mapeados,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'sin_senal_24h') AS gps_sin_senal_24h,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'en_ruta')      AS gps_en_ruta,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'detenido_motor_on') AS gps_detenido_motor_on,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'detenido')     AS gps_detenido,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'offline')      AS gps_offline,
    COUNT(*) FILTER (WHERE gps_estado_pin = 'sin_gps')      AS sin_gps,

    -- Geocerca
    COUNT(*) FILTER (WHERE en_zona_esperada = true)         AS en_zona_esperada,
    COUNT(*) FILTER (WHERE en_zona_esperada = false)        AS fuera_zona_esperada,
    COUNT(*) FILTER (WHERE geocerca_esperada_id IS NOT NULL
                       AND en_zona_esperada IS NULL)        AS sin_dato_zona
FROM base;

COMMENT ON VIEW v_flota_kpi_resumen IS
    'KPI agregado de la flota completa: comercial, PM, OT, alertas, GPS, geocercas. MIG85.';


-- ── 3. Resumen alertas por activo (para tabla rapida) ──────────────────────
DROP VIEW IF EXISTS v_flota_alertas_resumen CASCADE;
CREATE VIEW v_flota_alertas_resumen AS
SELECT
    a.id                                  AS activo_id,
    a.codigo                              AS activo_codigo,
    a.patente,
    COUNT(*) FILTER (WHERE al.severidad = 'critical') AS criticas,
    COUNT(*) FILTER (WHERE al.severidad = 'warning')  AS warnings,
    COUNT(*) FILTER (WHERE al.severidad = 'info')     AS infos,
    array_agg(DISTINCT al.tipo) FILTER (WHERE al.leida = false) AS tipos_activos,
    MAX(al.created_at)                    AS ultima_alerta_at
FROM activos a
LEFT JOIN alertas al ON al.entidad_tipo = 'activo' AND al.entidad_id = a.id AND al.leida = false
WHERE a.estado != 'dado_baja'
GROUP BY a.id, a.codigo, a.patente
HAVING COUNT(*) FILTER (WHERE al.id IS NOT NULL) > 0;

COMMENT ON VIEW v_flota_alertas_resumen IS
    'Conteo y tipos de alertas activas por activo. MIG85.';


GRANT SELECT ON v_flota_dashboard_unificado   TO authenticated;
GRANT SELECT ON v_flota_kpi_resumen           TO authenticated;
GRANT SELECT ON v_flota_alertas_resumen       TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_n INT; v_kpi RECORD;
BEGIN
    SELECT COUNT(*) INTO v_n FROM v_flota_dashboard_unificado;
    RAISE NOTICE '== MIG85 OK ==';
    RAISE NOTICE '   v_flota_dashboard_unificado: % activos', v_n;
    SELECT * INTO v_kpi FROM v_flota_kpi_resumen;
    RAISE NOTICE '   GPS mapeados: % / total %', v_kpi.gps_mapeados, v_kpi.total_activos;
    RAISE NOTICE '   PM vencidos: %, PM al dia: %, sin planes: %',
        v_kpi.pm_vencidos, v_kpi.pm_al_dia, v_kpi.pm_sin_planes;
    RAISE NOTICE '   Alertas activas total: %, criticas: %',
        v_kpi.alertas_activas_total, v_kpi.alertas_criticas_total;
END $$;

SELECT * FROM v_flota_kpi_resumen;

NOTIFY pgrst, 'reload schema';
