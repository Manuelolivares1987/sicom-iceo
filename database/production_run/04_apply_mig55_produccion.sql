-- ============================================================================
-- 04_apply_mig55_produccion.sql  —  PRODUCCION. Mig 55 base.
-- ----------------------------------------------------------------------------
-- Crea: enums, proveedores, centros_costo, OC, recepciones, salidas bodega,
-- ingresos/salidas/despachos combustible, sequences y funciones de folio.
-- IDEMPOTENTE.
--
-- Antes de ejecutar:
--   - Backup confirmado (paso 01).
--   - Prechecks OK (paso 02).
--   - Bitacora creada (paso 03).
-- ============================================================================


-- ── Registrar inicio del paso ────────────────────────────────────────
SELECT fn_log_operacion_migracion(
    'PROD_MIG55_START',
    'Iniciando aplicacion mig 55 (proveedores, CECO, OC, recepciones, salidas, combustible base, despachos)',
    'pendiente',
    NULL
);


-- ── 1. ENUMS ─────────────────────────────────────────────────────────

DO $$ BEGIN CREATE TYPE estado_oc_enum AS ENUM ('abierta','parcial','cerrada','anulada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE estado_oc_item_enum AS ENUM ('pendiente','parcial','completo');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE tipo_salida_bodega_enum AS ENUM ('ot','persona','ceco','venta','ajuste_autorizado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE tipo_proveedor_enum AS ENUM ('combustible','repuestos','servicios','lubricantes','filtros','otros');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE tipo_documento_proveedor_enum AS ENUM ('guia','factura','vale','boleta','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE tipo_salida_combustible_enum AS ENUM ('venta_externa','carga_equipo_propio','despacho_cliente','ajuste');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE estado_despacho_combustible_enum AS ENUM ('programado','en_ruta','entregado','observado','anulado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── 2. PROVEEDORES + CENTROS DE COSTO ────────────────────────────────

CREATE TABLE IF NOT EXISTS proveedores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo VARCHAR(30) UNIQUE NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    rut VARCHAR(20),
    tipo tipo_proveedor_enum NOT NULL DEFAULT 'otros',
    contacto VARCHAR(200),
    telefono VARCHAR(30),
    email VARCHAR(200),
    activo BOOLEAN NOT NULL DEFAULT true,
    observaciones TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_proveedores_tipo ON proveedores (tipo) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_proveedores_activo ON proveedores (activo);
ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_proveedores_select ON proveedores;
CREATE POLICY pol_proveedores_select ON proveedores FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS centros_costo (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo VARCHAR(30) UNIQUE NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    area VARCHAR(100),
    contrato_id UUID REFERENCES contratos(id),
    faena_id UUID REFERENCES faenas(id),
    activo BOOLEAN NOT NULL DEFAULT true,
    observaciones TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ceco_activo ON centros_costo (activo);
CREATE INDEX IF NOT EXISTS idx_ceco_faena  ON centros_costo (faena_id);
ALTER TABLE centros_costo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ceco_select ON centros_costo;
CREATE POLICY pol_ceco_select ON centros_costo FOR SELECT TO authenticated USING (true);


-- ── 3. ÓRDENES DE COMPRA ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ordenes_compra (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_oc VARCHAR(40) UNIQUE NOT NULL,
    proveedor_id UUID NOT NULL REFERENCES proveedores(id),
    fecha_oc DATE NOT NULL DEFAULT CURRENT_DATE,
    estado estado_oc_enum NOT NULL DEFAULT 'abierta',
    monto_total_clp NUMERIC(14,0) NOT NULL DEFAULT 0,
    observacion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_oc_proveedor ON ordenes_compra (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_oc_estado ON ordenes_compra (estado);
CREATE INDEX IF NOT EXISTS idx_oc_fecha ON ordenes_compra (fecha_oc DESC);

CREATE TABLE IF NOT EXISTS ordenes_compra_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    orden_compra_id UUID NOT NULL REFERENCES ordenes_compra(id) ON DELETE CASCADE,
    producto_id UUID REFERENCES productos(id),
    descripcion VARCHAR(500) NOT NULL,
    unidad VARCHAR(20) NOT NULL DEFAULT 'unidad',
    cantidad_comprada NUMERIC(12,2) NOT NULL CHECK (cantidad_comprada > 0),
    cantidad_recibida NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (cantidad_recibida >= 0),
    cantidad_pendiente NUMERIC(12,2) GENERATED ALWAYS AS (cantidad_comprada - cantidad_recibida) STORED,
    precio_unitario_clp NUMERIC(12,2) NOT NULL DEFAULT 0,
    estado estado_oc_item_enum NOT NULL DEFAULT 'pendiente',
    observacion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_oc_item_recibida_no_excede CHECK (cantidad_recibida <= cantidad_comprada)
);
CREATE INDEX IF NOT EXISTS idx_oc_items_oc ON ordenes_compra_items (orden_compra_id);
CREATE INDEX IF NOT EXISTS idx_oc_items_producto ON ordenes_compra_items (producto_id);
CREATE INDEX IF NOT EXISTS idx_oc_items_estado ON ordenes_compra_items (estado);

ALTER TABLE ordenes_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordenes_compra_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_oc_select ON ordenes_compra;
DROP POLICY IF EXISTS pol_oci_select ON ordenes_compra_items;
CREATE POLICY pol_oc_select ON ordenes_compra FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_oci_select ON ordenes_compra_items FOR SELECT TO authenticated USING (true);


-- ── 4. RECEPCIONES ───────────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS seq_folio_recepcion_bodega START 1;

CREATE TABLE IF NOT EXISTS recepciones_bodega (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_recepcion VARCHAR(30) UNIQUE NOT NULL,
    orden_compra_id UUID REFERENCES ordenes_compra(id),
    proveedor_id UUID NOT NULL REFERENCES proveedores(id),
    bodega_id UUID NOT NULL REFERENCES bodegas(id),
    fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    documento_proveedor_tipo tipo_documento_proveedor_enum NOT NULL,
    documento_proveedor_numero VARCHAR(60) NOT NULL,
    recibido_por UUID REFERENCES usuarios_perfil(id),
    observacion TEXT,
    evidencia_url TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'registrada' CHECK (estado IN ('registrada','anulada')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT uq_recepcion_doc_proveedor
        UNIQUE (proveedor_id, documento_proveedor_tipo, documento_proveedor_numero)
);
CREATE INDEX IF NOT EXISTS idx_recb_oc ON recepciones_bodega (orden_compra_id);
CREATE INDEX IF NOT EXISTS idx_recb_proveedor ON recepciones_bodega (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_recb_fecha ON recepciones_bodega (fecha_recepcion DESC);

CREATE TABLE IF NOT EXISTS recepciones_bodega_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recepcion_id UUID NOT NULL REFERENCES recepciones_bodega(id) ON DELETE CASCADE,
    orden_compra_item_id UUID REFERENCES ordenes_compra_items(id),
    producto_id UUID NOT NULL REFERENCES productos(id),
    cantidad_recibida NUMERIC(12,2) NOT NULL CHECK (cantidad_recibida > 0),
    unidad VARCHAR(20) NOT NULL DEFAULT 'unidad',
    costo_unitario_clp NUMERIC(12,2) NOT NULL DEFAULT 0,
    lote VARCHAR(60),
    fecha_vencimiento DATE,
    observacion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rbi_recepcion ON recepciones_bodega_items (recepcion_id);
CREATE INDEX IF NOT EXISTS idx_rbi_producto ON recepciones_bodega_items (producto_id);

ALTER TABLE recepciones_bodega ENABLE ROW LEVEL SECURITY;
ALTER TABLE recepciones_bodega_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_recb_select ON recepciones_bodega;
DROP POLICY IF EXISTS pol_rbi_select ON recepciones_bodega_items;
CREATE POLICY pol_recb_select ON recepciones_bodega FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_rbi_select ON recepciones_bodega_items FOR SELECT TO authenticated USING (true);


-- ── 5. SALIDAS DE BODEGA ─────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS seq_folio_salida_bodega START 1;

CREATE TABLE IF NOT EXISTS salidas_bodega (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_salida VARCHAR(30) UNIQUE NOT NULL,
    tipo_salida tipo_salida_bodega_enum NOT NULL,
    ot_id UUID REFERENCES ordenes_trabajo(id),
    ceco_id UUID NOT NULL REFERENCES centros_costo(id),
    bodega_id UUID NOT NULL REFERENCES bodegas(id),
    solicitado_por UUID REFERENCES usuarios_perfil(id),
    entregado_a VARCHAR(200),
    entregado_a_perfil_id UUID REFERENCES usuarios_perfil(id),
    autorizado_por UUID REFERENCES usuarios_perfil(id),
    fecha_salida TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    motivo TEXT NOT NULL,
    observacion TEXT,
    evidencia_url TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'registrada' CHECK (estado IN ('registrada','anulada')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT chk_salb_ot_obligatoria CHECK (tipo_salida != 'ot' OR ot_id IS NOT NULL),
    CONSTRAINT chk_salb_persona CHECK (tipo_salida != 'persona'
        OR (entregado_a IS NOT NULL OR entregado_a_perfil_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_salb_ot ON salidas_bodega (ot_id);
CREATE INDEX IF NOT EXISTS idx_salb_ceco ON salidas_bodega (ceco_id);
CREATE INDEX IF NOT EXISTS idx_salb_bodega ON salidas_bodega (bodega_id);

CREATE TABLE IF NOT EXISTS salidas_bodega_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    salida_id UUID NOT NULL REFERENCES salidas_bodega(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES productos(id),
    cantidad NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    unidad VARCHAR(20) NOT NULL DEFAULT 'unidad',
    costo_unitario_clp NUMERIC(12,2) NOT NULL DEFAULT 0,
    costo_total_clp NUMERIC(14,2) GENERATED ALWAYS AS (cantidad * costo_unitario_clp) STORED,
    observacion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sbi_salida ON salidas_bodega_items (salida_id);
CREATE INDEX IF NOT EXISTS idx_sbi_producto ON salidas_bodega_items (producto_id);

ALTER TABLE salidas_bodega ENABLE ROW LEVEL SECURITY;
ALTER TABLE salidas_bodega_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_salb_select ON salidas_bodega;
DROP POLICY IF EXISTS pol_sbi_select ON salidas_bodega_items;
CREATE POLICY pol_salb_select ON salidas_bodega FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_sbi_select ON salidas_bodega_items FOR SELECT TO authenticated USING (true);


-- ── 6. INGRESOS / SALIDAS / DESPACHOS DE COMBUSTIBLE ─────────────────

CREATE SEQUENCE IF NOT EXISTS seq_folio_ingreso_combustible START 1;
CREATE SEQUENCE IF NOT EXISTS seq_folio_salida_combustible START 1;
CREATE SEQUENCE IF NOT EXISTS seq_folio_despacho_combustible START 1;

CREATE TABLE IF NOT EXISTS ingresos_combustible (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_ingreso VARCHAR(30) UNIQUE NOT NULL,
    proveedor_id UUID NOT NULL REFERENCES proveedores(id),
    proveedor_nombre_snapshot VARCHAR(200) NOT NULL,
    orden_compra_id UUID REFERENCES ordenes_compra(id),
    numero_guia VARCHAR(60) NOT NULL,
    numero_pedido VARCHAR(60),
    fecha_documento DATE NOT NULL,
    fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    estanque_id UUID NOT NULL REFERENCES combustible_estanques(id),
    producto_combustible VARCHAR(40) NOT NULL DEFAULT 'diesel',
    volumen_carga_litros NUMERIC(12,2),
    meter_inicial NUMERIC(12,2),
    meter_final NUMERIC(12,2),
    litros_entregados NUMERIC(12,2) NOT NULL CHECK (litros_entregados > 0),
    conductor_nombre VARCHAR(200),
    camion_patente VARCHAR(20),
    cliente_nombre_documento VARCHAR(200),
    recibido_por UUID REFERENCES usuarios_perfil(id),
    evidencia_guia_url TEXT,
    firma_conductor_url TEXT,
    firma_receptor_url TEXT,
    observacion TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'registrado' CHECK (estado IN ('registrado','anulado')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT uq_ingreso_combustible_guia UNIQUE (proveedor_id, numero_guia)
);
CREATE INDEX IF NOT EXISTS idx_ic_proveedor ON ingresos_combustible (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_ic_estanque ON ingresos_combustible (estanque_id);
CREATE INDEX IF NOT EXISTS idx_ic_fecha ON ingresos_combustible (fecha_recepcion DESC);

CREATE TABLE IF NOT EXISTS salidas_combustible (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_salida VARCHAR(30) UNIQUE NOT NULL,
    tipo_salida tipo_salida_combustible_enum NOT NULL,
    fecha_salida TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    estanque_origen_id UUID NOT NULL REFERENCES combustible_estanques(id),
    producto_combustible VARCHAR(40) NOT NULL DEFAULT 'diesel',
    litros NUMERIC(12,2) NOT NULL CHECK (litros > 0),
    ceco_id UUID NOT NULL REFERENCES centros_costo(id),
    equipo_activo_id UUID REFERENCES activos(id),
    unidad_equipo_descripcion VARCHAR(200),
    cliente_id UUID,
    cliente_nombre_manual VARCHAR(200),
    conductor_id UUID REFERENCES usuarios_perfil(id),
    conductor_nombre_manual VARCHAR(200),
    kilometraje NUMERIC(12,1),
    horometro NUMERIC(12,1),
    motivo TEXT NOT NULL,
    pedido_por VARCHAR(200),
    autorizado_por UUID REFERENCES usuarios_perfil(id),
    retira_nombre VARCHAR(200),
    observacion TEXT,
    evidencia_vale_url TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'registrada' CHECK (estado IN ('registrada','anulada')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_sc_estanque ON salidas_combustible (estanque_origen_id);
CREATE INDEX IF NOT EXISTS idx_sc_ceco ON salidas_combustible (ceco_id);
CREATE INDEX IF NOT EXISTS idx_sc_tipo ON salidas_combustible (tipo_salida);

CREATE TABLE IF NOT EXISTS despachos_combustible (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_despacho VARCHAR(30) UNIQUE NOT NULL,
    salida_combustible_id UUID NOT NULL REFERENCES salidas_combustible(id),
    camion_activo_id UUID NOT NULL REFERENCES activos(id),
    conductor_id UUID NOT NULL REFERENCES usuarios_perfil(id),
    destino_cliente VARCHAR(200),
    destino_faena_id UUID REFERENCES faenas(id),
    fecha_salida TIMESTAMPTZ,
    fecha_entrega TIMESTAMPTZ,
    sello_1_numero VARCHAR(40),
    sello_2_numero VARCHAR(40),
    sello_3_numero VARCHAR(40),
    foto_sello_1_salida_url TEXT,
    foto_sello_2_salida_url TEXT,
    foto_sello_3_salida_url TEXT,
    foto_sello_1_entrega_url TEXT,
    foto_sello_2_entrega_url TEXT,
    foto_sello_3_entrega_url TEXT,
    sellos_intactos BOOLEAN,
    receptor_nombre VARCHAR(200),
    receptor_rut VARCHAR(20),
    firma_receptor_url TEXT,
    litros_cargados NUMERIC(12,2),
    litros_entregados NUMERIC(12,2),
    diferencia_litros NUMERIC(12,2) GENERATED ALWAYS AS
        (COALESCE(litros_entregados, 0) - COALESCE(litros_cargados, 0)) STORED,
    observacion_entrega TEXT,
    no_conformidad_id UUID REFERENCES no_conformidades(id),
    estado estado_despacho_combustible_enum NOT NULL DEFAULT 'programado',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    CONSTRAINT chk_despacho_sellos_salida CHECK (
        estado = 'programado'
        OR (sello_1_numero IS NOT NULL AND sello_2_numero IS NOT NULL AND sello_3_numero IS NOT NULL
            AND foto_sello_1_salida_url IS NOT NULL AND foto_sello_2_salida_url IS NOT NULL
            AND foto_sello_3_salida_url IS NOT NULL)
    ),
    CONSTRAINT chk_despacho_sellos_entrega CHECK (
        estado NOT IN ('entregado','observado')
        OR (foto_sello_1_entrega_url IS NOT NULL
            AND foto_sello_2_entrega_url IS NOT NULL
            AND foto_sello_3_entrega_url IS NOT NULL)
    )
);

ALTER TABLE ingresos_combustible ENABLE ROW LEVEL SECURITY;
ALTER TABLE salidas_combustible  ENABLE ROW LEVEL SECURITY;
ALTER TABLE despachos_combustible ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ic_select ON ingresos_combustible;
DROP POLICY IF EXISTS pol_sc_select ON salidas_combustible;
DROP POLICY IF EXISTS pol_dc_select ON despachos_combustible;
CREATE POLICY pol_ic_select ON ingresos_combustible FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_sc_select ON salidas_combustible FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_dc_select ON despachos_combustible FOR SELECT TO authenticated USING (true);


-- ── 7. FUNCIONES DE FOLIO ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_generar_folio_recepcion_bodega()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER; BEGIN v_seq := nextval('seq_folio_recepcion_bodega');
    RETURN 'REC-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 5, '0'); END; $$;

CREATE OR REPLACE FUNCTION fn_generar_folio_salida_bodega()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER; BEGIN v_seq := nextval('seq_folio_salida_bodega');
    RETURN 'SAL-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 5, '0'); END; $$;

CREATE OR REPLACE FUNCTION fn_generar_folio_ingreso_combustible()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER; BEGIN v_seq := nextval('seq_folio_ingreso_combustible');
    RETURN 'ICB-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 5, '0'); END; $$;

CREATE OR REPLACE FUNCTION fn_generar_folio_salida_combustible()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER; BEGIN v_seq := nextval('seq_folio_salida_combustible');
    RETURN 'SCB-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 5, '0'); END; $$;

CREATE OR REPLACE FUNCTION fn_generar_folio_despacho_combustible()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER; BEGIN v_seq := nextval('seq_folio_despacho_combustible');
    RETURN 'DCB-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 5, '0'); END; $$;


-- ── 8. VALIDACION RAPIDA FINAL ──────────────────────────────────────

SELECT
    'TABLAS_CREADAS' AS check_name,
    COUNT(*) AS encontradas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'proveedores','centros_costo','ordenes_compra','ordenes_compra_items',
    'recepciones_bodega','recepciones_bodega_items',
    'salidas_bodega','salidas_bodega_items',
    'ingresos_combustible','salidas_combustible','despachos_combustible'
  );
-- Esperado: 11

SELECT 'FUNCIONES_FOLIO' AS check_name, COUNT(*) AS encontradas
FROM pg_proc WHERE proname LIKE 'fn_generar_folio_%';
-- Esperado: 5


-- ── 9. Registrar fin del paso ────────────────────────────────────────
SELECT fn_log_operacion_migracion(
    'PROD_MIG55_END',
    'Mig 55 aplicada: 11 tablas, 5 funciones folio.',
    'ok',
    'Verificar siguiente paso: 05_validate_mig55_produccion.sql'
);


-- ============================================================================
-- ROLLBACK MANUAL (si es necesario)
-- ----------------------------------------------------------------------------
-- DROP TABLE despachos_combustible CASCADE;
-- DROP TABLE salidas_combustible CASCADE;
-- DROP TABLE ingresos_combustible CASCADE;
-- DROP TABLE salidas_bodega_items CASCADE;
-- DROP TABLE salidas_bodega CASCADE;
-- DROP TABLE recepciones_bodega_items CASCADE;
-- DROP TABLE recepciones_bodega CASCADE;
-- DROP TABLE ordenes_compra_items CASCADE;
-- DROP TABLE ordenes_compra CASCADE;
-- DROP TABLE centros_costo CASCADE;
-- DROP TABLE proveedores CASCADE;
-- DROP FUNCTION fn_generar_folio_recepcion_bodega();
-- DROP FUNCTION fn_generar_folio_salida_bodega();
-- DROP FUNCTION fn_generar_folio_ingreso_combustible();
-- DROP FUNCTION fn_generar_folio_salida_combustible();
-- DROP FUNCTION fn_generar_folio_despacho_combustible();
-- DROP SEQUENCE seq_folio_recepcion_bodega;
-- DROP SEQUENCE seq_folio_salida_bodega;
-- DROP SEQUENCE seq_folio_ingreso_combustible;
-- DROP SEQUENCE seq_folio_salida_combustible;
-- DROP SEQUENCE seq_folio_despacho_combustible;
-- ============================================================================
