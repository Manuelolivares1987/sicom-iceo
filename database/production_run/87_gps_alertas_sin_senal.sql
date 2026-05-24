-- ============================================================================
-- 87_gps_alertas_sin_senal.sql
-- ----------------------------------------------------------------------------
-- Alertas automaticas cuando un activo ARRENDADO o en LEASING lleva mas de
-- N horas sin reportar señal GPS. Sin esto, el problema es invisible hasta
-- que alguien corre una query manual (como recien hicimos: detectamos
-- 15 activos con >24h sin señal, uno con 31 dias).
--
-- Estrategia:
--   1. Vista v_gps_activos_riesgo: lista de activos arrendados/leasing en
--      riesgo (sin señal por categoria de tiempo).
--   2. fn_gps_generar_alertas_sin_senal: crea alertas en tabla 'alertas'
--      para los activos en riesgo (idempotente: no duplica si ya hay alerta
--      activa para el mismo activo).
--   3. Cron job 'gps-alertas-sin-senal': corre cada hora.
--
-- Niveles de severidad:
--   - warning  : 24-72h sin señal
--   - critical : >72h sin señal o bateria < 10%
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. Extender CHECK chk_alertas_tipo para aceptar 'gps_sin_senal' ────────
-- Sin esto, fn_gps_generar_alertas_sin_senal falla al insertar la alerta.
DO $body$
DECLARE
    v_def TEXT;
    v_new TEXT;
BEGIN
    SELECT pg_get_constraintdef(c.oid) INTO v_def
      FROM pg_constraint c
     WHERE c.conrelid = 'public.alertas'::regclass
       AND c.conname  = 'chk_alertas_tipo';

    IF v_def IS NULL THEN
        RAISE NOTICE 'Constraint chk_alertas_tipo no existe — se omite el patch';
        RETURN;
    END IF;
    IF v_def LIKE '%gps_sin_senal%' THEN
        RAISE NOTICE 'Constraint ya incluye gps_sin_senal — nada que hacer';
        RETURN;
    END IF;
    ALTER TABLE alertas DROP CONSTRAINT chk_alertas_tipo;
    v_new := regexp_replace(v_def, '\]\)\)$', ', ''gps_sin_senal''::text]))', 1);
    EXECUTE 'ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo ' || v_new;
    RAISE NOTICE 'Constraint chk_alertas_tipo extendido con gps_sin_senal';
END $body$;


-- ── 1. Vista de activos en riesgo ───────────────────────────────────────────
DROP VIEW IF EXISTS v_gps_activos_riesgo CASCADE;
CREATE VIEW v_gps_activos_riesgo AS
SELECT
    v.activo_id,
    v.activo_codigo,
    v.patente,
    v.activo_nombre,
    v.estado_comercial,
    v.contrato_cliente,
    v.faena_nombre,
    v.gps_device_id,
    v.gps_ultima_senal,
    v.gps_minutos_offline,
    ROUND(v.gps_minutos_offline / 60.0, 1)  AS horas_sin_senal,
    ROUND(v.gps_minutos_offline / 1440.0, 1) AS dias_sin_senal,
    v.gps_bateria_pct,
    CASE
        WHEN v.gps_minutos_offline > 4320 THEN 'critical'  -- >72h
        WHEN v.gps_bateria_pct IS NOT NULL AND v.gps_bateria_pct < 10 THEN 'critical'
        WHEN v.gps_minutos_offline > 1440 THEN 'warning'   -- 24-72h
        ELSE 'info'
    END AS severidad_sugerida,
    CASE
        WHEN v.gps_minutos_offline > 4320 AND v.gps_bateria_pct >= 50
            THEN 'tracker_probablemente_desconectado'
        WHEN v.gps_bateria_pct IS NOT NULL AND v.gps_bateria_pct < 10
            THEN 'bateria_baja'
        WHEN v.gps_minutos_offline > 1440
            THEN 'sin_reportar_24h'
        ELSE 'otro'
    END AS motivo_sugerido
FROM v_flota_dashboard_unificado v
WHERE v.estado_comercial IN ('arrendado','leasing','uso_interno')
  AND v.gps_device_id IS NOT NULL
  AND v.gps_estado_pin = 'sin_senal_24h';

