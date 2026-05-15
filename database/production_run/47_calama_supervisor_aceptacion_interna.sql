-- ============================================================================
-- 47_calama_supervisor_aceptacion_interna.sql
-- ----------------------------------------------------------------------------
-- 2 RPCs nuevos para el flujo de aceptacion INTERNA por supervisor (paralelo
-- al flujo de aceptacion del mandante de MIG29/30, que sigue intacto).
--
--   rpc_calama_supervisar_jornada          -> OK supervisor (transicion a
--                                              'aceptada' o 'cerrada')
--   rpc_calama_devolver_jornada_correccion -> devolver al operador
--                                              ('requiere_correccion')
--
-- Diferencias vs rpc_calama_registrar_aceptacion_jornada (MIG30):
--   - Rol permitido: fn_calama_puede_planificar() (admin global, jefe_sucursal,
--     planificador_calama, supervisor_calama). NO requiere fn_calama_es_mandante.
--   - NO requiere firma + nombre + RUT del cliente. Comentario opcional.
--   - NO inserta fila en calama_firmas_jornada. Solo auditoria.
--
-- Estados de entrada validos: finalizada_operador, pendiente_aprobacion.
-- Estado de salida segun avance:
--   avance_pct >= 100 -> 'cerrada' (y ot.estado='finalizada')
--   avance_pct <  100 -> 'aceptada' (y ot.estado='parcial')
-- (mismo criterio que MIG30 para aceptacion mandante).
--
-- Devolucion a correccion (rechazo supervisor):
--   estado_plan -> 'requiere_correccion'
--   ot.estado   -> 'requiere_correccion'
--   motivo obligatorio.
--
-- ADITIVA. NO toca migs anteriores. NO modifica check constraints.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_calama_puede_planificar') THEN
        RAISE EXCEPTION 'STOP - MIG17 no aplicada (falta fn_calama_puede_planificar).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_calama_audit_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG32 no aplicada (falta fn_calama_audit_jornada).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public'
           AND table_name='calama_plan_semanal_ots'
           AND column_name='cierre_jornada_at'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG33 no aplicada (falta cierre_jornada_at).';
    END IF;
END $$;


-- ============================================================================
-- ── RPC 1: supervisar_jornada (OK supervisor interno) ─────────────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_supervisar_jornada(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid           UUID := auth.uid();
    v_plan_ot_id    UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_comentario    TEXT := p_payload->>'comentario';
    v_ot_id         UUID;
    v_estado_actual TEXT;
    v_avance        NUMERIC;
    v_now           TIMESTAMPTZ := NOW();
    v_nuevo_estado_plan TEXT;
    v_nuevo_estado_ot   TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para supervisar jornada';
    END IF;
    IF v_plan_ot_id IS NULL THEN
        RAISE EXCEPTION 'plan_semanal_ot_id obligatorio';
    END IF;

    SELECT po.ot_id, po.estado_plan, ot.avance_pct
      INTO v_ot_id, v_estado_actual, v_avance
      FROM calama_plan_semanal_ots po
      JOIN calama_ordenes_trabajo  ot ON ot.id = po.ot_id
     WHERE po.id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    IF v_estado_actual NOT IN ('finalizada','finalizada_operador','pendiente_aprobacion') THEN
        RAISE EXCEPTION 'Jornada en estado % no admite supervision', v_estado_actual;
    END IF;

    -- Misma logica de cierre que rpc_calama_registrar_aceptacion_jornada.
    IF COALESCE(v_avance, 0) >= 100 THEN
        v_nuevo_estado_plan := 'cerrada';
        v_nuevo_estado_ot   := 'finalizada';
    ELSE
        v_nuevo_estado_plan := 'aceptada';
        v_nuevo_estado_ot   := 'parcial';
    END IF;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = v_nuevo_estado_plan,
           updated_at  = v_now
     WHERE id = v_plan_ot_id;

    UPDATE calama_ordenes_trabajo
       SET estado     = v_nuevo_estado_ot,
           updated_at = v_now
     WHERE id = v_ot_id;

    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id',              v_ot_id::text,
        'accion',             'supervisar_interno',
        'estado_anterior',    v_estado_actual,
        'estado_nuevo',       v_nuevo_estado_plan,
        'observacion',        v_comentario,
        'metadata', jsonb_build_object(
            'avance_pct_en_supervision', v_avance,
            'origen', 'rpc_calama_supervisar_jornada'
        )
    ));

    RETURN jsonb_build_object(
        'success',          true,
        'plan_semanal_ot_id', v_plan_ot_id,
        'estado_plan_nuevo', v_nuevo_estado_plan,
        'estado_ot_nuevo',   v_nuevo_estado_ot
    );
END $$;

COMMENT ON FUNCTION rpc_calama_supervisar_jornada(jsonb) IS
'MIG47 - OK supervisor interno. Transiciona pendiente_aprobacion/finalizada_operador -> aceptada (o cerrada si avance=100). NO requiere firma cliente. Auditado en calama_jornada_auditoria como supervisar_interno.';

GRANT EXECUTE ON FUNCTION rpc_calama_supervisar_jornada(jsonb) TO authenticated;


