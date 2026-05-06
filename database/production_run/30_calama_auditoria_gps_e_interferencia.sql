-- ============================================================================
-- 30_calama_auditoria_gps_e_interferencia.sql
-- ----------------------------------------------------------------------------
-- Refuerza la auditoria del wizard PRO terreno:
--   1. Agrega gps_accuracy + geolocation_status a evidencias y firmas.
--   2. Agrega gps_lat / gps_lng / gps_accuracy / geolocation_status a
--      calama_ot_ejecucion_eventos (asi cada PLAY/PAUSA/AVANCE deja huella).
--   3. Permite contexto/momento "interferencia_mandante" en evidencias.
--   4. Amplia los RPCs PRO terreno (iniciar / evento / finalizar / aceptar /
--      rechazar) para aceptar accuracy y geolocation_status.
--   5. Helper RPC dedicado para registrar interferencia mandante.
--
-- AISLACION: solo extiende, no rompe MIG29.
-- IDEMPOTENTE.
-- ============================================================================


-- ── 0. PRECHECK ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_iniciar_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG29 no aplicada';
    END IF;
END $$;


-- ── 1. ALTER calama_evidencias (accuracy + status) ──────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='gps_accuracy') THEN
        ALTER TABLE calama_evidencias ADD COLUMN gps_accuracy NUMERIC(8,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='geolocation_status') THEN
        -- granted | denied | unavailable | error
        ALTER TABLE calama_evidencias ADD COLUMN geolocation_status VARCHAR(20);
    END IF;
END $$;

-- Extender CHECK contexto + momento para incluir 'interferencia_mandante' / 'interferencia'
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname='chk_calama_evid_contexto'
                  AND conrelid='public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_contexto;
    END IF;
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_contexto CHECK (contexto IN (
        'ot_apertura','ot_avance','ot_cierre','subtarea','observacion','no_ejecucion','firma',
        'jornada_antes','jornada_durante','jornada_despues','jornada_rechazo',
        -- nuevo MIG30
        'interferencia_mandante'
    ));

    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname='chk_calama_evid_momento'
                  AND conrelid='public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_momento;
    END IF;
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_momento CHECK (
        momento IS NULL OR momento IN ('antes','durante','despues','rechazo','firma','generico','interferencia')
    );

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname='chk_calama_evid_geostatus'
                      AND conrelid='public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_geostatus CHECK (
            geolocation_status IS NULL OR geolocation_status IN ('granted','denied','unavailable','error')
        );
    END IF;
END $$;


-- ── 2. ALTER calama_firmas_jornada (accuracy + status) ──────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_firmas_jornada' AND column_name='gps_accuracy') THEN
        ALTER TABLE calama_firmas_jornada ADD COLUMN gps_accuracy NUMERIC(8,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_firmas_jornada' AND column_name='geolocation_status') THEN
        ALTER TABLE calama_firmas_jornada ADD COLUMN geolocation_status VARCHAR(20);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname='chk_calama_firma_geostatus'
                      AND conrelid='public.calama_firmas_jornada'::regclass) THEN
        ALTER TABLE calama_firmas_jornada ADD CONSTRAINT chk_calama_firma_geostatus CHECK (
            geolocation_status IS NULL OR geolocation_status IN ('granted','denied','unavailable','error')
        );
    END IF;
END $$;


-- ── 3. ALTER calama_ot_ejecucion_eventos (gps + status) ────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='gps_lat') THEN
        ALTER TABLE calama_ot_ejecucion_eventos ADD COLUMN gps_lat NUMERIC(10,7);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='gps_lng') THEN
        ALTER TABLE calama_ot_ejecucion_eventos ADD COLUMN gps_lng NUMERIC(10,7);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='gps_accuracy') THEN
        ALTER TABLE calama_ot_ejecucion_eventos ADD COLUMN gps_accuracy NUMERIC(8,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='geolocation_status') THEN
        ALTER TABLE calama_ot_ejecucion_eventos ADD COLUMN geolocation_status VARCHAR(20);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname='chk_calama_ejecev_geostatus'
                      AND conrelid='public.calama_ot_ejecucion_eventos'::regclass) THEN
        ALTER TABLE calama_ot_ejecucion_eventos ADD CONSTRAINT chk_calama_ejecev_geostatus CHECK (
            geolocation_status IS NULL OR geolocation_status IN ('granted','denied','unavailable','error')
        );
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_calama_ejecev_geo ON calama_ot_ejecucion_eventos (created_at DESC) WHERE geolocation_status = 'denied';


