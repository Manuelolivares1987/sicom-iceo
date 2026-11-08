-- 671 — El certificado solo lo bloquean las NC que el taller puede ver (Manuel 08-11-2026).
-- destructivo-ok: el DROP FUNCTION saca la sobrecarga vieja de 10 argumentos de
-- rpc_emitir_certificado_activo, que nadie llama (el front usa la de 13).
--
-- El problema: RSCY-85 decía «13 No Conformidades abiertas» y la bandeja de NC no
-- mostraba ninguna. Las 13 estaban guardadas en el historial (MIG405): 12 del lote
-- «Prueba de agosto 2026» y 1 más. Archivar las saca de las pantallas operativas, pero
-- el gate del certificado contaba `resuelto = false` sin mirar `archivado_at`: el jefe
-- quedaba bloqueado por NC que no tenía cómo encontrar ni cerrar. Pasaba en 12 equipos
-- (111 NC).
--
-- Regla nueva: bloquean las NC abiertas y NO archivadas — exactamente las que salen en
-- la bandeja. Si un lote archivado resulta tener NC reales, «deshacer» el lote las
-- devuelve a la bandeja y vuelven a bloquear: no se pierde nada.
--
-- De paso: la RPC devolvía 'id' y el front leía 'certificado_id', así que tras emitir
-- se abría /certificado/undefined. Ahora devuelve las dos claves.

DROP FUNCTION IF EXISTS public.rpc_emitir_certificado_activo(uuid,text,jsonb,text,text,text,uuid,date,text,uuid);

CREATE OR REPLACE FUNCTION public.rpc_emitir_certificado_activo(p_activo_id uuid, p_tipo_codigo text, p_datos jsonb, p_operador_nombre text, p_firma_operador_url text, p_firma_jefe_url text, p_operador_tecnico_id uuid DEFAULT NULL::uuid, p_fecha_emision date DEFAULT NULL::date, p_ciudad text DEFAULT NULL::text, p_ot_id uuid DEFAULT NULL::uuid, p_vence_el date DEFAULT NULL::date, p_horometro_emision numeric DEFAULT NULL::numeric, p_vigencia_horas numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_jefe TEXT; v_nc INT; v_numero INT; v_id UUID; v_fecha DATE;
    v_horo NUMERIC; v_lista TEXT;
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

    -- GATE [MIG671]: bloquean las NC abiertas que están en la bandeja (no archivadas),
    -- y el mensaje dice CUÁLES, no solo cuántas.
    SELECT COUNT(*),
           string_agg(left(descripcion, 60), ' · ' ORDER BY created_at) FILTER (WHERE rn <= 3)
      INTO v_nc, v_lista
      FROM (SELECT descripcion, created_at, row_number() OVER (ORDER BY created_at) rn
              FROM no_conformidades
             WHERE activo_id = p_activo_id AND COALESCE(resuelto, false) = false
               AND archivado_at IS NULL) s;
    IF v_nc > 0 THEN
        RAISE EXCEPTION 'El equipo tiene % No Conformidad(es) abiertas: % — ciérralas en la bandeja de NC antes de emitir.',
            v_nc, v_lista || CASE WHEN v_nc > 3 THEN ' (y ' || (v_nc - 3) || ' más)' ELSE '' END;
    END IF;

    v_fecha := COALESCE(p_fecha_emision, CURRENT_DATE);
    IF p_vence_el IS NOT NULL AND p_vence_el < v_fecha THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    -- [MIG514] Vigencia por horas: el horómetro de emisión es obligatorio
    -- (si no viene, se toma el del maestro — y si tampoco está, se exige).
    IF p_vigencia_horas IS NOT NULL THEN
        IF p_vigencia_horas <= 0 THEN
            RAISE EXCEPTION 'La vigencia en horas tiene que ser mayor que cero.';
        END IF;
        v_horo := COALESCE(p_horometro_emision,
                           (SELECT a.horas_uso_actual FROM activos a WHERE a.id = p_activo_id));
        IF v_horo IS NULL THEN
            RAISE EXCEPTION 'Anota el horómetro del equipo: la vigencia por horas se cuenta desde ahí.';
        END IF;
    END IF;

    SELECT nombre_completo INTO v_jefe FROM usuarios_perfil WHERE id = v_user;

    PERFORM pg_advisory_xact_lock(hashtext('cert_activo_' || p_activo_id::text));
    SELECT COALESCE(max(numero), 0) + 1 INTO v_numero
      FROM activo_certificados WHERE activo_id = p_activo_id;

    INSERT INTO activo_certificados (
        activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
        operador_tecnico_id, operador_nombre, firma_operador_url,
        jefe_nombre, firma_jefe_url, ot_id, vence_el,
        horometro_emision, vigencia_horas, created_by)
    VALUES (
        p_activo_id, p_tipo_codigo, v_numero, v_fecha,
        COALESCE(NULLIF(TRIM(p_ciudad),''), 'Coquimbo'), COALESCE(p_datos, '{}'::jsonb),
        p_operador_tecnico_id, TRIM(p_operador_nombre), p_firma_operador_url,
        COALESCE(v_jefe, '—'), p_firma_jefe_url, p_ot_id, p_vence_el,
        v_horo, p_vigencia_horas, v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'certificado_id', v_id, 'numero', v_numero,
        'horometro_vence', CASE WHEN p_vigencia_horas IS NOT NULL THEN v_horo + p_vigencia_horas END);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_emitir_certificado_activo(uuid,text,jsonb,text,text,text,uuid,date,text,uuid,date,numeric,numeric) TO authenticated;

NOTIFY pgrst, 'reload schema';
