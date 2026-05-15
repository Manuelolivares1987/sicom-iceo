-- ============================================================================
-- 46_calama_curva_s_por_conteo.sql
-- ----------------------------------------------------------------------------
-- Vista nueva v_calama_curva_s_conteo: curva diaria con las 3 metricas
-- oficiales (MIG34/35) reconstruidas a fecha X.
--
-- Las 3 metricas (frontend convertira a %):
--   - completitud  = finalizadas_acum     / total_ots
--   - real         = (finalizadas + en_ejecucion_acum) / total_ots
--   - proyectado   = (finalizadas + en_ejecucion + planificadas_acum) / total_ots
--
-- "AL FIN DEL DIA X":
--   - finalizadas_acum  = OTs cuya jornada se cerro en fecha <= X
--     (cierre_jornada_at de MIG33)
--   - en_ejecucion_acum = OTs con llegada_faena en fecha <= X pero sin cierre
--     todavia a esa fecha (en_ejecucion / parcial / pendiente_aprobacion /
--     requiere_correccion son los estados visibles antes de cerrar)
--   - planificadas_acum = OTs con jornada visible (no desprogramada / no
--     anulada / visible_en_kanban=true) en plan_dia.fecha <= X y AUN sin
--     haber llegado a faena ni cerrado
--
-- Total = OTs no canceladas en la planificacion (snapshot actual).
--
-- La vista NO sobrescribe v_calama_curva_s (mig 17). Conviven; el frontend
-- elige cual usar.
--
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE VIEW).
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public'
           AND table_name='calama_plan_semanal_ots'
           AND column_name='cierre_jornada_at'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG33 no aplicada (falta cierre_jornada_at).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public'
           AND table_name='calama_plan_semanal_ots'
           AND column_name='llegada_faena_at'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG32 no aplicada (falta llegada_faena_at).';
    END IF;
END $$;


-- ── Vista ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_calama_curva_s_conteo AS
WITH
fechas AS (
    -- Rango de fechas por planificacion.
    SELECT p.id AS planificacion_id,
           p.codigo,
           gs.fecha::DATE AS fecha
      FROM calama_planificaciones p
      CROSS JOIN LATERAL generate_series(
          p.fecha_inicio_plan,
          p.fecha_termino_plan,
          '1 day'::interval
      ) AS gs(fecha)
),
totales AS (
    SELECT planificacion_id,
           COUNT(*) FILTER (WHERE estado <> 'cancelada') AS total_ots
      FROM calama_ordenes_trabajo
     WHERE es_prueba = false
     GROUP BY planificacion_id
),
estados_por_ot AS (
    -- Para cada OT no cancelada y no de prueba, calcula:
    --   fecha_finalizada  = primera fecha en que cualquier jornada cerro
    --   fecha_inicio      = primera fecha en que el operador llego a faena
    --   fecha_planificada = primera fecha de plan_dia con jornada visible
    SELECT
        o.id AS ot_id,
        o.planificacion_id,
        MIN(po.cierre_jornada_at::DATE) AS fecha_finalizada,
        MIN(po.llegada_faena_at::DATE)  AS fecha_inicio,
        MIN(d.fecha) FILTER (
            WHERE po.visible_en_kanban = true
              AND po.desprogramada_at IS NULL
              AND po.anulada_at IS NULL
              AND po.estado_plan NOT IN (
                  'desprogramada','anulada_prueba','cancelada_operacional',
                  'no_ejecutada','reprogramada'
              )
        ) AS fecha_planificada
      FROM calama_ordenes_trabajo o
      LEFT JOIN calama_plan_semanal_ots po ON po.ot_id = o.id
      LEFT JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
     WHERE o.estado <> 'cancelada'
       AND o.es_prueba = false
     GROUP BY o.id, o.planificacion_id
),
conteos AS (
    SELECT
        f.planificacion_id,
        f.codigo,
        f.fecha,
        COALESCE(t.total_ots, 0) AS total_ots,
        COUNT(*) FILTER (
            WHERE e.fecha_finalizada IS NOT NULL
              AND e.fecha_finalizada <= f.fecha
        ) AS finalizadas_acum,
        COUNT(*) FILTER (
            WHERE e.fecha_inicio IS NOT NULL
              AND e.fecha_inicio <= f.fecha
              AND (e.fecha_finalizada IS NULL OR e.fecha_finalizada > f.fecha)
        ) AS en_ejecucion_acum,
        COUNT(*) FILTER (
            WHERE e.fecha_planificada IS NOT NULL
              AND e.fecha_planificada <= f.fecha
              AND (e.fecha_inicio IS NULL OR e.fecha_inicio > f.fecha)
              AND (e.fecha_finalizada IS NULL OR e.fecha_finalizada > f.fecha)
        ) AS planificadas_acum
      FROM fechas f
      LEFT JOIN totales t        ON t.planificacion_id = f.planificacion_id
      LEFT JOIN estados_por_ot e ON e.planificacion_id = f.planificacion_id
     GROUP BY f.planificacion_id, f.codigo, f.fecha, t.total_ots
)
SELECT
    planificacion_id,
    codigo,
    fecha,
    total_ots,
    finalizadas_acum,
    en_ejecucion_acum,
    planificadas_acum,
    -- Avance plan: lineal entre dia_actual / total_dias (mismo criterio
    -- que v_calama_curva_s de MIG17, util para banda de referencia).
    ROUND(
        100.0 * (fecha - (SELECT fecha_inicio_plan FROM calama_planificaciones
                           WHERE id = conteos.planificacion_id))
              / NULLIF((SELECT (fecha_termino_plan - fecha_inicio_plan)
                          FROM calama_planificaciones
                         WHERE id = conteos.planificacion_id), 0),
        2
    ) AS avance_plan_pct,
    -- Las 3 metricas oficiales.
    CASE WHEN total_ots = 0 THEN 0
         ELSE ROUND(100.0 * finalizadas_acum / total_ots, 2) END
        AS completitud_pct,
    CASE WHEN total_ots = 0 THEN 0
         ELSE ROUND(100.0 * (finalizadas_acum + en_ejecucion_acum) / total_ots, 2) END
        AS real_pct,
    CASE WHEN total_ots = 0 THEN 0
         ELSE ROUND(100.0 * (finalizadas_acum + en_ejecucion_acum + planificadas_acum)
                           / total_ots, 2) END
        AS proyectado_pct
  FROM conteos
 ORDER BY planificacion_id, fecha;

COMMENT ON VIEW v_calama_curva_s_conteo IS
'MIG46 - Curva S diaria por conteo de OTs (3 metricas oficiales MIG34/35: completitud, real, proyectado) + banda plan lineal. Excluye OTs de prueba y canceladas. Series por planificacion_id.';

GRANT SELECT ON v_calama_curva_s_conteo TO authenticated;

NOTIFY pgrst, 'reload schema';
