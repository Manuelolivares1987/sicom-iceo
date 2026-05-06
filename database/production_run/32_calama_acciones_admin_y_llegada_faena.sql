-- ============================================================================
-- 32_calama_acciones_admin_y_llegada_faena.sql
-- ----------------------------------------------------------------------------
-- Habilita acciones administrativas auditadas sobre jornadas Calama y agrega
-- el hito obligatorio "Llegada a faena" antes de iniciar la ejecucion.
--
-- ALCANCE:
--   1. Columnas en calama_plan_semanal_ots:
--      - desprogramada_at / desprogramada_by / motivo_desprogramacion / observacion_desprogramacion
--      - anulada_at / anulada_by / motivo_anulacion
--      - es_prueba (bool)
--      - visible_en_kanban (bool, default true)
--      - requiere_decision_programador (bool, default false)
--      - llegada_faena_at / llegada_faena_usuario_id / llegada_faena_evidencia_id
--      - llegada_faena_lat / llegada_faena_lng / llegada_faena_accuracy / llegada_faena_geo_status
--   2. CHECK estado_plan extendido: desprogramada, anulada_prueba, cancelada_operacional.
--   3. Tabla calama_jornada_auditoria + RLS.
--   4. Contexto evidencia 'llegada_faena' + momento 'llegada'.
--   5. Helper fn_calama_audit_jornada.
--   6. RPCs:
--      - rpc_calama_desprogramar_jornada
--      - rpc_calama_cancelar_jornada
--      - rpc_calama_resetear_jornada_prueba (admin global, exige RESET)
--      - rpc_calama_eliminar_jornada_prueba (admin global, exige ELIMINAR + sin firma mandante real)
--      - rpc_calama_registrar_llegada_faena
--   7. Modifica rpc_calama_iniciar_jornada para exigir llegada_faena_at.
--
-- IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECK ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_iniciar_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG29 no aplicada';
    END IF;
END $$;


-- ============================================================================
-- ── 1. ALTER calama_plan_semanal_ots ──────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    -- Desprogramacion / anulacion
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='desprogramada_at') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN desprogramada_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='desprogramada_by') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN desprogramada_by UUID REFERENCES auth.users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='motivo_desprogramacion') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN motivo_desprogramacion TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='observacion_desprogramacion') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN observacion_desprogramacion TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='anulada_at') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN anulada_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='anulada_by') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN anulada_by UUID REFERENCES auth.users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='motivo_anulacion') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN motivo_anulacion TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='es_prueba') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN es_prueba BOOLEAN NOT NULL DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='visible_en_kanban') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN visible_en_kanban BOOLEAN NOT NULL DEFAULT true;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='requiere_decision_programador') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN requiere_decision_programador BOOLEAN NOT NULL DEFAULT false;
    END IF;

    -- Llegada a faena
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_at') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_usuario_id') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_usuario_id UUID REFERENCES auth.users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_evidencia_id') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_evidencia_id UUID REFERENCES calama_evidencias(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_lat') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_lat NUMERIC(10,7);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_lng') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_lng NUMERIC(10,7);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_accuracy') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_accuracy NUMERIC(8,2);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                    AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_geo_status') THEN
        ALTER TABLE calama_plan_semanal_ots ADD COLUMN llegada_faena_geo_status VARCHAR(20);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_calama_planot_visible ON calama_plan_semanal_ots (plan_semanal_id) WHERE visible_en_kanban = true;
CREATE INDEX IF NOT EXISTS idx_calama_planot_decision ON calama_plan_semanal_ots (plan_semanal_id) WHERE requiere_decision_programador = true;


