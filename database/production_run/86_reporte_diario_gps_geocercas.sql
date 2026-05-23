-- ============================================================================
-- 86_reporte_diario_gps_geocercas.sql
-- ----------------------------------------------------------------------------
-- Extiende fn_generar_reporte_diario (MIG33) para incluir secciones de:
--   - gps: cobertura, sin señal, en movimiento, batería baja
--   - geocercas: ocupación actual, eventos del día, activos fuera de zona esperada
--   - cobertura_pm: porcentaje activos con plan preventivo asignado
--   - flota_kpi: snapshot del KPI agregado v_flota_kpi_resumen
--
-- Conserva todas las secciones previas (flota, oee_mes, mantenimiento,
-- comercial, prevencion, alertas, respel_mes).
--
-- ADITIVA, IDEMPOTENTE. Reemplaza la funcion in-place (mismo signature).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_generar_reporte_diario(p_fecha date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_payload     JSONB;
    v_inicio_mes  DATE := date_trunc('month', p_fecha)::DATE;
    v_inicio_dia  TIMESTAMPTZ := (p_fecha::TIMESTAMP)::TIMESTAMPTZ;
    v_fin_dia     TIMESTAMPTZ := ((p_fecha + 1)::TIMESTAMP)::TIMESTAMPTZ;
BEGIN
    SELECT jsonb_build_object(
        'fecha', p_fecha,
        'generado_en', NOW(),

        -- ── FLOTA ─────────────────────────────────────────────────────────
        'flota', jsonb_build_object(
            'total_equipos', (
                SELECT COUNT(*) FROM activos WHERE estado != 'dado_baja'
                  AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
            ),
            'por_estado_hoy', (
                SELECT jsonb_object_agg(estado_codigo, cantidad)
                FROM (SELECT estado_codigo, COUNT(*)::INTEGER AS cantidad
                        FROM estado_diario_flota WHERE fecha = p_fecha
                        GROUP BY estado_codigo) s
            ),
            'por_operacion', (
                SELECT jsonb_object_agg(COALESCE(operacion,'Sin asignar'), cantidad)
                FROM (SELECT operacion, COUNT(*)::INTEGER AS cantidad
                        FROM activos WHERE estado != 'dado_baja' GROUP BY operacion) s
            ),
            'cambios_24h', (
                SELECT COUNT(*) FROM estado_diario_flota
                 WHERE fecha = p_fecha AND override_manual = true
                   AND actualizado_at >= NOW() - INTERVAL '24 hours'
            )
        ),

        -- ── OEE (mes corriente) ──────────────────────────────────────────
        'oee_mes', (
            SELECT jsonb_build_object(
                'total',    (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, NULL) t),
                'coquimbo', (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Coquimbo') t),
                'calama',   (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Calama') t)
            )
        ),

        -- ── MANTENIMIENTO ────────────────────────────────────────────────
        'mantenimiento', jsonb_build_object(
            'ots_abiertas', (
                SELECT COUNT(*) FROM ordenes_trabajo
                 WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
            ),
            'ots_creadas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo WHERE created_at::DATE = p_fecha - 1
            ),
            'ots_cerradas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo WHERE fecha_termino::DATE = p_fecha - 1
            ),
            'por_prioridad', (
                SELECT jsonb_object_agg(prioridad, cantidad)
                FROM (SELECT prioridad, COUNT(*)::INTEGER AS cantidad
                        FROM ordenes_trabajo
                       WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
                       GROUP BY prioridad) s
            ),
            'tipo_correctivo_abierto', (
                SELECT COUNT(*) FROM ordenes_trabajo
                 WHERE tipo = 'correctivo'
                   AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
            )
        ),

        -- ── COBERTURA PM (NUEVO MIG86) ───────────────────────────────────
        'cobertura_pm', (
            SELECT to_jsonb(v) FROM v_mantenimiento_cobertura_resumen v
        ),

        -- ── COMERCIAL ────────────────────────────────────────────────────
        'comercial', jsonb_build_object(
            'arrendados',          (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'A'),
            'disponibles_perdida', (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'D'),
            'uso_interno',         (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'U'),
            'leasing',             (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'L'),
            'por_cliente', (
                SELECT jsonb_object_agg(COALESCE(cliente,'Sin cliente'), cantidad)
                FROM (SELECT cliente, COUNT(*)::INTEGER AS cantidad
                        FROM estado_diario_flota
                       WHERE fecha = p_fecha AND estado_codigo = 'A'
                       GROUP BY cliente) s
            )
        ),

        -- ── PREVENCION ───────────────────────────────────────────────────
        'prevencion', (
            SELECT to_jsonb(v) FROM vw_prevencion_resumen v
        ),

        -- ── ALERTAS ──────────────────────────────────────────────────────
        'alertas', jsonb_build_object(
            'criticas_activas', (
                SELECT COUNT(*) FROM alertas WHERE severidad = 'critical' AND leida = false
            ),
            'total_activas', (SELECT COUNT(*) FROM alertas WHERE leida = false),
            'por_entidad_tipo', (
                SELECT jsonb_object_agg(COALESCE(entidad_tipo,'sin_entidad'), cantidad)
                FROM (SELECT entidad_tipo, COUNT(*)::INTEGER AS cantidad
                        FROM alertas WHERE leida = false
                        GROUP BY entidad_tipo) s
            )
        ),

        -- ── RESPEL ───────────────────────────────────────────────────────
        'respel_mes', jsonb_build_object(
            'generado_kg', (
                SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
                 WHERE tipo_movimiento = 'generacion'
                   AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'retirado_kg', (
                SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
                 WHERE tipo_movimiento = 'retiro'
                   AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'pendientes_sidrep', (
                SELECT COUNT(*) FROM respel_movimientos
                 WHERE tipo_movimiento = 'retiro' AND numero_sidrep IS NULL
            )
        ),

        -- ── GPS (NUEVO MIG86) ────────────────────────────────────────────
        'gps', jsonb_build_object(
            'mapeados',             (SELECT gps_mapeados            FROM v_flota_kpi_resumen),
            'sin_gps',              (SELECT sin_gps                 FROM v_flota_kpi_resumen),
            'sin_senal_24h',        (SELECT gps_sin_senal_24h       FROM v_flota_kpi_resumen),
            'en_ruta',              (SELECT gps_en_ruta             FROM v_flota_kpi_resumen),
            'detenido_motor_on',    (SELECT gps_detenido_motor_on   FROM v_flota_kpi_resumen),
            'detenido',             (SELECT gps_detenido            FROM v_flota_kpi_resumen),
            'offline',              (SELECT gps_offline             FROM v_flota_kpi_resumen),
            'bateria_baja_count', (
                SELECT COUNT(*) FROM gps_estado_actual
                 WHERE bateria_pct IS NOT NULL AND bateria_pct < 20
            ),
            'eventos_log_24h', (
                SELECT COUNT(*) FROM gps_eventos_log
                 WHERE ts_gps >= v_inicio_dia AND ts_gps < v_fin_dia
            )
        ),

        -- ── GEOCERCAS (NUEVO MIG86) ──────────────────────────────────────
        'geocercas', jsonb_build_object(
            'total_activas',         (SELECT COUNT(*) FROM gps_geocercas WHERE activo = true),
            'en_zona_esperada',      (SELECT en_zona_esperada       FROM v_flota_kpi_resumen),
            'fuera_zona_esperada',   (SELECT fuera_zona_esperada    FROM v_flota_kpi_resumen),
            'sin_dato_zona',         (SELECT sin_dato_zona          FROM v_flota_kpi_resumen),
            'eventos_dia', jsonb_build_object(
                'total',    (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia),
                'entradas', (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia AND tipo_evento = 'entrada'),
                'salidas',  (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia AND tipo_evento = 'salida')
            ),
            'ocupacion_actual', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'geocerca', geocerca_nombre,
                    'tipo',     geocerca_tipo,
                    'activos_dentro', activos_dentro
                ) ORDER BY activos_dentro DESC), '[]'::jsonb)
                FROM (
                    SELECT geocerca_nombre,
                           geocerca_tipo::text AS geocerca_tipo,
                           COUNT(*)::INTEGER  AS activos_dentro
                      FROM v_geocerca_ocupacion
                     GROUP BY geocerca_nombre, geocerca_tipo
                ) s
            ),
            'fuera_de_zona_detalle', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'activo_codigo', activo_codigo,
                    'patente',       patente,
                    'cliente',       contrato_cliente,
                    'geocerca_esperada', geocerca_esperada,
                    'gps_estado_pin', gps_estado_pin
                )), '[]'::jsonb)
                  FROM v_flota_dashboard_unificado
                 WHERE en_zona_esperada = false
            )
        ),

        -- ── FLOTA KPI consolidado (NUEVO MIG86) ──────────────────────────
        'flota_kpi', (SELECT to_jsonb(k) FROM v_flota_kpi_resumen k)
    )
    INTO v_payload;

    RETURN v_payload;
END;
$$;


GRANT EXECUTE ON FUNCTION fn_generar_reporte_diario(date) TO authenticated;


-- ── Regenera el snapshot del dia para que el reporte ya tenga la nueva data ─
DO $$
DECLARE v_id UUID;
BEGIN
    SELECT fn_guardar_reporte_diario(CURRENT_DATE) INTO v_id;
    RAISE NOTICE '== MIG86 OK ==';
    RAISE NOTICE '   fn_generar_reporte_diario extendida con secciones gps + geocercas + cobertura_pm + flota_kpi';
    RAISE NOTICE '   snapshot regenerado para hoy (id=%)', v_id;
END $$;

-- Mostrar las nuevas secciones del snapshot regenerado
SELECT
    payload->'gps'        AS gps,
    payload->'geocercas'  AS geocercas_kpi,
    payload->'cobertura_pm' AS cobertura_pm
FROM reportes_diarios_snapshot
WHERE fecha = CURRENT_DATE;

NOTIFY pgrst, 'reload schema';
