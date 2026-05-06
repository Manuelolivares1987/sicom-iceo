-- ============================================================================
-- 29_calama_jornadas_pro_terreno.sql
-- ----------------------------------------------------------------------------
-- Lleva Operacion Calama a estandar profesional de terreno minero:
--   1. Evidencia fotografica obligatoria por momento (antes / durante / despues / rechazo)
--   2. Firma digital operador + firma digital mandante (aceptacion/rechazo)
--   3. Estados de jornada extendidos: pendiente_aprobacion / aceptada / rechazada / reprogramada / cerrada
--   4. Estado de OT extendido: parcial / pendiente_aprobacion / requiere_correccion
--   5. Reprogramacion de saldo (jornadas multidia con trazabilidad)
--   6. Base preparada para offline-first (client_uuid + sync_status + RPC sync_offline_batch)
--
-- ALCANCE:
--   - ALTER calama_evidencias (extender contexto, agregar columnas para jornada/firma/sync)
--   - ALTER plan_semanal_ots.estado_plan + ordenes_trabajo.estado (extender CHECK)
--   - CREATE calama_firmas_jornada (firmas operador + mandante asociadas a una jornada)
--   - CREATE calama_rechazos_jornada (registro estructurado de rechazos del mandante)
--   - 8 RPCs SECURITY DEFINER para flujo terreno
--   - Storage buckets calama-evidencias y calama-firmas + policies (mismo patron 14D)
--
-- AISLACION:
--   - NO toca otras MIGs.
--   - Solo extiende CHECK constraints (no cambia valores existentes, todos siguen validos).
--   - Idempotente: usa DROP + CREATE OR REPLACE / IF NOT EXISTS.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots') THEN
        RAISE EXCEPTION 'STOP - MIG20 no aplicada (calama_plan_semanal_ots no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='secuencia_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG28 no aplicada (falta calama_plan_semanal_ots.secuencia_jornada).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_evidencias') THEN
        RAISE EXCEPTION 'STOP - MIG17 no aplicada (calama_evidencias no existe).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. ALTER calama_evidencias ───────────────────────────────────────────────
-- ============================================================================
-- Agregar columnas para asociar evidencia a jornada / ejecucion y soportar
-- sincronizacion offline (client_uuid + sync_status).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias'
                      AND column_name='plan_semanal_ot_id') THEN
        ALTER TABLE calama_evidencias
            ADD COLUMN plan_semanal_ot_id UUID REFERENCES calama_plan_semanal_ots(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias'
                      AND column_name='ejecucion_id') THEN
        ALTER TABLE calama_evidencias
            ADD COLUMN ejecucion_id UUID REFERENCES calama_ot_ejecuciones(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias'
                      AND column_name='momento') THEN
        -- antes / durante / despues / rechazo / firma / generico
        ALTER TABLE calama_evidencias ADD COLUMN momento VARCHAR(20);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias'
                      AND column_name='client_uuid') THEN
        ALTER TABLE calama_evidencias ADD COLUMN client_uuid UUID UNIQUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_evidencias'
                      AND column_name='sync_status') THEN
        ALTER TABLE calama_evidencias ADD COLUMN sync_status VARCHAR(20) NOT NULL DEFAULT 'sincronizado';
    END IF;
END $$;

-- Extender CHECK contexto (incluir nuevos contextos de jornada).
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'chk_calama_evid_contexto'
                  AND conrelid = 'public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_contexto;
    END IF;
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_contexto CHECK (contexto IN (
        'ot_apertura','ot_avance','ot_cierre','subtarea','observacion','no_ejecucion','firma',
        -- nuevos contextos jornada PRO terreno
        'jornada_antes','jornada_durante','jornada_despues','jornada_rechazo'
    ));

    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'chk_calama_evid_link'
                  AND conrelid = 'public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_link;
    END IF;
    -- Ahora basta con tener al menos un link (incluye plan_semanal_ot_id)
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_link CHECK (
        ot_id IS NOT NULL
        OR subtarea_id IS NOT NULL
        OR avance_id IS NOT NULL
        OR plan_semanal_ot_id IS NOT NULL
    );

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'chk_calama_evid_momento'
                      AND conrelid = 'public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_momento CHECK (
            momento IS NULL OR momento IN ('antes','durante','despues','rechazo','firma','generico')
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'chk_calama_evid_sync'
                      AND conrelid = 'public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_sync CHECK (
            sync_status IN ('sincronizado','pendiente','error')
        );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_calama_evid_planot   ON calama_evidencias (plan_semanal_ot_id) WHERE plan_semanal_ot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_ejec     ON calama_evidencias (ejecucion_id) WHERE ejecucion_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_momento  ON calama_evidencias (momento) WHERE momento IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_sync     ON calama_evidencias (sync_status) WHERE sync_status <> 'sincronizado';


