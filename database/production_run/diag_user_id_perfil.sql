DO $diag$
DECLARE
  v_prod uuid; v_bod uuid; v_bfaena uuid; v_ot uuid; v_activo uuid; v_aceco uuid; v_nc uuid; v_user uuid;
  v_ticket uuid; v_item uuid; v_res jsonb; v_salida_ceco uuid; v_err text;
BEGIN
  SELECT ic.producto_id, ic.bodega_id, b.faena_id INTO v_prod, v_bod, v_bfaena
    FROM inventario_capas ic JOIN bodegas b ON b.id=ic.bodega_id
   WHERE ic.estado='disponible' AND ic.cantidad_disponible>=1 LIMIT 1;
  -- una OT cuyo activo tenga ceco_id (patente del Excel)
  SELECT o.id, o.activo_id, a.ceco_id INTO v_ot, v_activo, v_aceco
    FROM ordenes_trabajo o JOIN activos a ON a.id=o.activo_id WHERE a.ceco_id IS NOT NULL LIMIT 1;
  SELECT id INTO v_user FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);
  RAISE NOTICE 'ot=% activo=% ceco_patente=%', v_ot, v_activo, v_aceco;
  BEGIN
    UPDATE ordenes_trabajo SET faena_id=v_bfaena, estado='pausada' WHERE id=v_ot;
    INSERT INTO no_conformidades(activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen, estado_planificacion, registrada_por, created_by)
    VALUES (v_activo, v_ot, 'otra', 'NC', CURRENT_DATE, 'media', 'ejecucion_ot', 'registrada', v_user, v_user) RETURNING id INTO v_nc;
    INSERT INTO nc_materiales(no_conformidad_id, producto_id, descripcion, cantidad) VALUES (v_nc, v_prod, 'mat', 1);
    v_res := rpc_crear_ticket_bodega(v_ot, 'http://f/j.png', null);
    v_ticket := (v_res->>'ticket_id')::uuid;
    SELECT id INTO v_item FROM bodega_ticket_items WHERE ticket_id=v_ticket LIMIT 1;
    v_res := rpc_entregar_ticket_bodega(v_ticket, v_bod, jsonb_build_array(jsonb_build_object('ticket_item_id', v_item, 'cantidad', 1)), 'Yusedl', null);
    SELECT ceco_id INTO v_salida_ceco FROM salidas_bodega WHERE folio_salida = v_res->>'despacho_folio';
    RAISE NOTICE 'entrega estado=% ceco_devuelto=% salida_ceco=%', v_res->>'estado', v_res->>'ceco_id', v_salida_ceco;
    RAISE NOTICE 'CECO correcto = %', (v_salida_ceco = v_aceco);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT; RAISE NOTICE 'FALLO: %', v_err; END;
  RAISE EXCEPTION 'rollback';
END $diag$;
