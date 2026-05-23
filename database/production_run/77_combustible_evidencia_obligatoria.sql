-- ============================================================================
-- 77_combustible_evidencia_obligatoria.sql
-- ----------------------------------------------------------------------------
-- UNIFICA la exigencia de evidencia para TODOS los despachos de combustible.
--
-- Antes (MIG41 + MIG64): foto patente + firma + RUT receptor solo eran
-- obligatorios cuando p_vehiculo_externo_id NOT NULL.
--
-- Despues de esta migracion: TODO despacho de combustible (interno, externo,
-- a OT, CECO, faena, consumo interno, venta externa) requiere:
--   - foto_patente_url           (foto de la patente del vehiculo)
--   - foto_medidor_inicial_url   (foto del medidor antes de cargar)
--   - foto_medidor_final_url     (foto del medidor despues de cargar)
--   - firma_receptor_url         (firma digital del receptor)
--   - nombre_receptor            (nombre completo)
--   - rut_receptor               (RUT)
--
-- Adicionalmente extiende rpc_registrar_despacho_combustible_con_sellos para
-- aceptar vehiculo_externo_id + foto_patente_url + foto_medidor_*_url y
-- pasarlos al wrapper interno (rpc_registrar_salida_combustible_valorizada).
-- Anteriormente esos campos se perdian al pasar por el RPC de sellos.
--
-- ADITIVA, IDEMPOTENTE. Movimientos historicos sin evidencia siguen siendo
-- validos (no se aplica retroactivamente).
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada') THEN
        RAISE EXCEPTION 'STOP - MIG40/64 no aplicadas';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_despacho_combustible_con_sellos') THEN
        RAISE EXCEPTION 'STOP - MIG41 no aplicada';
    END IF;
END $$;


-- ============================================================================
-- 1. Reemplazar rpc_registrar_salida_combustible_valorizada
-- ----------------------------------------------------------------------------
-- Misma signature MIG64 + obligar evidencia para TODO despacho con destino
-- != consumo_interno (donde no hay receptor humano, ej: traslado interno
-- entre estanques que va por otra ruta).
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
    p_vehiculo_externo_id      UUID    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT    DEFAULT NULL,
    p_foto_medidor_final_url   TEXT    DEFAULT NULL,
    p_foto_patente_url         TEXT    DEFAULT NULL,
    p_firma_receptor_url       TEXT    DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL,
    -- MIG66: geo + lecturas medidor (defaults preservados)
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

    -- "Despacho fisico" = sale combustible a un equipo/vehiculo/cliente con
    -- receptor humano. Excluye 'consumo_interno' (uso propio sin entrega
    -- formal a un tercero). MIG77 obliga evidencia completa en despachos
    -- fisicos.
    v_es_despacho_fisico := p_destino_tipo <> 'consumo_interno';

    -- Validar vehiculo externo si presente
    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_ok
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_ok IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_ok THEN
            RAISE EXCEPTION 'Vehiculo externo % NO esta autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
    END IF;

    -- MIG77: evidencia OBLIGATORIA para todo despacho fisico
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

    -- Coherencia FK por destino
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

    -- Warning si las lecturas del medidor difieren > 3% de los litros declarados
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
        foto_patente_url, firma_receptor_url, nombre_receptor, rut_receptor
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_actual,
        v_stock_post, v_cpp_actual, v_valor_post,
        p_evidencia_url, p_observacion, v_user_id,
        p_vehiculo_externo_id, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_url, p_firma_receptor_url, p_nombre_receptor, p_rut_receptor
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
        'warning_medidor', v_warn_med
    );
END;
$$;


