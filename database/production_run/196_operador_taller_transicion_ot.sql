-- ============================================================================
-- SICOM-ICEO | 196 — operador_taller puede iniciar/pausar/finalizar OTs
--                    (rpc_transicion_ot lo dejó fuera al endurecerse en MIG189)
-- ============================================================================
-- Bug reportado por Manuel (2026-07-07): en /m/taller el operador (cuenta
-- compartida, elige su nombre p.ej. Sergio Cortés) aprieta "Iniciar jornada"
-- y no pasa nada.
--
-- Causa: MIG189 agregó a rpc_transicion_ot el gate fail-closed
-- fn_tiene_permiso_modulo('ordenes_trabajo','edit', [roles]) y el rol
-- operador_taller (creado DESPUÉS, en MIG192) no quedó en la lista → la RPC
-- lanza 42501, el sync offline de /m/taller se traga el error (queda en la
-- cola local con last_error) y la UI refresca el estado real → "no pasa nada".
-- MIG192 asumió que la RPC no requería cambios porque tenía GRANT a
-- authenticated, pero el gate interno de MIG189 igual denegaba.
--
--   1. rpc_transicion_ot: se agrega 'operador_taller' a los roles default del
--      gate, acotado a EJECUTAR (iniciar/pausar/finalizar) OTs ya liberadas a
--      ejecución — el mismo universo que ve en v_taller_mecanico_ots (MIG193).
--      No puede asignar, cancelar ni marcar no_ejecutada.
--   2. Si Admin dejó un override en rol_permisos_modulo sin 'edit', se le
--      agrega (el override manda sobre el default y taparía este fix).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                   WHERE t.typname='rol_usuario_enum' AND e.enumlabel='operador_taller') THEN
        RAISE EXCEPTION 'STOP — falta el rol operador_taller (MIG192).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_tiene_permiso_modulo') THEN
        RAISE EXCEPTION 'STOP — falta fn_tiene_permiso_modulo (MIG185).';
    END IF;
END $$;


-- ── 1. rpc_transicion_ot: mismo cuerpo de MIG189 + operador_taller acotado ───
CREATE OR REPLACE FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum DEFAULT NULL::causa_no_ejecucion_enum, p_detalle_no_ejecucion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_responsable_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_ot                     RECORD;
    v_count_evidence         INTEGER;
    v_count_checklist_total  INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas   estado_ot_enum[];
    v_rol                    TEXT;
BEGIN

    -- [MIG189] Autorización fail-closed (ordenes_trabajo/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    -- [MIG196] + operador_taller: ejecuta las OTs liberadas (app /m/taller).
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones','planificador','supervisor','tecnico_mantenimiento','operador_taller']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'edit' USING ERRCODE = '42501';
    END IF;

    -- [MIG196] El operador de taller solo EJECUTA: iniciar / pausar / finalizar.
    -- Nada de asignar, cancelar ni no_ejecutada (eso es de la jefatura).
    v_rol := public.fn_user_rol();
    IF v_rol = 'operador_taller'
       AND p_nuevo_estado NOT IN ('en_ejecucion','pausada','ejecutada_ok','ejecutada_con_observaciones') THEN
        RAISE EXCEPTION 'El operador de taller no puede pasar una OT a "%".', p_nuevo_estado
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada: %', p_ot_id; END IF;

    -- [MIG196] ... y solo sobre OTs ya liberadas a ejecución (universo MIG193).
    IF v_rol = 'operador_taller' AND v_ot.preparacion_ok_at IS NULL THEN
        RAISE EXCEPTION 'La OT % aun no esta liberada a ejecucion.', v_ot.folio
            USING ERRCODE = '42501';
    END IF;

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

REVOKE EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) TO authenticated;


-- ── 2. Si Admin dejó un override para el rol, que incluya 'edit' ──────────────
-- (el override de rol_permisos_modulo manda sobre el default y taparía el fix)
UPDATE rol_permisos_modulo
   SET permisos = array_append(permisos, 'edit')
 WHERE rol = 'operador_taller' AND modulo = 'ordenes_trabajo'
   AND NOT ('edit' = ANY(permisos));


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rpc_incluye_operador_taller', (SELECT prosrc LIKE '%operador_taller%'
        FROM pg_proc WHERE proname = 'rpc_transicion_ot'),
    'rpc_conserva_gate_189', (SELECT prosrc LIKE '%fn_tiene_permiso_modulo%'
        FROM pg_proc WHERE proname = 'rpc_transicion_ot'),
    'override_con_edit', (SELECT COALESCE(bool_and('edit' = ANY(permisos)), true)
        FROM rol_permisos_modulo
        WHERE rol = 'operador_taller' AND modulo = 'ordenes_trabajo')
) AS resultado;

NOTIFY pgrst, 'reload schema';
