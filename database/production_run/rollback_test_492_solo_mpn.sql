-- Prueba con ROLLBACK: la pauta del fabricante sólo para MPN (MIG492).
BEGIN;

DO $$
DECLARE
    v_admin UUID; v_act UUID; v_plan UUID; v_pauta UUID;
    v_contrato UUID; v_faena UUID;
    v_ot UUID; v_txt TEXT; v_n INT; v_pasos INT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    SELECT pm.id, pm.activo_id, pm.pauta_fabricante_id
      INTO v_plan, v_act, v_pauta
      FROM planes_mantenimiento pm
      JOIN pautas_fabricante p ON p.id = pm.pauta_fabricante_id
     WHERE pm.activo_plan AND p.activo AND jsonb_array_length(p.items_checklist) >= 5
     LIMIT 1;
    SELECT jsonb_array_length(items_checklist) INTO v_pasos FROM pautas_fabricante WHERE id = v_pauta;

    SELECT contrato_id, faena_id INTO v_contrato, v_faena FROM activos WHERE id = v_act;
    IF v_contrato IS NULL THEN SELECT id INTO v_contrato FROM contratos LIMIT 1; END IF;
    IF v_faena IS NULL THEN SELECT id INTO v_faena FROM faenas LIMIT 1; END IF;

    -- 1 · MPN declarado desde el nacimiento → pauta del fabricante
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, plan_mantenimiento_id, bono_concepto,
                                 fecha_programada, created_by)
    VALUES ('OT-TEST-492A', v_act, v_contrato, v_faena, 'preventivo', 'creada',
            'MPN', v_plan, 'MPN', CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;
    SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
      INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '1 %: MPN abre «%»', CASE WHEN v_txt='pauta' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 2 · MTN declarada → checklist genérico, aunque venga del mismo plan
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, plan_mantenimiento_id, bono_concepto,
                                 fecha_programada, created_by)
    VALUES ('OT-TEST-492B', v_act, v_contrato, v_faena, 'preventivo', 'creada',
            'MTN', v_plan, 'MTN', CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;
    SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
      INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '2 %: MTN abre «%»', CASE WHEN v_txt='generico' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 3 · Sin declarar, con contrato vigente, se deduce MPN → pauta
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, plan_mantenimiento_id,
                                 fecha_programada, created_by)
    VALUES ('OT-TEST-492C', v_act, v_contrato, v_faena, 'preventivo', 'creada',
            'sin declarar', v_plan, CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;
    SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
      INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '3 %: sin declarar (con contrato) abre «%»',
                 CASE WHEN v_txt='pauta' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 4 · Declararla MTN después cambia el checklist, porque nadie lo tocó
    UPDATE ordenes_trabajo SET bono_concepto = 'MTN' WHERE id = v_ot;
    SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
      INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot AND i.estado = 'en_progreso';
    RAISE NOTICE '4 %: al declararla MTN pasa a «%»',
                 CASE WHEN v_txt='generico' THEN 'OK' ELSE 'FALLA' END, v_txt;

    -- 5 · Y el checklist anterior queda anulado, no borrado
    SELECT count(*) INTO v_n FROM checklist_v2_instance
     WHERE ot_id = v_ot AND estado = 'anulado';
    RAISE NOTICE '5 %: el checklist anterior queda anulado (%)',
                 CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END, v_n;

    -- 6 · Si el mecánico ya respondió algo, NO se le cambia por debajo
    UPDATE ordenes_trabajo SET bono_concepto = 'MPN' WHERE id = v_ot;
    UPDATE checklist_v2_instance_item SET resultado = 'ok'
     WHERE instance_id = (SELECT id FROM checklist_v2_instance
                           WHERE ot_id = v_ot AND estado='en_progreso')
       AND id = (SELECT id FROM checklist_v2_instance_item
                  WHERE instance_id = (SELECT id FROM checklist_v2_instance
                                        WHERE ot_id = v_ot AND estado='en_progreso') LIMIT 1);
    SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
      INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot AND i.estado = 'en_progreso';
    UPDATE ordenes_trabajo SET bono_concepto = 'RCR' WHERE id = v_ot;
    DECLARE v_despues TEXT;
    BEGIN
        SELECT CASE WHEN t.pauta_fabricante_id IS NOT NULL THEN 'pauta' ELSE 'generico' END
          INTO v_despues
          FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
         WHERE i.ot_id = v_ot AND i.estado = 'en_progreso';
        RAISE NOTICE '6 %: con una respuesta puesta el checklist NO cambia (antes «%», después «%»)',
                     CASE WHEN v_despues = v_txt THEN 'OK' ELSE 'FALLA' END, v_txt, v_despues;
    END;

    -- 7 · Una OT correctiva sin plan sigue con el genérico
    INSERT INTO ordenes_trabajo (folio, activo_id, contrato_id, faena_id, tipo, estado,
                                 observaciones, fecha_programada, created_by)
    VALUES ('OT-TEST-492D', v_act, v_contrato, v_faena, 'correctivo', 'creada',
            'sin plan', CURRENT_DATE, v_admin)
    RETURNING id INTO v_ot;
    SELECT t.momento_uso::TEXT INTO v_txt
      FROM checklist_v2_instance i JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = v_ot;
    RAISE NOTICE '7 %: correctiva sin plan abre «%»',
                 CASE WHEN v_txt='recepcion_devolucion' THEN 'OK' ELSE 'FALLA' END, COALESCE(v_txt,'nada');
END $$;

ROLLBACK;
