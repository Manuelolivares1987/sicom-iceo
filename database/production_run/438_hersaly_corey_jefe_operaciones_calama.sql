-- ============================================================================
-- MIG438 · Hersaly Corey entra como jefe de operaciones de Calama
-- ----------------------------------------------------------------------------
-- Todo lo que es Calama lo ve él: Operación Calama (obras civiles, llave en
-- mano) y el Contrato ENEX/ESM, más Flota. Lo de Coquimbo, Romeral y Franke no
-- le aparece.
--
-- CÓMO SE LOGRA, con lo que ya existe (no se inventa nada):
--
--   · usuarios_perfil.rol = 'jefe_operaciones'
--     Le abre ENEX para gestionar (fn_enex_puede_gestionar ya lo incluye) y
--     planificar en Calama (fn_calama_puede_planificar ya lo incluye).
--
--   · usuarios_perfil.ambito = 'calama'   ← el recorte del menú, de MIG233
--     Deja a la vista: Dashboard + Operación Calama + Contrato ENEX + Flota.
--     Esa columna se creó por este mismo pedido; acá solo se usa.
--
--   · calama_roles_proyecto.rol_calama = 'jefe_sucursal'
--     El hueco que había: fn_calama_puede_importar NO incluye
--     'jefe_operaciones'. Sin este rol de proyecto no podría subir el Excel de
--     la Carta Gantt de su propia operación. Con él, sí.
--
-- ALCANCE REAL, dicho sin adornos: el ámbito recorta el MENÚ y la navegación.
-- NO es RLS. Quien consulte la API a mano sigue alcanzando lo demás. Es el
-- mismo alcance que tiene hoy solo_su_faena (ver MIG385) y es consistente con
-- el resto del sistema; blindarlo sería RLS por ámbito en cada tabla.
--
-- Cuenta propia, no la genérica jefe.calama@sicom-iceo.cl: con un contrato que
-- tiene multas por incumplimiento, lo que él apruebe, planifique o acepte
-- tiene que quedar con su nombre en la auditoría, no con el de un cargo.
--
-- IDEMPOTENTE: si la cuenta ya existe, no la duplica — actualiza rol y ámbito.
-- ============================================================================

BEGIN;

-- ┌────────────────────────────────────────────────────────────────────────┐
-- │ DATOS DE LA PERSONA — lo único que hay que revisar antes de aplicar    │
-- └────────────────────────────────────────────────────────────────────────┘
DO $alta$
DECLARE
    -- Correo por la convención de las cuentas personales: inicial + apellido,
    -- igual que acorrales, jalfaro, mgomez, hcortes. Verificado libre.
    c_nombre   TEXT := 'Hersaly Corey';
    c_email    TEXT := 'hcorey@pillado.cl';
    c_rut      TEXT := NULL;                        -- se completa desde Admin
    c_telefono TEXT := NULL;                        -- se completa desde Admin
    c_password TEXT := 'Calama.2026';               -- provisoria, la cambia al entrar

    c_cargo   CONSTANT TEXT := 'Jefe de Operaciones Calama';
    c_rol     CONSTANT TEXT := 'jefe_operaciones';
    c_ambito  CONSTANT TEXT := 'calama';

    v_id    UUID;
    v_faena UUID := (SELECT id FROM faenas WHERE codigo = 'FAE-TALLER-CAL');
    v_nueva BOOLEAN := false;
