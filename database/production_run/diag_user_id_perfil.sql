DO $diag$
DECLARE
  v_prod uuid; v_bod uuid; v_bfaena uuid; v_disp numeric; v_ot uuid; v_activo uuid; v_nc uuid; v_user uuid;
  v_ticket uuid; v_item uuid; v_res jsonb; v_sa numeric; v_sd numeric; v_err text; v_ctx text;
BEGIN
  SELECT ic.producto_id, ic.bodega_id, b.faena_id, SUM(ic.cantidad_disponible)
    INTO v_prod, v_bod, v_bfaena, v_disp
    FROM inventario_capas ic JOIN bodegas b ON b.id=ic.bodega_id
   WHERE ic.estado='disponible' AND ic.cantidad_disponible>0
   GROUP BY ic.producto_id, ic.bodega_id, b.faena_id HAVING SUM(ic.cantidad_disponible)>=2 ORDER BY 4 DESC LIMIT 1;
  SELECT id, activo_id INTO v_ot, v_activo FROM ordenes_trabajo WHERE activo_id IS NOT NULL LIMIT 1;
  SELECT id INTO v_user FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);
  BEGIN
    -- alinear OT: faena de la bodega + estado pausada (simula media jornada)
    UPDATE ordenes_trabajo SET faena_id=v_bfaena, estado='pausada' WHERE id=v_ot;
    INSERT INTO no_conformidades(activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen, estado_planificacion, registrada_por, created_by)
    VALUES (v_activo, v_ot, 'otra', 'NC test', CURRENT_DATE, 'media', 'ejecucion_ot', 'registrada', v_user, v_user) RETURNING id INTO v_nc;
    INSERT INTO nc_materiales(no_conformidad_id, producto_id, descripcion, cantidad) VALUES (v_nc, v_prod, 'mat test', 2);
    v_res := rpc_crear_ticket_bodega(v_ot, 'http://firma/jefe.png', 'test');
    v_ticket := (v_res->>'ticket_id')::uuid;
    SELECT id INTO v_item FROM bodega_ticket_items WHERE ticket_id=v_ticket LIMIT 1;
    RAISE NOTICE 'EMITIDO folio=% items=%', v_res->>'folio', v_res->>'items';
    SELECT COALESCE(SUM(cantidad_disponible),0) INTO v_sa FROM inventario_capas WHERE producto_id=v_prod AND bodega_id=v_bod AND estado='disponible';
    v_res := rpc_entregar_ticket_bodega(v_ticket, v_bod, jsonb_build_array(jsonb_build_object('ticket_item_id', v_item, 'cantidad', 1)), 'Yusedl', null);
    RAISE NOTICE 'PARCIAL estado=% despacho=%', v_res->>'estado', v_res->>'despacho_folio';
    v_res := rpc_entregar_ticket_bodega(v_ticket, v_bod, jsonb_build_array(jsonb_build_object('ticket_item_id', v_item, 'cantidad', 1)), 'Yusedl', null);
    RAISE NOTICE 'TOTAL estado=% despacho=%', v_res->>'estado', v_res->>'despacho_folio';
    BEGIN
      v_res := rpc_entregar_ticket_bodega(v_ticket, v_bod, jsonb_build_array(jsonb_build_object('ticket_item_id', v_item, 'cantidad', 1)), 'X', null);
      RAISE NOTICE 'FALLA: reuso permitido!';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ANTI-ROBO OK: %', SQLERRM; END;
    SELECT COALESCE(SUM(cantidad_disponible),0) INTO v_sd FROM inventario_capas WHERE producto_id=v_prod AND bodega_id=v_bod AND estado='disponible';
    RAISE NOTICE 'STOCK antes=% despues=% (baja 2)', v_sa, v_sd;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT, v_ctx=PG_EXCEPTION_CONTEXT; RAISE NOTICE 'FALLO: % | %', v_err, v_ctx;
  END;
  RAISE EXCEPTION 'rollback diag';
END $diag$;
