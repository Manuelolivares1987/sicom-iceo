-- ============================================================================
-- SICOM-ICEO | 277 — El link de firma distingue técnico ejecutor y ESM/ENEX
-- ============================================================================
-- El informe lleva DOS firmas: la del técnico ejecutor (Pillado, "verificación
-- realizada por") y la del mandante (ESM/ENEX, "revisado por"). La MIG276 solo
-- resolvió la del mandante, así que el técnico seguía teniendo que firmar en el
-- teléfono el mismo día.
--
-- Ahora el token lleva a quién corresponde y se generan los dos links por
-- separado. Reglas:
--   · la firma del técnico NO cierra el servicio — es el respaldo de quién hizo
--     el trabajo;
--   · la del mandante sí: con ella el servicio pasa a cumplida y cuenta para el
--     KPI del contrato;
--   · cualquiera de las dos invalida el PDF guardado, que queda desactualizado.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE enex_firma_tokens
    ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'mandante';

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enex_firma_tokens_tipo_check') THEN
        ALTER TABLE enex_firma_tokens
            ADD CONSTRAINT enex_firma_tokens_tipo_check CHECK (tipo IN ('tecnico','mandante'));
    END IF;
END $$;

COMMENT ON COLUMN enex_firma_tokens.tipo IS
    'A quién corresponde el link: tecnico (Pillado) o mandante (ESM/ENEX). MIG277.';


-- ── Link por tipo de firma ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_firma_link(p_ejecucion_id UUID, p_tipo TEXT DEFAULT 'mandante')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_token TEXT; v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para ENEX'; END IF;
    IF p_tipo NOT IN ('tecnico','mandante') THEN RAISE EXCEPTION 'Tipo de firma inválido'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_ejecuciones WHERE id = p_ejecucion_id) THEN
        RAISE EXCEPTION 'Ejecución no encontrada'; END IF;

    -- Un link vivo por servicio y tipo: dos links del mismo dando vueltas por
    -- WhatsApp es pedir confusión.
    SELECT id, token INTO v_id, v_token FROM enex_firma_tokens
     WHERE ejecucion_id = p_ejecucion_id AND tipo = p_tipo
       AND activo AND expira_at > now() AND firmado_at IS NULL
     ORDER BY created_at DESC LIMIT 1;

    IF v_token IS NULL THEN
        v_token := replace(gen_random_uuid()::text, '-', '')
                || replace(gen_random_uuid()::text, '-', '');
        INSERT INTO enex_firma_tokens (ejecucion_id, token, tipo, created_by)
        VALUES (p_ejecucion_id, v_token, p_tipo, auth.uid())
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'token', v_token, 'token_id', v_id, 'tipo', p_tipo);
END $$;


-- ── Lo que ve quien va a firmar (ahora sabe cuál de las dos firmas da) ──────
CREATE OR REPLACE FUNCTION rpc_enex_firma_datos(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ejec UUID; v_tok RECORD; v_out JSONB;
BEGIN
    SELECT * INTO v_tok FROM enex_firma_tokens WHERE token = p_token;
    IF v_tok IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'no_existe'); END IF;
    IF NOT v_tok.activo THEN RETURN jsonb_build_object('ok', false, 'motivo', 'revocado'); END IF;
    IF v_tok.expira_at <= now() THEN RETURN jsonb_build_object('ok', false, 'motivo', 'vencido'); END IF;
    v_ejec := v_tok.ejecucion_id;

    SELECT jsonb_build_object(
        'ok', true,
        'tipo', v_tok.tipo,
        -- "ya firmado" es el de ESTE link, no el del otro firmante.
        'ya_firmado', CASE WHEN v_tok.tipo = 'tecnico'
                           THEN e.firma_tecnico_url IS NOT NULL
                           ELSE e.firma_mandante_url IS NOT NULL END,
        'firmante', CASE WHEN v_tok.tipo = 'tecnico'
                         THEN e.tecnico_nombre ELSE e.firmante_mandante_nombre END,
        'firmado_at', CASE WHEN v_tok.tipo = 'tecnico' THEN NULL ELSE e.firmante_mandante_at END,
        -- Estado de la otra firma, para que se vea si falta la contraparte.
        'firma_tecnico_lista',  e.firma_tecnico_url IS NOT NULL,
        'firma_mandante_lista', e.firma_mandante_url IS NOT NULL,
        'tecnico_nombre',  e.tecnico_nombre,
        'mandante_nombre', e.firmante_mandante_nombre,
        'fecha', e.fecha_ejecucion,
        'ot_numero', e.ot_numero,
        'observacion', e.observacion,
        'tecnico', COALESCE(e.tecnico_nombre, e.ejecutor),
        'instalacion', i.nombre,
        'faena', f.nombre,
        'tipo_servicio', p.tipo_servicio,
        'pauta', pa.nombre,
        'evidencia_urls', e.evidencia_urls,
        'actividades', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'codigo', pi.codigo, 'descripcion', pi.descripcion, 'bloque', pi.bloque,
                       'resultado', ei.resultado, 'valor', ei.valor_medicion, 'unidad', pi.unidad,
                       'observacion', ei.observacion,
                       'fotos_antes', ei.fotos_antes, 'fotos_despues', ei.fotos_despues)
                     ORDER BY pi.bloque_orden, pi.orden)
              FROM enex_ejecucion_items ei
              JOIN enex_pauta_items pi ON pi.id = ei.pauta_item_id
             WHERE ei.ejecucion_id = e.id
               AND pi.bloque NOT LIKE '0.%'), '[]'::jsonb),
        'datos_servicio', COALESCE((
            SELECT jsonb_object_agg(pi.codigo, ei.observacion)
              FROM enex_ejecucion_items ei
              JOIN enex_pauta_items pi ON pi.id = ei.pauta_item_id
             WHERE ei.ejecucion_id = e.id AND pi.codigo LIKE 'DS.%'
               AND ei.observacion IS NOT NULL), '{}'::jsonb)
    ) INTO v_out
      FROM enex_ejecuciones e
      JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
      JOIN enex_faenas f ON f.id = i.faena_id
      LEFT JOIN enex_pautas pa ON pa.id = e.pauta_id
     WHERE e.id = v_ejec;

    UPDATE enex_firma_tokens SET usos = usos + 1 WHERE id = v_tok.id;
    RETURN v_out;
