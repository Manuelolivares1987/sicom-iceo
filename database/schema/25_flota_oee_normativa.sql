-- ============================================================================
-- SICOM-ICEO | Migración 25 — Modelo de Flota, OEE y Cumplimiento Normativo
-- ============================================================================
-- Propósito : Integrar maestro de flota vehicular con estados comerciales y
--             operativos, cálculo OEE, checklist de verificación de
--             disponibilidad, gestión de conductores, no conformidades,
--             estado diario y alertas normativas automáticas.
-- Normativas: DS 298, DS 160, DS 132, Ley 16.744, Ley 21.561, Código Trabajo.
-- ============================================================================

-- ============================================================================
-- 1. NUEVOS TIPOS ENUMERADOS
-- ============================================================================

-- 1.1 Estado comercial del activo (dimensión de negocio)
CREATE TYPE estado_comercial_enum AS ENUM (
    'arrendado',           -- A: En manos del cliente, generando ingreso
    'disponible',          -- D: Operativo y listo para arriendo
    'uso_interno',         -- U: Asignado a operaciones propias / contrato empresa
    'leasing',             -- L: En leasing operativo
    'en_recepcion',        -- R: Recién devuelto, pendiente de inspección
    'en_venta',            -- V: Dispuesto para venta
    'comprometido'         -- Reservado para un cliente, pendiente de entrega
);

-- 1.2 Resultado de verificación de disponibilidad
CREATE TYPE resultado_verificacion_enum AS ENUM (
    'aprobado',
    'rechazado',
    'aprobado_con_observaciones',
    'pendiente'
);

-- 1.3 Tipo de no conformidad de servicio (para componente Calidad del OEE)
CREATE TYPE tipo_no_conformidad_enum AS ENUM (
    'entrega_fuera_tiempo',
    'entrega_incompleta',
    'incumplimiento_norma',
    'incidente_seguridad',
    'contaminacion',
    'documentacion_incompleta',
    'no_conformidad_ambiental',
    'repeticion_servicio',
    'falla_en_terreno',
    'otra'
);

-- 1.4 Tipo de licencia de conducir
CREATE TYPE tipo_licencia_enum AS ENUM (
    'A1', 'A2', 'A3', 'A4', 'A5',
    'B', 'C', 'D', 'E', 'F'
);

-- 1.5 Ampliar tipo_ot_enum con verificación de disponibilidad
ALTER TYPE tipo_ot_enum ADD VALUE IF NOT EXISTS 'verificacion_disponibilidad';

-- 1.6 Ampliar tipo_certificacion_enum con nuevos tipos normativos
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'permiso_circulacion';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'hermeticidad';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'tc8_sec';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'inscripcion_sec';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'seguro_rc';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'fops_rops';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'cert_gancho';

-- 1.7 Ampliar alertas con nuevos tipos normativos
ALTER TABLE alertas DROP CONSTRAINT IF EXISTS chk_alertas_tipo;
ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo
    CHECK (tipo IN (
        'vencimiento', 'stock_minimo', 'ot_vencida', 'incumplimiento', 'bloqueante',
        -- Nuevos tipos normativos
        'antiguedad_vehiculo',    -- DS 298: >15 años
        'semep_vencido',          -- DS 298: certificado psicosensométrico
        'fatiga_conductor',       -- Ley 21.561: horas de espera/conducción
        'rt_por_vencer',          -- Rev. Técnica próxima a vencer
        'hermeticidad_vencida',   -- DS 160: cert. hermeticidad
        'sec_no_vigente',         -- DS 160: inscripción SEC
        'sensor_fuga',            -- DS 160: alarma sensor activa
        'accidente_no_reportado', -- Ley 16.744: >24hrs sin reporte
        'jornada_excedida',       -- Ley 40 hrs
        'pts_faltante',           -- DS 132: sin procedimiento de trabajo seguro
        'disponibilidad_vencida'  -- Checklist de disponibilidad caducado
    ));

-- ============================================================================
-- 2. AMPLIACIÓN TABLA ACTIVOS — Campos específicos de flota vehicular
-- ============================================================================

-- 2.1 Campos de identificación vehicular
ALTER TABLE activos ADD COLUMN IF NOT EXISTS patente VARCHAR(10);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS centro_costo VARCHAR(20);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS vin_chasis VARCHAR(50);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS numero_motor VARCHAR(50);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS anio_fabricacion INTEGER;
ALTER TABLE activos ADD COLUMN IF NOT EXISTS potencia VARCHAR(30);

-- 2.2 Estado comercial (nueva dimensión)
ALTER TABLE activos ADD COLUMN IF NOT EXISTS estado_comercial estado_comercial_enum;

