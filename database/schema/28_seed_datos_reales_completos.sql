-- ============================================================================
-- SICOM-ICEO | Migración 28 — Datos reales completos del Panel de Control
-- ============================================================================
-- Corrige y completa el seed 26 con TODAS las certificaciones (fechas reales),
-- sistemas de seguridad, estados diarios reales (abril 1-7), técnicos del
-- taller, y estados comerciales corregidos.
-- Fuente: Panel de Control Flota V30 2026 Mes 04-D7.xlsx (todas las hojas)
-- ============================================================================

-- ============================================================================
-- 1. CERTIFICACIONES REALES — Revisión Técnica por equipo
-- ============================================================================

DO $$
DECLARE
    v_activo_id UUID;
    v_rec       RECORD;
BEGIN
    -- Función helper para insertar certificación
    -- Rev. Técnica para CADA equipo con fecha real del Excel

    -- Camiones pesados (RT semestral)
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('JTYK-88',  '2026-07-20'),
            ('GGHB-32',  '2026-08-24'),
            ('SVCZ-38',  '2026-05-05'),   -- ¡27 días! ALERTA
            ('SVBJ-55',  '2026-06-30'),
            ('TRST-58',  '2026-09-27'),
            ('LKPY-18',  '2026-08-18'),
            ('TGGF-56',  '2026-09-04'),
            ('TGGF-57',  '2026-09-28'),
            ('TGGF-58',  '2026-09-25'),
            ('TRDP-97',  '2026-08-26'),
            ('GCHT-12',  '2026-08-19'),
            ('KCBY-30',  '2026-06-10'),   -- 63 días
            ('KCBY-31',  '2026-07-03'),
            ('KVWW-68',  '2026-08-11'),
            ('KVWW-69',  '2026-08-26'),
            ('DCHD-83',  '2026-06-03'),
            ('KVWD-27',  '2026-06-14'),
            ('DJKL-18',  '2026-06-30'),
            ('FSLZ-67',  '2026-07-15'),
            ('HKSR-81',  '2026-06-04'),
            ('JGBY-10',  '2026-06-05'),
            ('SVBJ-56',  '2026-06-22'),
            ('SVBJ-57',  '2026-05-12'),   -- ¡32 días! ALERTA
            ('TCJV-15',  '2026-06-19'),
            ('LCSX-78',  '2026-08-27'),
            ('HHWB-42',  '2026-06-03'),
            ('HHWB-44',  '2026-05-10'),   -- ¡30 días! ALERTA
            ('TRST-57',  '2026-06-03'),
            ('FJTJ-60',  '2026-08-06'),
            ('FJTJ-61',  '2026-07-14'),
            ('TGGF-59',  '2026-09-19'),
            ('TGGF-60',  '2026-09-07'),
            ('TRDP-96',  '2026-09-07'),
            ('TRSS-14',  '2026-08-07'),
            ('TRSS-16',  '2026-05-13'),   -- ¡33 días! ALERTA
            ('RSCY-85',  '2026-08-04'),
            ('RSCY-86',  '2026-08-03'),
            ('TRSS-13',  '2026-04-08'),   -- ¡VENCIDA AYER!
            ('TRSS-15',  '2026-08-06'),
            ('TTPC-47',  '2026-07-08'),
            ('GCSY-66',  '2026-05-29')
        ) AS t(patente, fecha_venc)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, bloqueante)
            VALUES (v_activo_id, 'revision_tecnica',
                    v_rec.patente || '-RT-2026', 'Planta Revisión Técnica',
                    (v_rec.fecha_venc::DATE - INTERVAL '180 days')::DATE, v_rec.fecha_venc::DATE,
                    CASE WHEN v_rec.fecha_venc::DATE < CURRENT_DATE THEN 'vencido'
                         WHEN v_rec.fecha_venc::DATE < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
                         ELSE 'vigente' END::estado_documento_enum,
                    true)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- Camionetas y livianos (RT anual, vencen 2026-2028)
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('VRST-19',  '2028-01-31'),
            ('JDKH-31',  '2026-04-30'),   -- ¡20 días! ALERTA
            ('KVDK-20',  '2027-02-28'),
            ('KVDK-21',  '2026-04-30'),   -- ¡20 días! ALERTA
            ('SBPG-12',  '2027-05-30'),
            ('SPRY-26',  '2026-09-30'),
            ('SPRY-28',  '2027-11-30'),
            ('LLBP-96',  '2026-09-30'),
            ('RZPC-83',  '2027-06-30'),
            ('SLRK-82',  '2027-05-30'),
            ('SPRY-29',  '2028-01-31'),
            ('TCRB-71',  '2026-04-30'),   -- ¡20 días! ALERTA
            ('TSTB-48',  '2026-11-30')
        ) AS t(patente, fecha_venc)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, bloqueante)
            VALUES (v_activo_id, 'revision_tecnica',
                    v_rec.patente || '-RT-2026', 'Planta Revisión Técnica',
                    (v_rec.fecha_venc::DATE - INTERVAL '365 days')::DATE, v_rec.fecha_venc::DATE,
                    CASE WHEN v_rec.fecha_venc::DATE < CURRENT_DATE THEN 'vencido'
                         WHEN v_rec.fecha_venc::DATE < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
                         ELSE 'vigente' END::estado_documento_enum,
                    true)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- Grúa horquilla Yale (sin PCirc/Seguro en Excel)
    SELECT id INTO v_activo_id FROM activos WHERE patente = 'GDP 30TK';
    IF v_activo_id IS NOT NULL THEN
        INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                     fecha_emision, fecha_vencimiento, estado, bloqueante)
        VALUES (v_activo_id, 'revision_tecnica', 'GDP30TK-RT', 'PRT',
                '2025-01-01', '2030-01-01', 'vigente', false)
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- ============================================================================
-- 2. CERTIFICACIONES — Hermeticidad (solo cisternas de combustible)
-- ============================================================================

