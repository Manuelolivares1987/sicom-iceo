-- ============================================================================
-- diag_calama_avance_promedio.sql
-- ----------------------------------------------------------------------------
-- Diagnostica la vista v_calama_resumen_general para entender por que
-- "Avance promedio" sale 45.5% mientras hay 41 finalizadas de 95.
-- Read-only.
-- ============================================================================

-- ── 1. Desglose por estado actual (todas las OTs de la planificacion) ─────
SELECT
    '01_desglose_por_estado' AS chequeo,
    p.codigo AS planificacion,
    o.estado,
    COUNT(*)::int AS cantidad,
    ROUND(AVG(o.avance_pct)::numeric, 1) AS avance_avg_estado,
    ROUND(MIN(o.avance_pct)::numeric, 1) AS avance_min,
    ROUND(MAX(o.avance_pct)::numeric, 1) AS avance_max
FROM calama_ordenes_trabajo o
JOIN calama_planificaciones p ON p.id = o.planificacion_id
WHERE p.codigo ILIKE 'VA_25_042%' OR p.codigo ILIKE '%CENTINELA%'
GROUP BY p.codigo, o.estado
ORDER BY p.codigo, o.estado;
-- Si ves estados como "parcial", "pendiente_aprobacion", "aceptada", "cerrada"
-- aqui pero los KPIs no los contabilizan -> bug en la vista (MIG34 lo arregla).


-- ── 2. Calculo manual de avance promedio vs avance completitud ────────────
SELECT
    '02_avance_promedio_vs_completitud' AS chequeo,
    p.codigo AS planificacion,
    COUNT(o.id)::int AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::int AS terminadas_real,
    COUNT(o.id) FILTER (WHERE o.estado = 'cancelada')::int AS canceladas,
    ROUND(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada')::numeric, 1) AS avance_promedio_simple,
    ROUND(
        (COUNT(o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
         / NULLIF(COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)), 1
    ) AS avance_completitud_pct,
    ROUND(SUM(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada')::numeric, 1) AS suma_avance,
    ROUND(SUM(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada')::numeric
        / NULLIF(COUNT(o.id) FILTER (WHERE o.estado <> 'cancelada'), 0), 1) AS avance_recalculado
FROM calama_ordenes_trabajo o
JOIN calama_planificaciones p ON p.id = o.planificacion_id
WHERE p.codigo ILIKE 'VA_25_042%' OR p.codigo ILIKE '%CENTINELA%'
GROUP BY p.codigo;
-- avance_promedio_simple debe coincidir con el 45.5% que ves.
-- avance_completitud_pct = % de OTs realmente terminadas (mas honesto).


-- ── 3. OTs en estados "PRO terreno" que la vista vieja NO contaba ─────────
SELECT
    '03_ots_huerfanas_estados_nuevos' AS chequeo,
    p.codigo AS planificacion,
    o.estado,
    COUNT(*)::int AS cantidad
FROM calama_ordenes_trabajo o
JOIN calama_planificaciones p ON p.id = o.planificacion_id
WHERE o.estado IN (
    'parcial','pendiente_aprobacion','requiere_correccion'
)
GROUP BY p.codigo, o.estado
ORDER BY p.codigo, o.estado;
-- Si esto tiene filas, esas OTs estan invisibles en KPIs hoy.


-- ── 4. Comentarios reales en plan_semanal vs OT madre ────────────────────
SELECT
    '04_comentarios_origen' AS chequeo,
    p.codigo AS planificacion,
    COUNT(DISTINCT po.ot_id) FILTER (
        WHERE po.observaciones IS NOT NULL AND po.observaciones <> ''
    )::int AS comentarios_en_jornadas,
    COUNT(DISTINCT o.id) FILTER (
        WHERE o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> ''
    )::int AS comentarios_apertura_ot,
    COUNT(DISTINCT o.id) FILTER (
        WHERE o.observaciones_cierre IS NOT NULL AND o.observaciones_cierre <> ''
    )::int AS comentarios_cierre_ot
FROM calama_planificaciones p
LEFT JOIN calama_ordenes_trabajo o ON o.planificacion_id = p.id
LEFT JOIN calama_plan_semanal_ots po ON po.ot_id = o.id
WHERE p.codigo ILIKE 'VA_25_042%' OR p.codigo ILIKE '%CENTINELA%'
GROUP BY p.codigo;
-- Si comentarios_en_jornadas=0 pero comentarios_apertura_ot>0, la vista
-- vieja NO los contaba (MIG34 los suma).


-- ── 5. Resumen actual desde la vista vs valores esperados ────────────────
SELECT
    '05_vista_actual' AS chequeo,
    planificacion_codigo,
    total_tareas,
    tareas_finalizadas,
    tareas_en_ejecucion,
    tareas_pendientes,
    tareas_no_ejecutadas,
    (total_tareas - tareas_finalizadas - tareas_en_ejecucion - tareas_pendientes - tareas_no_ejecutadas) AS huerfanas_no_categorizadas,
    avance_promedio_pct,
    tareas_con_comentario
FROM v_calama_resumen_general
WHERE planificacion_codigo ILIKE 'VA_25_042%' OR planificacion_codigo ILIKE '%CENTINELA%';
-- huerfanas_no_categorizadas > 0 confirma el bug de la vista.


-- ============================================================================
-- INTERPRETACION ESPERADA PARA TU CASO (95 tareas, 45.5%):
--   - Query 01: deberias ver finalizada=41, en_ejecucion=5, planificada=49,
--     y tal vez parcial/pendiente_aprobacion sin contar.
--   - Query 02:
--     * avance_promedio_simple = 45.5 (lo que ves hoy).
--     * avance_completitud_pct = 41/(95-cancelada) ≈ 43.2%
--     * suma_avance: 41*100 + 5*X + 49*0 = 4100 + 5X. Con 45.5*95 ≈ 4322
--       => X ≈ 44 -> avance promedio de las 5 en_ejecucion es ~44%.
--   - Query 04: si comentarios_apertura_ot > 0 pero la vista marca 0, hay bug.
-- ============================================================================
