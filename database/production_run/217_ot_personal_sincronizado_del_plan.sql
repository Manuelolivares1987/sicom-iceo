-- ============================================================================
-- SICOM-ICEO | 217 — El personal asignado en el plan SIEMPRE llega a la OT
-- ============================================================================
-- Bug reportado por Manuel (2026-07-09): asignó al mecánico en el plan del
-- taller pero al abrir la OT el responsable no estaba (o decía "Jefe de
-- Taller"). Es la misma familia de MIG194/195, que arregló SOLO uno de los
-- caminos de asignación (el modal "Editar" del Plan Taller).
--
-- Diagnóstico con datos de prod (jul-2026): varias OTs con cuadrilla asignada
-- en taller_plan_semanal_ots pero ot.tecnico_id NULL y ot.responsable_id NULL
-- o = cuenta del jefe. Tres huecos:
--   1. rpc_taller_asignar_responsable (asignación rápida del Kanban) escribe
--      SOLO el plan, nunca la OT.
--   2. Las jornadas nacen con cuadrilla (p.ej. desde agendar NC) sin pasar
--      por ninguna RPC que sincronice.
--   3. rpc_taller_liberar_ejecucion tapa el hueco con
--      responsable_id = COALESCE(responsable_id, auth.uid()) → la OT queda a
--      nombre del JEFE que libera, no del mecánico asignado.
--
-- Fix estructural (cubre caminos actuales y futuros):
--   1. fn_taller_sync_personal_ot(ot_id): deriva técnico + cuenta responsable
--      desde la jornada más reciente del plan (tecnico_id → cuenta del plan →
--      primer nombre de la cuadrilla si calza con UN técnico activo) y los
--      escribe en la OT. El plan manda.
--   2. TRIGGER en taller_plan_semanal_ots (insert/update de tecnico_id,
--      responsable_id, cuadrilla) → sincroniza la OT. Da lo mismo qué RPC o
--      pantalla asigne: siempre llega a la OT.
--   3. rpc_taller_liberar_ejecucion: sincroniza desde el plan ANTES del
--      fallback al jefe (que queda solo como último recurso, porque iniciar
--      ejecución exige responsable).
--   4. Backfill de todas las OTs con jornadas en el plan.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ordenes_trabajo' AND column_name='tecnico_id') THEN
        RAISE EXCEPTION 'STOP — falta ordenes_trabajo.tecnico_id (MIG195).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='taller_plan_semanal_ots' AND column_name='tecnico_id') THEN
        RAISE EXCEPTION 'STOP — falta taller_plan_semanal_ots.tecnico_id (MIG182).';
    END IF;
END $$;


-- ── 1. Derivar el personal del plan y escribirlo en la OT ────────────────────
CREATE OR REPLACE FUNCTION fn_taller_sync_personal_ot(p_ot_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_tecnico   UUID;
    v_plan_resp UUID;
    v_cuad      TEXT;
    v_resp      UUID;
BEGIN
    IF p_ot_id IS NULL THEN RETURN; END IF;

    -- Jornada más reciente que tenga algún dato de personal
    SELECT t.tecnico_id, t.responsable_id, NULLIF(TRIM(t.cuadrilla), '')
      INTO v_tecnico, v_plan_resp, v_cuad
      FROM taller_plan_semanal_ots t
     WHERE t.ot_id = p_ot_id
       AND (t.tecnico_id IS NOT NULL OR t.responsable_id IS NOT NULL
            OR NULLIF(TRIM(t.cuadrilla), '') IS NOT NULL)
     ORDER BY t.updated_at DESC
     LIMIT 1;

    -- Sin técnico explícito: ¿la cuenta asignada corresponde a un técnico?
    IF v_tecnico IS NULL AND v_plan_resp IS NOT NULL THEN
        SELECT id INTO v_tecnico FROM taller_tecnicos
         WHERE usuario_perfil_id = v_plan_resp AND activo
         ORDER BY nombre LIMIT 1;
    END IF;

    -- Último recurso: primer nombre de la cuadrilla (texto libre del picker),
    -- solo si calza exactamente con UN técnico activo del catálogo.
    IF v_tecnico IS NULL AND v_cuad IS NOT NULL THEN
        SELECT CASE WHEN COUNT(*) = 1 THEN (MIN(id::TEXT))::UUID END INTO v_tecnico
          FROM taller_tecnicos
         WHERE activo
           AND LOWER(TRIM(nombre)) = LOWER(TRIM(split_part(v_cuad, ',', 1)));
    END IF;

    IF v_tecnico IS NULL AND v_plan_resp IS NULL THEN RETURN; END IF;

    -- La cuenta responsable sigue al técnico (si tiene login propio)
    IF v_tecnico IS NOT NULL THEN
        SELECT usuario_perfil_id INTO v_resp FROM taller_tecnicos WHERE id = v_tecnico;
    END IF;

    UPDATE ordenes_trabajo
       SET tecnico_id     = COALESCE(v_tecnico, tecnico_id),
           responsable_id = COALESCE(v_resp, v_plan_resp, responsable_id),
           updated_at     = NOW()
     WHERE id = p_ot_id
       AND (tecnico_id     IS DISTINCT FROM COALESCE(v_tecnico, tecnico_id)
         OR responsable_id IS DISTINCT FROM COALESCE(v_resp, v_plan_resp, responsable_id));
END;
$$;

COMMENT ON FUNCTION fn_taller_sync_personal_ot(UUID) IS
    'Sincroniza tecnico_id/responsable_id de la OT desde la jornada mas reciente del plan taller. El plan manda. MIG217.';


-- ── 2. Trigger: cualquier asignación en el plan llega a la OT ────────────────
CREATE OR REPLACE FUNCTION fn_trg_plan_sync_personal_ot()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_taller_sync_personal_ot(NEW.ot_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_plan_sync_personal_ot ON taller_plan_semanal_ots;
CREATE TRIGGER trg_plan_sync_personal_ot
    AFTER INSERT OR UPDATE OF tecnico_id, responsable_id, cuadrilla
    ON taller_plan_semanal_ots
    FOR EACH ROW EXECUTE FUNCTION fn_trg_plan_sync_personal_ot();


-- ── 3. Liberar a ejecución: primero el plan, el jefe solo como último recurso ─
CREATE OR REPLACE FUNCTION rpc_taller_liberar_ejecucion(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo el jefe de taller libera a ejecucion (rol: %)', v_rol; END IF;

    -- [MIG217] El personal asignado en el plan llega a la OT antes de liberar
    PERFORM fn_taller_sync_personal_ot(p_ot_id);

    UPDATE ordenes_trabajo
       SET preparacion_ok_at = NOW(), preparacion_ok_por = auth.uid(),
           -- la ejecución requiere responsable; si el plan tampoco lo trae,
           -- queda el jefe que libera (ÚLTIMO recurso, no el camino normal)
           responsable_id = COALESCE(responsable_id, auth.uid()),
           estado = CASE WHEN estado='creada' THEN 'asignada' ELSE estado END,
           updated_at = NOW()
     WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'ot_id', p_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_liberar_ejecucion(UUID) TO authenticated;


-- ── 4. Backfill: todas las OTs con jornadas en el plan ───────────────────────
DO $$
DECLARE r RECORD; n INT := 0;
BEGIN
    FOR r IN SELECT DISTINCT ot_id FROM taller_plan_semanal_ots WHERE ot_id IS NOT NULL
    LOOP
        PERFORM fn_taller_sync_personal_ot(r.ot_id);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'Backfill personal OT: % OTs revisadas', n;
END $$;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'trigger_ok', (SELECT EXISTS (SELECT 1 FROM pg_trigger
        WHERE tgname='trg_plan_sync_personal_ot')),
    'liberar_sincroniza', (SELECT prosrc LIKE '%fn_taller_sync_personal_ot%'
        FROM pg_proc WHERE proname='rpc_taller_liberar_ejecucion'),
    'ots_con_tecnico', (SELECT COUNT(*) FROM ordenes_trabajo WHERE tecnico_id IS NOT NULL),
    'ots_plan_sin_tecnico', (SELECT COUNT(DISTINCT t.ot_id)
        FROM taller_plan_semanal_ots t
        JOIN ordenes_trabajo ot ON ot.id = t.ot_id
        WHERE NULLIF(TRIM(t.cuadrilla),'') IS NOT NULL AND ot.tecnico_id IS NULL)
) AS resultado;

NOTIFY pgrst, 'reload schema';
