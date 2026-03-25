-- SICOM-ICEO | Fase 2 | Tablas KPI, ICEO, Compliance y Auditoria
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 04_tablas_kpi_iceo_compliance.sql
-- Proposito : Creacion de las tablas de certificaciones, documentos,
--             incidentes, rutas de despacho, abastecimientos, definiciones
--             y mediciones de KPI, periodos e ICEO compuesto, auditoria
--             de eventos y alertas del sistema.
-- Dependencias: 01_tipos_y_enums.sql, 02_tablas_core.sql,
--               03_tablas_operaciones.sql (ordenes_trabajo, movimientos_inventario)
-- ============================================================================

-- ============================================================================
-- 1. CERTIFICACIONES — Certificaciones y permisos de activos
-- ============================================================================

CREATE TABLE certificaciones (
    id                   UUID                   PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id            UUID                   NOT NULL REFERENCES activos(id),
    tipo                 tipo_certificacion_enum NOT NULL,
    numero_certificado   VARCHAR(100),
    entidad_certificadora VARCHAR(200),
    fecha_emision        DATE                   NOT NULL,
    fecha_vencimiento    DATE                   NOT NULL,
    estado               estado_documento_enum  NOT NULL DEFAULT 'vigente',
    archivo_url          TEXT,
    notas                TEXT,
    bloqueante           BOOLEAN                NOT NULL DEFAULT false,
    created_at           TIMESTAMPTZ            NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ            NOT NULL DEFAULT NOW(),
    created_by           UUID                   REFERENCES auth.users(id),

    CONSTRAINT chk_certificaciones_fechas
        CHECK (fecha_vencimiento >= fecha_emision)
);

CREATE INDEX idx_certificaciones_activo_id         ON certificaciones (activo_id);
CREATE INDEX idx_certificaciones_tipo              ON certificaciones (tipo);
CREATE INDEX idx_certificaciones_estado            ON certificaciones (estado);
CREATE INDEX idx_certificaciones_fecha_vencimiento ON certificaciones (fecha_vencimiento);
CREATE INDEX idx_certificaciones_bloqueante        ON certificaciones (bloqueante) WHERE bloqueante = true;
CREATE INDEX idx_certificaciones_created_by        ON certificaciones (created_by);

CREATE TRIGGER trg_certificaciones_updated_at
    BEFORE UPDATE ON certificaciones
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 2. DOCUMENTOS — Documentos generales adjuntos a cualquier entidad
-- ============================================================================

CREATE TABLE documentos (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entidad_tipo      VARCHAR(50) NOT NULL,
    entidad_id        UUID        NOT NULL,
    nombre            VARCHAR(200) NOT NULL,
    tipo_documento    VARCHAR(100),
    archivo_url       TEXT        NOT NULL,
    fecha_vencimiento DATE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by        UUID        REFERENCES auth.users(id),

    CONSTRAINT chk_documentos_entidad_tipo
        CHECK (entidad_tipo IN ('contrato', 'faena', 'activo', 'ot', 'producto'))
);

CREATE INDEX idx_documentos_entidad       ON documentos (entidad_tipo, entidad_id);
CREATE INDEX idx_documentos_fecha_venc    ON documentos (fecha_vencimiento) WHERE fecha_vencimiento IS NOT NULL;
CREATE INDEX idx_documentos_created_by    ON documentos (created_by);

-- ============================================================================
-- 3. INCIDENTES — Incidentes de seguridad, ambientales y operacionales
-- ============================================================================

CREATE TABLE incidentes (
    id                   UUID                  PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id          UUID                  REFERENCES contratos(id),
    faena_id             UUID                  NOT NULL REFERENCES faenas(id),
    activo_id            UUID                  REFERENCES activos(id),
    ot_id                UUID                  REFERENCES ordenes_trabajo(id),
    tipo                 tipo_incidente_enum   NOT NULL,
    fecha_incidente      TIMESTAMPTZ           NOT NULL,
    descripcion          TEXT                  NOT NULL,
    gravedad             VARCHAR(20)           NOT NULL,
    causa_raiz           TEXT,
    acciones_correctivas TEXT,
    estado               VARCHAR(20)           NOT NULL DEFAULT 'abierto',
    impacto_operacional  TEXT,
    evidencias           JSONB,
    created_at           TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
    created_by           UUID                  REFERENCES auth.users(id),

    CONSTRAINT chk_incidentes_gravedad
        CHECK (gravedad IN ('leve', 'moderado', 'grave', 'muy_grave')),
    CONSTRAINT chk_incidentes_estado
        CHECK (estado IN ('abierto', 'en_investigacion', 'cerrado'))
);

