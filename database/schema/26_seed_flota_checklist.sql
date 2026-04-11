-- ============================================================================
-- SICOM-ICEO | Migración 26 — Seed Maestro de Flota + Checklist Disponibilidad
-- ============================================================================
-- Fuente: Panel de Control Flota V30 2026 Mes 04-D7.xlsx (hoja "Maestro")
-- 55 vehículos con datos completos de identificación y certificaciones.
-- ============================================================================

-- ============================================================================
-- 1. MARCAS DE VEHÍCULOS (upsert para no duplicar)
-- ============================================================================

INSERT INTO marcas (nombre) VALUES
    ('Mercedes-Benz'),
    ('Mack'),
    ('Volvo'),
    ('Scania'),
    ('Mitsubishi'),
    ('Renault'),
    ('Toyota'),
    ('Yale'),
    ('Maxus'),
    ('Nissan'),
    ('RAM'),
    ('Chevrolet'),
    ('Citroën')
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================================
-- 2. MODELOS DE VEHÍCULOS
-- ============================================================================

INSERT INTO modelos (marca_id, nombre, tipo_activo, especificaciones) VALUES
    -- Mercedes-Benz
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Actros 3336 K', 'camion_cisterna',
     '{"potencia": "360CV/355HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Actros 3341', 'camion_cisterna',
     '{"potencia": "408CV/402HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Axor 2633', 'camion_cisterna',
     '{"potencia": "326CV/321HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Axor 2633/45', 'camion_cisterna',
     '{"potencia": "326CV/321HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Accelo 1016/44', 'camion',
     '{"potencia": "156CV/168HP", "configuracion": "4x2"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'), 'Atego 1624A 4x4', 'camion',
     '{"potencia": "238CV/235HP", "configuracion": "4x4"}'),
    -- Mack
    ((SELECT id FROM marcas WHERE nombre = 'Mack'), 'GU813E Allison', 'camion_cisterna',
     '{"potencia": "389CV/384HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mack'), 'GU813E Mec', 'camion_cisterna',
     '{"potencia": "389CV/384HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mack'), 'GU 813 autom', 'camion_cisterna',
     '{"potencia": "384CV/379HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Mack'), 'GR64BX', 'camion_cisterna',
     '{"potencia": "384CV/379HP", "configuracion": "6x4"}'),
    -- Volvo
    ((SELECT id FROM marcas WHERE nombre = 'Volvo'), 'VM 350', 'camion_cisterna',
     '{"potencia": "350CV/345HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Volvo'), 'FMX 420', 'camion_cisterna',
     '{"potencia": "420CV/414HP", "configuracion": "6x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Volvo'), 'FMX 540', 'camion',
     '{"potencia": "540CV/533HP", "configuracion": "6x4"}'),
    -- Scania
    ((SELECT id FROM marcas WHERE nombre = 'Scania'), 'P450B', 'camion_cisterna',
     '{"potencia": "450CV/444HP", "configuracion": "6x4"}'),
    -- Renault
    ((SELECT id FROM marcas WHERE nombre = 'Renault'), 'C440', 'camion_cisterna',
     '{"potencia": "446CV/440HP", "configuracion": "6x4"}'),
    -- Mitsubishi
    ((SELECT id FROM marcas WHERE nombre = 'Mitsubishi'), 'Canter 7.5', 'camion',
     '{"potencia": "139CV/137HP", "configuracion": "4x2"}'),
    -- Toyota
    ((SELECT id FROM marcas WHERE nombre = 'Toyota'), '02-7FDA50', 'equipo_menor',
     '{"tipo": "grua_horquilla", "capacidad_kg": 7390}'),
    ((SELECT id FROM marcas WHERE nombre = 'Toyota'), 'New Hilux 4x4 2.4 MT DX', 'camioneta',
     '{"configuracion": "4x4", "motor": "2.4L Diesel"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Toyota'), 'Hilux 2.8 Autom', 'camioneta',
     '{"configuracion": "4x4", "motor": "2.8L Diesel"}'),
    -- Yale
    ((SELECT id FROM marcas WHERE nombre = 'Yale'), 'GDP 30TK', 'equipo_menor',
     '{"tipo": "grua_horquilla", "capacidad_kg": 3000}'),
    -- Maxus
    ((SELECT id FROM marcas WHERE nombre = 'Maxus'), 'T60 4x4 DX Plus 6 MT', 'camioneta',
     '{"configuracion": "4x4"}'),
    ((SELECT id FROM marcas WHERE nombre = 'Maxus'), 'T60 4x4 DX', 'camioneta',
     '{"configuracion": "4x4"}'),
    -- Nissan
    ((SELECT id FROM marcas WHERE nombre = 'Nissan'), 'NP300 Dob Cab', 'camioneta',
     '{"configuracion": "4x4"}'),
    -- RAM
    ((SELECT id FROM marcas WHERE nombre = 'RAM'), '1500 LIMITED 5,7L', 'camioneta',
     '{"motor": "5.7L HEMI V8", "configuracion": "4x4"}'),
    -- Chevrolet
    ((SELECT id FROM marcas WHERE nombre = 'Chevrolet'), 'Montana 1.2 MT', 'camioneta',
     '{"configuracion": "4x2", "motor": "1.2L Turbo"}'),
    -- Citroën
    ((SELECT id FROM marcas WHERE nombre = 'Citroën'), 'Berlingo K9 1.6 Diesel', 'camioneta',
     '{"configuracion": "4x2", "motor": "1.6L Diesel"}')
ON CONFLICT (marca_id, nombre) DO NOTHING;

-- ============================================================================
-- 3. ACTIVOS — 55 vehículos del maestro de flota
-- ============================================================================
-- Usamos DO $$ para poder referenciar modelos y marcas dinámicamente

DO $$
DECLARE
    v_contrato_id UUID;
