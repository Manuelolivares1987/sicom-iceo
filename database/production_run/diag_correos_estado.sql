-- Diagnóstico (solo lectura): estado real del envío de correos.
DO $d$
DECLARE r RECORD; v_n INT; v_txt TEXT;
BEGIN
    -- 1. Los crons programados y su comando (recortado).
    RAISE NOTICE '── CRONS (pg_cron) ──';
    FOR r IN SELECT jobid, jobname, schedule, active, substr(command, 1, 160) AS cmd
               FROM cron.job ORDER BY jobid
    LOOP
        RAISE NOTICE '[%] % · % · activo=% · %', r.jobid, COALESCE(r.jobname,'(sin nombre)'), r.schedule, r.active, r.cmd;
    END LOOP;

    -- 2. Últimas corridas de los crons de correo.
    RAISE NOTICE '── ÚLTIMAS CORRIDAS ──';
    FOR r IN
        SELECT j.jobname, d.status, d.return_message, d.start_time
          FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
         WHERE j.jobname ILIKE '%correo%' OR j.jobname ILIKE '%digest%' OR j.jobname ILIKE '%examen%'
            OR j.jobname ILIKE '%mail%' OR j.jobname ILIKE '%alerta%'
         ORDER BY d.start_time DESC LIMIT 8
    LOOP
        RAISE NOTICE '% · % · % · %', r.jobname, r.start_time, r.status, substr(COALESCE(r.return_message,''),1,90);
    END LOOP;

    -- 3. Secretos habilitados (solo nombre, jamás el valor).
    BEGIN
        SELECT string_agg(nombre, ', ') INTO v_txt FROM sistema_secretos;
        RAISE NOTICE 'secretos hasheados en sistema_secretos: %', COALESCE(v_txt,'(ninguno)');
    EXCEPTION WHEN undefined_table THEN RAISE NOTICE 'sistema_secretos no existe';
    END;

    -- 4. Evidencia de envíos: exámenes.
    BEGIN
        SELECT count(*) INTO v_n FROM prevencion_alertas_enviadas;
        RAISE NOTICE 'avisos de exámenes marcados como enviados: %', v_n;
        FOR r IN SELECT enviado_at::date AS dia, count(*) AS n
                   FROM prevencion_alertas_enviadas GROUP BY 1 ORDER BY 1 DESC LIMIT 5
        LOOP RAISE NOTICE '   % → % avisos', r.dia, r.n; END LOOP;
    EXCEPTION WHEN undefined_table OR undefined_column THEN
        RAISE NOTICE '(tabla de avisos de exámenes con otro nombre — revisar)';
    END;

    -- 5. Evidencia de envíos: digest de NC.
    SELECT count(*) FILTER (WHERE email_notificada_at IS NOT NULL),
           count(*) FILTER (WHERE email_notificada_at IS NULL),
           max(email_notificada_at)
      INTO r FROM no_conformidades;
    RAISE NOTICE 'NC notificadas por correo: % · SIN notificar: % · último envío: %',
        r.count, r.count_1, r.max;

    -- 6. Destinatarios configurados por faena (MIG302).
    BEGIN
        FOR r IN SELECT correo, nombre, activo,
                        (SELECT string_agg(f.codigo, ',') FROM prevencion_alertas_destinatario_faenas df
                          JOIN faenas f ON f.id = df.faena_id WHERE df.destinatario_id = d.id) AS faenas
                   FROM prevencion_alertas_destinatarios d ORDER BY correo
        LOOP
            RAISE NOTICE 'destinatario: % (%) activo=% · faenas=%', r.correo, COALESCE(r.nombre,'—'), r.activo, COALESCE(r.faenas,'todas');
        END LOOP;
    EXCEPTION WHEN undefined_table OR undefined_column THEN
        RAISE NOTICE '(destinatarios: estructura distinta — revisar tablas prevencion_alertas_*)';
    END;
END $d$;
