-- SICOM-ICEO | Correcciones Críticas de Robustez
-- ============================================================================
-- Ejecutar DESPUÉS de 17.
--
-- CORRECCIONES:
-- 1. Bloquear transición directa a 'cerrada' en rpc_transicion_ot
-- 2. Exigir responsable_id para pasar a en_ejecucion
-- 3. Trigger de inmutabilidad en ordenes_trabajo (estado cerrada)
-- 4. Validar bodega.faena_id = ot.faena_id en salida inventario
-- 5. Corregir seed de funciones KPI en kpi_definiciones
-- 6. Campo horas_hombre + tarifa + cálculo costo_mano_obra
--
-- IMPACTO: Solo modifica RPCs y agrega 1 trigger + 2 columnas.
--          No cambia tablas existentes ni rompe frontend.
-- ============================================================================


-- ############################################################################
-- CORRECCIÓN 1 + 2: REESCRIBIR rpc_transicion_ot
-- ############################################################################
-- Cambios:
--   - 'cerrada' REMOVIDO de transiciones válidas (solo via rpc_cerrar_ot_supervisor)
--   - responsable_id OBLIGATORIO para transición a en_ejecucion
--
-- NOTA: Primero eliminar la versión anterior (puede tener firma diferente)

DROP FUNCTION IF EXISTS rpc_transicion_ot(UUID, estado_ot_enum, UUID, causa_no_ejecucion_enum, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION rpc_transicion_ot(
    p_ot_id                UUID,
    p_nuevo_estado         estado_ot_enum,
    p_usuario_id           UUID,
    p_causa_no_ejecucion   causa_no_ejecucion_enum DEFAULT NULL,
    p_detalle_no_ejecucion TEXT DEFAULT NULL,
    p_observaciones        TEXT DEFAULT NULL,
    p_responsable_id       UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ot                     RECORD;
    v_count_evidence         INTEGER;
    v_count_checklist_total  INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas   estado_ot_enum[];
BEGIN
    -- 1. LOCK EXCLUSIVO
    SELECT * INTO v_ot
    FROM ordenes_trabajo
    WHERE id = p_ot_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
    END IF;

    -- 2. MÁQUINA DE ESTADOS
    -- CORRECCIÓN 1: 'cerrada' NO está en ninguna lista.
    -- Solo rpc_cerrar_ot_supervisor puede mover a 'cerrada'.
    v_transiciones_validas := CASE v_ot.estado
        WHEN 'creada'                      THEN ARRAY['asignada','cancelada']::estado_ot_enum[]
        WHEN 'asignada'                    THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'en_ejecucion'                THEN ARRAY['pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada']::estado_ot_enum[]
        WHEN 'pausada'                     THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'ejecutada_ok'                THEN ARRAY[]::estado_ot_enum[]  -- solo supervisor cierra
        WHEN 'ejecutada_con_observaciones' THEN ARRAY[]::estado_ot_enum[]  -- solo supervisor cierra
        WHEN 'no_ejecutada'                THEN ARRAY[]::estado_ot_enum[]  -- solo supervisor cierra
        WHEN 'cancelada'                   THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cerrada'                     THEN ARRAY[]::estado_ot_enum[]
        ELSE ARRAY[]::estado_ot_enum[]
    END;

    IF NOT (p_nuevo_estado = ANY(v_transiciones_validas)) THEN
        IF p_nuevo_estado = 'cerrada' THEN
            RAISE EXCEPTION 'La transición a "cerrada" solo puede realizarse mediante cierre de supervisor (rpc_cerrar_ot_supervisor).';
        END IF;
        RAISE EXCEPTION 'Transición inválida: "%" → "%". Permitidas: %',
            v_ot.estado, p_nuevo_estado, v_transiciones_validas;
    END IF;

    -- 3. VALIDACIONES POR TRANSICIÓN

    -- 3a. → asignada: requiere responsable
    IF p_nuevo_estado = 'asignada' THEN
        IF COALESCE(p_responsable_id, v_ot.responsable_id) IS NULL THEN
            RAISE EXCEPTION 'No se puede asignar OT sin responsable.';
        END IF;
    END IF;

    -- 3b. → en_ejecucion: CORRECCIÓN 2 — responsable OBLIGATORIO
    IF p_nuevo_estado = 'en_ejecucion' THEN
        IF v_ot.responsable_id IS NULL THEN
            RAISE EXCEPTION 'No se puede iniciar ejecución sin responsable asignado. Asigne un responsable primero.';
        END IF;
    END IF;

    -- 3c. → no_ejecutada: causa obligatoria
    IF p_nuevo_estado = 'no_ejecutada' THEN
        IF p_causa_no_ejecucion IS NULL THEN
            RAISE EXCEPTION 'Causa de no ejecución es obligatoria.';
        END IF;
    END IF;

    -- 3d. → ejecutada_ok: evidencia + checklist
    IF p_nuevo_estado = 'ejecutada_ok' THEN
        SELECT COUNT(*) INTO v_count_evidence
        FROM evidencias_ot WHERE ot_id = p_ot_id;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'REGLA: Tarea sin evidencia = tarea no ejecutada. Cargue al menos 1 foto.';
        END IF;

        SELECT COUNT(*) FILTER (WHERE obligatorio = true),
               COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
        INTO v_count_checklist_total, v_count_checklist_pending
        FROM checklist_ot WHERE ot_id = p_ot_id;

        IF v_count_checklist_total > 0 AND v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % de % ítems obligatorios sin completar.',
                v_count_checklist_pending, v_count_checklist_total;
        END IF;
    END IF;

    -- 3e. → ejecutada_con_observaciones: evidencia + checklist + observaciones
    IF p_nuevo_estado = 'ejecutada_con_observaciones' THEN
        SELECT COUNT(*) INTO v_count_evidence
        FROM evidencias_ot WHERE ot_id = p_ot_id;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'REGLA: Tarea sin evidencia = tarea no ejecutada.';
        END IF;

        SELECT COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
        INTO v_count_checklist_pending
        FROM checklist_ot WHERE ot_id = p_ot_id;
        IF v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % ítems obligatorios sin completar.', v_count_checklist_pending;
        END IF;

        IF COALESCE(p_observaciones, v_ot.observaciones, '') = '' THEN
            RAISE EXCEPTION 'Observaciones obligatorias al finalizar con observaciones.';
        END IF;
    END IF;

    -- 4. EJECUTAR TRANSICIÓN
    UPDATE ordenes_trabajo
    SET
        estado = p_nuevo_estado,
        responsable_id = CASE
            WHEN p_nuevo_estado = 'asignada' AND p_responsable_id IS NOT NULL
            THEN p_responsable_id
            ELSE responsable_id
        END,
        fecha_inicio = CASE
            WHEN p_nuevo_estado = 'en_ejecucion' AND fecha_inicio IS NULL THEN NOW()
            ELSE fecha_inicio
        END,
        fecha_termino = CASE
            WHEN p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada')
            THEN NOW()
            ELSE fecha_termino
        END,
        causa_no_ejecucion = CASE
            WHEN p_nuevo_estado = 'no_ejecutada' THEN p_causa_no_ejecucion
            ELSE causa_no_ejecucion
        END,
        detalle_no_ejecucion = CASE
            WHEN p_nuevo_estado = 'no_ejecutada' THEN p_detalle_no_ejecucion
            ELSE detalle_no_ejecucion
        END,
        observaciones = CASE
            WHEN p_observaciones IS NOT NULL THEN p_observaciones
            ELSE observaciones
        END,
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- 5. HISTORIAL
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, p_nuevo_estado,
            COALESCE(p_observaciones, p_detalle_no_ejecucion, v_ot.estado || ' → ' || p_nuevo_estado),
            p_usuario_id);

    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'folio', v_ot.folio,
        'estado_anterior', v_ot.estado,
        'estado_nuevo', p_nuevo_estado
    );
