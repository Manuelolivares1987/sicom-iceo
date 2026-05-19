-- ============================================================================
-- 65_ingreso_combustible_fotos.sql
-- ----------------------------------------------------------------------------
-- Extiende rpc_registrar_ingreso_combustible_valorizado (MIG40) para
-- capturar evidencia visual al recibir combustible:
--   - foto_patente_url: patente del CAMION PROVEEDOR (que descarga)
--   - foto_medidor_inicial_url: estanque antes (nivel inicial)
--   - foto_medidor_final_url: estanque despues (nivel cargado)
--
-- Las columnas ya existen en combustible_kardex_valorizado (agregadas
-- por MIG64). Esta migracion solo extiende la signature del RPC y agrega
-- validacion: las 3 fotos son OBLIGATORIAS para un ingreso (proteccion
-- legal frente al proveedor + auditoria interna).
--
-- ADITIVA, IDEMPOTENTE. Preserva signature MIG40 + 3 params al final.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado'
                      AND column_name='foto_patente_url') THEN
        RAISE EXCEPTION 'STOP - MIG64 no aplicada (faltan columnas de fotos).';
    END IF;
END $$;


-- ============================================================================
-- Reemplazar rpc_registrar_ingreso_combustible_valorizado
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_ingreso_combustible_valorizado(
    p_estanque_id        UUID,
    p_litros             NUMERIC,
    p_costo_unitario_clp NUMERIC,
    p_proveedor_id       UUID    DEFAULT NULL,
    p_doc_tipo           VARCHAR DEFAULT NULL,
    p_doc_numero         VARCHAR DEFAULT NULL,
    p_fecha_movimiento   TIMESTAMPTZ DEFAULT NULL,
    p_observacion        TEXT    DEFAULT NULL,
    p_evidencia_url      TEXT    DEFAULT NULL,
    -- NUEVO MIG65: evidencia visual
    p_foto_patente_url         TEXT DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_estanque     combustible_estanques%ROWTYPE;
    v_stock_post   NUMERIC;
    v_cpp_anterior NUMERIC;
    v_cpp_nuevo    NUMERIC;
    v_valor_anterior NUMERIC;
    v_valor_nuevo  NUMERIC;
    v_kardex_id    UUID;
    v_folio        VARCHAR;
    v_fecha        TIMESTAMPTZ;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para ingreso de combustible', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_costo_unitario_clp IS NULL OR p_costo_unitario_clp < 0 THEN
        RAISE EXCEPTION 'costo_unitario_clp debe ser >= 0';
    END IF;

    -- NUEVO MIG65: fotos obligatorias (evidencia legal frente a proveedor)
    IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DE LA PATENTE del camion proveedor.';
    END IF;
    IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DEL MEDIDOR INICIAL (antes de cargar).';
    END IF;
    IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DEL MEDIDOR FINAL (despues de cargar).';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    -- Lock estanque
    SELECT * INTO v_estanque
      FROM combustible_estanques
     WHERE id = p_estanque_id
     FOR UPDATE;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;

    v_stock_post := v_estanque.stock_teorico_lt + p_litros;
    IF v_stock_post > v_estanque.capacidad_lt THEN
        RAISE EXCEPTION 'Ingreso supera capacidad. Stock actual: % lt, capacidad: % lt, intento: % lt',
            v_estanque.stock_teorico_lt, v_estanque.capacidad_lt, p_litros;
    END IF;

    v_cpp_anterior   := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_valor_anterior := COALESCE(v_estanque.valor_total_stock, 0);

    -- CPP movil
    IF v_estanque.stock_teorico_lt > 0 THEN
        v_cpp_nuevo := ROUND(
            (v_estanque.stock_teorico_lt * v_cpp_anterior + p_litros * p_costo_unitario_clp)
            / v_stock_post, 4
        );
    ELSE
        v_cpp_nuevo := ROUND(p_costo_unitario_clp::numeric, 4);
    END IF;

    v_valor_nuevo := ROUND((v_stock_post * v_cpp_nuevo)::numeric, 2);

    -- Folio
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_ingreso_combustible') THEN
        SELECT fn_generar_folio_ingreso_combustible() INTO v_folio;
    ELSE
        v_folio := 'ICB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    -- Insert con fotos
    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        proveedor_id, documento_numero,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        foto_patente_url, foto_medidor_inicial_url, foto_medidor_final_url
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, 'ingreso_compra', v_folio,
        p_proveedor_id, p_doc_numero,
        p_litros, 0, p_costo_unitario_clp,
        v_stock_post, v_cpp_nuevo, v_valor_nuevo,
        p_evidencia_url, p_observacion, v_user_id,
        p_foto_patente_url, p_foto_medidor_inicial_url, p_foto_medidor_final_url
    );

    -- Actualizar estanque
    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_post,
           costo_promedio_lt = v_cpp_nuevo,
           valor_total_stock = v_valor_nuevo,
           updated_at        = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success', true,
        'kardex_id', v_kardex_id,
        'folio', v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_ingresados', p_litros,
        'costo_unitario_ingreso', p_costo_unitario_clp,
        'cpp_anterior', v_cpp_anterior,
        'cpp_nuevo', v_cpp_nuevo,
        'stock_anterior', v_estanque.stock_teorico_lt,
        'stock_nuevo', v_stock_post,
        'valor_anterior', v_valor_anterior,
        'valor_nuevo', v_valor_nuevo
    );
END;
$$;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'rpc_extendido', EXISTS(
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE p.proname='rpc_registrar_ingreso_combustible_valorizado'
           AND n.nspname='public'
           AND pg_get_function_arguments(p.oid) LIKE '%p_foto_patente_url%'
    )
) AS resultado;

NOTIFY pgrst, 'reload schema';
