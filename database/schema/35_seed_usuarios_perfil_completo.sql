-- ============================================================================
-- SICOM-ICEO | Migración 35 — Seed de usuarios_perfil para los 15 roles
-- ============================================================================
-- Propósito : Crear un perfil demo por cada rol definido en rol_usuario_enum,
--             cubriendo los roles operacionales nuevos (migración 31) que
--             no tenían seed (jefe_operaciones, jefe_mantenimiento, comercial,
--             prevencionista, colaborador, etc.) y ampliando la cobertura de
--             la migración 23 (que solo cubría 5 roles).
--
-- PREREQUISITOS
-- ----------------------------------------------------------------------------
-- La tabla usuarios_perfil tiene PK que referencia auth.users(id). NO se puede
-- insertar un perfil sin que exista primero el usuario en Supabase Auth.
--
-- Por eso este archivo está dividido en dos partes:
--   PASO 1 (manual, en Supabase Dashboard): crear los usuarios auth
--   PASO 2 (SQL, este archivo): insertar los perfiles con los UUIDs generados
-- ============================================================================


-- ============================================================================
-- PASO 1 — Crear estos 14 usuarios en Supabase Dashboard
-- ----------------------------------------------------------------------------
-- Ir a: Supabase → Authentication → Users → Add user
-- Password temporal para todos: Pillado2026!
-- (los usuarios deberán cambiarla en el primer login)
--
-- NOTA: El usuario #1 (admin@pillado.cl) YA EXISTE con UUID
--       d8d49f65-0bad-44a2-9565-09a4f2bd5abc — NO crearlo de nuevo.
--
--  #   Email                              Rol                          Password
-- ---- ---------------------------------- --------------------------- ----------
--  1   admin@pillado.cl                   administrador               (ya existe)
--  2   gerencia@pillado.cl                gerencia                    Pillado2026!
--  3   subgerente@pillado.cl              subgerente_operaciones      Pillado2026!
--  4   jefe.operaciones@pillado.cl        jefe_operaciones            Pillado2026!
--  5   jefe.mantenimiento@pillado.cl      jefe_mantenimiento          Pillado2026!
--  6   supervisor@pillado.cl              supervisor                  Pillado2026!
--  7   planificador@pillado.cl            planificador                Pillado2026!
--  8   tecnico@pillado.cl                 tecnico_mantenimiento       Pillado2026!
--  9   bodeguero@pillado.cl               bodeguero                   Pillado2026!
-- 10   abastecimiento@pillado.cl          operador_abastecimiento     Pillado2026!
-- 11   comercial@pillado.cl               comercial                   Pillado2026!
-- 12   prevencion@pillado.cl              prevencionista              Pillado2026!
-- 13   colaborador@pillado.cl             colaborador                 Pillado2026!
-- 14   auditor@pillado.cl                 auditor                     Pillado2026!
-- 15   rrhh@pillado.cl                    rrhh_incentivos             Pillado2026!
--
-- Después de crear cada uno, copiar el "User UID" de la tabla de usuarios en
-- el dashboard y pegarlo en el INSERT de abajo (reemplazar 'UUID-<rol>').
-- ============================================================================


-- ============================================================================
-- PASO 2 — Insertar perfiles (DESCOMENTAR y pegar UUIDs antes de ejecutar)
-- ----------------------------------------------------------------------------
-- Faena por defecto: FAE-TALLER-CQB (Taller Pillado — Coquimbo, base operativa)
-- Roles sin faena asignada (gerencia, auditor, rrhh): faena_id = NULL
-- ============================================================================

