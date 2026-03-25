-- SICOM-ICEO | Fase 2 | Datos Semilla
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 07_seed_data.sql
-- Proposito : Datos semilla realistas para un contrato de servicio de
--             abastecimiento de combustibles, lubricantes y mantenimiento
--             de plataformas en operacion minera en Chile.
-- Dependencias: 01 a 04 (todos los esquemas de tablas)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CONTRATO DE SERVICIO
-- ============================================================================

INSERT INTO contratos (id, codigo, nombre, cliente, descripcion, fecha_inicio, fecha_fin, estado, valor_contrato, moneda)
VALUES (
    gen_random_uuid(),
    'CTR-2024-001',
    'Contrato de Servicios de Abastecimiento y Mantenimiento - Minera Los Andes',
    'Compania Minera Los Andes SpA',
    'Contrato integral de administracion de combustibles y lubricantes, mantenimiento de plataformas fijas (surtidores, estanques, bombas) y mantenimiento de plataformas moviles (camiones cisterna, lubrimoviles, equipos de bombeo). Incluye gestion de inventario valorizado, trazabilidad con codigo de barras, cumplimiento documental y evaluacion mediante Indice Compuesto de Excelencia Operacional (ICEO).',
    '2024-07-01',
    '2027-06-30',
    'activo',
    18500000000.00,
    'CLP'
);

-- ============================================================================
-- 2. FAENAS
-- ============================================================================

INSERT INTO faenas (id, contrato_id, codigo, nombre, ubicacion, region, comuna, coordenadas_lat, coordenadas_lng, estado)
VALUES
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     'FAE-MP-001',
     'Faena Mina Principal',
     'Km 187 Ruta 25, Sector Mina Los Andes, Desierto de Atacama',
     'Antofagasta',
     'Sierra Gorda',
     -23.1234567,
     -69.3456789,
     'activa'),
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     'FAE-PC-002',
     'Faena Planta Concentradora',
     'Km 192 Ruta 25, Sector Planta de Procesos',
     'Antofagasta',
     'Sierra Gorda',
     -23.1567890,
     -69.3234567,
     'activa'),
    (gen_random_uuid(),
     (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
     'FAE-PE-003',
     'Faena Puerto Embarque',
     'Terminal Portuario Norte, Sector Industrial',
     'Antofagasta',
     'Mejillones',
     -23.0987654,
     -70.4123456,
     'activa');

-- ============================================================================
-- 3. BODEGAS (1 fija + 1 movil por faena)
-- ============================================================================

INSERT INTO bodegas (id, faena_id, codigo, nombre, tipo)
VALUES
    -- Faena Mina Principal
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     'BOD-MP-F01',
     'Bodega Central Combustibles - Mina Principal',
     'fija'),
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-MP-001'),
     'BOD-MP-M01',
     'Bodega Movil Lubrimovil - Mina Principal',
     'movil'),
    -- Faena Planta Concentradora
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     'BOD-PC-F01',
     'Bodega Central Combustibles - Planta Concentradora',
     'fija'),
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PC-002'),
     'BOD-PC-M01',
     'Bodega Movil Lubrimovil - Planta Concentradora',
     'movil'),
    -- Faena Puerto Embarque
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     'BOD-PE-F01',
     'Bodega Central Combustibles - Puerto Embarque',
     'fija'),
    (gen_random_uuid(),
     (SELECT id FROM faenas WHERE codigo = 'FAE-PE-003'),
     'BOD-PE-M01',
     'Bodega Movil Lubrimovil - Puerto Embarque',
     'movil');

-- ============================================================================
-- 4. MARCAS
-- ============================================================================

INSERT INTO marcas (id, nombre) VALUES
    (gen_random_uuid(), 'Caterpillar'),
    (gen_random_uuid(), 'Komatsu'),
    (gen_random_uuid(), 'Volvo'),
    (gen_random_uuid(), 'Mercedes-Benz'),
    (gen_random_uuid(), 'Scania'),
    (gen_random_uuid(), 'Lincoln'),
    (gen_random_uuid(), 'Wayne'),
    (gen_random_uuid(), 'Gilbarco'),
    (gen_random_uuid(), 'Tokheim'),
    (gen_random_uuid(), 'Atlas Copco');

