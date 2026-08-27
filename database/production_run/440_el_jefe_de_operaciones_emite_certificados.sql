-- ============================================================================
-- MIG440 · El jefe de operaciones también emite certificados
-- ----------------------------------------------------------------------------
-- Continuación de MIG439 (fijar vencimientos). Manuel: «sí, que los puedan
-- emitir; además el jefe de taller también».
--
-- El jefe de taller (rol `jefe_mantenimiento`, etiquetado «Jefe de Taller /
-- Mantenimiento» en Perfiles y Roles) YA estaba autorizado en los tres RPC de
-- emisión desde que nacieron — se deja verificado abajo, no hace falta tocarlo.
-- El que faltaba es `jefe_operaciones`.
--
-- Funciones que emiten:
--   · rpc_emitir_certificado(jsonb)        → hermeticidad, folio correlativo (MIG431)
--   · rpc_emitir_certificado_activo(...)   → carpeta de certificados del equipo (MIG219/436)
--     (existen DOS sobrecargas en prod: la vieja de 10 args y la de 11 con
--      p_vence_el; se parchan las dos para que no queden diciendo cosas
--      distintas según cuál resuelva PostgREST)
--
-- Lo que NO cambia: los gates de fondo del acto de emitir siguen intactos —
-- cero No Conformidades abiertas, firma del operador Y del jefe, y el
-- vencimiento calculado desde `certificado_vigencia_estandar`. Acá sólo se
-- amplía quién puede apretar el botón.
--
-- Igual que MIG439: se parcha la definición VIVA, es idempotente.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    r RECORD; v_def TEXT; v_tocados INT := 0;
BEGIN
    FOR r IN
        SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('rpc_emitir_certificado', 'rpc_emitir_certificado_activo')
    LOOP
        v_def := pg_get_functiondef(r.oid);

        IF v_def LIKE '%jefe_operaciones%' THEN
            RAISE NOTICE '%(%) ya permitía jefe_operaciones — sin cambios', r.proname, left(r.args, 40);
            CONTINUE;
        END IF;

        -- El jefe de taller tiene que estar: si no está, esta migración se
        -- escribió sobre una versión que no es la que creemos.
        IF v_def NOT LIKE '%jefe_mantenimiento%' THEN
            RAISE EXCEPTION 'En % no aparece jefe_mantenimiento: revisar a mano antes de tocar', r.proname;
        END IF;
        IF position('NOT IN (''administrador''' IN v_def) = 0 THEN
            RAISE EXCEPTION 'No encontré el control de rol en %: revisar a mano', r.proname;
        END IF;

        EXECUTE regexp_replace(v_def,
                   'NOT IN \(''administrador''',
                   'NOT IN (''administrador'',''jefe_operaciones''');
        v_tocados := v_tocados + 1;
        RAISE NOTICE '%(%) → jefe_operaciones autorizado', r.proname, left(r.args, 40);
    END LOOP;

    RAISE NOTICE 'Funciones actualizadas: %', v_tocados;
END $mig$;

-- ── Verificación: los dos jefes en las tres funciones ─────────────────────
DO $chk$
DECLARE v_falta TEXT;
BEGIN
    SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
      INTO v_falta
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('rpc_emitir_certificado', 'rpc_emitir_certificado_activo')
       AND (pg_get_functiondef(p.oid) NOT LIKE '%jefe_operaciones%'
         OR pg_get_functiondef(p.oid) NOT LIKE '%jefe_mantenimiento%');
    IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: falta algún jefe en: %', v_falta;
    END IF;
END $chk$;

-- ── Prueba con la sesión de un jefe de operaciones de verdad ──────────────
-- Se llama con datos vacíos / un tipo inexistente: el control de rol corre
-- ANTES de todo lo demás, así que llegar al siguiente error prueba que el rol
-- pasó, sin emitir ningún certificado ni consumir un folio.
DO $prueba$
DECLARE v_jefe UUID; v_msg TEXT;
BEGIN
    SELECT id INTO v_jefe FROM usuarios_perfil
     WHERE rol = 'jefe_operaciones' AND COALESCE(activo, true) LIMIT 1;
    IF v_jefe IS NULL THEN
        RAISE NOTICE 'No hay usuario con rol jefe_operaciones para probar; se omite.';
        RETURN;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_jefe, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM rpc_emitir_certificado('{}'::jsonb);
        RAISE EXCEPTION 'FALLO: se esperaba «falta el equipo o la fecha»';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF v_msg ILIKE '%No tienes permiso para emitir%' THEN
            RAISE EXCEPTION 'FALLO: hermeticidad sigue bloqueada para jefe_operaciones (%)', v_msg;
        END IF;
        RAISE NOTICE 'rpc_emitir_certificado OK para jefe_operaciones (llegó a: %)', v_msg;
    END;

    BEGIN
        -- Argumentos con NOMBRE, y con p_vence_el: con las dos sobrecargas
        -- vivas, la llamada posicional es ambigua («is not unique») y no
        -- llegaría a probar nada. El frontend siempre manda p_vence_el, así
        -- que resuelve a la de 11 argumentos igual que en producción.
        PERFORM rpc_emitir_certificado_activo(
            p_activo_id       := '00000000-0000-0000-0000-000000000000'::uuid,
            p_tipo_codigo     := '__tipo_que_no_existe__',
            p_datos           := '{}'::jsonb,
            p_operador_nombre := 'prueba MIG440',
            p_firma_operador_url := 'x', p_firma_jefe_url := 'y',
            p_vence_el        := NULL::date);
        RAISE EXCEPTION 'FALLO: se esperaba «tipo de certificado no existe»';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF v_msg ILIKE '%no autorizado para emitir%' THEN
            RAISE EXCEPTION 'FALLO: la carpeta sigue bloqueada para jefe_operaciones (%)', v_msg;
        END IF;
        RAISE NOTICE 'rpc_emitir_certificado_activo OK para jefe_operaciones (llegó a: %)', v_msg;
    END;

    PERFORM set_config('request.jwt.claims', NULL, true);
END $prueba$;

COMMIT;

-- Estado final: quién puede emitir
SELECT p.proname,
       left(pg_get_function_identity_arguments(p.oid), 30) AS args,
       (pg_get_functiondef(p.oid) LIKE '%jefe_operaciones%')  AS jefe_operaciones,
       (pg_get_functiondef(p.oid) LIKE '%jefe_mantenimiento%') AS jefe_taller
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('rpc_emitir_certificado', 'rpc_emitir_certificado_activo')
 ORDER BY 1, 2;
