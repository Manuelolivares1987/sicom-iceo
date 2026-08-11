-- ============================================================================
-- SICOM-ICEO | 276 — Firma del mandante a distancia (link con token)
-- ============================================================================
-- Hasta ahora la firma del mandante solo se podía dar en la pantalla de
-- terreno, con el teléfono del técnico en la mano. Si el supervisor de ENEX no
-- estaba ese día, el servicio quedaba sin firmar y sin contar para el KPI —
-- pasó con el trabajo del 10-08 en Lomas 2.
--
-- Ahora el planificador genera un link con token y se lo manda al supervisor
-- (WhatsApp/correo). El link abre una página pública con el servicio, la pauta
-- y las fotos del antes y después; el supervisor escribe su nombre y firma con
-- el dedo. Al firmar, el servicio pasa a CUMPLIDA.
--
-- La firma se guarda como data URL en la propia columna: el bucket de Storage
-- exige sesión y quien firma no la tiene. Es una imagen chica y ya viaja así
-- por el resto del sistema.
--
-- De paso: reeditar un servicio YA FIRMADO lo dejaba con estado 'ejecutada'
-- ("Falta firma" en pantalla) aunque la firma seguía guardada. El KPI cuenta
-- por la firma y nunca se vio afectado, pero en pantalla confundía.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_ejecuciones') THEN
        RAISE EXCEPTION 'STOP — falta MIG206/208'; END IF;
END $$;


-- ── 1. Tokens de firma ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_firma_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id UUID NOT NULL REFERENCES enex_ejecuciones(id) ON DELETE CASCADE,
    token        TEXT NOT NULL UNIQUE,
    activo       BOOLEAN NOT NULL DEFAULT TRUE,
    expira_at    TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '30 days',
    firmado_at   TIMESTAMPTZ,
    usos         INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by   UUID REFERENCES usuarios_perfil(id)
);

CREATE INDEX IF NOT EXISTS ix_enex_firma_tokens_ejec ON enex_firma_tokens (ejecucion_id);

COMMENT ON TABLE enex_firma_tokens IS
    'Links de firma remota del mandante. Token aleatorio, revocable y con vencimiento. MIG276.';

ALTER TABLE enex_firma_tokens ENABLE ROW LEVEL SECURITY;

-- Solo la gente del sistema ve y administra los tokens. Quien firma nunca lee
-- esta tabla: entra por los RPC de abajo, que reciben el token y nada más.
DROP POLICY IF EXISTS pol_enex_firma_tokens_sel ON enex_firma_tokens;
CREATE POLICY pol_enex_firma_tokens_sel ON enex_firma_tokens FOR SELECT
    USING (fn_user_rol() IS NOT NULL);
DROP POLICY IF EXISTS pol_enex_firma_tokens_wr ON enex_firma_tokens;
CREATE POLICY pol_enex_firma_tokens_wr ON enex_firma_tokens FOR ALL
    USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());

GRANT SELECT ON enex_firma_tokens TO authenticated;


-- ── 2. Crear / reusar el link de firma ──────────────────────────────────────
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
        v_token := encode(gen_random_bytes(24), 'hex');
        INSERT INTO enex_firma_tokens (ejecucion_id, token, created_by)
        VALUES (p_ejecucion_id, v_token, auth.uid())
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'token', v_token, 'token_id', v_id);
END $$;


-- ── 3. Lo que ve quien va a firmar ──────────────────────────────────────────
-- Recibe SOLO el token. Devuelve lo justo para reconocer el trabajo y firmarlo:
-- nada de ids internos, ni otras faenas, ni datos de contrato.
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
        'ya_firmado', e.firma_mandante_url IS NOT NULL,
        'firmante', e.firmante_mandante_nombre,
        'firmado_at', e.firmante_mandante_at,
        'fecha', e.fecha_ejecucion,
        'ot_numero', e.ot_numero,
        'observacion', e.observacion,
        'tecnico', COALESCE(e.tecnico_nombre, e.ejecutor),
        'firma_tecnico_url', e.firma_tecnico_url,
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


