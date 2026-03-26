-- SICOM-ICEO | Fase 6 | Datos Demo Realistas
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 08_seed_demo.sql
-- Proposito : Datos operacionales realistas para demostracion del sistema
--             completo. Construye sobre los datos semilla de 07_seed_data.sql.
-- Contexto : Operacion minera en el Desierto de Atacama, Region de Antofagasta.
--             Contrato de administracion de combustibles, lubricantes y
--             mantenimiento de plataformas para Compania Minera Los Andes SpA.
-- Dependencias: 01 a 07 (todos los esquemas y datos semilla base)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 0. MODELOS ADICIONALES (estanque y bomba genéricos para completar activos)
-- ============================================================================

INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Caterpillar'),
     'Estanque Horizontal 50.000L',
     'estanque',
     '{"capacidad_litros": 50000, "material": "acero_carbono", "doble_pared": true, "norma": "API 650"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Atlas Copco'),
     'Atlas Copco XAS 185 Compresor',
     'equipo_bombeo',
     '{"tipo": "compresor_portatil", "caudal_cfm": 185, "presion_bar": 7, "motor": "deutz_diesel"}');

-- ============================================================================
-- 1. USUARIOS DEMO (necesarios para OTs y movimientos de inventario)
-- ============================================================================
-- Insertamos usuarios ficticios en auth.users y luego perfiles.
-- En Supabase real estos vendrían de auth; aquí los simulamos.

DO $$
DECLARE
    v_user_admin     UUID := '00000000-0000-4000-a000-000000000001';
    v_user_sup_mp    UUID := '00000000-0000-4000-a000-000000000002';
    v_user_tec_mp1   UUID := '00000000-0000-4000-a000-000000000003';
    v_user_tec_mp2   UUID := '00000000-0000-4000-a000-000000000004';
    v_user_bod_mp    UUID := '00000000-0000-4000-a000-000000000005';
    v_user_sup_pc    UUID := '00000000-0000-4000-a000-000000000006';
    v_user_tec_pc    UUID := '00000000-0000-4000-a000-000000000007';
    v_user_sup_pe    UUID := '00000000-0000-4000-a000-000000000008';
    v_user_tec_pe    UUID := '00000000-0000-4000-a000-000000000009';
    v_user_planif    UUID := '00000000-0000-4000-a000-000000000010';
BEGIN
    -- Insertar en auth.users (esquema mínimo para FK)
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, instance_id, aud, role)
    VALUES
        (v_user_admin,   'admin@sicom-iceo.cl',        crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_sup_mp,  'supervisor.mp@sicom-iceo.cl', crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_tec_mp1, 'tecnico1.mp@sicom-iceo.cl',   crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_tec_mp2, 'tecnico2.mp@sicom-iceo.cl',   crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_bod_mp,  'bodeguero.mp@sicom-iceo.cl',  crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_sup_pc,  'supervisor.pc@sicom-iceo.cl', crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_tec_pc,  'tecnico.pc@sicom-iceo.cl',    crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_sup_pe,  'supervisor.pe@sicom-iceo.cl', crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_tec_pe,  'tecnico.pe@sicom-iceo.cl',    crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
        (v_user_planif,  'planificador@sicom-iceo.cl',  crypt('demo1234', gen_salt('bf')), NOW(), NOW(), NOW(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;

    -- Insertar perfiles de usuario
    INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, cargo, telefono, rol, faena_id, activo)
    VALUES
        (v_user_admin,   'admin@sicom-iceo.cl',         'Carlos Mendoza Fuentes',    '12.345.678-9', 'Administrador de Contrato', '+56 9 8765 4321', 'administrador', NULL, true),
        (v_user_sup_mp,  'supervisor.mp@sicom-iceo.cl', 'Roberto Espinoza Diaz',     '13.456.789-0', 'Supervisor Mina Principal', '+56 9 8765 4322', 'supervisor', (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'), true),
        (v_user_tec_mp1, 'tecnico1.mp@sicom-iceo.cl',  'Juan Perez Soto',           '14.567.890-1', 'Tecnico Mantenimiento',     '+56 9 8765 4323', 'tecnico_mantenimiento', (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'), true),
        (v_user_tec_mp2, 'tecnico2.mp@sicom-iceo.cl',  'Miguel Torres Araya',       '15.678.901-2', 'Tecnico Mantenimiento',     '+56 9 8765 4324', 'tecnico_mantenimiento', (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'), true),
        (v_user_bod_mp,  'bodeguero.mp@sicom-iceo.cl',  'Pedro Gonzalez Rojas',      '16.789.012-3', 'Bodeguero Central',         '+56 9 8765 4325', 'bodeguero', (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'), true),
        (v_user_sup_pc,  'supervisor.pc@sicom-iceo.cl', 'Andrea Morales Herrera',    '17.890.123-4', 'Supervisora Planta Conc.',  '+56 9 8765 4326', 'supervisor', (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'), true),
        (v_user_tec_pc,  'tecnico.pc@sicom-iceo.cl',   'Luis Contreras Vega',       '18.901.234-5', 'Tecnico Mantenimiento',     '+56 9 8765 4327', 'tecnico_mantenimiento', (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'), true),
        (v_user_sup_pe,  'supervisor.pe@sicom-iceo.cl', 'Francisco Reyes Tapia',     '19.012.345-6', 'Supervisor Puerto',         '+56 9 8765 4328', 'supervisor', (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'), true),
        (v_user_tec_pe,  'tecnico.pe@sicom-iceo.cl',   'Diego Alvarez Muñoz',       '20.123.456-7', 'Tecnico Mantenimiento',     '+56 9 8765 4329', 'tecnico_mantenimiento', (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'), true),
        (v_user_planif,  'planificador@sicom-iceo.cl',  'Maria Isabel Castro Rios',  '21.234.567-8', 'Planificador Mantenimiento','+56 9 8765 4330', 'planificador', NULL, true)
    ON CONFLICT (id) DO NOTHING;
END $$;

-- ============================================================================
-- 1. ACTIVOS (20 activos)
-- ============================================================================

-- --- Faena Mina Principal (FAE-MP-001): 8 activos ---

-- Surtidores
INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Gilbarco Veeder-Root Encore 700'),
     'SURT-MP-001', 'Surtidor Diesel Isla Norte', 'surtidor', 'GVR-ENC700-2023-001547', 'critica', 'operativo', '2024-07-15',
     'Isla de abastecimiento Norte, frente a taller mecanico');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Wayne Helix 6000'),
     'SURT-MP-002', 'Surtidor Diesel Isla Sur', 'surtidor', 'WYN-HLX6K-2024-003218', 'critica', 'operativo', '2024-08-01',
     'Isla de abastecimiento Sur, sector camiones');

-- Estanque
INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Estanque Horizontal 50.000L'),
     'EST-MP-001', 'Estanque Principal Diesel 50kL', 'estanque', 'EST-HRZ-50K-2024-0012', 'critica', 'operativo', '2024-07-10',
     'Area de almacenamiento combustible, sector poniente');

-- Bombas
INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Atlas Copco WEDA D60N'),
     'BOM-MP-001', 'Bomba Trasvasije Diesel N1', 'bomba', 'AC-WEDA60-2024-87431', 'alta', 'operativo', '2024-07-15', 3250.5,
     'Sala de bombas principal');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Atlas Copco WEDA D60N'),
     'BOM-MP-002', 'Bomba Trasvasije Diesel N2', 'bomba', 'AC-WEDA60-2024-87432', 'alta', 'en_mantenimiento', '2024-07-15', 3180.0,
     'Sala de bombas principal');

-- Camiones cisterna
INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Volvo FH 540 6x4 Cisterna'),
     'CT-MP-001', 'Cisterna Diesel 30kL N1', 'camion_cisterna', 'YV2RT40A5MA123456', 'critica', 'operativo', '2024-07-20', 85230.0, 4520.0,
     'Patio de equipos moviles - Mina Principal');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Mercedes-Benz Actros 2645 Cisterna'),
     'CT-MP-002', 'Cisterna Diesel 25kL N2', 'camion_cisterna', 'WDB96340310987654', 'alta', 'operativo', '2024-08-05', 72450.0, 3890.0,
     'Patio de equipos moviles - Mina Principal');

-- Lubrimovil
INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     (SELECT id FROM modelos WHERE nombre = 'Volvo FM 460 Lubrimovil'),
     'LM-MP-001', 'Lubrimovil Principal Mina', 'lubrimovil', 'YV2RH20C1PA654321', 'alta', 'operativo', '2024-07-25', 45670.0, 2780.0,
     'Patio de equipos moviles - Mina Principal');

-- --- Faena Planta Concentradora (FAE-PC-002): 6 activos ---

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Gilbarco Veeder-Root Encore 700'),
     'SURT-PC-001', 'Surtidor Diesel Planta', 'surtidor', 'GVR-ENC700-2024-002891', 'critica', 'operativo', '2024-08-10',
     'Estacion de combustible Planta Concentradora');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Wayne Ovation2'),
     'SURT-PC-002', 'Surtidor Diesel Planta N2', 'surtidor', 'WYN-OVT2-2024-005674', 'alta', 'operativo', '2024-08-15',
     'Estacion de combustible secundaria');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Estanque Horizontal 50.000L'),
     'EST-PC-001', 'Estanque Diesel Planta 50kL', 'estanque', 'EST-HRZ-50K-2024-0013', 'critica', 'operativo', '2024-08-05',
     'Area de almacenamiento Planta Concentradora');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Atlas Copco WEDA D60N'),
     'BOM-PC-001', 'Bomba Trasvasije Planta', 'bomba', 'AC-WEDA60-2024-87433', 'alta', 'operativo', '2024-08-10', 2890.0,
     'Sala de bombas Planta Concentradora');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Volvo FMX 500 4x4 Cisterna'),
     'CT-PC-001', 'Cisterna Diesel 20kL Planta', 'camion_cisterna', 'YV2FMX50BNA789012', 'alta', 'operativo', '2024-08-20', 52180.0, 2650.0,
     'Patio de equipos Planta Concentradora');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     (SELECT id FROM modelos WHERE nombre = 'Scania P 410 Lubrimovil'),
     'LM-PC-001', 'Lubrimovil Planta Concentradora', 'lubrimovil', 'XLEP410TN0A567890', 'media', 'en_mantenimiento', '2024-09-01', 38920.0, 2120.0,
     'Patio de equipos Planta Concentradora');

-- --- Faena Puerto Embarque (FAE-PE-003): 6 activos ---

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Tokheim Quantium 510M'),
     'SURT-PE-001', 'Surtidor Diesel Puerto', 'surtidor', 'TKH-Q510M-2024-001234', 'alta', 'operativo', '2024-09-01',
     'Estacion de combustible Puerto Embarque');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Estanque Horizontal 50.000L'),
     'EST-PE-001', 'Estanque Diesel Puerto 50kL', 'estanque', 'EST-HRZ-50K-2024-0014', 'alta', 'operativo', '2024-08-25',
     'Area de almacenamiento Puerto Embarque');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Atlas Copco WEDA D60N'),
     'BOM-PE-001', 'Bomba Trasvasije Puerto', 'bomba', 'AC-WEDA60-2024-87434', 'media', 'operativo', '2024-09-01', 1950.0,
     'Sala de bombas Puerto Embarque');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Scania R 500 6x4 Cisterna'),
     'CT-PE-001', 'Cisterna Diesel 30kL Puerto', 'camion_cisterna', 'XLER500TN0B345678', 'alta', 'fuera_servicio', '2024-09-10', 68340.0, 3450.0,
     'Patio de equipos Puerto Embarque');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, kilometraje_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Mercedes-Benz Sprinter 519 CDI'),
     'CAM-PE-001', 'Camioneta Servicio Puerto', 'camioneta', 'WDB9066571S234567', 'baja', 'operativo', '2024-09-15', 34560.0,
     'Patio de equipos Puerto Embarque');

