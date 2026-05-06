-- ============================================================================
-- 31_calama_edicion_plan_admin.sql
-- ----------------------------------------------------------------------------
-- Permite a admin / supervisor_calama editar el plan semanal aunque este
-- confirmado. Resuelve el bug multidia donde rpc_calama_mover_ot_plan_semanal
-- y rpc_calama_quitar_ot_plan_semanal usan SELECT INTO por (plan_semanal_id,
-- ot_id) y rompen cuando la OT tiene mas de una jornada (multidia, MIG28).
--
-- Nuevos RPCs que operan por p_plan_ot_id:
--   - rpc_calama_mover_jornada(p_plan_ot_id, p_fecha_destino, p_responsable_id?)
--   - rpc_calama_quitar_jornada(p_plan_ot_id)
--
-- Reglas:
--   - Plan en 'cerrado'/'cancelado' bloquea cambios.
--   - Plan en 'borrador'/'confirmado'/'en_ejecucion' admite cambios para
--     planificadores/admins.
--   - Bloqueo por estado_plan de la jornada individual:
--     en_ejecucion / pausada / finalizada / finalizada_operador /
--     pendiente_aprobacion / aceptada / cerrada => no se mueve ni quita
--     directamente (se reprograma saldo via rpc_calama_reprogramar_saldo_ot).
-- ============================================================================


-- ── 0. PRECHECK ─────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='secuencia_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG28 no aplicada (calama_plan_semanal_ots.secuencia_jornada)';
    END IF;
END $$;