DO $$
DECLARE
    v_activo_id UUID;
    v_rec       RECORD;
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('DCHD-83',  '2026-07-27'),
            ('KVWD-27',  '2026-07-13'),
            ('DJKL-18',  '2026-06-29'),
            ('FSLZ-67',  '2026-04-09'),  -- ¡VENCE HOY!
            ('HKSR-81',  '2026-04-22'),
            ('JGBY-10',  '2026-06-05'),
            ('SVBJ-56',  '2026-04-15'),  -- ¡5 días!
            ('SVBJ-57',  '2026-07-05'),
            ('TCJV-15',  '2025-06-30'),  -- ¡VENCIDA!
            ('LCSX-78',  '2026-04-01'),  -- ¡VENCIDA!
            ('HHWB-42',  '2026-02-21'),  -- ¡VENCIDA!
            ('HHWB-44',  '2026-03-24'),  -- ¡VENCIDA!
            ('TRST-57',  '2026-05-14'),
            ('FJTJ-60',  '2026-04-01'),  -- ¡VENCIDA!
            ('RSCY-85',  '2026-08-13')
        ) AS t(patente, fecha_venc)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, bloqueante)
            VALUES (v_activo_id, 'hermeticidad',
                    v_rec.patente || '-HERM', 'OEC Autorizado SEC',
                    (v_rec.fecha_venc::DATE - INTERVAL '5 years')::DATE, v_rec.fecha_venc::DATE,
                    CASE WHEN v_rec.fecha_venc::DATE < CURRENT_DATE THEN 'vencido'
                         WHEN v_rec.fecha_venc::DATE < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
                         ELSE 'vigente' END::estado_documento_enum,
                    true)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 3. CERTIFICACIONES — TC8 / Inscripción SEC (cisternas combustible)
-- ============================================================================

