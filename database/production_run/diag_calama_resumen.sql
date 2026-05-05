-- ============================================================================
-- diag_calama_resumen.sql  —  TODO en una sola tabla.
-- ----------------------------------------------------------------------------
-- Pega y ejecuta. Vas a ver UN SOLO result-set con todos los checks
-- en formato (check, valor). Read-only.
-- ============================================================================

WITH
-- Conteos basicos
c AS (
    SELECT
        (SELECT COUNT(*) FROM calama_ordenes_trabajo)            AS total_ots,
        (SELECT COUNT(*) FROM calama_planificaciones)            AS total_plan,
        (SELECT COUNT(*) FROM calama_zonas_proyecto)             AS total_zonas,
        (SELECT COUNT(*) FROM calama_planes_semanales)           AS total_plan_sem,
        (SELECT COUNT(*) FROM calama_plan_semanal_ots)           AS total_plan_ots,
        (SELECT COUNT(*) FROM calama_ot_avance_eventos)          AS total_eventos,
        (SELECT COUNT(*) FROM usuarios_perfil)                   AS total_perfiles,
        (SELECT COUNT(*) FROM usuarios_perfil WHERE activo=true) AS total_perfiles_activos,
        (SELECT COUNT(*) FROM usuarios_perfil WHERE rol='administrador')      AS total_admin,
        (SELECT COUNT(*) FROM usuarios_perfil WHERE rol='supervisor')         AS total_sup,
        (SELECT COUNT(*) FROM usuarios_perfil WHERE rol='colaborador')        AS total_colab,
        (SELECT COUNT(*) FROM auth.users)                                     AS total_auth_users
)
SELECT '01 total OTs Calama'                AS check_, total_ots::text             AS valor FROM c
UNION ALL SELECT '02 total planificaciones', total_plan::text         FROM c
UNION ALL SELECT '03 total zonas (lugares fisicos)', total_zonas::text FROM c
UNION ALL SELECT '04 total planes semanales',  total_plan_sem::text   FROM c
UNION ALL SELECT '05 total plan_ots (OTs en plan semanal)', total_plan_ots::text FROM c
UNION ALL SELECT '06 total eventos avance',    total_eventos::text    FROM c
UNION ALL SELECT '07 total perfiles',          total_perfiles::text   FROM c
UNION ALL SELECT '08 total perfiles activos',  total_perfiles_activos::text FROM c
UNION ALL SELECT '09 total con rol admin',     total_admin::text      FROM c
UNION ALL SELECT '10 total con rol supervisor', total_sup::text       FROM c
UNION ALL SELECT '11 total con rol colaborador', total_colab::text    FROM c
UNION ALL SELECT '12 total auth.users',        total_auth_users::text FROM c

UNION ALL SELECT '13 perfil sup (mig23)',
    COALESCE(
      (SELECT email || ' | rol=' || COALESCE(rol::text,'NULL') || ' | activo=' || activo::text
         FROM usuarios_perfil
        WHERE id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'),
      'NO EXISTE'
    )

UNION ALL SELECT '14 perfil oocc (mig23)',
    COALESCE(
      (SELECT email || ' | rol=' || COALESCE(rol::text,'NULL') || ' | activo=' || activo::text
         FROM usuarios_perfil
        WHERE id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'),
      'NO EXISTE'
    )

UNION ALL SELECT '15 rol calama sup',
    COALESCE(
      (SELECT rol_calama || ' (activo=' || activo::text || ')'
         FROM calama_roles_proyecto
        WHERE usuario_id = 'b6160090-4d00-42f6-b50e-b4a811ab584a'
        ORDER BY asignado_at DESC LIMIT 1),
      'NO EXISTE'
    )

UNION ALL SELECT '16 rol calama oocc',
    COALESCE(
      (SELECT rol_calama || ' (activo=' || activo::text || ')'
         FROM calama_roles_proyecto
        WHERE usuario_id = '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
        ORDER BY asignado_at DESC LIMIT 1),
      'NO EXISTE'
    )

UNION ALL SELECT '17 ultimos 5 emails activos',
    COALESCE(
      (SELECT string_agg(email, ', ' ORDER BY email)
         FROM (
           SELECT email FROM usuarios_perfil
            WHERE activo = true
            ORDER BY updated_at DESC NULLS LAST LIMIT 5
         ) x),
      'NINGUNO'
    )

UNION ALL SELECT '18 admins activos en BD',
    COALESCE(
      (SELECT string_agg(email || ' (' || COALESCE(rol::text,'NULL') || ')', ' | ')
         FROM usuarios_perfil
        WHERE activo = true
          AND rol IN ('administrador','gerencia','subgerente_operaciones','supervisor','planificador','jefe_operaciones')),
      'NINGUNO'
    )

UNION ALL SELECT '19 auth users sin perfil',
    COALESCE(
      (SELECT string_agg(au.email, ', ')
         FROM auth.users au
         LEFT JOIN usuarios_perfil up ON up.id = au.id
        WHERE up.id IS NULL),
      'TODOS TIENEN PERFIL'
    )

UNION ALL SELECT '20 OTs por estado',
    COALESCE(
      (SELECT string_agg(estado || ':' || total::text, ', ')
         FROM (SELECT estado, COUNT(*) AS total
                 FROM calama_ordenes_trabajo
                GROUP BY estado) x),
      'SIN OTs'
    )

UNION ALL SELECT '21 planificaciones recientes',
    COALESCE(
      (SELECT string_agg(codigo || ' (' || estado || ')', ', ')
         FROM (SELECT codigo, estado FROM calama_planificaciones
                ORDER BY created_at DESC LIMIT 5) x),
      'SIN PLANIFICACIONES'
    )

UNION ALL SELECT '22 sample 3 zonas',
    COALESCE(
      (SELECT string_agg(codigo_zona || ' ' || nombre, ' | ')
         FROM (SELECT codigo_zona, nombre FROM calama_zonas_proyecto
                ORDER BY codigo_zona LIMIT 3) x),
      'SIN ZONAS'
    )

UNION ALL SELECT '23 helpers RLS existen',
    'puede_ver=' || (to_regprocedure('public.fn_calama_puede_ver()') IS NOT NULL)::text ||
    ', puede_planif=' || (to_regprocedure('public.fn_calama_puede_planificar()') IS NOT NULL)::text ||
    ', es_admin=' || (to_regprocedure('public.fn_calama_es_admin_global()') IS NOT NULL)::text ||
    ', user_rol=' || (to_regprocedure('public.fn_user_rol()') IS NOT NULL)::text

ORDER BY check_;
