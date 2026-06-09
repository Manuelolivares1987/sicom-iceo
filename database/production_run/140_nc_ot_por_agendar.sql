-- ============================================================================
-- SICOM-ICEO | 140 — Correctivos de recepción por agendar (P3)
-- ----------------------------------------------------------------------------
-- Cuando una No Conformidad se "planifica" (fn_planificar_nc), se crea su OT
-- correctiva pero todavía NO está agendada en un día del Plan Semanal. Esta
-- vista lista esas OT (NC planificadas, OT abierta, sin jornada aún) para
-- mostrarlas como tercer bloque arrastrable en el Plan Semanal.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE VIEW v_nc_ot_por_agendar AS
SELECT nc.id AS nc_id, nc.plan_ot_id AS ot_id, o.folio AS ot_folio,
       nc.activo_id, a.patente, a.codigo, nc.descripcion, nc.severidad,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias
FROM no_conformidades nc
JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
JOIN activos a ON a.id = nc.activo_id
WHERE nc.plan_ot_id IS NOT NULL
  AND nc.estado_planificacion = 'planificada'
  AND o.estado IN ('creada','asignada')
  AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots tps WHERE tps.ot_id = nc.plan_ot_id);

SELECT count(*) AS correctivos_recepcion_por_agendar FROM v_nc_ot_por_agendar;
