-- ============================================================================
-- MIG488 · Sacar la OT entera del plan, no jornada por jornada
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 02-09-2026: «esta OT OT-202608-00015 la voy a eliminar del plan semanal, pero
-- necesito que también salga del plan taller; es una prueba y quiero volver a
-- hacer otra».
--
-- Ya lo había reportado antes, el 31-08: «estoy en el 07 de septiembre, la
-- quiero sacar del plan y no puedo». Recién ahora, con los datos delante, se ve
-- por qué.
--
-- POR QUÉ NO SALÍA
-- Dos cosas, y ninguna era un error de la pantalla:
--
--   1. `rpc_taller_quitar_jornada` saca UNA jornada. Esa OT tiene CINCO —lunes a
--      viernes del 07 al 11 de septiembre—, porque se planificó multidía. Sacar
--      una dejaba cuatro, y el equipo seguía en el tablero. Para el que mira,
--      «no se puede sacar».
--
--   2. Aunque se sacaran las cinco, la OT seguiría apareciendo. El descarte
--      automático de MIG443 sólo actúa sobre OT en estado `creada`; ésta está
--      `pausada` porque alcanzó a ejecutarse 15 minutos. Sin plan pero abierta,
--      cae en «viene de semanas anteriores» — que es exactamente el «plan
--      taller» del que Manuel dice que no sale.
--
-- LO QUE HACE ESTA MIGRACIÓN
-- Una sola acción que saca la OT completa: todas sus jornadas de una vez,
-- deteniendo lo que esté corriendo, y —si se pide— descartando la OT para que
-- no vuelva por la puerta de atrás.
--
-- LO QUE NO HACE, A PROPÓSITO
--
--   · Las jornadas FINALIZADAS no se tocan: son historia del plan.
--   · Una OT con costo imputado (materiales, salidas de bodega) no se descarta
--     sola. Eso se cierra, no se tira: el costo ya existe. Pero el bloqueo
--     INFORMA y se puede levantar: una OT de prueba que sacó un kilo de trapos
--     de bodega no puede quedar viva para siempre por eso. Levantarlo es de
--     administrador o subgerente, exige motivo, y queda escrito en la OT: el
--     movimiento de bodega no se deshace —el trapo salió—, sólo se acepta que
--     queda colgando de una OT descartada.
--   · Las no conformidades NO se borran. Una NC nació de mirar el equipo, no de
--     planificarlo: si el hallazgo es real, sigue siéndolo aunque la OT se haya
--     descartado. Quedan en la bandeja de «por agendar» y la función avisa
--     cuántas son, para que quien descarta lo sepa y decida.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_sacar_ot_del_plan(
    p_ot_id      UUID,
    p_descartar  BOOLEAN DEFAULT FALSE,
    p_motivo     TEXT    DEFAULT NULL,
    p_forzar     BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_rol      TEXT;
    v_nombre   TEXT;
    v_folio    TEXT;
    v_estado   TEXT;
    v_quitadas INT := 0;
    v_finales  INT := 0;
    v_detenidas INT := 0;
    v_ncs      INT := 0;
    v_bloqueo  TEXT := NULL;
    v_cancelada BOOLEAN := FALSE;
    r RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado para sacar una OT del plan', v_rol;
    END IF;

    SELECT ot.folio, ot.estado::TEXT INTO v_folio, v_estado
      FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
    IF v_folio IS NULL THEN RAISE EXCEPTION 'Esa OT no existe.'; END IF;

    -- Las jornadas ya finalizadas se quedan: son historia del plan.
    SELECT count(*) INTO v_finales FROM taller_plan_semanal_ots
     WHERE ot_id = p_ot_id AND estado_plan = 'finalizada';

    -- Lo que esté corriendo se detiene con su tiempo escrito. El avance no se
    -- pierde: se cancela la ejecución, no se borra.
    FOR r IN
        SELECT e.id, e.estado, e.last_event_at, e.started_at,
               COALESCE(e.tiempo_efectivo_segundos, 0) AS efectivo
          FROM taller_ot_ejecuciones e
          JOIN taller_plan_semanal_ots po ON po.id = e.plan_semanal_ot_id
         WHERE po.ot_id = p_ot_id
           AND po.estado_plan <> 'finalizada'
           AND e.estado IN ('en_ejecucion','pausada')
    LOOP
        UPDATE taller_ot_ejecuciones
           SET estado = 'cancelada',
               finished_at = NOW(),
               tiempo_efectivo_segundos = r.efectivo + CASE WHEN r.estado = 'en_ejecucion'
                   THEN GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.last_event_at))::INT) ELSE 0 END,
               tiempo_total_segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.started_at))::INT),
               observacion_cierre = 'Detenida al sacar la OT del plan',
               last_event_at = NOW(), updated_at = NOW()
         WHERE id = r.id;

        INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, created_by)
        VALUES (r.id, p_ot_id, 'cancel', 'La OT se sacó del plan', v_user);

        v_detenidas := v_detenidas + 1;
    END LOOP;

    DELETE FROM taller_plan_semanal_ots
     WHERE ot_id = p_ot_id AND COALESCE(estado_plan,'planificada') <> 'finalizada';
    GET DIAGNOSTICS v_quitadas = ROW_COUNT;

    -- ── Descartar la OT, si se pidió ────────────────────────────────────────
    IF p_descartar THEN
        IF v_estado IN ('cerrada','cancelada') THEN
            v_bloqueo := 'La OT ya estaba ' || v_estado || '.';
        ELSIF v_finales > 0 THEN
            v_bloqueo := 'Tiene ' || v_finales || ' jornada(s) finalizada(s): eso ya es trabajo hecho. '
                      || 'Se cierra, no se descarta.';
        ELSIF (EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = p_ot_id)
            OR EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = p_ot_id)
            OR EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.ot_id = p_ot_id))
           AND NOT p_forzar THEN
            v_bloqueo := 'Tiene material despachado de bodega. Eso normalmente se cierra, no se tira. '
                      || 'Si igual hay que descartarla, gerencia puede forzarlo dejando el motivo escrito.';
        ELSIF (EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = p_ot_id)
            OR EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = p_ot_id)
            OR EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.ot_id = p_ot_id))
           AND (v_rol NOT IN ('administrador','subgerente_operaciones')
                OR length(btrim(COALESCE(p_motivo,''))) < 5) THEN
            v_bloqueo := 'Forzar el descarte de una OT con material despachado es de gerencia, '
                      || 'y con el motivo escrito.';
        ELSE
            SELECT nombre_completo INTO v_nombre FROM usuarios_perfil WHERE id = v_user;

            UPDATE ordenes_trabajo
               SET estado = 'cancelada',
                   observaciones = trim(COALESCE(observaciones, '') || E'\n[Descartada por ' ||
                                        COALESCE(v_nombre, 'usuario') || ' el ' ||
                                        to_char(NOW(), 'DD-MM-YYYY') || '] ' ||
                                        COALESCE(NULLIF(btrim(p_motivo), ''), 'Sacada del plan.') ||
                                        CASE WHEN p_forzar THEN
                                            ' Se forzó pese al material ya despachado de bodega: '
                                            || 'ese movimiento queda registrado igual.'
                                        ELSE '' END),
                   updated_at = NOW()
             WHERE id = p_ot_id;

            v_cancelada := TRUE;
        END IF;
    END IF;

    -- Las NC no se borran: nacieron de mirar el equipo, no de planificarlo.
    SELECT count(*) INTO v_ncs FROM no_conformidades
     WHERE ot_id = p_ot_id AND COALESCE(resuelto, FALSE) = FALSE;

    RETURN jsonb_build_object(
        'success', TRUE,
        'folio', v_folio,
        'jornadas_quitadas', v_quitadas,
        'jornadas_finalizadas', v_finales,
        'ejecuciones_detenidas', v_detenidas,
        'ot_cancelada', v_cancelada,
        'nc_abiertas', v_ncs,
        'no_se_pudo_descartar', v_bloqueo
    );
