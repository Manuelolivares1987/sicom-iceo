-- ============================================================================
-- diag_36_bodega_estado_inventario.sql
-- ----------------------------------------------------------------------------
-- Diagnostico read-only del estado de inventario apoyado en las vistas de
-- mig 36. Salida en 9 resultsets etiquetados con la columna `dx` para que
-- sea facil pegarlos en orden.
--
-- USO:
--   Ejecutar completo. Copiar cada resultset en el chat (o el JSON
--   exportado) para que el agente arme el diagnostico ejecutivo y
--   recomiende siguiente frente.
--
-- NO TOCA STOCK. NO ESCRIBE NADA.
-- ============================================================================


-- ── Q1. Resumen de estados stock vs FIFO ─────────────────────────────────────
SELECT
    'Q1_resumen_stock_fifo'                         AS dx,
    estado_reconciliacion                           AS estado,
    COUNT(*)                                        AS productos,
    ROUND(SUM(cantidad_legacy)::numeric, 2)         AS suma_cantidad_legacy,
    ROUND(SUM(cantidad_fifo)::numeric, 2)           AS suma_cantidad_fifo,
    ROUND(SUM(valor_legacy)::numeric, 0)            AS suma_valor_legacy_clp,
    ROUND(SUM(valor_fifo)::numeric, 0)              AS suma_valor_fifo_clp,
    ROUND(SUM(delta_valor)::numeric, 0)             AS suma_delta_valor_clp
FROM v_bodega_reconciliacion_stock_fifo
GROUP BY estado_reconciliacion
ORDER BY productos DESC;


-- ── Q2. Top 20 desviaciones por cantidad ─────────────────────────────────────
SELECT
    'Q2_top_desviaciones_cant'                      AS dx,
    estado_reconciliacion                           AS estado,
    producto_codigo,
    LEFT(producto_nombre, 50)                       AS producto,
    producto_categoria                              AS categoria,
    bodega_codigo,
    cantidad_legacy,
    cantidad_fifo,
    delta_cantidad,
    valor_legacy                                    AS valor_legacy_clp,
    valor_fifo                                      AS valor_fifo_clp
FROM v_bodega_reconciliacion_stock_fifo
WHERE estado_reconciliacion <> 'cuadrado'
ORDER BY ABS(COALESCE(delta_cantidad, 0)) DESC NULLS LAST
LIMIT 20;


-- ── Q3. Top 20 desviaciones por valor ────────────────────────────────────────
SELECT
    'Q3_top_desviaciones_valor'                     AS dx,
    estado_reconciliacion                           AS estado,
    producto_codigo,
    LEFT(producto_nombre, 50)                       AS producto,
    producto_categoria                              AS categoria,
    bodega_codigo,
    cantidad_legacy,
    cantidad_fifo,
    valor_legacy                                    AS valor_legacy_clp,
    valor_fifo                                      AS valor_fifo_clp,
    delta_valor                                     AS delta_valor_clp
FROM v_bodega_reconciliacion_stock_fifo
WHERE estado_reconciliacion <> 'cuadrado'
ORDER BY ABS(COALESCE(delta_valor, 0)) DESC NULLS LAST
LIMIT 20;


-- ── Q4. Productos con stock legacy > 0 y sin capa FIFO (criticos para sembrar)
SELECT
    'Q4_sin_capa_con_stock'                         AS dx,
    producto_codigo,
    LEFT(producto_nombre, 50)                       AS producto,
    producto_categoria                              AS categoria,
    bodega_codigo,
    cantidad_legacy,
    costo_promedio_legacy                           AS costo_unit_clp,
    valor_legacy                                    AS valor_legacy_clp,
    ultimo_movimiento_legacy
FROM v_bodega_reconciliacion_stock_fifo
WHERE estado_reconciliacion = 'sin_capa_fifo'
  AND cantidad_legacy > 0
ORDER BY valor_legacy DESC NULLS LAST;