-- ============================================================================
-- 5. MODELOS
-- ============================================================================

-- Caterpillar: equipos de bombeo y herramientas
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Caterpillar'),
     'CAT C7.1 Pump Unit',
     'equipo_bombeo',
     '{"potencia_hp": 225, "caudal_lpm": 1200, "presion_bar": 10, "aplicacion": "bombeo diesel a granel"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Caterpillar'),
     'CAT 938K Wheel Loader',
     'equipo_menor',
     '{"potencia_hp": 192, "capacidad_balde_m3": 3.2, "peso_operativo_kg": 18200}');

-- Komatsu: equipos menores
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Komatsu'),
     'Komatsu WA470-8',
     'equipo_menor',
     '{"potencia_hp": 270, "capacidad_balde_m3": 4.4, "peso_operativo_kg": 25100}');

-- Volvo: camiones cisterna
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Volvo'),
     'Volvo FH 540 6x4 Cisterna',
     'camion_cisterna',
     '{"potencia_hp": 540, "capacidad_litros": 30000, "ejes": 3, "pbt_kg": 48000, "tipo_cisterna": "diesel"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Volvo'),
     'Volvo FMX 500 4x4 Cisterna',
     'camion_cisterna',
     '{"potencia_hp": 500, "capacidad_litros": 20000, "ejes": 2, "pbt_kg": 32000, "tipo_cisterna": "diesel", "traccion": "4x4"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Volvo'),
     'Volvo FM 460 Lubrimovil',
     'lubrimovil',
     '{"potencia_hp": 460, "compartimentos": 6, "capacidad_aceite_litros": 8000, "capacidad_grasa_kg": 500}');

-- Mercedes-Benz: camionetas y camiones de servicio
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'),
     'Mercedes-Benz Sprinter 519 CDI',
     'camioneta',
     '{"potencia_hp": 190, "traccion": "4x2", "carga_util_kg": 2500, "uso": "transporte tecnico y repuestos"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Mercedes-Benz'),
     'Mercedes-Benz Actros 2645 Cisterna',
     'camion_cisterna',
     '{"potencia_hp": 450, "capacidad_litros": 25000, "ejes": 3, "pbt_kg": 45000}');

-- Scania: camiones cisterna
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Scania'),
     'Scania R 500 6x4 Cisterna',
     'camion_cisterna',
     '{"potencia_hp": 500, "capacidad_litros": 30000, "ejes": 3, "pbt_kg": 48000, "tipo_cisterna": "diesel"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Scania'),
     'Scania P 410 Lubrimovil',
     'lubrimovil',
     '{"potencia_hp": 410, "compartimentos": 4, "capacidad_aceite_litros": 6000, "capacidad_grasa_kg": 350}');

-- Lincoln: equipos de lubricacion y bombeo
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Lincoln'),
     'Lincoln PowerMaster III',
     'equipo_bombeo',
     '{"tipo": "bomba_grasa", "relacion": "55:1", "presion_max_bar": 517, "caudal_gramo_min": 900}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Lincoln'),
     'Lincoln FlowMaster',
     'equipo_bombeo',
     '{"tipo": "bomba_aceite", "relacion": "5:1", "presion_max_bar": 52, "caudal_lpm": 30}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Lincoln'),
     'Lincoln Centro Lubricacion CL-6',
     'herramienta_critica',
     '{"carretes": 6, "tipo_fluidos": ["aceite_motor", "aceite_transmision", "aceite_hidraulico", "refrigerante", "grasa", "agua_destilada"]}');

-- Wayne: surtidores
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Wayne'),
     'Wayne Helix 6000',
     'surtidor',
     '{"lados": 2, "mangueras_por_lado": 2, "caudal_max_lpm": 120, "precision_porcentaje": 0.3, "display": "LED"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Wayne'),
     'Wayne Ovation2',
     'surtidor',
     '{"lados": 2, "mangueras_por_lado": 3, "caudal_max_lpm": 150, "precision_porcentaje": 0.25, "display": "LCD_color", "conectividad": "ethernet"}');

