-- ============================================================================
-- 24_calama_responsable_plan_y_ot.sql
-- ----------------------------------------------------------------------------
-- Fix: operador no ve OTs asignadas en plan_semanal_ots porque la RLS de
-- calama_ordenes_trabajo solo deja al operador ver OTs donde es responsable
-- DIRECTO (calama_ordenes_trabajo.responsable_id = auth.uid()).
--
-- DIAGNOSTICO:
--   - rpc_calama_mover_ot_plan_semanal y rpc_calama_asignar_responsable_ot_semana
--     escriben responsable_id solo en calama_plan_semanal_ots.
--   - calama_ordenes_trabajo.responsable_id queda NULL.
--   - /m/calama lee plan_semanal_ots (ve la asignacion) pero al hacer JOIN con
--     calama_ordenes_trabajo no ve la OT madre por RLS -> tarjeta vacia.
--
-- FIX en 2 capas (defensa en profundidad):
--   1. Helper SECURITY DEFINER fn_calama_uid_responsable_en_plan_ot(uuid):
--      bypassea RLS de plan_semanal_ots y verifica si auth.uid() es
--      responsable de ALGUN plan_ot de la OT.
--   2. Nueva policy SELECT en calama_ordenes_trabajo que permite al operador
--      ver la OT cuando es responsable via plan_semanal_ots.
--   3. Las dos RPCs de asignacion (mover + asignar_responsable) se actualizan
--      para que tambien sincronicen calama_ordenes_trabajo.responsable_id.
--      Esto provee consistencia de datos y permite a otras vistas (admin,
--      detalle OT) ver el responsable global.
--
-- AISLACION:
--   - NO toca otras MIGs ni RLS de otras tablas.
--   - NO desactiva RLS.
--   - Las RPCs nuevas mantienen firma identica (drop-in replacement).
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_RESP / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots') THEN
        RAISE EXCEPTION 'STOP - MIG20 no aplicada (calama_plan_semanal_ots no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_es_operador()') IS NULL THEN
        RAISE EXCEPTION 'STOP - fn_calama_es_operador() no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. HELPER SECURITY DEFINER ───────────────────────────────────────────────
-- ============================================================================
-- Verifica si auth.uid() es responsable de ESTA OT en algun plan_semanal_ots.
-- SECURITY DEFINER bypassea la RLS de plan_semanal_ots para evitar recursion.
CREATE OR REPLACE FUNCTION fn_calama_uid_responsable_en_plan_ot(p_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_plan_semanal_ots
         WHERE ot_id = p_ot_id
           AND responsable_id = auth.uid()
    );
$$;
GRANT EXECUTE ON FUNCTION fn_calama_uid_responsable_en_plan_ot(UUID) TO authenticated;


-- ============================================================================
-- ── 2. POLICY ADICIONAL en calama_ordenes_trabajo ────────────────────────────
-- ============================================================================
-- Permite al operador SELECT cuando es responsable via plan_semanal_ots.
-- No toca las policies existentes (planning + operador-directo). PostgreSQL
-- combina permissive policies con OR.
DROP POLICY IF EXISTS pol_calama_ot_select_op_via_plan ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_select_op_via_plan ON calama_ordenes_trabajo
    FOR SELECT TO authenticated
    USING (
        fn_calama_es_operador()
        AND fn_calama_uid_responsable_en_plan_ot(id)
    );


