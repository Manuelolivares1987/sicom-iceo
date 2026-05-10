-- ============================================================================
-- diag_36_bodega_estado_inventario_consolidado.sql
-- ----------------------------------------------------------------------------
-- Diagnostico read-only consolidado en UN SOLO resultset para copiar
-- completo desde Supabase como JSON.
--
-- Schema unico:
--   dx          (text)  etiqueta de la query origen (Q1..Q9)
--   categoria   (text)  sub-bucket dentro del dx (ej. estado, tipo)
--   item        (text)  clave de fila (ej. producto_codigo)
--   valor_1     (text)  metrica primaria
--   valor_2     (text)
--   valor_3     (text)
--   valor_4     (text)
--   estado      (text)  estado_reconciliacion u otro
--   detalle     (text)  descripcion legible
--   extra_json  (jsonb) campos adicionales
--
-- USO:
--   Ejecutar completo. Devuelve un unico resultset ordenado por dx.
--   Copiar todo el JSON desde Supabase y pegarlo en el chat.
--
-- NO TOCA STOCK. NO ESCRIBE NADA. NO ACTIVA RPCs.
-- ============================================================================

WITH

-- ── Q1. Resumen estados stock vs FIFO ──────────────────────────────────────
q1 AS (
    SELECT
        'Q1_resumen_stock_fifo'::text                     AS dx,
        estado_reconciliacion::text                       AS categoria,
        ''::text                                          AS item,
        COUNT(*)::text                                    AS valor_1,
        ROUND(SUM(cantidad_legacy)::numeric, 2)::text     AS valor_2,
        ROUND(SUM(cantidad_fifo)::numeric, 2)::text       AS valor_3,
        ROUND(SUM(delta_valor)::numeric, 0)::text         AS valor_4,
        estado_reconciliacion::text                       AS estado,
        ('productos=' || COUNT(*) || ' delta_cant=' || ROUND(SUM(delta_cantidad)::numeric, 2))::text AS detalle,
        jsonb_build_object(
            'suma_valor_legacy_clp', ROUND(SUM(valor_legacy)::numeric, 0),
            'suma_valor_fifo_clp',   ROUND(SUM(valor_fifo)::numeric, 0)
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    GROUP BY estado_reconciliacion
),

-- ── Q2. Top 20 desviaciones por cantidad ───────────────────────────────────
q2 AS (
    SELECT
        'Q2_top_desviaciones_cant'::text                  AS dx,
        producto_categoria::text                          AS categoria,
        producto_codigo::text                             AS item,
        cantidad_legacy::text                             AS valor_1,
        cantidad_fifo::text                               AS valor_2,
        ROUND(delta_cantidad::numeric, 3)::text           AS valor_3,
        ROUND(delta_valor::numeric, 0)::text              AS valor_4,
        estado_reconciliacion::text                       AS estado,
        (LEFT(producto_nombre, 60) || ' | ' || bodega_codigo)::text AS detalle,
        jsonb_build_object(
            'bodega_codigo', bodega_codigo,
            'valor_legacy_clp', ROUND(valor_legacy::numeric, 0),
            'valor_fifo_clp', ROUND(valor_fifo::numeric, 0)
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    WHERE estado_reconciliacion <> 'cuadrado'
    ORDER BY ABS(COALESCE(delta_cantidad, 0)) DESC NULLS LAST
    LIMIT 20
),

-- ── Q3. Top 20 desviaciones por valor ──────────────────────────────────────
q3 AS (
    SELECT
        'Q3_top_desviaciones_valor'::text                 AS dx,
        producto_categoria::text                          AS categoria,
        producto_codigo::text                             AS item,
        ROUND(valor_legacy::numeric, 0)::text             AS valor_1,
        ROUND(valor_fifo::numeric, 0)::text               AS valor_2,
        ROUND(delta_valor::numeric, 0)::text              AS valor_3,
        ROUND(delta_cantidad::numeric, 3)::text           AS valor_4,
        estado_reconciliacion::text                       AS estado,
        (LEFT(producto_nombre, 60) || ' | ' || bodega_codigo)::text AS detalle,
        jsonb_build_object(
            'bodega_codigo', bodega_codigo,
            'cantidad_legacy', cantidad_legacy,
            'cantidad_fifo', cantidad_fifo
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    WHERE estado_reconciliacion <> 'cuadrado'
    ORDER BY ABS(COALESCE(delta_valor, 0)) DESC NULLS LAST
    LIMIT 20
),

-- ── Q4. Productos con stock legacy > 0 y sin capa FIFO ─────────────────────
q4 AS (
    SELECT
        'Q4_sin_capa_con_stock'::text                     AS dx,
        producto_categoria::text                          AS categoria,
        producto_codigo::text                             AS item,
        cantidad_legacy::text                             AS valor_1,
        ROUND(costo_promedio_legacy::numeric, 2)::text    AS valor_2,
        ROUND(valor_legacy::numeric, 0)::text             AS valor_3,
        ''::text                                          AS valor_4,
        'sin_capa_fifo'::text                             AS estado,
        (LEFT(producto_nombre, 60) || ' | ' || bodega_codigo)::text AS detalle,
        jsonb_build_object(
            'bodega_codigo', bodega_codigo,
            'ultimo_movimiento', ultimo_movimiento_legacy
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    WHERE estado_reconciliacion = 'sin_capa_fifo'
      AND cantidad_legacy > 0
    ORDER BY valor_legacy DESC NULLS LAST
    LIMIT 50
),

-- ── Q5. Productos con stock > 0 y costo 0 ──────────────────────────────────
q5 AS (
    SELECT
        'Q5_stock_sin_costo'::text                        AS dx,
        producto_categoria::text                          AS categoria,
        producto_codigo::text                             AS item,
        cantidad_legacy::text                             AS valor_1,
        ROUND(costo_promedio_legacy::numeric, 4)::text    AS valor_2,
        cantidad_fifo::text                               AS valor_3,
        ''::text                                          AS valor_4,
        estado_reconciliacion::text                       AS estado,
        (LEFT(producto_nombre, 60) || ' | ' || bodega_codigo)::text AS detalle,
        jsonb_build_object(
            'bodega_codigo', bodega_codigo
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    WHERE cantidad_legacy > 0
      AND COALESCE(costo_promedio_legacy, 0) = 0
    ORDER BY cantidad_legacy DESC
    LIMIT 50
),

-- ── Q6. Distribucion por categoria de sin_capa_fifo con stock > 0 ──────────
q6 AS (
    SELECT
        'Q6_sin_capa_por_categoria'::text                 AS dx,
        producto_categoria::text                          AS categoria,
        ''::text                                          AS item,
        COUNT(*)::text                                    AS valor_1,
        ROUND(SUM(cantidad_legacy)::numeric, 2)::text     AS valor_2,
        ROUND(SUM(valor_legacy)::numeric, 0)::text        AS valor_3,
        SUM(CASE WHEN COALESCE(costo_promedio_legacy, 0) = 0 THEN 1 ELSE 0 END)::text AS valor_4,
        'sin_capa_fifo'::text                             AS estado,
        ('productos=' || COUNT(*) || ' valor_total='|| ROUND(SUM(valor_legacy)::numeric, 0))::text AS detalle,
        '{}'::jsonb                                       AS extra_json
    FROM v_bodega_reconciliacion_stock_fifo
    WHERE estado_reconciliacion = 'sin_capa_fifo'
      AND cantidad_legacy > 0
    GROUP BY producto_categoria
),

-- ── Q7. Combustible detalle por estanque ───────────────────────────────────
q7 AS (
    SELECT
        'Q7_combustible_detalle'::text                    AS dx,
        ''::text                                          AS categoria,
        estanque_codigo::text                             AS item,
        ROUND(estanque_stock_teorico_lt::numeric, 2)::text AS valor_1,
        COALESCE(ROUND(varilla_fisico_lt::numeric, 2)::text, '')                AS valor_2,
        COALESCE(ROUND(delta_fisico_vs_teorico_lt::numeric, 2)::text, '')       AS valor_3,
        COALESCE(dias_desde_ultima_varilla::text, '')     AS valor_4,
        estado_reconciliacion::text                       AS estado,
        estanque_nombre::text                             AS detalle,
        jsonb_build_object(
            'capacidad_lt', capacidad_lt,
            'activo', estanque_activo,
            'cpp_lt', estanque_cpp_lt,
            'valor_total_clp', estanque_valor_total,
            'varilla_fecha', varilla_fecha,
            'varilla_observaciones', varilla_observaciones,
            'kardex_fecha', kardex_fecha,
            'kardex_tipo', kardex_tipo,
            'kardex_stock_lt', kardex_stock_lt,
            'delta_estanque_vs_kardex_lt', delta_estanque_vs_kardex_lt
        )                                                 AS extra_json
    FROM v_bodega_reconciliacion_combustible
),

-- ── Q8. Movimientos excepcionales 60d ──────────────────────────────────────
q8 AS (
    SELECT
        'Q8_mov_excepcionales'::text                      AS dx,
        tipo::text                                        AS categoria,
        (producto_codigo || ' @ ' || bodega_codigo)::text AS item,
        cantidad::text                                    AS valor_1,
        ROUND(costo_unitario::numeric, 2)::text           AS valor_2,
        ROUND(costo_total::numeric, 0)::text              AS valor_3,
        TO_CHAR(fecha, 'YYYY-MM-DD HH24:MI')              AS valor_4,
        tipo::text                                        AS estado,
        (LEFT(producto_nombre, 60) || ' | motivo: ' || COALESCE(LEFT(motivo, 80), '—'))::text AS detalle,
        jsonb_build_object(
            'usuario_nombre', usuario_nombre,
            'usuario_rol', usuario_rol,
            'ot_folio', ot_folio,
            'producto_categoria', producto_categoria,
            'bodega_nombre', bodega_nombre
        )                                                 AS extra_json
    FROM v_bodega_movimientos_excepcionales
),

-- ── Q9. Capas FIFO actuales (resumen agregado) ─────────────────────────────
q9 AS (
    SELECT
        'Q9_capas_fifo_actuales'::text                    AS dx,
        'capas'::text                                     AS categoria,
        ''::text                                          AS item,
        COUNT(*)::text                                    AS valor_1,
        COUNT(*) FILTER (WHERE estado = 'disponible')::text AS valor_2,
        COUNT(*) FILTER (WHERE estado = 'agotada')::text  AS valor_3,
        COUNT(*) FILTER (WHERE recepcion_bodega_id IS NULL)::text AS valor_4,
        ''::text                                          AS estado,
        ('mas_antigua=' || COALESCE(MIN(fecha_recepcion)::text, '—') ||
         ' mas_nueva='  || COALESCE(MAX(fecha_recepcion)::text, '—'))::text AS detalle,
        jsonb_build_object(
            'valor_total_fifo_clp', ROUND(SUM(cantidad_disponible * costo_unitario)::numeric, 0),
            'cantidad_total_disponible', ROUND(SUM(cantidad_disponible)::numeric, 2)
        )                                                 AS extra_json
    FROM inventario_capas
)

SELECT * FROM q1
UNION ALL SELECT * FROM q2
UNION ALL SELECT * FROM q3
UNION ALL SELECT * FROM q4
UNION ALL SELECT * FROM q5
UNION ALL SELECT * FROM q6
UNION ALL SELECT * FROM q7
UNION ALL SELECT * FROM q8
UNION ALL SELECT * FROM q9
ORDER BY dx, categoria, item;

-- ============================================================================
-- Fin diagnostico consolidado. NO se escribio nada en BD. NO se toco stock.
-- ============================================================================
