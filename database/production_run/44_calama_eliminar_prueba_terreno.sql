-- ============================================================================
-- 44_calama_eliminar_prueba_terreno.sql
-- ----------------------------------------------------------------------------
-- Permite a administradores eliminar (hard delete) OTs de prueba creadas por
-- MIG42 (rpc_calama_crear_jornada_prueba_terreno) para no contaminar la app
-- en terreno con OTs que fueron solo para validar el flujo.
--
-- SAFETY: el RPC SOLO borra si la OT tiene es_prueba=true. Si una OT real
-- (es_prueba=false) llega por error al payload, falla con excepcion.
--
-- Borra en orden hijo->padre:
--   1. calama_firmas_jornada (es_prueba=true, ot_id)
--   2. calama_evidencias (es_prueba=true, ot_id)
--   3. calama_ot_ejecucion_eventos (es_prueba=true, ot_id)
--   4. calama_ot_ejecuciones (es_prueba=true, ot_id)
--   5. calama_plan_semanal_ots (es_prueba=true, ot_id)
--   6. calama_ot_precheck (ot_id)
--   7. calama_ot_acciones_audit (ot_id) — si la tabla existe
--   8. calama_ordenes_trabajo (es_prueba=true, id)
--
-- NO borra:
--   - Zona TEST (calama_zonas_proyecto codigo_zona='TEST'): se reusa para
--     proximas pruebas del mismo planificacion.
--   - calama_planes_semanales / calama_plan_semanal_dias del sandbox: se
--     reusan.
--   - Archivos en Supabase Storage: el frontend los borra ANTES via
--     supabase.storage.from(...).remove(paths). El RPC retorna los paths
--     que el frontend ya debio limpiar para auditoria.
--
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE).
-- NO modifica estructuras ni datos existentes mas alla del DELETE.
-- ============================================================================


-- ── Prechecks ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_rol TEXT;
BEGIN
    -- MIG42 requerida (es_prueba en tablas calama_*)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo'
                      AND column_name='es_prueba') THEN
        RAISE EXCEPTION 'STOP - MIG42 no aplicada (columna es_prueba en calama_ordenes_trabajo no existe)';
    END IF;

    -- Solo admin puede aplicar
    BEGIN
        v_rol := fn_user_rol();
    EXCEPTION WHEN OTHERS THEN
        v_rol := NULL;
    END;
    IF v_rol IS NULL THEN
        RAISE NOTICE 'Aplicando MIG44 como rol de sistema (current_user=%). OK.', current_user;
    ELSIF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar MIG44 desde sesion autenticada requiere administrador';
    END IF;
    RAISE NOTICE '== MIG44 prechecks OK ==';
END $$;


