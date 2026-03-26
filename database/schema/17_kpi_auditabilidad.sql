-- SICOM-ICEO | KPI Auditabilidad + Performance + Drill-down
-- ============================================================================
-- Ejecutar DESPUÉS de 16.
--
-- 1. Vistas materializadas para datos base de KPI
-- 2. Mejora datos_calculo con fuentes trazables
-- 3. RPC de drill-down por KPI
-- 4. Vista de snapshot mensual
-- ============================================================================


-- ############################################################################
-- 1. VISTAS MATERIALIZADAS PARA DATOS BASE DE KPI
-- ############################################################################
-- Estas vistas pre-agregan los datos operacionales que alimentan los KPIs.
-- Se refrescan cada hora o bajo demanda.

-- ── VM: Base para KPIs de OT (cumplimiento PM, backlog, MTTR) ──

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_ot_stats_periodo AS
SELECT
    ot.contrato_id,
    ot.faena_id,
    DATE_TRUNC('month', COALESCE(ot.fecha_programada, ot.created_at))::DATE AS periodo,
    ot.tipo,
    -- Para activos fijos vs móviles
    a.tipo AS activo_tipo,
    CASE
        WHEN a.tipo IN ('punto_fijo','surtidor','dispensador','estanque','bomba','manguera') THEN 'fijo'
        WHEN a.tipo IN ('punto_movil','camion_cisterna','lubrimovil','equipo_bombeo','camioneta','camion') THEN 'movil'
        ELSE 'otro'
    END AS categoria_activo,
    -- Contadores
    COUNT(*) AS total_ots,
    COUNT(*) FILTER (WHERE ot.tipo = 'preventivo') AS ots_preventivas,
    COUNT(*) FILTER (WHERE ot.tipo = 'correctivo') AS ots_correctivas,
    COUNT(*) FILTER (WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') AND ot.tipo = 'preventivo') AS pm_ejecutadas,
    COUNT(*) FILTER (WHERE ot.tipo = 'preventivo' AND ot.estado NOT IN ('cancelada')) AS pm_programadas,
    COUNT(*) FILTER (WHERE ot.tipo = 'correctivo' AND ot.estado IN ('creada','asignada','en_ejecucion','pausada')) AS correctivas_abiertas,
    COUNT(*) FILTER (WHERE ot.tipo = 'correctivo') AS correctivas_totales,
    -- MTTR (horas promedio de reparación correctiva)
    AVG(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0)
        FILTER (WHERE ot.tipo = 'correctivo' AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS mttr_horas,
    -- Disponibilidad (horas downtime por correctivos)
    SUM(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0)
        FILTER (WHERE ot.tipo = 'correctivo' AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS horas_downtime
FROM ordenes_trabajo ot
JOIN activos a ON a.id = ot.activo_id
GROUP BY ot.contrato_id, ot.faena_id, periodo, ot.tipo, a.tipo, categoria_activo;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ot_stats
    ON mv_ot_stats_periodo (contrato_id, faena_id, periodo, tipo, activo_tipo);

-- ── VM: Base para KPIs de inventario (exactitud, merma) ──

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_inventario_stats_periodo AS
WITH movs AS (
    SELECT
        b.faena_id,
        b.id AS bodega_id,
        DATE_TRUNC('month', mi.created_at)::DATE AS periodo,
        p.categoria,
        COUNT(*) FILTER (WHERE mi.tipo = 'salida') AS salidas_count,
        COALESCE(SUM(mi.cantidad) FILTER (WHERE mi.tipo = 'salida'), 0) AS volumen_salidas,
        COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = 'salida'), 0) AS valor_salidas,
        COALESCE(SUM(mi.cantidad) FILTER (WHERE mi.tipo = 'merma'), 0) AS volumen_mermas,
        COALESCE(SUM(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = 'merma'), 0) AS valor_mermas,
        COALESCE(SUM(mi.cantidad) FILTER (WHERE mi.tipo = 'entrada'), 0) AS volumen_entradas
    FROM movimientos_inventario mi
    JOIN bodegas b ON b.id = mi.bodega_id
    JOIN productos p ON p.id = mi.producto_id
    GROUP BY b.faena_id, b.id, periodo, p.categoria
),
conteos AS (
    SELECT
        ci.bodega_id,
        DATE_TRUNC('month', ci.created_at)::DATE AS periodo,
        COUNT(*) AS items_contados_total,
        COUNT(*) FILTER (WHERE cd.diferencia = 0) AS items_sin_diferencia
    FROM conteo_detalle cd
    JOIN conteos_inventario ci ON ci.id = cd.conteo_id
    GROUP BY ci.bodega_id, periodo
)
SELECT
    m.faena_id,
    m.periodo,
    m.categoria,
    m.salidas_count,
    m.volumen_salidas,
    m.valor_salidas,
    m.volumen_mermas,
    m.valor_mermas,
    m.volumen_entradas,
    COALESCE(c.items_sin_diferencia, 0) AS items_sin_diferencia,
    COALESCE(c.items_contados_total, 0) AS items_contados_total
FROM movs m
LEFT JOIN conteos c ON c.bodega_id = m.bodega_id AND c.periodo = m.periodo;

-- ── VM: Base para KPIs de certificaciones ──

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_certificaciones_stats AS
SELECT
    a.faena_id,
    a.contrato_id,
    CASE
        WHEN a.tipo IN ('punto_fijo','surtidor','dispensador','estanque','bomba','manguera') THEN 'fijo'
        WHEN a.tipo IN ('punto_movil','camion_cisterna','lubrimovil','equipo_bombeo','camioneta','camion') THEN 'movil'
        ELSE 'otro'
    END AS categoria_activo,
    COUNT(*) AS total_certificaciones,
    COUNT(*) FILTER (WHERE c.estado = 'vigente') AS vigentes,
    COUNT(*) FILTER (WHERE c.estado = 'por_vencer') AS por_vencer,
    COUNT(*) FILTER (WHERE c.estado = 'vencido') AS vencidas,
    COUNT(*) FILTER (WHERE c.tipo = 'calibracion' AND c.estado = 'vigente') AS calibraciones_vigentes,
    COUNT(*) FILTER (WHERE c.tipo = 'calibracion') AS calibraciones_total,
    COUNT(*) FILTER (WHERE c.tipo IN ('revision_tecnica','soap') AND c.estado = 'vigente') AS vehiculares_vigentes,
    COUNT(*) FILTER (WHERE c.tipo IN ('revision_tecnica','soap')) AS vehiculares_total
FROM certificaciones c
JOIN activos a ON a.id = c.activo_id
GROUP BY a.faena_id, a.contrato_id, categoria_activo;

-- ── VM: Base para KPIs de rutas/despacho ──

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_rutas_stats_periodo AS
SELECT
    rd.faena_id,
    rd.contrato_id,
    DATE_TRUNC('month', rd.fecha_programada)::DATE AS periodo,
    COUNT(*) AS rutas_programadas,
    COUNT(*) FILTER (WHERE rd.estado = 'completada') AS rutas_completadas,
    COUNT(*) FILTER (WHERE rd.estado = 'incompleta') AS rutas_incompletas,
    COUNT(*) FILTER (WHERE rd.fecha_ejecucion IS NOT NULL AND rd.fecha_ejecucion <= rd.fecha_programada) AS rutas_a_tiempo,
    COALESCE(SUM(rd.litros_despachados), 0) AS litros_despachados,
    COALESCE(SUM(rd.km_reales), 0) AS km_reales,
    COALESCE(SUM(rd.km_programados), 0) AS km_programados
FROM rutas_despacho rd
GROUP BY rd.faena_id, rd.contrato_id, periodo;

-- ── VM: Base para KPIs de incidentes ──

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_incidentes_stats_periodo AS
SELECT
    i.faena_id,
    i.contrato_id,
    DATE_TRUNC('month', i.fecha_incidente)::DATE AS periodo,
    i.tipo AS tipo_incidente,
    COUNT(*) AS total_incidentes
FROM incidentes i
GROUP BY i.faena_id, i.contrato_id, periodo, i.tipo;


-- ── Función para refrescar todas las MVs ──

CREATE OR REPLACE FUNCTION rpc_refrescar_vistas_kpi()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start TIMESTAMPTZ := clock_timestamp();
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ot_stats_periodo;
    REFRESH MATERIALIZED VIEW mv_inventario_stats_periodo;
    REFRESH MATERIALIZED VIEW mv_certificaciones_stats;
    REFRESH MATERIALIZED VIEW mv_rutas_stats_periodo;
    REFRESH MATERIALIZED VIEW mv_incidentes_stats_periodo;

    RETURN jsonb_build_object(
        'refreshed', true,
        'duration_ms', EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER,
        'views', ARRAY['mv_ot_stats_periodo','mv_inventario_stats_periodo','mv_certificaciones_stats','mv_rutas_stats_periodo','mv_incidentes_stats_periodo']
    );
END;
$$;


-- ############################################################################
-- 2. RPC DRILL-DOWN: DETALLE DE UN KPI ESPECÍFICO
-- ############################################################################
-- Dado un KPI y período, retorna los registros fuente que componen el cálculo.

CREATE OR REPLACE FUNCTION rpc_kpi_drill_down(
    p_kpi_codigo     VARCHAR(10),
    p_contrato_id    UUID,
    p_faena_id       UUID DEFAULT NULL,
    p_periodo_inicio DATE DEFAULT NULL,
    p_periodo_fin    DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_inicio     DATE;
    v_fin        DATE;
    v_kpi        RECORD;
    v_medicion   RECORD;
    v_registros  JSONB;
    v_valor      NUMERIC;
BEGIN
    v_inicio := COALESCE(p_periodo_inicio, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_fin := COALESCE(p_periodo_fin, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE);

    -- Obtener definición del KPI
    SELECT * INTO v_kpi FROM kpi_definiciones WHERE codigo = p_kpi_codigo;
    IF NOT FOUND THEN RAISE EXCEPTION 'KPI no encontrado: %', p_kpi_codigo; END IF;

    -- Obtener medición del período
    SELECT * INTO v_medicion FROM mediciones_kpi
    WHERE kpi_id = v_kpi.id AND contrato_id = p_contrato_id
      AND periodo_inicio = v_inicio;

    -- Obtener registros fuente según el tipo de KPI
    CASE
        -- KPIs basados en OTs (B1, B3, B6, C1, C3, C7)
        WHEN p_kpi_codigo IN ('B1','C1') THEN
            SELECT jsonb_agg(jsonb_build_object(
                'ot_id', ot.id, 'folio', ot.folio, 'tipo', ot.tipo,
                'estado', ot.estado, 'activo_codigo', a.codigo,
                'fecha_programada', ot.fecha_programada,
                'fecha_termino', ot.fecha_termino
            )) INTO v_registros
            FROM ordenes_trabajo ot
            JOIN activos a ON a.id = ot.activo_id
            WHERE ot.tipo = 'preventivo'
              AND ot.contrato_id = p_contrato_id
              AND (p_faena_id IS NULL OR ot.faena_id = p_faena_id)
              AND ot.fecha_programada BETWEEN v_inicio AND v_fin;

        WHEN p_kpi_codigo IN ('B3','C3') THEN -- MTTR
            SELECT jsonb_agg(jsonb_build_object(
                'ot_id', ot.id, 'folio', ot.folio,
                'activo_codigo', a.codigo,
                'fecha_inicio', ot.fecha_inicio,
                'fecha_termino', ot.fecha_termino,
                'horas_reparacion', ROUND(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio))/3600.0, 1)
            )) INTO v_registros
            FROM ordenes_trabajo ot
            JOIN activos a ON a.id = ot.activo_id
            WHERE ot.tipo = 'correctivo'
              AND ot.contrato_id = p_contrato_id
              AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL
              AND ot.fecha_termino BETWEEN v_inicio AND v_fin;

        WHEN p_kpi_codigo IN ('B6','C7') THEN -- Backlog
            SELECT jsonb_agg(jsonb_build_object(
                'ot_id', ot.id, 'folio', ot.folio,
                'estado', ot.estado, 'activo_codigo', a.codigo,
                'fecha_programada', ot.fecha_programada,
                'dias_abierta', CURRENT_DATE - ot.fecha_programada
            )) INTO v_registros
            FROM ordenes_trabajo ot
            JOIN activos a ON a.id = ot.activo_id
            WHERE ot.tipo = 'correctivo'
              AND ot.contrato_id = p_contrato_id
              AND ot.estado IN ('creada','asignada','en_ejecucion','pausada');

        -- KPIs basados en certificaciones (A7, B4, C4)
        WHEN p_kpi_codigo IN ('A7','B4','C4') THEN
            SELECT jsonb_agg(jsonb_build_object(
                'cert_id', c.id, 'tipo', c.tipo,
                'numero', c.numero_certificado,
                'activo_codigo', a.codigo,
                'fecha_vencimiento', c.fecha_vencimiento,
                'estado', c.estado,
                'bloqueante', c.bloqueante
            )) INTO v_registros
            FROM certificaciones c
            JOIN activos a ON a.id = c.activo_id
            WHERE a.contrato_id = p_contrato_id
              AND (p_faena_id IS NULL OR a.faena_id = p_faena_id);

        -- KPIs basados en incidentes (A8)
        WHEN p_kpi_codigo = 'A8' THEN
            SELECT jsonb_agg(jsonb_build_object(
                'incidente_id', i.id, 'tipo', i.tipo,
                'fecha', i.fecha_incidente,
                'gravedad', i.gravedad,
                'descripcion', LEFT(i.descripcion, 200),
                'estado', i.estado,
                'activo_id', i.activo_id
            )) INTO v_registros
            FROM incidentes i
            WHERE i.contrato_id = p_contrato_id
              AND i.tipo = 'ambiental'
              AND i.fecha_incidente BETWEEN v_inicio AND v_fin;

        -- KPIs basados en inventario (A4, A6, B5, C6)
        WHEN p_kpi_codigo IN ('A4','B5','C6') THEN
            SELECT jsonb_agg(jsonb_build_object(
                'conteo_id', ci.id, 'bodega', b.nombre,
                'producto', p.nombre, 'codigo', p.codigo,
                'stock_sistema', cd.stock_sistema,
                'stock_fisico', cd.stock_fisico,
                'diferencia', cd.diferencia,
                'dif_valorizada', cd.diferencia_valorizada
            )) INTO v_registros
            FROM conteo_detalle cd
            JOIN conteos_inventario ci ON ci.id = cd.conteo_id
            JOIN bodegas b ON b.id = ci.bodega_id
            JOIN productos p ON p.id = cd.producto_id
            WHERE (p_faena_id IS NULL OR b.faena_id = p_faena_id)
              AND ci.created_at BETWEEN v_inicio AND v_fin;

        -- KPIs basados en rutas (A3, A5)
        WHEN p_kpi_codigo IN ('A3','A5') THEN
            SELECT jsonb_agg(jsonb_build_object(
                'ruta_id', rd.id, 'fecha', rd.fecha_programada,
                'estado', rd.estado,
                'puntos_programados', rd.puntos_programados,
                'puntos_completados', rd.puntos_completados,
                'km', rd.km_reales, 'litros', rd.litros_despachados
            )) INTO v_registros
            FROM rutas_despacho rd
            WHERE rd.contrato_id = p_contrato_id
              AND rd.fecha_programada BETWEEN v_inicio AND v_fin;

        ELSE
            v_registros := '[]'::JSONB;
    END CASE;

    -- Retornar resultado completo
    RETURN jsonb_build_object(
        'kpi_codigo', p_kpi_codigo,
        'kpi_nombre', v_kpi.nombre,
        'kpi_formula', v_kpi.formula,
        'kpi_meta', v_kpi.meta_valor,
        'kpi_unidad', v_kpi.unidad,
        'kpi_peso', v_kpi.peso,
        'kpi_bloqueante', v_kpi.es_bloqueante,
        'periodo', v_inicio || ' a ' || v_fin,
        'medicion', CASE WHEN v_medicion.id IS NOT NULL THEN jsonb_build_object(
            'valor_medido', v_medicion.valor_medido,
            'porcentaje_cumplimiento', v_medicion.porcentaje_cumplimiento,
            'puntaje', v_medicion.puntaje,
            'valor_ponderado', v_medicion.valor_ponderado,
            'bloqueante_activado', v_medicion.bloqueante_activado,
            'calculado_en', v_medicion.calculado_en
        ) ELSE NULL END,
        'registros_fuente', COALESCE(v_registros, '[]'::JSONB),
        'total_registros', COALESCE(jsonb_array_length(v_registros), 0)
    );
END;
$$;

COMMENT ON FUNCTION rpc_kpi_drill_down IS
'Drill-down de un KPI: retorna definición, medición del período, y los registros fuente '
'(OTs, certificaciones, conteos, incidentes, rutas) que componen el cálculo.';


-- ############################################################################
-- 3. SNAPSHOT MENSUAL DE KPI (para histórico auditable)
-- ############################################################################

CREATE TABLE IF NOT EXISTS kpi_snapshots_mensuales (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id     UUID NOT NULL REFERENCES contratos(id),
    faena_id        UUID REFERENCES faenas(id),
    periodo         DATE NOT NULL,
    -- Snapshot completo como JSONB (inmutable después de cierre)
    snapshot_kpis   JSONB NOT NULL,   -- array de {codigo, valor, meta, pct, puntaje, ponderado, bloqueante}
    snapshot_iceo   JSONB NOT NULL,   -- {bruto, final, clasificacion, areas, bloqueantes}
    snapshot_incentivos JSONB,        -- array de {usuario, cargo, monto}
    -- Metadata
    total_kpis      INTEGER,
    total_bloqueantes_activos INTEGER DEFAULT 0,
    iceo_final      NUMERIC(7,4),
    clasificacion   clasificacion_iceo_enum,
    incentivo_habilitado BOOLEAN,
    -- Cierre
    cerrado         BOOLEAN NOT NULL DEFAULT false,
    cerrado_por     UUID REFERENCES usuarios_perfil(id),
    cerrado_en      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_snapshot_periodo UNIQUE (contrato_id, faena_id, periodo)
);

CREATE INDEX IF NOT EXISTS idx_snapshots_periodo ON kpi_snapshots_mensuales (contrato_id, periodo DESC);

-- RPC para crear snapshot del período (cierre mensual)
CREATE OR REPLACE FUNCTION rpc_cerrar_periodo_kpi(
    p_contrato_id    UUID,
    p_faena_id       UUID DEFAULT NULL,
    p_periodo        DATE DEFAULT NULL,
    p_usuario_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_periodo       DATE;
    v_kpis          JSONB;
    v_iceo          RECORD;
    v_incentivos    JSONB;
    v_snapshot_id   UUID;
BEGIN
    v_periodo := COALESCE(p_periodo, DATE_TRUNC('month', CURRENT_DATE)::DATE);

    -- Obtener ICEO del período
    SELECT * INTO v_iceo FROM iceo_periodos
    WHERE contrato_id = p_contrato_id
      AND periodo_inicio = v_periodo
    ORDER BY calculado_en DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay ICEO calculado para el período %. Calcule primero.', v_periodo;
    END IF;

    -- Snapshot de KPIs
    SELECT jsonb_agg(jsonb_build_object(
        'codigo', kd.codigo, 'nombre', kd.nombre, 'area', kd.area,
        'valor', mk.valor_medido, 'meta', kd.meta_valor,
        'pct', mk.porcentaje_cumplimiento, 'puntaje', mk.puntaje,
        'ponderado', mk.valor_ponderado,
        'bloqueante', kd.es_bloqueante,
        'bloqueante_activado', mk.bloqueante_activado
    )) INTO v_kpis
    FROM mediciones_kpi mk
    JOIN kpi_definiciones kd ON kd.id = mk.kpi_id
    WHERE mk.contrato_id = p_contrato_id AND mk.periodo_inicio = v_periodo;

    -- Snapshot de incentivos
    SELECT jsonb_agg(jsonb_build_object(
        'usuario', up.nombre_completo, 'rut', up.rut, 'cargo', ip.cargo,
        'monto_max', ip.monto_incentivo_max, 'monto_real', ip.monto_incentivo_real,
        'monto_final', ip.monto_incentivo_final, 'tramo_pct', ip.tramo_pct_pago
    )) INTO v_incentivos
    FROM incentivos_periodo ip
    JOIN usuarios_perfil up ON up.id = ip.usuario_id
    WHERE ip.contrato_id = p_contrato_id AND ip.periodo_inicio = v_periodo;

    -- Insertar snapshot
    v_snapshot_id := gen_random_uuid();
    INSERT INTO kpi_snapshots_mensuales (
        id, contrato_id, faena_id, periodo,
        snapshot_kpis, snapshot_iceo, snapshot_incentivos,
        total_kpis, total_bloqueantes_activos,
        iceo_final, clasificacion, incentivo_habilitado,
        cerrado, cerrado_por, cerrado_en
    ) VALUES (
        v_snapshot_id, p_contrato_id, p_faena_id, v_periodo,
        COALESCE(v_kpis, '[]'::JSONB),
        jsonb_build_object(
            'bruto', v_iceo.iceo_bruto, 'final', v_iceo.iceo_final,
            'clasificacion', v_iceo.clasificacion,
            'area_a', v_iceo.puntaje_area_a, 'area_b', v_iceo.puntaje_area_b, 'area_c', v_iceo.puntaje_area_c,
            'peso_a', v_iceo.peso_area_a, 'peso_b', v_iceo.peso_area_b, 'peso_c', v_iceo.peso_area_c,
            'bloqueantes', v_iceo.bloqueantes_activados
        ),
        v_incentivos,
        COALESCE(jsonb_array_length(v_kpis), 0),
        (SELECT COUNT(*) FROM mediciones_kpi WHERE contrato_id = p_contrato_id AND periodo_inicio = v_periodo AND bloqueante_activado = true),
        v_iceo.iceo_final, v_iceo.clasificacion, v_iceo.incentivo_habilitado,
        true, p_usuario_id, NOW()
    )
    ON CONFLICT (contrato_id, faena_id, periodo)
    DO UPDATE SET
        snapshot_kpis = EXCLUDED.snapshot_kpis,
        snapshot_iceo = EXCLUDED.snapshot_iceo,
        snapshot_incentivos = EXCLUDED.snapshot_incentivos,
        total_kpis = EXCLUDED.total_kpis,
        total_bloqueantes_activos = EXCLUDED.total_bloqueantes_activos,
        iceo_final = EXCLUDED.iceo_final,
        clasificacion = EXCLUDED.clasificacion,
        incentivo_habilitado = EXCLUDED.incentivo_habilitado,
        cerrado = true, cerrado_por = p_usuario_id, cerrado_en = NOW();

    RETURN jsonb_build_object(
        'snapshot_id', v_snapshot_id,
        'periodo', v_periodo,
        'iceo_final', v_iceo.iceo_final,
        'clasificacion', v_iceo.clasificacion,
        'kpis_snapshot', COALESCE(jsonb_array_length(v_kpis), 0),
        'incentivos_snapshot', COALESCE(jsonb_array_length(v_incentivos), 0),
        'cerrado', true
    );
END;
$$;


-- ############################################################################
-- 4. pg_cron: REFRESCAR MVs CADA HORA
-- ############################################################################

DO $$ BEGIN
    PERFORM cron.unschedule('refrescar-vistas-kpi');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'refrescar-vistas-kpi',
    '0 * * * *',  -- Cada hora
    $$
    DO $job$
    DECLARE v_start TIMESTAMPTZ := clock_timestamp();
    BEGIN
        PERFORM rpc_refrescar_vistas_kpi();
        INSERT INTO log_jobs_automaticos (job_name, resultado, duracion_ms)
        VALUES ('refrescar-vistas-kpi', 'ok',
                EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('refrescar-vistas-kpi', 'error', SQLERRM);
    END $job$;
    $$
);


-- ############################################################################
-- RESUMEN
-- ############################################################################
--
-- VISTAS MATERIALIZADAS (5):
-- ├── mv_ot_stats_periodo          → OTs PM/CM por período/área
-- ├── mv_inventario_stats_periodo  → Volúmenes, mermas, conteos
-- ├── mv_certificaciones_stats     → Vigentes/vencidas por tipo
-- ├── mv_rutas_stats_periodo       → Rutas completadas/pendientes
-- └── mv_incidentes_stats_periodo  → Incidentes por tipo
--
-- RPCs NUEVAS (3):
-- ├── rpc_refrescar_vistas_kpi()       → Refresca las 5 MVs
-- ├── rpc_kpi_drill_down(codigo, ...)  → Registros fuente de un KPI
-- └── rpc_cerrar_periodo_kpi(...)      → Snapshot mensual inmutable
--
-- TABLAS NUEVAS (1):
-- └── kpi_snapshots_mensuales → Snapshot JSONB inmutable por período
--
-- pg_cron (1 job nuevo):
-- └── refrescar-vistas-kpi → Cada hora
--
-- ============================================================================
