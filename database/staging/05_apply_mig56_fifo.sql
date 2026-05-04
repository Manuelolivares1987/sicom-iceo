-- ============================================================================
-- 05_apply_mig56_fifo.sql  —  FIFO repuestos/materiales (staging).
-- ----------------------------------------------------------------------------
-- DEPENDE DE: 03_apply_mig55_bodega_combustible_base.sql
-- IDEMPOTENTE: usa CREATE TABLE/INDEX IF NOT EXISTS y ALTER TABLE ADD COLUMN IF NOT EXISTS.
-- ============================================================================


-- ── 1. inventario_capas ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS inventario_capas (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id                 UUID NOT NULL REFERENCES productos(id),
    bodega_id                   UUID NOT NULL REFERENCES bodegas(id),
    recepcion_bodega_id         UUID REFERENCES recepciones_bodega(id),
    recepcion_bodega_item_id    UUID REFERENCES recepciones_bodega_items(id),
    orden_compra_id             UUID REFERENCES ordenes_compra(id),
    orden_compra_item_id        UUID REFERENCES ordenes_compra_items(id),
    proveedor_id                UUID REFERENCES proveedores(id),
    fecha_recepcion             DATE NOT NULL,
    folio_recepcion             VARCHAR(30),
    numero_oc                   VARCHAR(40),
    cantidad_inicial            NUMERIC(12,3) NOT NULL CHECK (cantidad_inicial > 0),
    cantidad_disponible         NUMERIC(12,3) NOT NULL CHECK (cantidad_disponible >= 0),
    unidad                      VARCHAR(20) NOT NULL DEFAULT 'unidad',
    costo_unitario              NUMERIC(14,4) NOT NULL CHECK (costo_unitario >= 0),
    costo_total_inicial         NUMERIC(16,2) GENERATED ALWAYS AS
                                    (cantidad_inicial * costo_unitario) STORED,
    costo_total_disponible      NUMERIC(16,2) GENERATED ALWAYS AS
                                    (cantidad_disponible * costo_unitario) STORED,
    lote                        VARCHAR(60),
    vencimiento                 DATE,
    numero_serie                VARCHAR(100),
    estado                      VARCHAR(20) NOT NULL DEFAULT 'disponible'
        CHECK (estado IN ('disponible','agotada','bloqueada','ajustada')),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by                  UUID REFERENCES auth.users(id),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_capa_disp_no_excede CHECK (cantidad_disponible <= cantidad_inicial)
);

CREATE INDEX IF NOT EXISTS idx_capa_fifo_disponibles
    ON inventario_capas (producto_id, bodega_id, fecha_recepcion ASC, created_at ASC, id ASC)
    WHERE estado = 'disponible';
CREATE INDEX IF NOT EXISTS idx_capa_recepcion_item ON inventario_capas (recepcion_bodega_item_id);
CREATE INDEX IF NOT EXISTS idx_capa_oc_item        ON inventario_capas (orden_compra_item_id);
CREATE INDEX IF NOT EXISTS idx_capa_proveedor      ON inventario_capas (proveedor_id);
CREATE INDEX IF NOT EXISTS idx_capa_estado         ON inventario_capas (producto_id, bodega_id, estado);

CREATE TRIGGER trg_capa_updated_at
    BEFORE UPDATE ON inventario_capas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE inventario_capas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_capa_select ON inventario_capas;
CREATE POLICY pol_capa_select ON inventario_capas FOR SELECT TO authenticated USING (true);


