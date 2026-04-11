-- ============================================================================
-- SICOM-ICEO | Migración 29 — Datos Reales de Operación Pillado Empresas
-- ============================================================================
-- Reemplaza datos demo con la estructura real del negocio:
-- - 2 operaciones: Coquimbo y Calama
-- - Contratos reales: CMP (Romeral), CM Cenizas (Francke), Boart Longyear
--   (Spence), ESM, y clientes de arriendo
-- - Faenas reales con ubicaciones
-- - Bodegas por faena
-- - Usuarios reales (técnicos del taller)
-- - Asignación correcta de activos a contratos/faenas
-- ============================================================================

-- ============================================================================
-- 1. CONTRATOS REALES
-- ============================================================================
-- Nota: No eliminamos el contrato demo para no romper FK existentes.
-- Insertamos los reales y luego reasignamos activos.

INSERT INTO contratos (id, codigo, nombre, cliente, descripcion, fecha_inicio, fecha_fin, estado, valor_contrato, moneda)
VALUES
    -- Contrato CMP (Coquimbo - Romeral): Combustibles + Mantención
    (gen_random_uuid(),
     'CTR-CMP-2025',
     'Contrato Servicios Combustibles y Mantención — CMP Romeral',
     'Compañía Minera del Pacífico (CMP)',
     'Administración de combustibles y lubricantes, mantención de plataformas fijas y móviles en faena Romeral. '
     'Incluye suministro de diesel, gestión de estanques, surtidores y equipos de abastecimiento.',
     '2025-01-01', '2027-12-31', 'activo', NULL, 'CLP'),

    -- Contrato CM Cenizas (Coquimbo - Francke, Taltal): Combustibles
    (gen_random_uuid(),
     'CTR-CENIZAS-2025',
     'Contrato Servicios Combustibles — CM Cenizas, Francke',
     'Compañía Minera Cenizas',
     'Administración de combustibles en faena Francke, Taltal. '
     'Incluye operación de aljibes de combustible y lubricantes.',
     '2025-01-01', '2027-12-31', 'activo', NULL, 'CLP'),

    -- Contrato Boart Longyear (Calama - Spence, DMH): Arriendo + Leasing
    (gen_random_uuid(),
     'CTR-BOART-2024',
     'Contrato Arriendo Flota — Boart Longyear, Spence/DMH',
     'Boart Longyear Chile',
     'Arriendo y leasing operativo de camiones cisterna (agua y combustible), '
     'camiones pluma y carrocerías planas para operaciones de perforación en Spence y Div. Ministro Hales.',
     '2024-06-01', '2027-05-31', 'activo', NULL, 'CLP'),

    -- Contrato ESM (Calama): Uso interno / Contrato
    (gen_random_uuid(),
     'CTR-ESM-2025',
     'Contrato Servicios — ESM Calama',
     'ESM',
     'Contrato de servicios con vehículos asignados en Calama.',
     '2025-01-01', '2026-12-31', 'activo', NULL, 'CLP'),

    -- Rental: Drilling service and solution (Coquimbo)
    (gen_random_uuid(),
     'CTR-DRILLING-2025',
     'Arriendo Flota — Drilling Service and Solution',
     'Drilling Service and Solution',
     'Arriendo de camiones de riego y aljibes de combustible para faenas de perforación '
     'en Copiapó (Sobek, Cuprita) y Huachalalume (Marquesa).',
     '2025-01-01', '2026-12-31', 'activo', NULL, 'CLP'),

    -- Rental: Rentamaq (Coquimbo)
    (gen_random_uuid(),
     'CTR-RENTAMAQ-2025',
     'Arriendo Flota — Rentamaq, Teck Andacollo',
     'Rentamaq',
     'Arriendo de camiones de riego para Mina Teck Andacollo.',
     '2025-01-01', '2026-06-30', 'activo', NULL, 'CLP'),

    -- Rental: Orbit Garant (Coquimbo + Calama)
    (gen_random_uuid(),
     'CTR-ORBIT-2025',
     'Arriendo Flota — Orbit Garant',
     'Orbit Garant',
     'Arriendo de aljibes de combustible. Los Bronces (Santiago) y El Abra (Calama).',
     '2025-01-01', '2026-12-31', 'activo', NULL, 'CLP'),

    -- Rental: Esmax (Coquimbo)
    (gen_random_uuid(),
     'CTR-ESMAX-2025',
     'Arriendo Aljibe — Esmax, El Salvador',
     'Esmax',
     'Arriendo de aljibe combustible 15kL para operación en El Salvador.',
     '2025-01-01', '2026-06-30', 'activo', NULL, 'CLP'),

    -- Rental: San Gerónimo (Coquimbo)
    (gen_random_uuid(),
     'CTR-SANGERONIMO-2025',
     'Arriendo Flota — San Gerónimo',
     'San Gerónimo',
     'Arriendo de aljibes combustible para Lambert y Coquimbo.',
     '2025-01-01', '2026-12-31', 'activo', NULL, 'CLP'),

    -- Rental: Major Drilling (Coquimbo)
    (gen_random_uuid(),
     'CTR-MAJOR-2025',
     'Arriendo Aljibe — Major Drilling S.A, Yastai',
     'Major Drilling S.A',
     'Arriendo de aljibe combustible 5kL para Faena Yastai, Tierra Amarilla.',
     '2025-06-01', '2026-05-31', 'activo', NULL, 'CLP'),

    -- Rental: TPM Minería (Coquimbo)
    (gen_random_uuid(),
     'CTR-TPM-2025',
     'Arriendo Camioneta Lubricadora — TPM Minería',
     'TPM Minería SA',
     'Arriendo de camioneta lubricadora para Caserones, Copiapó.',
     '2025-01-01', '2026-12-31', 'activo', NULL, 'CLP')

