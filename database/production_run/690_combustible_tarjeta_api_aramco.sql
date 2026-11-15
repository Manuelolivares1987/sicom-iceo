-- ============================================================================
-- MIG690 · Tarjeta Aramco Fleet (ESMAX) por API: reemplaza el Excel manual
-- ----------------------------------------------------------------------------
-- El web service SOAP de portaltarjetas.cl reemplaza la exportación a Excel de
-- la MIG659. Corre dentro de la base (pg_cron + pg_net), sin depender de Netlify.
--
--   * fn_aramco_solicitar_transacciones(desde, hasta): encola el POST SOAP
--     RetornarTransaccionesConsolidadas (todas las del período, máx 30 días).
--     NO se usan las operaciones «No Exportadas»: marcan las transacciones en
--     el portal como leídas y afectarían a otros usuarios del portal.
--   * fn_aramco_solicitar_tarjetas(): RetornarRestriccionesTarjetas (límite y
--     consumo por tarjeta). La operación de cambiar límites NO se usa.
--   * fn_aramco_procesar(): lee net._http_response, parsea el XML y guarda.
--
-- Credenciales: Vault, nombres aramco_rut y aramco_clave. Se cargan aparte,
-- nunca en este archivo ni en el repo.
--
-- Llave: la API no trae el «código de autorización» del Excel, trae
-- IDTransaccion. Las cargas del Excel se enlazan por patente + fecha_hora
-- exacta + guía de despacho (única en las 547, verificado 15-11-2026).
-- ============================================================================

-- ── 1. Columnas nuevas ──────────────────────────────────────────────────────
ALTER TABLE public.combustible_tarjeta_cargas
    ADD COLUMN IF NOT EXISTS id_transaccion TEXT,
    ADD COLUMN IF NOT EXISTS chofer         TEXT,
    ADD COLUMN IF NOT EXISTS region         TEXT,
    ADD COLUMN IF NOT EXISTS origen         TEXT NOT NULL DEFAULT 'excel';

CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_tarjeta_cargas_idtrx
    ON public.combustible_tarjeta_cargas (proveedor, id_transaccion)
    WHERE id_transaccion IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_comb_tarjeta_cargas_pat_fecha
    ON public.combustible_tarjeta_cargas (patente, fecha_hora);

-- ── 2. Bitácora de llamadas ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_api_llamadas (
    id           BIGSERIAL PRIMARY KEY,
    operacion    TEXT NOT NULL CHECK (operacion IN ('transacciones', 'tarjetas')),
    request_id   BIGINT NOT NULL,
    desde        DATE,
    hasta        DATE,
    estado       TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'ok', 'error')),
    resultado    JSONB,
    creada_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    procesada_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_comb_tarjeta_api_pend
    ON public.combustible_tarjeta_api_llamadas (id) WHERE estado = 'pendiente';
ALTER TABLE public.combustible_tarjeta_api_llamadas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS comb_tarjeta_api_ver ON public.combustible_tarjeta_api_llamadas;
CREATE POLICY comb_tarjeta_api_ver ON public.combustible_tarjeta_api_llamadas
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());

-- ── 3. Tarjetas: límite y consumo (última foto) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_tarjetas (
    proveedor        TEXT NOT NULL DEFAULT 'aramco',
    tarjeta          TEXT NOT NULL,          -- últimos 8 dígitos «XXXX XXXX», igual que el Excel
    patente          TEXT,                   -- normalizada: SPRY28
    activo_id        UUID REFERENCES public.activos(id) ON DELETE SET NULL,
    sucursal         TEXT,
    tipo_limite      TEXT,
    limite_monto     NUMERIC,
    consumo_monto    NUMERIC,
    limite_volumen   NUMERIC,
    consumo_volumen  NUMERIC,
    vista_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (proveedor, tarjeta)
);
ALTER TABLE public.combustible_tarjeta_tarjetas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS comb_tarjeta_tarjetas_ver ON public.combustible_tarjeta_tarjetas;
CREATE POLICY comb_tarjeta_tarjetas_ver ON public.combustible_tarjeta_tarjetas
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());

-- ── 4. Utilidades ───────────────────────────────────────────────────────────
-- Texto de un hijo directo de un nodo del namespace del portal. El nodo que
-- devuelve xpath() es un documento propio: el contexto es su raíz, por eso «/*/».
CREATE OR REPLACE FUNCTION public.fn_aramco_xml_txt(p_nodo XML, p_tag TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif((xpath('/*/p:' || p_tag || '/text()', p_nodo,
                         ARRAY[ARRAY['p', 'http://petrobrasflota.cl/']]))[1]::text, '')
