-- ============================================================================
-- SICOM-ICEO | 563 — Conteo físico aprobable de punta a punta (ajustes + FIFO)
-- ============================================================================
-- Contexto (2026-09-15): se carga el inventario físico de la Bodega Central
-- Repuestos — Taller Coquimbo (INVT14-09-26.xlsx, 1.833 líneas) usando el flujo
-- oficial conteos_inventario → conteo_detalle → rpc_aprobar_conteo_inventario.
--
-- Al revisar ese flujo aparecen 3 defectos que impedían aprobar un conteo real:
--
--   1. rpc_registrar_ajuste_inventario exige OT para todo ajuste negativo, pero
--      rpc_aprobar_conteo_inventario no pasa OT → cualquier conteo con faltantes
--      reventaba en la primera línea negativa.
--      → Regla nueva: un ajuste negativo necesita OT **o** un autorizador
--        (p_autorizado_por). El conteo aprobado pasa al supervisor como autorizador.
--
--   2. El ajuste hacía UPDATE sobre stock_bodega: si el producto no tenía fila en
--      esa bodega, el movimiento y el kardex quedaban escritos pero el stock NO
--      cambiaba (fallo silencioso).
--      → Ahora hace INSERT ... ON CONFLICT (upsert).
--
--   3. El ajuste no tocaba las capas FIFO (inventario_capas). Como el despacho de
--      vales consume capas (fn_consumir_inventario_fifo, MIG216), tras un conteo
--      el bodeguero vería "sin stock" en productos que sí contó.
--      → Ajuste positivo crea una capa (folio AJUSTE-INVENTARIO, mismo criterio
--        de la semilla MIG222: costo conocido o $1). Ajuste negativo consume capas
--        FIFO hasta donde alcancen, enlazadas al movimiento.
--
-- Además rpc_aprobar_conteo_inventario cierra fecha_fin al aprobar.
-- IDEMPOTENTE: solo CREATE OR REPLACE FUNCTION (los GRANT existentes se conservan).
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_consumir_inventario_fifo') THEN
        RAISE EXCEPTION 'STOP — falta fn_consumir_inventario_fifo (MIG56).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_aprobar_conteo_inventario') THEN
        RAISE EXCEPTION 'STOP — falta rpc_aprobar_conteo_inventario (núcleo legacy).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stock_bodega_producto') THEN
        RAISE EXCEPTION 'STOP — falta uq_stock_bodega_producto (necesario para el upsert).';
    END IF;
END $$;


-- ── 1. Ajuste de inventario: autorizador, upsert de stock y capas FIFO ──────
CREATE OR REPLACE FUNCTION public.rpc_registrar_ajuste_inventario(
    p_bodega_id      UUID,
    p_producto_id    UUID,
    p_cantidad       NUMERIC,
    p_motivo         TEXT,
    p_usuario_id     UUID,
    p_ot_id          UUID DEFAULT NULL,
    p_autorizado_por UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_stock          RECORD;
    v_tipo           tipo_movimiento_enum;
    v_abs_cantidad   NUMERIC(12,3);
    v_nuevo_stock    NUMERIC(12,3);
    v_movimiento_id  UUID;
    v_costo_capa     NUMERIC;
    v_unidad         VARCHAR;
    v_disp_fifo      NUMERIC;
    v_fifo           JSONB := NULL;
    v_capa_id        UUID := NULL;
BEGIN
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) = 0 THEN
        RAISE EXCEPTION 'Todo ajuste de inventario requiere motivo documentado.';
    END IF;

    v_abs_cantidad := ABS(p_cantidad);

    IF p_cantidad > 0 THEN
        v_tipo := 'ajuste_positivo';
    ELSIF p_cantidad < 0 THEN
        v_tipo := 'ajuste_negativo';
        -- Un faltante necesita respaldo: OT o un autorizador (supervisor del conteo).
        IF p_ot_id IS NULL AND p_autorizado_por IS NULL THEN
            RAISE EXCEPTION 'Ajuste negativo requiere OT asociada o autorización de un supervisor.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Cantidad de ajuste no puede ser 0.';
    END IF;

    -- Lock (o fila virtual en cero si el producto nunca tuvo stock en esta bodega)
    SELECT cantidad, costo_promedio INTO v_stock
      FROM stock_bodega
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
       FOR UPDATE;

    IF NOT FOUND THEN
        v_stock.cantidad := 0;
        v_stock.costo_promedio := 0;
    END IF;

    v_nuevo_stock := v_stock.cantidad + p_cantidad;

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

    -- Upsert: antes era UPDATE y fallaba en silencio si no existía la fila.
    INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
    VALUES (p_bodega_id, p_producto_id, v_nuevo_stock, v_stock.costo_promedio, NOW())
    ON CONFLICT (bodega_id, producto_id) DO UPDATE
       SET cantidad = EXCLUDED.cantidad,
           ultimo_movimiento = NOW();

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

    -- ── Sincronía FIFO ──────────────────────────────────────────────────────
    IF v_tipo = 'ajuste_positivo' THEN
        -- Costo de la capa: promedio del stock, o costo maestro, o última capa, o $1
        -- (mismo criterio que la semilla MIG222; se corrige después con
        -- rpc_actualizar_costo_capa mientras la capa no tenga consumos).
        SELECT COALESCE(
                 NULLIF(v_stock.costo_promedio, 0),
                 NULLIF(p.costo_unitario_actual, 0),
                 (SELECT ic.costo_unitario FROM inventario_capas ic
                   WHERE ic.producto_id = p_producto_id AND ic.bodega_id = p_bodega_id
                     AND ic.costo_unitario > 0
                   ORDER BY ic.fecha_recepcion DESC, ic.created_at DESC LIMIT 1),
                 1),
               p.unidad_medida
          INTO v_costo_capa, v_unidad
          FROM productos p WHERE p.id = p_producto_id;

        INSERT INTO inventario_capas (
            producto_id, bodega_id, fecha_recepcion, folio_recepcion,
            cantidad_inicial, cantidad_disponible, unidad,
            costo_unitario, estado, created_by, created_at, updated_at
        ) VALUES (
            p_producto_id, p_bodega_id, CURRENT_DATE, 'AJUSTE-INVENTARIO',
            v_abs_cantidad, v_abs_cantidad, v_unidad,
            v_costo_capa, 'disponible', p_usuario_id, NOW(), NOW()
        ) RETURNING id INTO v_capa_id;
    ELSE
        -- Consume capas hasta donde alcancen. Si las capas ya estaban por debajo
        -- del stock legacy (inconsistencia previa) no se bloquea el ajuste.
        SELECT COALESCE(SUM(cantidad_disponible), 0) INTO v_disp_fifo
          FROM inventario_capas
         WHERE producto_id = p_producto_id AND bodega_id = p_bodega_id
           AND estado = 'disponible';
        IF v_disp_fifo > 0 THEN
            v_fifo := fn_consumir_inventario_fifo(
                p_producto_id   := p_producto_id,
                p_bodega_id     := p_bodega_id,
                p_cantidad      := LEAST(v_disp_fifo, v_abs_cantidad),
                p_movimiento_id := v_movimiento_id,
                p_ot_id         := p_ot_id,
                p_consumido_por := p_usuario_id
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'tipo', v_tipo,
        'impacto_valorizado', v_abs_cantidad * v_stock.costo_promedio,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'motivo', p_motivo,
        'autorizado_por', p_autorizado_por,
        'capa_creada_id', v_capa_id,
        'fifo', v_fifo
    );
