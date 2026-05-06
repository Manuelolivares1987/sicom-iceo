-- ============================================================================
-- diag_calama_oocc_no_ve_planificacion.sql
-- ----------------------------------------------------------------------------
-- Diagnostico del bug "OOCC no ve la planificacion nueva creada por supcalama".
-- Read-only. Ejecutar como admin en Supabase SQL Editor.
--
-- 5 queries independientes; si tu editor no admite varias salidas, ejecuta
-- una a la vez (estan separadas por comentarios).
-- ============================================================================


-- ── 1. Jornadas asignadas a OOCC (todas, sin filtro de visibilidad) ────────
SELECT
    '01_jornadas_asignadas_oocc' AS chequeo,
    ot.folio                     AS folio_ot,
    LEFT(ot.titulo, 50)          AS titulo,
    po.id::text                  AS jornada_id,
    po.responsable_id::text      AS responsable_id,
    up.email                     AS responsable_email,
    po.estado_plan,
    po.visible_en_kanban,
    po.desprogramada_at,
    po.anulada_at,
    d.fecha,
    po.created_at,
    po.updated_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
LEFT JOIN usuarios_perfil up ON up.id = po.responsable_id
WHERE po.responsable_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
ORDER BY d.fecha DESC, po.updated_at DESC NULLS LAST;
-- Si esta consulta NO devuelve nada -> nadie planifico jornadas para OOCC
-- (problema de planificacion, no del mobile).


-- ── 2. Jornadas que el filtro mobile DEBERIA mostrar a OOCC ───────────────
SELECT
    '02_jornadas_visibles_mobile_oocc' AS chequeo,
    ot.folio                            AS folio_ot,
    LEFT(ot.titulo, 50)                 AS titulo,
    po.id::text                         AS jornada_id,
    po.estado_plan,
    po.visible_en_kanban,
    d.fecha
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
WHERE po.responsable_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
  AND COALESCE(po.visible_en_kanban, true) = true
  AND po.desprogramada_at IS NULL
  AND po.anulada_at IS NULL
  AND COALESCE(po.estado_plan, '') NOT IN (
    'desprogramada','anulada_prueba','cancelada_operacional',
    'no_ejecutada','cerrada','aceptada'
  )
ORDER BY d.fecha DESC;
-- Si esta consulta tiene filas pero el mobile NO las muestra -> bug frontend.
-- Si esta consulta esta vacia y la 01 si tiene -> bug en filtros (visible_en_kanban
-- o estado_plan invalido).


-- ── 3. Ultimas 30 jornadas modificadas en el sistema ──────────────────────
SELECT
    '03_ultimas_modificadas' AS chequeo,
    ot.folio                  AS folio_ot,
    LEFT(ot.titulo, 50)       AS titulo,
    po.id::text               AS jornada_id,
    po.responsable_id::text   AS responsable_id,
    up.email                  AS responsable_email,
    po.estado_plan,
    po.visible_en_kanban,
    d.fecha,
    po.created_at,
    po.updated_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
LEFT JOIN usuarios_perfil up ON up.id = po.responsable_id
ORDER BY po.updated_at DESC NULLS LAST, po.created_at DESC
LIMIT 30;
-- Si las jornadas que supcalama planifico estan aqui pero responsable_email != oocc,
-- entonces el dropdown responsable NO guardo el UID correcto.


-- ── 4. Jornadas SIN responsable (planificadas pero olvidadas) ─────────────
SELECT
    '04_sin_responsable' AS chequeo,
    ot.folio              AS folio_ot,
    LEFT(ot.titulo, 50)   AS titulo,
    po.id::text           AS jornada_id,
    po.estado_plan,
    d.fecha,
    po.updated_at
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
WHERE po.responsable_id IS NULL
ORDER BY po.updated_at DESC NULLS LAST, po.created_at DESC
LIMIT 30;


-- ── 5. Diagnostico de visibilidad por jornada ─────────────────────────────
SELECT
    '05_diagnostico_visibilidad' AS chequeo,
    ot.folio                      AS folio_ot,
    LEFT(ot.titulo, 50)           AS titulo,
    po.id::text                   AS jornada_id,
    po.responsable_id::text       AS responsable_id,
    up.email                      AS responsable_email,
    po.estado_plan,
    po.visible_en_kanban,
    po.desprogramada_at,
    po.anulada_at,
    d.fecha,
    CASE
      WHEN po.responsable_id IS NULL                                                                  THEN 'SIN_RESPONSABLE'
      WHEN COALESCE(po.visible_en_kanban, true) = false                                               THEN 'OCULTA_VISIBLE_FALSE'
      WHEN po.desprogramada_at IS NOT NULL                                                            THEN 'DESPROGRAMADA'
      WHEN po.anulada_at IS NOT NULL                                                                  THEN 'ANULADA'
      WHEN COALESCE(po.estado_plan, '') IN ('desprogramada','anulada_prueba','cancelada_operacional') THEN 'ESTADO_EXCLUIDO'
      WHEN COALESCE(po.estado_plan, '') IN ('cerrada','aceptada','no_ejecutada')                     THEN 'TERMINAL'
      ELSE 'VISIBLE'
    END AS diagnostico_visibilidad
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
LEFT JOIN usuarios_perfil up ON up.id = po.responsable_id
ORDER BY po.updated_at DESC NULLS LAST, po.created_at DESC
LIMIT 50;


-- ============================================================================
-- INTERPRETACION:
--
-- A) Si query 01 esta vacia:
--    - supcalama NO termino de asignar a OOCC. El responsable_id no se grabo.
--    - Ir al Plan Semanal y volver a asignar (dropdown debe mostrar toast
--      "Responsable actualizado: <nombre>").
--
-- B) Si query 01 tiene filas pero query 02 no:
--    - La jornada esta marcada visible_en_kanban=false, desprogramada o
--      con estado_plan excluido. Mira query 05 para detectar cual.
--
-- C) Si query 02 tiene filas pero el mobile no las muestra:
--    - Bug en frontend: probablemente el fallback IndexedDB se esta
--      activando aunque OOCC esta online. El commit que sigue arregla
--      esto: cuando el server cargo correctamente NO se reemplaza con
--      jornadas locales antiguas.
--
-- D) Si query 03 muestra que la jornada planificada por supcalama tiene
--    responsable_email != oocc: el dropdown no guardo. Ver
--    rpc_calama_asignar_responsable_ot_semana.
-- ============================================================================
