-- 631 — El selector de mes de arriba filtra todo el panel (Manuel 2026-10-20).
-- La comparación con los 3 años anteriores acepta un mes: ese mes en cada año
-- (si es el mes en curso, hasta el mismo día). Sin mes, igual que MIG629-630.

DROP FUNCTION IF EXISTS rpc_costos_comparado_misma_fecha(text[], text, integer);
CREATE OR REPLACE FUNCTION public.rpc_costos_comparado_misma_fecha(
    p_areas text[] DEFAULT NULL::text[], p_fuente text DEFAULT 'oc', p_anios integer DEFAULT 3,
    p_mes date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    v_hoy   DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    v_n     INTEGER := least(greatest(coalesce(p_anios, 3), 1), 10);
    v_mes   DATE := date_trunc('month', p_mes)::DATE;
    -- Año de referencia: el del mes elegido, o el año en curso.
    v_ref   INTEGER := coalesce(extract(year FROM v_mes)::INTEGER, extract(year FROM v_hoy)::INTEGER);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_fuente NOT IN ('oc', 'bodega') THEN
        RAISE EXCEPTION 'Fuente no válida: %', p_fuente;
    END IF;

    WITH base AS (
        -- Sin mes: 1-ene → mismo día y mes de hoy en cada año.
        -- Con mes: ese mes en cada año; si es el mes en curso, hasta el mismo día.
        SELECT a AS anio,
               CASE WHEN v_mes IS NULL THEN make_date(a, 1, 1)
                    ELSE make_date(a, extract(month FROM v_mes)::INTEGER, 1) END AS desde,
               CASE WHEN v_mes IS NULL OR v_mes = date_trunc('month', v_hoy)::DATE
                    THEN extract(month FROM coalesce(v_mes, v_hoy))::INTEGER END AS mes_corte,
               coalesce(extract(month FROM v_mes)::INTEGER, 0) AS mes_entero
          FROM generate_series(v_ref - v_n, v_ref) a
    ), cortes AS (
        -- Corte por día; el 29-feb se compara contra el 28-feb.
        SELECT anio, desde,
               CASE WHEN mes_corte IS NOT NULL
                    THEN make_date(anio, mes_corte,
                                   least(extract(day FROM v_hoy)::INTEGER,
                                         extract(day FROM (make_date(anio, mes_corte, 1) + INTERVAL '1 month - 1 day'))::INTEGER))
                    ELSE (make_date(anio, mes_entero, 1) + INTERVAL '1 month - 1 day')::DATE END AS hasta
          FROM base
    ), todo AS (
        SELECT k.anio, extract(month FROM v.fecha)::INTEGER AS mes, v.total, v.cod_prod,
               v.es_mercaderia, v.es_inversion, coalesce(c.area, 'sin_clasificar') AS area
          FROM cortes k
          JOIN v_costos_linea v ON v.fuente = p_fuente AND v.fecha BETWEEN k.desde AND k.hasta
          LEFT JOIN softland_cc c ON c.codigo = v.codi_cc
    ), lin AS (
        SELECT anio, mes, total, (left(cod_prod, 3) = 'SER') AS es_servicio, (area = 'equipo') AS a_equipo
          FROM todo WHERE NOT es_mercaderia AND area = ANY (v_areas)
    ), inv AS (
        SELECT anio, sum(total) AS inversion FROM todo WHERE es_inversion GROUP BY anio
    )
    SELECT jsonb_build_object(
        'fuente', p_fuente,
        'hoy', v_hoy,
        'mes', v_mes,
        'anios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'anio', k.anio, 'desde', k.desde, 'hasta', k.hasta,
                     'total', coalesce(t.total, 0), 'servicios', coalesce(t.servicios, 0),
                     'asignado_equipo', coalesce(t.asignado_equipo, 0),
                     'inversion', coalesce(i.inversion, 0)) ORDER BY k.anio), '[]')
                    FROM cortes k
                    LEFT JOIN (SELECT anio, sum(total) AS total,
                                      sum(total) FILTER (WHERE es_servicio) AS servicios,
                                      sum(total) FILTER (WHERE a_equipo) AS asignado_equipo
                                 FROM lin GROUP BY anio) t ON t.anio = k.anio
                    LEFT JOIN inv i ON i.anio = k.anio),
        'por_mes', (SELECT coalesce(jsonb_agg(jsonb_build_object('anio', anio, 'mes', mes, 'total', total)
                                              ORDER BY anio, mes), '[]')
                      FROM (SELECT anio, mes, sum(total) AS total FROM lin GROUP BY anio, mes) x),
        'datos_desde', CASE WHEN p_fuente = 'oc' THEN (SELECT min(fecha_oc) FROM softland_oc WHERE estado = 'AP')
                            ELSE (SELECT min(fecha) FROM softland_doc) END
    ) INTO r;
    RETURN r;
END $function$;

REVOKE ALL ON FUNCTION rpc_costos_comparado_misma_fecha(text[], text, integer, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_costos_comparado_misma_fecha(text[], text, integer, date) TO authenticated, anon;