CREATE INDEX idx_incidentes_contrato_id      ON incidentes (contrato_id);
CREATE INDEX idx_incidentes_faena_id         ON incidentes (faena_id);
CREATE INDEX idx_incidentes_activo_id        ON incidentes (activo_id);
CREATE INDEX idx_incidentes_ot_id            ON incidentes (ot_id);
CREATE INDEX idx_incidentes_tipo             ON incidentes (tipo);
CREATE INDEX idx_incidentes_gravedad         ON incidentes (gravedad);
CREATE INDEX idx_incidentes_estado           ON incidentes (estado);
CREATE INDEX idx_incidentes_fecha_incidente  ON incidentes (fecha_incidente);
CREATE INDEX idx_incidentes_created_by       ON incidentes (created_by);

CREATE TRIGGER trg_incidentes_updated_at
    BEFORE UPDATE ON incidentes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 4. RUTAS_DESPACHO — Rutas de despacho para unidades moviles
-- ============================================================================

CREATE TABLE rutas_despacho (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id         UUID          REFERENCES contratos(id),
    faena_id            UUID          NOT NULL REFERENCES faenas(id),
    activo_id           UUID          REFERENCES activos(id),
    fecha_programada    DATE          NOT NULL,
    fecha_ejecucion     DATE,
    ruta_descripcion    TEXT,
    puntos_programados  INTEGER       NOT NULL DEFAULT 0,
    puntos_completados  INTEGER       NOT NULL DEFAULT 0,
    km_programados      NUMERIC(10,1),
    km_reales           NUMERIC(10,1),
    litros_despachados  NUMERIC(12,2),
    estado              VARCHAR(20)   NOT NULL DEFAULT 'programada',
    ot_id               UUID          REFERENCES ordenes_trabajo(id),
    operador_id         UUID          REFERENCES usuarios_perfil(id),
    observaciones       TEXT,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    created_by          UUID          REFERENCES auth.users(id),

    CONSTRAINT chk_rutas_estado
        CHECK (estado IN ('programada', 'en_ejecucion', 'completada', 'incompleta', 'cancelada')),
    CONSTRAINT chk_rutas_puntos
        CHECK (puntos_programados >= 0 AND puntos_completados >= 0),
    CONSTRAINT chk_rutas_km
        CHECK ((km_programados IS NULL OR km_programados >= 0) AND
               (km_reales IS NULL OR km_reales >= 0)),
    CONSTRAINT chk_rutas_litros
        CHECK (litros_despachados IS NULL OR litros_despachados >= 0)
);

CREATE INDEX idx_rutas_despacho_contrato_id      ON rutas_despacho (contrato_id);
CREATE INDEX idx_rutas_despacho_faena_id         ON rutas_despacho (faena_id);
CREATE INDEX idx_rutas_despacho_activo_id        ON rutas_despacho (activo_id);
CREATE INDEX idx_rutas_despacho_ot_id            ON rutas_despacho (ot_id);
CREATE INDEX idx_rutas_despacho_operador_id      ON rutas_despacho (operador_id);
CREATE INDEX idx_rutas_despacho_estado           ON rutas_despacho (estado);
CREATE INDEX idx_rutas_despacho_fecha_programada ON rutas_despacho (fecha_programada);
CREATE INDEX idx_rutas_despacho_created_by       ON rutas_despacho (created_by);

CREATE TRIGGER trg_rutas_despacho_updated_at
    BEFORE UPDATE ON rutas_despacho
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 5. ABASTECIMIENTOS — Registros individuales de abastecimiento/lubricacion
-- ============================================================================