-- Gilbarco: surtidores y dispensadores
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Gilbarco'),
     'Gilbarco Veeder-Root Encore 700',
     'surtidor',
     '{"lados": 2, "mangueras_por_lado": 2, "caudal_max_lpm": 130, "precision_porcentaje": 0.3, "conectividad": "RS-485"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Gilbarco'),
     'Gilbarco Veeder-Root TLS-450 PLUS',
     'dispensador',
     '{"tipo": "consola_monitoreo_tanques", "sondas": 8, "conectividad": "ethernet_wifi", "alarmas": true}');

-- Tokheim: surtidores
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Tokheim'),
     'Tokheim Quantium 510M',
     'surtidor',
     '{"lados": 2, "mangueras_por_lado": 2, "caudal_max_lpm": 130, "precision_porcentaje": 0.25, "display": "LCD"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Tokheim'),
     'Tokheim Quantium 430',
     'dispensador',
     '{"lados": 1, "mangueras": 2, "caudal_max_lpm": 80, "uso": "lubricantes_granel"}');

-- Atlas Copco: compresores y bombas
INSERT INTO modelos (id, marca_id, nombre, tipo_activo, especificaciones) VALUES
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Atlas Copco'),
     'Atlas Copco XAS 188 KD',
     'equipo_menor',
     '{"tipo": "compresor_portatil", "caudal_cfm": 375, "presion_bar": 7, "motor": "deutz_diesel"}'),
    (gen_random_uuid(),
     (SELECT id FROM marcas WHERE nombre = 'Atlas Copco'),
     'Atlas Copco WEDA D60N',
     'bomba',
     '{"tipo": "bomba_sumergible", "caudal_lpm": 2400, "altura_max_m": 32, "potencia_kw": 5.5}');

-- ============================================================================
-- 6. PRODUCTOS
-- ============================================================================

-- 6.1 Combustibles
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'COMB-DB5-001', '7801234560010', 'Diesel B5 S-50 (Ultra Bajo Azufre)', 'combustible', 'diesel', 'litro', 785.5000, 'cpp', 50000, 500000, false),
    (gen_random_uuid(), 'COMB-G93-001', '7801234560027', 'Gasolina 93 Octanos SP', 'combustible', 'gasolina', 'litro', 1025.0000, 'cpp', 5000, 50000, false),
    (gen_random_uuid(), 'COMB-G97-001', '7801234560034', 'Gasolina 97 Octanos SP', 'combustible', 'gasolina', 'litro', 1125.0000, 'cpp', 2000, 20000, false);

-- 6.2 Lubricantes - Aceites Motor
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'LUB-SHR4-001', '7801234560041', 'Shell Rimula R4 X 15W-40 (tambor 208L)', 'lubricante', 'aceite_motor', 'litro', 3850.0000, 'cpp', 2000, 20000, true),
    (gen_random_uuid(), 'LUB-MDM-001', '7801234560058', 'Mobil Delvac MX 15W-40 (tambor 208L)', 'lubricante', 'aceite_motor', 'litro', 3920.0000, 'cpp', 2000, 20000, true);

-- 6.3 Lubricantes - Aceite Hidraulico
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'LUB-STS2-001', '7801234560065', 'Shell Tellus S2 M 46 Hidraulico (tambor 208L)', 'lubricante', 'aceite_hidraulico', 'litro', 4150.0000, 'cpp', 1000, 10000, true);

-- 6.4 Lubricantes - Aceite Engranajes
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'LUB-MSHC-001', '7801234560072', 'Mobil SHC 630 Sintetico Engranajes (tambor 208L)', 'lubricante', 'aceite_engranajes', 'litro', 12500.0000, 'cpp', 500, 5000, true);

-- 6.5 Lubricantes - Grasa
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'LUB-SGS2-001', '7801234560089', 'Shell Gadus S2 V220 2 Grasa EP (barril 180kg)', 'lubricante', 'grasa', 'kilogramo', 5600.0000, 'cpp', 500, 5000, true);

