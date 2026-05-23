-- ============================================================================
-- 79_mantenimiento_cobertura_vistas.sql
-- ----------------------------------------------------------------------------
-- Diagnostico de cobertura de plan preventivo. Hace visibles los activos
-- que tienen un modelo con pautas disponibles pero NO tienen planes
-- asignados (gap silencioso).
--
-- Antes: no existia ninguna vista que dijera "estos N activos no tienen PM".
-- Solo se veian los planes ya creados (Tab Vencidos, Plan Semanal, etc).
-- Resultado: 54 de 68 activos quedaron descubiertos al crecer la flota.
--
-- Esta migracion crea:
--   1. v_activos_sin_plan_preventivo  -- activos descubiertos con detalle
--   2. v_mantenimiento_cobertura_resumen -- KPI global de cobertura
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Activos sin plan preventivo ──────────────────────────────────────────
DROP VIEW IF EXISTS v_activos_sin_plan_preventivo CASCADE;
CREATE VIEW v_activos_sin_plan_preventivo AS
SELECT
    a.id                                  AS activo_id,
    a.codigo                              AS activo_codigo,
    a.nombre                              AS activo_nombre,
    a.patente,
    a.tipo                                AS activo_tipo,
    a.estado                              AS activo_estado,
    a.contrato_id,
    c.codigo                              AS contrato_codigo,
    c.cliente                             AS contrato_cliente,
    a.faena_id,
    f.nombre                              AS faena_nombre,
    a.modelo_id,
    m.nombre                              AS modelo_nombre,
    ma.nombre                             AS modelo_marca,
    COUNT(pf.id)                          AS pautas_disponibles,
    COUNT(pm.id) FILTER (WHERE pm.activo_plan = true) AS planes_asignados,
    COUNT(pf.id) - COUNT(pm.id) FILTER (WHERE pm.activo_plan = true) AS pautas_sin_cubrir,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.created_at                          AS activo_creado_at
FROM activos a
LEFT JOIN modelos m       ON m.id = a.modelo_id
LEFT JOIN marcas ma       ON ma.id = m.marca_id
LEFT JOIN contratos c     ON c.id = a.contrato_id
LEFT JOIN faenas f        ON f.id = a.faena_id
LEFT JOIN pautas_fabricante pf
       ON pf.modelo_id = a.modelo_id
      AND pf.activo = true
LEFT JOIN planes_mantenimiento pm
       ON pm.activo_id = a.id
      AND pm.pauta_fabricante_id = pf.id
WHERE a.estado != 'dado_baja'
GROUP BY a.id, a.codigo, a.nombre, a.patente, a.tipo, a.estado,
         a.contrato_id, c.codigo, c.cliente,
         a.faena_id, f.nombre,
         a.modelo_id, m.nombre, ma.nombre,
         a.kilometraje_actual, a.horas_uso_actual, a.created_at
HAVING COUNT(pf.id) > 0
   AND COUNT(pf.id) - COUNT(pm.id) FILTER (WHERE pm.activo_plan = true) > 0
ORDER BY pautas_sin_cubrir DESC, a.codigo;

COMMENT ON VIEW v_activos_sin_plan_preventivo IS
    'Activos cuyo modelo tiene pautas, pero al activo le faltan planes asignados. MIG79.';


-- ── 2. KPI global de cobertura ──────────────────────────────────────────────
DROP VIEW IF EXISTS v_mantenimiento_cobertura_resumen CASCADE;
CREATE VIEW v_mantenimiento_cobertura_resumen AS
WITH activos_vivos AS (
    SELECT a.id, a.modelo_id, a.tipo
    FROM activos a
    WHERE a.estado != 'dado_baja'
),
con_modelo AS (
    SELECT * FROM activos_vivos WHERE modelo_id IS NOT NULL
),
con_pautas AS (
    SELECT DISTINCT av.id
    FROM activos_vivos av
    JOIN pautas_fabricante pf
      ON pf.modelo_id = av.modelo_id
     AND pf.activo = true
),
con_plan AS (
    SELECT DISTINCT pm.activo_id AS id
    FROM planes_mantenimiento pm
    WHERE pm.activo_plan = true
),
sin_plan AS (
    SELECT id FROM con_pautas
    EXCEPT
    SELECT id FROM con_plan
)
SELECT
    (SELECT COUNT(*) FROM activos_vivos)                AS activos_totales,
    (SELECT COUNT(*) FROM con_modelo)                   AS activos_con_modelo,
    (SELECT COUNT(*) FROM con_pautas)                   AS activos_con_pautas_disponibles,
    (SELECT COUNT(*) FROM con_plan)                     AS activos_con_plan,
    (SELECT COUNT(*) FROM sin_plan)                     AS activos_sin_plan,
    CASE WHEN (SELECT COUNT(*) FROM con_pautas) > 0
         THEN ROUND(
              (SELECT COUNT(*) FROM con_plan)::numeric * 100
              / NULLIF((SELECT COUNT(*) FROM con_pautas), 0)
         , 1)
         ELSE 0
    END                                                  AS cobertura_pct,
    (SELECT COUNT(*) FROM pautas_fabricante WHERE activo = true) AS pautas_disponibles,
    (SELECT COUNT(*) FROM planes_mantenimiento WHERE activo_plan = true) AS planes_activos;

COMMENT ON VIEW v_mantenimiento_cobertura_resumen IS
    'KPI agregado de cobertura plan preventivo. MIG79.';


GRANT SELECT ON v_activos_sin_plan_preventivo   TO authenticated;
GRANT SELECT ON v_mantenimiento_cobertura_resumen TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_descubiertos INT; v_cobertura NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_descubiertos FROM v_activos_sin_plan_preventivo;
    SELECT cobertura_pct INTO v_cobertura FROM v_mantenimiento_cobertura_resumen;
    RAISE NOTICE '== MIG79 OK ==';
    RAISE NOTICE '   activos sin plan: %', v_descubiertos;
    RAISE NOTICE '   cobertura actual: % %%', v_cobertura;
END $$;

SELECT * FROM v_mantenimiento_cobertura_resumen;

NOTIFY pgrst, 'reload schema';
