-- ============================================================================
-- SICOM-ICEO | 599 — Costo por hora con todas las lecturas de horómetro
-- ============================================================================
-- MIG598 medía las horas solo con el GPS diario, que empezó a mediados de
-- septiembre 2026: en un período de 12 meses quedaba medido solo octubre.
--
-- Pero SICOM tiene lecturas de horómetro desde antes, en seis lugares: OS
-- históricas (2024 →), recepción en taller, cambios de estado y de contrato,
-- cierre de preventivas y el GPS. Se juntan en una sola serie y, por equipo,
-- se usa el PAR de lecturas más separado dentro del período que sea creíble:
-- el horómetro sube, a no más de 20 h por día, con al menos 30 días entre
-- ambas. Un número mal digitado (TGGF-60: 13.501 vs 1.349) no pasa el filtro.
--
-- Costo por hora = gasto de bodega sin petróleo entre esas dos fechas ÷ horas
-- entre ellas. Misma ventana arriba y abajo.
-- ============================================================================

CREATE OR REPLACE VIEW v_activo_lecturas_horometro AS
SELECT activo_id, fecha, horometro_fin AS horometro, 'gps'::TEXT AS fuente, 1 AS prioridad
  FROM activo_horas_dia WHERE horometro_fin > 0
UNION ALL
SELECT activo_id, coalesce(fecha_cierre, fecha_inicio, created_at)::DATE, horometro,
       'recepcion_taller', 2
  FROM checklist_v2_instance WHERE horometro > 0 AND activo_id IS NOT NULL
UNION ALL
SELECT activo_id, ultima_ejecucion_fecha::DATE, ultima_ejecucion_horas, 'preventiva', 3
  FROM planes_mantenimiento
 WHERE ultima_ejecucion_horas > 0 AND ultima_ejecucion_fecha IS NOT NULL
UNION ALL
SELECT activo_id, fecha_recepcion::DATE, horometro, 'os_historica', 4
  FROM historial_os_legacy WHERE horometro > 0 AND activo_id IS NOT NULL AND fecha_recepcion IS NOT NULL
UNION ALL
SELECT activo_id, fecha_recepcion::DATE, horometro, 'os_importada', 5
  FROM os_historico_importado
 WHERE horometro > 0 AND activo_id IS NOT NULL
   AND fecha_recepcion BETWEEN DATE '2015-01-01' AND CURRENT_DATE     -- hay fechas 1900 y futuras
UNION ALL
SELECT activo_id, cambio_at::DATE, horometro, 'cambio_estado', 6
  FROM historico_estado_activo WHERE horometro > 0
UNION ALL
SELECT activo_id, cambio_at::DATE, horometro, 'cambio_contrato', 6
  FROM historico_contrato_activo WHERE horometro > 0;

COMMENT ON VIEW v_activo_lecturas_horometro IS
    'Todas las lecturas de horómetro por equipo (GPS, taller, preventivas, OS, cambios). MIG599.';
GRANT SELECT ON v_activo_lecturas_horometro TO authenticated;


-- Ventana medida de cada equipo en un período: el par de lecturas creíble más
-- separado. Devuelve una fila por equipo con horas y fechas.
CREATE OR REPLACE FUNCTION fn_activo_ventana_horas(p_desde DATE, p_hasta DATE)
RETURNS TABLE (activo_id UUID, fecha_ini DATE, fecha_fin DATE, horo_ini NUMERIC, horo_fin NUMERIC,
               horas NUMERIC, dias INTEGER, fuente_ini TEXT, fuente_fin TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH l AS (
        -- Una lectura por equipo y día (la de mejor fuente).
        SELECT DISTINCT ON (activo_id, fecha) activo_id, fecha, horometro, fuente
          FROM v_activo_lecturas_horometro
         WHERE fecha BETWEEN p_desde AND p_hasta
         ORDER BY activo_id, fecha, prioridad
    ), pares AS (
        SELECT s.activo_id, s.fecha AS fi, e.fecha AS ff, s.horometro AS hi, e.horometro AS hf,
               s.fuente AS fu_i, e.fuente AS fu_f
          FROM l s JOIN l e ON e.activo_id = s.activo_id AND e.fecha >= s.fecha + 30
         WHERE e.horometro > s.horometro
           AND e.horometro - s.horometro <= 20 * (e.fecha - s.fecha)
    )
    SELECT DISTINCT ON (activo_id)
           activo_id, fi, ff, hi, hf, round(hf - hi, 1), (ff - fi), fu_i, fu_f
      FROM pares
     ORDER BY activo_id, (ff - fi) DESC, ff DESC;
$$;


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


-- Detalle: un equipo con dos CC llega como 'CC-1,CC-2'.
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
            OR d.codi_cc = ANY (string_to_array(upper(p_codi_cc), ',')))
       AND (p_familia IS NULL OR left(l.cod_prod, length(p_familia)) = upper(p_familia))
     ORDER BY l.total DESC
     LIMIT least(coalesce(p_limite, 500), 2000);
END $$;
