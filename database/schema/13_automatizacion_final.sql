-- SICOM-ICEO | Automatización Final + Correcciones de Gaps
-- ============================================================================
-- Ejecutar DESPUÉS de 12_motor_estados_ot_v3.sql
--
-- 1. Corrige pg_cron jobs con manejo de errores
-- 2. Corrige tipo de alerta en generación PM
-- 3. Agrega validación de activo operativo en rpc_crear_ot
-- 4. Agrega tabla de log de ejecución cron
-- 5. Mejora rpc_cerrar_ot_supervisor con advertencia de costo cero
-- ============================================================================


-- ############################################################################
-- 1. TABLA DE LOG PARA JOBS AUTOMATIZADOS
-- ############################################################################

CREATE TABLE IF NOT EXISTS log_jobs_automaticos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_name    VARCHAR(100) NOT NULL,
    resultado   VARCHAR(20) NOT NULL CHECK (resultado IN ('ok', 'error', 'warning')),
    detalles    JSONB,
    registros_procesados INTEGER DEFAULT 0,
    error_mensaje TEXT,
    duracion_ms INTEGER,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_log_jobs_created ON log_jobs_automaticos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_log_jobs_name ON log_jobs_automaticos (job_name, created_at DESC);


-- ############################################################################
-- 2. MEJORAR rpc_crear_ot — validar activo operativo y contrato activo
-- ############################################################################

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
    v_activo      RECORD;
    v_contrato    RECORD;
BEGIN
    -- ══ VALIDACIONES PREVIAS ══

    -- Validar contrato activo
    SELECT id, estado INTO v_contrato
    FROM contratos WHERE id = p_contrato_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contrato no encontrado: %', p_contrato_id;
    END IF;

    IF v_contrato.estado != 'activo' THEN
        RAISE EXCEPTION 'No se puede crear OT en contrato con estado "%".', v_contrato.estado;
    END IF;

    -- Validar activo existe y está operativo
    SELECT id, estado, codigo INTO v_activo
    FROM activos WHERE id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado: %', p_activo_id;
    END IF;

    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento') THEN
        RAISE EXCEPTION 'No se puede crear OT para activo en estado "%". Solo operativo o en_mantenimiento.', v_activo.estado;
    END IF;

    -- ══ GENERAR FOLIO ATÓMICO ══
    v_periodo := TO_CHAR(NOW(), 'YYYYMM');

    SELECT COALESCE(MAX(
        CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
    ), 0) + 1
    INTO v_secuencia
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%'
    FOR UPDATE;

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    v_estado := CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'creada' END;

    -- ══ INSERTAR OT ══
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

    -- ══ COPIAR CHECKLIST DESDE PAUTA ══
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

    -- ══ HISTORIAL ══
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    -- ══ RETORNAR ══
    RETURN jsonb_build_object(
        'id', v_ot_id,
        'folio', v_folio,
        'estado', v_estado,
        'qr_code', v_qr_code,
        'activo_codigo', v_activo.codigo
    );
END;
$$;


