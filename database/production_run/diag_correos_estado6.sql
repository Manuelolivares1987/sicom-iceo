-- Diagnóstico correos, parte 6: disparar UNA VEZ el mismo POST del cron (el
-- comando se lee del propio job, así el secreto no vive en este archivo) y
-- mirar la respuesta de pg_net. Puede enviar un correo real con lo que quede
-- pendiente de hoy — es el comportamiento diseñado.
DO $d$
DECLARE v_cmd TEXT; v_req BIGINT; r RECORD; v_i INT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'alerta-examenes-personal';
    EXECUTE 'SELECT (' || regexp_replace(v_cmd, '^\s*|;\s*$', '', 'g') || ')' INTO v_req;
    RAISE NOTICE 'request encolado: id %', v_req;

    -- Esperar la respuesta (pg_net trabaja aparte; el worker comitea solo).
    FOR v_i IN 1..14 LOOP
        PERFORM pg_sleep(2);
        SELECT status_code, timed_out, substr(COALESCE(content,''),1,200) AS body
          INTO r FROM net._http_response WHERE id = v_req;
        IF r.status_code IS NOT NULL OR COALESCE(r.timed_out, FALSE) THEN
            RAISE NOTICE 'respuesta: status=% timed_out=% body=%', r.status_code, r.timed_out, r.body;
            RETURN;
        END IF;
    END LOOP;
    RAISE NOTICE 'sin respuesta visible tras 28 s (puede llegar igual; revisar net._http_response id %)', v_req;
END $d$;