$$;

-- Número de tarjeta → últimos 8 dígitos «XXXX XXXX» (no se guarda el número completo).
CREATE OR REPLACE FUNCTION public.fn_aramco_tarjeta_corta(p_tarjeta TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN length(p_tarjeta) >= 8
                THEN substr(right(p_tarjeta, 8), 1, 4) || ' ' || right(p_tarjeta, 4) END
$$;

-- ── 5. POST SOAP vía pg_net (net.http_post solo envía JSON: se encola directo,
--       igual que lo hace net.http_post por dentro) ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_aramco_soap(p_operacion TEXT, p_extra TEXT DEFAULT '')
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_rut   TEXT;
    v_clave TEXT;
    v_body  TEXT;
    v_id    BIGINT;
BEGIN
    SELECT decrypted_secret INTO v_rut   FROM vault.decrypted_secrets WHERE name = 'aramco_rut';
    SELECT decrypted_secret INTO v_clave FROM vault.decrypted_secrets WHERE name = 'aramco_clave';
    IF v_rut IS NULL OR v_clave IS NULL THEN
        RAISE EXCEPTION 'Faltan los secretos aramco_rut / aramco_clave en Vault.';
    END IF;
    v_body := format(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
        '<soap:Body><%1$s xmlns="http://petrobrasflota.cl/">'
        '<credenciales><RUT>%2$s</RUT><Senha>%3$s</Senha></credenciales>%4$s'
        '</%1$s></soap:Body></soap:Envelope>',
        p_operacion, v_rut, v_clave, coalesce(p_extra, ''));

    INSERT INTO net.http_request_queue (method, url, headers, body, timeout_milliseconds)
    VALUES ('POST',
            'https://www.portaltarjetas.cl/wstransaccionesflota/wstransaccionesflota.asmx',
            jsonb_build_object('Content-Type', 'text/xml; charset=utf-8',
                               'SOAPAction', '"http://petrobrasflota.cl/' || p_operacion || '"'),
            convert_to(v_body, 'UTF8'),
            60000)
    RETURNING id INTO v_id;
    PERFORM net.wake();
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.fn_aramco_soap(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_aramco_solicitar_transacciones(p_desde DATE, p_hasta DATE)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_req BIGINT;
BEGIN
    IF p_hasta < p_desde OR p_hasta - p_desde > 30 THEN
        RAISE EXCEPTION 'El portal acepta períodos de hasta 30 días.';
    END IF;
    v_req := public.fn_aramco_soap('RetornarTransaccionesConsolidadas',
        format('<dataInicial>%s</dataInicial><dataFinal>%s</dataFinal>', p_desde, p_hasta));
    INSERT INTO combustible_tarjeta_api_llamadas (operacion, request_id, desde, hasta)
    VALUES ('transacciones', v_req, p_desde, p_hasta);
    RETURN v_req;
END $$;
REVOKE ALL ON FUNCTION public.fn_aramco_solicitar_transacciones(DATE, DATE) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_aramco_solicitar_tarjetas()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_req BIGINT;
BEGIN
    v_req := public.fn_aramco_soap('RetornarRestriccionesTarjetas');
    INSERT INTO combustible_tarjeta_api_llamadas (operacion, request_id) VALUES ('tarjetas', v_req);
    RETURN v_req;
END $$;
REVOKE ALL ON FUNCTION public.fn_aramco_solicitar_tarjetas() FROM PUBLIC, anon, authenticated;

-- ── 6. Guardar transacciones ya parseadas ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_aramco_guardar_transacciones(p_filas JSONB, p_hasta DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_imp       UUID;
    v_total     INT := jsonb_array_length(p_filas);
    v_enlazadas INT;
    v_nuevas    INT;
    v_con_gps   INT;
    v_archivo   TEXT := 'API Aramco ' || to_char(now() AT TIME ZONE 'America/Santiago', 'YYYY-MM-DD');
BEGIN
    -- a) Enlazar las que ya vinieron por Excel (misma patente, hora y guía).
    WITH f AS (
        SELECT * FROM jsonb_to_recordset(p_filas) AS x(id_transaccion TEXT, fecha_hora TIMESTAMP,
               patente TEXT, guia_despacho TEXT, factura TEXT, chofer TEXT, centro_costo TEXT, region TEXT)
    ), m AS (
        SELECT DISTINCT ON (c.id) c.id, f.id_transaccion, f.factura, f.chofer, f.centro_costo, f.region
          FROM f JOIN combustible_tarjeta_cargas c
            ON c.proveedor = 'aramco' AND c.id_transaccion IS NULL
           AND c.patente = f.patente AND c.fecha_hora = f.fecha_hora
           AND c.guia_despacho IS NOT DISTINCT FROM f.guia_despacho
         WHERE NOT EXISTS (SELECT 1 FROM combustible_tarjeta_cargas c2
                            WHERE c2.proveedor = 'aramco' AND c2.id_transaccion = f.id_transaccion)
    )
    UPDATE combustible_tarjeta_cargas c
       SET id_transaccion = m.id_transaccion,
           chofer         = coalesce(c.chofer, m.chofer),
           region         = coalesce(c.region, m.region),
           factura        = coalesce(c.factura, m.factura),
           centro_costo   = coalesce(c.centro_costo, m.centro_costo)
      FROM m WHERE m.id = c.id;
    GET DIAGNOSTICS v_enlazadas = ROW_COUNT;

    -- b) Un registro de importación por día (no uno por hora).
    SELECT id INTO v_imp FROM combustible_tarjeta_importaciones
     WHERE archivo = v_archivo ORDER BY created_at DESC LIMIT 1;
    IF v_imp IS NULL THEN
        INSERT INTO combustible_tarjeta_importaciones (archivo, filas) VALUES (v_archivo, 0)
        RETURNING id INTO v_imp;
    END IF;

    -- c) Nuevas.
    WITH f AS (
        SELECT * FROM jsonb_to_recordset(p_filas) AS x(
               id_transaccion TEXT, fecha_hora TIMESTAMP, tarjeta TEXT, patente TEXT,
               guia_despacho TEXT, factura TEXT, chofer TEXT, rut_chofer TEXT, odometro NUMERIC,
               producto TEXT, estacion TEXT, region TEXT, comuna TEXT, pizarra NUMERIC,
               litros NUMERIC, total_pizarra NUMERIC, total_descuento NUMERIC, total_pago NUMERIC,
               centro_costo TEXT)
         WHERE x.id_transaccion IS NOT NULL AND x.fecha_hora IS NOT NULL
           AND x.litros IS NOT NULL AND x.litros >= 0 AND coalesce(x.patente, '') <> ''
    ), ins AS (
        INSERT INTO combustible_tarjeta_cargas (
            importacion_id, origen, id_transaccion, cod_autorizacion, fecha_hora, tarjeta, patente,
            activo_id, centro_costo, guia_despacho, factura, chofer, rut_chofer, odometro_declarado,
            producto, estacion, region, comuna, pizarra_l, litros, total_pizarra, total_descuento, total_pago)
        SELECT v_imp, 'api', f.id_transaccion, 'API-' || f.id_transaccion, f.fecha_hora, f.tarjeta,
               f.patente,
               (SELECT a.id FROM activos a
                 WHERE regexp_replace(upper(a.patente), '[^A-Z0-9]', '', 'g') = f.patente
                 ORDER BY (a.fecha_baja IS NULL) DESC LIMIT 1),
               f.centro_costo, f.guia_despacho, f.factura, f.chofer, f.rut_chofer,
               nullif(f.odometro, 0), f.producto, f.estacion, f.region, f.comuna, f.pizarra,
               f.litros, f.total_pizarra, f.total_descuento, f.total_pago
          FROM f
         WHERE NOT EXISTS (SELECT 1 FROM combustible_tarjeta_cargas c
                            WHERE c.proveedor = 'aramco' AND c.id_transaccion = f.id_transaccion)
           AND NOT EXISTS (SELECT 1 FROM combustible_tarjeta_cargas c
                            WHERE c.proveedor = 'aramco' AND c.patente = f.patente
                              AND c.fecha_hora = f.fecha_hora
                              AND c.guia_despacho IS NOT DISTINCT FROM f.guia_despacho)
        ON CONFLICT DO NOTHING
        RETURNING id
    )
    SELECT count(*) INTO v_nuevas FROM ins;

    -- d) Posición GPS a la hora de la carga (misma regla que la MIG659: ±90 min).
    UPDATE combustible_tarjeta_cargas c
       SET gps_lat = s.latitud, gps_lng = s.longitud, gps_ts = s.ts_local, gps_dif_min = s.dif
      FROM (
        SELECT DISTINCT ON (c2.id) c2.id, l.latitud, l.longitud,
               public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado) AS ts_local,
               round(abs(extract(epoch FROM public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado)
                                            - c2.fecha_hora)) / 60)::int AS dif
          FROM combustible_tarjeta_cargas c2
          JOIN gps_eventos_log l
            ON l.activo_id = c2.activo_id AND l.latitud IS NOT NULL
           AND l.ts_gps BETWEEN ((c2.fecha_hora - interval '2 hours') AT TIME ZONE 'UTC')
                            AND ((c2.fecha_hora + interval '6 hours') AT TIME ZONE 'UTC')
         WHERE c2.importacion_id = v_imp AND c2.activo_id IS NOT NULL AND c2.gps_lat IS NULL
         ORDER BY c2.id, abs(extract(epoch FROM public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado)
                                              - c2.fecha_hora))
      ) s
     WHERE s.id = c.id AND s.dif <= 90;
    GET DIAGNOSTICS v_con_gps = ROW_COUNT;

    -- «hasta» = día cubierto por la consulta (no la última carga): la pantalla
    -- proyecta el mes en curso con este corte.
    UPDATE combustible_tarjeta_importaciones i
       SET filas     = i.filas + v_total,
           nuevas    = i.nuevas + v_nuevas,
           repetidas = i.repetidas + v_total - v_nuevas,
           desde     = coalesce((SELECT min(fecha_hora) FROM combustible_tarjeta_cargas WHERE importacion_id = v_imp), i.desde),
           hasta     = greatest(i.hasta, least(p_hasta::timestamp + interval '1 day' - interval '1 second',
                                               (now() AT TIME ZONE 'America/Santiago')::timestamp))
     WHERE i.id = v_imp;

    RETURN jsonb_build_object('filas', v_total, 'enlazadas', v_enlazadas, 'nuevas', v_nuevas,
                              'con_posicion_gps', v_con_gps);
