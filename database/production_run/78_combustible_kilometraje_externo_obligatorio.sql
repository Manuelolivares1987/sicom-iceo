-- ============================================================================
-- 78_combustible_kilometraje_externo_obligatorio.sql
-- ----------------------------------------------------------------------------
-- Despacho de combustible a VEHICULOS EXTERNOS: kilometraje obligatorio.
--
-- Motivo: cuando se carga combustible a vehiculos de subcontratistas
-- (LISSET LOPEZ G, MYG, etc.) hay que registrar el kilometraje al momento
-- de la carga para defender el cobro y controlar el rendimiento real
-- del vehiculo externo (lt/km).
--
-- Cambios:
--   1. Agrega columna kilometraje_vehiculo NUMERIC(12,1) a:
--        - combustible_kardex_valorizado
--        - combustible_despachos_sellos
--   2. Extiende rpc_registrar_salida_combustible_valorizada para aceptar
--      p_kilometraje_vehiculo. Obliga el campo solo si p_vehiculo_externo_id
--      NOT NULL (flota propia ya lo registraba via horometro/kilometraje
--      del activo).
--   3. Extiende rpc_registrar_despacho_combustible_con_sellos para aceptar
--      y propagar p_kilometraje_vehiculo.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada') THEN
        RAISE EXCEPTION 'STOP - MIG40/64/77 no aplicadas';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_despacho_combustible_con_sellos') THEN
        RAISE EXCEPTION 'STOP - MIG41/77 no aplicadas';
    END IF;
END $$;


-- ============================================================================
-- 1. Agregar columnas
-- ============================================================================
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS kilometraje_vehiculo NUMERIC(12,1);

ALTER TABLE combustible_despachos_sellos
    ADD COLUMN IF NOT EXISTS kilometraje_vehiculo NUMERIC(12,1);

COMMENT ON COLUMN combustible_kardex_valorizado.kilometraje_vehiculo IS
    'Kilometraje del vehiculo al momento del despacho. Obligatorio para vehiculos externos (MIG78).';
COMMENT ON COLUMN combustible_despachos_sellos.kilometraje_vehiculo IS
    'Kilometraje del vehiculo al momento del despacho con sellos. Obligatorio para vehiculos externos (MIG78).';


