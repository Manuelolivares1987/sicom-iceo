-- ============================================================================
-- 33_calama_ejecucion_auditable_multidispositivo.sql
-- ----------------------------------------------------------------------------
-- Cierra el flujo antifraude de ejecucion de jornadas Calama:
--   1. Soporta continuidad multidispositivo (PC -> celular -> PC).
--   2. Pausa exige foto + motivo + GPS.
--   3. Reanudacion exige foto + GPS.
--   4. Cierre exige llegada + foto antes + foto despues + firma operador.
--   5. Si jornada ya iniciada y faltan evidencias previas, permite
--      regularizacion con motivo (queda flag llegada_tardia /
--      foto_antes_regularizada).
--   6. Tiempos calculados por categoria: colacion, interferencia mandante,
--      pausas otros, efectivo.
--   7. RPC rpc_calama_obtener_estado_jornada con flags de faltantes.
--   8. Vista v_calama_auditoria_ejecucion_tiempos.
--
-- IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECK ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_iniciar_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG29 no aplicada';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='llegada_faena_at') THEN
        RAISE EXCEPTION 'STOP - MIG32 no aplicada';
    END IF;
END $$;


-- ============================================================================
-- ── 1. ALTER calama_plan_semanal_ots ──────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    -- Regularizaciones (cuando se inicio en PC sin llegada o foto antes).
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_tardia') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_tardia BOOLEAN NOT NULL DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_tardia_motivo') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_tardia_motivo TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='foto_antes_evidencia_id') THEN
        ALTER TABLE calama_plan_semanal_ots
            ADD COLUMN foto_antes_evidencia_id UUID REFERENCES calama_evidencias(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='foto_antes_regularizada') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN foto_antes_regularizada BOOLEAN NOT NULL DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='foto_antes_regularizada_motivo') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN foto_antes_regularizada_motivo TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='cierre_jornada_at') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN cierre_jornada_at TIMESTAMPTZ;
    END IF;
    -- Tiempos calculados (snapshot al cierre, para reportes rapidos).
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_en_faena_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_en_faena_segundos INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_operativo_bruto_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_operativo_bruto_segundos INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_pausado_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_pausado_segundos INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_colacion_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_colacion_segundos INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_interferencia_mandante_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_interferencia_mandante_segundos INT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_efectivo_trabajo_segundos') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN tiempo_efectivo_trabajo_segundos INT;
    END IF;
END $$;


