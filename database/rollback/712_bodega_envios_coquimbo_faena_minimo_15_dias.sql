-- Rollback MIG712: funciones a su versión previa (MIG711/MIG692) y se eliminan envíos, mínimos automáticos y el permiso del mecánico.
-- OJO: borra los envíos registrados (bodega_envios). Si hubo envíos reales, revisar antes: el stock ya movido NO se revierte.

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
    v_fifo   JSONB;
    v_cu     NUMERIC;
    v_cpp1   NUMERIC;
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
        -- Movimiento primero (el consumo FIFO lo referencia); costo se fija abajo.
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            activo_id, ceco_id, motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'salida', v_it.cantidad, 0,
                p_activo_id, v_ceco,
                left(concat_ws(' · ', nullif(btrim(p_motivo), ''),
                               CASE WHEN nullif(btrim(p_entregado_a), '') IS NOT NULL THEN 'entregado a ' || btrim(p_entregado_a) END), 500),
                'LECTOR-' || p_client_uuid::text, auth.uid(), NOW());
        -- [MIG711] consumo FIFO real (mismo motor que los vales de Coquimbo)
        v_fifo := fn_consumir_inventario_fifo(v_it.producto_id, p_bodega_id, v_it.cantidad,
                                              NULL, NULL, v_mov, NULL, v_ceco, auth.uid());
        v_cu := round((v_fifo->>'costo_total')::numeric / v_it.cantidad, 4);
        UPDATE movimientos_inventario SET costo_unitario = v_cu WHERE id = v_mov;
        UPDATE stock_bodega SET cantidad = v_nuevo, ultimo_movimiento = NOW(), updated_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        v_cpp1 := coalesce(fn_bodega_sync_cpp(p_bodega_id, v_it.producto_id), v_stock.costo_promedio);
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'salida', v_it.cantidad,
                v_stock.cantidad, v_nuevo, v_cu, v_stock.costo_promedio, v_cpp1,
                (v_fifo->>'costo_total')::numeric, v_nuevo * coalesce(v_cpp1, 0));
        v_total := v_total + (v_fifo->>'costo_total')::numeric;
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

CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_catalogo(p_bodega_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_bodega_puede_ver(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'generado_at', NOW(),
        'puede_operar', fn_bodega_puede_operar(p_bodega_id),
        'productos', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                         p.id, p.codigo, p.codigo_barras, p.nombre, p.categoria, p.unidad_medida,
                         coalesce(s.cantidad, 0), pr.minimo)), '[]'::jsonb)
                        FROM productos p
                        LEFT JOIN stock_bodega s ON s.producto_id = p.id AND s.bodega_id = p_bodega_id
                        LEFT JOIN bodega_stock_parametros pr ON pr.producto_id = p.id AND pr.bodega_id = p_bodega_id),
        'equipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'patente', a.patente, 'tipo', a.tipo)
                       ORDER BY a.patente), '[]'::jsonb)
                      FROM activos a WHERE a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42', 'LLBP-96')));
END $function$
;

