-- ============================================================================
-- SICOM-ICEO | 276b — El token de firma no depende de pgcrypto
-- ============================================================================
-- `gen_random_bytes` vive en el esquema `extensions` en Supabase y el RPC corre
-- con search_path = public, así que fallaba al crear el link. Se arma el token
-- con dos UUID v4 concatenados: 64 caracteres hex y ~244 bits de aleatoriedad,
-- de sobra para que no se pueda adivinar, sin depender de extensiones.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_enex_firma_link(p_ejecucion_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_token TEXT; v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para ENEX'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_ejecuciones WHERE id = p_ejecucion_id) THEN
        RAISE EXCEPTION 'Ejecución no encontrada'; END IF;

    -- Si ya hay un link vivo para este servicio, se reusa: dos links distintos
    -- circulando por WhatsApp es pedir confusión.
    SELECT id, token INTO v_id, v_token FROM enex_firma_tokens
     WHERE ejecucion_id = p_ejecucion_id AND activo AND expira_at > now() AND firmado_at IS NULL
     ORDER BY created_at DESC LIMIT 1;

    IF v_token IS NULL THEN
        v_token := replace(gen_random_uuid()::text, '-', '')
                || replace(gen_random_uuid()::text, '-', '');
        INSERT INTO enex_firma_tokens (ejecucion_id, token, created_by)
        VALUES (p_ejecucion_id, v_token, auth.uid())
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'token', v_token, 'token_id', v_id);
END $$;

GRANT EXECUTE ON FUNCTION rpc_enex_firma_link(UUID) TO authenticated;

SELECT 'MIG276b OK' AS resultado;