END $$;
REVOKE ALL ON FUNCTION public.fn_aramco_guardar_transacciones(JSONB, DATE) FROM PUBLIC, anon, authenticated;

-- ── 7. Procesar respuestas de pg_net ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_aramco_procesar()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    r       RECORD;
    v_doc   XML;
    v_ns    TEXT[] := ARRAY[ARRAY['p', 'http://petrobrasflota.cl/']];
    v_err   TEXT;
    v_filas JSONB;
    v_res   JSONB;
    v_out   JSONB := '[]'::jsonb;
BEGIN
    FOR r IN
        SELECT l.*, h.status_code, h.content, h.timed_out, h.error_msg
          FROM combustible_tarjeta_api_llamadas l
          LEFT JOIN net._http_response h ON h.id = l.request_id
         WHERE l.estado = 'pendiente'
         ORDER BY l.id
    LOOP
        IF r.status_code IS NULL AND NOT coalesce(r.timed_out, false) AND r.error_msg IS NULL THEN
            -- Sin respuesta aún. pg_net borra respuestas a las 6 h: se da por perdida.
            IF r.creada_at < now() - interval '6 hours' THEN
                UPDATE combustible_tarjeta_api_llamadas
                   SET estado = 'error', procesada_at = now(),
                       resultado = jsonb_build_object('error', 'sin respuesta')
                 WHERE id = r.id;
            END IF;
            CONTINUE;
        END IF;
        BEGIN
            IF r.status_code IS DISTINCT FROM 200 THEN
                RAISE EXCEPTION 'HTTP % %', r.status_code,
                    left(coalesce(r.error_msg, CASE WHEN r.timed_out THEN 'timeout' END, r.content, ''), 300);
            END IF;
            v_doc := xmlparse(DOCUMENT regexp_replace(r.content, '^\s*(﻿)?<\?xml[^>]*\?>', ''));
            SELECT string_agg(e::text, ' | ') INTO v_err
              FROM unnest(xpath('//p:ListaErrores/*', v_doc, v_ns)) e;
            IF v_err IS NOT NULL THEN
                RAISE EXCEPTION 'Portal: %', left(v_err, 400);
            END IF;

            IF r.operacion = 'transacciones' THEN
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                         'id_transaccion',  fn_aramco_xml_txt(n, 'IDTransaccion'),
                         'fecha_hora',      fn_aramco_xml_txt(n, 'Fecha'),
                         'tarjeta',         fn_aramco_tarjeta_corta(fn_aramco_xml_txt(n, 'Tarjeta')),
                         'patente',         regexp_replace(upper(coalesce(fn_aramco_xml_txt(n, 'Patente'), '')), '[^A-Z0-9]', '', 'g'),
                         'guia_despacho',   fn_aramco_xml_txt(n, 'GuiaDespacho'),
                         'factura',         nullif(fn_aramco_xml_txt(n, 'Factura'), '0'),
                         'chofer',          fn_aramco_xml_txt(n, 'Chofer'),
                         'rut_chofer',      fn_aramco_xml_txt(n, 'RUTChofer'),
                         'odometro',        fn_aramco_xml_txt(n, 'Odometro')::numeric,
                         'producto',        fn_aramco_xml_txt(n, 'Producto'),
                         'estacion',        fn_aramco_xml_txt(n, 'EstacionServicio'),
                         'region',          fn_aramco_xml_txt(n, 'Region'),
                         'comuna',          fn_aramco_xml_txt(n, 'Comuna'),
                         'pizarra',         fn_aramco_xml_txt(n, 'Pizarra')::numeric,
                         'litros',          fn_aramco_xml_txt(n, 'Volumen')::numeric,
                         'total_pizarra',   fn_aramco_xml_txt(n, 'TotalPizarra')::numeric,
                         'total_descuento', fn_aramco_xml_txt(n, 'TotalDescuento')::numeric,
                         'total_pago',      fn_aramco_xml_txt(n, 'TotalPago')::numeric,
                         'centro_costo',    nullif(fn_aramco_xml_txt(n, 'NombreCentroCosto'), '-'))), '[]'::jsonb)
                  INTO v_filas
                  FROM unnest(xpath('//p:TransacoesExportacao', v_doc, v_ns)) n;
                v_res := public.fn_aramco_guardar_transacciones(v_filas, r.hasta);
            ELSE
                WITH t AS (
                    SELECT fn_aramco_tarjeta_corta(fn_aramco_xml_txt(n, 'Tarjeta')) AS tarjeta,
                           regexp_replace(upper(coalesce(fn_aramco_xml_txt(n, 'Patente'), '')), '[^A-Z0-9]', '', 'g') AS pat,
                           fn_aramco_xml_txt(n, 'Sucursal') AS sucursal,
                           fn_aramco_xml_txt(n, 'TipoLimite') AS tipo_limite,
                           fn_aramco_xml_txt(n, 'LimiteMonto')::numeric AS limite_monto,
                           fn_aramco_xml_txt(n, 'ConsumoMonto')::numeric AS consumo_monto,
                           fn_aramco_xml_txt(n, 'LimiteVolumen')::numeric AS limite_volumen,
                           fn_aramco_xml_txt(n, 'ConsumoVolumen')::numeric AS consumo_volumen
                      FROM unnest(xpath('//p:RestricoesCartoesResultado', v_doc, v_ns)) n
                ), u AS (
                    INSERT INTO combustible_tarjeta_tarjetas (
                        tarjeta, patente, activo_id, sucursal, tipo_limite, limite_monto, consumo_monto,
                        limite_volumen, consumo_volumen, vista_at)
                    SELECT DISTINCT ON (t.tarjeta)
                           t.tarjeta, t.pat,
                           (SELECT a.id FROM activos a
                             WHERE regexp_replace(upper(a.patente), '[^A-Z0-9]', '', 'g') = t.pat
                             ORDER BY (a.fecha_baja IS NULL) DESC LIMIT 1),
                           t.sucursal, t.tipo_limite, t.limite_monto, t.consumo_monto,
                           t.limite_volumen, t.consumo_volumen, now()
                      FROM t WHERE t.tarjeta IS NOT NULL
                    ON CONFLICT (proveedor, tarjeta) DO UPDATE SET
                        patente = EXCLUDED.patente, activo_id = EXCLUDED.activo_id,
                        sucursal = EXCLUDED.sucursal, tipo_limite = EXCLUDED.tipo_limite,
                        limite_monto = EXCLUDED.limite_monto, consumo_monto = EXCLUDED.consumo_monto,
                        limite_volumen = EXCLUDED.limite_volumen, consumo_volumen = EXCLUDED.consumo_volumen,
                        vista_at = EXCLUDED.vista_at
                    RETURNING 1
                )
                SELECT jsonb_build_object('tarjetas', count(*)) INTO v_res FROM u;
            END IF;

            UPDATE combustible_tarjeta_api_llamadas
               SET estado = 'ok', procesada_at = now(), resultado = v_res WHERE id = r.id;
            v_out := v_out || jsonb_build_object('id', r.id, 'ok', v_res);
        EXCEPTION WHEN OTHERS THEN
            UPDATE combustible_tarjeta_api_llamadas
               SET estado = 'error', procesada_at = now(),
                   resultado = jsonb_build_object('error', left(SQLERRM, 500))
             WHERE id = r.id;
            v_out := v_out || jsonb_build_object('id', r.id, 'error', left(SQLERRM, 200));
        END;
    END LOOP;
    RETURN v_out;
