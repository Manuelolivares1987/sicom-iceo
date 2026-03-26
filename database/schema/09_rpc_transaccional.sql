-- SICOM-ICEO | Fase Mejora | RPCs Transaccionales + Correcciones Criticas
-- ============================================================================
-- Ejecutar DESPUES de los archivos 01-08
-- Este archivo:
-- 1. Corrige bugs criticos del schema
-- 2. Crea 7 RPCs transaccionales atomicas
-- 3. Elimina triggers redundantes (ahora manejados por RPCs)
-- ============================================================================


-- ============================================================================
-- PART 1: SCHEMA FIXES (critical bugs from audit)
-- ============================================================================

-- 1. Add missing column menor_es_mejor to kpi_definiciones
ALTER TABLE kpi_definiciones ADD COLUMN IF NOT EXISTS menor_es_mejor BOOLEAN NOT NULL DEFAULT false;
-- Update existing KPIs that are "less is better": A1, A2, A8, B2, B5, C4
UPDATE kpi_definiciones SET menor_es_mejor = true WHERE codigo IN ('A1','A2','A8','B2','B5','C4','C5');

-- 2. Fix generar_folio_ot() - replace RIGHT() with proper PostgreSQL syntax
CREATE OR REPLACE FUNCTION generar_folio_ot()
RETURNS TRIGGER AS $$
DECLARE
    v_periodo TEXT;
    v_secuencia INTEGER;
BEGIN
    IF NEW.folio IS NULL OR NEW.folio = '' THEN
        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(
            CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
        ), 0) + 1
        INTO v_secuencia
        FROM ordenes_trabajo
        WHERE folio LIKE 'OT-' || v_periodo || '-%';

        NEW.folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Add policy for users to read their own profile (needed for RLS to work)
