-- ============================================================================
-- 68_ajuste_stock_foto_obligatoria.sql
-- ----------------------------------------------------------------------------
-- Refuerzo del RPC rpc_ajustar_stock_estanque (MIG67):
--   - Agrega 4 columnas a combustible_kardex_valorizado:
--       foto_ajuste_url, foto_ajuste_lat, foto_ajuste_lon, foto_ajuste_ts
--   - Foto OBLIGATORIA en el ajuste (defensa frente a auditoria: prueba
--     visual del varillaje fisico al momento del ajuste).
--   - Coordenadas GPS OBLIGATORIAS (anti-reciclaje, mismo patron MIG66).
--
-- ADITIVA, IDEMPOTENTE. Reemplaza la signature de MIG67.
-- ============================================================================

-- ── 1. Columnas nuevas en kardex ────────────────────────────────────────────
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS foto_ajuste_url TEXT,
    ADD COLUMN IF NOT EXISTS foto_ajuste_lat NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_ajuste_lon NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_ajuste_ts  TIMESTAMPTZ;

COMMENT ON COLUMN combustible_kardex_valorizado.foto_ajuste_url IS
'URL de la foto del varillaje/medidor capturada al momento del ajuste de stock (MIG68). Obligatoria para tipo_movimiento=ajuste.';


-- ── 2. Drop signature anterior (MIG67) para limpieza ────────────────────────
DROP FUNCTION IF EXISTS rpc_ajustar_stock_estanque(
    UUID, NUMERIC, TEXT, TEXT, TIMESTAMPTZ, NUMERIC
);


-- ── 3. RPC con foto obligatoria + geo ───────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_ajustar_stock_estanque(
    p_estanque_id      UUID,
    p_litros_correctos NUMERIC,
    p_motivo           TEXT,
    p_foto_url         TEXT,
    p_foto_lat         NUMERIC,
    p_foto_lon         NUMERIC,
    p_foto_ts          TIMESTAMPTZ,
    p_evidencia_url    TEXT    DEFAULT NULL,
    p_fecha_movimiento TIMESTAMPTZ DEFAULT NULL,
    p_nuevo_cpp        NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_estanque    combustible_estanques%ROWTYPE;
    v_stock_actual NUMERIC;
    v_cpp_actual  NUMERIC;
    v_delta       NUMERIC;
    v_cpp_usar    NUMERIC;
    v_valor_post  NUMERIC;
    v_kardex_id   UUID;
    v_folio       VARCHAR;
    v_fecha       TIMESTAMPTZ;
    v_litros_in   NUMERIC := 0;
    v_litros_out  NUMERIC := 0;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para ajustar stock de estanque', v_rol;
    END IF;

    IF p_litros_correctos IS NULL OR p_litros_correctos < 0 THEN
        RAISE EXCEPTION 'litros_correctos debe ser >= 0';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 10 THEN
        RAISE EXCEPTION 'motivo obligatorio (minimo 10 caracteres) para auditoria';
    END IF;
    IF p_nuevo_cpp IS NOT NULL AND p_nuevo_cpp < 0 THEN
        RAISE EXCEPTION 'nuevo_cpp debe ser >= 0';
    END IF;

    -- MIG68: foto obligatoria
    IF p_foto_url IS NULL OR length(trim(p_foto_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del varillaje/medidor obligatoria para el ajuste de stock.';
    END IF;
    IF p_foto_lat IS NULL OR p_foto_lon IS NULL THEN
        RAISE EXCEPTION 'Foto sin coordenadas GPS. Habilita la ubicacion del dispositivo.';
    END IF;
    IF p_foto_ts IS NULL THEN
        RAISE EXCEPTION 'Foto sin timestamp. Reintenta la captura.';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

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

    IF p_litros_correctos > v_estanque.capacidad_lt THEN
        RAISE EXCEPTION 'litros_correctos (% lt) supera capacidad del estanque (% lt)',
            p_litros_correctos, v_estanque.capacidad_lt;
    END IF;

    v_stock_actual := COALESCE(v_estanque.stock_teorico_lt, 0);
    v_cpp_actual   := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_delta        := p_litros_correctos - v_stock_actual;
    v_cpp_usar     := COALESCE(p_nuevo_cpp, v_cpp_actual);

    IF v_delta = 0 AND p_nuevo_cpp IS NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'sin_cambios', true,
            'estanque_codigo', v_estanque.codigo,
            'stock_actual', v_stock_actual,
            'cpp_actual',   v_cpp_actual,
            'mensaje', 'No hay diferencia entre stock actual y litros declarados.'
        );
    END IF;

    IF v_delta > 0 THEN
        v_litros_in  := v_delta; v_litros_out := 0;
    ELSIF v_delta < 0 THEN
        v_litros_in  := 0; v_litros_out := ABS(v_delta);
    ELSE
        v_litros_in  := 0; v_litros_out := 0;
    END IF;

    v_valor_post := ROUND((p_litros_correctos * v_cpp_usar)::numeric, 2);
    v_folio := 'AJU-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        foto_ajuste_url, foto_ajuste_lat, foto_ajuste_lon, foto_ajuste_ts
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, 'ajuste', v_folio,
        v_litros_in, v_litros_out, v_cpp_usar,
        p_litros_correctos, v_cpp_usar, v_valor_post,
        p_evidencia_url,
        format('[AJUSTE STOCK] delta=%s lt | motivo: %s | usuario_rol: %s',
               v_delta, trim(p_motivo), v_rol),
        v_user_id,
        p_foto_url, p_foto_lat, p_foto_lon, p_foto_ts
    );

    UPDATE combustible_estanques
       SET stock_teorico_lt  = p_litros_correctos,
           costo_promedio_lt = v_cpp_usar,
           valor_total_stock = v_valor_post,
           updated_at        = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success', true,
        'sin_cambios', false,
        'kardex_id', v_kardex_id,
        'folio', v_folio,
        'estanque_codigo', v_estanque.codigo,
        'stock_anterior', v_stock_actual,
        'stock_nuevo',    p_litros_correctos,
        'delta',          v_delta,
        'cpp_anterior',   v_cpp_actual,
        'cpp_nuevo',      v_cpp_usar,
        'valor_anterior', ROUND((v_stock_actual * v_cpp_actual)::numeric, 2),
        'valor_nuevo',    v_valor_post
    );
END;
$$;

COMMENT ON FUNCTION rpc_ajustar_stock_estanque IS
'Ajusta el stock fisico de un estanque. Foto + GPS + motivo obligatorios. MIG68.';


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'col_foto_ajuste', EXISTS(SELECT 1 FROM information_schema.columns
                               WHERE table_name='combustible_kardex_valorizado'
                                 AND column_name='foto_ajuste_url'),
    'rpc_con_foto', EXISTS(
        SELECT 1 FROM pg_proc p
         WHERE p.proname='rpc_ajustar_stock_estanque'
           AND pg_get_function_arguments(p.oid) LIKE '%p_foto_url%'
    )
) AS resultado;

NOTIFY pgrst, 'reload schema';