ON CONFLICT DO NOTHING;

-- ============================================================================
-- 2. FAENAS REALES
-- ============================================================================

INSERT INTO faenas (id, contrato_id, codigo, nombre, ubicacion, region, comuna, coordenadas_lat, coordenadas_lng, estado)
VALUES
    -- ── OPERACION COQUIMBO ──
    -- Base operativa
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-CMP-2025'),
     'FAE-TALLER-CQB',
     'Taller Pillado — Coquimbo',
     'Taller central de mantenimiento y base operativa Coquimbo',
     'Coquimbo', 'Coquimbo', -29.9533, -71.3436, 'activa'),

    -- CMP Romeral
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-CMP-2025'),
     'FAE-CMP-ROMERAL',
     'CMP — Romeral',
     'Compañía Minera del Pacífico, Planta Romeral',
     'Coquimbo', 'La Serena', -29.7167, -71.1000, 'activa'),

    -- Francke (CM Cenizas)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-CENIZAS-2025'),
     'FAE-FRANCKE',
     'Francke — CM Cenizas, Taltal',
     'Compañía Minera Cenizas, Faena Francke',
     'Antofagasta', 'Taltal', -25.1000, -70.2500, 'activa'),

    -- Sobek (Drilling)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
     'FAE-SOBEK',
     'Faena Sobek — Copiapó',
     'Drilling Service and Solution, Faena Sobek, Copiapó',
     'Atacama', 'Copiapó', -27.3667, -70.3333, 'activa'),

    -- Marquesa (Drilling)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
     'FAE-MARQUESA',
     'Faena Marquesa — Huachalalume',
     'Drilling Service and Solution, Faena Marquesa',
     'Coquimbo', 'La Higuera', -29.5000, -71.1667, 'activa'),

    -- Cuprita (Drilling)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
     'FAE-CUPRITA',
     'Faena Cuprita — Inca de Oro',
     'Drilling Service and Solution, Faena Cuprita',
     'Atacama', 'Diego de Almagro', -26.7333, -69.9000, 'activa'),

    -- Teck Andacollo (Rentamaq)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-RENTAMAQ-2025'),
     'FAE-TECK',
     'Mina Teck — Andacollo',
     'Rentamaq, Mina Teck Andacollo',
     'Coquimbo', 'Andacollo', -30.2333, -71.0833, 'activa'),

    -- Yastai (Major Drilling)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-MAJOR-2025'),
     'FAE-YASTAI',
     'Faena Yastai — Tierra Amarilla',
     'Major Drilling, Faena Yastai',
     'Atacama', 'Tierra Amarilla', -27.4833, -70.2667, 'activa'),

    -- El Salvador (Esmax)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-ESMAX-2025'),
     'FAE-ELSALVADOR',
     'El Salvador — Esmax',
     'Esmax, Estación El Salvador',
     'Atacama', 'Diego de Almagro', -26.2500, -69.6167, 'activa'),

    -- Los Bronces (Orbit Garant)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-ORBIT-2025'),
     'FAE-LOSBRONCES',
     'Mina Los Bronces — Santiago',
     'Orbit Garant, Mina Los Bronces',
     'Metropolitana', 'Lo Barnechea', -33.1500, -70.2667, 'activa'),

    -- Caserones (TPM)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-TPM-2025'),
     'FAE-CASERONES',
     'Caserones — Copiapó',
     'TPM Minería, Mina Caserones',
     'Atacama', 'Tierra Amarilla', -28.3167, -69.2833, 'activa'),

    -- Lambert (San Gerónimo)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-SANGERONIMO-2025'),
     'FAE-LAMBERT',
     'San Antonio — Lambert',
     'San Gerónimo, Lambert',
     'Coquimbo', 'La Serena', -29.8667, -71.2500, 'activa'),

    -- Andina (Boart Longyear desde Coquimbo)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-ANDINA',
     'Andina — Boart Longyear',
     'Boart Longyear, Div. Andina',
     'Valparaíso', 'Los Andes', -32.8333, -70.3833, 'activa'),

    -- ── OPERACION CALAMA ──
    -- Base operativa
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-TALLER-CAL',
     'Taller Pillado — Calama',
     'Base operativa y taller de mantenimiento Calama',
     'Antofagasta', 'Calama', -22.4560, -68.9293, 'activa'),

    -- Spence (Boart Longyear)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-SPENCE',
     'Spence — Boart Longyear',
     'BHP Spence, operaciones de perforación Boart Longyear',
     'Antofagasta', 'Sierra Gorda', -22.8500, -69.3333, 'activa'),

    -- División Ministro Hales (Boart Longyear)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-DMH',
     'Div. Ministro Hales — Boart Longyear',
     'Codelco DMH, operaciones de perforación Boart Longyear',
     'Antofagasta', 'Calama', -22.3667, -68.8833, 'activa'),

    -- El Abra (Orbit Garant)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-ORBIT-2025'),
     'FAE-ELABRA',
     'El Abra — Orbit Garant',
     'Orbit Garant, Mina El Abra',
     'Antofagasta', 'Calama', -21.9167, -68.8333, 'activa'),

    -- Lomas Bayas (futuro)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-LOMASBAYAS',
     'Lomas Bayas',
     'Glencore Lomas Bayas (pendiente confirmación)',
     'Antofagasta', 'Sierra Gorda', -23.4167, -69.5000, 'activa'),

    -- Centinela (futuro)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
     'FAE-CENTINELA',
     'Centinela',
     'Antofagasta Minerals Centinela (pendiente confirmación)',
     'Antofagasta', 'Sierra Gorda', -23.0833, -69.1333, 'activa')