DO $$ BEGIN
    CREATE POLICY pol_authenticated_read_own_perfil ON usuarios_perfil
        FOR SELECT TO authenticated
        USING (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================================
-- PART 2: THE 7 TRANSACTIONAL RPC FUNCTIONS
-- ============================================================================

-- ═══════════════════════════════════════════
-- RPC 1: rpc_crear_ot
-- Crea OT con folio atomico, checklist de pauta, y auditoria
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_crear_ot(
    p_tipo           tipo_ot_enum,
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_activo_id      UUID,
    p_prioridad      prioridad_enum DEFAULT 'normal',
    p_fecha_programada DATE DEFAULT NULL,
    p_responsable_id UUID DEFAULT NULL,
    p_plan_mantenimiento_id UUID DEFAULT NULL,
    p_usuario_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_folio       VARCHAR(20);
    v_periodo     TEXT;
    v_secuencia   INTEGER;
    v_ot_id       UUID;
    v_qr_code     VARCHAR(100);
    v_estado      estado_ot_enum;
    v_pauta_items JSONB;
BEGIN
    -- 1. Generar folio atomico
    v_periodo := TO_CHAR(NOW(), 'YYYYMM');

    SELECT COALESCE(MAX(
        CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
    ), 0) + 1
    INTO v_secuencia
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%'
    FOR UPDATE; -- Lock para evitar folios duplicados

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    v_estado := CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'creada' END;

    -- 2. Insertar OT
    INSERT INTO ordenes_trabajo (
        id, folio, tipo, contrato_id, faena_id, activo_id,
        plan_mantenimiento_id, prioridad, estado,
        responsable_id, fecha_programada, qr_code,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_id, v_folio, p_tipo, p_contrato_id, p_faena_id, p_activo_id,
        p_plan_mantenimiento_id, p_prioridad, v_estado,
        p_responsable_id, p_fecha_programada, v_qr_code,
        (p_plan_mantenimiento_id IS NOT NULL), p_usuario_id
    );

    -- 3. Si viene de plan PM, copiar checklist de la pauta del fabricante
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist
        INTO v_pauta_items
        FROM planes_mantenimiento pm
        JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
        WHERE pm.id = p_plan_mantenimiento_id;

        IF v_pauta_items IS NOT NULL THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT
                gen_random_uuid(),
                v_ot_id,
                (item->>'orden')::INTEGER,
                item->>'descripcion',
                COALESCE((item->>'obligatorio')::BOOLEAN, true),
                COALESCE((item->>'requiere_foto')::BOOLEAN, false)
            FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    END IF;

    -- 4. Registrar en historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, p_usuario_id);

    -- 5. Retornar resultado
    RETURN jsonb_build_object(
        'id', v_ot_id,
        'folio', v_folio,
        'estado', v_estado,
        'qr_code', v_qr_code
    );
END;
$$;


-- ═══════════════════════════════════════════
-- RPC 2: rpc_transicion_ot
-- Cambia estado de OT validando transicion, reglas de cierre, historial
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_transicion_ot(
    p_ot_id          UUID,
    p_nuevo_estado   estado_ot_enum,
    p_usuario_id     UUID,
    p_causa_no_ejecucion causa_no_ejecucion_enum DEFAULT NULL,
    p_detalle_no_ejecucion TEXT DEFAULT NULL,
    p_observaciones  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ot             RECORD;
    v_count_evidence INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas estado_ot_enum[];
BEGIN
    -- 1. Obtener OT con lock exclusivo
    SELECT * INTO v_ot
    FROM ordenes_trabajo
    WHERE id = p_ot_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
    END IF;

    -- 2. Validar transicion permitida
    v_transiciones_validas := CASE v_ot.estado
        WHEN 'creada'     THEN ARRAY['asignada','cancelada']::estado_ot_enum[]
        WHEN 'asignada'   THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'en_ejecucion' THEN ARRAY['pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada']::estado_ot_enum[]
        WHEN 'pausada'    THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        ELSE ARRAY[]::estado_ot_enum[] -- estados finales: no se puede transicionar
    END;

    IF NOT (p_nuevo_estado = ANY(v_transiciones_validas)) THEN
        RAISE EXCEPTION 'Transicion invalida: % -> %. Permitidas: %',
            v_ot.estado, p_nuevo_estado, v_transiciones_validas;
    END IF;

    -- 3. Validaciones por tipo de transicion

    -- 3a. No ejecutada: requiere causa
    IF p_nuevo_estado = 'no_ejecutada' THEN
        IF p_causa_no_ejecucion IS NULL THEN
            RAISE EXCEPTION 'Causa de no ejecucion es obligatoria.';
        END IF;
    END IF;

    -- 3b. Ejecutada OK: requiere evidencia + checklist completo
    IF p_nuevo_estado IN ('ejecutada_ok', 'ejecutada_con_observaciones') THEN
        -- Contar evidencias
        SELECT COUNT(*) INTO v_count_evidence
        FROM evidencias_ot WHERE ot_id = p_ot_id;

        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar OT sin evidencia. Tarea sin evidencia = tarea no ejecutada.';
        END IF;

        -- Contar checklist obligatorios sin completar
        SELECT COUNT(*) INTO v_count_checklist_pending
        FROM checklist_ot
        WHERE ot_id = p_ot_id
          AND obligatorio = true
          AND resultado IS NULL;

        IF v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % items de checklist obligatorios sin completar.', v_count_checklist_pending;
        END IF;
    END IF;

    -- 4. Ejecutar la transicion
    UPDATE ordenes_trabajo
    SET
        estado = p_nuevo_estado,
        -- Timestamps automaticos segun transicion
        fecha_inicio = CASE
            WHEN p_nuevo_estado = 'en_ejecucion' AND fecha_inicio IS NULL THEN NOW()
            ELSE fecha_inicio
        END,
        fecha_termino = CASE
            WHEN p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada') THEN NOW()
            ELSE fecha_termino
        END,
        -- Causa de no ejecucion
        causa_no_ejecucion = COALESCE(p_causa_no_ejecucion, causa_no_ejecucion),
        detalle_no_ejecucion = COALESCE(p_detalle_no_ejecucion, detalle_no_ejecucion),
        -- Observaciones
        observaciones = COALESCE(p_observaciones, observaciones),
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- 5. Registrar en historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (
        gen_random_uuid(), p_ot_id, v_ot.estado, p_nuevo_estado,
        COALESCE(p_observaciones, p_detalle_no_ejecucion), p_usuario_id
    );

    -- 6. Retornar
    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'estado_anterior', v_ot.estado,
        'estado_nuevo', p_nuevo_estado,
        'folio', v_ot.folio
    );
END;
$$;


-- ═══════════════════════════════════════════
-- RPC 3: rpc_cerrar_ot_supervisor
-- Cierre supervisado: congela costos, calcula totales, marca cerrada
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_cerrar_ot_supervisor(
    p_ot_id              UUID,
    p_supervisor_id      UUID,
    p_observaciones      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ot              RECORD;
    v_costo_materiales NUMERIC(12,2);
BEGIN
    -- 1. Lock OT
    SELECT * INTO v_ot
    FROM ordenes_trabajo
    WHERE id = p_ot_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada.';
    END IF;

    IF v_ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones') THEN
        RAISE EXCEPTION 'Solo se puede cerrar una OT ejecutada. Estado actual: %', v_ot.estado;
    END IF;

    -- 2. Calcular costo total de materiales consumidos
    SELECT COALESCE(SUM(costo_unitario * cantidad), 0)
    INTO v_costo_materiales
    FROM movimientos_inventario
    WHERE ot_id = p_ot_id
      AND tipo IN ('salida', 'merma');

    -- 3. Cerrar OT
    UPDATE ordenes_trabajo
    SET
        fecha_cierre_supervisor = NOW(),
        supervisor_cierre_id = p_supervisor_id,
        observaciones_supervisor = p_observaciones,
        costo_materiales = v_costo_materiales,
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- 4. Si es preventiva, actualizar ultima ejecucion del plan
    IF v_ot.plan_mantenimiento_id IS NOT NULL THEN
        UPDATE planes_mantenimiento
        SET
            ultima_ejecucion_fecha = NOW(),
            ultima_ejecucion_km = (SELECT kilometraje_actual FROM activos WHERE id = v_ot.activo_id),
            ultima_ejecucion_horas = (SELECT horas_uso_actual FROM activos WHERE id = v_ot.activo_id),
            proxima_ejecucion_fecha = CASE
                WHEN frecuencia_dias IS NOT NULL THEN CURRENT_DATE + frecuencia_dias
                ELSE proxima_ejecucion_fecha
            END,
            updated_at = NOW()
        WHERE id = v_ot.plan_mantenimiento_id;
    END IF;

    -- 5. Historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, v_ot.estado, 'Cierre supervisor', p_supervisor_id);

    -- 6. Retornar
    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'folio', v_ot.folio,
        'costo_materiales', v_costo_materiales,
        'costo_mano_obra', v_ot.costo_mano_obra,
        'costo_total', v_costo_materiales + COALESCE(v_ot.costo_mano_obra, 0)
    );
