-- ============================================================================
-- MIG448 · El cronómetro dice quién lo apretó
-- ============================================================================
--
-- MIG446 dejó la columna `taller_ot_ejecuciones.tecnico_id` porque sin ella el
-- reparto proporcional del bono es imposible: los nueve técnicos comparten la
-- cuenta `operador_taller`, así que `ejecutor_id` es la misma persona para
-- todos. El nombre que cada uno elige en la app («Soy: Joel Coo») vive en el
-- localStorage de su teléfono y nunca llegaba al registro.
--
-- Esta migración abre el camino para que ese nombre viaje: quien inicia una
-- ejecución declara qué técnico es, y eso queda escrito en la ejecución.
--
-- Y aprovecha el mismo acto para cerrar el otro hueco: si el técnico no estaba
-- en la cuadrilla de esa jornada, se agrega al iniciar. Es la declaración más
-- confiable que existe —la hace la persona que va a trabajar, en el momento en
-- que empieza— y sigue siendo ANTES del trabajo, que es lo que pidió Manuel.
-- Una vez ejecutada la OT, el trigger de MIG446 congela la cuadrilla.
--
-- OJO CON LA FIRMA
-- El parámetro nuevo va con DEFAULT y la firma vieja de dos argumentos se
-- ELIMINA. No se pueden dejar las dos: una llamada de dos argumentos calzaría
-- con ambas y Postgres responde «is not unique», que es exactamente lo que
-- rompió la primera versión de MIG442. Con una sola firma, la app publicada
-- —que llama con dos— resuelve al DEFAULT y sigue funcionando igual.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS rpc_taller_iniciar_ejecucion_ot(UUID, TEXT);

CREATE OR REPLACE FUNCTION rpc_taller_iniciar_ejecucion_ot(
    p_ot_id      UUID,
    p_observacion TEXT DEFAULT NULL,
    p_tecnico_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user       UUID := auth.uid();
    v_ejecutor   UUID;
    v_plan_ot_id UUID;
    v_ejec_id    UUID;
    v_tec_ok     BOOLEAN := FALSE;
    v_sumado     BOOLEAN := FALSE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT id INTO v_ejecutor FROM usuarios_perfil WHERE id = v_user LIMIT 1;
    IF v_ejecutor IS NULL THEN RAISE EXCEPTION 'Usuario sin perfil'; END IF;

    IF p_tecnico_id IS NOT NULL THEN
        SELECT COALESCE(activo, TRUE) INTO v_tec_ok FROM taller_tecnicos WHERE id = p_tecnico_id;
        IF NOT COALESCE(v_tec_ok, FALSE) THEN
            RAISE EXCEPTION 'El técnico indicado no existe o está inactivo.';
        END IF;
    END IF;

    -- Plan OT mas reciente (multidia: agarra la jornada actual o futura mas cercana)
    SELECT t.id INTO v_plan_ot_id FROM taller_plan_semanal_ots t
      JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     WHERE t.ot_id = p_ot_id
       AND t.estado_plan IN ('planificada','asignada','liberada','pausada')
     ORDER BY d.fecha ASC, t.secuencia_jornada ASC
     LIMIT 1;

    INSERT INTO taller_ot_ejecuciones(
        ot_id, plan_semanal_ot_id, ejecutor_id, tecnico_id, estado, observacion_inicio
    ) VALUES (
        p_ot_id, v_plan_ot_id, v_ejecutor, p_tecnico_id, 'en_ejecucion', p_observacion
    ) RETURNING id INTO v_ejec_id;

    INSERT INTO taller_ot_ejecucion_eventos(
        ejecucion_id, ot_id, tipo, comentario, created_by
    ) VALUES (
        v_ejec_id, p_ot_id, 'start', p_observacion, v_user
    );

    -- El que empieza a trabajar queda en la cuadrilla de esa jornada. Si ya
    -- estaba, no pasa nada; si no había nadie, entra como titular.
    IF p_tecnico_id IS NOT NULL AND v_plan_ot_id IS NOT NULL THEN
        INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol, declarada_por, origen)
        SELECT v_plan_ot_id, p_tecnico_id,
               CASE WHEN EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = v_plan_ot_id)
                    THEN 'apoyo' ELSE 'titular' END,
               v_user, 'manual'
        ON CONFLICT (plan_ot_id, tecnico_id) DO NOTHING;
        GET DIAGNOSTICS v_sumado = ROW_COUNT;
    END IF;

    IF v_plan_ot_id IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'en_ejecucion', updated_at = NOW()
         WHERE id = v_plan_ot_id;
    END IF;
    UPDATE ordenes_trabajo SET estado = 'en_ejecucion', fecha_inicio = NOW(), updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'ejecucion_id', v_ejec_id,
        'plan_ot_id', v_plan_ot_id,
        'tecnico_id', p_tecnico_id,
        'sumado_a_cuadrilla', COALESCE(v_sumado, FALSE)
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) TO authenticated;

-- ── El catálogo de técnicos, para que la app pueda resolver el nombre ───────
CREATE OR REPLACE FUNCTION rpc_taller_tecnicos_activos()
RETURNS TABLE (id UUID, nombre TEXT, operacion TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT t.id, t.nombre::TEXT, t.operacion::TEXT
      FROM taller_tecnicos t
     WHERE COALESCE(t.activo, TRUE)
     ORDER BY t.nombre;
$$;

REVOKE ALL ON FUNCTION rpc_taller_tecnicos_activos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_tecnicos_activos() TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; v_args TEXT; v_tec INT;
BEGIN
    SELECT count(*), string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
      INTO v_n, v_args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_taller_iniciar_ejecucion_ot';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FALLO: debe quedar UNA firma o la llamada se vuelve ambigua; hay % (%)', v_n, v_args;
    END IF;
    RAISE NOTICE 'iniciar_ejecucion_ot OK: una sola firma (%)', v_args;

    SELECT count(*) INTO v_tec FROM rpc_taller_tecnicos_activos();
    RAISE NOTICE 'técnicos activos que la app puede elegir: %', v_tec;

    SELECT count(*) INTO v_tec FROM taller_ot_ejecuciones WHERE tecnico_id IS NOT NULL;
    RAISE NOTICE 'ejecuciones con técnico declarado hoy: % (empieza en cero, es lo esperado)', v_tec;
END
$mig$;

COMMIT;
