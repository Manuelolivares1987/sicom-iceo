-- ============================================================================
-- SICOM-ICEO | 604 — Costos: filtro por año y comparación con el año anterior
-- ============================================================================
-- Manuel: «todo debe tener un filtro para ver los datos solo de este año».
-- El panel abre en el año en curso. Si el período va desde enero dentro de un
-- mismo año (año a la fecha o un año completo), la comparación es contra los
-- MISMOS meses del año anterior (ene-oct 2026 vs ene-oct 2025), no contra los
-- meses inmediatamente previos. El resto del panel no cambia.
-- ============================================================================

-- El panel: igual que MIG598, cambia solo cómo se mide la hora.
CREATE OR REPLACE FUNCTION rpc_costos_operacion_panel(
    p_desde DATE, p_hasta DATE, p_areas TEXT[] DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_hasta DATE := date_trunc('month', p_hasta)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    v_meses INTEGER := (extract(year FROM age(date_trunc('month', p_hasta), date_trunc('month', p_desde))) * 12
                       + extract(month FROM age(date_trunc('month', p_hasta), date_trunc('month', p_desde))))::INTEGER + 1;
    -- Período anterior: los meses inmediatamente anteriores, SALVO que el
    -- período sea dentro de un mismo año desde enero (año a la fecha o año
    -- completo): ahí se compara con los mismos meses del año anterior.
    v_mismo_anio BOOLEAN := extract(month FROM p_desde) = 1
                            AND extract(year FROM p_desde) = extract(year FROM p_hasta);
    v_ant_desde DATE := CASE WHEN v_mismo_anio
                             THEN (date_trunc('month', p_desde) - INTERVAL '1 year')::DATE
                             ELSE (date_trunc('month', p_desde) - make_interval(months => v_meses))::DATE END;
    v_ant_hasta DATE := CASE WHEN v_mismo_anio
                             THEN (date_trunc('month', p_hasta) - INTERVAL '1 year')::DATE
                             ELSE (date_trunc('month', p_desde) - INTERVAL '1 month')::DATE END;
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH base AS (
        SELECT m.*, (m.mes BETWEEN v_desde AND v_hasta) AS en_periodo
          FROM mv_softland_costo_mes m
         WHERE (m.mes BETWEEN v_desde AND v_hasta OR m.mes BETWEEN v_ant_desde AND v_ant_hasta)
           AND m.area = ANY (v_areas)
           AND NOT m.es_petroleo                       -- mercadería, no costo
    ), per AS (SELECT * FROM base WHERE en_periodo),
    ventana AS (SELECT * FROM fn_activo_ventana_horas(v_desde, v_fin) WHERE horas >= 20),
    cph AS (
        SELECT v.activo_id, v.fecha_ini, v.fecha_fin, v.dias, v.horas, v.fuente_ini, v.fuente_fin,
               coalesce((SELECT sum(l.total)
                           FROM softland_doc d
                           JOIN softland_linea l USING (tipo, cod_bode, nro_int)
                           JOIN softland_cc c ON c.codigo = d.codi_cc
                          WHERE c.activo_id = v.activo_id
                            AND d.fecha BETWEEN v.fecha_ini AND v.fecha_fin
                            AND l.cod_prod <> 'CLUPETPET003'), 0) AS costo,
               coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT) AS tipo_equipo
          FROM ventana v JOIN activos a ON a.id = v.activo_id
         WHERE NOT coalesce(a.es_prueba, false)
    ), cph2 AS (SELECT *, costo / horas AS costo_hora FROM cph),
    -- Con menos de 100 h medidas el cociente es ruido (equipo casi parado con
    -- un gasto puntual): se muestra, pero no entra a la mediana del tipo.
    mediana AS (
        SELECT tipo_equipo, count(*) AS n,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY costo_hora) AS mediana
          FROM cph2 WHERE horas >= 100 GROUP BY tipo_equipo
    )
    SELECT jsonb_build_object(
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'meses', v_meses,
                                      'anterior_desde', v_ant_desde, 'anterior_hasta', v_ant_hasta,
                                      'compara_anio_anterior', v_mismo_anio),
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
            'flota_horas',      (SELECT sum(horas) FROM cph2),
            'flota_costo_medido', (SELECT sum(costo) FROM cph2),
            'flota_costo_hora', (SELECT sum(costo) / nullif(sum(horas), 0) FROM cph2),
            'equipos_medidos',  (SELECT count(*) FROM cph2),
            'dias_medidos_mediana', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY dias) FROM cph2)
        ) FROM per),
        'por_mes', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes), '[]') FROM (
            SELECT b.mes,
                   sum(b.total)                                  AS total,
                   sum(b.total) FILTER (WHERE b.area = 'equipo') AS asignado_equipo
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
            -- Un equipo puede tener dos CC en Softland: una fila por equipo.
            SELECT string_agg(DISTINCT p.codi_cc, ',') AS codi_cc, p.activo_id, a.patente, a.codigo AS activo_codigo,
                   coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT) AS tipo_equipo,
                   min(coalesce(sc.descripcion, cc.nombre)) AS descripcion,
                   fa.nombre AS faena,
                   sum(p.total) AS total,
                   sum(p.total) FILTER (WHERE p.familia = 'REPNEU') AS neumaticos,
                   sum(p.total) FILTER (WHERE p.familia IN ('CLULUB','CLUGRA')) AS lubricantes,
                   sum(p.total) FILTER (WHERE p.grupo = 'REP' AND p.familia <> 'REPNEU') AS repuestos,
                   (SELECT sum(b.total) FROM base b WHERE NOT b.en_periodo
                       AND (b.activo_id = p.activo_id OR (p.activo_id IS NULL AND b.codi_cc = min(p.codi_cc)))) AS total_anterior,
                   c.horas, c.dias AS dias_medidos, c.fecha_ini AS medido_desde, c.fecha_fin AS medido_hasta,
                   c.fuente_ini, c.fuente_fin,
                   c.costo AS costo_medido, c.costo_hora,
                   md.mediana AS mediana_tipo, md.n AS n_tipo
              FROM per p
              LEFT JOIN activos a ON a.id = p.activo_id
              LEFT JOIN faenas fa ON fa.id = a.faena_id
              LEFT JOIN softland_cc sc ON sc.codigo = p.codi_cc
              LEFT JOIN centros_costo cc ON upper(cc.codigo) = p.codi_cc
              LEFT JOIN cph2 c ON c.activo_id = p.activo_id
              LEFT JOIN mediana md ON md.tipo_equipo = c.tipo_equipo
             WHERE p.area = 'equipo'
             GROUP BY coalesce(p.activo_id::TEXT, p.codi_cc), p.activo_id, a.patente, a.codigo, a.tipo_equipamiento, a.tipo,
                      fa.nombre,
                      c.horas, c.dias, c.fecha_ini, c.fecha_fin, c.fuente_ini, c.fuente_fin,
                      c.costo, c.costo_hora, md.mediana, md.n) x),
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


