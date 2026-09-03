-- Diagnóstico correos, parte 4 (solo lectura): ¿hay avisos de exámenes que
-- DEBERÍAN estar saliendo hoy? Si hay pendientes y desde el 17-08 no se marca
-- ninguno, el correo diario está fallando en la cañería, no en la lógica.
DO $d$
DECLARE r RECORD; v_n INT := 0;
BEGIN
    FOR r IN SELECT * FROM fn_prevencion_alertas_pendientes() LIMIT 12 LOOP
        v_n := v_n + 1;
        RAISE NOTICE 'pendiente: % · % · vence % (% días) · nivel % · última alerta %',
            r.persona, r.tipo_nombre, r.fecha_vencimiento, r.dias_restantes, r.nivel, r.ultima_alerta;
    END LOOP;
    IF v_n = 0 THEN
        RAISE NOTICE 'HOY no hay avisos pendientes: el silencio desde el 17-08 puede ser legítimo.';
    ELSE
        RAISE NOTICE 'HAY % (o más) avisos que el cron debió mandar y no se marcaron.', v_n;
    END IF;
END $d$;
