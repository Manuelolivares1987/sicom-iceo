-- ============================================================================
-- 52_gps_config_y_mapeo.sql
-- ----------------------------------------------------------------------------
-- Aplica en produccion las tablas minimas para configurar proveedores GPS
-- (Radicom, Wialon, Geotab, Samsara, ...) y mapear cada dispositivo GPS a
-- un activo del maestro de flota.
--
-- Toma como base `database/schema/27_control_jornada_gps.sql` pero APLICA
-- SOLO LO NECESARIO para que la UI `/dashboard/admin/gps` funcione contra
-- BD real:
--   - config_gps_proveedor    (credenciales API key + URL base + mapeo JSONB)
--   - gps_activo_mapeo        (dispositivo GPS <-> activo)
--
-- INTENCIONALMENTE DIFERIDO a una mig posterior:
--   - actividades_conductor   (depende de tabla `conductores`)
--   - gps_eventos_log         (alto volumen, requiere Edge Function que
--                              consuma o reciba de Radicom)
--   - fn_procesar_evento_gps  (mismo)
--   - rpc_webhook_gps         (mismo)
--
-- ADITIVA, IDEMPOTENTE. Solo crea si no existe. RLS estricta: solo admin
-- global puede CRUD.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP - tabla activos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - falta fn_user_rol().';
    END IF;
END $$;


-- ============================================================================
-- 1. config_gps_proveedor — credenciales y configuracion por proveedor
-- ============================================================================
CREATE TABLE IF NOT EXISTS config_gps_proveedor (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(100) NOT NULL,                  -- "Radicom", "Wialon", ...
    activo          BOOLEAN      NOT NULL DEFAULT true,
    -- Conexion API
    api_base_url    VARCHAR(500),                           -- URL base del proveedor
    api_token       TEXT,                                   -- API key / bearer token (a futuro: cifrar)
    api_tipo_auth   VARCHAR(30)  DEFAULT 'api_key',         -- 'api_key', 'bearer', 'oauth2'
    webhook_secret  VARCHAR(200),                           -- Secret HMAC si el proveedor llama webhooks
    -- Configuracion de campos del payload del proveedor (mapeo)
    config_mapeo    JSONB        NOT NULL DEFAULT '{}',
    geofences       JSONB        NOT NULL DEFAULT '[]',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_gps_prov_nombre_nonempty CHECK (length(trim(nombre)) > 0),
    CONSTRAINT uq_gps_prov_nombre UNIQUE (nombre)
);

CREATE INDEX IF NOT EXISTS idx_gps_prov_activo ON config_gps_proveedor (activo);


-- ============================================================================
-- 2. gps_activo_mapeo — dispositivo GPS <-> activo
-- ============================================================================
CREATE TABLE IF NOT EXISTS gps_activo_mapeo (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID         NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    proveedor_id    UUID         NOT NULL REFERENCES config_gps_proveedor(id) ON DELETE CASCADE,
    gps_device_id   VARCHAR(100) NOT NULL,                  -- ID del equipo en el sistema del proveedor
    gps_device_name VARCHAR(200),                           -- Nombre del dispositivo
    imei            VARCHAR(20),                            -- IMEI fisico (opcional)
    activo          BOOLEAN      NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_gps_mapeo_activo_proveedor UNIQUE (activo_id, proveedor_id),
    CONSTRAINT uq_gps_mapeo_device UNIQUE (proveedor_id, gps_device_id)
);

CREATE INDEX IF NOT EXISTS idx_gps_mapeo_device ON gps_activo_mapeo (gps_device_id);
CREATE INDEX IF NOT EXISTS idx_gps_mapeo_activo ON gps_activo_mapeo (activo_id);


-- ============================================================================
-- 3. Trigger de updated_at
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_set_updated_at') THEN
        CREATE OR REPLACE FUNCTION fn_set_updated_at()
        RETURNS TRIGGER LANGUAGE plpgsql AS $f$
        BEGIN
            NEW.updated_at := NOW();
            RETURN NEW;
        END $f$;
    END IF;
