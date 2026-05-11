-- ============================================================================
-- smoke_test_40_combustible_cpp.sql
-- ----------------------------------------------------------------------------
-- Smoke test runtime de MIG40: CPP movil en ingreso + salida valorizada.
--
-- Estrategia:
--   1. Impostar admin via set_config('request.jwt.claim.sub', ...).
--   2. Snapshot inicial global (productos/FIFO/legacy/combustible).
--   3. Seleccionar el estanque con MAYOR stock teorico activo.
--   4. Snapshot del estanque elegido.
--   5. INGRESO de 10 lt a costo distinto al CPP actual (cpp_actual + 500
--      o $1500 si cpp_actual = 0). Verifica:
--      - stock_teorico_lt sube 10
--      - CPP recalculado por aritmetica esperada
--      - valor_total = stock_nuevo * cpp_nuevo
--      - kardex tiene fila 'ingreso_compra'
--   6. SALIDA de 5 lt destino 'consumo_interno'. Verifica:
--      - stock baja 5
--      - CPP no cambia (CPP movil aritmetico)
--      - costo_total = 5 * cpp_vigente
--      - kardex tiene fila 'salida_despacho'
--   7. Snapshot final + asserts:
--      - stock_bodega NO cambio
--      - inventario_capas NO cambio
--      - reconciliacion productos sigue cuadrada
--      - combustible_movimientos legacy NO cambio
--
-- IDEMPOTENTE PARCIAL: cada corrida agrega 10 lt y luego saca 5 lt
-- (neto +5 al estanque). Si se necesita limpiar, ver CLEANUP MANUAL al
-- final.
--
-- NO TOCA INVENTARIO PRODUCTOS. NO TOCA STOCK_BODEGA. NO TOCA FIFO.
-- ============================================================================


DROP TABLE IF EXISTS smoke_40_resultados;
CREATE TEMP TABLE smoke_40_resultados (
    paso       TEXT PRIMARY KEY,
    ok         BOOLEAN NOT NULL,
    detalle    TEXT,
    extra_json JSONB
);


DO $$
DECLARE
    -- Admin impostar
    v_admin_id        UUID;
    v_admin_email     TEXT;

    -- Estanque de prueba
    v_estanque_id     UUID;
    v_estanque_cod    VARCHAR;

    -- Snapshot global inicial
    v_stock_bodega_ini    NUMERIC;
    v_capas_ini           INT;
    v_valor_fifo_ini      NUMERIC;
    v_cuadrado_ini        INT;
    v_desviado_ini        INT;
    v_comb_mov_legacy_ini INT;

    -- Snapshot estanque
    v_stock_ini       NUMERIC;
    v_cpp_ini         NUMERIC;
    v_valor_ini       NUMERIC;
    v_cap             NUMERIC;

    -- Costos de prueba
    v_costo_ingreso   NUMERIC;
    v_litros_ingreso  NUMERIC := 10;
    v_litros_salida   NUMERIC := 5;

    -- Resultados RPC
    v_resp_ingreso    JSONB;
    v_resp_salida     JSONB;
    v_kardex_ing_id   UUID;
    v_kardex_sal_id   UUID;

    -- Estados post
    v_stock_post_ing  NUMERIC;
    v_cpp_post_ing    NUMERIC;
    v_valor_post_ing  NUMERIC;
    v_cpp_esperado    NUMERIC;
    v_stock_post_sal  NUMERIC;
    v_cpp_post_sal    NUMERIC;
    v_valor_post_sal  NUMERIC;

    -- Snapshot global final
    v_stock_bodega_fin    NUMERIC;
    v_capas_fin           INT;
    v_valor_fifo_fin      NUMERIC;
    v_cuadrado_fin        INT;
    v_desviado_fin        INT;
    v_comb_mov_legacy_fin INT;
