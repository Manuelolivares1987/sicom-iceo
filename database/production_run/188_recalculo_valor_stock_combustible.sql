-- ============================================================================
-- SICOM-ICEO | 188 — Regularización histórica de valor_total_stock (combustible)
-- ----------------------------------------------------------------------------
-- ⚠️  NO APLICAR JUNTO CON MIG187. Esta migración corrige los SALDOS históricos
--     que quedaron inflados por el bug (MIG77/78 dejaron de bajar el valor en
--     salidas; MIG76/93/99 nunca lo movieron en traspasos). MIG187 corrige el
--     comportamiento futuro; esta 188 regulariza el acumulado.
--
-- ⚠️  REQUIERE AUTORIZACIÓN EXPLÍCITA ("APLICAR EN PRODUCCIÓN"). El guard de
--     abajo aborta salvo que se edite v_autorizado := true. Antes de aplicar,
--     ejecutar el dry-run: database/diagnostics/combustible_reconciliacion.sql
--     (solo SELECT, muestra exactamente qué filas cambiarían y en cuánto).
--
-- Regla de regularización:
--   valor_total_stock := ROUND(stock_teorico_lt * COALESCE(costo_promedio_lt,0), 2)
--   (idéntica a la que usan el kardex y MIG187: el valor del estanque es
--   siempre stock vigente × CPP vigente, porque el CPP no cambia en salidas).
--   Se verificó en prod (2026-07-03) que el último kardex de cada estanque
--   coincide con stock×CPP; la columna era la única desviada.
--
-- Incluye estanques demo (es_demo=true): quedan también consistentes
-- (CAM-DEMO-1 pasa de $16.000.000 con stock 0 → $0). Se identifican aparte
-- en el respaldo y en el reporte de cambios.
--
-- Respaldo y rollback:
--   * Se crea combustible_estanques_valor_bkp_mig188 con los valores previos.
--   * Rollback: UPDATE desde esa tabla (bloque comentado al final).
--
-- Precondiciones (validadas por el propio script antes de tocar datos):
--   * MIG187 ya aplicada (la salida vuelve a mover el valor; si no, el
--     descuadre se reproduce con el siguiente movimiento).
--   * Ninguna fila con stock negativo.
-- ============================================================================

DO $$
DECLARE
    -- ⚠️ Cambiar a true SOLO con la instrucción explícita APLICAR EN PRODUCCIÓN.
    v_autorizado CONSTANT BOOLEAN := false;
BEGIN
    IF NOT v_autorizado THEN
        RAISE EXCEPTION 'MIG188 es una regularización one-shot de datos. Requiere '
            'autorización explícita: revisar el dry-run (database/diagnostics/'
            'combustible_reconciliacion.sql) y editar v_autorizado := true.';
    END IF;
END $$;

-- ── Precondiciones ───────────────────────────────────────────────────────────
DO $$
DECLARE v_def TEXT; v_neg INT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada';
    IF v_def NOT LIKE '%valor_total_stock = v_valor_post%' THEN
        RAISE EXCEPTION 'Precondición: aplicar MIG187 antes que MIG188.';
    END IF;
    SELECT count(*) INTO v_neg FROM public.combustible_estanques WHERE stock_teorico_lt < 0;
    IF v_neg > 0 THEN
        RAISE EXCEPTION 'Precondición: % estanques con stock negativo; investigar antes de regularizar.', v_neg;
    END IF;
END $$;

-- ── Respaldo de valores previos (rollback) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_estanques_valor_bkp_mig188 AS
SELECT now() AS respaldado_at, id, codigo, es_demo,
       stock_teorico_lt, costo_promedio_lt, valor_total_stock
FROM public.combustible_estanques;

-- ── Regularización ───────────────────────────────────────────────────────────
UPDATE public.combustible_estanques e
   SET valor_total_stock = ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt, 0))::numeric, 2),
       updated_at        = now()
 WHERE ROUND((e.stock_teorico_lt * COALESCE(e.costo_promedio_lt, 0))::numeric, 2)
       IS DISTINCT FROM e.valor_total_stock;

-- ── Postvalidación ───────────────────────────────────────────────────────────
DO $$
DECLARE v_mal INT; v_corregidos INT;
BEGIN
    SELECT count(*) INTO v_mal
      FROM public.combustible_estanques e
     WHERE ABS(COALESCE(e.valor_total_stock,0)
               - e.stock_teorico_lt * COALESCE(e.costo_promedio_lt,0)) > 0.011;
    IF v_mal > 0 THEN
        RAISE EXCEPTION 'Postvalidación FALLÓ: % estanques siguen descuadrados (rollback automático).', v_mal;
    END IF;
    SELECT count(*) INTO v_corregidos
      FROM public.combustible_estanques e
      JOIN public.combustible_estanques_valor_bkp_mig188 b ON b.id = e.id
     WHERE b.valor_total_stock IS DISTINCT FROM e.valor_total_stock;
    RAISE NOTICE 'MIG188 OK: % estanques regularizados (detalle en combustible_estanques_valor_bkp_mig188).', v_corregidos;
END $$;

-- Reporte de cambios (última SELECT: la imprime aplicar-migracion.mjs)
SELECT b.codigo, b.es_demo,
       b.valor_total_stock  AS valor_anterior,
       e.valor_total_stock  AS valor_nuevo,
       ROUND((e.valor_total_stock - b.valor_total_stock)::numeric, 2) AS diferencia
FROM public.combustible_estanques_valor_bkp_mig188 b
JOIN public.combustible_estanques e ON e.id = b.id
WHERE b.valor_total_stock IS DISTINCT FROM e.valor_total_stock
ORDER BY ABS(e.valor_total_stock - b.valor_total_stock) DESC;

-- ============================================================================
-- ROLLBACK (ejecutar manualmente solo si se necesita revertir):
--
-- UPDATE public.combustible_estanques e
--    SET valor_total_stock = b.valor_total_stock,
--        updated_at        = now()
--   FROM public.combustible_estanques_valor_bkp_mig188 b
--  WHERE b.id = e.id
--    AND e.valor_total_stock IS DISTINCT FROM b.valor_total_stock;
-- ============================================================================
