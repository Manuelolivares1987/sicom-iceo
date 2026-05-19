-- ============================================================================
-- 66_combustible_geo_y_propuesta_litros.sql
-- ----------------------------------------------------------------------------
-- Refuerzo de control de combustible:
--   A) Geo + timestamp de cada foto (anti-reciclaje) en kardex valorizado.
--   B) Lectura del totalizador del estanque (inicial/final) para validar
--      que los litros declarados coinciden con la diferencia fisica.
--   C) RPC rpc_propuesta_litros_equipo: promedio y stddev de los ultimos 5
--      despachos al mismo equipo (sirve como hint en la UI de salida).
--   D) Extender RPCs de ingreso y salida con los nuevos params (geo + lecturas).
--
-- ADITIVA, IDEMPOTENTE. Requiere MIG64 + MIG65 aplicadas.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado'
                      AND column_name='foto_patente_url') THEN
        RAISE EXCEPTION 'STOP - MIG64/65 no aplicadas (faltan columnas de fotos).';
    END IF;
END $$;


-- ============================================================================
-- A + B) Columnas nuevas
-- ============================================================================
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS foto_patente_lat          NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_patente_lon          NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_patente_ts           TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS foto_medidor_inicial_lat  NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_medidor_inicial_lon  NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_medidor_inicial_ts   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS foto_medidor_final_lat    NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_medidor_final_lon    NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS foto_medidor_final_ts     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS lectura_medidor_inicial_lt NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS lectura_medidor_final_lt   NUMERIC(12,2);

COMMENT ON COLUMN combustible_kardex_valorizado.foto_patente_lat IS
'Latitud GPS capturada en el dispositivo al momento de tomar la foto (MIG66, anti-reciclaje).';
COMMENT ON COLUMN combustible_kardex_valorizado.lectura_medidor_inicial_lt IS
'Lectura del totalizador del estanque ANTES del movimiento (MIG66). diff con final_lt valida los litros.';