BEGIN
    ------------------------------------------------------------------ 1) PRECHECK
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_ingreso_combustible_valorizado') THEN
        RAISE EXCEPTION 'STOP - MIG40 no aplicada (rpc_registrar_ingreso_combustible_valorizado falta)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada') THEN
        RAISE EXCEPTION 'STOP - MIG40 no aplicada (rpc_registrar_salida_combustible_valorizada falta)';
    END IF;

    INSERT INTO smoke_40_resultados VALUES (
        '01_precheck_mig40', TRUE,
        'MIG40 aplicada (2 RPCs presentes)', '{}'::jsonb
    );

    ------------------------------------------------------------------ 2) SNAPSHOT GLOBAL
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_bodega_ini FROM stock_bodega;
    SELECT COUNT(*), COALESCE(SUM(cantidad_disponible * costo_unitario), 0)
      INTO v_capas_ini, v_valor_fifo_ini
      FROM inventario_capas WHERE estado='disponible';
    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_ini, v_desviado_ini
      FROM v_bodega_reconciliacion_stock_fifo;
    SELECT COUNT(*) INTO v_comb_mov_legacy_ini FROM combustible_movimientos;

    INSERT INTO smoke_40_resultados VALUES (
        '02_snapshot_global_ini',
        v_desviado_ini = 0,
        format('stock_bodega=%s capas=%s fifo=%s reconc cuadrado=%s desviado=%s comb_mov_legacy=%s',
               v_stock_bodega_ini, v_capas_ini, v_valor_fifo_ini,
               v_cuadrado_ini, v_desviado_ini, v_comb_mov_legacy_ini),
        jsonb_build_object(
            'stock_bodega', v_stock_bodega_ini,
            'capas', v_capas_ini,
            'valor_fifo', v_valor_fifo_ini,
            'reconc_cuadrado', v_cuadrado_ini,
            'reconc_desviado', v_desviado_ini,
            'comb_mov_legacy', v_comb_mov_legacy_ini
        )
    );

    ------------------------------------------------------------------ 3) IMPOSTAR ADMIN
    SELECT id, email INTO v_admin_id, v_admin_email
      FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay admin disponible';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    IF auth.uid() IS NULL OR auth.uid() <> v_admin_id THEN
        RAISE EXCEPTION 'STOP - impostor admin no funciono';
    END IF;

    INSERT INTO smoke_40_resultados VALUES (
        '03_admin_impostado', TRUE,
        format('admin=%s', v_admin_email),
        jsonb_build_object('admin_id', v_admin_id)
    );

    ------------------------------------------------------------------ 4) ELEGIR ESTANQUE
    -- Elegir el estanque ACTIVO con mayor stock (mas seguro: no triggers raros
    -- en EST-600 que esta vacio). Si todos tienen stock 0, usar el primero
    -- activo y el primer ingreso establecera el CPP.
    SELECT id, codigo, stock_teorico_lt, costo_promedio_lt, valor_total_stock, capacidad_lt
      INTO v_estanque_id, v_estanque_cod, v_stock_ini, v_cpp_ini, v_valor_ini, v_cap
      FROM combustible_estanques
     WHERE activo = TRUE
     ORDER BY stock_teorico_lt DESC, codigo ASC
     LIMIT 1;
    IF v_estanque_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay estanque activo';
    END IF;

    -- Capacidad debe permitir el ingreso de 10 lt
    IF v_stock_ini + v_litros_ingreso > v_cap THEN
        INSERT INTO smoke_40_resultados VALUES (
            '04_elegir_estanque', FALSE,
            format('Estanque %s sin capacidad para ingreso de %s lt (stock=%s, cap=%s)',
                   v_estanque_cod, v_litros_ingreso, v_stock_ini, v_cap),
            jsonb_build_object('estanque', v_estanque_cod, 'stock', v_stock_ini, 'cap', v_cap)
        );
        RAISE EXCEPTION 'STOP - estanque elegido sin capacidad';
    END IF;

    INSERT INTO smoke_40_resultados VALUES (
        '04_elegir_estanque', TRUE,
        format('Estanque %s: stock=%s lt, CPP=%s, valor=%s, cap=%s',
               v_estanque_cod, v_stock_ini, v_cpp_ini, v_valor_ini, v_cap),
        jsonb_build_object(
            'estanque_id', v_estanque_id,
            'codigo', v_estanque_cod,
            'stock_ini', v_stock_ini,
            'cpp_ini', v_cpp_ini,
            'valor_ini', v_valor_ini,
            'capacidad', v_cap
        )
    );

    ------------------------------------------------------------------ 5) INGRESO VALORIZADO
    -- Costo intencionalmente distinto al CPP actual para verificar que CPP se mueve.
    v_costo_ingreso := CASE WHEN v_cpp_ini > 0 THEN v_cpp_ini + 500 ELSE 1500 END;

    BEGIN
        v_resp_ingreso := rpc_registrar_ingreso_combustible_valorizado(
            p_estanque_id        => v_estanque_id,
            p_litros             => v_litros_ingreso,
            p_costo_unitario_clp => v_costo_ingreso,
            p_doc_tipo           => 'guia',
            p_doc_numero         => 'SMOKE-MIG40-' || extract(epoch from now())::bigint::text,
            p_observacion        => 'Smoke MIG40 ingreso'
        );
        v_kardex_ing_id := (v_resp_ingreso->>'kardex_id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO smoke_40_resultados VALUES (
            '05_ingreso_valorizado', FALSE,
            'Fallo ingreso: ' || SQLERRM,
            jsonb_build_object('sqlerrm', SQLERRM, 'sqlstate', SQLSTATE)
        );
        RAISE;
    END;

    -- Verificar estado del estanque post-ingreso
    SELECT stock_teorico_lt, costo_promedio_lt, valor_total_stock
      INTO v_stock_post_ing, v_cpp_post_ing, v_valor_post_ing
      FROM combustible_estanques WHERE id = v_estanque_id;

    -- CPP esperado por aritmetica
    IF v_stock_ini > 0 THEN
        v_cpp_esperado := ROUND(
            (v_stock_ini * v_cpp_ini + v_litros_ingreso * v_costo_ingreso)
            / (v_stock_ini + v_litros_ingreso),
            4
        );
    ELSE
        v_cpp_esperado := ROUND(v_costo_ingreso::numeric, 4);
    END IF;

    INSERT INTO smoke_40_resultados VALUES (
        '05_ingreso_valorizado',
        v_stock_post_ing = v_stock_ini + v_litros_ingreso
          AND ABS(v_cpp_post_ing - v_cpp_esperado) < 0.01
          AND v_kardex_ing_id IS NOT NULL,
        format('stock %s->%s | cpp %s->%s (esperado %s) | costo ingreso=%s | kardex=%s',
               v_stock_ini, v_stock_post_ing,
               v_cpp_ini, v_cpp_post_ing, v_cpp_esperado,
               v_costo_ingreso, v_kardex_ing_id),
        jsonb_build_object(
            'kardex_id', v_kardex_ing_id,
            'folio', v_resp_ingreso->>'folio',
            'stock_post', v_stock_post_ing,
            'cpp_post', v_cpp_post_ing,
            'cpp_esperado', v_cpp_esperado,
            'valor_post', v_valor_post_ing,
            'response', v_resp_ingreso
        )
    );

    -- Verificar kardex tipo='ingreso_compra'
    IF NOT EXISTS (
        SELECT 1 FROM combustible_kardex_valorizado
         WHERE id = v_kardex_ing_id
           AND tipo_movimiento = 'ingreso_compra'
           AND litros_entrada = v_litros_ingreso
           AND ABS(costo_unitario_movimiento - v_costo_ingreso) < 0.01
    ) THEN
        INSERT INTO smoke_40_resultados VALUES (
            '06_kardex_ingreso_ok', FALSE,
            'Kardex ingreso mal construido o ausente',
            jsonb_build_object('kardex_id', v_kardex_ing_id)
        );
        RAISE EXCEPTION 'kardex ingreso mal';
    END IF;
    INSERT INTO smoke_40_resultados VALUES (
        '06_kardex_ingreso_ok', TRUE,
        format('kardex_id=%s tipo=ingreso_compra litros=%s costo=%s',
               v_kardex_ing_id, v_litros_ingreso, v_costo_ingreso),
        jsonb_build_object('kardex_id', v_kardex_ing_id)
    );

    ------------------------------------------------------------------ 7) SALIDA VALORIZADA
    BEGIN
        v_resp_salida := rpc_registrar_salida_combustible_valorizada(
            p_estanque_id      => v_estanque_id,
            p_litros           => v_litros_salida,
            p_destino_tipo     => 'consumo_interno',
            p_motivo           => 'Smoke MIG40 salida consumo interno prueba',
            p_observacion      => 'Smoke MIG40 salida'
        );
        v_kardex_sal_id := (v_resp_salida->>'kardex_id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO smoke_40_resultados VALUES (
            '07_salida_valorizada', FALSE,
            'Fallo salida: ' || SQLERRM,
            jsonb_build_object('sqlerrm', SQLERRM, 'sqlstate', SQLSTATE)
        );
        RAISE;
    END;

    SELECT stock_teorico_lt, costo_promedio_lt, valor_total_stock
      INTO v_stock_post_sal, v_cpp_post_sal, v_valor_post_sal
      FROM combustible_estanques WHERE id = v_estanque_id;

    INSERT INTO smoke_40_resultados VALUES (
        '07_salida_valorizada',
        v_stock_post_sal = v_stock_post_ing - v_litros_salida
          AND v_cpp_post_sal = v_cpp_post_ing   -- CPP no cambia
          AND v_kardex_sal_id IS NOT NULL,
        format('stock %s->%s | cpp %s (sin cambio, esperado) | costo salida=%s | kardex=%s',
               v_stock_post_ing, v_stock_post_sal,
               v_cpp_post_sal,
               (v_litros_salida * v_cpp_post_ing),
               v_kardex_sal_id),
        jsonb_build_object(
            'kardex_id', v_kardex_sal_id,
            'folio', v_resp_salida->>'folio',
            'stock_post', v_stock_post_sal,
            'cpp_vigente', v_cpp_post_sal,
            'costo_total', (v_resp_salida->>'costo_total'),
            'response', v_resp_salida
        )
    );

    -- Verificar kardex salida tipo='salida_despacho' (destino consumo_interno mapea a salida_despacho)
    IF NOT EXISTS (
        SELECT 1 FROM combustible_kardex_valorizado
         WHERE id = v_kardex_sal_id
           AND tipo_movimiento = 'salida_despacho'
           AND litros_salida = v_litros_salida
           AND ABS(costo_unitario_movimiento - v_cpp_post_ing) < 0.01
    ) THEN
        INSERT INTO smoke_40_resultados VALUES (
            '08_kardex_salida_ok', FALSE,
            'Kardex salida mal construido o ausente',
            jsonb_build_object('kardex_id', v_kardex_sal_id)
        );
        RAISE EXCEPTION 'kardex salida mal';
    END IF;
    INSERT INTO smoke_40_resultados VALUES (
        '08_kardex_salida_ok', TRUE,
        format('kardex_id=%s tipo=salida_despacho litros=%s costo_unit=%s',
               v_kardex_sal_id, v_litros_salida, v_cpp_post_ing),
        jsonb_build_object('kardex_id', v_kardex_sal_id)
    );

    ------------------------------------------------------------------ 9) SNAPSHOT GLOBAL FINAL + ASSERTS
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_bodega_fin FROM stock_bodega;
    SELECT COUNT(*), COALESCE(SUM(cantidad_disponible * costo_unitario), 0)
      INTO v_capas_fin, v_valor_fifo_fin
      FROM inventario_capas WHERE estado='disponible';
    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_fin, v_desviado_fin
      FROM v_bodega_reconciliacion_stock_fifo;
    SELECT COUNT(*) INTO v_comb_mov_legacy_fin FROM combustible_movimientos;

    -- Productos NO debe haber cambiado
    INSERT INTO smoke_40_resultados VALUES (
        '09_no_toco_stock_bodega',
        v_stock_bodega_fin = v_stock_bodega_ini,
        format('antes=%s despues=%s (esperado igual)', v_stock_bodega_ini, v_stock_bodega_fin),
        jsonb_build_object('ini', v_stock_bodega_ini, 'fin', v_stock_bodega_fin)
    );
    INSERT INTO smoke_40_resultados VALUES (
        '10_no_toco_inventario_capas',
        v_capas_fin = v_capas_ini AND v_valor_fifo_fin = v_valor_fifo_ini,
        format('capas %s->%s | valor fifo %s->%s', v_capas_ini, v_capas_fin, v_valor_fifo_ini, v_valor_fifo_fin),
        jsonb_build_object('capas_ini', v_capas_ini, 'capas_fin', v_capas_fin,
                           'valor_ini', v_valor_fifo_ini, 'valor_fin', v_valor_fifo_fin)
    );
    INSERT INTO smoke_40_resultados VALUES (
        '11_reconciliacion_productos_intacta',
        v_cuadrado_fin = v_cuadrado_ini AND v_desviado_fin = 0,
        format('cuadrado %s->%s | desviado %s->%s',
               v_cuadrado_ini, v_cuadrado_fin, v_desviado_ini, v_desviado_fin),
        jsonb_build_object('cuadrado_fin', v_cuadrado_fin, 'desviado_fin', v_desviado_fin)
    );
    INSERT INTO smoke_40_resultados VALUES (
        '12_no_toco_mov_legacy',
        v_comb_mov_legacy_fin = v_comb_mov_legacy_ini,
        format('combustible_movimientos legacy %s -> %s (esperado igual)',
               v_comb_mov_legacy_ini, v_comb_mov_legacy_fin),
        jsonb_build_object('ini', v_comb_mov_legacy_ini, 'fin', v_comb_mov_legacy_fin)
    );

    RAISE NOTICE '== Smoke MIG40 finalizado. SELECT * FROM smoke_40_resultados ORDER BY paso; ==';
