DO $diag$
DECLARE
  v_ot uuid; v_item uuid; v_user uuid; v_nc_antes int; v_nc_despues int; v_err text; v_ctx text;
BEGIN
  SELECT v.ot_id, v.instance_item_id INTO v_ot, v_item
    FROM v_taller_ot_checklist_v3 v
    JOIN taller_plan_semanal_ots t ON t.ot_id = v.ot_id
   WHERE v.es_custom = false AND v.excluido = false LIMIT 1;
  SELECT id INTO v_user FROM usuarios_perfil WHERE activo=true LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);
  BEGIN
    -- marcar el item NO OK con foto simulada
    UPDATE checklist_v2_instance_item SET resultado='no_ok', foto_url='https://x/foto.jpg', observacion='fuga detectada'
     WHERE id = v_item;
    SELECT COUNT(*) INTO v_nc_antes FROM no_conformidades WHERE checklist_item_ref = v_item;
    -- transicionar OT a pausada (dispara trigger)
    UPDATE ordenes_trabajo SET estado='pausada' WHERE id = v_ot AND estado <> 'pausada';
    SELECT COUNT(*) INTO v_nc_despues FROM no_conformidades WHERE checklist_item_ref = v_item;
    RAISE NOTICE 'NC antes=% despues=% (item=%)', v_nc_antes, v_nc_despues, v_item;
    -- verificar que entra al tablero del jefe
    PERFORM 1 FROM v_nc_recepcion WHERE ot_id = v_ot AND origen='ejecucion_ot';
    RAISE NOTICE 'en bandeja jefe: %', (SELECT COUNT(*) FROM v_nc_recepcion WHERE ot_id=v_ot AND origen='ejecucion_ot');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT, v_ctx=PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'ERROR: % | %', v_err, v_ctx;
  END;
  RAISE EXCEPTION 'rollback diag intencional';
END $diag$;
