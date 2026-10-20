-- 630 — La compra de equipos es inversión, no costo de operación (Manuel
-- 2026-10-20). En agosto de 2024 se aprobaron 7 camiones Scania, 2 grúas PM,
-- estanques y carrocerías: 1.124 MM en la familia EQUMAQ (maquinaria). Sumados
-- al costo, 2024 aparecía 3,5 veces sobre los demás años y la comparación a la
-- misma fecha (MIG629) no servía.
--
-- v_costos_linea gana `es_inversion` (código EQUMAQ*, en las dos fuentes) y
-- `es_mercaderia` pasa a significar «no es costo de operación»: combustible de
-- reventa/stock (MIG628) O inversión. Así todas las funciones del panel, que ya
-- filtran NOT es_mercaderia / NOT es_petroleo, la dejan fuera sin tocarlas.
-- EQUINS (instrumentos) y EQUECO (teléfonos, computación) siguen como costo.
-- La comparación a la misma fecha muestra la inversión aparte.

DROP MATERIALIZED VIEW IF EXISTS mv_softland_costo_mes;
DROP VIEW IF EXISTS v_costos_linea;
CREATE VIEW v_costos_linea AS
SELECT 'bodega'::TEXT                        AS fuente,
       d.fecha,
       d.codi_cc::TEXT                       AS codi_cc,
       l.cod_prod::TEXT                      AS cod_prod,
       l.des_prod::TEXT                      AS des_prod,
       l.cantidad, l.precio_unit, l.total,
       d.folio,
       d.concepto::TEXT                      AS concepto,
       coalesce(d.bodega, d.cod_bode)::TEXT  AS origen,       -- bodega
       d.glosa::TEXT                         AS glosa,
       (l.cod_prod = 'CLUPETPET003' OR l.cod_prod LIKE 'EQUMAQ%') AS es_mercaderia,   -- no es costo
       (l.cod_prod LIKE 'EQUMAQ%')           AS es_inversion
  FROM softland_doc d
  JOIN softland_linea l USING (tipo, cod_bode, nro_int)
UNION ALL
SELECT 'oc',
       o.fecha_oc,
       coalesce(l.codi_cc, o.codi_cc),
       l.cod_prod,
       l.det_prod,
       l.cantidad, l.precio_unit, l.total,
       o.num_oc,
       'OC',
       o.proveedor,                                            -- proveedor
       NULL::TEXT,
       ((l.cod_prod LIKE 'CLUPET%' AND coalesce(l.codi_cc, o.codi_cc) IN ('OC-TA-03', 'OC-TA-04'))
        OR l.cod_prod LIKE 'EQUMAQ%'),
       (l.cod_prod LIKE 'EQUMAQ%')
  FROM softland_oc o
  JOIN softland_oc_linea l USING (num_inter_oc)
 WHERE o.estado = 'AP';                                        -- solo OC válidas
REVOKE ALL ON v_costos_linea FROM PUBLIC, anon, authenticated;

CREATE MATERIALIZED VIEW mv_softland_costo_mes AS
SELECT
    v.fuente,
    date_trunc('month', v.fecha)::DATE          AS mes,
    v.concepto,
    coalesce(v.codi_cc, '(SIN CC)')             AS codi_cc,
    coalesce(c.area, 'sin_clasificar')          AS area,
    c.activo_id,
    coalesce(f.nombre, c.zona)                  AS zona,
    left(v.cod_prod, 3)                         AS grupo,
    left(v.cod_prod, 6)                         AS familia,
    v.es_mercaderia                             AS es_petroleo,   -- nombre histórico: «no es costo»
    sum(v.cantidad)                             AS cantidad,
    sum(v.total)                                AS total,
    count(*)                                    AS lineas,
    count(*) FILTER (WHERE v.total = 0)         AS lineas_sin_precio
FROM v_costos_linea v
LEFT JOIN softland_cc c ON c.codigo = v.codi_cc
LEFT JOIN activos a ON a.id = c.activo_id
LEFT JOIN faenas f ON f.id = a.faena_id
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
CREATE INDEX IF NOT EXISTS idx_mv_softland_costo_mes_mes ON mv_softland_costo_mes (fuente, mes);
REVOKE ALL ON mv_softland_costo_mes FROM PUBLIC, anon, authenticated;

-- Comparación a la misma fecha (MIG629) + inversión del mismo tramo, aparte.
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
