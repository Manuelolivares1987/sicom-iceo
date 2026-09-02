-- Prueba con ROLLBACK de corregir/anular un papel (MIG486). No deja nada en prod.
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_plan UUID; v_aud UUID;
    v_act UUID; v_c1 UUID; v_c2 UUID;
    v_n INT; v_txt TEXT; v_num TEXT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_aud   FROM usuarios_perfil WHERE rol = 'auditor_calidad' AND activo LIMIT 1;
    SELECT id INTO v_act FROM activos WHERE patente = 'SVBJ-57' LIMIT 1;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    -- Dos versiones del mismo papel: la vieja y la nueva.
    PERFORM rpc_renovar_certificacion(v_act, 'otra'::tipo_certificacion_enum,
        CURRENT_DATE - 400, CURRENT_DATE - 35, NULL, 'VIEJA', 'PRT', FALSE, NULL, 'manual',
        'Papel de prueba MIG486');
    SELECT id INTO v_c1 FROM certificaciones
     WHERE activo_id = v_act AND numero_certificado = 'VIEJA';

    PERFORM rpc_renovar_certificacion(v_act, 'otra'::tipo_certificacion_enum,
        CURRENT_DATE - 10, CURRENT_DATE + 355, NULL, 'NUEVA', 'PRT', FALSE, NULL, 'manual',
        'Papel de prueba MIG486');
    SELECT id INTO v_c2 FROM certificaciones
     WHERE activo_id = v_act AND numero_certificado = 'NUEVA';

    -- 1 · El vigente es el nuevo
    SELECT numero_certificado INTO v_num FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Papel de prueba MIG486';
    RAISE NOTICE '1 %: el vigente es % ', CASE WHEN v_num = 'NUEVA' THEN 'OK' ELSE 'FALLA' END, v_num;

    -- 2 · Corregir la fecha de vencimiento
    PERFORM rpc_certificacion_editar(v_c2, NULL, NULL, NULL, CURRENT_DATE + 10,
                                     NULL, NULL, NULL, NULL, 'Venía mal del PDF');
    SELECT estado::TEXT INTO v_txt FROM certificaciones WHERE id = v_c2;
    RAISE NOTICE '2 %: al acortar el vencimiento queda «%»',
                 CASE WHEN v_txt = 'por_vencer' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 3 · La corrección queda registrada, con el antes
    SELECT count(*) INTO v_n FROM certificacion_ediciones
     WHERE certificacion_id = v_c2 AND accion = 'editar';
    SELECT (antes ->> 'fecha_vencimiento') INTO v_txt FROM certificacion_ediciones
     WHERE certificacion_id = v_c2 AND accion = 'editar' ORDER BY hecho_at DESC LIMIT 1;
    RAISE NOTICE '3 %: % edición registrada, antes vencía %',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n, v_txt;

    -- 4 · Corregir a «otro» sin nombre no se puede
    BEGIN
        PERFORM rpc_certificacion_editar(v_c2, 'otra'::tipo_certificacion_enum, '  ',
                                         NULL, NULL, NULL, NULL, NULL, NULL, 'sin nombre');
        -- conserva el nombre anterior, así que esto NO debe fallar
        RAISE NOTICE '4 OK: conserva el nombre que ya tenía';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '4 (%): %', 'revisar', SQLERRM;
    END;

    -- 5 · Anular necesita motivo
    BEGIN
        PERFORM rpc_certificacion_anular(v_c2, 'x');
        RAISE NOTICE '5 FALLA: anuló sin motivo';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '5 OK: %', SQLERRM;
    END;

    -- 6 · El auditor de calidad puede corregir pero NO anular
    IF v_aud IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_aud)::text, TRUE);
        BEGIN
            PERFORM rpc_certificacion_anular(v_c2, 'no debería poder anular');
            RAISE NOTICE '6 FALLA: el auditor anuló un papel';
        EXCEPTION WHEN OTHERS THEN RAISE NOTICE '6 OK: %', SQLERRM;
        END;
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
    END IF;

    -- 7 · Anulado, el anterior vuelve a ser el vigente
    PERFORM rpc_certificacion_anular(v_c2, 'Se cargó el archivo del camión equivocado');
    SELECT numero_certificado INTO v_num FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Papel de prueba MIG486';
    RAISE NOTICE '7 %: anulado el nuevo, el vigente vuelve a ser %',
                 CASE WHEN v_num = 'VIEJA' THEN 'OK' ELSE 'FALLA' END, COALESCE(v_num,'ninguno');

    -- 8 · El QR del cliente tampoco lo ve
    SELECT count(*) INTO v_n FROM rpc_documentos_activo_publico(v_act)
     WHERE numero_certificado = 'NUEVA';
    RAISE NOTICE '8 %: el QR no muestra el anulado (%)',
                 CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 9 · Un papel anulado no se corrige: primero se restaura
    BEGIN
        PERFORM rpc_certificacion_editar(v_c2, NULL, NULL, NULL, CURRENT_DATE + 90);
        RAISE NOTICE '9 FALLA: corrigió un papel anulado';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '9 OK: %', SQLERRM;
    END;

    -- 10 · Restaurar lo devuelve
    PERFORM rpc_certificacion_restaurar(v_c2);
    SELECT numero_certificado INTO v_num FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Papel de prueba MIG486';
    SELECT count(*) INTO v_n FROM v_certificaciones_anuladas WHERE id = v_c2;
    RAISE NOTICE '10 %: restaurado, vigente % y ya no está en la lista de anulados (%)',
                 CASE WHEN v_num = 'NUEVA' AND v_n = 0 THEN 'OK' ELSE 'FALLA' END,
                 COALESCE(v_num,'ninguno'), v_n;
END $$;

ROLLBACK;
