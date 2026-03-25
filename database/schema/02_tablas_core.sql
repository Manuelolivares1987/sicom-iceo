-- SICOM-ICEO | Fase 2 | Tablas Core
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 02_tablas_core.sql
-- Propósito : Creación de las tablas maestras (core) del sistema:
--             contratos, faenas, perfiles de usuario, catálogos de marcas
--             y modelos, activos, pautas de fabricante, planes de
--             mantenimiento, bodegas, productos e inventario valorizado.
-- Dependencias: 01_tipos_y_enums.sql (extensiones, tipos ENUM)
-- ============================================================================

-- ============================================================================
-- 0. FUNCIÓN AUXILIAR: auto-update de updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 1. CONTRATOS — Contratos de servicio minero
-- ============================================================================

CREATE TABLE contratos (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo          VARCHAR(50) UNIQUE NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    cliente         VARCHAR(200),
    descripcion     TEXT,
    fecha_inicio    DATE,
    fecha_fin       DATE,
    estado          VARCHAR(20) NOT NULL DEFAULT 'activo',
    valor_contrato  NUMERIC(15,2),
    moneda          VARCHAR(3)  NOT NULL DEFAULT 'CLP',
    sla_json        JSONB,
    obligaciones_json JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID        REFERENCES auth.users(id),

    CONSTRAINT chk_contratos_estado
        CHECK (estado IN ('activo', 'pausado', 'finalizado', 'cancelado')),
    CONSTRAINT chk_contratos_fechas
        CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
    CONSTRAINT chk_contratos_valor
        CHECK (valor_contrato IS NULL OR valor_contrato >= 0)
);

CREATE INDEX idx_contratos_estado      ON contratos (estado);
CREATE INDEX idx_contratos_cliente     ON contratos (cliente);
CREATE INDEX idx_contratos_created_by  ON contratos (created_by);

CREATE TRIGGER trg_contratos_updated_at
    BEFORE UPDATE ON contratos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 2. FAENAS — Sitios mineros
-- ============================================================================

CREATE TABLE faenas (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id     UUID        NOT NULL REFERENCES contratos(id),
    codigo          VARCHAR(50) UNIQUE NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    ubicacion       TEXT,
    region          VARCHAR(100),
    comuna          VARCHAR(100),
    coordenadas_lat NUMERIC(10,7),
    coordenadas_lng NUMERIC(10,7),
    estado          VARCHAR(20) NOT NULL DEFAULT 'activa',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID        REFERENCES auth.users(id),

    CONSTRAINT chk_faenas_estado
        CHECK (estado IN ('activa', 'inactiva', 'en_cierre')),
    CONSTRAINT chk_faenas_coordenadas_lat
        CHECK (coordenadas_lat IS NULL OR (coordenadas_lat BETWEEN -90 AND 90)),
    CONSTRAINT chk_faenas_coordenadas_lng
        CHECK (coordenadas_lng IS NULL OR (coordenadas_lng BETWEEN -180 AND 180))
);

CREATE INDEX idx_faenas_contrato_id ON faenas (contrato_id);
CREATE INDEX idx_faenas_estado      ON faenas (estado);
CREATE INDEX idx_faenas_region      ON faenas (region);
CREATE INDEX idx_faenas_created_by  ON faenas (created_by);

CREATE TRIGGER trg_faenas_updated_at
    BEFORE UPDATE ON faenas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 3. USUARIOS_PERFIL — Perfil extendido (vinculado a auth.users)
-- ============================================================================

