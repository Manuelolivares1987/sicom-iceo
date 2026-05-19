-- ============================================================================
-- 64_salida_combustible_fotos_externos_receptor.sql
-- ----------------------------------------------------------------------------
-- Extiende combustible_kardex_valorizado (tabla detras del RPC
-- rpc_registrar_salida_combustible_valorizada, MIG40) para soportar:
--   - Despachos a vehiculos externos autorizados (LISSET LOPEZ G, MYG, ...)
--   - 2 fotos del medidor: inicial + final
--   - Foto de la patente del vehiculo
--   - Firma del receptor + nombre + RUT
--
-- Para despachos (tipo_movimiento empieza con 'salida_') las validaciones
-- adicionales son:
--   - Vehiculo externo presente -> foto_patente + firma_receptor obligatorios
--   - Fotos del medidor inicial + final son obligatorias siempre que sea
--     un despacho a equipo/externo (no aplica a consumo_interno ni venta_externa)
--
-- ADITIVA, IDEMPOTENTE. Preserva signature del RPC original; agrega 7
-- parametros nuevos al final con DEFAULT NULL.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - tabla combustible_kardex_valorizado no existe (correr MIG40).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='vehiculos_autorizados_externos') THEN
        RAISE EXCEPTION 'STOP - MIG62 no aplicada (falta vehiculos_autorizados_externos).';
    END IF;
END $$;


-- ============================================================================
-- 1. Agregar columnas a combustible_kardex_valorizado
-- ============================================================================
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS vehiculo_externo_id      UUID REFERENCES vehiculos_autorizados_externos(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS foto_medidor_inicial_url TEXT,
    ADD COLUMN IF NOT EXISTS foto_medidor_final_url   TEXT,
    ADD COLUMN IF NOT EXISTS foto_patente_url         TEXT,
    ADD COLUMN IF NOT EXISTS firma_receptor_url       TEXT,
    ADD COLUMN IF NOT EXISTS nombre_receptor          VARCHAR(200),
    ADD COLUMN IF NOT EXISTS rut_receptor             VARCHAR(20);

CREATE INDEX IF NOT EXISTS idx_kardex_vehic_ext
    ON combustible_kardex_valorizado (vehiculo_externo_id) WHERE vehiculo_externo_id IS NOT NULL;

COMMENT ON COLUMN combustible_kardex_valorizado.vehiculo_externo_id IS
    'FK a vehiculos_autorizados_externos (alternativa a equipo_id para flota propia).';
COMMENT ON COLUMN combustible_kardex_valorizado.firma_receptor_url IS
    'Firma digital del receptor. Obligatoria si despacho a vehiculo externo.';


-- ============================================================================
-- 2. Reemplazar rpc_registrar_salida_combustible_valorizada
-- ----------------------------------------------------------------------------
-- Preserva 100% la signature original (MIG40) y agrega 7 parametros nuevos
-- al final con DEFAULT NULL. Nueva logica de validacion al final.
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
    -- NUEVO MIG64
    p_vehiculo_externo_id      UUID    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT    DEFAULT NULL,
    p_foto_medidor_final_url   TEXT    DEFAULT NULL,
    p_foto_patente_url         TEXT    DEFAULT NULL,
    p_firma_receptor_url       TEXT    DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL
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

    -- NUEVO MIG64: si hay vehiculo externo, validar que este autorizado y exigir foto+firma
    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_ok
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_ok IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_ok THEN
            RAISE EXCEPTION 'Vehiculo externo % NO esta autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
        IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a vehiculo externo requiere FOTO DE LA PATENTE.';
        END IF;
        IF p_firma_receptor_url IS NULL OR length(trim(p_firma_receptor_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a vehiculo externo requiere FIRMA DEL RECEPTOR.';
        END IF;
    END IF;

    -- NUEVO MIG64: si destino es equipo o vehiculo externo, exigir 2 fotos del medidor
    IF p_destino_tipo = 'equipo' OR p_vehiculo_externo_id IS NOT NULL THEN
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a equipo/vehiculo requiere foto del medidor INICIAL.';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a equipo/vehiculo requiere foto del medidor FINAL.';
        END IF;
    END IF;

    -- Coherencia FK por destino (mantenida MIG40)
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

    -- Lock estanque
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

    -- Folio
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
        -- MIG64 nuevos
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
        'tipo_movimiento_kardex', v_tipo_kardex
    );
END;
$$;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'col_vehic_externo',  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='vehiculo_externo_id'),
    'col_foto_ini',       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='foto_medidor_inicial_url'),
    'col_foto_fin',       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='foto_medidor_final_url'),
    'col_foto_patente',   EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='foto_patente_url'),
    'col_firma',          EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='firma_receptor_url'),
    'rpc_extendido',      EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname='rpc_registrar_salida_combustible_valorizada' AND n.nspname='public' AND pg_get_function_arguments(p.oid) LIKE '%p_vehiculo_externo_id%')
) AS resultado;

NOTIFY pgrst, 'reload schema';
