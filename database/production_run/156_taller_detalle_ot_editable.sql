-- ============================================================================
-- SICOM-ICEO | 156 — Fase A: detalle de OT editable en el Plan Taller
-- ============================================================================
-- Resuelve lo que el jefe de taller ve al hacer click en una OT del Plan Taller:
--   1. RESPONSABLE: la jornada no tenia responsable; ahora la vista cae al
--      responsable de la OT (ordenes_trabajo.responsable_id) cuando la jornada
--      no tiene uno propio. (decision: el responsable de planificacion se ve)
--   2. CHECKLIST CORRECTO: el trigger fn_auto_checklist_ot creaba un checklist
--      V03 de inspeccion para TODA OT, pisando la pauta. Ahora, si la OT viene
--      de una pauta (plan_mantenimiento_id IS NOT NULL), NO se crea el V03: la
--      OT usa el checklist de la pauta (checklist_ot). El V03 queda para
--      recepcion/inspeccion sin pauta. (decision Manuel: siempre la pauta elegida)
--   3. TIEMPOS POR ACTIVIDAD: checklist_ot.tiempo_estimado_min (nuevo, editable).
--   4. EDICION: rpc_taller_editar_jornada + rpc_taller_checklist_* para que el
--      jefe edite responsable/cuadrilla/horas/obs y las tareas del checklist.
--   5. La vista expone conteo de checklist y tiempo estimado total.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tiempo estimado por item de checklist ────────────────────────────────
ALTER TABLE checklist_ot
    ADD COLUMN IF NOT EXISTS tiempo_estimado_min NUMERIC(7,2);

COMMENT ON COLUMN checklist_ot.tiempo_estimado_min IS
    'Tiempo estimado en minutos para esta tarea. Editable por el jefe de taller. MIG156.';


-- ── 2. Trigger checklist: no pisar la pauta ─────────────────────────────────
-- Reproduce fn_auto_checklist_ot (MIG144) agregando: si la OT viene de una
-- pauta de mantenimiento, usa el checklist de la pauta (checklist_ot) y NO
-- crea el checklist V03 de inspeccion.
CREATE OR REPLACE FUNCTION fn_auto_checklist_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
BEGIN
    -- Nunca bloquear la creacion de la OT.
    BEGIN
        -- OT desde pauta de mantenimiento -> usa el checklist de la pauta
        -- (lo crea rpc_crear_ot en checklist_ot); no se crea el V03.
        IF NEW.plan_mantenimiento_id IS NOT NULL THEN
            RETURN NEW;
        END IF;

        -- Template de inspeccion activo
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true
         ORDER BY version DESC LIMIT 1;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        -- Dedup A: esta OT ya tiene checklist
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- Dedup B: ya hay un checklist de inspeccion ABIERTO para el equipo
        -- (p.ej. el de recepcion). Se enlaza a esta OT en vez de crear otro.
        SELECT id INTO v_inst FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id
           AND momento_uso = 'recepcion_devolucion'
           AND estado = 'en_progreso'
         ORDER BY fecha_inicio DESC LIMIT 1;
        IF v_inst IS NOT NULL THEN
            UPDATE checklist_v2_instance SET ot_id = NEW.id
             WHERE id = v_inst AND ot_id IS NULL;
            RETURN NEW;
        END IF;

        -- Crear el checklist para esta OT
        SELECT contrato_id, horas_uso_actual, kilometraje_actual
          INTO v_contrato, v_horas, v_km
          FROM activos WHERE id = NEW.activo_id;

        SELECT id INTO v_entrega FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id AND momento_uso='entrega_arriendo' AND estado='cerrado'
         ORDER BY fecha_cierre DESC LIMIT 1;

        v_inst := fn_inicializar_checklist_v2(
            v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
            NULL, v_horas, v_km, NULL, v_entrega
        );
        UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;

    EXCEPTION WHEN OTHERS THEN
        NULL;  -- defensivo: jamas bloquear la OT
    END;
    RETURN NEW;
END $$;

COMMENT ON FUNCTION fn_auto_checklist_ot() IS
    'Al crear una OT SIN pauta activa el checklist de inspeccion V03 (dedup por equipo). '
    'Si la OT viene de una pauta, usa el checklist de la pauta (checklist_ot). MIG156.';