-- ============================================================================
-- 2. Reemplazar rpc_registrar_salida_combustible_valorizada
-- Agrega p_kilometraje_vehiculo al final. Obligatorio si externo.
--
-- Drop primero la version MIG77 (30 params) para que no quede overload al
-- crear la nueva de 31 params. Sin esto los GRANT al final fallan.
-- ============================================================================
DROP FUNCTION IF EXISTS rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC
);

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
    p_vehiculo_externo_id      UUID    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT    DEFAULT NULL,
    p_foto_medidor_final_url   TEXT    DEFAULT NULL,
    p_foto_patente_url         TEXT    DEFAULT NULL,
    p_firma_receptor_url       TEXT    DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL,
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
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL,
    -- NUEVO MIG78
    p_kilometraje_vehiculo       NUMERIC DEFAULT NULL
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
    v_cpp_actual  NUMERIC;
    v_valor_post  NUMERIC;
    v_costo_total NUMERIC;
    v_kardex_id   UUID;
    v_folio       VARCHAR;
    v_fecha       TIMESTAMPTZ;
    v_tipo_kardex VARCHAR(30);
    v_externo_ok  BOOLEAN;
    v_diff_med    NUMERIC;
    v_warn_med    TEXT;
    v_es_despacho_fisico BOOLEAN;
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
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'motivo es obligatorio (min 5 caracteres)';
    END IF;
    IF p_destino_tipo NOT IN ('equipo','ot','ceco','faena','consumo_interno','venta_externa') THEN
        RAISE EXCEPTION 'destino_tipo invalido: %', p_destino_tipo;
    END IF;

    v_es_despacho_fisico := p_destino_tipo <> 'consumo_interno';

    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_ok
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_ok IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_ok THEN
            RAISE EXCEPTION 'Vehiculo externo % NO esta autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
        -- MIG78: kilometraje obligatorio para externos
        IF p_kilometraje_vehiculo IS NULL OR p_kilometraje_vehiculo < 0 THEN
            RAISE EXCEPTION 'Kilometraje del vehiculo es OBLIGATORIO para despachos a vehiculo externo.';
        END IF;
    END IF;

    IF v_es_despacho_fisico THEN
        IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
            RAISE EXCEPTION 'Foto de la patente del vehiculo es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Foto del medidor INICIAL es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Foto del medidor FINAL es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_firma_receptor_url IS NULL OR length(trim(p_firma_receptor_url)) = 0 THEN
            RAISE EXCEPTION 'Firma del receptor es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_nombre_receptor IS NULL OR length(trim(p_nombre_receptor)) < 3 THEN
            RAISE EXCEPTION 'Nombre del receptor es OBLIGATORIO (min 3 caracteres).';
        END IF;
        IF p_rut_receptor IS NULL OR length(trim(p_rut_receptor)) < 7 THEN
            RAISE EXCEPTION 'RUT del receptor es OBLIGATORIO.';
        END IF;
    END IF;

    IF p_destino_tipo = 'equipo' AND p_equipo_id IS NULL AND p_vehiculo_externo_id IS NULL THEN
        RAISE EXCEPTION 'destino=equipo requiere equipo_id O vehiculo_externo_id';
    END IF;
    IF p_destino_tipo = 'ot' AND p_ot_id IS NULL THEN
        RAISE EXCEPTION 'destino=ot requiere ot_id';
    END IF;
    IF p_destino_tipo = 'ceco' AND p_ceco_id IS NULL THEN
        RAISE EXCEPTION 'destino=ceco requiere ceco_id';
    END IF;
    IF p_destino_tipo = 'faena' AND p_faena_id IS NULL THEN
        RAISE EXCEPTION 'destino=faena requiere faena_id';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    SELECT * INTO v_estanque FROM combustible_estanques WHERE id = p_estanque_id FOR UPDATE;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;
    IF v_estanque.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente en estanque %: actual % lt, solicitado % lt',
            v_estanque.codigo, v_estanque.stock_teorico_lt, p_litros;
    END IF;

    v_cpp_actual  := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_costo_total := ROUND((p_litros * v_cpp_actual)::numeric, 2);
    v_stock_post  := v_estanque.stock_teorico_lt - p_litros;
    v_valor_post  := ROUND((v_stock_post * v_cpp_actual)::numeric, 2);

    v_tipo_kardex := CASE
        WHEN p_vehiculo_externo_id IS NOT NULL THEN 'salida_externa'
        WHEN p_destino_tipo = 'equipo'         THEN 'salida_equipo'
        WHEN p_destino_tipo = 'venta_externa'  THEN 'salida_venta'
        ELSE                                        'salida_despacho'
    END;

    IF p_lectura_medidor_inicial_lt IS NOT NULL
       AND p_lectura_medidor_final_lt IS NOT NULL THEN
        v_diff_med := p_lectura_medidor_final_lt - p_lectura_medidor_inicial_lt;
        IF v_diff_med > 0 AND ABS(v_diff_med - p_litros) > GREATEST(p_litros * 0.03, 1) THEN
            v_warn_med := FORMAT('Diferencia medidor %.2f lt vs declarado %.2f lt', v_diff_med, p_litros);
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_salida_combustible') THEN
        SELECT fn_generar_folio_salida_combustible() INTO v_folio;
    ELSE
        v_folio := 'SCB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        equipo_id, ceco_id, cliente_nombre_manual,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        vehiculo_externo_id, foto_medidor_inicial_url, foto_medidor_final_url,
        foto_patente_url, firma_receptor_url, nombre_receptor, rut_receptor,
        kilometraje_vehiculo
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_actual,
        v_stock_post, v_cpp_actual, v_valor_post,
        p_evidencia_url, p_observacion, v_user_id,
        p_vehiculo_externo_id, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_url, p_firma_receptor_url, p_nombre_receptor, p_rut_receptor,
        p_kilometraje_vehiculo
    );

    UPDATE combustible_estanques
       SET stock_teorico_lt = v_stock_post,
           updated_at = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success',         true,
        'kardex_id',       v_kardex_id,
        'folio',           v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_salida',   p_litros,
        'destino_tipo',    p_destino_tipo,
        'cpp_vigente',     v_cpp_actual,
        'costo_total',     v_costo_total,
        'stock_anterior',  v_estanque.stock_teorico_lt,
        'stock_nuevo',     v_stock_post,
        'tipo_movimiento_kardex', v_tipo_kardex,
        'warning_medidor', v_warn_med,
        'kilometraje_vehiculo', p_kilometraje_vehiculo
    );
