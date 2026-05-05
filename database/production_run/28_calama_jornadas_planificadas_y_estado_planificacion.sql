-- ============================================================================
-- 28_calama_jornadas_planificadas_y_estado_planificacion.sql
-- ----------------------------------------------------------------------------
-- 1. PLANIFICACION MULTIDIA: permite que una OT tenga multiples jornadas.
-- 2. SEMANTICA estado_planificacion: vista que distingue OTs realmente
--    planificadas (con jornada en plan_semanal_ots) vs solo importadas.
-- 3. VISTAS REPORTE: atrasos, calidad de datos, reporte semanal.
-- 4. RPC para agregar jornada adicional sin reemplazar la existente.
--
-- DIAGNOSTICO:
--   - calama_plan_semanal_ots tiene UNIQUE (plan_semanal_id, ot_id) que
--     IMPIDE planificar la misma OT en varios dias dentro de la semana.
--   - calama_ordenes_trabajo.estado se usaba como "estado planificacion"
--     pero realmente es estado de ejecucion. Confunde reportes.
--   - No habia distinguir entre OT importada (default 'planificada') y OT
--     con jornada real asignada.
--
-- AISLACION:
--   - NO toca otras MIGs ni tablas que no sean calama_plan_semanal_ots.
--   - Cambia un UNIQUE constraint (drop/create), agrega 4 columnas
--     opcionales, crea 4 vistas y 1 RPC.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots') THEN
        RAISE EXCEPTION 'STOP - MIG20 no aplicada (calama_plan_semanal_ots no existe).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. PERMITIR MULTIPLES JORNADAS POR OT ────────────────────────────────────
-- ============================================================================
-- Drop UNIQUE viejo (plan_semanal_id, ot_id) y agregar nuevo
-- (plan_semanal_id, ot_id, plan_dia_id). Asi misma OT puede aparecer en
-- distintos dias dentro de la misma semana.
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'uq_calama_planot'
           AND conrelid = 'public.calama_plan_semanal_ots'::regclass
    ) THEN
        ALTER TABLE calama_plan_semanal_ots DROP CONSTRAINT uq_calama_planot;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'uq_calama_planot_jornada'
           AND conrelid = 'public.calama_plan_semanal_ots'::regclass
    ) THEN
        ALTER TABLE calama_plan_semanal_ots
            ADD CONSTRAINT uq_calama_planot_jornada
            UNIQUE (plan_semanal_id, ot_id, plan_dia_id);
    END IF;
END $$;


-- ============================================================================
-- ── 2. COLUMNAS NUEVAS para jornadas ─────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='horas_planificadas') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN horas_planificadas NUMERIC(5,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='avance_objetivo_pct') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN avance_objetivo_pct NUMERIC(5,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='secuencia_jornada') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN secuencia_jornada INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='reprogramada_desde_id') THEN
        ALTER TABLE calama_plan_semanal_ots
            ADD COLUMN reprogramada_desde_id UUID
            REFERENCES calama_plan_semanal_ots(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='motivo_reprogramacion') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN motivo_reprogramacion TEXT;
    END IF;
END $$;


