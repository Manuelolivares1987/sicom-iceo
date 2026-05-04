-- ============================================================================
-- 02_seed_datos_maestros.sql  —  Datos maestros minimos requeridos por mig 55+.
-- ----------------------------------------------------------------------------
-- Idempotente: usa ON CONFLICT DO NOTHING. Re-ejecutable sin riesgo.
--
-- IMPORTANTE: este script ASUME que las tablas `proveedores` y `centros_costo`
-- ya existen (las crea mig 55 BLOCK B y C). Por lo tanto:
--   - Ejecutar DESPUES de `03_apply_mig55_bodega_combustible_base.sql`.
--   - O modificar el orden si se prefiere seedear despues.
--
-- Razon: incluir aqui evita duplicar el seed dentro del archivo de DDL.
-- ============================================================================


-- ── 1. Proveedores principales ───────────────────────────────────────
-- Ajustar codigos/nombres si la realidad operativa difiere.

INSERT INTO proveedores (codigo, nombre, rut, tipo, activo) VALUES
    ('ENEX',     'ENEX S.A.',                          '92.011.000-2', 'combustible', true),
    ('ESMAX',    'Esmax Distribución S.A.',            '76.418.940-K', 'combustible', true),
    ('COPEC',    'Empresas Copec S.A.',                '99.520.000-7', 'combustible', true),
    ('PETROBRAS','Petróleos Brasileiro S.A.',          NULL,           'combustible', true)
ON CONFLICT (codigo) DO NOTHING;

-- Repuesteros frecuentes (placeholder — ajustar a proveedores reales)
INSERT INTO proveedores (codigo, nombre, tipo, activo) VALUES
    ('REPUESTERO-GENERICO', 'Repuestero Genérico (placeholder)', 'repuestos', true)
ON CONFLICT (codigo) DO NOTHING;


-- ── 2. Centros de Costo (CECO) mínimos ───────────────────────────────

INSERT INTO centros_costo (codigo, nombre, area, activo) VALUES
    ('CECO-TALLER-CQB',    'Taller Pillado Coquimbo',          'mantenimiento', true),
    ('CECO-TALLER-CAL',    'Taller Pillado Calama',            'mantenimiento', true),
    ('CECO-OPERACIONES',   'Operaciones Generales',            'operacional',   true),
    ('CECO-COMERCIAL',     'Comercial',                        'comercial',     true),
    ('CECO-VENTA-EXT',     'Venta Combustible Externa',        'comercial',     true),
    ('CECO-ADMIN',         'Administración',                   'admin',         true),
    ('CECO-PREVENCION',    'Prevención de Riesgos',            'prevencion',    true),
    ('CECO-BODEGA',        'Bodega',                           'logistica',     true)
ON CONFLICT (codigo) DO NOTHING;


-- ── 3. Verificacion ──────────────────────────────────────────────────
SELECT
    'PROVEEDORES_ACTIVOS' AS check_name,
    tipo,
    COUNT(*) AS cantidad
FROM proveedores
WHERE activo = true
GROUP BY tipo
ORDER BY tipo;

SELECT
    'CECO_ACTIVOS' AS check_name,
    area,
    COUNT(*) AS cantidad
FROM centros_costo
WHERE activo = true
GROUP BY area
ORDER BY area;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- - proveedores: deben existir al menos 4 de tipo combustible (ENEX, ESMAX,
--   COPEC, PETROBRAS) + 1 placeholder repuestero.
-- - centros_costo: 8 CECOs minimos. La operacion real puede tener mas,
--   pero estos son los minimos requeridos para los tests funcionales.
-- ============================================================================
