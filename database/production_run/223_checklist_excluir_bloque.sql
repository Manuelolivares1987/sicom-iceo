-- ============================================================================
-- SICOM-ICEO | 223 — Excluir/incluir un BLOQUE completo del checklist V03
-- ============================================================================
-- Pedido Manuel (2026-07-10): la preparación del jefe con 188 ítems es poco
-- amigable. La UI pasa a bloques colapsables y este RPC permite marcar
-- "No aplica" un bloque entero de una vez (en vez de ítem por ítem).
-- Mismos permisos que la edición de checklist (jefatura). IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_taller_v3_set_excluido_bloque(
    p_ot_id UUID,
    p_bloque TEXT,
    p_excluido BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_n INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para editar el checklist (rol: %)', v_rol;
    END IF;

    -- El bloque vive en la plantilla: resolver los ítems vía la vista V03.
    UPDATE checklist_v2_instance_item ii
       SET excluido = p_excluido
     WHERE ii.id IN (SELECT v.instance_item_id FROM v_taller_ot_checklist_v3 v
                      WHERE v.ot_id = p_ot_id AND v.bloque = p_bloque)
       AND COALESCE(ii.excluido, false) IS DISTINCT FROM p_excluido;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    RETURN jsonb_build_object('success', true, 'items_actualizados', v_n,
        'bloque', p_bloque, 'excluido', p_excluido);
END $$;
REVOKE EXECUTE ON FUNCTION rpc_taller_v3_set_excluido_bloque(UUID, TEXT, BOOLEAN) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION rpc_taller_v3_set_excluido_bloque(UUID, TEXT, BOOLEAN) TO authenticated;

SELECT jsonb_build_object(
    'rpc_ok', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_taller_v3_set_excluido_bloque'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