BEGIN
    IF c_email IS NULL OR c_email NOT LIKE '%@%' THEN
        RAISE EXCEPTION 'STOP - falta el correo de la persona.';
    END IF;
    IF c_password IS NULL OR LENGTH(c_password) < 8 THEN
        RAISE EXCEPTION 'STOP - la contrasena provisoria debe tener 8+ caracteres.';
    END IF;

    SELECT id INTO v_id FROM auth.users WHERE email = c_email;

    IF v_id IS NULL THEN
        v_id    := gen_random_uuid();
        v_nueva := true;

        -- Los ocho campos de texto en CADENA VACIA, nunca NULL: el driver de
        -- GoTrue los lee como string no-nullable y con NULL el login revienta
        -- sin decir por que. Esto es lo que dejo cuentas inservibles antes.
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
            c_email,
            extensions.crypt(c_password, extensions.gen_salt('bf')),
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object('rol', c_rol, 'nombre_completo', c_nombre),
            NOW(), NOW(), '', '', '', '', '', '', '', ''
        );
    END IF;

    -- auth.identities es obligatoria: sin esa fila el login falla aunque el
    -- usuario exista.
    IF NOT EXISTS (SELECT 1 FROM auth.identities WHERE user_id = v_id AND provider = 'email') THEN
        INSERT INTO auth.identities (
            id, user_id, provider, provider_id, identity_data,
            created_at, updated_at, last_sign_in_at
        ) VALUES (
            gen_random_uuid(), v_id, 'email', v_id::text,
            jsonb_build_object('sub', v_id::text, 'email', c_email,
                               'email_verified', true, 'phone_verified', false),
            NOW(), NOW(), NULL
        );
    END IF;

    -- Perfil: acá viven el rol que lee fn_user_rol() y el ámbito del menú.
    INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, telefono, cargo,
                                 rol, faena_id, ambito, activo)
    VALUES (v_id, c_email, c_nombre, c_rut, c_telefono, c_cargo,
            c_rol::rol_usuario_enum, v_faena, c_ambito, true)
    ON CONFLICT (id) DO UPDATE
       SET nombre_completo = EXCLUDED.nombre_completo,
           cargo           = EXCLUDED.cargo,
           rol             = EXCLUDED.rol,
           ambito          = EXCLUDED.ambito,
           rut             = COALESCE(EXCLUDED.rut, usuarios_perfil.rut),
           telefono        = COALESCE(EXCLUDED.telefono, usuarios_perfil.telefono),
           faena_id        = COALESCE(EXCLUDED.faena_id, usuarios_perfil.faena_id),
           activo          = true,
           updated_at      = NOW();

    -- Rol de proyecto Calama: lo que le falta a 'jefe_operaciones' para poder
    -- importar la Carta Gantt de su propia operación.
    IF NOT EXISTS (SELECT 1 FROM calama_roles_proyecto
                    WHERE usuario_id = v_id AND rol_calama = 'jefe_sucursal' AND activo) THEN
        INSERT INTO calama_roles_proyecto (usuario_id, rol_calama, activo, asignado_at, notas)
        VALUES (v_id, 'jefe_sucursal', true, NOW(),
                'MIG438 - jefe de operaciones de Calama, puede importar y planificar');
    END IF;

    RAISE NOTICE '% % (%) como % — ambito %, rol de proyecto jefe_sucursal',
        CASE WHEN v_nueva THEN 'CREADO:' ELSE 'ACTUALIZADO:' END,
        c_nombre, c_email, c_rol, c_ambito;
END $alta$;

COMMIT;


-- ============================================================================
-- Validación: qué quedó realmente
-- ============================================================================
SELECT up.nombre_completo,
       up.email,
       up.cargo,
       up.rol::text                                    AS rol_global,
       up.ambito,
       f.codigo                                        AS faena_base,
       cr.rol_calama                                   AS rol_proyecto_calama,
       (SELECT COUNT(*) FROM auth.identities i WHERE i.user_id = up.id) AS identities,
       (u.encrypted_password LIKE '$2%')               AS password_valida,
       u.email_confirmed_at IS NOT NULL                AS confirmado
  FROM usuarios_perfil up
  JOIN auth.users u        ON u.id = up.id
  LEFT JOIN faenas f       ON f.id = up.faena_id
  LEFT JOIN calama_roles_proyecto cr
         ON cr.usuario_id = up.id AND cr.activo
 WHERE up.ambito = 'calama'
 ORDER BY up.nombre_completo;