-- ============================================================================
-- ── 1. RPC: mover una jornada concreta (multidia-safe) ─────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_mover_jornada(
    p_plan_ot_id UUID,
    p_fecha_destino DATE,
    p_responsable_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_semanal_id UUID;
    v_ot_id UUID;
    v_estado_actual TEXT;
    v_estado_plan_general TEXT;
    v_dia_id UUID;
    v_zona UUID;
    v_warning TEXT := NULL;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para mover jornada';
    END IF;
    IF p_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_ot_id obligatorio'; END IF;
    IF p_fecha_destino IS NULL THEN RAISE EXCEPTION 'fecha_destino obligatoria'; END IF;

    SELECT plan_semanal_id, ot_id, estado_plan
      INTO v_plan_semanal_id, v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots
     WHERE id = p_plan_ot_id;
    IF v_plan_semanal_id IS NULL THEN RAISE EXCEPTION 'plan_ot_id no encontrado'; END IF;

    -- Bloqueo por estado del plan general.
    SELECT estado INTO v_estado_plan_general FROM calama_planes_semanales WHERE id = v_plan_semanal_id;
    IF v_estado_plan_general IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_estado_plan_general;
    END IF;
    IF v_estado_plan_general = 'confirmado' THEN
        v_warning := 'plan_confirmado_modificacion';
    END IF;

    -- Bloqueo por estado de la jornada individual.
    IF v_estado_actual IN (
        'en_ejecucion','pausada','finalizada','finalizada_operador',
        'pendiente_aprobacion','aceptada','cerrada'
    ) THEN
        RAISE EXCEPTION 'Jornada en estado % no se mueve directamente. Usa "Reprogramar saldo" si corresponde.',
            v_estado_actual;
    END IF;

    -- Resolver dia destino dentro del MISMO plan semanal (no permitir saltar de plan).
    SELECT id INTO v_dia_id
      FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_semanal_id AND fecha = p_fecha_destino;
    IF v_dia_id IS NULL THEN
        RAISE EXCEPTION 'fecha_destino % no pertenece a este plan_semanal_id', p_fecha_destino;
    END IF;

    -- Derivar zona desde el folio (paridad con MIG20).
    SELECT z.id INTO v_zona
      FROM calama_ordenes_trabajo o
      JOIN calama_planificaciones p ON p.id = o.planificacion_id
      LEFT JOIN calama_zonas_proyecto z
             ON z.planificacion_id = p.id
            AND z.codigo_zona = (regexp_match(o.folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0'
     WHERE o.id = v_ot_id LIMIT 1;

    UPDATE calama_plan_semanal_ots
       SET plan_dia_id    = v_dia_id,
           zona_proyecto_id = COALESCE(v_zona, zona_proyecto_id),
           responsable_id = COALESCE(p_responsable_id, responsable_id),
           estado_plan    = CASE
                             WHEN p_responsable_id IS NOT NULL AND estado_plan = 'planificada'
                                THEN 'asignada'
                             ELSE estado_plan
                           END,
           updated_at     = NOW()
     WHERE id = p_plan_ot_id;

    -- Sync responsable a OT madre si llego (paridad MIG24).
    IF p_responsable_id IS NOT NULL THEN
        UPDATE calama_ordenes_trabajo
           SET responsable_id = p_responsable_id, updated_at = NOW()
         WHERE id = v_ot_id
           AND (responsable_id IS DISTINCT FROM p_responsable_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'plan_ot_id', p_plan_ot_id,
        'plan_dia_id', v_dia_id,
        'warning', v_warning
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_mover_jornada(UUID, DATE, UUID) TO authenticated;


-- ============================================================================
-- ── 2. RPC: quitar una jornada concreta (multidia-safe) ────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_quitar_jornada(p_plan_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_semanal_id UUID;
    v_ot_id UUID;
    v_estado_actual TEXT;
    v_estado_plan_general TEXT;
    v_warning TEXT := NULL;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para quitar jornada';
    END IF;
    IF p_plan_ot_id IS NULL THEN RAISE EXCEPTION 'plan_ot_id obligatorio'; END IF;

    SELECT plan_semanal_id, ot_id, estado_plan
      INTO v_plan_semanal_id, v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots
     WHERE id = p_plan_ot_id;
    IF v_plan_semanal_id IS NULL THEN RAISE EXCEPTION 'plan_ot_id no encontrado'; END IF;

    SELECT estado INTO v_estado_plan_general FROM calama_planes_semanales WHERE id = v_plan_semanal_id;
    IF v_estado_plan_general IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_estado_plan_general;
    END IF;
    IF v_estado_plan_general = 'confirmado' THEN
        v_warning := 'plan_confirmado_modificacion';
    END IF;

    IF v_estado_actual IN (
        'en_ejecucion','pausada','finalizada','finalizada_operador',
        'pendiente_aprobacion','aceptada','cerrada'
    ) THEN
        RAISE EXCEPTION 'Jornada en estado % no se quita directamente.', v_estado_actual;
    END IF;

    DELETE FROM calama_plan_semanal_ots WHERE id = p_plan_ot_id;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', p_plan_ot_id, 'warning', v_warning);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_quitar_jornada(UUID) TO authenticated;


-- ============================================================================
-- ── 3. VERIFICACION FINAL ──────────────────────────────────────────────────
-- ============================================================================
WITH chk AS (
    SELECT
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_mover_jornada')   AS rpc_mover,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_quitar_jornada')  AS rpc_quitar
)
SELECT
    CASE
        WHEN NOT rpc_mover  THEN 'STOP_RPC_MOVER_JORNADA'
        WHEN NOT rpc_quitar THEN 'STOP_RPC_QUITAR_JORNADA'
        ELSE 'OK_MIG31_EDICION_PLAN_ADMIN'
    END AS resultado,
    rpc_mover, rpc_quitar,
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
            'PROD_MIG31_CALAMA_EDIT_PLAN',
            'Edicion plan semanal Calama: RPCs por plan_ot_id (multidia-safe), permitir cambios en plan confirmado.',
            current_user, NOW(), NOW(), 'ok',
            'rpc_calama_mover_jornada y rpc_calama_quitar_jornada operan por id de jornada. Solo bloquea cerrado/cancelado y estados de jornada ejecutados/aceptados.'
        );
    END IF;
END $$;
