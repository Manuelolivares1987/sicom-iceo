-- Diagnóstico correos, parte 5 (solo lectura): ¿el cron manda el secreto
-- correcto? ¿pg_net está reportando timeouts? Nunca se imprime el secreto:
-- solo se compara su hash contra sistema_secretos.
DO $d$
DECLARE v_cmd TEXT; v_sec TEXT; v_hash TEXT; v_ok BOOLEAN; r RECORD; v_timeout TEXT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'alerta-examenes-personal';
    IF v_cmd IS NULL THEN RAISE NOTICE 'no existe el job'; RETURN; END IF;

    -- URL usada (sin secreto) y si declara timeout.
    RAISE NOTICE 'url en el cron: %', substring(v_cmd FROM 'https://[^'']+');
    v_timeout := substring(v_cmd FROM 'timeout_milliseconds\s*:=\s*([0-9]+)');
    RAISE NOTICE 'timeout_milliseconds declarado: %', COALESCE(v_timeout, '(ninguno → default de pg_net)');

    -- El secreto del header, hasheado y comparado (jamás impreso).
    v_sec := substring(v_cmd FROM 'x-cron-secret[''"]?\s*,\s*[''"]([^''"]+)');
    IF v_sec IS NULL THEN
        v_sec := substring(v_cmd FROM 'x-cron-secret[''"]?\s*:\s*[''"]([^''"]+)');
    END IF;
    IF v_sec IS NULL THEN
        RAISE NOTICE 'no pude extraer el header x-cron-secret del comando';
    ELSE
        v_hash := encode(digest(v_sec, 'sha256'), 'hex');
        SELECT (hash = v_hash) INTO v_ok FROM sistema_secretos WHERE codigo = 'cron_alertas';
        RAISE NOTICE 'el secreto del cron calza con el hash de la base: %', v_ok;
    END IF;

    -- Errores recientes de pg_net (las columnas de verdad).
    FOR r IN
        SELECT id, status_code, error_msg, timed_out, created
          FROM net._http_response ORDER BY created DESC LIMIT 8
    LOOP
        RAISE NOTICE 'resp % · status=% · timed_out=% · error=%',
            r.created, COALESCE(r.status_code::TEXT,'—'), COALESCE(r.timed_out::TEXT,'—'),
            COALESCE(substr(r.error_msg,1,120), '—');
    END LOOP;
EXCEPTION WHEN undefined_column THEN
    RAISE NOTICE 'columnas distintas en net._http_response: %', (
        SELECT string_agg(column_name, ', ') FROM information_schema.columns
         WHERE table_schema='net' AND table_name='_http_response');
END $d$;