END;
$$;


-- ═══════════════════════════════════════════
-- RPC 4: rpc_registrar_salida_inventario
-- LA FUNCION MAS CRITICA: lock stock + movimiento + kardex + costo OT atomico
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_registrar_salida_inventario(
    p_bodega_id      UUID,
    p_producto_id    UUID,
    p_cantidad       NUMERIC(12,3),
    p_ot_id          UUID,
    p_usuario_id     UUID,
    p_activo_id      UUID DEFAULT NULL,
    p_lote           VARCHAR(100) DEFAULT NULL,
    p_motivo         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_stock          RECORD;
    v_ot             RECORD;
    v_movimiento_id  UUID;
    v_costo_unitario NUMERIC(15,4);
    v_nuevo_stock    NUMERIC(12,3);
    v_producto       RECORD;
BEGIN
    -- ══════════════════════════════════════════
    -- VALIDACIONES (antes de tocar datos)
    -- ══════════════════════════════════════════

    -- 1. OT obligatoria
    IF p_ot_id IS NULL THEN
        RAISE EXCEPTION 'REGLA: No se permite salida de inventario sin OT asociada.';
    END IF;

    -- 2. Validar que la OT existe y esta en estado valido
    SELECT id, estado, folio INTO v_ot
    FROM ordenes_trabajo
    WHERE id = p_ot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
    END IF;

    IF v_ot.estado NOT IN ('asignada', 'en_ejecucion') THEN
        RAISE EXCEPTION 'No se puede retirar material de OT en estado "%". Solo "asignada" o "en_ejecucion".', v_ot.estado;
    END IF;

    -- 3. Validar cantidad positiva
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
    END IF;

    -- 4. Obtener producto
    SELECT id, nombre, stock_minimo INTO v_producto
    FROM productos
    WHERE id = p_producto_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto no encontrado: %', p_producto_id;
    END IF;

    -- ══════════════════════════════════════════
    -- LOCK + OPERACION ATOMICA
    -- ══════════════════════════════════════════

    -- 5. Lock exclusivo del stock (previene race condition)
    SELECT cantidad, costo_promedio
    INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id
      AND producto_id = p_producto_id
    FOR UPDATE; -- LOCK EXCLUSIVO

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe stock del producto "%" en la bodega indicada.', v_producto.nombre;
    END IF;

    IF v_stock.cantidad < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente de "%". Disponible: %, solicitado: %.',
            v_producto.nombre, v_stock.cantidad, p_cantidad;
    END IF;

    -- 6. El costo unitario es el CPP vigente al momento de la salida
    v_costo_unitario := v_stock.costo_promedio;
    v_nuevo_stock := v_stock.cantidad - p_cantidad;
    v_movimiento_id := gen_random_uuid();

    -- 7. Registrar movimiento (sin triggers, todo en esta funcion)
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad,
        costo_unitario, ot_id, activo_id, lote, motivo,
        usuario_id, created_at
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, 'salida', p_cantidad,
        v_costo_unitario, p_ot_id, COALESCE(p_activo_id, (SELECT activo_id FROM ordenes_trabajo WHERE id = p_ot_id)),
        p_lote, p_motivo,
        p_usuario_id, NOW()
    );

    -- 8. Actualizar stock (ya tenemos el lock)
    UPDATE stock_bodega
    SET
        cantidad = v_nuevo_stock,
        -- CPP no cambia en salidas
        ultimo_movimiento = NOW(),
        updated_at = NOW()
    WHERE bodega_id = p_bodega_id
      AND producto_id = p_producto_id;

    -- 9. Registrar kardex
    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_id, p_producto_id, v_movimiento_id, NOW(), 'salida',
        p_cantidad, v_stock.cantidad, v_nuevo_stock,
        v_costo_unitario, v_stock.costo_promedio, v_stock.costo_promedio,
        p_cantidad * v_costo_unitario, v_nuevo_stock * v_stock.costo_promedio
    );

    -- 10. Actualizar costo de materiales en la OT
    UPDATE ordenes_trabajo
    SET costo_materiales = COALESCE(costo_materiales, 0) + (p_cantidad * v_costo_unitario),
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- 11. Alerta si stock bajo minimo
    IF v_nuevo_stock < v_producto.stock_minimo THEN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES (
            'stock_minimo',
            'Stock bajo minimo: ' || v_producto.nombre,
            'Stock actual: ' || v_nuevo_stock || '. Minimo: ' || v_producto.stock_minimo,
            'warning', 'producto', p_producto_id
        );
    END IF;

    -- 12. Retornar resultado completo
    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'producto', v_producto.nombre,
        'cantidad', p_cantidad,
        'costo_unitario', v_costo_unitario,
        'costo_total', p_cantidad * v_costo_unitario,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'ot_folio', v_ot.folio
    );
