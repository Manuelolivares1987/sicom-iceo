-- ============================================================================
-- SICOM-ICEO | 112 — Bandeja sugerencias GPS: mostrar lo ya confirmado del día
-- ============================================================================
-- Para poder CORREGIR un día ya cerrado, fn_sugerencias_estado_gps ahora
-- devuelve tambien 'estado_guardado': el estado que YA esta guardado en
-- estado_diario_flota para la fecha seleccionada (NULL si no hay). La UI lo
-- muestra y preselecciona el desplegable con ese valor, asi se ve que hay y se
-- cambia solo lo incorrecto.
-- (Cambia la firma de la funcion -> DROP + CREATE; se re-otorgan permisos.)
-- ============================================================================

DROP FUNCTION IF EXISTS fn_sugerencias_estado_gps(date);

CREATE FUNCTION public.fn_sugerencias_estado_gps(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_actual character,
               estado_sugerido character, estado_guardado character, zona text,
               gps_ts timestamp with time zone, coincide boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    a.id,
    a.patente::text,
    a.nombre::text,
    prev.estado_codigo AS estado_actual,
    COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::character(1) AS estado_sugerido,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = a.id AND e.fecha = p_fecha LIMIT 1) AS estado_guardado,
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

GRANT EXECUTE ON FUNCTION fn_sugerencias_estado_gps(date) TO anon, authenticated;

-- ── Verificacion ───────────────────────────────────────────────────────────
DO $$
DECLARE v_total INT; v_con_guardado INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE estado_guardado IS NOT NULL)
      INTO v_total, v_con_guardado
      FROM fn_sugerencias_estado_gps('2026-06-01');
    RAISE NOTICE '== estado_guardado en bandeja (01-jun) ==';
    RAISE NOTICE 'equipos: % | con valor guardado ese dia: %', v_total, v_con_guardado;
END $$;