INSERT INTO activos (id, contrato_id, faena_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado, fecha_alta, horas_uso_actual, ubicacion_detalle)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     (SELECT id FROM modelos WHERE nombre = 'Atlas Copco XAS 185 Compresor'),
     'EB-PE-001', 'Equipo Bombeo Compresor Puerto', 'equipo_bombeo', 'AC-XAS185-2024-56789', 'media', 'operativo', '2024-09-20', 1580.0,
     'Sector operaciones Puerto Embarque');

-- ============================================================================
-- 2. PAUTAS DEL FABRICANTE (8 pautas)
-- ============================================================================

-- PM 250 horas - Volvo FH 540
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_horas, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Volvo FH 540 6x4 Cisterna'),
    'PM 250 horas - Volvo FH 540',
    'por_horas', 250.0,
    'Mantenimiento preventivo cada 250 horas de operacion. Incluye cambio de aceite motor, revision de filtros y niveles generales.',
    '[
        {"orden": 1, "descripcion": "Cambio aceite motor 15W-40", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Cambio filtro aceite motor", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Revision nivel refrigerante", "obligatorio": true, "requiere_foto": false},
        {"orden": 4, "descripcion": "Revision tension correas", "obligatorio": true, "requiere_foto": true},
        {"orden": 5, "descripcion": "Verificar presion neumaticos", "obligatorio": true, "requiere_foto": false},
        {"orden": 6, "descripcion": "Revision estado mangueras cisterna", "obligatorio": true, "requiere_foto": true},
        {"orden": 7, "descripcion": "Engrase puntos de lubricacion", "obligatorio": true, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-SHR4-001", "descripcion": "Shell Rimula R4 X 15W-40", "cantidad": 38, "unidad": "litro"},
        {"producto_codigo": "FIL-CAT-0751", "descripcion": "Filtro Aceite", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "LUB-SGS2-001", "descripcion": "Grasa EP", "cantidad": 5, "unidad": "kilogramo"}
    ]'::jsonb,
    3.0, true);

-- PM 500 horas - Volvo FH 540
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_horas, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Volvo FH 540 6x4 Cisterna'),
    'PM 500 horas - Volvo FH 540',
    'por_horas', 500.0,
    'Mantenimiento preventivo mayor cada 500 horas. Incluye todo el PM 250h mas cambio de filtros de aire y combustible, revision de frenos.',
    '[
        {"orden": 1, "descripcion": "Cambio aceite motor 15W-40", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Cambio filtro aceite motor", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Cambio filtro aire primario", "obligatorio": true, "requiere_foto": true},
        {"orden": 4, "descripcion": "Cambio filtro combustible", "obligatorio": true, "requiere_foto": false},
        {"orden": 5, "descripcion": "Revision sistema de frenos", "obligatorio": true, "requiere_foto": true},
        {"orden": 6, "descripcion": "Cambio aceite caja de cambios", "obligatorio": true, "requiere_foto": false},
        {"orden": 7, "descripcion": "Revision sistema electrico", "obligatorio": true, "requiere_foto": false},
        {"orden": 8, "descripcion": "Inspeccion visual cisterna y valvulas", "obligatorio": true, "requiere_foto": true}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-SHR4-001", "descripcion": "Shell Rimula R4 X 15W-40", "cantidad": 38, "unidad": "litro"},
        {"producto_codigo": "FIL-CAT-0751", "descripcion": "Filtro Aceite", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-2503", "descripcion": "Filtro Aire Primario", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-0749", "descripcion": "Filtro Combustible", "cantidad": 2, "unidad": "unidad"},
        {"producto_codigo": "LUB-MSHC-001", "descripcion": "Aceite Sintetico Engranajes", "cantidad": 12, "unidad": "litro"}
    ]'::jsonb,
    6.0, true);

-- PM 10.000 km - Volvo FH 540
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_km, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Volvo FH 540 6x4 Cisterna'),
    'PM 10.000 km - Volvo FH 540',
    'por_kilometraje', 10000.0,
    'Mantenimiento preventivo basado en kilometraje. Enfocado en tren rodante, direccion y suspension.',
    '[
        {"orden": 1, "descripcion": "Inspeccion desgaste neumaticos", "obligatorio": true, "requiere_foto": true},
        {"orden": 2, "descripcion": "Verificar alineacion", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Revision amortiguadores y suspension", "obligatorio": true, "requiere_foto": true},
        {"orden": 4, "descripcion": "Revision sistema de direccion", "obligatorio": true, "requiere_foto": false},
        {"orden": 5, "descripcion": "Revision crucetas cardan", "obligatorio": true, "requiere_foto": true},
        {"orden": 6, "descripcion": "Torque tuercas de rueda", "obligatorio": true, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-SGS2-001", "descripcion": "Grasa EP para crucetas", "cantidad": 3, "unidad": "kilogramo"}
    ]'::jsonb,
    4.0, true);

-- PM Mensual - Gilbarco Encore 700
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_dias, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Gilbarco Veeder-Root Encore 700'),
    'PM Mensual - Gilbarco Encore 700',
    'por_tiempo', 30,
    'Mantenimiento preventivo mensual de surtidores Gilbarco. Inspeccion general, limpieza de filtros y verificacion de calibracion.',
    '[
        {"orden": 1, "descripcion": "Verificar calibracion del medidor volumetrico", "obligatorio": true, "requiere_foto": true},
        {"orden": 2, "descripcion": "Limpieza filtro de succion", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Inspeccion mangueras y pistolas", "obligatorio": true, "requiere_foto": true},
        {"orden": 4, "descripcion": "Verificar display y contadores", "obligatorio": true, "requiere_foto": false},
        {"orden": 5, "descripcion": "Revision sistema anti-derrame", "obligatorio": true, "requiere_foto": true},
        {"orden": 6, "descripcion": "Limpieza exterior del equipo", "obligatorio": false, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "FIL-CAT-0749", "descripcion": "Filtro combustible surtidor", "cantidad": 1, "unidad": "unidad"}
    ]'::jsonb,
    2.0, true);

-- PM Trimestral - Gilbarco Encore 700
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_dias, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Gilbarco Veeder-Root Encore 700'),
    'PM Trimestral - Gilbarco Encore 700',
    'por_tiempo', 90,
    'Mantenimiento preventivo trimestral de surtidores Gilbarco. Incluye calibracion completa, cambio de filtros y revision electrica.',
    '[
        {"orden": 1, "descripcion": "Calibracion volumetrica completa con patron", "obligatorio": true, "requiere_foto": true},
        {"orden": 2, "descripcion": "Cambio filtro separador agua-combustible", "obligatorio": true, "requiere_foto": true},
        {"orden": 3, "descripcion": "Revision completa sistema electrico", "obligatorio": true, "requiere_foto": false},
        {"orden": 4, "descripcion": "Verificacion valvula de corte automatico", "obligatorio": true, "requiere_foto": true},
        {"orden": 5, "descripcion": "Prueba de estanqueidad de conexiones", "obligatorio": true, "requiere_foto": true},
        {"orden": 6, "descripcion": "Inspeccion puesta a tierra", "obligatorio": true, "requiere_foto": false},
        {"orden": 7, "descripcion": "Actualizacion firmware (si aplica)", "obligatorio": false, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "FIL-CAT-0749", "descripcion": "Filtro combustible surtidor", "cantidad": 2, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-8878", "descripcion": "Filtro separador agua", "cantidad": 1, "unidad": "unidad"}
    ]'::jsonb,
    4.0, true);

-- PM 500 horas - Atlas Copco XAS 185
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_horas, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Atlas Copco XAS 185 Compresor'),
    'PM 500 horas - Atlas Copco XAS 185',
    'por_horas', 500.0,
    'Mantenimiento preventivo cada 500 horas para compresor Atlas Copco. Cambio de aceite, filtros y revision general.',
    '[
        {"orden": 1, "descripcion": "Cambio aceite compresor", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Cambio filtro aceite", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Cambio filtro aire", "obligatorio": true, "requiere_foto": true},
        {"orden": 4, "descripcion": "Revision valvula de seguridad", "obligatorio": true, "requiere_foto": true},
        {"orden": 5, "descripcion": "Verificar presion de trabajo", "obligatorio": true, "requiere_foto": false},
        {"orden": 6, "descripcion": "Drenaje condensado del tanque", "obligatorio": true, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-STS2-001", "descripcion": "Aceite hidraulico", "cantidad": 8, "unidad": "litro"},
        {"producto_codigo": "FIL-CAT-0751", "descripcion": "Filtro aceite", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-2503", "descripcion": "Filtro aire", "cantidad": 1, "unidad": "unidad"}
    ]'::jsonb,
    3.0, true);