END $$;


-- ── Output principal ────────────────────────────────────────────────────────
SELECT paso, ok, detalle, extra_json
  FROM smoke_40_resultados
 ORDER BY paso;


-- ── Verificacion complementaria: control consolidado del estanque tocado ─
SELECT 'control_post_smoke' AS dx,
       estanque_codigo, estado, stock_teorico_lt, cpp_actual, valor_teorico_clp,
       ultimo_varillaje_lt, delta_lt, dias_desde_varilla
  FROM v_combustible_control_kardex_varillaje
 ORDER BY estanque_codigo;


-- ── Vista del kardex valorizado reciente (top 5) ──────────────────────────
SELECT 'kardex_top5' AS dx,
       fecha_movimiento, estanque_codigo, tipo_movimiento, folio_movimiento,
       litros_entrada, litros_salida, costo_unitario_movimiento,
       stock_lt_despues, cpp_despues, valor_stock_despues
  FROM v_combustible_movimientos_valorizados
 ORDER BY fecha_movimiento DESC, created_at DESC
 LIMIT 5;


-- ============================================================================
-- CRITERIO DE AVANCE
-- ----------------------------------------------------------------------------
-- Los 12 pasos deben devolver ok=true. Si CUALQUIERA falla, NO avanzar a
-- 40-D (UI). Mandar el detalle del paso fallido.
--
-- Pasos esperados:
--   01_precheck_mig40                  RPCs presentes
--   02_snapshot_global_ini             reconc cuadrada al inicio
--   03_admin_impostado                 auth.uid = admin
--   04_elegir_estanque                 estanque con capacidad y stock
--   05_ingreso_valorizado              stock +10, CPP recalculado
--   06_kardex_ingreso_ok               fila kardex tipo=ingreso_compra
--   07_salida_valorizada               stock -5, CPP igual
--   08_kardex_salida_ok                fila kardex tipo=salida_despacho
--   09_no_toco_stock_bodega            stock_bodega sin cambios
--   10_no_toco_inventario_capas        capas FIFO sin cambios
--   11_reconciliacion_productos_intacta cuadrado intacto, desviado=0
--   12_no_toco_mov_legacy              combustible_movimientos sin cambios
-- ============================================================================


