-- ============================================================================
-- 84_taller_vistas_kpi.sql
-- ----------------------------------------------------------------------------
-- Vistas para dashboard supervisor y reporteria del plan semanal taller.
--
-- Crea:
--   1. v_taller_plan_semanal_ots_full  -- una fila por jornada con OT/activo/responsable
--   2. v_taller_kpi_semanal            -- % planificado, % ejecutado, % atraso por semana
--   3. v_taller_cumplimiento_pm_mes    -- cumplimiento PM por mes (curva S)
--   4. v_taller_ot_backlog             -- OTs candidatas a planificar (sin jornada en semana actual)
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Vista enriquecida de jornadas planificadas ──────────────────────────
DROP VIEW IF EXISTS v_taller_plan_semanal_ots_full CASCADE;
CREATE VIEW v_taller_plan_semanal_ots_full AS
SELECT
    t.id                            AS plan_ot_id,
    t.plan_semanal_id,
    t.plan_dia_id,
    d.fecha                         AS dia_fecha,
    d.nombre_dia                    AS dia_nombre,
    d.orden                         AS dia_orden,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado                       AS plan_estado,
    t.ot_id,
    ot.folio                        AS ot_folio,
    ot.tipo                         AS ot_tipo,
    ot.estado                       AS ot_estado,
    ot.prioridad                    AS ot_prioridad,
    ot.fecha_programada             AS ot_fecha_programada,
    ot.plan_mantenimiento_id,
    pm.nombre                       AS pm_nombre,
    pm.proxima_ejecucion_fecha      AS pm_proxima_fecha,
    ot.activo_id,
    a.codigo                        AS activo_codigo,
    a.nombre                        AS activo_nombre,
    a.patente                       AS activo_patente,
    a.tipo                          AS activo_tipo,
    ot.faena_id,
    f.nombre                        AS faena_nombre,
    ot.contrato_id,
    c.codigo                        AS contrato_codigo,
    c.cliente                       AS contrato_cliente,
    t.responsable_id,
    up.nombre_completo              AS responsable,
    t.cuadrilla,
    t.horas_planificadas,
    t.avance_objetivo_pct,
    t.secuencia_jornada,
    t.estado_plan                   AS jornada_estado,
    t.observaciones,
    -- Ejecucion activa (si existe)
    (SELECT id FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada')
       LIMIT 1)                     AS ejecucion_activa_id,
    (SELECT estado FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada')
       LIMIT 1)                     AS ejecucion_activa_estado,
    -- Avance acumulado (ultima ejecucion finalizada)
    (SELECT avance_final FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado = 'finalizada'
       ORDER BY finished_at DESC LIMIT 1) AS ultima_ejecucion_avance,
    t.created_at,
    t.updated_at
FROM taller_plan_semanal_ots t
JOIN taller_plan_semanal_dias d        ON d.id = t.plan_dia_id
JOIN taller_planes_semanales ps         ON ps.id = t.plan_semanal_id
JOIN ordenes_trabajo ot                 ON ot.id = t.ot_id
LEFT JOIN planes_mantenimiento pm       ON pm.id = ot.plan_mantenimiento_id
LEFT JOIN activos a                     ON a.id = ot.activo_id
LEFT JOIN faenas f                      ON f.id = ot.faena_id
LEFT JOIN contratos c                   ON c.id = ot.contrato_id
LEFT JOIN usuarios_perfil up            ON up.id = t.responsable_id;

COMMENT ON VIEW v_taller_plan_semanal_ots_full IS
    'Jornadas planificadas con OT, activo, responsable y ejecucion activa. MIG84.';


-- ── 2. KPI por semana ──────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_taller_kpi_semanal CASCADE;
CREATE VIEW v_taller_kpi_semanal AS
SELECT
    ps.id                                 AS plan_semanal_id,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado                             AS plan_estado,
    ps.faena_id,
    COUNT(t.id)                           AS jornadas_planificadas,
    COUNT(t.id) FILTER (WHERE t.estado_plan = 'finalizada') AS jornadas_finalizadas,
    COUNT(t.id) FILTER (WHERE t.estado_plan IN ('en_ejecucion','pausada')) AS jornadas_en_ejecucion,
    COUNT(t.id) FILTER (WHERE t.estado_plan IN ('planificada','asignada','liberada')) AS jornadas_pendientes,
    COUNT(t.id) FILTER (WHERE t.estado_plan = 'no_ejecutada') AS jornadas_no_ejecutadas,
    COUNT(DISTINCT t.ot_id)               AS ots_unicas,
    COUNT(DISTINCT ot.activo_id) FILTER (WHERE ot.activo_id IS NOT NULL) AS activos_intervenidos,
    COALESCE(SUM(t.horas_planificadas), 0) AS horas_planificadas,
    COALESCE(SUM(
        CASE WHEN e.tiempo_efectivo_segundos IS NOT NULL
             THEN e.tiempo_efectivo_segundos::NUMERIC / 3600.0
             ELSE 0 END
    ), 0)                                  AS horas_reales,
    CASE WHEN COUNT(t.id) > 0
         THEN ROUND(COUNT(t.id) FILTER (WHERE t.estado_plan = 'finalizada')::NUMERIC * 100 / COUNT(t.id), 1)
         ELSE 0 END                        AS cumplimiento_pct,
    COUNT(t.id) FILTER (WHERE d.fecha < CURRENT_DATE
                          AND t.estado_plan IN ('planificada','asignada','liberada','pausada')) AS jornadas_atrasadas
