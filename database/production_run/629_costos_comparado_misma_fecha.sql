-- 629 — Costo a la misma fecha contra los 3 años anteriores (Manuel 2026-10-20):
-- el acumulado desde 2014 (MIG627) no sirve para decidir; lo útil es comparar
-- el año en curso hasta hoy (1-ene → mismo día y mes) con el mismo tramo de
-- los 3 años anteriores. Mismo criterio del panel (fuente, sin mercadería,
-- áreas de operación salvo que se pidan administración y comercial).
-- Corte por DÍA, no por mes: el 20-oct se compara contra el 20-oct.

CREATE OR REPLACE FUNCTION public.rpc_costos_comparado_misma_fecha(
    p_areas text[] DEFAULT NULL::text[], p_fuente text DEFAULT 'oc', p_anios integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    v_hoy   DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    v_n     INTEGER := least(greatest(coalesce(p_anios, 3), 1), 10);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_fuente NOT IN ('oc', 'bodega') THEN
        RAISE EXCEPTION 'Fuente no válida: %', p_fuente;
    END IF;

    WITH cortes AS (
        -- Mismo día y mes en cada año; el 29-feb se compara contra el 28-feb.
        SELECT a AS anio, make_date(a, 1, 1) AS desde,
               make_date(a, extract(month FROM v_hoy)::INTEGER,
                         least(extract(day FROM v_hoy)::INTEGER,
                               extract(day FROM (make_date(a, extract(month FROM v_hoy)::INTEGER, 1)
                                                 + INTERVAL '1 month - 1 day'))::INTEGER)) AS hasta
          FROM generate_series(extract(year FROM v_hoy)::INTEGER - v_n, extract(year FROM v_hoy)::INTEGER) a
    ), lin AS (
        SELECT k.anio, extract(month FROM v.fecha)::INTEGER AS mes, v.total,
               (left(v.cod_prod, 3) = 'SER') AS es_servicio,
               (coalesce(c.area, 'sin_clasificar') = 'equipo') AS a_equipo
          FROM cortes k
          JOIN v_costos_linea v ON v.fuente = p_fuente AND v.fecha BETWEEN k.desde AND k.hasta
          LEFT JOIN softland_cc c ON c.codigo = v.codi_cc
         WHERE NOT v.es_mercaderia
           AND coalesce(c.area, 'sin_clasificar') = ANY (v_areas)
    )
    SELECT jsonb_build_object(
        'fuente', p_fuente,
        'hoy', v_hoy,
        'anios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'anio', k.anio, 'desde', k.desde, 'hasta', k.hasta,
                     'total', coalesce(t.total, 0), 'servicios', coalesce(t.servicios, 0),
                     'asignado_equipo', coalesce(t.asignado_equipo, 0)) ORDER BY k.anio), '[]')
                    FROM cortes k
                    LEFT JOIN (SELECT anio, sum(total) AS total,
                                      sum(total) FILTER (WHERE es_servicio) AS servicios,
                                      sum(total) FILTER (WHERE a_equipo) AS asignado_equipo
                                 FROM lin GROUP BY anio) t ON t.anio = k.anio),
        'por_mes', (SELECT coalesce(jsonb_agg(jsonb_build_object('anio', anio, 'mes', mes, 'total', total)
                                              ORDER BY anio, mes), '[]')
                      FROM (SELECT anio, mes, sum(total) AS total FROM lin GROUP BY anio, mes) x),
        -- Hasta dónde llegan los datos de cada fuente (si un año viejo está vacío, se ve aquí).
        'datos_desde', CASE WHEN p_fuente = 'oc' THEN (SELECT min(fecha_oc) FROM softland_oc WHERE estado = 'AP')
                            ELSE (SELECT min(fecha) FROM softland_doc) END
    ) INTO r;
    RETURN r;
END $function$;
REVOKE ALL ON FUNCTION rpc_costos_comparado_misma_fecha(text[], text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_costos_comparado_misma_fecha(text[], text, integer) TO authenticated, anon;