-- ── 4. Registrar la firma ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_firma_registrar(
    p_token TEXT, p_nombre TEXT, p_firma TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tok RECORD; v_nombre TEXT;
BEGIN
    v_nombre := NULLIF(TRIM(COALESCE(p_nombre, '')), '');
    IF v_nombre IS NULL THEN RAISE EXCEPTION 'Falta el nombre de quien firma'; END IF;
    IF p_firma IS NULL OR p_firma NOT LIKE 'data:image/%' THEN
        RAISE EXCEPTION 'Falta la firma'; END IF;
    -- Una firma de pad ronda las decenas de KB: más que esto es basura o abuso.
    IF length(p_firma) > 900000 THEN RAISE EXCEPTION 'La firma es demasiado grande'; END IF;

    SELECT * INTO v_tok FROM enex_firma_tokens WHERE token = p_token;
    IF v_tok IS NULL OR NOT v_tok.activo OR v_tok.expira_at <= now() THEN
        RAISE EXCEPTION 'El link de firma no es válido o ya venció'; END IF;

    UPDATE enex_ejecuciones
       SET firma_mandante_url      = p_firma,
           firmante_mandante_nombre = v_nombre,
           firmante_mandante_at     = now(),
           estado                   = 'cumplida',
           -- El PDF guardado ya no refleja la realidad: se invalida para que
           -- nadie mande a ENEX un informe sin la firma que acaba de darse.
           informe_pdf_url          = NULL
     WHERE id = v_tok.ejecucion_id;

    -- Un link, una firma.
    UPDATE enex_firma_tokens SET firmado_at = now(), activo = FALSE WHERE id = v_tok.id;

    RETURN jsonb_build_object('success', true);
END $$;


CREATE OR REPLACE FUNCTION rpc_enex_firma_revocar(p_ejecucion_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para ENEX'; END IF;
    UPDATE enex_firma_tokens SET activo = FALSE
     WHERE ejecucion_id = p_ejecucion_id AND activo AND firmado_at IS NULL;
    RETURN jsonb_build_object('success', true);
END $$;

-- Quien firma no tiene sesión: los dos RPC del link se exponen a anon. Reciben
-- el token y nada más, y no permiten enumerar (24 bytes aleatorios).
GRANT EXECUTE ON FUNCTION rpc_enex_firma_datos(TEXT)                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_registrar(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_link(UUID)                 TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_revocar(UUID)              TO authenticated;


-- ── 5. Reeditar un servicio firmado ya no lo muestra como "falta firma" ─────
-- rpc_enex_ejecutar_pauta ponía estado='ejecutada' cuando el guardado venía sin
-- firma, aunque la ejecución ya tuviera una guardada. La firma nunca se perdía
-- (y el KPI cuenta por ella), pero el chip de la pantalla mentía.
DO $$
DECLARE v_src TEXT; v_new TEXT;
BEGIN
    SELECT prosrc INTO v_src FROM pg_proc WHERE proname = 'rpc_enex_ejecutar_pauta' LIMIT 1;
    IF v_src IS NULL THEN RAISE NOTICE 'MIG276: no existe rpc_enex_ejecutar_pauta'; RETURN; END IF;
    IF position('MIG276' IN v_src) > 0 THEN RAISE NOTICE 'MIG276: el estado ya estaba corregido'; RETURN; END IF;
    RAISE NOTICE 'MIG276: revisar rpc_enex_ejecutar_pauta — el estado se corrige por trigger';
END $$;

-- Se resuelve con un trigger, que no depende de reescribir la función entera:
-- si la fila ya tiene firma del mandante, el estado no puede bajar de cumplida.
CREATE OR REPLACE FUNCTION fn_enex_estado_respeta_firma()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.firma_mandante_url IS NOT NULL AND NEW.estado IS DISTINCT FROM 'cumplida' THEN
        NEW.estado := 'cumplida';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_enex_estado_respeta_firma ON enex_ejecuciones;
CREATE TRIGGER tg_enex_estado_respeta_firma
    BEFORE INSERT OR UPDATE ON enex_ejecuciones
    FOR EACH ROW EXECUTE FUNCTION fn_enex_estado_respeta_firma();

COMMENT ON FUNCTION fn_enex_estado_respeta_firma() IS
    'Un servicio con firma del mandante no vuelve a "ejecutada" por reeditarlo. MIG276.';


-- ── 6. Validación ───────────────────────────────────────────────────────────
SELECT 'MIG276 OK' AS resultado,
       (SELECT count(*) FROM enex_firma_tokens) AS tokens,
       (SELECT count(*) FROM enex_ejecuciones WHERE firma_mandante_url IS NOT NULL AND estado <> 'cumplida') AS incoherentes;
