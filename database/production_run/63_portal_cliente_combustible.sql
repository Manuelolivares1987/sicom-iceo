-- ============================================================================
-- 63_portal_cliente_combustible.sql
-- ----------------------------------------------------------------------------
-- Portal cliente: permite que usuarios externos (clientes) accedan a un
-- subset de combustible_movimientos via Supabase Auth + RLS.
--
-- Cada usuario del portal tiene un perfil que define que puede ver:
--   - contratos_ids[]: contratos a los que tiene acceso (flota propia
--     arrendada a su empresa)
--   - empresas_externas[]: strings que matchean vehiculos_autorizados_externos
--     .empresa (despachos a sus patentes externas)
--
-- Admin/operativo de Pillado ve TODO (no se les aplica el filtro).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_movimientos') THEN
        RAISE EXCEPTION 'STOP - tabla combustible_movimientos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='vehiculos_autorizados_externos') THEN
        RAISE EXCEPTION 'STOP - MIG62 no aplicada.';
    END IF;
END $$;


-- ============================================================================
-- 1. TABLA cliente_portal_perfil
-- ============================================================================
CREATE TABLE IF NOT EXISTS cliente_portal_perfil (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    nombre_visible     VARCHAR(200) NOT NULL,    -- ej. "Codelco Norte - Juan Perez"
    empresa            VARCHAR(200),             -- nombre de la empresa cliente
    rut_empresa        VARCHAR(20),
    contratos_ids      UUID[]       NOT NULL DEFAULT '{}',
    empresas_externas  TEXT[]       NOT NULL DEFAULT '{}',
    activo             BOOLEAN      NOT NULL DEFAULT true,
    creado_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    creado_por         UUID         REFERENCES auth.users(id),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    ultimo_acceso_at   TIMESTAMPTZ,
    notas              TEXT,
    CONSTRAINT uq_portal_perfil_user UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_portal_perfil_activo
    ON cliente_portal_perfil (activo) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_portal_perfil_contratos
    ON cliente_portal_perfil USING GIN (contratos_ids);
CREATE INDEX IF NOT EXISTS idx_portal_perfil_empresas
    ON cliente_portal_perfil USING GIN (empresas_externas);

DROP TRIGGER IF EXISTS trg_portal_perfil_updated_at ON cliente_portal_perfil;
CREATE TRIGGER trg_portal_perfil_updated_at
    BEFORE UPDATE ON cliente_portal_perfil
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 2. FUNCION fn_es_usuario_portal
-- ----------------------------------------------------------------------------
-- TRUE si el usuario autenticado tiene perfil de portal activo (i.e. es
-- un cliente, NO un usuario interno de Pillado).
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_es_usuario_portal()
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM cliente_portal_perfil
         WHERE user_id = auth.uid() AND activo = true
    );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_es_usuario_portal() TO authenticated;


-- ============================================================================
-- 3. VISTA v_combustible_movimientos_cliente
-- ----------------------------------------------------------------------------
-- Vista publica al portal con TODO el detalle de movimientos que el cliente
-- puede ver, enriquecida (joins) para que la UI no haga queries extras.
-- ============================================================================
CREATE OR REPLACE VIEW v_combustible_movimientos_cliente AS
SELECT
    m.id,
    m.tipo,
    m.litros,
    m.lectura_inicial_lt,
    m.lectura_final_lt,
    m.costo_unitario_clp,
    m.costo_total_clp,
    m.created_at         AS fecha,
    m.observaciones,
    -- Estanque
    e.nombre             AS estanque_nombre,
    e.codigo             AS estanque_codigo,
    -- Destino
    m.destino_tipo,
    m.destino_descripcion,
    -- Vehiculo flota propia
    m.vehiculo_activo_id,
    af.codigo            AS activo_codigo,
    af.patente           AS activo_patente,
    cf.id                AS activo_contrato_id,
    cf.codigo            AS activo_contrato_codigo,
    cf.cliente           AS activo_cliente,
    -- Vehiculo externo
    m.vehiculo_externo_id,
    ve.patente           AS externo_patente,
    ve.empresa           AS externo_empresa,
    -- Fotos
    m.foto_medidor_inicial_url,
    m.foto_medidor_final_url,
    m.foto_patente_url,
    -- Receptor
    m.nombre_receptor,
    m.rut_receptor,
    m.firma_receptor_url,
    -- Horometros (solo para flota propia)
    m.horometro_vehiculo,
    m.kilometraje_vehiculo
  FROM combustible_movimientos m
  LEFT JOIN combustible_estanques e             ON e.id  = m.estanque_id
  LEFT JOIN activos af                          ON af.id = m.vehiculo_activo_id
  LEFT JOIN contratos cf                        ON cf.id = af.contrato_id
  LEFT JOIN vehiculos_autorizados_externos ve   ON ve.id = m.vehiculo_externo_id
 WHERE m.tipo = 'despacho'  -- portal solo ve despachos (no ingresos compra)
