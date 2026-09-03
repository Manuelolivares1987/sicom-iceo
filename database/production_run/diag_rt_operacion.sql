-- Diag (solo lectura): activos.operacion como zona Coquimbo/Calama.
DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT COALESCE(a.operacion::text,'(null)') AS op, count(*) AS n
               FROM activos a WHERE a.fecha_baja IS NULL GROUP BY 1 ORDER BY 2 DESC LOOP
        RAISE NOTICE 'operacion=% → % equipos', r.op, r.n;
    END LOOP;
    FOR r IN
        SELECT a.patente, COALESCE(a.operacion::text,'(null)') AS op, f.nombre AS faena
          FROM v_certificacion_actual c
          JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
          LEFT JOIN faenas f ON f.id = a.faena_id
         WHERE c.tipo::text='revision_tecnica' AND c.estado_real IN ('vencido','por_vencer')
         ORDER BY 2, 1 LOOP
        RAISE NOTICE '% · operacion=% · faena=%', r.patente, r.op, r.faena;
    END LOOP;
END $d$;
