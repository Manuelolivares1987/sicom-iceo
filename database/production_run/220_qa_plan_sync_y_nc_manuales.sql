-- ============================================================================
-- SICOM-ICEO | 220 — QA post-demo: el plan refleja la ejecución real,
--                    NC manuales visibles, y liberación masiva a ejecución
-- ============================================================================
-- Hallazgos del QA como usuario real (2026-07-09, tras la demo con problemas):
--
--   1. KPIs del Kanban del jefe en CERO aunque el taller trabajó: las OTs
--      ejecutadas desde /m/taller (rpc_transicion_ot) no actualizan
--      taller_plan_semanal_ots.estado_plan → "FINALIZADAS 0, CUMPLIM. 0%".
--      Confirmado en prod: OT-202607-00011/00018 ejecutadas con sus 6
--      jornadas aún 'planificada'.
--      FIX: trigger en ordenes_trabajo que sincroniza el estado_plan de las
--      jornadas al transicionar la OT (espejo del patrón MIG217, plan←OT).
--
--   2. NC de origen 'manual' INVISIBLES pero bloqueantes: v_nc_recepcion solo
--      lista recepcion/inspeccion/ejecucion → las 3 NC manuales de JTYK-88
--      bloquean sus certificados (MIG219) y no hay pantalla donde resolverlas.
--      FIX: incluir 'manual' en la vista de la bandeja.
--
--   3. El mecánico ve su app VACÍA con el plan lleno: 8 OTs planificadas y
--      asignadas esta semana, ninguna liberada (preparacion_ok_at NULL) — el
--      paso "Liberar a ejecución" vive escondido en la ficha de cada OT.
--      FIX: rpc_taller_liberar_ots(uuid[]) para liberar en masa desde el
--      Kanban (la UI agrega botón por card + "liberar día").
--
--   4. Backfill: jornadas de OTs ya ejecutadas/en ejecución → estado real.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_taller_liberar_ejecucion') THEN
        RAISE EXCEPTION 'STOP — falta rpc_taller_liberar_ejecucion (MIG159/217).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='taller_plan_semanal_ots' AND column_name='estado_plan') THEN
        RAISE EXCEPTION 'STOP — falta taller_plan_semanal_ots.estado_plan.';
    END IF;
END $$;


-- ── 1. La ejecución real de la OT actualiza el plan ──────────────────────────
CREATE OR REPLACE FUNCTION fn_trg_ot_sync_estado_plan()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_estado_plan TEXT;
BEGIN
    IF NEW.estado IS NOT DISTINCT FROM OLD.estado THEN RETURN NEW; END IF;
    v_estado_plan := CASE NEW.estado::text
        WHEN 'en_ejecucion'                THEN 'en_ejecucion'
        WHEN 'pausada'                     THEN 'pausada'
        WHEN 'ejecutada_ok'                THEN 'finalizada'
        WHEN 'ejecutada_con_observaciones' THEN 'finalizada'
        WHEN 'cerrada'                     THEN 'finalizada'
        ELSE NULL  -- creada/asignada/no_ejecutada/cancelada: el plan no cambia solo
    END;
    IF v_estado_plan IS NULL THEN RETURN NEW; END IF;

    UPDATE taller_plan_semanal_ots
       SET estado_plan = v_estado_plan, updated_at = NOW()
     WHERE ot_id = NEW.id
       AND estado_plan IS DISTINCT FROM v_estado_plan
       AND estado_plan NOT IN ('finalizada');  -- lo cerrado no se reabre
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ot_sync_estado_plan ON ordenes_trabajo;
CREATE TRIGGER trg_ot_sync_estado_plan
    AFTER UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_trg_ot_sync_estado_plan();


-- ── 2. Bandeja NC: las manuales también entran ───────────────────────────────
DROP VIEW IF EXISTS v_nc_recepcion;
CREATE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
       nc.ot_id
FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
-- [MIG220] + 'manual': antes eran invisibles pero bloqueaban certificados (MIG219)
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual');
GRANT SELECT ON v_nc_recepcion TO authenticated;


-- ── 3. Liberación masiva a ejecución ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_liberar_ots(p_ot_ids UUID[])
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_id UUID; v_ok INT := 0; v_errores JSONB := '[]'::jsonb;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo el jefe de taller libera a ejecucion (rol: %)', v_rol; END IF;

    FOREACH v_id IN ARRAY p_ot_ids LOOP
        BEGIN
            PERFORM rpc_taller_liberar_ejecucion(v_id);
            v_ok := v_ok + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errores := v_errores || jsonb_build_object('ot_id', v_id, 'error', SQLERRM);
        END;
    END LOOP;
    RETURN jsonb_build_object('success', true, 'liberadas', v_ok, 'errores', v_errores);
END $$;
REVOKE EXECUTE ON FUNCTION rpc_taller_liberar_ots(UUID[]) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION rpc_taller_liberar_ots(UUID[]) TO authenticated;


-- ── 4. Backfill: el plan refleja lo ya ejecutado ─────────────────────────────
UPDATE taller_plan_semanal_ots t
   SET estado_plan = CASE ot.estado::text
                       WHEN 'en_ejecucion' THEN 'en_ejecucion'
                       WHEN 'pausada'      THEN 'pausada'
                       ELSE 'finalizada'
                     END,
       updated_at = NOW()
  FROM ordenes_trabajo ot
 WHERE ot.id = t.ot_id
   AND ot.estado IN ('en_ejecucion','pausada','ejecutada_ok','ejecutada_con_observaciones','cerrada')
   AND t.estado_plan NOT IN ('finalizada')
   AND t.estado_plan IS DISTINCT FROM CASE ot.estado::text
                       WHEN 'en_ejecucion' THEN 'en_ejecucion'
                       WHEN 'pausada'      THEN 'pausada'
                       ELSE 'finalizada'
                     END;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'trigger_ok', (SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ot_sync_estado_plan')),
    'vista_incluye_manual', (SELECT position('manual' in pg_get_viewdef('v_nc_recepcion'::regclass)) > 0),
    'rpc_liberar_masivo', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_taller_liberar_ots')),
    'jornadas_finalizadas', (SELECT COUNT(*) FROM taller_plan_semanal_ots WHERE estado_plan='finalizada'),
    'nc_manuales_visibles', (SELECT COUNT(*) FROM v_nc_recepcion WHERE origen='manual' AND COALESCE(resuelto,false)=false)
) AS resultado;

NOTIFY pgrst, 'reload schema';
