-- 627 — Costo acumulado total de operaciones (Manuel 2026-10-20): en Gerencia →
-- Costos de Operación, arriba del panel, cuánto se lleva gastado en total desde
-- que hay registros de Softland, año por año, con el mismo criterio del panel:
-- salidas de bodega sin petróleo (se revende), áreas de operación salvo que se
-- pidan administración y comercial.
-- ADITIVA: una RPC nueva detrás de la misma puerta (fn_costos_operacion_puede_ver),
-- así también responde en el link con token (MIG620).

CREATE OR REPLACE FUNCTION public.rpc_costos_operacion_acumulado(p_areas text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH base AS (
        SELECT m.mes, m.total
          FROM mv_softland_costo_mes m
         WHERE m.area = ANY (v_areas)
           AND NOT m.es_petroleo
    ), anio AS (
        SELECT extract(year FROM mes)::INTEGER AS anio, sum(total) AS total, count(DISTINCT mes) AS meses
          FROM base GROUP BY 1
    )
    SELECT jsonb_build_object(
        'desde', (SELECT min(mes) FROM base),
        'hasta', (SELECT max(mes) FROM base),
        'total', coalesce((SELECT sum(total) FROM base), 0),
        'por_anio', (SELECT coalesce(jsonb_agg(jsonb_build_object('anio', anio, 'total', total, 'meses', meses)
                                               ORDER BY anio), '[]') FROM anio)
    ) INTO r;
    RETURN r;
END $function$;

REVOKE ALL ON FUNCTION rpc_costos_operacion_acumulado(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_costos_operacion_acumulado(text[]) TO authenticated, anon;

SELECT (fn_costos_operacion_panel_datos(current_date, current_date) IS NOT NULL) AS ok,
       (SELECT round(sum(total) / 1e6, 1) FROM mv_softland_costo_mes
         WHERE NOT es_petroleo AND area NOT IN ('administracion','comercial')) AS acumulado_mm;
