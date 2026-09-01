-- Prueba con ROLLBACK de la Fase 3 (MIG479). No deja nada en prod.
BEGIN;

DO $$
DECLARE
    v_jefe UUID; v_joel UUID; v_marco UUID;
    v_tec_joel UUID; v_tec_marco UUID;
    v_ot UUID; v_os UUID; v_n INT; v_txt TEXT; v_b TEXT;
BEGIN
    SELECT id INTO v_jefe FROM usuarios_perfil WHERE rol = 'jefe_mantenimiento' AND activo LIMIT 1;
    SELECT usuario_perfil_id, id INTO v_joel, v_tec_joel
      FROM taller_tecnicos WHERE nombre = 'Joel Coo';
    SELECT usuario_perfil_id, id INTO v_marco, v_tec_marco
      FROM taller_tecnicos WHERE nombre = 'Marco Díaz';
    RAISE NOTICE 'joel=% marco=%', v_joel, v_marco;

    SELECT id INTO v_ot FROM ordenes_trabajo
     WHERE estado::TEXT NOT IN ('cerrada','anulada','cancelada')
     ORDER BY created_at DESC LIMIT 1;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, TRUE);
    INSERT INTO taller_os (ot_id, folio, titulo, estado, creada_por)
    VALUES (v_ot, 'OS-TEST-F3', 'Prueba fase 3', 'abierta', v_jefe)
    RETURNING id INTO v_os;

    -- 1 · Sin asignar, la OS no aparece en el teléfono de nadie
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_joel)::text, TRUE);
    SELECT count(*) INTO v_n FROM rpc_taller_mis_os() WHERE folio = 'OS-TEST-F3';
    RAISE NOTICE '1 %: sin asignar no la ve Joel (%)', CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 2 · La sesión resuelve a la persona
    SELECT t.nombre INTO v_txt FROM taller_tecnicos t WHERE t.id = fn_taller_mi_tecnico_id();
    RAISE NOTICE '2 %: la sesión dice «%»', CASE WHEN v_txt = 'Joel Coo' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 3 · El jefe asigna, y recién ahí aparece
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_jefe)::text, TRUE);
    PERFORM rpc_taller_os_asignar(v_os, v_tec_joel, 'Prueba fase 3');
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_joel)::text, TRUE);
    SELECT count(*), max(bloqueo) INTO v_n, v_b FROM rpc_taller_mis_os() WHERE folio = 'OS-TEST-F3';
    RAISE NOTICE '3 %: asignada, Joel la ve (%) · bloqueo: %',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n, COALESCE(v_b, 'ninguno');

    -- 4 · Marco no ve el trabajo de Joel
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_marco)::text, TRUE);
    SELECT count(*) INTO v_n FROM rpc_taller_mis_os() WHERE folio = 'OS-TEST-F3';
    RAISE NOTICE '4 %: Marco no ve lo de Joel (%)', CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 5 · Marco no puede parar el reloj de Joel
    INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
    VALUES (v_os, v_tec_joel, v_joel);
    BEGIN
        PERFORM rpc_taller_os_pausar(v_os, v_tec_joel, NULL);
        RAISE NOTICE '5 FALLA: Marco paró el reloj de Joel';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '5 OK: %', SQLERRM;
    END;

    -- 6 · Marco tampoco cierra la OS de Joel
    BEGIN
        PERFORM rpc_taller_os_finalizar(v_os, 'no debería poder');
        RAISE NOTICE '6 FALLA: Marco cerró la OS de Joel';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '6 OK: %', SQLERRM;
    END;

    -- 7 · Joel sí para el suyo, y las horas que ve son las suyas
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_joel)::text, TRUE);
    PERFORM rpc_taller_os_pausar(v_os, v_tec_joel, 'fin de turno');
    SELECT count(*) INTO v_n FROM taller_os_tiempo WHERE os_id = v_os AND fin IS NULL;
    RAISE NOTICE '7 %: Joel paró su reloj (tramos abiertos: %)',
                 CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 8 · Y puede cerrar la suya
    PERFORM rpc_taller_os_finalizar(v_os, 'listo');
    SELECT estado INTO v_txt FROM taller_os WHERE id = v_os;
    RAISE NOTICE '8 %: la OS queda %', CASE WHEN v_txt = 'finalizada' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 9 · Terminada, sale del teléfono
    SELECT count(*) INTO v_n FROM rpc_taller_mis_os() WHERE folio = 'OS-TEST-F3';
    RAISE NOTICE '9 %: terminada ya no aparece (%)', CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;
END $$;

ROLLBACK;