-- 2.3 Campos de operación
ALTER TABLE activos ADD COLUMN IF NOT EXISTS operacion VARCHAR(50);        -- Coquimbo, Calama, etc.
ALTER TABLE activos ADD COLUMN IF NOT EXISTS cliente_actual VARCHAR(200);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS ubicacion_actual VARCHAR(200);

-- 2.4 Sistemas de seguridad instalados (JSONB flexible)
ALTER TABLE activos ADD COLUMN IF NOT EXISTS sistemas_seguridad JSONB DEFAULT '{}';
-- Estructura esperada:
-- {
--   "antisomnolencia": true/false/"Sist. Instalado",
--   "mobileye": true/false/"Sist. Instalado",
--   "ecam": true/false/"Sist. Instalado",
--   "gps": true/false,
--   "tacografo": true/false,
--   "limitador_velocidad": true/false,
--   "alarma_retroceso": true/false,
--   "camara_retroceso": true/false
-- }

-- 2.5 Verificación de disponibilidad
ALTER TABLE activos ADD COLUMN IF NOT EXISTS ultima_verificacion_id UUID;
ALTER TABLE activos ADD COLUMN IF NOT EXISTS verificacion_vigente_hasta TIMESTAMPTZ;

-- 2.6 Índices para nuevos campos
CREATE INDEX IF NOT EXISTS idx_activos_patente ON activos (patente) WHERE patente IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activos_estado_comercial ON activos (estado_comercial) WHERE estado_comercial IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activos_operacion ON activos (operacion) WHERE operacion IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activos_anio ON activos (anio_fabricacion) WHERE anio_fabricacion IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_patente_unique ON activos (patente) WHERE patente IS NOT NULL AND patente != '';

-- ============================================================================
-- 3. TABLA CONDUCTORES — Gestión de operadores y certificaciones
-- ============================================================================

CREATE TABLE IF NOT EXISTS conductores (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_perfil_id   UUID        REFERENCES usuarios_perfil(id),
    contrato_id         UUID        REFERENCES contratos(id),

    -- Datos personales
    rut                 VARCHAR(12) UNIQUE NOT NULL,
    nombre_completo     VARCHAR(200) NOT NULL,
    telefono            VARCHAR(20),
    email               VARCHAR(200),

    -- Licencia de conducir
    tipo_licencia       tipo_licencia_enum NOT NULL,
    licencia_numero     VARCHAR(30),
    licencia_vencimiento DATE,

    -- SEMEP (certificado psicosensométrico) — DS 298
    semep_vigente       BOOLEAN     NOT NULL DEFAULT false,
    semep_vencimiento   DATE,
    semep_tipo          VARCHAR(20) DEFAULT 'anual',  -- 'anual' para pesados, 'cuatrienal' para livianos

    -- Certificación sustancias peligrosas — DS 298
    cert_sustancias_peligrosas BOOLEAN NOT NULL DEFAULT false,
    cert_sp_vencimiento DATE,

    -- Inducción faena minera — DS 132
    induccion_faena     BOOLEAN     NOT NULL DEFAULT false,
    induccion_vencimiento DATE,

    -- Control de fatiga — Ley 21.561
    horas_espera_mes_actual NUMERIC(6,1) NOT NULL DEFAULT 0,
    ultimo_reset_horas  DATE        NOT NULL DEFAULT CURRENT_DATE,

    -- Estado
    activo              BOOLEAN     NOT NULL DEFAULT true,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID        REFERENCES auth.users(id)
);

CREATE INDEX idx_conductores_contrato ON conductores (contrato_id);
CREATE INDEX idx_conductores_activo ON conductores (activo) WHERE activo = true;
CREATE INDEX idx_conductores_semep ON conductores (semep_vencimiento) WHERE semep_vigente = true;

CREATE TRIGGER trg_conductores_updated_at
    BEFORE UPDATE ON conductores
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 4. ESTADO DIARIO DE FLOTA — Registro día a día por equipo
-- ============================================================================

