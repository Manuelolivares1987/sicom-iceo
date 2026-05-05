-- ============================================================================
-- 26_calama_avance_excel_correct_apply.sql
-- ----------------------------------------------------------------------------
-- Fix: rpc_calama_set_avance_excel_lote actualiza avance_pct con valor de
-- columna C SOLO si avance_pct esta en 0 Y la OT no tiene ejecucion. Eso
-- impedia que un re-import refrescara avances con datos reales actualizados
-- desde "Analisi carta gantt".
--
-- DIAGNOSTICO:
--   El usuario re-importo el Excel con datos actualizados. Los avances
--   NO se reflejan en BD porque la RPC respetaba el avance_pct previo
--   incluso cuando ese valor venia de un import anterior (no de un evento
--   real de operador/supervisor/planificador).
--
-- REGLA NUEVA:
--   - avance_excel_pct SIEMPRE se sobreescribe con col C (es la fuente de
--     verdad de planificacion).
--   - avance_pct se sobreescribe con col C SOLO si NO existen eventos
--     calama_ot_avance_eventos con fuente IN ('operador','supervisor',
--     'planificador') para esa OT. Es decir: si nadie modifico avance
--     manualmente o desde la app, el Excel manda.
--   - Si SI hay eventos reales, se preserva avance_pct (no toca avance real).
--
-- AISLACION:
--   - Solo redefine la funcion. No toca tablas, RLS, otras MIGs.
--   - Devuelve diagnostico ampliado: total_recibidos, matcheados,
--     actualizados_excel, actualizados_real, no_matcheados, ejemplos.
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_AVANCE_APPLY / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF to_regprocedure('public.rpc_calama_set_avance_excel_lote(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'STOP - rpc_calama_set_avance_excel_lote no existe (MIG22).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. CREATE OR REPLACE rpc_calama_set_avance_excel_lote ────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_set_avance_excel_lote(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_codigo TEXT := p_payload->>'plan_codigo';
    v_items JSONB := COALESCE(p_payload->'items','[]'::jsonb);
    v_item JSONB;
    v_folio TEXT;
    v_avance NUMERIC;
    v_count_recibidos INT := 0;
    v_count_matched INT := 0;
    v_count_act_excel INT := 0;
    v_count_act_real INT := 0;
    v_no_match_examples TEXT[] := ARRAY[]::TEXT[];
    v_ot_id UUID;
    v_avance_real_actual NUMERIC;
    v_estado_actual TEXT;
    v_tiene_evento_manual BOOLEAN;
    v_tiene_ejecucion BOOLEAN;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_importar() THEN
        RAISE EXCEPTION 'Rol no autorizado para actualizar avance Excel masivamente';
    END IF;
    IF v_plan_codigo IS NULL THEN RAISE EXCEPTION 'plan_codigo obligatorio'; END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
        v_count_recibidos := v_count_recibidos + 1;
        v_folio := 'OT_' || v_plan_codigo || '_' || COALESCE(v_item->>'tarea_codigo_excel','');
        v_avance := COALESCE(NULLIF(v_item->>'avance_excel_pct','')::NUMERIC, 0);
        v_avance := LEAST(GREATEST(v_avance, 0), 100);

        SELECT id, avance_pct, estado
          INTO v_ot_id, v_avance_real_actual, v_estado_actual
          FROM calama_ordenes_trabajo
         WHERE folio = v_folio;

        IF v_ot_id IS NULL THEN
            IF cardinality(v_no_match_examples) < 5 THEN
                v_no_match_examples := array_append(v_no_match_examples, v_folio);
            END IF;
            CONTINUE;
        END IF;

        v_count_matched := v_count_matched + 1;

        -- ¿La OT tiene eventos de avance real (manuales/operador) que protegen avance_pct?
        SELECT EXISTS (
            SELECT 1 FROM calama_ot_avance_eventos
             WHERE ot_id = v_ot_id
               AND fuente IN ('operador','supervisor','planificador')
        ) INTO v_tiene_evento_manual;

        SELECT EXISTS (
            SELECT 1 FROM calama_ot_ejecuciones
             WHERE ot_id = v_ot_id
        ) INTO v_tiene_ejecucion;

        -- avance_excel_pct SIEMPRE se actualiza
        UPDATE calama_ordenes_trabajo
           SET avance_excel_pct = v_avance,
               updated_at = NOW()
         WHERE id = v_ot_id;
        v_count_act_excel := v_count_act_excel + 1;

        -- avance_pct se sobreescribe SOLO si no hay evento real ni ejecucion
        IF NOT v_tiene_evento_manual AND NOT v_tiene_ejecucion THEN
            UPDATE calama_ordenes_trabajo
               SET avance_pct = v_avance,
                   estado = CASE
                       WHEN v_avance >= 100 AND estado IN ('planificada','liberada')
                            THEN 'finalizada'
                       WHEN v_avance > 0 AND estado IN ('planificada','liberada')
                            THEN 'en_ejecucion'
                       ELSE estado
                   END,
                   fecha_termino_real = CASE
                       WHEN v_avance >= 100 AND estado NOT IN ('cancelada','finalizada')
                            THEN NOW()
                       ELSE fecha_termino_real
                   END,
                   updated_at = NOW()
             WHERE id = v_ot_id;
            v_count_act_real := v_count_act_real + 1;

            -- Registrar evento de avance fuente='excel' solo cuando cambia el valor
            IF v_avance_real_actual IS DISTINCT FROM v_avance THEN
                INSERT INTO calama_ot_avance_eventos (
                    ot_id, avance_anterior, avance_nuevo, fuente, motivo, comentario, created_by
                ) VALUES (
                    v_ot_id, v_avance_real_actual, v_avance, 'excel',
                    CASE
                        WHEN v_avance_real_actual = 0 THEN 'inicial_desde_carta_gantt'
                        ELSE 'reimport_excel_actualizado'
                    END,
                    'Avance refrescado desde columna C de Analisi carta gantt', v_uid
                );
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'plan_codigo', v_plan_codigo,
        'total_recibidos', v_count_recibidos,
        'total_matcheados', v_count_matched,
        'total_no_matcheados', v_count_recibidos - v_count_matched,
        'total_actualizados_excel', v_count_act_excel,
        'total_actualizados_real', v_count_act_real,
        'ejemplos_no_matcheados', to_jsonb(v_no_match_examples)
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_set_avance_excel_lote(jsonb) TO authenticated;


-- ============================================================================
-- ── 2. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG26_AVANCE_APPLY',
        'rpc_calama_set_avance_excel_lote: re-import sobrescribe avance_pct salvo eventos reales',
        current_user, NOW(), NOW(), 'ok',
        'avance_excel_pct siempre se actualiza. avance_pct se actualiza si no hay evento operador/supervisor/planificador ni ejecucion.'
    );
END $$;


-- ============================================================================
-- ── 3. VERIFICACION ──────────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        (to_regprocedure('public.rpc_calama_set_avance_excel_lote(jsonb)') IS NOT NULL) AS rpc_ok
)
SELECT
    CASE WHEN rpc_ok THEN 'OK_OPERACION_CALAMA_AVANCE_APPLY'
         ELSE 'STOP_OPERACION_CALAMA_AVANCE_APPLY'
    END AS resultado,
    rpc_ok,
    'Re-importar Excel para que se aplique la nueva logica.' AS instruccion,
    NOW() AS chequeado_en
FROM checks;
