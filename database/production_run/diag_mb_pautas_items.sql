DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT mo.nombre AS modelo, p.nombre AS pauta, p.frecuencia_horas,
               jsonb_typeof(p.items_checklist) AS t,
               CASE WHEN jsonb_typeof(p.items_checklist)='array'
                    THEN jsonb_array_length(p.items_checklist) ELSE 0 END AS n_items,
               left(p.items_checklist::text, 500) AS muestra
          FROM pautas_fabricante p
          JOIN modelos mo ON mo.id = p.modelo_id
          JOIN marcas ma ON ma.id = mo.marca_id
         WHERE ma.nombre = 'Mercedes-Benz' AND p.activo
         ORDER BY mo.nombre, p.frecuencia_horas NULLS LAST
    LOOP
        RAISE NOTICE '=== % | % | %h | items(%): %', r.modelo, r.pauta, r.frecuencia_horas, r.n_items, r.muestra;
    END LOOP;
END $d$;
