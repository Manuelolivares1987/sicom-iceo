-- ============================================================================
-- SICOM-ICEO | 188 — Regularización histórica de valor_total_stock (combustible)
-- ----------------------------------------------------------------------------
-- ⚠️  NO APLICAR JUNTO CON MIG187. MIG187 corrige el comportamiento futuro;
--     esta 188 regulariza los SALDOS históricos (valor de estanque) que
--     quedaron inflados por el bug (MIG77/78 dejaron de bajar el valor en
--     salidas; MIG76/93/99 nunca lo movieron en traspasos).
--
-- ⚠️  REQUIERE AUTORIZACIÓN EXPLÍCITA ("APLICAR EN PRODUCCIÓN"). Editar el
--     bloque de PARÁMETROS con lo aprobado en el dry-run
--     (database/diagnostics/combustible_reconciliacion.sql) y poner
--     v_autorizado := true. La migración ABORTA si el estado actual difiere de
--     lo aprobado (conteo, IDs o delta máximo), evitando aplicar sobre datos
--     que cambiaron desde la revisión.
--
-- DISEÑO (rev. gate preproducción):
--   * DEMO EXCLUIDO POR DEFECTO: la regularización normal solo toca estanques
--     reales (es_demo = false). Los DEMO requieren una autorización aparte
--     (v_incluir_demo := true), porque son datos de prueba, no operación.
--   * PRECONDICIONES bloqueantes: conteo esperado, IDs esperados y delta máximo
--     absoluto. Si la realidad no coincide con lo aprobado → aborta.
--   * BACKUP con valor anterior, valor nuevo, fecha, usuario y motivo.
--   * Regla de valor: valor := ROUND(stock * COALESCE(cpp,0), 2) (idéntica a
--     kardex y MIG187). Verificado en prod: el último kardex de cada estanque
--     ya coincide con stock*cpp; solo la columna estaba desviada.
--
-- Rollback: UPDATE desde el backup (bloque comentado al final).
-- ============================================================================

DO $$
DECLARE
    -- ── PARÁMETROS (editar con lo aprobado en el dry-run) ───────────────────
    v_autorizado   CONSTANT BOOLEAN   := false;   -- ⚠️ true solo con APLICAR EN PRODUCCIÓN
    v_incluir_demo CONSTANT BOOLEAN   := false;   -- autorización SEPARADA para estanques demo
    -- Códigos de estanque REALES que el dry-run aprobó corregir (ajustar a prod):
    v_expected_ids CONSTANT TEXT[]    := ARRAY['EST-1K','EST-15K'];
    v_max_delta    CONSTANT NUMERIC   := 100000;  -- |cambio| máximo permitido por estanque real
    v_motivo       CONSTANT TEXT      := 'Regularizacion valor_total_stock (auditoria Fase 0, bug MIG77/78)';

    -- ── internos ────────────────────────────────────────────────────────────
    v_def          TEXT;
    v_neg          INT;
    v_ids_reales   TEXT[];
    v_n_reales     INT;
    v_max_real     NUMERIC;
    v_extra        TEXT[];
    v_n_corr       INT;
    v_uid          UUID := NULL;
