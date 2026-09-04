DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT COALESCE(ma.nombre,'?') AS marca, COALESCE(mo.nombre,'?') AS modelo,
               p.nombre AS pauta, p.tipo_plan::text AS tipo_plan, p.frecuencia_horas, p.frecuencia_km, p.frecuencia_dias,
               CASE WHEN jsonb_typeof(p.materiales_estimados)='array' THEN jsonb_array_length(p.materiales_estimados) ELSE 0 END AS n_mat
          FROM pautas_fabricante p
          LEFT JOIN modelos mo ON mo.id = p.modelo_id
          LEFT JOIN marcas ma ON ma.id = mo.marca_id
         WHERE p.activo
         ORDER BY 1,2, p.frecuencia_horas NULLS LAST
    LOOP
        RAISE NOTICE '% | % | % | % | %h %km %d | mat=%',
            rpad(r.marca,12), rpad(r.modelo,24), rpad(COALESCE(r.pauta,'?'),34),
            rpad(COALESCE(r.tipo_plan::text,'?'),12), r.frecuencia_horas, r.frecuencia_km, r.frecuencia_dias, r.n_mat;
    END LOOP;
END $d$;
