-- ============================================================================
-- SICOM-ICEO | Migracion 129 — Cumplimiento checklist cliente: TODO equipo fuera
-- ----------------------------------------------------------------------------
-- Amplia v_checklist_cliente_cumplimiento (mig 127) para incluir TODO equipo
-- que esta fuera de nuestras instalaciones: arrendado, leasing o bajo contrato.
-- Se les exigira el checklist semanal por contrato.
-- IDEMPOTENTE (CREATE OR REPLACE VIEW).
-- ============================================================================

CREATE OR REPLACE VIEW v_checklist_cliente_cumplimiento AS
WITH fuera AS (
    SELECT a.id AS activo_id, a.patente, a.codigo, a.nombre,
           COALESCE(a.cliente_actual, c.cliente) AS cliente, a.contrato_id,
           a.estado_comercial::TEXT AS estado_comercial
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
    WHERE a.fecha_baja IS NULL
      AND (
        a.estado_comercial IN ('arrendado','leasing')
        OR (a.contrato_id IS NOT NULL
            AND COALESCE(a.estado_comercial::TEXT,'') NOT IN
                ('disponible','en_recepcion','en_venta','uso_interno'))
      )
),
ult AS (
    SELECT DISTINCT ON (activo_id) activo_id, id AS ultimo_id, fecha AS ultima_fecha,
           anio, semana_iso, tiene_novedad, items_no_ok, ot_generada_id
    FROM checklist_cliente_semanal
    ORDER BY activo_id, fecha DESC, created_at DESC
)
-- Orden de columnas IDENTICO a mig 127 (CREATE OR REPLACE no reordena);
-- estado_comercial se agrega al final.
SELECT f.activo_id, f.patente, f.codigo, f.nombre, f.cliente, f.contrato_id,
       u.ultimo_id, u.ultima_fecha, u.tiene_novedad, u.items_no_ok, u.ot_generada_id,
       (u.activo_id IS NOT NULL
        AND u.anio = EXTRACT(ISOYEAR FROM NOW())::INT
        AND u.semana_iso = EXTRACT(WEEK FROM NOW())::INT) AS check_esta_semana,
       (CURRENT_DATE - u.ultima_fecha) AS dias_desde_ultimo,
       CASE
         WHEN u.activo_id IS NULL THEN 'sin_check'
         WHEN (CURRENT_DATE - u.ultima_fecha) > 7 THEN 'atrasado'
         ELSE 'al_dia'
       END AS estado_cumplimiento,
       f.estado_comercial
FROM fuera f
LEFT JOIN ult u ON u.activo_id = f.activo_id;

SELECT count(*) AS equipos_fuera_instalaciones FROM v_checklist_cliente_cumplimiento;