-- ── 3. Vista: responsable cae al de la OT + conteo de checklist ─────────────
DROP VIEW IF EXISTS v_taller_plan_semanal_ots_full CASCADE;
CREATE VIEW v_taller_plan_semanal_ots_full AS
SELECT
    t.id                            AS plan_ot_id,
    t.plan_semanal_id,
    t.plan_dia_id,
    d.fecha                         AS dia_fecha,
    d.nombre_dia                    AS dia_nombre,
    d.orden                         AS dia_orden,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado                       AS plan_estado,
    t.ot_id,
    ot.folio                        AS ot_folio,
    ot.tipo                         AS ot_tipo,
    ot.estado                       AS ot_estado,
    ot.prioridad                    AS ot_prioridad,
    ot.fecha_programada             AS ot_fecha_programada,
    ot.plan_mantenimiento_id,
    pm.nombre                       AS pm_nombre,
    pm.proxima_ejecucion_fecha      AS pm_proxima_fecha,
    ot.activo_id,
    a.codigo                        AS activo_codigo,
    a.nombre                        AS activo_nombre,
    a.patente                       AS activo_patente,
    a.tipo                          AS activo_tipo,
    ot.faena_id,
    f.nombre                        AS faena_nombre,
    ot.contrato_id,
    c.codigo                        AS contrato_codigo,
    c.cliente                       AS contrato_cliente,
    -- Responsable: el de la jornada; si no hay, el de la OT (planificacion)
    COALESCE(t.responsable_id, ot.responsable_id)        AS responsable_id,
    COALESCE(up.nombre_completo, up_ot.nombre_completo)  AS responsable,
    t.cuadrilla,
    t.horas_planificadas,
    t.avance_objetivo_pct,
    t.secuencia_jornada,
    t.estado_plan                   AS jornada_estado,
    t.observaciones,
    -- Checklist de la OT (pauta o inspeccion)
    (SELECT COUNT(*) FROM checklist_ot ch WHERE ch.ot_id = t.ot_id)                       AS checklist_total,
    (SELECT COUNT(*) FROM checklist_ot ch WHERE ch.ot_id = t.ot_id AND ch.resultado IS NOT NULL
        AND ch.resultado <> 'pendiente')                                                  AS checklist_completados,
    (SELECT COALESCE(SUM(ch.tiempo_estimado_min),0) FROM checklist_ot ch WHERE ch.ot_id = t.ot_id) AS tiempo_estimado_total_min,
    -- Ejecucion activa (si existe)
    (SELECT id FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada')
       LIMIT 1)                     AS ejecucion_activa_id,
    (SELECT estado FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada')
       LIMIT 1)                     AS ejecucion_activa_estado,
    (SELECT avance_final FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado = 'finalizada'
       ORDER BY finished_at DESC LIMIT 1) AS ultima_ejecucion_avance,
    t.created_at,
    t.updated_at
FROM taller_plan_semanal_ots t
JOIN taller_plan_semanal_dias d        ON d.id = t.plan_dia_id
JOIN taller_planes_semanales ps         ON ps.id = t.plan_semanal_id
JOIN ordenes_trabajo ot                 ON ot.id = t.ot_id
LEFT JOIN planes_mantenimiento pm       ON pm.id = ot.plan_mantenimiento_id
LEFT JOIN activos a                     ON a.id = ot.activo_id
LEFT JOIN faenas f                      ON f.id = ot.faena_id
LEFT JOIN contratos c                   ON c.id = ot.contrato_id
LEFT JOIN usuarios_perfil up            ON up.id = t.responsable_id
LEFT JOIN usuarios_perfil up_ot         ON up_ot.id = ot.responsable_id;

COMMENT ON VIEW v_taller_plan_semanal_ots_full IS
    'Jornadas con OT/activo/responsable (cae al de la OT), checklist y ejecucion. MIG156.';

GRANT SELECT ON v_taller_plan_semanal_ots_full TO authenticated;