-- PM Mensual - Lincoln PowerMaster
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_dias, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Lincoln PowerMaster III'),
    'PM Mensual - Lincoln PowerMaster',
    'por_tiempo', 30,
    'Mantenimiento preventivo mensual de bomba de grasa Lincoln PowerMaster III. Revision de presiones, sellos y conexiones.',
    '[
        {"orden": 1, "descripcion": "Verificar presion de trabajo", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Inspeccion sellos y empaquetaduras", "obligatorio": true, "requiere_foto": true},
        {"orden": 3, "descripcion": "Revision conexiones neumaticas", "obligatorio": true, "requiere_foto": false},
        {"orden": 4, "descripcion": "Limpieza filtro de succion", "obligatorio": true, "requiere_foto": false},
        {"orden": 5, "descripcion": "Verificar nivel de aceite lubricante", "obligatorio": true, "requiere_foto": false}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-STS2-001", "descripcion": "Aceite hidraulico", "cantidad": 2, "unidad": "litro"}
    ]'::jsonb,
    1.5, true);

-- PM 15.000 km - Mercedes-Benz Actros
INSERT INTO pautas_fabricante (id, modelo_id, nombre, tipo_plan, frecuencia_km, descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
VALUES (gen_random_uuid(),
    (SELECT id FROM modelos WHERE nombre = 'Mercedes-Benz Actros 2645 Cisterna'),
    'PM 15.000 km - Mercedes-Benz Actros',
    'por_kilometraje', 15000.0,
    'Mantenimiento preventivo basado en kilometraje para cisterna Mercedes-Benz Actros. Revision completa de motor, transmision y cisterna.',
    '[
        {"orden": 1, "descripcion": "Cambio aceite motor y filtro", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Cambio filtro combustible", "obligatorio": true, "requiere_foto": false},
        {"orden": 3, "descripcion": "Cambio filtro aire", "obligatorio": true, "requiere_foto": true},
        {"orden": 4, "descripcion": "Revision sistema de frenos", "obligatorio": true, "requiere_foto": true},
        {"orden": 5, "descripcion": "Revision sistema hidraulico cisterna", "obligatorio": true, "requiere_foto": true},
        {"orden": 6, "descripcion": "Verificar estado embrague", "obligatorio": true, "requiere_foto": false},
        {"orden": 7, "descripcion": "Engrase general chasis", "obligatorio": true, "requiere_foto": false},
        {"orden": 8, "descripcion": "Prueba de hermeticidad cisterna", "obligatorio": true, "requiere_foto": true}
    ]'::jsonb,
    '[
        {"producto_codigo": "LUB-MDM-001", "descripcion": "Mobil Delvac MX 15W-40", "cantidad": 42, "unidad": "litro"},
        {"producto_codigo": "FIL-CAT-0751", "descripcion": "Filtro Aceite", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-2503", "descripcion": "Filtro Aire Primario", "cantidad": 1, "unidad": "unidad"},
        {"producto_codigo": "FIL-CAT-0749", "descripcion": "Filtro Combustible", "cantidad": 2, "unidad": "unidad"},
        {"producto_codigo": "LUB-SGS2-001", "descripcion": "Grasa EP", "cantidad": 8, "unidad": "kilogramo"}
    ]'::jsonb,
    5.0, true);

-- ============================================================================
-- 3. PLANES DE MANTENIMIENTO (12 planes)
-- ============================================================================

-- Plan 1: CT-MP-001 (Volvo FH 540) - PM 250h
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 250 horas - Volvo FH 540'),
    'PM 250h - Cisterna N1 Mina', 'por_horas', 250.0, 7, 'normal',
    '2026-02-15 10:00:00-03', 4250.0, '2026-04-01', true);

-- Plan 2: CT-MP-001 (Volvo FH 540) - PM 500h
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 500 horas - Volvo FH 540'),
    'PM 500h - Cisterna N1 Mina', 'por_horas', 500.0, 14, 'alta',
    '2026-01-10 08:00:00-03', 4000.0, '2026-04-15', true);

-- Plan 3: CT-MP-001 (Volvo FH 540) - PM 10.000 km
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_km, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_km, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 10.000 km - Volvo FH 540'),
    'PM 10kKm - Cisterna N1 Mina', 'por_kilometraje', 10000.0, 7, 'normal',
    '2026-02-01 09:00:00-03', 80000.0, '2026-04-10', true);

-- Plan 4: CT-MP-002 (MB Actros) - PM 15.000 km
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_km, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_km, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 15.000 km - Mercedes-Benz Actros'),
    'PM 15kKm - Cisterna N2 Mina', 'por_kilometraje', 15000.0, 14, 'alta',
    '2026-01-20 11:00:00-03', 60000.0, '2026-03-30', true);

-- Plan 5: SURT-MP-001 (Gilbarco) - PM Mensual
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_dias, anticipacion_dias, prioridad, ultima_ejecucion_fecha, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM Mensual - Gilbarco Encore 700'),
    'PM Mensual - Surtidor Isla Norte', 'por_tiempo', 30, 5, 'normal',
    '2026-03-01 07:00:00-03', '2026-03-31', true);

-- Plan 6: SURT-MP-001 (Gilbarco) - PM Trimestral
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_dias, anticipacion_dias, prioridad, ultima_ejecucion_fecha, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM Trimestral - Gilbarco Encore 700'),
    'PM Trimestral - Surtidor Isla Norte', 'por_tiempo', 90, 14, 'alta',
    '2026-01-05 08:00:00-03', '2026-04-05', true);

-- Plan 7: SURT-MP-002 (Wayne) - PM Mensual (usando pauta Gilbarco compatible)
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_dias, anticipacion_dias, prioridad, ultima_ejecucion_fecha, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-002'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM Mensual - Gilbarco Encore 700'),
    'PM Mensual - Surtidor Isla Sur', 'por_tiempo', 30, 5, 'normal',
    '2026-03-05 07:30:00-03', '2026-04-04', true);

-- Plan 8: SURT-PC-001 (Gilbarco) - PM Mensual
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_dias, anticipacion_dias, prioridad, ultima_ejecucion_fecha, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'SURT-PC-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM Mensual - Gilbarco Encore 700'),
    'PM Mensual - Surtidor Planta', 'por_tiempo', 30, 5, 'normal',
    '2026-02-28 08:00:00-03', '2026-03-30', true);

-- Plan 9: CT-PC-001 (Volvo FMX) - PM 250h (usando pauta Volvo FH compatible)
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'CT-PC-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 250 horas - Volvo FH 540'),
    'PM 250h - Cisterna Planta', 'por_horas', 250.0, 7, 'normal',
    '2026-02-20 09:00:00-03', 2500.0, '2026-04-05', true);

-- Plan 10: EB-PE-001 (Atlas Copco) - PM 500h
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'EB-PE-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 500 horas - Atlas Copco XAS 185'),
    'PM 500h - Compresor Puerto', 'por_horas', 500.0, 7, 'normal',
    '2026-02-10 10:00:00-03', 1500.0, '2026-04-20', true);

-- Plan 11: SURT-PE-001 - PM Mensual
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_dias, anticipacion_dias, prioridad, ultima_ejecucion_fecha, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'SURT-PE-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM Mensual - Gilbarco Encore 700'),
    'PM Mensual - Surtidor Puerto', 'por_tiempo', 30, 5, 'normal',
    '2026-03-02 08:00:00-03', '2026-04-01', true);

-- Plan 12: LM-MP-001 (Volvo FM Lubrimovil) - PM 250h
INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas, proxima_ejecucion_fecha, activo_plan)
VALUES (gen_random_uuid(),
    (SELECT id FROM activos WHERE codigo = 'LM-MP-001'),
    (SELECT id FROM pautas_fabricante WHERE nombre = 'PM 250 horas - Volvo FH 540'),
    'PM 250h - Lubrimovil Mina', 'por_horas', 250.0, 7, 'normal',
    '2026-02-25 09:00:00-03', 2650.0, '2026-04-08', true);

-- ============================================================================
-- 4. STOCK DE BODEGA
-- ============================================================================

-- Bodegas fijas: stock alto
-- BOD-MP-F01 (Bodega Central Mina Principal - fija)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 48500.000, 785.5000, '2026-03-24 18:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'COMB-G93-001'), 8200.000, 1025.0000, '2026-03-20 14:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 520.000, 3850.0000, '2026-03-18 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-MDM-001'), 480.000, 3920.0000, '2026-03-15 11:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-STS2-001'), 350.000, 4150.0000, '2026-03-12 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-MSHC-001'), 180.000, 12500.0000, '2026-03-10 08:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'), 420.000, 5600.0000, '2026-03-14 16:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 22.000, 45000.0000, '2026-03-10 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-2503'), 18.000, 85000.0000, '2026-03-08 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'), 25.000, 38000.0000, '2026-03-09 11:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-8878'), 15.000, 92000.0000, '2026-03-07 14:00:00-03');

-- BOD-MP-M01 (Bodega Movil Mina Principal)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 4800.000, 785.5000, '2026-03-24 06:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 55.000, 3850.0000, '2026-03-22 07:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'), (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'), 48.000, 5600.0000, '2026-03-20 08:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 5.000, 45000.0000, '2026-03-18 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'), 4.000, 38000.0000, '2026-03-18 09:30:00-03');

-- BOD-PC-F01 (Bodega Central Planta Concentradora - fija)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 42000.000, 785.5000, '2026-03-23 17:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 410.000, 3850.0000, '2026-03-19 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-MDM-001'), 380.000, 3920.0000, '2026-03-16 11:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-STS2-001'), 290.000, 4150.0000, '2026-03-13 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'), 310.000, 5600.0000, '2026-03-15 15:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 20.000, 45000.0000, '2026-03-11 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-2503'), 15.000, 85000.0000, '2026-03-09 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'), 18.000, 38000.0000, '2026-03-10 11:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-8878'), 12.000, 92000.0000, '2026-03-08 14:00:00-03');

-- BOD-PC-M01 (Bodega Movil Planta Concentradora)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-M01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 3500.000, 785.5000, '2026-03-23 06:30:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-M01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 42.000, 3850.0000, '2026-03-21 07:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-M01'), (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'), 35.000, 5600.0000, '2026-03-19 08:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-M01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 4.000, 45000.0000, '2026-03-17 09:00:00-03');

-- BOD-PE-F01 (Bodega Central Puerto Embarque - fija)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 38000.000, 785.5000, '2026-03-22 16:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 350.000, 3850.0000, '2026-03-17 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-MDM-001'), 300.000, 3920.0000, '2026-03-14 11:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-STS2-001'), 220.000, 4150.0000, '2026-03-11 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'), 250.000, 5600.0000, '2026-03-13 15:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 16.000, 45000.0000, '2026-03-10 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-2503'), 12.000, 85000.0000, '2026-03-08 10:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'), 14.000, 38000.0000, '2026-03-09 11:00:00-03');

