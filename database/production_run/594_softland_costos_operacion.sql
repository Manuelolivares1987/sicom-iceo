-- ============================================================================
-- SICOM-ICEO | 594 — Costos de operación desde Softland
-- ============================================================================
-- Las salidas de bodega de Softland (Tipo S, Estado V, conceptos 07 consumo y
-- 08 EPP) se copian una vez al día a SICOM para armar el panel de costos de
-- operación.
--
-- Quién escribe: un script en el PC de la oficina (database/scripts/
-- softland-sync.mjs) que lee SERVERPILLADO\SQLEXPRESS por la LAN y llama a las
-- RPC de abajo con la anon key + un secreto propio ('softland_sync'). Es el
-- patrón de MIG301: en Supabase solo queda el hash, nunca el service_role en
-- el PC.
--
-- Clave natural del documento: (tipo, cod_bode, nro_int). Cada vez que un
-- documento cambia (hash distinto) se reemplazan TODAS sus líneas: así no hace
-- falta conocer el número de línea de iw_gmovi.
--
-- Borrados: cada corrida relee una ventana de N días. Al cerrar la corrida,
-- los documentos de esa ventana que no vinieron en ella se borran (se anularon
-- o eliminaron en Softland). Solo se cierra si la corrida terminó completa.
--
-- El centro de costo (CodiCC) es el mismo código de centros_costo de SICOM, y
-- activos.ceco_id (MIG162) lleva de ahí al equipo.
--
-- ADITIVA. No modifica datos existentes.
-- ============================================================================


-- ############################################################################
-- 1. TABLAS
-- ############################################################################

CREATE TABLE IF NOT EXISTS softland_doc (
    tipo            VARCHAR(2)   NOT NULL,
    cod_bode        VARCHAR(10)  NOT NULL,
    nro_int         INTEGER      NOT NULL,
    folio           INTEGER,
    concepto        VARCHAR(4),
    fecha           DATE         NOT NULL,
    glosa           TEXT,
    orden           INTEGER,
    codi_cc         VARCHAR(20),
    cod_aux         VARCHAR(20),
    bodega          TEXT,
    hash            TEXT         NOT NULL,
    run_id          UUID,
    sincronizado_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tipo, cod_bode, nro_int)
);
CREATE INDEX IF NOT EXISTS idx_softland_doc_fecha ON softland_doc (fecha);
CREATE INDEX IF NOT EXISTS idx_softland_doc_cc ON softland_doc (codi_cc);

COMMENT ON TABLE softland_doc IS
    'Cabecera de salida de bodega Softland (iw_gsaen). Copia diaria, no se edita en SICOM. MIG594.';

CREATE TABLE IF NOT EXISTS softland_linea (
    tipo        VARCHAR(2)   NOT NULL,
    cod_bode    VARCHAR(10)  NOT NULL,
    nro_int     INTEGER      NOT NULL,
    n           INTEGER      NOT NULL,     -- orden de llegada dentro del documento
    cod_prod    VARCHAR(40)  NOT NULL,
    des_prod    TEXT,
    cantidad    NUMERIC      NOT NULL DEFAULT 0,
    precio_unit NUMERIC      NOT NULL DEFAULT 0,   -- PreUniMB (costo promedio)
    total       NUMERIC      NOT NULL DEFAULT 0,   -- TotLinea
    PRIMARY KEY (tipo, cod_bode, nro_int, n),
    FOREIGN KEY (tipo, cod_bode, nro_int)
        REFERENCES softland_doc (tipo, cod_bode, nro_int) ON DELETE CASCADE
);

COMMENT ON TABLE softland_linea IS
    'Líneas de la salida (iw_gmovi). Se reemplazan completas cuando cambia el documento. MIG594.';

-- Centro de costo de Softland (cwtccos) + cómo se lee en el panel.
CREATE TABLE IF NOT EXISTS softland_cc (
    codigo       VARCHAR(20) PRIMARY KEY,      -- CodiCC en MAYÚSCULAS
    descripcion  TEXT,
    area         VARCHAR(20) NOT NULL DEFAULT 'sin_clasificar',
    zona         TEXT,                          -- Coquimbo / Calama / Romeral / Franke
    area_manual  BOOLEAN     NOT NULL DEFAULT FALSE,  -- si alguien la corrigió, el sync no la pisa
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_softland_cc_area CHECK (area IN (
        'equipo','operacion','taller','proyectos','generico',
        'administracion','comercial','sin_clasificar'))
);