FROM taller_planes_semanales ps
LEFT JOIN taller_plan_semanal_ots t ON t.plan_semanal_id = ps.id
LEFT JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
LEFT JOIN ordenes_trabajo ot ON ot.id = t.ot_id
LEFT JOIN LATERAL (
    SELECT SUM(tiempo_efectivo_segundos) AS tiempo_efectivo_segundos
      FROM taller_ot_ejecuciones
     WHERE ot_id = t.ot_id AND estado = 'finalizada'
) e ON true
GROUP BY ps.id, ps.fecha_inicio_semana, ps.fecha_fin_semana, ps.estado, ps.faena_id;

COMMENT ON VIEW v_taller_kpi_semanal IS
    'KPI por plan semanal: cumplimiento, atrasos, horas plan vs real. MIG84.';


-- ── 3. Cumplimiento PM mensual (curva S) ───────────────────────────────────
DROP VIEW IF EXISTS v_taller_cumplimiento_pm_mes CASCADE;
CREATE VIEW v_taller_cumplimiento_pm_mes AS
SELECT
    DATE_TRUNC('month', COALESCE(ot.fecha_termino, ot.fecha_programada, ot.created_at))::DATE AS mes,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo')                AS pm_total,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo'
                                    AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')) AS pm_completados,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo'
                                    AND ot.estado = 'no_ejecutada')             AS pm_no_ejecutados,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'correctivo')                AS correctivos_total,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'correctivo'
                                    AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')) AS correctivos_completados,
    CASE WHEN COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo') > 0
         THEN ROUND(
              COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo'
                                              AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada'))::NUMERIC
              * 100 / NULLIF(COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo'), 0)
         , 1)
         ELSE 0 END                                                             AS cumplimiento_pm_pct
FROM ordenes_trabajo ot
WHERE ot.created_at >= NOW() - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', COALESCE(ot.fecha_termino, ot.fecha_programada, ot.created_at))
ORDER BY mes DESC;

COMMENT ON VIEW v_taller_cumplimiento_pm_mes IS
    'Cumplimiento PM mensual (ultimos 12 meses). Curva S. MIG84.';


-- ── 4. Backlog: OTs candidatas a planificar (no estan en plan semanal actual) ─
DROP VIEW IF EXISTS v_taller_ot_backlog CASCADE;
CREATE VIEW v_taller_ot_backlog AS
SELECT
    ot.id                       AS ot_id,
    ot.folio                    AS ot_folio,
    ot.tipo                     AS ot_tipo,
    ot.estado                   AS ot_estado,
    ot.prioridad                AS ot_prioridad,
    ot.fecha_programada,
    ot.activo_id,
    a.codigo                    AS activo_codigo,
    a.nombre                    AS activo_nombre,
    a.patente                   AS activo_patente,
    ot.faena_id,
    f.nombre                    AS faena_nombre,
    ot.contrato_id,
    c.codigo                    AS contrato_codigo,
    c.cliente                   AS contrato_cliente,
    ot.plan_mantenimiento_id,
    pm.nombre                   AS pm_nombre,
    pm.proxima_ejecucion_fecha,
    ot.responsable_id,
    up.nombre_completo          AS responsable_actual,
    ot.observaciones,
    ot.created_at
FROM ordenes_trabajo ot
LEFT JOIN activos a              ON a.id = ot.activo_id
LEFT JOIN faenas f               ON f.id = ot.faena_id
LEFT JOIN contratos c            ON c.id = ot.contrato_id
LEFT JOIN planes_mantenimiento pm ON pm.id = ot.plan_mantenimiento_id
LEFT JOIN usuarios_perfil up     ON up.id = ot.responsable_id
WHERE ot.estado IN ('creada','asignada','pausada')
ORDER BY
    CASE ot.prioridad
        WHEN 'emergencia' THEN 1
        WHEN 'urgente'    THEN 2
        WHEN 'alta'       THEN 3
        WHEN 'normal'     THEN 4
        WHEN 'baja'       THEN 5
        ELSE 9 END,
    ot.fecha_programada NULLS LAST;

COMMENT ON VIEW v_taller_ot_backlog IS
    'OTs creadas/asignadas/pausadas. Candidatas a programar en el plan semanal. MIG84.';


GRANT SELECT ON v_taller_plan_semanal_ots_full   TO authenticated;
GRANT SELECT ON v_taller_kpi_semanal             TO authenticated;
GRANT SELECT ON v_taller_cumplimiento_pm_mes     TO authenticated;
GRANT SELECT ON v_taller_ot_backlog              TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM information_schema.views
     WHERE table_schema='public' AND table_name LIKE 'v_taller_%';
    IF v_count < 4 THEN
        RAISE EXCEPTION 'STOP - faltan vistas v_taller_*. Creadas: %', v_count;
    END IF;
    RAISE NOTICE '== MIG84 OK == % vistas v_taller_* creadas', v_count;
END $$;

NOTIFY pgrst, 'reload schema';
