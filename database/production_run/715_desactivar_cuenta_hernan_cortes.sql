-- ============================================================================
-- MIG715 — Desactivar la cuenta de Hernán Cortés (hcortes@pillado.cl)
-- ----------------------------------------------------------------------------
-- Manuel (18-11-2026): Marco Díaz tomó su lugar como mecánico de Franke
-- (MIG714) y pidió desactivar la cuenta de Hernán.
-- La app no bloquea por usuarios_perfil.activo (el perfil igual carga), así que
-- se bloquea el login en Supabase (banned_until) y se cierran sus sesiones.
-- La historia (OT, pautas, registros) queda intacta: no se borra nada.
-- Rollback: UPDATE auth.users SET banned_until = NULL WHERE email = 'hcortes@pillado.cl';
--           UPDATE public.usuarios_perfil SET activo = true WHERE email = 'hcortes@pillado.cl';
-- ============================================================================
UPDATE public.usuarios_perfil SET activo = false, solo_su_faena = false, updated_at = NOW()
 WHERE email = 'hcortes@pillado.cl';
UPDATE public.bodega_responsables SET activo = false WHERE email = 'hcortes@pillado.cl';
UPDATE auth.users SET banned_until = '2999-12-31 00:00:00+00', updated_at = NOW()
 WHERE email = 'hcortes@pillado.cl';
DELETE FROM auth.sessions WHERE user_id = (SELECT id FROM auth.users WHERE email = 'hcortes@pillado.cl');  -- destructivo-ok: cierra sesiones abiertas

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'hcortes@pillado.cl' AND banned_until > NOW()) THEN
        RAISE EXCEPTION 'MIG715: la cuenta de Hernán no quedó bloqueada';
    END IF;
    RAISE NOTICE 'MIG715 OK: cuenta hcortes@pillado.cl desactivada (login bloqueado, sesiones cerradas)';
END $$;