END;
$$;

COMMENT ON FUNCTION rpc_taller_sacar_ot_del_plan(UUID, BOOLEAN, TEXT, BOOLEAN) IS
    'Saca del plan todas las jornadas de una OT de una vez, deteniendo lo que '
    'esté corriendo, y opcionalmente descarta la OT para que no vuelva por la '
    'lista de arrastre. No borra no conformidades ni jornadas finalizadas.';

-- Sin soltar la firma anterior quedarían dos y la llamada sería ambigua.
DROP FUNCTION IF EXISTS rpc_taller_sacar_ot_del_plan(UUID, BOOLEAN, TEXT);
REVOKE ALL ON FUNCTION rpc_taller_sacar_ot_del_plan(UUID, BOOLEAN, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_sacar_ot_del_plan(UUID, BOOLEAN, TEXT, BOOLEAN) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    -- Cuántas OT del plan son multidía: son las que hoy hay que sacar a mano
    -- una jornada a la vez.
    SELECT count(*) INTO v_n FROM (
        SELECT ot_id FROM taller_plan_semanal_ots
         WHERE COALESCE(estado_plan,'planificada') <> 'finalizada'
         GROUP BY ot_id HAVING count(*) > 1) x;
    RAISE NOTICE 'OT con más de una jornada en el plan: %', v_n;

    SELECT count(*) INTO v_n FROM taller_plan_semanal_ots
     WHERE ot_id = 'fcc5732f-6fd3-49b1-940b-989eb895cbdd';
    RAISE NOTICE 'jornadas de la OT-202608-00015: %', v_n;
END $mig$;

COMMIT;
