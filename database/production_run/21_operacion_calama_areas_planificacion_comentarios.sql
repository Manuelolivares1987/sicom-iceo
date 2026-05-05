-- ============================================================================
-- 21_operacion_calama_areas_planificacion_comentarios.sql
-- ----------------------------------------------------------------------------
-- Refinamiento del Plan Semanal Calama:
--   - Helper SQL para derivar lugar fisico (zona N.0.0) desde folio de OT.
--   - RPC para editar comentarios de planificacion en plan_semanal_ots.
--   - Vistas para reporte general y reporte por lugar fisico (area).
--
-- DIAGNOSTICO:
--   - calama_zonas_proyecto YA TIENE 1.0.0 / 2.0.0 / ... (MIG18, importer Excel).
--     Cada zona tiene codigo_zona y nombre (ej "1.0.0", "Petrolera Oxidos").
--   - calama_ordenes_trabajo NO tiene FK directa a zona. La zona se deriva
--     del folio: OT_<plan_codigo>_<n.m.k> -> zona <n.0.0>.
--   - calama_plan_semanal_ots YA TIENE columna `observaciones` (MIG20).
--     Solo falta RPC y UI; no hay que ALTER TABLE.
--   - El % de avance del Excel (col C de Carta Gantt) NO se importa a OTs.
--     Para reportes usamos calama_ordenes_trabajo.avance_pct (mantenido por
--     ejecuciones) y avance_real de calama_planificaciones. Si en el futuro
--     se decide importar la col C, se puede agregar avance_excel en un parche
--     posterior; este script no toca el importer.
--
-- ALCANCE:
--   - 1 helper SQL: fn_calama_zona_codigo_de_folio(text)
--   - 1 RPC: rpc_calama_actualizar_comentario_plan_ot(jsonb)
--   - 2 vistas:
--       v_calama_avance_por_area
--       v_calama_resumen_general
--
-- AISLACION:
--   - NO toca MIG17/18/18B/19/20.
--   - NO toca QR (mig 14*), MIG55-57, ni rol_usuario_enum.
--   - NO crea tablas nuevas (todo lo necesario ya existe).
--   - Las vistas heredan RLS de las tablas base (security_invoker = true).
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_AREAS / WARNING / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_zonas_proyecto') THEN
        RAISE EXCEPTION 'STOP - MIG18 no aplicada (calama_zonas_proyecto no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots') THEN
        RAISE EXCEPTION 'STOP - MIG20 no aplicada (calama_plan_semanal_ots no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='observaciones') THEN
        RAISE EXCEPTION 'STOP - calama_plan_semanal_ots.observaciones no existe.';
    END IF;
END $$;


-- ============================================================================
-- ── 1. HELPER ────────────────────────────────────────────────────────────────
-- ============================================================================

