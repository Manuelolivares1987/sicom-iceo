-- ============================================================================
-- 96_reporte_flota_publico.sql
-- ----------------------------------------------------------------------------
-- RPC pública (SECURITY DEFINER, grant anon) que devuelve la "realidad de la
-- flota" para compartir por link sin login: distribución por estado del último
-- día, por operación, por cliente, y disponibilidad/utilización del mes.
-- Solo vehículos de flota (no bombas/estanques). Solo lectura agregada.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reporte_flota_publico()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER AS $$
WITH veh AS (
  SELECT id FROM activos
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
  'por_estado',     (SELECT jsonb_object_agg(estado_codigo, n)
                       FROM (SELECT estado_codigo, count(*) n FROM hoy GROUP BY 1) s),
  'por_operacion',  (SELECT jsonb_object_agg(coalesce(operacion,'Sin asignar'), n)
                       FROM (SELECT operacion, count(*) n FROM hoy GROUP BY 1) s),
  'por_cliente',    (SELECT jsonb_agg(jsonb_build_object('cliente', coalesce(cliente,'Sin contrato'), 'equipos', n) ORDER BY n DESC)
                       FROM (SELECT cliente, count(*) n FROM hoy GROUP BY 1) s),
  'disponibilidad', (SELECT round(100.0 * up / nullif(dias,0), 1) FROM mes),
  'utilizacion',    (SELECT round(100.0 * util / nullif(dias,0), 1) FROM mes)
);
$$;

GRANT EXECUTE ON FUNCTION fn_reporte_flota_publico() TO anon, authenticated;