DO $$
DECLARE
    v_activo_id UUID;
    v_rec       RECORD;
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('DCHD-83',  '2030-03-06'),
            ('KVWD-27',  '2028-11-15'),
            ('DJKL-18',  '2026-11-15'),
            ('FSLZ-67',  '2028-11-15'),
            ('HKSR-81',  '2030-11-04'),
            ('JGBY-10',  '2027-02-25'),
            ('SVBJ-56',  '2028-05-16'),
            ('SVBJ-57',  '2028-06-13'),
            ('TCJV-15',  '2029-02-01'),
            ('LCSX-78',  '2030-04-03'),
            ('HHWB-42',  '2030-09-03'),
            ('HHWB-44',  '2030-10-02'),
            ('TRST-57',  '2029-12-04'),
            ('FJTJ-60',  '2030-03-06'),
            ('RSCY-85',  '2031-02-16')
        ) AS t(patente, fecha_venc)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, bloqueante)
            VALUES (v_activo_id, 'tc8_sec',
                    v_rec.patente || '-TC8', 'SEC',
                    (v_rec.fecha_venc::DATE - INTERVAL '5 years')::DATE, v_rec.fecha_venc::DATE,
                    CASE WHEN v_rec.fecha_venc::DATE < CURRENT_DATE THEN 'vencido' ELSE 'vigente' END::estado_documento_enum,
                    true)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 4. CERTIFICACIONES — Certificado de Gancho (solo camiones pluma)
-- ============================================================================

DO $$
DECLARE
    v_activo_id UUID;
    v_rec       RECORD;
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('TGGF-60',  '2025-04-17'),  -- VENCIDA
            ('TRDP-96',  '2025-09-11'),  -- VENCIDA
            ('TRSS-14',  '2026-11-10'),
            ('TRSS-16',  '2025-10-08')   -- VENCIDA
        ) AS t(patente, fecha_venc)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            INSERT INTO certificaciones (activo_id, tipo, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, bloqueante)
            VALUES (v_activo_id, 'cert_gancho',
                    v_rec.patente || '-GANCHO', 'Organismo Certificador',
                    (v_rec.fecha_venc::DATE - INTERVAL '1 year')::DATE, v_rec.fecha_venc::DATE,
                    CASE WHEN v_rec.fecha_venc::DATE < CURRENT_DATE THEN 'vencido'
                         WHEN v_rec.fecha_venc::DATE < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
                         ELSE 'vigente' END::estado_documento_enum,
                    true)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 5. CORRECCIÓN estados comerciales y activo del seed 26
-- ============================================================================

DO $$
BEGIN
    -- KVWW-69: NO está arrendado, está F/S (día 1=M, días 2-7=F)
    UPDATE activos SET estado = 'fuera_servicio', estado_comercial = NULL,
        cliente_actual = 'Drilling service and solution'
    WHERE patente = 'KVWW-69';

    -- DCHD-83: Es habilitación, no uso_interno (días 2-7=H, año 2011 = 15 años!)
    UPDATE activos SET estado_comercial = NULL  -- En habilitación no tiene estado comercial
    WHERE patente = 'DCHD-83';

    -- FJTJ-60: Está en mantención (días 1-7=M), no en arriendo
    UPDATE activos SET estado = 'en_mantenimiento', estado_comercial = NULL
    WHERE patente = 'FJTJ-60';

    -- RSCY-86: Cambió de disponible a habilitación (día 1=D, días 2-7=H)
    UPDATE activos SET estado_comercial = NULL
    WHERE patente = 'RSCY-86';

    -- SBPG-12: Primeros 2 días en M, luego A. Corregir a arrendado (estado actual)
    UPDATE activos SET estado = 'operativo', estado_comercial = 'arrendado'
    WHERE patente = 'SBPG-12';

    -- Camionetas y furgones de uso interno que estaban mal clasificadas
    -- KVDK-20 está en Taller Fenix (aseguradora) - probablemente en reparación
    UPDATE activos SET ubicacion_actual = 'Taller Fenix (aseguradora)'
    WHERE patente = 'KVDK-20';
END $$;

-- ============================================================================
-- 6. ESTADO DIARIO — Días 1 al 7 de abril 2026 (datos reales del Excel)
-- ============================================================================

