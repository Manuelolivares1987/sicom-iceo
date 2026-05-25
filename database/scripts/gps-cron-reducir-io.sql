-- ============================================================================
-- gps-cron-reducir-io.sql
-- Reduce el I/O del pipeline GPS que satura el budget de disco en tier Micro.
-- Ejecutar en: Supabase Dashboard -> SQL Editor.
--
-- El cron de 60s (pg_cron creado desde el dashboard) llama a la edge function
-- gps-radicom-poll via net.http_post e inserta ~73k filas/dia en gps_eventos_log.
-- En Micro eso agota el presupuesto de E/S y deja la DB estrangulada.
--
-- USO:
--   PASO 1 -> correr el bloque [VER] para inspeccionar los jobs actuales.
--   PASO 2 -> correr [PAUSA] para frenar la escritura YA (recupera el budget).
--   PASO 3 -> cuando la DB responda normal, correr [REPROGRAMAR] para dejar
--             el polling en una frecuencia sana, y reactivar.
-- ============================================================================


-- ============================================================================
-- [VER] Jobs actuales (identifica los que llaman a gps-radicom-poll)
-- ============================================================================
SELECT jobid, jobname, schedule, active, left(command, 90) AS command
FROM cron.job
ORDER BY jobid;


-- ============================================================================
-- [PAUSA] Detener YA todos los crons que disparan gps-radicom-poll.
-- No los borra: solo los desactiva para que el budget de I/O se recupere.
-- ============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobid, jobname FROM cron.job WHERE command ILIKE '%gps-radicom-poll%' LOOP
    PERFORM cron.alter_job(r.jobid, active := false);
    RAISE NOTICE 'Pausado job % (%).', r.jobid, r.jobname;
  END LOOP;
END $$;


-- ============================================================================
-- [REPROGRAMAR] Cuando la DB ya responda bien: bajar frecuencia y reactivar.
--   - states (sin counters):  cada 3 min   (era cada 60s)
--   - counters (?counters=1):  cada 15 min  (era cada 5 min)
-- Ajusta los intervalos a tu gusto antes de correr.
-- ============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobid, command FROM cron.job WHERE command ILIKE '%gps-radicom-poll%' LOOP
    IF r.command ILIKE '%counters=1%' THEN
      PERFORM cron.alter_job(r.jobid, schedule := '*/15 * * * *', active := true);
    ELSE
      PERFORM cron.alter_job(r.jobid, schedule := '*/3 * * * *', active := true);
    END IF;
  END LOOP;
END $$;


-- ============================================================================
-- [VERIFICAR] Confirmar el estado final de los jobs GPS
-- ============================================================================
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE command ILIKE '%gps-radicom-poll%'
ORDER BY jobid;