END;
$$;


-- ═══════════════════════════════════════════
-- RPC 5: rpc_registrar_entrada_inventario
-- Entrada con calculo de CPP atomico + kardex
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_registrar_entrada_inventario(
    p_bodega_id          UUID,
    p_producto_id        UUID,
    p_cantidad           NUMERIC(12,3),
    p_costo_unitario     NUMERIC(15,4),
    p_documento_referencia VARCHAR(100),
    p_usuario_id         UUID,
    p_lote               VARCHAR(100) DEFAULT NULL,
    p_fecha_vencimiento  DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_stock          RECORD;
    v_movimiento_id  UUID;
    v_nuevo_stock    NUMERIC(12,3);
    v_nuevo_cpp      NUMERIC(15,4);
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad debe ser > 0';
    END IF;
    IF p_costo_unitario <= 0 THEN
        RAISE EXCEPTION 'Costo unitario debe ser > 0';
    END IF;

    -- Lock stock
    SELECT cantidad, costo_promedio
    INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        v_stock.cantidad := 0;
        v_stock.costo_promedio := 0;
    END IF;

    -- Calcular nuevo CPP
    v_nuevo_stock := v_stock.cantidad + p_cantidad;
    IF v_nuevo_stock > 0 THEN
        v_nuevo_cpp := (
            (v_stock.cantidad * v_stock.costo_promedio) +
            (p_cantidad * p_costo_unitario)
        ) / v_nuevo_stock;
    ELSE
        v_nuevo_cpp := p_costo_unitario;
    END IF;

    v_movimiento_id := gen_random_uuid();

    -- Movimiento
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        documento_referencia, lote, fecha_vencimiento, usuario_id
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, 'entrada', p_cantidad,
        p_costo_unitario, p_documento_referencia, p_lote, p_fecha_vencimiento, p_usuario_id
    );

    -- UPSERT stock
    INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
    VALUES (p_bodega_id, p_producto_id, v_nuevo_stock, v_nuevo_cpp, NOW())
    ON CONFLICT (bodega_id, producto_id)
    DO UPDATE SET
        cantidad = v_nuevo_stock,
        costo_promedio = v_nuevo_cpp,
        ultimo_movimiento = NOW();

    -- Kardex
    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_id, p_producto_id, v_movimiento_id, NOW(), 'entrada',
        p_cantidad, v_stock.cantidad, v_nuevo_stock,
        p_costo_unitario, v_stock.costo_promedio, v_nuevo_cpp,
        p_cantidad * p_costo_unitario, v_nuevo_stock * v_nuevo_cpp
    );

    -- Actualizar costo unitario actual del producto
    UPDATE productos
    SET costo_unitario_actual = v_nuevo_cpp, updated_at = NOW()
    WHERE id = p_producto_id;

    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'cpp_anterior', v_stock.costo_promedio,
        'cpp_posterior', v_nuevo_cpp,
        'valor_movimiento', p_cantidad * p_costo_unitario
    );
