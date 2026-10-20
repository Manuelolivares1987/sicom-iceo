-- 624 — Varios mecánicos en el plan y en la ejecución (2026-10-20).
--
-- Dos topes impedían trabajar en cuadrilla:
--
-- 1. El PLAN aceptaba como máximo 2 mecánicos por jornada (MIG451). En la base
--    ya había 4 jornadas antiguas con 3 personas: la realidad se había salido
--    del tope. Pasa a 4, igual que MAX_MECANICOS en la app.
--
-- 2. La EJECUCIÓN tenía `uq_taller_ejec_activa_ot`: UNA ejecución abierta por
--    OT. Con dos mecánicos en el mismo camión sólo uno podía apretar play; el
--    otro quedaba sin tiempo medido, y el bono (D2, MIG483: «se paga por tiempo
--    medido») caía a repartir por jornadas. Ahora el reloj es por OT Y por
--    persona: cada uno de la cuadrilla aprieta su propio play/pausa.
--
-- Reglas:
--   · Una persona no tiene dos relojes corriendo: si arranca en otra OT, el que
--     tenía andando se pausa solo (mismo principio que las OS, MIG473).
--   · La OT está «en ejecución» mientras al menos uno trabaja; queda «pausada»
--     cuando el último pausa (ahí salta el trigger de NC, como siempre).
--   · Pausar sin decir quién (el jefe desde el tablero) pausa a todos.
--   · Finalizar la OT cierra los relojes de todos y suma sus horas.
--   · Un reloj sin persona (arrancado por el jefe antes de esto) lo toma el
--     primer mecánico que lo pausa o reanuda.

-- ── 1. El índice: una ejecución abierta por OT y por persona ─────────────────
DROP INDEX IF EXISTS uq_taller_ejec_activa_ot;
CREATE UNIQUE INDEX IF NOT EXISTS uq_taller_ejec_activa_ot_tecnico
    ON taller_ot_ejecuciones (ot_id, COALESCE(tecnico_id, '00000000-0000-0000-0000-000000000000'::uuid))
 WHERE estado IN ('en_ejecucion','pausada');

-- Para encontrar rápido el reloj abierto de una persona.
CREATE INDEX IF NOT EXISTS idx_taller_ejec_tecnico_abierta
    ON taller_ot_ejecuciones (tecnico_id)
 WHERE estado IN ('en_ejecucion','pausada');

-- ── 2. El estado de la OT sigue a los relojes ────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_sync_estado_reloj(p_ot_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM taller_ot_ejecuciones
                WHERE ot_id = p_ot_id AND estado = 'en_ejecucion') THEN
        UPDATE taller_plan_semanal_ots po
           SET estado_plan = 'en_ejecucion', updated_at = NOW()
         WHERE po.estado_plan = 'pausada'
           AND po.id IN (SELECT e.plan_semanal_ot_id FROM taller_ot_ejecuciones e
                          WHERE e.ot_id = p_ot_id AND e.estado = 'en_ejecucion');
        UPDATE ordenes_trabajo SET estado = 'en_ejecucion', updated_at = NOW()
         WHERE id = p_ot_id AND estado = 'pausada';
    ELSE
        -- Nadie trabajando: la jornada y la OT quedan en pausa.
        UPDATE taller_plan_semanal_ots po
           SET estado_plan = 'pausada', updated_at = NOW()
         WHERE po.estado_plan = 'en_ejecucion'
           AND po.id IN (SELECT e.plan_semanal_ot_id FROM taller_ot_ejecuciones e
                          WHERE e.ot_id = p_ot_id AND e.estado = 'pausada');
        UPDATE ordenes_trabajo SET estado = 'pausada', updated_at = NOW()
         WHERE id = p_ot_id AND estado = 'en_ejecucion';
    END IF;
END;
$$;