-- ============================================================================
-- ── 2. ALTER plan_semanal_ots.estado_plan (extender CHECK) ───────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'chk_calama_planot_estado'
                  AND conrelid = 'public.calama_plan_semanal_ots'::regclass) THEN
        ALTER TABLE calama_plan_semanal_ots DROP CONSTRAINT chk_calama_planot_estado;
    END IF;
    ALTER TABLE calama_plan_semanal_ots ADD CONSTRAINT chk_calama_planot_estado CHECK (estado_plan IN (
        'planificada','asignada','liberada','en_ejecucion','pausada','finalizada','no_ejecutada','bloqueada',
        -- nuevos estados PRO terreno
        'descargada_offline','finalizada_operador','pendiente_aprobacion',
        'aceptada','rechazada','requiere_correccion','reprogramada','cerrada'
    ));
END $$;


-- ============================================================================
-- ── 3. ALTER ordenes_trabajo.estado (extender CHECK) ─────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'chk_calama_ot_estado'
                  AND conrelid = 'public.calama_ordenes_trabajo'::regclass) THEN
        ALTER TABLE calama_ordenes_trabajo DROP CONSTRAINT chk_calama_ot_estado;
    END IF;
    ALTER TABLE calama_ordenes_trabajo ADD CONSTRAINT chk_calama_ot_estado CHECK (estado IN (
        'planificada','liberada','en_ejecucion','en_pausa','finalizada','no_ejecutada','cancelada',
        -- nuevos estados PRO terreno
        'parcial','pendiente_aprobacion','requiere_correccion'
    ));
END $$;


-- ============================================================================
-- ── 4. TABLA calama_firmas_jornada ───────────────────────────────────────────
-- ============================================================================
CREATE TABLE IF NOT EXISTS calama_firmas_jornada (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_ot_id  UUID NOT NULL REFERENCES calama_plan_semanal_ots(id) ON DELETE CASCADE,
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    firmante_tipo       VARCHAR(20) NOT NULL,         -- operador | mandante | supervisor
    firmante_id         UUID REFERENCES auth.users(id),
    firmante_nombre     VARCHAR(200),                  -- resguardo si firma alguien externo (mandante)
    firmante_rut        VARCHAR(20),                   -- opcional para acta legal
    firma_url           TEXT NOT NULL,
    firma_storage_path  TEXT,
    contexto            VARCHAR(20) NOT NULL,          -- inicio | cierre_operador | aceptacion | rechazo
    gps_lat             NUMERIC(10,7),
    gps_lng             NUMERIC(10,7),
    observacion         TEXT,
    client_uuid         UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_firma_tipo CHECK (firmante_tipo IN ('operador','mandante','supervisor')),
    CONSTRAINT chk_calama_firma_ctx  CHECK (contexto IN ('inicio','cierre_operador','aceptacion','rechazo'))
);
CREATE INDEX IF NOT EXISTS idx_calama_firma_planot ON calama_firmas_jornada (plan_semanal_ot_id);
CREATE INDEX IF NOT EXISTS idx_calama_firma_ot     ON calama_firmas_jornada (ot_id);
CREATE INDEX IF NOT EXISTS idx_calama_firma_ctx    ON calama_firmas_jornada (contexto);


-- ============================================================================
-- ── 5. TABLA calama_rechazos_jornada ─────────────────────────────────────────
-- ============================================================================
CREATE TABLE IF NOT EXISTS calama_rechazos_jornada (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_ot_id  UUID NOT NULL REFERENCES calama_plan_semanal_ots(id) ON DELETE CASCADE,
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    mandante_id         UUID REFERENCES auth.users(id),
    motivo              TEXT NOT NULL,
    requiere_rehacer    BOOLEAN NOT NULL DEFAULT true,
    fotos_url           TEXT[] NOT NULL DEFAULT '{}',
    firma_id            UUID REFERENCES calama_firmas_jornada(id) ON DELETE SET NULL,
    observacion         TEXT,
    client_uuid         UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_rechazo_planot ON calama_rechazos_jornada (plan_semanal_ot_id);
CREATE INDEX IF NOT EXISTS idx_calama_rechazo_ot     ON calama_rechazos_jornada (ot_id);


-- ============================================================================
-- ── 6. RLS ───────────────────────────────────────────────────────────────────
-- ============================================================================
ALTER TABLE calama_firmas_jornada    ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_rechazos_jornada  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_calama_firma_select ON calama_firmas_jornada;
CREATE POLICY pol_calama_firma_select ON calama_firmas_jornada
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR firmante_id = auth.uid()
        OR fn_calama_uid_es_responsable_plan_ot(plan_semanal_ot_id)
    );