END;
$$;


-- ############################################################################
-- CORRECCIÓN 3: TRIGGER DE INMUTABILIDAD EN ordenes_trabajo
-- ############################################################################
-- Bloquea UPDATE en ordenes_trabajo cuando estado = 'cerrada'.
-- Excepción: el propio rpc_cerrar_ot_supervisor necesita hacer el UPDATE
-- que PONE el estado en 'cerrada'. Después de eso, queda bloqueado.

CREATE OR REPLACE FUNCTION trg_bloquear_update_ot_cerrada()
RETURNS TRIGGER AS $$
BEGIN
    -- Si el estado ANTERIOR ya era 'cerrada', bloquear cualquier cambio
    IF OLD.estado = 'cerrada' THEN
        RAISE EXCEPTION 'OT "%" está cerrada definitivamente. No se permite ninguna modificación.', OLD.folio;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ot_inmutable_cerrada ON ordenes_trabajo;
CREATE TRIGGER trg_ot_inmutable_cerrada
    BEFORE UPDATE ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION trg_bloquear_update_ot_cerrada();


-- ############################################################################
-- CORRECCIÓN 4: VALIDAR FAENA EN SALIDA DE INVENTARIO
-- ############################################################################

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
    v_bodega_faena   UUID;
BEGIN
    -- VALIDACIONES
    IF p_ot_id IS NULL THEN
        RAISE EXCEPTION 'REGLA: No se permite salida de inventario sin OT asociada.';
    END IF;

    SELECT id, estado, folio, faena_id INTO v_ot
    FROM ordenes_trabajo WHERE id = p_ot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
    END IF;

    IF v_ot.estado NOT IN ('asignada', 'en_ejecucion') THEN
        RAISE EXCEPTION 'No se puede retirar material de OT en estado "%".', v_ot.estado;
    END IF;

    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
    END IF;

    SELECT id, nombre, stock_minimo INTO v_producto
    FROM productos WHERE id = p_producto_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto no encontrado.';
    END IF;

    -- CORRECCIÓN 4: Validar que bodega pertenece a la faena de la OT
    SELECT faena_id INTO v_bodega_faena
    FROM bodegas WHERE id = p_bodega_id;

    IF v_bodega_faena IS NOT NULL AND v_ot.faena_id IS NOT NULL
       AND v_bodega_faena != v_ot.faena_id THEN
        RAISE EXCEPTION 'La bodega seleccionada no pertenece a la faena de la OT. Bodega faena: %, OT faena: %.',
            v_bodega_faena, v_ot.faena_id;
    END IF;

    -- LOCK + OPERACIÓN ATÓMICA
    SELECT cantidad, costo_promedio INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe stock de "%" en la bodega indicada.', v_producto.nombre;
    END IF;

    IF v_stock.cantidad < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente de "%". Disponible: %, solicitado: %.',
            v_producto.nombre, v_stock.cantidad, p_cantidad;
    END IF;

    v_costo_unitario := v_stock.costo_promedio;
    v_nuevo_stock := v_stock.cantidad - p_cantidad;
    v_movimiento_id := gen_random_uuid();

    -- Movimiento
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        ot_id, activo_id, lote, motivo, usuario_id, created_at
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, 'salida', p_cantidad,
        v_costo_unitario, p_ot_id,
        COALESCE(p_activo_id, (SELECT activo_id FROM ordenes_trabajo WHERE id = p_ot_id)),
        p_lote, p_motivo, p_usuario_id, NOW()
    );

    -- Stock
    UPDATE stock_bodega
    SET cantidad = v_nuevo_stock, ultimo_movimiento = NOW(), updated_at = NOW()
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;

    -- Kardex
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

    -- Costo OT
    UPDATE ordenes_trabajo
    SET costo_materiales = COALESCE(costo_materiales, 0) + (p_cantidad * v_costo_unitario),
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- Alerta stock mínimo
    IF v_nuevo_stock < v_producto.stock_minimo THEN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES ('stock_minimo', 'Stock bajo: ' || v_producto.nombre,
                'Stock: ' || v_nuevo_stock || '. Mínimo: ' || v_producto.stock_minimo,
                'warning', 'producto', p_producto_id);
    END IF;

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