-- ── 2. inventario_consumos_capas ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS inventario_consumos_capas (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    salida_bodega_id            UUID REFERENCES salidas_bodega(id),
    salida_bodega_item_id       UUID REFERENCES salidas_bodega_items(id),
    movimiento_inventario_id    UUID REFERENCES movimientos_inventario(id),
    ot_id                       UUID REFERENCES ordenes_trabajo(id),
    ceco_id                     UUID REFERENCES centros_costo(id),
    producto_id                 UUID NOT NULL REFERENCES productos(id),
    bodega_id                   UUID NOT NULL REFERENCES bodegas(id),
    capa_id                     UUID NOT NULL REFERENCES inventario_capas(id),
    cantidad_consumida          NUMERIC(12,3) NOT NULL CHECK (cantidad_consumida > 0),
    costo_unitario_capa         NUMERIC(14,4) NOT NULL CHECK (costo_unitario_capa >= 0),
    costo_total_consumido       NUMERIC(16,2) GENERATED ALWAYS AS
                                    (cantidad_consumida * costo_unitario_capa) STORED,
    fecha_consumo               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    consumido_por               UUID REFERENCES usuarios_perfil(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consumo_salida_item ON inventario_consumos_capas (salida_bodega_item_id);
CREATE INDEX IF NOT EXISTS idx_consumo_capa        ON inventario_consumos_capas (capa_id);
CREATE INDEX IF NOT EXISTS idx_consumo_ot          ON inventario_consumos_capas (ot_id);
CREATE INDEX IF NOT EXISTS idx_consumo_ceco        ON inventario_consumos_capas (ceco_id);
CREATE INDEX IF NOT EXISTS idx_consumo_producto    ON inventario_consumos_capas (producto_id, fecha_consumo DESC);

ALTER TABLE inventario_consumos_capas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_consumo_select ON inventario_consumos_capas;
CREATE POLICY pol_consumo_select ON inventario_consumos_capas FOR SELECT TO authenticated USING (true);


-- ── 3. Extender ot_materiales_planeados ──────────────────────────────

ALTER TABLE ot_materiales_planeados
    ADD COLUMN IF NOT EXISTS costo_unitario_real  NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS costo_total_real     NUMERIC(16,2),
    ADD COLUMN IF NOT EXISTS metodo_costeo        VARCHAR(20) DEFAULT 'fifo'
        CHECK (metodo_costeo IN ('fifo','promedio_ponderado','manual_autorizado')),
    ADD COLUMN IF NOT EXISTS salida_bodega_id     UUID REFERENCES salidas_bodega(id),
    ADD COLUMN IF NOT EXISTS ceco_id              UUID REFERENCES centros_costo(id);

CREATE INDEX IF NOT EXISTS idx_ot_mat_salida_bodega
    ON ot_materiales_planeados (salida_bodega_id) WHERE salida_bodega_id IS NOT NULL;


-- ── 4. fn_consumir_inventario_fifo (CORE) ────────────────────────────

CREATE OR REPLACE FUNCTION fn_consumir_inventario_fifo(
    p_producto_id           UUID,
    p_bodega_id             UUID,
    p_cantidad              NUMERIC,
    p_salida_bodega_id      UUID DEFAULT NULL,
    p_salida_bodega_item_id UUID DEFAULT NULL,
    p_movimiento_id         UUID DEFAULT NULL,
    p_ot_id                 UUID DEFAULT NULL,
    p_ceco_id               UUID DEFAULT NULL,
    p_consumido_por         UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pendiente             NUMERIC := p_cantidad;
    v_total_disponible      NUMERIC;
    v_capa                  RECORD;
    v_consumir              NUMERIC;
    v_costo_total           NUMERIC := 0;
    v_capas_detalle         JSONB := '[]'::JSONB;
    v_user                  UUID := COALESCE(p_consumido_por, auth.uid());
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Cantidad a consumir debe ser > 0 (recibido: %)', p_cantidad
            USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(SUM(cantidad_disponible), 0) INTO v_total_disponible
      FROM inventario_capas
     WHERE producto_id = p_producto_id
       AND bodega_id = p_bodega_id
       AND estado = 'disponible';

    IF v_total_disponible < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para producto % en bodega %. Disponible: %, solicitado: %',
            p_producto_id, p_bodega_id, v_total_disponible, p_cantidad
            USING ERRCODE = 'P0001';
    END IF;

    FOR v_capa IN
        SELECT id, cantidad_disponible, costo_unitario, fecha_recepcion, folio_recepcion
          FROM inventario_capas
         WHERE producto_id = p_producto_id
           AND bodega_id = p_bodega_id
           AND estado = 'disponible'
           AND cantidad_disponible > 0
         ORDER BY fecha_recepcion ASC, created_at ASC, id ASC
         FOR UPDATE
    LOOP
        EXIT WHEN v_pendiente <= 0;
        v_consumir := LEAST(v_pendiente, v_capa.cantidad_disponible);

        INSERT INTO inventario_consumos_capas (
            salida_bodega_id, salida_bodega_item_id, movimiento_inventario_id,
            ot_id, ceco_id, producto_id, bodega_id, capa_id,
            cantidad_consumida, costo_unitario_capa, consumido_por
        ) VALUES (
            p_salida_bodega_id, p_salida_bodega_item_id, p_movimiento_id,
            p_ot_id, p_ceco_id, p_producto_id, p_bodega_id, v_capa.id,
            v_consumir, v_capa.costo_unitario, v_user
        );

        UPDATE inventario_capas
           SET cantidad_disponible = cantidad_disponible - v_consumir,
               estado = CASE
                   WHEN cantidad_disponible - v_consumir <= 0 THEN 'agotada'
                   ELSE 'disponible'
               END,
               updated_at = NOW()
         WHERE id = v_capa.id;

        v_costo_total := v_costo_total + (v_consumir * v_capa.costo_unitario);
        v_pendiente   := v_pendiente   - v_consumir;

        v_capas_detalle := v_capas_detalle || jsonb_build_object(
            'capa_id',         v_capa.id,
            'fecha_recepcion', v_capa.fecha_recepcion,
            'folio_recepcion', v_capa.folio_recepcion,
            'cantidad',        v_consumir,
            'costo_unitario',  v_capa.costo_unitario,
            'costo_total',     v_consumir * v_capa.costo_unitario
        );
    END LOOP;

    IF v_pendiente > 0 THEN
        RAISE EXCEPTION 'Inconsistencia FIFO: quedan % unidades sin consumir.', v_pendiente
            USING ERRCODE = 'P0001';
    END IF;

    RETURN jsonb_build_object(
        'cantidad_consumida',         p_cantidad,
        'costo_total',                v_costo_total,
        'costo_unitario_promedio',    ROUND(v_costo_total / p_cantidad, 4),
        'capas_consumidas',           v_capas_detalle,
        'metodo',                     'fifo'
    );
END;
$$;


-- ── 5. Vistas para Finanzas (FIFO) ───────────────────────────────────

CREATE OR REPLACE VIEW v_stock_valorizado_fifo AS
SELECT
    p.id                    AS producto_id,
    p.codigo                AS producto_codigo,
    p.nombre                AS producto_nombre,
    b.id                    AS bodega_id,
    b.codigo                AS bodega_codigo,
    SUM(ic.cantidad_disponible)                       AS cantidad_total_disponible,
    SUM(ic.cantidad_disponible * ic.costo_unitario)   AS valor_total_fifo,
    ROUND(
        SUM(ic.cantidad_disponible * ic.costo_unitario) /
        NULLIF(SUM(ic.cantidad_disponible), 0)
    , 4) AS costo_promedio_informativo,
    COUNT(*) FILTER (WHERE ic.cantidad_disponible > 0) AS capas_activas,
    MIN(ic.fecha_recepcion) FILTER (WHERE ic.cantidad_disponible > 0) AS capa_mas_antigua,
    MAX(ic.fecha_recepcion) FILTER (WHERE ic.cantidad_disponible > 0) AS capa_mas_nueva
FROM inventario_capas ic
JOIN productos p ON p.id = ic.producto_id
JOIN bodegas   b ON b.id = ic.bodega_id
WHERE ic.estado = 'disponible'
GROUP BY p.id, p.codigo, p.nombre, b.id, b.codigo;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

SELECT 'TABLAS_FIFO' AS check_name,
       array_agg(table_name ORDER BY table_name) AS encontradas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('inventario_capas','inventario_consumos_capas');
-- Esperado: 2

SELECT 'COLUMNAS_OT_MAT_FIFO' AS check_name,
       array_agg(column_name ORDER BY column_name) AS encontradas
FROM information_schema.columns
WHERE table_name = 'ot_materiales_planeados'
  AND column_name IN ('costo_unitario_real','costo_total_real','metodo_costeo','salida_bodega_id','ceco_id');
-- Esperado: 5

SELECT 'FN_FIFO' AS check_name,
       COUNT(*) AS encontradas
FROM pg_proc WHERE proname = 'fn_consumir_inventario_fifo';
-- Esperado: 1

SELECT 'VISTA_STOCK_FIFO' AS check_name, COUNT(*) AS existe
FROM pg_views WHERE viewname = 'v_stock_valorizado_fifo';
-- Esperado: 1


-- ============================================================================
-- ROLLBACK MANUAL
-- ----------------------------------------------------------------------------
-- DROP VIEW IF EXISTS v_stock_valorizado_fifo;
-- DROP FUNCTION IF EXISTS fn_consumir_inventario_fifo CASCADE;
-- DROP TABLE IF EXISTS inventario_consumos_capas CASCADE;
-- DROP TABLE IF EXISTS inventario_capas CASCADE;
-- ALTER TABLE ot_materiales_planeados
--   DROP COLUMN IF EXISTS costo_unitario_real,
--   DROP COLUMN IF EXISTS costo_total_real,
--   DROP COLUMN IF EXISTS metodo_costeo,
--   DROP COLUMN IF EXISTS salida_bodega_id,
--   DROP COLUMN IF EXISTS ceco_id;
-- ============================================================================