BEGIN
    IF NOT v_autorizado THEN
        RAISE EXCEPTION 'MIG188 one-shot de datos. Revisar dry-run y editar v_autorizado := true.';
    END IF;

    -- Precondición 1: MIG187 aplicada (si no, el descuadre se reproduce).
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada';
    IF v_def NOT LIKE '%valor_total_stock = v_valor_post%' THEN
        RAISE EXCEPTION 'Precondición: aplicar MIG187 antes que MIG188.';
    END IF;

    -- Precondición 2: sin stock negativo.
    SELECT count(*) INTO v_neg FROM public.combustible_estanques WHERE stock_teorico_lt < 0;
    IF v_neg > 0 THEN
        RAISE EXCEPTION 'Precondición: % estanques con stock negativo; investigar antes.', v_neg;
    END IF;

    -- Estado REAL a corregir (SOLO no-demo).
    SELECT array_agg(codigo ORDER BY codigo),
           count(*),
           COALESCE(max(abs(ROUND((stock_teorico_lt*COALESCE(costo_promedio_lt,0))::numeric,2) - valor_total_stock)),0)
      INTO v_ids_reales, v_n_reales, v_max_real
      FROM public.combustible_estanques
     WHERE NOT es_demo
       AND ROUND((stock_teorico_lt*COALESCE(costo_promedio_lt,0))::numeric,2) IS DISTINCT FROM valor_total_stock;
    v_ids_reales := COALESCE(v_ids_reales, ARRAY[]::text[]);

    -- Precondición 3: el conjunto real == el aprobado (ni más ni menos).
    v_extra := ARRAY(SELECT unnest(v_ids_reales) EXCEPT SELECT unnest(v_expected_ids));
    IF array_length(v_extra,1) > 0 THEN
        RAISE EXCEPTION 'Aborta: estanques reales a corregir % difieren de lo aprobado %. Rehacer dry-run.',
            v_ids_reales, v_expected_ids;
    END IF;
    v_extra := ARRAY(SELECT unnest(v_expected_ids) EXCEPT SELECT unnest(v_ids_reales));
    IF array_length(v_extra,1) > 0 THEN
        RAISE EXCEPTION 'Aborta: estanques aprobados % ya no requieren corrección (real=%). Rehacer dry-run.',
            v_expected_ids, v_ids_reales;
    END IF;

    -- Precondición 4: delta máximo dentro del umbral aprobado.
    IF v_max_real > v_max_delta THEN
        RAISE EXCEPTION 'Aborta: delta máximo real % supera el umbral aprobado %.', v_max_real, v_max_delta;
    END IF;

    -- Backup con trazabilidad completa (valor anterior/nuevo, fecha, usuario, motivo).
    BEGIN v_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;
    CREATE TABLE IF NOT EXISTS public.combustible_estanques_valor_bkp_mig188 (
        respaldado_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        aplicado_por  UUID,
        aplicado_por_conn TEXT,
        motivo        TEXT,
        id            UUID,
        codigo        TEXT,
        es_demo       BOOLEAN,
        incluye_demo  BOOLEAN,
        valor_anterior NUMERIC,
        valor_nuevo    NUMERIC
    );
    INSERT INTO public.combustible_estanques_valor_bkp_mig188
        (aplicado_por, aplicado_por_conn, motivo, id, codigo, es_demo, incluye_demo, valor_anterior, valor_nuevo)
    SELECT v_uid, session_user, v_motivo, e.id, e.codigo, e.es_demo, v_incluir_demo,
           e.valor_total_stock,
           ROUND((e.stock_teorico_lt*COALESCE(e.costo_promedio_lt,0))::numeric,2)
      FROM public.combustible_estanques e
     WHERE (NOT e.es_demo OR v_incluir_demo)
       AND ROUND((e.stock_teorico_lt*COALESCE(e.costo_promedio_lt,0))::numeric,2) IS DISTINCT FROM e.valor_total_stock;

    -- Regularización (demo solo si autorizado aparte).
    UPDATE public.combustible_estanques e
       SET valor_total_stock = ROUND((e.stock_teorico_lt*COALESCE(e.costo_promedio_lt,0))::numeric,2),
           updated_at        = now()
     WHERE (NOT e.es_demo OR v_incluir_demo)
       AND ROUND((e.stock_teorico_lt*COALESCE(e.costo_promedio_lt,0))::numeric,2) IS DISTINCT FROM e.valor_total_stock;
    GET DIAGNOSTICS v_n_corr = ROW_COUNT;

    -- Postvalidación: los no-demo deben quedar cuadrados.
    SELECT count(*) INTO v_neg FROM public.combustible_estanques e
     WHERE NOT e.es_demo
       AND abs(COALESCE(e.valor_total_stock,0) - e.stock_teorico_lt*COALESCE(e.costo_promedio_lt,0)) > 0.011;
    IF v_neg > 0 THEN
        RAISE EXCEPTION 'Postvalidación FALLÓ: % estanques reales siguen descuadrados (rollback).', v_neg;
    END IF;

    RAISE NOTICE 'MIG188 OK: % estanques regularizados (demo incluido: %). Backup en combustible_estanques_valor_bkp_mig188.',
        v_n_corr, v_incluir_demo;
END $$;

-- Reporte de cambios (última SELECT: la imprime aplicar-migracion.mjs)
SELECT codigo, es_demo, valor_anterior, valor_nuevo,
       ROUND((valor_nuevo - valor_anterior)::numeric,2) AS diferencia, respaldado_at
FROM public.combustible_estanques_valor_bkp_mig188
ORDER BY respaldado_at DESC, abs(valor_nuevo - valor_anterior) DESC;

-- ============================================================================
-- ROLLBACK (manual, solo si se necesita revertir el último lote):
--
-- UPDATE public.combustible_estanques e
--    SET valor_total_stock = b.valor_anterior, updated_at = now()
--   FROM public.combustible_estanques_valor_bkp_mig188 b
--  WHERE b.id = e.id
--    AND b.respaldado_at = (SELECT max(respaldado_at) FROM public.combustible_estanques_valor_bkp_mig188)
--    AND e.valor_total_stock IS DISTINCT FROM b.valor_anterior;
-- ============================================================================
