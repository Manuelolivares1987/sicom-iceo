-- Diag (solo lectura): todos los usuarios con correo, para ubicar a los 4.
DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT nombre_completo, email, rol, activo FROM usuarios_perfil
              WHERE email IS NOT NULL ORDER BY nombre_completo LOOP
        RAISE NOTICE '% · % · % · activo=%', r.nombre_completo, r.email, r.rol, r.activo;
    END LOOP;
END $d$;
