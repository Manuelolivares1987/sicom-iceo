-- ============================================================================
-- SICOM-ICEO | 119 — Tareas del taller desde el checklist de recepción
-- ============================================================================
-- Visión: las actividades a realizar en un equipo salen de su checklist de
-- recepción/entrada — los ítems marcados 'no_ok' son el trabajo a hacer.
--   1. fn_tareas_recepcion_activo(activo): ítems no_ok de su última recepción.
--   2. rpc_programar_ot_recepcion(activo, ...): crea una OT correctiva cuyo
--      checklist SON esas fallas (reemplaza el checklist genérico del trigger).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_tareas_recepcion_activo(p_activo_id uuid)
RETURNS TABLE (
    instance_id    uuid,
    fecha_recepcion timestamptz,
    item_id        uuid,
    bloque         text,
    orden          integer,
    descripcion    text,
    observacion    text,
    costo_estimado numeric,
    cobrable       text
)
LANGUAGE sql STABLE
AS $$
  WITH inst AS (
    SELECT id, fecha_inicio
      FROM checklist_v2_instance
     WHERE activo_id = p_activo_id AND momento_uso = 'recepcion_devolucion'
     ORDER BY fecha_inicio DESC NULLS LAST LIMIT 1
  )
  SELECT inst.id::uuid, inst.fecha_inicio::timestamptz,
         ii.id::uuid, ti.bloque::text, ti.orden::integer, ti.descripcion::text,
         ii.observacion::text, ii.costo_estimado::numeric,
         COALESCE(ii.cobrable_override::text, ti.default_cobrable::text)
    FROM inst
    JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
    JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
   WHERE ii.resultado = 'no_ok'
   ORDER BY ti.bloque, ti.orden;
$$;

GRANT EXECUTE ON FUNCTION fn_tareas_recepcion_activo(uuid) TO authenticated;

-- ── Programar OT correctiva con las fallas de recepción como checklist ──────
CREATE OR REPLACE FUNCTION rpc_programar_ot_recepcion(
    p_activo_id uuid,
    p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha date DEFAULT NULL::date,
    p_responsable_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_res   jsonb;
    v_ot_id uuid;
    v_n     integer;
BEGIN
    SELECT count(*) INTO v_n FROM fn_tareas_recepcion_activo(p_activo_id);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'El equipo no tiene fallas de recepción (ítems no_ok) para programar.';
    END IF;

    -- Crea la OT correctiva (resuelve contrato/faena vía el wrapper de taller)
    v_res := rpc_programar_ot_taller(p_activo_id, 'correctivo', p_prioridad, p_fecha, p_responsable_id, NULL);
    v_ot_id := (v_res->>'id')::uuid;

    -- Reemplaza el checklist genérico por las fallas de recepción
    DELETE FROM checklist_ot WHERE ot_id = v_ot_id;
    INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
    SELECT gen_random_uuid(), v_ot_id,
           ROW_NUMBER() OVER (ORDER BY t.bloque, t.orden),
           t.descripcion || COALESCE(' — ' || t.observacion, ''),
           true,
           false
      FROM fn_tareas_recepcion_activo(p_activo_id) t;

    RETURN v_res || jsonb_build_object('tareas_cargadas', v_n);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_programar_ot_recepcion(uuid, prioridad_enum, date, uuid) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG119 OK: tareas desde checklist de recepción'; END $$;