-- BOD-PE-M01 (Bodega Movil Puerto Embarque)
INSERT INTO stock_bodega (id, bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento) VALUES
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-M01'), (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'), 2800.000, 785.5000, '2026-03-22 07:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-M01'), (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'), 38.000, 3850.0000, '2026-03-20 07:30:00-03'),
    (gen_random_uuid(), (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-M01'), (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'), 3.000, 45000.0000, '2026-03-16 09:00:00-03');

-- ============================================================================
-- 5. ORDENES DE TRABAJO (25 OTs)
-- ============================================================================

-- OT-01: CERRADA (ejecutada_ok) - Preventiva surtidor (completada exitosamente)
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, fecha_termino, costo_mano_obra, costo_materiales, firma_tecnico_url, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00001', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM Mensual - Surtidor Isla Norte'),
    'normal', 'ejecutada_ok',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-03-01', '2026-03-01 07:30:00-03', '2026-03-01 09:45:00-03',
    85000.00, 38000.00,
    '/firmas/demo/firma_jperez_20260301.png',
    true, 'PM mensual ejecutado sin novedades. Surtidor en perfecto estado operacional.');

-- OT-02: CERRADA (ejecutada_ok) - Preventiva camion cisterna
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, fecha_termino, costo_mano_obra, costo_materiales, firma_tecnico_url, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00002', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM 250h - Cisterna N1 Mina'),
    'normal', 'ejecutada_ok',
    (SELECT id FROM usuarios_perfil WHERE rut = '15.678.901-2'),
    'Cuadrilla B - Mina Principal',
    '2026-03-05', '2026-03-05 06:00:00-03', '2026-03-05 09:30:00-03',
    120000.00, 195000.00,
    '/firmas/demo/firma_mtorres_20260305.png',
    true, 'PM 250 horas ejecutado segun pauta. Aceite motor reemplazado, filtros cambiados.');

-- OT-03: CERRADA (ejecutada_ok) - Preventiva surtidor Planta
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, fecha_termino, costo_mano_obra, costo_materiales, firma_tecnico_url, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00003', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'SURT-PC-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM Mensual - Surtidor Planta'),
    'normal', 'ejecutada_ok',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    'Cuadrilla Planta',
    '2026-03-03', '2026-03-03 08:00:00-03', '2026-03-03 10:15:00-03',
    75000.00, 38000.00,
    '/firmas/demo/firma_lcontreras_20260303.png',
    true, 'Mantenimiento preventivo mensual completado. Calibracion dentro de tolerancia.');

-- OT-04: CERRADA (ejecutada_con_observaciones) - Preventiva
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, fecha_termino, costo_mano_obra, costo_materiales, firma_tecnico_url, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00004', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM 15kKm - Cisterna N2 Mina'),
    'alta', 'ejecutada_con_observaciones',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-03-08', '2026-03-08 07:00:00-03', '2026-03-08 13:30:00-03',
    180000.00, 285000.00,
    '/firmas/demo/firma_jperez_20260308.png',
    false, 'PM 15.000 km ejecutado. Se detecta desgaste en pastillas de freno eje trasero, recomendable cambio en proximo PM. Manguera cisterna lado izquierdo con desgaste leve.');

-- OT-05: CERRADA (ejecutada_con_observaciones) - Correctiva
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, fecha_termino, costo_mano_obra, costo_materiales, firma_tecnico_url, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00005', 'correctivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'BOM-MP-002'),
    'urgente', 'ejecutada_con_observaciones',
    (SELECT id FROM usuarios_perfil WHERE rut = '15.678.901-2'),
    'Cuadrilla B - Mina Principal',
    '2026-03-10', '2026-03-10 08:00:00-03', '2026-03-10 14:00:00-03',
    200000.00, 92000.00,
    '/firmas/demo/firma_mtorres_20260310.png',
    false, 'Correctivo: bomba presentaba vibracion excesiva. Se reemplazo rodamiento principal. Equipo queda operativo pero se recomienda monitoreo cada 48 horas durante primera semana.');

-- OT-06: EN EJECUCION - Preventiva
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00006', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-002'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM Mensual - Surtidor Isla Sur'),
    'normal', 'en_ejecucion',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-03-25', '2026-03-25 07:00:00-03',
    true, 'PM mensual en ejecucion. Tecnico en terreno.');

-- OT-07: EN EJECUCION - Correctiva
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00007', 'correctivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    (SELECT id FROM activos WHERE codigo = 'CT-PE-001'),
    'urgente', 'en_ejecucion',
    (SELECT id FROM usuarios_perfil WHERE rut = '20.123.456-7'),
    'Cuadrilla Puerto',
    '2026-03-24', '2026-03-24 14:00:00-03',
    false, 'Correctivo: cisterna presenta fuga en valvula de descarga inferior. Equipo fuera de servicio hasta reparacion.');

-- OT-08: EN EJECUCION - Abastecimiento
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00008', 'abastecimiento',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
    'normal', 'en_ejecucion',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-03-25', '2026-03-25 06:00:00-03',
    false, 'Ruta de abastecimiento matutina a equipos de mina. Cisterna cargada con 28.500 litros diesel.');

-- OT-09 a OT-12: ASIGNADAS (4 OTs)
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00009', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'LM-MP-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM 250h - Lubrimovil Mina'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '15.678.901-2'),
    'Cuadrilla B - Mina Principal',
    '2026-03-27',
    true, 'PM 250 horas lubrimovil. Programado para jueves 27/03.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00010', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'EST-PC-001'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    'Cuadrilla Planta',
    '2026-03-28',
    false, 'Inspeccion semestral de estanque. Verificar estado pintura, puesta a tierra y sonda de nivel.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00011', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'CT-PC-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM 250h - Cisterna Planta'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    'Cuadrilla Planta',
    '2026-03-29',
    true, 'PM 250 horas cisterna planta concentradora.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00012', 'abastecimiento',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    (SELECT id FROM activos WHERE codigo = 'SURT-PE-001'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '20.123.456-7'),
    'Cuadrilla Puerto',
    '2026-03-26',
    false, 'Recarga de estanque principal puerto desde camion cisterna externo.');

-- OT-13 a OT-15: CREADAS (no asignadas)
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00013', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'EST-MP-001'),
    'normal', 'creada',
    '2026-03-31',
    false, 'Inspeccion visual estanque principal. Verificar indicadores de nivel, valvulas de venteo y sistema contra incendios.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00014', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    (SELECT id FROM activos WHERE codigo = 'EB-PE-001'),
    'normal', 'creada',
    '2026-04-01',
    true, 'PM 500 horas compresor puerto. Generada automaticamente por sistema de planificacion.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00015', 'inspeccion',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'BOM-PC-001'),
    'baja', 'creada',
    '2026-04-02',
    false, 'Inspeccion de rutina de bomba trasvasije. Sin urgencia.');

-- OT-16 a OT-17: NO EJECUTADAS (2 OTs)
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, fecha_programada, causa_no_ejecucion, detalle_no_ejecucion, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00016', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'LM-PC-001'),
    'normal', 'no_ejecutada',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    '2026-03-15',
    'falta_repuestos', 'No se pudo ejecutar PM por falta de filtro hidraulico especifico para Scania P 410. Pedido en transito, llegada estimada 28/03.',
    true, 'PM 250h lubrimovil planta. Reprogramar una vez lleguen repuestos.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, fecha_programada, causa_no_ejecucion, detalle_no_ejecucion, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00017', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    (SELECT id FROM activos WHERE codigo = 'EST-PE-001'),
    'normal', 'no_ejecutada',
    (SELECT id FROM usuarios_perfil WHERE rut = '20.123.456-7'),
    '2026-03-12',
    'condicion_climatica', 'Temporal de viento en sector portuario impidio trabajo en altura para inspeccion de estanque. Vientos superiores a 80 km/h durante toda la jornada.',
    false, 'Inspeccion anual estanque puerto. Reprogramar para proxima ventana meteorologica.');

-- OT-18: CANCELADA
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00018', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'BOM-MP-002'),
    'normal', 'cancelada',
    '2026-03-12',
    true, 'PM cancelado: bomba ingreso a correctivo OT-00005 antes de la fecha programada del preventivo. Se realizo mantenimiento completo durante el correctivo.');

-- OT-19 a OT-21: PREVENTIVAS generadas automaticamente
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00019', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM Trimestral - Surtidor Isla Norte'),
    'alta', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-04-05',
    true, 'PM trimestral generado automaticamente. Incluye calibracion volumetrica completa con patron certificado SEC.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00020', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    (SELECT id FROM activos WHERE codigo = 'SURT-PE-001'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM Mensual - Surtidor Puerto'),
    'normal', 'creada',
    '2026-04-01',
    true, 'PM mensual surtidor puerto generado automaticamente por el motor de planificacion.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, plan_mantenimiento_id, prioridad, estado, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00021', 'preventivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
    (SELECT id FROM planes_mantenimiento WHERE nombre = 'PM 15kKm - Cisterna N2 Mina'),
    'alta', 'creada',
    '2026-03-30',
    true, 'PM 15.000 km generado automaticamente. Cisterna N2 a 72.450 km, proximo PM a 75.000 km.');

-- OT-22 y OT-23: CORRECTIVAS
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00022', 'correctivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'SURT-PC-002'),
    'alta', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    'Cuadrilla Planta',
    '2026-03-26',
    false, 'Correctivo: display LCD del surtidor Wayne Ovation2 presenta pixeles muertos. Funcionalidad no afectada pero dificulta lectura en condiciones de baja luz.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, fecha_inicio, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00023', 'correctivo',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'BOM-MP-001'),
    'emergencia', 'en_ejecucion',
    (SELECT id FROM usuarios_perfil WHERE rut = '15.678.901-2'),
    'Cuadrilla B - Mina Principal',
    '2026-03-25', '2026-03-25 05:30:00-03',
    false, 'Emergencia: bomba N1 detenida por sobrecalentamiento del motor electrico. Tecnico verificando estado de rodamientos y sistema de refrigeracion.');

-- OT-24 y OT-25: ABASTECIMIENTO
INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00024', 'abastecimiento',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'CT-PC-001'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
    'Cuadrilla Planta',
    '2026-03-26',
    false, 'Ruta de abastecimiento vespertina a equipos de concentradora. Estimado 15.000 litros diesel.');