-- 6.6 Filtros
INSERT INTO productos (id, codigo, codigo_barras, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, stock_maximo, tiene_vencimiento)
VALUES
    (gen_random_uuid(), 'FIL-CAT-0751', '7801234560096', 'Filtro Aceite CAT 1R-0751', 'filtro', 'filtro_aceite', 'unidad', 45000.0000, 'cpp', 50, 500, false),
    (gen_random_uuid(), 'FIL-CAT-2503', '7801234560102', 'Filtro Aire Primario CAT 6I-2503', 'filtro', 'filtro_aire', 'unidad', 85000.0000, 'cpp', 30, 300, false),
    (gen_random_uuid(), 'FIL-CAT-0749', '7801234560119', 'Filtro Combustible CAT 1R-0749', 'filtro', 'filtro_combustible', 'unidad', 38000.0000, 'cpp', 50, 500, false),
    (gen_random_uuid(), 'FIL-CAT-8878', '7801234560126', 'Filtro Hidraulico CAT 1G-8878', 'filtro', 'filtro_hidraulico', 'unidad', 92000.0000, 'cpp', 20, 200, false);

-- ============================================================================
-- 7. KPI DEFINICIONES (21 KPIs)
-- ============================================================================

-- -----------------------------------------------------------------------
-- Area A: Administracion de Combustibles (A1 - A8)
-- -----------------------------------------------------------------------

INSERT INTO kpi_definiciones (id, codigo, nombre, area, descripcion, formula, funcion_calculo, unidad, meta_valor, meta_direccion, peso, es_bloqueante, umbral_bloqueante, efecto_bloqueante, frecuencia, activo)
VALUES
    -- A1: Disponibilidad de puntos de abastecimiento
    (gen_random_uuid(),
     'A1',
     'Disponibilidad de Puntos de Abastecimiento',
     'administracion_combustibles',
     'Porcentaje de horas en que los puntos de abastecimiento (surtidores y dispensadores) estuvieron operativos respecto al total de horas programadas en el periodo.',
     '(horas_operativas / horas_programadas) * 100',
     'fn_kpi_disponibilidad_puntos_abastecimiento',
     '%',
     98.0000, 'mayor_igual', 0.0500, true, 90.0000, 'bloquear_incentivo', 'mensual', true),

    -- A2: Precision de despacho de combustible
    (gen_random_uuid(),
     'A2',
     'Precision de Despacho de Combustible',
     'administracion_combustibles',
     'Porcentaje de despachos cuya diferencia entre cantidad programada y cantidad real esta dentro de la tolerancia (+-0.5%).',
     '(despachos_dentro_tolerancia / total_despachos) * 100',
     'fn_kpi_precision_despacho',
     '%',
     99.0000, 'mayor_igual', 0.0400, false, NULL, NULL, 'mensual', true),

    -- A3: Cumplimiento de rutas programadas
    (gen_random_uuid(),
     'A3',
     'Cumplimiento de Rutas Programadas',
     'administracion_combustibles',
     'Porcentaje de rutas de despacho completadas respecto al total de rutas programadas en el periodo.',
     '(rutas_completadas / rutas_programadas) * 100',
     'fn_kpi_cumplimiento_rutas',
     '%',
     97.0000, 'mayor_igual', 0.0400, false, NULL, NULL, 'mensual', true),

    -- A4: Exactitud de inventario combustibles
    (gen_random_uuid(),
     'A4',
     'Exactitud de Inventario de Combustibles',
     'administracion_combustibles',
     'Porcentaje de coincidencia entre stock fisico medido (regla/sonda) y stock registrado en sistema, dentro de tolerancia (+-0.3%).',
     '(items_dentro_tolerancia / total_items_contados) * 100',
     'fn_kpi_exactitud_inventario_combustibles',
     '%',
     99.5000, 'mayor_igual', 0.0500, true, 95.0000, 'penalizar', 'mensual', true),

    -- A5: Tiempo de respuesta ante solicitudes de abastecimiento
    (gen_random_uuid(),
     'A5',
     'Tiempo de Respuesta Solicitudes Abastecimiento',
     'administracion_combustibles',
     'Porcentaje de solicitudes de abastecimiento atendidas dentro del plazo comprometido (maximo 2 horas desde la solicitud).',
     '(solicitudes_en_plazo / total_solicitudes) * 100',
     'fn_kpi_tiempo_respuesta_abastecimiento',
     '%',
     95.0000, 'mayor_igual', 0.0400, false, NULL, NULL, 'mensual', true),

    -- A6: Merma operacional de combustible
    (gen_random_uuid(),
     'A6',
     'Merma Operacional de Combustible',
     'administracion_combustibles',
     'Porcentaje de merma total de combustible respecto al volumen total despachado en el periodo. Meta: no superar 0.3%.',
     '(volumen_merma / volumen_total_despachado) * 100',
     'fn_kpi_merma_combustible',
     '%',
     0.3000, 'menor_igual', 0.0400, true, 1.0000, 'descontar', 'mensual', true),

    -- A7: Cumplimiento documental combustibles
    (gen_random_uuid(),
     'A7',
     'Cumplimiento Documental Combustibles',
     'administracion_combustibles',
     'Porcentaje de documentos y certificaciones vigentes (SEC, calibraciones, permisos) asociados a la operacion de combustibles.',
     '(documentos_vigentes / total_documentos_requeridos) * 100',
     'fn_kpi_cumplimiento_documental_combustibles',
     '%',
     100.0000, 'mayor_igual', 0.0300, true, 90.0000, 'bloquear_incentivo', 'mensual', true),

    -- A8: Tasa de incidentes ambientales combustibles
    (gen_random_uuid(),
     'A8',
     'Tasa de Incidentes Ambientales Combustibles',
     'administracion_combustibles',
     'Numero de incidentes ambientales (derrames, fugas) por cada 100.000 litros despachados en el periodo.',
     '(incidentes_ambientales / volumen_despachado_100k) * 100000',
     'fn_kpi_incidentes_ambientales_combustibles',
     'incidentes/100kL',
     0.0000, 'menor_igual', 0.0300, true, 1.0000, 'anular', 'mensual', true);

