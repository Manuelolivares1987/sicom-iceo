-- ============================================================================
-- MIG557 · Prevención: reportabilidad del prevencionista por faena
-- ============================================================================
-- Manuel (2026-09-14) entregó los FORMATOS REALES que cada faena exige
-- (carpeta PREVENCION): Centinela «Estadística RRHH y accidentabilidad
-- ESM-ENEX» (HH/dotación POR INSTALACIÓN), CMP la lámina GRP (PPT), Franke
-- 4.4 insumos + 4.5 retiro de residuos, Lomas el PPT Anexo 10.2, y el E-200
-- en su Word oficial (se rellena tal cual, plantilla con marcadores).
--
--   1. dotacion_diaria.instalacion: Centinela declara HH por instalación
--      (Mina Esperanza, Esperanza Sur, …). La subida gana un selector cuando
--      la ficha de la faena define `instalaciones`; el UNIQUE pasa a incluir
--      la instalación (mismo supervisor puede reportar varias instalaciones
--      el mismo día). NULLS NOT DISTINCT para las faenas sin instalación.
--   2. Ficha Centinela: las 7 instalaciones del formato real.
--   3. v_prevencion_dotacion_instalacion: HH 8× y dotación peak por
--      instalación — las filas del Excel de Centinela.
--   4. Plantillas nuevas: e200 pasa a DOCX oficial (mismo código de
--      plantilla), y se agregan estadistica_esm (Centinela), franke_insumos
--      (4.4) y franke_residuos (4.5). El CHECK se amplía.
--   5. Ítems nuevos Franke: 4.4 y 4.5 con su generador; Centinela
--      «Estadísticas RR.HH. y accidentabilidad» → estadistica_esm.
-- IDEMPOTENTE.
-- ============================================================================

BEGIN;

-- ── 1. Instalación en la subida ─────────────────────────────────────────────
ALTER TABLE prevencion_dotacion_diaria
    ADD COLUMN IF NOT EXISTS instalacion VARCHAR(120);

COMMENT ON COLUMN prevencion_dotacion_diaria.instalacion IS
    'Instalación dentro de la faena (Centinela declara HH por instalación en su estadística y el E-200). NULL en faenas sin instalaciones. MIG557.';

ALTER TABLE prevencion_dotacion_diaria
    DROP CONSTRAINT IF EXISTS uq_prev_dotacion;
DROP INDEX IF EXISTS uq_prev_dotacion_inst;
CREATE UNIQUE INDEX IF NOT EXISTS uq_prev_dotacion_inst
    ON prevencion_dotacion_diaria (faena_id, fecha, creado_por, instalacion)
    NULLS NOT DISTINCT;

-- ── 2. Instalaciones de Centinela (formato ESM-ENEX real) ───────────────────
UPDATE prevencion_faena_config c
   SET datos = jsonb_set(c.datos, '{instalaciones}', '[
        "Centinela Sulfuros — Mina Esperanza",
        "Centinela Sulfuros — Mina Esperanza Sur",
        "Centinela Sulfuros — Planta Concentradora (Planta)",
        "Centinela Oxido — Mina Rajo Abierto",
        "Centinela Oxido — Pila de lixiviación (Planta)",
        "Centinela Sulfuros — Puerto de Embarque (Muelle)",
        "Centinela Encuentro (DES) — Mina"
       ]'::jsonb),
       updated_at = NOW()
  FROM faenas f
 WHERE f.id = c.faena_id AND f.codigo = 'FAE-CENTINELA'
   AND (c.datos->'instalaciones') IS NULL;

-- ── 3. Vista por instalación ────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_prevencion_dotacion_instalacion
WITH (security_invoker = true) AS
WITH por_dia AS (
    SELECT faena_id,
           EXTRACT(YEAR  FROM fecha)::int AS anio,
           EXTRACT(MONTH FROM fecha)::int AS mes,
           COALESCE(instalacion, '') AS instalacion,
           fecha,
           SUM(hombres) AS hombres_dia,
           SUM(mujeres) AS mujeres_dia
    FROM prevencion_dotacion_diaria
    GROUP BY faena_id, 2, 3, 4, fecha
)
SELECT faena_id, anio, mes, instalacion,
       COUNT(*)             AS dias_reportados,
       SUM(hombres_dia) * 8 AS hh_hombres,
       SUM(mujeres_dia) * 8 AS hh_mujeres,
       MAX(hombres_dia)     AS dotacion_max_hombres,
       MAX(mujeres_dia)     AS dotacion_max_mujeres
FROM por_dia
GROUP BY faena_id, anio, mes, instalacion;

GRANT SELECT ON v_prevencion_dotacion_instalacion TO authenticated;

-- ── 4. Plantillas nuevas ────────────────────────────────────────────────────
ALTER TABLE prevencion_reportabilidad_items
    DROP CONSTRAINT IF EXISTS prevencion_reportabilidad_items_plantilla_check;
ALTER TABLE prevencion_reportabilidad_items
    ADD CONSTRAINT prevencion_reportabilidad_items_plantilla_check
    CHECK (plantilla IS NULL OR plantilla IN
        ('e200','grp_cmp','informe_franke','ppt_evidencias',
         'estadistica_esm','franke_insumos','franke_residuos'));

-- Centinela: su estadística RRHH tiene generador propio
UPDATE prevencion_reportabilidad_items it SET plantilla = 'estadistica_esm'
  FROM faenas f
 WHERE f.id = it.faena_id AND f.codigo = 'FAE-CENTINELA'
   AND it.nombre = 'Estadísticas RR.HH. y accidentabilidad';

-- ── 5. Ítems 4.4 y 4.5 de Franke ────────────────────────────────────────────
DO $seed$
DECLARE v_franke UUID;
BEGIN
    SELECT id INTO v_franke FROM faenas WHERE codigo = 'FAE-FRANCKE';
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden, plantilla)
    VALUES
        (v_franke, '4.4 Reporte de insumos mensual',
         'Formato SGA-MLC-24: consumos y generación de residuos del mes (I a VII).',
         'Insumos reportados por el supervisor (Residuos e insumos)', 'SCM Franke', 7, 45, 'franke_insumos'),
        (v_franke, '4.5 Gestión de residuos instalaciones',
         'Registro de retiro de residuos: un bloque por retiro semanal + total del mes.',
         'Retiros semanales reportados por el supervisor', 'SCM Franke / Amffal', 7, 46, 'franke_residuos')
    ON CONFLICT (faena_id, nombre) DO UPDATE SET plantilla = EXCLUDED.plantilla;
END $seed$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.codigo, it.nombre, it.plantilla
FROM prevencion_reportabilidad_items it JOIN faenas f ON f.id = it.faena_id
WHERE it.plantilla IS NOT NULL
ORDER BY f.codigo, it.orden;
