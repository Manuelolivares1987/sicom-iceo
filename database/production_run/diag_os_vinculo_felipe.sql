DO $d$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT t.nombre, up.email, up.rol
               FROM taller_tecnicos t JOIN usuarios_perfil up ON up.id = t.usuario_perfil_id
              WHERE t.nombre ILIKE '%felipe%' LOOP
        RAISE NOTICE 'tecnico % → cuenta % (rol %)', r.nombre, r.email, r.rol;
    END LOOP;
END $d$;