-- Pausa UN reloj (si está corriendo). Devuelve sus segundos efectivos.
CREATE OR REPLACE FUNCTION fn_taller_reloj_pausar(p_ejecucion_id UUID, p_motivo TEXT, p_motivo_tipo TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_e   RECORD;
    v_efe INT;
BEGIN
    SELECT id, ot_id, estado, last_event_at, COALESCE(tiempo_efectivo_segundos, 0) AS efe
      INTO v_e FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF v_e.id IS NULL OR v_e.estado <> 'en_ejecucion' THEN RETURN NULL; END IF;

    v_efe := v_e.efe + GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_e.last_event_at))::INT);

    UPDATE taller_ot_ejecuciones
       SET estado = 'pausada', tiempo_efectivo_segundos = v_efe,
           last_event_at = NOW(), updated_at = NOW()
     WHERE id = p_ejecucion_id;

    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, motivo_tipo, created_by)
    VALUES (p_ejecucion_id, v_e.ot_id, 'pause', p_motivo, NULLIF(p_motivo_tipo, ''), auth.uid());

    PERFORM fn_taller_ot_sync_estado_reloj(v_e.ot_id);
    RETURN v_efe;
END;
$$;

-- Una persona, un reloj corriendo: el de otra OT se pausa.
CREATE OR REPLACE FUNCTION fn_taller_pausar_otros_relojes(p_tecnico_id UUID, p_ot_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r   RECORD;
    v_n INT := 0;
BEGIN
    IF p_tecnico_id IS NULL THEN RETURN 0; END IF;
    FOR r IN
        SELECT e.id FROM taller_ot_ejecuciones e
         WHERE e.tecnico_id = p_tecnico_id AND e.estado = 'en_ejecucion' AND e.ot_id <> p_ot_id
    LOOP
        PERFORM fn_taller_reloj_pausar(r.id, 'Pasó a trabajar en otra OT', 'otro');
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_ot_sync_estado_reloj(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_taller_reloj_pausar(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_taller_pausar_otros_relojes(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ── 3. Iniciar: el reloj de ESTA persona ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_iniciar_ejecucion_ot_base(p_ot_id uuid, p_observacion text DEFAULT NULL::text, p_tecnico_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user       UUID := auth.uid();
    v_ejecutor   UUID;
    v_plan_ot_id UUID;
    v_ejec_id    UUID;
    v_ejec_est   VARCHAR;
    v_tec_ok     BOOLEAN := FALSE;
    v_sumado     BOOLEAN := FALSE;
    v_otros      INT := 0;
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

    -- [MIG624] Si esta persona ya tiene su reloj abierto en la OT, no se abre
    -- otro: se reanuda (o ya estaba corriendo). Doble toque o reintento offline.
    SELECT e.id, e.estado INTO v_ejec_id, v_ejec_est
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = p_ot_id AND e.estado IN ('en_ejecucion','pausada')
       AND e.tecnico_id IS NOT DISTINCT FROM p_tecnico_id
     ORDER BY e.started_at DESC LIMIT 1;

    -- Y nadie tiene dos relojes corriendo.
    v_otros := fn_taller_pausar_otros_relojes(p_tecnico_id, p_ot_id);

    IF v_ejec_id IS NOT NULL THEN
        IF v_ejec_est = 'pausada' THEN
            UPDATE taller_ot_ejecuciones
               SET estado = 'en_ejecucion', last_event_at = NOW(), updated_at = NOW()
             WHERE id = v_ejec_id;
            INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, created_by)
            VALUES (v_ejec_id, p_ot_id, 'resume', v_user);
            PERFORM fn_taller_ot_sync_estado_reloj(p_ot_id);
        END IF;
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec_id,
                                  'ya_estaba', v_ejec_est = 'en_ejecucion',
                                  'reanudada', v_ejec_est = 'pausada',
                                  'tecnico_id', p_tecnico_id, 'otros_pausados', v_otros);
    END IF;

    -- Plan OT mas reciente (multidia: agarra la jornada actual o futura mas cercana)
    SELECT t.id INTO v_plan_ot_id FROM taller_plan_semanal_ots t
      JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     WHERE t.ot_id = p_ot_id
       AND t.estado_plan IN ('planificada','asignada','liberada','pausada','en_ejecucion')
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
    -- [MIG624] El segundo mecánico no le corre la fecha de inicio a la OT.
    UPDATE ordenes_trabajo
       SET estado = 'en_ejecucion', fecha_inicio = COALESCE(fecha_inicio, NOW()), updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'ejecucion_id', v_ejec_id,
        'plan_ot_id', v_plan_ot_id,
        'tecnico_id', p_tecnico_id,
        'sumado_a_cuadrilla', COALESCE(v_sumado, FALSE),
        'otros_pausados', v_otros
    );
END;
$function$;

-- ── 4. Pausar / reanudar por OT, ahora con la persona ────────────────────────
DROP FUNCTION IF EXISTS rpc_taller_pausar_ejecucion_ot(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION rpc_taller_pausar_ejecucion_ot(
    p_ot_id UUID, p_motivo TEXT DEFAULT NULL, p_motivo_tipo TEXT DEFAULT NULL,
    p_tecnico_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    r      RECORD;
    v_n    INT := 0;
    v_ult  UUID;
    v_efe  INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    -- Sin persona (el jefe desde el tablero) se pausa a todos. Con persona,
    -- sólo su reloj; si no tiene uno, el reloj sin dueño (arrancado antes de
    -- MIG624) se toma como suyo.
    FOR r IN
        SELECT e.id FROM taller_ot_ejecuciones e
         WHERE e.ot_id = p_ot_id AND e.estado = 'en_ejecucion'
           AND (p_tecnico_id IS NULL OR e.tecnico_id = p_tecnico_id
                OR (e.tecnico_id IS NULL AND NOT EXISTS (
                        SELECT 1 FROM taller_ot_ejecuciones x
                         WHERE x.ot_id = p_ot_id AND x.estado = 'en_ejecucion'
                           AND x.tecnico_id = p_tecnico_id)))
    LOOP
        UPDATE taller_ot_ejecuciones SET tecnico_id = p_tecnico_id
         WHERE id = r.id AND tecnico_id IS NULL AND p_tecnico_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones x
                            WHERE x.ot_id = p_ot_id AND x.tecnico_id = p_tecnico_id
                              AND x.estado IN ('en_ejecucion','pausada'));
        v_efe := fn_taller_reloj_pausar(r.id, p_motivo, p_motivo_tipo);
        v_ult := r.id;
        v_n := v_n + 1;
    END LOOP;

    IF v_n = 0 THEN
        -- Sin reloj de esta persona corriendo no hay nada que pausar. Si NADIE
        -- trabaja, la OT igual queda pausada: el mecánico apretó pausa y eso es
        -- una señal válida.
        IF NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones
                        WHERE ot_id = p_ot_id AND estado = 'en_ejecucion') THEN
            UPDATE ordenes_trabajo SET estado = 'pausada', updated_at = NOW()
             WHERE id = p_ot_id AND estado = 'en_ejecucion';
        END IF;
        RETURN jsonb_build_object('success', true, 'sin_ejecucion', true);
    END IF;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ult,
                              'pausadas', v_n, 'tiempo_efectivo_seg', v_efe);
END;
$$;

DROP FUNCTION IF EXISTS rpc_taller_reanudar_ejecucion_ot(UUID);
CREATE OR REPLACE FUNCTION rpc_taller_reanudar_ejecucion_ot(p_ot_id UUID, p_tecnico_id UUID DEFAULT NULL)
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
       AND (p_tecnico_id IS NULL OR e.tecnico_id = p_tecnico_id)
     ORDER BY e.started_at DESC
     LIMIT 1;

    -- [MIG624] La persona no tiene reloj propio en la OT: si hay uno sin dueño
    -- pausado (de antes de MIG624), lo toma; si no, el teléfono arranca uno.
    IF v_ejec IS NULL AND p_tecnico_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones x
                        WHERE x.ot_id = p_ot_id AND x.tecnico_id = p_tecnico_id
                          AND x.estado IN ('en_ejecucion','pausada')) THEN
        SELECT e.id INTO v_ejec
          FROM taller_ot_ejecuciones e
         WHERE e.ot_id = p_ot_id AND e.estado = 'pausada' AND e.tecnico_id IS NULL
         ORDER BY e.started_at DESC
         LIMIT 1;
        IF v_ejec IS NOT NULL THEN
            UPDATE taller_ot_ejecuciones SET tecnico_id = p_tecnico_id WHERE id = v_ejec;
        END IF;
    END IF;

    IF v_ejec IS NULL THEN
        RETURN jsonb_build_object('success', true, 'sin_ejecucion', true);
    END IF;

    PERFORM fn_taller_pausar_otros_relojes(p_tecnico_id, p_ot_id);

    UPDATE taller_ot_ejecuciones
       SET estado = 'en_ejecucion', last_event_at = NOW(), updated_at = NOW()
     WHERE id = v_ejec;

    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, created_by)
    VALUES (v_ejec, p_ot_id, 'resume', v_user);

    PERFORM fn_taller_ot_sync_estado_reloj(p_ot_id);

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_pausar_ejecucion_ot(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_reanudar_ejecucion_ot(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_pausar_ejecucion_ot(UUID, TEXT, TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_taller_reanudar_ejecucion_ot(UUID, UUID) TO authenticated, service_role;


-- ── 5. Finalizar desde el tablero: se cierran los relojes de todos ──────────
CREATE OR REPLACE FUNCTION public.rpc_taller_finalizar_ejecucion(p_ejecucion_id uuid, p_avance_final numeric DEFAULT 100, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_started TIMESTAMPTZ; v_ot UUID; v_plan_ot UUID;
    v_t_efectivo INT; v_t_pausado INT; v_t_colacion INT;
    v_trabajo JSONB; v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
    v_otros INT := 0;
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

    -- [MIG445] Las dos puertas miden con la misma vara.
    v_trabajo := fn_taller_ot_tiene_trabajo(v_ot);
    IF NOT (v_trabajo->>'tiene')::BOOLEAN THEN
        RAISE EXCEPTION 'Esta OT no tiene trabajo registrado: ningún ítem del checklist respondido y sin tiempo de ejecución. No se puede dar por ejecutada.';
    END IF;

    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = v_ot
     ORDER BY i.created_at DESC
     LIMIT 1;

    IF v_inst.id IS NOT NULL THEN
        IF v_inst.horometro IS NULL THEN
            v_falta := array_append(v_falta, 'el horómetro'::TEXT);
        END IF;
        IF v_inst.kilometraje IS NULL AND fn_activo_exige_kilometraje(v_inst.activo_id) THEN
            v_falta := array_append(v_falta, 'el kilometraje'::TEXT);
        END IF;
        IF array_length(v_falta, 1) > 0 THEN
            RAISE EXCEPTION 'Falta anotar % del equipo antes de dar la OT por ejecutada.',
                array_to_string(v_falta, ' y ');
        END IF;
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
    -- [MIG624] Con cuadrilla hay más de un reloj abierto: se cierran todos y
    -- las horas de todos van a la OT.
    SELECT COALESCE(sum(COALESCE(e.tiempo_efectivo_segundos, 0)
             + CASE WHEN e.estado = 'en_ejecucion'
                    THEN GREATEST(0, EXTRACT(EPOCH FROM (NOW() - e.last_event_at))::INT) ELSE 0 END), 0)::INT
      INTO v_otros
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = v_ot AND e.estado IN ('en_ejecucion','pausada') AND e.id <> p_ejecucion_id;
    PERFORM fn_taller_cerrar_ejecuciones_abiertas(v_ot, p_observacion);

    UPDATE ordenes_trabajo
       -- [MIG624] Sin el cast el CASE salía como text y Finalizar desde el tablero
       -- fallaba siempre («estado is of type estado_ot_enum but expression is of type text»).
       SET estado = (CASE WHEN p_avance_final >= 100 THEN 'ejecutada_ok' ELSE 'ejecutada_con_observaciones' END)::estado_ot_enum,
           fecha_termino = NOW(),
           horas_hombre = COALESCE(horas_hombre, 0) + ((v_t_efectivo + v_otros)::NUMERIC / 3600.0),
           updated_at = NOW()
     WHERE id = v_ot;

    -- [MIG310] Lo que se hizo queda escrito en la OT, con las lecturas del
    -- equipo de ese momento. Nunca puede tumbar el cierre del taller.
    BEGIN
        PERFORM public.fn_ot_congelar_trabajo(v_ot, p_observacion);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'No se pudo congelar el trabajo de la OT %: %', v_ot, SQLERRM;
    END;

    PERFORM fn_taller_marcar_cierre(v_ot, 'tablero');

    RETURN jsonb_build_object(
        'success', true,
        'tiempo_efectivo_seg', v_t_efectivo,
        'tiempo_pausado_seg', v_t_pausado,
        'tiempo_colacion_seg', v_t_colacion,
        'avance_final', p_avance_final
    );
END;
$function$;

-- ── 6. Quitar la jornada detiene el reloj de todos ──────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_quitar_jornada(p_plan_ot_id uuid, p_detener boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    r           RECORD;
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
        -- [MIG624] Con cuadrilla puede haber un reloj por persona: se detienen todos.
        FOR r IN
            SELECT e.id, e.estado, e.last_event_at, e.started_at,
                   COALESCE(e.tiempo_efectivo_segundos, 0) AS efectivo
              FROM taller_ot_ejecuciones e
             WHERE e.plan_semanal_ot_id = p_plan_ot_id
               AND e.estado IN ('en_ejecucion','pausada')
        LOOP
            v_efectivo := r.efectivo;
            IF r.estado = 'en_ejecucion' THEN
                v_efectivo := v_efectivo + GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.last_event_at))::INT);
            END IF;

            UPDATE taller_ot_ejecuciones
               SET estado                   = 'cancelada',
                   finished_at              = NOW(),
                   tiempo_efectivo_segundos = v_efectivo,
                   tiempo_total_segundos    = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - r.started_at))::INT),
                   observacion_cierre       = 'Detenida al quitar la jornada del plan semanal',
                   last_event_at            = NOW(),
                   updated_at               = NOW()
             WHERE id = r.id;

            INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, comentario, created_by)
            VALUES (r.id, v_ot, 'cancel', 'La jornada se quitó del plan semanal', v_user);

            v_detenida := TRUE;
        END LOOP;
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
$function$;