CREATE TABLE IF NOT EXISTS estado_diario_flota (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID        NOT NULL REFERENCES activos(id),
    fecha           DATE        NOT NULL,
    contrato_id     UUID        REFERENCES contratos(id),

    -- Estado del día (código de una letra, compatible con Excel)
    estado_codigo   CHAR(1)     NOT NULL,
    -- A=Arrendado, D=Disponible, H=Habilitación, R=Recepción,
    -- M=Mantención>1día, T=Mantención<1día, F=Fuera servicio,
    -- V=Venta, U=Uso interno, L=Leasing

    -- Datos operacionales del día
    conductor_id    UUID        REFERENCES conductores(id),
    cliente         VARCHAR(200),
    ubicacion       VARCHAR(200),
    operacion       VARCHAR(50),

    -- Métricas diarias (para OEE)
    horas_operativas    NUMERIC(5,1) DEFAULT 0,  -- Hrs motor en tarea productiva
    horas_disponibles   NUMERIC(5,1) DEFAULT 0,  -- Hrs que estuvo disponible
    horas_mantencion    NUMERIC(5,1) DEFAULT 0,  -- Hrs en mantención
    km_recorridos       NUMERIC(10,1) DEFAULT 0,

    -- Observaciones
    observacion     TEXT,

    -- Auditoría
    registrado_por  UUID        REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Un solo registro por activo por día
    CONSTRAINT uq_estado_diario_activo_fecha UNIQUE (activo_id, fecha),
    CONSTRAINT chk_estado_codigo CHECK (estado_codigo IN ('A','D','H','R','M','T','F','V','U','L'))
);

CREATE INDEX idx_estado_diario_fecha ON estado_diario_flota (fecha);
CREATE INDEX idx_estado_diario_activo ON estado_diario_flota (activo_id);
CREATE INDEX idx_estado_diario_operacion ON estado_diario_flota (operacion);
CREATE INDEX idx_estado_diario_estado ON estado_diario_flota (estado_codigo);

CREATE TRIGGER trg_estado_diario_updated_at
    BEFORE UPDATE ON estado_diario_flota
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 5. VERIFICACIÓN DE DISPONIBILIDAD — Checklist obligatorio
-- ============================================================================

