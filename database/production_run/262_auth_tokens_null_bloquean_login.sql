-- ============================================================================
-- SICOM-ICEO | 262 — Los NULL en auth.users rompen el login («Database error
--                    querying schema»)
-- ----------------------------------------------------------------------------
-- Segunda causa por la que las cuentas sembradas por SQL no podían entrar (la
-- primera, la identidad faltante, la arregló MIG261).
--
-- Al probar el login de Felipe con la contraseña recién puesta, la API de auth
-- devolvía:
--     {"code":500,"error_code":"unexpected_failure",
--      "msg":"Database error querying schema"}
--
-- CAUSA: GoTrue (el servicio de auth de Supabase) lee confirmation_token,
-- recovery_token, email_change y email_change_token_new como TEXTO, no como
-- nullable. Un INSERT hecho a mano los deja en NULL y el escaneo de la fila
-- revienta antes siquiera de comparar la contraseña. Los usuarios creados por
-- la propia plataforma traen '' (cadena vacía) en esos campos, por eso entran.
--
-- Se normalizan a '' en todas las cuentas. Es lo mismo que escribe GoTrue.
-- ADITIVA, IDEMPOTENTE. No toca contraseñas ni correos.
-- ============================================================================

UPDATE auth.users
   SET confirmation_token          = COALESCE(confirmation_token, ''),
       recovery_token              = COALESCE(recovery_token, ''),
       email_change                = COALESCE(email_change, ''),
       email_change_token_new      = COALESCE(email_change_token_new, ''),
       email_change_token_current  = COALESCE(email_change_token_current, ''),
       phone_change                = COALESCE(phone_change, ''),
       phone_change_token          = COALESCE(phone_change_token, ''),
       reauthentication_token      = COALESCE(reauthentication_token, '')
 WHERE confirmation_token IS NULL
    OR recovery_token IS NULL
    OR email_change IS NULL
    OR email_change_token_new IS NULL
    OR email_change_token_current IS NULL
    OR phone_change IS NULL
    OR phone_change_token IS NULL
    OR reauthentication_token IS NULL;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_rotos INT;
BEGIN
    SELECT count(*) INTO v_rotos FROM auth.users
     WHERE confirmation_token IS NULL OR recovery_token IS NULL
        OR email_change IS NULL OR email_change_token_new IS NULL
        OR email_change_token_current IS NULL OR phone_change IS NULL
        OR phone_change_token IS NULL OR reauthentication_token IS NULL;
    IF v_rotos > 0 THEN
        RAISE EXCEPTION 'FALLO — quedan % cuentas con NULL en los campos de token', v_rotos;
    END IF;
    RAISE NOTICE 'MIG262 OK — ninguna cuenta queda con NULL en los campos que lee el login';
END $$;