-- ── 7. La cuadrilla llega a 4 ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_set_cuadrilla(p_plan_ot_id uuid, p_tecnico_ids uuid[], p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_texto  TEXT;
    v_n      INT;
    v_max    INT := 4;   -- [MIG624] mismo tope que MAX_MECANICOS en la app
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','jefe_operaciones','planificador') THEN
        RAISE EXCEPTION 'Tu perfil no puede asignar mecánicos.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id) THEN
        RAISE EXCEPTION 'La jornada no existe.';
    END IF;

    v_n := COALESCE(array_length(p_tecnico_ids, 1), 0);
    IF v_n > v_max THEN
        RAISE EXCEPTION 'Como máximo % mecánicos por jornada.', v_max;
    END IF;

    IF v_n > 0 AND EXISTS (
        SELECT 1 FROM unnest(p_tecnico_ids) AS x(id)
         WHERE NOT EXISTS (SELECT 1 FROM taller_tecnicos t
                            WHERE t.id = x.id AND COALESCE(t.activo, TRUE))
    ) THEN
        RAISE EXCEPTION 'Alguno de los técnicos no existe o está inactivo.';
    END IF;

    -- Fuera los que ya no están. El trigger de MIG446 bloquea si la OT ya se
    -- ejecutó, y anota la baja en la bitácora.
    DELETE FROM taller_ot_cuadrilla c
     WHERE c.plan_ot_id = p_plan_ot_id
       AND (v_n = 0 OR NOT (c.tecnico_id = ANY(p_tecnico_ids)));

    -- Y dentro los nuevos. El primero de la lista queda como titular.
    IF v_n > 0 THEN
        INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol, declarada_por, origen)
        SELECT p_plan_ot_id,
               x.id,
               CASE WHEN x.orden = 1 THEN 'titular' ELSE 'apoyo' END,
               v_user,
               'manual'
          FROM unnest(p_tecnico_ids) WITH ORDINALITY AS x(id, orden)
        ON CONFLICT (plan_ot_id, tecnico_id) DO NOTHING;
    END IF;

    -- El texto se deriva de la tabla, nunca al revés.
    SELECT string_agg(t.nombre, ', ' ORDER BY c.rol DESC, t.nombre)
      INTO v_texto
      FROM taller_ot_cuadrilla c
      JOIN taller_tecnicos t ON t.id = c.tecnico_id
     WHERE c.plan_ot_id = p_plan_ot_id;

    UPDATE taller_plan_semanal_ots
       SET cuadrilla = v_texto,
           observaciones = CASE
               WHEN COALESCE(length(trim(p_motivo)), 0) > 0
               THEN trim(COALESCE(observaciones, '') || E'\n[Cambio de cuadrilla] ' || trim(p_motivo))
               ELSE observaciones END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;

    RETURN jsonb_build_object('success', true, 'cuadrilla', v_texto, 'personas', v_n);
