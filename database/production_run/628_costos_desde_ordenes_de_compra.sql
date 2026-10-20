-- 628 — Costos de operación desde las órdenes de compra de Softland (Manuel
-- 2026-10-20): el panel deja de mirar solo las salidas de bodega y pasa a las
-- OC VÁLIDAS (estado AP «Aprobada»; PE pendiente y UN «Nula» quedan fuera).
-- Así entran los servicios (seguros, arriendos, reparaciones externas…) que
-- nunca pasan por bodega. Las salidas de bodega siguen disponibles como
-- segunda fuente (consumo real), con un selector en el panel.
--
-- 1) softland_oc / softland_oc_linea: copia de owordencom / owordendet (todas
--    las OC; el filtro AP se aplica al leer). Las carga softland-sync.ps1 con
--    rpc_softland_cargar_oc y cierra con rpc_softland_cerrar_oc.
-- 2) v_costos_linea: una sola base con columna `fuente` ('oc' | 'bodega').
--    Mercadería (no costo): en bodega, el petróleo (CLUPETPET003, como antes);
--    en OC, el combustible comprado a OC-TA-03 (reventa, «Confección
--    Estructuras») y OC-TA-04 (compras stock). El combustible cargado a un
--    equipo SÍ es costo.
-- 3) mv_softland_costo_mes se rehace con `fuente`. (Lo «recibido» de la OC no sirve:
--    owordendet.Recibido queda en 0 para lo que entra por bodega; la recepción
--    vive en la guía de entrada de inventario.)
-- 4) Todas las funciones del panel reciben p_fuente (por defecto 'oc'); las
--    firmas viejas se eliminan para que no haya sobrecargas ambiguas.
--    fn_reporte_costos_publico (correo mensual) usa 'oc'.

