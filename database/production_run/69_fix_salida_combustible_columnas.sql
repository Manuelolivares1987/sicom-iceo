-- ============================================================================
-- 69_fix_salida_combustible_columnas.sql
-- ----------------------------------------------------------------------------
-- FIX: MIG66 reescribio rpc_registrar_salida_combustible_valorizada con un
-- INSERT que referenciaba columnas inexistentes en combustible_kardex_valorizado
-- (ot_id, faena_id, destino_tipo, motivo, cliente_nombre). El error en runtime:
--   "column "ot_id" of relation "combustible_kardex_valorizado" does not exist"
--
-- Esta migracion republica el RPC con el INSERT correcto:
--   - Mantiene los params MIG64 (vehiculo_externo + fotos + receptor)
--   - Mantiene los params MIG66 (geo + lecturas medidor)
--   - INSERT usa solo las columnas que SI existen: equipo_id, ceco_id,
--     cliente_nombre_manual (no ot_id/faena_id/destino_tipo/motivo). La
--     info de OT/faena/destino/motivo va a la observacion como texto
--     plano por ahora.
--
-- ADITIVA, IDEMPOTENTE. No toca esquema, solo reemplaza la function.
-- ============================================================================

-- ── 0. DROP de TODAS las signatures previas ────────────────────────────────
-- (MIG64 dejo una signature, MIG66 otra distinta. Al usar CREATE OR REPLACE
--  con una signature diferente, PG crea una funcion nueva sin reemplazar la
--  anterior. Resultado: queries por nombre tiran 42725 "is not unique".)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT 'DROP FUNCTION IF EXISTS public.' || p.proname ||
               '(' || pg_get_function_identity_arguments(p.oid) || ')' AS drop_stmt
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'rpc_registrar_salida_combustible_valorizada'
    LOOP
        EXECUTE r.drop_stmt;
    END LOOP;
END $$;


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
    v_obs_final   TEXT;
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

        IF p_foto_medidor_inicial_lat IS NULL OR p_foto_medidor_inicial_lon IS NULL THEN
            RAISE EXCEPTION 'Foto medidor inicial sin coordenadas GPS.';
        END IF;
        IF p_foto_medidor_final_lat IS NULL OR p_foto_medidor_final_lon IS NULL THEN
            RAISE EXCEPTION 'Foto medidor final sin coordenadas GPS.';
        END IF;
        IF p_vehiculo_externo_id IS NOT NULL THEN
            IF p_foto_patente_lat IS NULL OR p_foto_patente_lon IS NULL THEN
                RAISE EXCEPTION 'Foto patente sin coordenadas GPS.';
            END IF;
        END IF;
    END IF;

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

    -- Trazabilidad de OT/faena/destino/motivo en observacion (las columnas
    -- dedicadas no existen en el kardex hoy).
    v_obs_final := format('[destino=%s | motivo=%s%s%s] %s',
        p_destino_tipo,
        trim(p_motivo),
        CASE WHEN p_ot_id    IS NOT NULL THEN ' | ot='   || p_ot_id::text    ELSE '' END,
        CASE WHEN p_faena_id IS NOT NULL THEN ' | faena='|| p_faena_id::text ELSE '' END,
        COALESCE(p_observacion, '')
    );

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        equipo_id, ceco_id, cliente_nombre_manual,
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
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_vigente,
        v_stock_post, v_cpp_vigente, ROUND((v_stock_post * v_cpp_vigente)::numeric, 2),
        p_evidencia_url, v_obs_final, v_user_id,
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

COMMENT ON FUNCTION rpc_registrar_salida_combustible_valorizada IS
'Salida valorizada con CPP vigente. Fix MIG69: INSERT usa columnas que existen (equipo_id, ceco_id, cliente_nombre_manual). OT/faena/motivo/destino se anexan a observacion.';

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'rpc_fix_aplicado', EXISTS(
        SELECT 1 FROM pg_proc p
         WHERE p.proname='rpc_registrar_salida_combustible_valorizada'
           AND pg_get_function_arguments(p.oid) LIKE '%p_lectura_medidor_final_lt%'
    )
) AS resultado;
