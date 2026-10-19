-- 617 — Informe mensual de costos para correo (Manuel 2026-10-19): top 10 por
-- equipo (gasto del mes + costo/h), por familia y por centro de costo, con un
-- link interactivo que se abre sin sesión vía token, igual que fiabilidad (MIG200).
--
-- 1) La lógica de rpc_costos_operacion_panel pasa a fn_costos_operacion_panel_datos
--    (SIN chequeo de permiso, sin EXECUTE para nadie salvo postgres). El RPC del
--    panel queda como puerta: permiso y delega. Cuerpo idéntico al vigente.
-- 2) fn_reporte_costos_publico(p_mes, p_token): sesión con permiso de costos O
--    token vigente de reporte_tokens (reporte='costos'). Devuelve solo lo que va
--    al informe: tops de 10, no el detalle por línea.
-- 3) Costo/h = ventana de 12 meses (MIG599). Mes a mes no se puede: el horómetro
--    GPS diario (activo_horas_dia) no avanza.
-- ADITIVA salvo el RPC del panel, que conserva firma y resultado.

CREATE OR REPLACE FUNCTION public.fn_costos_operacion_panel_datos(p_desde date, p_hasta date, p_areas text[] DEFAULT NULL::text[])
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
    r JSONB;
BEGIN
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
END $function$;

REVOKE ALL ON FUNCTION fn_costos_operacion_panel_datos(date, date, text[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_costos_operacion_panel(p_desde date, p_hasta date, p_areas text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    RETURN fn_costos_operacion_panel_datos(p_desde, p_hasta, p_areas);
END $function$;

-- ── Token del link ───────────────────────────────────────────────────────────
INSERT INTO reporte_tokens (reporte, token, activo)
SELECT 'costos', encode(extensions.gen_random_bytes(24), 'hex'), true
 WHERE NOT EXISTS (SELECT 1 FROM reporte_tokens WHERE reporte = 'costos' AND activo);

CREATE OR REPLACE FUNCTION public.fn_reporte_costos_link_token()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF session_user <> 'postgres' AND NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    RETURN (SELECT token FROM reporte_tokens
             WHERE reporte = 'costos' AND activo
               AND (expira_at IS NULL OR expira_at > NOW())
             ORDER BY created_at DESC LIMIT 1);
END $function$;

REVOKE ALL ON FUNCTION fn_reporte_costos_link_token() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_reporte_costos_link_token() TO authenticated;

-- ── El informe ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_reporte_costos_publico(p_mes date DEFAULT NULL, p_token text DEFAULT NULL)
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
                                          WHERE mv.mes = v_mes AND NOT mv.es_petroleo AND mv.area = 'equipo'
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
                                'total_anterior', (SELECT sum(mv.total) FROM mv_softland_costo_mes mv
                                                    WHERE mv.mes = v_ant AND NOT mv.es_petroleo
                                                      AND mv.codi_cc = x->>'codi_cc')) ORDER BY ord), '[]')
                        FROM jsonb_array_elements(m->'por_cc_no_equipo') WITH ORDINALITY t(x, ord) WHERE ord <= 10),
            'resto', (SELECT coalesce(sum((x->>'total')::NUMERIC), 0)
                        FROM jsonb_array_elements(m->'por_cc_no_equipo') WITH ORDINALITY t(x, ord) WHERE ord > 10))
    );
END $function$;

REVOKE ALL ON FUNCTION fn_reporte_costos_publico(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_reporte_costos_publico(date, text) TO anon, authenticated;

SELECT left((fn_reporte_costos_publico('2026-09-01') - 'tendencia')::text, 3000) AS muestra;
