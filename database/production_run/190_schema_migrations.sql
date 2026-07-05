-- ============================================================================
-- SICOM-ICEO | 190 — Registro formal de migraciones (schema_migrations)
-- ----------------------------------------------------------------------------
-- Control de aplicación: qué migración se aplicó, con qué hash, cuándo, por
-- quién, en qué ambiente y commit. Habilita bloqueo de re-ejecución y de drift
-- de hash (archivo modificado tras aplicarse). Lo consume db-migrate.mjs.
-- IDEMPOTENTE.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version        TEXT PRIMARY KEY,              -- ej. '190'
    filename       TEXT NOT NULL,
    sha256         TEXT NOT NULL,
    applied_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_by     TEXT,                          -- session_user (no credenciales)
    execution_ms   INTEGER,
    success        BOOLEAN NOT NULL DEFAULT true,
    error_message  TEXT,
    environment    TEXT,                          -- dev | staging | prod
    git_commit     TEXT
);
CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied ON public.schema_migrations(applied_at);

COMMENT ON TABLE public.schema_migrations IS
    'Registro de migraciones aplicadas (version, hash, ambiente, commit). '
    'db-migrate.mjs bloquea re-ejecución y cambios de hash post-aplicación.';

-- Registro de backups (frente 1). Sin contraseñas ni rutas sensibles completas.
CREATE TABLE IF NOT EXISTS public.backup_ejecuciones (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_inicio   TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_fin      TIMESTAMPTZ,
    tipo           TEXT NOT NULL DEFAULT 'diario',   -- diario | semanal | mensual | manual
    tamano_bytes   BIGINT,
    sha256         TEXT,
    ubicacion_logica TEXT,                            -- etiqueta, no ruta completa
    estado         TEXT NOT NULL DEFAULT 'en_curso',  -- en_curso | ok | error
    mensaje_error  TEXT,
    restauracion_probada BOOLEAN NOT NULL DEFAULT false,
    fecha_restauracion_probada TIMESTAMPTZ
);

SELECT 'schema_migrations + backup_ejecuciones creadas' AS resultado;
