DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT COALESCE(ma.nombre,'(sin marca)') AS marca,
               count(DISTINCT mo.id) AS modelos_con_pauta, count(*) AS pautas,
               count(*) FILTER (WHERE jsonb_typeof(p.materiales_estimados)='array'
                                  AND jsonb_array_length(p.materiales_estimados) > 0) AS con_materiales
          FROM pautas_fabricante p
          LEFT JOIN modelos mo ON mo.id = p.modelo_id
          LEFT JOIN marcas ma ON ma.id = mo.marca_id
         WHERE p.activo GROUP BY 1 ORDER BY 3 DESC
    LOOP
        RAISE NOTICE '% | modelos=% | pautas=% | con materiales=%', rpad(r.marca,15), r.modelos_con_pauta, r.pautas, r.con_materiales;
    END LOOP;
END $d$;