-- ── 4. RPC: editar la jornada (jefe de taller) ──────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_editar_jornada(
    p_plan_ot_id          UUID,
    p_responsable_id      UUID    DEFAULT NULL,
    p_cuadrilla           VARCHAR DEFAULT NULL,
    p_horas_planificadas  NUMERIC DEFAULT NULL,
    p_avance_objetivo     NUMERIC DEFAULT NULL,
    p_observaciones       TEXT    DEFAULT NULL,
    p_sync_responsable_ot BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_ot   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso para editar la jornada (rol: %)', v_rol;
    END IF;

    SELECT ot_id INTO v_ot FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'Jornada no existe'; END IF;

    UPDATE taller_plan_semanal_ots
       SET responsable_id     = COALESCE(p_responsable_id, responsable_id),
           cuadrilla          = COALESCE(p_cuadrilla, cuadrilla),
           horas_planificadas = COALESCE(p_horas_planificadas, horas_planificadas),
           avance_objetivo_pct= COALESCE(p_avance_objetivo, avance_objetivo_pct),
           observaciones      = COALESCE(p_observaciones, observaciones),
           estado_plan        = CASE WHEN estado_plan = 'planificada'
                                       AND COALESCE(p_responsable_id, responsable_id) IS NOT NULL
                                     THEN 'asignada' ELSE estado_plan END,
           updated_at         = NOW()
     WHERE id = p_plan_ot_id;

    -- Sincroniza el responsable hacia la OT para que sea consistente.
    IF p_sync_responsable_ot AND p_responsable_id IS NOT NULL THEN
        UPDATE ordenes_trabajo SET responsable_id = p_responsable_id, updated_at = NOW()
         WHERE id = v_ot;
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', p_plan_ot_id, 'ot_id', v_ot);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_editar_jornada(UUID,UUID,VARCHAR,NUMERIC,NUMERIC,TEXT,BOOLEAN) TO authenticated;


-- ── 5. RPCs: editar el checklist de la OT (tareas + tiempos) ─────────────────
CREATE OR REPLACE FUNCTION rpc_taller_checklist_upsert_item(
    p_ot_id        UUID,
    p_item_id      UUID    DEFAULT NULL,
    p_descripcion  TEXT    DEFAULT NULL,
    p_orden        INTEGER DEFAULT NULL,
    p_obligatorio  BOOLEAN DEFAULT TRUE,
    p_requiere_foto BOOLEAN DEFAULT FALSE,
    p_tiempo_estimado_min NUMERIC DEFAULT NULL,
    p_seccion      VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
    v_orden INTEGER;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso para editar el checklist (rol: %)', v_rol;
    END IF;

    IF p_item_id IS NOT NULL THEN
        UPDATE checklist_ot
           SET descripcion         = COALESCE(NULLIF(TRIM(p_descripcion),''), descripcion),
               orden               = COALESCE(p_orden, orden),
               obligatorio         = COALESCE(p_obligatorio, obligatorio),
               requiere_foto       = COALESCE(p_requiere_foto, requiere_foto),
               tiempo_estimado_min = p_tiempo_estimado_min,
               seccion             = COALESCE(p_seccion, seccion)
         WHERE id = p_item_id AND ot_id = p_ot_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Item de checklist no existe en la OT'; END IF;
    ELSE
        IF NULLIF(TRIM(p_descripcion),'') IS NULL THEN
            RAISE EXCEPTION 'La descripcion de la tarea es obligatoria';
        END IF;
        SELECT COALESCE(MAX(orden),0)+1 INTO v_orden FROM checklist_ot WHERE ot_id = p_ot_id;
        INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto, tiempo_estimado_min, seccion)
        VALUES (gen_random_uuid(), p_ot_id, COALESCE(p_orden, v_orden), TRIM(p_descripcion),
                COALESCE(p_obligatorio,true), COALESCE(p_requiere_foto,false), p_tiempo_estimado_min, p_seccion)
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_checklist_upsert_item(UUID,UUID,TEXT,INTEGER,BOOLEAN,BOOLEAN,NUMERIC,VARCHAR) TO authenticated;


CREATE OR REPLACE FUNCTION rpc_taller_checklist_eliminar_item(p_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso para editar el checklist (rol: %)', v_rol;
    END IF;
    -- No borrar tareas ya ejecutadas (con resultado)
    DELETE FROM checklist_ot
     WHERE id = p_item_id AND (resultado IS NULL OR resultado = 'pendiente')
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'No se puede eliminar: la tarea no existe o ya fue ejecutada';
    END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_checklist_eliminar_item(UUID) TO authenticated;


-- ── 6. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_tiempo',   (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                      WHERE table_name='checklist_ot' AND column_name='tiempo_estimado_min')),
    'vista_ok',     (SELECT EXISTS(SELECT 1 FROM information_schema.views
                      WHERE table_name='v_taller_plan_semanal_ots_full')),
    'rpc_editar',   (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_taller_editar_jornada')),
    'rpc_upsert',   (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_taller_checklist_upsert_item')),
    'rpc_eliminar', (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_taller_checklist_eliminar_item'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