-- ============================================================================
-- ── 4. RPC actualizado: rpc_calama_iniciar_jornada (acepta accuracy/status) ─
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_iniciar_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid              UUID := auth.uid();
    v_plan_ot_id       UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_foto_url         TEXT := p_payload->>'foto_antes_url';
    v_foto_path        TEXT := p_payload->>'foto_antes_storage_path';
    v_lat              NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng              NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc              NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status       TEXT    := p_payload->>'geolocation_status';
    v_observacion      TEXT := p_payload->>'observacion';
    v_client_uuid_evid UUID := NULLIF(p_payload->>'client_uuid_evidencia','')::UUID;
    v_ot_id            UUID;
    v_ejec_id          UUID;
    v_ejec_existente   UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
        RAISE EXCEPTION 'foto_antes_url obligatoria para iniciar jornada en terreno';
    END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    IF NOT (fn_calama_uid_es_responsable_plan_ot(v_plan_ot_id) OR fn_calama_puede_planificar()) THEN
        RAISE EXCEPTION 'No autorizado a iniciar esta jornada';
    END IF;

    SELECT id INTO v_ejec_existente
      FROM calama_ot_ejecuciones
     WHERE ot_id = v_ot_id AND estado IN ('en_ejecucion','pausada')
     LIMIT 1;

    IF v_ejec_existente IS NOT NULL THEN
        v_ejec_id := v_ejec_existente;
    ELSE
        INSERT INTO calama_ot_ejecuciones (
            ot_id, plan_semanal_ot_id, ejecutor_id, estado, started_at, last_event_at,
            observacion_inicio
        ) VALUES (
            v_ot_id, v_plan_ot_id, v_uid, 'en_ejecucion', NOW(), NOW(), v_observacion
        ) RETURNING id INTO v_ejec_id;

        INSERT INTO calama_ot_ejecucion_eventos (
            ejecucion_id, ot_id, tipo, comentario, created_by,
            gps_lat, gps_lng, gps_accuracy, geolocation_status
        ) VALUES (
            v_ejec_id, v_ot_id, 'start', v_observacion, v_uid,
            v_lat, v_lng, v_acc, v_geo_status
        );
    END IF;

    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
        archivo_url, storage_path, momento, gps_lat, gps_lng, gps_accuracy, geolocation_status,
        descripcion, client_uuid, sync_status, created_by
    ) VALUES (
        'jornada_antes','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
        v_foto_url, v_foto_path, 'antes', v_lat, v_lng, v_acc, v_geo_status,
        v_observacion, v_client_uuid_evid, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'en_ejecucion', updated_at = NOW()
     WHERE id = v_plan_ot_id
       AND estado_plan NOT IN ('finalizada','cerrada','aceptada');

    UPDATE calama_ordenes_trabajo
       SET estado = 'en_ejecucion', updated_at = NOW()
     WHERE id = v_ot_id
       AND estado IN ('planificada','liberada','en_pausa','requiere_correccion');

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id, 'plan_semanal_ot_id', v_plan_ot_id);
END $$;


-- ============================================================================
-- ── 5. RPC actualizado: rpc_calama_registrar_evento_jornada (con GPS) ──────
-- ============================================================================
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

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

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
        -- pausa la jornada y marca motivo interferencia_mandante.
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

    -- Foto asociada (durante o interferencia).
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
            archivo_url, storage_path, momento, gps_lat, gps_lng, gps_accuracy, geolocation_status,
            descripcion, client_uuid, sync_status, created_by
        ) VALUES (
            v_contexto_evid,'foto', v_ot_id, v_plan_ot_id, v_ejec_id,
            v_foto_url, v_foto_path, v_momento_evid,
            v_lat, v_lng, v_acc, v_geo_status,
            v_comentario, v_client_uuid, 'sincronizado', v_uid
        )
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id, 'tipo', v_tipo);
END $$;


-- ============================================================================
-- ── 6. RPC actualizado: rpc_calama_finalizar_jornada (con GPS accuracy) ────
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

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

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
     WHERE id = v_ejec_id;

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

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'pendiente_aprobacion', updated_at = v_now
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
        'estado_ot', v_estado_ot
    );
END $$;


