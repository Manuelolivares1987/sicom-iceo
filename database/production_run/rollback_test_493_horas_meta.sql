-- Prueba con ROLLBACK: las horas las manda la meta (MIG493). No deja nada.
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_op UUID; v_act UUID; v_contrato UUID; v_faena UUID;
    v_plan_sem UUID; v_dia UUID; v_ot UUID; v_po UUID;
    v_r JSONB; v_h NUMERIC;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_op    FROM usuarios_perfil WHERE rol = 'operador_taller' AND activo LIMIT 1;
    SELECT id, contrato_id, faena_id INTO v_act, v_contrato, v_faena
      FROM activos WHERE contrato_id IS NOT NULL LIMIT 1;

    -- 1 · Las horas de cada meta
    RAISE NOTICE '1 MTN: optimizado % h · normal % h',
                 fn_taller_horas_meta('MTN','optimizado'), fn_taller_horas_meta('MTN','normal');
    RAISE NOTICE '1 MPN: optimizado % h · normal % h',
                 fn_taller_horas_meta('MPN','optimizado'), fn_taller_horas_meta('MPN','normal');

    -- Una OT con una jornada en el plan
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, bono_concepto, fecha_programada, created_by)
    VALUES ('OT-TEST-493', v_act, v_contrato, v_faena, 'correctivo', 'creada',
            'Prueba MIG493', 'MTN', CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;

    SELECT ps.id INTO v_plan_sem FROM taller_planes_semanales ps
     ORDER BY ps.fecha_inicio_semana DESC LIMIT 1;
    SELECT d.id INTO v_dia FROM taller_plan_semanal_dias d
     WHERE d.plan_semanal_id = v_plan_sem ORDER BY d.fecha LIMIT 1;
    INSERT INTO taller_plan_semanal_ots (plan_semanal_id, plan_dia_id, ot_id, estado_plan)
    VALUES (v_plan_sem, v_dia, v_ot, 'planificada') RETURNING id INTO v_po;

    -- 2 · Dentro del normal, no pide nada
    v_r := rpc_taller_ot_set_horas_plan(v_ot, 80, NULL);
    SELECT horas_planificadas INTO v_h FROM taller_plan_semanal_ots WHERE id = v_po;
    RAISE NOTICE '2 %: 80 h (el normal de MTN) entran sin justificar · quedó %',
                 CASE WHEN (v_r ->> 'success')::BOOLEAN AND v_h = 80 THEN 'OK' ELSE 'FALLA' END, v_h;

    -- 3 · Pasarse del normal sin explicar, no
    v_r := rpc_taller_ot_set_horas_plan(v_ot, 96, NULL);
    RAISE NOTICE '3 %: 96 h piden justificación · «%»',
                 CASE WHEN (v_r ->> 'requiere_justificacion')::BOOLEAN THEN 'OK' ELSE 'FALLA' END,
                 v_r ->> 'motivo';

    -- 4 · Y las horas NO se movieron
    SELECT horas_planificadas INTO v_h FROM taller_plan_semanal_ots WHERE id = v_po;
    RAISE NOTICE '4 %: siguen en % h', CASE WHEN v_h = 80 THEN 'OK' ELSE 'FALLA' END, v_h;

    -- 5 · Con la explicación, sí
    v_r := rpc_taller_ot_set_horas_plan(v_ot, 96,
             'El motor sale a rectificado y vuelve recién el jueves');
    SELECT horas_planificadas INTO v_h FROM taller_plan_semanal_ots WHERE id = v_po;
    RAISE NOTICE '5 %: con motivo quedan % h', CASE WHEN v_h = 96 THEN 'OK' ELSE 'FALLA' END, v_h;

    -- 6 · Y la justificación queda en la OT, con nombre
    RAISE NOTICE '6 %: en la OT dice «%»',
                 CASE WHEN (SELECT horas_plan_justificacion IS NOT NULL
                              AND horas_plan_justificada_por IS NOT NULL
                            FROM ordenes_trabajo WHERE id = v_ot) THEN 'OK' ELSE 'FALLA' END,
                 (SELECT horas_plan_justificacion FROM ordenes_trabajo WHERE id = v_ot);

    -- 7 · Un motivo de dos palabras no es una justificación
    v_r := rpc_taller_ot_set_horas_plan(v_ot, 120, 'porque sí');
    RAISE NOTICE '7 %: «porque sí» no alcanza',
                 CASE WHEN (v_r ->> 'requiere_justificacion')::BOOLEAN THEN 'OK' ELSE 'FALLA' END;

    -- 8 · El operador de taller no fija las horas del plan
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_op)::text, TRUE);
    BEGIN
        PERFORM rpc_taller_ot_set_horas_plan(v_ot, 8, NULL);
        RAISE NOTICE '8 FALLA: el operador fijó las horas';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '8 OK: %', SQLERRM;
    END;

    -- 9 · Las horas quedan en UNA sola jornada: la suma es el paraguas
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
    RAISE NOTICE '9 %: el techo de la OT es % h, no la suma repetida por día',
                 CASE WHEN fn_taller_ot_horas_plan(v_ot) = 96 THEN 'OK' ELSE 'FALLA' END,
                 fn_taller_ot_horas_plan(v_ot);
END $$;

ROLLBACK;
