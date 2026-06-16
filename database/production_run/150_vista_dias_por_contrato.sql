-- ============================================================================
-- SICOM-ICEO | 150 — Vista: dias en arriendo por contrato (por equipo)
-- ----------------------------------------------------------------------------
-- Para el modal "Historia mensual" del analisis de fiabilidad (dashboard) y
-- reutilizable. Cuenta los dias que cada equipo estuvo bajo cada contrato en
-- estado A=arrendado o C=en contrato, sobre todo el historico diario.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE VIEW v_activo_dias_contrato AS
SELECT
    edf.activo_id,
    edf.contrato_id,
    COALESCE(c.codigo, '(sin contrato)') AS codigo,
    c.cliente,
    COUNT(*)::int AS dias
FROM estado_diario_flota edf
LEFT JOIN contratos c ON c.id = edf.contrato_id
WHERE edf.estado_codigo IN ('A','C')
GROUP BY edf.activo_id, edf.contrato_id, c.codigo, c.cliente;

GRANT SELECT ON v_activo_dias_contrato TO authenticated, anon;

SELECT
    (SELECT count(*) FROM pg_views WHERE viewname='v_activo_dias_contrato') AS vista_ok,
    (SELECT count(DISTINCT activo_id) FROM v_activo_dias_contrato) AS activos_con_dias;
