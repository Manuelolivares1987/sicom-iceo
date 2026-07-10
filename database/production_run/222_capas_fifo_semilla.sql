-- ============================================================================
-- SICOM-ICEO | 222 — Capas FIFO semilla a $1 + corrección de costo de capa
-- ============================================================================
-- Hallazgo QA 2026-07-09: 368 de 422 productos con stock legacy NO tienen capa
-- FIFO (solo se sembraron 40 en mayo). Consecuencia: el despacho de vales dice
-- "sin stock" aunque la bodega tenga el repuesto físico (caso PORTA FUSIBLE).
--
-- Decisión Manuel (2026-07-10): sembrar TODAS las capas faltantes con costo
-- unitario $1 (folio SEMILLA-INICIAL) y darle una pantalla para corregir el
-- costo real después.
--
--   1. Siembra: 1 capa por producto+bodega con stock legacy > 0 y sin capa.
--   2. rpc_actualizar_costo_capa: corrige el costo unitario de una capa SIN
--      consumos (si ya se consumió, el costeo histórico no se toca).
--   3. v_capas_fifo_admin: capas con producto/bodega y flag editable, para la
--      pantalla de administración de costos.
-- IDEMPOTENTE (la siembra no duplica).
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='inventario_capas') THEN
        RAISE EXCEPTION 'STOP — falta inventario_capas (MIG56).';
    END IF;
END $$;


-- ── 1. Siembra de capas faltantes a $1 ───────────────────────────────────────
-- costo_total_inicial / costo_total_disponible son columnas GENERADAS.
INSERT INTO inventario_capas (
    producto_id, bodega_id, fecha_recepcion, folio_recepcion,
    cantidad_inicial, cantidad_disponible, unidad,
    costo_unitario, estado, created_at, updated_at
)
SELECT sb.producto_id, sb.bodega_id, NOW(), 'SEMILLA-INICIAL',
       sb.cantidad, sb.cantidad, p.unidad_medida,
       1, 'disponible', NOW(), NOW()
  FROM stock_bodega sb
  JOIN productos p ON p.id = sb.producto_id
 WHERE sb.cantidad > 0
   AND NOT EXISTS (SELECT 1 FROM inventario_capas ic
                    WHERE ic.producto_id = sb.producto_id
                      AND ic.bodega_id  = sb.bodega_id);


-- ── 2. Corregir costo de una capa sin consumos ───────────────────────────────
CREATE OR REPLACE FUNCTION rpc_actualizar_costo_capa(
    p_capa_id UUID,
    p_costo_unitario NUMERIC
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_capa RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo administración corrige costos de capas (rol: %)', v_rol;
    END IF;
    IF p_costo_unitario IS NULL OR p_costo_unitario < 0 THEN
        RAISE EXCEPTION 'Costo unitario inválido';
    END IF;

    SELECT * INTO v_capa FROM inventario_capas WHERE id = p_capa_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Capa no existe'; END IF;
    IF EXISTS (SELECT 1 FROM inventario_consumos_capas WHERE capa_id = p_capa_id) THEN
        RAISE EXCEPTION 'La capa ya tiene consumos: su costo histórico no se puede tocar. Haz un ajuste contable.';
    END IF;

    -- costo_total_* son columnas generadas: se recalculan solas.
    UPDATE inventario_capas
       SET costo_unitario = p_costo_unitario,
           updated_at = NOW()
     WHERE id = p_capa_id;

    RETURN jsonb_build_object('success', true, 'capa_id', p_capa_id,
        'costo_unitario', p_costo_unitario);
END $$;
REVOKE EXECUTE ON FUNCTION rpc_actualizar_costo_capa(UUID, NUMERIC) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION rpc_actualizar_costo_capa(UUID, NUMERIC) TO authenticated;


-- ── 3. Vista para la pantalla de costos ──────────────────────────────────────
DROP VIEW IF EXISTS v_capas_fifo_admin;
CREATE VIEW v_capas_fifo_admin AS
SELECT ic.id, ic.producto_id, ic.bodega_id,
       p.codigo  AS producto_codigo,
       p.nombre  AS producto_nombre,
       p.categoria,
       b.nombre  AS bodega_nombre,
       ic.fecha_recepcion, ic.folio_recepcion,
       ic.cantidad_inicial, ic.cantidad_disponible, ic.unidad,
       ic.costo_unitario, ic.costo_total_disponible, ic.estado,
       (ic.folio_recepcion = 'SEMILLA-INICIAL') AS es_semilla,
       NOT EXISTS (SELECT 1 FROM inventario_consumos_capas cc
                    WHERE cc.capa_id = ic.id) AS editable
FROM inventario_capas ic
JOIN productos p ON p.id = ic.producto_id
JOIN bodegas  b ON b.id = ic.bodega_id;
GRANT SELECT ON v_capas_fifo_admin TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'capas_semilla', (SELECT COUNT(*) FROM inventario_capas WHERE folio_recepcion='SEMILLA-INICIAL'),
    'sin_capa_restantes', (SELECT COUNT(*) FROM stock_bodega sb WHERE sb.cantidad > 0
        AND NOT EXISTS (SELECT 1 FROM inventario_capas ic
                         WHERE ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id)),
    'rpc_ok', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_actualizar_costo_capa')),
    'vista_ok', (SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname='v_capas_fifo_admin'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
