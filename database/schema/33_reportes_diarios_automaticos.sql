-- ============================================================================
-- SICOM-ICEO | Migración 33 — Reportes Diarios Automáticos
-- ============================================================================
-- Propósito : Generar y almacenar snapshots diarios agregados para que cada
--             perfil (Operaciones, Mantenimiento, Comercial, Prevención,
--             Gerencia) tenga su reporte listo cada mañana sin tener que
--             recalcular al abrir el dashboard.
--
-- Diseño:
--   * Una función principal fn_generar_reporte_diario(fecha) que arma el
--     JSON completo del día.
--   * Una tabla reportes_diarios_snapshot que guarda los JSONs históricos.
--   * Un cron diario a las 06:30 Chile que guarda el snapshot.
--   * Vistas auxiliares para cada perfil que consumen el JSON.
--
-- Los reportes se ven en /dashboard/reporte-diario y se pueden exportar.
-- ============================================================================

-- ============================================================================
-- 1. TABLA DE SNAPSHOTS HISTÓRICOS
-- ============================================================================

CREATE TABLE IF NOT EXISTS reportes_diarios_snapshot (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    fecha           DATE        NOT NULL UNIQUE,
    payload         JSONB       NOT NULL,
    generado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    generado_por    UUID        REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_reportes_snap_fecha ON reportes_diarios_snapshot (fecha DESC);

COMMENT ON TABLE reportes_diarios_snapshot IS
    'Snapshots diarios pre-calculados del estado operacional completo del servicio.';

-- ============================================================================
-- 2. FUNCIÓN GENERADORA DEL REPORTE DIARIO
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_generar_reporte_diario(
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_payload JSONB;
    v_inicio_mes DATE := date_trunc('month', p_fecha)::DATE;
BEGIN
    -- Construir el JSON completo
    SELECT jsonb_build_object(
        'fecha', p_fecha,
        'generado_en', NOW(),

        -- ── SECCIÓN FLOTA ────────────────────────────────────
        'flota', jsonb_build_object(
            'total_equipos', (
                SELECT COUNT(*) FROM activos WHERE estado != 'dado_baja'
                  AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
            ),
            'por_estado_hoy', (
                SELECT jsonb_object_agg(estado_codigo, cantidad)
                FROM (
                    SELECT estado_codigo, COUNT(*)::INTEGER AS cantidad
                    FROM estado_diario_flota
                    WHERE fecha = p_fecha
                    GROUP BY estado_codigo
                ) s
            ),
            'por_operacion', (
                SELECT jsonb_object_agg(COALESCE(operacion,'Sin asignar'), cantidad)
                FROM (
                    SELECT operacion, COUNT(*)::INTEGER AS cantidad
                    FROM activos
                    WHERE estado != 'dado_baja'
                    GROUP BY operacion
                ) s
            ),
            'cambios_24h', (
                SELECT COUNT(*)
                FROM estado_diario_flota
                WHERE fecha = p_fecha
                  AND override_manual = true
                  AND actualizado_at >= NOW() - INTERVAL '24 hours'
            )
        ),

        -- ── SECCIÓN OEE (mes corriente) ──────────────────────
        'oee_mes', (
            SELECT jsonb_build_object(
                'total', (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, NULL) t),
                'coquimbo', (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Coquimbo') t),
                'calama', (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Calama') t)
            )
        ),

        -- ── SECCIÓN MANTENIMIENTO ────────────────────────────
        'mantenimiento', jsonb_build_object(
            'ots_abiertas', (
                SELECT COUNT(*) FROM ordenes_trabajo
                WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada')
            ),
            'ots_creadas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo
                WHERE created_at::DATE = p_fecha - 1
            ),
            'ots_cerradas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo
                WHERE fecha_termino::DATE = p_fecha - 1
            ),
            'por_prioridad', (
                SELECT jsonb_object_agg(prioridad, cantidad)
                FROM (
                    SELECT prioridad, COUNT(*)::INTEGER AS cantidad
                    FROM ordenes_trabajo
                    WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada')
                    GROUP BY prioridad
                ) s
            ),
            'tipo_correctivo_abierto', (
                SELECT COUNT(*) FROM ordenes_trabajo
                WHERE tipo = 'correctivo'
                  AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada')
            )
        ),

        -- ── SECCIÓN COMERCIAL ────────────────────────────────
        'comercial', jsonb_build_object(
            'arrendados', (
                SELECT COUNT(*) FROM estado_diario_flota
                WHERE fecha = p_fecha AND estado_codigo = 'A'
            ),
            'disponibles_perdida', (
                SELECT COUNT(*) FROM estado_diario_flota
                WHERE fecha = p_fecha AND estado_codigo = 'D'
            ),
            'uso_interno', (
                SELECT COUNT(*) FROM estado_diario_flota
                WHERE fecha = p_fecha AND estado_codigo = 'U'
            ),
            'leasing', (
                SELECT COUNT(*) FROM estado_diario_flota
                WHERE fecha = p_fecha AND estado_codigo = 'L'
            ),
            'por_cliente', (
                SELECT jsonb_object_agg(COALESCE(cliente,'Sin cliente'), cantidad)
                FROM (
                    SELECT cliente, COUNT(*)::INTEGER AS cantidad
                    FROM estado_diario_flota
                    WHERE fecha = p_fecha AND estado_codigo = 'A'
                    GROUP BY cliente
                ) s
            )
        ),

        -- ── SECCIÓN PREVENCIÓN / NORMATIVA ───────────────────
        'prevencion', (
            SELECT to_jsonb(v) FROM vw_prevencion_resumen v
        ),

        -- ── SECCIÓN ALERTAS CRÍTICAS ─────────────────────────
        'alertas', jsonb_build_object(
            'criticas_activas', (
                SELECT COUNT(*) FROM alertas
                WHERE severidad = 'critical' AND leida = false
            ),
            'total_activas', (
                SELECT COUNT(*) FROM alertas WHERE leida = false
            )
        ),

        -- ── SECCIÓN CUMPLIMIENTO RESPEL ──────────────────────
        'respel_mes', jsonb_build_object(
            'generado_kg', (
                SELECT COALESCE(SUM(cantidad), 0)
                FROM respel_movimientos
                WHERE tipo_movimiento = 'generacion'
                  AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'retirado_kg', (
                SELECT COALESCE(SUM(cantidad), 0)
                FROM respel_movimientos
                WHERE tipo_movimiento = 'retiro'
                  AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'pendientes_sidrep', (
                SELECT COUNT(*) FROM respel_movimientos
                WHERE tipo_movimiento = 'retiro' AND numero_sidrep IS NULL
            )
        )
    )
    INTO v_payload;

    RETURN v_payload;
END;
$$;

COMMENT ON FUNCTION fn_generar_reporte_diario(DATE) IS
    'Genera un JSON completo con los indicadores del día para todas las áreas.';

-- ============================================================================
-- 3. FUNCIÓN: GUARDAR SNAPSHOT
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_guardar_reporte_diario(
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_payload JSONB;
    v_id UUID;
    v_actor UUID;
BEGIN
    -- auth.uid() puede ser NULL cuando se ejecuta desde pg_cron
    BEGIN
        v_actor := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_actor := NULL;
    END;

    v_payload := fn_generar_reporte_diario(p_fecha);

    INSERT INTO reportes_diarios_snapshot (fecha, payload, generado_por)
    VALUES (p_fecha, v_payload, v_actor)
    ON CONFLICT (fecha) DO UPDATE
    SET payload = EXCLUDED.payload,
        generado_en = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ============================================================================
-- 4. CRON: ejecutar cada día a las 06:30 Chile (09:30 UTC)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule('reporte_diario_snapshot')
        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reporte_diario_snapshot');

        PERFORM cron.schedule(
            'reporte_diario_snapshot',
            '30 9 * * *',  -- 09:30 UTC = ~06:30 Chile
            $job$ SELECT fn_guardar_reporte_diario(CURRENT_DATE); $job$
        );
    END IF;
END $$;

-- ============================================================================
-- 5. EJECUCIÓN INICIAL: generar snapshot del día actual
-- ============================================================================

SELECT fn_guardar_reporte_diario(CURRENT_DATE);
