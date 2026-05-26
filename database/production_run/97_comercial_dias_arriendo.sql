-- ============================================================================
-- 97_comercial_dias_arriendo.sql
-- ----------------------------------------------------------------------------
-- Vista comercial por equipo: cuántos días ha estado arrendado (A o C), su
-- estado actual, y el ÚLTIMO cliente/contrato que tuvo arrendado (incluso si
-- ya dejó de estarlo) + cuántos días lleva sin arriendo.
-- Solo vehículos de flota.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_comercial_equipos(p_ini date, p_fin date)
RETURNS TABLE(
  activo_id            uuid,
  patente              text,
  equipamiento         text,
  estado_actual        char(1),
  cliente_actual       text,
  dias_arrendado       int,
  ultimo_cliente       text,
  fecha_ultimo_arriendo date,
  dias_sin_arriendo    int
)
LANGUAGE sql STABLE AS $$
  WITH veh AS (
    SELECT id, patente, nombre
    FROM activos
    WHERE estado <> 'dado_baja'
      AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
  )
  SELECT
    v.id,
    v.patente,
    v.nombre,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha <= p_fin ORDER BY e.fecha DESC LIMIT 1),
    (SELECT e.cliente FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha <= p_fin ORDER BY e.fecha DESC LIMIT 1),
    (SELECT count(*)::int FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha BETWEEN p_ini AND p_fin
         AND e.estado_codigo IN ('A','C')),
    (SELECT e.cliente FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin
       ORDER BY e.fecha DESC LIMIT 1),
    (SELECT max(e.fecha) FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin),
    (SELECT (p_fin - max(e.fecha))::int FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin)
  FROM veh v
  ORDER BY v.patente;
$$;

GRANT EXECUTE ON FUNCTION fn_comercial_equipos(date, date) TO authenticated;