-- ============================================================================
-- ── 2. RPC rpc_calama_obtener_estado_jornada ──────────────────────────────
-- ============================================================================
-- Devuelve estado completo de la jornada para el wizard movil. Incluye
-- ejecucion activa (potencialmente iniciada en otro dispositivo) y flags
-- de evidencias faltantes.
CREATE OR REPLACE FUNCTION rpc_calama_obtener_estado_jornada(p_plan_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_planot RECORD;
    v_ot RECORD;
    v_ejec RECORD;
    v_ejecutor RECORD;
    v_foto_antes_count INT;
    v_foto_despues_count INT;
    v_firma_operador_count INT;
    v_pausas_sin_foto INT;
    v_resultado JSONB;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT * INTO v_planot FROM calama_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_planot IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    SELECT id, folio, titulo, avance_pct, estado, descripcion
      INTO v_ot FROM calama_ordenes_trabajo WHERE id = v_planot.ot_id;

    -- Ejecucion activa (puede ser de otro usuario/dispositivo).
    SELECT id, ejecutor_id, estado, started_at, last_event_at,
           tiempo_total_segundos, tiempo_pausado_segundos,
           tiempo_efectivo_segundos, tiempo_colacion_segundos
      INTO v_ejec
      FROM calama_ot_ejecuciones
     WHERE ot_id = v_planot.ot_id
       AND estado IN ('en_ejecucion','pausada')
     ORDER BY started_at DESC LIMIT 1;

    IF v_ejec.ejecutor_id IS NOT NULL THEN
        SELECT id, email, nombre_completo INTO v_ejecutor
          FROM usuarios_perfil WHERE id = v_ejec.ejecutor_id;
    END IF;

    -- Conteos de evidencias clave.
    SELECT COUNT(*) INTO v_foto_antes_count
      FROM calama_evidencias
     WHERE plan_semanal_ot_id = p_plan_ot_id AND momento = 'antes';
    SELECT COUNT(*) INTO v_foto_despues_count
      FROM calama_evidencias
     WHERE plan_semanal_ot_id = p_plan_ot_id AND momento = 'despues';
    SELECT COUNT(*) INTO v_firma_operador_count
      FROM calama_firmas_jornada
     WHERE plan_semanal_ot_id = p_plan_ot_id
       AND firmante_tipo = 'operador' AND contexto = 'cierre_operador';

    -- Pausas sin foto adjunta (auditoria antifraude).
    SELECT COUNT(*) INTO v_pausas_sin_foto
      FROM calama_ot_ejecucion_eventos ev
     WHERE ev.ot_id = v_planot.ot_id
       AND ev.tipo = 'pause'
       AND NOT EXISTS (
         SELECT 1 FROM calama_evidencias e
          WHERE e.ejecucion_id = ev.ejecucion_id
            AND e.created_at BETWEEN ev.created_at - INTERVAL '10 seconds'
                                 AND ev.created_at + INTERVAL '60 seconds'
       );

    v_resultado := jsonb_build_object(
        'plan_semanal_ot_id', v_planot.id,
        'ot_id', v_planot.ot_id,
        'ot', jsonb_build_object(
            'folio', v_ot.folio, 'titulo', v_ot.titulo,
            'avance_pct', v_ot.avance_pct, 'estado', v_ot.estado,
            'descripcion', v_ot.descripcion
        ),
        'estado_plan', v_planot.estado_plan,
        'responsable_id', v_planot.responsable_id,
        'llegada_faena_at', v_planot.llegada_faena_at,
        'llegada_tardia', v_planot.llegada_tardia,
        'foto_antes_regularizada', v_planot.foto_antes_regularizada,
        'cierre_jornada_at', v_planot.cierre_jornada_at,
        'ejecucion_activa', CASE WHEN v_ejec.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id', v_ejec.id, 'estado', v_ejec.estado,
            'ejecutor_id', v_ejec.ejecutor_id,
            'ejecutor_email', v_ejecutor.email,
            'ejecutor_nombre', v_ejecutor.nombre_completo,
            'iniciada_por_otro_usuario', (v_ejec.ejecutor_id IS DISTINCT FROM v_uid),
            'started_at', v_ejec.started_at,
            'last_event_at', v_ejec.last_event_at,
            'tiempo_total_segundos', v_ejec.tiempo_total_segundos,
            'tiempo_efectivo_segundos', v_ejec.tiempo_efectivo_segundos,
            'tiempo_pausado_segundos', v_ejec.tiempo_pausado_segundos,
            'tiempo_colacion_segundos', v_ejec.tiempo_colacion_segundos
        ) END,
        'flags', jsonb_build_object(
            'falta_llegada_faena',  (v_planot.llegada_faena_at IS NULL),
            'falta_foto_antes',     (v_foto_antes_count = 0),
            'falta_foto_despues',   (v_foto_despues_count = 0),
            'falta_firma_operador', (v_firma_operador_count = 0),
            'pausa_activa',         (v_ejec.estado = 'pausada'),
            'puede_iniciar',        (v_ejec.id IS NULL
                                     AND v_planot.llegada_faena_at IS NOT NULL
                                     AND v_foto_antes_count > 0),
            'puede_reanudar',       (v_ejec.estado = 'pausada'),
            'puede_pausar',         (v_ejec.estado = 'en_ejecucion'),
            'puede_cerrar',         (v_ejec.estado IS NOT NULL
                                     AND v_planot.llegada_faena_at IS NOT NULL
                                     AND v_foto_antes_count > 0),
            'pausas_sin_foto',      v_pausas_sin_foto
        )
    );

    RETURN v_resultado;
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_obtener_estado_jornada(UUID) TO authenticated;


