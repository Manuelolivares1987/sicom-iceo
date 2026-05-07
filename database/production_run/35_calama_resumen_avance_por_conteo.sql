-- ============================================================================
-- 35_calama_resumen_avance_por_conteo.sql
-- ----------------------------------------------------------------------------
-- Reescribe las 3 metricas de avance segun la regla operacional del usuario:
--
--   1. avance_completitud_pct  = Finalizadas / Total
--      "Avance terminado" - cuantas OTs YA estan listas.
--
--   2. avance_real_pct          = (Finalizadas + En ejecucion) / Total
--      "Avance real" - cuantas OTs estan AVANZADAS o ya terminadas.
--
--   3. avance_proyectado_pct    = (Finalizadas + En ejecucion + Planif. semana) / Total
--      "Avance proyectado" - hasta donde llegariamos si todas las planificadas
--      esta semana se ejecutan.
--
-- Donde:
--   Finalizadas       = estado IN (finalizada, aceptada, cerrada)
--   En ejecucion      = estado IN (en_ejecucion, en_pausa, parcial,
--                                  pendiente_aprobacion, requiere_correccion)
--   Planif. semana    = OTs en calama_plan_semanal_ots activas (visibles, no
--                       desprogramadas, no anuladas) que NO esten ya en
--                       finalizadas ni en ejecucion.
--   Total             = OTs activas (estado <> cancelada).
--
-- avance_promedio_pct (AVG simple del avance_pct) se conserva para compat
-- pero no se usa en la UI principal.
--
-- IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_calama_resumen_general') THEN
        RAISE EXCEPTION 'STOP - MIG21/MIG34 no aplicadas';
    END IF;
END $$;


