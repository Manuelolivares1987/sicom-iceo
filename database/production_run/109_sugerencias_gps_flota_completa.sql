-- ============================================================================
-- SICOM-ICEO | 109 — Bandeja de sugerencias GPS cubre la FLOTA COMPLETA
-- ============================================================================
-- La bandeja /flota/sugerencias solo mostraba equipos con señal GPS y al
-- "confirmar todas" solo escribía los que cambiaban (coincide=false). Por eso
-- al cerrar junio solo quedaron 22 filas y el informe muestra 22.
--
-- Fix: fn_sugerencias_estado_gps ahora devuelve los 55 vehículos de flota
-- (LEFT JOIN al GPS para incluir los sin señal), con:
--   - estado_actual  = estado del día anterior (semilla)
--   - estado_sugerido = geocerca, fallback al día previo, luego 'D' (nunca NULL)
--   - coincide        = sugerido == previo
-- Así la persona puede cerrar TODA la flota desde la misma plataforma.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_sugerencias_estado_gps(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_actual character,
               estado_sugerido character, zona text, gps_ts timestamp with time zone, coincide boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    a.id,
    a.patente::text,
    a.nombre::text,
    prev.estado_codigo AS estado_actual,
    COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::character(1) AS estado_sugerido,
    (SELECT g.nombre FROM gps_geocercas g
       WHERE g.activo AND ga.latitud IS NOT NULL
         AND fn_punto_en_geocerca(ga.latitud, ga.longitud, g.id)
       ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC LIMIT 1) AS zona,
    ga.ts_gps,
    (prev.estado_codigo = COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')) AS coincide
  FROM activos a
  LEFT JOIN gps_estado_actual ga ON ga.activo_id = a.id
  LEFT JOIN LATERAL (
    SELECT e.estado_codigo
      FROM estado_diario_flota e
     WHERE e.activo_id = a.id AND e.fecha < p_fecha
     ORDER BY e.fecha DESC LIMIT 1
  ) prev ON true
  WHERE a.estado <> 'dado_baja'
    AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
  ORDER BY a.patente;
$function$;

-- ── Verificación ───────────────────────────────────────────────────────────
DO $$
DECLARE v_total INT; v_cambios INT; v_internos_cambio INT;
BEGIN
    SELECT count(*) INTO v_total FROM fn_sugerencias_estado_gps(CURRENT_DATE);
    SELECT count(*) INTO v_cambios FROM fn_sugerencias_estado_gps(CURRENT_DATE) WHERE coincide = false;
    SELECT count(*) INTO v_internos_cambio
      FROM fn_sugerencias_estado_gps(CURRENT_DATE) s JOIN activos a ON a.id=s.activo_id
     WHERE a.estado_comercial='uso_interno' AND s.coincide = false;
    RAISE NOTICE '== Bandeja GPS flota completa ==';
    RAISE NOTICE 'Equipos en bandeja: % (debe ser 55) | cambios sugeridos: % | uso interno con cambio: %',
                 v_total, v_cambios, v_internos_cambio;
    IF v_total <> 55 THEN RAISE EXCEPTION 'Se esperaban 55 equipos, hay %.', v_total; END IF;
END $$;