-- -----------------------------------------------------------------------
-- Area B: Mantenimiento de Plataformas Fijas (B1 - B6)
-- -----------------------------------------------------------------------

INSERT INTO kpi_definiciones (id, codigo, nombre, area, descripcion, formula, funcion_calculo, unidad, meta_valor, meta_direccion, peso, es_bloqueante, umbral_bloqueante, efecto_bloqueante, frecuencia, activo)
VALUES
    -- B1: Cumplimiento plan preventivo fijos
    (gen_random_uuid(),
     'B1',
     'Cumplimiento Plan Preventivo Plataformas Fijas',
     'mantenimiento_fijos',
     'Porcentaje de ordenes de mantenimiento preventivo ejecutadas vs programadas para activos fijos (surtidores, estanques, bombas) en el periodo.',
     '(ot_preventivas_ejecutadas / ot_preventivas_programadas) * 100',
     'fn_kpi_cumplimiento_pm_fijos',
     '%',
     98.0000, 'mayor_igual', 0.0700, true, 85.0000, 'bloquear_incentivo', 'mensual', true),

    -- B2: Disponibilidad de activos fijos
    (gen_random_uuid(),
     'B2',
     'Disponibilidad de Activos Fijos',
     'mantenimiento_fijos',
     'Porcentaje de tiempo que los activos fijos criticos estuvieron operativos respecto al total de horas del periodo.',
     '(horas_operativas_fijos / horas_totales_periodo) * 100',
     'fn_kpi_disponibilidad_activos_fijos',
     '%',
     97.0000, 'mayor_igual', 0.0700, true, 90.0000, 'penalizar', 'mensual', true),

    -- B3: Tiempo medio de reparacion fijos (MTTR)
    (gen_random_uuid(),
     'B3',
     'Tiempo Medio de Reparacion Activos Fijos (MTTR)',
     'mantenimiento_fijos',
     'Tiempo medio en horas entre el reporte de falla y la puesta en servicio de activos fijos. Meta: maximo 4 horas.',
     'SUM(horas_reparacion) / COUNT(reparaciones)',
     'fn_kpi_mttr_fijos',
     'horas',
     4.0000, 'menor_igual', 0.0500, false, NULL, NULL, 'mensual', true),

    -- B4: Cumplimiento calibraciones
    (gen_random_uuid(),
     'B4',
     'Cumplimiento de Calibraciones Programadas',
     'mantenimiento_fijos',
     'Porcentaje de calibraciones de instrumentos (medidores, surtidores) ejecutadas dentro del plazo programado.',
     '(calibraciones_en_plazo / calibraciones_programadas) * 100',
     'fn_kpi_cumplimiento_calibraciones',
     '%',
     100.0000, 'mayor_igual', 0.0500, true, 90.0000, 'bloquear_incentivo', 'mensual', true),

    -- B5: Exactitud de inventario repuestos fijos
    (gen_random_uuid(),
     'B5',
     'Exactitud Inventario Repuestos Plataformas Fijas',
     'mantenimiento_fijos',
     'Porcentaje de coincidencia entre stock fisico y stock sistema de repuestos para plataformas fijas.',
     '(items_correctos / total_items_contados) * 100',
     'fn_kpi_exactitud_inventario_repuestos_fijos',
     '%',
     98.0000, 'mayor_igual', 0.0400, false, NULL, NULL, 'mensual', true),

    -- B6: Backlog de OT correctivas fijos
    (gen_random_uuid(),
     'B6',
     'Backlog de OT Correctivas Plataformas Fijas',
     'mantenimiento_fijos',
     'Porcentaje de OT correctivas pendientes respecto al total de OT generadas para activos fijos en el periodo. Meta: maximo 5%.',
     '(ot_correctivas_pendientes / ot_correctivas_totales) * 100',
     'fn_kpi_backlog_correctivas_fijos',
     '%',
     5.0000, 'menor_igual', 0.0500, false, NULL, NULL, 'mensual', true);

