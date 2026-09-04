-- ============================================================================
-- MIG513 · La regla de ABSORCIÓN: la SL es la intermedia, la visita es UNA
-- ============================================================================
--
-- LO QUE DIJO MANUEL (04-09-2026)
-- «Entonces la regla de los 300 horas no es correcta, o correcta a medias:
-- la SL (Servicio liviano) es una intermedia.»
--
-- Exacto. Con la escalera de MIG510 (SL 300 / S1 600 / S2 1200…), a las 600 h
-- vencen la SL Y la S1 a la vez, y el motor generaba DOS OT para UNA visita.
-- La S1 trae la SL adentro: se programa solo el peldaño mayor, y al cerrarlo
-- los menores quedan al día. La SL solo se ejecuta sola en las visitas
-- intermedias (300, 900, 1500…).
--
-- ADEMÁS, DOS DEUDAS DE MIG510 QUE ESTA MIGRACIÓN PAGA
--  1. Los 210 planes por equipo COPIAN la frecuencia de su pauta al crearse:
--     MIG510 cambió las pautas pero los planes seguían en 200/400/800…
--     Se sincronizan (frecuencias, nombre, y se apagan los planes de pautas
--     desactivadas — las sueltas duplicadas de MB).
--  2. Las pautas nuevas (Scania, Accelo, Renault SL, camionetas) no tenían
--     PLANES en ningún equipo: se siembran, con línea base = lectura actual
--     (la primera visita es en +300 h desde hoy, no una avalancha de OT
--     vencidas el primer día).
-- ============================================================================

BEGIN;

-- ── 1 · Los planes se sincronizan con su pauta (deuda MIG510) ───────────────
UPDATE planes_mantenimiento pm
   SET frecuencia_horas = pf.frecuencia_horas,
       frecuencia_km    = pf.frecuencia_km,
       frecuencia_dias  = pf.frecuencia_dias,
       tipo_plan        = pf.tipo_plan,
       nombre           = pf.nombre,
       -- Un plan de una pauta desactivada se apaga; uno apagado a mano NO se
       -- prende solo.
       activo_plan      = pm.activo_plan AND pf.activo,
       updated_at       = NOW()
  FROM pautas_fabricante pf
 WHERE pf.id = pm.pauta_fabricante_id
   AND (pm.frecuencia_horas IS DISTINCT FROM pf.frecuencia_horas
        OR pm.frecuencia_km  IS DISTINCT FROM pf.frecuencia_km
        OR pm.frecuencia_dias IS DISTINCT FROM pf.frecuencia_dias
        OR pm.tipo_plan      IS DISTINCT FROM pf.tipo_plan
        OR pm.nombre         IS DISTINCT FROM pf.nombre
        OR (pm.activo_plan AND NOT pf.activo));

-- ── 2 · Sembrar los planes que faltan (Scania, Accelo, y todo hueco) ────────
INSERT INTO planes_mantenimiento (activo_id, pauta_fabricante_id, nombre, tipo_plan,
    frecuencia_dias, frecuencia_km, frecuencia_horas, frecuencia_ciclos,
    anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_km,
    ultima_ejecucion_horas, activo_plan)
SELECT a.id, pf.id, pf.nombre, pf.tipo_plan,
       pf.frecuencia_dias, pf.frecuencia_km, pf.frecuencia_horas, pf.frecuencia_ciclos,
       7, 'normal'::prioridad_enum,
       -- Línea base = HOY con la lectura actual: la primera visita es dentro
       -- de un ciclo, no una avalancha de OT vencidas el primer día.
       CURRENT_DATE, a.kilometraje_actual, a.horas_uso_actual, TRUE
  FROM activos a
  JOIN modelos mo ON mo.id = a.modelo_id
  JOIN pautas_fabricante pf ON pf.modelo_id = mo.id AND pf.activo
 WHERE a.fecha_baja IS NULL
   AND NOT EXISTS (SELECT 1 FROM planes_mantenimiento x
                    WHERE x.activo_id = a.id AND x.pauta_fabricante_id = pf.id);

-- ── 3 · Absorción al GENERAR: una visita, una OT ────────────────────────────
-- El cron deja de llevar la lógica adentro: llama a esta función (editable sin
-- reprogramar el job). Misma mecánica de siempre + la regla nueva.
CREATE OR REPLACE FUNCTION fn_generar_ots_preventivas()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_plan RECORD; v_result JSONB;
    v_count INT := 0; v_absorbidas INT := 0; v_errors INT := 0;
    v_start TIMESTAMPTZ := clock_timestamp();
