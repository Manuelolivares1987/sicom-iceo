-- ============================================================================
-- 61_combustible_fotos_inicio_fin.sql
-- ----------------------------------------------------------------------------
-- Agrega 2 fotos separadas a combustible_movimientos:
--   - foto_medidor_inicial_url: ANTES de despachar (lectura totalizador inicial)
--   - foto_medidor_final_url:   DESPUES de despachar (lectura totalizador final)
--
-- La diferencia entre ambas lecturas = litros despachados (validable visualmente
-- por el cliente). Critico para portal cliente (Fase 2) y trazabilidad cobro.
--
-- Mantiene `foto_medidor_url` original para retrocompatibilidad (datos pre-mig61).
-- Conserva ENTERA la signature original del RPC fn_registrar_movimiento_combustible
-- (MIG50) y solo agrega 2 parametros nuevos al final con DEFAULT NULL.
--
-- Para tipo='despacho' las 2 fotos nuevas son OBLIGATORIAS (cobro a cliente).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_movimientos') THEN
        RAISE EXCEPTION 'STOP - tabla combustible_movimientos no existe (correr MIG50 primero).';
    END IF;
END $$;


-- ============================================================================
-- 1. Agregar columnas
-- ============================================================================
ALTER TABLE combustible_movimientos
    ADD COLUMN IF NOT EXISTS foto_medidor_inicial_url TEXT,
    ADD COLUMN IF NOT EXISTS foto_medidor_final_url   TEXT;

COMMENT ON COLUMN combustible_movimientos.foto_medidor_inicial_url IS
    'Foto del medidor ANTES del movimiento. Obligatoria para despachos a cliente.';
COMMENT ON COLUMN combustible_movimientos.foto_medidor_final_url IS
    'Foto del medidor DESPUES del movimiento. Obligatoria para despachos a cliente.';


-- ============================================================================
-- 2. Reemplazar fn_registrar_movimiento_combustible
-- ----------------------------------------------------------------------------
-- Preserva 100% la signature MIG50 y agrega 2 parametros nuevos al final.
-- Agrega validacion: si tipo='despacho' ambas fotos nuevas son obligatorias.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_registrar_movimiento_combustible(
    p_tipo                 tipo_movimiento_combustible_enum,
    p_estanque_id          UUID,
    p_medidor_id           UUID,
    p_lectura_inicial_lt   NUMERIC,
    p_lectura_final_lt     NUMERIC,
    p_foto_medidor_url     TEXT DEFAULT NULL,
    -- ingreso
    p_proveedor            VARCHAR DEFAULT NULL,
    p_numero_factura       VARCHAR DEFAULT NULL,
    p_costo_unitario_clp   NUMERIC DEFAULT NULL,
    -- despacho
    p_destino_tipo         destino_despacho_combustible_enum DEFAULT NULL,
    p_vehiculo_activo_id   UUID DEFAULT NULL,
    p_destino_descripcion  VARCHAR DEFAULT NULL,
    p_horometro_vehiculo   NUMERIC DEFAULT NULL,
    p_kilometraje_vehiculo NUMERIC DEFAULT NULL,
    p_observaciones        TEXT DEFAULT NULL,
    -- NUEVO MIG61: fotos separadas inicio / fin
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL
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

    -- NUEVO MIG61: validar fotos obligatorias para despacho
    IF p_tipo = 'despacho' THEN
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor INICIAL (antes de cargar combustible).';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor FINAL (despues de cargar combustible).';
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
        foto_medidor_inicial_url, foto_medidor_final_url
    ) VALUES (
        p_tipo, p_estanque_id, p_medidor_id,
        p_lectura_inicial_lt, p_lectura_final_lt, v_litros,
        p_foto_medidor_url, v_user_id,
        p_proveedor, p_numero_factura, p_costo_unitario_clp, v_costo_total,
        p_destino_tipo, p_vehiculo_activo_id, p_destino_descripcion,
        p_horometro_vehiculo, p_kilometraje_vehiculo,
        p_observaciones,
        p_foto_medidor_inicial_url, p_foto_medidor_final_url
    )
    RETURNING id INTO v_movimiento_id;

    -- Actualizar horometro/kilometraje del activo si corresponde
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
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'col_foto_inicial', EXISTS(
        SELECT 1 FROM information_schema.columns
         WHERE table_name='combustible_movimientos' AND column_name='foto_medidor_inicial_url'
    ),
    'col_foto_final', EXISTS(
        SELECT 1 FROM information_schema.columns
         WHERE table_name='combustible_movimientos' AND column_name='foto_medidor_final_url'
    ),
    'rpc_actualizado_con_nuevos_params', EXISTS(
        SELECT 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.proname = 'fn_registrar_movimiento_combustible'
           AND n.nspname = 'public'
           AND pg_get_function_arguments(p.oid) LIKE '%p_foto_medidor_inicial_url%'
    )
) AS resultado;

NOTIFY pgrst, 'reload schema';