COMMENT ON TABLE softland_cc IS
    'Centros de costo Softland clasificados por área. generico = consumo sin equipo (p. ej. petróleo a Confección Estructuras). MIG594.';

-- Familia de producto por prefijo del código Softland (3 letras = grupo,
-- 6 letras = familia).
CREATE TABLE IF NOT EXISTS softland_familia (
    prefijo VARCHAR(6) PRIMARY KEY,
    nombre  TEXT NOT NULL
);

INSERT INTO softland_familia (prefijo, nombre) VALUES
    ('CLU',    'Combustibles y lubricantes'),
    ('CLUPET', 'Combustible'),
    ('CLULUB', 'Lubricantes'),
    ('CLUGRA', 'Grasas'),
    ('REP',    'Repuestos'),
    ('REPMOT', 'Repuestos motor y filtros'),
    ('REPNEU', 'Neumáticos'),
    ('REPCAR', 'Carrocería'),
    ('REPELE', 'Eléctrico'),
    ('REPALT', 'Accesorios y seguridad equipo'),
    ('REPORI', 'Sellos y o-rings'),
    ('REPARD', 'Refrigeración'),
    ('REPEQU', 'Repuestos equipos'),
    ('AFE',    'Ferretería y herramientas'),
    ('AFEFER', 'Ferretería'),
    ('AFEHEM', 'Herramientas manuales'),
    ('AFEHEL', 'Herramientas eléctricas'),
    ('AFEPIN', 'Pinturas'),
    ('AFEACE', 'Aceros y perfiles'),
    ('AFEAEL', 'Material eléctrico'),
    ('AFEADI', 'Aditivos'),
    ('AFEGAS', 'Gases de soldadura'),
    ('ISE',    'Seguridad'),
    ('ISEEPP', 'EPP'),
    ('ISEASE', 'Señalética'),
    ('ISEEXT', 'Extintores'),
    ('ISEFAR', 'Primeros auxilios y exámenes'),
    ('EQU',    'Equipos'),
    ('EQUINS', 'GPS e instrumentos'),
    ('EQUMAQ', 'Máquinas y kits'),
    ('EQUECO', 'Comunicaciones'),
    ('SER',    'Servicios'),
    ('COM',    'Componentes reparados'),
    ('AOF',    'Oficina'),
    ('IAF',    'Aseo'),
    ('ART',    'Mobiliario'),
    ('REC',    'Repuestos (otros)')
ON CONFLICT (prefijo) DO NOTHING;

CREATE TABLE IF NOT EXISTS softland_sync_log (
    id          BIGSERIAL PRIMARY KEY,
    run_id      UUID        NOT NULL UNIQUE,
    inicio      TIMESTAMPTZ NOT NULL,
    fin         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    desde       DATE,
    docs        INTEGER,
    docs_cambiados INTEGER,
    lineas      INTEGER,
    borrados    INTEGER,
    equipo      TEXT,
    detalle     JSONB
);

COMMENT ON TABLE softland_sync_log IS 'Una fila por corrida completa del sincronizador Softland. MIG594.';

-- Nadie lee estas tablas directo desde la aplicación: solo las RPC.
ALTER TABLE softland_doc      ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_linea    ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_cc       ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_familia  ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_sync_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON softland_doc, softland_linea, softland_cc, softland_familia, softland_sync_log
    FROM anon, authenticated;


-- ############################################################################
-- 2. CLASIFICACIÓN DEL CENTRO DE COSTO
-- ############################################################################
-- Equipo si el código es el CECO de un activo (MIG162) o si la descripción
-- trae una patente; si no, por el nombre.