END $$;
REVOKE ALL ON FUNCTION public.fn_aramco_procesar() FROM PUBLIC, anon, authenticated;

-- ── 8. Botón «Sincronizar ahora» (mismos permisos que cargar el Excel) ──────
CREATE OR REPLACE FUNCTION public.rpc_combustible_tarjeta_sincronizar()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::date;
BEGIN
    IF auth.uid() IS NULL OR NOT public.fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM combustible_tarjeta_api_llamadas
                WHERE estado = 'pendiente' AND creada_at > now() - interval '2 minutes') THEN
        RETURN jsonb_build_object('encolada', false, 'motivo', 'Ya hay una consulta en curso.');
    END IF;
    PERFORM public.fn_aramco_solicitar_transacciones(v_hoy - 3, v_hoy);
    RETURN jsonb_build_object('encolada', true);
END $$;
REVOKE ALL ON FUNCTION public.rpc_combustible_tarjeta_sincronizar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_combustible_tarjeta_sincronizar() TO authenticated;

-- Procesar desde el front (tras el botón) sin esperar al cron de 5 min.
CREATE OR REPLACE FUNCTION public.rpc_combustible_tarjeta_procesar()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    RETURN public.fn_aramco_procesar();
END $$;
REVOKE ALL ON FUNCTION public.rpc_combustible_tarjeta_procesar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_combustible_tarjeta_procesar() TO authenticated;