END;
$$;


-- ============================================================================
-- 3. Reemplazar rpc_registrar_despacho_combustible_con_sellos
-- Acepta + propaga p_kilometraje_vehiculo.
-- Drop primero la version MIG77 (31 params) para evitar overload.
-- ============================================================================
DROP FUNCTION IF EXISTS rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR,
    TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC
);

CREATE OR REPLACE FUNCTION rpc_registrar_despacho_combustible_con_sellos(
    p_estanque_id            UUID,
    p_litros                 NUMERIC,
    p_destino_tipo           VARCHAR,
    p_sello_inicial          VARCHAR,
    p_sello_final            VARCHAR,
    p_motivo                 TEXT,
    p_equipo_id              UUID    DEFAULT NULL,
    p_ot_id                  UUID    DEFAULT NULL,
    p_ceco_id                UUID    DEFAULT NULL,
    p_faena_id               UUID    DEFAULT NULL,
    p_cliente_nombre         VARCHAR DEFAULT NULL,
    p_receptor_nombre        VARCHAR DEFAULT NULL,
    p_receptor_rut           VARCHAR DEFAULT NULL,
    p_foto_sello_inicial_url TEXT    DEFAULT NULL,
    p_foto_sello_final_url   TEXT    DEFAULT NULL,
    p_foto_odometro_url      TEXT    DEFAULT NULL,
    p_foto_equipo_url        TEXT    DEFAULT NULL,
    p_firma_receptor_url     TEXT    DEFAULT NULL,
    p_lat                    NUMERIC DEFAULT NULL,
    p_lng                    NUMERIC DEFAULT NULL,
    p_accuracy               NUMERIC DEFAULT NULL,
    p_geolocation_status     VARCHAR DEFAULT NULL,
    p_fecha_movimiento       TIMESTAMPTZ DEFAULT NULL,
    p_observacion            TEXT    DEFAULT NULL,
    p_evidencia_url          TEXT    DEFAULT NULL,
    p_vehiculo_externo_id    UUID    DEFAULT NULL,
    p_foto_patente_url       TEXT    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT  DEFAULT NULL,
    p_foto_medidor_final_url   TEXT  DEFAULT NULL,
    p_lectura_medidor_inicial_lt NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL,
    -- NUEVO MIG78
    p_kilometraje_vehiculo   NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_resp        JSONB;
    v_kardex_id   UUID;
    v_folio       TEXT;
    v_despacho_id UUID;
    v_cpp         NUMERIC;
    v_costo_total NUMERIC;
    v_stock_final NUMERIC;
    v_destino_id  UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para despacho con sellos', v_rol;
    END IF;

    IF p_sello_inicial IS NULL OR LENGTH(TRIM(p_sello_inicial)) = 0 THEN
        RAISE EXCEPTION 'sello_inicial es obligatorio';
    END IF;
    IF p_sello_final IS NULL OR LENGTH(TRIM(p_sello_final)) = 0 THEN
        RAISE EXCEPTION 'sello_final es obligatorio';
    END IF;

    IF p_foto_sello_inicial_url IS NULL OR length(trim(p_foto_sello_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del sello INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_sello_final_url IS NULL OR length(trim(p_foto_sello_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del sello FINAL es OBLIGATORIA.';
    END IF;
    IF p_foto_equipo_url IS NULL OR length(trim(p_foto_equipo_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del equipo es OBLIGATORIA.';
    END IF;
    IF p_foto_odometro_url IS NULL OR length(trim(p_foto_odometro_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del odometro / horometro es OBLIGATORIA.';
    END IF;

    v_resp := rpc_registrar_salida_combustible_valorizada(
        p_estanque_id      => p_estanque_id,
        p_litros           => p_litros,
        p_destino_tipo     => p_destino_tipo,
        p_motivo           => p_motivo,
        p_equipo_id        => p_equipo_id,
        p_ot_id            => p_ot_id,
        p_ceco_id          => p_ceco_id,
        p_faena_id         => p_faena_id,
        p_cliente_nombre   => p_cliente_nombre,
        p_fecha_movimiento => p_fecha_movimiento,
        p_observacion      => p_observacion,
        p_evidencia_url    => p_evidencia_url,
        p_vehiculo_externo_id      => p_vehiculo_externo_id,
        p_foto_medidor_inicial_url => p_foto_medidor_inicial_url,
        p_foto_medidor_final_url   => p_foto_medidor_final_url,
        p_foto_patente_url         => p_foto_patente_url,
        p_firma_receptor_url       => p_firma_receptor_url,
        p_nombre_receptor          => p_receptor_nombre,
        p_rut_receptor             => p_receptor_rut,
        p_lectura_medidor_inicial_lt => p_lectura_medidor_inicial_lt,
        p_lectura_medidor_final_lt   => p_lectura_medidor_final_lt,
        p_kilometraje_vehiculo     => p_kilometraje_vehiculo
    );

    v_kardex_id   := (v_resp->>'kardex_id')::UUID;
    v_folio       := v_resp->>'folio';
    v_cpp         := (v_resp->>'cpp_vigente')::NUMERIC;
    v_costo_total := (v_resp->>'costo_total')::NUMERIC;
    v_stock_final := (v_resp->>'stock_nuevo')::NUMERIC;

    v_destino_id := COALESCE(p_equipo_id, p_ot_id, p_ceco_id, p_faena_id);

    v_despacho_id := gen_random_uuid();
    INSERT INTO combustible_despachos_sellos (
        id, movimiento_combustible_id, estanque_id, destino_tipo, destino_id,
        equipo_id, ot_id, ceco_id, faena_id,
        sello_inicial, sello_final,
        foto_sello_inicial_url, foto_sello_final_url,
        foto_odometro_url, foto_equipo_url,
        litros_despachados, operador_id,
        receptor_nombre, receptor_rut, firma_receptor_url,
        lat, lng, accuracy, geolocation_status,
        observacion, created_by,
        kilometraje_vehiculo
    ) VALUES (
        v_despacho_id, v_kardex_id, p_estanque_id, p_destino_tipo, v_destino_id,
        p_equipo_id, p_ot_id, p_ceco_id, p_faena_id,
        TRIM(p_sello_inicial), TRIM(p_sello_final),
        p_foto_sello_inicial_url, p_foto_sello_final_url,
        p_foto_odometro_url, p_foto_equipo_url,
        p_litros, v_user_id,
        p_receptor_nombre, p_receptor_rut, p_firma_receptor_url,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        p_observacion, v_user_id,
        p_kilometraje_vehiculo
    );

    RETURN jsonb_build_object(
        'success', true,
        'despacho_id', v_despacho_id,
        'movimiento_id', v_kardex_id,
        'folio_movimiento', v_folio,
        'stock_final', v_stock_final,
        'cpp_usado', v_cpp,
        'costo_total', v_costo_total,
        'destino_tipo', p_destino_tipo,
        'litros', p_litros,
        'kilometraje_vehiculo', p_kilometraje_vehiculo
    );
END;
$$;


-- ============================================================================
-- GRANTs (con signature explicita)
-- ============================================================================
GRANT EXECUTE ON FUNCTION rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC,
    NUMERIC
) TO authenticated;

GRANT EXECUTE ON FUNCTION rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR,
    TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC,
    NUMERIC
) TO authenticated;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'col_kilometraje_kardex',   EXISTS(SELECT 1 FROM information_schema.columns
                                        WHERE table_name='combustible_kardex_valorizado'
                                          AND column_name='kilometraje_vehiculo'),
    'col_kilometraje_sellos',   EXISTS(SELECT 1 FROM information_schema.columns
                                        WHERE table_name='combustible_despachos_sellos'
                                          AND column_name='kilometraje_vehiculo'),
    'rpc_salida_acepta_km',     EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                        WHERE p.proname='rpc_registrar_salida_combustible_valorizada'
                                          AND n.nspname='public'
                                          AND pg_get_function_arguments(p.oid) LIKE '%p_kilometraje_vehiculo%'),
    'rpc_sellos_acepta_km',     EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                        WHERE p.proname='rpc_registrar_despacho_combustible_con_sellos'
                                          AND n.nspname='public'
                                          AND pg_get_function_arguments(p.oid) LIKE '%p_kilometraje_vehiculo%')
) AS resultado;

NOTIFY pgrst, 'reload schema';
