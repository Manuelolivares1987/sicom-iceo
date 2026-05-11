-- ============================================================================
-- diag_smoke37_falla_reconciliacion.sql
-- ----------------------------------------------------------------------------
-- Diagnostico read-only de la fila desviada tras el smoke test MIG37.
--
-- HIPOTESIS A INVESTIGAR:
--   La aritmetica CPP movil (legacy stock_bodega.costo_promedio) y FIFO
--   real (suma cantidad_disponible * costo_unitario por capa) NO es
--   matematicamente equivalente cuando una recepcion entra con costo
--   muy distinto al CPP actual del producto.
--
--   Si el smoke recepciono a $1234 CLP pero el CPP real del producto
--   era $X, el CPP movil se desplaza a un promedio ponderado entre $X
--   y $1234. La salida posterior consume una capa antigua a $X via
--   FIFO (no a $1234). Legacy descuenta a CPP movil; FIFO descuenta a
--   costo de capa. La cantidad cuadra pero el valor NO.
--
-- Devuelve UN solo resultset con schema fijo:
--   dx, codigo, descripcion, num1, num2, num3, num4, num5
--
-- NO TOCA STOCK. NO ESCRIBE NADA.
-- ============================================================================

WITH
desviados AS (
    SELECT *
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado'
),

-- Q1: filas desviadas (resumen)
q1 AS (
    SELECT
        'Q1_filas_desviadas'                            AS dx,
        producto_codigo                                 AS codigo,
        LEFT(producto_nombre, 50) || ' @ ' || bodega_codigo AS descripcion,
        cantidad_legacy                                 AS num1,
        cantidad_fifo                                   AS num2,
        delta_cantidad                                  AS num3,
        ROUND(valor_legacy::numeric, 0)                 AS num4,
        ROUND(valor_fifo::numeric, 0)                   AS num5,
        estado_reconciliacion                           AS estado,
        producto_id::text                               AS producto_id_txt,
        bodega_id::text                                 AS bodega_id_txt
    FROM desviados
),

-- Q2: capas FIFO de los productos desviados
q2 AS (
    SELECT
        'Q2_capas_de_desviados'                         AS dx,
        ic.folio_recepcion                              AS codigo,
        LEFT(p.nombre, 40) || ' lote=' || COALESCE(ic.lote,'-')
            || ' fecha=' || ic.fecha_recepcion::text   AS descripcion,
        ic.cantidad_inicial                             AS num1,
        ic.cantidad_disponible                          AS num2,
        ic.costo_unitario                               AS num3,
        ROUND((ic.cantidad_disponible * ic.costo_unitario)::numeric, 0) AS num4,
        NULL::numeric                                   AS num5,
        ic.estado::text                                 AS estado,
        ic.producto_id::text                            AS producto_id_txt,
        ic.bodega_id::text                              AS bodega_id_txt
    FROM inventario_capas ic
    JOIN productos p ON p.id = ic.producto_id
    JOIN desviados d ON d.producto_id::text = ic.producto_id::text
                    AND d.bodega_id::text   = ic.bodega_id::text
    ORDER BY ic.fecha_recepcion ASC, ic.created_at ASC
),

-- Q3: consumos FIFO recientes (salidas que tocaron capas de productos desviados)
q3 AS (
    SELECT
        'Q3_consumos_capas'                             AS dx,
        sb.folio_salida                                 AS codigo,
        (icc.fecha_consumo::text || ' salida=' || COALESCE(sb.folio_salida,'-')
            || ' ot=' || COALESCE(sb.ot_id::text,'-'))  AS descripcion,
        icc.cantidad_consumida                          AS num1,
        icc.costo_unitario_capa                         AS num2,
        ROUND(icc.costo_total_consumido::numeric, 0)    AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        'consumo'                                       AS estado,
        icc.producto_id::text                           AS producto_id_txt,
        icc.bodega_id::text                             AS bodega_id_txt
    FROM inventario_consumos_capas icc
    JOIN desviados d ON d.producto_id::text = icc.producto_id::text
                    AND d.bodega_id::text   = icc.bodega_id::text
    LEFT JOIN salidas_bodega sb ON sb.id = icc.salida_bodega_id
    ORDER BY icc.fecha_consumo DESC
    LIMIT 20
),

-- Q4: movimientos_inventario recientes de productos desviados (entrada/salida legacy)
q4 AS (
    SELECT
        'Q4_movimientos_legacy'                         AS dx,
        COALESCE(mi.documento_referencia, '-')          AS codigo,
        (mi.created_at::text || ' tipo=' || mi.tipo::text
            || ' ot=' || COALESCE(mi.ot_id::text,'-')
            || ' motivo=' || COALESCE(LEFT(mi.motivo,40),'-')) AS descripcion,
        mi.cantidad                                     AS num1,
        mi.costo_unitario                               AS num2,
        ROUND(mi.costo_total::numeric, 0)               AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        mi.tipo::text                                   AS estado,
        mi.producto_id::text                            AS producto_id_txt,
        mi.bodega_id::text                              AS bodega_id_txt
    FROM movimientos_inventario mi
    JOIN desviados d ON d.producto_id::text = mi.producto_id::text
                    AND d.bodega_id::text   = mi.bodega_id::text
    ORDER BY mi.created_at DESC
    LIMIT 30
),