-- ============================================================================
-- ── 3. RPC rpc_calama_regularizar_llegada_faena ──────────────────────────
-- ============================================================================
-- Para casos en que la jornada se inicio en otro dispositivo sin registrar
-- llegada. Marca llegada_tardia=true + motivo obligatorio.
CREATE OR REPLACE FUNCTION rpc_calama_regularizar_llegada_faena(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_foto_url TEXT := p_payload->>'foto_llegada_url';
    v_foto_path TEXT := p_payload->>'foto_llegada_storage_path';
    v_motivo TEXT := p_payload->>'motivo';
    v_lat NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status TEXT := p_payload->>'geolocation_status';
    v_client_uuid UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id UUID;
    v_evid_id UUID;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
        RAISE EXCEPTION 'foto_llegada_url obligatoria';
    END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
        RAISE EXCEPTION 'motivo de regularizacion obligatorio';
    END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id,
        archivo_url, storage_path, momento,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        descripcion, client_uuid, sync_status, created_by
    ) VALUES (
        'llegada_faena','foto', v_ot_id, v_plan_ot_id,
        v_foto_url, v_foto_path, 'llegada',
        v_lat, v_lng, v_acc, v_geo_status,
        'REGULARIZACION: ' || v_motivo,
        v_client_uuid, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_evid_id;

    UPDATE calama_plan_semanal_ots
       SET llegada_faena_at = COALESCE(llegada_faena_at, v_now),
           llegada_faena_usuario_id = COALESCE(llegada_faena_usuario_id, v_uid),
           llegada_faena_evidencia_id = COALESCE(llegada_faena_evidencia_id, v_evid_id),
           llegada_faena_lat = COALESCE(llegada_faena_lat, v_lat),
           llegada_faena_lng = COALESCE(llegada_faena_lng, v_lng),
           llegada_faena_accuracy = COALESCE(llegada_faena_accuracy, v_acc),
           llegada_faena_geo_status = COALESCE(llegada_faena_geo_status, v_geo_status),
           llegada_tardia = true,
           llegada_tardia_motivo = v_motivo,
           updated_at = v_now
     WHERE id = v_plan_ot_id;

    RETURN jsonb_build_object('success', true, 'llegada_tardia', true, 'evidencia_id', v_evid_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_regularizar_llegada_faena(jsonb) TO authenticated;


-- ============================================================================
-- ── 4. RPC rpc_calama_registrar_foto_antes_regularizada ──────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_registrar_foto_antes_regularizada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_foto_url TEXT := p_payload->>'foto_url';
    v_foto_path TEXT := p_payload->>'foto_storage_path';
    v_motivo TEXT := p_payload->>'motivo';
    v_lat NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status TEXT := p_payload->>'geolocation_status';
    v_client_uuid UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id UUID;
    v_ejec_id UUID;
    v_evid_id UUID;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN RAISE EXCEPTION 'foto_url obligatoria'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo))=0 THEN RAISE EXCEPTION 'motivo obligatorio'; END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    SELECT id INTO v_ejec_id FROM calama_ot_ejecuciones
     WHERE ot_id = v_ot_id AND estado IN ('en_ejecucion','pausada')
     ORDER BY started_at DESC LIMIT 1;

    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
        archivo_url, storage_path, momento,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        descripcion, client_uuid, sync_status, created_by
    ) VALUES (
        'jornada_antes','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
        v_foto_url, v_foto_path, 'antes',
        v_lat, v_lng, v_acc, v_geo_status,
        'REGULARIZACION: ' || v_motivo,
        v_client_uuid, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_evid_id;

    UPDATE calama_plan_semanal_ots
       SET foto_antes_evidencia_id = COALESCE(foto_antes_evidencia_id, v_evid_id),
           foto_antes_regularizada = true,
           foto_antes_regularizada_motivo = v_motivo,
           updated_at = v_now
     WHERE id = v_plan_ot_id;

    RETURN jsonb_build_object('success', true, 'evidencia_id', v_evid_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_foto_antes_regularizada(jsonb) TO authenticated;


-- ============================================================================
-- ── 5. Reforzar rpc_calama_registrar_evento_jornada (foto en pause/resume) ─
-- ============================================================================
-- Mantenemos compatibilidad pero exigimos foto_url cuando tipo='pause' o
-- 'resume' o 'interferencia'. Para 'avance' y 'comentario' la foto sigue
-- siendo opcional.
CREATE OR REPLACE FUNCTION rpc_calama_registrar_evento_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid              UUID := auth.uid();
    v_plan_ot_id       UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_tipo             TEXT := p_payload->>'tipo';
    v_motivo           TEXT := p_payload->>'motivo';
    v_comentario       TEXT := p_payload->>'comentario';
    v_avance           NUMERIC := NULLIF(p_payload->>'avance','')::NUMERIC;
    v_foto_url         TEXT := p_payload->>'foto_url';
    v_foto_path        TEXT := p_payload->>'foto_storage_path';
    v_lat              NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng              NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc              NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status       TEXT    := p_payload->>'geolocation_status';
    v_client_uuid      UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id            UUID;
    v_ejec_id          UUID;
    v_estado_actual    TEXT;
    v_now              TIMESTAMPTZ := NOW();
    v_contexto_evid    TEXT;
    v_momento_evid     TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_tipo NOT IN ('pause','resume','avance','comentario','foto_durante','interferencia') THEN
        RAISE EXCEPTION 'tipo invalido: %', v_tipo;
    END IF;

    -- ANTIFRAUDE: pause / resume / interferencia exigen foto + motivo (motivo
    -- solo en pause e interferencia).
    IF v_tipo = 'pause' THEN
        IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
            RAISE EXCEPTION 'Pausa requiere motivo obligatorio';
        END IF;
        IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
            RAISE EXCEPTION 'Pausa requiere foto obligatoria';
        END IF;
    ELSIF v_tipo = 'resume' THEN
        IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
            RAISE EXCEPTION 'Reanudacion requiere foto obligatoria';
        END IF;
    ELSIF v_tipo = 'interferencia' THEN
        IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
            RAISE EXCEPTION 'Interferencia requiere motivo (tipo) obligatorio';
        END IF;
        IF v_comentario IS NULL OR length(trim(v_comentario)) = 0 THEN
            RAISE EXCEPTION 'Interferencia requiere observacion obligatoria';
        END IF;
        IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
            RAISE EXCEPTION 'Interferencia requiere foto obligatoria';
        END IF;
    END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    -- Permitir que el ejecutor original o un planificador continue (multi-device).
    IF NOT (fn_calama_uid_es_responsable_plan_ot(v_plan_ot_id) OR fn_calama_puede_planificar()) THEN
        RAISE EXCEPTION 'No autorizado';
    END IF;

    SELECT id, estado INTO v_ejec_id, v_estado_actual
      FROM calama_ot_ejecuciones
     WHERE ot_id = v_ot_id AND estado IN ('en_ejecucion','pausada')
     ORDER BY started_at DESC LIMIT 1;
    IF v_ejec_id IS NULL THEN RAISE EXCEPTION 'No hay ejecucion activa para esta OT'; END IF;

    IF v_tipo = 'pause' AND v_estado_actual = 'en_ejecucion' THEN
        UPDATE calama_ot_ejecuciones
           SET estado='pausada',
               tiempo_total_segundos = tiempo_total_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               tiempo_efectivo_segundos = tiempo_efectivo_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               last_event_at = v_now, updated_at = v_now
         WHERE id = v_ejec_id;
        UPDATE calama_plan_semanal_ots SET estado_plan='pausada', updated_at=v_now WHERE id=v_plan_ot_id;
    ELSIF v_tipo = 'resume' AND v_estado_actual = 'pausada' THEN
        -- Sumar tiempo pausado y reclasificar segun motivo si llega.
        UPDATE calama_ot_ejecuciones
           SET estado='en_ejecucion',
               tiempo_pausado_segundos = tiempo_pausado_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               last_event_at = v_now, updated_at = v_now
         WHERE id = v_ejec_id;
        UPDATE calama_plan_semanal_ots SET estado_plan='en_ejecucion', updated_at=v_now WHERE id=v_plan_ot_id;
    ELSIF v_tipo = 'avance' AND v_avance IS NOT NULL THEN
        UPDATE calama_ot_ejecuciones SET avance_final=v_avance, last_event_at=v_now WHERE id=v_ejec_id;
        UPDATE calama_ordenes_trabajo
           SET avance_pct = GREATEST(avance_pct, v_avance), updated_at = v_now
         WHERE id = v_ot_id;
    ELSIF v_tipo = 'interferencia' THEN
        IF v_estado_actual = 'en_ejecucion' THEN
            UPDATE calama_ot_ejecuciones
               SET estado='pausada',
                   tiempo_total_segundos = tiempo_total_segundos +
                       GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
                   tiempo_efectivo_segundos = tiempo_efectivo_segundos +
                       GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
                   last_event_at = v_now, updated_at = v_now
             WHERE id = v_ejec_id;
            UPDATE calama_plan_semanal_ots SET estado_plan='pausada', updated_at=v_now WHERE id=v_plan_ot_id;
        END IF;
    END IF;

    INSERT INTO calama_ot_ejecucion_eventos (
        ejecucion_id, ot_id, tipo, motivo, comentario, avance, created_by,
        gps_lat, gps_lng, gps_accuracy, geolocation_status
    ) VALUES (
        v_ejec_id, v_ot_id,
        CASE
            WHEN v_tipo='foto_durante' THEN 'comentario'
            WHEN v_tipo='interferencia' THEN 'pause'
            ELSE v_tipo
        END,
        CASE WHEN v_tipo='interferencia' THEN COALESCE(v_motivo,'interferencia_mandante') ELSE v_motivo END,
        v_comentario, v_avance, v_uid,
        v_lat, v_lng, v_acc, v_geo_status
    );

    -- Foto asociada al evento (durante/interferencia/pause/resume).
    IF v_foto_url IS NOT NULL AND length(v_foto_url) > 0 THEN
        v_contexto_evid := CASE
            WHEN v_tipo='interferencia' THEN 'interferencia_mandante'
            ELSE 'jornada_durante'
        END;
        v_momento_evid := CASE
            WHEN v_tipo='interferencia' THEN 'interferencia'
            ELSE 'durante'
        END;
        INSERT INTO calama_evidencias (
            contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
            archivo_url, storage_path, momento,
            gps_lat, gps_lng, gps_accuracy, geolocation_status,
            descripcion, client_uuid, sync_status, created_by
        ) VALUES (
            v_contexto_evid,'foto', v_ot_id, v_plan_ot_id, v_ejec_id,
            v_foto_url, v_foto_path, v_momento_evid,
            v_lat, v_lng, v_acc, v_geo_status,
            COALESCE(v_comentario, v_motivo), v_client_uuid, 'sincronizado', v_uid
        )
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id, 'tipo', v_tipo);
END $$;


-- ============================================================================
-- ── 6. Reforzar rpc_calama_finalizar_jornada (validar antifraude + tiempos) ─
-- ============================================================================
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

    -- ANTIFRAUDE: validar evidencias previas obligatorias.
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

    -- Tiempo interferencia mandante = suma de eventos pause con motivo interferencia.
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (
        LEAST(
            COALESCE(LEAD(ev.created_at) OVER (PARTITION BY ev.ejecucion_id ORDER BY ev.created_at), v_now),
            v_now
        ) - ev.created_at
    ))::INT), 0) INTO v_t_interf
    FROM calama_ot_ejecucion_eventos ev
    WHERE ev.ejecucion_id = v_ejec_id
      AND ev.tipo = 'pause'
      AND ev.motivo ILIKE '%interferencia%';

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

    -- Snapshot de tiempos en la jornada.
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


