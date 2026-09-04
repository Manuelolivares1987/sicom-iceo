DO $d$
DECLARE v TEXT;
BEGIN
    SELECT string_agg(column_name, ', ') INTO v FROM information_schema.columns WHERE table_name='log_jobs_auto';
    RAISE NOTICE 'log_jobs_auto: %', v;
    SELECT command INTO v FROM cron.job WHERE jobname='generar-ots-preventivas';
    RAISE NOTICE 'cola del cron: %', substr(v, 2500, 600);
    SELECT data_type INTO v FROM information_schema.columns WHERE table_name='planes_mantenimiento' AND column_name='prioridad';
    RAISE NOTICE 'planes.prioridad tipo: %', v;
END $d$;