END;
$$;


-- ═══════════════════════════════════════════
-- RPC 6: rpc_registrar_ajuste_inventario
-- Ajuste +/- con validacion de motivo y lock
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_registrar_ajuste_inventario(
    p_bodega_id      UUID,
    p_producto_id    UUID,
    p_cantidad       NUMERIC(12,3), -- positivo para ajuste+, negativo para ajuste-
    p_motivo         TEXT,
    p_usuario_id     UUID,
    p_ot_id          UUID DEFAULT NULL, -- requerido para ajustes negativos
    p_autorizado_por UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
$$;


-- ═══════════════════════════════════════════
-- RPC 7: rpc_calcular_iceo_periodo
-- Calcula TODOS los KPIs, pondera por area, aplica bloqueantes, genera ICEO
-- ═══════════════════════════════════════════

CREATE OR REPLACE FUNCTION rpc_calcular_iceo_periodo(
    p_contrato_id    UUID,
    p_faena_id       UUID DEFAULT NULL,
    p_periodo_inicio DATE DEFAULT NULL,
    p_periodo_fin    DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inicio         DATE;
    v_fin            DATE;
    v_kpi            RECORD;
    v_valor          NUMERIC;
    v_pct            NUMERIC;
    v_puntaje        NUMERIC;
    v_ponderado      NUMERIC;
    v_sum_a          NUMERIC := 0;
    v_sum_b          NUMERIC := 0;
    v_sum_c          NUMERIC := 0;
    v_peso_a         NUMERIC;
    v_peso_b         NUMERIC;
    v_peso_c         NUMERIC;
    v_iceo_bruto     NUMERIC;
    v_iceo_final     NUMERIC;
    v_incentivo      BOOLEAN := true;
    v_clasificacion  clasificacion_iceo_enum;
    v_bloqueantes    JSONB := '[]'::JSONB;
    v_iceo_id        UUID;
    v_medicion_id    UUID;
    v_umbral_def     NUMERIC;
    v_umbral_ace     NUMERIC;
    v_umbral_bue     NUMERIC;
BEGIN
    -- Periodo por defecto: mes actual
    v_inicio := COALESCE(p_periodo_inicio, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_fin := COALESCE(p_periodo_fin, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE);

    -- Obtener configuracion ICEO
    SELECT
        COALESCE(peso_area_a, 0.35),
        COALESCE(peso_area_b, 0.35),
        COALESCE(peso_area_c, 0.30),
        COALESCE(umbral_deficiente, 70),
        COALESCE(umbral_aceptable, 85),
        COALESCE(umbral_bueno, 95)
    INTO v_peso_a, v_peso_b, v_peso_c, v_umbral_def, v_umbral_ace, v_umbral_bue
    FROM configuracion_iceo
    WHERE contrato_id = p_contrato_id;

    IF NOT FOUND THEN
        v_peso_a := 0.35; v_peso_b := 0.35; v_peso_c := 0.30;
        v_umbral_def := 70; v_umbral_ace := 85; v_umbral_bue := 95;
    END IF;

    -- Crear registro ICEO (se actualizara al final)
    v_iceo_id := gen_random_uuid();

    -- Limpiar mediciones y detalle previos del mismo periodo
    DELETE FROM iceo_detalle WHERE iceo_periodo_id IN (
        SELECT id FROM iceo_periodos
        WHERE contrato_id = p_contrato_id
          AND COALESCE(faena_id, '00000000-0000-0000-0000-000000000000') =
              COALESCE(p_faena_id, '00000000-0000-0000-0000-000000000000')
          AND periodo_inicio = v_inicio
    );
    DELETE FROM iceo_periodos
    WHERE contrato_id = p_contrato_id
      AND COALESCE(faena_id, '00000000-0000-0000-0000-000000000000') =
          COALESCE(p_faena_id, '00000000-0000-0000-0000-000000000000')
      AND periodo_inicio = v_inicio;

    -- Iterar cada KPI activo
    FOR v_kpi IN
        SELECT * FROM kpi_definiciones WHERE activo = true ORDER BY area, codigo
    LOOP
        -- Llamar funcion de calculo dinamicamente
        BEGIN
            EXECUTE format('SELECT %I($1, $2, $3, $4)', v_kpi.funcion_calculo)
            INTO v_valor
            USING p_contrato_id, p_faena_id, v_inicio, v_fin;
        EXCEPTION WHEN OTHERS THEN
            v_valor := NULL; -- Funcion no existe o fallo
        END;

        IF v_valor IS NULL THEN
            v_valor := 0;
        END IF;

        -- Calcular % cumplimiento respecto a meta
        IF v_kpi.meta_direccion = 'mayor_igual' THEN
            v_pct := CASE WHEN v_kpi.meta_valor > 0
                THEN (v_valor / v_kpi.meta_valor) * 100
                ELSE 100 END;
        ELSE -- menor_igual (menos es mejor: MTTR, merma, etc.)
            v_pct := CASE WHEN v_valor > 0
                THEN (v_kpi.meta_valor / v_valor) * 100
                ELSE 100 END;
        END IF;

        -- Limitar a 100% maximo
        v_pct := LEAST(v_pct, 100);

        -- Buscar puntaje en tramos
        SELECT COALESCE(kt.puntaje, 0) INTO v_puntaje
        FROM kpi_tramos kt
        WHERE kt.kpi_id = v_kpi.id
          AND v_pct >= kt.rango_min
          AND v_pct < kt.rango_max
        ORDER BY kt.rango_min DESC
        LIMIT 1;

        IF v_puntaje IS NULL THEN
            v_puntaje := 0;
        END IF;

        -- Ponderar: puntaje * peso del KPI dentro de su area
        v_ponderado := v_puntaje * v_kpi.peso;

        -- Acumular por area
        CASE v_kpi.area
            WHEN 'administracion_combustibles' THEN v_sum_a := v_sum_a + v_ponderado;
            WHEN 'mantenimiento_fijos'         THEN v_sum_b := v_sum_b + v_ponderado;
            WHEN 'mantenimiento_moviles'       THEN v_sum_c := v_sum_c + v_ponderado;
        END CASE;

        -- Evaluar bloqueante
        IF v_kpi.es_bloqueante AND v_kpi.umbral_bloqueante IS NOT NULL THEN
            IF (v_kpi.meta_direccion = 'mayor_igual' AND v_valor < v_kpi.umbral_bloqueante) OR
               (v_kpi.meta_direccion = 'menor_igual' AND v_valor > v_kpi.umbral_bloqueante) THEN
                v_bloqueantes := v_bloqueantes || jsonb_build_object(
                    'kpi_codigo', v_kpi.codigo,
                    'kpi_nombre', v_kpi.nombre,
                    'valor', v_valor,
                    'umbral', v_kpi.umbral_bloqueante,
                    'efecto', v_kpi.efecto_bloqueante
                );
            END IF;
        END IF;

        -- Guardar medicion
        v_medicion_id := gen_random_uuid();
        INSERT INTO mediciones_kpi (
            id, kpi_id, contrato_id, faena_id, periodo_inicio, periodo_fin,
            valor_medido, porcentaje_cumplimiento, puntaje, valor_ponderado,
            bloqueante_activado, datos_calculo
        ) VALUES (
            v_medicion_id, v_kpi.id, p_contrato_id, p_faena_id, v_inicio, v_fin,
            v_valor, v_pct, v_puntaje, v_ponderado,
            (v_kpi.es_bloqueante AND v_kpi.umbral_bloqueante IS NOT NULL AND
             ((v_kpi.meta_direccion = 'mayor_igual' AND v_valor < v_kpi.umbral_bloqueante) OR
              (v_kpi.meta_direccion = 'menor_igual' AND v_valor > v_kpi.umbral_bloqueante))),
            jsonb_build_object('valor_raw', v_valor, 'meta', v_kpi.meta_valor, 'pct', v_pct)
        )
        ON CONFLICT (kpi_id, contrato_id, faena_id, periodo_inicio)
        DO UPDATE SET
            valor_medido = EXCLUDED.valor_medido,
            porcentaje_cumplimiento = EXCLUDED.porcentaje_cumplimiento,
            puntaje = EXCLUDED.puntaje,
            valor_ponderado = EXCLUDED.valor_ponderado,
            bloqueante_activado = EXCLUDED.bloqueante_activado,
            datos_calculo = EXCLUDED.datos_calculo,
            calculado_en = NOW();

        -- Guardar detalle ICEO
        INSERT INTO iceo_detalle (
            id, iceo_periodo_id, medicion_kpi_id, kpi_codigo,
            valor_medido, puntaje, peso, valor_ponderado,
            es_bloqueante, bloqueante_activado
        ) VALUES (
            gen_random_uuid(), v_iceo_id, v_medicion_id, v_kpi.codigo,
            v_valor, v_puntaje, v_kpi.peso, v_ponderado,
            v_kpi.es_bloqueante,
            (v_kpi.es_bloqueante AND v_kpi.umbral_bloqueante IS NOT NULL AND
             ((v_kpi.meta_direccion = 'mayor_igual' AND v_valor < v_kpi.umbral_bloqueante) OR
              (v_kpi.meta_direccion = 'menor_igual' AND v_valor > v_kpi.umbral_bloqueante)))
        );
    END LOOP;

    -- Calcular ICEO bruto
    v_iceo_bruto := (v_sum_a * v_peso_a) + (v_sum_b * v_peso_b) + (v_sum_c * v_peso_c);
    v_iceo_final := v_iceo_bruto;

    -- Aplicar bloqueantes (el mas severo gana)
    IF jsonb_array_length(v_bloqueantes) > 0 THEN
        DECLARE
            v_bloq RECORD;
        BEGIN
            FOR v_bloq IN SELECT * FROM jsonb_array_elements(v_bloqueantes) AS b LOOP
                CASE v_bloq.b->>'efecto'
                    WHEN 'anular' THEN
                        v_iceo_final := 0;
                        v_incentivo := false;
                    WHEN 'penalizar' THEN
                        v_iceo_final := LEAST(v_iceo_final, v_iceo_bruto * 0.5);
                        v_incentivo := false;
                    WHEN 'descontar' THEN
                        v_iceo_final := LEAST(v_iceo_final, v_iceo_bruto - 30);
                        v_incentivo := false;
                    WHEN 'bloquear_incentivo' THEN
                        v_incentivo := false;
                    ELSE NULL;
                END CASE;
            END LOOP;
        END;
    END IF;

    v_iceo_final := GREATEST(v_iceo_final, 0);

    -- Clasificacion
    v_clasificacion := CASE
        WHEN v_iceo_final >= v_umbral_bue THEN 'excelencia'
        WHEN v_iceo_final >= v_umbral_ace THEN 'bueno'
        WHEN v_iceo_final >= v_umbral_def THEN 'aceptable'
        ELSE 'deficiente'
    END;

    -- Insertar ICEO del periodo
    INSERT INTO iceo_periodos (
        id, contrato_id, faena_id, periodo_inicio, periodo_fin,
        puntaje_area_a, puntaje_area_b, puntaje_area_c,
        peso_area_a, peso_area_b, peso_area_c,
        iceo_bruto, iceo_final, clasificacion,
        bloqueantes_activados, incentivo_habilitado, calculado_en
    ) VALUES (
        v_iceo_id, p_contrato_id, p_faena_id, v_inicio, v_fin,
        v_sum_a, v_sum_b, v_sum_c,
        v_peso_a, v_peso_b, v_peso_c,
        v_iceo_bruto, v_iceo_final, v_clasificacion,
        v_bloqueantes, v_incentivo, NOW()
    );

    RETURN jsonb_build_object(
        'iceo_id', v_iceo_id,
        'periodo', v_inicio || ' a ' || v_fin,
        'area_a', v_sum_a,
        'area_b', v_sum_b,
        'area_c', v_sum_c,
        'iceo_bruto', v_iceo_bruto,
        'iceo_final', v_iceo_final,
        'clasificacion', v_clasificacion,
        'incentivo_habilitado', v_incentivo,
        'bloqueantes_count', jsonb_array_length(v_bloqueantes),
        'kpis_calculados', (SELECT COUNT(*) FROM kpi_definiciones WHERE activo = true)
    );
END;
$$;


-- ============================================================================
-- PART 3: DISABLE REDUNDANT TRIGGERS
-- These triggers are now handled atomically inside RPCs
-- ============================================================================

DROP TRIGGER IF EXISTS trg_mov_inv_validar_salida ON movimientos_inventario;
DROP TRIGGER IF EXISTS trg_mov_inv_actualizar_stock ON movimientos_inventario;
DROP TRIGGER IF EXISTS trg_mov_inv_registrar_kardex ON movimientos_inventario;
DROP TRIGGER IF EXISTS trg_mov_inv_actualizar_costo_ot ON movimientos_inventario;

-- Also drop OT folio/QR triggers (now handled by rpc_crear_ot)
DROP TRIGGER IF EXISTS trg_ot_generar_folio ON ordenes_trabajo;
DROP TRIGGER IF EXISTS trg_ot_qr_auto ON ordenes_trabajo;

-- Keep audit triggers active (trg_audit_*)
-- Keep OT estado historial trigger as backup (trg_ot_estado_historial)


-- ============================================================================
-- PART 4: FIX AUDIT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_old JSONB := NULL;
    v_new JSONB := NULL;
    v_user_id UUID;
BEGIN
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    IF TG_OP = 'INSERT' THEN
        v_new := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD);
    ELSIF TG_OP = 'UPDATE' THEN
        v_old := to_jsonb(OLD);
        v_new := to_jsonb(NEW);
    END IF;

    BEGIN
        INSERT INTO auditoria_eventos (tabla, accion, registro_id, datos_anteriores, datos_nuevos, usuario_id, created_at)
        VALUES (
            TG_TABLE_NAME, TG_OP,
            CASE WHEN TG_OP = 'DELETE' THEN (v_old->>'id')::UUID ELSE (v_new->>'id')::UUID END,
            v_old, v_new, v_user_id, NOW()
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FIN del archivo 09_rpc_transaccional.sql
-- ============================================================================
