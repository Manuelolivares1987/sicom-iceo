-- ============================================================================
-- smoke_test_41_combustible_sellos.sql
-- ----------------------------------------------------------------------------
-- Smoke runtime de MIG41: despacho combustible con sellos.
-- Registra 1 despacho pequeno (3 lt) sobre el estanque con mayor stock.
-- Cada corrida agrega 1 fila a combustible_despachos_sellos + saca 3 lt.
--
-- NO TOCA STOCK_BODEGA NI FIFO PRODUCTOS.
-- ============================================================================

DROP TABLE IF EXISTS smoke_41_resultados;
CREATE TEMP TABLE smoke_41_resultados (
    paso       TEXT PRIMARY KEY,
    ok         BOOLEAN NOT NULL,
    detalle    TEXT,
    extra_json JSONB
);


DO $$
DECLARE
    v_admin_id        UUID;
    v_estanque_id     UUID;
    v_estanque_cod    VARCHAR;
    v_stock_ini       NUMERIC;
    v_cpp_ini         NUMERIC;
    v_resp            JSONB;
    v_despacho_id     UUID;
    v_mov_id          UUID;
    v_folio           TEXT;
    v_stock_post      NUMERIC;
    v_litros_test     NUMERIC := 3;

    -- Snapshots globales
    v_stock_bod_ini   NUMERIC; v_stock_bod_fin   NUMERIC;
    v_capas_ini       INT;     v_capas_fin       INT;
    v_cuadrado_ini    INT;     v_cuadrado_fin    INT;
    v_desviado_ini    INT;     v_desviado_fin    INT;
BEGIN
    -- 01 Precheck
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_despacho_combustible_con_sellos') THEN
        RAISE EXCEPTION 'STOP - MIG41 no aplicada';
    END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '01_precheck_mig41', TRUE,
        'RPC despacho con sellos presente', '{}'::jsonb
    );

    -- 02 Snapshot global ini
    SELECT COALESCE(SUM(cantidad),0) INTO v_stock_bod_ini FROM stock_bodega;
    SELECT COUNT(*) INTO v_capas_ini FROM inventario_capas WHERE estado='disponible';
    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_ini, v_desviado_ini
      FROM v_bodega_reconciliacion_stock_fifo;
    INSERT INTO smoke_41_resultados VALUES (
        '02_snapshot_global_ini',
        v_desviado_ini = 0,
        format('cuadrado=%s desviado=%s capas=%s stock_bod=%s',
               v_cuadrado_ini, v_desviado_ini, v_capas_ini, v_stock_bod_ini),
        jsonb_build_object('cuadrado', v_cuadrado_ini, 'desviado', v_desviado_ini)
    );

    -- 03 Impostar admin
    SELECT id INTO v_admin_id FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'STOP - sin admin'; END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    IF auth.uid() <> v_admin_id THEN RAISE EXCEPTION 'STOP - impostor fallo'; END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '03_admin_impostado', TRUE, 'auth.uid()=admin OK',
        jsonb_build_object('admin_id', v_admin_id)
    );

    -- 04 Elegir estanque con stock suficiente (>= 3 lt)
    SELECT id, codigo, stock_teorico_lt, costo_promedio_lt
      INTO v_estanque_id, v_estanque_cod, v_stock_ini, v_cpp_ini
      FROM combustible_estanques
     WHERE activo=true AND stock_teorico_lt >= v_litros_test
     ORDER BY stock_teorico_lt DESC LIMIT 1;
    IF v_estanque_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay estanque con stock >= % lt', v_litros_test;
    END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '04_elegir_estanque', TRUE,
        format('Estanque %s: stock=%s lt, CPP=%s', v_estanque_cod, v_stock_ini, v_cpp_ini),
        jsonb_build_object('estanque', v_estanque_cod, 'stock', v_stock_ini, 'cpp', v_cpp_ini)
    );

    -- 05 Registrar despacho con sellos
    BEGIN
        v_resp := rpc_registrar_despacho_combustible_con_sellos(
            p_estanque_id     => v_estanque_id,
            p_litros          => v_litros_test,
            p_destino_tipo    => 'consumo_interno',
            p_sello_inicial   => 'SLI-SMOKE-' || extract(epoch from now())::bigint::text,
            p_sello_final     => 'SLF-SMOKE-' || extract(epoch from now())::bigint::text,
            p_motivo          => 'Smoke MIG41 despacho con sellos',
            p_receptor_nombre => 'Receptor Test',
            p_receptor_rut    => '11.111.111-1',
            p_observacion     => 'Smoke MIG41 despacho'
        );
        v_despacho_id := (v_resp->>'despacho_id')::UUID;
        v_mov_id      := (v_resp->>'movimiento_id')::UUID;
        v_folio       := v_resp->>'folio_movimiento';
        v_stock_post  := (v_resp->>'stock_final')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO smoke_41_resultados VALUES (
            '05_despacho_con_sellos', FALSE,
            'Fallo: ' || SQLERRM, jsonb_build_object('sqlerrm', SQLERRM)
        );
        RAISE;
    END;

    INSERT INTO smoke_41_resultados VALUES (
        '05_despacho_con_sellos',
        v_despacho_id IS NOT NULL AND v_mov_id IS NOT NULL AND v_stock_post = v_stock_ini - v_litros_test,
        format('despacho_id=%s mov_id=%s folio=%s stock %s->%s',
               v_despacho_id, v_mov_id, v_folio, v_stock_ini, v_stock_post),
        jsonb_build_object(
            'despacho_id', v_despacho_id,
            'movimiento_id', v_mov_id,
            'folio', v_folio,
            'stock_post', v_stock_post,
            'cpp_usado', v_resp->>'cpp_usado',
            'costo_total', v_resp->>'costo_total'
        )
    );

    -- 06 Verificar fila en combustible_despachos_sellos
    IF NOT EXISTS (
        SELECT 1 FROM combustible_despachos_sellos
         WHERE id = v_despacho_id
           AND movimiento_combustible_id = v_mov_id
           AND destino_tipo = 'consumo_interno'
           AND litros_despachados = v_litros_test
           AND sello_inicial LIKE 'SLI-SMOKE-%'
           AND sello_final LIKE 'SLF-SMOKE-%'
    ) THEN
        INSERT INTO smoke_41_resultados VALUES (
            '06_fila_despachos_sellos', FALSE,
            'Fila no encontrada o mal construida',
            jsonb_build_object('despacho_id', v_despacho_id)
        );
        RAISE EXCEPTION 'fila sellos mal';
    END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '06_fila_despachos_sellos', TRUE,
        'Fila correcta en combustible_despachos_sellos con sellos + mov_id',
        jsonb_build_object('despacho_id', v_despacho_id)
    );

    -- 07 Verificar kardex valorizado linkado
    IF NOT EXISTS (
        SELECT 1 FROM combustible_kardex_valorizado
         WHERE id = v_mov_id
           AND tipo_movimiento = 'salida_despacho'
           AND litros_salida = v_litros_test
    ) THEN
        INSERT INTO smoke_41_resultados VALUES (
            '07_kardex_linkado', FALSE,
            'Kardex no encontrado o mal',
            jsonb_build_object('mov_id', v_mov_id)
        );
        RAISE EXCEPTION 'kardex mal';
    END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '07_kardex_linkado', TRUE,
        'Kardex tipo=salida_despacho linkado correctamente',
        jsonb_build_object('mov_id', v_mov_id)
    );

    -- 08 Verificar vista v_combustible_despachos_con_sellos retorna la fila
    IF NOT EXISTS (
        SELECT 1 FROM v_combustible_despachos_con_sellos
         WHERE despacho_id = v_despacho_id
    ) THEN
        INSERT INTO smoke_41_resultados VALUES (
            '08_vista_despachos', FALSE,
            'Vista no retorna el despacho',
            jsonb_build_object('despacho_id', v_despacho_id)
        );
        RAISE EXCEPTION 'vista mal';
    END IF;
    INSERT INTO smoke_41_resultados VALUES (
        '08_vista_despachos', TRUE,
        'Vista retorna el despacho con joins',
        jsonb_build_object('despacho_id', v_despacho_id)
    );

    -- 09 Snapshot global final + asserts inventario productos
    SELECT COALESCE(SUM(cantidad),0) INTO v_stock_bod_fin FROM stock_bodega;
    SELECT COUNT(*) INTO v_capas_fin FROM inventario_capas WHERE estado='disponible';
    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_fin, v_desviado_fin
      FROM v_bodega_reconciliacion_stock_fifo;

    INSERT INTO smoke_41_resultados VALUES (
        '09_no_toco_stock_bodega',
        v_stock_bod_fin = v_stock_bod_ini,
        format('stock_bodega %s -> %s (esperado igual)', v_stock_bod_ini, v_stock_bod_fin),
        jsonb_build_object('ini', v_stock_bod_ini, 'fin', v_stock_bod_fin)
    );
    INSERT INTO smoke_41_resultados VALUES (
        '10_no_toco_capas_fifo',
        v_capas_fin = v_capas_ini,
        format('capas %s -> %s', v_capas_ini, v_capas_fin),
        jsonb_build_object('ini', v_capas_ini, 'fin', v_capas_fin)
    );
    INSERT INTO smoke_41_resultados VALUES (
        '11_reconciliacion_intacta',
        v_cuadrado_fin = v_cuadrado_ini AND v_desviado_fin = 0,
        format('cuadrado %s->%s desviado %s->%s',
               v_cuadrado_ini, v_cuadrado_fin, v_desviado_ini, v_desviado_fin),
        jsonb_build_object('cuadrado_fin', v_cuadrado_fin, 'desviado_fin', v_desviado_fin)
    );

    RAISE NOTICE '== Smoke MIG41 finalizado. SELECT * FROM smoke_41_resultados ORDER BY paso; ==';