-- ============================================================================
-- ── 3. RPC: agregar jornada adicional ────────────────────────────────────────
-- ============================================================================
-- A diferencia de rpc_calama_mover_ot_plan_semanal (que MUEVE la jornada
-- existente), esta RPC AGREGA una jornada nueva. Sirve para tareas multidia.
CREATE OR REPLACE FUNCTION rpc_calama_agregar_jornada_ot(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_semanal_id UUID := (p_payload->>'plan_semanal_id')::UUID;
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_fecha DATE := (p_payload->>'fecha')::DATE;
    v_responsable UUID := NULLIF(p_payload->>'responsable_id','')::UUID;
    v_horas NUMERIC := NULLIF(p_payload->>'horas_planificadas','')::NUMERIC;
    v_avance_obj NUMERIC := NULLIF(p_payload->>'avance_objetivo_pct','')::NUMERIC;
    v_comentario TEXT := p_payload->>'comentario';
    v_dia_id UUID;
    v_zona UUID;
    v_secuencia INT;
    v_id UUID;
    v_plan_estado TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para agregar jornada';
    END IF;
    IF v_plan_semanal_id IS NULL OR v_ot_id IS NULL OR v_fecha IS NULL THEN
        RAISE EXCEPTION 'plan_semanal_id, ot_id y fecha son obligatorios';
    END IF;

    SELECT estado INTO v_plan_estado FROM calama_planes_semanales WHERE id = v_plan_semanal_id;
    IF v_plan_estado IS NULL THEN RAISE EXCEPTION 'plan_semanal_id no encontrado'; END IF;
    IF v_plan_estado IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_plan_estado;
    END IF;

    SELECT id INTO v_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_semanal_id AND fecha = v_fecha;
    IF v_dia_id IS NULL THEN RAISE EXCEPTION 'fecha % no pertenece al plan', v_fecha; END IF;

    SELECT z.id INTO v_zona
      FROM calama_ordenes_trabajo o
      JOIN calama_planificaciones p ON p.id = o.planificacion_id
      LEFT JOIN calama_zonas_proyecto z
             ON z.planificacion_id = p.id
            AND z.codigo_zona = (regexp_match(o.folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0'
     WHERE o.id = v_ot_id LIMIT 1;

    SELECT COALESCE(MAX(secuencia_jornada), 0) + 1 INTO v_secuencia
      FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = v_plan_semanal_id AND ot_id = v_ot_id;

    INSERT INTO calama_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id, responsable_id,
        estado_plan, horas_planificadas, avance_objetivo_pct,
        secuencia_jornada, observaciones, created_by
    ) VALUES (
        v_plan_semanal_id, v_dia_id, v_ot_id, v_zona, v_responsable,
        CASE WHEN v_responsable IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
        v_horas, v_avance_obj, v_secuencia, v_comentario, v_uid
    ) RETURNING id INTO v_id;

    -- Sync responsable a OT madre si vino seteado (paridad MIG24)
    IF v_responsable IS NOT NULL THEN
        UPDATE calama_ordenes_trabajo
           SET responsable_id = v_responsable, updated_at = NOW()
         WHERE id = v_ot_id
           AND (responsable_id IS DISTINCT FROM v_responsable);
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_id, 'secuencia', v_secuencia);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_agregar_jornada_ot(jsonb) TO authenticated;


-- ============================================================================
-- ── 4. VISTA: estado_planificacion derivado ──────────────────────────────────
-- ============================================================================
-- Calcula estado_planificacion desde plan_semanal_ots, separado del estado
-- de ejecucion que vive en calama_ordenes_trabajo.estado.
DROP VIEW IF EXISTS public.v_calama_estado_planificacion_ots CASCADE;
CREATE VIEW v_calama_estado_planificacion_ots AS
WITH jornadas AS (
    SELECT
        po.ot_id,
        d.fecha,
        po.estado_plan,
        po.responsable_id
    FROM calama_plan_semanal_ots po
    JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
),
agg AS (
    SELECT
        o.id AS ot_id,
        o.folio,
        o.estado AS estado_ejecucion,
        o.avance_pct,
        o.avance_excel_pct,
        o.fecha_programada,
        o.responsable_id AS responsable_actual,
        COUNT(j.fecha)                                              AS total_jornadas,
        COUNT(j.fecha) FILTER (WHERE j.fecha >  CURRENT_DATE)        AS jornadas_futuras,
        COUNT(j.fecha) FILTER (WHERE j.fecha =  CURRENT_DATE)        AS jornadas_hoy,
        COUNT(j.fecha) FILTER (WHERE j.fecha <  CURRENT_DATE
                                   AND j.estado_plan NOT IN ('finalizada','no_ejecutada','cancelada'))
                                                                    AS jornadas_vencidas,
        MAX(j.fecha) FILTER (WHERE j.fecha <= CURRENT_DATE)          AS ultima_fecha_planificada,
        MIN(j.fecha) FILTER (WHERE j.fecha >= CURRENT_DATE)          AS proxima_fecha_planificada
    FROM calama_ordenes_trabajo o
    LEFT JOIN jornadas j ON j.ot_id = o.id
    GROUP BY o.id
)
SELECT
    a.ot_id,
    a.folio,
    a.estado_ejecucion,
    a.avance_pct,
    a.avance_excel_pct,
    a.fecha_programada,
    a.responsable_actual,
    a.total_jornadas,
    a.jornadas_futuras,
    a.jornadas_hoy,
    a.jornadas_vencidas,
    a.ultima_fecha_planificada,
    a.proxima_fecha_planificada,
    CASE
        WHEN a.estado_ejecucion = 'cancelada'                       THEN 'cancelada'
        WHEN a.estado_ejecucion = 'finalizada'                      THEN 'ejecutada'
        WHEN a.total_jornadas = 0                                   THEN 'no_planificada'
        WHEN a.jornadas_vencidas > 0 AND a.jornadas_futuras = 0
             AND a.jornadas_hoy = 0                                 THEN 'vencida'
        WHEN a.jornadas_futuras > 0 OR a.jornadas_hoy > 0           THEN 'planificada'
        WHEN a.avance_pct > 0 AND a.avance_pct < 100
             AND a.jornadas_futuras = 0                             THEN 'parcial_sin_proxima_jornada'
        ELSE 'planificada'
    END AS estado_planificacion
FROM agg a;

COMMENT ON VIEW v_calama_estado_planificacion_ots IS
    'Estado de planificacion derivado de plan_semanal_ots, separado del estado de ejecucion.';


-- ============================================================================
-- ── 5. VISTA: reporte de atrasos ─────────────────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_reporte_atrasos CASCADE;
CREATE VIEW v_calama_reporte_atrasos AS
SELECT
    po.id                                                AS plan_ot_id,
    po.ot_id,
    o.folio,
    fn_calama_zona_codigo_de_folio(o.folio)             AS codigo_zona,
    z.nombre                                             AS lugar_fisico,
    o.titulo,
    d.fecha                                              AS fecha_jornada,
    (CURRENT_DATE - d.fecha)                             AS dias_atraso,
    po.responsable_id,
    up.nombre_completo                                   AS responsable_nombre,
    o.avance_pct                                         AS avance_actual,
    po.observaciones                                     AS ultimo_comentario,
    po.estado_plan                                       AS estado_jornada,
    o.estado                                             AS estado_ejecucion
FROM calama_plan_semanal_ots po
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
JOIN calama_ordenes_trabajo o   ON o.id = po.ot_id
LEFT JOIN calama_zonas_proyecto z
       ON z.planificacion_id = o.planificacion_id
      AND z.codigo_zona = fn_calama_zona_codigo_de_folio(o.folio)
LEFT JOIN usuarios_perfil up    ON up.id = po.responsable_id
WHERE d.fecha < CURRENT_DATE
  AND po.estado_plan NOT IN ('finalizada','no_ejecutada','cancelada')
  AND o.estado NOT IN ('finalizada','cancelada')
ORDER BY (CURRENT_DATE - d.fecha) DESC, o.folio;


-- ============================================================================
-- ── 6. VISTA: calidad de datos ───────────────────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_calidad_datos CASCADE;
CREATE VIEW v_calama_calidad_datos AS
SELECT 'ots_sin_zona'                AS check_id,
       COUNT(*)                       AS valor,
       'OTs sin zona derivable del folio' AS descripcion
  FROM calama_ordenes_trabajo
 WHERE fn_calama_zona_codigo_de_folio(folio) IS NULL
UNION ALL
SELECT 'ots_sin_fecha_programada',
       COUNT(*),
       'OTs sin fecha_programada'
  FROM calama_ordenes_trabajo
 WHERE fecha_programada IS NULL
UNION ALL
SELECT 'ots_sin_responsable',
       COUNT(*),
       'OTs sin responsable_id (excluye finalizada/cancelada)'
  FROM calama_ordenes_trabajo
 WHERE responsable_id IS NULL
   AND estado NOT IN ('finalizada','cancelada')
UNION ALL
SELECT 'ots_no_planificadas',
       COUNT(*),
       'OTs no planificadas (sin jornada en plan_semanal_ots)'
  FROM calama_ordenes_trabajo o
 WHERE NOT EXISTS (SELECT 1 FROM calama_plan_semanal_ots po WHERE po.ot_id = o.id)
   AND o.estado NOT IN ('finalizada','cancelada')
UNION ALL
SELECT 'ots_parciales_sin_proxima_jornada',
       COUNT(*),
       'OTs con avance entre 1 y 99 sin jornada futura'
  FROM v_calama_estado_planificacion_ots
 WHERE avance_pct > 0 AND avance_pct < 100
   AND jornadas_futuras = 0 AND jornadas_hoy = 0
UNION ALL
SELECT 'jornadas_sin_responsable',
       COUNT(*),
       'Jornadas planificadas sin responsable'
  FROM calama_plan_semanal_ots
 WHERE responsable_id IS NULL AND estado_plan NOT IN ('finalizada','no_ejecutada','cancelada')
UNION ALL
SELECT 'jornadas_vencidas_sin_cierre',
       COUNT(*),
       'Jornadas con fecha pasada sin finalizar/no_ejec'
  FROM calama_plan_semanal_ots po
  JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
 WHERE d.fecha < CURRENT_DATE
   AND po.estado_plan NOT IN ('finalizada','no_ejecutada','cancelada');


-- ============================================================================
-- ── 7. VISTA: reporte semanal ────────────────────────────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_reporte_semanal CASCADE;
CREATE VIEW v_calama_reporte_semanal AS
SELECT
    ps.id                                                  AS plan_semanal_id,
    p.codigo                                               AS planificacion,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado                                              AS estado_plan,
    COUNT(po.id)                                           AS jornadas_total,
    COUNT(po.id) FILTER (WHERE po.estado_plan = 'finalizada')   AS jornadas_ejecutadas,
    COUNT(po.id) FILTER (WHERE po.estado_plan = 'no_ejecutada') AS jornadas_no_ejecutadas,
    COUNT(po.id) FILTER (WHERE po.estado_plan IN ('planificada','asignada','liberada')) AS jornadas_pendientes,
    COUNT(DISTINCT po.ot_id)                               AS ots_distintas,
    COUNT(DISTINCT po.responsable_id) FILTER (WHERE po.responsable_id IS NOT NULL)
                                                            AS responsables_asignados,
    COALESCE(SUM(po.horas_planificadas), 0)                AS horas_planificadas,
    COALESCE(SUM(o.horas_reales), 0)                       AS horas_reales,
    CASE WHEN COUNT(po.id) > 0 THEN
        ROUND(100.0 * COUNT(po.id) FILTER (WHERE po.estado_plan = 'finalizada') / COUNT(po.id), 1)
        ELSE 0 END                                         AS cumplimiento_pct
FROM calama_planes_semanales ps
JOIN calama_planificaciones p ON p.id = ps.planificacion_id
LEFT JOIN calama_plan_semanal_ots po ON po.plan_semanal_id = ps.id
LEFT JOIN calama_ordenes_trabajo o ON o.id = po.ot_id
GROUP BY ps.id, p.codigo, ps.fecha_inicio_semana, ps.fecha_fin_semana, ps.estado
ORDER BY ps.fecha_inicio_semana DESC;


-- ============================================================================
-- ── 8. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG28_JORNADAS_REPORTES',
        'Multidia + estado_planificacion + 4 vistas reporte + RPC agregar jornada',
        current_user, NOW(), NOW(), 'ok',
        'UNIQUE cambiado a (plan_sem, ot, dia). +4 columnas. +4 vistas. +1 RPC.'
    );
