-- SICOM-ICEO | Núcleo Transaccional Definitivo v2
-- ============================================================================
-- Ejecutar DESPUÉS de 09_rpc_transaccional.sql
--
-- Este archivo:
-- 1. Agrega RPCs faltantes (transferencia, conteo, actualizar métricas activo)
-- 2. Agrega trigger para bloquear escrituras en OTs cerradas
-- 3. Agrega vistas materializadas para costos por OT/activo/faena
-- 4. Agrega función de recálculo ICEO por evento
-- ============================================================================


-- ############################################################################
-- SECCIÓN 1: TRIGGER PARA INMUTABILIDAD DE OTs CERRADAS
-- ############################################################################
-- Bloquea INSERT en checklist_ot y evidencias_ot cuando la OT está cerrada.
-- Esto es la validación de última línea (server-side, imposible de bypassear).

CREATE OR REPLACE FUNCTION trg_bloquear_escritura_ot_cerrada()
RETURNS TRIGGER AS $$
DECLARE
    v_estado TEXT;
BEGIN
    SELECT estado INTO v_estado
    FROM ordenes_trabajo
    WHERE id = NEW.ot_id;

    IF v_estado IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada', 'cancelada') THEN
        RAISE EXCEPTION 'No se permite modificar datos de una OT en estado "%". La OT está cerrada.', v_estado;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar a checklist_ot (INSERT y UPDATE)
DROP TRIGGER IF EXISTS trg_checklist_ot_cerrada ON checklist_ot;
CREATE TRIGGER trg_checklist_ot_cerrada
    BEFORE INSERT OR UPDATE ON checklist_ot
    FOR EACH ROW
    EXECUTE FUNCTION trg_bloquear_escritura_ot_cerrada();

-- Aplicar a evidencias_ot (INSERT)
DROP TRIGGER IF EXISTS trg_evidencias_ot_cerrada ON evidencias_ot;
CREATE TRIGGER trg_evidencias_ot_cerrada
    BEFORE INSERT ON evidencias_ot
    FOR EACH ROW
    EXECUTE FUNCTION trg_bloquear_escritura_ot_cerrada();

-- Aplicar a movimientos_inventario con OT cerrada
CREATE OR REPLACE FUNCTION trg_bloquear_movimiento_ot_cerrada()
RETURNS TRIGGER AS $$
DECLARE
    v_estado TEXT;
BEGIN
    -- Solo validar si tiene OT asociada
    IF NEW.ot_id IS NOT NULL THEN
        SELECT estado INTO v_estado
        FROM ordenes_trabajo
        WHERE id = NEW.ot_id;

        IF v_estado IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada', 'cancelada') THEN
            RAISE EXCEPTION 'No se permite registrar movimiento de inventario contra OT cerrada (estado: %).', v_estado;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mov_inv_ot_cerrada ON movimientos_inventario;
CREATE TRIGGER trg_mov_inv_ot_cerrada
    BEFORE INSERT ON movimientos_inventario
    FOR EACH ROW
    EXECUTE FUNCTION trg_bloquear_movimiento_ot_cerrada();


-- ############################################################################
-- SECCIÓN 2: RPC TRANSFERENCIA DE INVENTARIO
-- ############################################################################
-- Transfiere stock de una bodega a otra atómicamente.
-- Genera 2 movimientos (transferencia_salida + transferencia_entrada) + 2 kardex.