BEGIN
    -- Obtener un contrato existente (o NULL si no hay)
    SELECT id INTO v_contrato_id FROM contratos WHERE activo = true LIMIT 1;

    -- ====================================================================
    -- CAMIONES DE RIEGO (Agua Industrial) — 15 unidades
    -- ====================================================================

    INSERT INTO activos (contrato_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado,
                         patente, centro_costo, vin_chasis, numero_motor, anio_fabricacion, potencia,
                         estado_comercial, operacion, cliente_actual, ubicacion_actual,
                         sistemas_seguridad, fecha_alta)
    VALUES
    -- 1. JTYK-88: M.Benz Actros 3336 K - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3336 K' LIMIT 1),
     'AI-20-02', 'Camión de Riego 20kL JTYK-88', 'camion_cisterna', 'WDB932162H0113415',
     'critica', 'operativo',
     'JTYK-88', 'AI-20-02', 'WDB932162H0113415', '541972C1002548', 2017, '360CV/355HP',
     'arrendado', 'Coquimbo', 'Drilling service and solution', 'Faena Sobek, Copiapó',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2017-01-01'),

    -- 2. GGHB-32: Mack GU813E - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU813E Allison' LIMIT 1),
     'AI-20-03', 'Camión de Riego 20kL GGHB-32', 'camion_cisterna', '1M2AX38C1EM026506',
     'critica', 'operativo',
     'GGHB-32', 'AI-20-03', '1M2AX38C1EM026506', 'MP81044986', 2014, '389CV/384HP',
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2014-01-01'),

    -- 3. SVCZ-38: Volvo VM 350 - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'VM 350' LIMIT 1),
     'AI-20-04', 'Camión de Riego 20kL SVCZ-38', 'camion_cisterna', '93KKYM0D8RE191065',
     'critica', 'operativo',
     'SVCZ-38', 'AI-20-04', '93KKYM0D8RE191065', 'D8601305C2EP', 2023, '350CV/345HP',
     'arrendado', 'Coquimbo', 'Rentamaq', 'Mina Teck Andacollo, Coquimbo',
     '{"antisomnolencia": true, "mobileye": true, "ecam": false}', '2023-01-01'),

    -- 4. SVBJ-55: Volvo VM 350 - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'VM 350' LIMIT 1),
     'AI-20-05', 'Camión de Riego 20kL SVBJ-55', 'camion_cisterna', '93KKYM0D5RE191064',
     'critica', 'operativo',
     'SVBJ-55', 'AI-20-05', '93KKYM0D5RE191064', 'D8600352C2EP', 2023, '350CV/345HP',
     'arrendado', 'Coquimbo', 'Rentamaq', 'Mina Teck Andacollo, Coquimbo',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2023-01-01'),

    -- 5. TRST-58: Scania P450B - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'AI-20-06', 'Camión de Riego 20kL TRST-58', 'camion_cisterna', '9BSP6X400R4072987',
     'critica', 'operativo',
     'TRST-58', 'AI-20-06', '9BSP6X400R4072987', '8461646', 2025, '450CV/444HP',
     'arrendado', 'Calama', 'Boart Longyear', 'División Ministro Hales, Calama',
     '{}', '2025-01-01'),

    -- 6. LKPY-18: Mack GU 813 autom - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU 813 autom' LIMIT 1),
     'AI-20-07', 'Camión de Riego 20kL LKPY-18', 'camion_cisterna', '1M2GR3HC9LM002052',
     'critica', 'en_mantenimiento',
     'LKPY-18', 'AI-20-07', '1M2GR3HC9LM002052', 'MP81244683', 2019, '384CV/379HP',
     NULL, 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2019-01-01'),

    -- 7. TGGF-56: Volvo FMX 420 - 22.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'AI-22-01', 'Camión de Riego 22kL TGGF-56', 'camion_cisterna', '93KXG10D1RE941303',
     'critica', 'operativo',
     'TGGF-56', 'AI-22-01', '93KXG10D1RE941303', 'D138097104C5E', 2024, '420CV/414HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 8. TGGF-57: Volvo FMX 420 - 22.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'AI-22-02', 'Camión de Riego 22kL TGGF-57', 'camion_cisterna', '93KXG10D5RE941914',
     'critica', 'operativo',
     'TGGF-57', 'AI-22-02', '93KXG10D5RE941914', 'D138097712C5E', 2024, '420CV/414HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": false, "mobileye": false, "ecam": true}', '2024-01-01'),

    -- 9. TGGF-58: Volvo FMX 420 - 22.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'AI-22-03', 'Camión de Riego 22kL TGGF-58', 'camion_cisterna', '93KXG10D2RE941913',
     'critica', 'operativo',
     'TGGF-58', 'AI-22-03', '93KXG10D2RE941913', 'D138097751C5E', 2024, '420CV/414HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 10. TRDP-97: Volvo FMX 420 - 22.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'AI-22-04', 'Camión de Riego 22kL TRDP-97', 'camion_cisterna', '93KXG10D2SE603548',
     'critica', 'operativo',
     'TRDP-97', 'AI-22-04', '93KXG10D2SE603548', 'D138109703C5E', 2024, '420CV/414HP',
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 11. GCHT-12: Mack GU813E Mec - 25.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU813E Mec' LIMIT 1),
     'AI-25-01', 'Camión de Riego 25kL GCHT-12', 'camion_cisterna', '1M2AX38C6DM022305',
     'critica', 'operativo',
     'GCHT-12', 'AI-25-01', '1M2AX38C6DM022305', 'MP81013366', 2014, '389CV/384HP',
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2014-01-01'),

    -- 12. KCBY-30: M.Benz Actros 3336 K - 25.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3336 K' LIMIT 1),
     'AI-25-02', 'Camión de Riego 25kL KCBY-30', 'camion_cisterna', 'WDB932162J0218353',
     'critica', 'operativo',
     'KCBY-30', 'AI-25-02', 'WDB932162J0218353', '541972C1025260', 2018, '360CV/355HP',
     'arrendado', 'Coquimbo', 'Drilling service and solution', 'Faena Marquesa, Huachalalume',
     '{"antisomnolencia": true, "mobileye": true, "ecam": false}', '2018-01-01'),

    -- 13. KCBY-31: M.Benz Actros 3336 K - 25.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3336 K' LIMIT 1),
     'AI-25-03', 'Agua Industrial 25kL KCBY-31', 'camion_cisterna', 'WDB932162J0213328',
     'critica', 'en_mantenimiento',
     'KCBY-31', 'AI-25-03', 'WDB932162J0213328', '541972C1024126', 2018, '360CV/355HP',
     NULL, 'Calama', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": true, "mobileye": true, "ecam": false}', '2018-01-01'),

    -- 14. KVWW-68: M.Benz Actros 3336 K - 25.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3336 K' LIMIT 1),
     'AI-25-04', 'Agua Industrial 25kL KVWW-68', 'camion_cisterna', 'WDB932162K0271738',
     'critica', 'en_mantenimiento',
     'KVWW-68', 'AI-25-04', 'WDB932162K0271738', '541972C1036272', 2019, '360CV/355HP',
     NULL, 'Calama', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2019-01-01'),

    -- 15. KVWW-69: M.Benz Actros 3336 K - 25.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3336 K' LIMIT 1),
     'AI-25-05', 'Agua Industrial 25kL KVWW-69', 'camion_cisterna', 'WDB932162K0271739',
     'critica', 'operativo',
     'KVWW-69', 'AI-25-05', 'WDB932162K0271739', '541972C1036475', 2019, '360CV/355HP',
     'arrendado', 'Coquimbo', 'Drilling service and solution', 'Faena Cuprita, Inca de Oro',
     '{"antisomnolencia": true, "mobileye": true, "ecam": false}', '2019-01-01');

    -- ====================================================================
    -- ALJIBES COMBUSTIBLE — 16 unidades
    -- ====================================================================

    INSERT INTO activos (contrato_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado,
                         patente, centro_costo, vin_chasis, numero_motor, anio_fabricacion, potencia,
                         estado_comercial, operacion, cliente_actual, ubicacion_actual,
                         sistemas_seguridad, fecha_alta)
    VALUES
    -- 16. DCHD-83: Mitsubishi Canter 7.5 - 5.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Canter 7.5' LIMIT 1),
     'CC-05-04', 'Aljibe Comb. 5kL DCHD-83', 'camion', 'FE85DGA20405',
     'alta', 'operativo',
     'DCHD-83', 'CC-05-04', 'FE85DGA20405', '4M50D62846', 2011, '139CV/137HP',
     'uso_interno', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2011-01-01'),

    -- 17. KVWD-27: M.Benz Accelo 1016/44 - 5.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Accelo 1016/44' LIMIT 1),
     'CC-05-10', 'Aljibe Comb. 5kL KVWD-27', 'camion', '9BM979078KB095915',
     'alta', 'operativo',
     'KVWD-27', 'CC-05-10', '9BM979078KB095915', '924990U1235826', 2018, '156CV/168HP',
     'arrendado', 'Coquimbo', 'San Gerónimo', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2018-01-01'),

    -- 18. DJKL-18: M.Benz Actros 3341 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3341' LIMIT 1),
     'CC-15-05', 'Aljibe Comb. 15kL DJKL-18', 'camion_cisterna', 'WDB930163CL577606',
     'critica', 'operativo',
     'DJKL-18', 'CC-15-05', 'WDB930163CL577606', '54194400777410', 2012, '408CV/402HP',
     'uso_interno', 'Coquimbo', 'Contrato CMP', 'CMP, Romeral',
     '{}', '2012-01-01'),

    -- 19. FSLZ-67: M.Benz Actros 3341 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Actros 3341' LIMIT 1),
     'CC-15-06', 'Aljibe Comb. 15kL FSLZ-67', 'camion_cisterna', 'WDB930163DL718103',
     'critica', 'operativo',
     'FSLZ-67', 'CC-15-06', 'WDB930163DL718103', '541974X0868775', 2013, '408CV/402HP',
     'uso_interno', 'Coquimbo', 'Contrato CMP', 'CMP, Romeral',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2013-01-01'),

    -- 20. HKSR-81: M.Benz Axor 2633 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Axor 2633' LIMIT 1),
     'CC-15-09', 'Aljibe Comb. 15kL HKSR-81', 'camion_cisterna', 'WDF950643GB981227',
     'critica', 'operativo',
     'HKSR-81', 'CC-15-09', 'WDF950643GB981227', '926919C1096345', 2016, '326CV/321HP',
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2016-01-01'),

    -- 21. JGBY-10: M.Benz Axor 2633/45 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Axor 2633/45' LIMIT 1),
     'CC-15-13', 'Aljibe Comb. 15kL JGBY-10', 'camion_cisterna', 'WDF950643HB982113',
     'critica', 'operativo',
     'JGBY-10', 'CC-15-13', 'WDF950643HB982113', '926945C1111027', 2017, '326CV/321HP',
     'arrendado', 'Coquimbo', 'Drilling service and solution', 'Faena Sobek, Copiapó',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2017-01-01'),

    -- 22. SVBJ-56: Volvo VM 350 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'VM 350' LIMIT 1),
     'CC-15-14', 'Aljibe Comb. 15kL SVBJ-56', 'camion_cisterna', '93KKYM0D1RE190968',
     'critica', 'operativo',
     'SVBJ-56', 'CC-15-14', '93KKYM0D1RE190968', 'D8599357C2EP', 2023, '350CV/345HP',
     'arrendado', 'Coquimbo', 'Esmax', 'El Salvador',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2023-01-01'),

    -- 23. SVBJ-57: Volvo VM 350 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'VM 350' LIMIT 1),
     'CC-15-15', 'Aljibe Comb. 15kL SVBJ-57', 'camion_cisterna', '93KKYM0D5RE190769',
     'critica', 'operativo',
     'SVBJ-57', 'CC-15-15', '93KKYM0D5RE190769', 'D8599354C2EP', 2023, '350CV/345HP',
     'arrendado', 'Coquimbo', 'Orbit Garant', 'Mina Los Bronces, Santiago',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2023-01-01'),

    -- 24. TCJV-15: Renault C440 - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'C440' LIMIT 1),
     'CC-15-16', 'Aljibe Comb. 15kL TCJV-15', 'camion_cisterna', 'VF630N358PD000096',
     'critica', 'operativo',
     'TCJV-15', 'CC-15-16', 'VF630N358PD000096', '2296470', 2024, '446CV/440HP',
     'arrendado', 'Calama', 'Orbit Garant', 'El Abra, Calama',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2024-01-01'),

    -- 25. LCSX-78: Mack GU 813 autom - 15.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU 813 autom' LIMIT 1),
     'CC-15-17', 'Aljibe Comb. 15kL LCSX-78', 'camion_cisterna', '1M2GR3HC8KM001828',
     'critica', 'en_mantenimiento',
     'LCSX-78', 'CC-15-17', '1M2GR3HC8KM001828', 'MP81224494', 2019, '384CV/379HP',
     NULL, 'Coquimbo', 'Sin Contrato', 'CMP, Romeral',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2019-01-01'),

    -- 26. HHWB-42: Mack GU 813 autom - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU 813 autom' LIMIT 1),
     'CC-20-01', 'Aljibe Comb. 20kL HHWB-42', 'camion_cisterna', '1M2AX38C4GM033095',
     'critica', 'operativo',
     'HHWB-42', 'CC-20-01', '1M2AX38C4GM033095', 'MP81101458', 2015, '389CV/384HP',
     'uso_interno', 'Coquimbo', 'Contrato CM Cenizas', 'Francke, Taltal',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2015-01-01'),

    -- 27. HHWB-44: Mack GU 813 autom - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GU 813 autom' LIMIT 1),
     'CC-20-02', 'Aljibe Comb. 20kL HHWB-44', 'camion_cisterna', '1M2AX38C0GM033742',
     'critica', 'operativo',
     'HHWB-44', 'CC-20-02', '1M2AX38C0GM033742', 'MP81108692', 2015, '389CV/384HP',
     'uso_interno', 'Coquimbo', 'Contrato CM Cenizas', 'Francke, Taltal',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2015-01-01'),

    -- 28. TRST-57: Scania P450B - 20.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CC-20-03', 'Aljibe Comb. 20kL TRST-57', 'camion_cisterna', '9BSP6X400R4072347',
     'critica', 'operativo',
     'TRST-57', 'CC-20-03', '9BSP6X400R4072347', '8460670', 2025, '450CV/444HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2025-01-01'),

    -- 29. FJTJ-60: M.Benz Atego 1624A 4x4 - 5.000L 4x4
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Atego 1624A 4x4' LIMIT 1),
     'CC-44-03', 'Aljibe Comb. 5kL 4x4 FJTJ-60', 'camion', 'WDB970373DL705168',
     'alta', 'en_mantenimiento',
     'FJTJ-60', 'CC-44-03', 'WDB970373DL705168', '902916C0988494', 2013, '238CV/235HP',
     NULL, 'Coquimbo', 'San Gerónimo', 'San Antonio, Lambert',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2013-01-01'),

    -- 30. FJTJ-61: M.Benz Atego 1624A 4x4 - Chasis cabinado
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Atego 1624A 4x4' LIMIT 1),
     'CC-44-04', 'Chasis Cabinado FJTJ-61', 'camion', 'WDB970373DL704740',
     'baja', 'operativo',
     'FJTJ-61', 'CC-44-04', 'WDB970373DL704740', '902916C0988346', 2013, '240CV/237HP',
     'en_venta', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2013-01-01'),

    -- 31. RSCY-85: M.Benz Accelo 1016/44 - 5.000L
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Accelo 1016/44' LIMIT 1),
     'CC-05-11', 'Aljibe Comb. 5kL RSCY-85', 'camion', '9BM979078NB245417',
     'alta', 'operativo',
     'RSCY-85', 'CC-05-11', '9BM979078NB245417', '924990U1365501', 2022, '156CV/168HP',
     'arrendado', 'Coquimbo', 'Major Drilling S.A', 'Faena Yastai, Tierra Amarilla',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2022-01-01');

    -- ====================================================================
    -- EQUIPOS ESPECIALES: Polibrazo, Plumas, Carrocerías, Grúas
    -- ====================================================================

    INSERT INTO activos (contrato_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado,
                         patente, centro_costo, vin_chasis, numero_motor, anio_fabricacion, potencia,
                         estado_comercial, operacion, cliente_actual, ubicacion_actual,
                         sistemas_seguridad, fecha_alta)
    VALUES
    -- 32. TGGF-59: Polibrazo
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'CH-20-01', 'Polibrazo 20t TGGF-59', 'camion', '93KXG10D7RE942157',
     'critica', 'operativo',
     'TGGF-59', 'CH-20-01', '93KXG10D7RE942157', 'D138098073C5E', 2024, '420CV/414HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 33. TGGF-60: Camión pluma
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 540' LIMIT 1),
     'CP-06-02', 'Camión Pluma 10t TGGF-60', 'camion', '93KXG40D4RE944562',
     'critica', 'operativo',
     'TGGF-60', 'CP-06-02', '93KXG40D4RE944562', 'D138100497C5E', 2024, '540CV/533HP',
     'disponible', 'Calama', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 34. TRDP-96: Camión pluma
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'FMX 420' LIMIT 1),
     'CP-06-03', 'Camión Pluma 10t TRDP-96', 'camion', '93KXG10DXSE603547',
     'critica', 'operativo',
     'TRDP-96', 'CP-06-03', '93KXG10DXSE603547', 'D138109743C5E', 2024, '420CV/414HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2024-01-01'),

    -- 35. TRSS-14: Camión pluma Scania
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CP-06-04', 'Camión Pluma 10t TRSS-14', 'camion', '9BSP6X400S4077464',
     'critica', 'operativo',
     'TRSS-14', 'CP-06-04', '9BSP6X400S4077464', '8465664', 2025, '450CV/444HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2025-01-01'),

    -- 36. TRSS-16: Camión pluma Scania
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CP-06-05', 'Camión Pluma 10t TRSS-16', 'camion', '9BSP6X400S4077599',
     'critica', 'operativo',
     'TRSS-16', 'CP-06-05', '9BSP6X400S4077599', '8465646', 2025, '450CV/444HP',
     'arrendado', 'Coquimbo', 'Boart Longyear', 'Andina',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2025-01-01'),

    -- 37. RSCY-86: Carrocería plana
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Accelo 1016/44' LIMIT 1),
     'CS-06-02', 'Carrocería Plana 6t RSCY-86', 'camion', '9BM979078NB241287',
     'media', 'operativo',
     'RSCY-86', 'CS-06-02', '9BM979078NB241287', '924990U1362284', 2022, '156CV/168HP',
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{"antisomnolencia": false, "mobileye": false, "ecam": false}', '2022-01-01'),

    -- 38-40. Carrocerías Planas Scania
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CS-06-03', 'Carrocería Plana 14.5t TRSS-13', 'camion', '9BSP6X400S4077645',
     'alta', 'operativo',
     'TRSS-13', 'CS-06-03', '9BSP6X400S4077645', '8465689', 2025, '450CV/444HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2025-01-01'),

    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CS-06-04', 'Carrocería Plana 14.5t TRSS-15', 'camion', '9BSP6X400S4077407',
     'alta', 'operativo',
     'TRSS-15', 'CS-06-04', '9BSP6X400S4077407', '8465842', 2025, '450CV/444HP',
     'leasing', 'Calama', 'Boart Longyear', 'Spence, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2025-01-01'),

    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'P450B' LIMIT 1),
     'CS-06-05', 'Carrocería Plana 14.5t TTPC-47', 'camion', '9BSP6X400S4078559',
     'alta', 'operativo',
     'TTPC-47', 'CS-06-05', '9BSP6X400S4078559', NULL, 2025, '450CV/444HP',
     'arrendado', 'Calama', 'Boart Longyear', 'División Ministro Hales, Calama',
     '{"antisomnolencia": true, "mobileye": false, "ecam": true}', '2025-01-01'),

    -- 41. Grúa Horquilla Toyota
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = '02-7FDA50' LIMIT 1),
     'GH-05-01', 'Grúa Horquilla 7.3t GCSY-66', 'equipo_menor', 'A7FDA5037402',
     'media', 'operativo',
     'GCSY-66', 'GH-05-01', 'A7FDA5037402', '14Z0018969', 2014, NULL,
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{}', '2014-01-01'),

    -- 42. Grúa Horquilla Yale
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'GDP 30TK' LIMIT 1),
     'GH-03-01', 'Grúa Horquilla 3t GDP30TK', 'equipo_menor', 'B871R13103M',
     'media', 'operativo',
     'GDP 30TK', 'GH-03-01', 'B871R13103M', NULL, 2014, NULL,
     'disponible', 'Coquimbo', 'Sin Contrato', 'Taller Pillado, Coquimbo',
     '{}', '2014-01-01');

    -- ====================================================================
    -- CAMIONETAS Y VEHÍCULOS LIVIANOS — 13 unidades
    -- ====================================================================

    INSERT INTO activos (contrato_id, modelo_id, codigo, nombre, tipo, numero_serie, criticidad, estado,
                         patente, centro_costo, vin_chasis, numero_motor, anio_fabricacion, potencia,
                         estado_comercial, operacion, cliente_actual, ubicacion_actual,
                         sistemas_seguridad, fecha_alta)
    VALUES
    -- 43. VRST-19: Maxus T60
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'T60 4x4 DX Plus 6 MT' LIMIT 1),
     'CA-20-01', 'Camioneta Maxus VRST-19', 'camioneta', 'LSFAM11A0TA042861',
     'media', 'operativo',
     'VRST-19', 'CA-20-01', 'LSFAM11A0TA042861', 'M924C079498', 2025, NULL,
     'uso_interno', 'Calama', 'Sin Contrato', 'Taller Pillado, Calama',
     '{}', '2025-01-01'),

    -- 44. JDKH-31: Nissan NP300
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'NP300 Dob Cab' LIMIT 1),
     'CA-23-03', 'Camioneta Nissan JDKH-31', 'camioneta', '3N6BD33B7GK895790',
     'media', 'operativo',
     'JDKH-31', 'CA-23-03', '3N6BD33B7GK895790', 'YS23010021C', 2017, NULL,
     'uso_interno', 'Coquimbo', NULL, 'Taller Pillado, Coquimbo',
     '{}', '2017-01-01'),

    -- 45. KVDK-20: Nissan NP300
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'NP300 Dob Cab' LIMIT 1),
     'CA-23-04', 'Camioneta Nissan KVDK-20', 'camioneta', '3N6BD33B2KK805258',
     'media', 'operativo',
     'KVDK-20', 'CA-23-04', '3N6BD33B2KK805258', 'YS23B266C028057', 2019, NULL,
     'uso_interno', 'Coquimbo', NULL, 'Taller Fenix (aseguradora)',
     '{}', '2019-01-01'),

    -- 46. KVDK-21: Nissan NP300
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'NP300 Dob Cab' LIMIT 1),
     'CA-23-05', 'Camioneta Nissan KVDK-21', 'camioneta', '3N6BD33B7KK805417',
     'media', 'operativo',
     'KVDK-21', 'CA-23-05', '3N6BD33B7KK805417', 'YS23B266C028601', 2019, NULL,
     'uso_interno', 'Coquimbo', NULL, 'Taller Pillado, Coquimbo',
     '{}', '2019-01-01'),

    -- 47. SBPG-12: Toyota Hilux Lubricadora
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'New Hilux 4x4 2.4 MT DX' LIMIT 1),
     'CA-24-01', 'Camioneta Lubricadora SBPG-12', 'camioneta', '8AJDB3CDXN1320891',
     'alta', 'operativo',
     'SBPG-12', 'CA-24-01', '8AJDB3CDXN1320891', '2GDG299782', 2022, NULL,
     'arrendado', 'Coquimbo', 'TPM Minería SA', 'Caserones, Copiapó',
     '{}', '2022-01-01'),

    -- 48. SPRY-26: Toyota Hilux
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'New Hilux 4x4 2.4 MT DX' LIMIT 1),
     'CA-24-02', 'Camioneta Toyota SPRY-26', 'camioneta', '8AJDB3CDXP1331666',
     'media', 'operativo',
     'SPRY-26', 'CA-24-02', '8AJDB3CDXP1331666', '2GDG353588', 2023, NULL,
     'uso_interno', 'Calama', 'Contrato ESM', 'Contrato ESM, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2023-01-01'),

    -- 49. SPRY-28: Toyota Hilux
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'New Hilux 4x4 2.4 MT DX' LIMIT 1),
     'CA-24-03', 'Camioneta Toyota SPRY-28', 'camioneta', '8AJDB3CD9P1331660',
     'media', 'operativo',
     'SPRY-28', 'CA-24-03', '8AJDB3CD9P1331660', '2GDG353522', 2023, NULL,
     'uso_interno', 'Calama', 'Contrato ESM', 'Contrato ESM, Calama',
     '{"antisomnolencia": true, "mobileye": true, "ecam": true}', '2023-01-01'),

    -- 50. LLBP-96: Toyota Hilux 2.8
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Hilux 2.8 Autom' LIMIT 1),
     'CA-28-01', 'Camioneta Toyota LLBP-96', 'camioneta', '8AJHA8CD0K2636551',
     'media', 'operativo',
     'LLBP-96', 'CA-28-01', '8AJHA8CD0K2636551', '1GDG103761', 2019, NULL,
     'uso_interno', 'Coquimbo', 'Contrato CM Cenizas', 'Francke, Taltal',
     '{}', '2019-01-01'),

    -- 51. RZPC-83: Maxus T60
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'T60 4x4 DX' LIMIT 1),
     'CA-28-02', 'Camioneta Maxus RZPC-83', 'camioneta', 'LSFAM11A7NA055979',
     'media', 'operativo',
     'RZPC-83', 'CA-28-02', 'LSFAM11A7NA055979', 'R921C040860', 2022, NULL,
     'uso_interno', 'Coquimbo', 'Contrato CMP', 'CMP, Romeral',
     '{}', '2022-01-01'),

    -- 52. SLRK-82: Citroën Berlingo (Taller Móvil TM-11)
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Berlingo K9 1.6 Diesel' LIMIT 1),
     'VC-FC-02', 'Furgón Taller Móvil TM-11 SLRK-82', 'camioneta', 'VR7EF9HPAPJ519505',
     'media', 'operativo',
     'SLRK-82', 'VC-FC-02', 'VR7EF9HPAPJ519505', '10JCAW0025734', 2023, NULL,
     'uso_interno', 'Coquimbo', NULL, 'Taller Pillado, Coquimbo',
     '{}', '2023-01-01'),

    -- 53. SPRY-29: Citroën Berlingo (Taller Móvil TM-12)
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Berlingo K9 1.6 Diesel' LIMIT 1),
     'VC-FC-03', 'Furgón Taller Móvil TM-12 SPRY-29', 'camioneta', 'VR7EF9HPAPJ518052',
     'media', 'operativo',
     'SPRY-29', 'VC-FC-03', 'VR7EF9HPAPJ518052', '10JCAW0024628', 2023, NULL,
     'uso_interno', 'Calama', NULL, 'Taller Pillado, Calama',
     '{}', '2023-01-01'),

    -- 54. TCRB-71: RAM 1500 (Gerencia)
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = '1500 LIMITED 5,7L' LIMIT 1),
     'OC-GE-02', 'Camioneta RAM Gerencia TCRB-71', 'camioneta', '1C6SRFHTXPN684575',
     'baja', 'operativo',
     'TCRB-71', 'OC-GE-02', '1C6SRFHTXPN684575', 'PN684575', 2024, NULL,
     'uso_interno', 'Coquimbo', NULL, NULL,
     '{}', '2024-01-01'),

    -- 55. TSTB-48: Chevrolet Montana
    (v_contrato_id,
     (SELECT id FROM modelos WHERE nombre = 'Montana 1.2 MT' LIMIT 1),
     'CA-12-01', 'Camioneta Chevrolet TSTB-48', 'camioneta', '9BGEP43C0SB148537',
     'baja', 'operativo',
     'TSTB-48', 'CA-12-01', '9BGEP43C0SB148537', 'L4H241364520', 2025, NULL,
     'uso_interno', 'Coquimbo', NULL, NULL,
     '{}', '2025-01-01');

