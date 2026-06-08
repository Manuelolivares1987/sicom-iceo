-- ============================================================================
-- SICOM-ICEO | Migracion 133 — Modo DEMO para combustible Franke
-- ----------------------------------------------------------------------------
-- Permite PROBAR el flujo completo (carga, trasvasije, despacho, venta) con
-- camiones DEMO aislados, usando los MISMOS RPC reales (asi se prueba de verdad),
-- pero sin tocar los estanques/camiones reales. Todo lo demo se puede borrar.
--
--   - Columna es_demo en combustible_estanques.
--   - 2 camiones DEMO (moviles, operacion Franke) con stock inicial para probar.
--   - rpc_limpiar_demos_franke(): borra TODO movimiento demo y resetea el stock.
-- IDEMPOTENTE.
-- ============================================================================

ALTER TABLE combustible_estanques ADD COLUMN IF NOT EXISTS es_demo BOOLEAN NOT NULL DEFAULT false;

-- 2 camiones DEMO con stock inicial (para poder despachar/vender/trasvasijar).
INSERT INTO combustible_estanques
    (codigo, nombre, capacidad_lt, tipo, patente, operacion, es_demo,
     stock_teorico_lt, costo_promedio_lt, valor_total_stock, activo)
SELECT v.codigo, v.nombre, 20000, 'movil', v.patente, 'Franke', true,
       20000, 800, 20000*800, true
FROM (VALUES
    ('CAM-DEMO-1', 'Camión DEMO 1 (pruebas)', 'DEMO-01'),
    ('CAM-DEMO-2', 'Camión DEMO 2 (pruebas)', 'DEMO-02')
) AS v(codigo, nombre, patente)
WHERE NOT EXISTS (SELECT 1 FROM combustible_estanques e WHERE e.codigo = v.codigo);

-- RPC: borrar todos los datos demo y resetear el stock de los camiones demo.
CREATE OR REPLACE FUNCTION rpc_limpiar_demos_franke()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rol  TEXT := fn_user_rol();
    v_ids  UUID[];
    v_k INT := 0; v_v INT := 0; v_c INT := 0; v_t INT := 0; v_va INT := 0;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones') THEN
        RAISE EXCEPTION 'Solo admin/supervisor puede borrar datos demo. Rol: %', v_rol;
    END IF;

    SELECT array_agg(id) INTO v_ids FROM combustible_estanques WHERE es_demo = true;
    IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN
        RETURN jsonb_build_object('mensaje', 'No hay camiones demo.');
    END IF;

    -- Borrar movimientos demo (hijos primero por seguridad de FKs).
    DELETE FROM combustible_ventas_franke WHERE estanque_movil_id = ANY(v_ids);
    GET DIAGNOSTICS v_v = ROW_COUNT;
    DELETE FROM combustible_cargas_camion WHERE estanque_movil_id = ANY(v_ids);
    GET DIAGNOSTICS v_c = ROW_COUNT;

    BEGIN DELETE FROM combustible_despachos_sellos ds
          USING combustible_kardex_valorizado k
          WHERE ds.movimiento_id = k.id AND k.estanque_id = ANY(v_ids);
    EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

    BEGIN DELETE FROM combustible_traspasos
          WHERE estanque_origen_id = ANY(v_ids) OR estanque_destino_id = ANY(v_ids);
          GET DIAGNOSTICS v_t = ROW_COUNT;
    EXCEPTION WHEN undefined_table THEN NULL; END;

    BEGIN DELETE FROM combustible_varillaje WHERE estanque_id = ANY(v_ids);
          GET DIAGNOSTICS v_va = ROW_COUNT;
    EXCEPTION WHEN undefined_table THEN NULL; END;

    BEGIN DELETE FROM combustible_recirculaciones WHERE estanque_id = ANY(v_ids);
    EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM combustible_movimientos WHERE estanque_id = ANY(v_ids);
    EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM combustible_stock_inicial WHERE estanque_id = ANY(v_ids);
    EXCEPTION WHEN undefined_table THEN NULL; END;

    DELETE FROM combustible_kardex_valorizado WHERE estanque_id = ANY(v_ids);
    GET DIAGNOSTICS v_k = ROW_COUNT;

    -- Resetear stock de los camiones demo para volver a probar.
    UPDATE combustible_estanques
       SET stock_teorico_lt = 20000, costo_promedio_lt = 800, valor_total_stock = 20000*800,
           updated_at = NOW()
     WHERE id = ANY(v_ids);

    RETURN jsonb_build_object('ok', true, 'camiones_demo', array_length(v_ids,1),
        'kardex', v_k, 'ventas', v_v, 'cargas', v_c, 'traspasos', v_t, 'varillaje', v_va);
END $$;
GRANT EXECUTE ON FUNCTION rpc_limpiar_demos_franke TO authenticated;

SELECT (SELECT count(*) FROM combustible_estanques WHERE es_demo) AS camiones_demo,
       (SELECT count(*) FROM pg_proc WHERE proname='rpc_limpiar_demos_franke') AS rpc;