END;
$$;


-- ── 2. Aprobar conteo: el supervisor autoriza los faltantes y cierra fecha ──
CREATE OR REPLACE FUNCTION public.rpc_aprobar_conteo_inventario(
    p_conteo_id    UUID,
    p_supervisor_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_conteo         RECORD;
    v_linea          RECORD;
    v_ajustes        INTEGER := 0;
    v_positivos      INTEGER := 0;
    v_negativos      INTEGER := 0;
    v_valor_total    NUMERIC(15,2) := 0;
    v_resultado      JSONB;
BEGIN
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

    FOR v_linea IN
        SELECT cd.*, p.nombre AS producto_nombre, p.codigo AS producto_codigo
          FROM conteo_detalle cd
          JOIN productos p ON p.id = cd.producto_id
         WHERE cd.conteo_id = p_conteo_id
           AND cd.diferencia != 0
           AND cd.ajuste_aplicado = false
         ORDER BY p.codigo
    LOOP
        SELECT rpc_registrar_ajuste_inventario(
            p_bodega_id      := v_conteo.bodega_id,
            p_producto_id    := v_linea.producto_id,
            p_cantidad       := v_linea.diferencia,
            p_motivo         := 'Ajuste por conteo físico #' || p_conteo_id::TEXT ||
                                ' del ' || COALESCE(v_conteo.fecha_inicio::DATE::TEXT, 's/f') ||
                                '. Sistema ' || v_linea.stock_sistema ||
                                ' → físico ' || v_linea.stock_fisico ||
                                ' (' || v_linea.producto_codigo || ' ' || v_linea.producto_nombre || ')',
            p_usuario_id     := p_supervisor_id,
            p_autorizado_por := p_supervisor_id
        ) INTO v_resultado;

        UPDATE conteo_detalle
           SET ajuste_aplicado = true,
               movimiento_ajuste_id = (v_resultado->>'movimiento_id')::UUID
         WHERE id = v_linea.id;

        v_ajustes := v_ajustes + 1;
        IF v_linea.diferencia > 0 THEN v_positivos := v_positivos + 1; ELSE v_negativos := v_negativos + 1; END IF;
        v_valor_total := v_valor_total + COALESCE(v_linea.diferencia_valorizada, 0);
    END LOOP;

    UPDATE conteos_inventario
       SET estado = 'aprobado',
           supervisor_aprobacion_id = p_supervisor_id,
           fecha_fin = COALESCE(fecha_fin, NOW())
     WHERE id = p_conteo_id;

    RETURN jsonb_build_object(
        'conteo_id', p_conteo_id,
        'ajustes_generados', v_ajustes,
        'ajustes_positivos', v_positivos,
        'ajustes_negativos', v_negativos,
        'valor_total_ajustes', v_valor_total,
        'aprobado_por', p_supervisor_id
    );
END;
$$;


-- ── 3. Validación ────────────────────────────────────────────────────────────
SELECT 'MIG563 OK' AS resultado,
       (SELECT count(*) FROM pg_proc WHERE proname IN ('rpc_registrar_ajuste_inventario','rpc_aprobar_conteo_inventario')) AS funciones;
