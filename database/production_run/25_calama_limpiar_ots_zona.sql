-- ============================================================================
-- 25_calama_limpiar_ots_zona.sql
-- ----------------------------------------------------------------------------
-- Elimina OTs erroneamente creadas con codigo .0.0 (que son zonas/lugares
-- fisicos, no tareas ejecutables). Las zonas siguen en calama_zonas_proyecto
-- intactas — esta tabla NO se toca.
--
-- REGLA DEFINITIVA:
--   Codigo terminado en .0.0 = zona/estacion/lugar fisico (calama_zonas_proyecto)
--   Codigo NO terminado en .0.0 = tarea/OT ejecutable (calama_ordenes_trabajo)
--
-- DIAGNOSTICO:
--   Imports previos al fix del parser (commits anteriores) creaban OTs para
--   filas .0.0 del Excel. Esto contaminaba:
--     - Ordenes Calama (mostraba 1.0.0 como OT arrastrable)
--     - Backlog del Plan Semanal (zona aparecia como tarea)
--     - Vista operador (zona como OT ejecutable)
--     - Calculo de avance general (zonas se mezclaban con tareas)
--
-- FIX:
--   1. Identifica OTs con folio que termina en .0.0
--   2. Elimina dependencias (plan_ots, ejecuciones, avances, evidencias,
--      observaciones, eventos, materiales asociados) — todas tienen
--      ON DELETE CASCADE asi que el DELETE final propaga.
--   3. DELETE de las OTs .0.0
--   4. Limpia tareas_maestro huerfanas con codigo .0.0 (tabla catalogo)
--
-- SEGURIDAD:
--   - calama_zonas_proyecto NO se modifica (tabla diferente).
--   - Si una OT .0.0 tenia ejecucion finalizada con horas reales reportadas,
--     se elimina con CASCADE — esto es aceptable porque era data espuria.
--   - El proceso muestra conteos antes y despues para auditar.
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_LIMPIEZA / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP - calama_ordenes_trabajo no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_zonas_proyecto') THEN
        RAISE EXCEPTION 'STOP - calama_zonas_proyecto no existe (tabla zonas).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. SNAPSHOT pre-limpieza (auditoria) ─────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_ots_zona INT;
    v_zonas INT;
    v_tareas_zona INT;
    v_plan_ots_zona INT;
    v_ejecuciones_zona INT;
BEGIN
    SELECT COUNT(*) INTO v_ots_zona
      FROM calama_ordenes_trabajo
     WHERE folio ~ '_[0-9]+\.0\.0$';

    SELECT COUNT(*) INTO v_zonas FROM calama_zonas_proyecto;

    SELECT COUNT(*) INTO v_tareas_zona
      FROM calama_tareas_maestro
     WHERE codigo ~ '_[0-9]+\.0\.0$';

    SELECT COUNT(*) INTO v_plan_ots_zona
      FROM calama_plan_semanal_ots po
      JOIN calama_ordenes_trabajo o ON o.id = po.ot_id
     WHERE o.folio ~ '_[0-9]+\.0\.0$';

    SELECT COUNT(*) INTO v_ejecuciones_zona
      FROM calama_ot_ejecuciones e
      JOIN calama_ordenes_trabajo o ON o.id = e.ot_id
     WHERE o.folio ~ '_[0-9]+\.0\.0$';

    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG25_SNAPSHOT_PRE',
        'Snapshot pre-limpieza OTs zona',
        current_user, NOW(), NOW(), 'ok',
        format(
            'OTs .0.0 a eliminar=%s | zonas (preservadas)=%s | tareas_maestro_zona=%s | plan_ots_zona=%s | ejecuciones_zona=%s',
            v_ots_zona, v_zonas, v_tareas_zona, v_plan_ots_zona, v_ejecuciones_zona
        )
    );
END $$;


-- ============================================================================
-- ── 2. ELIMINAR OTs CON FOLIO TERMINADO EN .0.0 ──────────────────────────────
-- ============================================================================
-- ON DELETE CASCADE en plan_semanal_ots, plan_semanal_materiales,
-- ot_ejecuciones, ot_ejecucion_eventos, ot_subtareas, evidencias,
-- observaciones, eventos_no_ejecucion, ot_avance_eventos, ot_precheck,
-- avances, materiales_planificados — todos se limpian solos.
DELETE FROM calama_ordenes_trabajo
 WHERE folio ~ '_[0-9]+\.0\.0$';


