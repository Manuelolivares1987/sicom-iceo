-- ============================================================================
-- SICOM-ICEO | 600 — Costos de operación por faena
-- ============================================================================
-- Manuel: «el costo por faena, que es lo que más consume: Franke, Romeral,
-- Calama».
--
-- El gasto de un equipo va a la faena donde estaba EL DÍA del gasto, no a la
-- de hoy: estado_diario_flota trae ubicación/cliente por equipo y día desde
-- enero 2026. La ubicación viene vacía en la mitad de los días → se arrastra
-- la última conocida (y antes de la primera, se usa la primera).
--
-- Grupos: Franke · Romeral · Calama · Otras faenas · Taller / sin contrato.
-- Además de los equipos, cada faena suma sus centros de costo propios
-- (Operaciones Franke, Operaciones Calama, Taller Calama…) por la zona del CC.
--
-- Costo por hora de la faena: por cada equipo, dentro de su ventana medida
-- (MIG599), las horas se reparten parejo por día y cada día va a la faena
-- donde estaba; el costo del mismo día, igual. Mismo numerador y denominador.
--
-- Sin petróleo (mercadería, MIG598).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_faena_grupo(p_ubicacion TEXT, p_cliente TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN coalesce(p_ubicacion, '') ~* 'franck|franke|cenizas|taltal' OR coalesce(p_cliente, '') ~* 'cenizas' THEN 'Franke'
        WHEN coalesce(p_ubicacion, '') ~* 'romeral|cmp'                  OR coalesce(p_cliente, '') ~* 'cmp'     THEN 'Romeral'
        WHEN coalesce(p_ubicacion, '') ~* 'calama|spence|esm|hales|abra|lomas|centinela'
                                                                         OR coalesce(p_cliente, '') ~* 'esm'     THEN 'Calama'
        WHEN coalesce(p_ubicacion, '') ~* 'taller|fenix'                 OR coalesce(p_cliente, '') ~* 'sin contrato' THEN 'Taller / sin contrato'
        WHEN nullif(nullif(btrim(p_ubicacion), 'N/A'), '') IS NOT NULL THEN 'Otras faenas'
        ELSE NULL
    END;
$$;

-- Faena de cada equipo cada día (con arrastre). Materializada: la usan
-- cálculos por línea; se refresca cada mañana y al cerrar el sync Softland.
DROP MATERIALIZED VIEW IF EXISTS mv_activo_faena_dia;
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
)
SELECT c.activo_id, c.fecha,
       coalesce(c.grupo, (SELECT f2.g FROM f f2 WHERE f2.activo_id = c.activo_id AND f2.g IS NOT NULL
                           ORDER BY f2.fecha LIMIT 1)) AS grupo,
       c.ubicacion
  FROM c;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_activo_faena_dia ON mv_activo_faena_dia (activo_id, fecha);
REVOKE ALL ON mv_activo_faena_dia FROM anon, authenticated;

-- Faena de un equipo en una fecha: ese día, o el último antes, o el primero después.
CREATE OR REPLACE FUNCTION fn_activo_faena_en(p_activo UUID, p_fecha DATE)
RETURNS TEXT LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT coalesce(
        (SELECT grupo FROM mv_activo_faena_dia WHERE activo_id = p_activo AND fecha <= p_fecha
          ORDER BY fecha DESC LIMIT 1),
        (SELECT grupo FROM mv_activo_faena_dia WHERE activo_id = p_activo AND fecha > p_fecha
          ORDER BY fecha LIMIT 1));
$$;