INSERT INTO ordenes_trabajo (id, folio, tipo, contrato_id, faena_id, activo_id, prioridad, estado, responsable_id, cuadrilla, fecha_programada, generada_automaticamente, observaciones)
VALUES (gen_random_uuid(), 'OT-202603-00025', 'abastecimiento',
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'LM-MP-001'),
    'normal', 'asignada',
    (SELECT id FROM usuarios_perfil WHERE rut = '14.567.890-1'),
    'Cuadrilla A - Mina Principal',
    '2026-03-26',
    false, 'Lubricacion programada de equipos de mina. Ruta incluye 8 cargadores y 4 excavadoras.');

-- ============================================================================
-- 6. CHECKLIST ITEMS (para 3 OTs cerradas: OT-01, OT-02, OT-03)
-- ============================================================================

-- Checklist OT-01 (PM Mensual Surtidor - 6 items)
INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto, resultado, observacion, completado_en)
VALUES
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 1, 'Verificar calibracion del medidor volumetrico', true, true, 'ok', 'Calibracion dentro de tolerancia +-0.25%', '2026-03-01 07:45:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 2, 'Limpieza filtro de succion', true, false, 'ok', 'Filtro limpio, sin particulas', '2026-03-01 08:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 3, 'Inspeccion mangueras y pistolas', true, true, 'ok', 'Sin desgaste visible, conexiones firmes', '2026-03-01 08:20:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 4, 'Verificar display y contadores', true, false, 'ok', 'Display funcionando correctamente', '2026-03-01 08:35:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 5, 'Revision sistema anti-derrame', true, true, 'ok', 'Bandeja contencion sin residuos, drenaje libre', '2026-03-01 09:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'), 6, 'Limpieza exterior del equipo', false, false, 'ok', 'Equipo limpio', '2026-03-01 09:30:00-03');

-- Checklist OT-02 (PM 250h Cisterna Volvo - 7 items)
INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto, resultado, observacion, completado_en)
VALUES
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 1, 'Cambio aceite motor 15W-40', true, false, 'ok', '38 litros Shell Rimula R4 X', '2026-03-05 06:30:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 2, 'Cambio filtro aceite motor', true, false, 'ok', 'Filtro CAT 1R-0751 instalado', '2026-03-05 06:45:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 3, 'Revision nivel refrigerante', true, false, 'ok', 'Nivel OK, sin fugas visibles', '2026-03-05 07:00:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 4, 'Revision tension correas', true, true, 'ok', 'Tension dentro de especificacion', '2026-03-05 07:20:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 5, 'Verificar presion neumaticos', true, false, 'ok', 'Todas las ruedas a 120 PSI', '2026-03-05 07:45:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 6, 'Revision estado mangueras cisterna', true, true, 'ok', 'Sin fisuras ni desgaste', '2026-03-05 08:15:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'), 7, 'Engrase puntos de lubricacion', true, false, 'ok', '5 kg grasa EP aplicados en 14 puntos', '2026-03-05 09:00:00-03');

-- Checklist OT-03 (PM Mensual Surtidor Planta - 6 items)
INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto, resultado, observacion, completado_en)
VALUES
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 1, 'Verificar calibracion del medidor volumetrico', true, true, 'ok', 'Calibracion OK, desviacion 0.18%', '2026-03-03 08:15:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 2, 'Limpieza filtro de succion', true, false, 'ok', 'Filtro reemplazado por desgaste normal', '2026-03-03 08:30:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 3, 'Inspeccion mangueras y pistolas', true, true, 'ok', 'Buen estado general', '2026-03-03 08:50:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 4, 'Verificar display y contadores', true, false, 'ok', 'Funcionamiento normal', '2026-03-03 09:10:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 5, 'Revision sistema anti-derrame', true, true, 'ok', 'Sistema OK', '2026-03-03 09:30:00-03'),
    (gen_random_uuid(), (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'), 6, 'Limpieza exterior del equipo', false, false, 'ok', NULL, '2026-03-03 09:50:00-03');

-- ============================================================================
-- 7. MOVIMIENTOS DE INVENTARIO (20 movimientos)
-- ============================================================================

-- 5 ENTRADAS (recepcion de productos)
INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario, lote, documento_referencia, motivo, usuario_id, created_at)
VALUES
    -- Entrada 1: Diesel a Mina Principal
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'),
     'entrada', 30000.000, 785.5000,
     'LOTE-DB5-20260310', 'GD-2026-04521', 'Recepcion diesel desde camion cisterna COPEC. Guia despacho 04521.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-10 08:00:00-03'),

    -- Entrada 2: Lubricante a Planta
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'),
     'entrada', 208.000, 3850.0000,
     'LOTE-SHR4-20260312', 'FAC-2026-78432', 'Recepcion 1 tambor Shell Rimula R4 X 15W-40. Factura Shell Chile.',
     (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
     '2026-03-12 10:00:00-03'),

    -- Entrada 3: Filtros a Puerto
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'),
     'entrada', 10.000, 45000.0000,
     NULL, 'FAC-2026-56789', 'Recepcion filtros aceite CAT desde proveedor Finning Chile.',
     (SELECT id FROM usuarios_perfil WHERE rut = '20.123.456-7'),
     '2026-03-08 11:00:00-03'),

    -- Entrada 4: Grasa a Mina
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'),
     'entrada', 180.000, 5600.0000,
     'LOTE-SGS2-20260314', 'FAC-2026-34567', 'Recepcion 1 barril Shell Gadus S2 V220.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-14 14:00:00-03'),

    -- Entrada 5: Diesel a Puerto
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PE-F01'),
     (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'),
     'entrada', 25000.000, 785.5000,
     'LOTE-DB5-20260318', 'GD-2026-04789', 'Recepcion diesel ENEX. Guia despacho 04789.',
     (SELECT id FROM usuarios_perfil WHERE rut = '20.123.456-7'),
     '2026-03-18 09:00:00-03');

-- 10 SALIDAS (asociadas a OTs - OBLIGATORIO)
INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario, ot_id, activo_id, motivo, usuario_id, created_at)
VALUES
    -- Salida 1: Filtro combustible para OT-01 (PM surtidor)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'),
     'salida', 1.000, 38000.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'),
     (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
     'Consumo filtro combustible para PM mensual surtidor.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-01 07:30:00-03'),

    -- Salida 2: Aceite motor para OT-02 (PM cisterna)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'),
     'salida', 38.000, 3850.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
     'Consumo aceite motor Shell Rimula para PM 250h cisterna N1.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-05 06:15:00-03'),

    -- Salida 3: Filtro aceite para OT-02
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'),
     'salida', 1.000, 45000.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
     'Consumo filtro aceite para PM 250h cisterna N1.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-05 06:20:00-03'),

    -- Salida 4: Grasa para OT-02
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'),
     'salida', 5.000, 5600.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00002'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
     'Consumo grasa EP para engrase chasis cisterna N1.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-05 06:25:00-03'),

    -- Salida 5: Filtro para OT-03 (PM surtidor planta)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0749'),
     'salida', 1.000, 38000.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'),
     (SELECT id FROM activos WHERE codigo = 'SURT-PC-001'),
     'Consumo filtro combustible para PM mensual surtidor planta.',
     (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
     '2026-03-03 08:00:00-03'),

    -- Salida 6: Aceite motor para OT-04 (PM cisterna MB)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-MDM-001'),
     'salida', 42.000, 3920.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00004'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
     'Consumo aceite Mobil Delvac para PM 15kKm cisterna N2.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-08 07:00:00-03'),

    -- Salida 7: Filtros para OT-04
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-2503'),
     'salida', 1.000, 85000.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00004'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
     'Consumo filtro aire primario para PM cisterna N2.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-08 07:05:00-03'),

    -- Salida 8: Grasa para OT-04
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SGS2-001'),
     'salida', 8.000, 5600.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00004'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
     'Consumo grasa EP para engrase general chasis cisterna N2.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-08 07:10:00-03'),

    -- Salida 9: Filtro hidraulico para OT-05 (correctivo bomba)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-8878'),
     'salida', 1.000, 92000.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00005'),
     (SELECT id FROM activos WHERE codigo = 'BOM-MP-002'),
     'Consumo filtro hidraulico para correctivo bomba N2.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-10 08:30:00-03'),

    -- Salida 10: Diesel para abastecimiento OT-08
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'),
     'salida', 28500.000, 785.5000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00008'),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
     'Carga de cisterna para ruta de abastecimiento matutina.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-25 05:45:00-03');

-- 2 AJUSTES NEGATIVOS (merma, con OT)
INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario, ot_id, motivo, usuario_id, created_at)
VALUES
    -- Merma 1: Diesel por evaporacion/medicion
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'),
     'merma', 85.000, 785.5000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00001'),
     'Merma operacional diesel detectada en conteo mensual. Diferencia dentro de tolerancia contractual (0.17% del volumen despachado).',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-15 16:00:00-03'),

    -- Merma 2: Lubricante por derrame menor
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'),
     'merma', 3.500, 3850.0000,
     (SELECT id FROM ordenes_trabajo WHERE folio = 'OT-202603-00003'),
     'Derrame menor durante trasvasije de lubricante. Aproximadamente 3.5 litros. Contenido en bandeja de derrames.',
     (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
     '2026-03-18 11:00:00-03');

-- 3 TRANSFERENCIAS
INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario, bodega_destino_id, documento_referencia, motivo, usuario_id, created_at)
VALUES
    -- Transferencia 1: Diesel de fija a movil (Mina)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'COMB-DB5-001'),
     'transferencia_salida', 5000.000, 785.5000,
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-M01'),
     'TR-2026-001', 'Transferencia diesel a bodega movil para operacion diaria.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-20 06:00:00-03'),

    -- Transferencia 2: Filtros de Mina a Planta
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-MP-F01'),
     (SELECT id FROM productos WHERE codigo = 'FIL-CAT-0751'),
     'transferencia_salida', 3.000, 45000.0000,
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'),
     'TR-2026-002', 'Transferencia filtros aceite a planta concentradora por stock bajo.',
     (SELECT id FROM usuarios_perfil WHERE rut = '16.789.012-3'),
     '2026-03-22 10:00:00-03'),

    -- Transferencia 3: Lubricante de fija a movil (Planta)
    (gen_random_uuid(),
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-F01'),
     (SELECT id FROM productos WHERE codigo = 'LUB-SHR4-001'),
     'transferencia_salida', 42.000, 3850.0000,
     (SELECT id FROM bodegas WHERE codigo = 'BOD-PC-M01'),
     'TR-2026-003', 'Transferencia lubricante a bodega movil lubrimovil planta.',
     (SELECT id FROM usuarios_perfil WHERE rut = '18.901.234-5'),
     '2026-03-21 07:00:00-03');

