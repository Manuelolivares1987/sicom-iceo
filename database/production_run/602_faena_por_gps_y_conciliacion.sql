-- ============================================================================
-- SICOM-ICEO | 602 — La faena del día sale del GPS + conciliación de ubicación
-- ============================================================================
-- Manuel: «compara con SICOM en dónde están los camiones». Al comparar:
--   · estado_diario_flota quedó desactualizado: la última ubicación escrita de
--     casi todos los camiones es del 31-05 o 22-07; el resto se arrastraba.
--   · la ficha (activos.faena_id) y el GPS no coinciden en varios camiones
--     (RSCY-85 ficha Yastai / GPS Franke; HHWB-44 ficha Franke / GPS Taller
--     Coquimbo; TRDP-97 y TRSS-16 en Spence según GPS).
--   · la geocerca «Contrato ESM, Calama» está sobre Minera Centinela
--     (ESM = Esperanza Sur): esos camiones SON Centinela.
--   · no hay camiones ni geocerca en Lomas Bayas: allá el servicio es la
--     lubricación ENEX y su gasto está en los CC comunes de Calama.
--
-- Faena del día, en este orden:
--   1. GPS ese día: última posición del día → geocerca más cercana dentro de
--      su radio + 5 km (si está lejos de todas, va en tránsito: no decide).
--   2. GPS ese día: última ENTRADA a una geocerca.
--   3. Estado diario ese día (ubicación escrita).
--   4. Lo último conocido (arrastre); antes del primer dato, el primero.
-- ============================================================================

