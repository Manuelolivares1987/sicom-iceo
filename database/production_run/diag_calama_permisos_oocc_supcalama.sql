-- ============================================================================
-- diag_calama_permisos_oocc_supcalama.sql
-- ----------------------------------------------------------------------------
-- Diagnostico de roles y RLS para los dos usuarios bloqueados:
--   - supcalama@pillado.cl (UID b6160090-4d00-42f6-b50e-b4a811ab584a)
--   - oocc@pillado.cl     (UID 6ee0a371-d8d5-4617-83f7-7d4a28066f07)
--
-- Read-only: NO altera datos. Devuelve un set de filas, una por chequeo.
-- Ejecutar como administrador en Supabase SQL Editor.
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
        '01_perfil_global' AS chequeo,
        up.email,
        up.id::TEXT       AS uid,
        up.rol            AS rol_global,
        up.activo,
        CASE WHEN up.activo AND up.rol IS NOT NULL THEN 'OK' ELSE 'STOP' END AS resultado
    FROM usuarios_perfil up
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
),

-- ── 2. Rol Calama (calama_roles_proyecto) ───────────────────────────────────
chk_rol_calama AS (
    SELECT
        '02_rol_calama' AS chequeo,
        up.email,
        up.id::TEXT       AS uid,
        STRING_AGG(rp.rol_calama || CASE WHEN rp.activo THEN '' ELSE ' (INACTIVO)' END, ', ') AS roles_calama,
        COUNT(*) FILTER (WHERE rp.activo)::TEXT AS activos,
        CASE
            WHEN COUNT(*) FILTER (WHERE rp.activo) > 0 THEN 'OK'
            ELSE 'STOP_SIN_ROL_CALAMA'
        END AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_roles_proyecto rp ON rp.usuario_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id
),

-- ── 3. Cuantas plan_semanal_ots tienen al usuario como responsable ──────────
chk_jornadas_responsable AS (
    SELECT
        '03_jornadas_responsable' AS chequeo,
        up.email,
        up.id::TEXT AS uid,
        NULL::TEXT  AS rol_global,
        NULL::TEXT  AS extra,
        COUNT(po.id)::TEXT AS valor,
        CASE WHEN COUNT(po.id) > 0 THEN 'OK' ELSE 'WARN_SIN_JORNADAS' END AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_plan_semanal_ots po ON po.responsable_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id
),

-- ── 4. Cuantas OTs Calama tienen al usuario como responsable ───────────────
chk_ots_responsable AS (
    SELECT
        '04_ots_responsable' AS chequeo,
        up.email,
        up.id::TEXT AS uid,
        NULL::TEXT  AS rol_global,
        NULL::TEXT  AS extra,
        COUNT(ot.id)::TEXT AS valor,
        CASE WHEN COUNT(ot.id) > 0 THEN 'OK' ELSE 'WARN_SIN_OTS_DIRECTAS' END AS resultado
    FROM usuarios_perfil up
    LEFT JOIN calama_ordenes_trabajo ot ON ot.responsable_id = up.id
    WHERE up.id IN ((SELECT uid FROM sup), (SELECT uid FROM oocc))
    GROUP BY up.email, up.id
),

-- ── 5. Funciones helper Calama (evaluadas en sesion del admin actual) ──────
-- Nota: estas funciones usan auth.uid(), por lo que retornan los valores del
-- USUARIO QUE EJECUTA ESTE SCRIPT (admin). Para evaluar cada usuario hay que
-- iniciar sesion como ese usuario y volver a correr 1 sola query.
chk_helpers_admin AS (
    SELECT
        '05_helpers_admin_actual' AS chequeo,
        '(admin que ejecuta)' AS email,
        auth.uid()::TEXT AS uid,
        fn_user_rol() AS rol_global,
        fn_calama_rol_proyecto() AS rol_calama,
        json_build_object(
            'puede_planificar', fn_calama_puede_planificar(),
            'puede_ver',        fn_calama_puede_ver(),
            'es_admin',         fn_calama_es_admin_global(),
            'es_operador',      fn_calama_es_operador(),
            'es_mandante',      fn_calama_es_mandante()
        )::TEXT AS evaluacion,
        CASE WHEN fn_calama_puede_planificar() THEN 'OK_ADMIN' ELSE 'INFO_ADMIN_SIN_ACCESO_PLANIFICAR' END AS resultado
)

SELECT
    chequeo,
    email,
    uid,
    rol_global,
    activo::TEXT  AS extra1,
    NULL::TEXT    AS extra2,
    NULL::TEXT    AS extra3,
    resultado
FROM chk_perfiles
UNION ALL
SELECT chequeo, email, uid, NULL, roles_calama, activos, NULL, resultado FROM chk_rol_calama
UNION ALL
SELECT chequeo, email, uid, rol_global, extra, valor, NULL, resultado FROM chk_jornadas_responsable
UNION ALL
SELECT chequeo, email, uid, rol_global, extra, valor, NULL, resultado FROM chk_ots_responsable
UNION ALL
SELECT chequeo, email, uid, rol_global, rol_calama, evaluacion, NULL, resultado FROM chk_helpers_admin
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
--   01_perfil_global oocc@pillado.cl     ... rol=colaborador  activo=true OK
--   01_perfil_global supcalama@pillado.cl... rol=supervisor   activo=true OK
--   02_rol_calama    oocc@pillado.cl     ... operador_calama  activos=1   OK
--   02_rol_calama    supcalama@pillado.cl... supervisor_calama activos=1  OK
--   03_jornadas_responsable oocc           ... valor>=1                   OK
--   03_jornadas_responsable supcalama      ... valor (puede ser 0)        WARN ok
--   04_ots_responsable      oocc/supcalama ... valor>=0
--   05_helpers_admin_actual ... fn_calama_puede_planificar=true (admin)   OK_ADMIN
--
-- Si falta calama_roles_proyecto o aparece STOP_SIN_ROL_CALAMA → asignarlo:
--
--   INSERT INTO calama_roles_proyecto (usuario_id, rol_calama, activo, asignado_at, notas)
--   VALUES ('6ee0a371-d8d5-4617-83f7-7d4a28066f07', 'operador_calama', true, NOW(),
--           'Reasignado desde diagnostico permisos');
-- ============================================================================
