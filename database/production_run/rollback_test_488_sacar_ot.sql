-- Prueba con ROLLBACK de sacar la OT entera del plan (MIG488). No deja nada.
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_plan UUID; v_op UUID;
    v_ot UUID := 'fcc5732f-6fd3-49b1-940b-989eb895cbdd';  -- OT-202608-00015
    v_r JSONB; v_n INT; v_est TEXT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_plan  FROM usuarios_perfil WHERE rol = 'planificador'  AND activo LIMIT 1;
    SELECT id INTO v_op    FROM usuarios_perfil WHERE rol = 'operador_taller' AND activo LIMIT 1;

    -- 1 · Un operador de taller no saca OT del plan
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_op)::text, TRUE);
    BEGIN
        PERFORM rpc_taller_sacar_ot_del_plan(v_ot, FALSE, NULL);
        RAISE NOTICE '1 FALLA: el operador sacó la OT del plan';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '1 OK: %', SQLERRM;
    END;

    -- 2 · Estado de partida
    SELECT count(*) INTO v_n FROM taller_plan_semanal_ots WHERE ot_id = v_ot;
    RAISE NOTICE '2 la OT entra con % jornadas en el plan', v_n;

    -- 3 · El planificador no puede FORZAR sobre material ya despachado
    IF v_plan IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plan)::text, TRUE);
        v_r := rpc_taller_sacar_ot_del_plan(v_ot, TRUE, 'Prueba: se rehace', TRUE);
        SELECT estado::TEXT INTO v_est FROM ordenes_trabajo WHERE id = v_ot;
        RAISE NOTICE '3 %: el planificador saca las jornadas pero NO descarta (%) · «%»',
                     CASE WHEN v_est <> 'cancelada' THEN 'OK' ELSE 'FALLA' END, v_est,
                     v_r ->> 'no_se_pudo_descartar';
    END IF;

    -- 4 · Las jornadas sí se fueron, todas de una vez
    SELECT count(*) INTO v_n FROM taller_plan_semanal_ots WHERE ot_id = v_ot;
    RAISE NOTICE '4 %: jornadas que quedan: %', CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 5 · Sin motivo, gerencia tampoco fuerza
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
    v_r := rpc_taller_sacar_ot_del_plan(v_ot, TRUE, 'x', TRUE);
    RAISE NOTICE '5 %: sin motivo dice «%»',
                 CASE WHEN v_r ->> 'no_se_pudo_descartar' IS NOT NULL THEN 'OK' ELSE 'FALLA' END,
                 v_r ->> 'no_se_pudo_descartar';

    -- 6 · Con motivo, gerencia sí
    v_r := rpc_taller_sacar_ot_del_plan(v_ot, TRUE, 'Era una prueba, se rehace', TRUE);
    SELECT estado::TEXT INTO v_est FROM ordenes_trabajo WHERE id = v_ot;
    RAISE NOTICE '6 %: la OT queda «%»', CASE WHEN v_est = 'cancelada' THEN 'OK' ELSE 'FALLA' END, v_est;

    -- 7 · Tampoco está en el backlog del taller
    SELECT count(*) INTO v_n FROM v_taller_ot_backlog WHERE ot_id = v_ot;
    RAISE NOTICE '7 %: en «viene de semanas anteriores»: %',
                 CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 8 · La ejecución se cancela con su tiempo, no se borra
    SELECT count(*) INTO v_n FROM taller_ot_ejecuciones
     WHERE ot_id = v_ot AND estado = 'cancelada' AND tiempo_efectivo_segundos > 0;
    RAISE NOTICE '8 %: ejecuciones canceladas con tiempo escrito: %',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 9 · Las no conformidades siguen ahí
    SELECT count(*) INTO v_n FROM no_conformidades
     WHERE ot_id = v_ot AND COALESCE(resuelto, FALSE) = FALSE;
    RAISE NOTICE '9 %: NC abiertas que sobreviven al descarte: %',
                 CASE WHEN v_n = 2 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 10 · Y el movimiento de bodega tampoco se toca
    SELECT count(*) INTO v_n FROM movimientos_inventario WHERE ot_id = v_ot;
    RAISE NOTICE '10 %: movimientos de bodega intactos: %',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 11 · Repetir no revienta
    v_r := rpc_taller_sacar_ot_del_plan(v_ot, TRUE, 'otra vez', TRUE);
    RAISE NOTICE '11 %: segunda vez dice «%»',
                 CASE WHEN v_r ->> 'no_se_pudo_descartar' IS NOT NULL THEN 'OK' ELSE 'FALLA' END,
                 v_r ->> 'no_se_pudo_descartar';
END $$;

ROLLBACK;