ON CONFLICT DO NOTHING;

-- ============================================================================
-- 3. BODEGAS POR FAENA
-- ============================================================================

INSERT INTO bodegas (id, faena_id, codigo, nombre, tipo) VALUES
    -- Taller Coquimbo
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB'),
     'BOD-CQB-F01', 'Bodega Central Repuestos — Taller Coquimbo', 'fija'),
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB'),
     'BOD-CQB-M01', 'Bodega Móvil TM-11 — Coquimbo', 'movil'),

    -- CMP Romeral
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL'),
     'BOD-CMP-F01', 'Bodega Combustibles — CMP Romeral', 'fija'),

    -- Francke
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE'),
     'BOD-FRK-F01', 'Bodega Combustibles — Francke', 'fija'),

    -- Taller Calama
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL'),
     'BOD-CAL-F01', 'Bodega Central Repuestos — Taller Calama', 'fija'),
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL'),
     'BOD-CAL-M01', 'Bodega Móvil TM-12 — Calama', 'movil'),

    -- Spence
    (gen_random_uuid(), (SELECT id FROM faenas WHERE codigo = 'FAE-SPENCE'),
     'BOD-SPN-F01', 'Bodega Repuestos — Spence', 'fija')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 4. ASIGNAR ACTIVOS A CONTRATOS Y FAENAS REALES
-- ============================================================================

