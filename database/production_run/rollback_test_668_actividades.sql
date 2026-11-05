-- Prueba de MIG668 contra producción: todo se deshace al final con RAISE.
DO $$
DECLARE
    v_jefe UUID; v_plan UUID; v_mec UUID; v_tec UUID; v_otro_tec UUID; v_cam UUID; v_lav UUID; v_rt UUID; v_j JSONB;
    v_est TEXT; v_ok INT := 0; v_cert UUID; v_t0 TIMESTAMPTZ; v_tok TEXT; v_msg TEXT;
BEGIN
    SELECT id INTO v_jefe FROM usuarios_perfil WHERE rol::text = 'jefe_mantenimiento' LIMIT 1;
    SELECT id INTO v_plan FROM usuarios_perfil WHERE rol::text = 'planificador' LIMIT 1;
    SELECT t.id, t.usuario_perfil_id INTO v_tec, v_mec FROM taller_tecnicos t
      JOIN usuarios_perfil u ON u.id = t.usuario_perfil_id WHERE u.rol::text = 'operador_taller' AND t.activo LIMIT 1;
    SELECT id INTO v_otro_tec FROM taller_tecnicos WHERE activo AND id <> v_tec LIMIT 1;
    SELECT id INTO v_cam FROM activos WHERE patente = 'KCBY-30';

    -- Planificador crea lavado y RT
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plan)::text, true);
    v_lav := rpc_taller_actividad_crear(v_cam, 'lavado', fn_taller_hoy(), fn_taller_hoy(), v_tec);
    v_rt  := rpc_taller_actividad_crear(v_cam, 'revision_tecnica', fn_taller_hoy() + 1, fn_taller_hoy() + 1, v_tec);
    RAISE NOTICE '1 creadas';

    -- Fecha pasada sin motivo: rebota
    BEGIN
        PERFORM rpc_taller_actividad_crear(v_cam, 'tc8_sec', fn_taller_hoy() - 1, fn_taller_hoy(), v_tec);
        RAISE EXCEPTION 'FALLO: aceptó fecha pasada sin motivo';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'FALLO%' THEN RAISE; END IF;
        RAISE NOTICE '2 fecha pasada: %', v_msg;
    END;
    -- Duplicado: rebota
    BEGIN
        PERFORM rpc_taller_actividad_crear(v_cam, 'lavado', fn_taller_hoy(), fn_taller_hoy(), v_tec);
        RAISE EXCEPTION 'FALLO: aceptó duplicado';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'FALLO%' THEN RAISE; END IF;
        RAISE NOTICE '3 duplicado: %', v_msg;
    END;
    -- Mover lo de hoy sin motivo: rebota. Mover lo futuro sin motivo: pasa.
    BEGIN
        PERFORM rpc_taller_actividad_reprogramar(v_lav, fn_taller_hoy() + 2, fn_taller_hoy() + 2);
        RAISE EXCEPTION 'FALLO: movió sin motivo';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'FALLO%' THEN RAISE; END IF;
        RAISE NOTICE '4 sin motivo: %', v_msg;
    END;
    PERFORM rpc_taller_actividad_reprogramar(v_rt, fn_taller_hoy() + 2, fn_taller_hoy() + 2);
    RAISE NOTICE '5 futuro se mueve sin motivo';

    -- Otro técnico no puede subir evidencia
    PERFORM set_config('request.jwt.claims', json_build_object('sub',
        (SELECT usuario_perfil_id FROM taller_tecnicos t JOIN usuarios_perfil u ON u.id=t.usuario_perfil_id
          WHERE t.activo AND t.id <> v_tec AND u.rol::text='operador_taller' LIMIT 1))::text, true);
    BEGIN
        PERFORM rpc_taller_actividad_evidencia_foto(v_lav, '[{"url":"x"}]');
        RAISE EXCEPTION 'FALLO: otro técnico subió evidencia';
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE '6 otro técnico: rechazado';
    END;

    -- Mecánico: ve lo suyo, marca hecha, sube foto → cerrada sin aprobación
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mec)::text, true);
    v_j := rpc_taller_mis_actividades();
    IF jsonb_array_length(v_j) < 2 THEN RAISE EXCEPTION 'FALLO: mis actividades = %', v_j; END IF;
    PERFORM rpc_taller_actividad_marcar_hecha(v_lav);
    v_est := rpc_taller_actividad_evidencia_foto(v_lav, '[{"url":"https://x/y.jpg"}]');
    IF v_est <> 'cerrada' THEN RAISE EXCEPTION 'FALLO: lavado quedó %', v_est; END IF;
    RAISE NOTICE '7 lavado cerrado con foto';

    -- RT: papeles malos rebotan
    BEGIN
        PERFORM rpc_taller_actividad_evidencia_cert(v_rt, 'https://x/rt.pdf', fn_taller_hoy(), fn_taller_hoy());
        RAISE EXCEPTION 'FALLO: aceptó emisión = vencimiento';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'FALLO%' THEN RAISE; END IF;
        RAISE NOTICE '8 emisión = vencimiento: %', v_msg;
    END;
    PERFORM rpc_taller_actividad_evidencia_cert(v_rt, 'https://x/rt.pdf', fn_taller_hoy(), fn_taller_hoy() + 180, 'N1');
    -- El mecánico no aprueba
    BEGIN
        PERFORM rpc_taller_actividad_aprobar(v_rt);
        RAISE EXCEPTION 'FALLO: mecánico aprobó';
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE '9 mecánico no aprueba';
    END;
    -- Jefe rechaza: vuelve a falta evidencia
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, true);
    PERFORM rpc_taller_actividad_rechazar(v_rt, 'Foto ilegible');
    SELECT estado INTO v_est FROM taller_actividades WHERE id = v_rt;
    IF v_est <> 'hecha' THEN RAISE EXCEPTION 'FALLO: tras rechazo quedó %', v_est; END IF;
    -- Mecánico vuelve a subir, jefe aprueba: papel renovado y actividad cerrada
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mec)::text, true);
    PERFORM rpc_taller_actividad_evidencia_cert(v_rt, 'https://x/rt.pdf', fn_taller_hoy(), fn_taller_hoy() + 180, 'N1');
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, true);
    PERFORM rpc_taller_actividad_aprobar(v_rt);
    SELECT estado, certificacion_id INTO v_est, v_cert FROM taller_actividades WHERE id = v_rt;
    IF v_est <> 'cerrada' OR v_cert IS NULL THEN RAISE EXCEPTION 'FALLO: RT quedó % %', v_est, v_cert; END IF;
    IF NOT EXISTS (SELECT 1 FROM v_control_documental WHERE activo_id = v_cam AND tipo::text = 'revision_tecnica'
                    AND estado::text = 'vigente' AND certificacion_id = v_cert) THEN
        RAISE EXCEPTION 'FALLO: Control documental no ve la RT nueva';
    END IF;
    RAISE NOTICE '10 RT aprobada: papel vigente en Control documental';

    -- Papel subido por la ficha cierra la actividad abierta
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plan)::text, true);
    v_rt := rpc_taller_actividad_crear(v_cam, 'analisis_gases', fn_taller_hoy() + 1, fn_taller_hoy() + 1, v_tec);
    PERFORM rpc_renovar_certificacion(p_activo_id => v_cam, p_tipo => 'analisis_gases',
        p_fecha_emision => fn_taller_hoy(), p_fecha_vencimiento => fn_taller_hoy() + 365);
    SELECT estado INTO v_est FROM taller_actividades WHERE id = v_rt;
    IF v_est <> 'cerrada' THEN RAISE EXCEPTION 'FALLO: papel por ficha no cerró: %', v_est; END IF;
    RAISE NOTICE '11 papel por ficha cierra';

    -- Pantalla por token, sin sesión
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, true);
    PERFORM rpc_pantalla_taller_crear('Prueba', 'Coquimbo');
    SELECT token INTO v_tok FROM pantalla_taller_accesos WHERE nombre = 'Prueba';
    PERFORM set_config('request.jwt.claims', '', true);
    v_t0 := clock_timestamp();
    v_j := rpc_pantalla_taller(v_tok);
    RAISE NOTICE '12 pantalla: valido=% camiones=% sin_agendar=% en % ms', v_j->>'valido',
        jsonb_array_length(v_j->'camiones'), v_j->'sin_agendar',
        round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);
    IF NOT (v_j->>'valido')::boolean OR jsonb_array_length(v_j->'camiones') < 1 THEN
        RAISE EXCEPTION 'FALLO: pantalla %', v_j;
    END IF;
    RAISE NOTICE '13 primera fila: %', left((v_j->'camiones'->0)::text, 600);
    IF (rpc_pantalla_taller('malo')->>'valido')::boolean THEN RAISE EXCEPTION 'FALLO: token malo'; END IF;

    RAISE EXCEPTION 'ROLLBACK_OK';
EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg = 'ROLLBACK_OK' THEN RAISE NOTICE 'TODO OK, deshecho.'; ELSE RAISE; END IF;
END $$;
