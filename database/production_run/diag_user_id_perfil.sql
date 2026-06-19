DO $diag$
DECLARE v_ot uuid; v_user uuid; v_one uuid; v_nc int; v_res jsonb; v_err text;
BEGIN
  SELECT v.ot_id INTO v_ot FROM v_taller_ot_checklist_v3 v JOIN taller_plan_semanal_ots t ON t.ot_id=v.ot_id GROUP BY v.ot_id LIMIT 1;
  SELECT id INTO v_user FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);
  BEGIN
    PERFORM rpc_taller_liberar_ejecucion(v_ot);
    UPDATE ordenes_trabajo SET estado='asignada' WHERE id=v_ot;
    PERFORM rpc_transicion_ot(v_ot, 'en_ejecucion', v_user);
    UPDATE checklist_v2_instance_item SET resultado='ok' WHERE id IN (SELECT instance_item_id FROM v_taller_ot_checklist_v3 WHERE ot_id=v_ot AND excluido=false AND obligatorio);
    SELECT instance_item_id INTO v_one FROM v_taller_ot_checklist_v3 WHERE ot_id=v_ot AND excluido=false AND obligatorio LIMIT 1;
    UPDATE checklist_v2_instance_item SET resultado='no_ok', foto_url='http://x/f.jpg' WHERE id=v_one;
    PERFORM rpc_transicion_ot(v_ot, 'pausada', v_user, p_observaciones=>'fin j1');
    SELECT COUNT(*) INTO v_nc FROM no_conformidades WHERE ot_id=v_ot AND origen='ejecucion_ot';
    PERFORM rpc_transicion_ot(v_ot, 'en_ejecucion', v_user);
    v_res := rpc_taller_finalizar_mecanico(v_ot, 'http://x/firma.png', false, null);
    RAISE NOTICE 'NC=% FINALIZAR -> %', v_nc, v_res->>'estado_nuevo';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT; RAISE NOTICE 'FALLO: %', v_err; END;
  RAISE EXCEPTION 'rollback';
END $diag$;
