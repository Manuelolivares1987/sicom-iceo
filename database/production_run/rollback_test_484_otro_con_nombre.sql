-- Prueba con ROLLBACK del «otro» con nombre (MIG484). No deja nada en prod.
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_act UUID; v_pat TEXT;
    v_n INT; v_txt TEXT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id, patente INTO v_act, v_pat FROM activos
     WHERE patente = 'SVBJ-57' LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    -- 1 · «Otro» sin nombre no entra
    BEGIN
        PERFORM rpc_renovar_certificacion(
            v_act, 'otra'::tipo_certificacion_enum, CURRENT_DATE, CURRENT_DATE + 365,
            NULL, NULL, NULL, NULL, NULL, 'manual', NULL);
        RAISE NOTICE '1 FALLA: aceptó un «otro» sin nombre';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '1 OK: %', SQLERRM;
    END;

    -- 2 · Con nombre entra, y se lee por su nombre
    PERFORM rpc_renovar_certificacion(
        v_act, 'otra'::tipo_certificacion_enum, CURRENT_DATE, CURRENT_DATE + 365,
        NULL, 'X-1', 'PRT', FALSE, NULL, 'manual', 'Prueba de estanqueidad de prueba');
    SELECT etiqueta INTO v_txt FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Prueba de estanqueidad de prueba';
    RAISE NOTICE '2 %: se lee «%»',
                 CASE WHEN v_txt = 'Prueba de estanqueidad de prueba' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 3 · Dos «otros» distintos NO se tapan
    SELECT count(*) INTO v_n FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo = 'otra';
    RAISE NOTICE '3 %: el equipo muestra % papeles «otros» distintos',
                 CASE WHEN v_n >= 3 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 4 · El mismo nombre otra vez es una RENOVACIÓN, no un papel nuevo
    PERFORM rpc_renovar_certificacion(
        v_act, 'otra'::tipo_certificacion_enum, CURRENT_DATE, CURRENT_DATE + 730,
        NULL, 'X-2', 'PRT', FALSE, NULL, 'manual', 'Prueba de estanqueidad de prueba');
    SELECT count(*) INTO v_n FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Prueba de estanqueidad de prueba';
    SELECT numero_certificado INTO v_txt FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo_otro = 'Prueba de estanqueidad de prueba';
    RAISE NOTICE '4 %: sigue siendo 1 papel (%), y el vigente es el nuevo (%)',
                 CASE WHEN v_n = 1 AND v_txt = 'X-2' THEN 'OK' ELSE 'FALLA' END, v_n, v_txt;

    -- 5 · El QR del cliente ve lo mismo, y con nombre
    SELECT count(*) INTO v_n FROM rpc_documentos_activo_publico(v_act) WHERE tipo = 'otra';
    SELECT string_agg(etiqueta, ' · ' ORDER BY etiqueta) INTO v_txt
      FROM rpc_documentos_activo_publico(v_act) WHERE tipo = 'otra';
    RAISE NOTICE '5 %: el QR muestra % «otros»: %',
                 CASE WHEN v_n >= 3 THEN 'OK' ELSE 'FALLA' END, v_n, v_txt;

    -- 6 · Un tipo normal no se contamina con el nombre libre
    PERFORM rpc_renovar_certificacion(
        v_act, 'soap'::tipo_certificacion_enum, CURRENT_DATE, CURRENT_DATE + 365,
        NULL, 'S-1', 'PRT', TRUE, NULL, 'manual', 'nombre que no corresponde');
    SELECT tipo_otro INTO v_txt FROM v_certificacion_actual
     WHERE activo_id = v_act AND tipo = 'soap';
    RAISE NOTICE '6 %: el SOAP quedó sin nombre libre (%)',
                 CASE WHEN v_txt IS NULL THEN 'OK' ELSE 'FALLA' END, COALESCE(v_txt, 'NULL');

    -- 7 · Y la lista de nombres ya usados lo ofrece para la próxima
    SELECT count(*) INTO v_n FROM v_certificado_tipos_otros
     WHERE nombre = 'Prueba de estanqueidad de prueba';
    RAISE NOTICE '7 %: el nombre queda disponible como sugerencia (%)',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n;
END $$;

ROLLBACK;
