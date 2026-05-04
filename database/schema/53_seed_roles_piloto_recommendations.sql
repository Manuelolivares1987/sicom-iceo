-- ============================================================================
-- 53_seed_roles_piloto_recommendations.sql
-- ----------------------------------------------------------------------------
-- ARCHIVO DE RECOMENDACIONES — NO EJECUTAR A CIEGAS.
--
-- Generado en FASE 5.1 de la auditoria SICOM-ICEO (2026-04-28).
-- Plantilla SQL comentada para crear los 11 perfiles del piloto operativo.
--
-- IMPORTANTE:
--   1. Supabase Auth NO permite crear usuarios desde SQL directo.
--   2. Cada usuario debe crearse PRIMERO desde el Dashboard de Supabase
--      (Authentication → Users → Add user) y obtener su UUID.
--   3. Luego, reemplazar los placeholders 'UUID-<rol>' por el UUID real
--      antes de ejecutar este SQL.
--   4. NO incluir contrasenas reales en este archivo. La contrasena se asigna
--      desde el Dashboard de Supabase Auth.
--   5. Para los roles secundarios (jefe_operaciones, planificador, comercial,
--      colaborador) ya existe seed completo en migracion 35.
-- ============================================================================


-- ============================================================================
-- BLOCK 0  Verificacion previa (SAFE — solo lectura)
-- ============================================================================

-- 0.1 Listar perfiles activos actuales
-- SELECT id, email, nombre_completo, rol, activo FROM usuarios_perfil WHERE activo = true;

-- 0.2 Listar roles cubiertos vs roles del enum
-- SELECT
--   unnest(enum_range(NULL::rol_usuario_enum))::TEXT AS rol_enum,
--   EXISTS (SELECT 1 FROM usuarios_perfil WHERE rol::TEXT = unnest(enum_range(NULL::rol_usuario_enum))::TEXT AND activo = true) AS tiene_perfil
-- ORDER BY rol_enum;


-- ============================================================================
-- BLOCK A  Crear usuarios en Supabase Auth (manual, en Dashboard)
-- ----------------------------------------------------------------------------
-- Ir a: Supabase → Authentication → Users → Add user.
-- Crear los siguientes 10 usuarios (admin ya existe). Asignar contrasena
-- temporal segura desde el Dashboard, NO desde este archivo.
--
-- #   Email                              Rol prioritario             Faena sugerida
-- --- ---------------------------------- --------------------------- -------------------
--  1  admin@pillado.cl                   administrador                (sin faena)  YA EXISTE
--  2  gerencia@pillado.cl                gerencia                     (sin faena)
--  3  subgerente@pillado.cl              subgerente_operaciones       FAE-TALLER-CQB
--  4  jefe.mantenimiento@pillado.cl      jefe_mantenimiento           FAE-TALLER-CQB
--  5  supervisor@pillado.cl              supervisor                   FAE-TALLER-CQB
--  6  tecnico@pillado.cl                 tecnico_mantenimiento        FAE-TALLER-CQB
--  7  bodeguero@pillado.cl               bodeguero                    FAE-TALLER-CQB
--  8  abastecimiento@pillado.cl          operador_abastecimiento      FAE-TALLER-CQB
--  9  prevencion@pillado.cl              prevencionista               FAE-TALLER-CQB
-- 10  auditor@pillado.cl                 auditor                      (sin faena)
-- 11  rrhh@pillado.cl                    rrhh_incentivos              (sin faena)
--
-- Despues de crear cada uno, copiar el "User UID" y pegarlo en el INSERT del
-- BLOCK B de abajo (reemplazar 'UUID-<rol>' por el UUID real).
-- ============================================================================


-- ============================================================================
-- BLOCK B  Insertar perfiles en usuarios_perfil  (DESCOMENTAR Y REEMPLAZAR UUIDs)
-- ----------------------------------------------------------------------------
-- Idempotente: ON CONFLICT (id) DO UPDATE para que se pueda re-ejecutar.
-- ============================================================================