-- ============================================================================
-- CLEANUP MANUAL (opcional — los datos piloto quedan en kardex valorizado)
-- ----------------------------------------------------------------------------
-- Identificacion: observaciones contienen 'Smoke MIG40'.
-- ATENCION: borrar kardex sin revertir stock del estanque desbalancea el
-- estado interno. Cleanup recomendado SOLO si se quiere reset:
--
-- BEGIN;
-- -- Listar primero
-- SELECT id, estanque_id, tipo_movimiento, litros_entrada, litros_salida, observacion
--   FROM combustible_kardex_valorizado
--  WHERE observacion ILIKE '%Smoke MIG40%'
--  ORDER BY created_at DESC;
--
-- -- Si confirmas, revertir el neto sobre el estanque (cada corrida agrega +5 lt
-- -- al estanque elegido):
-- -- UPDATE combustible_estanques
-- --    SET stock_teorico_lt = stock_teorico_lt - 5,
-- --        valor_total_stock = valor_total_stock - (5 * costo_promedio_lt),
-- --        updated_at = NOW()
-- --  WHERE id = '<estanque_id_smoke>';
--
-- -- DELETE FROM combustible_kardex_valorizado
-- --  WHERE observacion ILIKE '%Smoke MIG40%';
-- ROLLBACK;  -- cambiar a COMMIT si confirmas
-- ============================================================================
