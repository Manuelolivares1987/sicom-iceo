SELECT jsonb_build_object(
  'jornadas_total', (SELECT COUNT(*) FROM taller_plan_semanal_ots),
  'jornadas_con_resp_propio', (SELECT COUNT(*) FROM taller_plan_semanal_ots WHERE responsable_id IS NOT NULL),
  'jornadas_con_cuadrilla', (SELECT COUNT(*) FROM taller_plan_semanal_ots WHERE cuadrilla IS NOT NULL AND TRIM(cuadrilla) <> ''),
  'ots_total', (SELECT COUNT(*) FROM ordenes_trabajo),
  'ots_con_responsable', (SELECT COUNT(*) FROM ordenes_trabajo WHERE responsable_id IS NOT NULL),
  'ots_en_jornadas', (SELECT COUNT(DISTINCT ot_id) FROM taller_plan_semanal_ots),
  'ots_en_jornadas_con_resp', (SELECT COUNT(*) FROM taller_plan_semanal_ots t
        JOIN ordenes_trabajo o ON o.id = t.ot_id WHERE o.responsable_id IS NOT NULL)
) AS r;
