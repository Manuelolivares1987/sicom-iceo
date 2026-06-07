-- ============================================================================
-- SICOM-ICEO | Migracion 126 — Permisos por rol configurables (overrides)
-- ----------------------------------------------------------------------------
-- Hoy la matriz de permisos (rol x modulo x accion) esta hardcodeada en el
-- frontend (use-permissions.ts). Esta migracion agrega una capa de OVERRIDE en
-- BD para que el administrador configure, desde una pagina, que ve/puede cada
-- ROL en cada modulo. Modelo override-only: si NO hay fila para (rol, modulo),
-- el frontend usa el default hardcodeado; si hay fila, manda la fila.
--
--   - Tabla rol_permisos_modulo (rol, modulo, permisos[]).
--   - RLS: SELECT para todos los autenticados (cada quien calcula sus permisos);
--     escritura solo via RPC (admin).
--   - RPC fn_set_rol_permisos / fn_reset_rol_permisos (validan admin + permisos
--     validos + no permiten degradar al rol 'administrador' = anti-lockout).
--
-- IDEMPOTENTE. Sin seeds (los defaults siguen en el frontend).
-- ============================================================================

-- ── 1. TABLA ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rol_permisos_modulo (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rol          TEXT NOT NULL,
    modulo       TEXT NOT NULL,
    permisos     TEXT[] NOT NULL DEFAULT '{}',
    es_extendido BOOLEAN NOT NULL DEFAULT false,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by   UUID REFERENCES auth.users(id),
    CONSTRAINT uq_rol_permisos_modulo UNIQUE (rol, modulo)
);
CREATE INDEX IF NOT EXISTS idx_rpm_rol ON rol_permisos_modulo(rol);

COMMENT ON TABLE rol_permisos_modulo IS
    'Override de permisos por rol/modulo sobre los defaults hardcodeados del '
    'frontend. Sin fila => default. Editable por el administrador.';

-- ── 2. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE rol_permisos_modulo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_rpm_select ON rol_permisos_modulo;
CREATE POLICY pol_rpm_select ON rol_permisos_modulo
    FOR SELECT TO authenticated USING (true);

-- Escritura directa solo admin (defensa en profundidad; el camino normal es el RPC).
DROP POLICY IF EXISTS pol_rpm_admin ON rol_permisos_modulo;
CREATE POLICY pol_rpm_admin ON rol_permisos_modulo
    FOR ALL USING (fn_user_rol() = 'administrador')
    WITH CHECK (fn_user_rol() = 'administrador');

-- ── 3. RPC — upsert de permisos de un (rol, modulo) ─────────────────────────
CREATE OR REPLACE FUNCTION fn_set_rol_permisos(
    p_rol          TEXT,
    p_modulo       TEXT,
    p_permisos     TEXT[],
    p_es_extendido BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rol_actual TEXT := fn_user_rol();
    v_perm       TEXT;
    v_id         UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol_actual <> 'administrador' THEN
        RAISE EXCEPTION 'Solo el administrador puede configurar permisos. Rol: %', v_rol_actual;
    END IF;
    IF p_rol IS NULL OR p_modulo IS NULL THEN
        RAISE EXCEPTION 'rol y modulo son obligatorios.';
    END IF;
    -- Anti-lockout: el rol administrador no se puede degradar.
    IF p_rol = 'administrador' THEN
        RAISE EXCEPTION 'El rol administrador no es editable (acceso total garantizado).';
    END IF;
    -- Validar que cada permiso sea uno de los conocidos.
    FOREACH v_perm IN ARRAY COALESCE(p_permisos, '{}') LOOP
        IF v_perm NOT IN ('view','create','edit','delete','approve','export') THEN
            RAISE EXCEPTION 'Permiso invalido: %', v_perm;
        END IF;
    END LOOP;

    INSERT INTO rol_permisos_modulo (rol, modulo, permisos, es_extendido, updated_by, updated_at)
    VALUES (p_rol, p_modulo, COALESCE(p_permisos,'{}'), COALESCE(p_es_extendido,false), auth.uid(), NOW())
    ON CONFLICT (rol, modulo) DO UPDATE
        SET permisos = EXCLUDED.permisos,
            es_extendido = EXCLUDED.es_extendido,
            updated_by = auth.uid(),
            updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('id', v_id, 'rol', p_rol, 'modulo', p_modulo, 'permisos', p_permisos);
END $$;

-- ── 4. RPC — restaurar un rol a sus defaults (borra overrides) ──────────────
CREATE OR REPLACE FUNCTION fn_reset_rol_permisos(p_rol TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rol_actual TEXT := fn_user_rol();
    v_n INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol_actual <> 'administrador' THEN
        RAISE EXCEPTION 'Solo el administrador puede restaurar permisos.';
    END IF;
    DELETE FROM rol_permisos_modulo WHERE rol = p_rol;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN jsonb_build_object('rol', p_rol, 'overrides_eliminados', v_n);
END $$;

-- ── 5. VALIDACION ───────────────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM information_schema.tables
       WHERE table_schema='public' AND table_name='rol_permisos_modulo') AS tabla_ok,
    (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_set_rol_permisos','fn_reset_rol_permisos')) AS rpcs_ok,
    (SELECT count(*) FROM rol_permisos_modulo) AS overrides_actuales;
