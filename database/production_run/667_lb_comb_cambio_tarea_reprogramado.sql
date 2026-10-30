-- 667 — Lomas Bayas Combustibles: las tareas que ESM cambió el 26 y 27-10
-- (MIG666) se REPROGRAMAN, no quedan esperando el correo del ADC.
--
-- Manuel (30-10-2026): «ese día fui, pero ESM me pidió cambiar; la tarea
-- planificada debe ser reprogramada». Fechas: primera semana de diciembre,
-- en días seguidos como el plan original.
--   EESS Valle Amanda (mantención + calibración)        26-10 → 01-12
--   Brazo de carga Valle Amanda (calibración + mantención) 27-10 → 02-12
-- fn_enex_cambio_aplicar_destino valida que la fecha caiga dentro del
-- trimestre contractual de LB_COMB (oct-dic) y mueve fecha_programada.

DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
            ('50f04c33-10b9-4a35-a39e-eb5fb97bce9a'::uuid, DATE '2026-10-26', DATE '2026-12-01'),  -- EESS calibración
            ('0182b7a1-95f3-450f-9d5a-5e1f6c50c14b'::uuid, DATE '2026-10-26', DATE '2026-12-01'),  -- EESS mantención
            ('c9a154c9-2ac6-45de-bb7e-28fa7922f845'::uuid, DATE '2026-10-27', DATE '2026-12-02'),  -- Brazo calibración
            ('331739be-fcaa-4860-ac2f-fb8ff266f356'::uuid, DATE '2026-10-27', DATE '2026-12-02')   -- Brazo mantención
        ) AS t(prog, original, nueva)
    LOOP
        UPDATE enex_cambios_tarea
           SET destino = 'reprogramada', nueva_fecha = r.nueva, actualizado_at = now()
         WHERE programacion_id = r.prog;
        IF NOT FOUND THEN RAISE EXCEPTION 'Falta el cambio de tarea de %', r.prog; END IF;
        PERFORM fn_enex_cambio_aplicar_destino(r.prog, r.original, 'reprogramada', r.nueva);
    END LOOP;
END $$;

SELECT json_agg(json_build_object('instalacion', i.nombre, 'servicio', p.tipo_servicio, 'fecha', p.fecha_programada,
                                  'cambio', ct.destino, 'cambio_fecha', ct.fecha, 'nueva', ct.nueva_fecha) ORDER BY p.fecha_programada, i.nombre)
  FROM enex_cambios_tarea ct
  JOIN enex_programaciones p ON p.id = ct.programacion_id
  JOIN enex_instalaciones i ON i.id = p.instalacion_id
  JOIN enex_faenas f ON f.id = i.faena_id AND f.codigo = 'LB_COMB';
