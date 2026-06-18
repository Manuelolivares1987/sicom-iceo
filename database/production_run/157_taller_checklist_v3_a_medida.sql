-- ============================================================================
-- SICOM-ICEO | 157 — El detalle de OT del Plan Taller parte del checklist V03
-- ============================================================================
-- Decision Manuel (2026-06-18, corrige la de "siempre la pauta"):
--   El checklist de la actividad PARTE del checklist largo unificado
--   CL-INSPECCION-V03 (188 items con tiempos). El jefe de taller lo ajusta
--   A MEDIDA POR OT: cambia el tiempo por tarea, marca tareas que NO aplican,
--   y agrega tareas propias. El checklist MAESTRO no se toca.
--
-- Cambios:
--   1. Overrides por-OT en checklist_v2_instance_item: tiempo_min_override,
--      excluido, descripcion_custom; template_item_id pasa a NULLABLE (tareas
--      agregadas no vienen del maestro).
--   2. Revertir MIG156: el trigger fn_auto_checklist_ot vuelve a crear el V03
--      para TODA OT (tambien las de pauta) -> todas parten del checklist largo.
--   3. Backfill: crear la instancia V03 para las OT del plan que no la tengan.
--   4. Vista v_taller_ot_checklist_v3 (items efectivos por OT, con override).
--   5. v_taller_plan_semanal_ots_full: conteo/tiempo desde el V03.
--   6. RPCs: set_tiempo, set_excluido, agregar_item, eliminar_custom.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Overrides por-OT en la instancia ─────────────────────────────────────
ALTER TABLE checklist_v2_instance_item ALTER COLUMN template_item_id DROP NOT NULL;
ALTER TABLE checklist_v2_instance_item
    ADD COLUMN IF NOT EXISTS tiempo_min_override NUMERIC(7,2),
    ADD COLUMN IF NOT EXISTS excluido            BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS descripcion_custom  VARCHAR(300);

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_cl_item_tpl_o_custom') THEN
        ALTER TABLE checklist_v2_instance_item
            ADD CONSTRAINT chk_cl_item_tpl_o_custom
            CHECK (template_item_id IS NOT NULL OR descripcion_custom IS NOT NULL) NOT VALID;
    END IF;
END $$;

COMMENT ON COLUMN checklist_v2_instance_item.tiempo_min_override IS 'Tiempo (min) a medida por OT; si NULL usa el del maestro. MIG157.';
COMMENT ON COLUMN checklist_v2_instance_item.excluido IS 'La tarea no aplica a esta OT (no se borra del maestro). MIG157.';
COMMENT ON COLUMN checklist_v2_instance_item.descripcion_custom IS 'Tarea agregada por el jefe para esta OT (template_item_id NULL). MIG157.';


-- ── 2. Trigger: TODA OT parte del checklist V03 (revierte MIG156) ───────────
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
    BEGIN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true
         ORDER BY version DESC LIMIT 1;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

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
        NULL;
    END;
    RETURN NEW;
END $$;

COMMENT ON FUNCTION fn_auto_checklist_ot() IS
    'Al crear cualquier OT activa el checklist de inspeccion V03 (dedup por equipo). MIG157.';


-- ── 3. Backfill: instancia V03 para OT del plan sin checklist ────────────────
DO $$
DECLARE
    r       RECORD;
    v_tpl   UUID;
    v_inst  UUID;
    v_n     INT := 0;
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1;
    IF v_tpl IS NULL THEN RAISE NOTICE 'Sin template V03 activo; backfill omitido'; RETURN; END IF;

    FOR r IN
        SELECT DISTINCT t.ot_id, o.activo_id, o.contrato_id
          FROM taller_plan_semanal_ots t
          JOIN ordenes_trabajo o ON o.id = t.ot_id
         WHERE NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id = t.ot_id)
    LOOP
        BEGIN
            v_inst := fn_inicializar_checklist_v2(v_tpl, r.activo_id, r.contrato_id);
            UPDATE checklist_v2_instance SET ot_id = r.ot_id WHERE id = v_inst;
            v_n := v_n + 1;
        EXCEPTION WHEN OTHERS THEN NULL;  -- p.ej. activo sin tipo_equipamiento
        END;
    END LOOP;
    RAISE NOTICE 'Backfill V03: % instancias creadas', v_n;