-- ============================================================================
-- ── 2. Extender CHECK estado_plan con estados administrativos ─────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname='chk_calama_planot_estado'
                  AND conrelid='public.calama_plan_semanal_ots'::regclass) THEN
        ALTER TABLE calama_plan_semanal_ots DROP CONSTRAINT chk_calama_planot_estado;
    END IF;
    ALTER TABLE calama_plan_semanal_ots ADD CONSTRAINT chk_calama_planot_estado CHECK (estado_plan IN (
        'planificada','asignada','liberada','en_ejecucion','pausada','finalizada','no_ejecutada','bloqueada',
        'descargada_offline','finalizada_operador','pendiente_aprobacion',
        'aceptada','rechazada','requiere_correccion','reprogramada','cerrada',
        -- MIG32: administrativos
        'desprogramada','anulada_prueba','cancelada_operacional'
    ));
END $$;


-- ============================================================================
-- ── 3. Extender contexto/momento evidencias para "llegada_faena" ──────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname='chk_calama_evid_contexto'
                  AND conrelid='public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_contexto;
    END IF;
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_contexto CHECK (contexto IN (
        'ot_apertura','ot_avance','ot_cierre','subtarea','observacion','no_ejecucion','firma',
        'jornada_antes','jornada_durante','jornada_despues','jornada_rechazo',
        'interferencia_mandante',
        -- MIG32
        'llegada_faena'
    ));

    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname='chk_calama_evid_momento'
                  AND conrelid='public.calama_evidencias'::regclass) THEN
        ALTER TABLE calama_evidencias DROP CONSTRAINT chk_calama_evid_momento;
    END IF;
    ALTER TABLE calama_evidencias ADD CONSTRAINT chk_calama_evid_momento CHECK (
        momento IS NULL OR momento IN ('antes','durante','despues','rechazo','firma','generico','interferencia','llegada')
    );
END $$;


-- ============================================================================
-- ── 4. Tabla calama_jornada_auditoria ─────────────────────────────────────
-- ============================================================================
CREATE TABLE IF NOT EXISTS calama_jornada_auditoria (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_ot_id   UUID REFERENCES calama_plan_semanal_ots(id) ON DELETE SET NULL,
    ot_id                UUID REFERENCES calama_ordenes_trabajo(id) ON DELETE SET NULL,
    accion               TEXT NOT NULL,
    estado_anterior      TEXT,
    estado_nuevo         TEXT,
    fecha_anterior       DATE,
    fecha_nueva          DATE,
    responsable_anterior UUID,
    responsable_nuevo    UUID,
    motivo               TEXT,
    observacion          TEXT,
    ejecutado_por        UUID NOT NULL,
    ejecutado_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata             JSONB
);
CREATE INDEX IF NOT EXISTS idx_calama_audit_planot ON calama_jornada_auditoria (plan_semanal_ot_id, ejecutado_at DESC);
CREATE INDEX IF NOT EXISTS idx_calama_audit_ot     ON calama_jornada_auditoria (ot_id, ejecutado_at DESC);
CREATE INDEX IF NOT EXISTS idx_calama_audit_accion ON calama_jornada_auditoria (accion, ejecutado_at DESC);

ALTER TABLE calama_jornada_auditoria ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_calama_audit_select ON calama_jornada_auditoria;
CREATE POLICY pol_calama_audit_select ON calama_jornada_auditoria
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
    );

-- INSERT solo via SECURITY DEFINER (los RPCs lo hacen).
DROP POLICY IF EXISTS pol_calama_audit_insert ON calama_jornada_auditoria;
CREATE POLICY pol_calama_audit_insert ON calama_jornada_auditoria
    FOR INSERT TO authenticated
    WITH CHECK (fn_calama_puede_planificar());


