-- ============================================================================
-- MIG361 · El personal de Franke entra al sistema con nombre propio
-- ----------------------------------------------------------------------------
-- La pauta del mecánico (MIG357-359) quedó construida y sin nadie que pudiera
-- abrirla: Franke no tenía una sola cuenta en SICOM. Once personas, que salen
-- de la dotación declarada en el Informe de Gestión de julio 2026 y de la tabla
-- «Dotación del Turno» de la entrega del 06-12 de agosto.
--
--   TURNO A   Jacinto Simón Saldaña    Supervisor
--             Edison Arqueros          Supervisor (R)
--             Hernán Cortés            Mecánico
--             Jorge Cuevas             Conductor-operador
--             Felipe López             Conductor-operador
--             Daniel Berrios           Conductor-operador
--
--   TURNO B   Marcelo Espinosa Ríos    Supervisor
--             Yohan Rondón Andara      Mecánico
--             José Contreras Machuca   Conductor-operador
--             Omar Tapia Valle         Conductor-operador
--             Gabriel Durán Ramírez    Conductor-operador
--
-- CÓMO SE REPARTEN LOS ROLES, Y POR QUÉ
--   supervisor            reciben el turno, miden, verifican y firman
--   tecnico_mantenimiento los dos mecánicos · ejecutan la pauta de faena
--   operador_combustible  los seis conductores · sólo registran sus cargas
--
-- Es el mismo reparto que Romeral (MIG351/343): quien despacha no certifica
-- cuánto salió. Lo único distinto es el mecánico, que en Romeral no existe como
-- rol propio porque allá el electromecánico es además conductor.
--
-- ─────────────────────────────────────────────────────────────────────────
-- DOS NOMBRES QUE YA ESTABAN EN EL SISTEMA, Y NO SON LOS MISMOS
--
-- «Yohan Rondón» existe como tecnico.pc@sicom-iceo.cl desde el sembrado de
-- marzo 2026, en el taller de Coquimbo y sin haber entrado nunca. Es un dato de
-- demostración que tomó prestado un nombre real.
--
-- «Felipe López» existe como felipe.lopez@sicom-iceo.cl, es el auditor de
-- calidad del taller de Coquimbo y entró al sistema el 13 de agosto. Ese SÍ se
-- usa. El Felipe López de Franke es conductor-operador del turno A en Taltal:
-- por lo que dicen los cargos y las faenas, no son la misma persona.
--
-- Ninguna de las dos cuentas se toca acá. Quedan anotadas como pendiente para
-- que alguien que conozca a la gente lo confirme: dos personas distintas con el
-- mismo nombre en una lista desplegable es un problema de operación, y fusionar
-- o desactivar la cuenta equivocada es peor que dejar la duda escrita.
--
-- ─────────────────────────────────────────────────────────────────────────
-- OJO CON LOS DOS OMAR TAPIA
-- Romeral tiene a Omar Tapia RIVERA (otapia@pillado.cl) y Franke a Omar Tapia
-- VALLE. Son dos personas. El correo del segundo lleva la inicial del segundo
-- apellido, otapiav@, a propósito.
--
-- ─────────────────────────────────────────────────────────────────────────
-- CADA FAENA SABE CUÁL ES SU APLICACIÓN DE TERRENO
-- Hasta hoy el sistema mandaba a TODO operador de combustible a /m/romeral,
-- porque Romeral era la única faena con app. Con Franke adentro eso deja de ser
-- una simplificación y pasa a ser un error: un conductor de Taltal aterrizaría
-- en la app de otra faena, con otro catálogo y otros camiones.
--
-- La ruta pasa a ser un dato de la faena. Así, el día que otra faena tenga su
-- app, se declara acá y no se toca código.
--
-- SIN CONTRASEÑA, A PROPÓSITO
-- Las cuentas nacen bloqueadas. Ponerle la clave a alguien le corresponde a
-- quien administra el sistema, no a quien lo construye. El comando está al
-- final del archivo, y se ejecuta localmente sin dejar la clave escrita en
-- ninguna parte del repositorio.
-- ============================================================================

BEGIN;

-- ── Cada faena declara su aplicación de terreno ───────────────────────────
ALTER TABLE public.faenas
    ADD COLUMN IF NOT EXISTS app_movil TEXT;

COMMENT ON COLUMN public.faenas.app_movil IS
  'Ruta de la app de terreno de esta faena (/m/romeral, /m/franke). La gente de terreno aterriza aca al entrar. NULL = la faena no tiene app propia. MIG361.';

UPDATE public.faenas SET app_movil = '/m/romeral' WHERE codigo = 'FAE-CMP-ROMERAL';
UPDATE public.faenas SET app_movil = '/m/franke'  WHERE codigo = 'FAE-FRANCKE';


