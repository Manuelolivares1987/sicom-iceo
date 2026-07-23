-- ============================================================================
-- SICOM-ICEO | 241 — fn_activo_geocerca_actual: misma lógica que "Zona GPS" +
--                     geocerca más cercana cuando está fuera de todas
-- ----------------------------------------------------------------------------
-- Pedido Manuel (2026-07-22): la ubicación del modal no coincidía con la
-- "Zona GPS" de la página de Sugerencias.
--
-- Causa: la columna "Zona GPS" (fn_sugerencias_estado_gps / MIG112) resuelve la
-- geocerca con  ORDER BY (tipo='faena_cliente') DESC, radio_m ASC.
-- fn_activo_geocerca_actual (MIG240) además priorizaba la geocerca del contrato,
-- así que en teoría podían diferir. Se ALINEAN para que siempre coincidan.
--
-- Además: si el equipo está FUERA de toda geocerca (ej. SBPG-12, cerca de
-- Copiapó, a 62 km de la geocerca más próxima), se devuelve la geocerca más
-- cercana + distancia en km, para orientar al planificador (y evidenciar que
-- falta una geocerca en ese lugar). IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_activo_geocerca_actual(p_activo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_lat numeric; v_lng numeric; v_ts timestamptz;
    v_nombre text; v_near_nombre text; v_near_km numeric;
BEGIN
    SELECT latitud, longitud, ts_gps INTO v_lat, v_lng, v_ts
      FROM gps_estado_actual WHERE activo_id = p_activo_id;
    IF v_lat IS NULL THEN
        RETURN jsonb_build_object('nombre', NULL, 'ts_gps', NULL, 'motivo', 'sin_gps');
    END IF;

    -- Geocerca actual — MISMA lógica que la columna "Zona GPS" de Sugerencias
    -- (fn_sugerencias_estado_gps, MIG112): faena_cliente primero, luego radio menor.
    SELECT g.nombre INTO v_nombre
    FROM gps_geocercas g
    WHERE g.activo AND fn_punto_en_geocerca(v_lat, v_lng, g.id)
    ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC
    LIMIT 1;

    IF v_nombre IS NOT NULL THEN
        RETURN jsonb_build_object(
            'nombre', v_nombre, 'ts_gps', v_ts,
            'lat', v_lat, 'lng', v_lng, 'motivo', NULL
        );
    END IF;

    -- Fuera de toda geocerca: la más cercana + distancia (km) para orientar.
    SELECT g.nombre,
           ROUND((6371.0 * acos(LEAST(1,
              cos(radians(v_lat)) * cos(radians(g.centro_lat)) *
              cos(radians(g.centro_lng) - radians(v_lng))
              + sin(radians(v_lat)) * sin(radians(g.centro_lat)))))::numeric, 1)
      INTO v_near_nombre, v_near_km
      FROM gps_geocercas g
     WHERE g.activo AND g.centro_lat IS NOT NULL AND g.centro_lng IS NOT NULL
     ORDER BY 2 ASC
     LIMIT 1;

    RETURN jsonb_build_object(
        'nombre', NULL, 'ts_gps', v_ts, 'lat', v_lat, 'lng', v_lng,
        'motivo', 'fuera_de_geocercas',
        'cercana_nombre', v_near_nombre, 'cercana_km', v_near_km
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_activo_geocerca_actual(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_activo_geocerca_actual(uuid) TO authenticated;

-- Validación
DO $$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE '== muestra fn_activo_geocerca_actual ==';
    FOR r IN
        SELECT a.patente, fn_activo_geocerca_actual(a.id) AS geo
        FROM activos a JOIN gps_estado_actual g ON g.activo_id=a.id
        WHERE g.latitud IS NOT NULL
        ORDER BY a.patente LIMIT 12
    LOOP
        RAISE NOTICE '  % -> nombre=[%] cercana=[% a % km]',
            r.patente, r.geo->>'nombre', r.geo->>'cercana_nombre', r.geo->>'cercana_km';
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