END $$;


-- ── Registrar la firma que corresponda ──────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_firma_registrar(
    p_token TEXT, p_nombre TEXT, p_firma TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tok RECORD; v_nombre TEXT;
BEGIN
    v_nombre := NULLIF(TRIM(COALESCE(p_nombre, '')), '');
    IF v_nombre IS NULL THEN RAISE EXCEPTION 'Falta el nombre de quien firma'; END IF;
    IF p_firma IS NULL OR p_firma NOT LIKE 'data:image/%' THEN
        RAISE EXCEPTION 'Falta la firma'; END IF;
    IF length(p_firma) > 900000 THEN RAISE EXCEPTION 'La firma es demasiado grande'; END IF;

    SELECT * INTO v_tok FROM enex_firma_tokens WHERE token = p_token;
    IF v_tok IS NULL OR NOT v_tok.activo OR v_tok.expira_at <= now() THEN
        RAISE EXCEPTION 'El link de firma no es válido o ya venció'; END IF;

    IF v_tok.tipo = 'tecnico' THEN
        -- La firma del ejecutor respalda quién hizo el trabajo; no cierra el
        -- servicio: eso lo decide el mandante al recibirlo conforme.
        UPDATE enex_ejecuciones
           SET firma_tecnico_url = p_firma,
               tecnico_nombre    = v_nombre,
               informe_pdf_url   = NULL
         WHERE id = v_tok.ejecucion_id;
    ELSE
        UPDATE enex_ejecuciones
           SET firma_mandante_url       = p_firma,
               firmante_mandante_nombre = v_nombre,
               firmante_mandante_at     = now(),
               estado                   = 'cumplida',
               informe_pdf_url          = NULL
         WHERE id = v_tok.ejecucion_id;
    END IF;

    UPDATE enex_firma_tokens SET firmado_at = now(), activo = FALSE WHERE id = v_tok.id;

    RETURN jsonb_build_object('success', true, 'tipo', v_tok.tipo);
END $$;


CREATE OR REPLACE FUNCTION rpc_enex_firma_revocar(p_ejecucion_id UUID, p_tipo TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para ENEX'; END IF;
    UPDATE enex_firma_tokens SET activo = FALSE
     WHERE ejecucion_id = p_ejecucion_id AND activo AND firmado_at IS NULL
       AND (p_tipo IS NULL OR tipo = p_tipo);
    RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION rpc_enex_firma_link(UUID, TEXT)             TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_datos(TEXT)                  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_registrar(TEXT, TEXT, TEXT)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_revocar(UUID, TEXT)          TO authenticated;

-- La versión de un solo argumento queda fuera para que nadie la llame por error.
DROP FUNCTION IF EXISTS rpc_enex_firma_link(UUID);
DROP FUNCTION IF EXISTS rpc_enex_firma_revocar(UUID);

SELECT 'MIG277 OK' AS resultado,
       (SELECT count(*) FROM enex_firma_tokens WHERE tipo = 'mandante') AS tokens_mandante,
       (SELECT count(*) FROM enex_firma_tokens WHERE tipo = 'tecnico')  AS tokens_tecnico;