-- -----------------------------------------------------------------------
-- Area C: Mantenimiento de Plataformas Moviles (C1 - C7)
-- -----------------------------------------------------------------------

INSERT INTO kpi_definiciones (id, codigo, nombre, area, descripcion, formula, funcion_calculo, unidad, meta_valor, meta_direccion, peso, es_bloqueante, umbral_bloqueante, efecto_bloqueante, frecuencia, activo)
VALUES
    -- C1: Cumplimiento plan preventivo moviles
    (gen_random_uuid(),
     'C1',
     'Cumplimiento Plan Preventivo Plataformas Moviles',
     'mantenimiento_moviles',
     'Porcentaje de ordenes de mantenimiento preventivo ejecutadas vs programadas para activos moviles (cisterna, lubrimovil, equipos de bombeo) en el periodo.',
     '(ot_preventivas_ejecutadas / ot_preventivas_programadas) * 100',
     'fn_kpi_cumplimiento_pm_moviles',
     '%',
     97.0000, 'mayor_igual', 0.0600, true, 85.0000, 'bloquear_incentivo', 'mensual', true),

    -- C2: Disponibilidad de flota movil
    (gen_random_uuid(),
     'C2',
     'Disponibilidad de Flota Movil',
     'mantenimiento_moviles',
     'Porcentaje de tiempo que la flota movil (cisternas, lubrimoviles) estuvo operativa respecto al total de horas del periodo.',
     '(horas_operativas_moviles / horas_totales_periodo) * 100',
     'fn_kpi_disponibilidad_flota_movil',
     '%',
     95.0000, 'mayor_igual', 0.0600, true, 85.0000, 'penalizar', 'mensual', true),

    -- C3: Tiempo medio de reparacion moviles (MTTR)
    (gen_random_uuid(),
     'C3',
     'Tiempo Medio de Reparacion Flota Movil (MTTR)',
     'mantenimiento_moviles',
     'Tiempo medio en horas entre el reporte de falla y la puesta en servicio de activos moviles. Meta: maximo 8 horas.',
     'SUM(horas_reparacion) / COUNT(reparaciones)',
     'fn_kpi_mttr_moviles',
     'horas',
     8.0000, 'menor_igual', 0.0400, false, NULL, NULL, 'mensual', true),

    -- C4: Cumplimiento certificaciones vehiculares
    (gen_random_uuid(),
     'C4',
     'Cumplimiento Certificaciones Vehiculares',
     'mantenimiento_moviles',
     'Porcentaje de vehiculos con revision tecnica, SOAP, permisos de circulacion y licencias especiales vigentes.',
     '(vehiculos_certificados / total_vehiculos) * 100',
     'fn_kpi_cumplimiento_certificaciones_vehiculares',
     '%',
     100.0000, 'mayor_igual', 0.0500, true, 95.0000, 'bloquear_incentivo', 'mensual', true),

    -- C5: Consumo de combustible flota propia
    (gen_random_uuid(),
     'C5',
     'Eficiencia Consumo Combustible Flota Propia',
     'mantenimiento_moviles',
     'Porcentaje de cumplimiento respecto al rendimiento esperado (km/litro o litros/hora) de la flota de servicio propia.',
     '(rendimiento_real / rendimiento_esperado) * 100',
     'fn_kpi_eficiencia_combustible_flota',
     '%',
     95.0000, 'mayor_igual', 0.0300, false, NULL, NULL, 'mensual', true),

    -- C6: Exactitud inventario repuestos moviles
    (gen_random_uuid(),
     'C6',
     'Exactitud Inventario Repuestos Plataformas Moviles',
     'mantenimiento_moviles',
     'Porcentaje de coincidencia entre stock fisico y stock sistema de repuestos para plataformas moviles.',
     '(items_correctos / total_items_contados) * 100',
     'fn_kpi_exactitud_inventario_repuestos_moviles',
     '%',
     98.0000, 'mayor_igual', 0.0300, false, NULL, NULL, 'mensual', true),

    -- C7: Backlog de OT correctivas moviles
    (gen_random_uuid(),
     'C7',
     'Backlog de OT Correctivas Plataformas Moviles',
     'mantenimiento_moviles',
     'Porcentaje de OT correctivas pendientes respecto al total de OT generadas para activos moviles en el periodo. Meta: maximo 8%.',
     '(ot_correctivas_pendientes / ot_correctivas_totales) * 100',
     'fn_kpi_backlog_correctivas_moviles',
     '%',
     8.0000, 'menor_igual', 0.0300, false, NULL, NULL, 'mensual', true);