;

GRANT SELECT ON v_combustible_movimientos_cliente TO authenticated;


-- ============================================================================
-- 4. RLS en combustible_movimientos para usuarios portal
-- ----------------------------------------------------------------------------
-- Si el usuario es interno Pillado (rol existente) -> ve todo (politica existente).
-- Si el usuario es del portal -> solo ve despachos donde:
--   (a) el activo arrendado pertenece a un contrato en su perfil.contratos_ids
--   (b) O el vehiculo externo tiene una empresa en su perfil.empresas_externas
-- ============================================================================
DROP POLICY IF EXISTS pol_combustible_mov_portal_cliente ON combustible_movimientos;
CREATE POLICY pol_combustible_mov_portal_cliente
    ON combustible_movimientos
    FOR SELECT
    TO authenticated
    USING (
        -- Permiso si es usuario interno con rol pillado
        fn_user_rol() IS NOT NULL
        OR
        -- O si es usuario portal y el movimiento le corresponde
        EXISTS (
            SELECT 1
              FROM cliente_portal_perfil cp
              LEFT JOIN activos a  ON a.id = combustible_movimientos.vehiculo_activo_id
              LEFT JOIN vehiculos_autorizados_externos ve
                     ON ve.id = combustible_movimientos.vehiculo_externo_id
             WHERE cp.user_id = auth.uid()
               AND cp.activo = true
               AND combustible_movimientos.tipo = 'despacho'
               AND (
                    (a.contrato_id IS NOT NULL AND a.contrato_id = ANY(cp.contratos_ids))
                    OR (ve.empresa IS NOT NULL AND ve.empresa  = ANY(cp.empresas_externas))
               )
        )
    );