CREATE TABLE IF NOT EXISTS verificaciones_disponibilidad (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID        NOT NULL REFERENCES activos(id),
    ot_id           UUID        REFERENCES ordenes_trabajo(id),
    contrato_id     UUID        REFERENCES contratos(id),

    -- Resultado
    resultado       resultado_verificacion_enum NOT NULL DEFAULT 'pendiente',
    puntaje_total   INTEGER,            -- Items OK / Items totales
    items_total     INTEGER,
    items_ok        INTEGER,
    items_no_ok     INTEGER,
    items_na        INTEGER,

    -- Vigencia
    fecha_verificacion TIMESTAMPTZ,
    vigente_hasta      TIMESTAMPTZ,     -- fecha_verificacion + días vigencia
    dias_vigencia      INTEGER NOT NULL DEFAULT 7,

    -- Responsables
    verificado_por  UUID        REFERENCES auth.users(id),
    aprobado_por    UUID        REFERENCES auth.users(id),
    aprobado_en     TIMESTAMPTZ,

    -- Motivo de rechazo
    motivo_rechazo  TEXT,

    -- Auditoría
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verif_activo ON verificaciones_disponibilidad (activo_id);
CREATE INDEX idx_verif_resultado ON verificaciones_disponibilidad (resultado);
CREATE INDEX idx_verif_vigencia ON verificaciones_disponibilidad (vigente_hasta);

CREATE TRIGGER trg_verificaciones_updated_at
    BEFORE UPDATE ON verificaciones_disponibilidad
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 6. NO CONFORMIDADES — Para componente Calidad del OEE
-- ============================================================================

CREATE TABLE IF NOT EXISTS no_conformidades (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID        NOT NULL REFERENCES activos(id),
    ot_id           UUID        REFERENCES ordenes_trabajo(id),
    contrato_id     UUID        REFERENCES contratos(id),
    conductor_id    UUID        REFERENCES conductores(id),

    tipo            tipo_no_conformidad_enum NOT NULL,
    descripcion     TEXT        NOT NULL,
    fecha_evento    DATE        NOT NULL,
    severidad       VARCHAR(20) NOT NULL DEFAULT 'media',

    -- Resolución
    accion_correctiva TEXT,
    resuelto        BOOLEAN     NOT NULL DEFAULT false,
    resuelto_en     TIMESTAMPTZ,
    resuelto_por    UUID        REFERENCES auth.users(id),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID        REFERENCES auth.users(id),

    CONSTRAINT chk_nc_severidad CHECK (severidad IN ('baja', 'media', 'alta', 'critica'))
);

CREATE INDEX idx_nc_activo ON no_conformidades (activo_id);
CREATE INDEX idx_nc_fecha ON no_conformidades (fecha_evento);
CREATE INDEX idx_nc_tipo ON no_conformidades (tipo);
CREATE INDEX idx_nc_resuelta ON no_conformidades (resuelto) WHERE resuelto = false;

CREATE TRIGGER trg_nc_updated_at
    BEFORE UPDATE ON no_conformidades
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 7. CONTROL DE JORNADA CONDUCTORES — Ley 21.561
-- ============================================================================

CREATE TABLE IF NOT EXISTS registro_jornada_conductor (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conductor_id    UUID        NOT NULL REFERENCES conductores(id),
    activo_id       UUID        REFERENCES activos(id),
    fecha           DATE        NOT NULL,

    -- Tiempos del día
    hora_inicio_conduccion  TIME,
    hora_fin_conduccion     TIME,
    horas_conduccion        NUMERIC(4,1) DEFAULT 0,
    horas_espera            NUMERIC(4,1) DEFAULT 0,
    horas_descanso          NUMERIC(4,1) DEFAULT 0,

    -- Alertas automáticas
    alerta_5hrs_sin_descanso BOOLEAN DEFAULT false,
    alerta_espera_acumulada  BOOLEAN DEFAULT false,

    -- Ruta
    origen          VARCHAR(200),
    destino         VARCHAR(200),
    km_recorridos   NUMERIC(10,1) DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_jornada_conductor_fecha UNIQUE (conductor_id, fecha)
);

CREATE INDEX idx_jornada_conductor ON registro_jornada_conductor (conductor_id);
CREATE INDEX idx_jornada_fecha ON registro_jornada_conductor (fecha);

-- ============================================================================
-- 8. FUNCIONES: OEE POR ACTIVO Y POR FLOTA
-- ============================================================================

-- 8.1 OEE individual por activo en un periodo
CREATE OR REPLACE FUNCTION calcular_oee_activo(
    p_activo_id UUID,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS TABLE (
    activo_id UUID,
    patente VARCHAR,
    disponibilidad_mecanica NUMERIC,
    utilizacion_operativa NUMERIC,
    calidad_servicio NUMERIC,
    oee NUMERIC,
    dias_periodo INTEGER,
    dias_operativos INTEGER,
    dias_mantencion INTEGER,
    dias_fuera_servicio INTEGER,
    horas_productivas NUMERIC,
    horas_disponibles NUMERIC,
    servicios_totales BIGINT,
    servicios_no_conformes BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_dias_periodo INTEGER;
    v_dias_operativos INTEGER;
    v_dias_no_disponibles INTEGER;
    v_horas_productivas NUMERIC;
    v_horas_disponibles NUMERIC;
    v_servicios_totales BIGINT;
    v_servicios_nc BIGINT;
    v_disponibilidad NUMERIC;
    v_utilizacion NUMERIC;
    v_calidad NUMERIC;
    v_oee NUMERIC;
    v_dias_mant INTEGER;
    v_dias_fs INTEGER;
BEGIN
    v_dias_periodo := (p_fecha_fin - p_fecha_inicio) + 1;

    -- Contar días por estado desde estado_diario_flota
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T')), 0),
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo = 'F'), 0),
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H')), 0),
        COALESCE(SUM(edf.horas_operativas), 0),
        COALESCE(SUM(edf.horas_disponibles), 0)
    INTO v_dias_mant, v_dias_fs, v_dias_operativos, v_horas_productivas, v_horas_disponibles
    FROM estado_diario_flota edf
    WHERE edf.activo_id = p_activo_id
      AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    v_dias_no_disponibles := v_dias_mant + v_dias_fs;

    -- Disponibilidad Mecánica = (Días periodo - Días no disponibles) / Días periodo
    IF v_dias_periodo > 0 THEN
        v_disponibilidad := ROUND(
            ((v_dias_periodo - v_dias_no_disponibles)::NUMERIC / v_dias_periodo) * 100, 2
        );
    ELSE
        v_disponibilidad := 0;
    END IF;

    -- Utilización Operativa = Horas productivas / Horas disponibles
    IF v_horas_disponibles > 0 THEN
        v_utilizacion := ROUND((v_horas_productivas / v_horas_disponibles) * 100, 2);
    ELSE
        -- Fallback: usar días arrendados/leasing/uso_interno como proxy
        SELECT COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo IN ('A','U','L')), 0)
        INTO v_dias_operativos
        FROM estado_diario_flota edf
        WHERE edf.activo_id = p_activo_id
          AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

        IF (v_dias_periodo - v_dias_no_disponibles) > 0 THEN
            v_utilizacion := ROUND(
                (v_dias_operativos::NUMERIC / (v_dias_periodo - v_dias_no_disponibles)) * 100, 2
            );
        ELSE
            v_utilizacion := 0;
        END IF;
    END IF;

    -- Calidad de Servicio = (Servicios totales - No conformidades) / Servicios totales
    -- Servicios = días que el equipo estuvo en operación (A, U, L)
    SELECT COUNT(*)
    INTO v_servicios_totales
    FROM estado_diario_flota edf
    WHERE edf.activo_id = p_activo_id
      AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
      AND edf.estado_codigo IN ('A', 'U', 'L');

    SELECT COUNT(*)
    INTO v_servicios_nc
    FROM no_conformidades nc
    WHERE nc.activo_id = p_activo_id
      AND nc.fecha_evento BETWEEN p_fecha_inicio AND p_fecha_fin;

    IF v_servicios_totales > 0 THEN
        v_calidad := ROUND(
            (GREATEST(v_servicios_totales - v_servicios_nc, 0)::NUMERIC / v_servicios_totales) * 100, 2
        );
    ELSE
        v_calidad := 100;  -- Sin servicios, no hay no conformidades
    END IF;

    -- OEE = Disponibilidad × Utilización × Calidad (como porcentaje 0-100)
    v_oee := ROUND((v_disponibilidad / 100) * (v_utilizacion / 100) * (v_calidad / 100) * 100, 2);

    RETURN QUERY SELECT
        p_activo_id,
        a.patente,
        v_disponibilidad,
        v_utilizacion,
        v_calidad,
        v_oee,
        v_dias_periodo,
        v_dias_operativos,
        v_dias_mant,
        v_dias_fs,
        v_horas_productivas,
        v_horas_disponibles,
        v_servicios_totales,
        v_servicios_nc
    FROM activos a
    WHERE a.id = p_activo_id;
