-- 680 — Spence: Instalación Enaex (Orica), mantención y calibración del 02-11-2026.
-- Se llegó a la instalación y no se pudo realizar. Se reprograma al 18-11-2026,
-- después de la última programación de Spence (17-11). Sin papel firmado.

DO $$
DECLARE
    v_cal uuid := 'ab9f631c-5434-4bab-a16a-c8b8270f1752';
    v_man uuid := 'e2c3df3c-1cfc-4b3d-91cf-6b21c96fcf0a';
    v_inst uuid := 'b1c69feb-2b50-4c9b-ae2e-e2af4403e9eb';
    v_faena uuid := (SELECT id FROM enex_faenas WHERE codigo = 'SPENCE');
    v_ancla int := (SELECT trimestre_ancla FROM enex_faenas WHERE codigo = 'SPENCE');
    v_desc text := 'Se llegó a la instalación y no se pudo realizar el servicio. Se reprograma después de la última programación de Spence.';
BEGIN
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id IN (v_cal, v_man)) THEN
        RAISE EXCEPTION 'Una de las tareas ya tiene ejecución: no se reprograma';
    END IF;

    INSERT INTO enex_reprogramaciones (id, programacion_id, faena_id, instalacion_id, faena, instalacion, tipo_activo, actividad,
                                       fecha_original, trimestre, descripcion, nueva_fecha)
    VALUES
      ('c0a8f1e2-5b7d-4e3a-9f21-680000000001', v_cal, v_faena, v_inst, 'Spence', 'Instalación Enaex (Orica)', 'otro', 'calibracion',
       DATE '2026-11-02', fn_enex_trimestre_label(DATE '2026-11-02', v_ancla), v_desc, DATE '2026-11-18'),
      ('c0a8f1e2-5b7d-4e3a-9f21-680000000002', v_man, v_faena, v_inst, 'Spence', 'Instalación Enaex (Orica)', 'otro', 'mantencion',
       DATE '2026-11-02', fn_enex_trimestre_label(DATE '2026-11-02', v_ancla), v_desc, DATE '2026-11-18')
    ON CONFLICT (id) DO NOTHING;

    UPDATE enex_programaciones
       SET fecha_programada = DATE '2026-11-18', observacion = 'Reprogramada a 18-11-2026 (original 02-11)'
     WHERE id IN (v_cal, v_man);
END $$;
