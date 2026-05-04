-- ============================================================================
-- 02C_debug_fn_user_rol_detection.sql  —  Solo lectura. Diagnóstico.
-- ----------------------------------------------------------------------------
-- Confirma POR DIFERENTES MÉTODOS si la función public.fn_user_rol() existe.
-- Útil cuando un precheck reporta STOP pero la validación dedicada (02B) dice OK.
-- ============================================================================


-- ── 1. Detección via to_regprocedure (preferida) ─────────────────────
SELECT
    'TO_REGPROCEDURE' AS metodo,
    to_regprocedure('public.fn_user_rol()') AS oid_o_null,
    (to_regprocedure('public.fn_user_rol()') IS NOT NULL) AS detectada;
-- Esperado: detectada = true


-- ── 2. Detección via to_regproc (acepta proname sin paréntesis) ──────
SELECT
    'TO_REGPROC' AS metodo,
    to_regproc('public.fn_user_rol') AS oid_o_null,
    (to_regproc('public.fn_user_rol') IS NOT NULL) AS detectada;


-- ── 3. Detección via pg_proc + pg_namespace (clásico) ────────────────
SELECT
    'PG_PROC' AS metodo,
    p.proname,
    n.nspname                    AS schema,
    p.pronargs                   AS num_args,
    p.prorettype::regtype::TEXT  AS retorna,
    p.prosecdef                  AS is_security_definer,
    p.provolatile                AS volatilidad,
    pg_get_function_identity_arguments(p.oid) AS args_string
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_user_rol';
-- Esperado: 1 fila con num_args=0, retorna='text', is_security_definer=true.


-- ── 4. ¿La función fue confundida con una TABLA? (causa raíz del bug) ──
SELECT
    'INFORMATION_SCHEMA_TABLES' AS metodo,
    COUNT(*) AS encontradas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'fn_user_rol';
-- ⚠️ Esperado: 0 — porque fn_user_rol NO es una tabla, es una función.
--    Si el precheck original usaba esta query, NUNCA detectaba la función.
--    Ese es el bug del archivo 02_prechecks_produccion_safe.sql líneas 220-222.


-- ── 5. Detección correcta via routines ──────────────────────────────
SELECT
    'INFORMATION_SCHEMA_ROUTINES' AS metodo,
    routine_schema, routine_name, routine_type, data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'fn_user_rol';
-- Esperado: 1 fila con routine_type='FUNCTION', data_type='text'.


-- ── 6. Permiso EXECUTE para authenticated ────────────────────────────
SELECT
    'GRANT_EXECUTE' AS check_name,
    has_function_privilege('authenticated', 'public.fn_user_rol()', 'EXECUTE') AS authenticated_puede_ejecutar;


-- ── 7. Contexto actual (search_path, schema, usuario) ────────────────
SELECT
    'CONTEXTO' AS check_name,
    current_database() AS db,
    current_schema() AS current_schema,
    current_user AS user_actual,
    current_setting('search_path') AS search_path;
-- search_path no debería ser un problema porque las queries arriba usan 'public.'
-- explícitamente. Pero útil para descartar.


-- ── 8. Conteo: ¿cuántas funciones llamadas fn_user_rol hay en cualquier schema? ──
SELECT
    'TOTAL_FN_USER_ROL_EN_DB' AS check_name,
    COUNT(*) AS total,
    array_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')')
        AS firmas_completas
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'fn_user_rol';
-- Esperado: 1 (en public). Si > 1, hay duplicados en otros schemas.


-- ── 9. Resultado consolidado ─────────────────────────────────────────
SELECT
    CASE
        WHEN to_regprocedure('public.fn_user_rol()') IS NOT NULL
        THEN 'DETECTED_FN_USER_ROL — la función existe correctamente'
        ELSE 'MISSING_FN_USER_ROL — ejecutar 02A_hotfix_fn_user_rol.sql'
    END AS resultado;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- Si query (1) `detectada` = true PERO query (4) `encontradas` = 0:
--   → La función ESTÁ correctamente. El precheck original (02_prechecks_*.sql
--     líneas 220-222) tiene un bug: busca en information_schema.tables, lo cual
--     nunca encuentra funciones.
--   → SOLUCION: usar 02_prechecks_produccion_safe_v2.sql en lugar del original.
--
-- Si query (1) `detectada` = false:
--   → La función realmente falta. Ejecutar 02A_hotfix_fn_user_rol.sql.
-- ============================================================================
