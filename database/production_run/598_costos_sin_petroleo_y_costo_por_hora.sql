-- ============================================================================
-- SICOM-ICEO | 598 — Costos de operación: sin petróleo y con costo por hora
-- ============================================================================
-- 1. El petróleo (CLUPETPET003) sale del panel. Manuel: «compramos petróleo
--    pero lo vendemos, por ende se sale de la gestión». Es mercadería: pasa
--    por bodega (casi todo al CC genérico OC-TA-03) para revenderse, no es
--    costo de operar la flota. La gasolina sí queda (consumo de camionetas).
--
-- 2. Costo por hora operada por equipo = gasto de bodega sin petróleo ÷ horas
--    del GPS (activo_horas_dia, MIG597). Las horas existen solo desde mayo
--    2026 y no para todos los equipos, así que cada equipo se mide SOLO en
--    los meses completos que tienen horas: dividir 12 meses de gasto por 5
--    meses de horas inflaría el costo. Se compara contra la mediana de su
--    tipo de equipo.
-- ============================================================================

-- Meses medidos por equipo: desde el primer mes completo con lecturas hasta
-- el último (si la última lectura es de antes del día 25, ese mes no cuenta).
CREATE OR REPLACE VIEW v_activo_horas_mes AS
WITH lim AS (
    SELECT activo_id, min(fecha) AS primera, max(fecha) AS ultima
      FROM activo_horas_dia GROUP BY activo_id
), rango AS (
    SELECT activo_id,
           (date_trunc('month', primera)
             + CASE WHEN extract(day FROM primera) > 3 THEN INTERVAL '1 month' ELSE INTERVAL '0' END)::DATE AS mes_ini,
           (date_trunc('month', ultima)
             - CASE WHEN extract(day FROM ultima) < 25
                     AND date_trunc('month', ultima) < date_trunc('month', (NOW() AT TIME ZONE 'America/Santiago'))
                    THEN INTERVAL '1 month' ELSE INTERVAL '0' END)::DATE AS mes_fin
      FROM lim
)
SELECT d.activo_id, date_trunc('month', d.fecha)::DATE AS mes,
       sum(d.horas) AS horas, sum(d.km) AS km,
       count(*) FILTER (WHERE d.horas > 0.5) AS dias_con_uso
  FROM v_activo_horas_dia d
  JOIN rango r ON r.activo_id = d.activo_id
 WHERE date_trunc('month', d.fecha)::DATE BETWEEN r.mes_ini AND r.mes_fin
 GROUP BY 1, 2;

COMMENT ON VIEW v_activo_horas_mes IS
    'Horas GPS por equipo y mes, solo meses completos medidos. Base del costo por hora. MIG598.';
GRANT SELECT ON v_activo_horas_mes TO authenticated;