END;
$function$;

-- ── 8. El tablero ve quién está trabajando ──────────────────────────────────
CREATE OR REPLACE VIEW v_taller_plan_semanal_ots_full AS
 SELECT t.id AS plan_ot_id,
    t.plan_semanal_id,
    t.plan_dia_id,
    d.fecha AS dia_fecha,
    d.nombre_dia AS dia_nombre,
    d.orden AS dia_orden,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado AS plan_estado,
    t.ot_id,
    ot.folio AS ot_folio,
    ot.tipo AS ot_tipo,
    ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad,
    ot.preparacion_ok_at,
    ot.fecha_programada AS ot_fecha_programada,
    ot.plan_mantenimiento_id,
    pm.nombre AS pm_nombre,
    pm.proxima_ejecucion_fecha AS pm_proxima_fecha,
    ot.activo_id,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.patente AS activo_patente,
    a.tipo AS activo_tipo,
    ot.faena_id,
    f.nombre AS faena_nombre,
    ot.contrato_id,
    c.codigo AS contrato_codigo,
    c.cliente AS contrato_cliente,
    COALESCE(t.responsable_id, ot.responsable_id) AS responsable_id,
    COALESCE(up.nombre_completo, up_ot.nombre_completo) AS responsable,
    t.cuadrilla,
    t.horas_planificadas,
    t.avance_objetivo_pct,
    t.secuencia_jornada,
    t.estado_plan AS jornada_estado,
    t.observaciones,
    t.categoria,
    t.ot_id IS NULL AS es_tarea_libre,
    COALESCE(t.titulo, ot.folio) AS titulo,
    t.descripcion AS tarea_descripcion,
    t.equipo_externo,
    COALESCE(t.operacion, a.operacion) AS operacion,
    t.tecnico_id,
    tt.nombre AS tecnico_nombre,
    tt.especialidad AS tecnico_especialidad,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = t.ot_id AND v.excluido = false) AS checklist_total,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = t.ot_id AND v.excluido = false AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente'::resultado_item_enum) AS checklist_completados,
    ( SELECT COALESCE(sum(v.tiempo_min), 0::numeric) AS "coalesce"
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = t.ot_id AND v.excluido = false) AS tiempo_estimado_total_min,
    ( SELECT e.id
           FROM taller_ot_ejecuciones e
          WHERE e.ot_id = t.ot_id AND (e.estado::text = ANY (ARRAY['en_ejecucion'::text, 'pausada'::text]))
         ORDER BY (e.estado::text = 'en_ejecucion'::text) DESC, e.started_at DESC
         LIMIT 1) AS ejecucion_activa_id,
    ( SELECT e.estado
           FROM taller_ot_ejecuciones e
          WHERE e.ot_id = t.ot_id AND (e.estado::text = ANY (ARRAY['en_ejecucion'::text, 'pausada'::text]))
         ORDER BY (e.estado::text = 'en_ejecucion'::text) DESC, e.started_at DESC
         LIMIT 1) AS ejecucion_activa_estado,
    ( SELECT e.avance_final
           FROM taller_ot_ejecuciones e
          WHERE e.ot_id = t.ot_id AND e.estado::text = 'finalizada'::text
          ORDER BY e.finished_at DESC
         LIMIT 1) AS ultima_ejecucion_avance,
    t.created_at,
    t.updated_at,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object(
                'ejecucion_id', e.id,
                'tecnico_id', e.tecnico_id,
                'tecnico', COALESCE(tr.nombre, 'Sin nombre'),
                'estado', e.estado,
                'segundos', COALESCE(e.tiempo_efectivo_segundos, 0)
                    + CASE WHEN e.estado::text = 'en_ejecucion'
                           THEN GREATEST(0, EXTRACT(epoch FROM now() - e.last_event_at))::integer ELSE 0 END)
                ORDER BY (e.estado::text = 'en_ejecucion') DESC, tr.nombre)
           FROM taller_ot_ejecuciones e
             LEFT JOIN taller_tecnicos tr ON tr.id = e.tecnico_id
          WHERE e.ot_id = t.ot_id AND (e.estado::text = ANY (ARRAY['en_ejecucion'::text, 'pausada'::text]))), '[]'::jsonb) AS relojes
   FROM taller_plan_semanal_ots t
     JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     JOIN taller_planes_semanales ps ON ps.id = t.plan_semanal_id
     LEFT JOIN ordenes_trabajo ot ON ot.id = t.ot_id
     LEFT JOIN planes_mantenimiento pm ON pm.id = ot.plan_mantenimiento_id
     LEFT JOIN activos a ON a.id = ot.activo_id
     LEFT JOIN faenas f ON f.id = ot.faena_id
     LEFT JOIN contratos c ON c.id = ot.contrato_id
     LEFT JOIN usuarios_perfil up ON up.id = t.responsable_id
     LEFT JOIN usuarios_perfil up_ot ON up_ot.id = ot.responsable_id
     LEFT JOIN taller_tecnicos tt ON tt.id = t.tecnico_id;

