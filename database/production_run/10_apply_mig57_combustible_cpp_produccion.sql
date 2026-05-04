-- ============================================================================
-- 10_apply_mig57_combustible_cpp_produccion.sql  —  CPP movil. PRODUCCION.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='salidas_combustible') THEN
        RAISE EXCEPTION 'STOP — mig 55 no aplicada. Ejecutar primero el paso 04.';
    END IF;
END $$;

SELECT fn_log_operacion_migracion('PROD_MIG57_START', 'Iniciando CPP movil combustible', 'pendiente', NULL);


-- 1. Extender combustible_estanques
ALTER TABLE combustible_estanques
    ADD COLUMN IF NOT EXISTS costo_promedio_lt NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (costo_promedio_lt >= 0),
    ADD COLUMN IF NOT EXISTS valor_total_stock NUMERIC(16,2) NOT NULL DEFAULT 0 CHECK (valor_total_stock >= 0);


-- 2. combustible_stock_inicial
CREATE TABLE IF NOT EXISTS combustible_stock_inicial (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estanque_id UUID NOT NULL REFERENCES combustible_estanques(id),
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    litros_iniciales NUMERIC(12,2) NOT NULL CHECK (litros_iniciales > 0),
    costo_unitario_inicial NUMERIC(14,4) NOT NULL CHECK (costo_unitario_inicial >= 0),
    valor_total_inicial NUMERIC(16,2) GENERATED ALWAYS AS (litros_iniciales * costo_unitario_inicial) STORED,
    documento_respaldo_url TEXT,
    registrado_por UUID REFERENCES usuarios_perfil(id),
    observacion TEXT,
    anulado BOOLEAN NOT NULL DEFAULT false,
    anulado_por UUID REFERENCES usuarios_perfil(id),
    anulado_at TIMESTAMPTZ,
    motivo_anulacion TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);
DROP INDEX IF EXISTS uq_stock_inicial_activo;
CREATE UNIQUE INDEX uq_stock_inicial_activo
    ON combustible_stock_inicial (estanque_id) WHERE anulado = false;

ALTER TABLE combustible_stock_inicial ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_csi_select ON combustible_stock_inicial;
CREATE POLICY pol_csi_select ON combustible_stock_inicial FOR SELECT TO authenticated USING (true);


-- 3. combustible_kardex_valorizado
CREATE TABLE IF NOT EXISTS combustible_kardex_valorizado (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estanque_id UUID NOT NULL REFERENCES combustible_estanques(id),
    fecha_movimiento TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tipo_movimiento VARCHAR(30) NOT NULL
        CHECK (tipo_movimiento IN (
            'stock_inicial','ingreso_compra','salida_venta','salida_equipo',
            'salida_despacho','ajuste','varillaje'
        )),
    folio_movimiento VARCHAR(40),
    proveedor_id UUID REFERENCES proveedores(id),
    cliente_id UUID,
    cliente_nombre_manual VARCHAR(200),
    equipo_id UUID REFERENCES activos(id),
    ceco_id UUID REFERENCES centros_costo(id),
    ingreso_combustible_id UUID REFERENCES ingresos_combustible(id),
    salida_combustible_id UUID REFERENCES salidas_combustible(id),
    despacho_combustible_id UUID REFERENCES despachos_combustible(id),
    stock_inicial_id UUID REFERENCES combustible_stock_inicial(id),
    movimiento_combustible_id UUID REFERENCES combustible_movimientos(id),
    varillaje_id UUID REFERENCES combustible_varillaje(id),
    documento_numero VARCHAR(60),
    litros_entrada NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (litros_entrada >= 0),
    litros_salida NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (litros_salida >= 0),
    costo_unitario_movimiento NUMERIC(14,4) NOT NULL CHECK (costo_unitario_movimiento >= 0),
    valor_entrada NUMERIC(16,2) GENERATED ALWAYS AS (litros_entrada * costo_unitario_movimiento) STORED,
    valor_salida NUMERIC(16,2) GENERATED ALWAYS AS (litros_salida * costo_unitario_movimiento) STORED,
    stock_lt_despues NUMERIC(12,2) NOT NULL CHECK (stock_lt_despues >= 0),
    costo_promedio_lt_despues NUMERIC(14,4) NOT NULL CHECK (costo_promedio_lt_despues >= 0),
    valor_stock_despues NUMERIC(16,2) NOT NULL CHECK (valor_stock_despues >= 0),
    evidencia_url TEXT,
    observacion TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_kardex_una_dimension CHECK (
        (litros_entrada > 0 AND litros_salida = 0) OR
        (litros_entrada = 0 AND litros_salida > 0) OR
        (litros_entrada = 0 AND litros_salida = 0 AND tipo_movimiento IN ('varillaje','ajuste'))
    )
);
CREATE INDEX IF NOT EXISTS idx_ckv_estanque_fecha ON combustible_kardex_valorizado (estanque_id, fecha_movimiento DESC);
CREATE INDEX IF NOT EXISTS idx_ckv_tipo ON combustible_kardex_valorizado (tipo_movimiento);

ALTER TABLE combustible_kardex_valorizado ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ckv_select ON combustible_kardex_valorizado;
CREATE POLICY pol_ckv_select ON combustible_kardex_valorizado FOR SELECT TO authenticated USING (true);


-- 4. Extender ingresos/salidas combustible
ALTER TABLE ingresos_combustible
    ADD COLUMN IF NOT EXISTS costo_unitario_lt NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS valor_total_ingreso NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS costo_promedio_anterior NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS costo_promedio_nuevo NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS stock_anterior_lt NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS stock_nuevo_lt NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS valor_stock_anterior NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS valor_stock_nuevo NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS kardex_valorizado_id UUID REFERENCES combustible_kardex_valorizado(id);

