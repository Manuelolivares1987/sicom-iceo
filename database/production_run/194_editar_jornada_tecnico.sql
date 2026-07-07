-- ============================================================================
-- SICOM-ICEO | 194 — "Responsable" del detalle de OT del Plan Taller usa el
--                    catálogo de técnicos (mismo selector que el planificador)
-- ============================================================================
-- Bug reportado por Manuel (2026-07-07): en Plan Taller → editar orden, el
-- campo Responsable decía "Sin asignar" aunque el plan ya tenía a Sergio
-- Cortes, y el desplegable mostraba OTRA lista de personas.
-- Causa: el selector apuntaba a usuarios_perfil (cuentas de la plataforma)
-- mientras el planificador asigna técnicos del catálogo taller_tecnicos
-- (Sergio Cortes no tiene cuenta → jamás podía aparecer).
--
-- Fix: rpc_taller_editar_jornada acepta p_tecnico_id (taller_tecnicos):
--   * guarda taller_plan_semanal_ots.tecnico_id (columna de MIG182)
--   * deriva responsable_id/OT.responsable_id de la cuenta vinculada del
--     técnico (usuario_perfil_id) si la tiene — así el operador con login
--     ve la OT como suya (fn_taller_ot_asignada_al_usuario, MIG192/193)
--   * exige motivo si el plan está confirmado y cambia el técnico (MIG173)
--   * bitácora: evento cambio_responsable con campo='tecnico' y nombres
-- Se conserva p_responsable_id para compatibilidad (gana sobre el derivado).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='taller_plan_semanal_ots' AND column_name='tecnico_id') THEN
        RAISE EXCEPTION 'STOP — falta taller_plan_semanal_ots.tecnico_id (MIG182).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_taller_log_jornada_evento') THEN
        RAISE EXCEPTION 'STOP — falta fn_taller_log_jornada_evento (MIG173).';
    END IF;
END $$;


-- ── 1. RPC con p_tecnico_id ──────────────────────────────────────────────────
-- DROP + CREATE (no OR REPLACE) porque cambia la firma; el parámetro nuevo
-- tiene DEFAULT NULL, así las llamadas del frontend antiguo siguen resolviendo.
DROP FUNCTION IF EXISTS rpc_taller_editar_jornada(uuid, uuid, character varying, numeric, numeric, text, boolean, text);