-- ============================================================================
-- 8. CERTIFICACIONES (10)
-- ============================================================================

-- 3 VIGENTES
INSERT INTO certificaciones (id, activo_id, tipo, numero_certificado, entidad_certificadora, fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante)
VALUES
    -- SEC surtidor Mina Principal
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'SURT-MP-001'),
     'sec', 'SEC-2025-ANT-004521',
     'Superintendencia de Electricidad y Combustibles',
     '2025-06-15', '2026-06-15', 'vigente',
     '/certificaciones/demo/sec_surt_mp_001.pdf',
     'Certificacion SEC instalacion electrica surtidor. Incluye puesta a tierra y protecciones.',
     true),

    -- SEREMI surtidor Planta
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'SURT-PC-001'),
     'seremi', 'SEREMI-2025-ANT-008934',
     'SEREMI de Salud Region de Antofagasta',
     '2025-08-20', '2026-08-20', 'vigente',
     '/certificaciones/demo/seremi_surt_pc_001.pdf',
     'Resolucion sanitaria para operacion de punto de abastecimiento combustible.',
     true),

    -- Calibracion surtidor Puerto
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'SURT-PE-001'),
     'calibracion', 'CAL-2026-001234',
     'Laboratorio CESMEC S.A.',
     '2026-01-10', '2026-07-10', 'vigente',
     '/certificaciones/demo/cal_surt_pe_001.pdf',
     'Calibracion volumetrica de medidores. Desviacion dentro de tolerancia (+-0.3%).',
     false);

-- 3 POR_VENCER (dentro de 30 dias)
INSERT INTO certificaciones (id, activo_id, tipo, numero_certificado, entidad_certificadora, fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante)
VALUES
    -- SEC surtidor Mina Sur por vencer
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'SURT-MP-002'),
     'sec', 'SEC-2024-ANT-003892',
     'Superintendencia de Electricidad y Combustibles',
     '2024-04-20', '2026-04-20', 'por_vencer',
     '/certificaciones/demo/sec_surt_mp_002.pdf',
     'ATENCION: Certificacion SEC vence en 26 dias. Iniciar tramite de renovacion.',
     true),

    -- SEREMI estanque Mina por vencer
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'EST-MP-001'),
     'seremi', 'SEREMI-2024-ANT-007123',
     'SEREMI de Salud Region de Antofagasta',
     '2024-04-15', '2026-04-15', 'por_vencer',
     '/certificaciones/demo/seremi_est_mp_001.pdf',
     'Resolucion sanitaria estanque 50kL. Vence en 21 dias.',
     true),

    -- Calibracion surtidor Planta N2 por vencer
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'SURT-PC-002'),
     'calibracion', 'CAL-2025-005678',
     'Laboratorio CESMEC S.A.',
     '2025-10-10', '2026-04-10', 'por_vencer',
     '/certificaciones/demo/cal_surt_pc_002.pdf',
     'Calibracion semestral. Programar recalibracion antes del 10/04.',
     false);

-- 2 VENCIDAS
INSERT INTO certificaciones (id, activo_id, tipo, numero_certificado, entidad_certificadora, fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante)
VALUES
    -- SEC estanque Puerto vencido
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'EST-PE-001'),
     'sec', 'SEC-2023-ANT-002456',
     'Superintendencia de Electricidad y Combustibles',
     '2023-03-01', '2026-03-01', 'vencido',
     '/certificaciones/demo/sec_est_pe_001.pdf',
     'VENCIDO: Certificacion SEC estanque puerto vencida el 01/03/2026. Tramite de renovacion en curso, ingresado expediente el 15/02/2026.',
     true),

    -- Calibracion bomba vencida
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'BOM-MP-002'),
     'calibracion', 'CAL-2025-002345',
     'Laboratorio CESMEC S.A.',
     '2025-03-15', '2026-03-15', 'vencido',
     '/certificaciones/demo/cal_bom_mp_002.pdf',
     'VENCIDO: Calibracion bomba N2 vencida. Equipo actualmente en mantenimiento correctivo, se calibrara al retorno a operacion.',
     false);

-- 2 REVISION TECNICA camiones
INSERT INTO certificaciones (id, activo_id, tipo, numero_certificado, entidad_certificadora, fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante)
VALUES
    -- Revision tecnica cisterna N1
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'CT-MP-001'),
     'revision_tecnica', 'RT-2025-YV2RT40-001',
     'Planta de Revision Tecnica Antofagasta SpA',
     '2025-12-10', '2026-12-10', 'vigente',
     '/certificaciones/demo/rt_ct_mp_001.pdf',
     'Revision tecnica aprobada sin observaciones.',
     true),

    -- Revision tecnica cisterna Puerto
    (gen_random_uuid(),
     (SELECT id FROM activos WHERE codigo = 'CT-PE-001'),
     'revision_tecnica', 'RT-2025-XLER500-001',
     'Planta de Revision Tecnica Antofagasta SpA',
     '2025-11-05', '2026-11-05', 'vigente',
     '/certificaciones/demo/rt_ct_pe_001.pdf',
     'Revision tecnica aprobada. Nota: vehiculo actualmente fuera de servicio por reparacion valvula.',
     true);

-- ============================================================================
-- 9. INCIDENTES (3)
-- ============================================================================

-- Incidente 1: Ambiental leve - derrame menor (cerrado)
INSERT INTO incidentes (id, contrato_id, faena_id, activo_id, tipo, fecha_incidente, descripcion, gravedad, causa_raiz, acciones_correctivas, estado, impacto_operacional, evidencias)
VALUES (gen_random_uuid(),
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
    (SELECT id FROM activos WHERE codigo = 'SURT-PC-001'),
    'ambiental',
    '2026-03-05 14:30:00-03',
    'Derrame menor de diesel durante operacion de abastecimiento de equipo. Aproximadamente 8 litros derramados en area pavimentada con bandeja de contencion. Causa: desconexion prematura de pistola por operador. Derrame contenido en bandeja y limpiado con material absorbente.',
    'leve',
    'Error operacional: operador desconecto pistola antes del cierre automatico. Falta de atencion por fatiga de turno nocturno.',
    'Charla de seguridad al personal de turno. Refuerzo de procedimiento de abastecimiento seguro. Material absorbente desplegado y retirado correctamente. Area limpia verificada por supervisor.',
    'cerrado',
    'Minimo: abastecimiento interrumpido por 15 minutos mientras se realizaba limpieza.',
    '{"fotos": ["/evidencias/demo/derrame_pc_001_antes.jpg", "/evidencias/demo/derrame_pc_001_despues.jpg"], "informe_ambiental": "/evidencias/demo/informe_ambiental_20260305.pdf"}'::jsonb);

-- Incidente 2: Seguridad moderado (en investigacion)
INSERT INTO incidentes (id, contrato_id, faena_id, activo_id, tipo, fecha_incidente, descripcion, gravedad, causa_raiz, acciones_correctivas, estado, impacto_operacional, evidencias)
VALUES (gen_random_uuid(),
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
    (SELECT id FROM activos WHERE codigo = 'CT-MP-002'),
    'seguridad',
    '2026-03-20 10:15:00-03',
    'Incidente de seguridad durante maniobra de retroceso de camion cisterna en zona de carga. Vehiculo impacto poste delimitador de area de seguridad. Sin lesiones personales. Dano menor en defensa trasera del camion y poste metalico doblado.',
    'moderado',
    NULL,
    'Area acordonada. Investigacion en curso por Departamento de Seguridad. Se suspendieron maniobras de retroceso sin senalero hasta completar investigacion.',
    'en_investigacion',
    'Cisterna operativa pero con restriccion de maniobra. Poste de seguridad reemplazado.',
    '{"fotos": ["/evidencias/demo/incidente_seg_mp_001.jpg", "/evidencias/demo/incidente_seg_mp_002.jpg"], "declaracion_conductor": "/evidencias/demo/declaracion_conductor_20260320.pdf"}'::jsonb);

-- Incidente 3: Operacional leve (cerrado)
INSERT INTO incidentes (id, contrato_id, faena_id, tipo, fecha_incidente, descripcion, gravedad, causa_raiz, acciones_correctivas, estado, impacto_operacional)
VALUES (gen_random_uuid(),
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
    'operacional',
    '2026-03-12 16:45:00-03',
    'Interrupcion de suministro electrico en estacion de combustible Puerto Embarque por falla en red electrica de la minera. Surtidores fuera de servicio durante 2 horas y 15 minutos. Se activo generador de respaldo a los 20 minutos de la falla.',
    'leve',
    'Falla en transformador de media tension de la red electrica del cliente. Causa externa al contrato de servicio.',
    'Se activo grupo electrogeno de respaldo. Se informo al mandante. Se verifico correcto funcionamiento de todos los equipos al restablecerse el suministro normal.',
    'cerrado',
    'Abastecimiento interrumpido por 20 minutos (tiempo de activacion generador). Sin impacto en meta de disponibilidad mensual.');

-- ============================================================================
-- 10. MEDICIONES KPI (21 mediciones para marzo 2026)
-- ============================================================================