/*
INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, cargo, rol, faena_id, telefono, activo)
VALUES
    -- 1. Administrador (YA EXISTE — solo actualiza si cambian datos)
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
     'Usuario Gerencia',
     '10.000.001-1',
     'Gerente General',
     'gerencia',
     NULL,
     NULL,
     true),

    -- 3. Subgerente de Operaciones
    ('UUID-subgerente',
     'subgerente@pillado.cl',
     'Usuario Subgerente Operaciones',
     '10.000.002-2',
     'Subgerente de Operaciones',
     'subgerente_operaciones',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 4. Jefe de Mantenimiento
    ('UUID-jefe-mantenimiento',
     'jefe.mantenimiento@pillado.cl',
     'Usuario Jefe Mantenimiento',
     '10.000.004-4',
     'Jefe de Mantenimiento',
     'jefe_mantenimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 5. Supervisor
    ('UUID-supervisor',
     'supervisor@pillado.cl',
     'Usuario Supervisor',
     '10.000.005-5',
     'Supervisor de Terreno',
     'supervisor',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 6. Tecnico de Mantenimiento
    ('UUID-tecnico',
     'tecnico@pillado.cl',
     'Usuario Tecnico Mantenimiento',
     '10.000.007-7',
     'Tecnico de Mantenimiento',
     'tecnico_mantenimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 7. Bodeguero
    ('UUID-bodeguero',
     'bodeguero@pillado.cl',
     'Usuario Bodeguero',
     '10.000.008-8',
     'Bodeguero',
     'bodeguero',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 8. Operador de Abastecimiento
    ('UUID-abastecimiento',
     'abastecimiento@pillado.cl',
     'Usuario Operador Abastecimiento',
     '10.000.009-9',
     'Operador de Abastecimiento',
     'operador_abastecimiento',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 9. Prevencionista
    ('UUID-prevencion',
     'prevencion@pillado.cl',
     'Usuario Prevencionista',
     '10.000.011-1',
     'Prevencionista de Riesgos',
     'prevencionista',
     (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CQB' LIMIT 1),
     NULL,
     true),

    -- 10. Auditor
    ('UUID-auditor',
     'auditor@pillado.cl',
     'Usuario Auditor',
     '10.000.013-3',
     'Auditor Interno',
     'auditor',
     NULL,
     NULL,
     true),

    -- 11. RRHH Incentivos
    ('UUID-rrhh',
     'rrhh@pillado.cl',
     'Usuario RRHH Incentivos',
     '10.000.014-4',
     'Analista RRHH',
     'rrhh_incentivos',
     NULL,
     NULL,
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
-- BLOCK C  Verificacion post-insert (SAFE)
-- ============================================================================

-- C.1 Total de perfiles activos por rol (esperado: 11 roles distintos en piloto).
-- SELECT rol, COUNT(*) AS total
--   FROM usuarios_perfil
--  WHERE activo = true
--  GROUP BY rol
--  ORDER BY rol;

-- C.2 Verificar que cada perfil del piloto tiene auth.users asociado.
-- SELECT up.id, up.email, up.rol,
--        (au.id IS NOT NULL) AS tiene_auth
--   FROM usuarios_perfil up
--   LEFT JOIN auth.users au ON au.id = up.id
--  WHERE up.activo = true
--    AND up.email LIKE '%@pillado.cl'
--  ORDER BY up.rol;


-- ============================================================================
-- BLOCK D  Recomendaciones de seguridad operativa
-- ============================================================================

-- D.1 NO usar la misma contrasena para todos los usuarios en produccion.
-- D.2 Forzar cambio de contrasena en primer login (Supabase Dashboard → Auth Settings).
-- D.3 Habilitar MFA para roles administrativos (administrador, gerencia,
--     subgerente_operaciones) cuando este disponible.
-- D.4 Configurar email confirmado obligatorio antes de permitir login (por defecto en Supabase).
-- D.5 Auditar la tabla auditoria_eventos al menos cada 7 dias durante el piloto.

-- ============================================================================
-- FIN DEL ARCHIVO 53_seed_roles_piloto_recommendations.sql
-- ============================================================================
