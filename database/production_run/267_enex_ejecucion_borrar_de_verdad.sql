-- ============================================================================
-- SICOM-ICEO | 267 — En terreno, borrar tiene que borrar
-- ----------------------------------------------------------------------------
-- rpc_enex_ejecutar_pauta solo SUMABA: la galería que llegaba vacía conservaba
-- la anterior y el N° OT / la observación de la ejecución se guardaban con
-- COALESCE. Consecuencia en terreno: el mantenedor quitaba una foto mal sacada
-- (o desmarcaba una actividad) y al reabrir el servicio seguía ahí, porque el
-- servidor nunca la soltó. La foto equivocada llegaba igual al informe del
-- mandante.
--
-- Ese COALESCE existía por una buena razón: cuando la app no sabía qué fotos
-- había ya subidas, mandaba la galería vacía y habría borrado evidencia real.
-- Eso se resolvió en los PR #94/#95 — ahora la pantalla se hidrata siempre
-- desde el servidor y manda el estado completo de lo que muestra.
--
-- Para no confiar en que TODOS los teléfonos tengan la app nueva (es una PWA:
-- puede quedar un bundle viejo cacheado), el borrado es OPT-IN:
--   p_reemplazar = false (por defecto, y lo que manda un cliente viejo)
--       → comportamiento de siempre: lo que llega vacío no pisa lo guardado.
--   p_reemplazar = true (lo manda la app nueva)
--       → los ítems que VIAJAN en p_items se escriben tal cual: una galería
--         vacía vacía, un resultado nulo desmarca. Los ítems que NO viajan
--         siguen sin tocarse (la pauta se ataca por partes).
--
-- Las FIRMAS nunca se borran por esta vía: un «guardar avance» sin firma no
-- puede tumbar la firma del mandante, que es la que sostiene el KPI.
--
-- NO DESTRUCTIVA. No toca datos: solo reemplaza la función.
-- Se hace DROP de la firma anterior a propósito: con dos overloads PostgREST
-- elige cualquiera y los parámetros nuevos se pierden en silencio.
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid,
    text, text, timestamptz, timestamptz, integer);

