-- ============================================================================
-- 95_sugerencias_estado_gps.sql
-- ----------------------------------------------------------------------------
-- Cambio de enfoque: el estado NO se auto-aplica desde geocerca. En su lugar se
-- GENERAN SUGERENCIAS para que el planificador confirme.
--   1. Quita el cron 'estado-auto-geocerca' (ya no auto-aplica).
--   2. fn_sugerencias_estado_gps(fecha): por cada equipo con GPS devuelve el
--      estado actual (último día real, ej. 24) vs el estado sugerido por su
--      ubicación GPS/geocerca, la zona y si coinciden.
--   3. rpc_confirmar_estado_dia(activo, fecha, estado): el planificador aplica
--      la sugerencia confirmada (override_manual = true).
-- NO aplica nada automáticamente.
-- ============================================================================

-- 1. Quitar el cron automático
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'estado-auto-geocerca') THEN
    PERFORM cron.unschedule('estado-auto-geocerca');
  END IF;
END $$;

-- 2. Función de sugerencias (no aplica nada, solo sugiere)
CREATE OR REPLACE FUNCTION fn_sugerencias_estado_gps(p_fecha date DEFAULT current_date)
RETURNS TABLE(
  activo_id        uuid,
  patente          text,
  equipamiento     text,
  estado_actual    char(1),
  estado_sugerido  char(1),
  zona             text,
  gps_ts           timestamptz,
  coincide         boolean
)
LANGUAGE sql STABLE AS $$
  SELECT
    a.id,
    a.patente,
    a.nombre,
    (SELECT e.estado_codigo FROM estado_diario_flota e
      WHERE e.activo_id = a.id AND e.fecha < p_fecha
      ORDER BY e.fecha DESC LIMIT 1) AS estado_actual,
    fn_estado_por_geocerca(a.id) AS estado_sugerido,
    (SELECT g.nombre FROM gps_geocercas g
      WHERE g.activo AND fn_punto_en_geocerca(ga.latitud, ga.longitud, g.id)
      ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC LIMIT 1) AS zona,
    ga.ts_gps,
    ((SELECT e.estado_codigo FROM estado_diario_flota e
        WHERE e.activo_id = a.id AND e.fecha < p_fecha
        ORDER BY e.fecha DESC LIMIT 1) = fn_estado_por_geocerca(a.id)) AS coincide
  FROM activos a
  JOIN gps_estado_actual ga ON ga.activo_id = a.id AND ga.latitud IS NOT NULL
  WHERE a.estado <> 'dado_baja'
  ORDER BY a.patente;
$$;
GRANT EXECUTE ON FUNCTION fn_sugerencias_estado_gps(date) TO authenticated;

-- 3. Confirmar una sugerencia (lo aplica el planificador)
CREATE OR REPLACE FUNCTION rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado char)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO estado_diario_flota
    (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override, actualizado_por, actualizado_at)
  VALUES
    (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)', auth.uid(), now())
  ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
        motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
        actualizado_at = now(), updated_at = now();
END $$;
GRANT EXECUTE ON FUNCTION rpc_confirmar_estado_dia(uuid, date, char) TO authenticated;
