-- ============================================================================
-- 45_calama_fix_reactivar_jornada_desde_backlog.sql
-- ----------------------------------------------------------------------------
-- HOTFIX `rpc_calama_mover_ot_plan_semanal` (MIG20 + MIG24).
--
-- BUG: cuando el planificador arrastra una OT del backlog al Kanban, este RPC
-- busca por (plan_semanal_id, ot_id) y si encuentra fila la actualiza con el
-- nuevo plan_dia_id. Pero NO limpia los flags de ocultacion introducidos en
-- MIG31/32:
--   - desprogramada_at / desprogramada_by / motivo_desprogramacion /
--     observacion_desprogramacion
--   - anulada_at / anulada_by / motivo_anulacion
--   - visible_en_kanban
--   - requiere_decision_programador
--   - estado_plan en ('desprogramada','anulada_prueba','cancelada_operacional',
--     'no_ejecutada','reprogramada')
--
-- Consecuencia: si la OT tuvo una jornada desprogramada/anulada/cancelada
-- antes en la MISMA semana, esta queda como "fantasma" — backlog y mobile la
-- esconden via `jornadaActiva()` (frontend `calama-plan-semanal.ts:88-94`),
-- por lo que la OT vuelve al backlog. El usuario la arrastra; el RPC solo
-- mueve el plan_dia_id; los flags de ocultacion siguen seteados; el toast
-- "OT planificada para X dia" aparece pero la jornada nunca se renderiza en
-- el Kanban.
--
-- FIX: cuando se reusa una fila existente que esta en un estado oculto:
--   1. Resetear estado_plan a 'planificada' (o 'asignada' si llega responsable)
--   2. Limpiar todos los flags de desprogramacion / anulacion
--   3. Forzar visible_en_kanban=true, requiere_decision_programador=false
--   4. Loggear la accion en calama_jornada_auditoria como 'reactivar_desde_backlog'
--
-- Para filas en estados visibles (planificada/asignada/liberada/en_pausa/
-- pendiente_aprobacion/parcial/requiere_correccion/aceptada/rechazada/
-- descargada_offline/finalizada_operador/bloqueada) el comportamiento es el
-- mismo de siempre: solo se cambia plan_dia_id (+ zona + responsable). Para
-- en_ejecucion/finalizada/cerrada se sigue bloqueando con la excepcion previa.
--
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE FUNCTION).
-- NO toca tablas ni datos historicos.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'rpc_calama_mover_ot_plan_semanal'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG20/24 no aplicadas (falta rpc_calama_mover_ot_plan_semanal).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public'
           AND table_name='calama_plan_semanal_ots'
           AND column_name='visible_en_kanban'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG32 no aplicada (falta calama_plan_semanal_ots.visible_en_kanban).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'fn_calama_audit_jornada'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG32 no aplicada (falta fn_calama_audit_jornada).';
    END IF;
END $$;


