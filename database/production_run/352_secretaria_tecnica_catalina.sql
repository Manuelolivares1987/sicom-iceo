-- ============================================================================
-- MIG352 · La secretaria técnica es quien maneja Orpak, y sólo ella
-- ----------------------------------------------------------------------------
-- Tres correcciones al alta de MIG351, con lo que corresponde de verdad:
--
-- 1. ELIANA RIVERA YA NO ESTÁ EN LA FAENA
--    Se desactiva la cuenta, no se borra. Si mañana hay que revisar un cierre
--    de julio, el nombre que lo firmó tiene que seguir existiendo: borrar a la
--    persona borra la trazabilidad de lo que hizo mientras estuvo.
--
-- 2. CATALINA ES LA SECRETARIA TÉCNICA
--    Es quien saca la información desde Orpak y arma el cierre. Todo el módulo
--    de ingesta existe para sacarle ese trabajo de las manos: hasta hoy lo
--    hace a mano, con una aplicación aparte, y de ahí vienen buena parte de
--    los problemas que se venían arrastrando.
--
-- 3. LOS JEFES DE TURNO YA NO CARGAN ORPAK
--    En MIG351 quedaron pudiendo hacerlo porque no había forma de separarlos.
--    Ahora sí la hay y corresponde usarla: cargar el archivo reescribe la
--    imputación de todo un período, y reabrir un cierre cambia un documento
--    que ya se informó. Eso es del escritorio, no de la estación.
--
--    El permiso `inventario:approve` lo consulta UNA sola función en todo el
--    sistema —fn_comb_puede_administrar— así que quitárselo al rol supervisor
--    no toca nada más: ni Calama, ni Coquimbo, ni ENEX, ni bodega. Se verificó
--    antes de escribir esto.
--
--    Quedan con ese permiso: administrador, gerencia, subgerencia de
--    operaciones, jefatura de operaciones y planificador — que es el rol con
--    el que entra la secretaria técnica.
-- ============================================================================

BEGIN;

-- ── 1. Eliana ya no está ───────────────────────────────────────────────────
UPDATE public.usuarios_perfil
   SET activo = false, updated_at = NOW()
 WHERE email = 'erivera@pillado.cl';

-- ── 2. Catalina entra como secretaria técnica ──────────────────────────────
DO $alta$
DECLARE
    v_faena UUID := (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL');
    v_id    UUID;
    v_mail  TEXT := 'catalina@pillado.cl';
BEGIN
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_mail) THEN
        RAISE NOTICE 'La cuenta % ya existe.', v_mail;
        RETURN;
    END IF;

    v_id := gen_random_uuid();

    -- Los ocho campos de texto en CADENA VACIA, nunca NULL: con NULL el login
    -- revienta sin decir por que.
    INSERT INTO auth.users (
        id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change,
        email_change_token_new, email_change_token_current,
        phone_change, phone_change_token, reauthentication_token
    ) VALUES (
        v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        v_mail, 'SIN_CONTRASENA_ASIGNADA', NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('rol', 'planificador', 'nombre_completo', 'Catalina'),
        NOW(), NOW(), '', '', '', '', '', '', '', ''
    );

    INSERT INTO auth.identities (
        id, user_id, provider, provider_id, identity_data,
        created_at, updated_at, last_sign_in_at
    ) VALUES (
        gen_random_uuid(), v_id, 'email', v_id::text,
        jsonb_build_object('sub', v_id::text, 'email', v_mail,
                           'email_verified', true, 'phone_verified', false),
        NOW(), NOW(), NULL
    );

    INSERT INTO usuarios_perfil (id, email, nombre_completo, cargo, rol, faena_id, activo)
    VALUES (v_id, v_mail, 'Catalina', 'Secretaria técnica',
            'planificador'::rol_usuario_enum, v_faena, true);

    RAISE NOTICE 'Catalina creada como secretaria tecnica (falta completar el apellido).';
END $alta$;

-- ── 3. El supervisor deja de poder cargar Orpak y reabrir cierres ──────────
INSERT INTO public.rol_permisos_modulo (rol, modulo, permisos, es_extendido, updated_at)
VALUES ('supervisor', 'inventario',
        ARRAY['view','create','edit','export'], false, NOW())
ON CONFLICT DO NOTHING;

COMMIT;
