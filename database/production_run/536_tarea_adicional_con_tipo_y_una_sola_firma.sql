-- ============================================================================
-- MIG536 · Tarea adicional con tipo de respuesta + UNA sola firma (al Finalizar)
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (07-09-2026, probando con PRUEBA-01)
--  1. «Cuando se coloca una tarea adicional, que el jefe pueda elegir cómo se
--     responde: OK / NO OK, o que escriba.»
--  2. «Al apretar Finalizar debo volver a firmar — no me cuadra. El operador
--     debería firmar solo al finalizar. La firma anterior, ¿a qué se debe?»
--     Respuesta: B11.07 venía del formato papel del cierre de recepción.
--     Desde MIG472 el modal Finalizar YA exige la firma del técnico (queda
--     en ordenes_trabajo.firma_tecnico_url, la que usan informes y
--     certificados). Dos firmas del mismo ejecutor en el mismo flujo es una
--     de más: B11.07 se retira y la firma vive SOLO en Finalizar.
--
-- QUÉ SE HACE
--  a) checklist_v2_instance_item.tipo_respuesta_custom ('ok_no_ok'|'texto'):
--     las tareas a medida no tienen plantilla, así que el tipo viaja en la
--     fila. La vista lo resuelve: plantilla → custom → 'ok_no_ok'.
--  b) rpc_taller_v3_agregar_item acepta p_tipo_respuesta.
--  c) B11.07 retirado de la plantilla V03 y borrado de las instancias donde
--     NADIE firmó; lo firmado queda (es historia).
-- ============================================================================

BEGIN;

-- ── a · El tipo de respuesta de las tareas a medida ─────────────────────────
ALTER TABLE checklist_v2_instance_item
  ADD COLUMN IF NOT EXISTS tipo_respuesta_custom TEXT
  CHECK (tipo_respuesta_custom IS NULL OR tipo_respuesta_custom IN ('ok_no_ok', 'texto'));
COMMENT ON COLUMN checklist_v2_instance_item.tipo_respuesta_custom IS
'Cómo se responde una tarea agregada a medida (sin plantilla): con OK/NO OK o escribiendo. Lo elige el jefe al crearla. MIG536.';

DO $p$
DECLARE v_def TEXT;
        v_viejo TEXT := 'ti.tipo_respuesta,';
        v_nuevo TEXT := 'COALESCE(ti.tipo_respuesta, ii.tipo_respuesta_custom, ''ok_no_ok''::text) AS tipo_respuesta,';
BEGIN
    SELECT pg_get_viewdef('v_taller_ot_checklist_v3'::regclass) INTO v_def;
    IF position(v_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré ti.tipo_respuesta en la vista';
    END IF;
    IF position(v_viejo IN substring(v_def FROM position(v_viejo IN v_def) + length(v_viejo))) > 0 THEN
        RAISE EXCEPTION 'FALLO: la expresión aparece más de una vez';
    END IF;
    EXECUTE 'CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS ' || replace(v_def, v_viejo, v_nuevo);
    RAISE NOTICE 'vista v3: el tipo de los custom se resuelve (plantilla → custom → ok_no_ok)';
END $p$;

-- ── b · El RPC acepta el tipo ───────────────────────────────────────────────
DROP FUNCTION IF EXISTS rpc_taller_v3_agregar_item(UUID, TEXT, NUMERIC);
CREATE FUNCTION rpc_taller_v3_agregar_item(
    p_ot_id UUID, p_descripcion TEXT, p_tiempo_min NUMERIC DEFAULT NULL,
    p_tipo_respuesta TEXT DEFAULT 'ok_no_ok')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_inst UUID; v_tpl UUID; v_activo UUID; v_contrato UUID; v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    IF NULLIF(TRIM(p_descripcion),'') IS NULL THEN RAISE EXCEPTION 'Descripcion obligatoria'; END IF;
    IF p_tipo_respuesta NOT IN ('ok_no_ok', 'texto') THEN
        RAISE EXCEPTION 'La tarea se responde con OK/NO OK o con texto (recibí: %)', p_tipo_respuesta; END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE ot_id = p_ot_id ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_inst IS NULL THEN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1;
        SELECT activo_id, contrato_id INTO v_activo, v_contrato FROM ordenes_trabajo WHERE id = p_ot_id;
        v_inst := fn_inicializar_checklist_v2(v_tpl, v_activo, v_contrato);
        UPDATE checklist_v2_instance SET ot_id = p_ot_id WHERE id = v_inst;
    END IF;

    INSERT INTO checklist_v2_instance_item (instance_id, template_item_id, resultado,
                                            descripcion_custom, tiempo_min_override, tipo_respuesta_custom)
    VALUES (v_inst, NULL, 'pendiente', TRIM(p_descripcion), p_tiempo_min, p_tipo_respuesta)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'item_id', v_id, 'instance_id', v_inst);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_agregar_item(UUID,TEXT,NUMERIC,TEXT) TO authenticated;

-- ── c · Una sola firma: B11.07 se retira ────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    UPDATE checklist_template_v2_item ti SET vigente = false
      FROM checklist_template_v2 t
     WHERE t.id = ti.template_id AND t.activo AND t.nombre ILIKE '%V03%'
       AND ti.bloque::text = 'b7_cierre_recepcion' AND ti.codigo = 'B11.07' AND ti.vigente;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'B11.07 retirado de la plantilla: %', v_n;

    -- Sin firmar → fuera. Lo firmado se queda: es historia.
    DELETE FROM checklist_v2_instance_item ii
     USING checklist_template_v2_item ti
     WHERE ti.id = ii.template_item_id
       AND ti.codigo = 'B11.07' AND ti.bloque::text = 'b7_cierre_recepcion'
       AND COALESCE(ii.resultado::text, 'pendiente') = 'pendiente';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'B11.07 sin firmar borrados de instancias: %', v_n;
END
$mig$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='v_taller_ot_checklist_v3' AND column_name='tipo_respuesta') THEN
        RAISE EXCEPTION 'FALLO: la vista perdió tipo_respuesta';
    END IF;
    SELECT count(*) INTO v_n
      FROM v_taller_ot_checklist_v3 v
     WHERE v.es_custom AND v.tipo_respuesta IS NULL;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % custom siguen sin tipo resuelto', v_n; END IF;
    RAISE NOTICE 'MIG536 OK · customs con tipo elegible y la firma vive solo en Finalizar';
END
$mig$;

COMMIT;