END $$;

-- ============================================================================
-- 4. CHECKLIST TEMPLATE: Verificación de Disponibilidad
-- ============================================================================
-- Basado en DS 298, DS 160, DS 132, normativas mineras y walk-around check.
-- Este template se usa automáticamente cuando se crea una OT tipo
-- 'verificacion_disponibilidad'.
-- ============================================================================

INSERT INTO checklist_templates (tipo_ot, nombre, descripcion, items, activo)
VALUES (
    'verificacion_disponibilidad',
    'Verificación de Disponibilidad para Arriendo',
    'Checklist obligatorio antes de declarar un equipo disponible para entrega a cliente. '
    'Basado en DS 298 (transporte sustancias peligrosas), DS 160 (combustibles), '
    'DS 132 (seguridad minera) y estándares de mandantes mineros.',
    '[
        {"orden": 1,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Revisión Técnica vigente (verificar fecha en parabrisas)", "obligatorio": true, "requiere_foto": true},
        {"orden": 2,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "SOAP (Seguro Obligatorio) vigente", "obligatorio": true, "requiere_foto": true},
        {"orden": 3,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Permiso de Circulación vigente y pagado", "obligatorio": true, "requiere_foto": true},
        {"orden": 4,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Póliza de seguro RC vigente", "obligatorio": true, "requiere_foto": true},
        {"orden": 5,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Certificado Hermeticidad tanque vigente (cisterna comb.)", "obligatorio": false, "requiere_foto": true},
        {"orden": 6,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Inscripción SEC / TC8 vigente (cisterna combustible)", "obligatorio": false, "requiere_foto": true},
        {"orden": 7,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "HDS (Hojas de Datos de Seguridad) en cabina", "obligatorio": false, "requiere_foto": false},
        {"orden": 8,  "seccion": "DOCUMENTACION LEGAL", "descripcion": "Antigüedad vehículo menor a 15 años (DS 298)", "obligatorio": true, "requiere_foto": false},

        {"orden": 9,  "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Carrocería sin daños estructurales, golpes o fugas visibles", "obligatorio": true, "requiere_foto": true},
        {"orden": 10, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Neumáticos: presión correcta, banda de rodado >3mm, sin cortes", "obligatorio": true, "requiere_foto": true},
        {"orden": 11, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Luces delanteras (altas/bajas) operativas", "obligatorio": true, "requiere_foto": false},
        {"orden": 12, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Luces traseras, freno y retroceso operativas", "obligatorio": true, "requiere_foto": false},
        {"orden": 13, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Direccionales operativas (4 esquinas)", "obligatorio": true, "requiere_foto": false},
        {"orden": 14, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Espejos laterales y retrovisores en buen estado y ajustados", "obligatorio": true, "requiere_foto": false},
        {"orden": 15, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Parabrisas sin trizaduras, patente grabada en vidrios", "obligatorio": true, "requiere_foto": true},
        {"orden": 16, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Cintas reflectantes grado ingeniería en perimetro completo", "obligatorio": true, "requiere_foto": true},
        {"orden": 17, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Alarma de retroceso operativa (97-112 dB)", "obligatorio": true, "requiere_foto": false},
        {"orden": 18, "seccion": "EXTERIOR - CIRCUNVALACION", "descripcion": "Cámara de retroceso operativa y limpia", "obligatorio": true, "requiere_foto": false},

        {"orden": 19, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Baliza LED ámbar operativa", "obligatorio": true, "requiere_foto": true},
        {"orden": 20, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Luces estroboscópicas delanteras/traseras operativas", "obligatorio": true, "requiere_foto": false},
        {"orden": 21, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Pértiga mínimo 3 metros con luz estroboscópica (DS 132)", "obligatorio": true, "requiere_foto": true},
        {"orden": 22, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Rotulación sustancias peligrosas NCh 2190 (cisterna comb.)", "obligatorio": false, "requiere_foto": true},
        {"orden": 23, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Sistema de puesta a tierra presente y funcional (cisterna comb.)", "obligatorio": false, "requiere_foto": true},
        {"orden": 24, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Válvulas de corte operativas (cisterna comb.)", "obligatorio": false, "requiere_foto": false},
        {"orden": 25, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Corta corriente visible y funcional", "obligatorio": true, "requiere_foto": true},
        {"orden": 26, "seccion": "EQUIPAMIENTO MINERO", "descripcion": "Protección FOPS/ROPS cabina (equipo pesado DS 132)", "obligatorio": false, "requiere_foto": true},

        {"orden": 27, "seccion": "SISTEMAS TECNOLOGICOS", "descripcion": "Sistema antisomnolencia/DMS instalado y calibrado", "obligatorio": false, "requiere_foto": false},
        {"orden": 28, "seccion": "SISTEMAS TECNOLOGICOS", "descripcion": "Sistema ADAS (Mobileye o equiv.) instalado y calibrado", "obligatorio": false, "requiere_foto": false},
        {"orden": 29, "seccion": "SISTEMAS TECNOLOGICOS", "descripcion": "GPS certificado operativo y con señal", "obligatorio": true, "requiere_foto": false},
        {"orden": 30, "seccion": "SISTEMAS TECNOLOGICOS", "descripcion": "Tacógrafo o dispositivo electrónico de registro (DS 298)", "obligatorio": false, "requiere_foto": false},
        {"orden": 31, "seccion": "SISTEMAS TECNOLOGICOS", "descripcion": "Limitador/gobernador de velocidad configurado", "obligatorio": false, "requiere_foto": false},

        {"orden": 32, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Nivel aceite motor OK", "obligatorio": true, "requiere_foto": false},
        {"orden": 33, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Nivel líquido de frenos OK", "obligatorio": true, "requiere_foto": false},
        {"orden": 34, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Nivel refrigerante OK", "obligatorio": true, "requiere_foto": false},
        {"orden": 35, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Nivel aceite hidráulico OK (camión pluma)", "obligatorio": false, "requiere_foto": false},
        {"orden": 36, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Estado de correas y mangueras (sin desgaste/fugas)", "obligatorio": true, "requiere_foto": false},
        {"orden": 37, "seccion": "COMPARTIMIENTO MOTOR", "descripcion": "Batería: terminales limpios, carga adecuada", "obligatorio": true, "requiere_foto": false},

        {"orden": 38, "seccion": "INTERIOR CABINA", "descripcion": "Cinturones de seguridad 3 puntos operativos todos los asientos", "obligatorio": true, "requiere_foto": false},
        {"orden": 39, "seccion": "INTERIOR CABINA", "descripcion": "Freno de servicio: prueba funcional", "obligatorio": true, "requiere_foto": false},
        {"orden": 40, "seccion": "INTERIOR CABINA", "descripcion": "Freno de estacionamiento: prueba funcional", "obligatorio": true, "requiere_foto": false},
        {"orden": 41, "seccion": "INTERIOR CABINA", "descripcion": "Dirección sin juego excesivo", "obligatorio": true, "requiere_foto": false},
        {"orden": 42, "seccion": "INTERIOR CABINA", "descripcion": "Bocina operativa", "obligatorio": true, "requiere_foto": false},
        {"orden": 43, "seccion": "INTERIOR CABINA", "descripcion": "Tablero: sin alertas anómalas (check engine, ABS, etc.)", "obligatorio": true, "requiere_foto": true},
        {"orden": 44, "seccion": "INTERIOR CABINA", "descripcion": "Radio VHF o sistema de comunicación operativo", "obligatorio": true, "requiere_foto": false},
        {"orden": 45, "seccion": "INTERIOR CABINA", "descripcion": "Aire acondicionado y calefacción funcional", "obligatorio": true, "requiere_foto": false},
        {"orden": 46, "seccion": "INTERIOR CABINA", "descripcion": "Limpiaparabrisas funcional", "obligatorio": true, "requiere_foto": false},

        {"orden": 47, "seccion": "EMERGENCIA Y EPP", "descripcion": "Extintor certificado: carga vigente, sello intacto, accesible", "obligatorio": true, "requiere_foto": true},
        {"orden": 48, "seccion": "EMERGENCIA Y EPP", "descripcion": "Botiquín Clase A completo", "obligatorio": true, "requiere_foto": true},
        {"orden": 49, "seccion": "EMERGENCIA Y EPP", "descripcion": "Triángulos de seguridad (2 unidades)", "obligatorio": true, "requiere_foto": false},
        {"orden": 50, "seccion": "EMERGENCIA Y EPP", "descripcion": "Cuñas de rueda (wheel chocks) presentes", "obligatorio": true, "requiere_foto": false},
        {"orden": 51, "seccion": "EMERGENCIA Y EPP", "descripcion": "Linterna de emergencia operativa", "obligatorio": true, "requiere_foto": false},
        {"orden": 52, "seccion": "EMERGENCIA Y EPP", "descripcion": "Kit antiderrame: 3 baldes arena/absorbente (cisterna comb. DS 160)", "obligatorio": false, "requiere_foto": true},

        {"orden": 53, "seccion": "PRUEBA OPERATIVA", "descripcion": "Motor enciende sin anomalías, ralentí estable", "obligatorio": true, "requiere_foto": false},
        {"orden": 54, "seccion": "PRUEBA OPERATIVA", "descripcion": "Prueba de frenado en baja velocidad exitosa", "obligatorio": true, "requiere_foto": false},
        {"orden": 55, "seccion": "PRUEBA OPERATIVA", "descripcion": "Registro de km/horómetro actual", "obligatorio": true, "requiere_foto": true}
    ]'::JSONB,
    true
)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 5. SEED: Certificaciones desde el maestro de flota (Rev. Técnica, SOAP, etc.)
-- ============================================================================
-- Insertamos las certificaciones conocidas del Excel para los primeros equipos.

DO $$
DECLARE
    v_activo RECORD;
BEGIN
    FOR v_activo IN
        SELECT id, patente, codigo FROM activos WHERE patente IS NOT NULL
    LOOP
        -- Permiso de Circulación (todos tienen fecha 2026-09-30 según Excel)
        INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                     fecha_emision, fecha_vencimiento, estado, bloqueante)
        VALUES (v_activo.id, 'permiso_circulacion', v_activo.patente || '-PC-2026',
                'Municipalidad', '2026-03-01', '2026-09-30', 'vigente', true)
        ON CONFLICT DO NOTHING;

        -- SOAP (todos 2026-09-30)
        INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                     fecha_emision, fecha_vencimiento, estado, bloqueante)
        VALUES (v_activo.id, 'soap', v_activo.patente || '-SOAP-2026',
                'Aseguradora', '2026-03-01', '2026-09-30', 'vigente', true)
        ON CONFLICT DO NOTHING;
    END LOOP;
END $$;

-- ============================================================================
-- 6. NOMENCLATURA DE ESTADOS — Referencia para el sistema
-- ============================================================================

COMMENT ON COLUMN estado_diario_flota.estado_codigo IS
    'Código de estado diario: '
    'A=Arrendado (en manos cliente), '
    'D=Disponible (operativo para arriendo), '
    'H=En habilitación (preparándose), '
    'R=En recepción (devuelto, pendiente inspección), '
    'M=Mantención/reparación >1 día, '
    'T=Mantención/reparación <1 día (terreno), '
    'F=Fuera de servicio (sin HH asignadas), '
    'V=Dispuesto para venta, '
    'U=Uso interno/contrato empresa, '
    'L=Leasing operativo';
