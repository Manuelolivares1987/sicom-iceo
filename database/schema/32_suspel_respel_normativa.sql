-- ============================================================================
-- SICOM-ICEO | Migración 32 — Sustancias y Residuos Peligrosos (SUSPEL/RESPEL)
-- ============================================================================
-- Propósito : Soportar el cumplimiento normativo chileno para Prevención de
--             Riesgos:
--               - DS 43/2016 MINSAL (Almacenamiento SUSPEL)
--               - DS 148/2003 MINSAL (RESPEL + SIDREP)
--               - DS 298/1995 MTT    (Transporte cargas peligrosas)
--               - NCh 382.Of2013     (Clasificación SP)
--
-- Alcance:
--   1. Catálogo de productos peligrosos almacenados (diesel, lubricantes,
--      solventes, etc.) con HDS vigente.
--   2. Bodegas de almacenamiento con autorización sanitaria.
--   3. Catálogo de tipos de residuos peligrosos generados en taller.
--   4. Registro de movimientos RESPEL (libro de generación y retiros SIDREP).
--   5. Empresas receptoras autorizadas (Hidronor, Seché, Resin, etc.).
--   6. Documentos de cumplimiento asociados.
--   7. Vista agregada para el dashboard del prevencionista.
-- ============================================================================

-- ============================================================================
-- 1. TIPOS ENUMERADOS
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE clase_un_sp_enum AS ENUM (
        'clase_1',  -- Explosivos
        'clase_2',  -- Gases (comprimidos, licuados, disueltos)
        'clase_3',  -- Líquidos inflamables (diesel, bencina, solventes)
        'clase_4',  -- Sólidos inflamables
        'clase_5',  -- Comburentes y peróxidos
        'clase_6',  -- Tóxicos e infecciosos
        'clase_7',  -- Radiactivos
        'clase_8',  -- Corrosivos (ácidos, álcalis)
        'clase_9'   -- Misceláneos peligrosos
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE estado_documento_respel_enum AS ENUM (
        'vigente',
        'por_vencer',
        'vencido',
        'en_tramite',
        'no_aplica'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE tipo_bodega_sp_enum AS ENUM (
        'bodega_sp_general',       -- Bodega general de sustancias peligrosas
        'estanque_combustible',    -- Estanque fijo de combustible
        'aljibe_movil',            -- Aljibe móvil / camión cisterna
        'deposito_lubricantes',    -- Depósito de lubricantes
        'bodega_respel'            -- Bodega de residuos peligrosos
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- 2. CATÁLOGO DE PRODUCTOS PELIGROSOS (SUSPEL)
-- ============================================================================

CREATE TABLE IF NOT EXISTS suspel_productos (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo                VARCHAR(40) UNIQUE NOT NULL,
    nombre                VARCHAR(200) NOT NULL,
    nombre_comercial      VARCHAR(200),

    -- Clasificación normativa
    clase_un              clase_un_sp_enum NOT NULL,
    numero_un             VARCHAR(10),                -- UN1202, UN1203, etc.
    codigo_nch382         VARCHAR(20),                -- NCh 382 Of.2013
    grupo_embalaje        VARCHAR(5),                 -- I, II, III
    punto_inflamacion_c   NUMERIC(5,1),

    -- Hoja de datos de seguridad (HDS / SDS)
    hds_url               TEXT,
    hds_version           VARCHAR(20),
    hds_fecha_emision     DATE,
    hds_proxima_revision  DATE,                       -- Cada 5 años típicamente

    -- Proveedor
    proveedor             VARCHAR(200),
    pictogramas           TEXT[],                     -- ['GHS02','GHS08'...]

    activo                BOOLEAN NOT NULL DEFAULT true,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by            UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_suspel_prod_clase ON suspel_productos (clase_un);
CREATE INDEX IF NOT EXISTS idx_suspel_prod_hds_rev ON suspel_productos (hds_proxima_revision);
CREATE INDEX IF NOT EXISTS idx_suspel_prod_activo ON suspel_productos (activo) WHERE activo = true;

COMMENT ON TABLE suspel_productos IS
    'Catálogo NCh 382.Of2013 de sustancias peligrosas almacenadas. HDS vigente por 5 años.';

-- ============================================================================
-- 3. BODEGAS DE ALMACENAMIENTO (SUSPEL + RESPEL)
-- ============================================================================

CREATE TABLE IF NOT EXISTS suspel_bodegas (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo                VARCHAR(40) UNIQUE NOT NULL,
    nombre                VARCHAR(200) NOT NULL,
    tipo                  tipo_bodega_sp_enum NOT NULL,
    faena_id              UUID REFERENCES faenas(id),
    ubicacion             TEXT,

    -- Autorización sanitaria
    autorizacion_numero   VARCHAR(100),
    autorizacion_fecha    DATE,
    autorizacion_vencimiento DATE,
    autoridad_sanitaria   VARCHAR(100),               -- 'SEREMI Coquimbo', 'SEREMI Antofagasta'

    -- Capacidad
    capacidad_total_kg    NUMERIC(12,2),
    capacidad_total_litros NUMERIC(12,2),
    productos_permitidos  clase_un_sp_enum[],         -- Clases que puede almacenar

    -- Infraestructura obligatoria (DS 43)
    tiene_ducha_emergencia BOOLEAN NOT NULL DEFAULT false,
    tiene_lavaojos        BOOLEAN NOT NULL DEFAULT false,
    tiene_kit_derrame     BOOLEAN NOT NULL DEFAULT false,
    tiene_extintor        BOOLEAN NOT NULL DEFAULT false,
    tiene_rotulado        BOOLEAN NOT NULL DEFAULT false,
    tiene_sistema_contencion BOOLEAN NOT NULL DEFAULT false,

    -- Plan de emergencia
    plan_emergencia_url   TEXT,
    plan_emergencia_fecha DATE,

    ultima_inspeccion     DATE,
    proxima_inspeccion    DATE,

    activo                BOOLEAN NOT NULL DEFAULT true,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by            UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_suspel_bod_faena ON suspel_bodegas (faena_id);
CREATE INDEX IF NOT EXISTS idx_suspel_bod_venc ON suspel_bodegas (autorizacion_vencimiento);
CREATE INDEX IF NOT EXISTS idx_suspel_bod_insp ON suspel_bodegas (proxima_inspeccion);

COMMENT ON TABLE suspel_bodegas IS
    'Bodegas e instalaciones para almacenar sustancias y residuos peligrosos. Cumple DS 43.';

-- ============================================================================
-- 4. CATÁLOGO DE TIPOS DE RESIDUOS PELIGROSOS (RESPEL)
-- ============================================================================

CREATE TABLE IF NOT EXISTS respel_tipos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              VARCHAR(30) UNIQUE NOT NULL,        -- 'ACEITE_USADO', 'FILTRO_OIL', etc.
    nombre              VARCHAR(200) NOT NULL,
    descripcion         TEXT,

    -- Clasificación DS 148
    codigo_ds148        VARCHAR(20),                        -- I.8, A3020, etc.
    numero_un           VARCHAR(10),
    caracteristicas     TEXT[],                             -- ['toxicidad_cronica','inflamabilidad']
    tratamiento_sugerido VARCHAR(100),                      -- 'incineracion', 'reciclaje', 'disposicion_segura'

    unidad_medida       VARCHAR(20) NOT NULL DEFAULT 'kg',  -- kg, litros, unidades

    es_activo           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE respel_tipos IS
    'Catálogo de residuos peligrosos generados en operaciones y taller según DS 148/2003.';

-- ============================================================================
-- 5. EMPRESAS RECEPTORAS / TRANSPORTISTAS AUTORIZADAS DE RESPEL
-- ============================================================================

CREATE TABLE IF NOT EXISTS respel_empresas_receptoras (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre              VARCHAR(200) NOT NULL,
    rut                 VARCHAR(20) UNIQUE,

    -- Autorización sanitaria como receptor/transportista
    autorizacion_numero VARCHAR(100),
    autorizacion_vencimiento DATE,
    tipo_autorizacion   VARCHAR(50),                        -- 'transportista','receptor','eliminador'
    regiones_autorizadas TEXT[],

    tratamientos_autorizados TEXT[],                        -- ['incineracion','reciclaje']

    contacto_nombre     VARCHAR(200),
    contacto_telefono   VARCHAR(50),
    contacto_email      VARCHAR(200),

    contrato_vigente    BOOLEAN NOT NULL DEFAULT true,
    contrato_desde      DATE,
    contrato_hasta      DATE,

    activo              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_respel_empresas_activo ON respel_empresas_receptoras (activo);

-- ============================================================================
-- 6. REGISTRO DE MOVIMIENTOS RESPEL (LIBRO DE GENERACIÓN)
-- ============================================================================

CREATE TABLE IF NOT EXISTS respel_movimientos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Tipo de movimiento
    tipo_movimiento     VARCHAR(20) NOT NULL,               -- 'generacion','retiro','almacenamiento'
    fecha               DATE NOT NULL,

    -- Residuo
    respel_tipo_id      UUID NOT NULL REFERENCES respel_tipos(id),
    cantidad            NUMERIC(12,2) NOT NULL,
    unidad              VARCHAR(20) NOT NULL DEFAULT 'kg',

    -- Origen
    bodega_id           UUID REFERENCES suspel_bodegas(id),
    activo_origen_id    UUID REFERENCES activos(id),        -- Si viene de un equipo específico
    faena_id            UUID REFERENCES faenas(id),
    ot_id               UUID REFERENCES ordenes_trabajo(id), -- OT que generó el residuo

    -- Para retiros
    empresa_receptora_id UUID REFERENCES respel_empresas_receptoras(id),
    numero_sidrep       VARCHAR(100),                       -- Folio de declaración SIDREP
    numero_guia_transporte VARCHAR(100),
    certificado_disposicion_url TEXT,

    observaciones       TEXT,

    registrado_por      UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_respel_mov_tipo
        CHECK (tipo_movimiento IN ('generacion','retiro','almacenamiento','correccion'))
);

CREATE INDEX IF NOT EXISTS idx_respel_mov_fecha ON respel_movimientos (fecha);
CREATE INDEX IF NOT EXISTS idx_respel_mov_tipo ON respel_movimientos (respel_tipo_id);
CREATE INDEX IF NOT EXISTS idx_respel_mov_receptora ON respel_movimientos (empresa_receptora_id);
CREATE INDEX IF NOT EXISTS idx_respel_mov_mov ON respel_movimientos (tipo_movimiento);

COMMENT ON TABLE respel_movimientos IS
    'Libro de generación, almacenamiento y retiros de RESPEL. Base para declaraciones SIDREP.';

-- ============================================================================
-- 7. DOCUMENTOS NORMATIVOS GENERALES DE CUMPLIMIENTO
-- ============================================================================
-- Tabla genérica para adjuntar y versionar documentos normativos que no son
-- ni certificaciones de equipos ni HDS, ej: Plan de Manejo RESPEL,
-- autorización sanitaria de bodega, declaraciones RETC.

CREATE TABLE IF NOT EXISTS normativa_documentos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo              VARCHAR(250) NOT NULL,
    tipo                VARCHAR(40) NOT NULL,            -- 'plan_manejo_respel','autorizacion_bodega', etc.
    descripcion         TEXT,

    numero_documento    VARCHAR(100),
    entidad_emisora     VARCHAR(200),
    fecha_emision       DATE,
    fecha_vencimiento   DATE,
    estado              estado_documento_respel_enum NOT NULL DEFAULT 'vigente',

    archivo_url         TEXT,

    -- Relación a entidad
    bodega_id           UUID REFERENCES suspel_bodegas(id),
    faena_id            UUID REFERENCES faenas(id),

    notas               TEXT,
    responsable_id      UUID REFERENCES usuarios_perfil(id),

    activo              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_norm_doc_tipo ON normativa_documentos (tipo);
CREATE INDEX IF NOT EXISTS idx_norm_doc_venc ON normativa_documentos (fecha_vencimiento);
CREATE INDEX IF NOT EXISTS idx_norm_doc_estado ON normativa_documentos (estado);

-- ============================================================================
-- 8. SEED DE CATÁLOGOS (productos estándar, tipos RESPEL, empresas típicas)
-- ============================================================================

-- 8.1 Productos SUSPEL típicos para flota de combustibles
INSERT INTO suspel_productos (codigo, nombre, nombre_comercial, clase_un, numero_un, codigo_nch382, grupo_embalaje, punto_inflamacion_c, proveedor, pictogramas)
VALUES
    ('DIESEL_B5',       'Diesel B5 automotriz', 'Diesel Copec/ESMAX', 'clase_3', 'UN1202', 'NCh382-3', 'III',  55.0, 'ESMAX / Copec', ARRAY['GHS02','GHS07','GHS08','GHS09']),
    ('DIESEL_MINERO',   'Diesel para uso minero', 'Diesel B5 exento impuesto', 'clase_3', 'UN1202', 'NCh382-3', 'III', 55.0, 'ESMAX', ARRAY['GHS02','GHS07','GHS08']),
    ('BENCINA_93',      'Bencina 93 octanos', 'Bencina 93', 'clase_3', 'UN1203', 'NCh382-3', 'II', -40.0, 'Copec', ARRAY['GHS02','GHS07','GHS08','GHS09']),
    ('ACEITE_15W40',    'Aceite lubricante motor 15W40', 'Shell Rimula / Mobil Delvac', 'clase_9', NULL, NULL, 'III', 220.0, 'Shell/Mobil', ARRAY['GHS07','GHS09']),
    ('ACEITE_HIDRAULICO','Aceite hidráulico ISO VG68', 'Shell Tellus', 'clase_9', NULL, NULL, 'III', 210.0, 'Shell/Mobil', ARRAY['GHS07','GHS09']),
    ('ACEITE_TRANS',    'Aceite de transmisión 80W90', 'Shell Spirax', 'clase_9', NULL, NULL, 'III', 200.0, 'Shell/Mobil', ARRAY['GHS07']),
    ('REFRIGERANTE',    'Refrigerante etilenglicol 50/50', 'Prestone / Shell', 'clase_6', 'UN1153', NULL, 'III', NULL, 'Shell', ARRAY['GHS07','GHS08']),
    ('LIQUIDO_FRENO',   'Líquido de frenos DOT4', NULL, 'clase_6', NULL, NULL, 'III', 230.0, 'Varios', ARRAY['GHS07']),
    ('GRASA_LITIO',     'Grasa de litio multipropósito', NULL, 'clase_9', NULL, NULL, NULL, 220.0, 'Shell', ARRAY['GHS07']),
    ('SOLVENTE_LIMP',   'Solvente de limpieza industrial', NULL, 'clase_3', 'UN1993', NULL, 'II',  38.0, 'Varios', ARRAY['GHS02','GHS07','GHS08']),
    ('DESENGRASANTE',   'Desengrasante industrial alcalino', NULL, 'clase_8', 'UN1760', NULL, 'III', NULL, 'Varios', ARRAY['GHS05','GHS07']),
    ('ACIDO_BATERIA',   'Ácido sulfúrico electrolito baterías', NULL, 'clase_8', 'UN2796', NULL, 'II',  NULL, 'Varios', ARRAY['GHS05','GHS06'])
ON CONFLICT (codigo) DO NOTHING;

-- 8.2 Tipos de RESPEL estándar del taller mecánico
INSERT INTO respel_tipos (codigo, nombre, descripcion, codigo_ds148, numero_un, caracteristicas, tratamiento_sugerido, unidad_medida)
VALUES
    ('ACEITE_USADO',       'Aceite lubricante usado', 'Aceite usado de motor, hidráulico o transmisión proveniente de cambios de mantención', 'I.8 / A3020', 'UN3082', ARRAY['toxicidad_cronica','ecotoxico'], 'reciclaje', 'litros'),
    ('FILTROS_OIL',        'Filtros de aceite contaminados', 'Filtros de aceite usados con residuos de aceite', 'I.8', NULL, ARRAY['toxicidad_cronica'], 'incineracion', 'kg'),
    ('FILTROS_COMB',       'Filtros de combustible contaminados', 'Filtros de diesel/bencina usados', 'I.3', NULL, ARRAY['inflamabilidad'], 'incineracion', 'kg'),
    ('BATERIAS_PLOMO',     'Baterías plomo-ácido', 'Baterías de arranque fuera de uso', 'I.1 / A1010', 'UN2794', ARRAY['corrosivo','toxico'], 'reciclaje_autorizado', 'unidades'),
    ('ENVASES_CONTAM',     'Envases vacíos contaminados', 'Tambores y bidones vacíos que contuvieron SP', 'I.3/I.8', NULL, ARRAY['inflamabilidad','toxicidad_cronica'], 'reciclaje_autorizado', 'unidades'),
    ('TRAPOS_CONTAM',      'Paños y trapos contaminados', 'Elementos absorbentes contaminados con combustible o aceite', 'I.3/I.8', NULL, ARRAY['inflamabilidad'], 'incineracion', 'kg'),
    ('SOLVENTES_USADOS',   'Solventes usados', 'Solventes de limpieza ya contaminados', 'I.3', 'UN1993', ARRAY['inflamabilidad','toxicidad'], 'incineracion', 'litros'),
    ('REFRIGERANTE_USADO', 'Refrigerante usado', 'Refrigerante de motor retirado en mantención', 'I.6', NULL, ARRAY['toxicidad'], 'tratamiento_quimico', 'litros'),
    ('NEUMATICOS_FDU',     'Neumáticos fuera de uso', 'Neumáticos dados de baja - Ley REP 20.920', NULL, NULL, ARRAY['voluminoso'], 'reciclaje_rep', 'unidades'),
    ('LODOS_INDUS',        'Lodos de limpieza de estanques', 'Lodos con residuos de hidrocarburos', 'I.8', NULL, ARRAY['toxicidad_cronica','ecotoxico'], 'disposicion_segura', 'kg')
ON CONFLICT (codigo) DO NOTHING;

-- 8.3 Empresas receptoras típicas
INSERT INTO respel_empresas_receptoras (nombre, rut, tipo_autorizacion, regiones_autorizadas, tratamientos_autorizados, contacto_telefono, contacto_email)
VALUES
    ('Hidronor Chile S.A.',   '96.519.160-K', 'receptor_eliminador', ARRAY['I','II','III','IV','V','RM','VI','VII','VIII','IX','X','XIV','XV','XVI'], ARRAY['incineracion','reciclaje','disposicion_segura'], '+56-2-2350-0900', 'contacto@hidronor.cl'),
    ('Séché Group Chile',     '96.574.810-1', 'receptor_eliminador', ARRAY['RM','V','VI','VIII'], ARRAY['incineracion','reciclaje'], '+56-2-2964-2200', 'info@sechegroup.cl'),
    ('Resin SpA',             NULL,           'receptor',             ARRAY['RM','V'], ARRAY['reciclaje'], '+56-2-2000-0000', 'contacto@resin.cl'),
    ('Ecoprom Chile',         NULL,           'transportista',        ARRAY['IV','RM','V'], ARRAY['transporte'], NULL, NULL)
ON CONFLICT (rut) DO NOTHING;

-- ============================================================================
-- 9. VISTA AGREGADA PARA DASHBOARD PREVENCIONISTA
-- ============================================================================

CREATE OR REPLACE VIEW vw_prevencion_resumen AS
SELECT
    -- Certificaciones bloqueantes
    (SELECT COUNT(*) FROM certificaciones
       WHERE bloqueante = true AND fecha_vencimiento < CURRENT_DATE) AS certificaciones_vencidas,
    (SELECT COUNT(*) FROM certificaciones
       WHERE bloqueante = true AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days') AS certificaciones_por_vencer_30d,
    (SELECT COUNT(*) FROM certificaciones
       WHERE bloqueante = true AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '60 days') AS certificaciones_por_vencer_60d,

    -- SUSPEL: HDS por vencer
    (SELECT COUNT(*) FROM suspel_productos
       WHERE activo = true AND hds_proxima_revision < CURRENT_DATE + INTERVAL '90 days') AS hds_por_revisar,
    (SELECT COUNT(*) FROM suspel_productos WHERE activo = true) AS productos_suspel_activos,

    -- SUSPEL: bodegas
    (SELECT COUNT(*) FROM suspel_bodegas WHERE activo = true) AS bodegas_total,
    (SELECT COUNT(*) FROM suspel_bodegas
       WHERE activo = true AND autorizacion_vencimiento < CURRENT_DATE) AS bodegas_autorizacion_vencida,
    (SELECT COUNT(*) FROM suspel_bodegas
       WHERE activo = true AND proxima_inspeccion < CURRENT_DATE) AS bodegas_inspeccion_vencida,

    -- RESPEL: generación del mes actual
    (SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
       WHERE tipo_movimiento = 'generacion'
         AND fecha >= date_trunc('month', CURRENT_DATE)::DATE) AS respel_generado_mes_kg,
    (SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
       WHERE tipo_movimiento = 'retiro'
         AND fecha >= date_trunc('month', CURRENT_DATE)::DATE) AS respel_retirado_mes_kg,

    -- RESPEL: retiros sin declaración SIDREP
    (SELECT COUNT(*) FROM respel_movimientos
       WHERE tipo_movimiento = 'retiro' AND numero_sidrep IS NULL) AS retiros_sin_sidrep,

    -- Conductores: SEMEP
    (SELECT COUNT(*) FROM conductores
       WHERE activo = true AND (semep_vencimiento IS NULL OR semep_vencimiento < CURRENT_DATE)) AS conductores_semep_vencido,
    (SELECT COUNT(*) FROM conductores
       WHERE activo = true AND semep_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '60 days') AS conductores_semep_por_vencer,

    -- Conductores: horas espera
    (SELECT COUNT(*) FROM conductores
       WHERE activo = true AND horas_espera_mes_actual >= 88) AS conductores_fatiga_critica,

    -- Documentos normativos
    (SELECT COUNT(*) FROM normativa_documentos
       WHERE activo = true AND fecha_vencimiento < CURRENT_DATE) AS documentos_vencidos,
    (SELECT COUNT(*) FROM normativa_documentos
       WHERE activo = true AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days') AS documentos_por_vencer;

COMMENT ON VIEW vw_prevencion_resumen IS
    'Dashboard en un row: snapshot del cumplimiento normativo (SUSPEL, RESPEL, certificaciones, SEMEP).';