CREATE TABLE abastecimientos (
    id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    ruta_despacho_id         UUID          REFERENCES rutas_despacho(id),
    ot_id                    UUID          REFERENCES ordenes_trabajo(id),
    activo_destino_id        UUID          REFERENCES activos(id),
    producto_id              UUID          NOT NULL REFERENCES productos(id),
    cantidad_programada      NUMERIC(12,3),
    cantidad_real            NUMERIC(12,3) NOT NULL,
    diferencia               NUMERIC(12,3) GENERATED ALWAYS AS (cantidad_real - COALESCE(cantidad_programada, cantidad_real)) STORED,
    fecha_hora               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    operador_id              UUID          NOT NULL REFERENCES usuarios_perfil(id),
    movimiento_inventario_id UUID          REFERENCES movimientos_inventario(id),
    observaciones            TEXT,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_abastecimientos_cantidad_real
        CHECK (cantidad_real >= 0),
    CONSTRAINT chk_abastecimientos_cantidad_programada
        CHECK (cantidad_programada IS NULL OR cantidad_programada >= 0)
);

CREATE INDEX idx_abastecimientos_ruta_despacho_id  ON abastecimientos (ruta_despacho_id);
CREATE INDEX idx_abastecimientos_ot_id             ON abastecimientos (ot_id);
CREATE INDEX idx_abastecimientos_activo_destino_id ON abastecimientos (activo_destino_id);
CREATE INDEX idx_abastecimientos_producto_id       ON abastecimientos (producto_id);
CREATE INDEX idx_abastecimientos_operador_id       ON abastecimientos (operador_id);
CREATE INDEX idx_abastecimientos_mov_inventario_id ON abastecimientos (movimiento_inventario_id);
CREATE INDEX idx_abastecimientos_fecha_hora        ON abastecimientos (fecha_hora);

-- ============================================================================
-- 6. KPI_DEFINICIONES — Definiciones maestras de KPI
-- ============================================================================

CREATE TABLE kpi_definiciones (
    id                  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              VARCHAR(10)    UNIQUE NOT NULL,
    nombre              VARCHAR(200)   NOT NULL,
    area                area_kpi_enum  NOT NULL,
    descripcion         TEXT,
    formula             TEXT           NOT NULL,
    funcion_calculo     VARCHAR(100)   NOT NULL,
    unidad              VARCHAR(20),
    meta_valor          NUMERIC(15,4)  NOT NULL,
    meta_direccion      VARCHAR(15)    NOT NULL DEFAULT 'mayor_igual',
    peso                NUMERIC(5,4)   NOT NULL,
    es_bloqueante       BOOLEAN        NOT NULL DEFAULT false,
    umbral_bloqueante   NUMERIC(15,4),
    efecto_bloqueante   efecto_bloqueante_enum,
    factor_penalizacion NUMERIC(5,4),
    puntos_descuento    NUMERIC(5,2),
    frecuencia          frecuencia_enum NOT NULL DEFAULT 'mensual',
    activo              BOOLEAN        NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_kpi_meta_direccion
        CHECK (meta_direccion IN ('mayor_igual', 'menor_igual', 'igual')),
    CONSTRAINT chk_kpi_peso
        CHECK (peso > 0 AND peso <= 1)
);

CREATE INDEX idx_kpi_definiciones_area     ON kpi_definiciones (area);
CREATE INDEX idx_kpi_definiciones_activo   ON kpi_definiciones (activo);
CREATE INDEX idx_kpi_definiciones_codigo   ON kpi_definiciones (codigo);

CREATE TRIGGER trg_kpi_definiciones_updated_at
    BEFORE UPDATE ON kpi_definiciones
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 7. KPI_TRAMOS — Tramos de puntaje por KPI
-- ============================================================================

CREATE TABLE kpi_tramos (
    id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    kpi_id     UUID          NOT NULL REFERENCES kpi_definiciones(id),
    rango_min  NUMERIC(15,4) NOT NULL,
    rango_max  NUMERIC(15,4) NOT NULL,
    puntaje    NUMERIC(5,2)  NOT NULL,

    CONSTRAINT uq_kpi_tramos_kpi_rango UNIQUE (kpi_id, rango_min),
    CONSTRAINT chk_kpi_tramos_rango
        CHECK (rango_max >= rango_min)
);

CREATE INDEX idx_kpi_tramos_kpi_id ON kpi_tramos (kpi_id);

-- ============================================================================
-- 8. MEDICIONES_KPI — Mediciones de KPI por periodo
-- ============================================================================