/*
INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, cargo, rol, faena_id, telefono, activo)
VALUES
    -- 1. Administrador (acceso total) — UUID REAL, ya existe en auth.users
    ('d8d49f65-0bad-44a2-9565-09a4f2bd5abc',
     'admin@pillado.cl',
     'Manuel Olivares',
     NULL,
     'Administrador del Sistema',
     'administrador',
     NULL,
     NULL,
     true),

    -- 2. Gerencia (solo lectura global)
    ('UUID-gerencia',
     'gerencia@pillado.cl',
     'Usuario Gerencia General',
     '10.000.001-1',
     'Gerente General',
     'gerencia',
     NULL,
     '+56 9 2222 2222',
     true),

    -- 3. Subgerente de Operaciones
    ('UUID-subgerente',
     'subgerente@pillado.cl',
     'Usuario Subgerente Operaciones',
     '10.000.002-2',
     'Subgerente de Operaciones',
     'subgerente_operaciones',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 3333 3333',
     true),

    -- 4. Jefe de Operaciones (cambia estados flota, asigna OTs)
    ('UUID-jefe-operaciones',
     'jefe.operaciones@pillado.cl',
     'Usuario Jefe de Operaciones',
     '10.000.003-3',
     'Jefe de Operaciones',
     'jefe_operaciones',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 4444 4444',
     true),

    -- 5. Jefe de Mantenimiento (crea y cierra OTs, gestiona PM)
    ('UUID-jefe-mantenimiento',
     'jefe.mantenimiento@pillado.cl',
     'Usuario Jefe de Mantenimiento',
     '10.000.004-4',
     'Jefe de Mantenimiento',
     'jefe_mantenimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 5555 5555',
     true),

    -- 6. Supervisor de faena
    ('UUID-supervisor',
     'supervisor@pillado.cl',
     'Usuario Supervisor Terreno',
     '10.000.005-5',
     'Supervisor de Terreno',
     'supervisor',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 6666 6666',
     true),

    -- 7. Planificador (crea OTs, planes PM)
    ('UUID-planificador',
     'planificador@pillado.cl',
     'Usuario Planificador',
     '10.000.006-6',
     'Planificador de Mantenimiento',
     'planificador',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 7777 7777',
     true),

    -- 8. Técnico de Mantenimiento (ejecuta OTs)
    ('UUID-tecnico',
     'tecnico@pillado.cl',
     'Usuario Técnico Mantenimiento',
     '10.000.007-7',
     'Técnico de Mantenimiento',
     'tecnico_mantenimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 8888 8888',
     true),

    -- 9. Bodeguero (inventario, conteos)
    ('UUID-bodeguero',
     'bodeguero@pillado.cl',
     'Usuario Bodeguero',
     '10.000.008-8',
     'Bodeguero',
     'bodeguero',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 9999 9999',
     true),

    -- 10. Operador de Abastecimiento (combustibles)
    ('UUID-abastecimiento',
     'abastecimiento@pillado.cl',
     'Usuario Operador Abastecimiento',
     '10.000.009-9',
     'Operador de Abastecimiento',
     'operador_abastecimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 1010 1010',
     true),

    -- 11. Comercial (flota + contratos + comercial)
    ('UUID-comercial',
     'comercial@pillado.cl',
     'Usuario Comercial',
     '10.000.010-0',
     'Ejecutivo Comercial',
     'comercial',
     NULL,
     '+56 9 1111 0000',
     true),

    -- 12. Prevencionista (SUSPEL/RESPEL/certificaciones)
    ('UUID-prevencion',
     'prevencion@pillado.cl',
     'Usuario Prevencionista',
     '10.000.011-1',
     'Prevencionista de Riesgos',
     'prevencionista',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 1212 1212',
     true),

    -- 13. Colaborador (lectura básica)
    ('UUID-colaborador',
     'colaborador@pillado.cl',
     'Usuario Colaborador',
     '10.000.012-2',
     'Colaborador',
     'colaborador',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     '+56 9 1313 1313',
     true),

    -- 14. Auditor (solo lectura auditor)
    ('UUID-auditor',
     'auditor@pillado.cl',
     'Usuario Auditor',
     '10.000.013-3',
     'Auditor Interno',
     'auditor',
     NULL,
     '+56 9 1414 1414',
     true),

    -- 15. RRHH Incentivos (solo KPIs y reportes)
    ('UUID-rrhh',
     'rrhh@pillado.cl',
     'Usuario RRHH Incentivos',
     '10.000.014-4',
     'Analista RRHH',
     'rrhh_incentivos',
     NULL,
     '+56 9 1515 1515',
     true)
ON CONFLICT (id) DO UPDATE SET
    email           = EXCLUDED.email,
    nombre_completo = EXCLUDED.nombre_completo,
    rut             = EXCLUDED.rut,
    cargo           = EXCLUDED.cargo,
    rol             = EXCLUDED.rol,
    faena_id        = EXCLUDED.faena_id,
    telefono        = EXCLUDED.telefono,
    activo          = EXCLUDED.activo,
    updated_at      = NOW();
*/


-- ============================================================================
-- PASO 3 — Verificación (ejecutar después de hacer el INSERT)
-- ----------------------------------------------------------------------------
-- Compara cuántos perfiles existen contra los 15 roles esperados.
-- ============================================================================

DO $$
DECLARE
    v_total INTEGER;
    v_distintos_roles INTEGER;
    v_roles_faltantes TEXT;
BEGIN
    SELECT COUNT(*) INTO v_total FROM usuarios_perfil WHERE activo = true;
    SELECT COUNT(DISTINCT rol) INTO v_distintos_roles FROM usuarios_perfil WHERE activo = true;

    SELECT string_agg(missing_rol, ', ')
      INTO v_roles_faltantes
      FROM (
        SELECT unnest(enum_range(NULL::rol_usuario_enum))::TEXT AS missing_rol
        EXCEPT
        SELECT rol::TEXT FROM usuarios_perfil WHERE activo = true
      ) x;

    RAISE NOTICE '── Estado de perfiles ──';
    RAISE NOTICE 'Total perfiles activos:    %', v_total;
    RAISE NOTICE 'Roles distintos cubiertos: % / 15', v_distintos_roles;
    IF v_roles_faltantes IS NOT NULL THEN
        RAISE NOTICE 'Roles SIN perfil creado:   %', v_roles_faltantes;
    ELSE
        RAISE NOTICE 'OK: todos los roles del enum tienen al menos un perfil activo';
    END IF;
END $$;


-- ============================================================================
-- MATRIZ DE ACCESO (qué ve cada rol en el frontend)
-- ----------------------------------------------------------------------------
-- Para ver la matriz completa de permisos por rol y módulo, consultar:
--   SELECT * FROM _roles_matriz_permisos ORDER BY rol;
--
-- (tabla poblada en migración 31, y reflejada en frontend/src/hooks/use-permissions.ts)
-- ============================================================================