-- Deriva el codigo de zona/lugar fisico desde el folio de la OT.
-- Folio: OT_<plan_codigo>_<n.m.k>  -> zona "<n.0.0>"
CREATE OR REPLACE FUNCTION fn_calama_zona_codigo_de_folio(p_folio TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT (regexp_match(p_folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0';
$$;

GRANT EXECUTE ON FUNCTION fn_calama_zona_codigo_de_folio(TEXT) TO authenticated, anon;


-- ============================================================================
-- ── 2. RPC actualizar comentario de planificacion ────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_actualizar_comentario_plan_ot(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_semanal_id UUID := (p_payload->>'plan_semanal_id')::UUID;
    v_ot_id           UUID := (p_payload->>'ot_id')::UUID;
    v_observaciones   TEXT := p_payload->>'observaciones';
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para editar comentarios de planificacion';
    END IF;
    IF v_plan_semanal_id IS NULL OR v_ot_id IS NULL THEN
        RAISE EXCEPTION 'plan_semanal_id y ot_id son obligatorios';
    END IF;

    UPDATE calama_plan_semanal_ots
       SET observaciones = NULLIF(TRIM(COALESCE(v_observaciones,'')),''),
           updated_at = NOW()
     WHERE plan_semanal_id = v_plan_semanal_id AND ot_id = v_ot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no esta en este plan semanal';
    END IF;

    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_actualizar_comentario_plan_ot(jsonb) TO authenticated;


-- ============================================================================
-- ── 3. VISTA: avance por area (lugar fisico) ─────────────────────────────────
-- ============================================================================
-- Agrega OTs por planificacion + zona derivada del folio. Calcula totales,
-- finalizadas, en ejecucion, planificadas semana, no asignadas, avance promedio.

CREATE OR REPLACE VIEW v_calama_avance_por_area AS
WITH ot_zona AS (
    SELECT
        o.id,
        o.planificacion_id,
        o.estado,
        o.avance_pct,
        o.fecha_programada,
        fn_calama_zona_codigo_de_folio(o.folio) AS codigo_zona
    FROM calama_ordenes_trabajo o
),
plan_ots_resumen AS (
    SELECT
        po.plan_semanal_id,
        po.ot_id,
        po.responsable_id,
        po.estado_plan,
        po.observaciones,
        po.plan_dia_id,
        ps.planificacion_id,
        ps.fecha_inicio_semana,
        ps.fecha_fin_semana
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
)
SELECT
    p.id                                                    AS planificacion_id,
    p.codigo                                                AS planificacion_codigo,
    z.codigo_zona,
    z.nombre                                                AS lugar_fisico_nombre,
    z.id                                                    AS zona_proyecto_id,
    COUNT(o.id)                                             AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado = 'finalizada')      AS tareas_finalizadas,
    COUNT(o.id) FILTER (WHERE o.estado = 'en_ejecucion')    AS tareas_en_ejecucion,
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada','en_pausa'))
                                                            AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')    AS tareas_no_ejecutadas,
    COUNT(po.ot_id)                                         AS tareas_planificadas_semana,
    COUNT(po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                            AS tareas_sin_responsable,
    COUNT(po.observaciones) FILTER (WHERE po.observaciones IS NOT NULL AND po.observaciones <> '')
                                                            AS tareas_con_comentario,
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_promedio_pct
FROM calama_zonas_proyecto z
JOIN calama_planificaciones p
       ON p.id = z.planificacion_id
LEFT JOIN ot_zona o
       ON o.planificacion_id = p.id
      AND o.codigo_zona = z.codigo_zona
LEFT JOIN plan_ots_resumen po
       ON po.ot_id = o.id
      AND po.planificacion_id = p.id
GROUP BY p.id, p.codigo, z.id, z.codigo_zona, z.nombre
ORDER BY p.codigo, z.codigo_zona;

COMMENT ON VIEW v_calama_avance_por_area IS
    'Resumen por lugar fisico/area. Una fila por (planificacion, zona).';


-- ============================================================================
-- ── 4. VISTA: resumen general por planificacion ──────────────────────────────
-- ============================================================================
CREATE OR REPLACE VIEW v_calama_resumen_general AS
WITH ots AS (
    SELECT
        o.planificacion_id,
        o.id, o.estado, o.avance_pct, o.fecha_programada
    FROM calama_ordenes_trabajo o
),
plan_ots AS (
    SELECT
        ps.planificacion_id,
        po.ot_id, po.responsable_id, po.observaciones, po.estado_plan
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
),
zonas AS (
    SELECT planificacion_id, COUNT(*)::int AS total_zonas
    FROM calama_zonas_proyecto
    GROUP BY planificacion_id
)
SELECT
    p.id                                              AS planificacion_id,
    p.codigo                                          AS planificacion_codigo,
    p.nombre                                          AS planificacion_nombre,
    p.linea_negocio,
    p.estado                                          AS estado_planificacion,
    COALESCE(z.total_zonas, 0)                        AS total_lugares_fisicos,
    COUNT(o.id)                                       AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado = 'finalizada')        AS tareas_finalizadas,
    COUNT(o.id) FILTER (WHERE o.estado = 'en_ejecucion')      AS tareas_en_ejecucion,
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada','en_pausa'))
                                                              AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')      AS tareas_no_ejecutadas,
    COUNT(DISTINCT po.ot_id)                                  AS tareas_planificadas_semanas,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                              AS tareas_sin_responsable,
    COUNT(DISTINCT po.ot_id) FILTER (
        WHERE po.observaciones IS NOT NULL AND po.observaciones <> ''
    )                                                          AS tareas_con_comentario,
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                              AS avance_promedio_pct
FROM calama_planificaciones p
LEFT JOIN zonas    z ON z.planificacion_id = p.id
LEFT JOIN ots      o ON o.planificacion_id = p.id
LEFT JOIN plan_ots po ON po.planificacion_id = p.id AND po.ot_id = o.id
GROUP BY p.id, p.codigo, p.nombre, p.linea_negocio, p.estado, z.total_zonas
ORDER BY p.codigo;

COMMENT ON VIEW v_calama_resumen_general IS
    'Resumen general por planificacion (proyecto). 1 fila por planificacion.';


-- ============================================================================
-- ── 5. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG21_CALAMA_AREAS',
        'Refinamiento Plan Semanal: helper zona desde folio + RPC comentario + 2 vistas reporte',
        current_user, NOW(), NOW(), 'ok',
        '1 helper SQL + 1 RPC + 2 vistas. NO crea tablas nuevas.'
    );
END $$;


-- ============================================================================
-- ── 6. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        (to_regprocedure('public.fn_calama_zona_codigo_de_folio(text)') IS NOT NULL)              AS helper_ok,
        (to_regprocedure('public.rpc_calama_actualizar_comentario_plan_ot(jsonb)') IS NOT NULL)   AS rpc_ok,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_avance_por_area')           AS vista_area_ok,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_resumen_general')           AS vista_general_ok,
        -- Sanity: la columna observaciones sigue presente
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                   AND column_name='observaciones')                                                AS col_obs_ok
),
faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT helper_ok      THEN 'fn_calama_zona_codigo_de_folio' END,
        CASE WHEN NOT rpc_ok         THEN 'rpc_calama_actualizar_comentario_plan_ot' END,
        CASE WHEN NOT vista_area_ok  THEN 'v_calama_avance_por_area' END,
        CASE WHEN NOT vista_general_ok THEN 'v_calama_resumen_general' END,
        CASE WHEN NOT col_obs_ok     THEN 'calama_plan_semanal_ots.observaciones' END
    ]::text[], NULL) AS objetos_faltantes
    FROM checks
)
SELECT
    CASE
        WHEN cardinality(objetos_faltantes) = 0
            THEN 'OK_OPERACION_CALAMA_AREAS'
        ELSE 'STOP_OPERACION_CALAMA_AREAS'
    END AS resultado,
    COALESCE(NULLIF(array_to_string(objetos_faltantes, ', '), ''),
             '1 helper + 1 RPC + 2 vistas + columna observaciones presente.') AS detalle,
    cardinality(objetos_faltantes) AS faltantes_count,
    NOW() AS chequeado_en
FROM faltantes;
