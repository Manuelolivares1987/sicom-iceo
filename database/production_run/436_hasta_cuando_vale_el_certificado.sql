-- ============================================================================
-- MIG436 · Preguntar hasta cuándo vale, en vez de decir que no vence
-- ----------------------------------------------------------------------------
-- MIG435 hizo que emitir un certificado renueve el papel del equipo. Al
-- probarlo sobre el DJKL-18 salió esto:
--
--   ANTES   aire acondicionado: vencido hasta 08-08-2023
--   DESPUÉS aire acondicionado: no_aplica — el QR dice «permanente»
--
-- El papel pasó de vencido a permanente. Al cliente que escanea el camión se le
-- estaría afirmando que un certificado de mantención de aire acondicionado no
-- vence nunca, y no es cierto: vence, sólo que el sistema no sabe cuándo.
--
-- Es la misma falsa tranquilidad que se salió a corregir hace tres días, con
-- otra cara. «No consta» y «no vence» no son lo mismo, y el que mira el QR no
-- tiene cómo distinguirlos.
--
-- ── LO QUE SE HACE ─────────────────────────────────────────────────────────
-- Se le pregunta a quien emite. Es una sola fecha y la sabe: acaba de hacer el
-- trabajo. Queda en `vence_el`.
--
-- Y si no la pone, el papel queda como FALTA LA FECHA —un pendiente visible en
-- Control documental— en vez de «permanente». Un pendiente se resuelve; una
-- afirmación falsa no, porque nadie la cuestiona.
--
-- El orden es: lo que escribió quien emitió · lo que dure según el estándar ·
-- falta la fecha.
-- ============================================================================

BEGIN;

ALTER TABLE public.activo_certificados
  ADD COLUMN IF NOT EXISTS vence_el DATE;

COMMENT ON COLUMN public.activo_certificados.vence_el IS
  'MIG436: hasta cuándo vale este certificado, según quien lo emitió. Si va NULL el papel queda como «falta la fecha», nunca como «no vence».';

CREATE OR REPLACE FUNCTION public.fn_certificado_activo_renueva_papel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_papel TEXT; v_meses INT; v_vence DATE; v_origen TEXT; v_nota TEXT;
BEGIN
    SELECT tipo_papel INTO v_papel
      FROM certificado_tipo_equivale WHERE tipo_codigo = NEW.tipo_codigo;
    IF v_papel IS NULL THEN RETURN NEW; END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_papel;

    IF NEW.vence_el IS NOT NULL THEN
        -- Lo dijo quien emitió el certificado: manda.
        v_vence  := NEW.vence_el;
        v_origen := 'manual';
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || ': vigencia indicada por quien lo emitió, hasta '
                 || to_char(NEW.vence_el,'DD-MM-YYYY') || '.';
    ELSIF v_meses IS NOT NULL THEN
        v_vence  := (NEW.fecha_emision + (v_meses || ' months')::INTERVAL)::date;
        v_origen := 'documento';
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || ': vence ' || to_char(v_vence,'DD-MM-YYYY')
                 || ', ' || v_meses || ' meses desde la emisión.';
    ELSE
        -- No consta. Queda pendiente y visible, NO «permanente»: decirle al
        -- cliente que un certificado de mantención no vence nunca es falso.
        v_vence  := '2099-12-31'::date;
        v_origen := NULL;
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || '. Falta indicar hasta cuándo vale: nadie lo declaró al emitirlo '
                 || 'y no consta cuánto dura este certificado.';
    END IF;

    INSERT INTO certificaciones (
        activo_id, tipo, fecha_emision, fecha_vencimiento, numero_certificado,
        entidad_certificadora, bloqueante, archivo_url,
        fecha_origen, fecha_origen_nota, notas, created_by)
    VALUES (
        NEW.activo_id, v_papel::tipo_certificacion_enum, NEW.fecha_emision, v_vence,
        lpad(NEW.numero::text, 2, '0'), 'PILLADO Y COMPAÑÍA LTDA.', FALSE,
        '/certificado/' || NEW.id,
        v_origen, v_nota,
        'Certificado emitido desde SICOM, firmado por ' || COALESCE(NEW.operador_nombre,'—')
          || ' y ' || COALESCE(NEW.jefe_nombre,'—') || '.',
        NEW.created_by);

    RETURN NEW;
END $function$;