BEGIN
    FOR v_plan IN
        SELECT pm.*, a.contrato_id, a.faena_id, a.kilometraje_actual,
               a.horas_uso_actual, a.ciclos_actual, a.estado AS activo_estado
          FROM planes_mantenimiento pm
          JOIN activos a ON a.id = pm.activo_id
         WHERE pm.activo_plan = TRUE
           AND a.estado = 'operativo'
           AND NOT EXISTS (
               SELECT 1 FROM ordenes_trabajo ot
                WHERE ot.plan_mantenimiento_id = pm.id
                  AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                                        'no_ejecutada','cancelada','cerrada'))
    LOOP
        IF (
            (v_plan.tipo_plan = 'por_tiempo' AND v_plan.proxima_ejecucion_fecha IS NOT NULL
             AND v_plan.proxima_ejecucion_fecha <= CURRENT_DATE)
            OR (v_plan.tipo_plan IN ('por_kilometraje','mixto') AND v_plan.frecuencia_km IS NOT NULL
                AND (v_plan.kilometraje_actual - COALESCE(v_plan.ultima_ejecucion_km, 0)) >= v_plan.frecuencia_km)
            OR (v_plan.tipo_plan IN ('por_horas','mixto') AND v_plan.frecuencia_horas IS NOT NULL
                AND (v_plan.horas_uso_actual - COALESCE(v_plan.ultima_ejecucion_horas, 0)) >= v_plan.frecuencia_horas)
            OR (v_plan.tipo_plan = 'por_ciclos' AND v_plan.frecuencia_ciclos IS NOT NULL
                AND (v_plan.ciclos_actual - COALESCE(v_plan.ultima_ejecucion_ciclos, 0)) >= v_plan.frecuencia_ciclos)
        ) THEN
            -- [MIG513] ABSORCIÓN: si en el mismo equipo también venció un
            -- peldaño MAYOR de la escalera por horas, esta visita es UNA y la
            -- hace el mayor (la S1 trae la SL adentro). El menor no genera OT;
            -- su línea base avanza cuando el mayor se cierre.
            IF v_plan.tipo_plan IN ('por_horas','mixto') AND v_plan.frecuencia_horas IS NOT NULL
               AND EXISTS (
                   SELECT 1
                     FROM planes_mantenimiento pm2
                    WHERE pm2.activo_id = v_plan.activo_id
                      AND pm2.id <> v_plan.id
                      AND pm2.activo_plan
                      AND pm2.tipo_plan IN ('por_horas','mixto')
                      AND pm2.frecuencia_horas > v_plan.frecuencia_horas
                      AND (v_plan.horas_uso_actual - COALESCE(pm2.ultima_ejecucion_horas, 0))
                          >= pm2.frecuencia_horas)
            THEN
                v_absorbidas := v_absorbidas + 1;
                CONTINUE;
            END IF;

            BEGIN
                SELECT rpc_crear_ot(
                    p_tipo := 'preventivo',
                    p_contrato_id := v_plan.contrato_id,
                    p_faena_id := v_plan.faena_id,
                    p_activo_id := v_plan.activo_id,
                    p_prioridad := COALESCE(v_plan.prioridad, 'normal'),
                    p_fecha_programada := COALESCE(v_plan.proxima_ejecucion_fecha,
                                                   CURRENT_DATE + COALESCE(v_plan.anticipacion_dias, 7)),
                    p_plan_mantenimiento_id := v_plan.id
                ) INTO v_result;
                v_count := v_count + 1;
            EXCEPTION WHEN OTHERS THEN
                v_errors := v_errors + 1;
                RAISE WARNING 'Error generando OT PM para plan %: %', v_plan.id, SQLERRM;
            END;
        END IF;
    END LOOP;

    INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, detalles, duracion_ms)
    VALUES ('generar-ots-preventivas',
            CASE WHEN v_errors > 0 THEN 'warning' ELSE 'ok' END,
            v_count,
            jsonb_build_object('ots_creadas', v_count, 'absorbidas', v_absorbidas,
                               'errores', v_errors)::text,
            round(EXTRACT(EPOCH FROM clock_timestamp() - v_start) * 1000));

    RETURN jsonb_build_object('ots_creadas', v_count, 'absorbidas', v_absorbidas, 'errores', v_errors);
END;
$$;

REVOKE ALL ON FUNCTION fn_generar_ots_preventivas() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('generar-ots-preventivas')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generar-ots-preventivas');
SELECT cron.schedule('generar-ots-preventivas', '0 1 * * *',
    $cron$SELECT fn_generar_ots_preventivas();$cron$);