-- ============================================================================
-- C) RPC propuesta de litros por equipo (hint historico)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_propuesta_litros_equipo(p_equipo_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    WITH base AS (
        SELECT litros_salida::numeric AS lt, fecha_movimiento
          FROM combustible_kardex_valorizado
         WHERE equipo_id = p_equipo_id
           AND litros_salida IS NOT NULL
           AND litros_salida > 0
         ORDER BY fecha_movimiento DESC
         LIMIT 5
    ),
    stats AS (
        SELECT COUNT(*)::int           AS n,
               ROUND(AVG(lt), 2)        AS promedio,
               ROUND(COALESCE(STDDEV_SAMP(lt),0), 2) AS stddev,
               ROUND(MIN(lt), 2)        AS minimo,
               ROUND(MAX(lt), 2)        AS maximo
          FROM base
    )
    SELECT jsonb_build_object(
        'equipo_id',  p_equipo_id,
        'n_muestras', s.n,
        'promedio',   s.promedio,
        'stddev',     s.stddev,
        'minimo',     s.minimo,
        'maximo',     s.maximo,
        'ultimos',    COALESCE((SELECT jsonb_agg(jsonb_build_object('lt', lt, 'fecha', fecha_movimiento))
                                  FROM base), '[]'::jsonb)
    )
      FROM stats s;
$$;

COMMENT ON FUNCTION rpc_propuesta_litros_equipo IS
'Promedio y stddev de los ultimos 5 despachos al equipo. UI de salida lo usa como hint inicial.';


-- ============================================================================
-- D1) Extender rpc_registrar_ingreso_combustible_valorizado
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
    -- MIG65
    p_foto_patente_url         TEXT DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    -- MIG66: geo + lecturas
    p_foto_patente_lat           NUMERIC DEFAULT NULL,
    p_foto_patente_lon           NUMERIC DEFAULT NULL,
    p_foto_patente_ts            TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_inicial_lat   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_lon   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_ts    TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_final_lat     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_lon     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_ts      TIMESTAMPTZ DEFAULT NULL,
    p_lectura_medidor_inicial_lt NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL
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
    v_diff_medidor NUMERIC;
    v_warning      TEXT := NULL;
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

    -- MIG65: fotos obligatorias
    IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DE LA PATENTE del camion proveedor.';
    END IF;
    IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DEL MEDIDOR INICIAL (antes de cargar).';
    END IF;
    IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
        RAISE EXCEPTION 'Ingreso requiere FOTO DEL MEDIDOR FINAL (despues de cargar).';
    END IF;

    -- MIG66: geo obligatoria para anti-reciclaje
    IF p_foto_patente_lat IS NULL OR p_foto_patente_lon IS NULL THEN
        RAISE EXCEPTION 'Foto patente sin coordenadas GPS. Habilita la ubicacion del dispositivo.';
    END IF;
    IF p_foto_medidor_inicial_lat IS NULL OR p_foto_medidor_inicial_lon IS NULL THEN
        RAISE EXCEPTION 'Foto medidor inicial sin coordenadas GPS.';
    END IF;
    IF p_foto_medidor_final_lat IS NULL OR p_foto_medidor_final_lon IS NULL THEN
        RAISE EXCEPTION 'Foto medidor final sin coordenadas GPS.';
    END IF;

    -- MIG66: si vienen lecturas, validar diferencia ≈ litros (±3%)
    IF p_lectura_medidor_inicial_lt IS NOT NULL AND p_lectura_medidor_final_lt IS NOT NULL THEN
        v_diff_medidor := p_lectura_medidor_final_lt - p_lectura_medidor_inicial_lt;
        IF v_diff_medidor <= 0 THEN
            RAISE EXCEPTION 'Lectura final (%) debe ser mayor a inicial (%).',
                p_lectura_medidor_final_lt, p_lectura_medidor_inicial_lt;
        END IF;
        IF ABS(v_diff_medidor - p_litros) > GREATEST(p_litros * 0.03, 1.0) THEN
            v_warning := format('Diferencia medidor=%s lt no coincide con litros declarados=%s lt.',
                                v_diff_medidor, p_litros);
        END IF;
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

    v_stock_post := v_estanque.stock_teorico_lt + p_litros;
    IF v_stock_post > v_estanque.capacidad_lt THEN
        RAISE EXCEPTION 'Ingreso supera capacidad. Stock actual: % lt, capacidad: % lt, intento: % lt',
            v_estanque.stock_teorico_lt, v_estanque.capacidad_lt, p_litros;
    END IF;

    v_cpp_anterior   := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_valor_anterior := COALESCE(v_estanque.valor_total_stock, 0);

    IF v_estanque.stock_teorico_lt > 0 THEN
        v_cpp_nuevo := ROUND(
            (v_estanque.stock_teorico_lt * v_cpp_anterior + p_litros * p_costo_unitario_clp)
            / v_stock_post, 4
        );
    ELSE
        v_cpp_nuevo := ROUND(p_costo_unitario_clp::numeric, 4);
    END IF;

    v_valor_nuevo := ROUND((v_stock_post * v_cpp_nuevo)::numeric, 2);

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_ingreso_combustible') THEN
        SELECT fn_generar_folio_ingreso_combustible() INTO v_folio;
    ELSE
        v_folio := 'ICB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        proveedor_id, documento_numero,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        foto_patente_url, foto_medidor_inicial_url, foto_medidor_final_url,
        foto_patente_lat, foto_patente_lon, foto_patente_ts,
        foto_medidor_inicial_lat, foto_medidor_inicial_lon, foto_medidor_inicial_ts,
        foto_medidor_final_lat, foto_medidor_final_lon, foto_medidor_final_ts,
        lectura_medidor_inicial_lt, lectura_medidor_final_lt
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, 'ingreso_compra', v_folio,
        p_proveedor_id, p_doc_numero,
        p_litros, 0, p_costo_unitario_clp,
        v_stock_post, v_cpp_nuevo, v_valor_nuevo,
        p_evidencia_url, p_observacion, v_user_id,
        p_foto_patente_url, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_lat, p_foto_patente_lon, p_foto_patente_ts,
        p_foto_medidor_inicial_lat, p_foto_medidor_inicial_lon, p_foto_medidor_inicial_ts,
        p_foto_medidor_final_lat, p_foto_medidor_final_lon, p_foto_medidor_final_ts,
        p_lectura_medidor_inicial_lt, p_lectura_medidor_final_lt
    );

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
        'valor_nuevo', v_valor_nuevo,
        'warning_medidor', v_warning
    );
END;
$$;


