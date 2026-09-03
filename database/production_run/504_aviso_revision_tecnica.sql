-- ============================================================================
-- MIG504 · Aviso semanal: equipos con la revisión técnica vencida o por vencer
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «también tiene que llegar de aquellos equipos próximos a cumplir
-- su revisión técnica; eso debe llegar a Hersaly, Rodrigo, Juan Pablo y
-- Ricardo».
--
-- CÓMO FUNCIONA
-- El dato ya existe: v_certificacion_actual (MIG415-429, tipo
-- 'revision_tecnica') sabe el estado real de la RT vigente de cada equipo —
-- 'vencido', 'por_vencer' (≤30 días) o 'vigente'. Acá se expone al cron con el
-- patrón MIG301 (secreto compartido, sin service_role) y se programa el POST
-- semanal: lunes 08:15 Chile, junto al resumen de exámenes.
--
-- Destinatarios: RT_EMAIL_TO en Netlify.
-- ANTES DE APLICAR: reemplazar <CRON_SECRET> por el valor real (nunca al repo).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_rt_por_vencer_cron(p_secreto TEXT)
RETURNS TABLE (
    activo_id         UUID,
    patente           TEXT,
    codigo            TEXT,
    nombre            TEXT,
    cliente           TEXT,
    fecha_vencimiento DATE,
    dias_restantes    INT,
    estado            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    SELECT a.id,
           a.patente::TEXT, a.codigo::TEXT, a.nombre::TEXT,
           a.cliente_actual::TEXT,
           c.fecha_vencimiento,
           c.dias_restantes::INT,
           c.estado_real::TEXT
      FROM v_certificacion_actual c
      JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
     WHERE c.tipo::TEXT = 'revision_tecnica'
       AND c.estado_real IN ('vencido', 'por_vencer')
     ORDER BY (c.estado_real = 'vencido') DESC, c.dias_restantes NULLS FIRST, a.patente;
END;
$$;

REVOKE ALL ON FUNCTION fn_rt_por_vencer_cron(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_rt_por_vencer_cron(TEXT) TO anon, authenticated;

COMMIT;

-- ── El cron semanal ─────────────────────────────────────────────────────────
SELECT cron.unschedule('revision-tecnica-por-vencer')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer');

SELECT cron.schedule(
    'revision-tecnica-por-vencer',
    '15 12 * * 1',         -- LUNES 08:15 en Chile continental (UTC-4)
    $cron$
    -- Barra final + timeout 30 s: las lecciones de MIG501.
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/notificaciones/revision-tecnica/',
        headers := jsonb_build_object(
                       'Content-Type',  'application/json',
                       'x-cron-secret', '<CRON_SECRET>'),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000
    );
    $cron$
);

-- ── Verificación (aborta si el secreto no calza — regla MIG501) ─────────────
DO $mig$
DECLARE v_cmd TEXT; v_sec TEXT; v_ok BOOLEAN; v_n INT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    IF v_cmd IS NULL THEN RAISE EXCEPTION 'FALLO: el job no quedó programado'; END IF;
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL OR v_sec = '<CRON' || '_SECRET>' THEN
        RAISE EXCEPTION 'FALLO: falta reemplazar el secreto real antes de aplicar'; END IF;
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: el secreto del cron NO calza con sistema_secretos'; END IF;

    SELECT count(*) INTO v_n FROM fn_rt_por_vencer_cron(v_sec);
    RAISE NOTICE 'cron RT OK · hoy hay % equipos con la RT vencida o por vencer', v_n;
END
$mig$;
