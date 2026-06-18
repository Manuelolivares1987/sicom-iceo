DO $diag$
DECLARE
  v_ot uuid; v_item uuid; v_user uuid; v_new uuid; v_err text; v_ctx text;
BEGIN
  SELECT v.ot_id, v.instance_item_id INTO v_ot, v_item
    FROM v_taller_ot_checklist_v3 v
    JOIN taller_plan_semanal_ots t ON t.ot_id = v.ot_id
   WHERE v.es_custom = false LIMIT 1;
  SELECT id INTO v_user FROM usuarios_perfil WHERE rol IN ('administrador','jefe_mantenimiento') AND activo=true LIMIT 1;
  IF v_user IS NULL THEN SELECT id INTO v_user FROM usuarios_perfil WHERE activo=true LIMIT 1; END IF;
  RAISE NOTICE 'ot=% item=% user=%', v_ot, v_item, v_user;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);
  BEGIN
    PERFORM rpc_taller_v3_set_tiempo(v_item, 45);
    PERFORM rpc_taller_v3_set_excluido(v_item, true);
    PERFORM rpc_taller_v3_set_excluido(v_item, false);
    SELECT (rpc_taller_v3_agregar_item(v_ot, 'Tarea de prueba diag', 30)->>'item_id')::uuid INTO v_new;
    PERFORM rpc_taller_v3_eliminar_custom(v_new);
    RAISE NOTICE 'OK: las 4 RPC corrieron (item nuevo=% ya eliminado)', v_new;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT, v_ctx=PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'ERROR: % | %', v_err, v_ctx;
  END;
  RAISE EXCEPTION 'rollback diag intencional';
END $diag$;