-- ============================================================================
-- 8. KPI TRAMOS (6 tramos por cada KPI)
-- ============================================================================
-- Tramos de puntaje estandar para KPIs con meta_direccion = 'mayor_igual':
--   >= 100% meta  → 100 pts
--   95-99% meta   →  90 pts
--   90-94% meta   →  75 pts
--   85-89% meta   →  60 pts
--   80-84% meta   →  40 pts
--   <  80% meta   →   0 pts
--
-- Para KPIs con meta_direccion = 'menor_igual' la logica se invierte:
--   <= 100% meta  → 100 pts
--   101-105% meta →  90 pts
--   106-110% meta →  75 pts
--   111-115% meta →  60 pts
--   116-120% meta →  40 pts
--   >  120% meta  →   0 pts
-- ============================================================================

-- Funcion auxiliar para insertar tramos de KPI "mayor_igual"
-- Tramos se expresan como porcentaje de cumplimiento respecto a la meta (0-100+)
DO $$
DECLARE
    v_kpi RECORD;
BEGIN
    -- KPIs con meta_direccion = 'mayor_igual'
    FOR v_kpi IN
        SELECT id FROM kpi_definiciones WHERE meta_direccion = 'mayor_igual'
    LOOP
        -- Tramo 1: >= 100% cumplimiento → 100 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 100.0000, 999.9999, 100.00);

        -- Tramo 2: 95% a 99.99% cumplimiento → 90 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 95.0000, 99.9999, 90.00);

        -- Tramo 3: 90% a 94.99% cumplimiento → 75 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 90.0000, 94.9999, 75.00);

        -- Tramo 4: 85% a 89.99% cumplimiento → 60 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 85.0000, 89.9999, 60.00);

        -- Tramo 5: 80% a 84.99% cumplimiento → 40 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 80.0000, 84.9999, 40.00);

        -- Tramo 6: < 80% cumplimiento → 0 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 0.0000, 79.9999, 0.00);
    END LOOP;

    -- KPIs con meta_direccion = 'menor_igual' (A6, A8, B3, B6, C3, C7)
    -- Aqui el cumplimiento se mide como: si el valor medido <= meta, es 100%.
    -- Los tramos se expresan igualmente como % cumplimiento (invertido internamente por la funcion de calculo).
    FOR v_kpi IN
        SELECT id FROM kpi_definiciones WHERE meta_direccion = 'menor_igual'
    LOOP
        -- Tramo 1: >= 100% cumplimiento (valor <= meta) → 100 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 100.0000, 999.9999, 100.00);

        -- Tramo 2: 95-99.99% cumplimiento → 90 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 95.0000, 99.9999, 90.00);

        -- Tramo 3: 90-94.99% cumplimiento → 75 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 90.0000, 94.9999, 75.00);

        -- Tramo 4: 85-89.99% cumplimiento → 60 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 85.0000, 89.9999, 60.00);

        -- Tramo 5: 80-84.99% cumplimiento → 40 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 80.0000, 84.9999, 40.00);

        -- Tramo 6: < 80% cumplimiento → 0 pts
        INSERT INTO kpi_tramos (id, kpi_id, rango_min, rango_max, puntaje)
        VALUES (gen_random_uuid(), v_kpi.id, 0.0000, 79.9999, 0.00);
    END LOOP;
