-- ============================================================================
-- MIG443 · La OT que nació al programar no queda huérfana
-- ============================================================================
--
-- Arrastrar una patente a un día hace DOS cosas:
--   1. programar_ot_taller CREA una OT — artefacto permanente, con folio.
--   2. agregar_jornada la pone en el plan — artefacto de la semana.
--
-- «Quitar del plan» sólo deshacía la segunda. La OT quedaba viva, en estado
-- 'creada', sin trabajo y sin plan, y nadie la borraba nunca.
--
-- El caso que lo destapó: OT-202608-00008 (CC-44-04 / FJTJ-61), creada el
-- 28-ago al programar el camión, sacada del plan el mismo día, y ahí seguía.
--
-- Medido antes de tocar nada:
--   · 17 OTs huérfanas desde el 3 de junio (13 preventivas), ~2 por semana
--   · las 17 aparecen en «Viene de semanas anteriores»: 17 de 47 entradas,
--     el 36% de la lista que el planificador usa para decidir qué retomar
--   · ninguna tiene NC vinculadas ni materiales imputados
--
-- Lo que se hace:
--
--   A. Al sacar del plan la ÚLTIMA jornada de una OT que nunca se trabajó, la
--      OT se descarta sola, con el motivo escrito. Se reusa exactamente la
--      forma de rpc_taller_descartar_ot, incluidos sus resguardos.
--
--   B. Las 17 que ya están se descartan de una vez.
--
-- Lo que NO se descarta solo, a propósito:
--   · una OT con NC vinculadas — viene de un hallazgo, no de programar un
--     camión, y su lugar es la bandeja de NC por agendar
--   · una OT con materiales imputados desde bodega — eso se cierra, no se tira
--   · una OT con cualquier ejecución registrada, aunque sea de un minuto
-- ============================================================================

BEGIN;

-- ── A · Al quitar la última jornada ─────────────────────────────────────────
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
    v_nombre    TEXT;
    v_ejec      UUID;
    v_ejec_est  VARCHAR;
    v_last      TIMESTAMPTZ;
    v_started   TIMESTAMPTZ;
    v_ot        UUID;
    v_folio     TEXT;
    v_ot_estado VARCHAR;
    v_efectivo  INT;
    v_detenida  BOOLEAN := FALSE;
    v_descart   TEXT := NULL;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    -- [MIG261] quien planifica también puede sacar del plan lo que no va.
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT po.estado_plan, po.ot_id INTO v_estado, v_ot
      FROM taller_plan_semanal_ots po WHERE po.id = p_plan_ot_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;

    -- Lo hecho, hecho está.
    IF v_estado = 'finalizada' THEN
        RAISE EXCEPTION 'Esta jornada ya se finalizó: es parte del historial del plan y no se saca.';
    END IF;

    IF v_estado = 'en_ejecucion' AND NOT p_detener THEN
        RAISE EXCEPTION 'Esta jornada está en ejecución. Hay que detenerla para sacarla del plan.';
    END IF;

    -- [MIG442] Detener: la ejecución se cancela con su tiempo escrito. La OT no
    -- se cierra —el trabajo no terminó, se sacó del plan— así que vuelve sola a
    -- la lista de arrastre de la semana siguiente.
    IF v_estado = 'en_ejecucion' AND p_detener THEN
        SELECT e.id, e.estado, e.last_event_at, e.started_at,
               COALESCE(e.tiempo_efectivo_segundos, 0)
          INTO v_ejec, v_ejec_est, v_last, v_started, v_efectivo
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

    -- [MIG443] Si esa era la última jornada de una OT que nunca se trabajó, la
    -- OT no tiene por qué seguir existiendo: nació al programar el equipo, y el
    -- equipo se sacó del plan. Si no, queda flotando para siempre en «Viene de
    -- semanas anteriores», que es justo la lista donde más estorba.
    IF v_ot IS NOT NULL THEN
        SELECT ot.estado, ot.folio INTO v_ot_estado, v_folio
          FROM ordenes_trabajo ot WHERE ot.id = v_ot;

        IF v_ot_estado = 'creada'
           AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po
                            WHERE po.ot_id = v_ot
                              AND COALESCE(po.estado_plan,'planificada') <> 'cancelada')
           AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones e WHERE e.ot_id = v_ot)
           -- Con NC vinculadas no se toca: viene de un hallazgo, no de
           -- programar un camión, y su lugar es la bandeja de NC por agendar.
           AND NOT EXISTS (SELECT 1 FROM no_conformidades nc
                            WHERE nc.plan_ot_id = v_ot AND COALESCE(nc.resuelto,false) = false)
           -- Con costo imputado se cierra, no se tira (mismo criterio que
           -- rpc_taller_descartar_ot).
           AND NOT EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = v_ot)
           AND NOT EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = v_ot)
           AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.ot_id = v_ot)
        THEN
            SELECT nombre_completo INTO v_nombre FROM usuarios_perfil WHERE id = v_user;

            UPDATE ordenes_trabajo
               SET estado = 'cancelada',
                   observaciones = trim(COALESCE(observaciones, '') || E'\n[Descartada por ' ||
                                        COALESCE(v_nombre, 'usuario') || ' el ' ||
                                        to_char(NOW(), 'DD-MM-YYYY') ||
                                        '] Se creó al programar este equipo y quedó sin plan ni trabajo.'),
                   updated_at = NOW()
             WHERE id = v_ot;

            v_descart := v_folio;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'detenida', v_detenida,
        'estado_previo', v_estado,
        'ot_descartada', v_descart
    );