-- ── 9. Y el teléfono ve su reloj y el de sus compañeros ──────────────────────
CREATE OR REPLACE VIEW v_taller_mecanico_ots AS
 SELECT ot_id,
    ot_folio,
    ot_tipo,
    ot_estado,
    ot_prioridad,
    preparacion_ok_at,
    fecha_programada,
    activo_id,
    activo_codigo,
    activo_nombre,
    activo_patente,
    cuadrilla,
    responsable_id,
    responsable,
    asignada_a_mi,
    checklist_total,
    checklist_completados,
    tiempo_estimado_total_min,
    horas_planificadas,
    fecha_entrega_plan,
    COALESCE(( SELECT min(d.fecha) AS min
           FROM taller_plan_semanal_ots po
             JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
          WHERE po.ot_id = sub.ot_id AND COALESCE(po.estado_plan, 'planificada'::character varying)::text <> 'cancelada'::text AND d.fecha >= CURRENT_DATE), ( SELECT max(d.fecha) AS max
           FROM taller_plan_semanal_ots po
             JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
          WHERE po.ot_id = sub.ot_id AND COALESCE(po.estado_plan, 'planificada'::character varying)::text <> 'cancelada'::text), fecha_programada) AS fecha_grupo,
    ( SELECT string_agg(DISTINCT po.titulo::text, ' · '::text) AS string_agg
           FROM taller_plan_semanal_ots po
          WHERE po.ot_id = sub.ot_id AND po.titulo IS NOT NULL) AS tarea_titulo,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object(
                'ejecucion_id', e.id,
                'tecnico_id', e.tecnico_id,
                'tecnico', COALESCE(tr.nombre, 'Sin nombre'),
                'estado', e.estado,
                'segundos', COALESCE(e.tiempo_efectivo_segundos, 0)
                    + CASE WHEN e.estado::text = 'en_ejecucion'
                           THEN GREATEST(0, EXTRACT(epoch FROM now() - e.last_event_at))::integer ELSE 0 END)
                ORDER BY (e.estado::text = 'en_ejecucion') DESC, tr.nombre)
           FROM taller_ot_ejecuciones e
             LEFT JOIN taller_tecnicos tr ON tr.id = e.tecnico_id
          WHERE e.ot_id = sub.ot_id AND (e.estado::text = ANY (ARRAY['en_ejecucion'::text, 'pausada'::text]))), '[]'::jsonb) AS relojes
   FROM ( SELECT ot.id AS ot_id,
            ot.folio AS ot_folio,
            ot.tipo AS ot_tipo,
            ot.estado AS ot_estado,
            ot.prioridad AS ot_prioridad,
            ot.preparacion_ok_at,
            ot.fecha_programada,
            ot.activo_id,
            a.codigo AS activo_codigo,
            a.nombre AS activo_nombre,
            a.patente AS activo_patente,
            ( SELECT string_agg(n.nombre, ', '::text ORDER BY n.nombre) AS string_agg
                   FROM ( SELECT DISTINCT TRIM(BOTH FROM x.nombre) AS nombre
                           FROM taller_plan_semanal_ots t,
                            LATERAL unnest(string_to_array(t.cuadrilla::text, ','::text)) x(nombre)
                          WHERE t.ot_id = ot.id AND NULLIF(TRIM(BOTH FROM x.nombre), ''::text) IS NOT NULL) n) AS cuadrilla,
            ot.responsable_id,
            COALESCE(tt.nombre, up.nombre_completo) AS responsable,
            fn_taller_ot_asignada_al_usuario(ot.id) AS asignada_a_mi,
            ( SELECT count(*) AS count
                   FROM v_taller_ot_checklist_v3 v
                  WHERE v.ot_id = ot.id AND v.excluido = false) AS checklist_total,
            ( SELECT count(*) AS count
                   FROM v_taller_ot_checklist_v3 v
                  WHERE v.ot_id = ot.id AND v.excluido = false AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente'::resultado_item_enum) AS checklist_completados,
            ( SELECT COALESCE(sum(v.tiempo_min), 0::numeric) AS "coalesce"
                   FROM v_taller_ot_checklist_v3 v
                  WHERE v.ot_id = ot.id AND v.excluido = false) AS tiempo_estimado_total_min,
            ( SELECT sum(po.horas_planificadas) AS sum
                   FROM taller_plan_semanal_ots po
                  WHERE po.ot_id = ot.id AND COALESCE(po.estado_plan, 'planificada'::character varying)::text <> 'cancelada'::text) AS horas_planificadas,
            ( SELECT max(d.fecha) AS max
                   FROM taller_plan_semanal_ots po
                     JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
                  WHERE po.ot_id = ot.id AND COALESCE(po.estado_plan, 'planificada'::character varying)::text <> 'cancelada'::text) AS fecha_entrega_plan
           FROM ordenes_trabajo ot
             JOIN activos a ON a.id = ot.activo_id
             LEFT JOIN taller_tecnicos tt ON tt.id = ot.tecnico_id
             LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
          WHERE ot.preparacion_ok_at IS NOT NULL AND (ot.estado = ANY (ARRAY['asignada'::estado_ot_enum, 'en_ejecucion'::estado_ot_enum, 'pausada'::estado_ot_enum]))
          ORDER BY (
                CASE ot.estado
                    WHEN 'en_ejecucion'::estado_ot_enum THEN 1
                    WHEN 'pausada'::estado_ot_enum THEN 2
                    ELSE 3
                END), (
                CASE ot.prioridad
                    WHEN 'emergencia'::prioridad_enum THEN 1
                    WHEN 'urgente'::prioridad_enum THEN 2
                    WHEN 'alta'::prioridad_enum THEN 3
                    WHEN 'normal'::prioridad_enum THEN 4
                    ELSE 5
                END), ot.fecha_programada) sub;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'uq_taller_ejec_activa_ot') THEN
        RAISE EXCEPTION 'FALLO: sigue el índice de una ejecución por OT'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_taller_pausar_ejecucion_ot' AND pronargs = 4) THEN
        RAISE EXCEPTION 'FALLO: pausar por OT sin técnico'; END IF;
    IF pg_get_functiondef('rpc_taller_set_cuadrilla(uuid,uuid[],text)'::regprocedure) NOT LIKE '%v_max    INT := 4%' THEN
        RAISE EXCEPTION 'FALLO: tope de cuadrilla'; END IF;
END $$;

SELECT (SELECT count(*) FROM taller_ot_ejecuciones WHERE estado IN ('en_ejecucion','pausada')) AS relojes_abiertos,
       (SELECT count(*) FROM v_taller_plan_semanal_ots_full WHERE jsonb_array_length(relojes) > 0) AS jornadas_con_reloj,
       (SELECT count(*) FROM v_taller_mecanico_ots WHERE jsonb_array_length(relojes) > 0) AS ots_movil_con_reloj;
