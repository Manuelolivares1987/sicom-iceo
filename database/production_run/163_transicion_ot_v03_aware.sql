-- ============================================================================
-- SICOM-ICEO | 163 — Ejecución del mecánico: liberar deja responsable +
--                    rpc_transicion_ot reconoce el checklist V03 y sus fotos
-- ============================================================================
-- Bloqueos detectados al probar la app del mecánico (/m/taller):
--  1. Iniciar (→ en_ejecucion) exige responsable_id; las OT liberadas suelen
--     no tener responsable-persona. Fix: liberar deja responsable por defecto
--     (el jefe que libera) si la OT no tiene.
--  2. Finalizar (→ ejecutada_ok / con_observaciones) exigía evidencia en
--     evidencias_ot y checklist completo en checklist_ot (tablas viejas). Las
--     fotos y los ítems del mecánico viven en el checklist V03
--     (checklist_v2_instance_item). Fix: las validaciones cuentan TAMBIÉN el
--     V03 (fotos como evidencia; obligatorios del V03 no excluidos).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Liberar deja un responsable por defecto ───────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_liberar_ejecucion(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo el jefe de taller libera a ejecucion (rol: %)', v_rol; END IF;
    UPDATE ordenes_trabajo
       SET preparacion_ok_at = NOW(), preparacion_ok_por = auth.uid(),
           -- la ejecución requiere responsable; si no hay, queda el jefe que libera
           responsable_id = COALESCE(responsable_id, auth.uid()),
           estado = CASE WHEN estado='creada' THEN 'asignada' ELSE estado END,
           updated_at = NOW()
     WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'ot_id', p_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_liberar_ejecucion(UUID) TO authenticated;


-- ── 2. rpc_transicion_ot V03-aware (evidencia + checklist) ───────────────────
CREATE OR REPLACE FUNCTION public.rpc_transicion_ot(
    p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid,
    p_causa_no_ejecucion causa_no_ejecucion_enum DEFAULT NULL::causa_no_ejecucion_enum,
    p_detalle_no_ejecucion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text,
    p_responsable_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE
    v_ot                     RECORD;
    v_count_evidence         INTEGER;
    v_count_checklist_total  INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas   estado_ot_enum[];
BEGIN
    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada: %', p_ot_id; END IF;

    v_transiciones_validas := CASE v_ot.estado
        WHEN 'creada'                      THEN ARRAY['asignada','cancelada']::estado_ot_enum[]
        WHEN 'asignada'                    THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'en_ejecucion'                THEN ARRAY['pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada']::estado_ot_enum[]
        WHEN 'pausada'                     THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'ejecutada_ok'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'ejecutada_con_observaciones' THEN ARRAY[]::estado_ot_enum[]
        WHEN 'no_ejecutada'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cancelada'                   THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cerrada'                     THEN ARRAY[]::estado_ot_enum[]
        ELSE ARRAY[]::estado_ot_enum[]
    END;

    IF NOT (p_nuevo_estado = ANY(v_transiciones_validas)) THEN
        IF p_nuevo_estado = 'cerrada' THEN
            RAISE EXCEPTION 'La transición a "cerrada" solo puede realizarse mediante cierre de supervisor (rpc_cerrar_ot_supervisor).';
        END IF;
        RAISE EXCEPTION 'Transición inválida: "%" → "%". Permitidas: %', v_ot.estado, p_nuevo_estado, v_transiciones_validas;
    END IF;

    -- 3a. → asignada: requiere responsable
    IF p_nuevo_estado = 'asignada' THEN
        IF COALESCE(p_responsable_id, v_ot.responsable_id) IS NULL THEN
            RAISE EXCEPTION 'No se puede asignar OT sin responsable.';
        END IF;
    END IF;

    -- 3b. → en_ejecucion: responsable obligatorio
    IF p_nuevo_estado = 'en_ejecucion' THEN
        IF v_ot.responsable_id IS NULL THEN
            RAISE EXCEPTION 'No se puede iniciar ejecución sin responsable asignado. Asigne un responsable primero.';
        END IF;
    END IF;

    -- 3c. → no_ejecutada: causa obligatoria
    IF p_nuevo_estado = 'no_ejecutada' THEN
        IF p_causa_no_ejecucion IS NULL THEN RAISE EXCEPTION 'Causa de no ejecución es obligatoria.'; END IF;
    END IF;

    -- 3d/3e. → ejecutada_*: evidencia + checklist (cuenta el checklist V03)
    IF p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones') THEN
        -- Evidencia: fotos de evidencias_ot O fotos del checklist V03 O checklist_ot
        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = p_ot_id)
             + (SELECT COUNT(*) FROM checklist_v2_instance ci
                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                 WHERE ci.ot_id = p_ot_id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = p_ot_id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)
          INTO v_count_evidence;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'REGLA: Tarea sin evidencia = tarea no ejecutada. Cargue al menos 1 foto.';
        END IF;

        -- Obligatorios pendientes: primero el V03 (no excluido); si no hay V03, checklist_ot
        SELECT COUNT(*) FILTER (WHERE obligatorio),
               COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
          INTO v_count_checklist_total, v_count_checklist_pending
          FROM v_taller_ot_checklist_v3 WHERE ot_id = p_ot_id AND excluido = false;

        IF COALESCE(v_count_checklist_total,0) = 0 THEN
            SELECT COUNT(*) FILTER (WHERE obligatorio = true),
                   COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
              INTO v_count_checklist_total, v_count_checklist_pending
              FROM checklist_ot WHERE ot_id = p_ot_id;
        END IF;

        IF COALESCE(v_count_checklist_total,0) > 0 AND COALESCE(v_count_checklist_pending,0) > 0 THEN
            RAISE EXCEPTION 'Hay % de % ítems obligatorios sin completar.', v_count_checklist_pending, v_count_checklist_total;
        END IF;

        IF p_nuevo_estado = 'ejecutada_con_observaciones'
           AND COALESCE(p_observaciones, v_ot.observaciones, '') = '' THEN
            RAISE EXCEPTION 'Observaciones obligatorias al finalizar con observaciones.';
        END IF;
    END IF;

    UPDATE ordenes_trabajo
       SET estado = p_nuevo_estado,
           responsable_id = CASE WHEN p_nuevo_estado='asignada' AND p_responsable_id IS NOT NULL THEN p_responsable_id ELSE responsable_id END,
           fecha_inicio = CASE WHEN p_nuevo_estado='en_ejecucion' AND fecha_inicio IS NULL THEN NOW() ELSE fecha_inicio END,
           fecha_termino = CASE WHEN p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada') THEN NOW() ELSE fecha_termino END,
           causa_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_causa_no_ejecucion ELSE causa_no_ejecucion END,
           detalle_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_detalle_no_ejecucion ELSE detalle_no_ejecucion END,
           observaciones = CASE WHEN p_observaciones IS NOT NULL THEN p_observaciones ELSE observaciones END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, p_nuevo_estado,
            COALESCE(p_observaciones, p_detalle_no_ejecucion, v_ot.estado || ' → ' || p_nuevo_estado), p_usuario_id);

    RETURN jsonb_build_object('ot_id', p_ot_id, 'folio', v_ot.folio,
        'estado_anterior', v_ot.estado, 'estado_nuevo', p_nuevo_estado);
END;
$function$;

SELECT 'MIG163 OK' AS resultado;
NOTIFY pgrst, 'reload schema';
