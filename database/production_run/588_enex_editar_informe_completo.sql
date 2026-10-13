-- ############################################################################
-- MIG588 · Editar el informe ENEX completo desde la web
-- ----------------------------------------------------------------------------
-- MIG586 dejó editar solo la observación general y el N° OT. Manuel quiere
-- editar el informe completo desde el lápiz de /dashboard/enex/informes:
-- datos del servicio, resultado y observación de cada actividad, y poner o
-- sacar fotos (antes/después de cada actividad y el registro complementario).
--
-- POR QUÉ UN RPC PROPIO Y NO rpc_enex_ejecutar_pauta
-- El de terreno es para ejecutar: exige permiso de ejecutor, recalcula el
-- estado (ejecutada/cumplida), suma duración del cronómetro y anota quién
-- registró. Editar un informe desde la oficina no es ejecutar: no debe tocar
-- la duración, las firmas ni el estado.
--
-- REGLAS
--   · Permiso: fn_enex_puede_gestionar() (los mismos que gestionan informes).
--   · Con la firma de ESM puesta no se edita (MIG287/586): lo que ESM firmó
--     es lo que ESM vio.
--   · Las actividades que llegan reemplazan lo que había (fotos incluidas):
--     así sacar una foto la saca de verdad. Una actividad que llega vacía se
--     borra del informe. Las que no llegan no se tocan.
--   · Cualquier cambio deja informe_pdf_url en NULL para rehacer el PDF.
-- ############################################################################

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_enex_informe_guardar(
    p_ejecucion_id   UUID,
    p_fecha          DATE    DEFAULT NULL,
    p_ot_numero      TEXT    DEFAULT NULL,
    p_ejecutor       TEXT    DEFAULT NULL,
    p_observacion    TEXT    DEFAULT NULL,
    p_evidencia_urls TEXT[]  DEFAULT NULL,
    p_items          JSONB   DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_e      RECORD;
    it       JSONB;
    v_item   RECORD;
    v_valor  NUMERIC;
    v_dentro BOOLEAN;
    v_fa     JSONB;
    v_fd     JSONB;
    v_res    TEXT;
    v_obs    TEXT;
    v_upd    INT := 0;
    v_del    INT := 0;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN
        RAISE EXCEPTION 'Sin permiso ENEX' USING ERRCODE = '42501';
    END IF;

    SELECT id, pauta_id, firma_mandante_url INTO v_e
      FROM enex_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Servicio no encontrado'; END IF;
    IF v_e.firma_mandante_url IS NOT NULL THEN
        RAISE EXCEPTION 'El informe ya fue firmado por ESM: no se puede cambiar lo que firmó';
    END IF;

    -- Encabezado
    UPDATE enex_ejecuciones
       SET fecha_ejecucion = COALESCE(p_fecha, fecha_ejecucion),
           ot_numero       = NULLIF(btrim(COALESCE(p_ot_numero, '')), ''),
           ejecutor        = COALESCE(NULLIF(btrim(COALESCE(p_ejecutor, '')), ''), ejecutor),
           observacion     = NULLIF(btrim(COALESCE(p_observacion, '')), ''),
           evidencia_urls  = COALESCE(p_evidencia_urls, evidencia_urls),
           informe_pdf_url = NULL,
           updated_at      = now()
     WHERE id = p_ejecucion_id;

    -- Actividades
    FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
        SELECT * INTO v_item FROM enex_pauta_items WHERE id = (it->>'pauta_item_id')::UUID;
        IF v_item.id IS NULL THEN CONTINUE; END IF;

        v_res   := NULLIF(btrim(COALESCE(it->>'resultado', '')), '');
        v_obs   := NULLIF(btrim(COALESCE(it->>'observacion', '')), '');
        v_valor := NULLIF(btrim(COALESCE(it->>'valor_medicion', '')), '')::NUMERIC;
        v_fa    := COALESCE(it->'fotos_antes', '[]'::jsonb);
        v_fd    := COALESCE(it->'fotos_despues', '[]'::jsonb);
        IF jsonb_typeof(v_fa) <> 'array' THEN v_fa := '[]'::jsonb; END IF;
        IF jsonb_typeof(v_fd) <> 'array' THEN v_fd := '[]'::jsonb; END IF;

        -- Vacía: sale del informe.
        IF v_res IS NULL AND v_obs IS NULL AND v_valor IS NULL
           AND v_fa = '[]'::jsonb AND v_fd = '[]'::jsonb THEN
            DELETE FROM enex_ejecucion_items
             WHERE ejecucion_id = p_ejecucion_id AND pauta_item_id = v_item.id;
            IF FOUND THEN v_del := v_del + 1; END IF;
            CONTINUE;
        END IF;

        v_dentro := NULL;
        IF v_item.tipo_campo = 'medicion' AND v_valor IS NOT NULL
           AND (v_item.tolerancia_min IS NOT NULL OR v_item.tolerancia_max IS NOT NULL) THEN
            v_dentro := (v_item.tolerancia_min IS NULL OR v_valor >= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_min)
                    AND (v_item.tolerancia_max IS NULL OR v_valor <= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_max);
        END IF;

        INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, valor_medicion,
            dentro_tolerancia, foto_url, foto_antes_url, foto_despues_url, observacion,
            fotos_antes, fotos_despues)
        VALUES (p_ejecucion_id, v_item.id, v_res, v_valor, v_dentro, NULL,
            v_fa->>0, v_fd->>0, v_obs, v_fa, v_fd)
        ON CONFLICT (ejecucion_id, pauta_item_id) DO UPDATE SET
            resultado         = EXCLUDED.resultado,
            valor_medicion    = EXCLUDED.valor_medicion,
            dentro_tolerancia = EXCLUDED.dentro_tolerancia,
            -- foto_url (formato viejo, una foto suelta) se conserva salvo que
            -- se hayan sacado todas las fotos de la actividad.
            foto_url          = CASE WHEN EXCLUDED.fotos_antes = '[]'::jsonb
                                      AND EXCLUDED.fotos_despues = '[]'::jsonb
                                     THEN NULL ELSE enex_ejecucion_items.foto_url END,
            foto_antes_url    = EXCLUDED.foto_antes_url,
            foto_despues_url  = EXCLUDED.foto_despues_url,
            observacion       = EXCLUDED.observacion,
            fotos_antes       = EXCLUDED.fotos_antes,
            fotos_despues     = EXCLUDED.fotos_despues;
        v_upd := v_upd + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', p_ejecucion_id,
                              'actividades', v_upd, 'borradas', v_del);
END $function$;

REVOKE ALL ON FUNCTION public.rpc_enex_informe_guardar(UUID, DATE, TEXT, TEXT, TEXT, TEXT[], JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_informe_guardar(UUID, DATE, TEXT, TEXT, TEXT, TEXT[], JSONB) TO authenticated;

COMMIT;
