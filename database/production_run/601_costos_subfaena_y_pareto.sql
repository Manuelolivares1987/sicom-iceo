-- ============================================================================
-- SICOM-ICEO | 601 — Subfaenas (Calama: Spence, Centinela, Lomas Bayas) y Pareto
-- ============================================================================
-- Manuel: «en Pillado tenemos Franke, Calama y Romeral. Y en Calama atendemos
-- Spence, Centinela y Lomas Bayas. Eso es clave para mejorar los costos». Y:
-- «en cada gráfico quiero hacer clic y que se me abra un Pareto, todo con
-- visión de Pareto para poder atacar».
--
-- 1. Subfaena por equipo y día. Softland NO separa Spence/Centinela/Lomas
--    (solo tiene CC de Calama completo), así que la subfaena sale del equipo:
--    la ubicación diaria («Spence, Calama») y, para «Contrato ESM», la faena
--    asignada en SICOM (Spence/Centinela/Lomas Bayas — Combustible). Los CC
--    de Calama que Softland no reparte quedan en «Común Calama», a la vista.
--
-- 2. fn_costos_lineas: cada línea de bodega con su faena, subfaena, equipo,
--    familia y producto. Base única del panel por faena y del Pareto.
--
-- 3. rpc_costos_pareto(filtros, dimensión): ranking descendente con % y %
--    acumulado; se marca el grupo que hace el 80 %. Dimensión 'linea' = el
--    detalle final.
--
-- Sin petróleo (mercadería, MIG598). Sin administración ni comercial salvo
-- que se pida.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_subfaena(p_grupo TEXT, p_ubicacion TEXT, p_faena_sicom TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_grupo = 'Calama' THEN CASE
            WHEN coalesce(p_ubicacion, '') ~* 'spence'    THEN 'Spence'
            WHEN coalesce(p_ubicacion, '') ~* 'centinela' THEN 'Centinela'
            WHEN coalesce(p_ubicacion, '') ~* 'lomas'     THEN 'Lomas Bayas'
            WHEN coalesce(p_ubicacion, '') ~* 'taller'    THEN 'Taller Calama'
            WHEN coalesce(p_ubicacion, '') ~* 'hales'     THEN 'Ministro Hales'
            WHEN coalesce(p_ubicacion, '') ~* 'abra'      THEN 'El Abra'
            -- «Contrato ESM» u otra: la faena asignada al equipo en SICOM.
            WHEN coalesce(p_faena_sicom, '') ~* 'spence'    THEN 'Spence'
            WHEN coalesce(p_faena_sicom, '') ~* 'centinela' THEN 'Centinela'
            WHEN coalesce(p_faena_sicom, '') ~* 'lomas'     THEN 'Lomas Bayas'
            WHEN coalesce(p_faena_sicom, '') ~* 'taller'    THEN 'Taller Calama'
            ELSE 'Calama sin detalle'
        END
        WHEN p_grupo = 'Otras faenas' THEN coalesce(nullif(btrim(split_part(p_ubicacion, ',', 1)), ''), 'Otras')
        WHEN p_grupo = 'Taller / sin contrato' THEN
            CASE WHEN coalesce(p_ubicacion, '') ~* 'fenix' THEN 'Taller externo (aseguradora)'
                 ELSE 'Taller Coquimbo / sin contrato' END
        ELSE p_grupo
    END;
$$;


-- Faena y subfaena de cada equipo cada día (con arrastre).
DROP MATERIALIZED VIEW IF EXISTS mv_activo_faena_dia CASCADE;
CREATE MATERIALIZED VIEW mv_activo_faena_dia AS
WITH e AS (
    SELECT activo_id, fecha, fn_faena_grupo(ubicacion, cliente) AS g,
           nullif(nullif(btrim(ubicacion), 'N/A'), '') AS ubicacion
      FROM estado_diario_flota
), f AS (
    SELECT *, count(g) OVER (PARTITION BY activo_id ORDER BY fecha) AS tramo FROM e
), c AS (
    SELECT activo_id, fecha,
           first_value(g) OVER (PARTITION BY activo_id, tramo ORDER BY fecha) AS grupo,
           first_value(ubicacion) OVER (PARTITION BY activo_id, tramo ORDER BY fecha) AS ubicacion
      FROM f
), c2 AS (
    SELECT c.activo_id, c.fecha,
           coalesce(c.grupo, (SELECT f2.g FROM f f2 WHERE f2.activo_id = c.activo_id AND f2.g IS NOT NULL
                               ORDER BY f2.fecha LIMIT 1)) AS grupo,
           coalesce(c.ubicacion, (SELECT f2.ubicacion FROM f f2 WHERE f2.activo_id = c.activo_id AND f2.g IS NOT NULL
                                   ORDER BY f2.fecha LIMIT 1)) AS ubicacion
      FROM c
)
SELECT c2.activo_id, c2.fecha, c2.grupo, c2.ubicacion,
       fn_subfaena(c2.grupo, c2.ubicacion, fa.nombre) AS subfaena
  FROM c2
  JOIN activos a ON a.id = c2.activo_id
  LEFT JOIN faenas fa ON fa.id = a.faena_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_activo_faena_dia ON mv_activo_faena_dia (activo_id, fecha);
REVOKE ALL ON mv_activo_faena_dia FROM anon, authenticated;

-- Faena y subfaena de un equipo en una fecha: ese día, el último antes o el primero después.
CREATE OR REPLACE FUNCTION fn_activo_faena_sub_en(p_activo UUID, p_fecha DATE)
RETURNS TABLE (grupo TEXT, subfaena TEXT) LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT x.grupo, x.subfaena FROM (
        (SELECT m.grupo, m.subfaena, 0 AS o FROM mv_activo_faena_dia m
          WHERE m.activo_id = p_activo AND m.fecha <= p_fecha ORDER BY m.fecha DESC LIMIT 1)
        UNION ALL
        (SELECT m.grupo, m.subfaena, 1 FROM mv_activo_faena_dia m
          WHERE m.activo_id = p_activo AND m.fecha > p_fecha ORDER BY m.fecha LIMIT 1)
    ) x ORDER BY x.o LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_activo_faena_en(p_activo UUID, p_fecha DATE)
RETURNS TEXT LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT grupo FROM fn_activo_faena_sub_en(p_activo, p_fecha);
$$;


-- Cada línea de bodega con todos sus cortes.
CREATE OR REPLACE FUNCTION fn_costos_lineas(p_desde DATE, p_fin DATE, p_con_admin BOOLEAN DEFAULT FALSE)
RETURNS TABLE (
    fecha DATE, mes DATE, total NUMERIC, cantidad NUMERIC,
    cod_prod TEXT, des_prod TEXT, familia TEXT, grupo_prod TEXT,
    activo_id UUID, patente TEXT, tipo_equipo TEXT,
    codi_cc TEXT, cc_desc TEXT, area TEXT,
    faena TEXT, subfaena TEXT,
    folio INTEGER, concepto TEXT, bodega TEXT, glosa TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT d.fecha, date_trunc('month', d.fecha)::DATE, l.total, l.cantidad,
           l.cod_prod::TEXT, l.des_prod, left(l.cod_prod, 6), left(l.cod_prod, 3),
           c.activo_id, a.patente::TEXT, coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT),
           d.codi_cc::TEXT, c.descripcion, coalesce(c.area, 'sin_clasificar')::TEXT,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.grupo, 'Taller / sin contrato')
                WHEN d.codi_cc IS NULL THEN 'Sin centro de costo'
                ELSE fn_cc_faena(c.zona, c.area) END,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.subfaena, 'Taller Coquimbo / sin contrato')
                WHEN d.codi_cc IS NULL THEN 'Sin centro de costo'
                WHEN fn_cc_faena(c.zona, c.area) = 'Calama' THEN 'Común Calama'
                WHEN fn_cc_faena(c.zona, c.area) = 'Taller / sin contrato' THEN 'Taller Coquimbo / sin contrato'
                WHEN fn_cc_faena(c.zona, c.area) = 'Otras faenas' THEN coalesce(c.zona, 'Otras')
                ELSE fn_cc_faena(c.zona, c.area) END,
           d.folio, d.concepto::TEXT, coalesce(d.bodega, d.cod_bode), d.glosa
      FROM softland_doc d
      JOIN softland_linea l USING (tipo, cod_bode, nro_int)
      LEFT JOIN softland_cc c ON c.codigo = d.codi_cc
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN LATERAL fn_activo_faena_sub_en(c.activo_id, d.fecha) fs ON c.activo_id IS NOT NULL
     WHERE d.fecha BETWEEN p_desde AND p_fin
       AND l.cod_prod <> 'CLUPETPET003'
       AND (p_con_admin OR coalesce(c.area, 'sin_clasificar') NOT IN ('administracion', 'comercial'));