CREATE OR REPLACE FUNCTION fn_softland_cc_clasificar(p_codigo TEXT, p_desc TEXT)
RETURNS TABLE (area TEXT, zona TEXT)
LANGUAGE sql STABLE SET search_path = public AS $$
    WITH d AS (SELECT upper(coalesce(p_desc, '')) AS t, upper(p_codigo) AS c)
    SELECT
        CASE
            WHEN d.c IN ('OC-TA-03', 'OC-TA-04') THEN 'generico'
            WHEN EXISTS (SELECT 1 FROM centros_costo cc JOIN activos a ON a.ceco_id = cc.id
                          WHERE upper(cc.codigo) = d.c) THEN 'equipo'
            WHEN d.t ~ 'ADMINISTRACI|ADIMINISTRACI|GERENCIA GENERAL' THEN 'administracion'
            WHEN d.t ~ 'COMERCIAL' THEN 'comercial'
            WHEN d.t ~ 'TALLER' THEN 'taller'
            WHEN d.t ~ 'PROYECTO' THEN 'proyectos'
            WHEN d.t ~ 'OPERACI' THEN 'operacion'
            -- Patente chilena al final: "... HH WB 44", "... SL RK-82"
            WHEN d.t ~ '[A-Z]{2}[ -]?[A-Z]{2}[ -]?[0-9]{2}\s*$' THEN 'equipo'
            ELSE 'sin_clasificar'
        END,
        CASE
            WHEN d.t ~ 'CALAMA' THEN 'Calama'
            WHEN d.t ~ 'FRANCKE|FRANKE' THEN 'Franke'
            WHEN d.t ~ 'ROMERAL' THEN 'Romeral'
            WHEN d.t ~ 'COQUIMBO' THEN 'Coquimbo'
            ELSE NULL
        END
    FROM d;
$$;


-- ############################################################################
-- 3. RPC DEL SINCRONIZADOR (protegidas por secreto)
-- ############################################################################

-- Lote de documentos. p_docs = [{tipo, cod_bode, nro_int, folio, concepto,
-- fecha, glosa, orden, codi_cc, cod_aux, bodega, hash, lineas:[{cod_prod,
-- des_prod, cantidad, precio_unit, total}]}]
CREATE OR REPLACE FUNCTION rpc_softland_cargar_docs(p_secreto TEXT, p_run UUID, p_docs JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_cambiados INTEGER := 0;
    v_lineas    INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    IF p_run IS NULL OR jsonb_typeof(p_docs) <> 'array' THEN
        RAISE EXCEPTION 'Lote inválido.';
    END IF;

    CREATE TEMP TABLE _sl_in ON COMMIT DROP AS
    SELECT upper(d->>'tipo')               AS tipo,
           d->>'cod_bode'                  AS cod_bode,
           (d->>'nro_int')::INTEGER        AS nro_int,
           (d->>'folio')::INTEGER          AS folio,
           d->>'concepto'                  AS concepto,
           (d->>'fecha')::DATE             AS fecha,
           nullif(btrim(d->>'glosa'), '')  AS glosa,
           (d->>'orden')::INTEGER          AS orden,
           nullif(upper(btrim(d->>'codi_cc')), '') AS codi_cc,
           nullif(btrim(d->>'cod_aux'), '') AS cod_aux,
           nullif(btrim(d->>'bodega'), '') AS bodega,
           d->>'hash'                      AS hash,
           d->'lineas'                     AS lineas
      FROM jsonb_array_elements(p_docs) d;

    -- Documentos nuevos o con hash distinto: se reemplazan sus líneas.
    CREATE TEMP TABLE _sl_cambio ON COMMIT DROP AS
    SELECT i.* FROM _sl_in i
      LEFT JOIN softland_doc s USING (tipo, cod_bode, nro_int)
     WHERE s.hash IS DISTINCT FROM i.hash;

    INSERT INTO softland_doc (tipo, cod_bode, nro_int, folio, concepto, fecha, glosa,
                              orden, codi_cc, cod_aux, bodega, hash, run_id, sincronizado_at)
    SELECT tipo, cod_bode, nro_int, folio, concepto, fecha, glosa,
           orden, codi_cc, cod_aux, bodega, hash, p_run, NOW()
      FROM _sl_in
    ON CONFLICT (tipo, cod_bode, nro_int) DO UPDATE SET
        folio = EXCLUDED.folio, concepto = EXCLUDED.concepto, fecha = EXCLUDED.fecha,
        glosa = EXCLUDED.glosa, orden = EXCLUDED.orden, codi_cc = EXCLUDED.codi_cc,
        cod_aux = EXCLUDED.cod_aux, bodega = EXCLUDED.bodega, hash = EXCLUDED.hash,
        run_id = EXCLUDED.run_id,
        sincronizado_at = CASE WHEN softland_doc.hash = EXCLUDED.hash
                               THEN softland_doc.sincronizado_at ELSE NOW() END;

    DELETE FROM softland_linea l USING _sl_cambio c
     WHERE l.tipo = c.tipo AND l.cod_bode = c.cod_bode AND l.nro_int = c.nro_int;

    INSERT INTO softland_linea (tipo, cod_bode, nro_int, n, cod_prod, des_prod,
                                cantidad, precio_unit, total)
    SELECT c.tipo, c.cod_bode, c.nro_int, l.ord::INTEGER,
           upper(btrim(l.v->>'cod_prod')), btrim(l.v->>'des_prod'),
           coalesce((l.v->>'cantidad')::NUMERIC, 0),
           coalesce((l.v->>'precio_unit')::NUMERIC, 0),
           coalesce((l.v->>'total')::NUMERIC, 0)
      FROM _sl_cambio c
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.lineas, '[]'::jsonb))
           WITH ORDINALITY AS l(v, ord);
    GET DIAGNOSTICS v_lineas = ROW_COUNT;

    SELECT count(*) INTO v_cambiados FROM _sl_cambio;
    RETURN jsonb_build_object('docs', (SELECT count(*) FROM _sl_in),
                              'cambiados', v_cambiados, 'lineas', v_lineas);
