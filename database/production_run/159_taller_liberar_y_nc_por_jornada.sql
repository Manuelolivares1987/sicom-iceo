-- ============================================================================
-- SICOM-ICEO | 159 — Handoff jefe→ejecutor + NC por jornada desde el V03
-- ============================================================================
-- Flujo (Manuel, 2026-06-18):
--   1. El jefe de taller prepara el checklist en la ficha de la OT (tiempos,
--      excluir, agregar tareas).
--   2. Da OK con "Liberar a ejecucion" -> se bloquea la edicion y el ejecutor
--      puede ejecutar (marcar OK/NO_OK/NA + foto).
--   3. Al finalizar CADA JORNADA (pausa o fin) saltan las NC de los items NO_OK
--      con su foto, y llegan a la bandeja del jefe.
--   4. Sobre esas NC el jefe hace el pedido de bodega (ya existe).
--
-- Cambios:
--   1. ordenes_trabajo.preparacion_ok_at / _por (flag de liberacion).
--   2. RPCs rpc_taller_liberar_ejecucion / rpc_taller_reabrir_preparacion.
--   3. fn_generar_nc_desde_v3_ot(p_ot_id): NC idempotentes desde items NO_OK
--      (no excluidos) del checklist V03 ligado a la OT, con foto.
--   4. Trigger: al pasar la OT a 'pausada' o finalizada se generan las NC.
--   5. v_nc_recepcion incluye origen 'ejecucion_ot' (entran al tablero de NC).
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Flag de liberacion ────────────────────────────────────────────────────
ALTER TABLE ordenes_trabajo
    ADD COLUMN IF NOT EXISTS preparacion_ok_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS preparacion_ok_por UUID REFERENCES usuarios_perfil(id);

COMMENT ON COLUMN ordenes_trabajo.preparacion_ok_at IS
    'Cuando el jefe de taller libero el checklist a ejecucion. NULL = en preparacion. MIG159.';


-- ── 2. RPCs liberar / reabrir ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_liberar_ejecucion(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo el jefe de taller libera a ejecucion (rol: %)', v_rol; END IF;
    UPDATE ordenes_trabajo
       SET preparacion_ok_at = NOW(), preparacion_ok_por = auth.uid(), updated_at = NOW()
     WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'ot_id', p_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_liberar_ejecucion(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_taller_reabrir_preparacion(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo el jefe de taller reabre la preparacion (rol: %)', v_rol; END IF;
    UPDATE ordenes_trabajo
       SET preparacion_ok_at = NULL, preparacion_ok_por = NULL, updated_at = NOW()
     WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'ot_id', p_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_reabrir_preparacion(UUID) TO authenticated;


-- ── 3. NC desde items NO_OK del checklist V03 (idempotente) ──────────────────
CREATE OR REPLACE FUNCTION fn_generar_nc_desde_v3_ot(p_ot_id UUID)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_activo UUID;
    v_n      INT := 0;
    r        RECORD;
BEGIN
    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_activo IS NULL THEN RETURN 0; END IF;

    FOR r IN
        SELECT v.instance_item_id, v.descripcion, v.observacion, v.foto_url
          FROM v_taller_ot_checklist_v3 v
         WHERE v.ot_id = p_ot_id AND v.excluido = false AND v.resultado = 'no_ok'
    LOOP
        -- idempotente: una NC por item de checklist
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = r.instance_item_id) THEN
            CONTINUE;
        END IF;
        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen,
            checklist_item_ref, foto_url, estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_activo, p_ot_id, 'otra',
            r.descripcion || COALESCE(' — ' || r.observacion, ''),
            CURRENT_DATE, 'media', 'ejecucion_ot',
            r.instance_item_id, r.foto_url, 'registrada', v_user, v_user
        );
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;
GRANT EXECUTE ON FUNCTION fn_generar_nc_desde_v3_ot(UUID) TO authenticated;


-- ── 4. Trigger: NC al pausar / finalizar la OT (fin de jornada) ──────────────
CREATE OR REPLACE FUNCTION fn_trg_nc_al_pausar_finalizar_ot()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NEW.estado IS DISTINCT FROM OLD.estado
       AND NEW.estado::text IN ('pausada','ejecutada_ok','ejecutada_con_observaciones') THEN
        BEGIN
            PERFORM fn_generar_nc_desde_v3_ot(NEW.id);
        EXCEPTION WHEN OTHERS THEN NULL;  -- nunca bloquear la transicion
        END;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nc_al_pausar_finalizar_ot ON ordenes_trabajo;
CREATE TRIGGER trg_nc_al_pausar_finalizar_ot
    AFTER UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_trg_nc_al_pausar_finalizar_ot();


-- ── 5. Las NC de ejecucion entran al tablero del jefe ────────────────────────
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
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot');


-- ── 6. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'cols_liberar', (SELECT array_agg(column_name ORDER BY column_name)
        FROM information_schema.columns WHERE table_name='ordenes_trabajo'
          AND column_name IN ('preparacion_ok_at','preparacion_ok_por')),
    'rpcs', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_taller_liberar_ejecucion','rpc_taller_reabrir_preparacion','fn_generar_nc_desde_v3_ot')),
    'trigger', (SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_nc_al_pausar_finalizar_ot')),
    'vista_nc_ok', (SELECT EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_nc_recepcion'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