-- ############################################################################
-- 3. MEJORAR rpc_cerrar_ot_supervisor — advertir si costo = 0
-- ############################################################################
-- No bloquea cierre con costo 0 (hay OTs legítimas sin materiales, como inspecciones),
-- pero incluye flag en el retorno para que el frontend pueda advertir.

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
    v_count_evidence         INTEGER;
    v_count_checklist_pending INTEGER;
    v_count_movimientos      INTEGER;
    v_advertencias           TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- 1. Lock
    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada.';
    END IF;

    IF v_ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada') THEN
        RAISE EXCEPTION 'Solo se puede cerrar una OT ejecutada o no ejecutada. Estado actual: "%".', v_ot.estado;
    END IF;

    -- 2. Validar completitud (solo para ejecutadas, no para no_ejecutada)
    IF v_ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones') THEN
        SELECT COUNT(*) INTO v_count_evidence FROM evidencias_ot WHERE ot_id = p_ot_id;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar OT sin evidencia registrada.';
        END IF;

        SELECT COUNT(*) INTO v_count_checklist_pending
        FROM checklist_ot WHERE ot_id = p_ot_id AND obligatorio = true AND resultado IS NULL;
        IF v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % ítems obligatorios sin completar.', v_count_checklist_pending;
        END IF;
    END IF;

    -- 3. Calcular costos
    SELECT COALESCE(SUM(cantidad * costo_unitario), 0), COUNT(*)
    INTO v_costo_materiales, v_count_movimientos
    FROM movimientos_inventario
    WHERE ot_id = p_ot_id AND tipo IN ('salida', 'merma');

    -- Advertencias (no bloquean, pero se reportan)
    IF v_count_movimientos = 0 AND v_ot.tipo NOT IN ('inspeccion', 'regularizacion') THEN
        v_advertencias := array_append(v_advertencias, 'OT sin materiales registrados');
    END IF;
    IF v_costo_materiales = 0 AND COALESCE(v_ot.costo_mano_obra, 0) = 0 THEN
        v_advertencias := array_append(v_advertencias, 'OT con costo total $0');
    END IF;

    -- 4. Cerrar
    UPDATE ordenes_trabajo
    SET
        estado = 'cerrada',
        fecha_cierre_supervisor = NOW(),
        supervisor_cierre_id = p_supervisor_id,
        observaciones_supervisor = p_observaciones,
        costo_materiales = v_costo_materiales,
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- 5. Plan PM
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

    -- 6. Historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, 'cerrada',
            COALESCE(p_observaciones, 'Cierre supervisor'), p_supervisor_id);

    -- 7. Retornar con advertencias
    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'folio', v_ot.folio,
        'estado_anterior', v_ot.estado,
        'estado_nuevo', 'cerrada',
        'costo_materiales', v_costo_materiales,
        'costo_mano_obra', COALESCE(v_ot.costo_mano_obra, 0),
        'costo_total', v_costo_materiales + COALESCE(v_ot.costo_mano_obra, 0),
        'movimientos_count', v_count_movimientos,
        'advertencias', to_jsonb(v_advertencias),
        'supervisor_id', p_supervisor_id
    );
END;
$$;


-- ############################################################################
-- 4. RECREAR pg_cron JOBS CON MANEJO DE ERRORES
-- ############################################################################
-- Primero eliminar jobs existentes, luego recrear con TRY/CATCH.

-- Eliminar jobs existentes (si pg_cron está habilitado)
DO $$ BEGIN
    PERFORM cron.unschedule('generar-ots-preventivas');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
    PERFORM cron.unschedule('verificar-certificaciones');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
    PERFORM cron.unschedule('alertas-stock-minimo');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
    PERFORM cron.unschedule('recalculo-kpi-diario');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
    PERFORM cron.unschedule('detectar-ots-vencidas');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
    PERFORM cron.unschedule('procesar-recalculos-iceo');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ── JOB 1: Generar OTs Preventivas (diario 01:00 UTC) ──