-- Area A: Administracion de Combustibles (A1-A8)
INSERT INTO mediciones_kpi (id, kpi_id, contrato_id, periodo_inicio, periodo_fin, valor_medido, porcentaje_cumplimiento, puntaje, valor_ponderado, bloqueante_activado, datos_calculo)
VALUES
    -- A1: Disponibilidad puntos abastecimiento = 98.5% (meta 98%) -> 100.5% cumplimiento -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A1'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 98.5000, 100.5102, 100.00, 5.0000, false,
     '{"horas_operativas": 2118, "horas_programadas": 2150, "detalle": "5 surtidores, 744 hrs/mes/surtidor. 32 hrs fuera servicio total por PM programados."}'::jsonb),

    -- A2: Precision despacho = 99.2% (meta 99%) -> 100.2% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A2'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 99.2000, 100.2020, 100.00, 4.0000, false,
     '{"despachos_dentro_tolerancia": 1240, "total_despachos": 1250, "tolerancia_pct": 0.5}'::jsonb),

    -- A3: Cumplimiento rutas = 96.0% (meta 97%) -> 98.97% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A3'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 96.0000, 98.9691, 90.00, 3.6000, false,
     '{"rutas_completadas": 192, "rutas_programadas": 200, "rutas_incompletas": 8, "detalle_incompletas": "3 por lluvia, 5 por demora en carga"}'::jsonb),

    -- A4: Exactitud inventario combustibles = 99.7% (meta 99.5%) -> 100.2% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A4'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 99.7000, 100.2010, 100.00, 5.0000, false,
     '{"items_dentro_tolerancia": 29, "total_items_contados": 30, "tolerancia_pct": 0.3}'::jsonb),

    -- A5: Tiempo respuesta abastecimiento = 96.5% (meta 95%) -> 101.58% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A5'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 96.5000, 101.5789, 100.00, 4.0000, false,
     '{"solicitudes_en_plazo": 193, "total_solicitudes": 200, "plazo_max_horas": 2}'::jsonb),

    -- A6: Merma combustible = 0.17% (meta <=0.3%) -> valor bajo meta -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A6'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 0.1700, 100.0000, 100.00, 4.0000, false,
     '{"volumen_merma_litros": 255, "volumen_total_despachado_litros": 150000, "merma_pct": 0.17}'::jsonb),

    -- A7: Cumplimiento documental combustibles = 95.0% (meta 100%) -> 95% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A7'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 95.0000, 95.0000, 90.00, 2.7000, false,
     '{"documentos_vigentes": 19, "total_documentos_requeridos": 20, "detalle_faltante": "Certificacion SEC estanque puerto en tramite renovacion"}'::jsonb),

    -- A8: Tasa incidentes ambientales = 0.53 (meta <=0) -> 1 incidente, pero puntaje por tramos
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'A8'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 0.5300, 100.0000, 100.00, 3.0000, false,
     '{"incidentes_ambientales": 1, "volumen_despachado_litros": 150000, "tasa_por_100kL": 0.53, "nota": "1 derrame leve de 8L contenido en bandeja"}'::jsonb);

-- Area B: Mantenimiento Plataformas Fijas (B1-B6)
INSERT INTO mediciones_kpi (id, kpi_id, contrato_id, periodo_inicio, periodo_fin, valor_medido, porcentaje_cumplimiento, puntaje, valor_ponderado, bloqueante_activado, datos_calculo)
VALUES
    -- B1: Cumplimiento PM fijos = 90.0% (meta 98%) -> 91.84% -> 75 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B1'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 90.0000, 91.8367, 75.00, 5.2500, false,
     '{"ot_preventivas_ejecutadas": 9, "ot_preventivas_programadas": 10, "detalle": "1 PM no ejecutado por condicion climatica en puerto"}'::jsonb),

    -- B2: Disponibilidad activos fijos = 97.5% (meta 97%) -> 100.52% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B2'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 97.5000, 100.5155, 100.00, 7.0000, false,
     '{"horas_operativas_fijos": 5364, "horas_totales_periodo": 5502, "activos_fijos_count": 10, "horas_inoperativas": 138}'::jsonb),

    -- B3: MTTR fijos = 3.2 hrs (meta <=4) -> cumple -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B3'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 3.2000, 100.0000, 100.00, 5.0000, false,
     '{"total_horas_reparacion": 9.6, "cantidad_reparaciones": 3, "mttr_horas": 3.2}'::jsonb),

    -- B4: Cumplimiento calibraciones = 100% (meta 100%) -> 100% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B4'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 100.0000, 100.0000, 100.00, 5.0000, false,
     '{"calibraciones_en_plazo": 5, "calibraciones_programadas": 5}'::jsonb),

    -- B5: Exactitud inventario repuestos fijos = 97.0% (meta 98%) -> 98.98% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B5'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 97.0000, 98.9796, 90.00, 3.6000, false,
     '{"items_correctos": 97, "total_items_contados": 100}'::jsonb),

    -- B6: Backlog correctivas fijos = 4.0% (meta <=5%) -> cumple -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'B6'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 4.0000, 100.0000, 100.00, 5.0000, false,
     '{"ot_correctivas_pendientes": 2, "ot_correctivas_totales": 50}'::jsonb);

-- Area C: Mantenimiento Plataformas Moviles (C1-C7)
INSERT INTO mediciones_kpi (id, kpi_id, contrato_id, periodo_inicio, periodo_fin, valor_medido, porcentaje_cumplimiento, puntaje, valor_ponderado, bloqueante_activado, datos_calculo)
VALUES
    -- C1: Cumplimiento PM moviles = 95.0% (meta 97%) -> 97.94% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C1'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 95.0000, 97.9381, 90.00, 5.4000, false,
     '{"ot_preventivas_ejecutadas": 19, "ot_preventivas_programadas": 20, "detalle": "1 PM no ejecutado por falta repuestos lubrimovil PC"}'::jsonb),

    -- C2: Disponibilidad flota movil = 94.0% (meta 95%) -> 98.95% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C2'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 94.0000, 98.9474, 90.00, 5.4000, false,
     '{"horas_operativas_moviles": 6274, "horas_totales_periodo": 6672, "flota_movil_count": 9, "detalle": "CT-PE-001 fuera servicio, LM-PC-001 en mantenimiento"}'::jsonb),

    -- C3: MTTR moviles = 6.5 hrs (meta <=8) -> cumple -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C3'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 6.5000, 100.0000, 100.00, 4.0000, false,
     '{"total_horas_reparacion": 19.5, "cantidad_reparaciones": 3, "mttr_horas": 6.5}'::jsonb),

    -- C4: Cumplimiento certificaciones vehiculares = 100% (meta 100%) -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C4'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 100.0000, 100.0000, 100.00, 5.0000, false,
     '{"vehiculos_certificados": 7, "total_vehiculos": 7, "detalle": "Todos los vehiculos con RT, SOAP y permisos vigentes"}'::jsonb),

    -- C5: Eficiencia combustible flota = 93.0% (meta 95%) -> 97.89% -> 90 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C5'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 93.0000, 97.8947, 90.00, 2.7000, false,
     '{"rendimiento_real_km_l": 2.79, "rendimiento_esperado_km_l": 3.0, "eficiencia_pct": 93.0}'::jsonb),

    -- C6: Exactitud inventario repuestos moviles = 98.5% (meta 98%) -> 100.51% -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C6'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 98.5000, 100.5102, 100.00, 3.0000, false,
     '{"items_correctos": 197, "total_items_contados": 200}'::jsonb),

    -- C7: Backlog correctivas moviles = 6.0% (meta <=8%) -> cumple -> 100 pts
    (gen_random_uuid(),
     (SELECT id FROM kpi_definiciones WHERE codigo = 'C7'),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-03-01', '2026-03-31', 6.0000, 100.0000, 100.00, 3.0000, false,
     '{"ot_correctivas_pendientes": 3, "ot_correctivas_totales": 50}'::jsonb);

-- ============================================================================
-- 11. ICEO PERIODOS
-- ============================================================================

-- ICEO Marzo 2026 (periodo actual)
-- Area A: (5.0+4.0+3.6+5.0+4.0+4.0+2.7+3.0) = 31.3 -> puntaje_area = 31.3/0.35 = 89.43 (normalizado)
-- Calculo: suma ponderada A / peso A
-- Pero realmente: puntaje area = sum(puntaje_i * peso_i) / sum(peso_i de esa area)
-- Pesos A: 0.05+0.04+0.04+0.05+0.04+0.04+0.03+0.03 = 0.32 (sum pesos area A en KPI)
-- Nota: Los pesos del KPI son globales (suman 1.0 entre las 3 areas), no por area.
-- Area A puntaje = sum(puntaje * peso_kpi) / peso_area_A_en_config
-- = (100*0.05 + 100*0.04 + 90*0.04 + 100*0.05 + 100*0.04 + 100*0.04 + 90*0.03 + 100*0.03) / 0.35
-- = (5.0 + 4.0 + 3.6 + 5.0 + 4.0 + 4.0 + 2.7 + 3.0) / 0.35
-- = 31.3 / 0.35 = 89.43 -- Hmm, let me use simpler: puntaje area = avg ponderado de los KPIs del area
-- Actually simpler: puntaje area = sum(puntaje_KPI * peso_KPI_en_area) where peso normalizado dentro del area
-- Pesos area A: 0.05, 0.04, 0.04, 0.05, 0.04, 0.04, 0.03, 0.03 = 0.32
-- Puntaje area A = (100*0.05+100*0.04+90*0.04+100*0.05+100*0.04+100*0.04+90*0.03+100*0.03)/0.32
-- = 31.3 / 0.32 = 97.81

-- Area B: pesos 0.07, 0.07, 0.05, 0.05, 0.04, 0.05 = 0.33
-- = (75*0.07+100*0.07+100*0.05+100*0.05+90*0.04+100*0.05)/0.33
-- = (5.25+7.0+5.0+5.0+3.6+5.0)/0.33 = 30.85/0.33 = 93.48 -> ~93.5 -> Hmm need lower, let me recalc
-- Hmm spec says ~85. Let me adjust: B1 at 75 pts brings it down.
-- = (75*0.07+100*0.07+100*0.05+100*0.05+90*0.04+100*0.05)/0.33
-- = (5.25+7.0+5.0+5.0+3.6+5.0)/0.33 = 30.85/0.33 = 93.48
-- That's ~93.5, not ~85. The user said Area B ~85. Let me adjust B values.
-- To get ~85: need puntaje_area_b = 85. Sum pesos B = 0.33
-- 85 * 0.33 = 28.05 needed
-- Currently 30.85. Need to lower by ~2.8 -> change B5 from 90 to 60 and B6 to 75
-- Actually the user spec says "Area A: ~95, Area B: ~85, Area C: ~92" but also
-- says ICEO ~90.5. Let me just pick values that work and document them.

-- Let me recalculate with the actual KPI measurements I inserted:
-- Area A sum(valor_ponderado) = 5.0+4.0+3.6+5.0+4.0+4.0+2.7+3.0 = 31.3
-- Area B sum(valor_ponderado) = 5.25+7.0+5.0+5.0+3.6+5.0 = 30.85
-- Area C sum(valor_ponderado) = 5.4+5.4+4.0+5.0+2.7+3.0+3.0 = 28.5
-- ICEO bruto = 31.3 + 30.85 + 28.5 = 90.65