-- ── Q5. Productos con stock legacy > 0 y costo unitario = 0 (bloqueador) ────
SELECT
    'Q5_stock_sin_costo'                            AS dx,
    producto_codigo,
    LEFT(producto_nombre, 50)                       AS producto,
    producto_categoria                              AS categoria,
    bodega_codigo,
    cantidad_legacy,
    costo_promedio_legacy,
    estado_reconciliacion
FROM v_bodega_reconciliacion_stock_fifo
WHERE cantidad_legacy > 0
  AND COALESCE(costo_promedio_legacy, 0) = 0
ORDER BY cantidad_legacy DESC;


-- ── Q6. Distribucion por categoria de productos sin capa FIFO ───────────────
SELECT
    'Q6_sin_capa_por_categoria'                     AS dx,
    producto_categoria                              AS categoria,
    COUNT(*)                                        AS productos,
    ROUND(SUM(cantidad_legacy)::numeric, 2)         AS suma_cantidad,
    ROUND(SUM(valor_legacy)::numeric, 0)            AS suma_valor_clp,
    SUM(CASE WHEN COALESCE(costo_promedio_legacy, 0) = 0 THEN 1 ELSE 0 END)
                                                    AS productos_sin_costo
FROM v_bodega_reconciliacion_stock_fifo
WHERE estado_reconciliacion = 'sin_capa_fifo'
  AND cantidad_legacy > 0
GROUP BY producto_categoria
ORDER BY suma_valor_clp DESC NULLS LAST;


-- ── Q7. Combustible: estado por estanque ─────────────────────────────────────
SELECT
    'Q7_combustible_detalle'                        AS dx,
    estanque_codigo,
    estanque_nombre,
    estanque_activo                                 AS activo,
    estado_reconciliacion                           AS estado,
    estanque_stock_teorico_lt                       AS teorico_lt,
    varilla_fisico_lt                               AS fisico_ult_lt,
    delta_fisico_vs_teorico_lt                      AS delta_lt,
    varilla_fecha,
    dias_desde_ultima_varilla                       AS dias_sin_varilla,
    estanque_cpp_lt                                 AS cpp_clp,
    estanque_valor_total                            AS valor_clp,
    kardex_fecha,
    kardex_stock_lt,
    delta_estanque_vs_kardex_lt                     AS delta_kardex_lt
FROM v_bodega_reconciliacion_combustible
ORDER BY estanque_codigo;


-- ── Q8. Movimientos excepcionales 60d (detalle) ─────────────────────────────
SELECT
    'Q8_mov_excepcionales'                          AS dx,
    fecha,
    tipo,
    bodega_codigo,
    producto_codigo,
    LEFT(producto_nombre, 40)                       AS producto,
    producto_categoria                              AS categoria,
    cantidad,
    costo_unitario                                  AS costo_unit_clp,
    costo_total                                     AS costo_total_clp,
    LEFT(motivo, 100)                               AS motivo,
    usuario_nombre,
    usuario_rol,
    ot_folio
FROM v_bodega_movimientos_excepcionales
ORDER BY fecha DESC;


-- ── Q9. Capas FIFO actuales (cuantas hay y de donde vienen) ─────────────────
-- Si el numero es 0 o muy bajo, confirma que las capas iniciales nunca se
-- sembraron y el frente #3 es prerequisito antes de cualquier transaccional.
SELECT
    'Q9_capas_fifo_actuales'                        AS dx,
    COUNT(*)                                        AS total_capas,
    COUNT(*) FILTER (WHERE estado = 'disponible')   AS capas_disponibles,
    COUNT(*) FILTER (WHERE estado = 'agotada')      AS capas_agotadas,
    COUNT(*) FILTER (WHERE recepcion_bodega_id IS NULL) AS capas_sin_recepcion,
    MIN(fecha_recepcion)                            AS capa_mas_antigua,
    MAX(fecha_recepcion)                            AS capa_mas_nueva,
    ROUND(SUM(cantidad_disponible * costo_unitario)::numeric, 0) AS valor_total_fifo_clp
FROM inventario_capas;


-- ============================================================================
-- Fin diagnostico. NO se escribio nada en BD. NO se toco stock.
-- ============================================================================
