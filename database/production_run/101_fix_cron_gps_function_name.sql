-- ============================================================================
-- 101_fix_cron_gps_function_name.sql
-- ----------------------------------------------------------------------------
-- BUG (ingesta GPS caida desde 2026-05-25): los crons gps-radicom-states y
-- gps-radicom-counters llaman por net.http_post a la edge function
-- 'smooth-worker', pero esa funcion ya NO existe (al redeplegar el 25-may quedo
-- como 'gps-radicom-poll'). Cada llamada horaria devolvia HTTP 404 NOT_FOUND y
-- por eso NINGUN tracker recibia posiciones nuevas (51/51 "sin senal").
-- Verificado: POST a /functions/v1/gps-radicom-poll responde 200
-- {"ok":true,"trackers":51,"eventos":51}.
--
-- FIX: reemplazar 'smooth-worker' por 'gps-radicom-poll' en el comando de los
-- crons afectados, preservando schedule y token (no se transcribe el token al
-- repo: se edita el comando vivo con cron.alter_job). Idempotente.
-- ============================================================================

DO $mig101$
DECLARE
    r RECORD;
    v_n INT := 0;
BEGIN
    FOR r IN
        SELECT jobid, jobname, command
        FROM cron.job
        WHERE command LIKE '%smooth-worker%'
    LOOP
        PERFORM cron.alter_job(
            r.jobid,
            command := replace(r.command, 'smooth-worker', 'gps-radicom-poll')
        );
        v_n := v_n + 1;
        RAISE NOTICE 'Cron % actualizado: smooth-worker -> gps-radicom-poll', r.jobname;
    END LOOP;

    IF v_n = 0 THEN
        RAISE NOTICE 'Ningun cron apuntaba a smooth-worker (ya corregido?).';
    END IF;
END
$mig101$;

-- Verificacion: no debe quedar ningun cron apuntando a smooth-worker.
SELECT jobname, schedule, active,
       (command LIKE '%gps-radicom-poll%') AS apunta_ok,
       (command LIKE '%smooth-worker%')    AS aun_roto
FROM cron.job
WHERE jobname LIKE 'gps-radicom%'
ORDER BY jobname;
