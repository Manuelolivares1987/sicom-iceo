-- ============================================================================
-- 83_taller_plan_semanal_rpcs.sql
-- ----------------------------------------------------------------------------
-- RPCs para operar el plan semanal del taller. Replica patrones de MIG20
-- (Calama plan semanal) adaptados a ordenes_trabajo.
--
-- RPCs creadas:
--   - rpc_taller_get_or_create_plan_semanal(fecha_inicio, faena?)
--   - rpc_taller_agregar_jornada_ot(plan_semanal_id, ot_id, fecha, ...)
--   - rpc_taller_mover_jornada(plan_ot_id, fecha_destino, responsable?)
--   - rpc_taller_quitar_jornada(plan_ot_id)
--   - rpc_taller_asignar_responsable(plan_ot_id, responsable_id, cuadrilla?)
--   - rpc_taller_confirmar_plan_semanal(plan_semanal_id)
--   - rpc_taller_iniciar_ejecucion_ot(ot_id, observacion?)
--   - rpc_taller_pausar_ejecucion(ejecucion_id, motivo)
--   - rpc_taller_reanudar_ejecucion(ejecucion_id)
--   - rpc_taller_finalizar_ejecucion(ejecucion_id, avance_final, observacion?)
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. get_or_create_plan_semanal ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_get_or_create_plan_semanal(
    p_fecha_inicio DATE,
    p_faena_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_plan_id UUID;
    v_fecha_fin DATE;
    v_existe BOOLEAN;
    v_dias_es TEXT[] := ARRAY['lunes','martes','miercoles','jueves','viernes','sabado','domingo'];
    i INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_fecha_inicio IS NULL THEN RAISE EXCEPTION 'fecha_inicio obligatoria'; END IF;
    IF EXTRACT(DOW FROM p_fecha_inicio) <> 1 THEN
        RAISE EXCEPTION 'fecha_inicio debe ser lunes (DOW=1). Recibido: %', EXTRACT(DOW FROM p_fecha_inicio);
    END IF;
    v_fecha_fin := p_fecha_inicio + INTERVAL '6 days';

    SELECT id INTO v_plan_id
      FROM taller_planes_semanales
     WHERE fecha_inicio_semana = p_fecha_inicio
       AND faena_id IS NOT DISTINCT FROM p_faena_id;
    v_existe := v_plan_id IS NOT NULL;

    IF NOT v_existe THEN
        INSERT INTO taller_planes_semanales(
            faena_id, fecha_inicio_semana, fecha_fin_semana, estado, creado_por
        ) VALUES (
            p_faena_id, p_fecha_inicio, v_fecha_fin, 'borrador', v_user
        ) RETURNING id INTO v_plan_id;

        FOR i IN 0..6 LOOP
            INSERT INTO taller_plan_semanal_dias(
                plan_semanal_id, fecha, nombre_dia, orden, estado
            ) VALUES (
                v_plan_id, p_fecha_inicio + i, v_dias_es[i+1], i+1, 'borrador'
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'plan_semanal_id', v_plan_id,
        'fecha_inicio', p_fecha_inicio,
        'fecha_fin', v_fecha_fin,
        'creado_nuevo', NOT v_existe
    );
END;
$$;


-- ── 2. agregar_jornada_ot (multidia: misma OT en varios dias) ──────────────
CREATE OR REPLACE FUNCTION rpc_taller_agregar_jornada_ot(
    p_plan_semanal_id  UUID,
    p_ot_id            UUID,
    p_fecha            DATE,
    p_responsable_id   UUID    DEFAULT NULL,
    p_cuadrilla        VARCHAR DEFAULT NULL,
    p_horas_planificadas NUMERIC DEFAULT NULL,
    p_avance_objetivo  NUMERIC DEFAULT NULL,
    p_observaciones    TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_dia_id UUID;
    v_plan_ot_id UUID;
    v_secuencia INT;
    v_rol TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para planificar taller', v_rol;
    END IF;

    SELECT id INTO v_dia_id FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha;
    IF v_dia_id IS NULL THEN
        RAISE EXCEPTION 'Fecha % no pertenece al plan_semanal %', p_fecha, p_plan_semanal_id;
    END IF;

    -- Secuencia incremental por (plan, ot)
    SELECT COALESCE(MAX(secuencia_jornada), 0) + 1
      INTO v_secuencia
      FROM taller_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    INSERT INTO taller_plan_semanal_ots(
        plan_semanal_id, plan_dia_id, ot_id, responsable_id, cuadrilla,
        horas_planificadas, avance_objetivo_pct, secuencia_jornada,
        estado_plan, observaciones, created_by
    ) VALUES (
        p_plan_semanal_id, v_dia_id, p_ot_id, p_responsable_id, p_cuadrilla,
        p_horas_planificadas, p_avance_objetivo, v_secuencia,
        CASE WHEN p_responsable_id IS NULL THEN 'planificada' ELSE 'asignada' END,
        p_observaciones, v_user
    )
    ON CONFLICT (plan_semanal_id, ot_id, plan_dia_id) DO UPDATE
       SET responsable_id    = EXCLUDED.responsable_id,
           cuadrilla         = EXCLUDED.cuadrilla,
           horas_planificadas = EXCLUDED.horas_planificadas,
           avance_objetivo_pct = EXCLUDED.avance_objetivo_pct,
           observaciones     = COALESCE(EXCLUDED.observaciones, taller_plan_semanal_ots.observaciones),
           updated_at        = NOW()
    RETURNING id INTO v_plan_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'plan_ot_id', v_plan_ot_id,
        'secuencia', v_secuencia
    );
END;
$$;


-- ── 3. mover_jornada (cambia fecha y/o responsable de una jornada) ─────────
CREATE OR REPLACE FUNCTION rpc_taller_mover_jornada(
    p_plan_ot_id     UUID,
    p_fecha_destino  DATE,
    p_responsable_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_plan_id UUID; v_dia_destino UUID; v_estado VARCHAR;
    v_rol TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT plan_semanal_id, estado_plan INTO v_plan_id, v_estado
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;
    IF v_estado IN ('en_ejecucion','finalizada') THEN
        RAISE EXCEPTION 'No se puede mover jornada en estado %', v_estado;
    END IF;

    SELECT id INTO v_dia_destino FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_id AND fecha = p_fecha_destino;
    IF v_dia_destino IS NULL THEN
        RAISE EXCEPTION 'Fecha % no pertenece al plan', p_fecha_destino;
    END IF;

    UPDATE taller_plan_semanal_ots
       SET plan_dia_id = v_dia_destino,
           responsable_id = COALESCE(p_responsable_id, responsable_id),
           estado_plan = CASE
             WHEN COALESCE(p_responsable_id, responsable_id) IS NOT NULL
              AND estado_plan = 'planificada' THEN 'asignada'
             ELSE estado_plan
           END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- ── 4. quitar_jornada ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_quitar_jornada(p_plan_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid(); v_estado VARCHAR; v_rol TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;
    SELECT estado_plan INTO v_estado FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;
    IF v_estado IN ('en_ejecucion','finalizada') THEN
        RAISE EXCEPTION 'No se puede quitar jornada en estado %', v_estado;
    END IF;
    DELETE FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    RETURN jsonb_build_object('success', true);
END;
$$;


-- ── 5. asignar_responsable ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_asignar_responsable(
    p_plan_ot_id     UUID,
    p_responsable_id UUID,
    p_cuadrilla      VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_rol TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;
    UPDATE taller_plan_semanal_ots
       SET responsable_id = p_responsable_id,
           cuadrilla = COALESCE(p_cuadrilla, cuadrilla),
           estado_plan = CASE WHEN estado_plan = 'planificada' THEN 'asignada' ELSE estado_plan END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;
    RETURN jsonb_build_object('success', true);
END;
$$;


-- ── 6. confirmar_plan_semanal ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_confirmar_plan_semanal(p_plan_semanal_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT; v_ots INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;
    UPDATE taller_planes_semanales
       SET estado = 'confirmado',
           confirmado_por = v_user,
           confirmado_at = NOW(),
           updated_at = NOW()
     WHERE id = p_plan_semanal_id AND estado = 'borrador';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Plan % no existe o ya no esta en borrador', p_plan_semanal_id;
    END IF;
    SELECT COUNT(*) INTO v_ots FROM taller_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id;
    RETURN jsonb_build_object('success', true, 'ots_confirmadas', v_ots);
END;
$$;


-- ── 7. iniciar_ejecucion_ot ────────────────────────────────────────────────
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
    SELECT id INTO v_ejecutor FROM usuarios_perfil WHERE user_id = v_user LIMIT 1;
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


-- ── 8. pausar_ejecucion ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_pausar_ejecucion(
    p_ejecucion_id UUID,
    p_motivo       VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_ot UUID; v_plan_ot UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT estado, last_event_at, ot_id, plan_semanal_ot_id
      INTO v_estado, v_last, v_ot, v_plan_ot
      FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no existe'; END IF;
    IF v_estado <> 'en_ejecucion' THEN
        RAISE EXCEPTION 'No se puede pausar en estado %', v_estado;
    END IF;
    v_delta := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);
    UPDATE taller_ot_ejecuciones
       SET estado = 'pausada',
           tiempo_efectivo_segundos = tiempo_efectivo_segundos + v_delta,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;
    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, motivo, created_by)
    VALUES (p_ejecucion_id, v_ot, 'pause', p_motivo, v_user);
    IF v_plan_ot IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'pausada', updated_at = NOW()
         WHERE id = v_plan_ot;
    END IF;
    RETURN jsonb_build_object('success', true, 'delta_segundos', v_delta);
END;
$$;


-- ── 9. reanudar_ejecucion ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_reanudar_ejecucion(p_ejecucion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_ot UUID; v_plan_ot UUID; v_motivo VARCHAR;
    v_es_colacion BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT estado, last_event_at, ot_id, plan_semanal_ot_id
      INTO v_estado, v_last, v_ot, v_plan_ot
      FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    IF v_estado <> 'pausada' THEN
        RAISE EXCEPTION 'No se puede reanudar en estado %', v_estado;
    END IF;
    v_delta := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);
    -- Detectar si la pausa anterior fue por "colacion"
    SELECT motivo INTO v_motivo FROM taller_ot_ejecucion_eventos
     WHERE ejecucion_id = p_ejecucion_id AND tipo = 'pause'
     ORDER BY created_at DESC LIMIT 1;
    v_es_colacion := LOWER(COALESCE(v_motivo, '')) LIKE '%colacion%';

    UPDATE taller_ot_ejecuciones
       SET estado = 'en_ejecucion',
           tiempo_pausado_segundos = CASE WHEN NOT v_es_colacion
                                          THEN tiempo_pausado_segundos + v_delta
                                          ELSE tiempo_pausado_segundos END,
           tiempo_colacion_segundos = CASE WHEN v_es_colacion
                                           THEN tiempo_colacion_segundos + v_delta
                                           ELSE tiempo_colacion_segundos END,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;
    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, created_by)
    VALUES (p_ejecucion_id, v_ot, 'resume', v_user);
    IF v_plan_ot IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'en_ejecucion', updated_at = NOW()
         WHERE id = v_plan_ot;
    END IF;
    RETURN jsonb_build_object('success', true, 'colacion', v_es_colacion);
END;
$$;


-- ── 10. finalizar_ejecucion ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_finalizar_ejecucion(
    p_ejecucion_id UUID,
    p_avance_final NUMERIC DEFAULT 100,
    p_observacion  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_started TIMESTAMPTZ; v_ot UUID; v_plan_ot UUID;
    v_t_efectivo INT; v_t_pausado INT; v_t_colacion INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT estado, last_event_at, started_at, ot_id, plan_semanal_ot_id,
           tiempo_efectivo_segundos, tiempo_pausado_segundos, tiempo_colacion_segundos
      INTO v_estado, v_last, v_started, v_ot, v_plan_ot,
           v_t_efectivo, v_t_pausado, v_t_colacion
      FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no existe'; END IF;
    IF v_estado IN ('finalizada','cancelada') THEN
        RAISE EXCEPTION 'Ejecucion ya esta %', v_estado;
    END IF;
    IF v_estado = 'en_ejecucion' THEN
        v_delta := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);
        v_t_efectivo := v_t_efectivo + v_delta;
    END IF;
    UPDATE taller_ot_ejecuciones
       SET estado = 'finalizada',
           finished_at = NOW(),
           tiempo_efectivo_segundos = v_t_efectivo,
           tiempo_total_segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_started))::INT),
           avance_final = p_avance_final,
           observacion_cierre = p_observacion,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;
    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, avance, comentario, created_by)
    VALUES (p_ejecucion_id, v_ot, 'finish', p_avance_final, p_observacion, v_user);
    IF v_plan_ot IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'finalizada', updated_at = NOW()
         WHERE id = v_plan_ot;
    END IF;
    UPDATE ordenes_trabajo
       SET estado = CASE WHEN p_avance_final >= 100 THEN 'ejecutada_ok' ELSE 'ejecutada_con_observaciones' END,
           fecha_termino = NOW(),
           horas_hombre = COALESCE(horas_hombre, 0) + (v_t_efectivo::NUMERIC / 3600.0),
           updated_at = NOW()
     WHERE id = v_ot;
    RETURN jsonb_build_object(
        'success', true,
        'tiempo_efectivo_seg', v_t_efectivo,
        'tiempo_pausado_seg', v_t_pausado,
        'tiempo_colacion_seg', v_t_colacion,
        'avance_final', p_avance_final
    );
END;
$$;


-- ── GRANTs ──────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION rpc_taller_get_or_create_plan_semanal(DATE, UUID)            TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_agregar_jornada_ot(UUID, UUID, DATE, UUID, VARCHAR, NUMERIC, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_mover_jornada(UUID, DATE, UUID)                    TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_quitar_jornada(UUID)                               TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_asignar_responsable(UUID, UUID, VARCHAR)           TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_confirmar_plan_semanal(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_pausar_ejecucion(UUID, VARCHAR)                    TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_reanudar_ejecucion(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_finalizar_ejecucion(UUID, NUMERIC, TEXT)           TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname LIKE 'rpc_taller_%';
    IF v_count < 10 THEN
        RAISE EXCEPTION 'STOP - faltan RPCs taller_*. Creadas: %', v_count;
    END IF;
    RAISE NOTICE '== MIG83 OK == % RPCs taller_* instaladas', v_count;
END $$;

NOTIFY pgrst, 'reload schema';
