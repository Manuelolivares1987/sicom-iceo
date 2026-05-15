-- ============================================================================
-- 50_calama_jornadas_en_vivo.sql
-- ----------------------------------------------------------------------------
-- Vista nueva v_calama_jornadas_en_vivo: feed del dia para el supervisor.
--
-- Agrega todas las jornadas relacionadas con el dia de hoy en cualquier
-- estado activo + cerradas hoy. Permite renderizar 3 tabs en
-- /dashboard/operacion-calama/aceptaciones:
--
--   1. EN VIVO   - jornadas con ejecucion corriendo / pausada / en faena
--                  sin iniciar / cerradas hoy.
--   2. PENDIENTES - estado_plan IN ('pendiente_aprobacion','finalizada_operador')
--                   (lo que ya cubre v_calama_jornadas_pendientes_supervision).
--   3. HOY       - vista de cierre del dia, agrupada por categoria.
--
-- La columna `categoria_vivo` clasifica la jornada para render:
--   - 'corriendo'              -> ejecucion en_ejecucion
--   - 'pausada'                -> ejecucion pausada
--   - 'cerrada_hoy'            -> cierre_jornada_at::date = hoy
--   - 'en_faena_sin_iniciar'   -> llegada_faena pero sin ejecucion
--   - 'pendiente_inicio'       -> planificada hoy, sin llegada
--
-- Filtros: oculta desprogramadas / anuladas / OTs de prueba.
--
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE VIEW).
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ot_ejecuciones') THEN
        RAISE EXCEPTION 'STOP - falta calama_ot_ejecuciones.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public'
                      AND table_name='calama_plan_semanal_ots'
                      AND column_name='cierre_jornada_at') THEN
        RAISE EXCEPTION 'STOP - MIG33 no aplicada (falta cierre_jornada_at).';
    END IF;
END $$;


-- ── Vista ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_calama_jornadas_en_vivo AS
WITH ejecucion_activa AS (
    SELECT DISTINCT ON (ot_id)
        ot_id,
        id AS ejecucion_id,
        ejecutor_id,
        estado,
        started_at,
        last_event_at,
        tiempo_total_segundos,
        tiempo_pausado_segundos,
        tiempo_efectivo_segundos,
        tiempo_colacion_segundos
      FROM calama_ot_ejecuciones
     WHERE estado IN ('en_ejecucion','pausada')
     ORDER BY ot_id, started_at DESC
),
ultima_evidencia AS (
    SELECT DISTINCT ON (ot_id)
        ot_id,
        archivo_url,
        contexto,
        momento,
        gps_lat,
        gps_lng,
        created_at AS evidencia_at
      FROM calama_evidencias
     ORDER BY ot_id, created_at DESC
),
ultimo_evento AS (
    SELECT DISTINCT ON (ot_id)
        ot_id,
        tipo,
        motivo,
        created_at AS evento_at
      FROM calama_ot_ejecucion_eventos
     ORDER BY ot_id, created_at DESC
)
SELECT
    po.id                                        AS plan_semanal_ot_id,
    po.ot_id,
    o.folio,
    o.titulo,
    o.avance_pct,
    o.descripcion,
    po.estado_plan,
    d.fecha                                      AS fecha_jornada,
    d.nombre_dia,
    -- Hitos PRO terreno
    po.llegada_faena_at,
    po.cierre_jornada_at,
    -- Responsable asignado (plan)
    po.responsable_id,
    u.nombre_completo                            AS responsable_nombre,
    u.email                                      AS responsable_email,
    -- Ejecucion en vivo (si hay)
    e.ejecucion_id,
    e.estado                                     AS ejecucion_estado,
    e.started_at                                 AS ejecucion_started_at,
    e.last_event_at,
    e.tiempo_total_segundos,
    e.tiempo_pausado_segundos,
    e.tiempo_efectivo_segundos,
    e.tiempo_colacion_segundos,
    ej.nombre_completo                           AS ejecutor_nombre,
    ej.email                                     AS ejecutor_email,
    -- Tiempos finales (post cierre)
    po.tiempo_en_faena_segundos,
    po.tiempo_operativo_bruto_segundos,
    po.tiempo_efectivo_trabajo_segundos,
    po.tiempo_interferencia_mandante_segundos,
    -- Ultima evidencia subida (para preview)
    ue.archivo_url                               AS ultima_evidencia_url,
    ue.contexto                                  AS ultima_evidencia_contexto,
    ue.momento                                   AS ultima_evidencia_momento,
    ue.gps_lat                                   AS ultima_evidencia_lat,
    ue.gps_lng                                   AS ultima_evidencia_lng,
    ue.evidencia_at                              AS ultima_evidencia_at,
    -- Ultimo evento
    uev.tipo                                     AS ultimo_evento_tipo,
    uev.motivo                                   AS ultimo_evento_motivo,
    uev.evento_at,
    -- Conteos de evidencias por momento
    (SELECT COUNT(*) FROM calama_evidencias x
      WHERE x.ot_id = po.ot_id AND x.contexto = 'jornada_antes')     AS evid_antes,
    (SELECT COUNT(*) FROM calama_evidencias x
      WHERE x.ot_id = po.ot_id AND x.contexto = 'jornada_durante')   AS evid_durante,
    (SELECT COUNT(*) FROM calama_evidencias x
      WHERE x.ot_id = po.ot_id AND x.contexto = 'jornada_despues')   AS evid_despues,
    (SELECT COUNT(*) FROM calama_evidencias x
      WHERE x.ot_id = po.ot_id AND x.contexto = 'llegada_faena')     AS evid_llegada,
    (SELECT COUNT(*) FROM calama_firmas_jornada f
      WHERE f.plan_semanal_ot_id = po.id AND f.firmante_tipo = 'operador') AS firmas_operador,
    -- Clasificacion para render
    CASE
        WHEN e.estado = 'en_ejecucion'                       THEN 'corriendo'
        WHEN e.estado = 'pausada'                            THEN 'pausada'
        WHEN po.cierre_jornada_at::date = CURRENT_DATE       THEN 'cerrada_hoy'
        WHEN po.llegada_faena_at IS NOT NULL
             AND po.cierre_jornada_at IS NULL                THEN 'en_faena_sin_iniciar'
        ELSE                                                      'pendiente_inicio'
    END                                          AS categoria_vivo,
    -- Planificacion
    p.codigo                                     AS planificacion_codigo,
    p.id                                         AS planificacion_id
  FROM calama_plan_semanal_ots po
  JOIN calama_ordenes_trabajo o    ON o.id = po.ot_id
  JOIN calama_planificaciones p    ON p.id = o.planificacion_id
  LEFT JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
  LEFT JOIN usuarios_perfil u      ON u.id = po.responsable_id
  LEFT JOIN ejecucion_activa e     ON e.ot_id = po.ot_id
  LEFT JOIN usuarios_perfil ej     ON ej.id = e.ejecutor_id
  LEFT JOIN ultima_evidencia ue    ON ue.ot_id = po.ot_id
  LEFT JOIN ultimo_evento uev      ON uev.ot_id = po.ot_id
 WHERE po.visible_en_kanban = true
   AND po.desprogramada_at IS NULL
   AND po.anulada_at IS NULL
   AND o.es_prueba = false
   AND (
        d.fecha = CURRENT_DATE
     OR po.llegada_faena_at::date  = CURRENT_DATE
     OR po.cierre_jornada_at::date = CURRENT_DATE
     OR e.estado IN ('en_ejecucion','pausada')
   );