-- ############################################################################
-- CORRECCIÓN 5: ACTUALIZAR SEED DE FUNCIONES KPI
-- ############################################################################
-- Esto corrige kpi_definiciones.funcion_calculo para que apunte a las
-- funciones reales. El fix 15 ya lo hace, pero esto lo aplica de forma
-- idempotente para cualquier instalación.

UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a1' WHERE codigo = 'A1' AND funcion_calculo != 'calcular_kpi_a1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a2' WHERE codigo = 'A2' AND funcion_calculo != 'calcular_kpi_a2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a3' WHERE codigo = 'A3' AND funcion_calculo != 'calcular_kpi_a3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a4' WHERE codigo = 'A4' AND funcion_calculo != 'calcular_kpi_a4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a5' WHERE codigo = 'A5' AND funcion_calculo != 'calcular_kpi_a5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a6' WHERE codigo = 'A6' AND funcion_calculo != 'calcular_kpi_a6';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a7' WHERE codigo = 'A7' AND funcion_calculo != 'calcular_kpi_a7';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a8' WHERE codigo = 'A8' AND funcion_calculo != 'calcular_kpi_a8';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b1' WHERE codigo = 'B1' AND funcion_calculo != 'calcular_kpi_b1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b2' WHERE codigo = 'B2' AND funcion_calculo != 'calcular_kpi_b2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b3' WHERE codigo = 'B3' AND funcion_calculo != 'calcular_kpi_b3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b4' WHERE codigo = 'B4' AND funcion_calculo != 'calcular_kpi_b4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b5' WHERE codigo = 'B5' AND funcion_calculo != 'calcular_kpi_b5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b6' WHERE codigo = 'B6' AND funcion_calculo != 'calcular_kpi_b6';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c1' WHERE codigo = 'C1' AND funcion_calculo != 'calcular_kpi_c1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c2' WHERE codigo = 'C2' AND funcion_calculo != 'calcular_kpi_c2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c3' WHERE codigo = 'C3' AND funcion_calculo != 'calcular_kpi_c3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c4' WHERE codigo = 'C4' AND funcion_calculo != 'calcular_kpi_c4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c5' WHERE codigo = 'C5' AND funcion_calculo != 'calcular_kpi_c5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c6' WHERE codigo = 'C6' AND funcion_calculo != 'calcular_kpi_c6';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c7' WHERE codigo = 'C7' AND funcion_calculo != 'calcular_kpi_c7';


