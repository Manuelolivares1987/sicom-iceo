-- Diag (solo lectura): qué campos de zona tiene activos y cómo se ven los 12 RT.
DO $d$
DECLARE r RECORD; v TEXT;
BEGIN
    SELECT string_agg(column_name, ', ') INTO v FROM information_schema.columns
     WHERE table_name='activos' AND (column_name ILIKE '%faena%' OR column_name ILIKE '%ubicacion%' OR column_name ILIKE '%zona%' OR column_name ILIKE '%region%');
    RAISE NOTICE 'columnas de zona en activos: %', v;
    FOR r IN
        SELECT a.patente, f.codigo AS faena, f.nombre AS faena_nombre, a.ubicacion_actual, a.cliente_actual
          FROM v_certificacion_actual c
          JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
          LEFT JOIN faenas f ON f.id = a.faena_id
         WHERE c.tipo::text='revision_tecnica' AND c.estado_real IN ('vencido','por_vencer')
         ORDER BY f.nombre NULLS LAST, a.patente
    LOOP
        RAISE NOTICE '% · faena=% (%) · ubic=% · cliente=%', r.patente, r.faena, r.faena_nombre, r.ubicacion_actual, r.cliente_actual;
    END LOOP;
END $d$;
