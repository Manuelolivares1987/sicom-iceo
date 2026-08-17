-- ============================================================================
-- SICOM-ICEO | 300 — Cron diario de alerta de exámenes por vencer
-- ============================================================================
-- Llama a /api/notificaciones/examenes-vencimiento todos los días a las 08:00.
--
-- ── POR QUÉ CORRE TODOS LOS DÍAS Y NO MANDA CORREO TODOS LOS DÍAS ──────────
-- El escalamiento vive en la BASE (fn_prevencion_alertas_pendientes, MIG299):
-- devuelve solo los exámenes cuyo último aviso ya cumplió su cadencia —semanal
-- entre 60 y 31 días, cada 3 días entre 30 y 15, día por medio entre 14 y 8, y
-- diario en la última semana y mientras siga vencido—. Si no hay nada que
-- avisar, la API responde `enviadas: 0` y no sale ningún correo.
--
-- Así el cron es trivial y el criterio queda en un solo lugar: cambiar la
-- cadencia no toca el cron ni el frontend.
--
-- ── ANTES DE APLICAR ───────────────────────────────────────────────────────
-- Configurar en Netlify → Site settings → Environment:
--     PREVENCION_EMAIL_TO   destinatarios separados por coma
--     CRON_SECRET           el mismo valor que va abajo (ya existe para el
--                           digest de No Conformidades: usar ESE mismo)
--     SMTP_USER / SMTP_PASS  la cuenta que envía (App Password de Gmail)
--
-- Y reemplazar <CRON_SECRET> abajo por el valor real antes de ejecutar.
-- ============================================================================

-- Idempotente: si el job ya existe, se reemplaza.
SELECT cron.unschedule('alerta-examenes-personal')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alerta-examenes-personal');

SELECT cron.schedule(
    'alerta-examenes-personal',
    '0 12 * * *',          -- 08:00 en Chile continental (UTC-4)
    $cron$
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/notificaciones/examenes-vencimiento',
        headers := jsonb_build_object(
                       'Content-Type',  'application/json',
                       'x-cron-secret', '<CRON_SECRET>'),
        body    := '{}'::jsonb
    );
    $cron$
);

COMMENT ON EXTENSION pg_cron IS
    'Jobs programados. alerta-examenes-personal: aviso diario de exámenes por vencer (MIG300).';
