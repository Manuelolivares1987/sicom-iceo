-- ============================================================================
-- 06_seed_capas_iniciales_fifo.sql  —  Sembrar capas iniciales para legacy.
-- ----------------------------------------------------------------------------
-- Para cada producto con stock > 0 en stock_bodega, crear UNA capa inicial
-- con costo histórico (costo_promedio existente).
--
-- DEPENDE DE: 05_apply_mig56_fifo.sql
-- ============================================================================


-- ── 1. PRECHECK: productos con stock pero sin costo_promedio ─────────

WITH productos_sin_costo AS (
    SELECT sb.bodega_id, sb.producto_id, sb.cantidad,
           sb.costo_promedio AS costo,
           p.codigo, p.nombre
      FROM stock_bodega sb
      JOIN productos p ON p.id = sb.producto_id
     WHERE sb.cantidad > 0
       AND (sb.costo_promedio IS NULL OR sb.costo_promedio = 0)
)
SELECT 'PRODUCTOS_SIN_COSTO' AS check_name,
       COUNT(*) AS cantidad,
       SUM(cantidad) AS unidades
  FROM productos_sin_costo;
-- Esperado: si > 0, REVISAR antes de continuar.


-- ── 2. PRECHECK: cantidades negativas (no deberian existir) ──────────

SELECT 'CANTIDADES_NEGATIVAS' AS check_name,
       COUNT(*) AS cantidad
  FROM stock_bodega
 WHERE cantidad < 0;
-- Esperado: 0


-- ── 3. PRECHECK: capas ya existentes (no debe haber) ─────────────────

SELECT 'CAPAS_EXISTENTES' AS check_name, COUNT(*) AS cantidad
  FROM inventario_capas;
-- Esperado: 0 si es la primera ejecucion


-- ── 4. SEMBRAR CAPAS INICIALES LEGACY ────────────────────────────────
-- DESCOMENTAR EL INSERT cuando los prechecks anteriores sean OK.
-- Si el precheck (1) tiene > 0, decidir:
--   (a) cargar con costo 0 y justificacion (no recomendado para finanzas).
--   (b) actualizar costo_promedio en stock_bodega antes (mejor).
--   (c) excluir esos productos del INSERT (filtrar WHERE costo_promedio > 0).

/*
INSERT INTO inventario_capas (
    producto_id, bodega_id, fecha_recepcion, folio_recepcion,
    cantidad_inicial, cantidad_disponible, unidad, costo_unitario,
    estado
)
SELECT
    sb.producto_id, sb.bodega_id, CURRENT_DATE,
    'CAPA-INICIAL-LEGACY-' || TO_CHAR(NOW(), 'YYYYMMDD'),
    sb.cantidad, sb.cantidad,
    COALESCE(p.unidad_medida, 'unidad'),
    COALESCE(sb.costo_promedio, 0),
    'disponible'
  FROM stock_bodega sb
  JOIN productos p ON p.id = sb.producto_id
 WHERE sb.cantidad > 0
   AND sb.costo_promedio IS NOT NULL
   AND sb.costo_promedio > 0;
*/


-- ── 5. RECONCILIACION POST-SEED ──────────────────────────────────────

SELECT
    'RECONCILIACION_FIFO' AS check_name,
    COUNT(*) AS productos_desincronizados
FROM (
    SELECT
        sb.producto_id, sb.bodega_id,
        sb.cantidad   AS stock_bodega_cantidad,
        COALESCE(SUM(ic.cantidad_disponible), 0) AS capas_total
    FROM stock_bodega sb
    LEFT JOIN inventario_capas ic
      ON ic.producto_id = sb.producto_id
     AND ic.bodega_id = sb.bodega_id
     AND ic.estado = 'disponible'
    WHERE sb.cantidad > 0
    GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
    HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
) sub;
-- Esperado tras seed: 0 (perfecta reconciliacion)


-- ── 6. RESUMEN ───────────────────────────────────────────────────────

SELECT
    (SELECT COUNT(*) FROM inventario_capas) AS total_capas,
    (SELECT COUNT(*) FROM inventario_capas WHERE estado='disponible') AS capas_disponibles,
    (SELECT SUM(cantidad_inicial * costo_unitario) FROM inventario_capas) AS valor_total_inicial,
    (SELECT SUM(cantidad_disponible * costo_unitario) FROM inventario_capas WHERE estado='disponible') AS valor_disponible;


-- ============================================================================
-- INSTRUCCIONES PARA OPERADOR
-- ============================================================================
-- 1. Ejecutar prechecks (queries 1, 2, 3).
-- 2. Si productos_sin_costo > 0:
--    a. Listar los productos: SELECT codigo, nombre, cantidad FROM stock_bodega
--       JOIN productos USING (producto_id) WHERE costo_promedio IS NULL OR costo_promedio = 0;
--    b. Coordinar con Finanzas para actualizar costo_promedio en stock_bodega.
--    c. O ajustar el INSERT del paso 4 para excluir esos productos.
-- 3. Descomentar el INSERT del paso 4 y ejecutar.
-- 4. Ejecutar reconciliacion (paso 5). Esperado: 0 desincronizados.
-- ============================================================================