END;
$$;

-- 8.2 OEE de flota completa (por operación o total)
CREATE OR REPLACE FUNCTION calcular_oee_flota(
    p_contrato_id UUID,
    p_fecha_inicio DATE,
    p_fecha_fin DATE,
    p_operacion VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    operacion VARCHAR,
    total_equipos BIGINT,
    disponibilidad_promedio NUMERIC,
    utilizacion_promedio NUMERIC,
    calidad_promedio NUMERIC,
    oee_promedio NUMERIC,
    clasificacion VARCHAR
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH activos_flota AS (
        SELECT a.id
        FROM activos a
        WHERE (a.contrato_id = p_contrato_id OR p_contrato_id IS NULL)
          AND a.estado != 'dado_baja'
          AND a.tipo IN ('camion_cisterna', 'camion', 'camioneta', 'lubrimovil')
          AND (p_operacion IS NULL OR a.operacion = p_operacion)
    ),
    oee_por_activo AS (
        SELECT
            o.disponibilidad_mecanica,
            o.utilizacion_operativa,
            o.calidad_servicio,
            o.oee
        FROM activos_flota af
        CROSS JOIN LATERAL calcular_oee_activo(af.id, p_fecha_inicio, p_fecha_fin) o
    )
    SELECT
        COALESCE(p_operacion, 'TOTAL')::VARCHAR,
        COUNT(*)::BIGINT,
        ROUND(AVG(opa.disponibilidad_mecanica), 2),
        ROUND(AVG(opa.utilizacion_operativa), 2),
        ROUND(AVG(opa.calidad_servicio), 2),
        ROUND(AVG(opa.oee), 2),
        CASE
            WHEN AVG(opa.oee) >= 80 THEN 'Clase Mundial'
            WHEN AVG(opa.oee) >= 64 THEN 'Bueno'
            WHEN AVG(opa.oee) >= 50 THEN 'Aceptable'
            ELSE 'Deficiente'
        END::VARCHAR
    FROM oee_por_activo opa;
END;
$$;

-- ============================================================================
-- 9. FUNCIONES: ALERTAS NORMATIVAS AUTOMÁTICAS
-- ============================================================================

-- 9.1 Verificar antigüedad de flota (DS 298: >15 años = bloqueo)
CREATE OR REPLACE FUNCTION fn_verificar_antiguedad_flota()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_anio_actual INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
    v_count INTEGER := 0;
    v_activo RECORD;
BEGIN
    FOR v_activo IN
        SELECT id, patente, anio_fabricacion, nombre
        FROM activos
        WHERE anio_fabricacion IS NOT NULL
          AND (v_anio_actual - anio_fabricacion) > 15
          AND estado != 'dado_baja'
          AND tipo IN ('camion_cisterna', 'camion', 'camioneta', 'lubrimovil')
    LOOP
        -- Crear alerta si no existe una reciente
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_activo.id
              AND tipo = 'antiguedad_vehiculo'
              AND created_at > CURRENT_DATE - INTERVAL '30 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                'antiguedad_vehiculo',
                'BLOQUEO DS 298: Vehículo supera 15 años',
                format('El vehículo %s (PPU: %s, año %s) tiene %s años de antigüedad. '
                       'Según DS 298, no puede operar en transporte de sustancias peligrosas. '
                       'Requiere evaluación especial o dar de baja.',
                       v_activo.nombre, v_activo.patente, v_activo.anio_fabricacion,
                       v_anio_actual - v_activo.anio_fabricacion),
                'critical',
                'activo',
                v_activo.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$$;

-- 9.2 Verificar SEMEP conductores vencido (DS 298)
CREATE OR REPLACE FUNCTION fn_verificar_semep_conductores()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    v_conductor RECORD;
BEGIN
    FOR v_conductor IN
        SELECT id, rut, nombre_completo, semep_vencimiento
        FROM conductores
        WHERE activo = true
          AND (semep_vencimiento IS NULL OR semep_vencimiento < CURRENT_DATE)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_conductor.id
              AND tipo = 'semep_vencido'
              AND created_at > CURRENT_DATE - INTERVAL '7 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                'semep_vencido',
                'BLOQUEO DS 298: SEMEP vencido - Conductor inhabilitado',
                format('El conductor %s (RUT: %s) tiene su certificado SEMEP vencido (%s). '
                       'No puede operar equipos pesados ni de sustancias peligrosas.',
                       v_conductor.nombre_completo, v_conductor.rut,
                       COALESCE(v_conductor.semep_vencimiento::TEXT, 'Sin fecha')),
                'critical',
                'conductor',
                v_conductor.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$$;

-- 9.3 Verificar horas de espera conductores (Ley 21.561: máx 88 hrs/mes)
CREATE OR REPLACE FUNCTION fn_verificar_fatiga_conductores()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    v_record RECORD;
BEGIN
    FOR v_record IN
        SELECT
            c.id,
            c.nombre_completo,
            c.rut,
            COALESCE(SUM(rjc.horas_espera), 0) AS horas_espera_mes
        FROM conductores c
        LEFT JOIN registro_jornada_conductor rjc
            ON rjc.conductor_id = c.id
            AND rjc.fecha >= date_trunc('month', CURRENT_DATE)::DATE
            AND rjc.fecha <= CURRENT_DATE
        WHERE c.activo = true
        GROUP BY c.id, c.nombre_completo, c.rut
        HAVING COALESCE(SUM(rjc.horas_espera), 0) > 70  -- Alerta anticipada a 70 hrs
    LOOP
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES (
            'fatiga_conductor',
            CASE WHEN v_record.horas_espera_mes >= 88
                THEN 'BLOQUEO Ley 21.561: Conductor excede 88 hrs espera/mes'
                ELSE 'ALERTA Ley 21.561: Conductor se acerca a 88 hrs espera/mes'
            END,
            format('Conductor %s (RUT: %s) acumula %s hrs de espera este mes. '
                   'Límite legal: 88 hrs mensuales.',
                   v_record.nombre_completo, v_record.rut, v_record.horas_espera_mes),
            CASE WHEN v_record.horas_espera_mes >= 88 THEN 'critical' ELSE 'warning' END,
            'conductor',
            v_record.id
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- 9.4 Verificar certificaciones próximas a vencer y vencidas
CREATE OR REPLACE FUNCTION fn_verificar_certificaciones_flota()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    v_cert RECORD;
BEGIN
    FOR v_cert IN
        SELECT
            c.id, c.tipo, c.fecha_vencimiento, c.bloqueante,
            a.id AS activo_id, a.patente, a.nombre AS activo_nombre,
            CASE
                WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencida'
                WHEN c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
            END AS estado_cert
        FROM certificaciones c
        JOIN activos a ON a.id = c.activo_id
        WHERE a.estado != 'dado_baja'
          AND c.estado != 'vencido'
          AND c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days'
          AND c.tipo IN ('revision_tecnica', 'hermeticidad', 'tc8_sec', 'inscripcion_sec',
                         'soap', 'permiso_circulacion', 'seguro_rc')
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_cert.id
              AND tipo IN ('rt_por_vencer', 'hermeticidad_vencida', 'sec_no_vigente', 'vencimiento')
              AND created_at > CURRENT_DATE - INTERVAL '7 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                CASE v_cert.tipo
                    WHEN 'revision_tecnica' THEN 'rt_por_vencer'
                    WHEN 'hermeticidad' THEN 'hermeticidad_vencida'
                    WHEN 'tc8_sec' THEN 'sec_no_vigente'
                    WHEN 'inscripcion_sec' THEN 'sec_no_vigente'
                    ELSE 'vencimiento'
                END,
                format('%s: %s — %s %s',
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'BLOQUEO' ELSE 'ALERTA' END,
                    v_cert.tipo,
                    v_cert.activo_nombre,
                    COALESCE('(PPU: ' || v_cert.patente || ')', '')),
                format('Certificación %s del equipo %s %s el %s.',
                    v_cert.tipo, v_cert.activo_nombre,
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'VENCIÓ' ELSE 'vence' END,
                    v_cert.fecha_vencimiento),
                CASE WHEN v_cert.estado_cert = 'vencida' THEN 'critical' ELSE 'warning' END,
                'certificacion',
                v_cert.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$$;

-- 9.5 Verificar vigencia de checklist de disponibilidad
CREATE OR REPLACE FUNCTION fn_verificar_disponibilidad_vigente()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
    v_activo RECORD;
BEGIN
    FOR v_activo IN
        SELECT a.id, a.patente, a.nombre, a.estado_comercial,
               a.verificacion_vigente_hasta
        FROM activos a
        WHERE a.estado != 'dado_baja'
          AND a.estado_comercial = 'disponible'
          AND (a.verificacion_vigente_hasta IS NULL
               OR a.verificacion_vigente_hasta < NOW())
    LOOP
        -- Marcar como ya no disponible: requiere re-verificación
        UPDATE activos
        SET estado_comercial = 'en_recepcion'  -- Fuerza re-verificación
        WHERE id = v_activo.id
          AND estado_comercial = 'disponible';

        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES (
            'disponibilidad_vencida',
            format('Verificación vencida: %s retirado de disponibles',
                   COALESCE(v_activo.patente, v_activo.nombre)),
            format('El equipo %s (PPU: %s) tenía checklist vigente hasta %s. '
                   'Ha sido retirado de disponibles. Requiere nueva verificación.',
                   v_activo.nombre, v_activo.patente, v_activo.verificacion_vigente_hasta),
            'warning',
            'activo',
            v_activo.id
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- ============================================================================
-- 10. TRIGGER: Bloqueo automático al marcar disponible sin verificación
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_validar_cambio_disponible()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Si se intenta cambiar estado_comercial a 'disponible'
    IF NEW.estado_comercial = 'disponible'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial != 'disponible')
    THEN
        -- Verificar que existe un checklist aprobado y vigente
        IF NOT EXISTS (
            SELECT 1 FROM verificaciones_disponibilidad vd
            WHERE vd.activo_id = NEW.id
              AND vd.resultado = 'aprobado'
              AND vd.vigente_hasta > NOW()
        ) THEN
            RAISE EXCEPTION
                'No se puede marcar como disponible sin checklist de verificación aprobado y vigente. '
                'Cree una OT de verificación_disponibilidad primero.';
        END IF;

        -- Actualizar referencia a última verificación
        SELECT vd.id, vd.vigente_hasta
        INTO NEW.ultima_verificacion_id, NEW.verificacion_vigente_hasta
        FROM verificaciones_disponibilidad vd
        WHERE vd.activo_id = NEW.id
          AND vd.resultado = 'aprobado'
          AND vd.vigente_hasta > NOW()
        ORDER BY vd.vigente_hasta DESC
        LIMIT 1;
    END IF;

    -- Bloqueo por antigüedad (DS 298: >15 años)
    IF NEW.anio_fabricacion IS NOT NULL
       AND (EXTRACT(YEAR FROM CURRENT_DATE) - NEW.anio_fabricacion) > 15
       AND NEW.estado_comercial IN ('disponible', 'arrendado')
       AND NEW.tipo IN ('camion_cisterna', 'camion')
    THEN
        RAISE EXCEPTION
            'BLOQUEO DS 298: Vehículo año % supera 15 años de antigüedad. '
            'No puede operar en transporte de sustancias peligrosas.',
            NEW.anio_fabricacion;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_cambio_disponible
    BEFORE UPDATE OF estado_comercial ON activos
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_cambio_disponible();

-- ============================================================================
-- 11. FUNCIÓN: Ejecución consolidada de todas las verificaciones normativas
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_ejecutar_verificaciones_normativas()
RETURNS TABLE (
    verificacion VARCHAR,
    alertas_generadas INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY SELECT 'Antigüedad flota (DS 298)'::VARCHAR, fn_verificar_antiguedad_flota();
    RETURN QUERY SELECT 'SEMEP conductores (DS 298)'::VARCHAR, fn_verificar_semep_conductores();
    RETURN QUERY SELECT 'Fatiga conductores (Ley 21.561)'::VARCHAR, fn_verificar_fatiga_conductores();
    RETURN QUERY SELECT 'Certificaciones flota'::VARCHAR, fn_verificar_certificaciones_flota();
    RETURN QUERY SELECT 'Disponibilidad vigente'::VARCHAR, fn_verificar_disponibilidad_vigente();
END;
$$;

-- ============================================================================
-- 12. VISTA: Resumen de disponibilidad diaria por operación
-- ============================================================================

CREATE OR REPLACE VIEW v_resumen_diario_flota AS
SELECT
    edf.fecha,
    edf.operacion,
    COUNT(*) AS total_equipos,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'A') AS arrendados,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'D') AS disponibles,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'U') AS uso_interno,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'L') AS leasing,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'M') AS en_mantencion,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'T') AS en_terreno,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'F') AS fuera_servicio,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'H') AS en_habilitacion,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'R') AS en_recepcion,
    COUNT(*) FILTER (WHERE edf.estado_codigo = 'V') AS en_venta,
    -- Disponibilidad mecánica del día
    ROUND(
        COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H'))::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 1
    ) AS disponibilidad_mecanica_pct,
    -- Tasa de arriendo del día
    ROUND(
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'A')::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H','V')), 0) * 100, 1
    ) AS tasa_arriendo_pct