-- ============================================================================
-- ── 1. v_calama_avance_por_area (rebuild) ──────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_avance_por_area CASCADE;
CREATE VIEW v_calama_avance_por_area AS
WITH ot_zona AS (
    SELECT
        o.id, o.planificacion_id, o.estado, o.avance_pct, o.fecha_programada,
        o.observaciones_apertura, o.observaciones_cierre,
        fn_calama_zona_codigo_de_folio(o.folio) AS codigo_zona
    FROM calama_ordenes_trabajo o
),
plan_ots_resumen AS (
    SELECT
        po.plan_semanal_id, po.ot_id, po.responsable_id, po.estado_plan,
        po.observaciones, po.plan_dia_id,
        ps.planificacion_id
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
    WHERE COALESCE(po.visible_en_kanban, true) = true
      AND po.desprogramada_at IS NULL
      AND po.anulada_at IS NULL
)
SELECT
    p.id                                                    AS planificacion_id,
    p.codigo                                                AS planificacion_codigo,
    z.codigo_zona,
    z.nombre                                                AS lugar_fisico_nombre,
    z.id                                                    AS zona_proyecto_id,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada')      AS total_tareas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                            AS tareas_finalizadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                            AS tareas_en_ejecucion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                            AS tareas_pendientes,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'no_ejecutada')    AS tareas_no_ejecutadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')
                                                            AS tareas_pendiente_aprobacion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'parcial') AS tareas_parciales,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'requiere_correccion')
                                                            AS tareas_requiere_correccion,
    COUNT(DISTINCT po.ot_id)                                AS tareas_planificadas_semana,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                            AS tareas_sin_responsable,
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                        AS tareas_con_comentario,

    -- Avance promedio simple (legacy, no se muestra en UI principal).
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_promedio_pct,

    -- ── Las 3 metricas por CONTEO de OTs ──
    -- (a) Completitud: solo finalizadas / total
    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_completitud_pct,

    -- (b) Real: (finalizadas + en ejecucion) / total
    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (
                WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                   'en_ejecucion','en_pausa','parcial',
                                   'pendiente_aprobacion','requiere_correccion')
            )::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_real_pct,

    -- (c) Proyectado: (finalizadas + en ejecucion + planificadas-semana NO ya contadas) / total
    ROUND(
        COALESCE(
            (
                COUNT(DISTINCT o.id) FILTER (
                    WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                       'en_ejecucion','en_pausa','parcial',
                                       'pendiente_aprobacion','requiere_correccion')
                )::numeric
                + COUNT(DISTINCT po.ot_id) FILTER (
                    WHERE po.ot_id IS NOT NULL
                      AND o.estado NOT IN ('finalizada','aceptada','cerrada',
                                           'en_ejecucion','en_pausa','parcial',
                                           'pendiente_aprobacion','requiere_correccion','cancelada')
                )::numeric
            ) * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_proyectado_pct
FROM calama_zonas_proyecto z
JOIN calama_planificaciones p ON p.id = z.planificacion_id
LEFT JOIN ot_zona o ON o.planificacion_id = p.id AND o.codigo_zona = z.codigo_zona
LEFT JOIN plan_ots_resumen po ON po.ot_id = o.id AND po.planificacion_id = p.id
GROUP BY p.id, p.codigo, z.id, z.codigo_zona, z.nombre
ORDER BY p.codigo, z.codigo_zona;

GRANT SELECT ON v_calama_avance_por_area TO authenticated;
COMMENT ON VIEW v_calama_avance_por_area IS
    'MIG35: avance por area con 3 metricas de avance por conteo de OTs.';


-- ============================================================================
-- ── 2. v_calama_resumen_general (rebuild) ──────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_resumen_general CASCADE;
CREATE VIEW v_calama_resumen_general AS
WITH ots AS (
    SELECT
        o.planificacion_id, o.id, o.estado, o.avance_pct,
        o.observaciones_apertura, o.observaciones_cierre
    FROM calama_ordenes_trabajo o
),
plan_ots AS (
    SELECT
        ps.planificacion_id, po.ot_id, po.responsable_id,
        po.observaciones, po.estado_plan
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
    WHERE COALESCE(po.visible_en_kanban, true) = true
      AND po.desprogramada_at IS NULL
      AND po.anulada_at IS NULL
),
zonas AS (
    SELECT planificacion_id, COUNT(*)::int AS total_zonas
    FROM calama_zonas_proyecto GROUP BY planificacion_id
)
SELECT
    p.id                                              AS planificacion_id,
    p.codigo                                          AS planificacion_codigo,
    p.nombre                                          AS planificacion_nombre,
    p.linea_negocio,
    p.estado                                          AS estado_planificacion,
    COALESCE(z.total_zonas, 0)                        AS total_lugares_fisicos,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada')  AS total_tareas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'cancelada')   AS tareas_canceladas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                                  AS tareas_finalizadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                                  AS tareas_en_ejecucion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                                  AS tareas_pendientes,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'no_ejecutada') AS tareas_no_ejecutadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')  AS tareas_pendiente_aprobacion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'parcial')      AS tareas_parciales,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'requiere_correccion')   AS tareas_requiere_correccion,
    COUNT(DISTINCT po.ot_id)                                       AS tareas_planificadas_semanas,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                                  AS tareas_sin_responsable,
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                              AS tareas_con_comentario,

    -- Legacy (AVG simple): para compat con consumidores viejos.
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                                  AS avance_promedio_pct,

    -- ── Las 3 metricas por CONTEO de OTs (regla operacional) ──
    -- (a) Completitud: solo finalizadas / total
    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_completitud_pct,

    -- (b) Real: (finalizadas + en ejecucion) / total
    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (
                WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                   'en_ejecucion','en_pausa','parcial',
                                   'pendiente_aprobacion','requiere_correccion')
            )::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_real_pct,

    -- (c) Proyectado: (finalizadas + en ejecucion + planif-semana sin solapar) / total
    ROUND(
        COALESCE(
            (
                COUNT(DISTINCT o.id) FILTER (
                    WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                       'en_ejecucion','en_pausa','parcial',
                                       'pendiente_aprobacion','requiere_correccion')
                )::numeric
                + COUNT(DISTINCT po.ot_id) FILTER (
                    WHERE po.ot_id IS NOT NULL
                      AND o.estado NOT IN ('finalizada','aceptada','cerrada',
                                           'en_ejecucion','en_pausa','parcial',
                                           'pendiente_aprobacion','requiere_correccion','cancelada')
                )::numeric
            ) * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_proyectado_pct
FROM calama_planificaciones p
LEFT JOIN zonas    z ON z.planificacion_id = p.id
LEFT JOIN ots      o ON o.planificacion_id = p.id
LEFT JOIN plan_ots po ON po.planificacion_id = p.id AND po.ot_id = o.id
GROUP BY p.id, p.codigo, p.nombre, p.linea_negocio, p.estado, z.total_zonas
ORDER BY p.codigo;

GRANT SELECT ON v_calama_resumen_general TO authenticated;
COMMENT ON VIEW v_calama_resumen_general IS
    'MIG35: 3 metricas de avance por CONTEO de OTs (completitud / real / proyectado).';


-- ============================================================================
-- BITACORA + verificacion
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG35_CALAMA_AVANCE_CONTEO',
            'MIG35: avance_completitud / avance_real / avance_proyectado por conteo de OTs (no AVG).',
            current_user, NOW(), NOW(), 'ok',
            'avance_completitud = finalizadas/total. avance_real = (finalizadas+en_ejecucion)/total. avance_proyectado = (finalizadas+en_ejecucion+planif_semana)/total.'
        );
    END IF;
END $$;

WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_resumen_general' AND column_name='avance_real_pct')        AS rg_real,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_resumen_general' AND column_name='avance_proyectado_pct') AS rg_proy,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_avance_por_area' AND column_name='avance_real_pct')        AS area_real
)
SELECT
    CASE
        WHEN NOT rg_real    THEN 'STOP_RG_REAL'
        WHEN NOT rg_proy    THEN 'STOP_RG_PROYECTADO'
        WHEN NOT area_real  THEN 'STOP_AREA_REAL'
        ELSE 'OK_MIG35_AVANCE_CONTEO'
    END AS resultado,
    rg_real, rg_proy, area_real,
    NOW() AS chequeado_en
FROM chk;