ALTER TABLE salidas_combustible
    ADD COLUMN IF NOT EXISTS costo_unitario_aplicado NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS valor_total_salida NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS costo_promedio_al_momento NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS stock_anterior_lt NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS stock_nuevo_lt NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS valor_stock_anterior NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS valor_stock_nuevo NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS kardex_valorizado_id UUID REFERENCES combustible_kardex_valorizado(id);


-- 5. RPC stock inicial
CREATE OR REPLACE FUNCTION rpc_registrar_stock_inicial_combustible(
    p_estanque_id UUID, p_fecha DATE,
    p_litros_iniciales NUMERIC, p_costo_unitario_inicial NUMERIC,
    p_documento_respaldo_url TEXT DEFAULT NULL, p_observacion TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol TEXT := fn_user_rol();
    v_estanque combustible_estanques%ROWTYPE;
    v_activo_existente UUID;
    v_stock_inicial_id UUID;
    v_kardex_id UUID;
    v_valor_total NUMERIC;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;
    IF p_litros_iniciales <= 0 THEN RAISE EXCEPTION 'litros_iniciales debe ser > 0'; END IF;
    IF p_costo_unitario_inicial < 0 THEN RAISE EXCEPTION 'costo debe ser >= 0'; END IF;
    IF p_observacion IS NULL OR LENGTH(TRIM(p_observacion)) < 5 THEN
        RAISE EXCEPTION 'Observacion obligatoria (min 5)';
    END IF;
    SELECT * INTO v_estanque FROM combustible_estanques WHERE id=p_estanque_id FOR UPDATE;
    IF v_estanque.id IS NULL THEN RAISE EXCEPTION 'Estanque % no existe', p_estanque_id; END IF;
    SELECT id INTO v_activo_existente FROM combustible_stock_inicial
     WHERE estanque_id=p_estanque_id AND anulado=false;
    IF v_activo_existente IS NOT NULL THEN
        RAISE EXCEPTION 'Ya existe stock inicial activo (id=%)', v_activo_existente;
    END IF;
    v_valor_total := p_litros_iniciales * p_costo_unitario_inicial;
    v_stock_inicial_id := gen_random_uuid();
    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_stock_inicial (
        id, estanque_id, fecha, litros_iniciales, costo_unitario_inicial,
        documento_respaldo_url, registrado_por, observacion, created_by
    ) VALUES (
        v_stock_inicial_id, p_estanque_id, p_fecha, p_litros_iniciales,
        p_costo_unitario_inicial, p_documento_respaldo_url, v_user, p_observacion, v_user
    );
    UPDATE combustible_estanques
       SET stock_teorico_lt=p_litros_iniciales,
           costo_promedio_lt=p_costo_unitario_inicial,
           valor_total_stock=v_valor_total,
           updated_at=NOW()
     WHERE id=p_estanque_id;
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        stock_inicial_id, litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by
    ) VALUES (
        v_kardex_id, p_estanque_id, p_fecha::TIMESTAMPTZ, 'stock_inicial',
        'INI-' || TO_CHAR(p_fecha, 'YYYYMMDD') || '-' || SUBSTRING(p_estanque_id::TEXT,1,4),
        v_stock_inicial_id, p_litros_iniciales, 0, p_costo_unitario_inicial,
        p_litros_iniciales, p_costo_unitario_inicial, v_valor_total,
        p_documento_respaldo_url, p_observacion, v_user
    );
    RETURN jsonb_build_object(
        'success', true,
        'stock_inicial_id', v_stock_inicial_id,
        'kardex_id', v_kardex_id,
        'litros', p_litros_iniciales,
        'costo_unitario', p_costo_unitario_inicial,
        'valor_total', v_valor_total
    );
END; $$;


-- 6. Vista stock valorizado actual
CREATE OR REPLACE VIEW v_combustible_stock_valorizado_actual AS
SELECT
    e.id AS estanque_id, e.codigo AS estanque_codigo, e.nombre AS estanque_nombre,
    e.capacidad_lt, e.stock_teorico_lt, e.costo_promedio_lt, e.valor_total_stock,
    ROUND(e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0) * 100, 1) AS pct_llenado
FROM combustible_estanques e
WHERE e.activo = true
ORDER BY e.codigo;


-- Verificación
SELECT 'TABLAS_57' AS check_name, COUNT(*) AS encontradas
FROM information_schema.tables WHERE table_schema='public'
AND table_name IN ('combustible_stock_inicial','combustible_kardex_valorizado');

SELECT 'COLUMNAS_ESTANQUES_CPP' AS check_name, COUNT(*) AS encontradas
FROM information_schema.columns WHERE table_name='combustible_estanques'
AND column_name IN ('costo_promedio_lt','valor_total_stock');

SELECT 'RPC_STOCK_INICIAL' AS check_name, COUNT(*) AS encontradas
FROM pg_proc WHERE proname='rpc_registrar_stock_inicial_combustible';


-- Log
SELECT fn_log_operacion_migracion('PROD_MIG57_END', 'Mig 57 CPP movil aplicada.', 'ok',
    'Continuar paso 11 validate. Stock inicial en paso 12 (manual con Finanzas).');


-- ============================================================================
-- ROLLBACK
-- DROP VIEW v_combustible_stock_valorizado_actual;
-- DROP FUNCTION rpc_registrar_stock_inicial_combustible CASCADE;
-- DROP TABLE combustible_kardex_valorizado CASCADE;
-- DROP TABLE combustible_stock_inicial CASCADE;
-- ALTER TABLE combustible_estanques
--   DROP COLUMN costo_promedio_lt, DROP COLUMN valor_total_stock;
-- ============================================================================