-- ============================================================================
-- 2. Reemplazar rpc_registrar_despacho_combustible_con_sellos
-- ----------------------------------------------------------------------------
-- Agrega parametros: p_vehiculo_externo_id + p_foto_patente_url +
-- p_foto_medidor_inicial_url + p_foto_medidor_final_url
-- y los pasa al RPC interno (salida valorizada).
--
-- IMPORTANTE: drop primero la version MIG41 (25 params) para que no quede
-- como overload. Sin esto, el GRANT EXECUTE de mas abajo falla con
-- "function name is not unique".
-- ============================================================================
DROP FUNCTION IF EXISTS rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR,
    TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT
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
    -- NUEVO MIG77
    p_vehiculo_externo_id    UUID    DEFAULT NULL,
    p_foto_patente_url       TEXT    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT  DEFAULT NULL,
    p_foto_medidor_final_url   TEXT  DEFAULT NULL,
    -- MIG77: fotos sello obligatorias (antes eran opcionales)
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

    -- Sellos obligatorios
    IF p_sello_inicial IS NULL OR LENGTH(TRIM(p_sello_inicial)) = 0 THEN
        RAISE EXCEPTION 'sello_inicial es obligatorio';
    END IF;
    IF p_sello_final IS NULL OR LENGTH(TRIM(p_sello_final)) = 0 THEN
        RAISE EXCEPTION 'sello_final es obligatorio';
    END IF;

    -- MIG77: fotos de los sellos y del equipo/odometro OBLIGATORIAS
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

    -- Llamar a la salida valorizada (MIG40+MIG64+MIG77)
    -- Esta llamada valida adicionalmente: foto_patente, fotos medidor,
    -- firma_receptor, nombre, RUT — para todo despacho fisico.
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
        p_lectura_medidor_final_lt   => p_lectura_medidor_final_lt
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
        observacion, created_by
    ) VALUES (
        v_despacho_id, v_kardex_id, p_estanque_id, p_destino_tipo, v_destino_id,
        p_equipo_id, p_ot_id, p_ceco_id, p_faena_id,
        TRIM(p_sello_inicial), TRIM(p_sello_final),
        p_foto_sello_inicial_url, p_foto_sello_final_url,
        p_foto_odometro_url, p_foto_equipo_url,
        p_litros, v_user_id,
        p_receptor_nombre, p_receptor_rut, p_firma_receptor_url,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        p_observacion, v_user_id
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
        'litros', p_litros
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_despacho_combustible_con_sellos IS
    'Despacho de combustible con sellos antifraude + evidencia completa obligatoria (MIG77).';


-- ============================================================================
-- 3. fn_registrar_movimiento_combustible (legacy MIG50/61/62)
-- ----------------------------------------------------------------------------
-- Elevar a obligatorio para tipo='despacho' (sin importar si es externo).
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_registrar_movimiento_combustible(
    p_tipo                 tipo_movimiento_combustible_enum,
    p_estanque_id          UUID,
    p_medidor_id           UUID,
    p_lectura_inicial_lt   NUMERIC,
    p_lectura_final_lt     NUMERIC,
    p_foto_medidor_url     TEXT DEFAULT NULL,
    p_proveedor            VARCHAR DEFAULT NULL,
    p_numero_factura       VARCHAR DEFAULT NULL,
    p_costo_unitario_clp   NUMERIC DEFAULT NULL,
    p_destino_tipo         destino_despacho_combustible_enum DEFAULT NULL,
    p_vehiculo_activo_id   UUID DEFAULT NULL,
    p_destino_descripcion  VARCHAR DEFAULT NULL,
    p_horometro_vehiculo   NUMERIC DEFAULT NULL,
    p_kilometraje_vehiculo NUMERIC DEFAULT NULL,
    p_observaciones        TEXT DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    p_vehiculo_externo_id  UUID DEFAULT NULL,
    p_firma_receptor_url   TEXT DEFAULT NULL,
    p_nombre_receptor      VARCHAR DEFAULT NULL,
    p_rut_receptor         VARCHAR DEFAULT NULL,
    p_foto_patente_url     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id        UUID;
    v_litros         NUMERIC(10,2);
    v_costo_total    NUMERIC(14,0);
    v_movimiento_id  UUID;
    v_stock_nuevo    NUMERIC(10,2);
    v_externo_existe BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    IF p_lectura_final_lt < p_lectura_inicial_lt THEN
        RAISE EXCEPTION 'Lectura final (%) debe ser >= lectura inicial (%)',
            p_lectura_final_lt, p_lectura_inicial_lt;
    END IF;

    v_litros := p_lectura_final_lt - p_lectura_inicial_lt;
    IF v_litros <= 0 THEN
        RAISE EXCEPTION 'Los litros del movimiento deben ser > 0';
    END IF;

    -- MIG77: evidencia OBLIGATORIA para todo despacho (no solo externo)
    IF p_tipo = 'despacho' THEN
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor INICIAL.';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor FINAL.';
        END IF;
        IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere FOTO DE LA PATENTE del vehiculo.';
        END IF;
        IF p_firma_receptor_url IS NULL OR length(trim(p_firma_receptor_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere FIRMA DEL RECEPTOR.';
        END IF;
        IF p_nombre_receptor IS NULL OR length(trim(p_nombre_receptor)) < 3 THEN
            RAISE EXCEPTION 'Despacho requiere NOMBRE DEL RECEPTOR (min 3 caracteres).';
        END IF;
        IF p_rut_receptor IS NULL OR length(trim(p_rut_receptor)) < 7 THEN
            RAISE EXCEPTION 'Despacho requiere RUT DEL RECEPTOR.';
        END IF;
    END IF;

    -- Si despacho a vehiculo externo, validar autorizacion
    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_existe
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_existe IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_existe THEN
            RAISE EXCEPTION 'Vehiculo externo % esta marcado como NO autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
    END IF;

    v_costo_total := CASE
        WHEN p_costo_unitario_clp IS NOT NULL
        THEN ROUND(p_costo_unitario_clp * v_litros, 0)
        ELSE NULL
    END;

    INSERT INTO combustible_movimientos (
        tipo, estanque_id, medidor_id,
        lectura_inicial_lt, lectura_final_lt, litros,
        foto_medidor_url, operador_id,
        proveedor, numero_factura, costo_unitario_clp, costo_total_clp,
        destino_tipo, vehiculo_activo_id, destino_descripcion,
        horometro_vehiculo, kilometraje_vehiculo,
        observaciones,
        foto_medidor_inicial_url, foto_medidor_final_url,
        vehiculo_externo_id, firma_receptor_url,
        nombre_receptor, rut_receptor, foto_patente_url
    ) VALUES (
        p_tipo, p_estanque_id, p_medidor_id,
        p_lectura_inicial_lt, p_lectura_final_lt, v_litros,
        p_foto_medidor_url, v_user_id,
        p_proveedor, p_numero_factura, p_costo_unitario_clp, v_costo_total,
        p_destino_tipo, p_vehiculo_activo_id, p_destino_descripcion,
        p_horometro_vehiculo, p_kilometraje_vehiculo,
        p_observaciones,
        p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_vehiculo_externo_id, p_firma_receptor_url,
        p_nombre_receptor, p_rut_receptor, p_foto_patente_url
    )
    RETURNING id INTO v_movimiento_id;

    IF p_vehiculo_activo_id IS NOT NULL THEN
        UPDATE activos
           SET horas_uso_actual   = GREATEST(horas_uso_actual,   COALESCE(p_horometro_vehiculo,   horas_uso_actual)),
               kilometraje_actual = GREATEST(kilometraje_actual, COALESCE(p_kilometraje_vehiculo, kilometraje_actual)),
               updated_at         = NOW()
         WHERE id = p_vehiculo_activo_id;
    END IF;

    SELECT stock_teorico_lt INTO v_stock_nuevo
      FROM combustible_estanques WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success',         true,
        'movimiento_id',   v_movimiento_id,
        'litros',          v_litros,
        'stock_teorico',   v_stock_nuevo,
        'costo_total_clp', v_costo_total
    );
END;
$$;


-- ============================================================================
-- GRANTs (con signature explicita por overloads)
-- ============================================================================
GRANT EXECUTE ON FUNCTION rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC
) TO authenticated;

GRANT EXECUTE ON FUNCTION rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR,
    TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC
) TO authenticated;

GRANT EXECUTE ON FUNCTION fn_registrar_movimiento_combustible(
    tipo_movimiento_combustible_enum, UUID, UUID,
    NUMERIC, NUMERIC, TEXT,
    VARCHAR, VARCHAR, NUMERIC,
    destino_despacho_combustible_enum, UUID, VARCHAR,
    NUMERIC, NUMERIC, TEXT,
    TEXT, TEXT,
    UUID, TEXT, VARCHAR, VARCHAR, TEXT
) TO authenticated;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'rpc_salida_valorizada',   EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada'),
    'rpc_despacho_con_sellos', EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_despacho_combustible_con_sellos'),
    'fn_mov_legacy',           EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_registrar_movimiento_combustible'),
    'rpc_sellos_acepta_externo', EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                         WHERE p.proname='rpc_registrar_despacho_combustible_con_sellos'
                                           AND n.nspname='public'
                                           AND pg_get_function_arguments(p.oid) LIKE '%p_vehiculo_externo_id%')
) AS resultado;

NOTIFY pgrst, 'reload schema';
