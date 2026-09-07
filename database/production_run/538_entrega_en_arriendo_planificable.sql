-- ============================================================================
-- MIG538 · La ENTREGA en arriendo se planifica y la ejecuta el operador
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (07-09-2026)
-- «El Check-List de Entrega necesito que el planificador lo planifique y que
-- le salga en la aplicación del operador, que es quien lo debe hacer.»
--
-- QUÉ SE HACE
--  1. rpc_programar_entrega_arriendo: crea la OT por el mismo camino del plan
--     (rpc_programar_ot_taller, tipo inspección, SIEMPRE nueva — cada entrega
--     es un evento) y le CAMBIA el checklist: la V03 de inspección que el
--     trigger MIG144 le puso al nacer se anula (o se suelta si ya tenía
--     respuestas) y se instala la plantilla «Check-List Entrega V02 (inicio
--     arriendo)». El plan semanal la agenda como cualquier OT y el operador
--     la ve y la ejecuta en /m/taller.
--  2. ED.08 (firma técnico Pillado) y ED.09 (firma representante del cliente)
--     estaban como OK/NO OK — se «respondían» con un botón en vez de firmar.
--     Pasan a tipo FIRMA: pad + RUT en el teléfono, uno por firmante.
-- ============================================================================

BEGIN;

-- ── 1 · Las firmas de la entrega FIRMAN ─────────────────────────────────────
UPDATE checklist_template_v2_item ti SET tipo_respuesta = 'firma'
  FROM checklist_template_v2 t
 WHERE t.id = ti.template_id AND t.momento_uso = 'entrega_arriendo' AND t.activo
   AND ti.codigo IN ('ED.08', 'ED.09') AND ti.tipo_respuesta <> 'firma';

-- ── 2 · Programar una entrega desde el plan ─────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_programar_entrega_arriendo(
    p_activo_id UUID,
    p_prioridad prioridad_enum DEFAULT 'normal',
    p_fecha DATE DEFAULT NULL,
    p_responsable_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_r    JSONB;
    v_ot   UUID;
    v_tpl  UUID;
    v_inst UUID;
    v_contrato UUID; v_horas NUMERIC; v_km NUMERIC;
BEGIN
    -- Mismo camino y mismos permisos que cualquier OT del plan. Nunca se
    -- reutiliza una OT abierta: cada entrega es su propio evento.
    v_r := rpc_programar_ot_taller(p_activo_id, 'inspeccion'::tipo_ot_enum,
                                   p_prioridad, p_fecha, p_responsable_id, NULL, false);
    v_ot := (v_r->>'id')::uuid;

    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso = 'entrega_arriendo' AND activo
     ORDER BY version DESC LIMIT 1;
    IF v_tpl IS NULL THEN RAISE EXCEPTION 'No hay plantilla de Entrega activa'; END IF;

    -- La V03 que el trigger le puso al crear la OT no corresponde acá: si
    -- está virgen se anula; si traía respuestas (checklist flotante que el
    -- dedup enlazó), se suelta para no perder trabajo de nadie.
    FOR v_inst IN SELECT i.id FROM checklist_v2_instance i WHERE i.ot_id = v_ot LOOP
        IF EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                    WHERE ii.instance_id = v_inst
                      AND COALESCE(ii.resultado::text,'pendiente') <> 'pendiente') THEN
            UPDATE checklist_v2_instance SET ot_id = NULL WHERE id = v_inst;
        ELSE
            UPDATE checklist_v2_instance SET estado = 'anulado', ot_id = NULL,
                   observaciones = COALESCE(observaciones,'') || ' [MIG538] Reemplazado por el Check-List de Entrega.'
             WHERE id = v_inst;
        END IF;
    END LOOP;

    SELECT contrato_id, horas_uso_actual, kilometraje_actual
      INTO v_contrato, v_horas, v_km FROM activos WHERE id = p_activo_id;
    v_inst := fn_inicializar_checklist_v2(v_tpl, p_activo_id, v_contrato, NULL, v_horas, v_km, NULL, NULL);
    UPDATE checklist_v2_instance SET ot_id = v_ot WHERE id = v_inst;

    UPDATE ordenes_trabajo
       SET observaciones = TRIM(COALESCE(observaciones,'') || E'\nEntrega en arriendo — Check-List V02 (inicio arriendo).'),
           updated_at = NOW()
     WHERE id = v_ot;

    RETURN v_r || jsonb_build_object('entrega', true, 'checklist_instance_id', v_inst);
END $$;
REVOKE ALL ON FUNCTION rpc_programar_entrega_arriendo(UUID, prioridad_enum, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_programar_entrega_arriendo(UUID, prioridad_enum, DATE, UUID) TO authenticated;

-- ── Verificación con rollback sobre PRUEBA-01 ───────────────────────────────
DO $mig$
DECLARE v_admin UUID; v_activo UUID; v_r JSONB; v_n INT; v_momento TEXT; v_firmas INT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    BEGIN
        v_r := rpc_programar_entrega_arriendo(v_activo, 'normal', CURRENT_DATE + 1, NULL);

        SELECT t.momento_uso, count(ii.id) INTO v_momento, v_n
          FROM checklist_v2_instance i
          JOIN checklist_template_v2 t ON t.id = i.template_id
          LEFT JOIN checklist_v2_instance_item ii ON ii.instance_id = i.id
         WHERE i.ot_id = (v_r->>'id')::uuid AND i.estado = 'en_progreso'
         GROUP BY t.momento_uso;
        IF v_momento IS DISTINCT FROM 'entrega_arriendo' OR v_n < 20 THEN
            RAISE EXCEPTION 'FALLO_REAL: la OT quedó con checklist % (% items)', v_momento, v_n;
        END IF;

        SELECT count(*) INTO v_firmas
          FROM v_taller_ot_checklist_v3 v
         WHERE v.ot_id = (v_r->>'id')::uuid AND v.tipo_respuesta = 'firma';
        IF v_firmas <> 2 THEN
            RAISE EXCEPTION 'FALLO_REAL: la entrega trae % ítems de firma (deben ser 2)', v_firmas;
        END IF;

        RAISE EXCEPTION 'ROLLBACK_MARKER OT % con Entrega V02 (% items, 2 firmas)', v_r->>'folio', v_n;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK (revertida): %', SQLERRM;
        ELSE
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
    END;
    RAISE NOTICE 'MIG538 OK · la entrega se planifica y llega al teléfono del operador';
END
$mig$;

COMMIT;