CREATE OR REPLACE FUNCTION rpc_costos_operacion_panel(
    p_desde DATE, p_hasta DATE, p_areas TEXT[] DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_hasta DATE := date_trunc('month', p_hasta)::DATE;
    v_meses INTEGER := (extract(year FROM age(date_trunc('month', p_hasta), date_trunc('month', p_desde))) * 12
                       + extract(month FROM age(date_trunc('month', p_hasta), date_trunc('month', p_desde))))::INTEGER + 1;
    v_ant_desde DATE := (date_trunc('month', p_desde) - make_interval(months => v_meses))::DATE;
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH base AS (
        SELECT m.*, (m.mes BETWEEN v_desde AND v_hasta) AS en_periodo
          FROM mv_softland_costo_mes m
         WHERE m.mes BETWEEN v_ant_desde AND v_hasta
           AND m.area = ANY (v_areas)
           AND NOT m.es_petroleo                       -- mercadería, no costo
    ), per AS (SELECT * FROM base WHERE en_periodo),
    -- Costo por hora: por equipo, solo meses del período con horas medidas.
    medido AS (
        SELECT h.activo_id, sum(h.horas) AS horas, sum(h.km) AS km, count(*) AS meses,
               sum(cm.costo) AS costo
          FROM v_activo_horas_mes h
          LEFT JOIN (SELECT activo_id, mes, sum(total) AS costo FROM per
                      WHERE activo_id IS NOT NULL GROUP BY 1, 2) cm
            ON cm.activo_id = h.activo_id AND cm.mes = h.mes
         WHERE h.mes BETWEEN v_desde AND v_hasta
         GROUP BY h.activo_id
        HAVING sum(h.horas) >= 20                       -- con menos, el cociente no dice nada
    ), cph AS (
        SELECT m.activo_id, m.horas, m.km, m.meses, coalesce(m.costo, 0) AS costo,
               coalesce(m.costo, 0) / m.horas AS costo_hora,
               coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT) AS tipo_equipo
          FROM medido m JOIN activos a ON a.id = m.activo_id
    ), mediana AS (
        SELECT tipo_equipo, count(*) AS n,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY costo_hora) AS mediana
          FROM cph GROUP BY tipo_equipo
    )
    SELECT jsonb_build_object(
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'meses', v_meses,
                                      'anterior_desde', v_ant_desde),
        'kpi', (SELECT jsonb_build_object(
            'total',            coalesce(sum(total), 0),
            'total_anterior',   (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo),
            'asignado_equipo',  coalesce(sum(total) FILTER (WHERE area = 'equipo'), 0),
            'asignado_equipo_anterior', (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo AND area = 'equipo'),
            'epp',              coalesce(sum(total) FILTER (WHERE concepto = '08'), 0),
            'neumaticos',       coalesce(sum(total) FILTER (WHERE familia = 'REPNEU'), 0),
            'lineas',           coalesce(sum(lineas), 0),
            'lineas_sin_precio', coalesce(sum(lineas_sin_precio), 0),
            'equipos_con_gasto', count(DISTINCT activo_id),
            'sin_cc',           coalesce(sum(total) FILTER (WHERE codi_cc = '(SIN CC)'), 0),
            'flota_horas',      (SELECT sum(horas) FROM cph),
            'flota_costo_medido', (SELECT sum(costo) FROM cph),
            'flota_costo_hora', (SELECT sum(costo) / nullif(sum(horas), 0) FROM cph),
            'equipos_medidos',  (SELECT count(*) FROM cph)
        ) FROM per),
        'por_mes', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes), '[]') FROM (
            SELECT b.mes,
                   sum(b.total)                                  AS total,
                   sum(b.total) FILTER (WHERE b.area = 'equipo') AS asignado_equipo,
                   (SELECT sum(h.horas) FROM v_activo_horas_mes h WHERE h.mes = b.mes) AS horas
              FROM base b GROUP BY b.mes) x),
        'por_area', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT area, sum(total) AS total FROM per GROUP BY area) x),
        'por_zona', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT coalesce(zona, 'Sin zona') AS zona, sum(total) AS total FROM per GROUP BY 1) x),
        'por_familia', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT p.familia, coalesce(f6.nombre, f3.nombre, p.familia) AS nombre,
                   coalesce(f3.nombre, p.grupo) AS grupo,
                   sum(p.total) AS total,
                   (SELECT sum(b.total) FROM base b WHERE NOT b.en_periodo AND b.familia = p.familia) AS total_anterior
              FROM per p
              LEFT JOIN softland_familia f6 ON f6.prefijo = p.familia
              LEFT JOIN softland_familia f3 ON f3.prefijo = p.grupo
             GROUP BY p.familia, f6.nombre, f3.nombre, p.grupo) x),
        'por_equipo', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT p.codi_cc, p.activo_id, a.patente, a.codigo AS activo_codigo,
                   coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT) AS tipo_equipo,
                   coalesce(sc.descripcion, cc.nombre) AS descripcion,
                   fa.nombre AS faena,
                   sum(p.total) AS total,
                   sum(p.total) FILTER (WHERE p.familia = 'REPNEU') AS neumaticos,
                   sum(p.total) FILTER (WHERE p.familia IN ('CLULUB','CLUGRA')) AS lubricantes,
                   sum(p.total) FILTER (WHERE p.grupo = 'REP' AND p.familia <> 'REPNEU') AS repuestos,
                   (SELECT sum(b.total) FROM base b WHERE NOT b.en_periodo AND b.codi_cc = p.codi_cc) AS total_anterior,
                   c.horas, c.km, c.meses AS meses_medidos, c.costo AS costo_medido, c.costo_hora,
                   md.mediana AS mediana_tipo, md.n AS n_tipo
              FROM per p
              LEFT JOIN activos a ON a.id = p.activo_id
              LEFT JOIN faenas fa ON fa.id = a.faena_id
              LEFT JOIN softland_cc sc ON sc.codigo = p.codi_cc
              LEFT JOIN centros_costo cc ON upper(cc.codigo) = p.codi_cc
              LEFT JOIN cph c ON c.activo_id = p.activo_id
              LEFT JOIN mediana md ON md.tipo_equipo = c.tipo_equipo
             WHERE p.area = 'equipo'
             GROUP BY p.codi_cc, p.activo_id, a.patente, a.codigo, a.tipo_equipamiento, a.tipo,
                      sc.descripcion, cc.nombre, fa.nombre,
                      c.horas, c.km, c.meses, c.costo, c.costo_hora, md.mediana, md.n) x),
        'costo_hora_tipo', (SELECT coalesce(jsonb_agg(x ORDER BY x.mediana DESC), '[]') FROM (
            SELECT tipo_equipo, n, mediana FROM mediana) x),
        'por_cc_no_equipo', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT p.codi_cc, p.area, sc.descripcion, sum(p.total) AS total
              FROM per p LEFT JOIN softland_cc sc ON sc.codigo = p.codi_cc
             WHERE p.area <> 'equipo'
             GROUP BY p.codi_cc, p.area, sc.descripcion) x),
        'sync', (SELECT jsonb_build_object('ultima', max(fin),
                    'docs', (SELECT count(*) FROM softland_doc),
                    'max_fecha', (SELECT max(fecha) FROM softland_doc))
                   FROM softland_sync_log)
    ) INTO r;

    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_costos_operacion_panel(DATE, DATE, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_operacion_panel(DATE, DATE, TEXT[]) TO authenticated;


-- El detalle tampoco muestra petróleo: si no, el total del modal no calza con
-- la fila de la que se abrió.
CREATE OR REPLACE FUNCTION rpc_costos_operacion_detalle(
    p_desde DATE, p_hasta DATE, p_codi_cc TEXT DEFAULT NULL, p_familia TEXT DEFAULT NULL,
    p_limite INTEGER DEFAULT 500)
RETURNS TABLE (
    fecha DATE, folio INTEGER, concepto TEXT, bodega TEXT, codi_cc TEXT,
    cod_prod TEXT, des_prod TEXT, cantidad NUMERIC, precio_unit NUMERIC, total NUMERIC,
    glosa TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_codi_cc IS NULL AND p_familia IS NULL THEN
        RAISE EXCEPTION 'Indique centro de costo o familia.';
    END IF;

    RETURN QUERY
    SELECT d.fecha, d.folio, d.concepto::TEXT, coalesce(d.bodega, d.cod_bode), d.codi_cc::TEXT,
           l.cod_prod::TEXT, l.des_prod, l.cantidad, l.precio_unit, l.total, d.glosa
      FROM softland_doc d
      JOIN softland_linea l USING (tipo, cod_bode, nro_int)
     WHERE d.fecha >= p_desde AND d.fecha < (date_trunc('month', p_hasta) + INTERVAL '1 month')::DATE
       AND l.cod_prod <> 'CLUPETPET003'
       AND (p_codi_cc IS NULL
            OR (p_codi_cc = '(SIN CC)' AND d.codi_cc IS NULL)
            OR d.codi_cc = upper(p_codi_cc))
       AND (p_familia IS NULL OR left(l.cod_prod, length(p_familia)) = upper(p_familia))
     ORDER BY l.total DESC
     LIMIT least(coalesce(p_limite, 500), 2000);
END $$;
