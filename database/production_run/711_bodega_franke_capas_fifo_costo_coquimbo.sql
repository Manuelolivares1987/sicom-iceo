-- ============================================================================
-- MIG711 — Bodega de faena Franke: capas FIFO al día y costo desde Coquimbo
-- ----------------------------------------------------------------------------
-- Problema (prueba E2E 18-11-2026, tras cargar el inventario inicial de Franke):
--   1. Sacar / Recibir del lector (rpc_bodega_faena_salida / _ingreso) solo
--      movían stock_bodega: las capas FIFO quedaban congeladas y, tras la
--      primera salida, stock ≠ FIFO (lo que lee cualquier vale/reporte FIFO).
--   2. El inventario inicial entró sin costo (CPP 0): cada salida cargaba $0
--      al camión y el panel valorizaba la bodega en $0.
--
-- Regla de costo (Manuel, 18-11): Franke se abastece desde la bodega central
-- de Coquimbo y a veces compra en otro lado. Costo de referencia de un
-- producto, en orden:
--   a) CPP de BOD-CQB-F01 · b) última capa con costo de BOD-CQB-F01 ·
--   c) último precio de OC aprobada en Softland (código exacto, luego código
--      base sin sufijo de talla, p.ej. ISEEPPBUP003-XXL → ISEEPPBUP003) ·
--   d) costo maestro · e) 0.
--
-- Cambios:
--   • fn_bodega_costo_referencia(producto)  — la regla de arriba.
--   • fn_bodega_sync_cpp(bodega, producto)  — CPP = valor FIFO disponible ÷ un.
--   • rpc_bodega_faena_salida  — consume capas FIFO (fn_consumir_inventario_fifo)
--     y carga al movimiento/kardex el costo FIFO real.
--   • rpc_bodega_faena_ingreso — crea una capa por ítem (costo = el informado si
--     es compra con costo, si no la referencia) y recalcula CPP desde FIFO.
--   • Datos: revaloriza las 141 capas del inventario inicial de Franke (sin
--     consumos) + sus movimientos/kardex de ajuste + CPP de stock_bodega.
--   • Verificación: en Franke stock = FIFO por producto, o aborta.
--
-- Firmas públicas sin cambio (el frontend no se toca).
-- Rollback: database/rollback/711_bodega_franke_capas_fifo_costo_coquimbo.sql
-- ============================================================================

-- ── 1. Costo de referencia ──────────────────────────────────────────────────
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
REVOKE ALL ON FUNCTION public.fn_bodega_costo_referencia(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_bodega_costo_referencia(UUID) TO authenticated;

-- ── 2. CPP desde FIFO ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_bodega_sync_cpp(p_bodega_id UUID, p_producto_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_cant NUMERIC; v_valor NUMERIC; v_cpp NUMERIC;
BEGIN
    SELECT coalesce(sum(cantidad_disponible), 0), coalesce(sum(cantidad_disponible * costo_unitario), 0)
      INTO v_cant, v_valor
      FROM inventario_capas
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id AND estado = 'disponible';
    IF v_cant > 0 THEN
        v_cpp := round(v_valor / v_cant, 4);
        UPDATE stock_bodega SET costo_promedio = v_cpp, updated_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;
    END IF;
    RETURN v_cpp;
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_sync_cpp(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ── 3. Sacar (lector) con consumo FIFO ──────────────────────────────────────
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
END $function$;

-- ── 4. Recibir (lector) creando capa FIFO ───────────────────────────────────
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
    v_doc   TEXT;
    v_n     INT := 0;
    v_total NUMERIC := 0;
    v_res   JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
        RAISE EXCEPTION 'No tiene permiso para recibir en esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos escaneados.'; END IF;
    IF length(btrim(coalesce(p_origen, ''))) < 3 THEN RAISE EXCEPTION 'Indique de dónde viene (ej. envío desde Coquimbo, compra local).'; END IF;
    v_doc := coalesce(nullif(btrim(p_documento), ''), 'LECTOR-' || p_client_uuid::text);

    FOR v_it IN
        SELECT x.producto_id, x.cantidad, x.costo_unitario AS costo_inf, p.nombre, p.unidad_medida
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC, costo_unitario NUMERIC)
          JOIN productos p ON p.id = x.producto_id
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre; END IF;
        -- [MIG711] costo: el informado (compra local con factura) o la referencia Coquimbo → Softland
        v_costo := coalesce(nullif(v_it.costo_inf, 0), fn_bodega_costo_referencia(v_it.producto_id));
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id FOR UPDATE;
        v_cant0 := coalesce(v_stock.cantidad, 0);
        v_cpp0 := coalesce(v_stock.costo_promedio, 0);
        v_cant1 := v_cant0 + v_it.cantidad;
        v_mov := gen_random_uuid();
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'entrada', v_it.cantidad, v_costo,
                left(btrim(p_origen), 300), v_doc, auth.uid(), NOW());
        INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
        VALUES (p_bodega_id, v_it.producto_id, v_cant1, v_costo, NOW())
        ON CONFLICT (bodega_id, producto_id) DO UPDATE
           SET cantidad = EXCLUDED.cantidad, ultimo_movimiento = NOW(), updated_at = NOW();
        INSERT INTO inventario_capas (producto_id, bodega_id, fecha_recepcion, folio_recepcion,
                                      cantidad_inicial, cantidad_disponible, unidad, costo_unitario,
                                      estado, created_by, created_at, updated_at)
        VALUES (v_it.producto_id, p_bodega_id, CURRENT_DATE, left(v_doc, 50),
                v_it.cantidad, v_it.cantidad, coalesce(v_it.unidad_medida, 'unidad'), v_costo,
                'disponible', auth.uid(), NOW(), NOW());
        v_cpp1 := coalesce(fn_bodega_sync_cpp(p_bodega_id, v_it.producto_id), v_costo);
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'entrada', v_it.cantidad,
                v_cant0, v_cant1, v_costo, v_cpp0, v_cpp1, v_it.cantidad * v_costo, v_cant1 * v_cpp1);
        v_total := v_total + v_it.cantidad * v_costo;
        v_n := v_n + 1;
    END LOOP;
    IF v_n <> jsonb_array_length(p_items) THEN RAISE EXCEPTION 'Algún producto escaneado no existe.'; END IF;
    v_res := jsonb_build_object('ok', true, 'items', v_n, 'costo_total', round(v_total));
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'ingreso', v_res);
    RETURN v_res;
