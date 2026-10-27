-- ============================================================================
-- 657_gps_mapa_cada_5_min_y_hora_real.sql
-- ----------------------------------------------------------------------------
-- 27-10-2026. SBPG-12 iba a 90 km/h y en nuestro mapa aparecía ~30 km atrás
-- de lo que mostraba Radicom. Dos causas:
--
--   1. El cron gps-radicom-states corre UNA vez por hora (se espació en mayo
--      por el I/O del cómputo NANO). El mapa refresca cada 60 s, pero relee
--      la misma foto: hasta 60 min de atraso.
--   2. Navixy entrega la hora en hora de Chile y la edge function le pega
--      una «Z» (la trata como UTC): ts_gps queda 3 h atrás (4 h en invierno).
--      El mapa decía «hace 3 h» a camiones que reportaron hace 2 minutos.
--
-- Qué cambia:
--   - Cron cada 5 min. Para NO multiplicar las escrituras pesadas, la RPC
--     decide el modo por lote:
--       · COMPLETO (≈1 vez por hora, o si trae counters): igual que antes,
--         inserta en gps_eventos_log → horas por día, activos km/horas
--         (auditoría), geocercas.
--       · LIVIANO (el resto): solo actualiza la posición en gps_estado_actual
--         y únicamente si cambió algo. Sin log, sin tocar activos.
--   - La hora de Radicom se lee del payload con fn_navixy_ts (America/Santiago,
--     sigue bien con el cambio de horario). No hace falta redesplegar la edge
--     function. El historial viejo NO se corrige aquí.
--   - El trigger de geocercas ya no corre si la posición no cambió.
--   - cron.job_run_details no se purgaba nunca (desde marzo, 29 MB): se
--     guardan 30 días. Compensa las 288 corridas diarias nuevas.
--
-- Medido antes de aplicar (27-10): BD 331 MB; cómputo con 90 conexiones y
-- 512 MB de shared_buffers; caché 99,98 %; WAL ≈ 42 MB/día; ≈ 38 mil updates
-- y 103 mil inserts por día. El modo liviano suma como máximo ~16 mil updates
-- diarios sobre una tabla de 55 filas (104 kB) que vive en memoria.
-- ============================================================================

ALTER TABLE config_gps_proveedor
    ADD COLUMN IF NOT EXISTS ultimo_log_at TIMESTAMPTZ;

COMMENT ON COLUMN config_gps_proveedor.ultimo_log_at IS
  'MIG657: último lote que se escribió completo en gps_eventos_log. Si fue hace < 55 min, el lote siguiente solo mueve la posición en gps_estado_actual.';