-- ── El RPC recibe la fecha ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_emitir_certificado_activo(
    p_activo_id uuid, p_tipo_codigo text, p_datos jsonb,
    p_operador_nombre text, p_firma_operador_url text, p_firma_jefe_url text,
    p_operador_tecnico_id uuid DEFAULT NULL, p_fecha_emision date DEFAULT NULL,
    p_ciudad text DEFAULT NULL, p_ot_id uuid DEFAULT NULL,
    p_vence_el date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_jefe TEXT; v_nc INT; v_numero INT; v_id UUID; v_fecha DATE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Rol % no autorizado para emitir certificados', v_rol;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificado_tipos WHERE codigo = p_tipo_codigo AND activo) THEN
        RAISE EXCEPTION 'Tipo de certificado "%" no existe', p_tipo_codigo;
    END IF;
    IF COALESCE(TRIM(p_operador_nombre),'') = '' THEN
        RAISE EXCEPTION 'Indica el operador que realizó el trabajo';
    END IF;
    IF COALESCE(TRIM(p_firma_operador_url),'') = '' OR COALESCE(TRIM(p_firma_jefe_url),'') = '' THEN
        RAISE EXCEPTION 'El certificado requiere la firma del operador Y la del jefe de taller';
    END IF;

    -- GATE: el equipo debe haber resuelto todas sus No Conformidades.
    SELECT COUNT(*) INTO v_nc FROM no_conformidades
     WHERE activo_id = p_activo_id AND COALESCE(resuelto, false) = false;
    IF v_nc > 0 THEN
        RAISE EXCEPTION 'El equipo tiene % No Conformidad(es) abiertas — deben resolverse todas antes de emitir certificados.', v_nc;
    END IF;

    v_fecha := COALESCE(p_fecha_emision, CURRENT_DATE);
    IF p_vence_el IS NOT NULL AND p_vence_el < v_fecha THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    SELECT nombre_completo INTO v_jefe FROM usuarios_perfil WHERE id = v_user;

    -- Correlativo por equipo, bajo bloqueo.
    PERFORM pg_advisory_xact_lock(hashtext('cert_activo_' || p_activo_id::text));
    SELECT COALESCE(max(numero), 0) + 1 INTO v_numero
      FROM activo_certificados WHERE activo_id = p_activo_id;

    INSERT INTO activo_certificados (
        activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
        operador_tecnico_id, operador_nombre, firma_operador_url,
        jefe_nombre, firma_jefe_url, ot_id, vence_el, created_by)
    VALUES (
        p_activo_id, p_tipo_codigo, v_numero, v_fecha,
        COALESCE(NULLIF(TRIM(p_ciudad),''), 'Coquimbo'), COALESCE(p_datos, '{}'::jsonb),
        p_operador_tecnico_id, TRIM(p_operador_nombre), p_firma_operador_url,
        COALESCE(v_jefe, '—'), p_firma_jefe_url, p_ot_id, p_vence_el, v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'numero', v_numero);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_emitir_certificado_activo(
    uuid, text, jsonb, text, text, text, uuid, date, text, uuid, date) TO authenticated;

DO $r$
DECLARE v_activo UUID; v_id UUID;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE COALESCE(patente,codigo)='DJKL-18';
    INSERT INTO activo_certificados (activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
                                     operador_nombre, firma_operador_url, jefe_nombre, firma_jefe_url,
                                     vence_el, created_by)
    VALUES (v_activo, 'aire_acondicionado', 999, CURRENT_DATE, 'Coquimbo', '{}'::jsonb,
            'prueba', 'x', 'prueba', 'x', (CURRENT_DATE + 180)::date,
            (SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1))
    RETURNING id INTO v_id;
    RAISE NOTICE 'Con fecha indicada -> el papel queda: % hasta %',
      (SELECT estado FROM v_control_documental WHERE activo_id=v_activo AND tipo='aire_acondicionado'),
      (SELECT fecha_vencimiento::date FROM v_control_documental WHERE activo_id=v_activo AND tipo='aire_acondicionado');
    DELETE FROM certificaciones WHERE archivo_url = '/certificado/' || v_id;
    DELETE FROM activo_certificados WHERE id = v_id;

    INSERT INTO activo_certificados (activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
                                     operador_nombre, firma_operador_url, jefe_nombre, firma_jefe_url,
                                     created_by)
    VALUES (v_activo, 'aire_acondicionado', 998, CURRENT_DATE, 'Coquimbo', '{}'::jsonb,
            'prueba', 'x', 'prueba', 'x',
            (SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1))
    RETURNING id INTO v_id;
    RAISE NOTICE 'Sin fecha indicada -> el papel queda: % (el QR dice %)',
      (SELECT estado FROM v_control_documental WHERE activo_id=v_activo AND tipo='aire_acondicionado'),
      (SELECT estado FROM rpc_documentos_activo_publico(v_activo) WHERE tipo='aire_acondicionado');
    DELETE FROM certificaciones WHERE archivo_url = '/certificado/' || v_id;
    DELETE FROM activo_certificados WHERE id = v_id;
END
$r$;

COMMIT;
