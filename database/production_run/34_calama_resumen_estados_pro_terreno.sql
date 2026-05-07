-- ============================================================================
-- 34_calama_resumen_estados_pro_terreno.sql
-- ----------------------------------------------------------------------------
-- Corrige las vistas v_calama_resumen_general y v_calama_avance_por_area
-- para que contemplen los estados PRO terreno (MIG29-32):
--   - parcial, pendiente_aprobacion, requiere_correccion (de OT madre)
--   - aceptada, cerrada (cuentan como terminada)
--   - cancelada_operacional / desprogramada / anulada (excluidas del total)
--
-- Tambien:
--   - tareas_con_comentario ahora suma comentarios de plan_semanal_ots Y
--     observaciones_apertura/cierre de la OT madre.
--   - Nuevo campo avance_completitud_pct = % de OTs realmente terminadas
--     (terminadas / total_activas). Es la metrica honesta de cumplimiento.
--   - Mantiene avance_promedio_pct (AVG simple) para compatibilidad.
--
-- IDEMPOTENTE: DROP + CREATE OR REPLACE.
-- ============================================================================

-- ── 0. PRECHECK ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_calama_resumen_general') THEN
        RAISE EXCEPTION 'STOP - v_calama_resumen_general no existe (MIG21 no aplicada)';
    END IF;
END $$;


