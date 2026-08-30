-- ============================================================================
-- MIG445 · Para cerrar una OT tiene que haber trabajo, y por una sola puerta
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 30-08-2026, al empezar a trazar los incentivos del taller: «para cerrar tiene
-- que existir trabajo, y hay que crear el sistema antifraude, porque esto es
-- dinero».
--
-- LO QUE SE ENCONTRÓ, QUE ES PEOR
-- No es que el jefe de taller no pueda cerrar: ya puede. `rpc_transicion_ot`
-- autoriza a administrador, jefe_mantenimiento, jefe_operaciones y planificador
-- desde MIG196. El problema es que hay DOS PUERTAS para cerrar una OT y sólo una
-- tiene cerradura:
--
--   · rpc_taller_finalizar_mecanico  (app de terreno)
--       exige firma del técnico + horómetro + kilometraje
--
--   · rpc_taller_finalizar_ejecucion (tablero del plan semanal)
--       no exige NADA: ni firma, ni medidores, ni checklist, ni rol.
--       Escribe ordenes_trabajo.estado = 'ejecutada_ok' directo.
--
-- Es decir: la puerta que usa la jefatura —la misma que va a decidir cuánto se
-- le paga a cada mecánico— cierra una OT sin una sola prueba de que el trabajo
-- ocurrió. Mientras el cierre no valía plata daba lo mismo. Desde septiembre el
-- cierre ES la plata.
--
-- QUÉ SE HACE
--   1. `fn_taller_ot_tiene_trabajo`: qué cuenta como trabajo, en un solo lugar,
--      para que las dos puertas midan con la misma vara.
--   2. Las dos puertas exigen lo mismo: trabajo registrado y medidores.
--   3. Queda escrito QUIÉN cerró, POR DÓNDE y si esa persona era de la
--      cuadrilla que ejecuta —el autocierre no se prohíbe, se marca, que es lo
--      que sirve para auditar—.
--
-- QUÉ NO SE HACE ACÁ, A PROPÓSITO
--   El reparto del bono entre cuadrilla, el prorrateo y el bloqueo de trabajos
--   a externos dependen de decisiones de criterio que todavía no están en acta.
--   Esto es la puerta; el motor viene después y se apoya en ella.
-- ============================================================================

BEGIN;

