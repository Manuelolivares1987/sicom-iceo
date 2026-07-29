-- ============================================================================
-- SICOM-ICEO | 256 — Planificar la semana reutiliza la OT abierta
-- ----------------------------------------------------------------------------
-- Levantado por Manuel desde /dashboard/mantenimiento/plan-semanal-taller:
-- «al momento de planificar las tareas semanales se duplica la OT; la idea es
-- que se pueda utilizar la misma OT abierta para planificar las próximas
-- semanas hasta que esté cerrada».
--
-- CAUSA: el modal «Programar» del plan semanal llama a rpc_programar_ot_taller,
-- que va directo a rpc_crear_ot y SIEMPRE inserta una OT nueva. No mira si el
-- equipo ya tiene una OT abierta del mismo trabajo. Resultado: un trabajo que
-- se arrastra dos o tres semanas deja dos o tres OT abiertas para lo mismo, con
-- su checklist y sus horas repartidas entre folios distintos.
-- Hoy en producción hay equipos con 6 y 7 OT correctivas abiertas a la vez.
--
-- SOLUCIÓN: antes de crear, buscar una OT ABIERTA del mismo trabajo y reutilizarla.
--   Abierta = estado NOT IN (ejecutada_ok, ejecutada_con_observaciones,
--                            no_ejecutada, cancelada, cerrada)
--   Mismo trabajo =
--     · preventivo CON pauta  → misma pauta (plan_mantenimiento_id). La pauta es
--                               la identidad del trabajo; es el mismo criterio
--                               que ya usa generar_ots_preventivas.
--     · resto                 → mismo activo + mismo tipo, y ambas sin pauta
--                               (una preventiva «sin pauta» no se cuelga de una
--                               OT que sí tiene pauta).
--
-- Al reutilizar se corre la fecha programada a la nueva semana y se sube la
-- prioridad si la nueva es mayor; el checklist y el avance se conservan, que es
-- justo lo que se perdía al duplicar.
--
-- p_reutilizar permite forzar una OT nueva desde la UI cuando de verdad es otro
-- trabajo distinto sobre el mismo equipo.
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_programar_ot_taller') THEN
        RAISE EXCEPTION 'STOP — falta rpc_programar_ot_taller.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_crear_ot') THEN
        RAISE EXCEPTION 'STOP — falta rpc_crear_ot.';
    END IF;
END $$;


-- ── 1. ¿Hay una OT abierta para este mismo trabajo? ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ot_abierta_reutilizable(
    p_activo_id UUID,
    p_tipo      tipo_ot_enum,
    p_plan_mantenimiento_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT o.id
      FROM ordenes_trabajo o
     WHERE o.activo_id = p_activo_id
       AND o.tipo = p_tipo
       AND o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                            'no_ejecutada','cancelada','cerrada')
       AND (
             -- Con pauta: manda la pauta, es la identidad del trabajo
             (p_plan_mantenimiento_id IS NOT NULL
              AND o.plan_mantenimiento_id = p_plan_mantenimiento_id)
             -- Sin pauta: mismo activo y tipo, y la OT tampoco debe tener pauta
          OR (p_plan_mantenimiento_id IS NULL
              AND o.plan_mantenimiento_id IS NULL)
           )
     ORDER BY o.created_at DESC
     LIMIT 1;
$function$;

COMMENT ON FUNCTION public.fn_ot_abierta_reutilizable(UUID, tipo_ot_enum, UUID) IS
    'OT abierta del mismo trabajo que se puede seguir usando en vez de duplicar. MIG256.';