END $function$;

-- ── 5. Datos: revalorizar el inventario inicial de Franke (18-11-2026) ───────
-- Solo capas sin consumos (las 141 del conteo inicial); no toca otras bodegas.
DO $$
DECLARE
    v_bod UUID;
    v_n   INT;
BEGIN
    SELECT id INTO v_bod FROM bodegas WHERE codigo = 'BOD-FRK-F01';

    CREATE TEMP TABLE _frk_costo ON COMMIT DROP AS
    SELECT ic.producto_id, fn_bodega_costo_referencia(ic.producto_id) AS costo
      FROM inventario_capas ic
     WHERE ic.bodega_id = v_bod AND ic.folio_recepcion = 'AJUSTE-INVENTARIO'
       AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.capa_id = ic.id)
     GROUP BY ic.producto_id;

    UPDATE inventario_capas ic SET costo_unitario = t.costo
      FROM _frk_costo t
     WHERE ic.bodega_id = v_bod AND ic.producto_id = t.producto_id
       AND ic.folio_recepcion = 'AJUSTE-INVENTARIO'
       AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas c WHERE c.capa_id = ic.id);
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE stock_bodega sb SET costo_promedio = t.costo, updated_at = NOW()
      FROM _frk_costo t WHERE sb.bodega_id = v_bod AND sb.producto_id = t.producto_id;

    -- Movimientos y kardex del ajuste inicial (solo si es el único movimiento del producto)
    UPDATE movimientos_inventario m SET costo_unitario = t.costo
      FROM _frk_costo t
     WHERE m.bodega_id = v_bod AND m.producto_id = t.producto_id AND m.tipo = 'ajuste_positivo'
       AND NOT EXISTS (SELECT 1 FROM movimientos_inventario o
                        WHERE o.bodega_id = v_bod AND o.producto_id = t.producto_id AND o.id <> m.id);
    UPDATE kardex k SET costo_unitario = t.costo, costo_promedio_anterior = 0,
                        costo_promedio_posterior = t.costo,
                        valor_movimiento = k.cantidad_movimiento * t.costo,
                        valor_stock_posterior = k.cantidad_posterior * t.costo
      FROM movimientos_inventario m, _frk_costo t
     WHERE k.movimiento_id = m.id AND m.bodega_id = v_bod AND m.producto_id = t.producto_id
       AND m.tipo = 'ajuste_positivo';
    UPDATE conteo_detalle d SET diferencia_valorizada = d.diferencia * t.costo
      FROM conteos_inventario ci, _frk_costo t
     WHERE d.conteo_id = ci.id AND ci.bodega_id = v_bod AND d.producto_id = t.producto_id;

    RAISE NOTICE 'MIG711: % capas de Franke revalorizadas; % productos sin costo de referencia',
        v_n, (SELECT count(*) FROM _frk_costo WHERE costo = 0);
END $$;

-- ── 6. Verificación ─────────────────────────────────────────────────────────
DO $$
DECLARE v_bod UUID; v_desv INT; v_valor NUMERIC; v_un NUMERIC;
BEGIN
    SELECT id INTO v_bod FROM bodegas WHERE codigo = 'BOD-FRK-F01';
    SELECT count(*) INTO v_desv FROM (
        SELECT sb.producto_id
          FROM stock_bodega sb
          LEFT JOIN inventario_capas ic ON ic.bodega_id = sb.bodega_id AND ic.producto_id = sb.producto_id AND ic.estado = 'disponible'
         WHERE sb.bodega_id = v_bod
         GROUP BY sb.producto_id, sb.cantidad
        HAVING sb.cantidad <> coalesce(sum(ic.cantidad_disponible), 0)) x;
    IF v_desv > 0 THEN RAISE EXCEPTION 'MIG711: % productos de Franke con stock ≠ FIFO', v_desv; END IF;
    SELECT sum(cantidad_disponible), round(sum(cantidad_disponible * costo_unitario))
      INTO v_un, v_valor FROM inventario_capas WHERE bodega_id = v_bod AND estado = 'disponible';
    RAISE NOTICE 'MIG711 OK: Franke stock = FIFO (% un., valor FIFO $%)', v_un, v_valor;
END $$;