-- ── 1. Tablas ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS softland_oc (
    num_inter_oc    INTEGER PRIMARY KEY,
    num_oc          INTEGER,
    fecha_oc        DATE NOT NULL,
    estado          VARCHAR(2) NOT NULL,          -- AP Aprobada · PE Pendiente · UN Nula
    cod_aux         TEXT,
    proveedor       TEXT,
    codi_cc         TEXT,
    cod_arn         TEXT,
    usuario         TEXT,
    aprobador       TEXT,
    neto            NUMERIC NOT NULL DEFAULT 0,
    total_oc        NUMERIC NOT NULL DEFAULT 0,   -- con IVA
    hash            TEXT,
    run_id          UUID,
    sincronizado_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_softland_oc_fecha ON softland_oc (fecha_oc);

CREATE TABLE IF NOT EXISTS softland_oc_linea (
    num_inter_oc INTEGER NOT NULL REFERENCES softland_oc (num_inter_oc) ON DELETE CASCADE,
    num_linea    INTEGER NOT NULL,
    cod_prod     TEXT,
    det_prod     TEXT,
    codi_cc      TEXT,
    fecha_ent    DATE,
    cantidad     NUMERIC NOT NULL DEFAULT 0,
    recibido     NUMERIC NOT NULL DEFAULT 0,
    saldo        NUMERIC NOT NULL DEFAULT 0,
    precio_unit  NUMERIC NOT NULL DEFAULT 0,
    total        NUMERIC NOT NULL DEFAULT 0,      -- neto, con descuentos
    PRIMARY KEY (num_inter_oc, num_linea)
);
CREATE INDEX IF NOT EXISTS idx_softland_oc_linea_cc ON softland_oc_linea (codi_cc);

-- Igual que softland_doc: RLS sin políticas, se lee solo por funciones SECURITY DEFINER.
ALTER TABLE softland_oc       ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_oc_linea ENABLE ROW LEVEL SECURITY;

-- ── Carga (lote de OC con sus líneas) ───────────────────────────────────────
-- p_ocs = [{num_inter_oc, num_oc, fecha_oc, estado, cod_aux, proveedor, codi_cc,
--           cod_arn, usuario, aprobador, neto, total_oc, hash,
--           lineas: [{num_linea, cod_prod, det_prod, codi_cc, fecha_ent, cantidad,
--                     recibido, saldo, precio_unit, total}]}]
CREATE OR REPLACE FUNCTION public.rpc_softland_cargar_oc(p_secreto text, p_run uuid, p_ocs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_cambiadas INTEGER := 0;
    v_lineas    INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    IF p_run IS NULL OR jsonb_typeof(p_ocs) <> 'array' THEN
        RAISE EXCEPTION 'Lote inválido.';
    END IF;

    CREATE TEMP TABLE _oc_in ON COMMIT DROP AS
    SELECT (o->>'num_inter_oc')::INTEGER              AS num_inter_oc,
           (o->>'num_oc')::INTEGER                    AS num_oc,
           (o->>'fecha_oc')::DATE                     AS fecha_oc,
           upper(btrim(o->>'estado'))                 AS estado,
           nullif(btrim(o->>'cod_aux'), '')           AS cod_aux,
           nullif(btrim(o->>'proveedor'), '')         AS proveedor,
           nullif(upper(btrim(o->>'codi_cc')), '')    AS codi_cc,
           nullif(btrim(o->>'cod_arn'), '')           AS cod_arn,
           nullif(btrim(o->>'usuario'), '')           AS usuario,
           nullif(btrim(o->>'aprobador'), '')         AS aprobador,
           coalesce((o->>'neto')::NUMERIC, 0)         AS neto,
           coalesce((o->>'total_oc')::NUMERIC, 0)     AS total_oc,
           o->>'hash'                                 AS hash,
           o->'lineas'                                AS lineas
      FROM jsonb_array_elements(p_ocs) o;

    CREATE TEMP TABLE _oc_cambio ON COMMIT DROP AS
    SELECT i.* FROM _oc_in i
      LEFT JOIN softland_oc s USING (num_inter_oc)
     WHERE s.hash IS DISTINCT FROM i.hash;

    INSERT INTO softland_oc (num_inter_oc, num_oc, fecha_oc, estado, cod_aux, proveedor, codi_cc,
                             cod_arn, usuario, aprobador, neto, total_oc, hash, run_id, sincronizado_at)
    SELECT num_inter_oc, num_oc, fecha_oc, estado, cod_aux, proveedor, codi_cc,
           cod_arn, usuario, aprobador, neto, total_oc, hash, p_run, NOW()
      FROM _oc_in
    ON CONFLICT (num_inter_oc) DO UPDATE SET
        num_oc = EXCLUDED.num_oc, fecha_oc = EXCLUDED.fecha_oc, estado = EXCLUDED.estado,
        cod_aux = EXCLUDED.cod_aux, proveedor = EXCLUDED.proveedor, codi_cc = EXCLUDED.codi_cc,
        cod_arn = EXCLUDED.cod_arn, usuario = EXCLUDED.usuario, aprobador = EXCLUDED.aprobador,
        neto = EXCLUDED.neto, total_oc = EXCLUDED.total_oc, hash = EXCLUDED.hash,
        run_id = EXCLUDED.run_id,
        sincronizado_at = CASE WHEN softland_oc.hash = EXCLUDED.hash
                               THEN softland_oc.sincronizado_at ELSE NOW() END;

    DELETE FROM softland_oc_linea l USING _oc_cambio c WHERE l.num_inter_oc = c.num_inter_oc;

    INSERT INTO softland_oc_linea (num_inter_oc, num_linea, cod_prod, det_prod, codi_cc, fecha_ent,
                                   cantidad, recibido, saldo, precio_unit, total)
    SELECT c.num_inter_oc, coalesce((l.v->>'num_linea')::INTEGER, l.ord::INTEGER),
           nullif(upper(btrim(l.v->>'cod_prod')), ''), nullif(btrim(l.v->>'det_prod'), ''),
           nullif(upper(btrim(l.v->>'codi_cc')), ''), (l.v->>'fecha_ent')::DATE,
           coalesce((l.v->>'cantidad')::NUMERIC, 0), coalesce((l.v->>'recibido')::NUMERIC, 0),
           coalesce((l.v->>'saldo')::NUMERIC, 0), coalesce((l.v->>'precio_unit')::NUMERIC, 0),
           coalesce((l.v->>'total')::NUMERIC, 0)
      FROM _oc_cambio c
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.lineas, '[]'::jsonb)) WITH ORDINALITY AS l(v, ord)
    ON CONFLICT (num_inter_oc, num_linea) DO NOTHING;
    GET DIAGNOSTICS v_lineas = ROW_COUNT;

    SELECT count(*) INTO v_cambiadas FROM _oc_cambio;
    RETURN jsonb_build_object('ocs', (SELECT count(*) FROM _oc_in), 'cambiadas', v_cambiadas, 'lineas', v_lineas);