DO $alta$
DECLARE
    v_faena  UUID := (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');
    v_id     UUID;
    p        RECORD;
    v_nuevos INT := 0;
BEGIN
    IF v_faena IS NULL THEN
        RAISE EXCEPTION 'MIG361: no existe la faena Franke.';
    END IF;

    FOR p IN
        SELECT * FROM (VALUES
            -- Turno A
            ('jsimon@pillado.cl',     'Jacinto Simón Saldaña',  'Supervisor de turno',     'supervisor',            'A'),
            ('earqueros@pillado.cl',  'Edison Arqueros',        'Supervisor de turno (R)', 'supervisor',            'A'),
            ('hcortes@pillado.cl',    'Hernán Cortés',          'Mecánico de faena',       'tecnico_mantenimiento', 'A'),
            ('jcuevas@pillado.cl',    'Jorge Cuevas',           'Conductor operador',      'operador_combustible',  'A'),
            ('flopez@pillado.cl',     'Felipe López Franke',    'Conductor operador',      'operador_combustible',  'A'),
            ('dberrios@pillado.cl',   'Daniel Berrios',         'Conductor operador',      'operador_combustible',  'A'),
            -- Turno B
            ('mespinosa@pillado.cl',  'Marcelo Espinosa Ríos',  'Supervisor de turno',     'supervisor',            'B'),
            ('yrondon@pillado.cl',    'Yohan Rondón Andara',    'Mecánico de faena',       'tecnico_mantenimiento', 'B'),
            ('jcontreras@pillado.cl', 'José Contreras Machuca', 'Conductor operador',      'operador_combustible',  'B'),
            ('otapiav@pillado.cl',    'Omar Tapia Valle',       'Conductor operador',      'operador_combustible',  'B'),
            ('gduran@pillado.cl',     'Gabriel Durán Ramírez',  'Conductor operador',      'operador_combustible',  'B')
        ) AS t(email, nombre, cargo, rol, turno)
    LOOP
        SELECT id INTO v_id FROM auth.users WHERE email = p.email;
        IF v_id IS NOT NULL THEN
            RAISE NOTICE 'MIG361 · ya existe: %', p.email;
            CONTINUE;
        END IF;

        v_id := gen_random_uuid();

        -- Los ocho campos de texto van en CADENA VACÍA, nunca NULL: el driver
        -- de GoTrue los lee como string no-nullable y con NULL el login
        -- revienta sin decir por qué.
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
            'SIN_CONTRASENA_ASIGNADA',
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('rol', p.rol, 'nombre_completo', p.nombre),
            NOW(), NOW(),
            '', '', '', '', '', '', '', ''
        );

        -- Sin esta fila el login falla aunque la clave sea correcta. Es el modo
        -- de fallar más confuso que tiene Supabase.
        INSERT INTO auth.identities (
            id, user_id, provider, provider_id, identity_data,
            created_at, updated_at, last_sign_in_at
        ) VALUES (
            gen_random_uuid(), v_id, 'email', v_id::text,
            jsonb_build_object('sub', v_id::text, 'email', p.email,
                               'email_verified', true, 'phone_verified', false),
            NOW(), NOW(), NULL
        );

        INSERT INTO public.usuarios_perfil
               (id, email, nombre_completo, cargo, rol, faena_id, activo)
        VALUES (v_id, p.email, p.nombre,
                p.cargo || ' · turno ' || p.turno,
                p.rol::rol_usuario_enum, v_faena, TRUE);

        v_nuevos := v_nuevos + 1;
    END LOOP;

    RAISE NOTICE 'MIG361 · cuentas Franke creadas: % (bloqueadas hasta que se les asigne clave)', v_nuevos;
END
$alta$;


-- ── Lo que hay que confirmar con alguien que conozca a la gente ───────────
INSERT INTO public.combustible_faena_pendiente
       (faena_id, texto, origen, pedido_por, prioridad)
SELECT f.id,
       'Hay dos nombres repetidos entre Franke y Coquimbo y hace falta confirmar si son la misma '
    || 'persona. (1) «Felipe López»: el de Coquimbo es auditor de calidad y usa el sistema; el de '
    || 'Franke es conductor-operador del turno A y se creó como flopez@pillado.cl con el nombre '
    || '«Felipe López Franke» para poder distinguirlos en las listas. (2) «Yohan Rondón»: existe '
    || 'una cuenta de demostración de marzo (tecnico.pc@sicom-iceo.cl, nunca usada) con ese nombre; '
    || 'la real es yrondon@pillado.cl. Resolver desde Admin → Perfiles y roles.',
       'sistema', 'MIG361', 'normal'
  FROM public.faenas f
 WHERE f.codigo = 'FAE-FRANCKE'
   AND NOT EXISTS (
       SELECT 1 FROM public.combustible_faena_pendiente p
        WHERE p.faena_id = f.id AND p.pedido_por = 'MIG361' AND p.estado = 'abierto');

COMMIT;

-- ============================================================================
-- PARA ACTIVARLAS
-- ----------------------------------------------------------------------------
-- Una clave por persona, nunca una compartida: todo el módulo está construido
-- sobre poder decir quién firmó cada cierre.
--
--   node database/scripts/psql-cli.mjs "UPDATE auth.users SET encrypted_password =
--     extensions.crypt('LA-CLAVE', extensions.gen_salt('bf')), updated_at = NOW()
--     WHERE email = 'persona@pillado.cl'"
--
-- Y probarla de verdad, que es la parte que se suele saltar: un UPDATE que
-- devuelve OK no prueba que alguien pueda entrar.
--
--   POST {SUPABASE_URL}/auth/v1/token?grant_type=password
--   { "email": "...", "password": "..." }
-- ============================================================================
