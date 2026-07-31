-- ============================================================================
-- SICOM-ICEO | 265 — Terreno ENEX: antes/después en todo ítem, varias fotos y
--                    tiempo de ejecución
-- ----------------------------------------------------------------------------
-- Pedido de Manuel sobre /m/enex (la app del mantenedor en terreno):
--   · que cada ítem de la pauta se pueda comprimir            → UI
--   · que exija foto del ANTES y del DESPUÉS                  → aquí + UI
--   · que siempre baje las actividades para trabajar sin señal → UI/offline
--   · que permita sacar MÁS DE UNA foto                       → aquí + UI
--   · que la app tome el TIEMPO de la ejecución               → aquí + UI
--
-- Hoy el antes/después existía solo para las actividades marcadas «críticas»
-- (MIG238) y guardaba UNA foto de cada una: foto_antes_url / foto_despues_url.
-- Ahora cada ítem lleva dos galerías (fotos_antes / fotos_despues) y la primera
-- foto de cada una sigue copiándose a las columnas viejas, porque de ahí las
-- lee el informe PDF del mandante.
--
-- El tiempo se guarda en la ejecución: cuándo empezó, cuándo cerró y cuántos
-- segundos efectivos estuvo el mantenedor en el trabajo.
--
-- ADITIVA, IDEMPOTENTE. No borra datos ni rompe lo ya registrado.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_enex_ejecutar_pauta') THEN
        RAISE EXCEPTION 'STOP — falta rpc_enex_ejecutar_pauta (MIG208).';
    END IF;
END $$;


-- ── 1. Galerías por ítem y tiempo por ejecución ─────────────────────────────
ALTER TABLE public.enex_ejecucion_items
    ADD COLUMN IF NOT EXISTS fotos_antes   JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS fotos_despues JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.enex_ejecucion_items.fotos_antes IS
    'Todas las fotos del ANTES del ítem (array de URLs). foto_antes_url guarda la primera. MIG265.';
COMMENT ON COLUMN public.enex_ejecucion_items.fotos_despues IS
    'Todas las fotos del DESPUÉS del ítem (array de URLs). foto_despues_url guarda la primera. MIG265.';

-- Lo ya registrado con una sola foto pasa a la galería, para que el informe
-- nuevo no muestre vacías las ejecuciones viejas.
UPDATE public.enex_ejecucion_items
   SET fotos_antes = jsonb_build_array(foto_antes_url)
 WHERE foto_antes_url IS NOT NULL AND fotos_antes = '[]'::jsonb;
UPDATE public.enex_ejecucion_items
   SET fotos_despues = jsonb_build_array(foto_despues_url)
 WHERE foto_despues_url IS NOT NULL AND fotos_despues = '[]'::jsonb;

ALTER TABLE public.enex_ejecuciones
    ADD COLUMN IF NOT EXISTS inicio_at         TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS fin_at            TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS duracion_segundos INT;

COMMENT ON COLUMN public.enex_ejecuciones.duracion_segundos IS
    'Tiempo que tomó la ejecución en terreno, medido por la app. MIG265.';


-- ── 2. La RPC recibe las galerías y el tiempo ───────────────────────────────
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
    -- [MIG265] tiempo medido por la app
    p_inicio_at timestamptz DEFAULT NULL,
    p_fin_at timestamptz DEFAULT NULL,
    p_duracion_segundos int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_pauta UUID; v_ejec UUID; v_firma_m TEXT; v_estado TEXT; it JSONB;
    v_item RECORD; v_dentro BOOLEAN; v_valor NUMERIC; v_n INT := 0;
    v_fa JSONB; v_fd JSONB;
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
        ot_numero = COALESCE(EXCLUDED.ot_numero, enex_ejecuciones.ot_numero),
        ejecutor = COALESCE(EXCLUDED.ejecutor, enex_ejecuciones.ejecutor),
        observacion = COALESCE(EXCLUDED.observacion, enex_ejecuciones.observacion),
        evidencia_urls = COALESCE(EXCLUDED.evidencia_urls, enex_ejecuciones.evidencia_urls),
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
            foto_url = COALESCE(EXCLUDED.foto_url, enex_ejecucion_items.foto_url),
            foto_antes_url = COALESCE(EXCLUDED.foto_antes_url, enex_ejecucion_items.foto_antes_url),
            foto_despues_url = COALESCE(EXCLUDED.foto_despues_url, enex_ejecucion_items.foto_despues_url),
            -- La galería que llega manda cuando trae algo; si viene vacía se
            -- conserva la anterior (guardar avance no borra fotos ya subidas).
            fotos_antes = CASE WHEN EXCLUDED.fotos_antes = '[]'::jsonb
                               THEN enex_ejecucion_items.fotos_antes ELSE EXCLUDED.fotos_antes END,
            fotos_despues = CASE WHEN EXCLUDED.fotos_despues = '[]'::jsonb
                                 THEN enex_ejecucion_items.fotos_despues ELSE EXCLUDED.fotos_despues END,
            observacion = EXCLUDED.observacion;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec, 'estado', v_estado,
        'cumplida', v_firma_m IS NOT NULL, 'items', v_n, 'pauta_id', v_pauta,
        'duracion_segundos', p_duracion_segundos);
