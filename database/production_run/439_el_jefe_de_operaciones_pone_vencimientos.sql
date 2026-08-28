-- ============================================================================
-- MIG439 · El jefe de operaciones puede poner el vencimiento de un papel
-- ----------------------------------------------------------------------------
-- Reporte de Manuel (2026-08-27, sobre /dashboard/flota/control-documental):
-- el rol `jefe_operaciones` entra a Control documental —el módulo es 'flota' y
-- ahí sí tiene permiso— pero al corregir una fecha recibe
--   «Tu rol (jefe_operaciones) no puede fijar vencimientos de certificados».
--
-- El jefe de operaciones YA podía subir un papel nuevo con su vencimiento
-- (rpc_renovar_certificacion, MIG272/433 lo incluyen). Lo que no podía era
-- corregir la fecha de un papel ya cargado, que es justamente lo que esa
-- pantalla existe para hacer. La lista de roles quedó distinta en cada RPC
-- porque se escribieron en migraciones separadas (409/411 y 427), no por una
-- decisión: acá se empareja.
--
-- Se abren las 4 acciones de vigencia de esa pantalla:
--   · rpc_certificacion_fijar_fecha          (corregir el vencimiento)
--   · rpc_certificacion_descartar_propuesta  (rechazar la fecha propuesta)
--   · rpc_certificacion_no_caduca            (marcar «no caduca»)
--   · rpc_certificacion_vuelve_a_caducar     (revertir lo anterior)
--
-- NO se toca `rpc_emitir_certificado_activo` (emitir un certificado con firmas
-- es otro acto, no "poner una fecha"). Si se quiere, se pide aparte.
--
-- El parche se hace SOBRE LA DEFINICIÓN VIVA (pg_get_functiondef + replace) en
-- vez de recrear los cuerpos: así no se pisa ninguna corrección posterior a la
-- migración donde nacieron. Es idempotente.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    r        RECORD;
    v_def    TEXT;
    v_nuevo  TEXT;
    v_tocados INT := 0;
BEGIN
    FOR r IN
        SELECT p.oid, p.proname
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('rpc_certificacion_fijar_fecha',
                             'rpc_certificacion_descartar_propuesta',
                             'rpc_certificacion_no_caduca',
                             'rpc_certificacion_vuelve_a_caducar')
    LOOP
        v_def := pg_get_functiondef(r.oid);

        IF v_def LIKE '%jefe_operaciones%' THEN
            RAISE NOTICE '% ya permitía jefe_operaciones — sin cambios', r.proname;
            CONTINUE;
        END IF;

        IF position('NOT IN (''administrador''' IN v_def) = 0 THEN
            RAISE EXCEPTION 'No encontré el control de rol en %: revisar a mano', r.proname;
        END IF;

        -- Sólo la PRIMERA aparición: es el gate de rol al inicio del cuerpo.
        v_nuevo := regexp_replace(
                     v_def,
                     'NOT IN \(''administrador''',
                     'NOT IN (''administrador'',''jefe_operaciones''');

        EXECUTE v_nuevo;
        v_tocados := v_tocados + 1;
        RAISE NOTICE '% → jefe_operaciones autorizado', r.proname;
    END LOOP;

    RAISE NOTICE 'Funciones actualizadas: %', v_tocados;
END $mig$;

-- ── Verificación: las 4 tienen que nombrar al rol ─────────────────────────
DO $chk$
DECLARE v_falta TEXT;
BEGIN
    SELECT string_agg(p.proname, ', ')
      INTO v_falta
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('rpc_certificacion_fijar_fecha',
                         'rpc_certificacion_descartar_propuesta',
                         'rpc_certificacion_no_caduca',
                         'rpc_certificacion_vuelve_a_caducar')
       AND pg_get_functiondef(p.oid) NOT LIKE '%jefe_operaciones%';
    IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: siguen sin permitir jefe_operaciones: %', v_falta;
    END IF;
END $chk$;

-- ── Prueba con la sesión de un jefe de operaciones de verdad ──────────────
-- Se llama con un id de documento inexistente a propósito: el control de rol
-- corre ANTES de buscar el documento, así que "no se encontró el documento"
-- prueba que el rol pasó, sin escribir nada en la flota.
DO $prueba$
DECLARE
    v_jefe UUID;
    v_msg  TEXT;
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
        PERFORM rpc_certificacion_fijar_fecha(
            '00000000-0000-0000-0000-000000000000'::uuid, CURRENT_DATE + 30);
        RAISE EXCEPTION 'FALLO: se esperaba «el certificado no existe»';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF v_msg ILIKE '%no puede fijar vencimientos%' THEN
            RAISE EXCEPTION 'FALLO: el jefe de operaciones sigue bloqueado (%)', v_msg;
        END IF;
        RAISE NOTICE 'fijar_fecha OK para jefe_operaciones (llegó a: %)', v_msg;
    END;

    BEGIN
        PERFORM rpc_certificacion_no_caduca(
            '00000000-0000-0000-0000-000000000000'::uuid, 'este', 'prueba MIG439');
        RAISE EXCEPTION 'FALLO: se esperaba «no se encontró el documento»';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF v_msg ILIKE '%No tienes permiso%' THEN
            RAISE EXCEPTION 'FALLO: «no caduca» sigue bloqueado (%)', v_msg;
        END IF;
        RAISE NOTICE 'no_caduca OK para jefe_operaciones (llegó a: %)', v_msg;
    END;

    PERFORM set_config('request.jwt.claims', NULL, true);
END $prueba$;

COMMIT;

-- Estado final
SELECT p.proname,
       (pg_get_functiondef(p.oid) LIKE '%jefe_operaciones%') AS permite_jefe_operaciones
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('rpc_certificacion_fijar_fecha','rpc_certificacion_descartar_propuesta',
                     'rpc_certificacion_no_caduca','rpc_certificacion_vuelve_a_caducar',
                     'rpc_renovar_certificacion')
 ORDER BY 1;
