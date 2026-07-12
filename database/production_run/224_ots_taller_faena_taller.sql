-- ============================================================================
-- SICOM-ICEO | 224 — OTs de taller toman la faena del taller
-- ============================================================================
-- Problema: las OTs creadas desde el plan de taller heredaban la faena del
-- activo (ej. la faena del arriendo "San Antonio — Lambert"), que no tiene
-- bodegas. rpc_registrar_salida_inventario exige bodega.faena = ot.faena,
-- por lo que los vales de esas OTs eran IMPOSIBLES de despachar.
--
-- Fix:
--   1. fn_faena_taller_para_activo(activo): faena del taller según la
--      operación del activo (Calama → FAE-TALLER-CAL, resto → FAE-TALLER-CQB).
--   2. rpc_programar_ot_taller crea la OT ya con la faena del taller.
--   3. rpc_taller_agregar_jornada_ot (el embudo por el que pasa TODA OT que
--      entra al plan: preventivas, recepciones, correctivos NC) re-asigna la
--      faena del taller al agendar.
--   4. Data fix: OTs ya agendadas en el plan de taller → faena del taller.
-- ============================================================================

-- ── 1. Helper ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_faena_taller_para_activo(p_activo_id uuid)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE WHEN a.operacion = 'Calama'
              THEN (SELECT f.id FROM faenas f WHERE f.codigo = 'FAE-TALLER-CAL')
              ELSE (SELECT f.id FROM faenas f WHERE f.codigo = 'FAE-TALLER-CQB')
         END
    FROM activos a
   WHERE a.id = p_activo_id
$$;

GRANT EXECUTE ON FUNCTION fn_faena_taller_para_activo(uuid) TO authenticated;

-- ── 2. rpc_programar_ot_taller: OT nace con la faena del taller ──────────────
CREATE OR REPLACE FUNCTION public.rpc_programar_ot_taller(
    p_activo_id uuid,
    p_tipo tipo_ot_enum,
    p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha date DEFAULT NULL::date,
    p_responsable_id uuid DEFAULT NULL::uuid,
    p_plan_mantenimiento_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_contrato_id uuid;
    v_faena_id    uuid;
    v_a_contrato  uuid;
    v_a_faena     uuid;
BEGIN
    SELECT contrato_id, faena_id INTO v_a_contrato, v_a_faena FROM activos WHERE id = p_activo_id;

    -- Contrato: el del activo si está activo; si no, el contrato interno.
    SELECT id INTO v_contrato_id FROM contratos WHERE id = v_a_contrato AND estado = 'activo';
    IF v_contrato_id IS NULL THEN v_contrato_id := fn_contrato_interno_id(); END IF;

    -- Faena: la del TALLER (el trabajo se hace ahí y sus vales salen de la
    -- bodega del taller), no la del arriendo del equipo.
    v_faena_id := COALESCE(fn_faena_taller_para_activo(p_activo_id), v_a_faena, fn_faena_interna_id());

    RETURN rpc_crear_ot(p_tipo, v_contrato_id, v_faena_id, p_activo_id, p_prioridad,
                        p_fecha, p_responsable_id, p_plan_mantenimiento_id, auth.uid());
END;
$function$;

-- ── 3. rpc_taller_agregar_jornada_ot: re-asigna faena al agendar ─────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_agregar_jornada_ot(
    p_plan_semanal_id uuid, p_ot_id uuid, p_fecha date,
    p_responsable_id uuid DEFAULT NULL::uuid,
    p_cuadrilla character varying DEFAULT NULL::character varying,
    p_horas_planificadas numeric DEFAULT NULL::numeric,
    p_avance_objetivo numeric DEFAULT NULL::numeric,
    p_observaciones text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_dia_id UUID;
    v_plan_ot_id UUID;
    v_secuencia INT;
    v_rol TEXT;
    v_faena_taller UUID;
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

    -- [MIG224] La OT agendada en el taller pasa a la faena del taller: sus
    -- vales se despachan desde la bodega del taller, no la del arriendo.
    SELECT fn_faena_taller_para_activo(o.activo_id) INTO v_faena_taller
      FROM ordenes_trabajo o WHERE o.id = p_ot_id AND o.activo_id IS NOT NULL;
    IF v_faena_taller IS NOT NULL THEN
        UPDATE ordenes_trabajo
           SET faena_id = v_faena_taller, updated_at = NOW()
         WHERE id = p_ot_id AND faena_id IS DISTINCT FROM v_faena_taller;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'plan_ot_id', v_plan_ot_id,
        'secuencia', v_secuencia
    );
END;
$function$;

-- ── 4. Data fix: OTs ya agendadas en el plan de taller ───────────────────────
UPDATE ordenes_trabajo o
   SET faena_id = fn_faena_taller_para_activo(o.activo_id), updated_at = NOW()
 WHERE o.id IN (SELECT DISTINCT ot_id FROM taller_plan_semanal_ots WHERE ot_id IS NOT NULL)
   AND o.activo_id IS NOT NULL
   AND fn_faena_taller_para_activo(o.activo_id) IS NOT NULL
   AND o.faena_id IS DISTINCT FROM fn_faena_taller_para_activo(o.activo_id);

DO $$
DECLARE v_pend INT;
BEGIN
    SELECT count(*) INTO v_pend
      FROM bodega_tickets t
      JOIN ordenes_trabajo o ON o.id = t.ot_id
     WHERE t.estado IN ('emitido','parcial')
       AND (SELECT count(*) FROM bodegas b WHERE b.faena_id = o.faena_id) = 0;
    RAISE NOTICE 'MIG224 OK: OTs de taller con faena de taller. Vales pendientes sin bodega en su faena: %', v_pend;
END $$;
