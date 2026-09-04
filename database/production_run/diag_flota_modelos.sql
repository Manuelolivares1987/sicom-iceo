DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT COALESCE(ma.nombre,'(sin marca)') AS marca, COALESCE(mo.nombre,'(sin modelo)') AS modelo,
               a.tipo::text AS tipo, count(*) AS n,
               round(avg(a.horas_uso_actual)) AS horas_prom, round(avg(a.kilometraje_actual)) AS km_prom
          FROM activos a
          LEFT JOIN modelos mo ON mo.id = a.modelo_id
          LEFT JOIN marcas ma ON ma.id = mo.marca_id
         WHERE a.fecha_baja IS NULL
         GROUP BY 1,2,3 ORDER BY 4 DESC, 1, 2
    LOOP
        RAISE NOTICE '% | % | % | n=% | ~% h | ~% km',
            rpad(r.marca,14), rpad(r.modelo,30), rpad(r.tipo,16), r.n,
            COALESCE(r.horas_prom,0), COALESCE(r.km_prom,0);
    END LOOP;
END $d$;
