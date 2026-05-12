-- ============================================================================
-- 43_calama_fix_finalizar_jornada_window.sql
-- ----------------------------------------------------------------------------
-- HOTFIX MIG33. La RPC rpc_calama_finalizar_jornada (mig 33 linea 493) tenia
-- un SUM(...) con LEAD(...) OVER (...) anidado:
--
--     SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (
--         LEAST(COALESCE(LEAD(ev.created_at) OVER (...), v_now), v_now)
--         - ev.created_at
--     ))::INT), 0) INTO v_t_interf
--     FROM calama_ot_ejecucion_eventos ev
--     WHERE ev.ejecucion_id = v_ejec_id
--       AND ev.tipo = 'pause'
--       AND ev.motivo ILIKE '%interferencia%';
--
-- PostgreSQL: 'aggregate function calls cannot contain window function calls'
-- (codigo 42803). El error es de PLAN, no de runtime - explota aunque el
-- WHERE no devuelva filas. Por eso recien aparece ahora: Manuel es la
-- primera persona que cierra una jornada desde MIG33.
--
-- BUG SEMANTICO ADICIONAL: el LEAD sobre filas filtradas a pauses-de-
-- interferencia da el siguiente pause-de-interferencia. Pero la pausa
-- termina con el siguiente RESUME o FINISH, no con la siguiente pausa.
-- La duracion estaba sobreestimada cuando habia mas de una pausa de
-- interferencia en una misma jornada.
--
-- Fix: WITH eventos_secuencia que calcula LEAD sobre TODOS los eventos
-- de la ejecucion, luego filtra a pauses-de-interferencia en el outer
-- para sumar la duracion correcta.
--
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE FUNCTION).
-- NO toca tablas ni datos.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_finalizar_jornada'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG29/30/33 no aplicadas (falta rpc_calama_finalizar_jornada).';
    END IF;
END $$;