-- ============================================================================
-- ── 7. RPC actualizado: aceptacion (con GPS accuracy) ──────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_registrar_aceptacion_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid                UUID := auth.uid();
    v_plan_ot_id         UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_firma_url          TEXT := p_payload->>'firma_mandante_url';
    v_firma_path         TEXT := p_payload->>'firma_mandante_storage_path';
    v_firmante_nombre    TEXT := p_payload->>'firmante_nombre';
    v_firmante_rut       TEXT := p_payload->>'firmante_rut';
    v_observacion        TEXT := p_payload->>'observacion';
    v_lat                NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng                NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc                NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status         TEXT    := p_payload->>'geolocation_status';
    v_client_uuid        UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id              UUID;
    v_estado_actual      TEXT;
    v_avance             NUMERIC;
    v_now                TIMESTAMPTZ := NOW();
    v_firma_id           UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_es_mandante() THEN
        RAISE EXCEPTION 'Rol no autorizado para aceptar jornada';
    END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_firma_url IS NULL OR length(v_firma_url) = 0 THEN
        RAISE EXCEPTION 'firma_mandante_url obligatoria';
    END IF;
    IF v_firmante_nombre IS NULL OR length(trim(v_firmante_nombre)) = 0 THEN
        RAISE EXCEPTION 'firmante_nombre obligatorio';
    END IF;

    SELECT po.ot_id, po.estado_plan, ot.avance_pct
      INTO v_ot_id, v_estado_actual, v_avance
      FROM calama_plan_semanal_ots po
      JOIN calama_ordenes_trabajo  ot ON ot.id = po.ot_id
     WHERE po.id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;
    IF v_estado_actual NOT IN ('finalizada','finalizada_operador','pendiente_aprobacion') THEN
        RAISE EXCEPTION 'Jornada en estado % no admite aceptacion', v_estado_actual;
    END IF;

    INSERT INTO calama_firmas_jornada (
        plan_semanal_ot_id, ot_id, firmante_tipo, firmante_id, firmante_nombre, firmante_rut,
        firma_url, firma_storage_path, contexto,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'mandante', v_uid, v_firmante_nombre, v_firmante_rut,
        v_firma_url, v_firma_path, 'aceptacion',
        v_lat, v_lng, v_acc, v_geo_status,
        v_observacion, v_client_uuid
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = CASE WHEN v_avance >= 100 THEN 'cerrada' ELSE 'aceptada' END,
           updated_at  = v_now
     WHERE id = v_plan_ot_id;

    UPDATE calama_ordenes_trabajo
       SET estado = CASE WHEN v_avance >= 100 THEN 'finalizada' ELSE 'parcial' END,
           updated_at = v_now
     WHERE id = v_ot_id;

    RETURN jsonb_build_object('success', true, 'firma_id', v_firma_id, 'plan_semanal_ot_id', v_plan_ot_id);
END $$;


-- ============================================================================
-- ── 8. RPC actualizado: rechazo (con GPS accuracy + nombre firmante) ───────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_registrar_rechazo_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid                UUID := auth.uid();
    v_plan_ot_id         UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo             TEXT := p_payload->>'motivo';
    v_requiere_rehacer   BOOLEAN := COALESCE((p_payload->>'requiere_rehacer')::BOOLEAN, true);
    v_fotos              JSONB := p_payload->'fotos';
    v_firma_url          TEXT := p_payload->>'firma_mandante_url';
    v_firma_path         TEXT := p_payload->>'firma_mandante_storage_path';
    v_firmante_nombre    TEXT := p_payload->>'firmante_nombre';
    v_observacion        TEXT := p_payload->>'observacion';
    v_lat                NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng                NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc                NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status         TEXT    := p_payload->>'geolocation_status';
    v_client_uuid_rech   UUID := NULLIF(p_payload->>'client_uuid_rechazo','')::UUID;
    v_client_uuid_firma  UUID := NULLIF(p_payload->>'client_uuid_firma','')::UUID;
    v_ot_id              UUID;
    v_now                TIMESTAMPTZ := NOW();
    v_firma_id           UUID;
    v_rechazo_id         UUID;
    v_fotos_url          TEXT[] := '{}';
    v_foto              JSONB;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_es_mandante() THEN
        RAISE EXCEPTION 'Rol no autorizado para rechazar jornada';
    END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
        RAISE EXCEPTION 'motivo de rechazo obligatorio';
    END IF;
    IF v_firma_url IS NULL OR length(v_firma_url) = 0 THEN
        RAISE EXCEPTION 'firma_mandante_url obligatoria';
    END IF;
    IF v_firmante_nombre IS NULL OR length(trim(v_firmante_nombre)) = 0 THEN
        RAISE EXCEPTION 'firmante_nombre obligatorio';
    END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    INSERT INTO calama_firmas_jornada (
        plan_semanal_ot_id, ot_id, firmante_tipo, firmante_id, firmante_nombre,
        firma_url, firma_storage_path, contexto,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'mandante', v_uid, v_firmante_nombre,
        v_firma_url, v_firma_path, 'rechazo',
        v_lat, v_lng, v_acc, v_geo_status,
        v_observacion, v_client_uuid_firma
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    IF v_fotos IS NOT NULL AND jsonb_typeof(v_fotos) = 'array' THEN
        FOR v_foto IN SELECT * FROM jsonb_array_elements(v_fotos) LOOP
            INSERT INTO calama_evidencias (
                contexto, tipo, ot_id, plan_semanal_ot_id,
                archivo_url, storage_path, momento,
                gps_lat, gps_lng, gps_accuracy, geolocation_status,
                descripcion, client_uuid, sync_status, created_by
            ) VALUES (
                'jornada_rechazo','foto', v_ot_id, v_plan_ot_id,
                v_foto->>'url', v_foto->>'storage_path', 'rechazo',
                v_lat, v_lng, v_acc, v_geo_status,
                v_motivo, NULLIF(v_foto->>'client_uuid','')::UUID, 'sincronizado', v_uid
            )
            ON CONFLICT (client_uuid) DO NOTHING;
            v_fotos_url := array_append(v_fotos_url, v_foto->>'url');
        END LOOP;
    END IF;

    INSERT INTO calama_rechazos_jornada (
        plan_semanal_ot_id, ot_id, mandante_id, motivo, requiere_rehacer,
        fotos_url, firma_id, observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, v_uid, v_motivo, v_requiere_rehacer,
        v_fotos_url, v_firma_id, v_observacion, v_client_uuid_rech
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_rechazo_id;

    UPDATE calama_plan_semanal_ots SET estado_plan='rechazada', updated_at=v_now WHERE id=v_plan_ot_id;
    UPDATE calama_ordenes_trabajo
       SET estado = CASE WHEN v_requiere_rehacer THEN 'requiere_correccion' ELSE 'parcial' END,
           updated_at = v_now
     WHERE id = v_ot_id;

    RETURN jsonb_build_object(
        'success', true, 'rechazo_id', v_rechazo_id, 'firma_id', v_firma_id,
        'fotos_count', array_length(v_fotos_url,1)
    );
END $$;


-- ============================================================================
-- ── 9. VERIFICACION FINAL (1 fila) ─────────────────────────────────────────
-- ============================================================================
WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='gps_accuracy')        AS evid_acc,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='geolocation_status')  AS evid_geo,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_firmas_jornada' AND column_name='gps_accuracy')    AS firma_acc,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_firmas_jornada' AND column_name='geolocation_status') AS firma_geo,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='gps_lat')   AS ev_lat,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos' AND column_name='gps_accuracy') AS ev_acc,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_iniciar_jornada')                                       AS rpc_iniciar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_evento_jornada')                              AS rpc_evento,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_finalizar_jornada')                                     AS rpc_finalizar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_aceptacion_jornada')                          AS rpc_aceptar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_rechazo_jornada')                             AS rpc_rechazar
)
SELECT
    CASE
        WHEN NOT evid_acc      THEN 'STOP_EVID_ACC'
        WHEN NOT evid_geo      THEN 'STOP_EVID_GEO'
        WHEN NOT firma_acc     THEN 'STOP_FIRMA_ACC'
        WHEN NOT firma_geo     THEN 'STOP_FIRMA_GEO'
        WHEN NOT ev_lat        THEN 'STOP_EVENTO_LAT'
        WHEN NOT ev_acc        THEN 'STOP_EVENTO_ACC'
        WHEN NOT rpc_iniciar   THEN 'STOP_RPC_INICIAR'
        WHEN NOT rpc_evento    THEN 'STOP_RPC_EVENTO'
        WHEN NOT rpc_finalizar THEN 'STOP_RPC_FINALIZAR'
        WHEN NOT rpc_aceptar   THEN 'STOP_RPC_ACEPTAR'
        WHEN NOT rpc_rechazar  THEN 'STOP_RPC_RECHAZAR'
        ELSE 'OK_MIG30_GPS_INTERFERENCIA'
    END AS resultado,
    evid_acc, evid_geo, firma_acc, firma_geo, ev_lat, ev_acc,
    rpc_iniciar, rpc_evento, rpc_finalizar, rpc_aceptar, rpc_rechazar,
    NOW() AS chequeado_en
FROM chk;


-- ============================================================================
-- BITACORA
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG30_CALAMA_AUDIT_GPS',
            'Auditoria GPS + interferencia mandante: accuracy y status en evidencias/firmas/eventos.',
            current_user, NOW(), NOW(), 'ok',
            'Extiende RPCs PRO terreno para registrar accuracy y geolocation_status. Permite contexto interferencia_mandante.'
        );
    END IF;
END $$;