END $$;


-- ── 4. Vista: checklist V03 efectivo por OT (instancia mas reciente) ─────────
DROP VIEW IF EXISTS v_taller_ot_checklist_v3 CASCADE;
CREATE VIEW v_taller_ot_checklist_v3 AS
WITH inst AS (
    SELECT DISTINCT ON (ot_id) id, ot_id, activo_id, estado
      FROM checklist_v2_instance
     WHERE ot_id IS NOT NULL
     ORDER BY ot_id, fecha_inicio DESC
)
SELECT
    ii.id                                         AS instance_item_id,
    inst.id                                       AS instance_id,
    inst.ot_id,
    inst.estado                                   AS instance_estado,
    COALESCE(ti.bloque::text, 'Tareas adicionales') AS bloque,
    COALESCE(ti.bloque_orden, 999)                AS bloque_orden,
    COALESCE(ti.orden, 9999)                       AS orden,
    ti.codigo,
    COALESCE(ii.descripcion_custom, ti.descripcion) AS descripcion,
    COALESCE(ii.tiempo_min_override, ti.tiempo_min)  AS tiempo_min,
    (ii.tiempo_min_override IS NOT NULL)          AS tiempo_editado,
    COALESCE(ti.requiere_foto, false)             AS requiere_foto,
    COALESCE(ti.obligatorio, false)               AS obligatorio,
    COALESCE(ti.critico, false)                   AS critico,
    ti.categoria_calidad,
    ii.resultado,
    ii.observacion,
    ii.foto_url,
    ii.excluido,
    (ii.template_item_id IS NULL)                 AS es_custom
FROM inst
JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id;

COMMENT ON VIEW v_taller_ot_checklist_v3 IS
    'Checklist V03 efectivo por OT (instancia mas reciente) con overrides a medida. MIG157.';
GRANT SELECT ON v_taller_ot_checklist_v3 TO authenticated;