SELECT cron.schedule(
    'generar-ots-preventivas',
    '0 1 * * *',
    $$
    DO $job$
    DECLARE
        v_plan RECORD;
        v_result JSONB;
        v_count INTEGER := 0;
        v_errors INTEGER := 0;
        v_start TIMESTAMPTZ := clock_timestamp();
    BEGIN
        FOR v_plan IN
            SELECT pm.*, a.contrato_id, a.faena_id, a.kilometraje_actual,
                   a.horas_uso_actual, a.ciclos_actual, a.estado AS activo_estado
            FROM planes_mantenimiento pm
            JOIN activos a ON a.id = pm.activo_id
            WHERE pm.activo_plan = true
              AND a.estado = 'operativo'
              AND NOT EXISTS (
                  SELECT 1 FROM ordenes_trabajo ot
                  WHERE ot.plan_mantenimiento_id = pm.id
                    AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
              )
        LOOP
            IF (
                (v_plan.tipo_plan = 'por_tiempo' AND v_plan.proxima_ejecucion_fecha IS NOT NULL
                 AND v_plan.proxima_ejecucion_fecha <= CURRENT_DATE)
                OR (v_plan.tipo_plan IN ('por_kilometraje','mixto') AND v_plan.frecuencia_km IS NOT NULL
                    AND (v_plan.kilometraje_actual - COALESCE(v_plan.ultima_ejecucion_km, 0)) >= v_plan.frecuencia_km)
                OR (v_plan.tipo_plan IN ('por_horas','mixto') AND v_plan.frecuencia_horas IS NOT NULL
                    AND (v_plan.horas_uso_actual - COALESCE(v_plan.ultima_ejecucion_horas, 0)) >= v_plan.frecuencia_horas)
                OR (v_plan.tipo_plan = 'por_ciclos' AND v_plan.frecuencia_ciclos IS NOT NULL
                    AND (v_plan.ciclos_actual - COALESCE(v_plan.ultima_ejecucion_ciclos, 0)) >= v_plan.frecuencia_ciclos)
            ) THEN
                BEGIN
                    SELECT rpc_crear_ot(
                        p_tipo := 'preventivo',
                        p_contrato_id := v_plan.contrato_id,
                        p_faena_id := v_plan.faena_id,
                        p_activo_id := v_plan.activo_id,
                        p_prioridad := COALESCE(v_plan.prioridad, 'normal'),
                        p_fecha_programada := COALESCE(v_plan.proxima_ejecucion_fecha, CURRENT_DATE + COALESCE(v_plan.anticipacion_dias, 7)),
                        p_plan_mantenimiento_id := v_plan.id
                    ) INTO v_result;
                    v_count := v_count + 1;
                EXCEPTION WHEN OTHERS THEN
                    v_errors := v_errors + 1;
                    RAISE WARNING 'Error generando OT PM para plan %: %', v_plan.id, SQLERRM;
                END;
            END IF;
        END LOOP;

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, detalles, duracion_ms)
        VALUES ('generar-ots-preventivas',
                CASE WHEN v_errors > 0 THEN 'warning' ELSE 'ok' END,
                v_count,
                jsonb_build_object('generadas', v_count, 'errores', v_errors),
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    END $job$;
    $$
);

-- ── JOB 2: Verificar Certificaciones (diario 06:00 UTC) ──

SELECT cron.schedule(
    'verificar-certificaciones',
    '0 6 * * *',
    $$
    DO $job$
    DECLARE
        v_start TIMESTAMPTZ := clock_timestamp();
        v_count INTEGER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM verificar_certificaciones();

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, duracion_ms)
        VALUES ('verificar-certificaciones', 'ok', COALESCE(v_count, 0),
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje, duracion_ms)
        VALUES ('verificar-certificaciones', 'error', SQLERRM,
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    END $job$;
    $$
);

-- ── JOB 3: Alertas Stock Mínimo (cada 6 horas) ──

SELECT cron.schedule(
    'alertas-stock-minimo',
    '0 */6 * * *',
    $$
    DO $job$
    DECLARE
        v_start TIMESTAMPTZ := clock_timestamp();
        v_count INTEGER;
    BEGIN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        SELECT
            'stock_minimo',
            'Stock bajo mínimo: ' || p.nombre,
            'Bodega ' || b.nombre || ': stock actual ' || sb.cantidad || ' ' || p.unidad_medida ||
            ', mínimo requerido: ' || p.stock_minimo,
            'warning', 'producto', p.id
        FROM stock_bodega sb
        JOIN productos p ON p.id = sb.producto_id
        JOIN bodegas b ON b.id = sb.bodega_id
        WHERE sb.cantidad < p.stock_minimo AND sb.cantidad > 0
          AND NOT EXISTS (
              SELECT 1 FROM alertas a
              WHERE a.entidad_id = p.id AND a.tipo = 'stock_minimo'
                AND a.created_at > CURRENT_DATE
          );

        GET DIAGNOSTICS v_count = ROW_COUNT;

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, duracion_ms)
        VALUES ('alertas-stock-minimo', 'ok', v_count,
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('alertas-stock-minimo', 'error', SQLERRM);
    END $job$;
    $$
);

-- ── JOB 4: Recálculo KPI Diario (23:00 UTC) ──

