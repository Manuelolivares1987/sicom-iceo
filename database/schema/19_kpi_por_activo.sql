-- SICOM-ICEO | KPI por Activo + MTBF + Disponibilidad
-- ============================================================================
-- Ejecutar DESPUÉS de 18.
--
-- Agrega métricas calculadas por activo individual:
-- 1. Vista v_kpi_activo con MTBF, disponibilidad, cumplimiento PM, etc.
-- 2. RPC para obtener KPIs de un activo específico
-- ============================================================================


-- ############################################################################
-- 1. VISTA: KPI POR ACTIVO INDIVIDUAL
-- ############################################################################

CREATE OR REPLACE VIEW v_kpi_activo AS
WITH periodos AS (
    -- Último mes como período por defecto
    SELECT
        DATE_TRUNC('month', CURRENT_DATE)::DATE AS inicio,
        (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE AS fin,
        EXTRACT(EPOCH FROM (
            (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day') -
            DATE_TRUNC('month', CURRENT_DATE)
        )) / 3600.0 AS horas_periodo
),
ot_stats AS (
    SELECT
        ot.activo_id,
        -- Contadores
        COUNT(*) AS total_ots,
        COUNT(*) FILTER (WHERE ot.tipo = 'preventivo') AS ots_pm,
        COUNT(*) FILTER (WHERE ot.tipo = 'correctivo') AS ots_cm,
        COUNT(*) FILTER (WHERE ot.tipo = 'preventivo'
            AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')) AS pm_ejecutadas,
        COUNT(*) FILTER (WHERE ot.tipo = 'preventivo'
            AND ot.estado NOT IN ('cancelada')) AS pm_programadas,
        -- MTTR: promedio horas reparación correctiva
        AVG(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0)
            FILTER (WHERE ot.tipo = 'correctivo'
                AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS mttr_horas,
        -- Total downtime correctivo (horas)
        COALESCE(SUM(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0)
            FILTER (WHERE ot.tipo = 'correctivo'
                AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL), 0) AS downtime_horas,
        -- Número de fallas (correctivos cerrados)
        COUNT(*) FILTER (WHERE ot.tipo = 'correctivo'
            AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')) AS fallas_periodo,
        -- Costo total
        COALESCE(SUM(ot.costo_mano_obra), 0) + COALESCE(
            (SELECT SUM(mi.cantidad * mi.costo_unitario) FROM movimientos_inventario mi
             WHERE mi.activo_id = ot.activo_id AND mi.tipo IN ('salida','merma')), 0) AS costo_acumulado
    FROM ordenes_trabajo ot
    GROUP BY ot.activo_id
),
cert_stats AS (
    SELECT
        c.activo_id,
        COUNT(*) AS certs_total,
        COUNT(*) FILTER (WHERE c.estado = 'vigente') AS certs_vigentes,
        COUNT(*) FILTER (WHERE c.estado IN ('vencido','por_vencer')) AS certs_en_riesgo
    FROM certificaciones c
    GROUP BY c.activo_id
)
SELECT
    a.id AS activo_id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.criticidad,
    a.estado,
    a.faena_id,
    -- Modelo/Marca
    m.nombre AS modelo,
    ma.nombre AS marca,
    -- MTTR
    ROUND(COALESCE(os.mttr_horas, 0)::NUMERIC, 1) AS mttr_horas,
    -- MTBF (horas operativas entre fallas)
    CASE
        WHEN COALESCE(os.fallas_periodo, 0) > 0 THEN
            ROUND(((SELECT horas_periodo FROM periodos) - COALESCE(os.downtime_horas, 0))
                / os.fallas_periodo, 1)
        ELSE NULL -- sin fallas = MTBF infinito (bueno)
    END AS mtbf_horas,
    -- Disponibilidad % (horas operativas / horas período)
    CASE
        WHEN (SELECT horas_periodo FROM periodos) > 0 THEN
            ROUND((((SELECT horas_periodo FROM periodos) - COALESCE(os.downtime_horas, 0))
                / (SELECT horas_periodo FROM periodos) * 100)::NUMERIC, 1)
        ELSE 100.0
    END AS disponibilidad_pct,
    -- Cumplimiento PM %
    CASE
        WHEN COALESCE(os.pm_programadas, 0) > 0 THEN
            ROUND((COALESCE(os.pm_ejecutadas, 0)::NUMERIC / os.pm_programadas * 100), 1)
        ELSE NULL
    END AS cumplimiento_pm_pct,
    -- Tasa de correctivos %
    CASE
        WHEN COALESCE(os.total_ots, 0) > 0 THEN
            ROUND((COALESCE(os.ots_cm, 0)::NUMERIC / os.total_ots * 100), 1)
        ELSE 0
    END AS tasa_correctivos_pct,
    -- Costo acumulado
    COALESCE(os.costo_acumulado, 0) AS costo_acumulado,
    -- OTs
    COALESCE(os.total_ots, 0) AS total_ots,
    COALESCE(os.ots_pm, 0) AS ots_preventivas,
    COALESCE(os.ots_cm, 0) AS ots_correctivas,
    COALESCE(os.fallas_periodo, 0) AS fallas_periodo,
    -- Certificaciones
    COALESCE(cs.certs_total, 0) AS certs_total,
    COALESCE(cs.certs_vigentes, 0) AS certs_vigentes,
    COALESCE(cs.certs_en_riesgo, 0) AS certs_en_riesgo,
    -- Cumplimiento documental %
    CASE
        WHEN COALESCE(cs.certs_total, 0) > 0 THEN
            ROUND((COALESCE(cs.certs_vigentes, 0)::NUMERIC / cs.certs_total * 100), 1)
        ELSE 100.0
    END AS cumplimiento_doc_pct,
    -- Health Score compuesto (0-100)
    -- Fórmula: (disponibilidad×30 + cumpl_PM×25 + cumpl_doc×20 + (100-tasa_correct)×15 + mttr_score×10) / 100
    ROUND((
        COALESCE(
            CASE WHEN (SELECT horas_periodo FROM periodos) > 0 THEN
                (((SELECT horas_periodo FROM periodos) - COALESCE(os.downtime_horas, 0))
                / (SELECT horas_periodo FROM periodos) * 100)
            ELSE 100 END, 100) * 0.30
        +
        COALESCE(
            CASE WHEN COALESCE(os.pm_programadas, 0) > 0 THEN
                (COALESCE(os.pm_ejecutadas, 0)::NUMERIC / os.pm_programadas * 100)
            ELSE 100 END, 100) * 0.25
        +
        COALESCE(
            CASE WHEN COALESCE(cs.certs_total, 0) > 0 THEN
                (COALESCE(cs.certs_vigentes, 0)::NUMERIC / cs.certs_total * 100)
            ELSE 100 END, 100) * 0.20
        +
        (100 - COALESCE(
            CASE WHEN COALESCE(os.total_ots, 0) > 0 THEN
                (COALESCE(os.ots_cm, 0)::NUMERIC / os.total_ots * 100)
            ELSE 0 END, 0)) * 0.15
        +
        -- MTTR score: 100 si <=4h, 75 si <=8h, 50 si <=12h, 25 si <=24h, 0 si >24h
        CASE
            WHEN COALESCE(os.mttr_horas, 0) = 0 THEN 100
            WHEN os.mttr_horas <= 4 THEN 100
            WHEN os.mttr_horas <= 8 THEN 75
            WHEN os.mttr_horas <= 12 THEN 50
            WHEN os.mttr_horas <= 24 THEN 25
            ELSE 0
        END * 0.10
    )::NUMERIC, 1) AS health_score
FROM activos a
LEFT JOIN modelos m ON m.id = a.modelo_id
LEFT JOIN marcas ma ON ma.id = m.marca_id
LEFT JOIN ot_stats os ON os.activo_id = a.id
LEFT JOIN cert_stats cs ON cs.activo_id = a.id;

COMMENT ON VIEW v_kpi_activo IS
'KPIs por activo individual: MTTR, MTBF, disponibilidad, cumplimiento PM, '
'tasa correctivos, costo acumulado, cumplimiento documental, health score.';


-- ############################################################################
-- 2. RPC: OBTENER KPIs DE UN ACTIVO
-- ############################################################################

CREATE OR REPLACE FUNCTION rpc_kpi_activo(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_kpi RECORD;
BEGIN
    SELECT * INTO v_kpi FROM v_kpi_activo WHERE activo_id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado: %', p_activo_id;
    END IF;

    RETURN jsonb_build_object(
        'activo_id', v_kpi.activo_id,
        'codigo', v_kpi.codigo,
        'nombre', v_kpi.nombre,
        'tipo', v_kpi.tipo,
        'criticidad', v_kpi.criticidad,
        'estado', v_kpi.estado,
        'marca', v_kpi.marca,
        'modelo', v_kpi.modelo,
        'kpis', jsonb_build_object(
            'mttr_horas', v_kpi.mttr_horas,
            'mtbf_horas', v_kpi.mtbf_horas,
            'disponibilidad_pct', v_kpi.disponibilidad_pct,
            'cumplimiento_pm_pct', v_kpi.cumplimiento_pm_pct,
            'tasa_correctivos_pct', v_kpi.tasa_correctivos_pct,
            'cumplimiento_doc_pct', v_kpi.cumplimiento_doc_pct,
            'health_score', v_kpi.health_score
        ),
        'contadores', jsonb_build_object(
            'total_ots', v_kpi.total_ots,
            'ots_preventivas', v_kpi.ots_preventivas,
            'ots_correctivas', v_kpi.ots_correctivas,
            'fallas_periodo', v_kpi.fallas_periodo,
            'costo_acumulado', v_kpi.costo_acumulado,
            'certs_total', v_kpi.certs_total,
            'certs_vigentes', v_kpi.certs_vigentes,
            'certs_en_riesgo', v_kpi.certs_en_riesgo
        )
    );
END;
$$;


-- ############################################################################
-- 3. VISTA: RANKING DE ACTIVOS POR HEALTH SCORE
-- ############################################################################

CREATE OR REPLACE VIEW v_ranking_activos AS
SELECT
    activo_id, codigo, nombre, tipo, criticidad, estado, faena_id,
    marca, modelo,
    health_score,
    disponibilidad_pct,
    cumplimiento_pm_pct,
    mttr_horas,
    tasa_correctivos_pct,
    costo_acumulado,
    -- Semáforo basado en health score
    CASE
        WHEN health_score >= 90 THEN 'verde'
        WHEN health_score >= 70 THEN 'amarillo'
        ELSE 'rojo'
    END AS semaforo
FROM v_kpi_activo
WHERE estado != 'dado_baja'
ORDER BY health_score ASC NULLS LAST;

COMMENT ON VIEW v_ranking_activos IS
'Ranking de activos por health score. Los peores primero para priorización.';


-- ############################################################################
-- RESUMEN
-- ############################################################################
--
-- v_kpi_activo: 7 KPIs por activo + health score compuesto
-- ├── MTTR (promedio horas reparación)
-- ├── MTBF (horas entre fallas)
-- ├── Disponibilidad % (horas operativas / horas período)
-- ├── Cumplimiento PM % (ejecutadas / programadas)
-- ├── Tasa Correctivos % (correctivos / total OTs)
-- ├── Cumplimiento Documental % (certs vigentes / total)
-- └── Health Score (compuesto 0-100):
--     30% disponibilidad + 25% cumpl.PM + 20% cumpl.doc
--     + 15% (100 - tasa correctivos) + 10% MTTR score
--
-- rpc_kpi_activo(id): retorna KPIs como JSONB
-- v_ranking_activos: ranking peores primero para priorización
--
-- ============================================================================
