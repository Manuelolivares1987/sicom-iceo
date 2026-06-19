-- ============================================================================
-- SICOM-ICEO | 160 — Vista de OTs para la app del mecánico
-- ============================================================================
-- Lista las OTs YA LIBERADAS a ejecución (preparacion_ok_at), no finalizadas,
-- con la cuadrilla (para filtrar por nombre de mecánico), el responsable y el
-- avance del checklist V03. Alimenta /m/taller (vista mecánico offline-first).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DROP VIEW IF EXISTS v_taller_mecanico_ots CASCADE;
CREATE VIEW v_taller_mecanico_ots AS
SELECT
    ot.id                       AS ot_id,
    ot.folio                    AS ot_folio,
    ot.tipo                     AS ot_tipo,
    ot.estado                   AS ot_estado,
    ot.prioridad                AS ot_prioridad,
    ot.preparacion_ok_at,
    ot.fecha_programada,
    ot.activo_id,
    a.codigo                    AS activo_codigo,
    a.nombre                    AS activo_nombre,
    a.patente                   AS activo_patente,
    (SELECT string_agg(DISTINCT t.cuadrilla, ', ')
       FROM taller_plan_semanal_ots t
      WHERE t.ot_id = ot.id AND NULLIF(TRIM(t.cuadrilla),'') IS NOT NULL) AS cuadrilla,
    up.nombre_completo          AS responsable,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false)                       AS checklist_total,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false
         AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente')       AS checklist_completados,
    (SELECT COALESCE(SUM(v.tiempo_min),0) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false)                       AS tiempo_estimado_total_min
FROM ordenes_trabajo ot
JOIN activos a               ON a.id = ot.activo_id
LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
WHERE ot.preparacion_ok_at IS NOT NULL
  AND ot.estado IN ('asignada','en_ejecucion','pausada')
ORDER BY
    CASE ot.estado WHEN 'en_ejecucion' THEN 1 WHEN 'pausada' THEN 2 ELSE 3 END,
    CASE ot.prioridad WHEN 'emergencia' THEN 1 WHEN 'urgente' THEN 2 WHEN 'alta' THEN 3
                      WHEN 'normal' THEN 4 ELSE 5 END,
    ot.fecha_programada NULLS LAST;

COMMENT ON VIEW v_taller_mecanico_ots IS
    'OTs liberadas a ejecucion (no finalizadas) con cuadrilla y avance checklist V03. App mecanico. MIG160.';
GRANT SELECT ON v_taller_mecanico_ots TO authenticated;

SELECT jsonb_build_object(
    'vista_ok', (SELECT EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_taller_mecanico_ots')),
    'ots_liberadas', (SELECT COUNT(*) FROM v_taller_mecanico_ots)
) AS resultado;

NOTIFY pgrst, 'reload schema';