-- ============================================================================
-- ── 5. Helper fn_calama_audit_jornada ─────────────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_calama_audit_jornada(p_payload jsonb)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO calama_jornada_auditoria (
        plan_semanal_ot_id, ot_id, accion,
        estado_anterior, estado_nuevo, fecha_anterior, fecha_nueva,
        responsable_anterior, responsable_nuevo,
        motivo, observacion, ejecutado_por, metadata
    ) VALUES (
        NULLIF(p_payload->>'plan_semanal_ot_id','')::UUID,
        NULLIF(p_payload->>'ot_id','')::UUID,
        p_payload->>'accion',
        p_payload->>'estado_anterior', p_payload->>'estado_nuevo',
        NULLIF(p_payload->>'fecha_anterior','')::DATE,
        NULLIF(p_payload->>'fecha_nueva','')::DATE,
        NULLIF(p_payload->>'responsable_anterior','')::UUID,
        NULLIF(p_payload->>'responsable_nuevo','')::UUID,
        p_payload->>'motivo',
        p_payload->>'observacion',
        COALESCE(NULLIF(p_payload->>'ejecutado_por','')::UUID, auth.uid()),
        p_payload->'metadata'
    ) RETURNING id INTO v_id;
    RETURN v_id;
END $$;


-- ============================================================================
-- ── 6. RPC desprogramar jornada ───────────────────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_desprogramar_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo     TEXT := p_payload->>'motivo';
    v_obs        TEXT := p_payload->>'observacion';
    v_destino    TEXT := COALESCE(p_payload->>'destino','desprogramada'); -- backlog | requiere_reprogramacion | desprogramada
    v_ot_id      UUID;
    v_estado_actual TEXT;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo))=0 THEN RAISE EXCEPTION 'motivo obligatorio'; END IF;

    SELECT ot_id, estado_plan INTO v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;
    IF v_estado_actual IN ('aceptada','cerrada') THEN
        RAISE EXCEPTION 'Jornada en estado % no se desprograma', v_estado_actual;
    END IF;

    IF v_destino = 'backlog' THEN
        DELETE FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    ELSE
        UPDATE calama_plan_semanal_ots
           SET estado_plan = 'desprogramada',
               desprogramada_at = v_now,
               desprogramada_by = v_uid,
               motivo_desprogramacion = v_motivo,
               observacion_desprogramacion = v_obs,
               requiere_decision_programador = (v_destino = 'requiere_reprogramacion'),
               visible_en_kanban = (v_destino = 'requiere_reprogramacion'),
               updated_at = v_now
         WHERE id = v_plan_ot_id;
    END IF;

    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id', v_ot_id::text,
        'accion','desprogramar',
        'estado_anterior', v_estado_actual,
        'estado_nuevo', CASE WHEN v_destino='backlog' THEN 'eliminada' ELSE 'desprogramada' END,
        'motivo', v_motivo, 'observacion', v_obs,
        'metadata', jsonb_build_object('destino', v_destino)
    ));

    RETURN jsonb_build_object('success', true, 'destino', v_destino);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_desprogramar_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 7. RPC cancelar jornada ───────────────────────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_cancelar_jornada(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo TEXT := p_payload->>'motivo';
    v_obs    TEXT := p_payload->>'observacion';
    v_tipo   TEXT := COALESCE(p_payload->>'tipo_cancelacion','operacional');
    v_ot_id  UUID;
    v_estado_actual TEXT;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo))=0 THEN RAISE EXCEPTION 'motivo obligatorio'; END IF;
    IF v_tipo NOT IN ('operacional','prueba','mandante','clima','otro') THEN
        RAISE EXCEPTION 'tipo_cancelacion invalido: %', v_tipo;
    END IF;

    SELECT ot_id, estado_plan INTO v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;
    IF v_estado_actual IN ('aceptada','cerrada') THEN
        RAISE EXCEPTION 'Jornada % no se cancela directamente', v_estado_actual;
    END IF;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'cancelada_operacional',
           visible_en_kanban = false,
           requiere_decision_programador = false,
           updated_at = v_now
     WHERE id = v_plan_ot_id;

    -- Cancelar ejecucion activa si existe.
    UPDATE calama_ot_ejecuciones
       SET estado = 'cancelada', finished_at = v_now, updated_at = v_now
     WHERE plan_semanal_ot_id = v_plan_ot_id
       AND estado IN ('en_ejecucion','pausada');

    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id', v_ot_id::text,
        'accion','cancelar',
        'estado_anterior', v_estado_actual,
        'estado_nuevo','cancelada_operacional',
        'motivo', v_motivo, 'observacion', v_obs,
        'metadata', jsonb_build_object('tipo_cancelacion', v_tipo)
    ));

    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_cancelar_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── 8. RPC resetear jornada de prueba (solo admin global) ─────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_resetear_jornada_prueba(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo TEXT := p_payload->>'motivo';
    v_modo   TEXT := COALESCE(p_payload->>'modo','mantener_programada');
    v_confirm TEXT := p_payload->>'confirmacion_texto';
    v_ot_id  UUID;
    v_estado_actual TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_avance_max NUMERIC := 0;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_es_admin_global() THEN
        RAISE EXCEPTION 'Solo admin global puede resetear jornadas de prueba';
    END IF;
    IF v_confirm <> 'RESET' THEN RAISE EXCEPTION 'Debes escribir RESET para confirmar'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo))=0 THEN RAISE EXCEPTION 'motivo obligatorio'; END IF;
    IF v_modo NOT IN ('mantener_programada','devolver_backlog','desprogramar','eliminar_logico') THEN
        RAISE EXCEPTION 'modo invalido: %', v_modo;
    END IF;

    SELECT ot_id, estado_plan INTO v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    -- Detener ejecucion activa.
    UPDATE calama_ot_ejecuciones
       SET estado='cancelada', finished_at=v_now, observacion_cierre=COALESCE(observacion_cierre,'')||' [reset prueba]', updated_at=v_now
     WHERE plan_semanal_ot_id = v_plan_ot_id
       AND estado IN ('en_ejecucion','pausada');

    IF v_modo = 'devolver_backlog' THEN
        DELETE FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    ELSIF v_modo = 'eliminar_logico' THEN
        UPDATE calama_plan_semanal_ots
           SET estado_plan = 'anulada_prueba',
               anulada_at = v_now,
               anulada_by = v_uid,
               motivo_anulacion = v_motivo,
               es_prueba = true,
               visible_en_kanban = false,
               requiere_decision_programador = false,
               llegada_faena_at = NULL,
               llegada_faena_usuario_id = NULL,
               llegada_faena_evidencia_id = NULL,
               llegada_faena_lat = NULL, llegada_faena_lng = NULL,
               llegada_faena_accuracy = NULL, llegada_faena_geo_status = NULL,
               updated_at = v_now
         WHERE id = v_plan_ot_id;
    ELSIF v_modo = 'desprogramar' THEN
        UPDATE calama_plan_semanal_ots
           SET estado_plan = 'desprogramada',
               es_prueba = true,
               desprogramada_at = v_now, desprogramada_by = v_uid,
               motivo_desprogramacion = v_motivo,
               visible_en_kanban = false,
               requiere_decision_programador = false,
               llegada_faena_at = NULL, llegada_faena_usuario_id = NULL,
               llegada_faena_evidencia_id = NULL,
               llegada_faena_lat = NULL, llegada_faena_lng = NULL,
               llegada_faena_accuracy = NULL, llegada_faena_geo_status = NULL,
               updated_at = v_now
         WHERE id = v_plan_ot_id;
    ELSE  -- mantener_programada
        UPDATE calama_plan_semanal_ots
           SET estado_plan = CASE WHEN responsable_id IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
               es_prueba = true,
               requiere_decision_programador = false,
               llegada_faena_at = NULL, llegada_faena_usuario_id = NULL,
               llegada_faena_evidencia_id = NULL,
               llegada_faena_lat = NULL, llegada_faena_lng = NULL,
               llegada_faena_accuracy = NULL, llegada_faena_geo_status = NULL,
               updated_at = v_now
         WHERE id = v_plan_ot_id;
    END IF;

    -- Recalcular avance OT madre desde el max() de jornadas vivas.
    SELECT COALESCE(MAX(avance_final), 0) INTO v_avance_max
      FROM calama_ot_ejecuciones
     WHERE ot_id = v_ot_id AND estado='finalizada';
    UPDATE calama_ordenes_trabajo
       SET avance_pct = LEAST(100, GREATEST(0, COALESCE(v_avance_max,0))),
           updated_at = v_now
     WHERE id = v_ot_id;

    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id', v_ot_id::text,
        'accion','resetear_prueba',
        'estado_anterior', v_estado_actual,
        'estado_nuevo', v_modo,
        'motivo', v_motivo,
        'metadata', jsonb_build_object('modo', v_modo)
    ));

    RETURN jsonb_build_object('success', true, 'modo', v_modo);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_resetear_jornada_prueba(jsonb) TO authenticated;