-- ============================================================================
-- D2) Extender rpc_registrar_salida_combustible_valorizada
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_salida_combustible_valorizada(
    p_estanque_id      UUID,
    p_litros           NUMERIC,
    p_destino_tipo     VARCHAR,
    p_motivo           TEXT,
    p_equipo_id        UUID    DEFAULT NULL,
    p_ot_id            UUID    DEFAULT NULL,
    p_ceco_id          UUID    DEFAULT NULL,
    p_faena_id         UUID    DEFAULT NULL,
    p_cliente_nombre   VARCHAR DEFAULT NULL,
    p_fecha_movimiento TIMESTAMPTZ DEFAULT NULL,
    p_observacion      TEXT    DEFAULT NULL,
    p_evidencia_url    TEXT    DEFAULT NULL,
    -- MIG64
    p_vehiculo_externo_id      UUID    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT    DEFAULT NULL,
    p_foto_medidor_final_url   TEXT    DEFAULT NULL,
    p_foto_patente_url         TEXT    DEFAULT NULL,
    p_firma_receptor_url       TEXT    DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL,
    -- MIG66
    p_foto_patente_lat           NUMERIC DEFAULT NULL,
    p_foto_patente_lon           NUMERIC DEFAULT NULL,
    p_foto_patente_ts            TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_inicial_lat   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_lon   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_ts    TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_final_lat     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_lon     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_ts      TIMESTAMPTZ DEFAULT NULL,
    p_lectura_medidor_inicial_lt NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_estanque    combustible_estanques%ROWTYPE;
    v_stock_post  NUMERIC;
    v_cpp_vigente NUMERIC;
    v_costo_total NUMERIC;
    v_kardex_id   UUID;
    v_folio       VARCHAR;
    v_fecha       TIMESTAMPTZ;
    v_tipo_kardex TEXT;
    v_diff_medidor NUMERIC;
    v_warning     TEXT := NULL;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para salida de combustible', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'motivo minimo 5 caracteres';
    END IF;

    -- Validar destino + obligatoriedades MIG64
    IF p_destino_tipo = 'equipo' THEN
        IF p_vehiculo_externo_id IS NOT NULL THEN
            IF p_foto_patente_url IS NULL OR p_firma_receptor_url IS NULL OR
               p_nombre_receptor IS NULL OR length(trim(p_nombre_receptor)) = 0 THEN
                RAISE EXCEPTION 'Vehiculo externo: foto patente + firma receptor + nombre receptor obligatorios.';
            END IF;
        ELSIF p_equipo_id IS NULL THEN
            RAISE EXCEPTION 'destino=equipo requiere equipo_id o vehiculo_externo_id.';
        END IF;
        IF p_foto_medidor_inicial_url IS NULL OR p_foto_medidor_final_url IS NULL THEN
            RAISE EXCEPTION 'Destino equipo: foto medidor inicial y final obligatorias.';
        END IF;

        -- MIG66: geo obligatoria en fotos medidor
        IF p_foto_medidor_inicial_lat IS NULL OR p_foto_medidor_inicial_lon IS NULL THEN
            RAISE EXCEPTION 'Foto medidor inicial sin coordenadas GPS.';
        END IF;
        IF p_foto_medidor_final_lat IS NULL OR p_foto_medidor_final_lon IS NULL THEN
            RAISE EXCEPTION 'Foto medidor final sin coordenadas GPS.';
        END IF;
        -- geo de patente solo si hay externo
        IF p_vehiculo_externo_id IS NOT NULL THEN
            IF p_foto_patente_lat IS NULL OR p_foto_patente_lon IS NULL THEN
                RAISE EXCEPTION 'Foto patente sin coordenadas GPS.';
            END IF;
        END IF;
    END IF;

    -- MIG66: si vienen lecturas, validar diferencia ≈ litros
    IF p_lectura_medidor_inicial_lt IS NOT NULL AND p_lectura_medidor_final_lt IS NOT NULL THEN
        v_diff_medidor := p_lectura_medidor_final_lt - p_lectura_medidor_inicial_lt;
        IF v_diff_medidor <= 0 THEN
            RAISE EXCEPTION 'Lectura final (%) debe ser mayor a inicial (%).',
                p_lectura_medidor_final_lt, p_lectura_medidor_inicial_lt;
        END IF;
        IF ABS(v_diff_medidor - p_litros) > GREATEST(p_litros * 0.03, 1.0) THEN
            v_warning := format('Diferencia medidor=%s lt no coincide con litros declarados=%s lt.',
                                v_diff_medidor, p_litros);
        END IF;
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    SELECT * INTO v_estanque FROM combustible_estanques WHERE id=p_estanque_id FOR UPDATE;
    IF v_estanque.id IS NULL THEN RAISE EXCEPTION 'Estanque no existe'; END IF;
    IF NOT v_estanque.activo THEN RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo; END IF;
    IF p_litros > v_estanque.stock_teorico_lt THEN
        RAISE EXCEPTION 'Stock insuficiente: solicitado % lt, disponible % lt',
            p_litros, v_estanque.stock_teorico_lt;
    END IF;

    v_cpp_vigente := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_stock_post  := v_estanque.stock_teorico_lt - p_litros;
    v_costo_total := ROUND((p_litros * v_cpp_vigente)::numeric, 2);

    v_tipo_kardex := CASE p_destino_tipo
                       WHEN 'venta_externa' THEN 'salida_venta'
                       ELSE 'salida_consumo'
                     END;

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_salida_combustible') THEN
        SELECT fn_generar_folio_salida_combustible() INTO v_folio;
    ELSE
        v_folio := 'SCB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        equipo_id, ot_id, ceco_id, faena_id, cliente_nombre, destino_tipo, motivo,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        vehiculo_externo_id, foto_medidor_inicial_url, foto_medidor_final_url,
        foto_patente_url, firma_receptor_url, nombre_receptor, rut_receptor,
        foto_patente_lat, foto_patente_lon, foto_patente_ts,
        foto_medidor_inicial_lat, foto_medidor_inicial_lon, foto_medidor_inicial_ts,
        foto_medidor_final_lat, foto_medidor_final_lon, foto_medidor_final_ts,
        lectura_medidor_inicial_lt, lectura_medidor_final_lt
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ot_id, p_ceco_id, p_faena_id, p_cliente_nombre, p_destino_tipo, p_motivo,
        0, p_litros, v_cpp_vigente,
        v_stock_post, v_cpp_vigente, ROUND((v_stock_post * v_cpp_vigente)::numeric, 2),
        p_evidencia_url, p_observacion, v_user_id,
        p_vehiculo_externo_id, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_url, p_firma_receptor_url, p_nombre_receptor, p_rut_receptor,
        p_foto_patente_lat, p_foto_patente_lon, p_foto_patente_ts,
        p_foto_medidor_inicial_lat, p_foto_medidor_inicial_lon, p_foto_medidor_inicial_ts,
        p_foto_medidor_final_lat, p_foto_medidor_final_lon, p_foto_medidor_final_ts,
        p_lectura_medidor_inicial_lt, p_lectura_medidor_final_lt
    );

    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_post,
           valor_total_stock = ROUND((v_stock_post * v_cpp_vigente)::numeric, 2),
           updated_at        = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success', true,
        'kardex_id', v_kardex_id,
        'folio', v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_salida', p_litros,
        'destino_tipo', p_destino_tipo,
        'cpp_vigente', v_cpp_vigente,
        'costo_total', v_costo_total,
        'stock_anterior', v_estanque.stock_teorico_lt,
        'stock_nuevo', v_stock_post,
        'tipo_movimiento_kardex', v_tipo_kardex,
        'warning_medidor', v_warning
    );
END;
$$;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'col_lat',     EXISTS(SELECT 1 FROM information_schema.columns
                          WHERE table_name='combustible_kardex_valorizado' AND column_name='foto_patente_lat'),
    'col_lectura', EXISTS(SELECT 1 FROM information_schema.columns
                          WHERE table_name='combustible_kardex_valorizado' AND column_name='lectura_medidor_inicial_lt'),
    'rpc_propuesta', EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_propuesta_litros_equipo'),
    'rpc_ingreso_geo', EXISTS(
        SELECT 1 FROM pg_proc p
         WHERE p.proname='rpc_registrar_ingreso_combustible_valorizado'
           AND pg_get_function_arguments(p.oid) LIKE '%p_foto_patente_lat%'
    ),
    'rpc_salida_geo', EXISTS(
        SELECT 1 FROM pg_proc p
         WHERE p.proname='rpc_registrar_salida_combustible_valorizada'
           AND pg_get_function_arguments(p.oid) LIKE '%p_foto_patente_lat%'
    )
) AS resultado;

NOTIFY pgrst, 'reload schema';
