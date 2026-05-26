-- ============================================================================
-- 98_reporte_publico_dias_arriendo.sql
-- ----------------------------------------------------------------------------
-- Extiende fn_reporte_flota_publico() para incluir el detalle por equipo:
-- días arrendado (A+C) en el año, estado actual, último cliente arrendado y
-- días sin arriendo. Para que el reporte público (link + PDF) lo muestre.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reporte_flota_publico()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER AS $$
WITH veh AS (
  SELECT id, patente, nombre FROM activos
   WHERE estado <> 'dado_baja'
     AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
),
ult AS (
  SELECT max(fecha) AS f FROM estado_diario_flota WHERE activo_id IN (SELECT id FROM veh)
),
hoy AS (
  SELECT e.estado_codigo, e.cliente, e.operacion
  FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
  WHERE e.fecha = (SELECT f FROM ult)
),
mes AS (
  SELECT count(*) AS dias,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','D','L','U')) AS up,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','L')) AS util
  FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
  WHERE e.fecha >= date_trunc('month', (SELECT f FROM ult))
)
SELECT jsonb_build_object(
  'fecha',          (SELECT f FROM ult),
  'total',          (SELECT count(*) FROM hoy),
  'por_estado',     (SELECT jsonb_object_agg(estado_codigo, n) FROM (SELECT estado_codigo, count(*) n FROM hoy GROUP BY 1) s),
  'por_operacion',  (SELECT jsonb_object_agg(coalesce(operacion,'Sin asignar'), n) FROM (SELECT operacion, count(*) n FROM hoy GROUP BY 1) s),
  'por_cliente',    (SELECT jsonb_agg(jsonb_build_object('cliente', coalesce(cliente,'Sin contrato'), 'equipos', n) ORDER BY n DESC) FROM (SELECT cliente, count(*) n FROM hoy GROUP BY 1) s),
  'disponibilidad', (SELECT round(100.0 * up / nullif(dias,0), 1) FROM mes),
  'utilizacion',    (SELECT round(100.0 * util / nullif(dias,0), 1) FROM mes),
  'equipos',        (
    SELECT jsonb_agg(jsonb_build_object(
             'patente', q.patente, 'equipamiento', q.equipamiento, 'estado', q.estado,
             'dias_arrendado', q.dias, 'ultimo_cliente', q.ultimo_cliente, 'dias_sin_arriendo', q.dias_sin
           ) ORDER BY q.dias DESC)
    FROM (
      SELECT v.patente, v.nombre AS equipamiento,
        (SELECT e.estado_codigo FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha<=(SELECT f FROM ult) ORDER BY e.fecha DESC LIMIT 1) AS estado,
        (SELECT count(*)::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha >= date_trunc('year',(SELECT f FROM ult)) AND e.fecha<=(SELECT f FROM ult) AND e.estado_codigo IN ('A','C')) AS dias,
        (SELECT e.cliente FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.estado_codigo IN ('A','C') AND e.fecha<=(SELECT f FROM ult) ORDER BY e.fecha DESC LIMIT 1) AS ultimo_cliente,
        (SELECT ((SELECT f FROM ult) - max(e.fecha))::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.estado_codigo IN ('A','C') AND e.fecha<=(SELECT f FROM ult)) AS dias_sin
      FROM veh v
    ) q
  )
);
$$;

GRANT EXECUTE ON FUNCTION fn_reporte_flota_publico() TO anon, authenticated;
