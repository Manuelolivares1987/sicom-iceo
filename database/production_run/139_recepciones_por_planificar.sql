-- ============================================================================
-- SICOM-ICEO | 139 — Recepciones por planificar (gatillo Sugerencias -> Plan)
-- ----------------------------------------------------------------------------
-- Cuando el planificador marca un equipo como 'R' (Recepción) en Sugerencias de
-- estado (estado_diario_flota.estado_codigo='R'), el equipo debe aparecer en el
-- Plan Semanal como "Recepción por planificar". Al arrastrarlo a un día se crea
-- la OT de inspección de recepción (fn_iniciar_informe_recepcion).
--
-- Esta vista lista los equipos cuyo ÚLTIMO estado es 'R' y que aún NO tienen una
-- OT de inspección de recepción abierta. IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE VIEW v_recepciones_por_planificar AS
WITH ult AS (
    SELECT DISTINCT ON (e.activo_id) e.activo_id, e.estado_codigo, e.fecha
    FROM estado_diario_flota e
    ORDER BY e.activo_id, e.fecha DESC
)
SELECT a.id AS activo_id, a.patente, a.codigo, a.nombre, u.fecha AS fecha_recepcion
FROM ult u
JOIN activos a ON a.id = u.activo_id
WHERE u.estado_codigo = 'R'
  AND a.fecha_baja IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM ordenes_trabajo o
      WHERE o.activo_id = a.id
        AND o.tipo = 'inspeccion_recepcion'
        AND o.estado IN ('creada','asignada','en_ejecucion','pausada')
  );

SELECT count(*) AS recepciones_por_planificar FROM v_recepciones_por_planificar;
