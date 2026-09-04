DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT ma.nombre AS marca, mo.nombre AS modelo, p.nombre AS pauta, p.frecuencia_horas,
               CASE WHEN jsonb_typeof(p.items_checklist)='array' THEN jsonb_array_length(p.items_checklist) ELSE 0 END AS n
          FROM pautas_fabricante p
          JOIN modelos mo ON mo.id = p.modelo_id
          JOIN marcas ma ON ma.id = mo.marca_id
         WHERE ma.nombre IN ('Volvo','Mack','Renault') AND p.activo
         ORDER BY ma.nombre, mo.nombre, p.frecuencia_horas NULLS LAST
    LOOP
        RAISE NOTICE '% | % | % | %h | items=%', rpad(r.marca,8), rpad(r.modelo,16), rpad(r.pauta,52), r.frecuencia_horas, r.n;
    END LOOP;
END $d$;