COMMENT ON VIEW v_calama_jornadas_en_vivo IS
'MIG50 - Feed del dia para tablero de aceptaciones. Incluye jornadas planificadas hoy, ejecutadas hoy, cerradas hoy, o con ejecucion activa. Trae ejecucion en vivo + ultima evidencia + ultimo evento + conteos + categoria para render.';

GRANT SELECT ON v_calama_jornadas_en_vivo TO authenticated;


-- ── Vista resumen del dia (KPIs para tab "Hoy") ────────────────────────────
CREATE OR REPLACE VIEW v_calama_resumen_hoy AS
SELECT
    COUNT(*)                                                       AS total_jornadas,
    COUNT(*) FILTER (WHERE categoria_vivo = 'corriendo')           AS corriendo,
    COUNT(*) FILTER (WHERE categoria_vivo = 'pausada')             AS pausadas,
    COUNT(*) FILTER (WHERE categoria_vivo = 'en_faena_sin_iniciar') AS en_faena_sin_iniciar,
    COUNT(*) FILTER (WHERE categoria_vivo = 'pendiente_inicio')    AS pendientes_inicio,
    COUNT(*) FILTER (WHERE categoria_vivo = 'cerrada_hoy')         AS cerradas_hoy,
    COUNT(*) FILTER (WHERE estado_plan IN ('finalizada_operador','pendiente_aprobacion'))
                                                                   AS pendientes_supervision,
    COUNT(*) FILTER (WHERE estado_plan IN ('aceptada','cerrada'))  AS aceptadas_hoy,
    COUNT(*) FILTER (WHERE estado_plan = 'requiere_correccion')    AS requieren_correccion,
    -- Tiempos acumulados del dia (segundos)
    COALESCE(SUM(tiempo_efectivo_trabajo_segundos), 0)             AS total_seg_efectivo_cerradas,
    COALESCE(SUM(tiempo_efectivo_segundos), 0)                     AS total_seg_efectivo_en_vivo,
    COALESCE(SUM(tiempo_interferencia_mandante_segundos), 0)       AS total_seg_interferencia
  FROM v_calama_jornadas_en_vivo;

COMMENT ON VIEW v_calama_resumen_hoy IS
'MIG50 - KPIs del dia derivados de v_calama_jornadas_en_vivo. Una sola fila con conteos por categoria y totales de tiempo.';

GRANT SELECT ON v_calama_resumen_hoy TO authenticated;

NOTIFY pgrst, 'reload schema';