END $$;
REVOKE ALL ON FUNCTION rpc_softland_cargar_docs(TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cargar_docs(TEXT, UUID, JSONB) TO anon, authenticated;


-- Maestro de centros de costo (cwtccos). p_cc = [{codigo, descripcion}]
CREATE OR REPLACE FUNCTION rpc_softland_cargar_cc(p_secreto TEXT, p_cc JSONB)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO softland_cc (codigo, descripcion, area, zona, updated_at)
    SELECT x.codigo, x.descripcion, k.area, k.zona, NOW()
      FROM (SELECT DISTINCT ON (upper(btrim(e->>'codigo')))
                   upper(btrim(e->>'codigo')) AS codigo,
                   nullif(btrim(e->>'descripcion'), '') AS descripcion
              FROM jsonb_array_elements(p_cc) e
             WHERE nullif(btrim(e->>'codigo'), '') IS NOT NULL) x
      CROSS JOIN LATERAL fn_softland_cc_clasificar(x.codigo, x.descripcion) k
    ON CONFLICT (codigo) DO UPDATE SET
        descripcion = EXCLUDED.descripcion,
        area = CASE WHEN softland_cc.area_manual THEN softland_cc.area ELSE EXCLUDED.area END,
        zona = CASE WHEN softland_cc.area_manual THEN softland_cc.zona ELSE EXCLUDED.zona END,
        updated_at = NOW();
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION rpc_softland_cargar_cc(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cargar_cc(TEXT, JSONB) TO anon, authenticated;


-- Cierre de corrida: borra lo que desapareció de la ventana, refresca el
-- resumen y deja la bitácora. p_desde NULL = no borrar nada.
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

    -- Un CodiCC que llegó en un documento pero no en el maestro igual se clasifica.
    INSERT INTO softland_cc (codigo, area, zona)
    SELECT DISTINCT d.codi_cc, k.area, k.zona
      FROM softland_doc d
      CROSS JOIN LATERAL fn_softland_cc_clasificar(d.codi_cc, NULL) k
     WHERE d.codi_cc IS NOT NULL
    ON CONFLICT (codigo) DO NOTHING;

    REFRESH MATERIALIZED VIEW mv_softland_costo_mes;

    INSERT INTO softland_sync_log (run_id, inicio, desde, docs, docs_cambiados, lineas,
                                   borrados, equipo, detalle)
    VALUES (p_run, p_inicio, p_desde,
            (p_stats->>'docs')::INTEGER, (p_stats->>'cambiados')::INTEGER,
            (p_stats->>'lineas')::INTEGER, v_borrados, p_stats->>'equipo', p_stats)
    ON CONFLICT (run_id) DO NOTHING;

    RETURN jsonb_build_object('borrados', v_borrados);
END $$;
REVOKE ALL ON FUNCTION rpc_softland_cerrar_corrida(TEXT, UUID, TIMESTAMPTZ, DATE, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cerrar_corrida(TEXT, UUID, TIMESTAMPTZ, DATE, JSONB) TO anon, authenticated;


-- ############################################################################
-- 4. RESUMEN MENSUAL (una sola materializada, se refresca al cerrar la corrida)
-- ############################################################################

DROP MATERIALIZED VIEW IF EXISTS mv_softland_costo_mes;
CREATE MATERIALIZED VIEW mv_softland_costo_mes AS
SELECT
    date_trunc('month', d.fecha)::DATE                  AS mes,
    d.concepto,
    d.cod_bode,
    coalesce(d.bodega, d.cod_bode)                      AS bodega,
    coalesce(d.codi_cc, '(SIN CC)')                     AS codi_cc,
    coalesce(c.area, 'sin_clasificar')                  AS area,
    a.id                                                AS activo_id,
    coalesce(c.zona, f.nombre)                          AS zona,
    left(l.cod_prod, 3)                                 AS grupo,
    left(l.cod_prod, 6)                                 AS familia,
    (l.cod_prod = 'CLUPETPET003')                       AS es_petroleo,
    sum(l.cantidad)                                     AS cantidad,
    sum(l.total)                                        AS total,
    count(*)                                            AS lineas,
    count(*) FILTER (WHERE l.total = 0)                 AS lineas_sin_precio
FROM softland_doc d
JOIN softland_linea l USING (tipo, cod_bode, nro_int)
LEFT JOIN softland_cc c ON c.codigo = d.codi_cc
LEFT JOIN centros_costo cc ON upper(cc.codigo) = d.codi_cc
LEFT JOIN LATERAL (SELECT a.id, a.faena_id FROM activos a
                    WHERE a.ceco_id = cc.id AND NOT coalesce(a.es_prueba, false)
                    ORDER BY a.fecha_baja NULLS FIRST LIMIT 1) a ON TRUE
LEFT JOIN faenas f ON f.id = a.faena_id
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11;

CREATE INDEX IF NOT EXISTS idx_mv_softland_costo_mes_mes ON mv_softland_costo_mes (mes);
REVOKE ALL ON mv_softland_costo_mes FROM anon, authenticated;


-- ############################################################################
-- 5. LECTURA DEL PANEL
-- ############################################################################

CREATE OR REPLACE FUNCTION fn_costos_operacion_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('gerencia', 'view', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','jefe_mantenimiento'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_costos_operacion_puede_ver() TO authenticated;


-- Todo el panel en una llamada. p_areas NULL = solo operaciones (sin
-- administración ni comercial).
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
    ), per AS (SELECT * FROM base WHERE en_periodo)
    SELECT jsonb_build_object(
        'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'meses', v_meses,
                                      'anterior_desde', v_ant_desde),
        'kpi', (SELECT jsonb_build_object(
            'total',            coalesce(sum(total), 0),
            'total_anterior',   (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo),
            'sin_petroleo',     coalesce(sum(total) FILTER (WHERE NOT es_petroleo), 0),
            'sin_petroleo_anterior', (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo AND NOT es_petroleo),
            'petroleo_total',   coalesce(sum(total) FILTER (WHERE es_petroleo), 0),
            'petroleo_litros',  coalesce(sum(cantidad) FILTER (WHERE es_petroleo), 0),
            'petroleo_litros_anterior', (SELECT coalesce(sum(cantidad), 0) FROM base WHERE NOT en_periodo AND es_petroleo),
            'petroleo_total_anterior',  (SELECT coalesce(sum(total), 0) FROM base WHERE NOT en_periodo AND es_petroleo),
            'petroleo_sin_equipo_litros', coalesce(sum(cantidad) FILTER (WHERE es_petroleo AND area <> 'equipo'), 0),
            'asignado_equipo',  coalesce(sum(total) FILTER (WHERE area = 'equipo'), 0),
            'epp',              coalesce(sum(total) FILTER (WHERE concepto = '08'), 0),
            'lineas',           coalesce(sum(lineas), 0),
            'lineas_sin_precio', coalesce(sum(lineas_sin_precio), 0),
            'equipos_con_gasto', count(DISTINCT activo_id)
        ) FROM per),
        'por_mes', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes), '[]') FROM (
            SELECT mes,
                   sum(total) FILTER (WHERE NOT es_petroleo) AS sin_petroleo,
                   sum(total) FILTER (WHERE es_petroleo)     AS petroleo,
                   sum(cantidad) FILTER (WHERE es_petroleo)  AS litros,
                   sum(total) FILTER (WHERE area = 'equipo') AS asignado_equipo,
                   sum(total)                                AS total
              FROM base GROUP BY mes) x),
        'por_area', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT area, sum(total) AS total,
                   sum(total) FILTER (WHERE NOT es_petroleo) AS sin_petroleo
              FROM per GROUP BY area) x),
        'por_zona', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT coalesce(zona, 'Sin zona') AS zona, sum(total) AS total,
                   sum(total) FILTER (WHERE NOT es_petroleo) AS sin_petroleo
              FROM per GROUP BY 1) x),
        'por_bodega', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT bodega, sum(total) AS total FROM per GROUP BY bodega) x),
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
                   sum(p.total) FILTER (WHERE NOT p.es_petroleo) AS sin_petroleo,
                   sum(p.total) FILTER (WHERE p.familia = 'REPNEU') AS neumaticos,
                   sum(p.total) FILTER (WHERE p.familia IN ('CLULUB','CLUGRA')) AS lubricantes,
                   sum(p.total) FILTER (WHERE p.grupo = 'REP' AND p.familia <> 'REPNEU') AS repuestos,
                   sum(p.cantidad) FILTER (WHERE p.es_petroleo) AS litros,
                   (SELECT sum(b.total) FROM base b WHERE NOT b.en_periodo AND b.codi_cc = p.codi_cc) AS total_anterior
              FROM per p
              LEFT JOIN activos a ON a.id = p.activo_id
              LEFT JOIN faenas fa ON fa.id = a.faena_id
              LEFT JOIN softland_cc sc ON sc.codigo = p.codi_cc
              LEFT JOIN centros_costo cc ON upper(cc.codigo) = p.codi_cc
             WHERE p.area = 'equipo'
             GROUP BY p.codi_cc, p.activo_id, a.patente, a.codigo, a.tipo_equipamiento, a.tipo,
                      sc.descripcion, cc.nombre, fa.nombre) x),
        'por_cc_no_equipo', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
            SELECT p.codi_cc, p.area, sc.descripcion,
                   sum(p.total) AS total,
                   sum(p.total) FILTER (WHERE p.es_petroleo) AS petroleo,
                   sum(p.cantidad) FILTER (WHERE p.es_petroleo) AS litros
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