CREATE TABLE usuarios_perfil (
    id              UUID        PRIMARY KEY REFERENCES auth.users(id),
    email           VARCHAR(255),
    nombre_completo VARCHAR(200),
    rut             VARCHAR(12),
    cargo           VARCHAR(150),
    telefono        VARCHAR(30),
    rol             rol_usuario_enum,
    faena_id        UUID        REFERENCES faenas(id),
    activo          BOOLEAN     NOT NULL DEFAULT true,
    firma_url       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_usuarios_perfil_rol       ON usuarios_perfil (rol);
CREATE INDEX idx_usuarios_perfil_faena_id  ON usuarios_perfil (faena_id);
CREATE INDEX idx_usuarios_perfil_activo    ON usuarios_perfil (activo);
CREATE INDEX idx_usuarios_perfil_rut       ON usuarios_perfil (rut);

CREATE TRIGGER trg_usuarios_perfil_updated_at
    BEFORE UPDATE ON usuarios_perfil
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 4. MARCAS — Marcas de equipos
-- ============================================================================

CREATE TABLE marcas (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre     VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 5. MODELOS — Modelos de equipos
-- ============================================================================

CREATE TABLE modelos (
    id               UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    marca_id         UUID              NOT NULL REFERENCES marcas(id),
    nombre           VARCHAR(150)      NOT NULL,
    tipo_activo      tipo_activo_enum  NOT NULL,
    especificaciones JSONB,
    created_at       TIMESTAMPTZ       NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_modelos_marca_nombre UNIQUE (marca_id, nombre)
);

CREATE INDEX idx_modelos_marca_id    ON modelos (marca_id);
CREATE INDEX idx_modelos_tipo_activo ON modelos (tipo_activo);

-- ============================================================================
-- 6. ACTIVOS — Todos los activos gestionados
-- ============================================================================

CREATE TABLE activos (
    id                UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id       UUID              REFERENCES contratos(id),
    faena_id          UUID              REFERENCES faenas(id),
    modelo_id         UUID              NOT NULL REFERENCES modelos(id),
    codigo            VARCHAR(50)       UNIQUE NOT NULL,
    nombre            VARCHAR(200),
    tipo              tipo_activo_enum  NOT NULL,
    numero_serie      VARCHAR(100),
    criticidad        criticidad_enum   NOT NULL DEFAULT 'media',
    estado            estado_activo_enum NOT NULL DEFAULT 'operativo',
    fecha_alta        DATE,
    fecha_baja        DATE,
    ubicacion_detalle TEXT,
    kilometraje_actual NUMERIC(12,1)    NOT NULL DEFAULT 0,
    horas_uso_actual  NUMERIC(12,1)     NOT NULL DEFAULT 0,
    ciclos_actual     INTEGER           NOT NULL DEFAULT 0,
    notas             TEXT,
    created_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    created_by        UUID              REFERENCES auth.users(id),

    CONSTRAINT chk_activos_kilometraje CHECK (kilometraje_actual >= 0),
    CONSTRAINT chk_activos_horas       CHECK (horas_uso_actual >= 0),
    CONSTRAINT chk_activos_ciclos      CHECK (ciclos_actual >= 0),
    CONSTRAINT chk_activos_fechas
        CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_alta)
);

CREATE INDEX idx_activos_contrato_id ON activos (contrato_id);
CREATE INDEX idx_activos_faena_id    ON activos (faena_id);
CREATE INDEX idx_activos_modelo_id   ON activos (modelo_id);
CREATE INDEX idx_activos_tipo        ON activos (tipo);
CREATE INDEX idx_activos_estado      ON activos (estado);
CREATE INDEX idx_activos_criticidad  ON activos (criticidad);
CREATE INDEX idx_activos_created_by  ON activos (created_by);

CREATE TRIGGER trg_activos_updated_at
    BEFORE UPDATE ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 7. PAUTAS_FABRICANTE — Pautas maestras de mantenimiento del fabricante
-- ============================================================================

CREATE TABLE pautas_fabricante (
    id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    modelo_id             UUID              NOT NULL REFERENCES modelos(id),
    nombre                VARCHAR(200)      NOT NULL,
    tipo_plan             tipo_plan_pm_enum NOT NULL,
    frecuencia_dias       INTEGER,
    frecuencia_km         NUMERIC(12,1),
    frecuencia_horas      NUMERIC(12,1),
    frecuencia_ciclos     INTEGER,
    descripcion           TEXT,
    items_checklist       JSONB             NOT NULL,
    materiales_estimados  JSONB,
    duracion_estimada_hrs NUMERIC(5,1),
    activo                BOOLEAN           NOT NULL DEFAULT true,
    created_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    created_by            UUID              REFERENCES auth.users(id),

    CONSTRAINT chk_pautas_frecuencia_dias   CHECK (frecuencia_dias IS NULL OR frecuencia_dias > 0),
    CONSTRAINT chk_pautas_frecuencia_km     CHECK (frecuencia_km IS NULL OR frecuencia_km > 0),
    CONSTRAINT chk_pautas_frecuencia_horas  CHECK (frecuencia_horas IS NULL OR frecuencia_horas > 0),
    CONSTRAINT chk_pautas_frecuencia_ciclos CHECK (frecuencia_ciclos IS NULL OR frecuencia_ciclos > 0),
    CONSTRAINT chk_pautas_duracion          CHECK (duracion_estimada_hrs IS NULL OR duracion_estimada_hrs > 0)
);

CREATE INDEX idx_pautas_fabricante_modelo_id ON pautas_fabricante (modelo_id);
CREATE INDEX idx_pautas_fabricante_tipo_plan ON pautas_fabricante (tipo_plan);
CREATE INDEX idx_pautas_fabricante_activo    ON pautas_fabricante (activo);
CREATE INDEX idx_pautas_fabricante_created_by ON pautas_fabricante (created_by);

CREATE TRIGGER trg_pautas_fabricante_updated_at
    BEFORE UPDATE ON pautas_fabricante
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 8. PLANES_MANTENIMIENTO — Planes PM asignados a activos individuales
-- ============================================================================

CREATE TABLE planes_mantenimiento (
    id                       UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id                UUID              NOT NULL REFERENCES activos(id),
    pauta_fabricante_id      UUID              NOT NULL REFERENCES pautas_fabricante(id),
    nombre                   VARCHAR(200),
    tipo_plan                tipo_plan_pm_enum,
    frecuencia_dias          INTEGER,
    frecuencia_km            NUMERIC(12,1),
    frecuencia_horas         NUMERIC(12,1),
    frecuencia_ciclos        INTEGER,
    anticipacion_dias        INTEGER           NOT NULL DEFAULT 7,
    prioridad                prioridad_enum    NOT NULL DEFAULT 'normal',
    ultima_ejecucion_fecha   TIMESTAMPTZ,
    ultima_ejecucion_km      NUMERIC(12,1),
    ultima_ejecucion_horas   NUMERIC(12,1),
    ultima_ejecucion_ciclos  INTEGER,
    proxima_ejecucion_fecha  DATE,
    activo_plan              BOOLEAN           NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    created_by               UUID              REFERENCES auth.users(id),

    CONSTRAINT chk_planes_frecuencia_dias   CHECK (frecuencia_dias IS NULL OR frecuencia_dias > 0),
    CONSTRAINT chk_planes_frecuencia_km     CHECK (frecuencia_km IS NULL OR frecuencia_km > 0),
    CONSTRAINT chk_planes_frecuencia_horas  CHECK (frecuencia_horas IS NULL OR frecuencia_horas > 0),
    CONSTRAINT chk_planes_frecuencia_ciclos CHECK (frecuencia_ciclos IS NULL OR frecuencia_ciclos > 0),
    CONSTRAINT chk_planes_anticipacion      CHECK (anticipacion_dias >= 0)
);

CREATE INDEX idx_planes_mant_activo_id           ON planes_mantenimiento (activo_id);
CREATE INDEX idx_planes_mant_pauta_fabricante_id  ON planes_mantenimiento (pauta_fabricante_id);
CREATE INDEX idx_planes_mant_proxima_ejecucion   ON planes_mantenimiento (proxima_ejecucion_fecha);
CREATE INDEX idx_planes_mant_activo_plan         ON planes_mantenimiento (activo_plan);
CREATE INDEX idx_planes_mant_created_by          ON planes_mantenimiento (created_by);

CREATE TRIGGER trg_planes_mantenimiento_updated_at
    BEFORE UPDATE ON planes_mantenimiento
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 9. BODEGAS — Almacenes por faena
-- ============================================================================

CREATE TABLE bodegas (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id        UUID        NOT NULL REFERENCES faenas(id),
    codigo          VARCHAR(50) UNIQUE NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    tipo            VARCHAR(50) NOT NULL,
    responsable_id  UUID        REFERENCES usuarios_perfil(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_bodegas_tipo
        CHECK (tipo IN ('fija', 'movil', 'virtual'))
);

CREATE INDEX idx_bodegas_faena_id       ON bodegas (faena_id);
CREATE INDEX idx_bodegas_responsable_id ON bodegas (responsable_id);
CREATE INDEX idx_bodegas_tipo           ON bodegas (tipo);

CREATE TRIGGER trg_bodegas_updated_at
    BEFORE UPDATE ON bodegas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 10. PRODUCTOS — Catálogo de productos de inventario
-- ============================================================================

CREATE TABLE productos (
    id                    UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo                VARCHAR(50)       UNIQUE NOT NULL,
    codigo_barras         VARCHAR(100)      UNIQUE,
    nombre                VARCHAR(200)      NOT NULL,
    categoria             VARCHAR(50)       NOT NULL,
    subcategoria          VARCHAR(100),
    unidad_medida         VARCHAR(20)       NOT NULL,
    costo_unitario_actual NUMERIC(15,4)     NOT NULL DEFAULT 0,
    metodo_valorizacion   metodo_valorizacion_enum NOT NULL DEFAULT 'cpp',
    stock_minimo          NUMERIC(12,3)     NOT NULL DEFAULT 0,
    stock_maximo          NUMERIC(12,3),
    tiene_vencimiento     BOOLEAN           NOT NULL DEFAULT false,
    created_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    created_by            UUID              REFERENCES auth.users(id),

    CONSTRAINT chk_productos_categoria
        CHECK (categoria IN ('combustible', 'lubricante', 'filtro', 'repuesto', 'consumible', 'epp')),
    CONSTRAINT chk_productos_costo
        CHECK (costo_unitario_actual >= 0),
    CONSTRAINT chk_productos_stock_minimo
        CHECK (stock_minimo >= 0),
    CONSTRAINT chk_productos_stock_maximo
        CHECK (stock_maximo IS NULL OR stock_maximo >= stock_minimo)
);

CREATE INDEX idx_productos_categoria   ON productos (categoria);
CREATE INDEX idx_productos_subcategoria ON productos (subcategoria);
CREATE INDEX idx_productos_created_by  ON productos (created_by);

CREATE TRIGGER trg_productos_updated_at
    BEFORE UPDATE ON productos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 11. STOCK_BODEGA — Stock por producto y bodega (inventario valorizado)
-- ============================================================================

CREATE TABLE stock_bodega (
    id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    bodega_id          UUID          NOT NULL REFERENCES bodegas(id),
    producto_id        UUID          NOT NULL REFERENCES productos(id),
    cantidad           NUMERIC(12,3) NOT NULL DEFAULT 0,
    costo_promedio     NUMERIC(15,4) NOT NULL DEFAULT 0,
    valor_total        NUMERIC(15,2) GENERATED ALWAYS AS (cantidad * costo_promedio) STORED,
    ultimo_movimiento  TIMESTAMPTZ,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_stock_bodega_producto UNIQUE (bodega_id, producto_id),
    CONSTRAINT chk_stock_cantidad       CHECK (cantidad >= 0),
    CONSTRAINT chk_stock_costo_promedio CHECK (costo_promedio >= 0)
);

CREATE INDEX idx_stock_bodega_bodega_id   ON stock_bodega (bodega_id);
CREATE INDEX idx_stock_bodega_producto_id ON stock_bodega (producto_id);

CREATE TRIGGER trg_stock_bodega_updated_at
    BEFORE UPDATE ON stock_bodega
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- Fin de 02_tablas_core.sql
-- ============================================================================