-- ============================================================================
-- 5. RPC admin para crear / actualizar usuario del portal
-- ----------------------------------------------------------------------------
-- ASUME que el usuario auth.users ya existe (creado via Supabase Dashboard
-- por el admin con email + password). Esta RPC solo gestiona el perfil.
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_admin_crear_perfil_portal(
    p_user_id           UUID,
    p_nombre_visible    VARCHAR,
    p_empresa           VARCHAR DEFAULT NULL,
    p_rut_empresa       VARCHAR DEFAULT NULL,
    p_contratos_ids     UUID[]  DEFAULT '{}',
    p_empresas_externas TEXT[]  DEFAULT '{}',
    p_notas             TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF fn_user_rol() NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo administradores pueden crear usuarios del portal.';
    END IF;

    INSERT INTO cliente_portal_perfil (
        user_id, nombre_visible, empresa, rut_empresa,
        contratos_ids, empresas_externas, notas, creado_por
    ) VALUES (
        p_user_id, p_nombre_visible, p_empresa, p_rut_empresa,
        p_contratos_ids, p_empresas_externas, p_notas, auth.uid()
    )
    ON CONFLICT (user_id) DO UPDATE
       SET nombre_visible    = EXCLUDED.nombre_visible,
           empresa           = EXCLUDED.empresa,
           rut_empresa       = EXCLUDED.rut_empresa,
           contratos_ids     = EXCLUDED.contratos_ids,
           empresas_externas = EXCLUDED.empresas_externas,
           notas             = EXCLUDED.notas,
           activo            = true,
           updated_at        = NOW()
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'perfil_id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION rpc_admin_crear_perfil_portal(UUID, VARCHAR, VARCHAR, VARCHAR, UUID[], TEXT[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_admin_crear_perfil_portal(UUID, VARCHAR, VARCHAR, VARCHAR, UUID[], TEXT[], TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION rpc_admin_toggle_perfil_portal(p_user_id UUID, p_activo BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF fn_user_rol() NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo administradores.';
    END IF;
    UPDATE cliente_portal_perfil SET activo = p_activo, updated_at = NOW()
     WHERE user_id = p_user_id;
    RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_admin_toggle_perfil_portal(UUID, BOOLEAN) TO authenticated;


-- ============================================================================
-- 6. RPC para registrar ultimo_acceso (lo llama el portal al login)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_portal_marcar_acceso()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE cliente_portal_perfil
       SET ultimo_acceso_at = NOW()
     WHERE user_id = auth.uid() AND activo = true;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_portal_marcar_acceso() TO authenticated;


-- ============================================================================
-- 7. VISTA v_admin_perfiles_portal (para listar en UI admin)
-- ============================================================================
CREATE OR REPLACE VIEW v_admin_perfiles_portal AS
SELECT
    cp.id,
    cp.user_id,
    u.email,
    cp.nombre_visible,
    cp.empresa,
    cp.rut_empresa,
    cp.contratos_ids,
    cp.empresas_externas,
    cp.activo,
    cp.creado_at,
    cp.ultimo_acceso_at,
    cp.notas,
    -- Conteo de elementos por mostrar
    array_length(cp.contratos_ids,     1) AS n_contratos,
    array_length(cp.empresas_externas, 1) AS n_empresas
  FROM cliente_portal_perfil cp
  LEFT JOIN auth.users u ON u.id = cp.user_id;

GRANT SELECT ON v_admin_perfiles_portal TO authenticated;


-- ============================================================================
-- 8. RLS para cliente_portal_perfil
-- ============================================================================
ALTER TABLE cliente_portal_perfil ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_portal_perfil_select ON cliente_portal_perfil;
CREATE POLICY pol_portal_perfil_select ON cliente_portal_perfil
    FOR SELECT TO authenticated
    USING (
        fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','bodeguero')
        OR user_id = auth.uid()
    );

DROP POLICY IF EXISTS pol_portal_perfil_write ON cliente_portal_perfil;
CREATE POLICY pol_portal_perfil_write ON cliente_portal_perfil
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones'));


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_perfil',           to_regclass('public.cliente_portal_perfil') IS NOT NULL,
    'fn_es_usuario_portal',   EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_es_usuario_portal'),
    'vista_mov_cliente',      to_regclass('public.v_combustible_movimientos_cliente') IS NOT NULL,
    'vista_admin_perfiles',   to_regclass('public.v_admin_perfiles_portal') IS NOT NULL,
    'rpc_crear_perfil',       EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_admin_crear_perfil_portal'),
    'rpc_toggle',             EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_admin_toggle_perfil_portal'),
    'rpc_marcar_acceso',      EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_portal_marcar_acceso'),
    'rls_portal_cliente',     EXISTS(SELECT 1 FROM pg_policies WHERE policyname='pol_combustible_mov_portal_cliente')
) AS resultado;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- DESPUES DE APLICAR:
-- 1. En Supabase Dashboard -> Authentication -> Users -> crear usuario con
--    email + password para cada cliente
-- 2. Copiar el user_id (uuid) del usuario recien creado
-- 3. En la UI /dashboard/admin/portal-usuarios crear el perfil del portal
--    indicando user_id + contratos y/o empresas autorizadas
-- 4. El cliente entra a /portal/login con email + password
-- ============================================================================