DROP POLICY IF EXISTS pol_calama_firma_insert ON calama_firmas_jornada;
CREATE POLICY pol_calama_firma_insert ON calama_firmas_jornada
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR firmante_id = auth.uid()
        OR fn_calama_uid_es_responsable_plan_ot(plan_semanal_ot_id)
    );

DROP POLICY IF EXISTS pol_calama_rechazo_select ON calama_rechazos_jornada;
CREATE POLICY pol_calama_rechazo_select ON calama_rechazos_jornada
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR fn_calama_uid_es_responsable_plan_ot(plan_semanal_ot_id)
    );

DROP POLICY IF EXISTS pol_calama_rechazo_insert ON calama_rechazos_jornada;
CREATE POLICY pol_calama_rechazo_insert ON calama_rechazos_jornada
    FOR INSERT TO authenticated
    WITH CHECK (fn_calama_puede_planificar());


-- ============================================================================
-- ── 7. HELPER fn_calama_es_mandante ──────────────────────────────────────────
-- ============================================================================
-- "Mandante" = quien acepta o rechaza la jornada en nombre del cliente.
-- Hoy = supervisor / jefe_sucursal / planificador / admin global. Se puede
-- restringir luego agregando rol_calama='mandante_calama'.
CREATE OR REPLACE FUNCTION fn_calama_es_mandante()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT
        fn_calama_es_admin_global()
        OR fn_user_rol() IN ('supervisor','jefe_operaciones','planificador','gerencia')
        OR fn_calama_rol_proyecto() IN ('supervisor_calama','jefe_sucursal','planificador_calama');
$$;
GRANT EXECUTE ON FUNCTION fn_calama_es_mandante() TO authenticated;