-- ############################################################################
-- CORRECCIÓN 6: COSTO MANO DE OBRA
-- ############################################################################

-- Nuevos campos en ordenes_trabajo
ALTER TABLE ordenes_trabajo ADD COLUMN IF NOT EXISTS horas_hombre NUMERIC(8,2) DEFAULT 0;
ALTER TABLE ordenes_trabajo ADD COLUMN IF NOT EXISTS tarifa_hora NUMERIC(12,2) DEFAULT 0;

-- Nota: costo_mano_obra ya existe como campo normal (no generado).
-- Lo actualizamos en rpc_cerrar_ot_supervisor para que se calcule
-- automáticamente si horas_hombre y tarifa_hora están seteados.

-- Reescribir cierre supervisor para incluir cálculo de MO
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
    v_ot                     RECORD;
    v_costo_materiales       NUMERIC(12,2);
    v_costo_mo               NUMERIC(12,2);
    v_count_evidence         INTEGER;
    v_count_checklist_pending INTEGER;
    v_count_movimientos      INTEGER;
    v_advertencias           TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada.';
    END IF;

    IF v_ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada') THEN
        RAISE EXCEPTION 'Solo se puede cerrar OT ejecutada o no ejecutada. Estado: "%".', v_ot.estado;
    END IF;

    -- Validar completitud (solo para ejecutadas)
    IF v_ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones') THEN
        SELECT COUNT(*) INTO v_count_evidence FROM evidencias_ot WHERE ot_id = p_ot_id;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar OT sin evidencia.';
        END IF;

        SELECT COUNT(*) INTO v_count_checklist_pending
        FROM checklist_ot WHERE ot_id = p_ot_id AND obligatorio = true AND resultado IS NULL;
        IF v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % ítems obligatorios sin completar.', v_count_checklist_pending;
        END IF;
    END IF;

    -- Calcular costos materiales
    SELECT COALESCE(SUM(cantidad * costo_unitario), 0), COUNT(*)
    INTO v_costo_materiales, v_count_movimientos
    FROM movimientos_inventario
    WHERE ot_id = p_ot_id AND tipo IN ('salida', 'merma');

    -- CORRECCIÓN 6: Calcular costo mano de obra
    -- Si horas_hombre y tarifa están seteados, calcular. Si no, usar lo que ya tenga.
    IF COALESCE(v_ot.horas_hombre, 0) > 0 AND COALESCE(v_ot.tarifa_hora, 0) > 0 THEN
        v_costo_mo := ROUND(v_ot.horas_hombre * v_ot.tarifa_hora);
    ELSE
        v_costo_mo := COALESCE(v_ot.costo_mano_obra, 0);
    END IF;

    -- Advertencias
    IF v_count_movimientos = 0 AND v_ot.tipo NOT IN ('inspeccion', 'regularizacion') THEN
        v_advertencias := array_append(v_advertencias, 'OT sin materiales registrados');
    END IF;
    IF v_costo_materiales = 0 AND v_costo_mo = 0 THEN
        v_advertencias := array_append(v_advertencias, 'OT con costo total $0');
    END IF;
    IF COALESCE(v_ot.horas_hombre, 0) = 0 THEN
        v_advertencias := array_append(v_advertencias, 'Sin horas hombre registradas');
    END IF;

    -- CERRAR
    UPDATE ordenes_trabajo
    SET
        estado = 'cerrada',
        fecha_cierre_supervisor = NOW(),
        supervisor_cierre_id = p_supervisor_id,
        observaciones_supervisor = p_observaciones,
        costo_materiales = v_costo_materiales,
        costo_mano_obra = v_costo_mo,
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- Plan PM
    IF v_ot.plan_mantenimiento_id IS NOT NULL AND v_ot.estado != 'no_ejecutada' THEN
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

    -- Historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, 'cerrada',
            COALESCE(p_observaciones, 'Cierre supervisor'), p_supervisor_id);

    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'folio', v_ot.folio,
        'estado_anterior', v_ot.estado,
        'estado_nuevo', 'cerrada',
        'costo_materiales', v_costo_materiales,
        'costo_mano_obra', v_costo_mo,
        'costo_total', v_costo_materiales + v_costo_mo,
        'movimientos_count', v_count_movimientos,
        'advertencias', to_jsonb(v_advertencias),
        'supervisor_id', p_supervisor_id
    );
