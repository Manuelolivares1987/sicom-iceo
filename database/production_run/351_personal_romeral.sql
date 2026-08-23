-- ============================================================================
-- MIG351 · El personal de Romeral entra al sistema con nombre propio
-- ----------------------------------------------------------------------------
-- Hasta hoy Romeral tenía UNA cuenta compartida de operador para toda la
-- faena. Con eso el sistema no puede decir quién hizo qué más allá del nombre
-- que alguien teclea, y esa es justamente la pregunta que hace el mandante
-- cuando algo no cuadra.
--
-- El personal sale de la liquidación de julio 2026. Son diez personas y la
-- dotación confirma el turno 4x4: CUATRO jefes de turno, que son dos
-- cuadrillas de día y noche. Y aparece Álvaro Corrales, que es el nombre que
-- firma «Realizado por» en la planilla de Cierre Romeral — o sea, el jefe de
-- turno es efectivamente quien hace el cierre.
--
-- CÓMO SE REPARTEN LOS ROLES
--   supervisor            los 4 jefes de turno · reciben, miden y firman
--   planificador          la secretaria técnica · Orpak, excepciones, entregables
--   operador_combustible  los 5 conductores · sólo registran sus cargas
--
-- Los dos primeros hoy resuelven al mismo conjunto de permisos. Son roles
-- distintos a propósito: desde Admin → Perfiles y roles se le puede quitar al
-- supervisor el permiso de «aprobar» en inventario —que es cargar Orpak y
-- reabrir cierres— sin tocar una migración. Esa flexibilidad es la razón por
-- la que las tres puertas del módulo preguntan por PERMISO y no por rol.
--
-- SIN CONTRASEÑA, A PROPÓSITO
-- Las cuentas nacen bloqueadas: existen, tienen su rol y su faena, y nadie
-- puede entrar todavía. Poner la contraseña le corresponde a quien administra
-- el sistema, no a quien lo construye. Al final de este archivo está el
-- comando para hacerlo, que se ejecuta localmente y no deja la clave escrita
-- en ninguna parte.
--
-- No se guardan RUT ni datos de la liquidación: para operar hace falta el
-- nombre, el cargo y el rol, y nada más.
-- ============================================================================

BEGIN;

DO $alta$
DECLARE
    v_faena UUID := (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL');
    v_id    UUID;
    p       RECORD;
    v_nuevos INT := 0;
BEGIN
    IF v_faena IS NULL THEN
        RAISE EXCEPTION 'No existe la faena Romeral.';
    END IF;

    FOR p IN
        SELECT * FROM (VALUES
            ('acorrales@pillado.cl', 'Álvaro Corrales González',  'Jefe de turno',       'supervisor'),
            ('jalfaro@pillado.cl',   'Jorge Alfaro Bugueño',      'Jefe de turno',       'supervisor'),
            ('pastorga@pillado.cl',  'Pablo Astorga Cortés',      'Jefe de turno',       'supervisor'),
            ('mgomez@pillado.cl',    'Mario Gómez Castañeda',     'Jefe de turno',       'supervisor'),
            ('erivera@pillado.cl',   'Eliana Rivera Berríos',     'Secretaria técnica',  'planificador'),
            ('otapia@pillado.cl',    'Omar Tapia Rivera',         'Conductor operador',  'operador_combustible'),
            ('orivera@pillado.cl',   'Óscar Rivera Saavedra',     'Conductor operador',  'operador_combustible'),
            ('eguerrero@pillado.cl', 'Erick Guerrero Díaz',       'Conductor operador',  'operador_combustible'),
            ('nrojas@pillado.cl',    'Nicolás Rojas Vega',        'Conductor operador',  'operador_combustible'),
            ('lvera@pillado.cl',     'Luis Vera Contreras',       'Electromecánico · conductor operador', 'operador_combustible')
        ) AS t(email, nombre, cargo, rol)
    LOOP
        SELECT id INTO v_id FROM auth.users WHERE email = p.email;
        IF v_id IS NOT NULL THEN
            RAISE NOTICE 'ya existe: %', p.email;
            CONTINUE;
        END IF;

        v_id := gen_random_uuid();

        -- Los ocho campos de texto van en CADENA VACIA, nunca NULL: el driver
        -- de GoTrue los lee como string no-nullable y con NULL el login
        -- revienta sin decir por que. Es lo que dejo cuentas inservibles antes.
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
            p.email,
            -- Bloqueada: no es un hash valido, asi que ninguna contrasena entra.
            -- La pone quien administra, con el comando del final del archivo.
            'SIN_CONTRASENA_ASIGNADA',
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('rol', p.rol, 'nombre_completo', p.nombre),
            NOW(), NOW(),
            '', '', '', '', '', '', '', ''
        );

        -- Sin esta fila el login falla aunque el usuario exista.
        INSERT INTO auth.identities (
            id, user_id, provider, provider_id, identity_data,
            created_at, updated_at, last_sign_in_at
        ) VALUES (
            gen_random_uuid(), v_id, 'email', v_id::text,
            jsonb_build_object('sub', v_id::text, 'email', p.email,
                               'email_verified', true, 'phone_verified', false),
            NOW(), NOW(), NULL
        );

        INSERT INTO usuarios_perfil (id, email, nombre_completo, cargo, rol, faena_id, activo)
        VALUES (v_id, p.email, p.nombre, p.cargo, p.rol::rol_usuario_enum, v_faena, true);

        v_nuevos := v_nuevos + 1;
    END LOOP;

    RAISE NOTICE 'Cuentas creadas: % (bloqueadas hasta que se les asigne contrasena)', v_nuevos;
END $alta$;

COMMIT;

-- ============================================================================
-- PARA ACTIVARLAS
-- ----------------------------------------------------------------------------
-- Ejecutar esto en el terminal, reemplazando LA-CLAVE por la que se quiera.
-- La clave queda sólo en esa línea, en el computador de quien la escribe:
--
--   node database/scripts/psql-cli.mjs "UPDATE auth.users SET encrypted_password =
--     extensions.crypt('LA-CLAVE', extensions.gen_salt('bf')), updated_at = NOW()
--     WHERE email LIKE '%@pillado.cl' AND encrypted_password = 'SIN_CONTRASENA_ASIGNADA'"
--
-- Conviene que cada persona la cambie después. Y verificar SIEMPRE con un
-- login real antes de dar una cuenta por buena: una cuenta que existe y no
-- deja entrar es peor que una que no existe, porque nadie la revisa.
-- ============================================================================