-- ── 5. v_taller_plan_semanal_ots_full: conteo/tiempo desde el V03 ───────────
DROP VIEW IF EXISTS v_taller_plan_semanal_ots_full CASCADE;
CREATE VIEW v_taller_plan_semanal_ots_full AS
SELECT
    t.id AS plan_ot_id, t.plan_semanal_id, t.plan_dia_id,
    d.fecha AS dia_fecha, d.nombre_dia AS dia_nombre, d.orden AS dia_orden,
    ps.fecha_inicio_semana, ps.fecha_fin_semana, ps.estado AS plan_estado,
    t.ot_id, ot.folio AS ot_folio, ot.tipo AS ot_tipo, ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad, ot.fecha_programada AS ot_fecha_programada,
    ot.plan_mantenimiento_id, pm.nombre AS pm_nombre, pm.proxima_ejecucion_fecha AS pm_proxima_fecha,
    ot.activo_id, a.codigo AS activo_codigo, a.nombre AS activo_nombre,
    a.patente AS activo_patente, a.tipo AS activo_tipo,
    ot.faena_id, f.nombre AS faena_nombre,
    ot.contrato_id, c.codigo AS contrato_codigo, c.cliente AS contrato_cliente,
    COALESCE(t.responsable_id, ot.responsable_id)        AS responsable_id,
    COALESCE(up.nombre_completo, up_ot.nombre_completo)  AS responsable,
    t.cuadrilla, t.horas_planificadas, t.avance_objetivo_pct,
    t.secuencia_jornada, t.estado_plan AS jornada_estado, t.observaciones,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false)                          AS checklist_total,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false
         AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente')            AS checklist_completados,
    (SELECT COALESCE(SUM(v.tiempo_min),0) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false)                          AS tiempo_estimado_total_min,
    (SELECT id FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada') LIMIT 1) AS ejecucion_activa_id,
    (SELECT estado FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada') LIMIT 1) AS ejecucion_activa_estado,
    (SELECT avance_final FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado = 'finalizada'
       ORDER BY finished_at DESC LIMIT 1)                                       AS ultima_ejecucion_avance,
    t.created_at, t.updated_at
FROM taller_plan_semanal_ots t
JOIN taller_plan_semanal_dias d  ON d.id = t.plan_dia_id
JOIN taller_planes_semanales ps   ON ps.id = t.plan_semanal_id
JOIN ordenes_trabajo ot           ON ot.id = t.ot_id
LEFT JOIN planes_mantenimiento pm ON pm.id = ot.plan_mantenimiento_id
LEFT JOIN activos a               ON a.id = ot.activo_id
LEFT JOIN faenas f                ON f.id = ot.faena_id
LEFT JOIN contratos c             ON c.id = ot.contrato_id
LEFT JOIN usuarios_perfil up      ON up.id = t.responsable_id
LEFT JOIN usuarios_perfil up_ot   ON up_ot.id = ot.responsable_id;

COMMENT ON VIEW v_taller_plan_semanal_ots_full IS
    'Jornadas con OT/responsable/ejecucion + conteo y tiempo del checklist V03. MIG157.';
GRANT SELECT ON v_taller_plan_semanal_ots_full TO authenticated;


-- ── 6. RPCs de edicion a medida (jefe de taller) ────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_v3_set_tiempo(p_item_id UUID, p_tiempo_min NUMERIC)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    UPDATE checklist_v2_instance_item SET tiempo_min_override = p_tiempo_min
     WHERE id = p_item_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Item no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_set_tiempo(UUID,NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_taller_v3_set_excluido(p_item_id UUID, p_excluido BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    UPDATE checklist_v2_instance_item SET excluido = COALESCE(p_excluido,false)
     WHERE id = p_item_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Item no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_set_excluido(UUID,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_taller_v3_agregar_item(
    p_ot_id UUID, p_descripcion TEXT, p_tiempo_min NUMERIC DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_inst UUID; v_tpl UUID; v_activo UUID; v_contrato UUID; v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    IF NULLIF(TRIM(p_descripcion),'') IS NULL THEN RAISE EXCEPTION 'Descripcion obligatoria'; END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE ot_id = p_ot_id ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_inst IS NULL THEN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1;
        SELECT activo_id, contrato_id INTO v_activo, v_contrato FROM ordenes_trabajo WHERE id = p_ot_id;
        v_inst := fn_inicializar_checklist_v2(v_tpl, v_activo, v_contrato);
        UPDATE checklist_v2_instance SET ot_id = p_ot_id WHERE id = v_inst;
    END IF;

    INSERT INTO checklist_v2_instance_item (instance_id, template_item_id, resultado, descripcion_custom, tiempo_min_override)
    VALUES (v_inst, NULL, 'pendiente', TRIM(p_descripcion), p_tiempo_min)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'item_id', v_id, 'instance_id', v_inst);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_agregar_item(UUID,TEXT,NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_taller_v3_eliminar_custom(p_item_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    -- Solo se borran tareas agregadas a medida (las del maestro se marcan excluido)
    DELETE FROM checklist_v2_instance_item
     WHERE id = p_item_id AND template_item_id IS NULL RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Solo se pueden eliminar tareas agregadas (las del maestro se marcan como no aplica)'; END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_eliminar_custom(UUID) TO authenticated;


-- ── 7. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'cols_override', (SELECT array_agg(column_name ORDER BY column_name)
        FROM information_schema.columns WHERE table_name='checklist_v2_instance_item'
          AND column_name IN ('tiempo_min_override','excluido','descripcion_custom')),
    'vista_v3', (SELECT EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_taller_ot_checklist_v3')),
    'rpcs', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_taller_v3_set_tiempo','rpc_taller_v3_set_excluido','rpc_taller_v3_agregar_item','rpc_taller_v3_eliminar_custom')),
    'ots_plan_con_v03', (SELECT COUNT(DISTINCT t.ot_id) FROM taller_plan_semanal_ots t
        JOIN checklist_v2_instance ci ON ci.ot_id = t.ot_id),
    'items_v3_en_plan', (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
        WHERE v.ot_id IN (SELECT ot_id FROM taller_plan_semanal_ots))
) AS resultado;

NOTIFY pgrst, 'reload schema';
