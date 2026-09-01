-- Prueba con ROLLBACK del flujo de OS externa (MIG477). No deja nada en prod.
BEGIN;

DO $$
DECLARE
    v_jefe UUID; v_ger UUID; v_jop UUID;
    v_ot UUID; v_os UUID; v_folio TEXT;
    v_err TEXT; v_ok BOOLEAN;
    v_horas NUMERIC; v_horas2 NUMERIC;
BEGIN
    SELECT id INTO v_jefe FROM usuarios_perfil WHERE rol = 'jefe_mantenimiento' AND activo LIMIT 1;
    SELECT id INTO v_ger  FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_jop  FROM usuarios_perfil WHERE rol = 'jefe_operaciones' AND activo LIMIT 1;
    RAISE NOTICE 'jefe=% gerente=% jefe_op=%', v_jefe, v_ger, v_jop;

    SELECT id INTO v_ot FROM ordenes_trabajo
     WHERE estado::TEXT NOT IN ('cerrada','anulada','cancelada')
     ORDER BY created_at DESC LIMIT 1;

    -- Entra el jefe de taller
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, TRUE);

    INSERT INTO taller_os (ot_id, folio, titulo, estado, creada_por)
    VALUES (v_ot, 'OS-TEST-EXT', 'Prueba externa', 'abierta', v_jefe)
    RETURNING id INTO v_os;

    -- 1 · Sin proveedor no se puede mandar afuera
    BEGIN
        PERFORM rpc_taller_os_declarar_externo(v_os, TRUE, NULL, NULL);
        RAISE NOTICE '1 FALLA: aceptó una externa sin proveedor';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '1 OK bloquea sin proveedor: %', SQLERRM;
    END;

    -- 2 · Declarada bien
    PERFORM rpc_taller_os_declarar_externo(v_os, TRUE, 'Rectificados Coquimbo',
            'No tenemos torno para rectificar el disco.');
    SELECT es_externo INTO v_ok FROM taller_os WHERE id = v_os;
    RAISE NOTICE '2 declarada externa: %', v_ok;

    -- 3 · Sin autorizar no arranca
    BEGIN
        PERFORM rpc_taller_os_iniciar(v_os, v_jefe);
        RAISE NOTICE '3 FALLA: arrancó sin autorización de gerencia';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '3 OK no arranca: %', SQLERRM;
    END;

    -- 4 · El jefe de operaciones NO autoriza
    IF v_jop IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jop)::text, TRUE);
        BEGIN
            PERFORM rpc_taller_os_autorizar_externo(v_os);
            RAISE NOTICE '4 FALLA: el jefe de operaciones autorizó';
        EXCEPTION WHEN OTHERS THEN RAISE NOTICE '4 OK jefe_op no autoriza: %', SQLERRM;
        END;
    END IF;

    -- 5 · El gerente sí
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ger)::text, TRUE);
    PERFORM rpc_taller_os_autorizar_externo(v_os);
    SELECT externo_autorizado_at IS NOT NULL INTO v_ok FROM taller_os WHERE id = v_os;
    RAISE NOTICE '5 autorizada por gerencia: %', v_ok;

    -- 6 · Las horas del externo no ocupan el techo del taller
    UPDATE taller_os SET horas_estimadas = 40 WHERE id = v_os;
    SELECT fn_taller_ot_horas_os(v_ot) INTO v_horas;
    UPDATE taller_os SET es_externo = FALSE WHERE id = v_os;
    SELECT fn_taller_ot_horas_os(v_ot) INTO v_horas2;
    RAISE NOTICE '6 horas con externa=% / si fuera del taller=% (deben diferir en 40)',
                 v_horas, v_horas2;

    -- 7 · Redeclarar borra la autorización
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, TRUE);
    PERFORM rpc_taller_os_declarar_externo(v_os, TRUE, 'Otro taller',
            'Cambiamos de proveedor porque el primero no tenía hora.');
    SELECT externo_autorizado_at IS NULL INTO v_ok FROM taller_os WHERE id = v_os;
    RAISE NOTICE '7 al cambiar proveedor se pierde la autorización: %', v_ok;

    -- 8 · La meta del planificador
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ger)::text, TRUE);
    RAISE NOTICE '8 meta optimizado -> %', rpc_taller_ot_set_meta(v_ot, 'optimizado');
    RAISE NOTICE '8 meta normal     -> %', rpc_taller_ot_set_meta(v_ot, 'normal');
END $$;

ROLLBACK;