$$;
REVOKE ALL ON FUNCTION fn_costos_lineas(DATE, DATE, BOOLEAN) FROM PUBLIC, anon, authenticated;


-- Pareto genérico. p_filtros: {faena, subfaena, activo_id, familia, grupo_prod,
-- cod_prod, codi_cc, area, mes, tipo_equipo}. p_dimension: faena | subfaena |
-- equipo | familia | producto | centro_costo | mes | linea.
CREATE OR REPLACE FUNCTION rpc_costos_pareto(
    p_desde DATE, p_hasta DATE, p_filtros JSONB, p_dimension TEXT, p_con_admin BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$  -- VOLATILE: usa tabla temporal
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    f JSONB := coalesce(p_filtros, '{}'::jsonb);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_dimension NOT IN ('faena','subfaena','equipo','familia','producto','centro_costo','mes','linea') THEN
        RAISE EXCEPTION 'Dimensión no válida: %', p_dimension;
    END IF;

    CREATE TEMP TABLE _pl ON COMMIT DROP AS
    SELECT * FROM fn_costos_lineas(v_desde, v_fin, p_con_admin) l
     WHERE (f->>'faena' IS NULL OR l.faena = f->>'faena')
       AND (f->>'subfaena' IS NULL OR l.subfaena = f->>'subfaena')
       AND (f->>'activo_id' IS NULL OR l.activo_id = (f->>'activo_id')::UUID)
       AND (f->>'familia' IS NULL OR l.familia = f->>'familia')
       AND (f->>'grupo_prod' IS NULL OR l.grupo_prod = f->>'grupo_prod')
       AND (f->>'cod_prod' IS NULL OR l.cod_prod = f->>'cod_prod')
       AND (f->>'codi_cc' IS NULL
            OR (f->>'codi_cc' = '(SIN CC)' AND l.codi_cc IS NULL)
            OR l.codi_cc = ANY (string_to_array(upper(f->>'codi_cc'), ',')))
       AND (f->>'area' IS NULL OR l.area = f->>'area')
       AND (f->>'mes' IS NULL OR l.mes = (f->>'mes')::DATE)
       AND (f->>'tipo_equipo' IS NULL OR l.tipo_equipo = f->>'tipo_equipo');

    IF p_dimension = 'linea' THEN
        SELECT jsonb_build_object(
            'total', (SELECT coalesce(sum(total), 0) FROM _pl),
            'lineas', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
                SELECT fecha, folio, concepto, bodega, codi_cc, cod_prod, des_prod, cantidad,
                       CASE WHEN cantidad <> 0 THEN total / cantidad END AS precio_unit, total, glosa,
                       patente, subfaena
                  FROM _pl ORDER BY total DESC LIMIT 300) x)) INTO r;
        RETURN r;
    END IF;

    WITH g AS (
        SELECT CASE p_dimension
                 WHEN 'faena'        THEN faena
                 WHEN 'subfaena'     THEN subfaena
                 WHEN 'equipo'       THEN coalesce(activo_id::TEXT, 'cc:' || coalesce(codi_cc, '(SIN CC)'))
                 WHEN 'familia'      THEN familia
                 WHEN 'producto'     THEN cod_prod
                 WHEN 'centro_costo' THEN coalesce(codi_cc, '(SIN CC)')
                 WHEN 'mes'          THEN mes::TEXT
               END AS clave,
               CASE p_dimension
                 WHEN 'equipo'       THEN coalesce(patente, cc_desc, codi_cc, 'Sin centro de costo')
                 WHEN 'familia'      THEN coalesce((SELECT nombre FROM softland_familia WHERE prefijo = familia),
                                                   (SELECT nombre FROM softland_familia WHERE prefijo = grupo_prod), familia)
                 WHEN 'producto'     THEN des_prod
                 WHEN 'centro_costo' THEN coalesce(cc_desc, codi_cc, 'Sin centro de costo')
                 ELSE NULL
               END AS etiqueta,
               total, cantidad
          FROM _pl
    ), a AS (
        SELECT clave, max(etiqueta) AS etiqueta, sum(total) AS total, sum(cantidad) AS cantidad, count(*) AS lineas
          FROM g GROUP BY clave
    ), o AS (
        SELECT a.*,
               100.0 * total / nullif(sum(total) OVER (), 0) AS pct,
               100.0 * sum(total) OVER (ORDER BY total DESC, clave ROWS UNBOUNDED PRECEDING)
                     / nullif(sum(total) OVER (), 0) AS pct_acum,
               row_number() OVER (ORDER BY total DESC, clave) AS rk
          FROM a
    )
    SELECT jsonb_build_object(
        'dimension', p_dimension,
        'total', (SELECT coalesce(sum(total), 0) FROM a),
        'n', (SELECT count(*) FROM a),
        -- Cuántos ítems hacen el 80 %: el primero que cruza el 80 % también cuenta.
        'vitales', (SELECT coalesce(min(rk), 0) FROM o WHERE pct_acum >= 80),
        'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'clave', clave, 'etiqueta', coalesce(etiqueta, clave), 'total', total,
                     'cantidad', cantidad, 'lineas', lineas, 'pct', pct, 'pct_acum', pct_acum)
                   ORDER BY rk), '[]') FROM o WHERE rk <= 40),
        'resto', (SELECT jsonb_build_object('n', count(*), 'total', coalesce(sum(total), 0)) FROM o WHERE rk > 40)
    ) INTO r;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_costos_pareto(DATE, DATE, JSONB, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_pareto(DATE, DATE, JSONB, TEXT, BOOLEAN) TO authenticated;


-- Panel por faena con subfaenas (misma base que el Pareto).
CREATE OR REPLACE FUNCTION rpc_costos_por_faena(p_desde DATE, p_hasta DATE)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$  -- VOLATILE: usa tabla temporal
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    CREATE TEMP TABLE _fl ON COMMIT DROP AS SELECT * FROM fn_costos_lineas(v_desde, v_fin, FALSE);

    WITH dias AS (
        SELECT grupo AS faena, subfaena, count(*) AS dias_equipo, count(DISTINCT activo_id) AS equipos
          FROM mv_activo_faena_dia
         WHERE fecha BETWEEN v_desde AND v_fin AND grupo IS NOT NULL
         GROUP BY ROLLUP (grupo, subfaena)
    ),
    ven AS (SELECT * FROM fn_activo_ventana_horas(v_desde, v_fin) WHERE horas >= 20),
    hdia AS (
        SELECT v.activo_id, gs::DATE AS fecha, v.horas / nullif(v.dias, 0) AS horas,
               coalesce(fs.grupo, 'Taller / sin contrato') AS faena,
               coalesce(fs.subfaena, 'Taller Coquimbo / sin contrato') AS subfaena
          FROM ven v
          CROSS JOIN LATERAL generate_series(v.fecha_ini + 1, v.fecha_fin, INTERVAL '1 day') gs
          LEFT JOIN LATERAL fn_activo_faena_sub_en(v.activo_id, gs::DATE) fs ON TRUE
    ),
    hcost AS (
        SELECT l.faena, l.subfaena, l.total
          FROM _fl l JOIN ven v ON v.activo_id = l.activo_id
         WHERE l.fecha > v.fecha_ini AND l.fecha <= v.fecha_fin
    ),
    cph AS (
        SELECT h.faena, h.subfaena, sum(h.horas) AS horas FROM hdia h GROUP BY ROLLUP (h.faena, h.subfaena)
    ),
    cphc AS (
        SELECT faena, subfaena, sum(total) AS costo FROM hcost GROUP BY ROLLUP (faena, subfaena)
    ),
    tot AS (
        SELECT faena, subfaena,
               sum(total) AS total,
               sum(total) FILTER (WHERE activo_id IS NOT NULL) AS equipos_costo,
               sum(total) FILTER (WHERE activo_id IS NULL) AS directo,
               sum(total) FILTER (WHERE familia = 'REPNEU') AS neumaticos,
               sum(total) FILTER (WHERE familia IN ('CLULUB', 'CLUGRA')) AS lubricantes,
               sum(total) FILTER (WHERE grupo_prod = 'REP' AND familia <> 'REPNEU') AS repuestos,
               sum(total) FILTER (WHERE grupo_prod = 'ISE') AS seguridad_epp
          FROM _fl GROUP BY ROLLUP (faena, subfaena)
    ),
    fila AS (
        SELECT t.*, d.dias_equipo, d.equipos,
               t.equipos_costo / nullif(d.dias_equipo, 0) AS costo_equipo_dia,
               c.horas, k.costo AS costo_medido, k.costo / nullif(c.horas, 0) AS costo_hora
          FROM tot t
          LEFT JOIN dias d ON d.faena IS NOT DISTINCT FROM t.faena AND d.subfaena IS NOT DISTINCT FROM t.subfaena
          LEFT JOIN cph c  ON c.faena IS NOT DISTINCT FROM t.faena AND c.subfaena IS NOT DISTINCT FROM t.subfaena
          LEFT JOIN cphc k ON k.faena IS NOT DISTINCT FROM t.faena AND k.subfaena IS NOT DISTINCT FROM t.subfaena
         WHERE t.faena IS NOT NULL
    )
    SELECT jsonb_build_object(
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_fin),
        'faenas', (SELECT coalesce(jsonb_agg(to_jsonb(x) - 'subfaena' ORDER BY x.total DESC), '[]')
                     FROM fila x WHERE x.subfaena IS NULL),
        'subfaenas', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.faena, x.total DESC), '[]')
                        FROM fila x WHERE x.subfaena IS NOT NULL),
        'por_mes', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes, x.faena), '[]') FROM (
            SELECT mes, faena, sum(total) AS total FROM _fl GROUP BY 1, 2) x),
        'equipos', (SELECT coalesce(jsonb_agg(x ORDER BY x.faena, x.total DESC), '[]') FROM (
            SELECT faena, activo_id, patente, sum(total) AS total
              FROM _fl WHERE activo_id IS NOT NULL GROUP BY faena, activo_id, patente) x),
        'directos', (SELECT coalesce(jsonb_agg(x ORDER BY x.faena, x.total DESC), '[]') FROM (
            SELECT faena, codi_cc, cc_desc AS descripcion, sum(total) AS total
              FROM _fl WHERE activo_id IS NULL GROUP BY faena, codi_cc, cc_desc) x)
    ) INTO r;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_costos_por_faena(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_por_faena(DATE, DATE) TO authenticated;

-- (fn_refrescar_faena_dia y el cierre del sync ya refrescan mv_activo_faena_dia.)