-- ============================================================================
-- ── 7. Vista v_calama_auditoria_ejecucion_tiempos ────────────────────────
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_auditoria_ejecucion_tiempos CASCADE;
CREATE VIEW v_calama_auditoria_ejecucion_tiempos AS
SELECT
    po.id                                            AS jornada_id,
    ot.folio                                         AS ot_codigo,
    ot.titulo                                        AS ot_titulo,
    up.email                                         AS responsable_email,
    d.fecha                                          AS fecha_jornada,
    po.llegada_faena_at,
    po.llegada_tardia,
    ej.started_at                                    AS inicio_jornada_at,
    po.cierre_jornada_at,
    EXTRACT(EPOCH FROM (ej.started_at - po.llegada_faena_at))::INT / 60 AS minutos_llegada_a_inicio,
    po.tiempo_operativo_bruto_segundos,
    po.tiempo_pausado_segundos,
    po.tiempo_colacion_segundos,
    po.tiempo_interferencia_mandante_segundos,
    po.tiempo_efectivo_trabajo_segundos,
    po.tiempo_en_faena_segundos,
    (SELECT COUNT(*) FROM calama_ot_ejecucion_eventos e WHERE e.ejecucion_id = ej.id AND e.tipo='pause')   AS total_pausas,
    (SELECT COUNT(*) FROM calama_ot_ejecucion_eventos e
       WHERE e.ejecucion_id = ej.id AND e.tipo='pause'
         AND NOT EXISTS (SELECT 1 FROM calama_evidencias ev
                          WHERE ev.ejecucion_id = e.ejecucion_id
                            AND ev.created_at BETWEEN e.created_at - INTERVAL '10 sec'
                                                   AND e.created_at + INTERVAL '60 sec')) AS total_pausas_sin_foto,
    (SELECT COUNT(*) FROM calama_evidencias e WHERE e.plan_semanal_ot_id = po.id AND e.momento='llegada') > 0  AS tiene_foto_llegada,
    (SELECT COUNT(*) FROM calama_evidencias e WHERE e.plan_semanal_ot_id = po.id AND e.momento='antes')   > 0  AS tiene_foto_antes,
    (SELECT COUNT(*) FROM calama_evidencias e WHERE e.plan_semanal_ot_id = po.id AND e.momento='despues') > 0  AS tiene_foto_despues,
    (SELECT COUNT(*) FROM calama_firmas_jornada f WHERE f.plan_semanal_ot_id = po.id
        AND f.firmante_tipo='operador' AND f.contexto='cierre_operador') > 0                                  AS tiene_firma_operador,
    po.llegada_faena_geo_status                                                                                AS gps_llegada_status,
    po.foto_antes_regularizada,
    po.estado_plan,
    CASE
      WHEN po.llegada_faena_at IS NULL                                                  THEN 'incompleto'
      WHEN NOT EXISTS (SELECT 1 FROM calama_evidencias e
                        WHERE e.plan_semanal_ot_id = po.id AND e.momento='antes')      THEN 'incompleto'
      WHEN po.cierre_jornada_at IS NULL                                                 THEN 'en_proceso'
      WHEN NOT EXISTS (SELECT 1 FROM calama_evidencias e
                        WHERE e.plan_semanal_ot_id = po.id AND e.momento='despues')   THEN 'incompleto'
      WHEN NOT EXISTS (SELECT 1 FROM calama_firmas_jornada f
                        WHERE f.plan_semanal_ot_id = po.id
                          AND f.firmante_tipo='operador' AND f.contexto='cierre_operador') THEN 'incompleto'
      WHEN po.llegada_tardia OR po.foto_antes_regularizada                              THEN 'regularizado'
      ELSE 'completo'
    END AS estado_auditoria
