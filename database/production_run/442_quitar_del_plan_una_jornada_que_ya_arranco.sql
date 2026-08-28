-- ============================================================================
-- MIG442 · Quitar del plan una jornada que ya arrancó
-- ============================================================================
--
-- El planificador mete al plan una OT que viene arrastrada de semanas
-- anteriores, se da cuenta de que no va, y no la puede sacar.
--
-- Dos casos distintos, los dos mudos:
--
--   · estado_plan = 'en_ejecucion' (10 jornadas, 7 de arrastre)
--     El botón de quitar SE VE, y al apretarlo el RPC contesta
--     «No se puede quitar jornada en estado en_ejecucion». Nada explica qué
--     hacer.
--
--   · estado_plan = 'finalizada' (8 jornadas, 6 de arrastre)
--     El botón directamente NO EXISTE en la tarjeta. El planificador lo busca
--     y no está.
--
-- La regla vieja además era incoherente: una jornada 'pausada' —que también
-- tiene trabajo registrado— sí se podía quitar. O sea, no protegía el dato:
-- protegía el momento.
--
-- Lo que se decidió con operaciones:
--
--   · EN EJECUCIÓN → se puede quitar, deteniendo primero. La ejecución se
--     cancela dejando escrito el tiempo trabajado hasta ese momento, y la OT
--     NO se cierra: sigue abierta y vuelve a «Viene de semanas anteriores».
--     Hay que pedirlo explícitamente (p_detener), para que nadie borre una
--     jornada andando por accidente.
--
--   · FINALIZADA → no se saca. El trabajo ya se hizo y esa jornada es el
--     historial de la semana; sacarla haría mentir al cumplimiento. Lo que
--     cambia es que ahora el mensaje lo dice.
--
-- Ojo con lo que se pierde: `taller_plan_jornada_eventos` cuelga de la jornada
-- con ON DELETE CASCADE, así que la bitácora de play/pausa de ESA jornada se
-- va con ella. El registro de la ejecución en sí sobrevive: su FK al plan es
-- ON DELETE SET NULL.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_quitar_jornada(
    p_plan_ot_id UUID,
    p_detener    BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_estado    VARCHAR;
    v_rol       TEXT;
    v_ejec      UUID;
    v_ejec_est  VARCHAR;
    v_last      TIMESTAMPTZ;
    v_started   TIMESTAMPTZ;
    v_ot        UUID;
    v_efectivo  INT;
    v_detenida  BOOLEAN := FALSE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    -- [MIG261] quien planifica también puede sacar del plan lo que no va.
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT estado_plan INTO v_estado FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;

    -- Lo hecho, hecho está.
    IF v_estado = 'finalizada' THEN
        RAISE EXCEPTION 'Esta jornada ya se finalizó: es parte del historial del plan y no se saca.';
    END IF;

    IF v_estado = 'en_ejecucion' AND NOT p_detener THEN
        RAISE EXCEPTION 'Esta jornada está en ejecución. Hay que detenerla para sacarla del plan.';
    END IF;

    -- Detener: la ejecución se cancela con su tiempo escrito. La OT no se
    -- cierra —el trabajo no terminó, se sacó del plan— así que vuelve sola a
    -- la lista de arrastre de la semana siguiente.
    IF v_estado = 'en_ejecucion' AND p_detener THEN
        SELECT e.id, e.estado, e.last_event_at, e.started_at, e.ot_id,
               COALESCE(e.tiempo_efectivo_segundos, 0)
          INTO v_ejec, v_ejec_est, v_last, v_started, v_ot, v_efectivo
          FROM taller_ot_ejecuciones e
         WHERE e.plan_semanal_ot_id = p_plan_ot_id
           AND e.estado IN ('en_ejecucion','pausada')
         ORDER BY e.started_at DESC
         LIMIT 1;

        IF v_ejec IS NOT NULL THEN
            IF v_ejec_est = 'en_ejecucion' THEN
                v_efectivo := v_efectivo + GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);
            END IF;

            UPDATE taller_ot_ejecuciones
               SET estado                   = 'cancelada',
                   finished_at              = NOW(),
                   tiempo_efectivo_segundos = v_efectivo,
                   tiempo_total_segundos    = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_started))::INT),
                   observacion_cierre       = 'Detenida al quitar la jornada del plan semanal',
                   last_event_at            = NOW(),
                   updated_at               = NOW()
             WHERE id = v_ejec;

            INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, created_by)
            VALUES (v_ejec, v_ot, 'cancel', 'La jornada se quitó del plan semanal', v_user);

            v_detenida := TRUE;
        END IF;
    END IF;

    DELETE FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'detenida', v_detenida,
        'estado_previo', v_estado
    );
END;
$$;

COMMENT ON FUNCTION rpc_taller_quitar_jornada(UUID, BOOLEAN) IS
'Saca una jornada del plan semanal. Una jornada en ejecución exige p_detener y se cancela dejando el tiempo escrito, sin cerrar la OT; una finalizada no se saca (MIG442).';

REVOKE ALL ON FUNCTION rpc_taller_quitar_jornada(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_taller_quitar_jornada(UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION rpc_taller_quitar_jornada(UUID, BOOLEAN) TO authenticated;

-- La versión vieja de un solo argumento se ELIMINA. No se puede dejar viva
-- junto a la nueva: con `p_detener` teniendo DEFAULT, una llamada de un solo
-- argumento calza con las dos y Postgres responde
-- «function rpc_taller_quitar_jornada(uuid) is not unique».
--
-- Eso rompería la pestaña que ya está abierta con el bundle publicado, que
-- llama con un solo argumento. Con una sola firma, esa misma llamada resuelve
-- al DEFAULT FALSE y sigue funcionando igual que antes.
DROP FUNCTION IF EXISTS rpc_taller_quitar_jornada(UUID);

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_n    INT;
    v_args TEXT;
BEGIN
    SELECT count(*), string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
      INTO v_n, v_args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_taller_quitar_jornada';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FALLO: debe quedar UNA sola firma o la llamada se vuelve ambigua; hay % (%)', v_n, v_args;
    END IF;
    RAISE NOTICE 'rpc_taller_quitar_jornada OK: una sola firma (%)', v_args;
END
$mig$;

COMMIT;
