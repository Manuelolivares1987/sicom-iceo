-- ============================================================================
-- prevencion-db-salud.sql
-- Blindaje para que NINGUNA tabla vuelva a tumbar la DB por crecer sin tope.
--   1. Quita el cron GPS abusivo (el UPDATE directo a cron.job NO funciona en
--      Supabase; hay que usar cron.unschedule()).
--   2. Crea un WATCHDOG: bitacora diaria de tamaño de DB + top tablas, para que
--      VEAS el problema venir antes de que sea crisis.
--   3. Retencion automatica de las tablas-log (GPS, geocercas, alertas viejas,
--      log de jobs). NO toca datos del negocio (inventario, combustible, OTs...).
--   4. Una sola rutina diaria que hace todo.
--
-- Correr en Supabase SQL Editor, seccion por seccion. Idempotente.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- SECCION 1 — Quitar el/los cron GPS de 60s (reemplaza el UPDATE que fallo)
-- ════════════════════════════════════════════════════════════════════════════
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE command ILIKE '%gps-radicom-poll%';

-- Verificar que ya no quedan:
SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobid;


-- ════════════════════════════════════════════════════════════════════════════
-- SECCION 2 — Bitacora de salud (VISIBILIDAD: "saber que esta pasando")
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS db_salud_log (
    id          BIGSERIAL PRIMARY KEY,
    medido_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
    db_mb       NUMERIC,            -- tamaño total de la DB en MB
    umbral_mb   NUMERIC,            -- umbral configurado
    en_riesgo   BOOLEAN,            -- true si db_mb > umbral
    detalle     JSONB               -- top tablas + filas borradas en la purga
);


-- ════════════════════════════════════════════════════════════════════════════
-- SECCION 3 — Rutina de mantenimiento diario (purga + watchdog)
-- Cada purga va en su propio bloque: si una falla (ej. columna distinta), las
-- demas igual se ejecutan. No aborta todo.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_mantenimiento_diario(p_umbral_mb NUMERIC DEFAULT 350)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_res     JSONB := '{}'::jsonb;
    v_n       BIGINT;
    v_db_mb   NUMERIC;
    v_top     JSONB;
    v_riesgo  BOOLEAN;
BEGIN
    -- 1. GPS telemetria > 30 dias
    BEGIN
        DELETE FROM gps_eventos_log WHERE ts_gps < now() - interval '30 days';
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_res := v_res || jsonb_build_object('gps_eventos', v_n);
    EXCEPTION WHEN OTHERS THEN v_res := v_res || jsonb_build_object('gps_eventos_err', SQLERRM); END;

    -- 2. Eventos de geocerca > 90 dias
    BEGIN
        IF to_regclass('public.gps_geocerca_eventos') IS NOT NULL THEN
            DELETE FROM gps_geocerca_eventos WHERE created_at < now() - interval '90 days';
            GET DIAGNOSTICS v_n = ROW_COUNT;
            v_res := v_res || jsonb_build_object('geocerca_eventos', v_n);
        END IF;
    EXCEPTION WHEN OTHERS THEN v_res := v_res || jsonb_build_object('geocerca_err', SQLERRM); END;

    -- 3. Alertas ya leidas > 90 dias (las no leidas se conservan)
    BEGIN
        DELETE FROM alertas WHERE leida = true AND created_at < now() - interval '90 days';
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_res := v_res || jsonb_build_object('alertas_leidas', v_n);
    EXCEPTION WHEN OTHERS THEN v_res := v_res || jsonb_build_object('alertas_err', SQLERRM); END;

    -- 4. Log de jobs automaticos > 30 dias
    BEGIN
        IF to_regclass('public.log_jobs_automaticos') IS NOT NULL THEN
            DELETE FROM log_jobs_automaticos WHERE created_at < now() - interval '30 days';
            GET DIAGNOSTICS v_n = ROW_COUNT;
            v_res := v_res || jsonb_build_object('log_jobs', v_n);
        END IF;
    EXCEPTION WHEN OTHERS THEN v_res := v_res || jsonb_build_object('log_jobs_err', SQLERRM); END;

    -- 5. WATCHDOG: tamaño total + top 6 tablas
    SELECT round(pg_database_size(current_database()) / 1048576.0, 1) INTO v_db_mb;
    SELECT jsonb_agg(t) INTO v_top FROM (
        SELECT relname AS tabla,
               round(pg_total_relation_size(relid) / 1048576.0, 1) AS mb,
               n_live_tup AS filas
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(relid) DESC
        LIMIT 6
    ) t;
    v_riesgo := v_db_mb > p_umbral_mb;

    INSERT INTO db_salud_log (db_mb, umbral_mb, en_riesgo, detalle)
    VALUES (v_db_mb, p_umbral_mb, v_riesgo,
            v_res || jsonb_build_object('db_mb', v_db_mb, 'top_tablas', v_top));

    RETURN jsonb_build_object('db_mb', v_db_mb, 'en_riesgo', v_riesgo,
                              'purgas', v_res, 'top_tablas', v_top);
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- SECCION 4 — Programar la rutina (todos los dias 04:00 UTC ~ 00:00 Chile)
-- ════════════════════════════════════════════════════════════════════════════
SELECT cron.unschedule('mantenimiento-diario')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'mantenimiento-diario');

SELECT cron.schedule(
    'mantenimiento-diario',
    '0 4 * * *',
    $$ SELECT fn_mantenimiento_diario(350); $$   -- umbral 350 MB (Free=500). Sube en Pro.
);


-- ════════════════════════════════════════════════════════════════════════════
-- SECCION 5 — Primera corrida + queries de visibilidad (corre cuando quieras)
-- ════════════════════════════════════════════════════════════════════════════
-- Ejecuta la rutina ahora mismo y muestra el resultado:
SELECT fn_mantenimiento_diario(350);

-- Ver el tamaño total de la DB:
SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano_db;

-- Ver las tablas mas grandes (esto es "saber que esta pasando"):
SELECT relname AS tabla,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamano,
       n_live_tup AS filas
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 15;

-- Ver el historial de salud (tendencia dia a dia):
SELECT medido_en, db_mb, en_riesgo FROM db_salud_log ORDER BY medido_en DESC LIMIT 30;