-- ============================================================================
-- ── 3. LIMPIAR tareas_maestro huerfanas .0.0 (catalogo) ──────────────────────
-- ============================================================================
-- calama_tareas_maestro es catalogo (no FK CASCADE) — se limpia explicito.
-- Solo elimina las que terminan en .0.0 (zonas) y NO tienen OTs vinculadas.
DELETE FROM calama_tareas_maestro tm
 WHERE tm.codigo ~ '_[0-9]+\.0\.0$'
   AND NOT EXISTS (
       SELECT 1 FROM calama_ordenes_trabajo o
        WHERE o.tarea_maestro_id = tm.id
   );


-- ============================================================================
-- ── 4. SNAPSHOT post-limpieza ────────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_ots_zona_post INT;
    v_zonas_post INT;
    v_tareas_zona_post INT;
    v_total_ots INT;
BEGIN
    SELECT COUNT(*) INTO v_ots_zona_post
      FROM calama_ordenes_trabajo
     WHERE folio ~ '_[0-9]+\.0\.0$';

    SELECT COUNT(*) INTO v_zonas_post FROM calama_zonas_proyecto;

    SELECT COUNT(*) INTO v_tareas_zona_post
      FROM calama_tareas_maestro
     WHERE codigo ~ '_[0-9]+\.0\.0$';

    SELECT COUNT(*) INTO v_total_ots FROM calama_ordenes_trabajo;

    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG25_LIMPIEZA_OK',
        'Limpieza OTs .0.0 completada',
        current_user, NOW(), NOW(), 'ok',
        format(
            'OTs .0.0 restantes=%s (debe ser 0) | zonas preservadas=%s | tareas_maestro_zona=%s | total OTs validas=%s',
            v_ots_zona_post, v_zonas_post, v_tareas_zona_post, v_total_ots
        )
    );
END $$;


-- ============================================================================
-- ── 5. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        (SELECT COUNT(*) FROM calama_ordenes_trabajo
          WHERE folio ~ '_[0-9]+\.0\.0$')::int      AS ots_zona_restantes,
        (SELECT COUNT(*) FROM calama_zonas_proyecto)::int  AS zonas_preservadas,
        (SELECT COUNT(*) FROM calama_ordenes_trabajo)::int AS total_ots_validas,
        (SELECT COUNT(*) FROM calama_tareas_maestro
          WHERE codigo ~ '_[0-9]+\.0\.0$')::int     AS tareas_maestro_zona_restantes
)
SELECT
    CASE
        WHEN ots_zona_restantes = 0
         AND zonas_preservadas > 0
            THEN 'OK_OPERACION_CALAMA_LIMPIEZA'
        WHEN zonas_preservadas = 0
            THEN 'STOP_OPERACION_CALAMA_LIMPIEZA - ZONAS BORRADAS POR ERROR'
        WHEN ots_zona_restantes > 0
            THEN 'STOP_OPERACION_CALAMA_LIMPIEZA - OTS .0.0 PERSISTEN'
        ELSE 'WARNING_OPERACION_CALAMA_LIMPIEZA'
    END AS resultado,
    ots_zona_restantes,
    zonas_preservadas,
    total_ots_validas,
    tareas_maestro_zona_restantes,
    CASE
        WHEN ots_zona_restantes = 0 AND zonas_preservadas > 0
        THEN 'OK: zonas preservadas en calama_zonas_proyecto, OTs .0.0 eliminadas.'
        ELSE 'Revisar conteos.'
    END AS detalle,
    NOW() AS chequeado_en
FROM checks;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- ots_zona_restantes  : DEBE ser 0 (no debe quedar OTs .0.0)
-- zonas_preservadas   : DEBE ser >0 (las zonas siguen intactas, ej: 17)
-- total_ots_validas   : 95 si solo importaste el Excel Centinela (112 - 17)
-- tareas_maestro_zona : DEBE ser 0 (catalogo limpio de zonas)
-- ============================================================================
