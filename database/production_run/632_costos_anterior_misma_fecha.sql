-- 632 — Todo cuadra a la misma fecha (Manuel 2026-10-21). Arriba decía ▼6,8 %
-- (1-ene→21-oct contra 1-ene→21-oct 2025) y la tarjeta ▼9,4 %: la tarjeta
-- comparaba contra octubre 2025 COMPLETO (12,9 MM de días que 2026 aún no vive).
-- fn_costos_operacion_panel_datos ahora lee por día y, si el período llega al
-- mes en curso, corta el período anterior el mismo día. Afecta a todas las
-- flechas y «vs» del panel (tarjetas, familias, equipos, alzas) y al correo.
-- Además el anterior por centro de costo sale del mismo cálculo (antes el
-- correo lo leía aparte del resumen mensual).

CREATE OR REPLACE FUNCTION public.fn_costos_operacion_panel_datos(p_desde date, p_hasta date, p_areas text[] DEFAULT NULL::text[], p_fuente text DEFAULT 'oc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- MIG632: si el período llega al mes en curso (incompleto), el anterior se
    -- corta el mismo día de su último mes: 1-ene→21-oct contra 1-ene→21-oct, no
    -- contra octubre completo. Igual que la comparación de arriba (MIG629).
    v_fin_mes   DATE := (date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE;
    v_ant_fin   DATE := CASE WHEN v_fin < v_fin_mes
                             THEN LEAST(v_ant_hasta + (v_fin - date_trunc('month', p_hasta)::DATE),
                                        (v_ant_hasta + INTERVAL '1 month - 1 day')::DATE)
                             ELSE (v_ant_hasta + INTERVAL '1 month - 1 day')::DATE END;
    r JSONB;
BEGIN
    IF p_fuente NOT IN ('oc', 'bodega') THEN
        RAISE EXCEPTION 'Fuente no válida: %', p_fuente;
    END IF;

    WITH base AS (
        -- Por día (no el resumen mensual), para cortar el período anterior al mismo día.
        SELECT date_trunc('month', v.fecha)::DATE           AS mes,
               v.concepto,
               coalesce(v.codi_cc, '(SIN CC)')               AS codi_cc,
               coalesce(c.area, 'sin_clasificar')            AS area,
               c.activo_id,
               coalesce(f.nombre, c.zona)                    AS zona,
               left(v.cod_prod, 3)                           AS grupo,
               left(v.cod_prod, 6)                           AS familia,
               sum(v.cantidad)                               AS cantidad,
               sum(v.total)                                  AS total,
               count(*)                                      AS lineas,
               count(*) FILTER (WHERE v.total = 0)           AS lineas_sin_precio,
               (v.fecha BETWEEN v_desde AND v_fin)           AS en_periodo
          FROM v_costos_linea v
          LEFT JOIN softland_cc c ON c.codigo = v.codi_cc
          LEFT JOIN activos a ON a.id = c.activo_id
          LEFT JOIN faenas f ON f.id = a.faena_id
         WHERE v.fuente = p_fuente
           AND NOT v.es_mercaderia                     -- mercadería e inversión, no costo
           AND (v.fecha BETWEEN v_desde AND v_fin OR v.fecha BETWEEN v_ant_desde AND v_ant_fin)
           AND coalesce(c.area, 'sin_clasificar') = ANY (v_areas)
         GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 13
    ), per AS (SELECT * FROM base WHERE en_periodo),
    ventana AS (SELECT * FROM fn_activo_ventana_horas(v_desde, v_fin) WHERE horas >= 20),
    cph AS (
        SELECT v.activo_id, v.fecha_ini, v.fecha_fin, v.dias, v.horas, v.fuente_ini, v.fuente_fin,
               coalesce((SELECT sum(l.total)
                           FROM v_costos_linea l
                           JOIN softland_cc c ON c.codigo = l.codi_cc
                          WHERE l.fuente = p_fuente
                            AND c.activo_id = v.activo_id
                            AND l.fecha BETWEEN v.fecha_ini AND v.fecha_fin
                            AND NOT l.es_mercaderia), 0) AS costo,
               coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT) AS tipo_equipo
          FROM ventana v JOIN activos a ON a.id = v.activo_id
         WHERE NOT coalesce(a.es_prueba, false) AND NOT coalesce(a.es_externo, false)
    ), cph2 AS (SELECT *, costo / horas AS costo_hora FROM cph),
    -- Con menos de 100 h medidas el cociente es ruido (equipo casi parado con
    -- un gasto puntual): se muestra, pero no entra a la mediana del tipo.
    mediana AS (
        SELECT tipo_equipo, count(*) AS n,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY costo_hora) AS mediana
          FROM cph2 WHERE horas >= 100 GROUP BY tipo_equipo
    )
    SELECT jsonb_build_object(
        'fuente', p_fuente,
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'meses', v_meses,
                                      'anterior_desde', v_ant_desde, 'anterior_hasta', v_ant_hasta,
                                      'fin', v_fin, 'anterior_fin', v_ant_fin,
                                      'compara_anio_anterior', v_mismo_anio),
        'kpi', (SELECT jsonb_build_object(
            'total',            coalesce(sum(total), 0),
            'total_anterior',   (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo),
            'asignado_equipo',  coalesce(sum(total) FILTER (WHERE area = 'equipo'), 0),
            'asignado_equipo_anterior', (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo AND area = 'equipo'),
            -- EPP: en bodega, la entrega a personas (concepto 08); en OC, la familia ISEEPP.
            'epp',              coalesce(sum(total) FILTER (WHERE CASE WHEN p_fuente = 'bodega'
                                                                    THEN concepto = '08' ELSE familia = 'ISEEPP' END), 0),
            'servicios',        coalesce(sum(total) FILTER (WHERE grupo = 'SER'), 0),
            'servicios_anterior', (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo AND grupo = 'SER'),
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
                   sum(b.total) FILTER (WHERE b.area = 'equipo') AS asignado_equipo,
                   sum(b.total) FILTER (WHERE b.grupo = 'SER')   AS servicios
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
                   sum(p.total) FILTER (WHERE p.grupo = 'SER') AS servicios,
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
            SELECT p.codi_cc, p.area, sc.descripcion, sum(p.total) AS total,
                   (SELECT sum(b.total) FROM base b WHERE NOT b.en_periodo AND b.codi_cc = p.codi_cc) AS total_anterior
              FROM per p LEFT JOIN softland_cc sc ON sc.codigo = p.codi_cc
             WHERE p.area <> 'equipo'
             GROUP BY p.codi_cc, p.area, sc.descripcion) x),
        'sync', (SELECT jsonb_build_object('ultima', max(fin),
                    'docs', CASE WHEN p_fuente = 'oc' THEN (SELECT count(*) FROM softland_oc WHERE estado = 'AP')
                                 ELSE (SELECT count(*) FROM softland_doc) END,
                    'max_fecha', CASE WHEN p_fuente = 'oc' THEN (SELECT max(fecha_oc) FROM softland_oc WHERE estado = 'AP')
                                      ELSE (SELECT max(fecha) FROM softland_doc) END)
                   FROM softland_sync_log)
    ) INTO r;

    RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.fn_reporte_costos_publico(p_mes date DEFAULT NULL::date, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_token_ok BOOLEAN := false;
    -- Por defecto el último mes cerrado: el mes en curso todavía se está cargando en Softland.
    v_mes  DATE := date_trunc('month', coalesce(p_mes, (NOW() AT TIME ZONE 'America/Santiago')::DATE - INTERVAL '1 month'))::DATE;
    v_ant  DATE := (v_mes - INTERVAL '1 month')::DATE;
    v_12   DATE := (v_mes - INTERVAL '11 months')::DATE;
    m JSONB; a JSONB;
BEGIN
    IF p_token IS NOT NULL THEN
        SELECT EXISTS (SELECT 1 FROM reporte_tokens t
                        WHERE t.reporte = 'costos' AND t.token = p_token AND t.activo
                          AND (t.expira_at IS NULL OR t.expira_at > NOW()))
          INTO v_token_ok;
    END IF;
    IF session_user <> 'postgres' AND NOT v_token_ok AND NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Acceso no autorizado.' USING ERRCODE = '42501';
    END IF;
    IF v_token_ok THEN
        BEGIN
            UPDATE reporte_tokens SET last_used_at = NOW(), usos = usos + 1
             WHERE reporte = 'costos' AND token = p_token;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    m := fn_costos_operacion_panel_datos(v_mes, v_mes, NULL);
    a := fn_costos_operacion_panel_datos(v_12, v_mes, NULL);

    RETURN jsonb_build_object(
        'mes', v_mes,
        'mes_anterior', v_ant,
        'sync', m->'sync',
        'kpi', jsonb_build_object(
            'total',              m->'kpi'->'total',
            'total_anterior',     m->'kpi'->'total_anterior',
            'asignado_equipo',    m->'kpi'->'asignado_equipo',
            'asignado_equipo_anterior', m->'kpi'->'asignado_equipo_anterior',
            'equipos_con_gasto',  m->'kpi'->'equipos_con_gasto',
            'lineas_sin_precio',  m->'kpi'->'lineas_sin_precio',
            'total_12m',          a->'kpi'->'total',
            'costo_hora_12m',     a->'kpi'->'flota_costo_hora',
            'horas_12m',          a->'kpi'->'flota_horas',
            'equipos_medidos_12m', a->'kpi'->'equipos_medidos'),
        'tendencia', (SELECT coalesce(jsonb_agg(jsonb_build_object('mes', x->'mes', 'total', x->'total') ORDER BY x->>'mes'), '[]')
                        FROM jsonb_array_elements(a->'por_mes') x
                       WHERE (x->>'mes')::DATE BETWEEN v_12 AND v_mes),
        'equipos', jsonb_build_object(
            'n',     jsonb_array_length(m->'por_equipo'),
            'items', (SELECT coalesce(jsonb_agg(fila ORDER BY ord), '[]') FROM (
                SELECT e.ord, jsonb_build_object(
                    'activo_id',      e.x->'activo_id',
                    'etiqueta',       coalesce(e.x->>'patente', e.x->>'activo_codigo', e.x->>'descripcion', e.x->>'codi_cc'),
                    'tipo_equipo',    e.x->'tipo_equipo',
                    'faena',          e.x->'faena',
                    'total',          e.x->'total',
                    'total_anterior', e.x->'total_anterior',
                    'costo_hora_12m', hh.h->'costo_hora',
                    'horas_12m',      hh.h->'horas',
                    'mediana_tipo',   hh.h->'mediana_tipo',
                    -- En qué se gastó: las 3 familias más grandes del equipo en el mes.
                    'familias', (SELECT coalesce(jsonb_agg(jsonb_build_object('nombre', f.nombre, 'total', f.total) ORDER BY f.total DESC), '[]')
                                   FROM (SELECT coalesce(f6.nombre, mv.familia) AS nombre, sum(mv.total) AS total
                                           FROM mv_softland_costo_mes mv
                                           LEFT JOIN softland_familia f6 ON f6.prefijo = mv.familia
                                          WHERE mv.fuente = 'oc' AND mv.mes = v_mes AND NOT mv.es_petroleo AND mv.area = 'equipo'
                                            AND ((e.x->>'activo_id') IS NOT NULL AND mv.activo_id = (e.x->>'activo_id')::UUID
                                              OR (e.x->>'activo_id') IS NULL AND mv.codi_cc = ANY (string_to_array(e.x->>'codi_cc', ',')))
                                          GROUP BY 1 ORDER BY 2 DESC LIMIT 3) f)
                ) AS fila
                  FROM (SELECT x, ord FROM jsonb_array_elements(m->'por_equipo') WITH ORDINALITY t(x, ord) WHERE ord <= 10) e
                  LEFT JOIN LATERAL (SELECT y AS h FROM jsonb_array_elements(a->'por_equipo') y
                                      WHERE (e.x->>'activo_id') IS NOT NULL AND y->>'activo_id' = e.x->>'activo_id' LIMIT 1) hh ON true
            ) s),
            'resto', (SELECT coalesce(sum((x->>'total')::NUMERIC), 0)
                        FROM jsonb_array_elements(m->'por_equipo') WITH ORDINALITY t(x, ord) WHERE ord > 10)),
        'familias', jsonb_build_object(
            'n',     jsonb_array_length(m->'por_familia'),
            'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                                'familia', x->'familia', 'nombre', x->'nombre', 'grupo', x->'grupo',
                                'total', x->'total', 'total_anterior', x->'total_anterior') ORDER BY ord), '[]')
                        FROM jsonb_array_elements(m->'por_familia') WITH ORDINALITY t(x, ord) WHERE ord <= 10),
            'resto', (SELECT coalesce(sum((x->>'total')::NUMERIC), 0)
                        FROM jsonb_array_elements(m->'por_familia') WITH ORDINALITY t(x, ord) WHERE ord > 10)),
        -- Centros de costo que NO son un equipo (operación de faena, taller,
        -- proyectos): los equipos ya tienen su propio top.
        'centros_costo', jsonb_build_object(
            'n',     jsonb_array_length(m->'por_cc_no_equipo'),
            'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                                'codi_cc', x->'codi_cc', 'area', x->'area', 'descripcion', x->'descripcion',
                                'total', x->'total',
                                'total_anterior', x->'total_anterior') ORDER BY ord), '[]')
                        FROM jsonb_array_elements(m->'por_cc_no_equipo') WITH ORDINALITY t(x, ord) WHERE ord <= 10),
            'resto', (SELECT coalesce(sum((x->>'total')::NUMERIC), 0)
                        FROM jsonb_array_elements(m->'por_cc_no_equipo') WITH ORDINALITY t(x, ord) WHERE ord > 10))
    );
END $function$;
