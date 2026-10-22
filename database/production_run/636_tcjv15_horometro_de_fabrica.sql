-- MIG636 · TCJV-15 pasa al GPS de fábrica Renault (decisión de Manuel, 22-10)
-- ============================================================================
-- TCJV-15 (CC-15-16, VIN VF630N358PD000096) tenía Radicom y Renault. El
-- horómetro Radicom (engine_hours del tracker) va atrás de la ECU del motor:
-- a las 05:00 UTC del 22-10 Radicom leyó 1.737,90 h y la ECU 1.946,69 h.
-- Manda la ECU: es lo que ve el mecánico en el tablero y lo que usa la pauta
-- del fabricante.
--
-- Las bases de sus 6 preventivas (ultima_ejecucion_horas) están en escala
-- Radicom: el SL 300 h quedó en 1.663,4 el 04-09, coherente con Radicom
-- (1.684 el 15-09). Cambiar la fuente sin moverlas adelantaría todas sus
-- preventivas 209 h sin uso real. Se corren en la misma diferencia medida
-- (208,8 h): lo que falta para cada una queda igual.
--
-- El día del cambio queda sin horas en v_activo_horas_dia (salto > 24 h se
-- descarta, MIG597); desde el día siguiente cuenta normal.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_activo  UUID;
    v_renault UUID;
    v_radicom UUID;
    v_offset  CONSTANT NUMERIC := 208.8;
    v_planes  INTEGER;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE upper(vin_chasis) = 'VF630N358PD000096';
    SELECT id INTO v_renault FROM config_gps_proveedor WHERE nombre = 'Renault rFMS';
    SELECT id INTO v_radicom FROM config_gps_proveedor WHERE nombre = 'Radicom';
    IF v_activo IS NULL OR v_renault IS NULL THEN
        RAISE EXCEPTION 'FALLO: falta TCJV-15 o el proveedor Renault (MIG635)';
    END IF;

    -- Idempotente: si Renault ya rige, no se vuelve a correr la base.
    IF EXISTS (SELECT 1 FROM gps_activo_mapeo
                WHERE activo_id = v_activo AND proveedor_id = v_renault AND activo) THEN
        RAISE NOTICE 'TCJV-15 ya está en Renault: nada que hacer';
        RETURN;
    END IF;

    UPDATE gps_activo_mapeo SET activo = FALSE
     WHERE activo_id = v_activo AND proveedor_id = v_radicom;

    INSERT INTO gps_activo_mapeo (activo_id, proveedor_id, gps_device_id, gps_device_name, activo)
    VALUES (v_activo, v_renault, 'VF630N358PD000096', 'Renault C(RT)', TRUE)
    ON CONFLICT (activo_id, proveedor_id) DO UPDATE SET activo = TRUE;

    UPDATE planes_mantenimiento
       SET ultima_ejecucion_horas = ultima_ejecucion_horas + v_offset
     WHERE activo_id = v_activo
       AND ultima_ejecucion_horas > 0;
    GET DIAGNOSTICS v_planes = ROW_COUNT;

    -- El estado actual se rehace con la primera lectura Renault; los
    -- contadores solo avanzan, así que se parte de cero en esta fuente.
    UPDATE gps_estado_actual
       SET horometro_hrs = NULL
     WHERE activo_id = v_activo;

    RAISE NOTICE 'TCJV-15 → Renault. Bases de % planes corridas en % h', v_planes, v_offset;
END
$$;

COMMIT;