-- Detalle de líneas de un centro de costo (o de una familia) para bajar al dato.
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
       AND (p_codi_cc IS NULL OR d.codi_cc = upper(p_codi_cc))
       AND (p_familia IS NULL OR left(l.cod_prod, length(p_familia)) = upper(p_familia))
     ORDER BY l.total DESC
     LIMIT least(coalesce(p_limite, 500), 2000);
END $$;
REVOKE ALL ON FUNCTION rpc_costos_operacion_detalle(DATE, DATE, TEXT, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_operacion_detalle(DATE, DATE, TEXT, TEXT, INTEGER) TO authenticated;


-- Corregir el área de un centro de costo desde el panel (queda manual).
CREATE OR REPLACE FUNCTION rpc_softland_cc_set_area(p_codigo TEXT, p_area TEXT, p_zona TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('gerencia', 'edit', ARRAY['administrador','gerencia','subgerente_operaciones']) THEN
        RAISE EXCEPTION 'Sin permiso.' USING ERRCODE = '42501';
    END IF;
    UPDATE softland_cc SET area = p_area, zona = coalesce(p_zona, zona),
           area_manual = TRUE, updated_at = NOW()
     WHERE codigo = upper(p_codigo);
    -- Se refresca acá también para que el cambio se vea sin esperar al sync.
    REFRESH MATERIALIZED VIEW mv_softland_costo_mes;
END $$;
REVOKE ALL ON FUNCTION rpc_softland_cc_set_area(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_softland_cc_set_area(TEXT, TEXT, TEXT) TO authenticated;