-- Faena de un centro de costo que no es equipo.
CREATE OR REPLACE FUNCTION fn_cc_faena(p_zona TEXT, p_area TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_zona IN ('Franke', 'Romeral', 'Calama') THEN p_zona
        WHEN p_area = 'taller' OR p_zona = 'Coquimbo' THEN 'Taller / sin contrato'
        WHEN p_zona IS NOT NULL THEN 'Otras faenas'
        ELSE 'Taller / sin contrato'
    END;
$$;


CREATE OR REPLACE FUNCTION rpc_costos_por_faena(p_desde DATE, p_hasta DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH lin AS (
        SELECT d.fecha, l.total, left(l.cod_prod, 6) AS familia, c.activo_id, c.area, c.zona, d.codi_cc
          FROM softland_doc d
          JOIN softland_linea l USING (tipo, cod_bode, nro_int)
          LEFT JOIN softland_cc c ON c.codigo = d.codi_cc
         WHERE d.fecha BETWEEN v_desde AND v_fin
           AND l.cod_prod <> 'CLUPETPET003'
           AND coalesce(c.area, 'sin_clasificar') NOT IN ('administracion', 'comercial')
    ), lin_f AS (
        SELECT lin.*,
               CASE WHEN activo_id IS NOT NULL THEN coalesce(fn_activo_faena_en(activo_id, fecha), 'Taller / sin contrato')
                    WHEN codi_cc IS NULL THEN 'Sin centro de costo'   -- casi todo EPP (concepto 08)
                    ELSE fn_cc_faena(zona, area) END AS faena
          FROM lin
    ),
    -- Días-equipo por faena en el período (cuántos equipos tuvo, en promedio).
    dias AS (
        SELECT grupo AS faena, count(*) AS dias_equipo, count(DISTINCT activo_id) AS equipos
          FROM mv_activo_faena_dia
         WHERE fecha BETWEEN v_desde AND v_fin AND grupo IS NOT NULL
         GROUP BY grupo
    ),
    -- Costo por hora: horas de la ventana medida repartidas por día.
    ven AS (SELECT * FROM fn_activo_ventana_horas(v_desde, v_fin) WHERE horas >= 20),
    hdia AS (
        SELECT v.activo_id, gs::DATE AS fecha, v.horas / nullif(v.dias, 0) AS horas,
               coalesce(fn_activo_faena_en(v.activo_id, gs::DATE), 'Taller / sin contrato') AS faena
          FROM ven v CROSS JOIN LATERAL generate_series(v.fecha_ini + 1, v.fecha_fin, INTERVAL '1 day') gs
    ),
    cph AS (
        SELECT h.faena, sum(h.horas) AS horas,
               (SELECT sum(l.total) FROM lin_f l JOIN ven v ON v.activo_id = l.activo_id
                 WHERE l.faena = h.faena AND l.fecha > v.fecha_ini AND l.fecha <= v.fecha_fin) AS costo
          FROM hdia h GROUP BY h.faena
    ),
    tot AS (
        SELECT faena,
               sum(total) AS total,
               sum(total) FILTER (WHERE activo_id IS NOT NULL) AS equipos_costo,
               sum(total) FILTER (WHERE activo_id IS NULL) AS directo,
               sum(total) FILTER (WHERE familia = 'REPNEU') AS neumaticos,
               sum(total) FILTER (WHERE familia IN ('CLULUB', 'CLUGRA')) AS lubricantes,
               sum(total) FILTER (WHERE left(familia, 3) = 'REP' AND familia <> 'REPNEU') AS repuestos,
               sum(total) FILTER (WHERE left(familia, 3) = 'ISE') AS seguridad_epp
          FROM lin_f GROUP BY faena
    )
    SELECT jsonb_build_object(
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_fin),
        'faenas', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT t.faena, t.total, t.equipos_costo, t.directo, t.neumaticos, t.lubricantes,
                   t.repuestos, t.seguridad_epp,
                   d.dias_equipo, d.equipos,
                   t.equipos_costo / nullif(d.dias_equipo, 0) AS costo_equipo_dia,
                   c.horas, c.costo AS costo_medido, c.costo / nullif(c.horas, 0) AS costo_hora
              FROM tot t
              LEFT JOIN dias d ON d.faena = t.faena
              LEFT JOIN cph c ON c.faena = t.faena) x),
        'por_mes', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes, x.faena), '[]') FROM (
            SELECT date_trunc('month', fecha)::DATE AS mes, faena, sum(total) AS total
              FROM lin_f GROUP BY 1, 2) x),
        'equipos', (SELECT coalesce(jsonb_agg(x ORDER BY x.faena, x.total DESC), '[]') FROM (
            SELECT l.faena, l.activo_id, a.patente, sum(l.total) AS total
              FROM lin_f l JOIN activos a ON a.id = l.activo_id
             GROUP BY l.faena, l.activo_id, a.patente) x),
        'directos', (SELECT coalesce(jsonb_agg(x ORDER BY x.faena, x.total DESC), '[]') FROM (
            SELECT l.faena, l.codi_cc, sc.descripcion, sum(l.total) AS total
              FROM lin_f l LEFT JOIN softland_cc sc ON sc.codigo = l.codi_cc
             WHERE l.activo_id IS NULL
             GROUP BY l.faena, l.codi_cc, sc.descripcion) x)
    ) INTO r;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_costos_por_faena(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_por_faena(DATE, DATE) TO authenticated;


-- Refresco: cada mañana (después del cálculo automático de estados) y al
-- cerrar cada sincronización Softland.
CREATE OR REPLACE FUNCTION fn_refrescar_faena_dia()
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activo_faena_dia;
$$;

SELECT cron.unschedule('refrescar-faena-dia')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refrescar-faena-dia');
SELECT cron.schedule('refrescar-faena-dia', '0 15 * * *', 'SELECT fn_refrescar_faena_dia()');

CREATE OR REPLACE FUNCTION rpc_softland_cerrar_corrida(
    p_secreto TEXT, p_run UUID, p_inicio TIMESTAMPTZ, p_desde DATE, p_stats JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_borrados INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;

    IF p_desde IS NOT NULL THEN
        DELETE FROM softland_doc
         WHERE fecha >= p_desde AND run_id IS DISTINCT FROM p_run;
        GET DIAGNOSTICS v_borrados = ROW_COUNT;
    END IF;

    INSERT INTO softland_cc (codigo, area, zona)
    SELECT DISTINCT d.codi_cc, k.area, k.zona
      FROM softland_doc d
      CROSS JOIN LATERAL fn_softland_cc_clasificar(d.codi_cc, NULL) k
     WHERE d.codi_cc IS NOT NULL
    ON CONFLICT (codigo) DO NOTHING;

    REFRESH MATERIALIZED VIEW mv_softland_costo_mes;
    REFRESH MATERIALIZED VIEW mv_activo_faena_dia;

    INSERT INTO softland_sync_log (run_id, inicio, desde, docs, docs_cambiados, lineas,
                                   borrados, equipo, detalle)
    VALUES (p_run, p_inicio, p_desde,
            (p_stats->>'docs')::INTEGER, (p_stats->>'cambiados')::INTEGER,
            (p_stats->>'lineas')::INTEGER, v_borrados, p_stats->>'equipo', p_stats)
    ON CONFLICT (run_id) DO NOTHING;

    RETURN jsonb_build_object('borrados', v_borrados);
END $$;