CREATE OR REPLACE FUNCTION rpc_transferir_inventario(
    p_bodega_origen_id   UUID,
    p_bodega_destino_id  UUID,
    p_producto_id        UUID,
    p_cantidad           NUMERIC(12,3),
    p_usuario_id         UUID,
    p_motivo             TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_stock_origen   RECORD;
    v_stock_destino  RECORD;
    v_nuevo_stock_o  NUMERIC(12,3);
    v_nuevo_stock_d  NUMERIC(12,3);
    v_nuevo_cpp_d    NUMERIC(15,4);
    v_mov_salida_id  UUID;
    v_mov_entrada_id UUID;
    v_producto       RECORD;
BEGIN
    -- Validaciones
    IF p_bodega_origen_id = p_bodega_destino_id THEN
        RAISE EXCEPTION 'Bodega origen y destino no pueden ser la misma.';
    END IF;
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
    END IF;

    SELECT id, nombre INTO v_producto FROM productos WHERE id = p_producto_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;

    -- Lock origen
    SELECT cantidad, costo_promedio INTO v_stock_origen
    FROM stock_bodega
    WHERE bodega_id = p_bodega_origen_id AND producto_id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND OR v_stock_origen.cantidad < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente en bodega origen. Disponible: %, solicitado: %.',
            COALESCE(v_stock_origen.cantidad, 0), p_cantidad;
    END IF;

    -- Lock destino
    SELECT cantidad, costo_promedio INTO v_stock_destino
    FROM stock_bodega
    WHERE bodega_id = p_bodega_destino_id AND producto_id = p_producto_id
    FOR UPDATE;

    -- Calcular nuevos stocks
    v_nuevo_stock_o := v_stock_origen.cantidad - p_cantidad;

    IF NOT FOUND THEN
        v_stock_destino.cantidad := 0;
        v_stock_destino.costo_promedio := 0;
    END IF;

    v_nuevo_stock_d := v_stock_destino.cantidad + p_cantidad;
    -- CPP destino: promedio ponderado con el CPP del origen
    IF v_nuevo_stock_d > 0 THEN
        v_nuevo_cpp_d := (
            (v_stock_destino.cantidad * v_stock_destino.costo_promedio) +
            (p_cantidad * v_stock_origen.costo_promedio)
        ) / v_nuevo_stock_d;
    ELSE
        v_nuevo_cpp_d := v_stock_origen.costo_promedio;
    END IF;

    v_mov_salida_id := gen_random_uuid();
    v_mov_entrada_id := gen_random_uuid();

    -- Movimiento salida
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        bodega_destino_id, motivo, usuario_id
    ) VALUES (
        v_mov_salida_id, p_bodega_origen_id, p_producto_id, 'transferencia_salida',
        p_cantidad, v_stock_origen.costo_promedio,
        p_bodega_destino_id, p_motivo, p_usuario_id
    );

    -- Movimiento entrada
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        bodega_destino_id, motivo, usuario_id
    ) VALUES (
        v_mov_entrada_id, p_bodega_destino_id, p_producto_id, 'transferencia_entrada',
        p_cantidad, v_stock_origen.costo_promedio,
        p_bodega_origen_id, p_motivo, p_usuario_id
    );

    -- Update stock origen
    UPDATE stock_bodega
    SET cantidad = v_nuevo_stock_o, ultimo_movimiento = NOW(), updated_at = NOW()
    WHERE bodega_id = p_bodega_origen_id AND producto_id = p_producto_id;

    -- UPSERT stock destino
    INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
    VALUES (p_bodega_destino_id, p_producto_id, v_nuevo_stock_d, v_nuevo_cpp_d, NOW())
    ON CONFLICT (bodega_id, producto_id)
    DO UPDATE SET
        cantidad = v_nuevo_stock_d,
        costo_promedio = v_nuevo_cpp_d,
        ultimo_movimiento = NOW(),
        updated_at = NOW();

    -- Kardex origen
    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_origen_id, p_producto_id, v_mov_salida_id,
        NOW(), 'transferencia_salida',
        p_cantidad, v_stock_origen.cantidad, v_nuevo_stock_o,
        v_stock_origen.costo_promedio, v_stock_origen.costo_promedio, v_stock_origen.costo_promedio,
        p_cantidad * v_stock_origen.costo_promedio, v_nuevo_stock_o * v_stock_origen.costo_promedio
    );

    -- Kardex destino
    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_destino_id, p_producto_id, v_mov_entrada_id,
        NOW(), 'transferencia_entrada',
        p_cantidad, v_stock_destino.cantidad, v_nuevo_stock_d,
        v_stock_origen.costo_promedio, v_stock_destino.costo_promedio, v_nuevo_cpp_d,
        p_cantidad * v_stock_origen.costo_promedio, v_nuevo_stock_d * v_nuevo_cpp_d
    );

    RETURN jsonb_build_object(
        'producto', v_producto.nombre,
        'cantidad', p_cantidad,
        'costo_unitario', v_stock_origen.costo_promedio,
        'bodega_origen_stock', v_nuevo_stock_o,
        'bodega_destino_stock', v_nuevo_stock_d,
        'bodega_destino_cpp', v_nuevo_cpp_d
    );
END;
$$;


-- ############################################################################
-- SECCIÓN 3: RPC CONTEO DE INVENTARIO CON AJUSTES AUTOMÁTICOS
-- ############################################################################
-- Aprueba un conteo y genera automáticamente los ajustes para cada diferencia.

