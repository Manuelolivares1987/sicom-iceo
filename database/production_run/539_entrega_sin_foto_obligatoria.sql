-- ============================================================================
-- MIG539 · La entrega en arriendo no exige foto para finalizar
-- ============================================================================
-- Manuel probó la entrega y el Finalizar rebotó con «REGLA: Tarea sin
-- evidencia = tarea no ejecutada. Cargue al menos 1 foto.» Esa regla es de
-- los trabajos de taller (lo hecho se demuestra con foto); la entrega no:
-- su evidencia son las DOS firmas del Check-List V02 (técnico y cliente,
-- ED.08/ED.09) que ya son obligatorias. Se exime del candado de foto a las
-- OT cuyo checklist vigente es de momento 'entrega_arriendo'.
--
-- El candado vive en DOS lugares (verificado en prod): rpc_transicion_ot
-- (la puerta) y el trigger validar_cierre_ot (el que de verdad impide el
-- UPDATE). Parche por línea en ambos: la condición del candado suma un
-- NOT EXISTS (checklist de entrega no anulado en la OT).
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_oid  OID;
    v_src  TEXT;
    v_new  TEXT;
    v_tgt  TEXT := 'IF v_count_evidence = 0 THEN';
    v_rep  TEXT := 'IF v_count_evidence = 0 AND NOT EXISTS ('
                || 'SELECT 1 FROM checklist_v2_instance ei '
                || 'JOIN checklist_template_v2 et ON et.id = ei.template_id '
                || 'WHERE ei.ot_id = p_ot_id AND et.momento_uso = ''entrega_arriendo'' '
                || 'AND ei.estado <> ''anulado'') THEN';
BEGIN
    SELECT p.oid INTO v_oid
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_transicion_ot';
    IF v_oid IS NULL THEN RAISE EXCEPTION 'FALLO: rpc_transicion_ot no existe'; END IF;

    v_src := pg_get_functiondef(v_oid);

    -- El target debe aparecer EXACTAMENTE una vez o el parche no es seguro.
    IF (length(v_src) - length(replace(v_src, v_tgt, ''))) / length(v_tgt) <> 1 THEN
        RAISE EXCEPTION 'FALLO: el candado de evidencia no aparece una única vez (%)',
            (length(v_src) - length(replace(v_src, v_tgt, ''))) / length(v_tgt);
    END IF;

    v_new := replace(v_src, v_tgt, v_rep);
    EXECUTE v_new;
    RAISE NOTICE 'rpc_transicion_ot parchado: la entrega queda eximida del candado de foto';
END
$mig$;

-- El trigger validar_cierre_ot repite la regla y es el que de verdad bloquea
-- el UPDATE (lección MIG472: la puerta es el RPC, el candado real el trigger).
DO $mig$
DECLARE
    v_oid  OID;
    v_src  TEXT;
    v_new  TEXT;
    v_tgt  TEXT := 'IF v_evidencias_count = 0 THEN';
    v_rep  TEXT := 'IF v_evidencias_count = 0 AND NOT EXISTS ('
                || 'SELECT 1 FROM checklist_v2_instance ei '
                || 'JOIN checklist_template_v2 et ON et.id = ei.template_id '
                || 'WHERE ei.ot_id = NEW.id AND et.momento_uso = ''entrega_arriendo'' '
                || 'AND ei.estado <> ''anulado'') THEN';
BEGIN
    SELECT p.oid INTO v_oid
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'validar_cierre_ot';
    IF v_oid IS NULL THEN RAISE EXCEPTION 'FALLO: validar_cierre_ot no existe'; END IF;

    v_src := pg_get_functiondef(v_oid);

    IF (length(v_src) - length(replace(v_src, v_tgt, ''))) / length(v_tgt) <> 1 THEN
        RAISE EXCEPTION 'FALLO: el candado del trigger no aparece una única vez (%)',
            (length(v_src) - length(replace(v_src, v_tgt, ''))) / length(v_tgt);
    END IF;

    v_new := replace(v_src, v_tgt, v_rep);
    EXECUTE v_new;
    RAISE NOTICE 'validar_cierre_ot parchado: mismo criterio que el RPC';
END
$mig$;

-- ── Verificación E2E con rollback: entrega de TEST-01 finalizada SIN fotos ──
DO $mig$
DECLARE
    v_admin  UUID;
    v_activo UUID;
    v_r      JSONB;
    v_ot     UUID;
    v_res    JSONB;
    v_estado TEXT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    IF v_admin IS NULL OR v_activo IS NULL THEN
        RAISE EXCEPTION 'FALLO: falta admin o TEST-01 para la prueba';
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    BEGIN
        -- 1 · Programar la entrega (checklist V02 de entrega, sin fotos jamás)
        v_r  := rpc_programar_entrega_arriendo(v_activo, 'normal', CURRENT_DATE, v_admin);
        v_ot := (v_r->>'id')::uuid;

        -- 2 · El "operador" completa todo el checklist (firmas incluidas)
        UPDATE checklist_v2_instance_item ii
           SET resultado = 'ok'
          FROM checklist_v2_instance i
         WHERE i.id = ii.instance_id AND i.ot_id = v_ot
           AND COALESCE(ii.excluido, false) = false;

        -- 3 · Firma del técnico en la OT (la pide el trigger de cierre) y flujo
        UPDATE ordenes_trabajo SET firma_tecnico_url = 'data:image/png;base64,TEST'
         WHERE id = v_ot;

        SELECT estado::text INTO v_estado FROM ordenes_trabajo WHERE id = v_ot;
        IF v_estado = 'creada' THEN
            PERFORM rpc_transicion_ot(v_ot, 'asignada', v_admin,
                                      NULL, NULL, NULL, v_admin);
        END IF;
        PERFORM rpc_transicion_ot(v_ot, 'en_ejecucion', v_admin);

        -- 4 · Finalizar SIN NINGUNA FOTO: antes rebotaba, ahora debe pasar
        v_res := rpc_transicion_ot(v_ot, 'ejecutada_ok', v_admin);

        SELECT estado::text INTO v_estado FROM ordenes_trabajo WHERE id = v_ot;
        IF v_estado <> 'ejecutada_ok' THEN
            RAISE EXCEPTION 'FALLO_REAL: la entrega no quedó ejecutada_ok (quedó %)', v_estado;
        END IF;

        RAISE EXCEPTION 'ROLLBACK_MARKER entrega finalizada sin foto, estado=%', v_estado;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK (revertida): %', SQLERRM;
        ELSE
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
    END;

    -- El parche quedó escrito de verdad
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'rpc_transicion_ot'
                      AND prosrc LIKE '%entrega_arriendo%')
       OR NOT EXISTS (SELECT 1 FROM pg_proc
                    WHERE proname = 'validar_cierre_ot'
                      AND prosrc LIKE '%entrega_arriendo%') THEN
        RAISE EXCEPTION 'FALLO: el parche no quedó escrito en las dos funciones';
    END IF;
    RAISE NOTICE 'MIG539 OK · la entrega en arriendo finaliza sin exigir foto';
END
$mig$;

COMMIT;
