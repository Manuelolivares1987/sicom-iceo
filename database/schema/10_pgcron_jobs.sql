-- SICOM-ICEO | Tareas Programadas (pg_cron)
-- ============================================================================
-- PREREQUISITO: Habilitar pg_cron en Supabase Dashboard > Database > Extensions
-- ============================================================================

-- ============================================================================
-- 1. GENERAR OTs PREVENTIVAS (diario a las 01:00 UTC)
-- ============================================================================
-- Evalúa todos los planes de mantenimiento activos y genera OTs automáticas
-- para aquellos que hayan alcanzado su condición de disparo (tiempo, km, hrs, ciclos).
-- Usa la función rpc_crear_ot para garantizar atomicidad.

SELECT cron.schedule(
    'generar-ots-preventivas',
    '0 1 * * *',  -- Todos los días a la 01:00 UTC
    $$
    DO $job$
    DECLARE
        v_plan RECORD;
        v_result JSONB;
        v_count INTEGER := 0;
        v_activo RECORD;
    BEGIN
        FOR v_plan IN
            SELECT pm.*, a.contrato_id, a.faena_id, a.kilometraje_actual, a.horas_uso_actual, a.ciclos_actual
            FROM planes_mantenimiento pm
            JOIN activos a ON a.id = pm.activo_id
            WHERE pm.activo_plan = true
              AND a.estado = 'operativo'
              -- No generar si ya existe OT abierta para este plan
              AND NOT EXISTS (
                  SELECT 1 FROM ordenes_trabajo ot
                  WHERE ot.plan_mantenimiento_id = pm.id
                    AND ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada', 'cancelada')
              )
        LOOP
            -- Evaluar condición de disparo
            IF (
                (pm.tipo_plan = 'por_tiempo' AND pm.proxima_ejecucion_fecha IS NOT NULL AND pm.proxima_ejecucion_fecha <= CURRENT_DATE)
                OR (pm.tipo_plan = 'por_kilometraje' AND pm.frecuencia_km IS NOT NULL AND
                    (v_plan.kilometraje_actual - COALESCE(pm.ultima_ejecucion_km, 0)) >= pm.frecuencia_km)
                OR (pm.tipo_plan = 'por_horas' AND pm.frecuencia_horas IS NOT NULL AND
                    (v_plan.horas_uso_actual - COALESCE(pm.ultima_ejecucion_horas, 0)) >= pm.frecuencia_horas)
                OR (pm.tipo_plan = 'por_ciclos' AND pm.frecuencia_ciclos IS NOT NULL AND
                    (v_plan.ciclos_actual - COALESCE(pm.ultima_ejecucion_ciclos, 0)) >= pm.frecuencia_ciclos)
                OR (pm.tipo_plan = 'mixto' AND (
                    (pm.proxima_ejecucion_fecha IS NOT NULL AND pm.proxima_ejecucion_fecha <= CURRENT_DATE)
                    OR (pm.frecuencia_km IS NOT NULL AND (v_plan.kilometraje_actual - COALESCE(pm.ultima_ejecucion_km, 0)) >= pm.frecuencia_km)
                    OR (pm.frecuencia_horas IS NOT NULL AND (v_plan.horas_uso_actual - COALESCE(pm.ultima_ejecucion_horas, 0)) >= pm.frecuencia_horas)
                ))
            ) THEN
                -- Crear OT preventiva via RPC
                SELECT rpc_crear_ot(
                    p_tipo := 'preventivo',
                    p_contrato_id := v_plan.contrato_id,
                    p_faena_id := v_plan.faena_id,
                    p_activo_id := pm.activo_id,
                    p_prioridad := COALESCE(pm.prioridad, 'normal'),
                    p_fecha_programada := COALESCE(pm.proxima_ejecucion_fecha, CURRENT_DATE + COALESCE(pm.anticipacion_dias, 7)),
                    p_plan_mantenimiento_id := pm.id
                ) INTO v_result;

                v_count := v_count + 1;

                -- Generar alerta
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
                VALUES (
                    'ot_vencida',
                    'OT preventiva generada: ' || (v_result->>'folio'),
                    'Se generó automáticamente OT para plan PM del activo ' || pm.activo_id,
                    'info', 'ordenes_trabajo', (v_result->>'id')::UUID
                );
            END IF;
        END LOOP;

        RAISE NOTICE 'OTs preventivas generadas: %', v_count;
    END $job$;
    $$
);

