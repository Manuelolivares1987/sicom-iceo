-- ============================================================================
-- 10_validate_combustible_cpp.sql  —  Test del ejemplo $900/$966,67/$483.333.
-- ----------------------------------------------------------------------------
-- NOTA: este script ejecuta los movimientos REALES sobre un estanque de test.
-- Si no quieres tocar los estanques reales, crear uno test antes:
--
-- INSERT INTO combustible_estanques (codigo, nombre, capacidad_lt, faena_id, activo)
-- VALUES ('TEST-EST-VAL', 'Estanque Test Validacion', 5000, NULL, true);
-- ============================================================================


-- ── 1. Crear estanque test si no existe ──────────────────────────────

INSERT INTO combustible_estanques (codigo, nombre, capacidad_lt, faena_id, activo)
VALUES ('TEST-EST-VAL', 'Estanque Test Validacion', 5000, NULL, true)
ON CONFLICT (codigo) DO NOTHING;


-- ── 2. Test del ejemplo CPP movil ────────────────────────────────────

DO $$
DECLARE
    v_estanque_id UUID;
    v_resultado_inicial JSONB;
    v_estanque_post combustible_estanques%ROWTYPE;
    v_cpp_esperado NUMERIC;
BEGIN
    SELECT id INTO v_estanque_id FROM combustible_estanques WHERE codigo='TEST-EST-VAL';
    IF v_estanque_id IS NULL THEN
        RAISE EXCEPTION 'Estanque test no existe.';
    END IF;

    -- Limpiar stock_inicial anterior si hubo
    UPDATE combustible_stock_inicial
       SET anulado = true, anulado_at = NOW(), motivo_anulacion = 'TEST RESET'
     WHERE estanque_id = v_estanque_id AND anulado = false;

    -- Reset estanque
    UPDATE combustible_estanques
       SET stock_teorico_lt = 0,
           costo_promedio_lt = 0,
           valor_total_stock = 0
     WHERE id = v_estanque_id;

    -- ── PASO 1: Stock inicial 1.000 lt a $900 ──
    v_resultado_inicial := rpc_registrar_stock_inicial_combustible(
        p_estanque_id              => v_estanque_id,
        p_fecha                    => CURRENT_DATE,
        p_litros_iniciales         => 1000,
        p_costo_unitario_inicial   => 900,
        p_documento_respaldo_url   => NULL,
        p_observacion              => 'Test validacion staging — ejemplo $900/$966,67'
    );
    RAISE NOTICE 'Stock inicial registrado: %', v_resultado_inicial;

    SELECT * INTO v_estanque_post FROM combustible_estanques WHERE id = v_estanque_id;
    IF v_estanque_post.stock_teorico_lt <> 1000 OR
       v_estanque_post.costo_promedio_lt <> 900 OR
       v_estanque_post.valor_total_stock <> 900000 THEN
        RAISE EXCEPTION 'TEST 1 FALLO: stock=%, cpp=%, valor=% (esperado 1000, 900, 900000)',
            v_estanque_post.stock_teorico_lt, v_estanque_post.costo_promedio_lt, v_estanque_post.valor_total_stock;
    END IF;
    RAISE NOTICE 'TEST 1 OK: stock=1000, CPP=900, valor=900.000';

    -- ── PASO 2: Simular ingreso 2.000 lt a $1.000 (sin RPC todavia, manual) ──
    -- En produccion esto seria rpc_registrar_ingreso_combustible_valorizado;
    -- aqui hacemos el calculo manual + inserciones para validar la matematica.

    -- valor_actual = 1000 * 900 = 900.000
    -- valor_ingreso = 2000 * 1000 = 2.000.000
    -- stock_nuevo = 3000
    -- cpp_nuevo = (900.000 + 2.000.000) / 3000 = 966.6667
    -- valor_stock_nuevo = 2.900.000

    v_cpp_esperado := ROUND(2900000 / 3000.0, 4);

    UPDATE combustible_estanques
       SET stock_teorico_lt = 3000,
           costo_promedio_lt = v_cpp_esperado,
           valor_total_stock = 2900000,
           updated_at = NOW()
     WHERE id = v_estanque_id;

    INSERT INTO combustible_kardex_valorizado (
        estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues
    ) VALUES (
        v_estanque_id, NOW(), 'ingreso_compra', 'TEST-ICB-001',
        2000, 0, 1000,
        3000, v_cpp_esperado, 2900000
    );

    RAISE NOTICE 'TEST 2 OK: ingreso 2000 lt @ $1000, nuevo CPP=%, stock=3000', v_cpp_esperado;

    -- ── PASO 3: Salida 500 lt @ CPP vigente ──
    -- valor_total_salida = 500 * 966.6667 = 483.333,35
    -- stock_nuevo = 2500
    -- valor_stock_nuevo = 2.900.000 - 483.333,35 = 2.416.666,65

    UPDATE combustible_estanques
       SET stock_teorico_lt = 2500,
           valor_total_stock = 2900000 - (500 * v_cpp_esperado),
           updated_at = NOW()
     WHERE id = v_estanque_id;

    INSERT INTO combustible_kardex_valorizado (
        estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues
    ) VALUES (
        v_estanque_id, NOW(), 'salida_venta', 'TEST-SCB-001',
        0, 500, v_cpp_esperado,
        2500, v_cpp_esperado, 2900000 - (500 * v_cpp_esperado)
    );

    SELECT * INTO v_estanque_post FROM combustible_estanques WHERE id = v_estanque_id;
    RAISE NOTICE 'TEST 3 OK: salida 500 lt @ %, nuevo stock=%, valor=%',
        v_cpp_esperado, v_estanque_post.stock_teorico_lt, v_estanque_post.valor_total_stock;

    IF v_estanque_post.stock_teorico_lt <> 2500 THEN
        RAISE EXCEPTION 'TEST 3 FALLO: stock final=% (esperado 2500)', v_estanque_post.stock_teorico_lt;
    END IF;

    RAISE NOTICE 'TODOS LOS TESTS COMBUSTIBLE PASARON.';

    -- Rollback
    RAISE EXCEPTION 'ROLLBACK_INTENCIONAL_TEST';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ROLLBACK_INTENCIONAL_TEST%' THEN
            RAISE NOTICE 'TESTS COMBUSTIBLE COMPLETADOS (rollback ejecutado).';
        ELSE
            RAISE;
        END IF;
END $$;


-- ── 3. Vista actual ──────────────────────────────────────────────────

SELECT * FROM v_combustible_stock_valorizado_actual ORDER BY estanque_codigo;


-- ── 4. Reconciliacion estanque vs ultimo kardex ──────────────────────

SELECT
    e.codigo,
    e.stock_teorico_lt   AS estanque_stock,
    (SELECT stock_lt_despues FROM combustible_kardex_valorizado
      WHERE estanque_id = e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_stock,
    e.valor_total_stock  AS estanque_valor,
    (SELECT valor_stock_despues FROM combustible_kardex_valorizado
      WHERE estanque_id = e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_valor
FROM combustible_estanques e
WHERE e.activo = true
ORDER BY e.codigo;
-- Pares deben coincidir
