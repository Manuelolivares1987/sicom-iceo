-- Diag (solo lectura): ¿por qué OS-202608-00001-1 no sale en la lista del taller?
DO $d$
DECLARE r RECORD; v_n INT;
BEGIN
    FOR r IN
        SELECT o.folio, o.titulo, o.estado, o.fecha_programada, o.created_at::date AS creada,
               ot.folio AS ot_folio, ot.estado::text AS ot_estado, a.patente,
               (SELECT count(*) FROM taller_os_asignacion x WHERE x.os_id = o.id AND x.hasta IS NULL) AS asignados
          FROM taller_os o
          JOIN ordenes_trabajo ot ON ot.id = o.ot_id
          JOIN activos a ON a.id = ot.activo_id
         WHERE o.folio ILIKE 'OS-202608-00001%' OR o.fecha_programada IS NOT NULL
         ORDER BY o.created_at DESC LIMIT 10
    LOOP
        RAISE NOTICE '% «%» estado=% fecha_prog=% creada=% OT=%(%) patente=% asignados=%',
            r.folio, r.titulo, r.estado, r.fecha_programada, r.creada, r.ot_folio, r.ot_estado, r.patente, r.asignados;
    END LOOP;

    SELECT count(*) INTO v_n FROM taller_os WHERE estado NOT IN ('finalizada','anulada');
    RAISE NOTICE 'OS abiertas (lo que la lista debería mostrar): %', v_n;
END $d$;
