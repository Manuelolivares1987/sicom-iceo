-- ============================================================================
-- SICOM-ICEO | 153 — Fix rpc_taller_iniciar_ejecucion_ot: columna user_id
-- ============================================================================
-- Error reportado al hacer "play" (iniciar ejecución) en el Plan Semanal Taller:
--   column "user_id" does not exist
--
-- Causa: en MIG 83 (linea 297) la funcion resuelve el ejecutor con:
--   SELECT id INTO v_ejecutor FROM usuarios_perfil WHERE user_id = v_user
-- pero la tabla usuarios_perfil NO tiene columna user_id: su PK `id` ES el
-- auth.uid() (asi lo usan fn_user_rol() y todos los FK -> usuarios_perfil(id)).
--
-- Fix: cambiar el filtro a `WHERE id = v_user`.
-- Reproduce el cuerpo de MIG 83 sin otros cambios. IDEMPOTENTE (CREATE OR REPLACE).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_taller_iniciar_ejecucion_ot(
    p_ot_id      UUID,
    p_observacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_ejecutor UUID;
    v_plan_ot_id UUID;
    v_ejec_id UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT id INTO v_ejecutor FROM usuarios_perfil WHERE id = v_user LIMIT 1;
    IF v_ejecutor IS NULL THEN RAISE EXCEPTION 'Usuario sin perfil'; END IF;

    -- Plan OT mas reciente (multidia: agarra la jornada actual o futura mas cercana)
    SELECT id INTO v_plan_ot_id FROM taller_plan_semanal_ots t
      JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     WHERE t.ot_id = p_ot_id
       AND t.estado_plan IN ('planificada','asignada','liberada','pausada')
     ORDER BY d.fecha ASC, t.secuencia_jornada ASC
     LIMIT 1;

    INSERT INTO taller_ot_ejecuciones(
        ot_id, plan_semanal_ot_id, ejecutor_id, estado, observacion_inicio
    ) VALUES (
        p_ot_id, v_plan_ot_id, v_ejecutor, 'en_ejecucion', p_observacion
    ) RETURNING id INTO v_ejec_id;

    INSERT INTO taller_ot_ejecucion_eventos(
        ejecucion_id, ot_id, tipo, comentario, created_by
    ) VALUES (
        v_ejec_id, p_ot_id, 'start', p_observacion, v_user
    );

    IF v_plan_ot_id IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'en_ejecucion', updated_at = NOW()
         WHERE id = v_plan_ot_id;
    END IF;
    UPDATE ordenes_trabajo SET estado = 'en_ejecucion', fecha_inicio = NOW(), updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id, 'plan_ot_id', v_plan_ot_id);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT) TO authenticated;