-- ============================================================================
-- ── RPC 2: devolver jornada a correccion (rechazo supervisor) ─────────────
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_devolver_jornada_correccion(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid           UUID := auth.uid();
    v_plan_ot_id    UUID := (p_payload->>'plan_semanal_ot_id')::UUID;
    v_motivo        TEXT := p_payload->>'motivo';
    v_observacion   TEXT := p_payload->>'observacion';
    v_ot_id         UUID;
    v_estado_actual TEXT;
    v_now           TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para devolver jornada';
    END IF;
    IF v_plan_ot_id IS NULL THEN
        RAISE EXCEPTION 'plan_semanal_ot_id obligatorio';
    END IF;
    IF v_motivo IS NULL OR length(trim(v_motivo)) = 0 THEN
        RAISE EXCEPTION 'motivo obligatorio para devolver a correccion';
    END IF;

    SELECT po.ot_id, po.estado_plan
      INTO v_ot_id, v_estado_actual
      FROM calama_plan_semanal_ots po
     WHERE po.id = v_plan_ot_id;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'plan_semanal_ot_id no encontrado'; END IF;

    IF v_estado_actual NOT IN ('finalizada','finalizada_operador','pendiente_aprobacion') THEN
        RAISE EXCEPTION 'Jornada en estado % no admite devolucion', v_estado_actual;
    END IF;

    UPDATE calama_plan_semanal_ots
       SET estado_plan = 'requiere_correccion',
           updated_at  = v_now
     WHERE id = v_plan_ot_id;

    UPDATE calama_ordenes_trabajo
       SET estado     = 'requiere_correccion',
           updated_at = v_now
     WHERE id = v_ot_id;

    PERFORM fn_calama_audit_jornada(jsonb_build_object(
        'plan_semanal_ot_id', v_plan_ot_id::text,
        'ot_id',              v_ot_id::text,
        'accion',             'devolver_a_correccion',
        'estado_anterior',    v_estado_actual,
        'estado_nuevo',       'requiere_correccion',
        'motivo',             v_motivo,
        'observacion',        v_observacion,
        'metadata', jsonb_build_object('origen','rpc_calama_devolver_jornada_correccion')
    ));

    RETURN jsonb_build_object(
        'success',           true,
        'plan_semanal_ot_id', v_plan_ot_id,
        'estado_plan_nuevo', 'requiere_correccion'
    );
END $$;

COMMENT ON FUNCTION rpc_calama_devolver_jornada_correccion(jsonb) IS
'MIG47 - Devuelve jornada al operador para correccion. Transiciona pendiente_aprobacion/finalizada_operador -> requiere_correccion. Motivo obligatorio. Auditado en calama_jornada_auditoria como devolver_a_correccion.';

GRANT EXECUTE ON FUNCTION rpc_calama_devolver_jornada_correccion(jsonb) TO authenticated;


-- ============================================================================
-- ── Vista: jornadas pendientes de supervision ─────────────────────────────
-- ============================================================================
CREATE OR REPLACE VIEW v_calama_jornadas_pendientes_supervision AS
SELECT
    po.id                  AS plan_semanal_ot_id,
    po.ot_id,
    o.folio,
    o.titulo,
    p.linea_negocio,
    o.avance_pct,
    po.estado_plan,
    po.plan_dia_id,
    d.fecha                AS fecha_jornada,
    d.nombre_dia,
    po.llegada_faena_at,
    po.cierre_jornada_at,
    po.responsable_id,
    u.email                AS responsable_email,
    -- Tiempos (cargados al cierre por MIG33).
    po.tiempo_en_faena_segundos,
    po.tiempo_operativo_bruto_segundos,
    po.tiempo_pausado_segundos,
    po.tiempo_colacion_segundos,
    po.tiempo_interferencia_mandante_segundos,
    po.tiempo_efectivo_trabajo_segundos,
    -- Evidencias agregadas para el listado.
    (SELECT COUNT(*) FROM calama_evidencias e
      WHERE e.ot_id = po.ot_id AND e.contexto = 'jornada_antes')   AS evid_antes,
    (SELECT COUNT(*) FROM calama_evidencias e
      WHERE e.ot_id = po.ot_id AND e.contexto = 'jornada_durante') AS evid_durante,
    (SELECT COUNT(*) FROM calama_evidencias e
      WHERE e.ot_id = po.ot_id AND e.contexto = 'jornada_despues') AS evid_despues,
    (SELECT COUNT(*) FROM calama_firmas_jornada f
      WHERE f.plan_semanal_ot_id = po.id AND f.firmante_tipo = 'operador') AS firmas_operador,
    p.id     AS planificacion_id,
    p.codigo AS planificacion_codigo
  FROM calama_plan_semanal_ots po
  JOIN calama_ordenes_trabajo  o ON o.id = po.ot_id
  JOIN calama_planificaciones  p ON p.id = o.planificacion_id
  LEFT JOIN calama_plan_semanal_dias d ON d.id = po.plan_dia_id
  LEFT JOIN auth.users u ON u.id = po.responsable_id
 WHERE po.estado_plan IN ('finalizada_operador','pendiente_aprobacion')
   AND po.visible_en_kanban = true
   AND po.desprogramada_at IS NULL
   AND po.anulada_at IS NULL
   AND o.es_prueba = false;

COMMENT ON VIEW v_calama_jornadas_pendientes_supervision IS
'MIG47 - Listado de jornadas que esperan OK del supervisor (estado_plan en finalizada_operador o pendiente_aprobacion). Excluye OTs de prueba, desprogramadas y anuladas. Incluye tiempos, evidencias y firma operador para revision.';

GRANT SELECT ON v_calama_jornadas_pendientes_supervision TO authenticated;

NOTIFY pgrst, 'reload schema';