END $$;

DROP TRIGGER IF EXISTS trg_config_gps_proveedor_updated_at ON config_gps_proveedor;
CREATE TRIGGER trg_config_gps_proveedor_updated_at
    BEFORE UPDATE ON config_gps_proveedor
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 4. RLS — solo administrador (rol global) puede CRUD; lectura para roles
--    de operacion (necesarios para enriquecer datos en frontend).
-- ============================================================================
ALTER TABLE config_gps_proveedor ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_activo_mapeo     ENABLE ROW LEVEL SECURITY;

-- config_gps_proveedor: lectura para autenticados (UI lee SIN exponer api_token
-- en el SELECT del frontend; ver `/dashboard/admin/gps/page.tsx`). Mutaciones
-- solo admin.
DROP POLICY IF EXISTS pol_gps_prov_select ON config_gps_proveedor;
CREATE POLICY pol_gps_prov_select ON config_gps_proveedor
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_gps_prov_insert ON config_gps_proveedor;
CREATE POLICY pol_gps_prov_insert ON config_gps_proveedor
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones'));

DROP POLICY IF EXISTS pol_gps_prov_update ON config_gps_proveedor;
CREATE POLICY pol_gps_prov_update ON config_gps_proveedor
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones'));

DROP POLICY IF EXISTS pol_gps_prov_delete ON config_gps_proveedor;
CREATE POLICY pol_gps_prov_delete ON config_gps_proveedor
    FOR DELETE TO authenticated
    USING (fn_user_rol() IN ('administrador','subgerente_operaciones'));

-- gps_activo_mapeo: mismo patron
DROP POLICY IF EXISTS pol_gps_mapeo_select ON gps_activo_mapeo;
CREATE POLICY pol_gps_mapeo_select ON gps_activo_mapeo
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_gps_mapeo_insert ON gps_activo_mapeo;
CREATE POLICY pol_gps_mapeo_insert ON gps_activo_mapeo
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_gps_mapeo_update ON gps_activo_mapeo;
CREATE POLICY pol_gps_mapeo_update ON gps_activo_mapeo
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_gps_mapeo_delete ON gps_activo_mapeo;
CREATE POLICY pol_gps_mapeo_delete ON gps_activo_mapeo
    FOR DELETE TO authenticated
    USING (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));


-- ============================================================================
-- 5. Seed: registrar Radicom como proveedor preconfigurado (sin token —
--    Manuel lo carga desde UI).
-- ============================================================================
INSERT INTO config_gps_proveedor (
    nombre, activo, api_tipo_auth, config_mapeo
) VALUES (
    'Radicom', true, 'api_key',
    jsonb_build_object(
        'descripcion', 'Proveedor GPS chileno. Cargar api_base_url y api_token desde /dashboard/admin/gps.',
        'campo_latitud', 'lat',
        'campo_longitud', 'lon',
        'campo_velocidad', 'speed',
        'umbral_velocidad_kmh', 5,
        'intervalo_polling_seg', 60
    )
)
ON CONFLICT (nombre) DO NOTHING;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_config_gps_proveedor', (SELECT to_regclass('public.config_gps_proveedor') IS NOT NULL),
    'tabla_gps_activo_mapeo',     (SELECT to_regclass('public.gps_activo_mapeo')     IS NOT NULL),
    'proveedores_seed',           (SELECT COUNT(*) FROM config_gps_proveedor),
    'radicom_creado',             (SELECT EXISTS(SELECT 1 FROM config_gps_proveedor WHERE nombre='Radicom')),
    'rls_habilitada',
        (SELECT bool_and(c.relrowsecurity)
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname='public'
            AND c.relname IN ('config_gps_proveedor','gps_activo_mapeo'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