-- Q5: OC piloto SMOKE_TEST_MIG37
q5 AS (
    SELECT
        'Q5_oc_piloto'                                  AS dx,
        numero_oc                                       AS codigo,
        ('estado=' || estado::text || ' fecha=' || fecha_oc::text
            || ' obs=' || COALESCE(LEFT(observacion,40),'-')) AS descripcion,
        monto_total_clp::numeric                        AS num1,
        NULL::numeric                                   AS num2,
        NULL::numeric                                   AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        estado::text                                    AS estado,
        ''::text                                        AS producto_id_txt,
        ''::text                                        AS bodega_id_txt
    FROM ordenes_compra
    WHERE observacion = 'SMOKE_TEST_MIG37'
    ORDER BY created_at DESC
    LIMIT 10
),

-- Q6: Recepciones piloto SMOKE_TEST_MIG37
q6 AS (
    SELECT
        'Q6_recepciones_piloto'                         AS dx,
        folio_recepcion                                 AS codigo,
        ('estado=' || estado::text || ' bodega=' || bodega_id::text
            || ' obs=' || COALESCE(LEFT(observacion,40),'-')) AS descripcion,
        NULL::numeric                                   AS num1,
        NULL::numeric                                   AS num2,
        NULL::numeric                                   AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        estado                                          AS estado,
        ''::text                                        AS producto_id_txt,
        bodega_id::text                                 AS bodega_id_txt
    FROM recepciones_bodega
    WHERE observacion ILIKE '%SMOKE_TEST_MIG37%'
    ORDER BY created_at DESC
    LIMIT 10
),

-- Q7: Salidas piloto SMOKE_TEST_MIG37
q7 AS (
    SELECT
        'Q7_salidas_piloto'                             AS dx,
        folio_salida                                    AS codigo,
        ('estado=' || estado::text || ' tipo=' || tipo_salida::text
            || ' ot=' || COALESCE(ot_id::text,'-')
            || ' motivo=' || COALESCE(LEFT(motivo,30),'-')) AS descripcion,
        NULL::numeric                                   AS num1,
        NULL::numeric                                   AS num2,
        NULL::numeric                                   AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        estado                                          AS estado,
        ''::text                                        AS producto_id_txt,
        bodega_id::text                                 AS bodega_id_txt
    FROM salidas_bodega
    WHERE motivo ILIKE '%SMOKE TEST MIG37%'
    ORDER BY created_at DESC
    LIMIT 10
),

-- Q8: stock_bodega actual del/los productos desviados
q8 AS (
    SELECT
        'Q8_stock_bodega_actual'                        AS dx,
        p.codigo                                        AS codigo,
        LEFT(p.nombre,40) || ' @ ' || b.codigo          AS descripcion,
        sb.cantidad                                     AS num1,
        sb.costo_promedio                               AS num2,
        ROUND(sb.valor_total::numeric, 0)               AS num3,
        NULL::numeric                                   AS num4,
        NULL::numeric                                   AS num5,
        sb.ultimo_movimiento::text                      AS estado,
        sb.producto_id::text                            AS producto_id_txt,
        sb.bodega_id::text                              AS bodega_id_txt
    FROM stock_bodega sb
    JOIN productos p ON p.id = sb.producto_id
    JOIN bodegas   b ON b.id = sb.bodega_id
    JOIN desviados d ON d.producto_id::text = sb.producto_id::text
                    AND d.bodega_id::text   = sb.bodega_id::text
),

-- Q9: resumen
q9 AS (
    SELECT
        'Q9_resumen_desviacion'                         AS dx,
        ''                                              AS codigo,
        'total_desviados / total_filas'                 AS descripcion,
        (SELECT COUNT(*) FROM desviados)::numeric       AS num1,
        (SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo)::numeric AS num2,
        (SELECT SUM(ABS(delta_cantidad)) FROM desviados)::numeric AS num3,
        (SELECT SUM(ABS(delta_valor))    FROM desviados)::numeric AS num4,
        NULL::numeric                                   AS num5,
        ''                                              AS estado,
        ''::text                                        AS producto_id_txt,
        ''::text                                        AS bodega_id_txt
)

SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q9
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q1
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q8
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q2
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q3
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q4
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q5
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q6
UNION ALL SELECT dx, codigo, descripcion, num1, num2, num3, num4, num5, estado, producto_id_txt, bodega_id_txt FROM q7
ORDER BY 1, 2;

-- ============================================================================
-- Como leer los resultsets:
--   Q9 — cuenta global y suma absoluta de delta cantidad/valor.
--   Q1 — fila(s) desviada(s) con producto, bodega, cantidades y valores.
--   Q8 — snapshot stock_bodega actual de los productos desviados.
--   Q2 — todas las capas FIFO de esos productos (incluye capas iniciales
--        del 2026-05-02 y capas del smoke test).
--   Q3 — consumos FIFO registrados para esos productos (capa_id, cantidad,
--        costo, ot, ceco). Si solo hay 1 fila reciente, la salida bajo capa.
--   Q4 — movimientos_inventario legacy (entrada/salida) para los productos
--        desviados, ultimas 30 filas. Si hay 1 entrada y 1 salida del smoke
--        test, la mecanica del flujo se ejecuto.
--   Q5-Q7 — la huella de las corridas previas del smoke (OC, recepcion, salida).
--
-- Patron esperado si la causa es CPP-vs-FIFO:
--   Q1 num3 (delta_cantidad) = 0  -- cantidad cuadra
--   Q1 num4 vs num5 (valor_legacy vs valor_fifo) DIFIEREN
--   Q4 ultima fila tipo='salida' costo_unitario = CPP movil
--   Q3 ultima fila costo_unitario_capa <> costo_unitario de Q4
-- ============================================================================