END;
$$;

COMMENT ON FUNCTION rpc_taller_quitar_jornada(UUID, BOOLEAN) IS
'Saca una jornada del plan semanal. En ejecución exige p_detener y cancela la ejecución sin cerrar la OT; finalizada no se saca; y si era la última jornada de una OT que nunca se trabajó, descarta la OT (MIG442, MIG443).';

-- ── B · Las que ya quedaron huérfanas ───────────────────────────────────────
DO $mig$
DECLARE
    v_n INT;
    r   RECORD;
BEGIN
    FOR r IN
        SELECT ot.id, ot.folio
          FROM ordenes_trabajo ot
         WHERE ot.estado = 'creada'
           AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po WHERE po.ot_id = ot.id)
           AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones e WHERE e.ot_id = ot.id)
           AND NOT EXISTS (SELECT 1 FROM no_conformidades nc
                            WHERE nc.plan_ot_id = ot.id AND COALESCE(nc.resuelto,false) = false)
           AND NOT EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = ot.id)
           AND NOT EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = ot.id)
           AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.ot_id = ot.id)
    LOOP
        UPDATE ordenes_trabajo
           SET estado = 'cancelada',
               observaciones = trim(COALESCE(observaciones, '') ||
                   E'\n[Descartada el ' || to_char(NOW(), 'DD-MM-YYYY') ||
                   '] Se creó al programar y nunca tuvo plan ni trabajo (limpieza MIG443).'),
               updated_at = NOW()
         WHERE id = r.id;
        RAISE NOTICE '  descartada %', r.folio;
    END LOOP;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'Limpieza terminada.';
END
$mig$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_quedan INT;
    v_firmas INT;
BEGIN
    SELECT count(*) INTO v_quedan
      FROM ordenes_trabajo ot
     WHERE ot.estado = 'creada'
       AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po WHERE po.ot_id = ot.id)
       AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones e WHERE e.ot_id = ot.id)
       AND NOT EXISTS (SELECT 1 FROM no_conformidades nc
                        WHERE nc.plan_ot_id = ot.id AND COALESCE(nc.resuelto,false) = false);

    IF v_quedan > 0 THEN
        RAISE EXCEPTION 'FALLO: siguen % OTs huérfanas sin NC', v_quedan;
    END IF;

    SELECT count(*) INTO v_firmas
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_taller_quitar_jornada';
    IF v_firmas <> 1 THEN
        RAISE EXCEPTION 'FALLO: rpc_taller_quitar_jornada debe tener UNA firma, hay %', v_firmas;
    END IF;

    RAISE NOTICE 'OK: 0 huérfanas y una sola firma del RPC';
END
$mig$;

COMMIT;
