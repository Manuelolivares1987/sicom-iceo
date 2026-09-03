-- Diagnóstico correos, parte 3 (solo lectura): ¿el POST del cron llega y el
-- endpoint responde OK? ¿cuántos avisos de exámenes se han marcado enviados?
DO $d$
DECLARE r RECORD; v_txt TEXT;
BEGIN
    SELECT string_agg(column_name, ', ') INTO v_txt
      FROM information_schema.columns WHERE table_name = 'prevencion_alertas_enviadas';
    RAISE NOTICE 'prevencion_alertas_enviadas columnas: %', v_txt;
    FOR r IN EXECUTE
        'SELECT date_trunc(''day'', enviada_at)::date AS dia, count(*) AS n
           FROM prevencion_alertas_enviadas GROUP BY 1 ORDER BY 1 DESC LIMIT 8'
    LOOP RAISE NOTICE '   % → % avisos marcados', r.dia, r.n; END LOOP;

    -- Respuestas HTTP recientes de pg_net (si aún no se purgaron).
    BEGIN
        FOR r IN
            SELECT id, status_code, substr(COALESCE(content,''),1,140) AS body, created
              FROM net._http_response ORDER BY created DESC LIMIT 10
        LOOP
            RAISE NOTICE 'http resp: % · % · % · %', r.created, r.status_code, r.id, r.body;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE '(net._http_response no legible: %)', SQLERRM;
    END;
END $d$;