END $$;


SELECT paso, ok, detalle, extra_json FROM smoke_41_resultados ORDER BY paso;


-- Verificacion complementaria: ultimo despacho con sellos
SELECT 'ultimo_despacho_smoke' AS dx,
       despacho_id, fecha, estanque_codigo, folio_movimiento,
       litros, costo_total, destino_tipo,
       sello_inicial, sello_final, receptor_nombre
  FROM v_combustible_despachos_con_sellos
 WHERE observacion ILIKE '%Smoke MIG41%'
 ORDER BY fecha DESC LIMIT 1;


-- ============================================================================
-- CLEANUP MANUAL (opcional — cada corrida agrega 1 despacho y saca 3 lt)
-- ----------------------------------------------------------------------------
-- BEGIN;
-- -- Listar:
-- SELECT id, estanque_id, litros_despachados, observacion, created_at
--   FROM combustible_despachos_sellos
--  WHERE observacion ILIKE '%Smoke MIG41%';
--
-- -- Revertir stock (cada corrida saco 3 lt):
-- -- UPDATE combustible_estanques
-- --    SET stock_teorico_lt = stock_teorico_lt + 3,
-- --        valor_total_stock = valor_total_stock + (3 * costo_promedio_lt),
-- --        updated_at = NOW()
-- --  WHERE id = '<estanque_smoke>';
--
-- -- DELETE FROM combustible_despachos_sellos WHERE observacion ILIKE '%Smoke MIG41%';
-- -- DELETE FROM combustible_kardex_valorizado WHERE observacion ILIKE '%Smoke MIG41%';
-- ROLLBACK;
-- ============================================================================