FROM estado_diario_flota edf
GROUP BY edf.fecha, edf.operacion;

-- ============================================================================
-- 13. VISTA: Dashboard OEE consolidado
-- ============================================================================

CREATE OR REPLACE VIEW v_oee_mensual AS
SELECT
    date_trunc('month', edf.fecha)::DATE AS mes,
    edf.operacion,
    COUNT(DISTINCT edf.activo_id) AS total_equipos,

    -- Disponibilidad Mecánica
    ROUND(
        COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H'))::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 2
    ) AS disponibilidad_pct,

    -- Utilización (días productivos / días disponibles)
    ROUND(
        COUNT(*) FILTER (WHERE edf.estado_codigo IN ('A','U','L'))::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H')), 0) * 100, 2
    ) AS utilizacion_pct,

    -- Horas productivas vs disponibles (si hay datos de horómetro)
    ROUND(
        SUM(edf.horas_operativas) / NULLIF(SUM(edf.horas_disponibles), 0) * 100, 2
    ) AS utilizacion_horometro_pct,

    -- Totales
    SUM(edf.horas_operativas) AS total_horas_productivas,
    SUM(edf.horas_disponibles) AS total_horas_disponibles,
    SUM(edf.km_recorridos) AS total_km

FROM estado_diario_flota edf
GROUP BY date_trunc('month', edf.fecha), edf.operacion;

