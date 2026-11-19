-- Rollback MIG711: vuelve rpc_bodega_faena_salida / _ingreso a la versión MIG692 (sin FIFO)
-- y elimina las funciones nuevas. NO revierte la revalorización de capas/CPP de Franke
-- (los costos de referencia quedan; el costo previo era 0 o $1).

CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_salida(p_bodega_id uuid, p_items jsonb, p_activo_id uuid, p_motivo text, p_entregado_a text, p_client_uuid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_prev   JSONB;
    v_ceco   UUID;
    v_it     RECORD;
    v_stock  RECORD;
    v_mov    UUID;
    v_nuevo  NUMERIC;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
    v_bajo   JSONB := '[]'::jsonb;
    v_min    NUMERIC;
    v_res    JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
        RAISE EXCEPTION 'No tiene permiso para sacar de esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos escaneados.'; END IF;
    IF p_activo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Equipo no encontrado.';
    END IF;
    SELECT id INTO v_ceco FROM centros_costo WHERE codigo = 'FRK-OPER';

    FOR v_it IN
        SELECT x.producto_id, x.cantidad, p.nombre, p.categoria
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
          JOIN productos p ON p.id = x.producto_id
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN
            RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre;
        END IF;
        IF v_it.categoria IN ('repuesto', 'filtro', 'lubricante') AND p_activo_id IS NULL THEN
            RAISE EXCEPTION '«%» es % : indique a qué camión o equipo va.', v_it.nombre, v_it.categoria;
        END IF;
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id FOR UPDATE;
        IF NOT FOUND OR v_stock.cantidad < v_it.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente de «%»: hay %, pide %.',
                v_it.nombre, coalesce(v_stock.cantidad, 0), v_it.cantidad;
        END IF;
        v_nuevo := v_stock.cantidad - v_it.cantidad;
        v_mov := gen_random_uuid();
        -- costo_total es columna generada (cantidad × costo_unitario).
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            activo_id, ceco_id, motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'salida', v_it.cantidad, coalesce(v_stock.costo_promedio, 0),
                p_activo_id, v_ceco,
                left(concat_ws(' · ', nullif(btrim(p_motivo), ''),
                               CASE WHEN nullif(btrim(p_entregado_a), '') IS NOT NULL THEN 'entregado a ' || btrim(p_entregado_a) END), 500),
                'LECTOR-' || p_client_uuid::text, auth.uid(), NOW());
        UPDATE stock_bodega SET cantidad = v_nuevo, ultimo_movimiento = NOW(), updated_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'salida', v_it.cantidad,
                v_stock.cantidad, v_nuevo, coalesce(v_stock.costo_promedio, 0), v_stock.costo_promedio,
                v_stock.costo_promedio, v_it.cantidad * coalesce(v_stock.costo_promedio, 0),
                v_nuevo * coalesce(v_stock.costo_promedio, 0));
        v_total := v_total + v_it.cantidad * coalesce(v_stock.costo_promedio, 0);
        v_n := v_n + 1;
        SELECT minimo INTO v_min FROM bodega_stock_parametros WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        IF v_min > 0 AND v_nuevo <= v_min THEN
            v_bajo := v_bajo || jsonb_build_object('producto', v_it.nombre, 'stock', v_nuevo, 'minimo', v_min);
        END IF;
    END LOOP;
    IF v_n <> jsonb_array_length(p_items) THEN RAISE EXCEPTION 'Algún producto escaneado no existe.'; END IF;

    v_res := jsonb_build_object('ok', true, 'items', v_n, 'costo_total', round(v_total), 'bajo_minimo', v_bajo);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'salida', v_res);
    RETURN v_res;
END $function$
;

CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_ingreso(p_bodega_id uuid, p_items jsonb, p_origen text, p_documento text, p_client_uuid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_prev  JSONB;
    v_it    RECORD;
    v_stock RECORD;
    v_costo NUMERIC;
    v_mov   UUID;
    v_cant0 NUMERIC;
    v_cpp0  NUMERIC;
    v_cant1 NUMERIC;
    v_cpp1  NUMERIC;
    v_n     INT := 0;
    v_res   JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
        RAISE EXCEPTION 'No tiene permiso para recibir en esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos escaneados.'; END IF;
    IF length(btrim(coalesce(p_origen, ''))) < 3 THEN RAISE EXCEPTION 'Indique de dónde viene (ej. envío desde Coquimbo, compra local).'; END IF;

    FOR v_it IN
        SELECT x.producto_id, x.cantidad, p.nombre, p.costo_unitario_actual
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
          JOIN productos p ON p.id = x.producto_id
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre; END IF;
        SELECT nullif(s.costo_promedio, 0) INTO v_costo FROM stock_bodega s JOIN bodegas b ON b.id = s.bodega_id
         WHERE b.codigo = 'BOD-CQB-F01' AND s.producto_id = v_it.producto_id;
        v_costo := coalesce(v_costo, nullif(v_it.costo_unitario_actual, 0), 0);
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id FOR UPDATE;
        v_cant0 := coalesce(v_stock.cantidad, 0);
        v_cpp0 := coalesce(v_stock.costo_promedio, 0);
        v_cant1 := v_cant0 + v_it.cantidad;
        v_cpp1 := CASE WHEN v_cant1 > 0 THEN (v_cant0 * v_cpp0 + v_it.cantidad * v_costo) / v_cant1 ELSE v_costo END;
        v_mov := gen_random_uuid();
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'entrada', v_it.cantidad, v_costo,
                left(btrim(p_origen), 300), coalesce(nullif(btrim(p_documento), ''), 'LECTOR-' || p_client_uuid::text),
                auth.uid(), NOW());
        INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
        VALUES (p_bodega_id, v_it.producto_id, v_cant1, v_cpp1, NOW())
        ON CONFLICT (bodega_id, producto_id) DO UPDATE
           SET cantidad = EXCLUDED.cantidad, costo_promedio = EXCLUDED.costo_promedio,
               ultimo_movimiento = NOW(), updated_at = NOW();
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'entrada', v_it.cantidad,
                v_cant0, v_cant1, v_costo, v_cpp0, v_cpp1, v_it.cantidad * v_costo, v_cant1 * v_cpp1);
        v_n := v_n + 1;
    END LOOP;
    IF v_n <> jsonb_array_length(p_items) THEN RAISE EXCEPTION 'Algún producto escaneado no existe.'; END IF;
    v_res := jsonb_build_object('ok', true, 'items', v_n);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'ingreso', v_res);
    RETURN v_res;
END $function$
;

DROP FUNCTION IF EXISTS public.fn_bodega_sync_cpp(UUID, UUID);
DROP FUNCTION IF EXISTS public.fn_bodega_costo_referencia(UUID);
