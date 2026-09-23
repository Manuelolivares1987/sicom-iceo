-- ============================================================================
-- MIG574 · Se apaga la alerta antigua «GPS sin señal»: la reemplaza el Centinela
-- ============================================================================
--
-- 23-09-2026, Manuel: «sí, apaga la alerta antigua de GPS».
--
-- fn_gps_generar_alertas_sin_senal (cron horario 'gps-alertas-sin-senal')
-- escribía una alerta nueva por equipo cada 24 h en `alertas`: 951 en total,
-- 39 abiertas hoy, sin correo ni dueño. Fue ahí donde se perdieron las 48
-- alertas críticas de KVWD-27. El Centinela (MIG571-573) cubre lo mismo con un
-- incidente por camión, correo, acuse y escalamiento.
--
-- Reversible: el job se PAUSA (no se borra) y la función queda. Para volver:
--   SELECT cron.alter_job((SELECT jobid FROM cron.job
--          WHERE jobname = 'gps-alertas-sin-senal'), active := true);
-- ============================================================================

BEGIN;

SELECT cron.alter_job(jobid, active := false)
  FROM cron.job WHERE jobname = 'gps-alertas-sin-senal';

-- Las abiertas se archivan para que dejen de pesar en la campanita.
UPDATE alertas
   SET leida = true,
       leida_en = NOW(),
       motivo_cierre = 'Reemplazada por el Centinela de flota (MIG574)'
 WHERE tipo = 'gps_sin_senal' AND leida = false;

COMMIT;

DO $mig$
DECLARE v_activo BOOLEAN; v_abiertas INT;
BEGIN
    SELECT active INTO v_activo FROM cron.job WHERE jobname = 'gps-alertas-sin-senal';
    SELECT count(*) INTO v_abiertas FROM alertas WHERE tipo = 'gps_sin_senal' AND NOT leida;
    IF v_activo OR v_abiertas > 0 THEN
        RAISE EXCEPTION 'FALLO: job activo=% · abiertas=%', v_activo, v_abiertas;
    END IF;
    RAISE NOTICE 'Alerta antigua de GPS apagada: job pausado, 0 abiertas';
END
$mig$;