DO $$
DECLARE
    v_activo_id   UUID;
    v_contrato_id UUID;
    v_rec         RECORD;
    dia           INTEGER;
BEGIN
    SELECT id INTO v_contrato_id FROM contratos WHERE estado = 'activo' LIMIT 1;

    FOR v_rec IN
        SELECT * FROM (VALUES
            -- Patente, Operación, Cliente, Ubicación, d1, d2, d3, d4, d5, d6, d7
            ('JTYK-88','Coquimbo','Drilling service and solution','Faena Sobek, Copiapó','A','A','A','A','A','A','T'),
            ('GGHB-32','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('SVCZ-38','Coquimbo','Rentamaq','Mina Teck Andacollo, Coquimbo','A','A','A','A','A','A','A'),
            ('SVBJ-55','Coquimbo','Rentamaq','Mina Teck Andacollo, Coquimbo','A','A','A','A','A','A','M'),
            ('TRST-58','Calama','Boart Longyear','División Ministro Hales, Calama','A','A','A','A','A','A','A'),
            ('LKPY-18','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','M','M','M','M','M','M','M'),
            ('TGGF-56','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TGGF-57','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','R'),
            ('TGGF-58','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TRDP-97','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('GCHT-12','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('KCBY-30','Coquimbo','Drilling service and solution','Faena Marquesa, Huachalalume','A','A','A','A','A','A','A'),
            ('KCBY-31','Calama','Sin Contrato','Taller Pillado, Coquimbo','M','M','M','M','M','M','M'),
            ('KVWW-68','Calama','Sin Contrato','Taller Pillado, Coquimbo','M','M','M','M','M','M','M'),
            ('KVWW-69','Coquimbo','Drilling service and solution','Faena Cuprita, Inca de Oro','M','F','F','F','F','F','F'),
            ('DCHD-83','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','U','H','H','H','H','H','H'),
            ('KVWD-27','Coquimbo','San Gerónimo','Taller Pillado, Coquimbo','A','A','A','A','A','A','A'),
            ('DJKL-18','Coquimbo','Contrato CMP','CMP, Romeral','U','U','U','U','U','T','U'),
            ('FSLZ-67','Coquimbo','Contrato CMP','CMP, Romeral','U','U','U','U','U','U','U'),
            ('HKSR-81','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('JGBY-10','Coquimbo','Drilling service and solution','Faena Sobek, Copiapó','A','A','A','A','A','A','A'),
            ('SVBJ-56','Coquimbo','Esmax','El Salvador','A','A','A','A','A','A','A'),
            ('SVBJ-57','Coquimbo','Orbit Garant','Mina Los Bronces, Santiago','A','A','A','A','A','A','A'),
            ('TCJV-15','Calama','Orbit Garant','El Abra, Calama','A','A','A','A','A','A','A'),
            ('LCSX-78','Coquimbo','Sin Contrato','CMP, Romeral','M','M','M','M','M','M','M'),
            ('HHWB-42','Coquimbo','Contrato CM Cenizas','Francke, Taltal','U','U','U','U','U','U','U'),
            ('HHWB-44','Coquimbo','Contrato CM Cenizas','Francke, Taltal','U','U','U','U','U','U','U'),
            ('TRST-57','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('FJTJ-60','Coquimbo','San Gerónimo','San Antonio, Lambert','M','M','M','M','M','M','M'),
            ('FJTJ-61','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','V','V','V','V','V','V','V'),
            ('TGGF-59','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TGGF-60','Calama','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('TRDP-96','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TRSS-14','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TRSS-16','Coquimbo','Boart Longyear','Andina','A','A','A','A','A','A','A'),
            ('RSCY-85','Coquimbo','Major Drilling S.A','Faena Yastai, Tierra Amarilla','A','A','A','A','A','A','A'),
            ('RSCY-86','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','H','H','H','H','H','H'),
            ('TRSS-13','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','L','L'),
            ('TRSS-15','Calama','Boart Longyear','Spence, Calama','L','L','L','L','L','T','L'),
            ('TTPC-47','Calama','Boart Longyear','División Ministro Hales, Calama','A','A','A','A','A','A','A'),
            ('GCSY-66','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('GDP 30TK','Coquimbo','Sin Contrato','Taller Pillado, Coquimbo','D','D','D','D','D','D','D'),
            ('VRST-19','Calama','Sin Contrato','Taller Pillado, Calama','U','U','U','U','U','U','U'),
            ('JDKH-31','Coquimbo',NULL,'Taller Pillado, Coquimbo','U','U','U','U','U','U','U'),
            ('KVDK-20','Coquimbo',NULL,'Taller Fenix (aseguradora)','U','U','U','U','U','U','U'),
            ('KVDK-21','Coquimbo',NULL,'Taller Pillado, Coquimbo','U','U','U','U','U','U','U'),
            ('SBPG-12','Coquimbo','TPM Minería SA','Caserones, Copiapó','M','M','A','A','A','A','A'),
            ('SPRY-26','Calama','Contrato ESM','Contrato ESM, Calama','U','U','U','U','U','U','U'),
            ('SPRY-28','Calama','Contrato ESM','Contrato ESM, Calama','U','U','U','U','U','U','U'),
            ('LLBP-96','Coquimbo','Contrato CM Cenizas','Francke, Taltal','U','U','U','U','U','U','U'),
            ('RZPC-83','Coquimbo','Contrato CMP','CMP, Romeral','U','U','U','U','U','U','U'),
            ('SLRK-82','Coquimbo',NULL,'Taller Pillado, Coquimbo','U','U','U','U','U','U','U'),
            ('SPRY-29','Calama',NULL,'Taller Pillado, Calama','U','U','U','U','U','U','U'),
            ('TCRB-71','Coquimbo',NULL,NULL,'U','U','U','U','U','U','U'),
            ('TSTB-48','Coquimbo',NULL,NULL,'U','U','U','U','U','U','U')
        ) AS t(patente, operacion, cliente, ubicacion, d1, d2, d3, d4, d5, d6, d7)
    LOOP
        SELECT id INTO v_activo_id FROM activos WHERE patente = v_rec.patente;
        IF v_activo_id IS NOT NULL THEN
            FOR dia IN 1..7 LOOP
                DECLARE
                    v_estado CHAR(1);
                BEGIN
                    v_estado := CASE dia
                        WHEN 1 THEN v_rec.d1 WHEN 2 THEN v_rec.d2
                        WHEN 3 THEN v_rec.d3 WHEN 4 THEN v_rec.d4
                        WHEN 5 THEN v_rec.d5 WHEN 6 THEN v_rec.d6
                        WHEN 7 THEN v_rec.d7
                    END;

                    INSERT INTO estado_diario_flota (
                        activo_id, fecha, contrato_id, estado_codigo,
                        cliente, ubicacion, operacion
                    ) VALUES (
                        v_activo_id,
                        ('2026-04-0' || dia)::DATE,
                        v_contrato_id,
                        v_estado,
                        v_rec.cliente,
                        v_rec.ubicacion,
                        v_rec.operacion
                    )
                    ON CONFLICT (activo_id, fecha) DO UPDATE
                    SET estado_codigo = EXCLUDED.estado_codigo,
                        cliente = EXCLUDED.cliente,
                        ubicacion = EXCLUDED.ubicacion,
                        operacion = EXCLUDED.operacion;
                END;
            END LOOP;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 7. TÉCNICOS DEL TALLER — Seed de conductores/técnicos reales
-- ============================================================================

INSERT INTO conductores (rut, nombre_completo, tipo_licencia, semep_vigente, activo)
VALUES
    ('11111111-1', 'Felipe López', 'A2', true, true),
    ('22222222-2', 'Juan Valenzuela', 'A2', true, true),
    ('33333333-3', 'Yohan Rondón', 'A2', true, true),
    ('44444444-4', 'Pereira', 'A2', true, true),
    ('55555555-5', 'Luis Hernández', 'A2', true, true),
    ('66666666-6', 'Rodrigo Cortés', 'A2', true, true),
    ('77777777-7', 'Jesús Varela', 'B', true, true),
    ('88888888-8', 'Nibaldo', 'B', true, true)
ON CONFLICT (rut) DO NOTHING;

-- ============================================================================
-- 8. ACTUALIZAR sistemas_seguridad con datos correctos del Maestro
-- ============================================================================

-- Los que tienen Somnolencia + Mobileye + Ecam (los 3)
UPDATE activos SET sistemas_seguridad = '{"antisomnolencia": true, "mobileye": true, "ecam": true}'::JSONB
WHERE patente IN ('SVBJ-55', 'TGGF-56', 'TGGF-58', 'TRDP-97', 'TGGF-59', 'TGGF-60',
                  'TRDP-96', 'TRSS-14', 'TRSS-16', 'TRSS-13', 'TRSS-15', 'TTPC-47',
                  'SPRY-26', 'SPRY-28');

-- Somnolencia + Mobileye (sin Ecam)
UPDATE activos SET sistemas_seguridad = '{"antisomnolencia": true, "mobileye": true, "ecam": false}'::JSONB
WHERE patente IN ('SVCZ-38', 'KCBY-30', 'KCBY-31', 'KVWW-69', 'SVBJ-56');

-- Solo Ecam
UPDATE activos SET sistemas_seguridad = '{"antisomnolencia": false, "mobileye": false, "ecam": true}'::JSONB
WHERE patente IN ('TGGF-57');

-- Somnolencia + Mobileye + Ecam para Scania nuevos
UPDATE activos SET sistemas_seguridad = '{"antisomnolencia": true, "mobileye": true, "ecam": true}'::JSONB
WHERE patente IN ('TRST-57');

-- Nada instalado (camionetas simples, vehículos antiguos)
UPDATE activos SET sistemas_seguridad = '{"antisomnolencia": false, "mobileye": false, "ecam": false}'::JSONB
WHERE patente IN ('JTYK-88', 'GGHB-32', 'LKPY-18', 'GCHT-12', 'KVWW-68', 'DCHD-83',
                  'KVWD-27', 'HKSR-81', 'JGBY-10', 'LCSX-78', 'HHWB-42', 'HHWB-44',
                  'FJTJ-60', 'FJTJ-61', 'RSCY-85', 'RSCY-86', 'GCSY-66');

-- ============================================================================
-- 9. ALERTAS INMEDIATAS — Ejecutar verificación con datos reales
-- ============================================================================
-- Al correr esto con los datos reales, debería generar alertas para:
-- 1. DCHD-83: año 2011 = 15 años de antigüedad (DS 298)
-- 2. TRSS-13: RT vencida (2026-04-08)
-- 3. FSLZ-67: Hermeticidad vence HOY (2026-04-09)
-- 4. LCSX-78: Hermeticidad VENCIDA (2026-04-01)
-- 5. HHWB-42: Hermeticidad VENCIDA (2026-02-21)
-- 6. HHWB-44: Hermeticidad VENCIDA (2026-03-24)
-- 7. FJTJ-60: Hermeticidad VENCIDA (2026-04-01)
-- 8. TCJV-15: Hermeticidad VENCIDA (2025-06-30)
-- 9. TGGF-60: Cert. Gancho VENCIDO (2025-04-17)
-- 10. TRDP-96: Cert. Gancho VENCIDO (2025-09-11)
-- 11. TRSS-16: Cert. Gancho VENCIDO (2025-10-08)
-- 12. SVCZ-38: RT en 27 días (por vencer)
-- 13. SVBJ-57: RT en 32 días (por vencer)
-- 14. HHWB-44: RT en 30 días (por vencer)
-- 15. JDKH-31: RT en 20 días (por vencer)
-- 16. KVDK-21: RT en 20 días (por vencer)
-- 17. TCRB-71: RT en 20 días (por vencer)

SELECT fn_ejecutar_verificaciones_normativas();
