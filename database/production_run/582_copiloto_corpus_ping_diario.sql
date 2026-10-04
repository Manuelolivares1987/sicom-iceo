-- ============================================================================
-- MIG582 · Copiloto: ping diario para que la biblioteca no se pause sola
-- ============================================================================
--
-- 04-10-2026, Manuel preguntó si el copiloto tiene información de Mack. Al ir
-- a contarla, la biblioteca (proyecto Supabase aparte «copiloto-corpus», plan
-- gratuito) estaba INACTIVE: se pausa sola tras una semana sin uso y la última
-- consulta del taller fue el 24-09. El copiloto abría, pero sin manuales.
-- Manuel: «te autorizo, reactívalo y arma el ping diario».
--
-- Un cron diario llama a /api/copiloto/ping/, que hace una consulta real a la
-- base del corpus. Mismo patrón y mismo secreto que los correos (MIG571):
-- pg_cron → net.http_post con x-cron-secret. La URL lleva barra final.
--
-- 10:30 UTC = 07:30 Chile en verano, 06:30 en invierno: antes del turno.
-- ============================================================================

DO $cron$
DECLARE
    v_cmd TEXT;
    v_sec TEXT;
    v_ok  BOOLEAN;
BEGIN
    -- El secreto vigente se toma de un job activo y se verifica (regla MIG501).
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF v_sec IS NULL OR NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: no hay un CRON_SECRET vigente que reutilizar';
    END IF;

    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname = 'copiloto-corpus-ping';

    PERFORM cron.schedule('copiloto-corpus-ping', '30 10 * * *', format($p$
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/copiloto/ping/',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', %L),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000);
    $p$, v_sec));
END
$cron$;

-- ── Verificación ─────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_cmd TEXT; v_act BOOLEAN;
BEGIN
    SELECT command, active INTO v_cmd, v_act FROM cron.job WHERE jobname = 'copiloto-corpus-ping';
    IF v_cmd IS NULL OR NOT v_act
       OR v_cmd NOT LIKE '%/api/copiloto/ping/%' OR v_cmd NOT LIKE '%x-cron-secret%' THEN
        RAISE EXCEPTION 'FALLO: el job copiloto-corpus-ping no quedó bien armado';
    END IF;
    RAISE NOTICE 'OK: copiloto-corpus-ping programado (diario 10:30 UTC)';
END
$mig$;

SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'copiloto-corpus-ping';