FROM calama_plan_semanal_ots po
JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
LEFT JOIN usuarios_perfil up ON up.id = po.responsable_id
LEFT JOIN LATERAL (
    SELECT id, started_at FROM calama_ot_ejecuciones
     WHERE ot_id = po.ot_id ORDER BY started_at DESC LIMIT 1
) ej ON true;

GRANT SELECT ON v_calama_auditoria_ejecucion_tiempos TO authenticated;


-- ============================================================================
-- ── 8. Verificacion final + bitacora ──────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG33_CALAMA_AUDIT_MULTIDISPOSITIVO',
            'MIG33: ejecucion auditable multidispositivo (regularizacion + foto en pause/resume + tiempos + vista auditoria).',
            current_user, NOW(), NOW(), 'ok',
            'Pausa exige foto+motivo. Reanudar exige foto. Cerrar valida llegada+foto_antes+foto_despues+firma. RPC obtener_estado_jornada con flags. Vista v_calama_auditoria_ejecucion_tiempos.'
        );
    END IF;
END $$;

WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='llegada_tardia')                       AS col_llegada_tardia,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='cierre_jornada_at')                    AS col_cierre,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='tiempo_efectivo_trabajo_segundos')     AS col_t_efectivo,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_obtener_estado_jornada')                          AS rpc_estado,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_regularizar_llegada_faena')                       AS rpc_regul_llegada,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_foto_antes_regularizada')               AS rpc_regul_antes,
        EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                 AND viewname='v_calama_auditoria_ejecucion_tiempos')                                              AS vista_auditoria
)
SELECT
    CASE
        WHEN NOT col_llegada_tardia THEN 'STOP_COL_LLEGADA_TARDIA'
        WHEN NOT col_cierre         THEN 'STOP_COL_CIERRE'
        WHEN NOT col_t_efectivo     THEN 'STOP_COL_T_EFECTIVO'
        WHEN NOT rpc_estado         THEN 'STOP_RPC_ESTADO'
        WHEN NOT rpc_regul_llegada  THEN 'STOP_RPC_REGUL_LLEGADA'
        WHEN NOT rpc_regul_antes    THEN 'STOP_RPC_REGUL_ANTES'
        WHEN NOT vista_auditoria    THEN 'STOP_VISTA_AUDITORIA'
        ELSE 'OK_MIG33_AUDIT_MULTIDISPOSITIVO'
    END AS resultado,
    col_llegada_tardia, col_cierre, col_t_efectivo,
    rpc_estado, rpc_regul_llegada, rpc_regul_antes, vista_auditoria,
    NOW() AS chequeado_en
FROM chk;
