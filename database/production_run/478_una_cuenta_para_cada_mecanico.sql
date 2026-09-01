-- ============================================================================
-- MIG478 · Una cuenta para cada mecánico
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «crea una cuenta para cada mecánico, así se ve su trabajo».
--
-- POR QUÉ IMPORTA MÁS DE LO QUE PARECE
-- Hoy el taller entra con la cuenta compartida «Jefe de Taller». Con eso, el
-- reloj de la OS no puede decir quién trabajó: MIG462 tuvo que repartir el bono
-- por jornadas asignadas o en partes iguales, porque el tiempo medido no se
-- podía atribuir a nadie. Con cuenta propia, el tiempo medido vuelve a ser la
-- primera regla del reparto y cada uno responde por lo suyo.
--
-- LA RECETA
-- La edge function admin-crear-usuario sigue sin desplegar, así que el alta va
-- por SQL. Los 8 campos de texto de auth.users van en CADENA VACÍA (con NULL el
-- driver de GoTrue revienta al iniciar sesión) y auth.identities es obligatoria.
--
-- CONVENCIÓN
-- Manuel pidió crearlas «como el jefe de taller»: dominio @sicom-iceo.cl con
-- nombre.apellido, igual que jefe.taller y felipe.lopez. Pero una por persona,
-- no de cargo — el punto de todo esto es que la auditoría diga la persona y no
-- el puesto. El cargo va en usuarios_perfil.cargo, como en las otras.
--
-- CLAVE DE ENTRADA
-- Una temporal común, para entregarla en el taller. Hay que cambiarla: mientras
-- sea la misma para todos, una cuenta personal sigue siendo compartida.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_tmp  TEXT := 'Taller2026.';
    v_uid  UUID;
    r RECORD;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('brian.alday@sicom-iceo.cl',    'Brian Alday',    'Brian Alday',    'Mecánico'),
            ('danny.guerra@sicom-iceo.cl',   'Danny Guerra',   'Danny Guerra',   'Soldador'),
            ('joel.coo@sicom-iceo.cl',       'Joel Coo',       'Joel Coo',       'Mecánico A'),
            ('jorge.castro@sicom-iceo.cl',   'Jorge Castro',   'Jorge Castro',   'Conductor operador'),
            ('marco.diaz@sicom-iceo.cl',     'Marco Díaz',     'Marco Díaz',     'Mecánico A'),
            ('yeran.sanhueza@sicom-iceo.cl', 'Yeran Sanhueza', 'Yeran Sanhueza', 'Mecánico B'),
            ('yusdel.sarduy@sicom-iceo.cl',  'Yusdel Sarduy',  'Yusdel Sarduy',  'Mecánico B')
        ) AS t(email, nombre, tecnico, cargo)
    LOOP
        SELECT id INTO v_uid FROM auth.users WHERE email = r.email;
        IF v_uid IS NOT NULL THEN
            RAISE NOTICE 'ya existía: %', r.email;
            CONTINUE;
        END IF;

        v_uid := gen_random_uuid();

        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at,
            confirmation_token, recovery_token, email_change,
            email_change_token_new, email_change_token_current,
            phone_change, phone_change_token, reauthentication_token
        ) VALUES (
            '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
            r.email, extensions.crypt(v_tmp, extensions.gen_salt('bf')),
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('rol', 'operador_taller', 'nombre_completo', r.nombre),
            NOW(), NOW(),
            '', '', '', '', '', '', '', ''
        );

        INSERT INTO auth.identities (
            id, user_id, provider, provider_id, identity_data,
            last_sign_in_at, created_at, updated_at
        ) VALUES (
            gen_random_uuid(), v_uid, 'email', v_uid::TEXT,
            jsonb_build_object('sub', v_uid::TEXT, 'email', r.email,
                               'email_verified', TRUE, 'phone_verified', FALSE),
            NULL, NOW(), NOW()
        );

        INSERT INTO usuarios_perfil (id, email, nombre_completo, cargo, rol, activo)
        VALUES (v_uid, r.email, r.nombre, r.cargo, 'operador_taller', TRUE);

        -- El técnico deja de ser un nombre suelto y pasa a tener dueño.
        UPDATE taller_tecnicos SET usuario_perfil_id = v_uid, updated_at = NOW()
         WHERE nombre = r.tecnico AND usuario_perfil_id IS NULL;

        RAISE NOTICE 'creada: % (%)', r.email, r.nombre;
    END LOOP;
END $$;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $$
DECLARE v_sin INT; v_con INT; v_id INT;
BEGIN
    SELECT count(*) INTO v_sin FROM taller_tecnicos WHERE activo AND usuario_perfil_id IS NULL;
    SELECT count(*) INTO v_con FROM taller_tecnicos WHERE activo AND usuario_perfil_id IS NOT NULL;
    SELECT count(*) INTO v_id FROM auth.identities i
      JOIN auth.users u ON u.id = i.user_id
     WHERE u.email LIKE '%@sicom-iceo.cl' AND u.raw_user_meta_data->>'rol' = 'operador_taller';
    RAISE NOTICE 'técnicos activos con cuenta: % · sin cuenta: % · identities de operador de taller: %',
                 v_con, v_sin, v_id;
END $$;

COMMIT;