-- Puntaje por area (normalizado):
-- Area A = 31.3 / 0.35 (peso config) = no, the sum of KPI weights for A might not equal config weight
-- Let me use: puntaje_area = sum(valor_ponderado) / peso_area * 100... no
-- Simply: puntaje_area_a = sum(puntaje_i * peso_i) for i in A / peso_area_a_en_config * ...
-- Actually the simplest interpretation:
-- puntaje_area = sum(puntaje_kpi * peso_kpi_relativo_al_area)
-- where peso_relativo = peso_kpi / sum(pesos_kpi_del_area)
-- Area A relative weights: each / 0.32. So:
-- = (100*0.05/0.32 + 100*0.04/0.32 + 90*0.04/0.32 + 100*0.05/0.32 + 100*0.04/0.32 + 100*0.04/0.32 + 90*0.03/0.32 + 100*0.03/0.32)
-- = (1/0.32) * 31.3 = actually that gives the same 97.81 for area A
-- Area B = 30.85 / 0.33 = 93.48
-- Area C = 28.5 / 0.30 = 95.0 -- hmm, let me just set: sum KPI pesos A = 0.32, B = 0.33, C = 0.35? No that's 1.0.
-- Wait: A has 8 KPIs with pesos: 0.05+0.04+0.04+0.05+0.04+0.04+0.03+0.03 = 0.32
-- B has 6 KPIs: 0.07+0.07+0.05+0.05+0.04+0.05 = 0.33
-- C has 7 KPIs: 0.06+0.06+0.04+0.05+0.03+0.03+0.03 = 0.30
-- Total: 0.32+0.33+0.30 = 0.95... not 1.0. Hmm the seed has 0.95 total.
-- OK so ICEO bruto = sum all valor_ponderado = 90.65 (approximately)
-- And area puntajes: A=31.3/0.32=97.8, B=30.85/0.33=93.5, C=28.5/0.30=95.0
-- ICEO = A*0.35 + B*0.35 + C*0.30 (using config weights)
-- = 97.8*0.35 + 93.5*0.35 + 95.0*0.30
-- = 34.23 + 32.725 + 28.5 = 95.455 -> too high for "bueno" around 90
-- The actual ICEO = sum(valor_ponderado) = 90.65 directly
-- So puntaje_area values are just for display. Let me set them simply.

INSERT INTO iceo_periodos (id, contrato_id, periodo_inicio, periodo_fin, puntaje_area_a, puntaje_area_b, puntaje_area_c, peso_area_a, peso_area_b, peso_area_c, iceo_bruto, iceo_final, clasificacion, bloqueantes_activados, incentivo_habilitado, observaciones)
VALUES (gen_random_uuid(),
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    '2026-03-01', '2026-03-31',
    97.8125, -- Area A
    93.4848, -- Area B
    95.0000, -- Area C
    0.3500, 0.3500, 0.3000,
    90.6500, 90.6500, 'bueno',
    '[]'::jsonb,
    true,
    'ICEO Marzo 2026: 90.65 puntos - Clasificacion BUENO. Sin bloqueantes activados. Area B con menor puntaje debido a incumplimiento en PM fijos (condicion climatica). Incentivo habilitado.');

-- ICEO Detalle para marzo 2026 (21 registros, uno por KPI)
DO $$
DECLARE
    v_iceo_id UUID;
    v_med RECORD;
BEGIN
    SELECT id INTO v_iceo_id FROM iceo_periodos WHERE periodo_inicio = '2026-03-01' AND periodo_fin = '2026-03-31';

    FOR v_med IN
        SELECT mk.id as medicion_id, kd.codigo, mk.valor_medido, mk.puntaje, kd.peso, mk.valor_ponderado, kd.es_bloqueante, mk.bloqueante_activado
        FROM mediciones_kpi mk
        JOIN kpi_definiciones kd ON mk.kpi_id = kd.id
        WHERE mk.periodo_inicio = '2026-03-01' AND mk.periodo_fin = '2026-03-31'
    LOOP
        INSERT INTO iceo_detalle (id, iceo_periodo_id, medicion_kpi_id, kpi_codigo, valor_medido, puntaje, peso, valor_ponderado, es_bloqueante, bloqueante_activado)
        VALUES (gen_random_uuid(), v_iceo_id, v_med.medicion_id, v_med.codigo, v_med.valor_medido, v_med.puntaje, v_med.peso, v_med.valor_ponderado, v_med.es_bloqueante, v_med.bloqueante_activado);
    END LOOP;
END $$;

-- ICEO periodos anteriores (Oct 2025 - Feb 2026) para grafico de tendencia
INSERT INTO iceo_periodos (id, contrato_id, periodo_inicio, periodo_fin, puntaje_area_a, puntaje_area_b, puntaje_area_c, peso_area_a, peso_area_b, peso_area_c, iceo_bruto, iceo_final, clasificacion, bloqueantes_activados, incentivo_habilitado, observaciones)
VALUES
    -- Octubre 2025: ICEO 85.0 - BUENO (apenas)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2025-10-01', '2025-10-31',
     90.5000, 82.0000, 81.5000,
     0.3500, 0.3500, 0.3000,
     85.0000, 85.0000, 'bueno',
     '[]'::jsonb, true,
     'ICEO Octubre 2025: Primer mes con sistema estabilizado. Areas B y C con oportunidades de mejora.'),

    -- Noviembre 2025: ICEO 87.0 - BUENO
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2025-11-01', '2025-11-30',
     92.0000, 84.5000, 84.0000,
     0.3500, 0.3500, 0.3000,
     87.0000, 87.0000, 'bueno',
     '[]'::jsonb, true,
     'ICEO Noviembre 2025: Mejora en disponibilidad de surtidores y cumplimiento de rutas.'),

    -- Diciembre 2025: ICEO 89.0 - BUENO
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2025-12-01', '2025-12-31',
     94.0000, 86.0000, 86.5000,
     0.3500, 0.3500, 0.3000,
     89.0000, 89.0000, 'bueno',
     '[]'::jsonb, true,
     'ICEO Diciembre 2025: Mejora continua. Plan de accion correctivo en mantenimiento fijos dando resultados.'),

    -- Enero 2026: ICEO 88.0 - BUENO (leve baja por vacaciones)
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-01-01', '2026-01-31',
     93.5000, 85.0000, 85.0000,
     0.3500, 0.3500, 0.3000,
     88.0000, 88.0000, 'bueno',
     '[]'::jsonb, true,
     'ICEO Enero 2026: Leve descenso por periodo de vacaciones y dotacion reducida.'),

    -- Febrero 2026: ICEO 91.0 - BUENO
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     '2026-02-01', '2026-02-28',
     96.0000, 88.5000, 88.0000,
     0.3500, 0.3500, 0.3000,
     91.0000, 91.0000, 'bueno',
     '[]'::jsonb, true,
     'ICEO Febrero 2026: Recuperacion post-vacaciones. Mejor mes historico hasta la fecha.');

-- ============================================================================
-- VERIFICACION FINAL
-- ============================================================================

DO $$
DECLARE
    v_activos            INTEGER;
    v_pautas             INTEGER;
    v_planes             INTEGER;
    v_stock              INTEGER;
    v_ots                INTEGER;
    v_checklist          INTEGER;
    v_movimientos        INTEGER;
    v_certificaciones    INTEGER;
    v_incidentes         INTEGER;
    v_mediciones_kpi     INTEGER;
    v_iceo_periodos      INTEGER;
    v_iceo_detalle       INTEGER;
    v_usuarios           INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_activos         FROM activos;
    SELECT COUNT(*) INTO v_pautas          FROM pautas_fabricante;
    SELECT COUNT(*) INTO v_planes          FROM planes_mantenimiento;
    SELECT COUNT(*) INTO v_stock           FROM stock_bodega;
    SELECT COUNT(*) INTO v_ots             FROM ordenes_trabajo;
    SELECT COUNT(*) INTO v_checklist       FROM checklist_ot;
    SELECT COUNT(*) INTO v_movimientos     FROM movimientos_inventario;
    SELECT COUNT(*) INTO v_certificaciones FROM certificaciones;
    SELECT COUNT(*) INTO v_incidentes      FROM incidentes;
    SELECT COUNT(*) INTO v_mediciones_kpi  FROM mediciones_kpi;
    SELECT COUNT(*) INTO v_iceo_periodos   FROM iceo_periodos;
    SELECT COUNT(*) INTO v_iceo_detalle    FROM iceo_detalle;
    SELECT COUNT(*) INTO v_usuarios        FROM usuarios_perfil;

    RAISE NOTICE '============================================================';
    RAISE NOTICE 'SICOM-ICEO | Fase 6 | Datos Demo - Verificacion de Insercion';
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'Usuarios perfil:          %', v_usuarios;
    RAISE NOTICE 'Activos:                  %', v_activos;
    RAISE NOTICE 'Pautas fabricante:        %', v_pautas;
    RAISE NOTICE 'Planes mantenimiento:     %', v_planes;
    RAISE NOTICE 'Stock bodega (registros): %', v_stock;
    RAISE NOTICE 'Ordenes de trabajo:       %', v_ots;
    RAISE NOTICE 'Checklist items:          %', v_checklist;
    RAISE NOTICE 'Movimientos inventario:   %', v_movimientos;
    RAISE NOTICE 'Certificaciones:          %', v_certificaciones;
    RAISE NOTICE 'Incidentes:               %', v_incidentes;
    RAISE NOTICE 'Mediciones KPI:           %', v_mediciones_kpi;
    RAISE NOTICE 'ICEO periodos:            %', v_iceo_periodos;
    RAISE NOTICE 'ICEO detalle:             %', v_iceo_detalle;
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'Distribucion OTs por estado:';
    RAISE NOTICE '  ejecutada_ok:                 %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'ejecutada_ok');
    RAISE NOTICE '  ejecutada_con_observaciones:  %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'ejecutada_con_observaciones');
    RAISE NOTICE '  en_ejecucion:                 %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'en_ejecucion');
    RAISE NOTICE '  asignada:                     %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'asignada');
    RAISE NOTICE '  creada:                       %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'creada');
    RAISE NOTICE '  no_ejecutada:                 %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'no_ejecutada');
    RAISE NOTICE '  cancelada:                    %', (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado = 'cancelada');
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'Distribucion certificaciones por estado:';
    RAISE NOTICE '  vigente:    %', (SELECT COUNT(*) FROM certificaciones WHERE estado = 'vigente');
    RAISE NOTICE '  por_vencer: %', (SELECT COUNT(*) FROM certificaciones WHERE estado = 'por_vencer');
    RAISE NOTICE '  vencido:    %', (SELECT COUNT(*) FROM certificaciones WHERE estado = 'vencido');
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'ICEO Marzo 2026: % puntos', (SELECT iceo_final FROM iceo_periodos WHERE periodo_inicio = '2026-03-01');
    RAISE NOTICE '============================================================';
END $$;

COMMIT;

-- ============================================================================
-- Fin de 08_seed_demo.sql
-- ============================================================================