CREATE OR REPLACE FUNCTION rpc_aprobar_conteo_inventario(
    p_conteo_id      UUID,
    p_supervisor_id  UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
$$;


-- ############################################################################
-- SECCIÓN 4: RPC ACTUALIZAR MÉTRICAS DE ACTIVO
-- ############################################################################
-- Actualiza km, horas o ciclos de un activo y evalúa si dispara PM.

CREATE OR REPLACE FUNCTION rpc_actualizar_metricas_activo(
    p_activo_id      UUID,
    p_kilometraje    NUMERIC(12,1) DEFAULT NULL,
    p_horas_uso      NUMERIC(12,1) DEFAULT NULL,
    p_ciclos         INTEGER DEFAULT NULL,
    p_usuario_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_activo          RECORD;
    v_plan            RECORD;
    v_ot_result       JSONB;
    v_ots_generadas   INTEGER := 0;
BEGIN
    -- Lock activo
    SELECT * INTO v_activo
    FROM activos
    WHERE id = p_activo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado.';
    END IF;

    -- Actualizar métricas (solo las que se proporcionan)
    UPDATE activos
    SET
        kilometraje_actual = COALESCE(p_kilometraje, kilometraje_actual),
        horas_uso_actual = COALESCE(p_horas_uso, horas_uso_actual),
        ciclos_actual = COALESCE(p_ciclos, ciclos_actual),
        updated_at = NOW()
    WHERE id = p_activo_id;

    -- Evaluar planes PM que puedan dispararse por las nuevas métricas
    FOR v_plan IN
        SELECT pm.*
        FROM planes_mantenimiento pm
        WHERE pm.activo_id = p_activo_id
          AND pm.activo_plan = true
          AND NOT EXISTS (
              SELECT 1 FROM ordenes_trabajo ot
              WHERE ot.plan_mantenimiento_id = pm.id
                AND ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada', 'cancelada')
          )
    LOOP
        -- Evaluar condición de disparo
        IF (
            (v_plan.tipo_plan IN ('por_kilometraje', 'mixto')
             AND v_plan.frecuencia_km IS NOT NULL
             AND p_kilometraje IS NOT NULL
             AND (p_kilometraje - COALESCE(v_plan.ultima_ejecucion_km, 0)) >= v_plan.frecuencia_km)
            OR
            (v_plan.tipo_plan IN ('por_horas', 'mixto')
             AND v_plan.frecuencia_horas IS NOT NULL
             AND p_horas_uso IS NOT NULL
             AND (p_horas_uso - COALESCE(v_plan.ultima_ejecucion_horas, 0)) >= v_plan.frecuencia_horas)
            OR
            (v_plan.tipo_plan = 'por_ciclos'
             AND v_plan.frecuencia_ciclos IS NOT NULL
             AND p_ciclos IS NOT NULL
             AND (p_ciclos - COALESCE(v_plan.ultima_ejecucion_ciclos, 0)) >= v_plan.frecuencia_ciclos)
        ) THEN
            -- Crear OT preventiva
            SELECT rpc_crear_ot(
                p_tipo := 'preventivo',
                p_contrato_id := v_activo.contrato_id,
                p_faena_id := v_activo.faena_id,
                p_activo_id := p_activo_id,
                p_prioridad := COALESCE(v_plan.prioridad, 'normal'),
                p_fecha_programada := CURRENT_DATE + COALESCE(v_plan.anticipacion_dias, 7),
                p_plan_mantenimiento_id := v_plan.id,
                p_usuario_id := p_usuario_id
            ) INTO v_ot_result;

            v_ots_generadas := v_ots_generadas + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'activo_id', p_activo_id,
        'kilometraje', COALESCE(p_kilometraje, v_activo.kilometraje_actual),
        'horas_uso', COALESCE(p_horas_uso, v_activo.horas_uso_actual),
        'ciclos', COALESCE(p_ciclos, v_activo.ciclos_actual),
        'ots_preventivas_generadas', v_ots_generadas
    );
END;
$$;


-- ############################################################################
-- SECCIÓN 5: VISTAS PARA COSTOS POR OT / ACTIVO / FAENA
-- ############################################################################

-- Vista: costo total por OT (materiales + mano de obra)
CREATE OR REPLACE VIEW v_costos_por_ot AS
SELECT
    ot.id AS ot_id,
    ot.folio,
    ot.tipo,
    ot.estado,
    ot.activo_id,
    ot.faena_id,
    ot.contrato_id,
    COALESCE(ot.costo_mano_obra, 0) AS costo_mano_obra,
    COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_materiales_real,
    COALESCE(ot.costo_mano_obra, 0) +
        COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_total_real,
    COUNT(mi.id) FILTER (WHERE mi.tipo IN ('salida', 'merma')) AS total_movimientos,
    ot.fecha_programada,
    ot.fecha_inicio,
    ot.fecha_termino
FROM ordenes_trabajo ot
LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
GROUP BY ot.id;

COMMENT ON VIEW v_costos_por_ot IS 'Costo real por OT: mano de obra + materiales consumidos (salida + merma).';

-- Vista: costo acumulado por activo
CREATE OR REPLACE VIEW v_costos_por_activo AS
SELECT
    a.id AS activo_id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.faena_id,
    COUNT(DISTINCT ot.id) AS total_ots,
    COALESCE(SUM(ot.costo_mano_obra), 0) AS costo_mano_obra_total,
    COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_materiales_total,
    COALESCE(SUM(ot.costo_mano_obra), 0) +
        COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_total,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'correctivo') AS ots_correctivas,
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo') AS ots_preventivas
FROM activos a
LEFT JOIN ordenes_trabajo ot ON ot.activo_id = a.id
LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
GROUP BY a.id;