-- ============================================================================
-- 2. VERIFICAR CERTIFICACIONES VENCIDAS (diario a las 06:00 UTC)
-- ============================================================================
-- Actualiza estados de certificaciones y genera alertas.
-- Bloquea activos si certificación bloqueante está vencida.

SELECT cron.schedule(
    'verificar-certificaciones',
    '0 6 * * *',  -- Todos los días a las 06:00 UTC
    $$
    SELECT verificar_certificaciones();
    $$
);

-- ============================================================================
-- 3. ALERTAS DE STOCK MÍNIMO (cada 6 horas)
-- ============================================================================
-- Revisa productos con stock bajo el mínimo y genera alertas.

SELECT cron.schedule(
    'alertas-stock-minimo',
    '0 */6 * * *',  -- Cada 6 horas
    $$
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
    SELECT
        'stock_minimo',
        'Stock bajo mínimo: ' || p.nombre,
        'Bodega ' || b.nombre || ': stock actual ' || sb.cantidad || ' ' || p.unidad_medida ||
        ', mínimo requerido: ' || p.stock_minimo,
        'warning',
        'producto',
        p.id
    FROM stock_bodega sb
    JOIN productos p ON p.id = sb.producto_id
    JOIN bodegas b ON b.id = sb.bodega_id
    WHERE sb.cantidad < p.stock_minimo
      AND sb.cantidad > 0
      -- No duplicar alertas del mismo día
      AND NOT EXISTS (
          SELECT 1 FROM alertas a
          WHERE a.entidad_id = p.id
            AND a.tipo = 'stock_minimo'
            AND a.created_at > CURRENT_DATE
      );
    $$
);

-- ============================================================================
-- 4. RECÁLCULO KPI DIARIO (cada noche a las 23:00 UTC)
-- ============================================================================
-- Para cada contrato activo, recalcula los KPIs del mes en curso.
-- Esto mantiene el dashboard actualizado sin esperar cierre de período.

SELECT cron.schedule(
    'recalculo-kpi-diario',
    '0 23 * * *',  -- Todos los días a las 23:00 UTC
    $$
    DO $job$
    DECLARE
        v_contrato RECORD;
        v_inicio DATE;
        v_fin DATE;
    BEGIN
        v_inicio := DATE_TRUNC('month', CURRENT_DATE)::DATE;
        v_fin := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

        FOR v_contrato IN
            SELECT id FROM contratos WHERE estado = 'activo'
        LOOP
            PERFORM rpc_calcular_iceo_periodo(
                p_contrato_id := v_contrato.id,
                p_periodo_inicio := v_inicio,
                p_periodo_fin := v_fin
            );
        END LOOP;
    END $job$;
    $$
);

-- ============================================================================
-- 5. DETECTAR OTs VENCIDAS (diario a las 07:00 UTC)
-- ============================================================================
-- OTs con fecha_programada pasada que siguen en estados no terminales.

SELECT cron.schedule(
    'detectar-ots-vencidas',
    '0 7 * * *',  -- Todos los días a las 07:00 UTC
    $$
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
    SELECT
        'ot_vencida',
        'OT vencida: ' || ot.folio,
        'La OT ' || ot.folio || ' tenía fecha programada ' || ot.fecha_programada || ' y sigue en estado "' || ot.estado || '".',
        'critical',
        'ordenes_trabajo',
        ot.id,
        ot.responsable_id
    FROM ordenes_trabajo ot
    WHERE ot.fecha_programada < CURRENT_DATE
      AND ot.estado IN ('creada', 'asignada', 'en_ejecucion', 'pausada')
      -- No duplicar alertas del mismo día
      AND NOT EXISTS (
          SELECT 1 FROM alertas a
          WHERE a.entidad_id = ot.id
            AND a.tipo = 'ot_vencida'
            AND a.created_at > CURRENT_DATE
      );
    $$
);

-- ============================================================================
-- VERIFICAR JOBS CREADOS
-- ============================================================================
-- Ejecutar para confirmar que los jobs se crearon correctamente:
-- SELECT * FROM cron.job ORDER BY jobid;