-- ── 1 · Qué cuenta como trabajo ─────────────────────────────────────────────
--
-- Un checklist con ítems respondidos, o tiempo de ejecución medido. Cualquiera
-- de los dos basta: hay OT de una hora que se resuelven sin checklist y hay
-- checklists largos que se responden sin cronómetro. Lo que no puede pasar es
-- que no haya ninguno de los dos y la OT figure ejecutada.
CREATE OR REPLACE FUNCTION fn_taller_ot_tiene_trabajo(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_items    INT := 0;
    v_seg      INT := 0;
    v_inst     UUID;
BEGIN
    SELECT i.id INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;

    IF v_inst IS NOT NULL THEN
        SELECT count(*) INTO v_items
          FROM checklist_v2_instance_item ii
         WHERE ii.instance_id = v_inst
           AND COALESCE(ii.excluido, FALSE) = FALSE
           AND (
                 (ii.resultado IS NOT NULL AND ii.resultado::TEXT <> 'pendiente')
              OR ii.valor_numerico IS NOT NULL
              OR NULLIF(trim(COALESCE(ii.observacion, '')), '') IS NOT NULL
              OR COALESCE(array_length(ii.foto_urls, 1), 0) > 0
           );
    END IF;

    SELECT COALESCE(sum(GREATEST(e.tiempo_efectivo_segundos, 0)), 0)::INT INTO v_seg
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = p_ot_id;

    RETURN jsonb_build_object(
        'tiene',             (v_items > 0 OR v_seg > 0),
        'items_respondidos', v_items,
        'segundos',          v_seg
    );
END;
$$;

COMMENT ON FUNCTION fn_taller_ot_tiene_trabajo IS
'Qué cuenta como trabajo para poder cerrar una OT: ítems de checklist respondidos o tiempo de ejecución medido (MIG445).';

-- ── 2 · Quién cerró, por dónde, y si se cerró a sí mismo ────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS cerrada_por  UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS cerrada_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cerrada_via  TEXT,
  ADD COLUMN IF NOT EXISTS cierre_propio BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN ordenes_trabajo.cerrada_via IS
'Por qué puerta se cerró: terreno (app del mecánico) o tablero (plan semanal). MIG445.';
COMMENT ON COLUMN ordenes_trabajo.cierre_propio IS
'TRUE si quien cerró figuraba en la cuadrilla que ejecuta. No se prohíbe: se marca, para poder auditarlo. MIG445.';

DO $mig$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ot_cerrada_via') THEN
        ALTER TABLE ordenes_trabajo
          ADD CONSTRAINT chk_ot_cerrada_via
          CHECK (cerrada_via IS NULL OR cerrada_via IN ('terreno','tablero'));
    END IF;
END
$mig$;

-- Deja la marca del cierre. Se llama desde las dos puertas para que la huella
-- sea la misma venga de donde venga.
CREATE OR REPLACE FUNCTION fn_taller_marcar_cierre(p_ot_id UUID, p_via TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_nombre TEXT;
    v_propio BOOLEAN := FALSE;
BEGIN
    SELECT up.nombre_completo INTO v_nombre FROM usuarios_perfil up WHERE up.id = v_user;

    -- ¿El que cierra es de la cuadrilla? La cuadrilla es texto libre por ahora
    -- —queda estructurada cuando se defina el reparto del bono—, así que se
    -- compara por nombre, que es lo que ese campo guarda hoy.
    IF v_nombre IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM taller_plan_semanal_ots po
             WHERE po.ot_id = p_ot_id
               AND po.cuadrilla ILIKE '%' || split_part(v_nombre, ' ', 1) || '%'
        ) INTO v_propio;
    END IF;

    UPDATE ordenes_trabajo
       SET cerrada_por   = v_user,
           cerrada_at    = NOW(),
           cerrada_via   = p_via,
           cierre_propio = COALESCE(v_propio, FALSE),
           updated_at    = NOW()
     WHERE id = p_ot_id;
END;
$$;

-- ── 3 · La puerta del terreno, con el control de trabajo ────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_finalizar_mecanico(
    p_ot_id UUID,
    p_firma_tecnico_url TEXT,
    p_con_observaciones BOOLEAN DEFAULT FALSE,
    p_observaciones TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
    v_trabajo JSONB;
    v_res JSONB;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_firma_tecnico_url IS NULL OR length(trim(p_firma_tecnico_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del técnico es obligatoria para finalizar'; END IF;

    -- [MIG445] Sin trabajo registrado no hay OT que cerrar.
    v_trabajo := fn_taller_ot_tiene_trabajo(p_ot_id);
    IF NOT (v_trabajo->>'tiene')::BOOLEAN THEN
        RAISE EXCEPTION 'Esta OT no tiene trabajo registrado: no hay ningún ítem respondido ni tiempo de ejecución. Marca el checklist o usa el cronómetro antes de finalizar.';
    END IF;

    -- [MIG397] Con cuánto uso volvió el equipo se anota antes de cerrar.
    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
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
            RAISE EXCEPTION 'Falta anotar % del equipo. Está arriba de la lista de tareas, en «Medidores del equipo».',
                array_to_string(v_falta, ' y ');
        END IF;
    END IF;

    UPDATE ordenes_trabajo SET firma_tecnico_url = p_firma_tecnico_url, updated_at = NOW() WHERE id = p_ot_id;

    v_res := rpc_transicion_ot(
        p_ot_id,
        (CASE WHEN p_con_observaciones THEN 'ejecutada_con_observaciones' ELSE 'ejecutada_ok' END)::estado_ot_enum,
        v_user, NULL, NULL, p_observaciones, NULL);

    PERFORM fn_taller_marcar_cierre(p_ot_id, 'terreno');
    RETURN v_res;
END;
$$;

COMMIT;

BEGIN;

-- ── 4 · La puerta del tablero, con la MISMA cerradura ───────────────────────
--
-- Esta es la que usa la jefatura desde el plan semanal, y hasta hoy cerraba la
-- OT sin pedir nada. Ahora pide lo mismo que la de terreno: trabajo registrado
-- y medidores anotados. Lo único que no pide es la firma del técnico —quien
-- cierra desde el tablero no es el técnico— y por eso queda marcado que el
-- cierre vino por acá.
CREATE OR REPLACE FUNCTION rpc_taller_finalizar_ejecucion(
    p_ejecucion_id UUID,
    p_avance_final NUMERIC DEFAULT 100,
    p_observacion  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_started TIMESTAMPTZ; v_ot UUID; v_plan_ot UUID;
    v_t_efectivo INT; v_t_pausado INT; v_t_colacion INT;
    v_trabajo JSONB; v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
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
    UPDATE ordenes_trabajo
       SET estado = CASE WHEN p_avance_final >= 100 THEN 'ejecutada_ok' ELSE 'ejecutada_con_observaciones' END,
           fecha_termino = NOW(),
           horas_hombre = COALESCE(horas_hombre, 0) + (v_t_efectivo::NUMERIC / 3600.0),
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
$$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_ot   UUID;
    v_r    JSONB;
    v_sin  INT;
BEGIN
    -- La función de trabajo responde sobre una OT real
    SELECT ot.id INTO v_ot FROM ordenes_trabajo ot
     WHERE EXISTS (SELECT 1 FROM checklist_v2_instance i WHERE i.ot_id = ot.id)
     LIMIT 1;
    IF v_ot IS NOT NULL THEN
        v_r := fn_taller_ot_tiene_trabajo(v_ot);
        RAISE NOTICE 'fn_taller_ot_tiene_trabajo OK: %', v_r::TEXT;
    END IF;

    -- Cuántas OT abiertas hoy NO podrían cerrarse por falta de trabajo
    SELECT count(*) INTO v_sin
      FROM ordenes_trabajo ot
     WHERE ot.estado IN ('creada','asignada','en_ejecucion','pausada')
       AND NOT (fn_taller_ot_tiene_trabajo(ot.id)->>'tiene')::BOOLEAN;
    RAISE NOTICE 'OT abiertas sin ningún trabajo registrado: %', v_sin;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='ordenes_trabajo'
                      AND column_name='cierre_propio') THEN
        RAISE EXCEPTION 'FALLO: no quedó la marca de cierre';
    END IF;
    RAISE NOTICE 'las dos puertas exigen lo mismo y dejan huella';
END
$mig$;

COMMIT;
