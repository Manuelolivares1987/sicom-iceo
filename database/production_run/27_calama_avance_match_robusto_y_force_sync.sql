-- ============================================================================
-- 27_calama_avance_match_robusto_y_force_sync.sql
-- ----------------------------------------------------------------------------
-- 1. rpc_calama_set_avance_excel_lote: matching ROBUSTO via planificacion_id
--    + sufijo del folio. Antes dependia del armado exacto del folio
--    'OT_<plan_codigo>_<codigo>' lo que era fragil.
--
-- 2. NUEVO: rpc_calama_forzar_sync_avance_excel(plan_codigo)
--    Para carga inicial / reset: copia avance_excel_pct -> avance_pct para
--    TODAS las OTs del plan. NO respeta eventos previos. Solo planificador/
--    admin puede invocarlo. Util cuando Excel es la verdad y queremos
--    re-sincronizar desde cero.
--
-- 3. Devuelve diagnostico ampliado con ejemplos de diferencias.
--
-- AISLACION: solo redefine y agrega funciones. Tablas/RLS/MIGs intactas.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF to_regprocedure('public.rpc_calama_set_avance_excel_lote(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'STOP - MIG22/26 no aplicada (rpc_calama_set_avance_excel_lote no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_puede_importar()') IS NULL THEN
        RAISE EXCEPTION 'STOP - fn_calama_puede_importar no existe (MIG18).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. CREATE OR REPLACE rpc_calama_set_avance_excel_lote (matching robusto)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_set_avance_excel_lote(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_codigo TEXT := p_payload->>'plan_codigo';
    v_items JSONB := COALESCE(p_payload->'items','[]'::jsonb);
    v_item JSONB;
    v_codigo_excel TEXT;
    v_avance NUMERIC;
    v_count_recibidos INT := 0;
    v_count_matched INT := 0;
    v_count_act_excel INT := 0;
    v_count_act_real INT := 0;
    v_count_protegidos INT := 0;
    v_no_match_examples TEXT[] := ARRAY[]::TEXT[];
    v_diff_examples TEXT[] := ARRAY[]::TEXT[];
    v_plan_id UUID;
    v_ot_id UUID;
    v_avance_real_actual NUMERIC;
    v_estado_actual TEXT;
    v_tiene_evento_real BOOLEAN;
    v_tiene_ejecucion BOOLEAN;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_importar() THEN
        RAISE EXCEPTION 'Rol no autorizado para actualizar avance Excel masivamente';
    END IF;
    IF v_plan_codigo IS NULL THEN RAISE EXCEPTION 'plan_codigo obligatorio'; END IF;

    SELECT id INTO v_plan_id FROM calama_planificaciones WHERE codigo = v_plan_codigo;
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'planificacion % no encontrada', v_plan_codigo;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
        v_count_recibidos := v_count_recibidos + 1;
        v_codigo_excel := COALESCE(v_item->>'tarea_codigo_excel','');
        v_avance := COALESCE(NULLIF(v_item->>'avance_excel_pct','')::NUMERIC, 0);
        v_avance := LEAST(GREATEST(v_avance, 0), 100);

        IF v_codigo_excel = '' THEN CONTINUE; END IF;

        -- Match ROBUSTO: planificacion + folio terminado en _<codigo>
        SELECT id, avance_pct, estado
          INTO v_ot_id, v_avance_real_actual, v_estado_actual
          FROM calama_ordenes_trabajo
         WHERE planificacion_id = v_plan_id
           AND folio ~ ('_' || replace(v_codigo_excel, '.', '\.') || '$')
         LIMIT 1;

        IF v_ot_id IS NULL THEN
            IF cardinality(v_no_match_examples) < 8 THEN
                v_no_match_examples := array_append(v_no_match_examples, v_codigo_excel);
            END IF;
            CONTINUE;
        END IF;

        v_count_matched := v_count_matched + 1;

        -- ¿Tiene evento real (no-excel) o ejecucion?
        SELECT EXISTS (
            SELECT 1 FROM calama_ot_avance_eventos
             WHERE ot_id = v_ot_id
               AND fuente IN ('operador','supervisor','planificador')
        ) INTO v_tiene_evento_real;

        SELECT EXISTS (
            SELECT 1 FROM calama_ot_ejecuciones WHERE ot_id = v_ot_id
        ) INTO v_tiene_ejecucion;

        -- avance_excel_pct: SIEMPRE
        UPDATE calama_ordenes_trabajo
           SET avance_excel_pct = v_avance, updated_at = NOW()
         WHERE id = v_ot_id;
        v_count_act_excel := v_count_act_excel + 1;

        IF v_tiene_evento_real OR v_tiene_ejecucion THEN
            v_count_protegidos := v_count_protegidos + 1;
            -- Si hay diferencia entre real y excel, registrar en ejemplos
            IF v_avance_real_actual IS DISTINCT FROM v_avance
               AND cardinality(v_diff_examples) < 8 THEN
                v_diff_examples := array_append(v_diff_examples,
                    v_codigo_excel || ': real=' || v_avance_real_actual::text ||
                    ' excel=' || v_avance::text || ' (PROTEGIDO)'
                );
            END IF;
        ELSE
            -- avance_pct: tambien se sobreescribe
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

            IF v_avance_real_actual IS DISTINCT FROM v_avance THEN
                INSERT INTO calama_ot_avance_eventos (
                    ot_id, avance_anterior, avance_nuevo, fuente, motivo, comentario, created_by
                ) VALUES (
                    v_ot_id, v_avance_real_actual, v_avance, 'excel',
                    CASE WHEN v_avance_real_actual = 0
                         THEN 'inicial_desde_carta_gantt'
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
        'plan_id', v_plan_id,
        'total_recibidos', v_count_recibidos,
        'total_matcheados', v_count_matched,
        'total_no_matcheados', v_count_recibidos - v_count_matched,
        'total_actualizados_excel', v_count_act_excel,
        'total_actualizados_real', v_count_act_real,
        'total_protegidos_por_evento_real', v_count_protegidos,
        'ejemplos_no_matcheados', to_jsonb(v_no_match_examples),
        'ejemplos_diferencias_protegidas', to_jsonb(v_diff_examples)
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_set_avance_excel_lote(jsonb) TO authenticated;


-- ============================================================================
-- ── 2. NUEVA: rpc_calama_forzar_sync_avance_excel(plan_codigo) ───────────────
-- ============================================================================
-- Sin guardas: copia avance_excel_pct -> avance_pct para TODAS las OTs del
-- plan. Util para reset/carga inicial. Solo admin/gerencia/subgerente.
CREATE OR REPLACE FUNCTION rpc_calama_forzar_sync_avance_excel(p_plan_codigo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_id UUID;
    v_count INT := 0;
    v_count_changed INT := 0;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- SOLO admin global. fn_calama_puede_importar es muy amplio.
    IF NOT fn_calama_es_admin_global() THEN
        RAISE EXCEPTION 'Solo admin puede forzar sync de avance Excel';
    END IF;

    SELECT id INTO v_plan_id FROM calama_planificaciones WHERE codigo = p_plan_codigo;
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'planificacion % no encontrada', p_plan_codigo;
    END IF;

    -- Registrar evento por cada OT donde el avance cambia (auditoria)
    INSERT INTO calama_ot_avance_eventos (
        ot_id, avance_anterior, avance_nuevo, fuente, motivo, comentario, created_by
    )
    SELECT id, avance_pct, avance_excel_pct,
           'sistema', 'forzar_sync_inicial',
           'Sync forzado: avance_pct = avance_excel_pct (carga inicial)', v_uid
      FROM calama_ordenes_trabajo
     WHERE planificacion_id = v_plan_id
       AND avance_pct IS DISTINCT FROM avance_excel_pct;

    -- Hacer la copia avance_excel_pct -> avance_pct
    WITH upd AS (
        UPDATE calama_ordenes_trabajo
           SET avance_pct = avance_excel_pct,
               estado = CASE
                   WHEN avance_excel_pct >= 100 AND estado IN ('planificada','liberada','en_ejecucion','en_pausa')
                        THEN 'finalizada'
                   WHEN avance_excel_pct > 0 AND estado IN ('planificada','liberada')
                        THEN 'en_ejecucion'
                   ELSE estado
               END,
               fecha_termino_real = CASE
                   WHEN avance_excel_pct >= 100 AND estado NOT IN ('cancelada','finalizada')
                        THEN NOW()
                   ELSE fecha_termino_real
               END,
               updated_at = NOW()
         WHERE planificacion_id = v_plan_id
           AND avance_pct IS DISTINCT FROM avance_excel_pct
        RETURNING id
    )
    SELECT COUNT(*) INTO v_count_changed FROM upd;

    SELECT COUNT(*) INTO v_count
      FROM calama_ordenes_trabajo
     WHERE planificacion_id = v_plan_id;

    RETURN jsonb_build_object(
        'success', true,
        'plan_codigo', p_plan_codigo,
        'total_ots_plan', v_count,
        'total_actualizadas', v_count_changed,
        'mensaje',
        format('Sync forzado: %s/%s OTs alineadas a avance_excel_pct', v_count_changed, v_count)
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_forzar_sync_avance_excel(TEXT) TO authenticated;


-- ============================================================================
-- ── 3. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG27_AVANCE_MATCH_FORCE',
        'rpc_calama_set_avance_excel_lote (matching robusto) + rpc_calama_forzar_sync_avance_excel',
        current_user, NOW(), NOW(), 'ok',
        'Match por planificacion_id + folio suffix. Force sync admin-only.'
    );
END $$;


-- ============================================================================
-- ── 4. VERIFICACION ──────────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        (to_regprocedure('public.rpc_calama_set_avance_excel_lote(jsonb)') IS NOT NULL)        AS rpc_lote_ok,
        (to_regprocedure('public.rpc_calama_forzar_sync_avance_excel(text)') IS NOT NULL)      AS rpc_force_ok
)
SELECT
    CASE WHEN rpc_lote_ok AND rpc_force_ok
         THEN 'OK_OPERACION_CALAMA_MATCH_FORCE'
         ELSE 'STOP_OPERACION_CALAMA_MATCH_FORCE'
    END AS resultado,
    rpc_lote_ok, rpc_force_ok,
    'Re-importar Excel y/o llamar rpc_calama_forzar_sync_avance_excel para alinear.' AS instruccion,
    NOW() AS chequeado_en
FROM checks;