CREATE TABLE mediciones_kpi (
    id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    kpi_id                   UUID          NOT NULL REFERENCES kpi_definiciones(id),
    contrato_id              UUID          NOT NULL REFERENCES contratos(id),
    faena_id                 UUID          REFERENCES faenas(id),
    periodo_inicio           DATE          NOT NULL,
    periodo_fin              DATE          NOT NULL,
    valor_medido             NUMERIC(15,4) NOT NULL,
    porcentaje_cumplimiento  NUMERIC(7,4),
    puntaje                  NUMERIC(5,2)  NOT NULL,
    valor_ponderado          NUMERIC(7,4)  NOT NULL,
    bloqueante_activado      BOOLEAN       NOT NULL DEFAULT false,
    datos_calculo            JSONB,
    calculado_en             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_mediciones_kpi_periodo
        UNIQUE (kpi_id, contrato_id, faena_id, periodo_inicio),
    CONSTRAINT chk_mediciones_periodo
        CHECK (periodo_fin >= periodo_inicio)
);

CREATE INDEX idx_mediciones_kpi_kpi_id       ON mediciones_kpi (kpi_id);
CREATE INDEX idx_mediciones_kpi_contrato_id  ON mediciones_kpi (contrato_id);
CREATE INDEX idx_mediciones_kpi_faena_id     ON mediciones_kpi (faena_id);
CREATE INDEX idx_mediciones_kpi_periodo      ON mediciones_kpi (periodo_inicio, periodo_fin);
CREATE INDEX idx_mediciones_kpi_bloqueante   ON mediciones_kpi (bloqueante_activado) WHERE bloqueante_activado = true;

-- ============================================================================
-- 9. ICEO_PERIODOS — Indice ICEO compuesto por periodo
-- ============================================================================

CREATE TABLE iceo_periodos (
    id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id            UUID          NOT NULL REFERENCES contratos(id),
    faena_id               UUID          REFERENCES faenas(id),
    periodo_inicio         DATE          NOT NULL,
    periodo_fin            DATE          NOT NULL,
    puntaje_area_a         NUMERIC(7,4),
    puntaje_area_b         NUMERIC(7,4),
    puntaje_area_c         NUMERIC(7,4),
    peso_area_a            NUMERIC(5,4)  NOT NULL DEFAULT 0.35,
    peso_area_b            NUMERIC(5,4)  NOT NULL DEFAULT 0.35,
    peso_area_c            NUMERIC(5,4)  NOT NULL DEFAULT 0.30,
    iceo_bruto             NUMERIC(7,4)  NOT NULL,
    iceo_final             NUMERIC(7,4)  NOT NULL,
    clasificacion          clasificacion_iceo_enum NOT NULL,
    bloqueantes_activados  JSONB,
    incentivo_habilitado   BOOLEAN       NOT NULL DEFAULT true,
    observaciones          TEXT,
    calculado_en           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_iceo_periodos_contrato_periodo
        UNIQUE (contrato_id, faena_id, periodo_inicio),
    CONSTRAINT chk_iceo_periodos_periodo
        CHECK (periodo_fin >= periodo_inicio)
);

CREATE INDEX idx_iceo_periodos_contrato_id   ON iceo_periodos (contrato_id);
CREATE INDEX idx_iceo_periodos_faena_id      ON iceo_periodos (faena_id);
CREATE INDEX idx_iceo_periodos_periodo       ON iceo_periodos (periodo_inicio, periodo_fin);
CREATE INDEX idx_iceo_periodos_clasificacion ON iceo_periodos (clasificacion);

-- ============================================================================
-- 10. ICEO_DETALLE — Desglose del ICEO por KPI individual
-- ============================================================================

CREATE TABLE iceo_detalle (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    iceo_periodo_id     UUID          NOT NULL REFERENCES iceo_periodos(id),
    medicion_kpi_id     UUID          NOT NULL REFERENCES mediciones_kpi(id),
    kpi_codigo          VARCHAR(10),
    valor_medido        NUMERIC(15,4),
    puntaje             NUMERIC(5,2),
    peso                NUMERIC(5,4),
    valor_ponderado     NUMERIC(7,4),
    es_bloqueante       BOOLEAN,
    bloqueante_activado BOOLEAN       NOT NULL DEFAULT false,
    impacto_descripcion TEXT
);