-- ============================================================================
-- ── 1. v_calama_avance_por_area (rebuild) ──────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_avance_por_area CASCADE;
CREATE VIEW v_calama_avance_por_area AS
WITH ot_zona AS (
    SELECT
        o.id,
        o.planificacion_id,
        o.estado,
        o.avance_pct,
        o.fecha_programada,
        o.observaciones_apertura,
        o.observaciones_cierre,
        fn_calama_zona_codigo_de_folio(o.folio) AS codigo_zona
    FROM calama_ordenes_trabajo o
),
plan_ots_resumen AS (
    SELECT
        po.plan_semanal_id, po.ot_id, po.responsable_id, po.estado_plan,
        po.observaciones, po.plan_dia_id,
        ps.planificacion_id, ps.fecha_inicio_semana, ps.fecha_fin_semana
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
    COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada')      AS total_tareas,
    -- Estados terminales OK
    COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                            AS tareas_finalizadas,
    -- En curso (incluye nuevos PRO terreno)
    COUNT(o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                            AS tareas_en_ejecucion,
    -- Pendientes (no iniciadas)
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                            AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')    AS tareas_no_ejecutadas,
    -- Nuevos KPIs PRO terreno (visibles en UI)
    COUNT(o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')
                                                            AS tareas_pendiente_aprobacion,
    COUNT(o.id) FILTER (WHERE o.estado = 'parcial')         AS tareas_parciales,
    COUNT(o.id) FILTER (WHERE o.estado = 'requiere_correccion')
                                                            AS tareas_requiere_correccion,
    COUNT(po.ot_id)                                         AS tareas_planificadas_semana,
    COUNT(po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                            AS tareas_sin_responsable,
    -- Comentarios: jornada plan_semanal O observaciones de OT madre.
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                        AS tareas_con_comentario,
    -- Avance promedio simple (compat).
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_promedio_pct,
    -- Avance completitud: terminadas / total_activas * 100.
    ROUND(
        COALESCE(
            COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_completitud_pct
FROM calama_zonas_proyecto z
JOIN calama_planificaciones p ON p.id = z.planificacion_id
LEFT JOIN ot_zona o ON o.planificacion_id = p.id AND o.codigo_zona = z.codigo_zona
LEFT JOIN plan_ots_resumen po ON po.ot_id = o.id AND po.planificacion_id = p.id
GROUP BY p.id, p.codigo, z.id, z.codigo_zona, z.nombre
ORDER BY p.codigo, z.codigo_zona;

GRANT SELECT ON v_calama_avance_por_area TO authenticated;
COMMENT ON VIEW v_calama_avance_por_area IS
    'MIG34: Resumen por lugar fisico. Incluye estados PRO terreno y avance_completitud_pct.';


-- ============================================================================
-- ── 2. v_calama_resumen_general (rebuild) ──────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_resumen_general CASCADE;
CREATE VIEW v_calama_resumen_general AS
WITH ots AS (
    SELECT
        o.planificacion_id, o.id, o.estado, o.avance_pct, o.fecha_programada,
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
    COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada')           AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado = 'cancelada')            AS tareas_canceladas,
    -- Terminales OK (suman para "completitud")
    COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                                  AS tareas_finalizadas,
    -- En curso (incluye nuevos PRO terreno)
    COUNT(o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                                  AS tareas_en_ejecucion,
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                                  AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')          AS tareas_no_ejecutadas,
    -- Nuevos KPIs PRO terreno
    COUNT(o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')  AS tareas_pendiente_aprobacion,
    COUNT(o.id) FILTER (WHERE o.estado = 'parcial')               AS tareas_parciales,
    COUNT(o.id) FILTER (WHERE o.estado = 'requiere_correccion')   AS tareas_requiere_correccion,
    COUNT(DISTINCT po.ot_id)                                      AS tareas_planificadas_semanas,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                                  AS tareas_sin_responsable,
    -- Comentarios desde plan_semanal o desde la OT directamente.
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                              AS tareas_con_comentario,
    -- Avance promedio simple (mismo calculo que antes, para compat).
    -- 3 metricas distintas (lo que el usuario quiere ver):
    -- (a) Avance promedio (real): AVG simple del avance_pct de cada OT.
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                                  AS avance_promedio_pct,
    -- (b) Completitud: % de OTs terminadas sobre activas (cuenta solo finalizada/aceptada/cerrada).
    ROUND(
        COALESCE(
            COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_completitud_pct,
    -- (c) Proyectado: terminadas + planificadas-semana se cuentan como 100%; el resto usa avance real.
    --     Subquery escalar para evitar duplicados con LEFT JOIN multidia.
    (
        SELECT ROUND(COALESCE(
            SUM(CASE
                WHEN o2.estado IN ('finalizada','aceptada','cerrada') THEN 100
                WHEN EXISTS (
                    SELECT 1 FROM calama_plan_semanal_ots po2
                    JOIN calama_planes_semanales ps2 ON ps2.id = po2.plan_semanal_id
                    WHERE po2.ot_id = o2.id
                      AND ps2.planificacion_id = p.id
                      AND COALESCE(po2.visible_en_kanban, true) = true
                      AND po2.desprogramada_at IS NULL
                      AND po2.anulada_at IS NULL
                ) AND o2.estado NOT IN ('finalizada','aceptada','cerrada','cancelada')
                    THEN 100
                ELSE COALESCE(o2.avance_pct, 0)
            END)::numeric / NULLIF(COUNT(*), 0)
        , 0)::numeric, 1)
        FROM calama_ordenes_trabajo o2
        WHERE o2.planificacion_id = p.id AND o2.estado <> 'cancelada'
    )                                                              AS avance_proyectado_pct
FROM calama_planificaciones p
LEFT JOIN zonas    z ON z.planificacion_id = p.id
LEFT JOIN ots      o ON o.planificacion_id = p.id
LEFT JOIN plan_ots po ON po.planificacion_id = p.id AND po.ot_id = o.id
GROUP BY p.id, p.codigo, p.nombre, p.linea_negocio, p.estado, z.total_zonas
ORDER BY p.codigo;

GRANT SELECT ON v_calama_resumen_general TO authenticated;
COMMENT ON VIEW v_calama_resumen_general IS
    'MIG34: Resumen general por planificacion. Cuenta estados PRO terreno y agrega avance_completitud_pct.';


-- ============================================================================
-- ── 3. Bitacora ────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG34_CALAMA_RESUMEN_PRO',
            'MIG34: vistas resumen general/area incluyen estados PRO terreno + avance_completitud_pct + comentarios reales.',
            current_user, NOW(), NOW(), 'ok',
            'Aceptada/cerrada cuentan como finalizadas. Parcial/pendiente_aprobacion/requiere_correccion cuentan como en_ejecucion. Comentarios suma plan_semanal+OT.'
        );
    END IF;
END $$;


-- ============================================================================
-- ── 4. Verificacion ────────────────────────────────────────────────────────
-- ============================================================================
WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_resumen_general' AND column_name='avance_completitud_pct') AS rg_completitud,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_resumen_general' AND column_name='avance_proyectado_pct')  AS rg_proyectado,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_resumen_general' AND column_name='tareas_pendiente_aprobacion') AS rg_pend_aprob,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='v_calama_avance_por_area' AND column_name='avance_completitud_pct') AS area_completitud
)
SELECT
    CASE
        WHEN NOT rg_completitud   THEN 'STOP_RESUMEN_COMPLETITUD'
        WHEN NOT rg_proyectado    THEN 'STOP_RESUMEN_PROYECTADO'
        WHEN NOT rg_pend_aprob    THEN 'STOP_RESUMEN_PEND_APROB'
        WHEN NOT area_completitud THEN 'STOP_AREA_COMPLETITUD'
        ELSE 'OK_MIG34_RESUMEN_PRO_TERRENO'
    END AS resultado,
    rg_completitud, rg_proyectado, rg_pend_aprob, area_completitud,
    NOW() AS chequeado_en
FROM chk;
