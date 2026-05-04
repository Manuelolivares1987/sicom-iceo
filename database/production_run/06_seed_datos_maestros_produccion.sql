-- ============================================================================
-- 06_seed_datos_maestros_produccion.sql  —  Idempotente.
-- Inserta proveedores y CECO mínimos. Si ya existen, no duplica.
-- ============================================================================

-- Proveedores combustible base
INSERT INTO proveedores (codigo, nombre, rut, tipo, activo) VALUES
    ('ENEX',     'ENEX S.A.',                          '92.011.000-2', 'combustible', true),
    ('ESMAX',    'Esmax Distribución S.A.',            '76.418.940-K', 'combustible', true),
    ('COPEC',    'Empresas Copec S.A.',                '99.520.000-7', 'combustible', true)
ON CONFLICT (codigo) DO NOTHING;

-- CECO mínimos
INSERT INTO centros_costo (codigo, nombre, area, activo) VALUES
    ('CECO-TALLER-CQB',    'Taller Pillado Coquimbo',     'mantenimiento', true),
    ('CECO-TALLER-CAL',    'Taller Pillado Calama',       'mantenimiento', true),
    ('CECO-OPERACIONES',   'Operaciones Generales',       'operacional',   true),
    ('CECO-COMERCIAL',     'Comercial',                   'comercial',     true),
    ('CECO-VENTA-EXT',     'Venta Combustible Externa',   'comercial',     true),
    ('CECO-ADMIN',         'Administración',              'admin',         true),
    ('CECO-PREVENCION',    'Prevención de Riesgos',       'prevencion',    true),
    ('CECO-BODEGA',        'Bodega',                      'logistica',     true)
ON CONFLICT (codigo) DO NOTHING;


-- Listado actual
SELECT 'PROVEEDORES_COMBUSTIBLE' AS check_name, COUNT(*) AS cantidad
FROM proveedores WHERE tipo = 'combustible' AND activo = true;

SELECT 'CECO_ACTIVOS' AS check_name, COUNT(*) AS cantidad
FROM centros_costo WHERE activo = true;

SELECT codigo, nombre, tipo FROM proveedores WHERE activo=true ORDER BY tipo, codigo;
SELECT codigo, nombre, area FROM centros_costo WHERE activo=true ORDER BY area, codigo;


-- Log
SELECT fn_log_operacion_migracion(
    'PROD_SEED_MAESTROS',
    'Seed proveedores ENEX/ESMAX/COPEC + 8 CECOs minimos (idempotente).',
    'ok', NULL);