DO $$
BEGIN
    -- Camiones arrendados a Drilling service and solution
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-SOBEK')
    WHERE patente IN ('JTYK-88', 'JGBY-10') AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-MARQUESA')
    WHERE patente = 'KCBY-30' AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-DRILLING-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CUPRITA')
    WHERE patente = 'KVWW-69' AND patente IS NOT NULL;

    -- Rentamaq → Teck Andacollo
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-RENTAMAQ-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TECK')
    WHERE patente IN ('SVCZ-38', 'SVBJ-55') AND patente IS NOT NULL;

    -- Boart Longyear → Spence/DMH (Leasing)
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-SPENCE')
    WHERE patente IN ('TGGF-56','TGGF-57','TGGF-58','TRST-57','TGGF-59',
                      'TRDP-96','TRSS-14','TRSS-13','TRSS-15') AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-DMH')
    WHERE patente IN ('TRST-58', 'TTPC-47') AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-BOART-2024'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-ANDINA')
    WHERE patente = 'TRSS-16' AND patente IS NOT NULL;

    -- CMP Romeral (uso interno / contrato combustibles)
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-CMP-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL')
    WHERE patente IN ('DJKL-18', 'FSLZ-67', 'RZPC-83') AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-CMP-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL')
    WHERE patente = 'LCSX-78' AND patente IS NOT NULL;

    -- CM Cenizas → Francke
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-CENIZAS-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE')
    WHERE patente IN ('HHWB-42', 'HHWB-44', 'LLBP-96') AND patente IS NOT NULL;

    -- Orbit Garant
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-ORBIT-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-LOSBRONCES')
    WHERE patente = 'SVBJ-57' AND patente IS NOT NULL;

    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-ORBIT-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-ELABRA')
    WHERE patente = 'TCJV-15' AND patente IS NOT NULL;

    -- Esmax → El Salvador
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-ESMAX-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-ELSALVADOR')
    WHERE patente = 'SVBJ-56' AND patente IS NOT NULL;

    -- San Gerónimo
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-SANGERONIMO-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-LAMBERT')
    WHERE patente IN ('KVWD-27', 'FJTJ-60') AND patente IS NOT NULL;

    -- Major Drilling → Yastai
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-MAJOR-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-YASTAI')
    WHERE patente = 'RSCY-85' AND patente IS NOT NULL;

    -- TPM Minería → Caserones
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-TPM-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CASERONES')
    WHERE patente = 'SBPG-12' AND patente IS NOT NULL;

    -- ESM Calama
    UPDATE activos SET
        contrato_id = (SELECT id FROM contratos WHERE codigo = 'CTR-ESM-2025'),
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL')
    WHERE patente IN ('SPRY-26', 'SPRY-28') AND patente IS NOT NULL;

    -- Equipos disponibles / sin contrato → Taller Coquimbo
    UPDATE activos SET
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
    WHERE patente IN ('GGHB-32','TRDP-97','GCHT-12','KCBY-31','KVWW-68',
                      'DCHD-83','HKSR-81','FJTJ-61','RSCY-86',
                      'GCSY-66','GDP 30TK','JDKH-31','KVDK-20','KVDK-21',
                      'SLRK-82','TCRB-71','TSTB-48')
      AND faena_id IS NULL AND patente IS NOT NULL;

    UPDATE activos SET
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
    WHERE patente = 'LKPY-18' AND patente IS NOT NULL;

    -- Equipos en Taller Calama
    UPDATE activos SET
        faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL')
    WHERE patente IN ('VRST-19', 'SPRY-29', 'TGGF-60')
      AND faena_id IS NULL AND patente IS NOT NULL;
END $$;

-- ============================================================================
-- 5. ACTUALIZAR USUARIOS DEMO CON NOMBRES REALES (técnicos del taller)
-- ============================================================================
-- Actualizar los perfiles existentes para que reflejen personas reales

UPDATE usuarios_perfil SET
    nombre_completo = 'Felipe López',
    cargo = 'Técnico Mecánico Senior',
    faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
WHERE email = 'tecnico1.mp@sicom-iceo.cl';

UPDATE usuarios_perfil SET
    nombre_completo = 'Juan Valenzuela',
    cargo = 'Técnico Mecánico',
    faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
WHERE email = 'tecnico2.mp@sicom-iceo.cl';

UPDATE usuarios_perfil SET
    nombre_completo = 'Yohan Rondón',
    cargo = 'Técnico Mecánico',
    faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
WHERE email = 'tecnico.pc@sicom-iceo.cl';

UPDATE usuarios_perfil SET
    nombre_completo = 'Supervisor Operación Coquimbo',
    cargo = 'Supervisor de Operaciones',
    faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB')
WHERE email = 'supervisor.mp@sicom-iceo.cl';

UPDATE usuarios_perfil SET
    nombre_completo = 'Supervisor Operación Calama',
    cargo = 'Supervisor de Operaciones',
    faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL')
WHERE email = 'supervisor.pc@sicom-iceo.cl';

UPDATE usuarios_perfil SET
    nombre_completo = 'Administrador de Contrato',
    cargo = 'Administrador de Contrato'
WHERE email = 'admin@sicom-iceo.cl';

-- ============================================================================
-- 6. ACTUALIZAR estado_diario_flota CON CONTRATO CORRECTO
-- ============================================================================

UPDATE estado_diario_flota edf
SET contrato_id = a.contrato_id
FROM activos a
WHERE edf.activo_id = a.id
  AND a.contrato_id IS NOT NULL;

-- ============================================================================
-- 7. VERIFICACIÓN: Estado de la migración
-- ============================================================================

-- Resumen de contratos
-- SELECT codigo, cliente, estado, (SELECT COUNT(*) FROM activos WHERE contrato_id = c.id) AS equipos
-- FROM contratos c WHERE estado = 'activo' ORDER BY codigo;

-- Resumen de faenas
-- SELECT f.codigo, f.nombre, f.region, c.cliente,
--        (SELECT COUNT(*) FROM activos WHERE faena_id = f.id) AS equipos
-- FROM faenas f JOIN contratos c ON c.id = f.contrato_id
-- WHERE f.estado = 'activa' ORDER BY f.codigo;