-- ============================================================================
-- ── 9. RPC eliminar jornada de prueba (admin global) ──────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_eliminar_jornada_prueba(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo TEXT := p_payload->>'motivo';
    v_confirm TEXT := p_payload->>'confirmacion_texto';
    v_ot_id  UUID;
    v_estado_actual TEXT;
    v_firma_real_count INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_es_admin_global() THEN
        RAISE EXCEPTION 'Solo admin global puede eliminar jornadas';
    END IF;
    IF v_confirm <> 'ELIMINAR' THEN RAISE EXCEPTION 'Debes escribir ELIMINAR para confirmar'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo))=0 THEN RAISE EXCEPTION 'motivo obligatorio'; END IF;

    SELECT ot_id, estado_plan INTO v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    -- No permitir eliminar si ya hay firma de mandante real (aceptacion o rechazo).
    SELECT COUNT(*) INTO v_firma_real_count
      FROM calama_firmas_jornada
     WHERE plan_semanal_ot_id = v_plan_ot_id
       AND firmante_tipo = 'mandante';
    IF v_firma_real_count > 0 THEN
        RAISE EXCEPTION 'No se puede eliminar: la jornada tiene firma de mandante (% firmas)', v_firma_real_count;
    END IF;

    -- Auditar antes de borrar.
    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id', v_ot_id::text,
        'accion','eliminar_prueba',
        'estado_anterior', v_estado_actual,
        'estado_nuevo','eliminada',
        'motivo', v_motivo
    ));

    DELETE FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;

    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_eliminar_jornada_prueba(jsonb) TO authenticated;