CREATE INDEX idx_iceo_detalle_iceo_periodo_id ON iceo_detalle (iceo_periodo_id);
CREATE INDEX idx_iceo_detalle_medicion_kpi_id ON iceo_detalle (medicion_kpi_id);
CREATE INDEX idx_iceo_detalle_kpi_codigo      ON iceo_detalle (kpi_codigo);
CREATE INDEX idx_iceo_detalle_bloqueante      ON iceo_detalle (bloqueante_activado) WHERE bloqueante_activado = true;

-- ============================================================================
-- 11. CONFIGURACION_ICEO — Configuracion ICEO por contrato
-- ============================================================================

CREATE TABLE configuracion_iceo (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id      UUID         NOT NULL UNIQUE REFERENCES contratos(id),
    peso_area_a      NUMERIC(5,4) NOT NULL DEFAULT 0.35,
    peso_area_b      NUMERIC(5,4) NOT NULL DEFAULT 0.35,
    peso_area_c      NUMERIC(5,4) NOT NULL DEFAULT 0.30,
    umbral_deficiente NUMERIC(5,2) NOT NULL DEFAULT 70,
    umbral_aceptable NUMERIC(5,2) NOT NULL DEFAULT 85,
    umbral_bueno     NUMERIC(5,2) NOT NULL DEFAULT 95,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_config_iceo_pesos_suma
        CHECK (peso_area_a + peso_area_b + peso_area_c = 1.0),
    CONSTRAINT chk_config_iceo_pesos_positivos
        CHECK (peso_area_a > 0 AND peso_area_b > 0 AND peso_area_c > 0),
    CONSTRAINT chk_config_iceo_umbrales
        CHECK (umbral_deficiente < umbral_aceptable AND umbral_aceptable < umbral_bueno)
);

CREATE TRIGGER trg_configuracion_iceo_updated_at
    BEFORE UPDATE ON configuracion_iceo
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 12. AUDITORIA_EVENTOS — Log completo de auditoria
-- ============================================================================

CREATE TABLE auditoria_eventos (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tabla            VARCHAR(100) NOT NULL,
    registro_id      UUID         NOT NULL,
    accion           VARCHAR(20)  NOT NULL,
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    usuario_id       UUID,
    ip_address       INET,
    user_agent       TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_auditoria_accion
        CHECK (accion IN ('INSERT', 'UPDATE', 'DELETE'))
);

-- NOTA: No se agrega FK en usuario_id hacia auth.users porque pueden
-- existir acciones del sistema sin usuario asociado.

CREATE INDEX idx_auditoria_tabla        ON auditoria_eventos (tabla);
CREATE INDEX idx_auditoria_registro_id  ON auditoria_eventos (registro_id);
CREATE INDEX idx_auditoria_created_at   ON auditoria_eventos (created_at);
CREATE INDEX idx_auditoria_usuario_id   ON auditoria_eventos (usuario_id);
CREATE INDEX idx_auditoria_tabla_registro ON auditoria_eventos (tabla, registro_id);

-- ============================================================================
-- 13. ALERTAS — Alertas generadas por el sistema
-- ============================================================================

CREATE TABLE alertas (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo             VARCHAR(50)  NOT NULL,
    titulo           VARCHAR(200) NOT NULL,
    mensaje          TEXT,
    severidad        VARCHAR(20)  NOT NULL DEFAULT 'info',
    entidad_tipo     VARCHAR(50),
    entidad_id       UUID,
    destinatario_id  UUID         REFERENCES usuarios_perfil(id),
    leida            BOOLEAN      NOT NULL DEFAULT false,
    leida_en         TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_alertas_tipo
        CHECK (tipo IN ('vencimiento', 'stock_minimo', 'ot_vencida', 'incumplimiento', 'bloqueante')),
    CONSTRAINT chk_alertas_severidad
        CHECK (severidad IN ('info', 'warning', 'critical'))
);

CREATE INDEX idx_alertas_tipo            ON alertas (tipo);
CREATE INDEX idx_alertas_severidad       ON alertas (severidad);
CREATE INDEX idx_alertas_destinatario_id ON alertas (destinatario_id);
CREATE INDEX idx_alertas_leida           ON alertas (leida) WHERE leida = false;
CREATE INDEX idx_alertas_entidad         ON alertas (entidad_tipo, entidad_id);
CREATE INDEX idx_alertas_created_at      ON alertas (created_at);

-- ============================================================================
-- Fin de 04_tablas_kpi_iceo_compliance.sql
-- ============================================================================
