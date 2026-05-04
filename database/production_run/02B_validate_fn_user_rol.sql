-- ============================================================================
-- 02B_validate_fn_user_rol.sql  —  Validar que el hotfix quedó correcto.
-- Solo lectura. Ejecutar después de 02A.
-- ============================================================================


-- ── 1. ¿Existe la función? ───────────────────────────────────────────
SELECT
    'EXISTS' AS check_name,
    COUNT(*) AS encontrada
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_user_rol';
-- Esperado: 1


-- ── 2. Firma sin argumentos + retorna text ───────────────────────────
SELECT
    'FIRMA' AS check_name,
    p.proname,
    p.pronargs                    AS num_args,
    p.prorettype::regtype::TEXT   AS retorna,
    pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_user_rol';
-- Esperado: num_args=0, retorna=text, args=''


-- ── 3. ¿Es SECURITY DEFINER? ─────────────────────────────────────────
SELECT
    'SECURITY_DEFINER' AS check_name,
    p.prosecdef         AS is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_user_rol';
-- Esperado: true


-- ── 4. Permiso EXECUTE para authenticated ────────────────────────────
SELECT
    'GRANT_AUTHENTICATED' AS check_name,
    has_function_privilege('authenticated', 'public.fn_user_rol()', 'EXECUTE') AS tiene_execute;
-- Esperado: true


-- ── 5. Tabla usuarios_perfil + columnas requeridas ───────────────────
SELECT
    'USUARIOS_PERFIL' AS check_name,
    (SELECT COUNT(*) FROM information_schema.tables
       WHERE table_schema='public' AND table_name='usuarios_perfil') AS tabla,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='rol') AS columna_rol,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='activo') AS columna_activo;
-- Esperado: tabla=1, columna_rol=1, columna_activo=1


-- ── 6. Conteo de perfiles activos por rol ────────────────────────────
SELECT
    'PERFILES_POR_ROL' AS check_name,
    rol,
    COUNT(*) AS cantidad
FROM public.usuarios_perfil
WHERE activo = true
GROUP BY rol
ORDER BY rol;


-- ── 7. Test de invocación (NULL desde SQL Editor es esperado) ────────
SELECT public.fn_user_rol() AS rol_actual_en_sql_editor;
-- En SQL Editor sin sesión Auth → NULL. Esto NO es fallo.
-- Para validar funcionalmente, el frontend debe llamar la función
-- estando logueado.


-- ── 8. Resultado consolidado ─────────────────────────────────────────
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_user_rol') = 1
         AND (SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_user_rol') = true
         AND (SELECT prorettype::regtype::TEXT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_user_rol') = 'text'
         AND (SELECT pronargs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_user_rol') = 0
         AND has_function_privilege('authenticated', 'public.fn_user_rol()', 'EXECUTE') = true
         AND (SELECT COUNT(*) FROM information_schema.columns
               WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='rol') = 1
         AND (SELECT COUNT(*) FROM information_schema.columns
               WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='activo') = 1
        THEN 'OK_FN_USER_ROL'
        ELSE 'STOP_FN_USER_ROL — revisar checks 1-7 arriba'
    END AS resultado;