-- ── Reemplazar funcion ─────────────────────────────────────────────────────
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
    v_op TEXT;
    v_existing_id UUID;
    v_existing_estado TEXT;
    v_estaba_oculta BOOLEAN := false;
    v_plan_estado TEXT;
    v_resp_final UUID;
    v_nuevo_estado TEXT;
    -- Estados que ocultan la jornada del Kanban / mobile (deben ser
    -- coherentes con ESTADOS_JORNADA_OCULTAS en frontend calama-plan-semanal.ts).
    v_estados_ocultos TEXT[] := ARRAY[
        'desprogramada','anulada_prueba','cancelada_operacional',
        'no_ejecutada','reprogramada'
    ];
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

    -- Buscar fila existente. Incluye filas ocultas (desprogramada_at /
    -- anulada_at / visible_en_kanban=false) — ese es el caso que arregla MIG45.
    SELECT id, estado_plan,
           (estado_plan = ANY (v_estados_ocultos)
            OR desprogramada_at IS NOT NULL
            OR anulada_at IS NOT NULL
            OR visible_en_kanban = false)
      INTO v_existing_id, v_existing_estado, v_estaba_oculta
      FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    IF v_existing_id IS NOT NULL THEN
        -- Estados que NO se mueven directamente.
        IF v_existing_estado IN ('en_ejecucion','finalizada','aceptada','cerrada') THEN
            RAISE EXCEPTION 'OT en estado_plan % no puede moverse', v_existing_estado;
        END IF;

        -- Calcular nuevo estado_plan.
        --   - Si la fila estaba oculta -> reactivar a 'planificada' (o 'asignada' si vino responsable).
        --   - Si estaba en 'planificada' y llega responsable -> 'asignada' (comportamiento previo).
        --   - En cualquier otro caso visible -> mantener estado.
        v_nuevo_estado := CASE
            WHEN v_estaba_oculta AND p_responsable_id IS NOT NULL THEN 'asignada'
            WHEN v_estaba_oculta                                   THEN 'planificada'
            WHEN p_responsable_id IS NOT NULL
                 AND v_existing_estado = 'planificada'             THEN 'asignada'
            ELSE v_existing_estado
        END;

        UPDATE calama_plan_semanal_ots
           SET plan_dia_id     = v_dia_id,
               zona_proyecto_id = COALESCE(v_zona, zona_proyecto_id),
               responsable_id  = COALESCE(p_responsable_id, responsable_id),
               estado_plan     = v_nuevo_estado,
               -- Limpieza de flags de ocultacion (no-op si ya estaban en NULL/true/false).
               desprogramada_at            = NULL,
               desprogramada_by            = NULL,
               motivo_desprogramacion      = NULL,
               observacion_desprogramacion = NULL,
               anulada_at                  = NULL,
               anulada_by                  = NULL,
               motivo_anulacion            = NULL,
               visible_en_kanban           = true,
               requiere_decision_programador = false,
               updated_at = NOW()
         WHERE id = v_existing_id
        RETURNING responsable_id INTO v_resp_final;

        v_op := CASE WHEN v_estaba_oculta THEN 'reactivada' ELSE 'updated' END;

        -- Auditoria solo cuando hubo reactivacion (no spamear log con movidas normales).
        IF v_estaba_oculta THEN
            PERFORM fn_calama_audit_jornada(jsonb_build_object(
                'plan_semanal_ot_id', v_existing_id::text,
                'ot_id',              p_ot_id::text,
                'accion',             'reactivar_desde_backlog',
                'estado_anterior',    v_existing_estado,
                'estado_nuevo',       v_nuevo_estado,
                'fecha_nueva',        p_fecha_destino::text,
                'responsable_nuevo',  v_resp_final::text,
                'metadata', jsonb_build_object(
                    'plan_semanal_id', p_plan_semanal_id::text,
                    'plan_dia_id',     v_dia_id::text,
                    'origen',          'rpc_calama_mover_ot_plan_semanal'
                )
            ));
        END IF;
    ELSE
        INSERT INTO calama_plan_semanal_ots (
            plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id, responsable_id,
            estado_plan, created_by
        ) VALUES (
            p_plan_semanal_id, v_dia_id, p_ot_id, v_zona, p_responsable_id,
            CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
            v_uid
        ) RETURNING id, responsable_id INTO v_existing_id, v_resp_final;
        v_op := 'inserted';
    END IF;

    -- SYNC: replicar responsable a calama_ordenes_trabajo si vino seteado.
    -- (Comportamiento MIG24 preservado.)
    IF v_resp_final IS NOT NULL THEN
        UPDATE calama_ordenes_trabajo
           SET responsable_id = v_resp_final, updated_at = NOW()
         WHERE id = p_ot_id
           AND (responsable_id IS DISTINCT FROM v_resp_final);
    END IF;

    RETURN jsonb_build_object(
        'success',     true,
        'plan_ot_id',  v_existing_id,
        'op',          v_op,
        'reactivada',  COALESCE(v_estaba_oculta, false)
    );
END $$;

COMMENT ON FUNCTION rpc_calama_mover_ot_plan_semanal(UUID, UUID, DATE, UUID) IS
'Planifica una OT en un dia del plan semanal. MIG20+24 + fix MIG45 (reactiva jornadas ocultas por desprogramacion/anulacion/cancelacion al re-arrastrar desde backlog, en vez de dejar la fila fantasma).';

GRANT EXECUTE ON FUNCTION rpc_calama_mover_ot_plan_semanal(UUID, UUID, DATE, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
