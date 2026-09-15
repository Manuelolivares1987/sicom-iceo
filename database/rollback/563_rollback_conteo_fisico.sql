-- Rollback MIG563: restaura las definiciones previas (capturadas de prod 2026-09-15)
CREATE OR REPLACE FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid DEFAULT NULL::uuid, p_autorizado_por uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_stock          RECORD;
    v_tipo           tipo_movimiento_enum;
    v_abs_cantidad   NUMERIC(12,3);
    v_nuevo_stock    NUMERIC(12,3);
    v_movimiento_id  UUID;
BEGIN
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) = 0 THEN
        RAISE EXCEPTION 'Todo ajuste de inventario requiere motivo documentado.';
    END IF;

    v_abs_cantidad := ABS(p_cantidad);

    IF p_cantidad > 0 THEN
        v_tipo := 'ajuste_positivo';
    ELSIF p_cantidad < 0 THEN
        v_tipo := 'ajuste_negativo';
        -- Ajustes negativos requieren OT para trazabilidad
        IF p_ot_id IS NULL THEN
            RAISE EXCEPTION 'Ajuste negativo requiere OT asociada para trazabilidad.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Cantidad de ajuste no puede ser 0.';
    END IF;

    -- Lock
    SELECT cantidad, costo_promedio INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        v_stock.cantidad := 0;
        v_stock.costo_promedio := 0;
    END IF;

    v_nuevo_stock := v_stock.cantidad + p_cantidad; -- p_cantidad ya tiene signo

    IF v_nuevo_stock < 0 THEN
        RAISE EXCEPTION 'Ajuste resultaria en stock negativo. Stock actual: %, ajuste: %',
            v_stock.cantidad, p_cantidad;
    END IF;

    v_movimiento_id := gen_random_uuid();

    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        ot_id, motivo, usuario_id
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, v_tipo, v_abs_cantidad,
        v_stock.costo_promedio, p_ot_id, p_motivo, p_usuario_id
    );

    UPDATE stock_bodega
    SET cantidad = v_nuevo_stock, ultimo_movimiento = NOW()
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;

    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_id, p_producto_id, v_movimiento_id, NOW(), v_tipo,
        v_abs_cantidad, v_stock.cantidad, v_nuevo_stock,
        v_stock.costo_promedio, v_stock.costo_promedio, v_stock.costo_promedio,
        v_abs_cantidad * v_stock.costo_promedio, v_nuevo_stock * v_stock.costo_promedio
    );

    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'tipo', v_tipo,
        'impacto_valorizado', v_abs_cantidad * v_stock.costo_promedio,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'motivo', p_motivo
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_conteo         RECORD;
    v_linea          RECORD;
    v_ajustes        INTEGER := 0;
    v_valor_total    NUMERIC(15,2) := 0;
    v_resultado      JSONB;
BEGIN
    -- Obtener conteo
    SELECT * INTO v_conteo
    FROM conteos_inventario
    WHERE id = p_conteo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conteo no encontrado.';
    END IF;

    IF v_conteo.estado != 'completado' THEN
        RAISE EXCEPTION 'Solo se puede aprobar un conteo en estado "completado". Estado actual: %.', v_conteo.estado;
    END IF;

    -- Iterar cada línea con diferencia
    FOR v_linea IN
        SELECT cd.*, p.nombre AS producto_nombre
        FROM conteo_detalle cd
        JOIN productos p ON p.id = cd.producto_id
        WHERE cd.conteo_id = p_conteo_id
          AND cd.diferencia != 0
          AND cd.ajuste_aplicado = false
    LOOP
        -- Generar ajuste atómico
        SELECT rpc_registrar_ajuste_inventario(
            p_bodega_id      := v_conteo.bodega_id,
            p_producto_id    := v_linea.producto_id,
            p_cantidad       := v_linea.diferencia, -- positivo o negativo
            p_motivo         := 'Ajuste por conteo físico #' || p_conteo_id::TEXT ||
                               '. Diferencia: ' || v_linea.diferencia ||
                               ' (' || v_linea.producto_nombre || ')',
            p_usuario_id     := p_supervisor_id
        ) INTO v_resultado;

        -- Marcar línea como ajustada
        UPDATE conteo_detalle
        SET ajuste_aplicado = true,
            movimiento_ajuste_id = (v_resultado->>'movimiento_id')::UUID
        WHERE id = v_linea.id;

        v_ajustes := v_ajustes + 1;
        v_valor_total := v_valor_total + COALESCE(v_linea.diferencia_valorizada, 0);
    END LOOP;

    -- Aprobar conteo
    UPDATE conteos_inventario
    SET estado = 'aprobado',
        supervisor_aprobacion_id = p_supervisor_id
    WHERE id = p_conteo_id;

    RETURN jsonb_build_object(
        'conteo_id', p_conteo_id,
        'ajustes_generados', v_ajustes,
        'valor_total_ajustes', v_valor_total,
        'aprobado_por', p_supervisor_id
    );
END;
$function$
;
