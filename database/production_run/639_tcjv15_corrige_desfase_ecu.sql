-- MIG639 · TCJV-15: el desfase Radicom → ECU era 206,78 h / 321,26 km
-- ============================================================================
-- MIG636 y MIG637 usaron 208,8 h / 348,44 km: comparaban la lectura Radicom
-- con la ECU de las 05:00 UTC del 22-10, pero la última lectura Radicom fue a
-- las 18:43 del 21-10 (hora Chile) y quedó congelada mientras el camión
-- trabajó esa noche. En ese mismo instante (camión detenido, Renault 19:36
-- marca lo mismo hasta las 21:23):
--   Radicom 1.737,90 h / 24.380,92 km  vs  ECU 1.944,68 h / 24.702,18 km
-- → 206,78 h / 321,26 km. Se devuelven 2,02 h y 27,18 km:
--   · historial diario hasta el 20-10 (todo escala Radicom) y el inicio del
--     21-10 (mínimo del día = lectura Radicom);
--   · bases de las preventivas (MIG636 les sumó 208,8).
-- Centinela: el 20-10 vale 1.944,77 h solo antes de esta corrección.
-- ============================================================================

DO $$
DECLARE
    v_activo UUID;
    c_h  CONSTANT NUMERIC := 2.02;
    c_km CONSTANT NUMERIC := 27.18;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE upper(vin_chasis) = 'VF630N358PD000096';

    IF NOT EXISTS (SELECT 1 FROM activo_horas_dia
                    WHERE activo_id = v_activo AND fecha = '2026-10-20' AND horometro_fin = 1944.77) THEN
        RAISE NOTICE 'MIG639 ya aplicada';
        RETURN;
    END IF;

    UPDATE activo_horas_dia
       SET horometro_ini = horometro_ini - c_h,
           horometro_fin = horometro_fin - c_h,
           km_ini = km_ini - c_km,
           km_fin = km_fin - c_km,
           actualizado_at = NOW()
     WHERE activo_id = v_activo AND fecha <= '2026-10-20';

    UPDATE activo_horas_dia
       SET horometro_ini = horometro_ini - c_h,
           km_ini = km_ini - c_km,
           actualizado_at = NOW()
     WHERE activo_id = v_activo AND fecha = '2026-10-21'
       AND horometro_ini = 1946.70 AND km_ini = 24729.36;

    UPDATE planes_mantenimiento
       SET ultima_ejecucion_horas = ultima_ejecucion_horas - c_h
     WHERE activo_id = v_activo
       AND ultima_ejecucion_horas > 0;
END $$;
