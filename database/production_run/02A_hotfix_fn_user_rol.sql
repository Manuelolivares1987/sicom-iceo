-- ============================================================================
-- 02A_hotfix_fn_user_rol.sql  —  HOTFIX MINIMO PARA PRODUCCION
-- ----------------------------------------------------------------------------
-- Crea SOLO la función public.fn_user_rol(). NO toca tablas, ni RLS, ni
-- migraciones 55/56/57.
--
-- Resuelve el STOP del precheck 02_prechecks_produccion_safe.sql:
--   "STOP — falta función fn_user_rol (mig 31)"
--
-- IDEMPOTENTE: usa CREATE OR REPLACE FUNCTION.
-- SEGURO: SET search_path = public para evitar inyección por search path.
-- ============================================================================


-- ── 1. Precheck: ¿ya existe? ─────────────────────────────────────────
SELECT
    'PRECHECK_FN_USER_ROL' AS check_name,
    COUNT(*)               AS existe_actualmente,
    array_agg(prosecdef::TEXT) AS security_definer_actual
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_user_rol';
-- Si existe = 1, igual la sobreescribimos (CREATE OR REPLACE).
-- Si existe = 0, la creamos.


-- ── 2. Verificar dependencias mínimas ────────────────────────────────
DO $$
BEGIN
    -- usuarios_perfil debe existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name='usuarios_perfil'
    ) THEN
        RAISE EXCEPTION 'STOP — tabla public.usuarios_perfil no existe. Aplicar mig 02 primero.';
    END IF;

    -- columna rol debe existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='rol'
    ) THEN
        RAISE EXCEPTION 'STOP — columna usuarios_perfil.rol no existe.';
    END IF;

    -- columna activo debe existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='usuarios_perfil' AND column_name='activo'
    ) THEN
        RAISE EXCEPTION 'STOP — columna usuarios_perfil.activo no existe.';
    END IF;

    RAISE NOTICE 'Dependencias OK. Procediendo a crear fn_user_rol.';
END $$;


-- ── 3. Crear o reemplazar la función ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_user_rol()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT rol::text
      FROM public.usuarios_perfil
     WHERE id = auth.uid()
       AND activo = true
     LIMIT 1;
$$;

COMMENT ON FUNCTION public.fn_user_rol() IS
    'Retorna el rol del usuario autenticado consultando usuarios_perfil. '
    'Devuelve NULL si no hay sesión o si no existe perfil activo. '
    'SECURITY DEFINER permite leer la tabla saltando RLS para esta lectura específica.';

GRANT EXECUTE ON FUNCTION public.fn_user_rol() TO authenticated;


-- ── 4. Verificación post: confirmar creación ─────────────────────────
SELECT
    'POST_FN_USER_ROL' AS check_name,
    proname,
    prosecdef          AS is_security_definer,
    prorettype::regtype::TEXT AS retorna,
    pronargs           AS num_args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_user_rol';
-- Esperado: 1 fila con is_security_definer=true, retorna=text, num_args=0.


-- ── 5. Test de invocación ────────────────────────────────────────────
SELECT public.fn_user_rol() AS rol_actual;
-- ⚠️ NOTA: si ejecutas este script desde el SQL Editor de Supabase
-- (panel admin), `auth.uid()` puede devolver NULL porque NO hay sesión
-- de un usuario autenticado vía Auth — el SQL Editor corre con rol
-- `postgres` (service_role).
--
-- En ese caso, `rol_actual` será NULL. Esto NO es un fallo de la función;
-- significa que el contexto SQL Editor no tiene un `auth.uid()` válido.
--
-- Para validar funcionalmente:
-- 1. La función se invocará desde el frontend con sesión Supabase Auth.
-- 2. Allí, `auth.uid()` devolverá el UUID del usuario autenticado.
-- 3. Y `fn_user_rol()` retornará su rol (ej: 'administrador').


-- ── 6. Insertar log SOLO si la tabla existe (no fallar si no) ────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_HOTFIX_FN_USER_ROL',
            'Hotfix: creada/reemplazada public.fn_user_rol() simple (SQL/STABLE/SECURITY DEFINER).',
            current_user,
            NOW(), NOW(), 'ok',
            'Resuelve STOP del precheck 02. NO toca mig 55/56/57.'
        );
        RAISE NOTICE 'Log registrado en operacion_migraciones_log.';
    ELSE
        RAISE NOTICE 'Tabla operacion_migraciones_log no existe todavia (paso 03 pendiente). Se omite el log.';
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK MANUAL (si fuera necesario)
-- ----------------------------------------------------------------------------
-- DROP FUNCTION IF EXISTS public.fn_user_rol();
-- ============================================================================