CREATE OR REPLACE FUNCTION public.rpc_bodega_set_parametro(p_bodega_id uuid, p_producto_id uuid, p_minimo numeric, p_maximo numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF p_minimo IS NULL OR p_minimo < 0 THEN RAISE EXCEPTION 'El mínimo debe ser 0 o más.'; END IF;
    IF p_maximo IS NOT NULL AND p_maximo < p_minimo THEN RAISE EXCEPTION 'El máximo no puede ser menor que el mínimo.'; END IF;
    INSERT INTO bodega_stock_parametros (bodega_id, producto_id, minimo, maximo, updated_by, updated_at)
    VALUES (p_bodega_id, p_producto_id, p_minimo, p_maximo, auth.uid(), NOW())
    ON CONFLICT (bodega_id, producto_id) DO UPDATE
       SET minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, updated_by = auth.uid(), updated_at = NOW();
END $function$
;

CREATE OR REPLACE FUNCTION public.fn_bodega_alertas_cron(p_secreto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    RETURN (SELECT coalesce(jsonb_agg(b), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
                 'bodega_id', bo.id, 'bodega', bo.nombre,
                 'para', (SELECT coalesce(jsonb_agg(DISTINCT r.email), '[]') FROM bodega_responsables r
                           WHERE r.bodega_id = bo.id AND r.activo AND r.recibe_alertas AND r.tipo_correo = 'para' AND r.email IS NOT NULL),
                 'cc',   (SELECT coalesce(jsonb_agg(DISTINCT r.email), '[]') FROM bodega_responsables r
                           WHERE r.bodega_id = bo.id AND r.activo AND r.recibe_alertas AND r.tipo_correo = 'cc' AND r.email IS NOT NULL),
                 'nuevas', (SELECT jsonb_agg(jsonb_build_object('id', a.id, 'producto', p.nombre, 'codigo', p.codigo,
                               'unidad', p.unidad_medida, 'stock', a.stock, 'minimo', a.minimo) ORDER BY p.nombre)
                              FROM bodega_alertas_stock a JOIN productos p ON p.id = a.producto_id
                             WHERE a.bodega_id = bo.id AND a.estado = 'abierta' AND a.notificada_at IS NULL),
                 'abiertas', (SELECT count(*) FROM bodega_alertas_stock a WHERE a.bodega_id = bo.id AND a.estado = 'abierta')) AS b
          FROM bodegas bo
         WHERE EXISTS (SELECT 1 FROM bodega_alertas_stock a
                        WHERE a.bodega_id = bo.id AND a.estado = 'abierta' AND a.notificada_at IS NULL)) q);
END $function$
;

DROP FUNCTION IF EXISTS public.rpc_bodega_envio_sugerido(UUID, UUID);
DROP FUNCTION IF EXISTS public.rpc_bodega_envios(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.rpc_bodega_envio_anular(UUID, TEXT);
DROP FUNCTION IF EXISTS public.rpc_bodega_envio_recibir(UUID, JSONB, TEXT, UUID);
DROP FUNCTION IF EXISTS public.fn_bodega_entrada_transferencia(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.rpc_bodega_envio_crear(UUID, UUID, JSONB, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.rpc_bodega_recalcular_minimos(UUID);
DROP FUNCTION IF EXISTS public.fn_bodega_recalcular_minimos(UUID);
DROP FUNCTION IF EXISTS public.fn_bodega_puede_enviar(UUID);
DROP FUNCTION IF EXISTS public.fn_bodega_puede_sacar(UUID);
DROP TABLE IF EXISTS public.bodega_envio_items;   -- destructivo-ok: rollback
DROP TABLE IF EXISTS public.bodega_envios;        -- destructivo-ok: rollback
DROP SEQUENCE IF EXISTS public.bodega_envio_folio_seq;
DROP TABLE IF EXISTS public.bodega_cecos_consumo; -- destructivo-ok: rollback
DELETE FROM public.bodega_operaciones WHERE tipo IN ('envio', 'recepcion_envio');
ALTER TABLE public.bodega_operaciones DROP CONSTRAINT IF EXISTS bodega_operaciones_tipo_check;
ALTER TABLE public.bodega_operaciones ADD CONSTRAINT bodega_operaciones_tipo_check CHECK (tipo IN ('salida', 'ingreso', 'conteo'));
DELETE FROM public.bodega_responsables WHERE solo_sacar;
ALTER TABLE public.bodega_responsables DROP COLUMN IF EXISTS solo_sacar;
DELETE FROM public.bodega_stock_parametros WHERE origen <> 'manual';
ALTER TABLE public.bodega_stock_parametros DROP CONSTRAINT IF EXISTS bodega_stock_parametros_origen_check;
ALTER TABLE public.bodega_stock_parametros DROP COLUMN IF EXISTS consumo_diario, DROP COLUMN IF EXISTS origen, DROP COLUMN IF EXISTS calculado_at;
ALTER TABLE public.bodegas DROP COLUMN IF EXISTS dias_minimo;

-- fn_bodega_costo_referencia vuelve a la versión MIG711
CREATE OR REPLACE FUNCTION public.fn_bodega_costo_referencia(p_producto_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
    v_cod   TEXT;
    v_base  TEXT;
    v_cqb   UUID;
    v_costo NUMERIC;
BEGIN
    SELECT codigo INTO v_cod FROM productos WHERE id = p_producto_id;
    IF v_cod IS NULL THEN RETURN 0; END IF;
    SELECT id INTO v_cqb FROM bodegas WHERE codigo = 'BOD-CQB-F01';

    -- a) CPP Coquimbo
    SELECT nullif(costo_promedio, 0) INTO v_costo FROM stock_bodega
     WHERE bodega_id = v_cqb AND producto_id = p_producto_id;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;

    -- b) última capa con costo en Coquimbo (ignora las semillas de $1)
    SELECT costo_unitario INTO v_costo FROM inventario_capas
     WHERE bodega_id = v_cqb AND producto_id = p_producto_id AND costo_unitario > 1
     ORDER BY fecha_recepcion DESC, created_at DESC LIMIT 1;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;

    -- c) último precio de OC aprobada (código exacto, luego base sin sufijo)
    SELECT l.precio_unit INTO v_costo
      FROM softland_oc_linea l JOIN softland_oc o USING (num_inter_oc)
     WHERE l.cod_prod = v_cod AND o.estado = 'AP' AND l.precio_unit > 0
     ORDER BY o.fecha_oc DESC, o.num_inter_oc DESC LIMIT 1;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    v_base := regexp_replace(v_cod, '-[^-]+$', '');
    IF v_base <> v_cod THEN
        SELECT l.precio_unit INTO v_costo
          FROM softland_oc_linea l JOIN softland_oc o USING (num_inter_oc)
         WHERE l.cod_prod = v_base AND o.estado = 'AP' AND l.precio_unit > 0
         ORDER BY o.fecha_oc DESC, o.num_inter_oc DESC LIMIT 1;
        IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    END IF;

    -- d) costo maestro · e) 0
    SELECT nullif(costo_unitario_actual, 0) INTO v_costo FROM productos WHERE id = p_producto_id;
    RETURN round(coalesce(v_costo, 0), 4);
END $$;
