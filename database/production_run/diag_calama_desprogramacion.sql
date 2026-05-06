-- ============================================================================
-- diag_calama_desprogramacion.sql
-- ----------------------------------------------------------------------------
-- Diagnostico del bug "Sacar no quita la jornada del Kanban / mobile".
-- Read-only: NO altera datos.
--
-- Verifica:
--   1. MIG32 aplicada (columnas + tabla auditoria + RPCs).
--   2. Jornadas con estados/flags de "fuera del programa".
--   3. Visibilidad esperada en Kanban activo.
--   4. Visibilidad esperada en /m/calama del operador OOCC.
--   5. Auditoria reciente de desprogramaciones.
-- ============================================================================

-- ── 1. MIG32 aplicada? ──────────────────────────────────────────────────────
SELECT
    '01_mig32_aplicada'::text AS chequeo,
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
             AND table_name='calama_plan_semanal_ots' AND column_name='visible_en_kanban')      AS col_visible_en_kanban,
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
             AND table_name='calama_plan_semanal_ots' AND column_name='desprogramada_at')       AS col_desprogramada_at,
    EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public'
             AND table_name='calama_jornada_auditoria')                                         AS tabla_auditoria,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_desprogramar_jornada')              AS rpc_desprogramar,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_cancelar_jornada')                  AS rpc_cancelar,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_resetear_jornada_prueba')           AS rpc_reset,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_eliminar_jornada_prueba')           AS rpc_eliminar,
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_llegada_faena')           AS rpc_llegada,
    NOW() AS chequeado_en;

-- Si col_visible_en_kanban=false o tabla_auditoria=false: MIG32 NO esta aplicada.
-- Aplicar: database/production_run/32_calama_acciones_admin_y_llegada_faena.sql


-- ── 2. Jornadas que estan FUERA del programa (debieran estar ocultas) ─────
SELECT
    '02_jornadas_fuera_programa'::text AS chequeo,
    ot.folio                            AS folio_ot,
    LEFT(ot.titulo, 60)                 AS titulo,
    po.id::text                         AS jornada_id,
    po.estado_plan,
    po.visible_en_kanban,
    po.desprogramada_at,
    po.anulada_at,
    po.motivo_desprogramacion,
    po.motivo_anulacion,
    po.es_prueba,
    po.requiere_decision_programador,
    po.responsable_id::text             AS responsable_id,
    po.updated_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
WHERE COALESCE(po.visible_en_kanban, true) = false
   OR po.desprogramada_at IS NOT NULL
   OR po.anulada_at IS NOT NULL
   OR po.estado_plan IN ('desprogramada','anulada_prueba','cancelada_operacional')
ORDER BY COALESCE(po.anulada_at, po.desprogramada_at, po.updated_at) DESC NULLS LAST
LIMIT 30;


-- ── 3. Jornadas que SI deberian aparecer en Kanban activo ─────────────────
-- (filtro replica el del frontend en otsByDia)
SELECT
    '03_jornadas_visibles_kanban'::text AS chequeo,
    ot.folio                            AS folio_ot,
    LEFT(ot.titulo, 50)                 AS titulo,
    po.id::text                         AS jornada_id,
    po.estado_plan,
    d.fecha,
    d.nombre_dia,
    po.responsable_id::text             AS responsable_id,
    po.updated_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
WHERE COALESCE(po.visible_en_kanban, true) = true
  AND po.desprogramada_at IS NULL
  AND po.anulada_at IS NULL
  AND po.estado_plan NOT IN ('desprogramada','anulada_prueba','cancelada_operacional','no_ejecutada','reprogramada')
ORDER BY d.fecha DESC, po.updated_at DESC
LIMIT 30;


-- ── 4. Lo que deberia ver OOCC en /m/calama (filtro mobile) ──────────────
SELECT
    '04_jornadas_visibles_oocc'::text AS chequeo,
    ot.folio                          AS folio_ot,
    LEFT(ot.titulo, 50)               AS titulo,
    po.id::text                       AS jornada_id,
    po.estado_plan,
    d.fecha,
    po.llegada_faena_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d  ON d.id = po.plan_dia_id
WHERE po.responsable_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
  AND COALESCE(po.visible_en_kanban, true) = true
  AND po.desprogramada_at IS NULL
  AND po.anulada_at IS NULL
  AND po.estado_plan NOT IN ('desprogramada','anulada_prueba','cancelada_operacional','no_ejecutada','reprogramada')
ORDER BY d.fecha DESC
LIMIT 30;


-- ── 5. Auditoria reciente (acciones admin) ────────────────────────────────
SELECT
    '05_auditoria_reciente'::text AS chequeo,
    aud.accion,
    aud.estado_anterior,
    aud.estado_nuevo,
    aud.motivo,
    aud.observacion,
    aud.ejecutado_at,
    (SELECT email FROM usuarios_perfil WHERE id = aud.ejecutado_por) AS ejecutado_por_email,
    aud.metadata::text AS metadata
FROM calama_jornada_auditoria aud
ORDER BY aud.ejecutado_at DESC
LIMIT 20;


-- ── 6. Ejecuciones activas (PLAY/PAUSA pendientes que pueden estar bloqueando) ─
SELECT
    '06_ejecuciones_activas'::text AS chequeo,
    ej.id::text                    AS ejecucion_id,
    ot.folio                       AS folio_ot,
    ej.estado,
    ej.started_at,
    ej.last_event_at,
    ej.tiempo_efectivo_segundos,
    ej.ejecutor_id::text           AS ejecutor_id,
    (SELECT email FROM usuarios_perfil WHERE id = ej.ejecutor_id) AS ejecutor_email
FROM calama_ot_ejecuciones ej
JOIN calama_ordenes_trabajo ot ON ot.id = ej.ot_id
WHERE ej.estado IN ('en_ejecucion','pausada')
ORDER BY ej.started_at DESC
LIMIT 20;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - Si chequeo 01 muestra col_visible_en_kanban=false: APLICAR MIG32.
-- - Si chequeo 02 esta vacio despues de presionar "Sacar": el RPC NO actualizo
--   la fila (revisar respuesta RPC en el frontend).
-- - Si chequeo 02 muestra la fila pero chequeo 03 TAMBIEN la sigue mostrando:
--   el filtro del backend o el query del frontend NO esta bien (revisar
--   getOTsPlanSemanal).
-- - Si OOCC sigue viendo en chequeo 04 una jornada que ya esta en chequeo 02:
--   getMisOTsAsignadas no esta filtrando (este commit lo arregla).
-- - Si chequeo 06 muestra ejecucion 'en_ejecucion'/'pausada' de prueba:
--   usa "Reset prueba" desde admin (modo: eliminar_logico) y se cancela la
--   ejecucion automaticamente.
-- ============================================================================