END $$;

-- ============================================================================
-- 9. CONFIGURACION ICEO PARA EL CONTRATO
-- ============================================================================

INSERT INTO configuracion_iceo (id, contrato_id, peso_area_a, peso_area_b, peso_area_c, umbral_deficiente, umbral_aceptable, umbral_bueno)
VALUES (
    gen_random_uuid(),
    (SELECT id FROM contratos WHERE codigo = 'CTR-2024-001'),
    0.3500,   -- Peso Area A: Administracion Combustibles
    0.3500,   -- Peso Area B: Mantenimiento Fijos
    0.3000,   -- Peso Area C: Mantenimiento Moviles
    70.00,    -- Bajo 70 puntos = Deficiente
    85.00,    -- 70-84.99 = Aceptable; 85+ = Bueno
    95.00     -- 95+ = Excelencia
);

-- ============================================================================
-- Verificacion final: resumen de datos semilla insertados
-- ============================================================================

DO $$
DECLARE
    v_contratos    INTEGER;
    v_faenas       INTEGER;
    v_bodegas      INTEGER;
    v_marcas       INTEGER;
    v_modelos      INTEGER;
    v_productos    INTEGER;
    v_kpi          INTEGER;
    v_tramos       INTEGER;
    v_config_iceo  INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_contratos   FROM contratos;
    SELECT COUNT(*) INTO v_faenas      FROM faenas;
    SELECT COUNT(*) INTO v_bodegas     FROM bodegas;
    SELECT COUNT(*) INTO v_marcas      FROM marcas;
    SELECT COUNT(*) INTO v_modelos     FROM modelos;
    SELECT COUNT(*) INTO v_productos   FROM productos;
    SELECT COUNT(*) INTO v_kpi         FROM kpi_definiciones;
    SELECT COUNT(*) INTO v_tramos      FROM kpi_tramos;
    SELECT COUNT(*) INTO v_config_iceo FROM configuracion_iceo;

    RAISE NOTICE '============================================';
    RAISE NOTICE 'SICOM-ICEO - Datos Semilla Insertados';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Contratos:          %', v_contratos;
    RAISE NOTICE 'Faenas:             %', v_faenas;
    RAISE NOTICE 'Bodegas:            %', v_bodegas;
    RAISE NOTICE 'Marcas:             %', v_marcas;
    RAISE NOTICE 'Modelos:            %', v_modelos;
    RAISE NOTICE 'Productos:          %', v_productos;
    RAISE NOTICE 'KPI Definiciones:   %', v_kpi;
    RAISE NOTICE 'KPI Tramos:         %', v_tramos;
    RAISE NOTICE 'Config ICEO:        %', v_config_iceo;
    RAISE NOTICE '============================================';
END $$;

COMMIT;

-- ============================================================================
-- Fin de 07_seed_data.sql
-- ============================================================================