END $$;


-- ============================================================================
-- ── 9. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'uq_calama_planot_jornada'
                   AND conrelid = 'public.calama_plan_semanal_ots'::regclass)        AS uq_nuevo_ok,
        NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'uq_calama_planot'
                   AND conrelid = 'public.calama_plan_semanal_ots'::regclass)        AS uq_viejo_quitado,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                   AND column_name='horas_planificadas')                              AS col_horas,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                   AND column_name='avance_objetivo_pct')                             AS col_obj,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_estado_planificacion_ots') AS v_estado,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_reporte_atrasos')          AS v_atrasos,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_calidad_datos')            AS v_calidad,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_reporte_semanal')          AS v_semanal,
        (to_regprocedure('public.rpc_calama_agregar_jornada_ot(jsonb)') IS NOT NULL)  AS rpc_jornada_ok
)
SELECT
    CASE
        WHEN uq_nuevo_ok AND uq_viejo_quitado AND col_horas AND col_obj
         AND v_estado AND v_atrasos AND v_calidad AND v_semanal AND rpc_jornada_ok
            THEN 'OK_OPERACION_CALAMA_JORNADAS'
        ELSE 'STOP_OPERACION_CALAMA_JORNADAS'
    END AS resultado,
    uq_nuevo_ok, uq_viejo_quitado, col_horas, col_obj,
    v_estado, v_atrasos, v_calidad, v_semanal, rpc_jornada_ok,
    NOW() AS chequeado_en
FROM checks;