-- ── 4 · Absorción al CERRAR: el mayor deja a los menores al día ─────────────
CREATE OR REPLACE FUNCTION public.fn_ot_cerrada_avanza_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_plan RECORD; v_fecha DATE;
BEGIN
    IF NEW.plan_mantenimiento_id IS NULL THEN RETURN NEW; END IF;
    IF NEW.estado::text NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.estado::text IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_plan FROM planes_mantenimiento WHERE id = NEW.plan_mantenimiento_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    v_fecha := COALESCE(NEW.fecha_termino::date, CURRENT_DATE);

    UPDATE planes_mantenimiento
       SET ultima_ejecucion_fecha = v_fecha,
           ultima_ejecucion_km    = COALESCE(
               (SELECT a.kilometraje_actual FROM activos a WHERE a.id = NEW.activo_id),
               ultima_ejecucion_km),
           ultima_ejecucion_horas = COALESCE(
               (SELECT a.horas_uso_actual FROM activos a WHERE a.id = NEW.activo_id),
               ultima_ejecucion_horas),
           proxima_ejecucion_fecha = v_fecha + COALESCE(frecuencia_dias, 30),
           updated_at = NOW()
     WHERE id = NEW.plan_mantenimiento_id;

    -- [MIG513] ABSORCIÓN: cerrar un peldaño mayor deja al día los MENORES de
    -- la misma escalera por horas (la S1 incluye la SL: hacerla ES hacer la
    -- SL). Así a las 900 h vuelve a tocar la SL sola, como manda el ciclo.
    IF v_plan.tipo_plan IN ('por_horas','mixto') AND v_plan.frecuencia_horas IS NOT NULL THEN
        UPDATE planes_mantenimiento p2
           SET ultima_ejecucion_fecha = v_fecha,
               ultima_ejecucion_km    = COALESCE(
                   (SELECT a.kilometraje_actual FROM activos a WHERE a.id = NEW.activo_id),
                   p2.ultima_ejecucion_km),
               ultima_ejecucion_horas = COALESCE(
                   (SELECT a.horas_uso_actual FROM activos a WHERE a.id = NEW.activo_id),
                   p2.ultima_ejecucion_horas),
               proxima_ejecucion_fecha = v_fecha + COALESCE(p2.frecuencia_dias, 30),
               updated_at = NOW()
         WHERE p2.activo_id = NEW.activo_id
           AND p2.id <> NEW.plan_mantenimiento_id
           AND p2.activo_plan
           AND p2.tipo_plan IN ('por_horas','mixto')
           AND p2.frecuencia_horas IS NOT NULL
           AND p2.frecuencia_horas < v_plan.frecuencia_horas;
    END IF;

    RETURN NEW;
END $function$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_desyn INT; v_scania INT; v_nuevos INT; v_apagados INT;
BEGIN
    -- Ningún plan de camión quedó con frecuencia distinta a su pauta.
    SELECT count(*) INTO v_desyn
      FROM planes_mantenimiento pm JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
     WHERE pm.activo_plan AND pf.activo
       AND pm.frecuencia_horas IS DISTINCT FROM pf.frecuencia_horas;
    IF v_desyn > 0 THEN RAISE EXCEPTION 'FALLO: % planes siguen desincronizados de su pauta', v_desyn; END IF;

    SELECT count(*) INTO v_scania
      FROM planes_mantenimiento pm
      JOIN activos a ON a.id = pm.activo_id
      JOIN modelos mo ON mo.id = a.modelo_id JOIN marcas ma ON ma.id = mo.marca_id
     WHERE ma.nombre = 'Scania' AND pm.activo_plan;
    IF v_scania = 0 THEN RAISE EXCEPTION 'FALLO: los Scania siguen sin planes'; END IF;

    SELECT count(*) INTO v_nuevos FROM planes_mantenimiento WHERE created_at > NOW() - INTERVAL '5 minutes';
    SELECT count(*) INTO v_apagados FROM planes_mantenimiento pm
      JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
     WHERE NOT pf.activo AND NOT pm.activo_plan;

    RAISE NOTICE 'planes sincronizados OK · sembrados ahora: % · planes Scania: % · apagados por pauta duplicada: %',
        v_nuevos, v_scania, v_apagados;

    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='generar-ots-preventivas'
                     AND command LIKE '%fn_generar_ots_preventivas%') THEN
        RAISE EXCEPTION 'FALLO: el cron no quedó llamando a la función nueva';
    END IF;
    RAISE NOTICE 'absorción activa: al generar (el mayor manda) y al cerrar (deja a los menores al día)';
END
$mig$;

COMMIT;