REVOKE ALL ON FUNCTION public.fn_ot_abierta_reutilizable(UUID, tipo_ot_enum, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ot_abierta_reutilizable(UUID, tipo_ot_enum, UUID) TO authenticated;


-- ── 2. Programar desde el plan: reutiliza antes de crear ────────────────────
CREATE OR REPLACE FUNCTION public.rpc_programar_ot_taller(
    p_activo_id  UUID,
    p_tipo       tipo_ot_enum,
    p_prioridad  prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha      DATE DEFAULT NULL,
    p_responsable_id UUID DEFAULT NULL,
    p_plan_mantenimiento_id UUID DEFAULT NULL,
    p_reutilizar BOOLEAN DEFAULT TRUE      -- [MIG256] false = forzar OT nueva
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_contrato_id uuid;
    v_faena_id    uuid;
    v_a_contrato  uuid;
    v_a_faena     uuid;
    v_existente   uuid;
    v_ot          RECORD;
    v_orden_nueva INT;
    v_orden_vieja INT;
BEGIN
    SELECT contrato_id, faena_id INTO v_a_contrato, v_a_faena FROM activos WHERE id = p_activo_id;

    -- [MIG256] ¿Ya hay una OT abierta de este mismo trabajo? Se sigue usando.
    IF COALESCE(p_reutilizar, TRUE) THEN
        v_existente := fn_ot_abierta_reutilizable(p_activo_id, p_tipo, p_plan_mantenimiento_id);
    END IF;

    IF v_existente IS NOT NULL THEN
        SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = v_existente;

        -- La fecha programada se corre a la semana que se está planificando y
        -- la prioridad solo sube, nunca baja.
        v_orden_nueva := array_position(ARRAY['baja','normal','alta','urgente'], p_prioridad::text);
        v_orden_vieja := array_position(ARRAY['baja','normal','alta','urgente'], v_ot.prioridad::text);

        UPDATE ordenes_trabajo
           SET fecha_programada = COALESCE(p_fecha, fecha_programada),
               prioridad = CASE WHEN COALESCE(v_orden_nueva,0) > COALESCE(v_orden_vieja,0)
                                THEN p_prioridad ELSE prioridad END,
               responsable_id = COALESCE(p_responsable_id, responsable_id),
               updated_at = NOW()
         WHERE id = v_existente
        RETURNING * INTO v_ot;

        RETURN jsonb_build_object(
            'id', v_ot.id,
            'folio', v_ot.folio,
            'estado', v_ot.estado,
            'reutilizada', true,
            'mensaje', 'Se siguió usando la OT abierta ' || v_ot.folio ||
                       ' (no se creó una nueva); su checklist y su avance se mantienen.'
        );
    END IF;

    -- Contrato: el del activo si está activo; si no, el contrato interno.
    SELECT id INTO v_contrato_id FROM contratos WHERE id = v_a_contrato AND estado = 'activo';
    IF v_contrato_id IS NULL THEN v_contrato_id := fn_contrato_interno_id(); END IF;

    -- Faena: la del TALLER (el trabajo se hace ahí y sus vales salen de la
    -- bodega del taller), no la del arriendo del equipo.
    v_faena_id := COALESCE(fn_faena_taller_para_activo(p_activo_id), v_a_faena, fn_faena_interna_id());

    RETURN rpc_crear_ot(p_tipo, v_contrato_id, v_faena_id, p_activo_id, p_prioridad,
                        p_fecha, p_responsable_id, p_plan_mantenimiento_id, auth.uid())
           || jsonb_build_object('reutilizada', false);
END;
$function$;

-- La firma vieja (6 args) queda eliminada para no dejar overloads ambiguos:
-- PostgREST elegiría cualquiera de las dos y el front dejaría de reutilizar.
DROP FUNCTION IF EXISTS public.rpc_programar_ot_taller(uuid, tipo_ot_enum, prioridad_enum, date, uuid, uuid);

REVOKE ALL ON FUNCTION public.rpc_programar_ot_taller(UUID, tipo_ot_enum, prioridad_enum, DATE, UUID, UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_programar_ot_taller(UUID, tipo_ot_enum, prioridad_enum, DATE, UUID, UUID, BOOLEAN) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_activo UUID; v_pat TEXT;
    v_r1 JSONB; v_r2 JSONB; v_r3 JSONB;
    v_antes INT; v_despues INT;
BEGIN
    -- Solo debe existir la firma nueva
    IF (SELECT count(*) FROM pg_proc WHERE proname='rpc_programar_ot_taller') <> 1 THEN
        RAISE EXCEPTION 'FALLO — quedó más de una firma de rpc_programar_ot_taller';
    END IF;

    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    SELECT a.id, a.patente INTO v_activo, v_pat
      FROM activos a
      JOIN contratos c ON c.id = a.contrato_id AND c.estado='activo'
     WHERE a.estado IN ('operativo','en_mantenimiento','fuera_servicio')
       AND a.fecha_baja IS NULL
     LIMIT 1;
    IF v_user IS NULL OR v_activo IS NULL THEN
        RAISE NOTICE 'MIG256: sin datos para smoke (ok)'; RETURN;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    SELECT count(*) INTO v_antes FROM ordenes_trabajo WHERE activo_id = v_activo;

    -- 1ª programación: crea
    v_r1 := rpc_programar_ot_taller(v_activo, 'inspeccion'::tipo_ot_enum, 'normal'::prioridad_enum,
                                    CURRENT_DATE, NULL, NULL, TRUE);
    IF (v_r1->>'reutilizada')::boolean THEN
        RAISE EXCEPTION 'FALLO — la primera programación debía crear, no reutilizar';
    END IF;

    -- 2ª programación de la semana siguiente: NO debe duplicar
    v_r2 := rpc_programar_ot_taller(v_activo, 'inspeccion'::tipo_ot_enum, 'alta'::prioridad_enum,
                                    CURRENT_DATE + 7, NULL, NULL, TRUE);
    IF NOT (v_r2->>'reutilizada')::boolean THEN
        RAISE EXCEPTION 'FALLO — la segunda programación duplicó la OT (%)', v_r2->>'folio';
    END IF;
    IF (v_r2->>'id') <> (v_r1->>'id') THEN
        RAISE EXCEPTION 'FALLO — reutilizó una OT distinta';
    END IF;

    -- La fecha se corrió y la prioridad subió
    IF (SELECT fecha_programada FROM ordenes_trabajo WHERE id=(v_r1->>'id')::uuid) <> CURRENT_DATE + 7 THEN
        RAISE EXCEPTION 'FALLO — no se corrió la fecha programada';
    END IF;
    IF (SELECT prioridad::text FROM ordenes_trabajo WHERE id=(v_r1->>'id')::uuid) <> 'alta' THEN
        RAISE EXCEPTION 'FALLO — no subió la prioridad';
    END IF;

    -- Forzando OT nueva sí se crea otra
    v_r3 := rpc_programar_ot_taller(v_activo, 'inspeccion'::tipo_ot_enum, 'normal'::prioridad_enum,
                                    CURRENT_DATE + 14, NULL, NULL, FALSE);
    IF (v_r3->>'reutilizada')::boolean OR (v_r3->>'id') = (v_r1->>'id') THEN
        RAISE EXCEPTION 'FALLO — p_reutilizar=false debía crear una OT nueva';
    END IF;

    SELECT count(*) INTO v_despues FROM ordenes_trabajo WHERE activo_id = v_activo;
    RAISE NOTICE 'MIG256 OK en %: 3 programaciones -> % OT nuevas (antes % / después %). Reutilizada: %',
        v_pat, v_despues - v_antes, v_antes, v_despues, v_r2->>'mensaje';

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