CREATE OR REPLACE FUNCTION rpc_ingestar_gps_batch(p_proveedor_nombre TEXT, p_eventos JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_proveedor_id UUID;
    v_ultimo_log   TIMESTAMPTZ;
    v_completo     BOOLEAN;
    v_ev           JSONB;
    v_activo_id    UUID;
    v_ts           TIMESTAMPTZ;
    v_contacto     TIMESTAMPTZ;
    v_insertados   INTEGER := 0;
    v_movidos      INTEGER := 0;
    v_n            INTEGER;
    v_sin_mapeo    INTEGER := 0;
    v_errores      INTEGER := 0;
BEGIN
    -- 1. Resolver proveedor (FOR UPDATE: dos lotes simultáneos no escriben ambos completo)
    SELECT id, ultimo_log_at INTO v_proveedor_id, v_ultimo_log
      FROM config_gps_proveedor
     WHERE nombre = p_proveedor_nombre
       AND activo = true
     LIMIT 1
       FOR UPDATE;

    IF v_proveedor_id IS NULL THEN
        RAISE EXCEPTION 'Proveedor GPS no encontrado o inactivo: %', p_proveedor_nombre;
    END IF;

    -- [MIG657] Modo del lote. Solo Radicom tiene modo liviano.
    v_completo := p_proveedor_nombre <> 'Radicom'
               OR v_ultimo_log IS NULL
               OR v_ultimo_log < NOW() - INTERVAL '55 minutes'
               OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_eventos) e
                           WHERE NULLIF(e->>'odometer_km', '') IS NOT NULL
                              OR NULLIF(e->>'engine_hours', '') IS NOT NULL);

    -- 2. Procesar cada evento
    FOR v_ev IN SELECT * FROM jsonb_array_elements(p_eventos)
    LOOP
        BEGIN
            -- Buscar mapeo dispositivo -> activo
            SELECT activo_id INTO v_activo_id
              FROM gps_activo_mapeo
             WHERE proveedor_id = v_proveedor_id
               AND gps_device_id = v_ev->>'gps_device_id'
               AND activo = true
             LIMIT 1;

            IF v_activo_id IS NULL THEN
                v_sin_mapeo := v_sin_mapeo + 1;
            END IF;

            -- [MIG657] Navixy entrega hora de Chile: se lee del payload crudo.
            IF p_proveedor_nombre = 'Radicom' THEN
                v_ts := COALESCE(fn_navixy_ts(v_ev->'payload'->'gps'->>'updated'),
                                 fn_navixy_ts(v_ev->'payload'->>'last_update'),
                                 NOW());
            ELSE
                v_ts := COALESCE(NULLIF(v_ev->>'ts_gps','')::TIMESTAMPTZ, NOW());
            END IF;

            IF v_completo THEN
                INSERT INTO gps_eventos_log (
                    proveedor_id, gps_device_id, activo_id,
                    ts_gps,
                    latitud, longitud, velocidad_kmh, heading, altitud_m,
                    ignicion, movimiento, conexion,
                    odometro_km, horometro_hrs,
                    bateria_pct, gsm_red, gsm_signal,
                    inputs, outputs, payload_raw
                ) VALUES (
                    v_proveedor_id,
                    v_ev->>'gps_device_id',
                    v_activo_id,
                    v_ts,
                    NULLIF(v_ev->>'lat','')::NUMERIC,
                    NULLIF(v_ev->>'lng','')::NUMERIC,
                    NULLIF(v_ev->>'speed','')::NUMERIC,
                    NULLIF(v_ev->>'heading','')::NUMERIC,
                    NULLIF(v_ev->>'altitude','')::NUMERIC,
                    NULLIF(v_ev->>'ignition','')::BOOLEAN,
                    NULLIF(v_ev->>'movement',''),
                    NULLIF(v_ev->>'connection',''),
                    NULLIF(v_ev->>'odometer_km','')::NUMERIC,
                    NULLIF(v_ev->>'engine_hours','')::NUMERIC,
                    NULLIF(v_ev->>'battery_pct','')::NUMERIC,
                    NULLIF(v_ev->>'gsm_network',''),
                    NULLIF(v_ev->>'gsm_signal','')::NUMERIC,
                    v_ev->'inputs',
                    v_ev->'outputs',
                    v_ev->'payload'
                );
                v_insertados := v_insertados + 1;

            ELSIF v_activo_id IS NOT NULL THEN
                -- Liviano: solo la posición, y solo si cambió algo.
                v_contacto := fn_navixy_ts(v_ev->'payload'->>'last_update');
                UPDATE gps_estado_actual e
                   SET ts_gps             = v_ts,
                       ts_actualizado     = NOW(),
                       latitud            = NULLIF(v_ev->>'lat','')::NUMERIC,
                       longitud           = NULLIF(v_ev->>'lng','')::NUMERIC,
                       velocidad_kmh      = NULLIF(v_ev->>'speed','')::NUMERIC,
                       heading            = NULLIF(v_ev->>'heading','')::NUMERIC,
                       ignicion           = NULLIF(v_ev->>'ignition','')::BOOLEAN,
                       movimiento         = NULLIF(v_ev->>'movement',''),
                       conexion           = NULLIF(v_ev->>'connection',''),
                       bateria_pct        = NULLIF(v_ev->>'battery_pct','')::NUMERIC,
                       gsm_red            = NULLIF(v_ev->>'gsm_network',''),
                       ts_ultimo_contacto = GREATEST(e.ts_ultimo_contacto, v_contacto)
                 WHERE e.activo_id = v_activo_id
                   AND (e.ts_gps IS NULL OR v_ts >= e.ts_gps)
                   AND (e.ts_gps, e.latitud, e.longitud, e.velocidad_kmh, e.ignicion,
                        e.movimiento, e.conexion, e.ts_ultimo_contacto)
                       IS DISTINCT FROM
                       -- mismas escalas que las columnas: si no, el redondeo
                       -- hace «distinta» una posición idéntica
                       (v_ts, NULLIF(v_ev->>'lat','')::NUMERIC(10,7), NULLIF(v_ev->>'lng','')::NUMERIC(10,7),
                        NULLIF(v_ev->>'speed','')::NUMERIC(6,2), NULLIF(v_ev->>'ignition','')::BOOLEAN,
                        NULLIF(v_ev->>'movement','')::VARCHAR, NULLIF(v_ev->>'connection','')::VARCHAR,
                        GREATEST(e.ts_ultimo_contacto, v_contacto));
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos + v_n;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_errores := v_errores + 1;
        END;
    END LOOP;

    IF v_completo THEN
        UPDATE config_gps_proveedor SET ultimo_log_at = NOW() WHERE id = v_proveedor_id;
    END IF;

    RETURN jsonb_build_object(
        'modo',         CASE WHEN v_completo THEN 'completo' ELSE 'liviano' END,
        'insertados',   v_insertados,
        'movidos',      v_movidos,
        'sin_mapeo',    v_sin_mapeo,
        'errores',      v_errores,
        'proveedor_id', v_proveedor_id,
        'ts',           NOW()
    );
END;
$function$;


-- Geocercas: en INSERT siempre; en UPDATE solo si la posición cambió.
DROP TRIGGER IF EXISTS trg_geocercas_evaluar ON gps_estado_actual;
CREATE TRIGGER trg_geocercas_evaluar
    AFTER INSERT ON gps_estado_actual
    FOR EACH ROW EXECUTE FUNCTION fn_evaluar_geocercas_estado();
CREATE TRIGGER trg_geocercas_evaluar_upd
    AFTER UPDATE OF latitud, longitud ON gps_estado_actual
    FOR EACH ROW
    WHEN (OLD.latitud IS DISTINCT FROM NEW.latitud OR OLD.longitud IS DISTINCT FROM NEW.longitud)
    EXECUTE FUNCTION fn_evaluar_geocercas_estado();


-- Cron: cada 5 min (el modo liviano lo hace barato).
SELECT cron.alter_job(jobid, schedule := '*/5 * * * *')
  FROM cron.job WHERE jobname = 'gps-radicom-states';

-- Historial de crons: 30 días.
DELETE FROM cron.job_run_details WHERE end_time < NOW() - INTERVAL '30 days';
SELECT cron.unschedule('purgar-historial-cron')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purgar-historial-cron');
SELECT cron.schedule('purgar-historial-cron', '30 4 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < NOW() - INTERVAL '30 days'$$);

SELECT jobname, schedule, active FROM cron.job
 WHERE jobname IN ('gps-radicom-states', 'purgar-historial-cron');
