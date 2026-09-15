-- ============================================================================
-- MIG565 · La secretaria técnica de Romeral ve la documentación de su gente
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (15-09-2026)
-- «Necesito un usuario y contraseña para la secretaria técnica de Romeral,
-- Catalina, para que pueda ver documentación de personas y equipos.»
--
-- LO QUE ENCONTRÉ
-- Catalina Rojas YA tiene cuenta (catalina@pillado.cl, MIG352): rol
-- planificador, faena Romeral, solo_su_faena (MIG385). Su menú ya trae
-- «Equipos de la faena» (ficha → pestaña Documentos) y «Personal acreditado»
-- (/dashboard/prevencion/personal). Los papeles de los equipos los ve: la
-- tabla certificaciones deja leer a cualquier autenticado.
--
-- Lo que NO ve es la gente. fn_prevencion_personal_puede_ver() autoriza por
-- defecto a administrador, gerencia, subgerencia, prevencionista, jefaturas,
-- supervisor, auditor y rrhh_incentivos — el planificador no está. Con RLS
-- encima de prevencion_personal y prevencion_examenes, la pantalla le carga
-- vacía sin decir por qué.
--
-- LA CORRECCIÓN
-- El permiso se configura, no se recodifica: una fila en rol_permisos_modulo
-- (lo mismo que hace Admin → Perfiles y roles) da al rol planificador
-- `prevencion: view`. Es por ROL, así que Eduardo (taller Coquimbo) y María
-- Isabel también podrán LEER prevención; ninguno podía crear ni editar ahí y
-- eso no cambia. Catalina sigue acotada a Romeral por solo_su_faena.
--
-- La contraseña de Catalina se restablece aparte, fuera del repositorio.
-- ============================================================================

BEGIN;

DO $chk$
DECLARE r RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM rol_permisos_modulo WHERE rol = 'planificador' AND modulo = 'prevencion') THEN
        RAISE EXCEPTION 'Ya hay un override planificador/prevencion: revisar a mano antes de pisarlo';
    END IF;
    -- Un override es TOTAL para (rol, módulo): si alguna función diera al
    -- planificador una acción distinta de view por defecto, esta fila se la
    -- quitaría. Se comprueba que no exista tal caso.
    FOR r IN
        SELECT p.proname
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND pg_get_functiondef(p.oid) ~ $re$fn_tiene_permiso_modulo\('prevencion',\s*'(create|edit|delete|approve|export)'$re$
           AND pg_get_functiondef(p.oid) ~ 'planificador'
    LOOP
        RAISE EXCEPTION 'FALLO: % da al planificador una acción de prevención distinta de view; el override la anularía', r.proname;
    END LOOP;
END $chk$;

INSERT INTO public.rol_permisos_modulo (rol, modulo, permisos, es_extendido, updated_at)
VALUES ('planificador', 'prevencion', ARRAY['view'], false, NOW());

-- ── Verificación: como Catalina, la función de RLS tiene que decir que sí ──
DO $ver$
DECLARE v_id UUID; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_id FROM auth.users WHERE email = 'catalina@pillado.cl';
    IF v_id IS NULL THEN RAISE EXCEPTION 'catalina@pillado.cl no existe'; END IF;
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
    SELECT fn_prevencion_personal_puede_ver() INTO v_ok;
    PERFORM set_config('request.jwt.claims', '', true);
    IF NOT v_ok THEN RAISE EXCEPTION 'FALLO: Catalina sigue sin poder ver el control documental'; END IF;
    RAISE NOTICE 'Catalina (planificador, Romeral) → fn_prevencion_personal_puede_ver = %', v_ok;
END $ver$;

COMMIT;
