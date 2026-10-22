-- MIG642 · Reprogramar la escalera: elegir cuál es la próxima mantención
-- ============================================================================
-- Desde Horas por equipo se elige la pauta que toca y a qué horómetro (X).
-- Las bases de la escalera se recalculan para que el orden siga el ciclo:
--   · la elegida (F):                   X − F
--   · menores que dividen a F:           X − f   (se absorben en X)
--   · mayores múltiplo de F:             X − F   (cuentan desde el peldaño
--                                                anterior a X)
--   · las que no calzan (3.000, 6.000, 8.000…): sin cambio
-- Misma regla que frontend/src/lib/escalera-mantencion.ts.
--
-- Fecha de cada base: hoy − (horómetro − base) / ritmo de 30 días (entre 2 y
-- 20 h/día, 8 si no hay ritmo). v_plan_mantenimiento_estado descarta la pauta
-- si entre su base y hoy salen más de 24 h/día: con la fecha de hoy, las
-- bases más viejas quedarían «inconsistentes».
-- Ninguna base puede quedar sobre el horómetro actual. Bitácora en
-- plan_mantenimiento_registro_manual (MIG640).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_escalera_reprogramar(p_plan_id UUID, p_horas NUMERIC, p_nota TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_plan   planes_mantenimiento;
    v_act    activos;
    v_hoy    DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    v_ritmo  NUMERIC;
    F        NUMERIC;
    r        RECORD;
    v_base   NUMERIC;
    v_fecha  DATE;
    v_max    NUMERIC;
    v_n      INT := 0;
    v_cambios JSONB := '[]'::JSONB;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('mantenimiento', 'edit',
            ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para reprogramar mantenciones.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_plan FROM planes_mantenimiento WHERE id = p_plan_id AND activo_plan;
    IF NOT FOUND OR v_plan.frecuencia_horas IS NULL OR v_plan.frecuencia_horas <= 0 THEN
        RAISE EXCEPTION 'La pauta no existe o no es por horas.' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_nota, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe el motivo (mínimo 5 caracteres).' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_act FROM activos WHERE id = v_plan.activo_id;
    IF coalesce(v_act.horas_uso_actual, 0) <= 0 THEN
        RAISE EXCEPTION 'El equipo no tiene horómetro.' USING ERRCODE = 'P0001';
    END IF;
    F := v_plan.frecuencia_horas;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Indica a qué horómetro toca.' USING ERRCODE = 'P0001';
    END IF;

    -- La base más alta (la menor pauta que se mueve) no puede quedar sobre el horómetro.
    SELECT max(CASE WHEN pm.id = p_plan_id THEN p_horas - F
                    WHEN pm.frecuencia_horas < F AND mod(F, pm.frecuencia_horas) = 0 THEN p_horas - pm.frecuencia_horas
                    WHEN pm.frecuencia_horas > F AND mod(pm.frecuencia_horas, F) = 0 THEN p_horas - F END)
      INTO v_max
      FROM planes_mantenimiento pm
     WHERE pm.activo_id = v_plan.activo_id AND pm.activo_plan
       AND pm.frecuencia_horas IS NOT NULL AND pm.frecuencia_horas > 0;
    IF v_max > v_act.horas_uso_actual THEN
        RAISE EXCEPTION 'La próxima puede tocar a lo más a las % h (horómetro actual % h).',
            round(v_act.horas_uso_actual + (p_horas - v_max), 1), round(v_act.horas_uso_actual, 1)
            USING ERRCODE = 'P0001';
    END IF;

    SELECT least(greatest(coalesce(horas_por_dia, 8), 2), 20) INTO v_ritmo
      FROM v_equipo_horas WHERE activo_id = v_plan.activo_id;
    v_ritmo := coalesce(v_ritmo, 8);

    FOR r IN
        SELECT pm.* FROM planes_mantenimiento pm
         WHERE pm.activo_id = v_plan.activo_id AND pm.activo_plan
           AND pm.frecuencia_horas IS NOT NULL AND pm.frecuencia_horas > 0
    LOOP
        v_base := CASE WHEN r.id = p_plan_id THEN p_horas - F
                       WHEN r.frecuencia_horas < F AND mod(F, r.frecuencia_horas) = 0 THEN p_horas - r.frecuencia_horas
                       WHEN r.frecuencia_horas > F AND mod(r.frecuencia_horas, F) = 0 THEN p_horas - F END;
        CONTINUE WHEN v_base IS NULL;
        v_fecha := v_hoy - ceil(greatest(v_act.horas_uso_actual - v_base, 0) / v_ritmo)::INT;

        INSERT INTO plan_mantenimiento_registro_manual (plan_id, activo_id, fecha, horas, km, nota, antes, absorbidos)
        VALUES (r.id, r.activo_id, v_fecha, v_base, NULL,
                format('Escalera: próxima %s a las %s h · %s', v_plan.nombre, p_horas, btrim(p_nota)),
                jsonb_build_object('fecha', r.ultima_ejecucion_fecha, 'horas', r.ultima_ejecucion_horas,
                                   'km', r.ultima_ejecucion_km), 0);

        UPDATE planes_mantenimiento
           SET ultima_ejecucion_horas = v_base,
               ultima_ejecucion_fecha = v_fecha,
               proxima_ejecucion_fecha = v_fecha + coalesce(frecuencia_dias, 30),
               updated_at = NOW()
         WHERE id = r.id;
        v_n := v_n + 1;
        v_cambios := v_cambios || jsonb_build_object('pauta', r.nombre, 'base', v_base, 'fecha', v_fecha);
    END LOOP;

    RETURN jsonb_build_object('pautas', v_n, 'cambios', v_cambios);
END $function$;

REVOKE ALL ON FUNCTION rpc_escalera_reprogramar(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_escalera_reprogramar(UUID, NUMERIC, TEXT) TO authenticated;

COMMIT;
