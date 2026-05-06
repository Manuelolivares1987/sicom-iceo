-- ============================================================================
-- diag_calama_permisos_oocc_supcalama.sql
-- ----------------------------------------------------------------------------
-- Diagnostico de roles y RLS para los dos usuarios bloqueados:
--   - supcalama@pillado.cl (UID b6160090-4d00-42f6-b50e-b4a811ab584a)
--   - oocc@pillado.cl     (UID 6ee0a371-d8d5-4617-83f7-7d4a28066f07)
--
-- Read-only: NO altera datos. Devuelve un set de filas, una por chequeo.
-- Ejecutar como administrador en Supabase SQL Editor.
--
-- IMPORTANTE: cada SELECT del UNION castea explicitamente todas las columnas
-- a TEXT para evitar el error "UNION types rol_usuario_enum and text cannot
-- be matched" (la columna usuarios_perfil.rol es enum, no text).
-- ============================================================================

WITH
sup AS (
    SELECT 'b6160090-4d00-42f6-b50e-b4a811ab584a'::UUID AS uid
),
oocc AS (
    SELECT '6ee0a371-d8d5-4617-83f7-7d4a28066f07'::UUID AS uid
),

-- ── 1. Perfil global ─────────────────────────────────────────────────────────
chk_perfiles AS (
    SELECT
        '01_perfil_global'::text AS chequeo,
        up.email::text           AS email,
        up.id::text              AS uid,
        up.rol::text             AS rol_global,
        up.activo::text          AS extra1,
        NULL::text               AS extra2,
        NULL::text               AS extra3,
        (CASE WHEN up.activo AND up.rol IS NOT NULL THEN 'OK' ELSE 'STOP' END)::text AS resultado
    FROM usuarios_perfil up
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
),

-- ── 2. Rol Calama (calama_roles_proyecto) ───────────────────────────────────
chk_rol_calama AS (
    SELECT
        '02_rol_calama'::text AS chequeo,
        up.email::text        AS email,
        up.id::text           AS uid,
        NULL::text            AS rol_global,
        STRING_AGG(rp.rol_calama::text || CASE WHEN rp.activo THEN '' ELSE ' (INACTIVO)' END, ', ')::text AS extra1,
        COUNT(*) FILTER (WHERE rp.activo)::text AS extra2,
        NULL::text            AS extra3,
        (CASE
            WHEN COUNT(*) FILTER (WHERE rp.activo) > 0 THEN 'OK'
            ELSE 'STOP_SIN_ROL_CALAMA'
         END)::text           AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_roles_proyecto rp ON rp.usuario_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id
),

-- ── 3. Cuantas plan_semanal_ots tienen al usuario como responsable ──────────
chk_jornadas_responsable AS (
    SELECT
        '03_jornadas_responsable'::text AS chequeo,
        up.email::text                   AS email,
        up.id::text                      AS uid,
        up.rol::text                     AS rol_global,
        NULL::text                       AS extra1,
        COUNT(po.id)::text               AS extra2,
        NULL::text                       AS extra3,
        (CASE WHEN COUNT(po.id) > 0 THEN 'OK' ELSE 'WARN_SIN_JORNADAS' END)::text AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_plan_semanal_ots po ON po.responsable_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id, up.rol
),

-- ── 4. Cuantas OTs Calama tienen al usuario como responsable ───────────────
chk_ots_responsable AS (
    SELECT
        '04_ots_responsable'::text AS chequeo,
        up.email::text             AS email,
        up.id::text                AS uid,
        up.rol::text               AS rol_global,
        NULL::text                 AS extra1,
        COUNT(ot.id)::text         AS extra2,
        NULL::text                 AS extra3,
        (CASE WHEN COUNT(ot.id) > 0 THEN 'OK' ELSE 'WARN_SIN_OTS_DIRECTAS' END)::text AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_ordenes_trabajo ot ON ot.responsable_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id, up.rol
),

-- ── 5. Funciones helper Calama (evaluadas en sesion del admin actual) ──────
-- Nota: estas funciones usan auth.uid(), por lo que retornan los valores del
-- USUARIO QUE EJECUTA ESTE SCRIPT (admin). Para evaluar cada usuario hay que
-- iniciar sesion como ese usuario y volver a correr 1 sola query.
chk_helpers_admin AS (
    SELECT
        '05_helpers_admin_actual'::text AS chequeo,
        '(admin que ejecuta)'::text     AS email,
        COALESCE(auth.uid()::text, '(sin sesion)') AS uid,
        fn_user_rol()::text             AS rol_global,
        fn_calama_rol_proyecto()::text  AS extra1,
        json_build_object(
            'puede_planificar', fn_calama_puede_planificar(),
            'puede_ver',        fn_calama_puede_ver(),
            'es_admin',         fn_calama_es_admin_global(),
            'es_operador',      fn_calama_es_operador(),
            'es_mandante',      fn_calama_es_mandante()
        )::text                         AS extra2,
        NULL::text                      AS extra3,
        (CASE WHEN fn_calama_puede_planificar()
              THEN 'OK_ADMIN'
              ELSE 'INFO_ADMIN_SIN_ACCESO_PLANIFICAR'
         END)::text                     AS resultado
)

SELECT chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado FROM chk_perfiles
UNION ALL
SELECT chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado FROM chk_rol_calama
UNION ALL
SELECT chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado FROM chk_jornadas_responsable
UNION ALL
SELECT chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado FROM chk_ots_responsable
UNION ALL
SELECT chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado FROM chk_helpers_admin
ORDER BY chequeo, email NULLS LAST;


-- ============================================================================
-- INSTRUCCIONES PARA EL USUARIO:
-- ----------------------------------------------------------------------------
-- 1) Pega TODO este script en Supabase SQL Editor (como admin) y ejecutalo.
-- 2) La salida es una tabla con columnas:
--      chequeo, email, uid, rol_global, extra1, extra2, extra3, resultado
-- 3) Copia las filas y pegamelas aqui.
--
-- Filas esperadas (interpretacion):
--
--   01_perfil_global oocc@pillado.cl     ... rol_global=colaborador  extra1=true (activo) OK
--   01_perfil_global supcalama@pillado.cl... rol_global=supervisor   extra1=true (activo) OK
--   02_rol_calama    oocc@pillado.cl     ... extra1=operador_calama  extra2=1 (activos)   OK
--   02_rol_calama    supcalama@pillado.cl... extra1=supervisor_calama extra2=1            OK
--   03_jornadas_responsable oocc           ... extra2=count (>=0)                          OK | WARN
--   03_jornadas_responsable supcalama      ... extra2=count                                OK | WARN
--   04_ots_responsable      oocc/supcalama ... extra2=count
--   05_helpers_admin_actual ... rol_global=administrador, extra2=json con funciones        OK_ADMIN
--
-- Si aparece STOP_SIN_ROL_CALAMA → asignar rol Calama:
--
--   INSERT INTO calama_roles_proyecto (usuario_id, rol_calama, activo, asignado_at, notas)
--   VALUES
--     ('b6160090-4d00-42f6-b50e-b4a811ab584a', 'supervisor_calama', true, NOW(), 'Reasignado'),
--     ('6ee0a371-d8d5-4617-83f7-7d4a28066f07', 'operador_calama',   true, NOW(), 'Reasignado')
--   ON CONFLICT (usuario_id, rol_calama, faena_calama_id) DO UPDATE SET activo=true;
-- ============================================================================