-- ============================================================================
-- ── 3. RPC: mover OT + sync responsable global ───────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_mover_ot_plan_semanal(
    p_plan_semanal_id UUID,
    p_ot_id UUID,
    p_fecha_destino DATE,
    p_responsable_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_dia_id UUID;
    v_zona UUID;
    v_estado_plan TEXT;
    v_existing_id UUID;
    v_existing_estado TEXT;
    v_plan_estado TEXT;
    v_resp_final UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para mover OTs';
    END IF;

    SELECT estado INTO v_plan_estado FROM calama_planes_semanales WHERE id = p_plan_semanal_id;
    IF v_plan_estado IS NULL THEN RAISE EXCEPTION 'plan_semanal_id no encontrado'; END IF;
    IF v_plan_estado IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_plan_estado;
    END IF;

    SELECT id INTO v_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha_destino;
    IF v_dia_id IS NULL THEN RAISE EXCEPTION 'fecha_destino % no pertenece a este plan', p_fecha_destino; END IF;

    SELECT z.id INTO v_zona
      FROM calama_ordenes_trabajo o
      JOIN calama_planificaciones p ON p.id = o.planificacion_id
      LEFT JOIN calama_zonas_proyecto z
             ON z.planificacion_id = p.id
            AND z.codigo_zona = (regexp_match(o.folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0'
     WHERE o.id = p_ot_id
     LIMIT 1;

    SELECT id, estado_plan INTO v_existing_id, v_existing_estado
      FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    IF v_existing_id IS NOT NULL THEN
        IF v_existing_estado IN ('en_ejecucion','finalizada') THEN
            RAISE EXCEPTION 'OT en estado_plan % no puede moverse', v_existing_estado;
        END IF;
        UPDATE calama_plan_semanal_ots
           SET plan_dia_id = v_dia_id,
               zona_proyecto_id = COALESCE(v_zona, zona_proyecto_id),
               responsable_id = COALESCE(p_responsable_id, responsable_id),
               estado_plan = CASE WHEN p_responsable_id IS NOT NULL AND estado_plan = 'planificada'
                                  THEN 'asignada' ELSE estado_plan END,
               updated_at = NOW()
         WHERE id = v_existing_id
        RETURNING responsable_id INTO v_resp_final;
        v_estado_plan := 'updated';
    ELSE
        INSERT INTO calama_plan_semanal_ots (
            plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id, responsable_id,
            estado_plan, created_by
        ) VALUES (
            p_plan_semanal_id, v_dia_id, p_ot_id, v_zona, p_responsable_id,
            CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
            v_uid
        ) RETURNING id, responsable_id INTO v_existing_id, v_resp_final;
        v_estado_plan := 'inserted';
    END IF;

    -- SYNC: replicar responsable a calama_ordenes_trabajo si vino seteado.
    -- Esto permite que el operador vea la OT por la policy directa, ademas
    -- de la nueva via plan_semanal_ots.
    IF v_resp_final IS NOT NULL THEN
        UPDATE calama_ordenes_trabajo
           SET responsable_id = v_resp_final, updated_at = NOW()
         WHERE id = p_ot_id
           AND (responsable_id IS DISTINCT FROM v_resp_final);
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_existing_id, 'op', v_estado_plan);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_mover_ot_plan_semanal(UUID, UUID, DATE, UUID) TO authenticated;


-- ============================================================================
-- ── 4. RPC: asignar responsable + sync ───────────────────────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_asignar_responsable_ot_semana(
    p_plan_semanal_id UUID,
    p_ot_id UUID,
    p_responsable_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    UPDATE calama_plan_semanal_ots
       SET responsable_id = p_responsable_id,
           estado_plan = CASE WHEN estado_plan = 'planificada' THEN 'asignada' ELSE estado_plan END,
           updated_at = NOW()
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada en este plan'; END IF;

    -- SYNC bidireccional con calama_ordenes_trabajo.responsable_id
    IF p_responsable_id IS NOT NULL THEN
        UPDATE calama_ordenes_trabajo
           SET responsable_id = p_responsable_id, updated_at = NOW()
         WHERE id = p_ot_id
           AND (responsable_id IS DISTINCT FROM p_responsable_id);
    END IF;

    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_asignar_responsable_ot_semana(UUID, UUID, UUID) TO authenticated;


-- ============================================================================
-- ── 5. BACKFILL: sincronizar responsables ya asignados ───────────────────────
-- ============================================================================
-- Si ya planificaste OTs con OOCC antes de este parche, la OT madre tiene
-- responsable_id NULL y este UPDATE las pone al dia.
UPDATE calama_ordenes_trabajo ot
   SET responsable_id = sub.responsable_id, updated_at = NOW()
  FROM (
    SELECT DISTINCT ON (ot_id) ot_id, responsable_id
      FROM calama_plan_semanal_ots
     WHERE responsable_id IS NOT NULL
     ORDER BY ot_id, updated_at DESC
  ) sub
 WHERE ot.id = sub.ot_id
   AND (ot.responsable_id IS DISTINCT FROM sub.responsable_id);


-- ============================================================================
-- ── 6. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG24_CALAMA_RESPONSABLE',
        'Fix operador no ve OTs: helper + policy + sync responsable',
        current_user, NOW(), NOW(), 'ok',
        '1 helper + 1 policy + 2 RPCs sincronizadas + backfill.'
    );
END $$;


-- ============================================================================
-- ── 7. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        (to_regprocedure('public.fn_calama_uid_responsable_en_plan_ot(uuid)') IS NOT NULL) AS helper_ok,
        EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public'
                   AND tablename='calama_ordenes_trabajo'
                   AND policyname='pol_calama_ot_select_op_via_plan') AS policy_ok,
        (to_regprocedure('public.rpc_calama_mover_ot_plan_semanal(uuid,uuid,date,uuid)') IS NOT NULL) AS mover_ok,
        (to_regprocedure('public.rpc_calama_asignar_responsable_ot_semana(uuid,uuid,uuid)') IS NOT NULL) AS asignar_ok,
        (SELECT COUNT(*) FROM calama_ordenes_trabajo
          WHERE responsable_id IS NOT NULL)::int AS ots_con_responsable
)
SELECT
    CASE WHEN helper_ok AND policy_ok AND mover_ok AND asignar_ok
         THEN 'OK_OPERACION_CALAMA_RESP'
         ELSE 'STOP_OPERACION_CALAMA_RESP'
    END AS resultado,
    helper_ok, policy_ok, mover_ok, asignar_ok,
    ots_con_responsable,
    NOW() AS chequeado_en
FROM checks;