END;
$$;


-- ############################################################################
-- VERIFICACIÓN FINAL
-- ############################################################################

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Verificar trigger de inmutabilidad
    SELECT COUNT(*) INTO v_count FROM pg_trigger WHERE tgname = 'trg_ot_inmutable_cerrada';
    IF v_count = 0 THEN RAISE EXCEPTION 'Trigger trg_ot_inmutable_cerrada no creado'; END IF;
    RAISE NOTICE 'OK: Trigger inmutabilidad OT cerrada activo';

    -- Verificar KPI funciones corregidas
    SELECT COUNT(*) INTO v_count FROM kpi_definiciones
    WHERE funcion_calculo LIKE 'fn_kpi_%';
    IF v_count > 0 THEN RAISE EXCEPTION 'Aún hay % KPIs con fn_kpi_*', v_count; END IF;
    RAISE NOTICE 'OK: % KPIs con nombre correcto', (SELECT COUNT(*) FROM kpi_definiciones WHERE activo = true);

    -- Verificar columnas nuevas
    SELECT COUNT(*) INTO v_count FROM information_schema.columns
    WHERE table_name = 'ordenes_trabajo' AND column_name = 'horas_hombre';
    IF v_count = 0 THEN RAISE EXCEPTION 'Campo horas_hombre no creado'; END IF;
    RAISE NOTICE 'OK: Campos horas_hombre y tarifa_hora activos';

    RAISE NOTICE '=== TODAS LAS CORRECCIONES APLICADAS EXITOSAMENTE ===';
END $$;

-- ============================================================================
-- FIN del archivo 18_correcciones_criticas.sql
-- ============================================================================
