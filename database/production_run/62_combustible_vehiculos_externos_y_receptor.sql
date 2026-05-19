-- ============================================================================
-- 62_combustible_vehiculos_externos_y_receptor.sql
-- ----------------------------------------------------------------------------
-- Agrega capacidad de despachar combustible a vehiculos EXTERNOS autorizados
-- (no son flota Pillado, son sub-contratistas o clientes a los que se les
-- autoriza cargar). Tambien captura firma del receptor y foto de la patente.
--
-- Para despachos a EXTERNOS: foto_patente + firma_receptor son OBLIGATORIAS.
-- Para despachos a FLOTA PROPIA: ambas son opcionales.
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
-- 1. TABLA vehiculos_autorizados_externos
-- ============================================================================
CREATE TABLE IF NOT EXISTS vehiculos_autorizados_externos (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    patente          VARCHAR(20)  NOT NULL,
    empresa          VARCHAR(200) NOT NULL,
    contrato_id      UUID         REFERENCES contratos(id) ON DELETE SET NULL,
    activo           BOOLEAN      NOT NULL DEFAULT true,
    fecha_autorizacion DATE       NOT NULL DEFAULT CURRENT_DATE,
    fecha_revocacion DATE,
    notas            TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by       UUID         REFERENCES auth.users(id),
    CONSTRAINT uq_vehiculo_externo_patente UNIQUE (patente)
);

CREATE INDEX IF NOT EXISTS idx_vehic_ext_activo   ON vehiculos_autorizados_externos (activo) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_vehic_ext_empresa  ON vehiculos_autorizados_externos (empresa);
CREATE INDEX IF NOT EXISTS idx_vehic_ext_contrato ON vehiculos_autorizados_externos (contrato_id) WHERE contrato_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_vehic_ext_updated_at ON vehiculos_autorizados_externos;
CREATE TRIGGER trg_vehic_ext_updated_at
    BEFORE UPDATE ON vehiculos_autorizados_externos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 2. Agregar columnas a combustible_movimientos
-- ============================================================================
ALTER TABLE combustible_movimientos
    ADD COLUMN IF NOT EXISTS vehiculo_externo_id UUID REFERENCES vehiculos_autorizados_externos(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS firma_receptor_url  TEXT,
    ADD COLUMN IF NOT EXISTS nombre_receptor     VARCHAR(200),
    ADD COLUMN IF NOT EXISTS rut_receptor        VARCHAR(20),
    ADD COLUMN IF NOT EXISTS foto_patente_url    TEXT;

CREATE INDEX IF NOT EXISTS idx_combustible_mov_vehic_ext
    ON combustible_movimientos (vehiculo_externo_id) WHERE vehiculo_externo_id IS NOT NULL;

COMMENT ON COLUMN combustible_movimientos.vehiculo_externo_id IS
    'FK a vehiculos_autorizados_externos. Alternativa a vehiculo_activo_id (flota propia).';
COMMENT ON COLUMN combustible_movimientos.firma_receptor_url IS
    'Firma capturada del receptor (data URL upload a evidencias-combustible). Obligatoria si despacho a vehiculo externo.';
COMMENT ON COLUMN combustible_movimientos.foto_patente_url IS
    'Foto de la patente del vehiculo (validacion visual). Obligatoria si despacho a vehiculo externo.';


-- ============================================================================
-- 3. Reemplazar fn_registrar_movimiento_combustible
-- ----------------------------------------------------------------------------
-- Mantiene firma anterior (MIG61) + 5 parametros nuevos al final.
-- Validacion: si vehiculo_externo_id presente -> foto_patente + firma_receptor
-- son obligatorios.
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
    -- MIG61: fotos separadas inicio / fin
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    -- NUEVO MIG62: vehiculo externo + receptor
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

    -- MIG61: fotos del medidor inicio/fin obligatorias para despacho
    IF p_tipo = 'despacho' THEN
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor INICIAL (antes de cargar).';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho requiere foto del medidor FINAL (despues de cargar).';
        END IF;
    END IF;

    -- MIG62: si despacho a vehiculo externo -> validaciones extra
    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_existe
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_existe IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_existe THEN
            RAISE EXCEPTION 'Vehiculo externo % esta marcado como NO autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
        IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a vehiculo externo requiere FOTO DE LA PATENTE.';
        END IF;
        IF p_firma_receptor_url IS NULL OR length(trim(p_firma_receptor_url)) = 0 THEN
            RAISE EXCEPTION 'Despacho a vehiculo externo requiere FIRMA DEL RECEPTOR.';
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

    -- Actualizar horometro/kilometraje del activo (solo flota propia)
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
-- 4. RLS para vehiculos_autorizados_externos
-- ============================================================================
ALTER TABLE vehiculos_autorizados_externos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_vehic_ext_select ON vehiculos_autorizados_externos;
CREATE POLICY pol_vehic_ext_select ON vehiculos_autorizados_externos
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_vehic_ext_write ON vehiculos_autorizados_externos;
CREATE POLICY pol_vehic_ext_write ON vehiculos_autorizados_externos
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','bodeguero'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','bodeguero'));


-- ============================================================================
-- 5. SEED inicial — 17 patentes autorizadas (Excel Manuel 2026-05-19)
-- ============================================================================
INSERT INTO vehiculos_autorizados_externos (patente, empresa, notas) VALUES
  ('LH-SL-21', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('TG-VF-36', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('TD-XB-87', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('PZ-VX-34', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('RV-KH-42', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('PY-CS-39', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('JH-SG-22', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('VT-HG-27', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('SP-YP-47', 'LISSET LOPEZ G', 'Seed inicial 2026-05-19'),
  ('HRWL-50',  'MYG',            'Seed inicial 2026-05-19'),
  ('HSFD-76',  'MYG',            'Seed inicial 2026-05-19'),
  ('HSHR-13',  'MYG',            'Seed inicial 2026-05-19'),
  ('HYYT-23',  'MYG',            'Seed inicial 2026-05-19'),
  ('KHPH-26',  'MYG',            'Seed inicial 2026-05-19'),
  ('RPSY-67',  'MYG',            'Seed inicial 2026-05-19'),
  ('VRYT-27',  'MYG',            'Seed inicial 2026-05-19'),
  ('VRYT-77',  'MYG',            'Seed inicial 2026-05-19')
ON CONFLICT (patente) DO UPDATE
   SET empresa = EXCLUDED.empresa,
       activo  = true;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_externos',         to_regclass('public.vehiculos_autorizados_externos') IS NOT NULL,
    'col_vehic_externo_id',   EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_movimientos' AND column_name='vehiculo_externo_id'),
    'col_firma_receptor',     EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_movimientos' AND column_name='firma_receptor_url'),
    'col_foto_patente',       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_movimientos' AND column_name='foto_patente_url'),
    'rpc_actualizado',        EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname='fn_registrar_movimiento_combustible' AND n.nspname='public' AND pg_get_function_arguments(p.oid) LIKE '%p_foto_patente_url%'),
    'patentes_seed',          (SELECT COUNT(*) FROM vehiculos_autorizados_externos)
) AS resultado;

NOTIFY pgrst, 'reload schema';
