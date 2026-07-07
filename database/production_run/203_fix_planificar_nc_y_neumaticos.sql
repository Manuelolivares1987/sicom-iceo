-- ============================================================================
-- SICOM-ICEO | 203 — Fix "Planificar NC" (cast enum) + profundidad de
--                    neumáticos en el checklist
-- ============================================================================
-- Reportado por Manuel (2026-07-07):
--   1. BUG: "Planificar" en la bandeja de NC lanza error. Causa:
--      fn_planificar_nc (MIG138) inserta la OT con prioridad armada en un
--      CASE de texto y la columna es prioridad_enum → 'column "prioridad" is
--      of type prioridad_enum but expression is of type text'. Fix: casts.
--   2. MEJORA: el checklist debe pedir el nivel de profundidad de CADA
--      neumático. Se agrega checklist_v2_instance_item.mediciones JSONB
--      (array [{pos, mm}]) y se expone en v_taller_ot_checklist_v3 (columna
--      al final, CREATE OR REPLACE — no rompe vistas dependientes).
--      La UI del mecánico la pide en los ítems de neumáticos y el jefe la ve
--      en el detalle de la OT.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Fix fn_planificar_nc: casts a los enums ──────────────────────────────
CREATE OR REPLACE FUNCTION fn_planificar_nc(p_nc_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_act  RECORD;
    v_ot   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT * INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'NC % no existe', p_nc_id; END IF;
    IF v_nc.plan_ot_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', v_nc.plan_ot_id, 'mensaje', 'Ya tenía OT'); END IF;

    SELECT id, contrato_id, faena_id, patente, codigo INTO v_act FROM activos WHERE id = v_nc.activo_id;
    IF v_act.contrato_id IS NULL OR v_act.faena_id IS NULL THEN
        RAISE EXCEPTION 'El equipo % no tiene contrato/faena para crear OT.', COALESCE(v_act.patente, v_act.codigo); END IF;

    INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
        observaciones, generada_automaticamente, created_by)
    VALUES ('correctivo'::tipo_ot_enum, v_act.contrato_id, v_act.faena_id, v_nc.activo_id,
        (CASE v_nc.severidad WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END)::prioridad_enum,
        'creada'::estado_ot_enum,
        'NC: ' || v_nc.descripcion ||
        COALESCE(E'\nGrupo: ' || v_nc.grupo_trabajo, '') ||
        COALESCE(' · ' || v_nc.horas_estimadas || ' h', ''),
        true, v_user)
    RETURNING id INTO v_ot;

    UPDATE no_conformidades SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
    WHERE id = p_nc_id;

    RETURN jsonb_build_object('ot_id', v_ot, 'nc_id', p_nc_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_planificar_nc(UUID) TO authenticated;


-- ── 2. Mediciones por neumático en el ítem del checklist ─────────────────────
ALTER TABLE checklist_v2_instance_item ADD COLUMN IF NOT EXISTS mediciones JSONB;
COMMENT ON COLUMN checklist_v2_instance_item.mediciones IS
    'Mediciones estructuradas del ítem (p.ej. profundidad por neumático: [{"pos":"Pos 1","mm":8.5}, ...]). MIG203.';

-- Columna nueva AL FINAL: CREATE OR REPLACE no rompe las vistas dependientes
-- (v_taller_mecanico_ots, v_taller_plan_semanal_ots_full usan esta vista).
CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS
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
    (ii.template_item_id IS NULL)                 AS es_custom,
    ii.mediciones
FROM inst
JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'fn_con_cast', (SELECT prosrc LIKE '%::prioridad_enum%' FROM pg_proc WHERE proname='fn_planificar_nc'),
    'col_mediciones', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='checklist_v2_instance_item' AND column_name='mediciones')),
    'vista_con_mediciones', (SELECT position('mediciones' IN pg_get_viewdef('v_taller_ot_checklist_v3'::regclass)) > 0)
) AS resultado;

NOTIFY pgrst, 'reload schema';
