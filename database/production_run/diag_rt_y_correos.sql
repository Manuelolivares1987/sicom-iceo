-- Diag (solo lectura): tipos de certificado RT + correos de las 4 personas.
DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT DISTINCT tipo::text AS t FROM certificaciones
              WHERE tipo::text ILIKE '%revision%' OR tipo::text ILIKE '%tecnica%' LOOP
        RAISE NOTICE 'tipo certificado: %', r.t;
    END LOOP;
    FOR r IN SELECT count(*) AS n, estado_real::text AS e FROM v_certificacion_actual
              WHERE tipo::text = 'revision_tecnica' GROUP BY 2 LOOP
        RAISE NOTICE 'RT por estado: % → %', r.e, r.n;
    END LOOP;
    FOR r IN SELECT nombre_completo, email, rol FROM usuarios_perfil
              WHERE activo AND (nombre_completo ILIKE '%hersal%' OR nombre_completo ILIKE '%rodrigo%'
                 OR nombre_completo ILIKE '%juan pablo%' OR nombre_completo ILIKE '%ricardo%') LOOP
        RAISE NOTICE 'usuario: % · % · %', r.nombre_completo, r.email, r.rol;
    END LOOP;
END $d$;
