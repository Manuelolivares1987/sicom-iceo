-- ============================================================================
-- MIG449 · El reloj del taller empieza a correr
-- ============================================================================
--
-- LO QUE SE ENCONTRÓ, Y ES LO MÁS GRAVE DE TODO EL PROYECTO DE INCENTIVOS
--
-- El botón de play de la app del mecánico NO MIDE TIEMPO. Llama a
-- `rpc_transicion_ot`, que sólo cambia el estado de la OT a 'en_ejecucion'.
-- Nunca crea una fila en `taller_ot_ejecuciones`. Lo mismo la pausa.
--
-- El resultado, contado en producción:
--
--     5 ejecuciones en todo el sistema · la última del 13 de julio
--     2 de esas 5 amarradas a una jornada del plan
--
-- Las únicas cinco vienen del tablero del plan semanal, no del teléfono. Es
-- decir: el tiempo de trabajo del taller no se está midiendo en ninguna parte.
--
-- Eso es la base de las dos cosas que el bono necesita: los DÍAS que decide el
-- tramo (optimizado / normal / con demora) y el REPARTO proporcional entre la
-- cuadrilla. Sin reloj no hay ninguno de los dos, y el motor de incentivos
-- calcularía sobre vacío por más migraciones que se le pongan encima.
--
-- QUÉ SE HACE
--   1. `rpc_taller_pausar_ejecucion_ot`: pausar desde el teléfono, que sólo
--      conoce la OT y no el id de la ejecución —la app trabaja sin señal—.
--   2. Finalizar cierra también la ejecución abierta, con su tiempo. Hasta hoy
--      la OT se daba por ejecutada y la ejecución quedaba corriendo para
--      siempre.
--   3. Reanudar desde la OT, por el mismo motivo que la pausa.
--
-- El cambio de la app —que el play llame a esto en vez de a la transición de
-- estado— va aparte, en el frontend.
-- ============================================================================

BEGIN;

-- ── 1 · Pausar conociendo sólo la OT ────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_pausar_ejecucion_ot(
    p_ot_id       UUID,
    p_motivo      TEXT DEFAULT NULL,
    p_motivo_tipo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_ejec  UUID;
    v_est   VARCHAR;
    v_last  TIMESTAMPTZ;
    v_efe   INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT e.id, e.estado, e.last_event_at, COALESCE(e.tiempo_efectivo_segundos, 0)
      INTO v_ejec, v_est, v_last, v_efe
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = p_ot_id AND e.estado = 'en_ejecucion'
     ORDER BY e.started_at DESC
     LIMIT 1;

    -- Sin reloj corriendo no hay nada que pausar, pero la OT sí puede quedar
    -- pausada: el mecánico apretó pausa y eso es una señal válida.
    IF v_ejec IS NULL THEN
        UPDATE ordenes_trabajo SET estado = 'pausada', updated_at = NOW()
         WHERE id = p_ot_id AND estado = 'en_ejecucion';
        RETURN jsonb_build_object('success', true, 'sin_ejecucion', true);
    END IF;

    v_efe := v_efe + GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);

    UPDATE taller_ot_ejecuciones
       SET estado = 'pausada',
           tiempo_efectivo_segundos = v_efe,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = v_ejec;

    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, motivo_tipo, created_by)
    VALUES (v_ejec, p_ot_id, 'pause', p_motivo,
            NULLIF(p_motivo_tipo, ''), v_user);

    UPDATE taller_plan_semanal_ots po
       SET estado_plan = 'pausada', updated_at = NOW()
      FROM taller_ot_ejecuciones e
     WHERE e.id = v_ejec AND po.id = e.plan_semanal_ot_id
       AND po.estado_plan = 'en_ejecucion';

    UPDATE ordenes_trabajo SET estado = 'pausada', updated_at = NOW()
     WHERE id = p_ot_id AND estado = 'en_ejecucion';

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec, 'tiempo_efectivo_seg', v_efe);
END;
$$;

-- ── 2 · Reanudar conociendo sólo la OT ──────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_reanudar_ejecucion_ot(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_ejec UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT e.id INTO v_ejec
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = p_ot_id AND e.estado = 'pausada'
     ORDER BY e.started_at DESC
     LIMIT 1;

    IF v_ejec IS NULL THEN
        RETURN jsonb_build_object('success', true, 'sin_ejecucion', true);
    END IF;

    UPDATE taller_ot_ejecuciones
       SET estado = 'en_ejecucion', last_event_at = NOW(), updated_at = NOW()
     WHERE id = v_ejec;

    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, created_by)
    VALUES (v_ejec, p_ot_id, 'resume', v_user);

    UPDATE ordenes_trabajo SET estado = 'en_ejecucion', updated_at = NOW()
     WHERE id = p_ot_id AND estado = 'pausada';

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec);
END;
$$;

-- ── 3 · Finalizar cierra también el reloj ───────────────────────────────────
--
-- Hasta hoy la OT se daba por ejecutada y la ejecución quedaba abierta para
-- siempre. De ahí salen los días que decide el bono: si no se cierra, no hay
-- fecha de término que medir.
CREATE OR REPLACE FUNCTION fn_taller_cerrar_ejecuciones_abiertas(p_ot_id UUID, p_observacion TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    r      RECORD;
    v_n    INT := 0;
    v_efe  INT;
BEGIN
    FOR r IN
        SELECT e.id, e.estado, e.last_event_at, e.started_at,
               COALESCE(e.tiempo_efectivo_segundos, 0) AS efe
          FROM taller_ot_ejecuciones e
         WHERE e.ot_id = p_ot_id AND e.estado IN ('en_ejecucion','pausada')
    LOOP
        v_efe := r.efe;
        IF r.estado = 'en_ejecucion' THEN
            v_efe := v_efe + GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.last_event_at))::INT);
        END IF;

        UPDATE taller_ot_ejecuciones
           SET estado = 'finalizada',
               finished_at = NOW(),
               tiempo_efectivo_segundos = v_efe,
               tiempo_total_segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.started_at))::INT),
               observacion_cierre = COALESCE(observacion_cierre, p_observacion),
               last_event_at = NOW(),
               updated_at = NOW()
         WHERE id = r.id;

        INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, created_by)
        VALUES (r.id, p_ot_id, 'finish', p_observacion, v_user);

        v_n := v_n + 1;
    END LOOP;

    RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_pausar_ejecucion_ot(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_reanudar_ejecucion_ot(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_pausar_ejecucion_ot(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_reanudar_ejecucion_ot(UUID) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public'
       AND p.proname IN ('rpc_taller_pausar_ejecucion_ot','rpc_taller_reanudar_ejecucion_ot',
                         'fn_taller_cerrar_ejecuciones_abiertas');
    IF v_n <> 3 THEN RAISE EXCEPTION 'FALLO: faltan funciones del reloj (%)', v_n; END IF;

    SELECT count(*) INTO v_n FROM taller_ot_ejecuciones WHERE estado IN ('en_ejecucion','pausada');
    RAISE NOTICE 'ejecuciones abiertas que quedarán cerradas al finalizar su OT: %', v_n;
    RAISE NOTICE 'el reloj queda listo; falta que la app lo llame';
END
$mig$;

COMMIT;
