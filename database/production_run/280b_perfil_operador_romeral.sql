-- ============================================================================
-- SICOM-ICEO | 280b — Perfil de la cuenta compartida del camión de Romeral
-- ============================================================================
-- CORRER DESPUÉS de crear la credencial en Supabase (Authentication → Add user)
-- con el correo de abajo. La contraseña la define quien crea la cuenta; este
-- script solo le da el perfil y el rol dentro del sistema.
--
-- Es una cuenta COMPARTIDA por los operadores que se turnan en el camión: cada
-- uno escribe su nombre en la app al empezar el turno, y ese nombre es el que
-- queda en cada despacho. Mismo criterio que la cuenta de los mecánicos
-- (operador.taller@sicom-iceo.cl).
--
-- El rol operador_combustible no ve nada más que /m/romeral: esa credencial
-- vive en un teléfono en faena y va a circular.
-- IDEMPOTENTE.
-- ============================================================================

DO $$
DECLARE
    v_email TEXT := 'operador.romeral@sicom-iceo.cl';
    v_uid   UUID;
BEGIN
    SELECT id INTO v_uid FROM auth.users WHERE lower(email) = lower(v_email);

    IF v_uid IS NULL THEN
        RAISE EXCEPTION
          'No existe el usuario % en Supabase. Créalo primero en Authentication → Users → Add user (y define ahí la contraseña).',
          v_email;
    END IF;

    INSERT INTO usuarios_perfil (id, nombre_completo, rol, activo)
    VALUES (v_uid, 'Operador Camión Romeral', 'operador_combustible', TRUE)
    ON CONFLICT (id) DO UPDATE
        SET rol = 'operador_combustible',
            nombre_completo = COALESCE(usuarios_perfil.nombre_completo, 'Operador Camión Romeral'),
            activo = TRUE;

    RAISE NOTICE 'Perfil listo para % (rol operador_combustible)', v_email;
END $$;

SELECT up.id, u.email, up.nombre_completo, up.rol, up.activo
  FROM usuarios_perfil up
  JOIN auth.users u ON u.id = up.id
 WHERE up.rol = 'operador_combustible';
