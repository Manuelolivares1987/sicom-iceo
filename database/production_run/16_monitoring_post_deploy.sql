-- ============================================================================
-- 16_monitoring_post_deploy.sql  —  Solo lectura. Ejecutar:
--   - 1 hora después del deploy
--   - 24 horas después
--   - 7 días después
-- ============================================================================


-- ── 1. Eventos auditoria últimas 24h (resumen) ───────────────────────
SELECT
    tabla, accion, COUNT(*) AS eventos
FROM auditoria_eventos
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY tabla, accion
ORDER BY eventos DESC
LIMIT 20;


-- ── 2. Movimientos inventario últimas 24h ────────────────────────────
SELECT
    tipo, COUNT(*) AS movimientos,
    SUM(cantidad) AS total_unidades
FROM movimientos_inventario
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY tipo;


-- ── 3. Movimientos combustible últimas 24h ───────────────────────────
SELECT
    tipo, COUNT(*) AS movimientos,
    SUM(litros) AS total_litros
FROM combustible_movimientos
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY tipo;


-- ── 4. ⚠️ Stock negativo ─────────────────────────────────────────────
SELECT
    'STOCK_NEGATIVO' AS alert,
    COUNT(*) AS productos_con_stock_negativo
FROM stock_bodega
WHERE cantidad < 0;
-- Esperado: 0


-- ── 5. ⚠️ Productos con stock pero sin capa FIFO ─────────────────────
SELECT
    'PRODUCTOS_SIN_CAPA' AS alert,
    COUNT(*) AS cantidad
FROM stock_bodega sb
WHERE sb.cantidad > 0
  AND NOT EXISTS (
    SELECT 1 FROM inventario_capas ic
     WHERE ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
  );
-- Esperado: 0 (o solo productos con costo NULL/0 documentados)


-- ── 6. ⚠️ Estanques con stock pero sin CPP ───────────────────────────
SELECT
    e.codigo,
    e.stock_teorico_lt,
    e.costo_promedio_lt,
    e.valor_total_stock
FROM combustible_estanques e
WHERE e.activo = true
  AND e.stock_teorico_lt > 0
  AND (e.costo_promedio_lt IS NULL OR e.costo_promedio_lt = 0);
-- Esperado: vacío


-- ── 7. ⚠️ Reconciliacion estanques vs ultimo kardex ──────────────────
SELECT
    e.codigo,
    e.stock_teorico_lt AS estanque,
    (SELECT stock_lt_despues FROM combustible_kardex_valorizado
      WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_ultimo,
    e.valor_total_stock AS estanque_valor,
    (SELECT valor_stock_despues FROM combustible_kardex_valorizado
      WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_valor_ultimo
FROM combustible_estanques e
WHERE e.activo = true;
-- Pares deben coincidir.


-- ── 8. Reconciliacion FIFO ────────────────────────────────────────────
SELECT
    'RECONCILIACION_FIFO' AS check_name,
    COUNT(*) AS productos_desincronizados
FROM (
    SELECT sb.producto_id, sb.bodega_id, sb.cantidad,
           COALESCE(SUM(ic.cantidad_disponible), 0) AS capas
    FROM stock_bodega sb
    LEFT JOIN inventario_capas ic
      ON ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
    WHERE sb.cantidad > 0
    GROUP BY sb.producto_id, sb.bodega_id, sb.cantidad
    HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001
) sub;


-- ── 9. Usuarios activos por rol ──────────────────────────────────────
SELECT rol, COUNT(*) FROM usuarios_perfil WHERE activo=true GROUP BY rol ORDER BY rol;


-- ── 10. Conteo tablas nuevas ─────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM proveedores) AS proveedores,
    (SELECT COUNT(*) FROM centros_costo) AS ceco,
    (SELECT COUNT(*) FROM ordenes_compra) AS ocs,
    (SELECT COUNT(*) FROM recepciones_bodega) AS recepciones,
    (SELECT COUNT(*) FROM salidas_bodega) AS salidas_bodega,
    (SELECT COUNT(*) FROM ingresos_combustible) AS ingresos_comb,
    (SELECT COUNT(*) FROM salidas_combustible) AS salidas_comb,
    (SELECT COUNT(*) FROM despachos_combustible) AS despachos,
    (SELECT COUNT(*) FROM inventario_capas) AS capas_fifo,
    (SELECT COUNT(*) FROM inventario_consumos_capas) AS consumos_fifo,
    (SELECT COUNT(*) FROM combustible_stock_inicial WHERE anulado=false) AS stocks_iniciales,
    (SELECT COUNT(*) FROM combustible_kardex_valorizado) AS kardex_combustible;


-- ── 11. ⚠️ Folios duplicados (no deberian existir) ───────────────────
SELECT 'FOLIOS_DUPLICADOS_REC' AS check_name, folio_recepcion, COUNT(*)
FROM recepciones_bodega GROUP BY folio_recepcion HAVING COUNT(*) > 1;

SELECT 'FOLIOS_DUPLICADOS_SAL' AS check_name, folio_salida, COUNT(*)
FROM salidas_bodega GROUP BY folio_salida HAVING COUNT(*) > 1;

SELECT 'FOLIOS_DUPLICADOS_ICB' AS check_name, folio_ingreso, COUNT(*)
FROM ingresos_combustible GROUP BY folio_ingreso HAVING COUNT(*) > 1;

SELECT 'FOLIOS_DUPLICADOS_SCB' AS check_name, folio_salida, COUNT(*)
FROM salidas_combustible GROUP BY folio_salida HAVING COUNT(*) > 1;


-- ── 12. ⚠️ Guías duplicadas (deberia bloquearse por UNIQUE) ──────────
SELECT 'GUIAS_DUPLICADAS' AS check_name, proveedor_id, numero_guia, COUNT(*)
FROM ingresos_combustible
GROUP BY proveedor_id, numero_guia HAVING COUNT(*) > 1;


-- ── 13. ⚠️ OC duplicadas ─────────────────────────────────────────────
SELECT 'OC_DUPLICADAS' AS check_name, numero_oc, COUNT(*)
FROM ordenes_compra GROUP BY numero_oc HAVING COUNT(*) > 1;


-- ── 14. Bitacora migraciones (resumen) ───────────────────────────────
SELECT codigo_paso, COUNT(*) AS veces, MAX(fecha_inicio) AS ultima_ejecucion,
       array_agg(DISTINCT resultado) AS resultados
FROM operacion_migraciones_log
GROUP BY codigo_paso
ORDER BY MAX(fecha_inicio) DESC;


-- ── 15. ⚠️ Errores en bitacora ───────────────────────────────────────
SELECT * FROM operacion_migraciones_log
WHERE resultado IN ('error','revertido','warning')
ORDER BY fecha_inicio DESC LIMIT 20;
-- Esperado: 0 filas (o documentadas).


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- Si TODAS las queries devuelven valores esperados (0 negativos, 0 duplicados,
-- pares coincidentes, sin errores en bitacora), el deploy esta OK.
--
-- Si alguna devuelve filas inesperadas: investigar inmediatamente.
-- ============================================================================