COMMENT ON VIEW v_costos_por_activo IS 'Costo acumulado por activo: total OTs, mano de obra, materiales, ratio preventivo/correctivo.';

-- Vista: costo por faena
CREATE OR REPLACE VIEW v_costos_por_faena AS
SELECT
    f.id AS faena_id,
    f.codigo,
    f.nombre,
    COUNT(DISTINCT ot.id) AS total_ots,
    COALESCE(SUM(ot.costo_mano_obra), 0) AS costo_mano_obra_total,
    COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_materiales_total,
    COALESCE(SUM(ot.costo_mano_obra), 0) +
        COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo IN ('salida', 'merma')), 0) AS costo_total,
    -- Valorización inventario en bodega
    COALESCE((
        SELECT SUM(sb.cantidad * sb.costo_promedio)
        FROM stock_bodega sb
        JOIN bodegas b ON b.id = sb.bodega_id
        WHERE b.faena_id = f.id
    ), 0) AS valorizacion_inventario
FROM faenas f
LEFT JOIN ordenes_trabajo ot ON ot.faena_id = f.id
LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
GROUP BY f.id;

COMMENT ON VIEW v_costos_por_faena IS 'Costo por faena: total OTs, mano de obra, materiales, valorización inventario.';


-- ############################################################################
-- SECCIÓN 6: TRIGGER PARA RECÁLCULO ICEO POR EVENTO
-- ############################################################################
-- Cuando se cierra una OT o se registra un incidente, marcar que el ICEO
-- del período necesita recálculo.
-- No recalculamos inline (sería muy lento), sino que marcamos un flag.

