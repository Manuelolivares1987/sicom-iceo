-- ============================================================================
-- SICOM-ICEO | Migracion 48 — OT ↔ Bodega: materiales planeados y faltantes
-- ============================================================================
-- Flujo:
--  1. Planificador o tecnico agrega materiales requeridos a una OT
--     (producto + cantidad + comentario).
--  2. Trigger evalua stock en la bodega mas cercana a la faena de la OT
--     y marca el estado automaticamente: 'suficiente' | 'faltante'.
--  3. Bodeguero entrega: llama fn_despachar_material_ot que genera
--     movimiento_inventario (salida) y marca 'despachado'.
--  4. Vista v_materiales_pendientes_despacho lista lo que espera
--     el bodeguero por entregar.
-- ============================================================================

-- ============================================================================
-- 1. ENUM de estado de material
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE estado_material_ot_enum AS ENUM (
        'faltante',     -- Stock insuficiente
        'suficiente',   -- Stock disponible, pendiente de despacho
        'despachado',   -- Entregado al tecnico (movimiento_inventario creado)
        'cancelado'     -- El item se cancelo (p.ej. no se usara)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================================
-- 2. TABLA ot_materiales_planeados
-- ============================================================================

CREATE TABLE IF NOT EXISTS ot_materiales_planeados (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id              UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    producto_id        UUID NOT NULL REFERENCES productos(id),
    cantidad_plan      NUMERIC(12,3) NOT NULL CHECK (cantidad_plan > 0),
    cantidad_entregada NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (cantidad_entregada >= 0),
    estado             estado_material_ot_enum NOT NULL DEFAULT 'suficiente',
    bodega_id          UUID REFERENCES bodegas(id),   -- bodega origen esperada
    movimiento_id      UUID REFERENCES movimientos_inventario(id), -- set al despachar
    comentario         TEXT,
    planificado_por    UUID REFERENCES usuarios_perfil(id),
    despachado_por     UUID REFERENCES usuarios_perfil(id),
    despachado_en      TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ot_mat_ot      ON ot_materiales_planeados (ot_id);
CREATE INDEX IF NOT EXISTS idx_ot_mat_prod    ON ot_materiales_planeados (producto_id);
CREATE INDEX IF NOT EXISTS idx_ot_mat_bodega  ON ot_materiales_planeados (bodega_id);
CREATE INDEX IF NOT EXISTS idx_ot_mat_estado  ON ot_materiales_planeados (estado)
    WHERE estado IN ('faltante','suficiente');

CREATE TRIGGER trg_ot_mat_updated_at
    BEFORE UPDATE ON ot_materiales_planeados
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 3. TRIGGER — recalcular estado segun stock disponible
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_recalcular_estado_material_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock   NUMERIC;
    v_bodega  UUID;
BEGIN
    -- Si ya esta despachado o cancelado, no recalcular
    IF NEW.estado IN ('despachado','cancelado') THEN
        RETURN NEW;
    END IF;

    -- Resolver bodega: la declarada, o la primera bodega que tenga stock,
    -- o la primera bodega del sistema si no hay stock en ninguna.
    IF NEW.bodega_id IS NOT NULL THEN
        v_bodega := NEW.bodega_id;
    ELSE
        SELECT sb.bodega_id
          INTO v_bodega
          FROM stock_bodega sb
         WHERE sb.producto_id = NEW.producto_id
           AND sb.cantidad >= NEW.cantidad_plan
         ORDER BY sb.cantidad DESC
         LIMIT 1;

        IF v_bodega IS NULL THEN
            SELECT id INTO v_bodega FROM bodegas ORDER BY created_at LIMIT 1;
        END IF;
        NEW.bodega_id := v_bodega;
    END IF;

    -- Stock en la bodega elegida
    SELECT COALESCE(cantidad, 0) INTO v_stock
      FROM stock_bodega
     WHERE bodega_id = v_bodega
       AND producto_id = NEW.producto_id;

    v_stock := COALESCE(v_stock, 0);

    IF v_stock >= NEW.cantidad_plan THEN
        NEW.estado := 'suficiente';
    ELSE
        NEW.estado := 'faltante';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ot_mat_estado ON ot_materiales_planeados;
CREATE TRIGGER trg_ot_mat_estado
    BEFORE INSERT OR UPDATE OF cantidad_plan, producto_id, bodega_id
    ON ot_materiales_planeados
    FOR EACH ROW EXECUTE FUNCTION fn_recalcular_estado_material_ot();


-- ============================================================================
-- 4. RPC — agregar material a una OT
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_agregar_material_ot(
    p_ot_id        UUID,
    p_producto_id  UUID,
    p_cantidad     NUMERIC,
    p_comentario   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id  UUID;
    v_mat_id   UUID;
    v_mat      RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- Verificar que la OT existe y no esta cerrada
    IF NOT EXISTS (
        SELECT 1 FROM ordenes_trabajo
         WHERE id = p_ot_id
           AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                              'no_ejecutada','cancelada','cerrada')
    ) THEN
        RAISE EXCEPTION 'OT no existe o esta cerrada.';
    END IF;

    INSERT INTO ot_materiales_planeados (
        ot_id, producto_id, cantidad_plan, comentario, planificado_por
    ) VALUES (
        p_ot_id, p_producto_id, p_cantidad, p_comentario, v_user_id
    )
    RETURNING id INTO v_mat_id;

    SELECT * INTO v_mat FROM ot_materiales_planeados WHERE id = v_mat_id;

    RETURN jsonb_build_object(
        'success',        true,
        'material_id',    v_mat_id,
        'estado',         v_mat.estado,
        'bodega_id',      v_mat.bodega_id
    );
END;
$$;


-- ============================================================================
-- 5. RPC — despachar material (bodeguero)
-- ============================================================================
-- Descuenta stock, crea movimiento_inventario tipo 'salida_consumo' y
-- marca el registro como 'despachado'.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_despachar_material_ot(
    p_material_id    UUID,
    p_cantidad       NUMERIC DEFAULT NULL  -- NULL = cantidad_plan completa
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id    UUID;
    v_mat        RECORD;
    v_cant_real  NUMERIC;
    v_stock_row  RECORD;
    v_mov_id     UUID;
    v_ot         RECORD;
    v_producto   RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_mat
      FROM ot_materiales_planeados
     WHERE id = p_material_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Material planeado % no existe.', p_material_id;
    END IF;

    IF v_mat.estado = 'despachado' THEN
        RAISE EXCEPTION 'Este material ya fue despachado.';
    END IF;

    IF v_mat.estado = 'cancelado' THEN
        RAISE EXCEPTION 'Material cancelado, no se puede despachar.';
    END IF;

    v_cant_real := COALESCE(p_cantidad, v_mat.cantidad_plan);

    IF v_cant_real <= 0 THEN
        RAISE EXCEPTION 'Cantidad debe ser mayor a cero.';
    END IF;

    -- Verificar stock
    SELECT * INTO v_stock_row
      FROM stock_bodega
     WHERE bodega_id = v_mat.bodega_id
       AND producto_id = v_mat.producto_id;

    IF NOT FOUND OR v_stock_row.cantidad < v_cant_real THEN
        RAISE EXCEPTION 'Stock insuficiente en bodega (disponible: %, requerido: %).',
            COALESCE(v_stock_row.cantidad, 0), v_cant_real;
    END IF;

    SELECT * INTO v_ot       FROM ordenes_trabajo WHERE id = v_mat.ot_id;
    SELECT * INTO v_producto FROM productos       WHERE id = v_mat.producto_id;

    -- Crear movimiento de inventario tipo salida
    INSERT INTO movimientos_inventario (
        bodega_id, producto_id, activo_id, ot_id,
        tipo_movimiento, cantidad, costo_unitario, costo_total,
        observacion, created_by
    ) VALUES (
        v_mat.bodega_id, v_mat.producto_id, v_ot.activo_id, v_mat.ot_id,
        'salida_consumo', v_cant_real,
        COALESCE(v_stock_row.costo_promedio, 0),
        v_cant_real * COALESCE(v_stock_row.costo_promedio, 0),
        'Despacho a OT ' || COALESCE(v_ot.folio, v_ot.id::text),
        v_user_id
    )
    RETURNING id INTO v_mov_id;

    -- Actualizar stock
    UPDATE stock_bodega
       SET cantidad = cantidad - v_cant_real,
           ultimo_movimiento = NOW()
     WHERE bodega_id = v_mat.bodega_id
       AND producto_id = v_mat.producto_id;

    -- Marcar material como despachado
    UPDATE ot_materiales_planeados
       SET estado             = 'despachado',
           cantidad_entregada = v_cant_real,
           movimiento_id      = v_mov_id,
           despachado_por     = v_user_id,
           despachado_en      = NOW(),
           updated_at         = NOW()
     WHERE id = p_material_id;

    RETURN jsonb_build_object(
        'success',        true,
        'material_id',    p_material_id,
        'movimiento_id',  v_mov_id,
        'cantidad',       v_cant_real
    );
END;
$$;


-- ============================================================================
-- 6. VISTA — materiales pendientes de despacho (para bodeguero)
-- ============================================================================

CREATE OR REPLACE VIEW v_materiales_pendientes_despacho AS
SELECT
    m.id                   AS material_id,
    m.estado,
    m.cantidad_plan,
    m.cantidad_entregada,
    m.bodega_id,
    b.nombre               AS bodega,
    m.producto_id,
    p.codigo               AS producto_codigo,
    p.nombre               AS producto_nombre,
    p.unidad_medida,
    -- Stock actual en la bodega asignada
    (SELECT cantidad FROM stock_bodega
       WHERE bodega_id = m.bodega_id AND producto_id = m.producto_id) AS stock_actual,
    m.ot_id,
    ot.folio               AS ot_folio,
    ot.prioridad           AS ot_prioridad,
    ot.fecha_programada    AS ot_fecha,
    ot.faena_id,
    f.nombre               AS faena,
    ot.activo_id,
    a.patente              AS activo_patente,
    a.codigo               AS activo_codigo,
    m.planificado_por,
    up.nombre_completo     AS planificado_por_nombre,
    m.comentario,
    m.created_at
FROM ot_materiales_planeados m
JOIN productos p              ON p.id = m.producto_id
LEFT JOIN bodegas b           ON b.id = m.bodega_id
LEFT JOIN ordenes_trabajo ot  ON ot.id = m.ot_id
LEFT JOIN faenas f            ON f.id = ot.faena_id
LEFT JOIN activos a           ON a.id = ot.activo_id
LEFT JOIN usuarios_perfil up  ON up.id = m.planificado_por
WHERE m.estado IN ('faltante','suficiente');

COMMENT ON VIEW v_materiales_pendientes_despacho IS
    'Materiales pedidos por OTs que aun no fueron despachados. Lista de '
    'trabajo del bodeguero. Incluye stock_actual para decidir despacho.';


-- ============================================================================
-- 7. RLS basica (authenticated puede leer/escribir)
-- ============================================================================

ALTER TABLE ot_materiales_planeados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_mat_all ON ot_materiales_planeados;
CREATE POLICY pol_mat_all ON ot_materiales_planeados
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);


-- ============================================================================
-- 8. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_tabla_ok   BOOLEAN;
    v_fn1_ok     BOOLEAN;
    v_fn2_ok     BOOLEAN;
    v_vista_ok   BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_name = 'ot_materiales_planeados') INTO v_tabla_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_agregar_material_ot') INTO v_fn1_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_despachar_material_ot') INTO v_fn2_ok;
    SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'v_materiales_pendientes_despacho') INTO v_vista_ok;

    RAISE NOTICE '== Migracion 48 ==';
    RAISE NOTICE 'Tabla ot_materiales_planeados ......... %', v_tabla_ok;
    RAISE NOTICE 'fn_agregar_material_ot ................ %', v_fn1_ok;
    RAISE NOTICE 'fn_despachar_material_ot .............. %', v_fn2_ok;
    RAISE NOTICE 'v_materiales_pendientes_despacho ...... %', v_vista_ok;

    IF NOT (v_tabla_ok AND v_fn1_ok AND v_fn2_ok AND v_vista_ok) THEN
        RAISE EXCEPTION 'Migracion 48 incompleta.';
    END IF;
END $$;