-- ============================================================================
-- ── 10. RPC registrar llegada a faena ────────────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_registrar_llegada_faena(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_ot_id UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_foto_url TEXT := p_payload->>'foto_llegada_url';
    v_foto_path TEXT := p_payload->>'foto_llegada_storage_path';
    v_lat NUMERIC := NULLIF(p_payload->>'gps_lat','')::NUMERIC;
    v_lng NUMERIC := NULLIF(p_payload->>'gps_lng','')::NUMERIC;
    v_acc NUMERIC := NULLIF(p_payload->>'gps_accuracy','')::NUMERIC;
    v_geo_status TEXT := p_payload->>'geolocation_status';
    v_obs TEXT := p_payload->>'observacion';
    v_client_uuid UUID := NULLIF(p_payload->>'client_uuid','')::UUID;
    v_ot_id UUID;
    v_evid_id UUID;
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url)=0 THEN
        RAISE EXCEPTION 'foto_llegada_url obligatoria';
    END IF;

    SELECT ot_id INTO v_ot_id FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    IF NOT (fn_calama_uid_es_responsable_plan_ot(v_plan_ot_id) OR fn_calama_puede_planificar()) THEN
        RAISE EXCEPTION 'No autorizado';
    END IF;

    INSERT INTO calama_evidencias (
        contexto, tipo, ot_id, plan_semanal_ot_id,
        archivo_url, storage_path, momento,
        gps_lat, gps_lng, gps_accuracy, geolocation_status,
        descripcion, client_uuid, sync_status, created_by
    ) VALUES (
        'llegada_faena','foto', v_ot_id, v_plan_ot_id,
        v_foto_url, v_foto_path, 'llegada',
        v_lat, v_lng, v_acc, v_geo_status,
        v_obs, v_client_uuid, 'sincronizado', v_uid
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_evid_id;

    UPDATE calama_plan_semanal_ots
       SET llegada_faena_at = v_now,
           llegada_faena_usuario_id = v_uid,
           llegada_faena_evidencia_id = COALESCE(v_evid_id, llegada_faena_evidencia_id),
           llegada_faena_lat = v_lat, llegada_faena_lng = v_lng,
           llegada_faena_accuracy = v_acc, llegada_faena_geo_status = v_geo_status,
           updated_at = v_now
     WHERE id = v_plan_ot_id
       AND llegada_faena_at IS NULL;  -- idempotente: no sobreescribe

    RETURN jsonb_build_object(
        'success', true,
        'plan_semanal_ot_id', v_plan_ot_id,
        'evidencia_id', v_evid_id,
        'llegada_faena_at', v_now
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_llegada_faena(jsonb) TO authenticated;


-- ============================================================================
-- ── 11. Modificar rpc_calama_iniciar_jornada (exigir llegada previa) ─────
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
    v_llegada          TIMESTAMPTZ;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id obligatorio'; END IF;
    IF v_foto_url IS NULL OR length(v_foto_url) = 0 THEN
        RAISE EXCEPTION 'foto_antes_url obligatoria para iniciar jornada en terreno';
    END IF;

    SELECT ot_id, llegada_faena_at INTO v_ot_id, v_llegada
      FROM calama_plan_semanal_ots WHERE id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;
    IF v_llegada IS NULL THEN
        RAISE EXCEPTION 'Llegada a faena no registrada. Registra llegada con foto + GPS antes de iniciar.';
    END IF;

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
-- ── 12. Bitacora + verificacion ────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG32_CALAMA_ACCIONES_LLEGADA',
            'MIG32: acciones administrativas (desprogramar/cancelar/resetear/eliminar) + llegada a faena obligatoria.',
            current_user, NOW(), NOW(), 'ok',
            'Tabla calama_jornada_auditoria. RPCs nuevos. Iniciar jornada exige llegada_faena_at.'
        );
    END IF;
END $$;

WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='llegada_faena_at')                  AS llegada_col,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='es_prueba')                         AS es_prueba_col,
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='calama_plan_semanal_ots' AND column_name='visible_en_kanban')                 AS vis_col,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public'
                 AND table_name='calama_jornada_auditoria')                                                    AS audit_tab,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_desprogramar_jornada')                        AS rpc_despr,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_cancelar_jornada')                            AS rpc_canc,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_resetear_jornada_prueba')                     AS rpc_reset,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_eliminar_jornada_prueba')                     AS rpc_elim,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_registrar_llegada_faena')                     AS rpc_lleg,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_calama_audit_jornada')                                AS fn_audit
)
SELECT
    CASE
        WHEN NOT llegada_col   THEN 'STOP_LLEGADA_COL'
        WHEN NOT es_prueba_col THEN 'STOP_ES_PRUEBA_COL'
        WHEN NOT vis_col       THEN 'STOP_VIS_COL'
        WHEN NOT audit_tab     THEN 'STOP_AUDIT_TAB'
        WHEN NOT fn_audit      THEN 'STOP_FN_AUDIT'
        WHEN NOT rpc_despr     THEN 'STOP_RPC_DESPR'
        WHEN NOT rpc_canc      THEN 'STOP_RPC_CANC'
        WHEN NOT rpc_reset     THEN 'STOP_RPC_RESET'
        WHEN NOT rpc_elim      THEN 'STOP_RPC_ELIM'
        WHEN NOT rpc_lleg      THEN 'STOP_RPC_LLEG'
        ELSE 'OK_MIG32_ACCIONES_LLEGADA'
    END AS resultado,
    llegada_col, es_prueba_col, vis_col, audit_tab, fn_audit,
    rpc_despr, rpc_canc, rpc_reset, rpc_elim, rpc_lleg,
    NOW() AS chequeado_en
FROM chk;
