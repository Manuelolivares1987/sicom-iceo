-- ============================================================================
-- 176_cron_nc_digest.sql   ⚠ NO APLICAR HASTA CONFIGURAR EL CORREO
-- ----------------------------------------------------------------------------
-- Programa el envío del digest de No Conformidades por correo. El cron llama
-- por net.http_post a la API /api/notificaciones/nc-digest del sitio Netlify,
-- que arma el resumen y lo manda por Gmail (ver MIG175 + lib/email/mailer.ts).
--
-- ANTES de aplicar:
--   1. En Netlify configura: SMTP_USER, SMTP_PASS, NC_EMAIL_TO,
--      SUPABASE_SERVICE_ROLE_KEY y CRON_SECRET (ver frontend/.env.example).
--   2. Reemplaza abajo __CRON_SECRET__ por el MISMO valor de CRON_SECRET.
--   3. Verifica la URL del sitio (default https://pilladoiceo.netlify.app).
--
-- Frecuencia: cada 2 horas (carga mínima). Ajusta el schedule si quieres.
-- Para envío inmediato por NC, esto se puede cambiar a un webhook, pero el
-- digest evita spam y es más barato en el tier actual.
-- IDEMPOTENTE (re-crea el job).
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'nc-digest-email') THEN
        PERFORM cron.unschedule('nc-digest-email');
    END IF;
END $$;

SELECT cron.schedule(
    job_name => 'nc-digest-email',
    schedule => '0 */2 * * *',  -- cada 2 horas en :00
    command  => $cmd$
        SELECT net.http_post(
            url     := 'https://pilladoiceo.netlify.app/api/notificaciones/nc-digest',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-cron-secret', '__CRON_SECRET__'
            ),
            body    := '{}'::jsonb
        );
    $cmd$
);

SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'nc-digest-email';
