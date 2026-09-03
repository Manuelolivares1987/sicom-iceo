-- Diagnóstico correos, parte 2 (solo lectura).
DO $d$
DECLARE r RECORD; v_env INT; v_sin INT; v_max TIMESTAMPTZ; v_txt TEXT;
BEGIN
    -- Columnas reales de sistema_secretos + filas.
    SELECT string_agg(column_name, ', ') INTO v_txt
      FROM information_schema.columns WHERE table_name = 'sistema_secretos';
    RAISE NOTICE 'sistema_secretos columnas: %', COALESCE(v_txt, '(no existe)');
    BEGIN
        FOR r IN EXECUTE 'SELECT * FROM sistema_secretos' LOOP
            RAISE NOTICE '   secreto: %', r;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '   (no legible: %)', SQLERRM;
    END;

    -- Corridas del cron de exámenes (jobname alerta-examenes-personal).
    RAISE NOTICE '── corridas alerta-examenes-personal ──';
    FOR r IN
        SELECT d.status, d.return_message, d.start_time
          FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
         WHERE j.jobname = 'alerta-examenes-personal'
         ORDER BY d.start_time DESC LIMIT 6
    LOOP
        RAISE NOTICE '% · % · %', r.start_time, r.status, substr(COALESCE(r.return_message,''),1,120);
    END LOOP;

    -- Evidencia exámenes: tabla de avisos enviados.
    SELECT string_agg(table_name, ', ') INTO v_txt
      FROM information_schema.tables
     WHERE table_schema='public' AND table_name LIKE 'prevencion_alert%';
    RAISE NOTICE 'tablas prevencion_alert*: %', COALESCE(v_txt,'(ninguna)');
    BEGIN
        FOR r IN EXECUTE
            'SELECT enviado_at::date AS dia, count(*) AS n FROM prevencion_alertas_enviadas GROUP BY 1 ORDER BY 1 DESC LIMIT 6'
        LOOP RAISE NOTICE '   avisos exámenes % → %', r.dia, r.n; END LOOP;
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '   (avisos: %)', SQLERRM;
    END;

    -- Digest NC.
    SELECT count(*) FILTER (WHERE email_notificada_at IS NOT NULL),
           count(*) FILTER (WHERE email_notificada_at IS NULL),
           max(email_notificada_at)
      INTO v_env, v_sin, v_max FROM no_conformidades;
    RAISE NOTICE 'NC notificadas por correo: % · sin notificar: % · último: %', v_env, v_sin, v_max;

    -- Destinatarios por faena.
    SELECT string_agg(column_name, ', ') INTO v_txt
      FROM information_schema.columns WHERE table_name = 'prevencion_alertas_destinatarios';
    RAISE NOTICE 'destinatarios columnas: %', COALESCE(v_txt,'(no existe)');
    BEGIN
        FOR r IN EXECUTE 'SELECT * FROM prevencion_alertas_destinatarios ORDER BY 1' LOOP
            RAISE NOTICE '   %', r;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '   (destinatarios: %)', SQLERRM;
    END;
END $d$;