-- ── 9. El import de Excel se salta las cargas que ya llegaron por la API ────
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_excel_ya_por_api()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.origen = 'excel' AND EXISTS (
        SELECT 1 FROM combustible_tarjeta_cargas c
         WHERE c.proveedor = NEW.proveedor AND c.patente = NEW.patente
           AND c.fecha_hora = NEW.fecha_hora
           AND c.guia_despacho IS NOT DISTINCT FROM NEW.guia_despacho) THEN
        RETURN NULL;   -- ya está: no se inserta (cuenta como repetida)
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_comb_tarjeta_excel_ya_por_api ON public.combustible_tarjeta_cargas;
CREATE TRIGGER trg_comb_tarjeta_excel_ya_por_api
    BEFORE INSERT ON public.combustible_tarjeta_cargas
    FOR EACH ROW EXECUTE FUNCTION public.fn_comb_tarjeta_excel_ya_por_api();

-- ── 10. Cron ────────────────────────────────────────────────────────────────
-- Cada hora: últimos 3 días (las transacciones llegan con atraso). Cada día
-- 06:10 Chile: límites y consumo de tarjetas. Cada 5 min: procesar respuestas.
DO $$
BEGIN
    PERFORM cron.unschedule(jobname) FROM cron.job
     WHERE jobname IN ('aramco-transacciones', 'aramco-tarjetas', 'aramco-procesar');
    PERFORM cron.schedule('aramco-transacciones', '7 * * * *',
        $c$SELECT public.fn_aramco_solicitar_transacciones(
               (now() AT TIME ZONE 'America/Santiago')::date - 3,
               (now() AT TIME ZONE 'America/Santiago')::date)$c$);
    PERFORM cron.schedule('aramco-tarjetas', '10 9 * * *',
        $c$SELECT public.fn_aramco_solicitar_tarjetas()$c$);
    PERFORM cron.schedule('aramco-procesar', '*/5 * * * *',
        $c$SELECT public.fn_aramco_procesar()$c$);
END $$;

SELECT 'MIG690 OK' AS resultado;
