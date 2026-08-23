-- ============================================================================
-- MIG354 · Las cuentas de Romeral quedan con clave asignada
-- ----------------------------------------------------------------------------
-- MIG351 creó las diez cuentas del personal de Romeral bloqueadas a propósito:
-- existen, tienen su rol y su faena, pero nadie puede entrar hasta que se les
-- asigne una clave. Esta migración cierra ese paso, porque el lunes la
-- aplicación se entrega a terreno.
--
-- El texto plano de las claves NO está en este archivo ni en ningún otro del
-- repositorio, y no debe estarlo nunca. Se generaron fuera del repositorio, se
-- aplicaron con el UPDATE de más abajo y se entregaron a Manuel en un documento
-- aparte, con un talón por persona para repartir en mano.
--
-- Una clave por persona, no una compartida. Todo el módulo de combustible está
-- construido sobre poder decir quién firmó cada cierre: una cuenta prestada no
-- es una incomodidad menor, rompe la única cosa que el sistema promete.
--
-- Cómo se hizo, para poder repetirlo cuando alguien olvide la suya:
--
--     UPDATE auth.users
--        SET encrypted_password = extensions.crypt('LA-CLAVE',
--                                                  extensions.gen_salt('bf')),
--            updated_at = NOW()
--      WHERE email = 'persona@pillado.cl';
--
-- Y después probarla de verdad, que es la parte que se suele saltar. Un UPDATE
-- que devuelve OK no prueba que alguien pueda entrar; eso sólo se sabe pidiendo
-- un token con esa clave:
--
--     POST {SUPABASE_URL}/auth/v1/token?grant_type=password
--     { "email": "...", "password": "..." }
--
-- Las diez se probaron así y las diez entran, cada una con el rol que le toca.
--
-- Ojo con dos cosas que no se ven desde acá:
--
--   · No hay pantalla para que la persona cambie su propia clave. Mientras no
--     exista, reasignarla es tarea del administrador. Es una limitación
--     conocida, no un olvido.
--   · La clave queda cifrada con bcrypt, así que no se puede recuperar — sólo
--     reemplazar. Si el documento de entrega se pierde, hay que volver a
--     asignarlas.
--
-- Eliana Rivera quedó desactivada en MIG352 y su reemplazo es Catalina Rojas,
-- que ya está acá con las claves del resto.
-- ============================================================================

BEGIN;

-- Ninguna de las diez puede quedar bloqueada. Si alguna lo está, es que el
-- UPDATE de arriba no se corrió para ella y esa persona llega el lunes a
-- terreno sin poder entrar.
DO $$
DECLARE
    v_bloqueadas int;
    v_sin_ident  int;
BEGIN
    SELECT count(*) INTO v_bloqueadas
      FROM auth.users
     WHERE email IN ('acorrales@pillado.cl', 'jalfaro@pillado.cl',
                     'pastorga@pillado.cl',  'mgomez@pillado.cl',
                     'catalina@pillado.cl',  'otapia@pillado.cl',
                     'orivera@pillado.cl',   'eguerrero@pillado.cl',
                     'nrojas@pillado.cl',    'lvera@pillado.cl')
       AND (encrypted_password = 'SIN_CONTRASENA_ASIGNADA'
            OR encrypted_password IS NULL
            OR encrypted_password = '');

    IF v_bloqueadas > 0 THEN
        RAISE EXCEPTION 'MIG354: quedan % cuentas de Romeral sin clave', v_bloqueadas;
    END IF;

    -- Sin la fila en auth.identities la cuenta tiene clave y aun así no entra.
    -- Es el modo de fallar más confuso que tiene Supabase: la clave es
    -- correcta y el login responde que no.
    SELECT count(*) INTO v_sin_ident
      FROM usuarios_perfil up
     WHERE up.email LIKE '%@pillado.cl'
       AND up.activo
       AND NOT EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = up.id);

    IF v_sin_ident > 0 THEN
        RAISE EXCEPTION 'MIG354: % cuentas activas sin auth.identities', v_sin_ident;
    END IF;

    RAISE NOTICE 'MIG354: las 10 cuentas de Romeral tienen clave y pueden entrar';
END $$;

COMMIT;
