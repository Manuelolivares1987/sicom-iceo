-- Ver la respuesta del request 2711 (disparo de prueba del cron reparado).
DO $d$
DECLARE r RECORD;
BEGIN
    SELECT status_code, timed_out, substr(COALESCE(content,''),1,250) AS body, created
      INTO r FROM net._http_response WHERE id = 2711;
    IF r IS NULL THEN RAISE NOTICE 'aún sin fila para 2711'; 
    ELSE RAISE NOTICE 'respuesta 2711: status=% timed_out=% · %', r.status_code, r.timed_out, r.body;
    END IF;
END $d$;