-- Tabla auxiliar para rastrear períodos que necesitan recálculo
CREATE TABLE IF NOT EXISTS iceo_recalculo_pendiente (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id UUID NOT NULL REFERENCES contratos(id),
    faena_id    UUID REFERENCES faenas(id),
    periodo     DATE NOT NULL,
    motivo      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    procesado   BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_iceo_recalculo_pendiente
    ON iceo_recalculo_pendiente (procesado, periodo)
    WHERE procesado = false;

-- Trigger: cuando una OT cambia a estado terminal, marcar recálculo
CREATE OR REPLACE FUNCTION trg_marcar_iceo_recalculo()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo cuando cambia a estado terminal
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada') THEN
        IF OLD.estado IS NULL OR OLD.estado != NEW.estado THEN
            INSERT INTO iceo_recalculo_pendiente (contrato_id, faena_id, periodo, motivo)
            VALUES (
                NEW.contrato_id,
                NEW.faena_id,
                DATE_TRUNC('month', CURRENT_DATE)::DATE,
                'OT ' || NEW.folio || ' cambió a ' || NEW.estado
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_ot_iceo_recalculo ON ordenes_trabajo;
CREATE TRIGGER trg_ot_iceo_recalculo
    AFTER UPDATE ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION trg_marcar_iceo_recalculo();

-- Trigger: cuando se registra un incidente, marcar recálculo
CREATE OR REPLACE FUNCTION trg_incidente_iceo_recalculo()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO iceo_recalculo_pendiente (contrato_id, faena_id, periodo, motivo)
    VALUES (
        NEW.contrato_id,
        NEW.faena_id,
        DATE_TRUNC('month', CURRENT_DATE)::DATE,
        'Incidente registrado: ' || NEW.tipo || ' - ' || LEFT(NEW.descripcion, 100)
    )
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_incidente_iceo_recalculo ON incidentes;
CREATE TRIGGER trg_incidente_iceo_recalculo
    AFTER INSERT ON incidentes
    FOR EACH ROW
    EXECUTE FUNCTION trg_incidente_iceo_recalculo();

-- Función para procesar recálculos pendientes (llamada por pg_cron)
CREATE OR REPLACE FUNCTION rpc_procesar_recalculos_iceo()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pendiente RECORD;
    v_resultado JSONB;
    v_count     INTEGER := 0;
BEGIN
    FOR v_pendiente IN
        SELECT DISTINCT contrato_id, faena_id, periodo
        FROM iceo_recalculo_pendiente
        WHERE procesado = false
        ORDER BY periodo DESC
    LOOP
        -- Recalcular ICEO del período
        SELECT rpc_calcular_iceo_periodo(
            p_contrato_id    := v_pendiente.contrato_id,
            p_faena_id       := v_pendiente.faena_id,
            p_periodo_inicio := v_pendiente.periodo,
            p_periodo_fin    := (v_pendiente.periodo + INTERVAL '1 month' - INTERVAL '1 day')::DATE
        ) INTO v_resultado;

        -- Marcar como procesados
        UPDATE iceo_recalculo_pendiente
        SET procesado = true
        WHERE contrato_id = v_pendiente.contrato_id
          AND COALESCE(faena_id, '00000000-0000-0000-0000-000000000000') =
              COALESCE(v_pendiente.faena_id, '00000000-0000-0000-0000-000000000000')
          AND periodo = v_pendiente.periodo
          AND procesado = false;

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'periodos_recalculados', v_count
    );
END;
$$;


-- ############################################################################
-- SECCIÓN 7: RESUMEN DE OPERACIONES TRANSACCIONALES
-- ############################################################################
--
-- INVENTARIO COMPLETO:
-- ┌─────────────────────────────────────────────────────────┐
-- │ rpc_registrar_salida_inventario   → lock + kardex + OT  │
-- │ rpc_registrar_entrada_inventario  → lock + CPP + kardex │
-- │ rpc_registrar_ajuste_inventario   → lock + motivo       │
-- │ rpc_transferir_inventario         → 2 locks + 2 kardex  │ ← NUEVO
-- │ rpc_aprobar_conteo_inventario     → ajustes automáticos │ ← NUEVO
-- └─────────────────────────────────────────────────────────┘
--
-- OT COMPLETO:
-- ┌─────────────────────────────────────────────────────────┐
-- │ rpc_crear_ot                      → folio + checklist   │
-- │ rpc_transicion_ot                 → máquina estados     │
-- │ rpc_cerrar_ot_supervisor          → congelar costos     │
-- └─────────────────────────────────────────────────────────┘
--
-- ACTIVOS:
-- ┌─────────────────────────────────────────────────────────┐
-- │ rpc_actualizar_metricas_activo    → km/hrs + auto PM    │ ← NUEVO
-- └─────────────────────────────────────────────────────────┘
--
-- ICEO:
-- ┌─────────────────────────────────────────────────────────┐
-- │ rpc_calcular_iceo_periodo         → 21 KPIs + ICEO     │
-- │ rpc_procesar_recalculos_iceo      → batch por eventos   │ ← NUEVO
-- └─────────────────────────────────────────────────────────┘
--
-- TRIGGERS DE PROTECCIÓN:
-- ┌─────────────────────────────────────────────────────────┐
-- │ trg_checklist_ot_cerrada          → inmutabilidad       │ ← NUEVO
-- │ trg_evidencias_ot_cerrada         → inmutabilidad       │ ← NUEVO
-- │ trg_mov_inv_ot_cerrada            → inmutabilidad       │ ← NUEVO
-- │ trg_ot_iceo_recalculo             → marcar recálculo    │ ← NUEVO
-- │ trg_incidente_iceo_recalculo      → marcar recálculo    │ ← NUEVO
-- └─────────────────────────────────────────────────────────┘
--
-- VISTAS DE COSTOS:
-- ┌─────────────────────────────────────────────────────────┐
-- │ v_costos_por_ot                   → MO + materiales     │ ← NUEVO
-- │ v_costos_por_activo               → acumulado histórico │ ← NUEVO
-- │ v_costos_por_faena                → total + valorización│ ← NUEVO
-- └─────────────────────────────────────────────────────────┘
--
-- ============================================================================
-- FIN del archivo 11_nucleo_transaccional_v2.sql
-- ============================================================================