CREATE OR REPLACE FUNCTION public.rpc_enex_ejecutar_pauta(
    p_programacion_id uuid,
    p_items jsonb,
    p_ot_numero text DEFAULT NULL::text,
    p_ejecutor text DEFAULT NULL::text,
    p_observacion text DEFAULT NULL::text,
    p_fecha date DEFAULT NULL::date,
    p_evidencia_urls text[] DEFAULT NULL::text[],
    p_firma_tecnico_url text DEFAULT NULL::text,
    p_tecnico_nombre text DEFAULT NULL::text,
    p_firma_mandante_url text DEFAULT NULL::text,
    p_firmante_mandante text DEFAULT NULL::text,
    p_client_uuid uuid DEFAULT NULL::uuid,
    p_foto_antes_url text DEFAULT NULL::text,
    p_foto_despues_url text DEFAULT NULL::text,
    p_inicio_at timestamptz DEFAULT NULL::timestamptz,
    p_fin_at timestamptz DEFAULT NULL::timestamptz,
    p_duracion_segundos integer DEFAULT NULL::integer,
    p_reemplazar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_pauta UUID; v_ejec UUID; v_firma_m TEXT; v_estado TEXT; it JSONB;
    v_item RECORD; v_dentro BOOLEAN; v_valor NUMERIC; v_n INT := 0;
    v_fa JSONB; v_fd JSONB; v_rep BOOLEAN := COALESCE(p_reemplazar, false);
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_programaciones WHERE id = p_programacion_id) THEN
        RAISE EXCEPTION 'Programación no existe'; END IF;

    v_pauta := fn_enex_pauta_de_programacion(p_programacion_id);
    v_firma_m := NULLIF(TRIM(COALESCE(p_firma_mandante_url,'')),'');
    v_estado := CASE WHEN v_firma_m IS NOT NULL THEN 'cumplida' ELSE 'ejecutada' END;

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion, ot_numero, ejecutor,
        observacion, evidencia_urls, firma_tecnico_url, tecnico_nombre,
        firma_mandante_url, firmante_mandante_nombre, firmante_mandante_at, registrado_por, client_uuid,
        foto_antes_url, foto_despues_url, inicio_at, fin_at, duracion_segundos)
    VALUES (p_programacion_id, v_pauta, v_estado, COALESCE(p_fecha, CURRENT_DATE), p_ot_numero, p_ejecutor,
        p_observacion, p_evidencia_urls, NULLIF(TRIM(COALESCE(p_firma_tecnico_url,'')),''),
        NULLIF(TRIM(COALESCE(p_tecnico_nombre,'')),''), v_firma_m,
        NULLIF(TRIM(COALESCE(p_firmante_mandante,'')),''),
        CASE WHEN v_firma_m IS NOT NULL THEN NOW() END, auth.uid(), p_client_uuid,
        NULLIF(TRIM(COALESCE(p_foto_antes_url,'')),''), NULLIF(TRIM(COALESCE(p_foto_despues_url,'')),''),
        p_inicio_at, p_fin_at, p_duracion_segundos)
    ON CONFLICT (programacion_id) DO UPDATE SET
        pauta_id = EXCLUDED.pauta_id, estado = v_estado,
        fecha_ejecucion = COALESCE(EXCLUDED.fecha_ejecucion, enex_ejecuciones.fecha_ejecucion),
        -- [MIG267] Con p_reemplazar, vaciar el N° OT o la observación general
        -- se guarda; sin él, se conserva lo anterior (cliente viejo).
        ot_numero = CASE WHEN v_rep THEN EXCLUDED.ot_numero
                         ELSE COALESCE(EXCLUDED.ot_numero, enex_ejecuciones.ot_numero) END,
        ejecutor = COALESCE(EXCLUDED.ejecutor, enex_ejecuciones.ejecutor),
        observacion = CASE WHEN v_rep THEN EXCLUDED.observacion
                           ELSE COALESCE(EXCLUDED.observacion, enex_ejecuciones.observacion) END,
        evidencia_urls = COALESCE(EXCLUDED.evidencia_urls, enex_ejecuciones.evidencia_urls),
        -- Las firmas NO se sueltan nunca: sostienen el KPI del contrato.
        firma_tecnico_url = COALESCE(EXCLUDED.firma_tecnico_url, enex_ejecuciones.firma_tecnico_url),
        tecnico_nombre = COALESCE(EXCLUDED.tecnico_nombre, enex_ejecuciones.tecnico_nombre),
        firma_mandante_url = COALESCE(EXCLUDED.firma_mandante_url, enex_ejecuciones.firma_mandante_url),
        firmante_mandante_nombre = COALESCE(EXCLUDED.firmante_mandante_nombre, enex_ejecuciones.firmante_mandante_nombre),
        firmante_mandante_at = COALESCE(enex_ejecuciones.firmante_mandante_at, EXCLUDED.firmante_mandante_at),
        -- [MIG265] el inicio es el de la primera vez que se abrió el trabajo;
        -- el fin y la duración, los del último guardado.
        inicio_at = COALESCE(enex_ejecuciones.inicio_at, EXCLUDED.inicio_at),
        fin_at = COALESCE(EXCLUDED.fin_at, enex_ejecuciones.fin_at),
        duracion_segundos = GREATEST(COALESCE(EXCLUDED.duracion_segundos, 0),
                                     COALESCE(enex_ejecuciones.duracion_segundos, 0)),
        updated_at = NOW()
    RETURNING id INTO v_ejec;

    FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
        SELECT * INTO v_item FROM enex_pauta_items WHERE id = (it->>'pauta_item_id')::UUID;
        IF v_item.id IS NULL THEN CONTINUE; END IF;
        v_valor := NULLIF(it->>'valor_medicion','')::NUMERIC;
        v_dentro := NULL;
        IF v_item.tipo_campo = 'medicion' AND v_valor IS NOT NULL
           AND (v_item.tolerancia_min IS NOT NULL OR v_item.tolerancia_max IS NOT NULL) THEN
            v_dentro := (v_item.tolerancia_min IS NULL OR v_valor >= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_min)
                    AND (v_item.tolerancia_max IS NULL OR v_valor <= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_max);
        END IF;

        -- [MIG265] Galerías. Si viene el formato viejo (una URL suelta), se
        -- convierte en un array de uno para no perder nada.
        v_fa := COALESCE(it->'fotos_antes', '[]'::jsonb);
        IF jsonb_typeof(v_fa) <> 'array' THEN v_fa := '[]'::jsonb; END IF;
        IF v_fa = '[]'::jsonb AND NULLIF(it->>'foto_antes_url','') IS NOT NULL THEN
            v_fa := jsonb_build_array(it->>'foto_antes_url');
        END IF;
        v_fd := COALESCE(it->'fotos_despues', '[]'::jsonb);
        IF jsonb_typeof(v_fd) <> 'array' THEN v_fd := '[]'::jsonb; END IF;
        IF v_fd = '[]'::jsonb AND NULLIF(it->>'foto_despues_url','') IS NOT NULL THEN
            v_fd := jsonb_build_array(it->>'foto_despues_url');
        END IF;

        INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, valor_medicion,
            dentro_tolerancia, foto_url, foto_antes_url, foto_despues_url, observacion,
            fotos_antes, fotos_despues)
        VALUES (v_ejec, v_item.id, NULLIF(it->>'resultado',''), v_valor, v_dentro,
            NULLIF(it->>'foto_url',''),
            COALESCE(NULLIF(it->>'foto_antes_url',''), v_fa->>0),
            COALESCE(NULLIF(it->>'foto_despues_url',''), v_fd->>0),
            NULLIF(it->>'observacion',''), v_fa, v_fd)
        ON CONFLICT (ejecucion_id, pauta_item_id) DO UPDATE SET
            resultado = EXCLUDED.resultado, valor_medicion = EXCLUDED.valor_medicion,
            dentro_tolerancia = EXCLUDED.dentro_tolerancia,
            -- [MIG267] Con p_reemplazar, la galería que llega manda aunque
            -- venga vacía: así una foto mal sacada se puede sacar del informe.
            foto_url = CASE WHEN v_rep THEN EXCLUDED.foto_url
                            ELSE COALESCE(EXCLUDED.foto_url, enex_ejecucion_items.foto_url) END,
            foto_antes_url = CASE WHEN v_rep THEN EXCLUDED.foto_antes_url
                                  ELSE COALESCE(EXCLUDED.foto_antes_url, enex_ejecucion_items.foto_antes_url) END,
            foto_despues_url = CASE WHEN v_rep THEN EXCLUDED.foto_despues_url
                                    ELSE COALESCE(EXCLUDED.foto_despues_url, enex_ejecucion_items.foto_despues_url) END,
            fotos_antes = CASE WHEN NOT v_rep AND EXCLUDED.fotos_antes = '[]'::jsonb
                               THEN enex_ejecucion_items.fotos_antes ELSE EXCLUDED.fotos_antes END,
            fotos_despues = CASE WHEN NOT v_rep AND EXCLUDED.fotos_despues = '[]'::jsonb
                                 THEN enex_ejecucion_items.fotos_despues ELSE EXCLUDED.fotos_despues END,
            observacion = EXCLUDED.observacion;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec, 'estado', v_estado,
        'cumplida', v_firma_m IS NOT NULL, 'items', v_n, 'pauta_id', v_pauta,
        'duracion_segundos', p_duracion_segundos, 'reemplazar', v_rep);
END $function$;

-- Permisos idénticos a los que tenía la función anterior: authenticated +
-- service_role, nunca PUBLIC/anon. Hay que revocar los dos por separado:
-- crear una función otorga EXECUTE a PUBLIC, y los default privileges del
-- esquema public en Supabase se lo otorgan además a anon. Esta función escribe
-- las ejecuciones que sostienen el KPI del contrato.
REVOKE ALL ON FUNCTION public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid,
    text, text, timestamptz, timestamptz, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid,
    text, text, timestamptz, timestamptz, integer, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid,
    text, text, timestamptz, timestamptz, integer, boolean) TO authenticated, service_role;
