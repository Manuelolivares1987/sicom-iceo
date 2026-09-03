-- ============================================================================
-- MIG502 · Aviso por correo: el cliente no ha hecho su checklist del QR
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «hay algo muy importante que es el checklist que hace el cliente
-- escaneando el QR: debe llegar un correo de aviso si el cliente no lo ha
-- hecho».
--
-- CÓMO FUNCIONA
-- El cálculo ya existe: v_checklist_cliente_cumplimiento (MIG127/129) sabe,
-- por cada equipo fuera de nuestras instalaciones, cuándo fue el último
-- checklist del cliente y si está al día. Acá solo se expone al cron con el
-- patrón de MIG301 (el secreto compartido, SIN service_role) y se programa el
-- POST diario.
--
-- QUÉ AVISA Y CUÁNDO
-- Diario a las 09:00 Chile, pero SOLO cuando hay equipos con más de 7 días sin
-- checklist ('atrasado') o que nunca han tenido uno ('sin_check'). Mientras el
-- cliente cumpla su semana, silencio. Cuando se atrasa, insiste todos los días
-- hasta que lo haga — igual que un examen vencido.
--
-- ANTES DE APLICAR: reemplazar <CRON_SECRET> por el valor real (nunca al repo)
-- y tener CHECKLIST_CLIENTE_EMAIL_TO configurado en Netlify.
-- ============================================================================

BEGIN;

-- ── 1 · Lo que el cron puede leer, gateado por el secreto ───────────────────
CREATE OR REPLACE FUNCTION fn_checklist_cliente_pendientes_cron(p_secreto TEXT)
RETURNS TABLE (
    activo_id         UUID,
    patente           TEXT,
    codigo            TEXT,
    nombre            TEXT,
    cliente           TEXT,
    estado_comercial  TEXT,
    ultima_fecha      DATE,
    dias_desde_ultimo INT,
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
    SELECT v.activo_id,
           v.patente::TEXT, v.codigo::TEXT, v.nombre::TEXT, v.cliente::TEXT,
           v.estado_comercial::TEXT,
           v.ultima_fecha, v.dias_desde_ultimo::INT,
           v.estado_cumplimiento::TEXT
      FROM v_checklist_cliente_cumplimiento v
     WHERE v.estado_cumplimiento <> 'al_dia'
     ORDER BY (v.estado_cumplimiento = 'sin_check') DESC,
              v.dias_desde_ultimo DESC NULLS FIRST,
              v.cliente NULLS LAST, v.patente;
END;
$$;

REVOKE ALL ON FUNCTION fn_checklist_cliente_pendientes_cron(TEXT) FROM PUBLIC;
-- anon: la ruta del correo usa la clave anónima; sin el secreto la función no
-- entrega nada (mismo diseño que las alertas de exámenes, MIG301).
GRANT EXECUTE ON FUNCTION fn_checklist_cliente_pendientes_cron(TEXT) TO anon, authenticated;

COMMIT;

-- ── 2 · El cron diario (fuera de la transacción, como MIG300/501) ───────────
SELECT cron.unschedule('checklist-cliente-pendiente')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'checklist-cliente-pendiente');

SELECT cron.schedule(
    'checklist-cliente-pendiente',
    '0 13 * * *',          -- 09:00 en Chile continental (UTC-4)
    $cron$
    -- Barra final obligatoria (trailingSlash) y timeout de 30 s: las dos
    -- lecciones de MIG501 — sin ellas el cron corre «exitoso» y mudo.
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/notificaciones/checklist-cliente/',
        headers := jsonb_build_object(
                       'Content-Type',  'application/json',
                       'x-cron-secret', '<CRON_SECRET>'),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000
    );
    $cron$
);

-- ── Verificación (aborta si el secreto no es el vigente — regla MIG501) ─────
DO $mig$
DECLARE v_cmd TEXT; v_sec TEXT; v_ok BOOLEAN; v_n INT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'checklist-cliente-pendiente';
    IF v_cmd IS NULL THEN RAISE EXCEPTION 'FALLO: el job no quedó programado'; END IF;

    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL OR v_sec = '<CRON' || '_SECRET>' THEN
        RAISE EXCEPTION 'FALLO: falta reemplazar el secreto real antes de aplicar';
    END IF;
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: el secreto del cron NO calza con sistema_secretos';
    END IF;

    -- La función responde con el secreto embebido (prueba real del gate).
    SELECT count(*) INTO v_n FROM fn_checklist_cliente_pendientes_cron(v_sec);
    RAISE NOTICE 'cron OK · hoy hay % equipos con checklist del cliente pendiente/atrasado', v_n;
END
$mig$;
