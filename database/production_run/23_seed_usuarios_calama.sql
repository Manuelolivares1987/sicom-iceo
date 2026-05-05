-- ============================================================================
-- 23_seed_usuarios_calama.sql
-- ----------------------------------------------------------------------------
-- Asocia 2 usuarios de Supabase Auth (ya creados) a usuarios_perfil + asigna
-- su rol Calama en calama_roles_proyecto.
--
-- Usuarios:
--   1. Supervisor Calama         supcalama@pillado.cl
--      auth.uid: b6160090-4d00-42f6-b50e-b4a811ab584a
--      rol global: supervisor
--      rol Calama: supervisor_calama
--
--   2. Operacion Obras Civiles Calama   oocc@pillado.cl
--      auth.uid: 6ee0a371-d8d5-4617-83f7-7d4a28066f07
--      rol global: colaborador  (no existe 'operador' en rol_usuario_enum)
--      rol Calama: operador_calama  ← clave para fn_calama_es_operador()
--
-- IDEMPOTENCIA:
--   - usuarios_perfil: ON CONFLICT (id) DO UPDATE
--   - calama_roles_proyecto: DELETE de filas previas del mismo (usuario, rol)
--     antes del INSERT (para evitar duplicados con faena_calama_id NULL)
--
-- AISLACION:
--   - NO toca rol_usuario_enum (no existe 'operador'; se usa 'colaborador')
--   - NO modifica RLS, MIG17/18/18B/19/20/21/22, ni datos Calama existentes.
--   - Solo crea/actualiza 2 perfiles + 2 roles Calama.
--
-- VERIFICACION FINAL: 1 fila OK_USUARIOS_CALAMA / STOP_USUARIOS_CALAMA.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM auth.users WHERE id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'
    ) THEN
        RAISE EXCEPTION 'STOP - auth.users no contiene UID b6160090-...584a (Supervisor Calama)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM auth.users WHERE id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
    ) THEN
        RAISE EXCEPTION 'STOP - auth.users no contiene UID 6ee0a371-...6f07 (Operador OOCC)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_roles_proyecto') THEN
        RAISE EXCEPTION 'STOP - calama_roles_proyecto no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. usuarios_perfil ───────────────────────────────────────────────────────
-- ============================================================================

-- 1.1 Supervisor Calama
INSERT INTO usuarios_perfil (id, email, nombre_completo, cargo, rol, activo)
VALUES (
    'b6160090-4d00-42f6-b50e-b4a811ab584a',
    'supcalama@pillado.cl',
    'Supervisor Calama',
    'Supervisor Operacion Calama',
    'supervisor',
    true
)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    nombre_completo = COALESCE(NULLIF(EXCLUDED.nombre_completo,''), usuarios_perfil.nombre_completo),
    cargo = COALESCE(NULLIF(EXCLUDED.cargo,''), usuarios_perfil.cargo),
    rol = EXCLUDED.rol,
    activo = true,
    updated_at = NOW();

-- 1.2 Operacion Obras Civiles Calama
INSERT INTO usuarios_perfil (id, email, nombre_completo, cargo, rol, activo)
VALUES (
    '6ee0a371-d8d5-4617-83f7-7d4a28066f07',
    'oocc@pillado.cl',
    'Operacion Obras Civiles Calama',
    'Operador Obras Civiles Calama',
    'colaborador',
    true
)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    nombre_completo = COALESCE(NULLIF(EXCLUDED.nombre_completo,''), usuarios_perfil.nombre_completo),
    cargo = COALESCE(NULLIF(EXCLUDED.cargo,''), usuarios_perfil.cargo),
    rol = EXCLUDED.rol,
    activo = true,
    updated_at = NOW();


-- ============================================================================
-- ── 2. calama_roles_proyecto (rol Calama-especifico) ─────────────────────────
-- ============================================================================
-- DELETE previo del mismo (usuario, rol) para idempotencia limpia, ya que el
-- UNIQUE incluye faena_calama_id que puede ser NULL y NULL != NULL en UNIQUE.

-- 2.1 Supervisor → supervisor_calama (sin faena especifica)
DELETE FROM calama_roles_proyecto
 WHERE usuario_id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'
   AND rol_calama = 'supervisor_calama'
   AND faena_calama_id IS NULL;

INSERT INTO calama_roles_proyecto (usuario_id, rol_calama, activo, asignado_at, notas)
VALUES (
    'b6160090-4d00-42f6-b50e-b4a811ab584a',
    'supervisor_calama',
    true,
    NOW(),
    'Asignado via 23_seed_usuarios_calama.sql'
);

-- 2.2 Operador OOCC → operador_calama
DELETE FROM calama_roles_proyecto
 WHERE usuario_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
   AND rol_calama = 'operador_calama'
   AND faena_calama_id IS NULL;

INSERT INTO calama_roles_proyecto (usuario_id, rol_calama, activo, asignado_at, notas)
VALUES (
    '6ee0a371-d8d5-4617-83f7-7d4a28066f07',
    'operador_calama',
    true,
    NOW(),
    'Asignado via 23_seed_usuarios_calama.sql'
);


-- ============================================================================
-- ── 3. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG23_SEED_USUARIOS_CALAMA',
        'Seed: Supervisor Calama + Operador OOCC + roles_proyecto',
        current_user, NOW(), NOW(), 'ok',
        '2 usuarios_perfil + 2 calama_roles_proyecto.'
    );
END $$;


-- ============================================================================
-- ── 4. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        EXISTS (SELECT 1 FROM usuarios_perfil
                 WHERE id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'
                   AND rol = 'supervisor' AND activo = true) AS sup_perfil_ok,
        EXISTS (SELECT 1 FROM usuarios_perfil
                 WHERE id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
                   AND rol = 'colaborador' AND activo = true) AS op_perfil_ok,
        EXISTS (SELECT 1 FROM calama_roles_proyecto
                 WHERE usuario_id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'
                   AND rol_calama = 'supervisor_calama' AND activo = true) AS sup_calama_ok,
        EXISTS (SELECT 1 FROM calama_roles_proyecto
                 WHERE usuario_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
                   AND rol_calama = 'operador_calama' AND activo = true) AS op_calama_ok
)
SELECT
    CASE
        WHEN sup_perfil_ok AND op_perfil_ok AND sup_calama_ok AND op_calama_ok
            THEN 'OK_USUARIOS_CALAMA'
        ELSE 'STOP_USUARIOS_CALAMA'
    END AS resultado,
    sup_perfil_ok,
    op_perfil_ok,
    sup_calama_ok,
    op_calama_ok,
    NOW() AS chequeado_en
FROM checks;