-- ============================================================================
-- RPC: rpc_calama_eliminar_prueba_terreno
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_eliminar_prueba_terreno(p_payload jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid              UUID := auth.uid();
    v_rol              TEXT;
    v_ot_id            UUID := NULLIF(p_payload->>'ot_id','')::UUID;
    v_es_prueba        BOOLEAN;
    v_folio            TEXT;
    v_paths_evidencias TEXT[];
    v_paths_firmas     TEXT[];
    v_n_firmas         INT := 0;
    v_n_evidencias     INT := 0;
    v_n_eventos        INT := 0;
    v_n_ejecuciones    INT := 0;
    v_n_jornadas       INT := 0;
    v_n_precheck       INT := 0;
    v_n_audit          INT := 0;
    v_n_ot             INT := 0;
BEGIN
    -- ── Auth + rol ─────────────────────────────────────────────────────────
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para eliminar pruebas', v_rol;
    END IF;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'ot_id obligatorio en p_payload'; END IF;

    -- ── Safety: solo es_prueba=true ─────────────────────────────────────────
    SELECT es_prueba, folio INTO v_es_prueba, v_folio
      FROM calama_ordenes_trabajo
     WHERE id = v_ot_id;
    IF v_folio IS NULL THEN
        RAISE EXCEPTION 'OT % no encontrada', v_ot_id;
    END IF;
    IF NOT COALESCE(v_es_prueba, false) THEN
        RAISE EXCEPTION 'NEGADO: OT % (folio %) NO es de prueba (es_prueba=false). Este RPC solo elimina OTs sandbox.', v_ot_id, v_folio;
    END IF;

    -- ── Recolectar paths para retornar al frontend ─────────────────────────
    SELECT COALESCE(array_agg(storage_path) FILTER (WHERE storage_path IS NOT NULL), ARRAY[]::TEXT[])
      INTO v_paths_evidencias
      FROM calama_evidencias
     WHERE ot_id = v_ot_id;

    SELECT COALESCE(array_agg(storage_path) FILTER (WHERE storage_path IS NOT NULL), ARRAY[]::TEXT[])
      INTO v_paths_firmas
      FROM calama_firmas_jornada
     WHERE ot_id = v_ot_id;

    -- ── DELETE hijo -> padre ────────────────────────────────────────────────
    DELETE FROM calama_firmas_jornada WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_firmas = ROW_COUNT;

    DELETE FROM calama_evidencias WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_evidencias = ROW_COUNT;

    DELETE FROM calama_ot_ejecucion_eventos WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_eventos = ROW_COUNT;

    DELETE FROM calama_ot_ejecuciones WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_ejecuciones = ROW_COUNT;

    DELETE FROM calama_plan_semanal_ots WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_jornadas = ROW_COUNT;

    DELETE FROM calama_ot_precheck WHERE ot_id = v_ot_id;
    GET DIAGNOSTICS v_n_precheck = ROW_COUNT;

    -- Audit table: tolerar si no existe
    BEGIN
        EXECUTE 'DELETE FROM calama_ot_acciones_audit WHERE ot_id = $1' USING v_ot_id;
        GET DIAGNOSTICS v_n_audit = ROW_COUNT;
    EXCEPTION WHEN undefined_table THEN
        v_n_audit := 0;
    WHEN undefined_column THEN
        v_n_audit := 0;
    END;

    -- Padre: la OT misma. Doble safety check con es_prueba=true.
    DELETE FROM calama_ordenes_trabajo WHERE id = v_ot_id AND es_prueba = true;
    GET DIAGNOSTICS v_n_ot = ROW_COUNT;
    IF v_n_ot = 0 THEN
        RAISE EXCEPTION 'INCONSISTENCIA: no se elimino la OT % aunque pasaba safety check', v_ot_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'ot_id', v_ot_id,
        'folio', v_folio,
        'eliminado', jsonb_build_object(
            'ot', v_n_ot,
            'jornadas', v_n_jornadas,
            'ejecuciones', v_n_ejecuciones,
            'eventos', v_n_eventos,
            'evidencias', v_n_evidencias,
            'firmas', v_n_firmas,
            'precheck', v_n_precheck,
            'audit', v_n_audit
        ),
        'paths_evidencias', to_jsonb(v_paths_evidencias),
        'paths_firmas',     to_jsonb(v_paths_firmas),
        'mensaje', 'OT de prueba eliminada. El frontend ya debio limpiar Storage; los paths se devuelven solo para confirmacion.'
    );
END $$;

COMMENT ON FUNCTION rpc_calama_eliminar_prueba_terreno IS
'Elimina (hard delete) una OT marcada es_prueba=true junto a sus jornadas, ejecuciones, eventos, evidencias, firmas y precheck. Refusa si la OT es real (es_prueba=false). MIG44.';

GRANT EXECUTE ON FUNCTION rpc_calama_eliminar_prueba_terreno(jsonb) TO authenticated;


-- ============================================================================
-- VERIFICACION POST-APLICACION
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_eliminar_prueba_terreno') THEN
        RAISE EXCEPTION 'FAIL - rpc_calama_eliminar_prueba_terreno no quedo creada';
    END IF;
    RAISE NOTICE '== MIG44 aplicada OK. rpc_calama_eliminar_prueba_terreno disponible. ==';
END $$;