-- ESM = Esperanza Sur = Minera Centinela.
CREATE OR REPLACE FUNCTION fn_subfaena(p_grupo TEXT, p_ubicacion TEXT, p_faena_sicom TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_grupo = 'Calama' THEN CASE
            WHEN coalesce(p_ubicacion, '') ~* 'spence'          THEN 'Spence'
            WHEN coalesce(p_ubicacion, '') ~* 'centinela|esm'   THEN 'Centinela'
            WHEN coalesce(p_ubicacion, '') ~* 'lomas'           THEN 'Lomas Bayas'
            WHEN coalesce(p_ubicacion, '') ~* 'taller'          THEN 'Taller Calama'
            WHEN coalesce(p_ubicacion, '') ~* 'hales'           THEN 'Ministro Hales'
            WHEN coalesce(p_ubicacion, '') ~* 'abra'            THEN 'El Abra'
            WHEN coalesce(p_faena_sicom, '') ~* 'spence'        THEN 'Spence'
            WHEN coalesce(p_faena_sicom, '') ~* 'centinela'     THEN 'Centinela'
            WHEN coalesce(p_faena_sicom, '') ~* 'lomas'         THEN 'Lomas Bayas'
            WHEN coalesce(p_faena_sicom, '') ~* 'taller'        THEN 'Taller Calama'
            ELSE 'Calama sin detalle'
        END
        WHEN p_grupo = 'Otras faenas' THEN coalesce(nullif(btrim(split_part(p_ubicacion, ',', 1)), ''), 'Otras')
        WHEN p_grupo = 'Taller / sin contrato' THEN
            CASE WHEN coalesce(p_ubicacion, '') ~* 'fenix' THEN 'Taller externo (aseguradora)'
                 ELSE 'Taller Coquimbo / sin contrato' END
        ELSE p_grupo
    END;
$$;


-- Geocerca más cercana a un punto (dentro de su radio + 5 km).
CREATE OR REPLACE FUNCTION fn_geocerca_cercana(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS TABLE (nombre TEXT, km NUMERIC) LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT z.nombre::TEXT, round(d.km::NUMERIC, 1)
      FROM gps_geocercas z
      CROSS JOIN LATERAL (SELECT 6371 * acos(least(1, cos(radians(p_lat)) * cos(radians(z.centro_lat))
                    * cos(radians(z.centro_lng) - radians(p_lng))
                    + sin(radians(p_lat)) * sin(radians(z.centro_lat)))) AS km) d
     WHERE z.activo AND z.centro_lat IS NOT NULL AND p_lat IS NOT NULL
       AND d.km <= coalesce(z.radio_m, 2000) / 1000.0 + 5
     ORDER BY d.km LIMIT 1;
$$;


-- Dónde estuvo cada equipo cada día según el GPS.
DROP MATERIALIZED VIEW IF EXISTS mv_activo_gps_dia CASCADE;
CREATE MATERIALIZED VIEW mv_activo_gps_dia AS
WITH pos AS (
    SELECT DISTINCT ON (activo_id, (ts_gps AT TIME ZONE 'America/Santiago')::DATE)
           activo_id, (ts_gps AT TIME ZONE 'America/Santiago')::DATE AS fecha, latitud, longitud
      FROM gps_eventos_log
     WHERE activo_id IS NOT NULL AND latitud IS NOT NULL AND longitud IS NOT NULL
     ORDER BY activo_id, (ts_gps AT TIME ZONE 'America/Santiago')::DATE, ts_gps DESC
), por_pos AS (
    SELECT p.activo_id, p.fecha, g.nombre
      FROM pos p CROSS JOIN LATERAL fn_geocerca_cercana(p.latitud, p.longitud) g
), por_evento AS (
    SELECT DISTINCT ON (e.activo_id, (e.ts AT TIME ZONE 'America/Santiago')::DATE)
           e.activo_id, (e.ts AT TIME ZONE 'America/Santiago')::DATE AS fecha, z.nombre::TEXT AS nombre
      FROM gps_geocerca_eventos e JOIN gps_geocercas z ON z.id = e.geocerca_id
     WHERE e.tipo_evento = 'entrada' AND e.activo_id IS NOT NULL
     ORDER BY e.activo_id, (e.ts AT TIME ZONE 'America/Santiago')::DATE, e.ts DESC
)
SELECT coalesce(pp.activo_id, pe.activo_id) AS activo_id,
       coalesce(pp.fecha, pe.fecha) AS fecha,
       coalesce(pp.nombre, pe.nombre) AS geocerca
  FROM por_pos pp
  FULL JOIN por_evento pe ON pe.activo_id = pp.activo_id AND pe.fecha = pp.fecha;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_activo_gps_dia ON mv_activo_gps_dia (activo_id, fecha);
REVOKE ALL ON mv_activo_gps_dia FROM anon, authenticated;


-- Faena y subfaena de cada equipo cada día: GPS > estado diario > arrastre.
DROP MATERIALIZED VIEW IF EXISTS mv_activo_faena_dia CASCADE;
CREATE MATERIALIZED VIEW mv_activo_faena_dia AS
WITH est AS (
    SELECT activo_id, fecha, nullif(nullif(btrim(ubicacion), 'N/A'), '') AS ubicacion, cliente
      FROM estado_diario_flota
), dato AS (
    -- Lo que se sabe de cada día, con su fuente.
    SELECT coalesce(g.activo_id, e.activo_id) AS activo_id,
           coalesce(g.fecha, e.fecha) AS fecha,
           CASE WHEN g.geocerca IS NOT NULL THEN g.geocerca ELSE e.ubicacion END AS ubicacion,
           CASE WHEN g.geocerca IS NOT NULL THEN NULL ELSE e.cliente END AS cliente,
           CASE WHEN g.geocerca IS NOT NULL THEN 'gps'
                WHEN fn_faena_grupo(e.ubicacion, e.cliente) IS NOT NULL THEN 'estado_diario' END AS fuente
      FROM mv_activo_gps_dia g
      FULL JOIN est e ON e.activo_id = g.activo_id AND e.fecha = g.fecha
), cal AS (
    -- Calendario continuo por equipo, desde su primer dato hasta hoy.
    SELECT a.activo_id, gs::DATE AS fecha
      FROM (SELECT activo_id, min(fecha) AS desde FROM dato GROUP BY activo_id) a
      CROSS JOIN LATERAL generate_series(a.desde, (NOW() AT TIME ZONE 'America/Santiago')::DATE, INTERVAL '1 day') gs
), d AS (
    SELECT c.activo_id, c.fecha,
           CASE WHEN x.fuente IS NOT NULL THEN fn_faena_grupo(x.ubicacion, x.cliente) END AS g,
           CASE WHEN x.fuente IS NOT NULL THEN x.ubicacion END AS ubicacion,
           x.fuente
      FROM cal c LEFT JOIN dato x ON x.activo_id = c.activo_id AND x.fecha = c.fecha
), t AS (
    SELECT *, count(g) OVER (PARTITION BY activo_id ORDER BY fecha) AS tramo FROM d
), r AS (
    SELECT activo_id, fecha,
           first_value(g) OVER w AS grupo,
           first_value(ubicacion) OVER w AS ubicacion,
           CASE WHEN fuente IS NOT NULL THEN fuente
                WHEN tramo > 0 THEN 'arrastre' END AS fuente
      FROM t WINDOW w AS (PARTITION BY activo_id, tramo ORDER BY fecha)
), r2 AS (
    SELECT r.activo_id, r.fecha,
           coalesce(r.grupo, p.g) AS grupo,
           coalesce(r.ubicacion, p.ubicacion) AS ubicacion,
           coalesce(r.fuente, 'primer_dato') AS fuente
      FROM r
      LEFT JOIN LATERAL (SELECT t2.g, t2.ubicacion FROM t t2
                          WHERE t2.activo_id = r.activo_id AND t2.g IS NOT NULL
                          ORDER BY t2.fecha LIMIT 1) p ON r.grupo IS NULL
)
SELECT r2.activo_id, r2.fecha, r2.grupo, r2.ubicacion, r2.fuente,
       fn_subfaena(r2.grupo, r2.ubicacion, fa.nombre) AS subfaena
  FROM r2
  JOIN activos a ON a.id = r2.activo_id
  LEFT JOIN faenas fa ON fa.id = a.faena_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_activo_faena_dia ON mv_activo_faena_dia (activo_id, fecha);
REVOKE ALL ON mv_activo_faena_dia FROM anon, authenticated;

-- Las funciones que leen mv_activo_faena_dia (fn_activo_faena_sub_en, …) no
-- dependen del objeto: siguen funcionando con la vista recreada.


-- Conciliación: dónde dice cada fuente que está cada camión hoy.
CREATE OR REPLACE VIEW v_flota_ubicacion_conciliacion AS
SELECT a.id AS activo_id, a.patente, a.tipo::TEXT AS tipo,
       fa.nombre AS faena_ficha,
       fn_faena_grupo(fa.nombre, NULL) AS grupo_ficha,
       e.ubicacion AS estado_ubicacion, e.fecha AS estado_fecha,
       fn_faena_grupo(e.ubicacion, e.cliente) AS grupo_estado,
       gz.nombre AS gps_geocerca, gz.km AS gps_km, g.ts_gps AS gps_fecha,
       fn_faena_grupo(gz.nombre, NULL) AS grupo_gps,
       fn_subfaena(fn_faena_grupo(gz.nombre, NULL), gz.nombre, fa.nombre) AS subfaena_gps,
       m.grupo AS grupo_usado, m.subfaena AS subfaena_usada, m.fuente AS fuente_usada
  FROM activos a
  LEFT JOIN faenas fa ON fa.id = a.faena_id
  LEFT JOIN LATERAL (SELECT ed.ubicacion, ed.cliente, ed.fecha FROM estado_diario_flota ed
                      WHERE ed.activo_id = a.id AND nullif(nullif(btrim(ed.ubicacion), ''), 'N/A') IS NOT NULL
                      ORDER BY ed.fecha DESC LIMIT 1) e ON TRUE
  LEFT JOIN gps_estado_actual g ON g.activo_id = a.id
  LEFT JOIN LATERAL fn_geocerca_cercana(g.latitud, g.longitud) gz ON TRUE
  LEFT JOIN LATERAL (SELECT mf.grupo, mf.subfaena, mf.fuente FROM mv_activo_faena_dia mf
                      WHERE mf.activo_id = a.id ORDER BY mf.fecha DESC LIMIT 1) m ON TRUE
 WHERE a.fecha_baja IS NULL AND NOT coalesce(a.es_prueba, false)
   AND a.tipo::TEXT IN ('camion', 'camion_cisterna', 'camioneta');

COMMENT ON VIEW v_flota_ubicacion_conciliacion IS
    'Ficha vs estado diario vs GPS por camión, y la faena que usa el panel de costos. MIG602.';
GRANT SELECT ON v_flota_ubicacion_conciliacion TO authenticated;


-- Refresco diario: primero GPS, después faena (depende de la anterior).
CREATE OR REPLACE FUNCTION fn_refrescar_faena_dia()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activo_gps_dia;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activo_faena_dia;
END $$;

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
    REFRESH MATERIALIZED VIEW mv_activo_gps_dia;
    REFRESH MATERIALIZED VIEW mv_activo_faena_dia;

    INSERT INTO softland_sync_log (run_id, inicio, desde, docs, docs_cambiados, lineas,
                                   borrados, equipo, detalle)
    VALUES (p_run, p_inicio, p_desde,
            (p_stats->>'docs')::INTEGER, (p_stats->>'cambiados')::INTEGER,
            (p_stats->>'lineas')::INTEGER, v_borrados, p_stats->>'equipo', p_stats)
    ON CONFLICT (run_id) DO NOTHING;

    RETURN jsonb_build_object('borrados', v_borrados);
END $$;

SELECT grupo, subfaena, fuente, count(*) AS dias
  FROM mv_activo_faena_dia WHERE fecha >= DATE '2026-09-01'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
