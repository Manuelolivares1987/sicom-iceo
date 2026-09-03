-- ============================================================================
-- MIG503 · El aviso de exámenes pasa a UNA vez por semana (lunes 08:00)
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «necesito que el tema de los exámenes sea solo una vez a la
-- semana».
--
-- El cálculo de qué avisar no cambia (fn_prevencion_alertas_pendientes decide
-- según cercanía y última alerta); lo que cambia es el RITMO del cartero: en
-- vez de tocar la puerta todos los días, pasa los lunes con el resumen de la
-- semana. El correo además sale con la plantilla nueva de marca.
--
-- ANTES DE APLICAR: reemplazar <CRON_SECRET> por el valor real (nunca al repo).
-- ============================================================================

SELECT cron.unschedule('alerta-examenes-personal')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alerta-examenes-personal');

SELECT cron.schedule(
    'alerta-examenes-personal',
    '0 12 * * 1',          -- LUNES 08:00 en Chile continental (UTC-4)
    $cron$
    -- Barra final + timeout 30 s: las dos lecciones de MIG501.
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/notificaciones/examenes-vencimiento/',
        headers := jsonb_build_object(
                       'Content-Type',  'application/json',
                       'x-cron-secret', '<CRON_SECRET>'),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000
    );
    $cron$
);

-- ── Verificación (aborta si el secreto no calza — regla MIG501) ─────────────
DO $mig$
DECLARE v_cmd TEXT; v_sched TEXT; v_sec TEXT; v_ok BOOLEAN;
BEGIN
    SELECT command, schedule INTO v_cmd, v_sched
      FROM cron.job WHERE jobname = 'alerta-examenes-personal';
    IF v_cmd IS NULL THEN RAISE EXCEPTION 'FALLO: el job no quedó programado'; END IF;
    IF v_sched <> '0 12 * * 1' THEN
        RAISE EXCEPTION 'FALLO: el horario quedó % y no lunes 12:00 UTC', v_sched; END IF;

    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL OR v_sec = '<CRON' || '_SECRET>' THEN
        RAISE EXCEPTION 'FALLO: falta reemplazar el secreto real antes de aplicar'; END IF;
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: el secreto del cron NO calza con sistema_secretos'; END IF;

    RAISE NOTICE 'aviso de exámenes reprogramado: LUNES 08:00 Chile, secreto vigente, timeout 30 s';
END
$mig$;