COMMENT ON VIEW v_gps_activos_riesgo IS
    'Activos arrendados/leasing/uso_interno con tracker mapeado y sin señal >24h. MIG87.';


-- ── 2. Funcion que genera alertas (idempotente) ─────────────────────────────
CREATE OR REPLACE FUNCTION fn_gps_generar_alertas_sin_senal()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_r           RECORD;
    v_creadas     INT := 0;
    v_existentes  INT := 0;
    v_alerta_id   UUID;
BEGIN
    FOR v_r IN
        SELECT * FROM v_gps_activos_riesgo
        WHERE severidad_sugerida IN ('warning','critical')
    LOOP
        -- Si ya hay alerta activa de este tipo para este activo, no crear duplicado
        IF EXISTS (
            SELECT 1 FROM alertas
             WHERE entidad_tipo = 'activo'
               AND entidad_id = v_r.activo_id
               AND tipo = 'gps_sin_senal'
               AND leida = false
               AND created_at > NOW() - INTERVAL '24 hours'
        ) THEN
            v_existentes := v_existentes + 1;
            CONTINUE;
        END IF;

        v_alerta_id := gen_random_uuid();
        INSERT INTO alertas (
            id, tipo, titulo, mensaje, severidad,
            entidad_tipo, entidad_id, leida, created_at
        ) VALUES (
            v_alerta_id,
            'gps_sin_senal',
            'GPS sin señal: ' || v_r.activo_codigo ||
                CASE WHEN v_r.patente IS NOT NULL THEN ' · ' || v_r.patente ELSE '' END,
            'Activo ' || v_r.activo_codigo
                || ' (' || COALESCE(v_r.patente, '—') || ')'
                || ' en ' || v_r.estado_comercial
                || ' lleva ' || ROUND(v_r.dias_sin_senal, 1)::text
                || ' dias sin reportar GPS. Cliente: ' || COALESCE(v_r.contrato_cliente, '—')
                || ', Faena: ' || COALESCE(v_r.faena_nombre, '—')
                || '. Bateria: ' || CASE WHEN v_r.gps_bateria_pct IS NULL THEN '—'
                                          ELSE v_r.gps_bateria_pct::text || '%' END
                || '. Causa probable: ' || v_r.motivo_sugerido,
            v_r.severidad_sugerida,
            'activo', v_r.activo_id, false, NOW()
        );
        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success',           true,
        'alertas_creadas',   v_creadas,
        'alertas_existentes', v_existentes,
        'ts',                NOW()
    );
END;
$$;

COMMENT ON FUNCTION fn_gps_generar_alertas_sin_senal IS
    'Genera alertas para activos arrendados/leasing/interno sin señal GPS >24h. Idempotente. MIG87.';


-- ── 3. Cron job: cada hora ──────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gps-alertas-sin-senal') THEN
        PERFORM cron.unschedule('gps-alertas-sin-senal');
    END IF;
END $$;

SELECT cron.schedule(
    job_name => 'gps-alertas-sin-senal',
    schedule => '0 * * * *',  -- cada hora en :00
    command  => $cmd$ SELECT fn_gps_generar_alertas_sin_senal(); $cmd$
);


GRANT EXECUTE ON FUNCTION fn_gps_generar_alertas_sin_senal() TO authenticated;
GRANT SELECT  ON v_gps_activos_riesgo TO authenticated;


-- ── 4. Ejecutar la primera vez para crear alertas del estado actual ────────
SELECT fn_gps_generar_alertas_sin_senal();


-- ── Validacion ──────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'vista_creada', to_regclass('public.v_gps_activos_riesgo') IS NOT NULL,
    'rpc_creada',   EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_gps_generar_alertas_sin_senal'),
    'cron_creado',  EXISTS(SELECT 1 FROM cron.job WHERE jobname='gps-alertas-sin-senal'),
    'activos_en_riesgo_ahora', (SELECT COUNT(*) FROM v_gps_activos_riesgo WHERE severidad_sugerida IN ('warning','critical')),
    'alertas_gps_activas',     (SELECT COUNT(*) FROM alertas WHERE tipo = 'gps_sin_senal' AND leida = false)
) AS resultado;

NOTIFY pgrst, 'reload schema';