END $function$;
REVOKE ALL ON FUNCTION rpc_softland_cargar_oc(text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cargar_oc(text, uuid, jsonb) TO anon, authenticated;

-- Cierre de la carga de OC: borra las de la ventana que ya no existen en
-- Softland y registra los centros de costo nuevos. Antes de rpc_softland_cerrar_corrida
-- (que refresca el resumen mensual).
CREATE OR REPLACE FUNCTION public.rpc_softland_cerrar_oc(p_secreto text, p_run uuid, p_desde date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_borradas INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    IF p_desde IS NOT NULL THEN
        DELETE FROM softland_oc WHERE fecha_oc >= p_desde AND run_id IS DISTINCT FROM p_run;
        GET DIAGNOSTICS v_borradas = ROW_COUNT;
    END IF;

    INSERT INTO softland_cc (codigo, area, zona)
    SELECT DISTINCT l.codi_cc, k.area, k.zona
      FROM softland_oc_linea l
      CROSS JOIN LATERAL fn_softland_cc_clasificar(l.codi_cc, NULL) k
     WHERE l.codi_cc IS NOT NULL
    ON CONFLICT (codigo) DO NOTHING;

    RETURN jsonb_build_object('borradas', v_borradas);
END $function$;
REVOKE ALL ON FUNCTION rpc_softland_cerrar_oc(text, uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cerrar_oc(text, uuid, date) TO anon, authenticated;

-- ── 2. Base única de líneas de costo ────────────────────────────────────────
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
       (l.cod_prod = 'CLUPETPET003')         AS es_mercaderia
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
       (l.cod_prod LIKE 'CLUPET%' AND coalesce(l.codi_cc, o.codi_cc) IN ('OC-TA-03', 'OC-TA-04'))
  FROM softland_oc o
  JOIN softland_oc_linea l USING (num_inter_oc)
 WHERE o.estado = 'AP';                                        -- solo OC válidas
REVOKE ALL ON v_costos_linea FROM PUBLIC, anon, authenticated;

-- ── 3. Resumen mensual con fuente ───────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS mv_softland_costo_mes;
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

-- ── 4. Funciones con fuente ─────────────────────────────────────────────────
DROP FUNCTION IF EXISTS fn_costos_lineas(date, date, boolean);
CREATE OR REPLACE FUNCTION public.fn_costos_lineas(p_desde date, p_fin date, p_con_admin boolean DEFAULT false,
                                                   p_fuente text DEFAULT 'oc')
 RETURNS TABLE(fecha date, mes date, total numeric, cantidad numeric, cod_prod text, des_prod text, familia text, grupo_prod text, activo_id uuid, patente text, tipo_equipo text, codi_cc text, cc_desc text, area text, faena text, subfaena text, folio integer, concepto text, bodega text, glosa text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT v.fecha, date_trunc('month', v.fecha)::DATE, v.total, v.cantidad,
           v.cod_prod, v.des_prod, left(v.cod_prod, 6), left(v.cod_prod, 3),
           c.activo_id, a.patente::TEXT, coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT),
           v.codi_cc, c.descripcion, coalesce(c.area, 'sin_clasificar')::TEXT,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.grupo, 'Taller / sin contrato')
                WHEN v.codi_cc IS NULL THEN 'Sin centro de costo'
                ELSE fn_cc_faena(c.zona, c.area) END,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.subfaena, 'Taller Coquimbo / sin contrato')
                WHEN v.codi_cc IS NULL THEN 'Sin centro de costo'
                WHEN fn_cc_faena(c.zona, c.area) = 'Calama' THEN 'Calibraciones (servicio Calama)'
                WHEN fn_cc_faena(c.zona, c.area) = 'Taller / sin contrato' THEN 'Taller Coquimbo / sin contrato'
                WHEN fn_cc_faena(c.zona, c.area) = 'Otras faenas' THEN coalesce(c.zona, 'Otras')
                ELSE fn_cc_faena(c.zona, c.area) END,
           v.folio, v.concepto, v.origen, v.glosa
      FROM v_costos_linea v
      LEFT JOIN softland_cc c ON c.codigo = v.codi_cc
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN LATERAL fn_activo_faena_sub_en(c.activo_id, v.fecha) fs ON c.activo_id IS NOT NULL
     WHERE v.fuente = p_fuente
       AND v.fecha BETWEEN p_desde AND p_fin
       AND NOT v.es_mercaderia
       AND (p_con_admin OR coalesce(c.area, 'sin_clasificar') NOT IN ('administracion', 'comercial'));
$function$;
REVOKE ALL ON FUNCTION fn_costos_lineas(date, date, boolean, text) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS rpc_costos_operacion_panel(date, date, text[]);
DROP FUNCTION IF EXISTS fn_costos_operacion_panel_datos(date, date, text[]);
CREATE OR REPLACE FUNCTION public.fn_costos_operacion_panel_datos(p_desde date, p_hasta date, p_areas text[] DEFAULT NULL::text[],
                                                                  p_fuente text DEFAULT 'oc')
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
    IF p_fuente NOT IN ('oc', 'bodega') THEN
        RAISE EXCEPTION 'Fuente no válida: %', p_fuente;
    END IF;

    WITH base AS (
        SELECT m.*, (m.mes BETWEEN v_desde AND v_hasta) AS en_periodo
          FROM mv_softland_costo_mes m
         WHERE m.fuente = p_fuente
           AND (m.mes BETWEEN v_desde AND v_hasta OR m.mes BETWEEN v_ant_desde AND v_ant_hasta)
           AND m.area = ANY (v_areas)
           AND NOT m.es_petroleo                       -- mercadería, no costo
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
            SELECT p.codi_cc, p.area, sc.descripcion, sum(p.total) AS total
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
REVOKE ALL ON FUNCTION fn_costos_operacion_panel_datos(date, date, text[], text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_costos_operacion_panel(p_desde date, p_hasta date, p_areas text[] DEFAULT NULL::text[],
                                                             p_fuente text DEFAULT 'oc')
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    RETURN fn_costos_operacion_panel_datos(p_desde, p_hasta, p_areas, p_fuente);
END $function$;

DROP FUNCTION IF EXISTS rpc_costos_operacion_acumulado(text[]);
CREATE OR REPLACE FUNCTION public.rpc_costos_operacion_acumulado(p_areas text[] DEFAULT NULL::text[], p_fuente text DEFAULT 'oc')
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_areas TEXT[] := coalesce(p_areas, ARRAY['equipo','operacion','taller','proyectos','generico','sin_clasificar']);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH base AS (
        SELECT m.mes, m.total
          FROM mv_softland_costo_mes m
         WHERE m.fuente = p_fuente
           AND m.area = ANY (v_areas)
           AND NOT m.es_petroleo
    ), anio AS (
        SELECT extract(year FROM mes)::INTEGER AS anio, sum(total) AS total, count(DISTINCT mes) AS meses
          FROM base GROUP BY 1
    )
    SELECT jsonb_build_object(
        'desde', (SELECT min(mes) FROM base),
        'hasta', (SELECT max(mes) FROM base),
        'total', coalesce((SELECT sum(total) FROM base), 0),
        'por_anio', (SELECT coalesce(jsonb_agg(jsonb_build_object('anio', anio, 'total', total, 'meses', meses)
                                               ORDER BY anio), '[]') FROM anio)
    ) INTO r;
    RETURN r;
END $function$;

DROP FUNCTION IF EXISTS rpc_costos_operacion_detalle(date, date, text, text, integer);
CREATE OR REPLACE FUNCTION public.rpc_costos_operacion_detalle(p_desde date, p_hasta date, p_codi_cc text DEFAULT NULL::text,
                                                               p_familia text DEFAULT NULL::text, p_limite integer DEFAULT 500,
                                                               p_fuente text DEFAULT 'oc')
 RETURNS TABLE(fecha date, folio integer, concepto text, bodega text, codi_cc text, cod_prod text, des_prod text, cantidad numeric, precio_unit numeric, total numeric, glosa text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_codi_cc IS NULL AND p_familia IS NULL THEN
        RAISE EXCEPTION 'Indique centro de costo o familia.';
    END IF;

    RETURN QUERY
    SELECT v.fecha, v.folio, v.concepto, v.origen, v.codi_cc,
           v.cod_prod, v.des_prod, v.cantidad, v.precio_unit, v.total, v.glosa
      FROM v_costos_linea v
     WHERE v.fuente = p_fuente
       AND v.fecha >= p_desde AND v.fecha < (date_trunc('month', p_hasta) + INTERVAL '1 month')::DATE
       AND NOT v.es_mercaderia
       AND (p_codi_cc IS NULL
            OR (p_codi_cc = '(SIN CC)' AND v.codi_cc IS NULL)
            OR v.codi_cc = ANY (string_to_array(upper(p_codi_cc), ',')))
       AND (p_familia IS NULL OR left(v.cod_prod, length(p_familia)) = upper(p_familia))
     ORDER BY v.total DESC
     LIMIT least(coalesce(p_limite, 500), 2000);
END $function$;

DROP FUNCTION IF EXISTS rpc_costos_pareto(date, date, jsonb, text, boolean);
CREATE OR REPLACE FUNCTION public.rpc_costos_pareto(p_desde date, p_hasta date, p_filtros jsonb, p_dimension text,
                                                    p_con_admin boolean DEFAULT false, p_fuente text DEFAULT 'oc')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$  -- VOLATILE: usa tabla temporal
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
    IF p_dimension NOT IN ('faena','subfaena','equipo','familia','producto','centro_costo','mes','linea','proveedor') THEN
        RAISE EXCEPTION 'Dimensión no válida: %', p_dimension;
    END IF;

    CREATE TEMP TABLE _pl ON COMMIT DROP AS
    SELECT * FROM fn_costos_lineas(v_desde, v_fin, p_con_admin, p_fuente) l
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
       AND (f->>'tipo_equipo' IS NULL OR l.tipo_equipo = f->>'tipo_equipo')
       AND (f->>'proveedor' IS NULL OR l.bodega = f->>'proveedor');

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
                 WHEN 'proveedor'    THEN coalesce(bodega, '(sin proveedor)')
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
END $function$;

DROP FUNCTION IF EXISTS rpc_costos_por_faena(date, date);
CREATE OR REPLACE FUNCTION public.rpc_costos_por_faena(p_desde date, p_hasta date, p_fuente text DEFAULT 'oc')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$  -- VOLATILE: usa tabla temporal
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    CREATE TEMP TABLE _fl ON COMMIT DROP AS SELECT * FROM fn_costos_lineas(v_desde, v_fin, FALSE, p_fuente);

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
               sum(total) FILTER (WHERE grupo_prod = 'ISE') AS seguridad_epp,
               sum(total) FILTER (WHERE grupo_prod = 'SER') AS servicios
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
END $function$;

DROP FUNCTION IF EXISTS rpc_costos_faena_equipos(date, date, text, text);
CREATE OR REPLACE FUNCTION public.rpc_costos_faena_equipos(p_desde date, p_hasta date, p_faena text, p_subfaena text DEFAULT NULL::text,
                                                           p_fuente text DEFAULT 'oc')
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH d AS (
        SELECT m.activo_id, count(*) AS dias, min(m.fecha) AS desde, max(m.fecha) AS hasta,
               count(*) FILTER (WHERE m.fuente = 'gps') AS dias_gps,
               count(*) FILTER (WHERE m.fuente = 'estado_diario') AS dias_estado,
               count(*) FILTER (WHERE m.fuente IN ('arrastre', 'primer_dato')) AS dias_arrastre,
               string_agg(DISTINCT m.subfaena, ', ') AS subfaenas
          FROM mv_activo_faena_dia m
         WHERE m.grupo = p_faena
           AND (p_subfaena IS NULL OR m.subfaena = p_subfaena)
           AND m.fecha BETWEEN v_desde AND v_fin
         GROUP BY m.activo_id
    ), c AS (
        SELECT l.activo_id, sum(l.total) AS costo
          FROM fn_costos_lineas(v_desde, v_fin, FALSE, p_fuente) l
         WHERE l.faena = p_faena AND (p_subfaena IS NULL OR l.subfaena = p_subfaena)
           AND l.activo_id IS NOT NULL
         GROUP BY l.activo_id
    )
    SELECT jsonb_build_object(
        'dias_periodo', (v_fin - v_desde + 1),
        'equipos', coalesce(jsonb_agg(jsonb_build_object(
            'activo_id', coalesce(d.activo_id, c.activo_id),
            'patente', a.patente, 'tipo', coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT),
            'faena_ficha', fa.nombre,
            'dias', coalesce(d.dias, 0), 'desde', d.desde, 'hasta', d.hasta,
            'dias_gps', coalesce(d.dias_gps, 0), 'dias_estado', coalesce(d.dias_estado, 0),
            'dias_arrastre', coalesce(d.dias_arrastre, 0),
            'subfaenas', d.subfaenas,
            'costo', coalesce(c.costo, 0))
          ORDER BY coalesce(d.dias, 0) DESC, coalesce(c.costo, 0) DESC), '[]'))
      INTO r
      FROM d
      FULL JOIN c ON c.activo_id = d.activo_id
      JOIN activos a ON a.id = coalesce(d.activo_id, c.activo_id)
      LEFT JOIN faenas fa ON fa.id = a.faena_id;
    RETURN r;
END $function$;

-- Permisos de las RPC del panel: igual que antes (la puerta es fn_costos_operacion_puede_ver,
-- que acepta sesión con permiso o el token del link, MIG620).
DO $$
DECLARE f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'rpc_costos_operacion_panel(date, date, text[], text)',
        'rpc_costos_operacion_acumulado(text[], text)',
        'rpc_costos_operacion_detalle(date, date, text, text, integer, text)',
        'rpc_costos_pareto(date, date, jsonb, text, boolean, text)',
        'rpc_costos_por_faena(date, date, text)',
        'rpc_costos_faena_equipos(date, date, text, text, text)']
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, anon', f);
    END LOOP;
END $$;

-- ── Informe mensual por correo: pasa a OC ───────────────────────────────────
-- Mismo cuerpo que MIG617, con la fuente fija en 'oc' en las dos consultas
-- directas al resumen (antes sumaban sin distinguir fuente).
DO $$
DECLARE v_def TEXT;
BEGIN
    v_def := pg_get_functiondef('public.fn_reporte_costos_publico'::regproc);
    IF position('mv.fuente = ''oc''' IN v_def) > 0 THEN RETURN; END IF;   -- ya aplicado
    IF position('WHERE mv.mes = v_mes AND NOT mv.es_petroleo AND mv.area = ''equipo''' IN v_def) = 0
       OR position('WHERE mv.mes = v_ant AND NOT mv.es_petroleo' IN v_def) = 0 THEN
        RAISE EXCEPTION 'MIG628: fn_reporte_costos_publico no tiene el cuerpo esperado';
    END IF;
    v_def := replace(v_def, 'WHERE mv.mes = v_mes AND NOT mv.es_petroleo AND mv.area = ''equipo''',
                            'WHERE mv.fuente = ''oc'' AND mv.mes = v_mes AND NOT mv.es_petroleo AND mv.area = ''equipo''');
    v_def := replace(v_def, 'WHERE mv.mes = v_ant AND NOT mv.es_petroleo',
                            'WHERE mv.fuente = ''oc'' AND mv.mes = v_ant AND NOT mv.es_petroleo');
    EXECUTE v_def;
END $$;

-- El cierre de la corrida diaria ya refresca mv_softland_costo_mes, que ahora incluye las OC.
SELECT 'ok' AS mig628;