-- ── Reemplazar funcion ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_calama_finalizar_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid                UUID := auth.uid();
    v_plan_ot_id         UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_avance             NUMERIC := COALESCE(NULLIF(p_payload->>'avance_final','')::NUMERIC, 100);
    v_foto_url           TEXT := p_payload->>'foto_despues_url';
    v_foto_path          TEXT := p_payload->>'foto_despues_storage_path';
    v_firma_url          TEXT := p_payload->>'firma_operador_url';
    v_firma_path         TEXT := p_payload->>'firma_operador_storage_path';
    v_observacion        TEXT := p_payload->>'observacion';
    v_lat                NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng                NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc                NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status         TEXT    := p_payload->>'geolocation_status';
    v_client_uuid_foto   UUID := NULLIF(p_payload->>'client_uuid_foto','')::UUID;
    v_client_uuid_firma  UUID := NULLIF(p_payload->>'client_uuid_firma','')::UUID;
    v_ot_id              UUID;
    v_ejec_id            UUID;
    v_now                TIMESTAMPTZ := NOW();
    v_firma_id           UUID;
    v_estado_ot          TEXT;
    v_planot             RECORD;
    v_foto_antes_count   INT;
    v_t_pausado          INT;
    v_t_efectivo         INT;
    v_t_colacion         INT;
    v_t_interf           INT;
    v_t_total            INT;
    v_t_en_faena         INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
        RAISE EXCEPTION 'foto_despues_url obligatoria para cerrar jornada';
    END IF;
    IF v_firma_url IS NULL OR length(v_firma_url) = 0 THEN
        RAISE EXCEPTION 'firma_operador_url obligatoria para cerrar jornada';
    END IF;
    IF v_avance < 0 OR v_avance > 100 THEN
        RAISE EXCEPTION 'avance_final fuera de rango (0-100)';
    END IF;
    IF v_avance < 100 AND (v_observacion IS NULL OR length(trim(v_observacion))=0) THEN
        RAISE EXCEPTION 'Cierre parcial requiere observacion obligatoria';
    END IF;

    SELECT * INTO v_planot FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_planot IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;
    v_ot_id := v_planot.ot_id;

    -- ANTIFRAUDE
    IF v_planot.llegada_faena_at IS NULL THEN
        RAISE EXCEPTION 'No se puede cerrar: falta llegada a faena (registrar o regularizar)';
    END IF;
    SELECT COUNT(*) INTO v_foto_antes_count FROM calama_evidencias
     WHERE plan_semanal_ot_id = v_plan_ot_id AND momento = 'antes';
    IF v_foto_antes_count = 0 THEN
        RAISE EXCEPTION 'No se puede cerrar: falta foto ANTES (registrar o regularizar)';
    END IF;

    IF NOT (fn_calama_uid_es_responsable_plan_ot(v_plan_ot_id) OR fn_calama_puede_planificar()) THEN
        RAISE EXCEPTION 'No autorizado';
    END IF;

    SELECT id INTO v_ejec_id
      FROM calama_ot_ejecuciones
     WHERE ot_id = v_ot_id AND estado IN ('en_ejecucion','pausada')
     ORDER BY started_at DESC LIMIT 1;
    IF v_ejec_id IS NULL THEN RAISE EXCEPTION 'No hay ejecucion activa que cerrar'; END IF;

    UPDATE calama_ot_ejecuciones
       SET estado            = 'finalizada',
           finished_at       = v_now,
           tiempo_total_segundos = tiempo_total_segundos +
               GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
           tiempo_efectivo_segundos = tiempo_efectivo_segundos +
               CASE WHEN estado = 'en_ejecucion'
                    THEN GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT)
                    ELSE 0 END,
           last_event_at     = v_now,
           avance_final      = v_avance,
           observacion_cierre = v_observacion,
           updated_at        = v_now
     WHERE id = v_ejec_id
    RETURNING tiempo_total_segundos, tiempo_pausado_segundos,
              tiempo_efectivo_segundos, tiempo_colacion_segundos
       INTO v_t_total, v_t_pausado, v_t_efectivo, v_t_colacion;

    -- FIX MIG43: WITH para extraer el LEAD del SUM (PostgreSQL no permite
    -- window function dentro de aggregate). Ademas el LEAD ahora corre
    -- sobre TODOS los eventos de la ejecucion - asi la duracion de cada
    -- pausa de interferencia es hasta el siguiente evento real
    -- (resume/finish), no hasta la siguiente pausa de interferencia.
    WITH eventos_secuencia AS (
        SELECT
            ev.created_at,
            ev.tipo,
            ev.motivo,
            LEAD(ev.created_at) OVER (
                PARTITION BY ev.ejecucion_id ORDER BY ev.created_at
            ) AS siguiente_at
        FROM calama_ot_ejecucion_eventos ev
        WHERE ev.ejecucion_id = v_ejec_id
    )
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (
        LEAST(COALESCE(siguiente_at, v_now), v_now) - created_at
    ))::INT), 0)
      INTO v_t_interf
      FROM eventos_secuencia
     WHERE tipo = 'pause'
       AND motivo ILIKE '%interferencia%';

    INSERT INTO calama_ot_ejecucion_eventos (
        ejecucion_id, ot_id, tipo, comentario, avance, created_by,
        gps_lat, gps_lng, gps_accuracy, geolocation_status
    ) VALUES (
        v_ejec_id, v_ot_id, 'finish', v_observacion, v_avance, v_uid,
        v_lat, v_lng, v_acc, v_geo_status
    );

    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
        archivo_url, storage_path, momento, gps_lat, gps_lng, gps_accuracy, geolocation_status,
        descripcion, client_uuid, sync_status, created_by
    ) VALUES (
        'jornada_despues','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
        v_foto_url, v_foto_path, 'despues', v_lat, v_lng, v_acc, v_geo_status,
        v_observacion, v_client_uuid_foto, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING;

    INSERT INTO calama_firmas_jornada (
        plan_semanal_ot_id, ot_id, firmante_tipo, firmante_id,
        firma_url, firma_storage_path, contexto,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'operador', v_uid,
        v_firma_url, v_firma_path, 'cierre_operador',
        v_lat, v_lng, v_acc, v_geo_status,
        v_observacion, v_client_uuid_firma
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    v_t_en_faena := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_planot.llegada_faena_at))::INT);
    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'pendiente_aprobacion',
           cierre_jornada_at = v_now,
           tiempo_en_faena_segundos = v_t_en_faena,
           tiempo_operativo_bruto_segundos = v_t_total,
           tiempo_pausado_segundos = v_t_pausado,
           tiempo_colacion_segundos = v_t_colacion,
           tiempo_interferencia_mandante_segundos = v_t_interf,
           tiempo_efectivo_trabajo_segundos = GREATEST(0, COALESCE(v_t_total,0) - COALESCE(v_t_pausado,0)),
           updated_at = v_now
     WHERE id = v_plan_ot_id;

    v_estado_ot := CASE WHEN v_avance >= 100 THEN 'pendiente_aprobacion' ELSE 'parcial' END;
    UPDATE calama_ordenes_trabajo
       SET estado = v_estado_ot,
           avance_pct = GREATEST(avance_pct, v_avance),
           updated_at = v_now
     WHERE id = v_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'ejecucion_id', v_ejec_id,
        'firma_id', v_firma_id,
        'estado_ot', v_estado_ot,
        'tiempos', jsonb_build_object(
            'en_faena_segundos', v_t_en_faena,
            'operativo_bruto_segundos', v_t_total,
            'pausado_segundos', v_t_pausado,
            'colacion_segundos', v_t_colacion,
            'interferencia_mandante_segundos', v_t_interf,
            'efectivo_segundos', GREATEST(0, COALESCE(v_t_total,0) - COALESCE(v_t_pausado,0))
        )
    );
END $$;

COMMENT ON FUNCTION rpc_calama_finalizar_jornada(jsonb) IS
'Cierra jornada con foto despues + firma operador. MIG29+30+33 + fix MIG43 (window-en-aggregate y semantica del LEAD para tiempo interferencia).';

GRANT EXECUTE ON FUNCTION rpc_calama_finalizar_jornada(jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