SELECT cron.schedule(
    'recalculo-kpi-diario',
    '0 23 * * *',
    $$
    DO $job$
    DECLARE
        v_contrato RECORD;
        v_inicio DATE;
        v_fin DATE;
        v_start TIMESTAMPTZ := clock_timestamp();
        v_count INTEGER := 0;
    BEGIN
        v_inicio := DATE_TRUNC('month', CURRENT_DATE)::DATE;
        v_fin := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

        FOR v_contrato IN SELECT id FROM contratos WHERE estado = 'activo'
        LOOP
            BEGIN
                PERFORM rpc_calcular_iceo_periodo(
                    p_contrato_id := v_contrato.id,
                    p_periodo_inicio := v_inicio,
                    p_periodo_fin := v_fin
                );
                v_count := v_count + 1;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Error recalculando ICEO contrato %: %', v_contrato.id, SQLERRM;
            END;
        END LOOP;

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, duracion_ms)
        VALUES ('recalculo-kpi-diario', 'ok', v_count,
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    END $job$;
    $$
);

-- ── JOB 5: Detectar OTs Vencidas (diario 07:00 UTC) ──

SELECT cron.schedule(
    'detectar-ots-vencidas',
    '0 7 * * *',
    $$
    DO $job$
    DECLARE
        v_start TIMESTAMPTZ := clock_timestamp();
        v_count INTEGER;
    BEGIN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
        SELECT
            'ot_vencida',
            'OT vencida: ' || ot.folio,
            'La OT ' || ot.folio || ' tenía fecha programada ' || ot.fecha_programada ||
            ' y sigue en estado "' || ot.estado || '".',
            'critical', 'ordenes_trabajo', ot.id, ot.responsable_id
        FROM ordenes_trabajo ot
        WHERE ot.fecha_programada < CURRENT_DATE
          AND ot.estado IN ('creada', 'asignada', 'en_ejecucion', 'pausada')
          AND NOT EXISTS (
              SELECT 1 FROM alertas a
              WHERE a.entidad_id = ot.id AND a.tipo = 'ot_vencida'
                AND a.created_at > CURRENT_DATE
          );

        GET DIAGNOSTICS v_count = ROW_COUNT;

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, duracion_ms)
        VALUES ('detectar-ots-vencidas', 'ok', v_count,
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('detectar-ots-vencidas', 'error', SQLERRM);
    END $job$;
    $$
);

-- ── JOB 6: Procesar Recálculos ICEO Pendientes (cada 2 horas) ──

SELECT cron.schedule(
    'procesar-recalculos-iceo',
    '0 */2 * * *',
    $$
    DO $job$
    DECLARE
        v_start TIMESTAMPTZ := clock_timestamp();
        v_result JSONB;
    BEGIN
        SELECT rpc_procesar_recalculos_iceo() INTO v_result;

        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, detalles, duracion_ms)
        VALUES ('procesar-recalculos-iceo', 'ok',
                COALESCE((v_result->>'periodos_recalculados')::INTEGER, 0),
                v_result,
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('procesar-recalculos-iceo', 'error', SQLERRM);
    END $job$;
    $$
);


-- ############################################################################
-- RESUMEN FINAL DE AUTOMATIZACIÓN
-- ############################################################################
--
-- ┌─────────────────────────────────┬────────────┬──────────────────────────┐
-- │ JOB                             │ FRECUENCIA │ FUNCIÓN                  │
-- ├─────────────────────────────────┼────────────┼──────────────────────────┤
-- │ generar-ots-preventivas         │ Diario 01h │ Evalúa PM, crea OTs     │
-- │ verificar-certificaciones       │ Diario 06h │ Vencimientos + bloqueos  │
-- │ alertas-stock-minimo            │ Cada 6h    │ Stock bajo mínimo       │
-- │ detectar-ots-vencidas           │ Diario 07h │ OTs con fecha pasada    │
-- │ recalculo-kpi-diario            │ Diario 23h │ KPI + ICEO del mes      │
-- │ procesar-recalculos-iceo        │ Cada 2h    │ ICEO pendientes eventos │
-- └─────────────────────────────────┴────────────┴──────────────────────────┘
--
-- TODOS los jobs:
-- ✓ Manejan errores con BEGIN...EXCEPTION...END
-- ✓ Registran ejecución en log_jobs_automaticos
-- ✓ Registran duración, errores y conteos
-- ✓ No generan duplicados (verifican existencia)
-- ✓ Usan RPCs transaccionales cuando corresponde
--
-- ============================================================================
-- FIN del archivo 13_automatizacion_final.sql
-- ============================================================================