-- ============================================================================
-- 14. COMENTARIOS DE DOCUMENTACIÓN
-- ============================================================================

COMMENT ON TABLE conductores IS
    'Conductores/operadores de flota. Gestiona licencias, SEMEP (DS 298), '
    'certificación sustancias peligrosas y control de fatiga (Ley 21.561).';

COMMENT ON TABLE estado_diario_flota IS
    'Registro diario del estado de cada equipo. Alimenta cálculos OEE, '
    'reportes de disponibilidad y tasa de arriendo. Un registro por equipo por día.';

COMMENT ON TABLE verificaciones_disponibilidad IS
    'Checklist obligatorio antes de declarar un equipo disponible para arriendo. '
    'Basado en normativas DS 298, DS 160, DS 132. Tiene vigencia configurable.';

COMMENT ON TABLE no_conformidades IS
    'No conformidades de servicio (calidad). Alimenta el componente de Calidad '
    'del OEE. Tipos: entregas fuera de tiempo, incompletas, incidentes, etc.';

COMMENT ON TABLE registro_jornada_conductor IS
    'Control de horas de conducción, espera y descanso por conductor. '
    'Aplica Ley 21.561: máx 88 hrs espera/mes, descanso cada 5 hrs conducción.';

COMMENT ON FUNCTION calcular_oee_activo IS
    'Calcula OEE individual: Disponibilidad × Utilización × Calidad. '
    'Disponibilidad desde estado_diario_flota, Calidad desde no_conformidades.';

COMMENT ON FUNCTION calcular_oee_flota IS
    'OEE promedio de la flota, filtrable por operación. '
    'Clasificación: >=80 Clase Mundial, >=64 Bueno, >=50 Aceptable, <50 Deficiente.';

COMMENT ON FUNCTION fn_validar_cambio_disponible IS
    'TRIGGER: Impide marcar equipo como disponible sin checklist aprobado y vigente. '
    'También bloquea equipos >15 años para transporte sustancias peligrosas (DS 298).';