CREATE FUNCTION rpc_taller_editar_jornada(
    p_plan_ot_id          UUID,
    p_responsable_id      UUID    DEFAULT NULL,
    p_cuadrilla           VARCHAR DEFAULT NULL,
    p_horas_planificadas  NUMERIC DEFAULT NULL,
    p_avance_objetivo     NUMERIC DEFAULT NULL,
    p_observaciones       TEXT    DEFAULT NULL,
    p_sync_responsable_ot BOOLEAN DEFAULT TRUE,
    p_motivo              TEXT    DEFAULT NULL,
    p_tecnico_id          UUID    DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_ot   UUID; v_plan UUID; v_conf BOOLEAN;
    v_resp_old UUID; v_cuad_old VARCHAR; v_horas_old NUMERIC; v_tec_old UUID;
    v_resp_from_tec UUID;
    v_resp_nuevo UUID;
    v_cambia_personal BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para editar la jornada (rol: %)', v_rol;
    END IF;

    SELECT ot_id, plan_semanal_id, responsable_id, cuadrilla, horas_planificadas, tecnico_id
      INTO v_ot, v_plan, v_resp_old, v_cuad_old, v_horas_old, v_tec_old
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'Jornada no existe'; END IF;

    -- Cuenta vinculada del técnico (si la tiene) para derivar el responsable.
    IF p_tecnico_id IS NOT NULL THEN
        SELECT usuario_perfil_id INTO v_resp_from_tec
          FROM taller_tecnicos WHERE id = p_tecnico_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Técnico no existe en el catálogo'; END IF;
    END IF;
    v_resp_nuevo := COALESCE(p_responsable_id, v_resp_from_tec);

    v_conf := fn_taller_plan_confirmado(v_plan);
    v_cambia_personal :=
        (p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old)
     OR (p_cuadrilla     IS NOT NULL AND p_cuadrilla     IS DISTINCT FROM v_cuad_old)
     OR (p_tecnico_id    IS NOT NULL AND p_tecnico_id    IS DISTINCT FROM v_tec_old);

    -- Si el plan esta confirmado y cambia el personal, exigir motivo.
    IF v_conf AND v_cambia_personal AND COALESCE(TRIM(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO: el plan esta confirmado; indica por que cambia el personal asignado.';
    END IF;

    UPDATE taller_plan_semanal_ots
       SET tecnico_id         = COALESCE(p_tecnico_id, tecnico_id),
           responsable_id     = COALESCE(v_resp_nuevo, responsable_id),
           cuadrilla          = COALESCE(p_cuadrilla, cuadrilla),
           horas_planificadas = COALESCE(p_horas_planificadas, horas_planificadas),
           avance_objetivo_pct= COALESCE(p_avance_objetivo, avance_objetivo_pct),
           estado_plan        = CASE WHEN estado_plan = 'planificada'
                                       AND (COALESCE(v_resp_nuevo, responsable_id) IS NOT NULL
                                            OR COALESCE(p_tecnico_id, tecnico_id) IS NOT NULL)
                                     THEN 'asignada' ELSE estado_plan END,
           observaciones      = COALESCE(p_observaciones, observaciones),
           updated_at         = NOW()
     WHERE id = p_plan_ot_id;

    IF p_sync_responsable_ot AND v_resp_nuevo IS NOT NULL THEN
        UPDATE ordenes_trabajo SET responsable_id = v_resp_nuevo, updated_at = NOW()
         WHERE id = v_ot;
    END IF;

    -- Bitacora
    IF p_tecnico_id IS NOT NULL AND p_tecnico_id IS DISTINCT FROM v_tec_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_campo := 'tecnico',
            p_valor_anterior := (SELECT nombre FROM taller_tecnicos WHERE id = v_tec_old),
            p_valor_nuevo    := (SELECT nombre FROM taller_tecnicos WHERE id = p_tecnico_id));
    ELSIF p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_responsable_anterior := v_resp_old, p_responsable_nuevo := p_responsable_id);
    END IF;
    IF p_cuadrilla IS NOT NULL AND p_cuadrilla IS DISTINCT FROM v_cuad_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_cuadrilla', p_motivo,
            p_cuadrilla_anterior := v_cuad_old, p_cuadrilla_nueva := p_cuadrilla);
    END IF;
    IF p_horas_planificadas IS NOT NULL AND p_horas_planificadas IS DISTINCT FROM v_horas_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_horas', p_motivo,
            p_campo := 'horas_planificadas',
            p_valor_anterior := v_horas_old::TEXT, p_valor_nuevo := p_horas_planificadas::TEXT);
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', p_plan_ot_id, 'ot_id', v_ot);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_taller_editar_jornada(uuid, uuid, character varying, numeric, numeric, text, boolean, text, uuid) TO authenticated;

COMMENT ON FUNCTION rpc_taller_editar_jornada(uuid, uuid, character varying, numeric, numeric, text, boolean, text, uuid) IS
    'Edita la jornada del plan taller. p_tecnico_id (catálogo taller_tecnicos) asigna el responsable técnico y deriva responsable_id de su cuenta vinculada. MIG194.';


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rpc_con_tecnico', (SELECT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname='rpc_taller_editar_jornada'
          AND pg_get_function_identity_arguments(oid) LIKE '%p_tecnico_id%')),
    'sin_firma_vieja', (SELECT COUNT(*) = 1 FROM pg_proc WHERE proname='rpc_taller_editar_jornada')
) AS resultado;

NOTIFY pgrst, 'reload schema';
