-- ============================================================================
-- MIG501 · El aviso diario de exámenes llevaba desde el 17-08 mudo
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «necesito revisar lo que es el envío de correos, analiza si está
-- configurado y cómo llegan».
--
-- LO QUE SE ENCONTRÓ (diag_correos_estado*.sql)
-- El cron corre todos los días a las 08:00 y pg_cron dice "succeeded", pero
-- desde el 17-08 no se marcó NI UN aviso — con exámenes vencidos hace 23 días
-- esperando. Invocado a mano el endpoint funciona perfecto (200, 25 alertas a
-- 4 destinatarios). Dos fallas, cualquiera basta para el silencio:
--
--   1. EL SECRETO DEL CRON NO ES EL VIGENTE. Se rotó CRON_SECRET en Netlify
--      después de crear el job: el endpoint respondía 401 y pg_cron igual dice
--      "succeeded", porque para él encolar el POST ya es éxito.
--   2. EL TIMEOUT POR DEFECTO DE pg_net ES 5000 ms, y el endpoint tarda más
--      (función fría de Netlify + enviar por SMTP de Gmail). La conexión se
--      cortaba antes de la respuesta.
--
-- QUÉ SE HACE
--   · Se reprograma el job con el secreto vigente y timeout de 30 s.
--   · VERIFICACIÓN QUE ABORTA: el secreto que quedó escrito en el job se
--     hashea y se compara contra sistema_secretos. Si no calza, la migración
--     falla — este modo de falla no puede volver a entrar callado.
--
-- ANTES DE APLICAR: reemplazar <CRON_SECRET> por el valor real (el de
-- Netlify). En el repo queda el placeholder; el valor no se comitea nunca.
-- ============================================================================

SELECT cron.unschedule('alerta-examenes-personal')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alerta-examenes-personal');

SELECT cron.schedule(
    'alerta-examenes-personal',
    '0 12 * * *',          -- 08:00 en Chile continental (UTC-4)
    $cron$
    -- La barra final NO es cosmética (trailingSlash: sin barra → 308 y pg_net
    -- no sigue redirects). El timeout tampoco: el default de pg_net son 5 s y
    -- este endpoint arranca frío y manda correo por SMTP — tarda más (MIG501).
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

-- ── Verificación (aborta si el secreto no es el vigente) ────────────────────
DO $mig$
DECLARE v_cmd TEXT; v_sec TEXT; v_ok BOOLEAN; v_to TEXT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'alerta-examenes-personal';
    IF v_cmd IS NULL THEN RAISE EXCEPTION 'FALLO: el job no quedó programado'; END IF;

    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL THEN RAISE EXCEPTION 'FALLO: no se pudo leer el header del job'; END IF;
    IF v_sec = '<CRON' || '_SECRET>' THEN
        RAISE EXCEPTION 'FALLO: quedó el placeholder — reemplazar por el secreto real antes de aplicar';
    END IF;

    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: el secreto del cron NO calza con el hash vigente (sistema_secretos.cron_alertas)';
    END IF;

    v_to := substring(v_cmd FROM 'timeout_milliseconds := ([0-9]+)');
    IF COALESCE(v_to,'0')::INT < 15000 THEN
        RAISE EXCEPTION 'FALLO: el timeout quedó en % ms — el endpoint necesita más', v_to;
    END IF;

    RAISE NOTICE 'cron reprogramado: secreto vigente (hash OK) + timeout % ms + barra final', v_to;
END
$mig$;