END $function$;

-- La firma vieja (sin los 3 parámetros de tiempo) se elimina: con las dos,
-- PostgREST podría elegir cualquiera y el tiempo se perdería en silencio.
DROP FUNCTION IF EXISTS public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid, text, text);

REVOKE ALL ON FUNCTION public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid, text, text,
    timestamptz, timestamptz, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_ejecutar_pauta(
    uuid, jsonb, text, text, text, date, text[], text, text, text, text, uuid, text, text,
    timestamptz, timestamptz, int) TO authenticated;


-- ── 3. Cuánto se demoró cada servicio (para el panel y el KPI) ──────────────
CREATE OR REPLACE VIEW public.v_enex_tiempos_ejecucion AS
SELECT e.id AS ejecucion_id,
       e.programacion_id,
       p.periodo_anio AS anio, p.periodo_mes AS mes,
       i.nombre        AS instalacion,
       i.tipo          AS tipo_instalacion,
       p.tipo_servicio,
       e.fecha_ejecucion,
       e.ejecutor,
       e.inicio_at, e.fin_at,
       e.duracion_segundos,
       ROUND(e.duracion_segundos / 60.0, 1) AS duracion_minutos,
       e.estado,
       (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id = e.id)::int AS items,
       (SELECT count(*) FROM enex_ejecucion_items x
         WHERE x.ejecucion_id = e.id
           AND (jsonb_array_length(x.fotos_antes) + jsonb_array_length(x.fotos_despues)) > 0)::int AS items_con_evidencia,
       (SELECT COALESCE(sum(jsonb_array_length(x.fotos_antes) + jsonb_array_length(x.fotos_despues)), 0)
          FROM enex_ejecucion_items x WHERE x.ejecucion_id = e.id)::int AS fotos_totales
  FROM enex_ejecuciones e
  JOIN enex_programaciones p ON p.id = e.programacion_id
  LEFT JOIN enex_instalaciones i ON i.id = p.instalacion_id;

COMMENT ON VIEW public.v_enex_tiempos_ejecucion IS
    'Duración real de cada servicio de terreno ENEX y cuánta evidencia trae. MIG265.';

GRANT SELECT ON public.v_enex_tiempos_ejecucion TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_firmas INT; v_cols INT;
BEGIN
    -- Solo debe quedar la firma nueva de la RPC
    SELECT count(*) INTO v_firmas FROM pg_proc WHERE proname='rpc_enex_ejecutar_pauta';
    IF v_firmas <> 1 THEN
        RAISE EXCEPTION 'FALLO — quedaron % firmas de rpc_enex_ejecutar_pauta', v_firmas;
    END IF;

    SELECT count(*) INTO v_cols FROM information_schema.columns
     WHERE table_name='enex_ejecucion_items' AND column_name IN ('fotos_antes','fotos_despues');
    IF v_cols <> 2 THEN RAISE EXCEPTION 'FALLO — faltan las galerías de fotos'; END IF;

    SELECT count(*) INTO v_cols FROM information_schema.columns
     WHERE table_name='enex_ejecuciones' AND column_name IN ('inicio_at','fin_at','duracion_segundos');
    IF v_cols <> 3 THEN RAISE EXCEPTION 'FALLO — faltan las columnas de tiempo'; END IF;

    -- La vista responde
    PERFORM count(*) FROM v_enex_tiempos_ejecucion;

    RAISE NOTICE 'MIG265 OK — galerías antes/después, tiempo de ejecución y vista de tiempos. % ítems migrados con su foto previa',
        (SELECT count(*) FROM enex_ejecucion_items
          WHERE fotos_antes <> '[]'::jsonb OR fotos_despues <> '[]'::jsonb);
END $$;

NOTIFY pgrst, 'reload schema';
