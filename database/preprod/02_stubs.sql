-- Stubs de dependencias NO relevantes para la seguridad (matemática de fiabilidad
-- y proyección de stock). Se declaran ANTES de la base porque la fn_reporte
-- pre-185 es LANGUAGE sql (valida dependencias en tiempo de creación).
-- DIFERENCIA CONOCIDA vs prod: estos stubs devuelven datos representativos, no el
-- cálculo real. Lo que se prueba (guard, grants, contrato de claves) es
-- independiente de estos valores.
SET client_min_messages = warning;

CREATE OR REPLACE FUNCTION fn_calcular_fiabilidad_activo(p_activo uuid, p_ini date, p_fin date)
RETURNS TABLE(activo_id uuid, patente varchar, categoria_uso categoria_uso_enum,
  dias_observados integer, dias_up integer, dias_down integer, eventos_falla integer,
  mtbf_dias numeric, mttr_dias numeric, disponibilidad_inherente numeric, disponibilidad_fisica numeric)
LANGUAGE sql STABLE AS $$
  SELECT p_activo, 'STUB'::varchar, 'arriendo_comercial'::categoria_uso_enum,
         30, 27, 3, 2, 13.5::numeric, 1.5::numeric, 0.90::numeric, 0.90::numeric;
$$;

CREATE OR REPLACE FUNCTION fn_calcular_fiabilidad_flota(p_ini date, p_fin date)
RETURNS TABLE(categoria categoria_uso_enum, total_equipos bigint, dias_equipo bigint,
  dias_up bigint, dias_down bigint, eventos_falla_total bigint, disponibilidad_fisica numeric,
  utilizacion_bruta numeric, mtbf_agregado numeric, mttr_agregado numeric)
LANGUAGE sql STABLE AS $$
  SELECT 'arriendo_comercial'::categoria_uso_enum, 1::bigint, 30::bigint,
         27::bigint, 3::bigint, 2::bigint, 0.90::numeric, 0.60::numeric, 13.5::numeric, 1.5::numeric;
$$;

CREATE OR REPLACE FUNCTION fn_estado_por_geocerca(p_activo uuid)
RETURNS char LANGUAGE sql STABLE AS $$ SELECT NULL::char; $$;

-- Vistas stub que consume fn_reporte.
CREATE OR REPLACE VIEW v_activo_ultimo_arriendo AS
  SELECT NULL::uuid AS activo_id, NULL::text AS tipo_uso, NULL::text AS cliente,
         NULL::text AS lugar, NULL::date AS fecha_inicio, NULL::date AS fecha_fin,
         NULL::int AS dias, NULL::boolean AS vigente
  WHERE false;

CREATE OR REPLACE VIEW v_combustible_proyeccion_stock AS
  SELECT e.codigo AS estanque_codigo, e.nombre AS estanque_nombre, e.capacidad_lt,
         e.stock_teorico_lt AS stock_actual,
         COALESCE(e.stock_minimo_alerta_lt, 0) AS stock_minimo,
         30::numeric AS dias_cobertura, NULL::date AS fecha_agotamiento_estimada,
         'ok'::text AS severidad
  FROM combustible_estanques e
  WHERE e.activo;