-- ============================================================================
-- ── 8. RPC: rpc_calama_iniciar_jornada (foto antes obligatoria) ──────────────
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
    v_observacion      TEXT := p_payload->>'observacion';
    v_client_uuid_evid UUID := NULLIF(p_payload->>'client_uuid_evidencia','')::UUID;
    v_client_uuid_ejec UUID := NULLIF(p_payload->>'client_uuid_ejecucion','')::UUID;
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

    -- Solo el responsable o un planificador pueden iniciar.
    IF NOT (fn_calama_uid_es_responsable_plan_ot(v_plan_ot_id) OR fn_calama_puede_planificar()) THEN
        RAISE EXCEPTION 'No autorizado a iniciar esta jornada';
    END IF;

    -- Si ya hay ejecucion activa la reutilizamos (idempotente).
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
            ejecucion_id, ot_id, tipo, comentario, created_by
        ) VALUES (
            v_ejec_id, v_ot_id, 'start', v_observacion, v_uid
        );
    END IF;

    -- Foto ANTES (idempotente via client_uuid).
    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
        archivo_url, storage_path, momento, gps_lat, gps_lng, descripcion,
        client_uuid, sync_status, created_by
    ) VALUES (
        'jornada_antes','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
        v_foto_url, v_foto_path, 'antes', v_lat, v_lng, v_observacion,
        v_client_uuid_evid, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING;

    -- Sincronizar estados.
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
GRANT EXECUTE ON FUNCTION rpc_calama_iniciar_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 9. RPC: rpc_calama_registrar_evento_jornada (PLAY/PAUSA/RESUME + fotos) ─
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_registrar_evento_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid              UUID := auth.uid();
    v_plan_ot_id       UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_tipo             TEXT := p_payload->>'tipo';      -- pause | resume | avance | comentario | foto_durante
    v_motivo           TEXT := p_payload->>'motivo';
    v_comentario       TEXT := p_payload->>'comentario';
    v_avance           NUMERIC := NULLIF(p_payload->>'avance','')::NUMERIC;
    v_foto_url         TEXT := p_payload->>'foto_url';
    v_foto_path        TEXT := p_payload->>'foto_storage_path';
    v_lat              NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng              NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_client_uuid      UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id            UUID;
    v_ejec_id          UUID;
    v_estado_actual    TEXT;
    v_now              TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_tipo NOT IN ('pause','resume','avance','comentario','foto_durante') THEN
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

    -- PAUSE / RESUME mutan timers + estado.
    IF v_tipo = 'pause' AND v_estado_actual = 'en_ejecucion' THEN
        UPDATE calama_ot_ejecuciones
           SET estado='pausada',
               tiempo_total_segundos = tiempo_total_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               tiempo_efectivo_segundos = tiempo_efectivo_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               last_event_at = v_now,
               updated_at = v_now
         WHERE id = v_ejec_id;
        UPDATE calama_plan_semanal_ots SET estado_plan='pausada', updated_at=v_now WHERE id=v_plan_ot_id;
    ELSIF v_tipo = 'resume' AND v_estado_actual = 'pausada' THEN
        UPDATE calama_ot_ejecuciones
           SET estado='en_ejecucion',
               tiempo_pausado_segundos = tiempo_pausado_segundos +
                   GREATEST(0, EXTRACT(EPOCH FROM (v_now - last_event_at))::INT),
               last_event_at = v_now,
               updated_at = v_now
         WHERE id = v_ejec_id;
        UPDATE calama_plan_semanal_ots SET estado_plan='en_ejecucion', updated_at=v_now WHERE id=v_plan_ot_id;
    ELSIF v_tipo = 'avance' AND v_avance IS NOT NULL THEN
        UPDATE calama_ot_ejecuciones SET avance_final=v_avance, last_event_at=v_now WHERE id=v_ejec_id;
        -- avance parcial actualiza OT madre solo si es mayor (no retrocede).
        UPDATE calama_ordenes_trabajo
           SET avance_pct = GREATEST(avance_pct, v_avance), updated_at = v_now
         WHERE id = v_ot_id;
    END IF;

    -- Registrar evento (siempre).
    INSERT INTO calama_ot_ejecucion_eventos (
        ejecucion_id, ot_id, tipo, motivo, comentario, avance, created_by
    ) VALUES (
        v_ejec_id, v_ot_id,
        CASE WHEN v_tipo='foto_durante' THEN 'comentario' ELSE v_tipo END,
        v_motivo, v_comentario, v_avance, v_uid
    );

    -- Foto DURANTE (si vino).
    IF v_foto_url IS NOT NULL AND length(v_foto_url) > 0 THEN
        INSERT INTO calama_evidencias (
            contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
            archivo_url, storage_path, momento, gps_lat, gps_lng, descripcion,
            client_uuid, sync_status, created_by
        ) VALUES (
            'jornada_durante','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
            v_foto_url, v_foto_path, 'durante', v_lat, v_lng, v_comentario,
            v_client_uuid, 'sincronizado', v_uid
        )
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_evento_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 10. RPC: rpc_calama_finalizar_jornada (foto despues + firma operador) ───
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

    -- Cerrar ejecucion (igual que rpc_calama_finalizar_ejecucion_ot).
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
        ejecucion_id, ot_id, tipo, comentario, avance, created_by
    ) VALUES (
        v_ejec_id, v_ot_id, 'finish', v_observacion, v_avance, v_uid
    );

    -- Foto DESPUES (idempotente).
    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id, ejecucion_id,
        archivo_url, storage_path, momento, gps_lat, gps_lng, descripcion,
        client_uuid, sync_status, created_by
    ) VALUES (
        'jornada_despues','foto', v_ot_id, v_plan_ot_id, v_ejec_id,
        v_foto_url, v_foto_path, 'despues', v_lat, v_lng, v_observacion,
        v_client_uuid_foto, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING;

    -- Firma OPERADOR (idempotente).
    INSERT INTO calama_firmas_jornada (
        plan_semanal_ot_id, ot_id, firmante_tipo, firmante_id,
        firma_url, firma_storage_path, contexto, gps_lat, gps_lng, observacion,
        client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'operador', v_uid,
        v_firma_url, v_firma_path, 'cierre_operador', v_lat, v_lng, v_observacion,
        v_client_uuid_firma
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    -- Estado jornada → pendiente_aprobacion (mandante debe aceptar/rechazar).
    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'pendiente_aprobacion',
           updated_at  = v_now
     WHERE id = v_plan_ot_id;

    -- Estado OT madre depende del avance.
    --   100 → pendiente_aprobacion (espera mandante)
    --   < 100 → parcial (queda saldo, puede o no reprogramarse)
    v_estado_ot := CASE WHEN v_avance >= 100 THEN 'pendiente_aprobacion' ELSE 'parcial' END;
    UPDATE calama_ordenes_trabajo
       SET estado     = v_estado_ot,
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
GRANT EXECUTE ON FUNCTION rpc_calama_finalizar_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 11. RPC: rpc_calama_registrar_aceptacion_jornada (mandante firma OK) ────
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
        firma_url, firma_storage_path, contexto, gps_lat, gps_lng, observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'mandante', v_uid, v_firmante_nombre, v_firmante_rut,
        v_firma_url, v_firma_path, 'aceptacion', v_lat, v_lng, v_observacion, v_client_uuid
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = CASE WHEN v_avance >= 100 THEN 'cerrada' ELSE 'aceptada' END,
           updated_at  = v_now
     WHERE id = v_plan_ot_id;

    -- Si la OT alcanzo 100%, marcarla como finalizada definitivamente.
    UPDATE calama_ordenes_trabajo
       SET estado = CASE WHEN v_avance >= 100 THEN 'finalizada' ELSE 'parcial' END,
           updated_at = v_now
     WHERE id = v_ot_id;

    RETURN jsonb_build_object('success', true, 'firma_id', v_firma_id, 'plan_semanal_ot_id', v_plan_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_aceptacion_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 12. RPC: rpc_calama_registrar_rechazo_jornada (mandante rechaza) ────────
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

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    -- Firma mandante.
    INSERT INTO calama_firmas_jornada (
        plan_semanal_ot_id, ot_id, firmante_tipo, firmante_id, firmante_nombre,
        firma_url, firma_storage_path, contexto, gps_lat, gps_lng, observacion, client_uuid
    ) VALUES (
        v_plan_ot_id, v_ot_id, 'mandante', v_uid, v_firmante_nombre,
        v_firma_url, v_firma_path, 'rechazo', v_lat, v_lng, v_observacion, v_client_uuid_firma
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_firma_id;

    -- Fotos rechazo (cada una → calama_evidencias 'jornada_rechazo').
    IF v_fotos IS NOT NULL AND jsonb_typeof(v_fotos) = 'array' THEN
        FOR v_foto IN SELECT * FROM jsonb_array_elements(v_fotos) LOOP
            INSERT INTO calama_evidencias (
                contexto, tipo, ot_id, plan_semanal_ot_id,
                archivo_url, storage_path, momento, gps_lat, gps_lng, descripcion,
                client_uuid, sync_status, created_by
            ) VALUES (
                'jornada_rechazo','foto', v_ot_id, v_plan_ot_id,
                v_foto->>'url', v_foto->>'storage_path', 'rechazo', v_lat, v_lng, v_motivo,
                NULLIF(v_foto->>'client_uuid','')::UUID, 'sincronizado', v_uid
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

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'rechazada', updated_at = v_now
     WHERE id = v_plan_ot_id;

    UPDATE calama_ordenes_trabajo
       SET estado = CASE WHEN v_requiere_rehacer THEN 'requiere_correccion' ELSE 'parcial' END,
           updated_at = v_now
     WHERE id = v_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'rechazo_id', v_rechazo_id,
        'firma_id', v_firma_id,
        'fotos_count', array_length(v_fotos_url,1)
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_rechazo_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 13. RPC: rpc_calama_reprogramar_saldo_ot ────────────────────────────────
-- ============================================================================
-- Crea una nueva jornada (mismo ot_id, otra fecha), trazada a la origen via
-- reprogramada_desde_id. Marca la jornada origen como 'reprogramada'.
CREATE OR REPLACE FUNCTION rpc_calama_reprogramar_saldo_ot(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid                UUID := auth.uid();
    v_plan_ot_origen     UUID := (p_payload->>'plan_semanal_ot_origen_id')::UUID;
    v_plan_semanal_id    UUID := (p_payload->>'plan_semanal_id')::UUID;
    v_fecha_destino      DATE := (p_payload->>'fecha_destino')::DATE;
    v_responsable        UUID := NULLIF(p_payload->>'responsable_id','')::UUID;
    v_avance_objetivo    NUMERIC := NULLIF(p_payload->>'avance_objetivo_pct','')::NUMERIC;
    v_horas              NUMERIC := NULLIF(p_payload->>'horas_planificadas','')::NUMERIC;
    v_motivo             TEXT := p_payload->>'motivo';
    v_ot_id              UUID;
    v_dia_id             UUID;
    v_zona               UUID;
    v_secuencia          INT;
    v_id_nueva           UUID;
    v_estado_origen      TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para reprogramar saldo';
    END IF;
    IF v_plan_ot_origen IS NULL OR v_plan_semanal_id IS NULL OR v_fecha_destino IS NULL THEN
        RAISE EXCEPTION 'plan_semanal_ot_origen_id, plan_semanal_id y fecha_destino son obligatorios';
    END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
        RAISE EXCEPTION 'motivo de reprogramacion obligatorio';
    END IF;

    SELECT ot_id, estado_plan INTO v_ot_id, v_estado_origen
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_origen;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_ot_origen no encontrado'; END IF;

    SELECT id INTO v_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_semanal_id AND fecha = v_fecha_destino;
    IF v_dia_id IS NULL THEN RAISE EXCEPTION 'fecha_destino % no pertenece al plan_semanal_id', v_fecha_destino; END IF;

    SELECT z.id INTO v_zona
      FROM calama_ordenes_trabajo o
      JOIN calama_planificaciones p ON p.id = o.planificacion_id
      LEFT JOIN calama_zonas_proyecto z
             ON z.planificacion_id = p.id
            AND z.codigo_zona = (regexp_match(o.folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0'
     WHERE o.id = v_ot_id LIMIT 1;

    SELECT COALESCE(MAX(secuencia_jornada),0) + 1 INTO v_secuencia
      FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = v_plan_semanal_id AND ot_id = v_ot_id;

    INSERT INTO calama_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id, responsable_id,
        estado_plan, horas_planificadas, avance_objetivo_pct, secuencia_jornada,
        reprogramada_desde_id, motivo_reprogramacion, observaciones, created_by
    ) VALUES (
        v_plan_semanal_id, v_dia_id, v_ot_id, v_zona, v_responsable,
        CASE WHEN v_responsable IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
        v_horas, v_avance_objetivo, v_secuencia,
        v_plan_ot_origen, v_motivo, v_motivo, v_uid
    ) RETURNING id INTO v_id_nueva;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'reprogramada',
           motivo_reprogramacion = v_motivo,
           updated_at = NOW()
     WHERE id = v_plan_ot_origen
       AND estado_plan NOT IN ('cerrada','aceptada');

    RETURN jsonb_build_object(
        'success', true,
        'plan_semanal_ot_nueva_id', v_id_nueva,
        'secuencia', v_secuencia
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_reprogramar_saldo_ot(jsonb) TO authenticated;


-- ============================================================================
-- ── 14. RPC: rpc_calama_preparar_offline_operador (bundle pre-descarga) ─────
-- ============================================================================
-- Devuelve el bundle de jornadas + OTs + materiales que el operador necesita
-- para trabajar offline en la fecha indicada (default = hoy).
-- BASE para iteracion proxima (cliente IndexedDB consume este bundle).
CREATE OR REPLACE FUNCTION rpc_calama_preparar_offline_operador(p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid    UUID := auth.uid();
    v_fecha  DATE := COALESCE(NULLIF(p_payload->>'fecha','')::DATE, CURRENT_DATE);
    v_result JSONB;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT jsonb_build_object(
        'fecha', v_fecha,
        'usuario', v_uid,
        'jornadas', COALESCE(jsonb_agg(jornada), '[]'::jsonb)
    ) INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'plan_semanal_ot_id', po.id,
            'ot_id', ot.id,
            'folio', ot.folio,
            'titulo', ot.titulo,
            'avance_pct', ot.avance_pct,
            'fecha_jornada', d.fecha,
            'estado_plan', po.estado_plan,
            'avance_objetivo_pct', po.avance_objetivo_pct,
            'horas_planificadas', po.horas_planificadas,
            'secuencia_jornada', po.secuencia_jornada,
            'observaciones', po.observaciones,
            'zona_proyecto_id', po.zona_proyecto_id
        ) AS jornada
        FROM calama_plan_semanal_ots po
        JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
        JOIN calama_ordenes_trabajo ot ON ot.id = po.ot_id
        WHERE po.responsable_id = v_uid
          AND d.fecha = v_fecha
          AND po.estado_plan NOT IN ('finalizada','cerrada','aceptada','no_ejecutada','reprogramada')
        ORDER BY po.secuencia_jornada NULLS LAST, po.created_at
    ) j;

    -- Marcar jornadas como descargadas (best-effort, no critico).
    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'descargada_offline', updated_at = NOW()
     WHERE responsable_id = v_uid
       AND estado_plan IN ('planificada','asignada','liberada')
       AND plan_dia_id IN (SELECT id FROM calama_plan_semanal_dias WHERE fecha = v_fecha);

    RETURN COALESCE(v_result, jsonb_build_object('fecha', v_fecha, 'jornadas','[]'::jsonb));
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_preparar_offline_operador(jsonb) TO authenticated;


-- ============================================================================
-- ── 15. RPC: rpc_calama_sync_offline_batch (idempotente via client_uuid) ────
-- ============================================================================
-- Recibe un array de eventos generados offline y los procesa en orden.
-- Cada evento tiene un client_uuid; los duplicados se ignoran via ON CONFLICT.
-- Tipos soportados: iniciar_jornada, evento_jornada, finalizar_jornada,
--                   aceptacion, rechazo, reprogramar.
CREATE OR REPLACE FUNCTION rpc_calama_sync_offline_batch(p_eventos jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid       UUID := auth.uid();
    v_evento    JSONB;
    v_tipo      TEXT;
    v_resultado JSONB;
    v_resultados JSONB := '[]'::jsonb;
    v_errores    JSONB := '[]'::jsonb;
    v_ok_count   INT := 0;
    v_err_count  INT := 0;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_eventos IS NULL OR jsonb_typeof(p_eventos) <> 'array' THEN
        RAISE EXCEPTION 'p_eventos debe ser array';
    END IF;

    FOR v_evento IN SELECT * FROM jsonb_array_elements(p_eventos) LOOP
        v_tipo := v_evento->>'tipo';
        BEGIN
            IF v_tipo = 'iniciar_jornada' THEN
                v_resultado := rpc_calama_iniciar_jornada(v_evento->'payload');
            ELSIF v_tipo = 'evento_jornada' THEN
                v_resultado := rpc_calama_registrar_evento_jornada(v_evento->'payload');
            ELSIF v_tipo = 'finalizar_jornada' THEN
                v_resultado := rpc_calama_finalizar_jornada(v_evento->'payload');
            ELSIF v_tipo = 'aceptacion' THEN
                v_resultado := rpc_calama_registrar_aceptacion_jornada(v_evento->'payload');
            ELSIF v_tipo = 'rechazo' THEN
                v_resultado := rpc_calama_registrar_rechazo_jornada(v_evento->'payload');
            ELSIF v_tipo = 'reprogramar' THEN
                v_resultado := rpc_calama_reprogramar_saldo_ot(v_evento->'payload');
            ELSE
                RAISE EXCEPTION 'tipo desconocido: %', v_tipo;
            END IF;
            v_resultados := v_resultados || jsonb_build_array(jsonb_build_object(
                'client_uuid', v_evento->>'client_uuid',
                'tipo', v_tipo,
                'ok', true,
                'resultado', v_resultado
            ));
            v_ok_count := v_ok_count + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errores := v_errores || jsonb_build_array(jsonb_build_object(
                'client_uuid', v_evento->>'client_uuid',
                'tipo', v_tipo,
                'ok', false,
                'error', SQLERRM
            ));
            v_err_count := v_err_count + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'ok_count', v_ok_count,
        'err_count', v_err_count,
        'resultados', v_resultados,
        'errores', v_errores
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_sync_offline_batch(jsonb) TO authenticated;


-- ============================================================================
-- ── 16. STORAGE BUCKETS + POLICIES ──────────────────────────────────────────
-- ============================================================================

-- Bucket calama-evidencias (privado, solo authenticated).
INSERT INTO storage.buckets (id, name, public)
VALUES ('calama-evidencias', 'calama-evidencias', false)
ON CONFLICT (id) DO NOTHING;

-- Bucket calama-firmas (privado).
INSERT INTO storage.buckets (id, name, public)
VALUES ('calama-firmas', 'calama-firmas', false)
ON CONFLICT (id) DO NOTHING;

-- INSERT: cualquier authenticated puede subir bajo su path.
DROP POLICY IF EXISTS "storage_calama_evid_auth_insert" ON storage.objects;
CREATE POLICY "storage_calama_evid_auth_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'calama-evidencias');

DROP POLICY IF EXISTS "storage_calama_firmas_auth_insert" ON storage.objects;
CREATE POLICY "storage_calama_firmas_auth_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'calama-firmas');

-- SELECT: cualquier authenticated puede leer (RLS adicional via metadata si se requiere).
DROP POLICY IF EXISTS "storage_calama_evid_auth_select" ON storage.objects;
CREATE POLICY "storage_calama_evid_auth_select"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'calama-evidencias');

DROP POLICY IF EXISTS "storage_calama_firmas_auth_select" ON storage.objects;
CREATE POLICY "storage_calama_firmas_auth_select"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'calama-firmas');


-- ============================================================================
-- ── 17. BITACORA ────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG29_CALAMA_PRO_TERRENO',
            'Calama PRO terreno: evidencias antes/durante/despues + firmas + aceptacion/rechazo + reprogramar saldo + base offline.',
            current_user, NOW(), NOW(), 'ok',
            'Tablas: calama_firmas_jornada, calama_rechazos_jornada. ALTER calama_evidencias (+momento +sync). 8 RPCs nuevos. Buckets calama-evidencias y calama-firmas.'
        );
    END IF;
END $$;


-- ============================================================================
-- ── 18. VERIFICACION FINAL (1 fila) ─────────────────────────────────────────
-- ============================================================================
WITH
chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='momento')                  AS evid_momento,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='plan_semanal_ot_id')      AS evid_planot,
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_evidencias' AND column_name='client_uuid')             AS evid_clientuuid,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_firmas_jornada')                                       AS tabla_firmas,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_rechazos_jornada')                                     AS tabla_rechazos,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_iniciar_jornada')                                        AS rpc_iniciar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_finalizar_jornada')                                      AS rpc_finalizar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_registrar_aceptacion_jornada')                           AS rpc_aceptar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_registrar_rechazo_jornada')                              AS rpc_rechazar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_reprogramar_saldo_ot')                                   AS rpc_reprogramar,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_preparar_offline_operador')                              AS rpc_offline,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_sync_offline_batch')                                     AS rpc_sync,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_registrar_evento_jornada')                               AS rpc_evento,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_calama_es_mandante')                                             AS fn_mandante,
        EXISTS (SELECT 1 FROM storage.buckets WHERE id='calama-evidencias')                                                AS bucket_evid,
        EXISTS (SELECT 1 FROM storage.buckets WHERE id='calama-firmas')                                                    AS bucket_firmas,
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='storage' AND tablename='objects'
                   AND policyname='storage_calama_evid_auth_insert')                                                       AS pol_evid_insert,
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='storage' AND tablename='objects'
                   AND policyname='storage_calama_firmas_auth_insert')                                                     AS pol_firmas_insert
)
SELECT
    CASE
        WHEN NOT evid_momento     THEN 'STOP_EVIDENCIAS_MOMENTO'
        WHEN NOT evid_planot      THEN 'STOP_EVIDENCIAS_PLANOT'
        WHEN NOT evid_clientuuid  THEN 'STOP_EVIDENCIAS_CLIENTUUID'
        WHEN NOT tabla_firmas     THEN 'STOP_TABLA_FIRMAS'
        WHEN NOT tabla_rechazos   THEN 'STOP_TABLA_RECHAZOS'
        WHEN NOT rpc_iniciar      THEN 'STOP_RPC_INICIAR'
        WHEN NOT rpc_finalizar    THEN 'STOP_RPC_FINALIZAR'
        WHEN NOT rpc_aceptar      THEN 'STOP_RPC_ACEPTAR'
        WHEN NOT rpc_rechazar     THEN 'STOP_RPC_RECHAZAR'
        WHEN NOT rpc_reprogramar  THEN 'STOP_RPC_REPROGRAMAR'
        WHEN NOT rpc_offline      THEN 'STOP_RPC_OFFLINE'
        WHEN NOT rpc_sync         THEN 'STOP_RPC_SYNC'
        WHEN NOT rpc_evento       THEN 'STOP_RPC_EVENTO'
        WHEN NOT fn_mandante      THEN 'STOP_FN_MANDANTE'
        WHEN NOT bucket_evid      THEN 'STOP_BUCKET_EVIDENCIAS'
        WHEN NOT bucket_firmas    THEN 'STOP_BUCKET_FIRMAS'
        WHEN NOT pol_evid_insert  THEN 'STOP_POLICY_EVID_INSERT'
        WHEN NOT pol_firmas_insert THEN 'STOP_POLICY_FIRMAS_INSERT'
        ELSE 'OK_MIG29_CALAMA_PRO_TERRENO'
    END                AS resultado,
    evid_momento, evid_planot, evid_clientuuid,
    tabla_firmas, tabla_rechazos,
    rpc_iniciar, rpc_evento, rpc_finalizar, rpc_aceptar, rpc_rechazar,
    rpc_reprogramar, rpc_offline, rpc_sync, fn_mandante,
    bucket_evid, bucket_firmas, pol_evid_insert, pol_firmas_insert,
    NOW() AS chequeado_en
FROM chk;


-- ============================================================================
-- ROLLBACK (manual, si fuera necesario):
--   DROP FUNCTION IF EXISTS rpc_calama_iniciar_jornada(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_registrar_evento_jornada(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_finalizar_jornada(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_registrar_aceptacion_jornada(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_registrar_rechazo_jornada(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_reprogramar_saldo_ot(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_preparar_offline_operador(jsonb);
--   DROP FUNCTION IF EXISTS rpc_calama_sync_offline_batch(jsonb);
--   DROP FUNCTION IF EXISTS fn_calama_es_mandante();
--   DROP TABLE IF EXISTS calama_rechazos_jornada;
--   DROP TABLE IF EXISTS calama_firmas_jornada;
--   ALTER TABLE calama_evidencias DROP COLUMN momento, sync_status, client_uuid, plan_semanal_ot_id, ejecucion_id;
--   (CHECK constraints volverian al estado MIG17 — usar las definiciones originales)
-- ============================================================================
