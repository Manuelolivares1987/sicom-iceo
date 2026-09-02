-- Prueba con ROLLBACK: la pauta del fabricante como checklist (MIG490) y las
-- horas que salen de los días (MIG491). No deja nada en producción.
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_act UUID; v_plan UUID; v_pauta UUID;
    v_ot UUID; v_tpl UUID; v_inst UUID; v_contrato UUID; v_faena UUID;
    v_n INT; v_txt TEXT; v_pasos INT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    -- Un plan de mantenimiento real, con su pauta y sus pasos.
    SELECT pm.id, pm.activo_id, pm.pauta_fabricante_id
      INTO v_plan, v_act, v_pauta
      FROM planes_mantenimiento pm
      JOIN pautas_fabricante p ON p.id = pm.pauta_fabricante_id
      JOIN activos a ON a.id = pm.activo_id
     WHERE pm.activo_plan AND p.activo
       AND jsonb_array_length(p.items_checklist) >= 5
     LIMIT 1;

    SELECT jsonb_array_length(items_checklist) INTO v_pasos FROM pautas_fabricante WHERE id = v_pauta;
    SELECT contrato_id, faena_id INTO v_contrato, v_faena FROM activos WHERE id = v_act;
    IF v_contrato IS NULL THEN
        SELECT id INTO v_contrato FROM contratos LIMIT 1;
    END IF;
    IF v_faena IS NULL THEN
        SELECT id INTO v_faena FROM faenas LIMIT 1;
    END IF;
    RAISE NOTICE '0 plan de prueba: pauta con % pasos', v_pasos;

    -- 1 · La pauta tiene su template materializado, con los mismos pasos
    SELECT id INTO v_tpl FROM checklist_template_v2 WHERE pauta_fabricante_id = v_pauta;
    SELECT count(*) INTO v_n FROM checklist_template_v2_item WHERE template_id = v_tpl;
    RAISE NOTICE '1 %: el template existe y trae % ítems (la pauta tiene %)',
                 CASE WHEN v_tpl IS NOT NULL AND v_n = v_pasos THEN 'OK' ELSE 'FALLA' END, v_n, v_pasos;

    -- 2 · Una OT preventiva desde ese plan abre la PAUTA, no el V03
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, plan_mantenimiento_id, fecha_programada, created_by)
    VALUES ('OT-TEST-490A', v_act, v_contrato, v_faena, 'preventivo', 'creada', 'Prueba MIG490',
            v_plan, CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;

    SELECT t.nombre, (CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 1 ELSE 0 END)
      INTO v_txt, v_n
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '2 %: la OT abrió «%»',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, COALESCE(v_txt, 'nada');

    -- 3 · Y con los pasos del fabricante adentro
    SELECT count(*) INTO v_n FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '3 %: el mecánico ve % ítems (no los 188 de la inspección)',
                 CASE WHEN v_n = v_pasos THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 4 · Una OT SIN plan sigue abriendo la inspección general
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, fecha_programada, created_by)
    VALUES ('OT-TEST-490B', v_act, v_contrato, v_faena, 'correctivo', 'creada',
            'Prueba MIG490 sin plan', CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;
    SELECT t.momento_uso::TEXT INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '4 %: sin plan abre «%»',
                 CASE WHEN v_txt = 'recepcion_devolucion' THEN 'OK' ELSE 'FALLA' END, COALESCE(v_txt,'nada');

    -- 5 · Editar la pauta con su checklist YA EN USO abre una versión nueva,
    --     sin tocar la que el mecánico está respondiendo.
    UPDATE pautas_fabricante
       SET items_checklist = items_checklist || '["Paso agregado en la prueba"]'::jsonb
     WHERE id = v_pauta;

    SELECT count(*) INTO v_n FROM checklist_template_v2_item WHERE template_id = v_tpl;
    RAISE NOTICE '5a %: la versión en uso queda intacta con sus % ítems',
                 CASE WHEN v_n = v_pasos THEN 'OK' ELSE 'FALLA' END, v_n;

    SELECT count(*) INTO v_n FROM checklist_template_v2_item i
     WHERE i.template_id = (SELECT id FROM checklist_template_v2
                             WHERE pauta_fabricante_id = v_pauta AND activo);
    SELECT version INTO v_pasos FROM checklist_template_v2
     WHERE pauta_fabricante_id = v_pauta AND activo;
    RAISE NOTICE '5b %: la versión nueva (v%) trae % ítems',
                 CASE WHEN v_n = 7 AND v_pasos = 2 THEN 'OK' ELSE 'FALLA' END, v_pasos, v_n;

    SELECT count(*) INTO v_n FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
     WHERE i.template_id = v_tpl;
    RAISE NOTICE '5c %: las respuestas del mecánico siguen ahí (%)',
                 CASE WHEN v_n = 6 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 6 · Y desactivar la pauta desactiva su checklist
    UPDATE pautas_fabricante SET activo = FALSE WHERE id = v_pauta;
    SELECT activo::TEXT INTO v_txt FROM checklist_template_v2 WHERE id = v_tpl;
    RAISE NOTICE '6 %: pauta desactivada → template activo = %',
                 CASE WHEN v_txt = 'false' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- ── MIG491 · las horas salen de los días ────────────────────────────────
    RAISE NOTICE '7 jornada del taller: % h', fn_taller_horas_jornada();
    RAISE NOTICE '8 %: 3 días = % h · 5 días = % h · 0 días = %',
                 CASE WHEN fn_taller_horas_por_dias(3) = 24
                       AND fn_taller_horas_por_dias(5) = 40
                       AND fn_taller_horas_por_dias(0) IS NULL THEN 'OK' ELSE 'FALLA' END,
                 fn_taller_horas_por_dias(3), fn_taller_horas_por_dias(5),
                 COALESCE(fn_taller_horas_por_dias(0)::TEXT, 'NULL');
END $$;

ROLLBACK;
