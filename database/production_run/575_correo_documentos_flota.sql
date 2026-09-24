-- ============================================================================
-- MIG575 · Correo diario de papeles de flota (todos los documentos, arrendados primero)
-- ============================================================================
--
-- 24-09-2026, Manuel: «necesito que los correos salgan referente a
-- documentación de vehículos (principalmente los que están en arriendo y
-- próximamente se van a vencer papeles)». Elegido: diario, solo si hay
-- cambios; a los mismos destinatarios del aviso de revisión técnica.
--
-- Hasta hoy el único correo de papeles era el de REVISIÓN TÉCNICA (MIG504,
-- lunes). Hermeticidad, análisis de gases, SOAP, permiso de circulación,
-- SEC, mantención por horas, etc. solo generaban alertas dentro de la app.
-- Al 24-09 había 61 papeles vencidos y 21 por vencer; en equipos arrendados
-- o en leasing, varios tipos con 9–11 cada uno.
--
-- Cómo decide si manda:
--   · Cada papel vencido/por vencer cae en un TRAMO: vencido · ≤7 d · ≤15 d ·
--     ≤30 d (o ≤50 h si vence por horómetro).
--   · `docs_flota_avisos` guarda el último tramo avisado de cada certificado.
--   · Se manda si algún papel entró a la lista o bajó de tramo (marcado NUEVO
--     en el correo). Los lunes se manda igual, como recordatorio completo.
--   · El papel renovado sale solo: el certificado nuevo queda vigente y el
--     viejo deja de ser «el actual».
--   · Se marca DESPUÉS de que el correo salió (si falla, se reintenta mañana).
--
-- Reemplaza al correo semanal de RT: ese job se PAUSA (no se borra). Para volver:
--   SELECT cron.alter_job((SELECT jobid FROM cron.job
--          WHERE jobname = 'revision-tecnica-por-vencer'), active := true);
--
-- Sin service_role: el mismo CRON_SECRET habilita estas dos funciones (MIG301).
-- El comando del cron se copia del job de RT, así el secreto no vive en el repo.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS docs_flota_avisos (
    certificacion_id UUID PRIMARY KEY,
    tramo            TEXT NOT NULL,
    avisado_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE docs_flota_avisos IS
    '[MIG575] Último tramo avisado por correo de cada certificado de flota. Solo lo tocan las funciones *_cron.';
ALTER TABLE docs_flota_avisos ENABLE ROW LEVEL SECURITY;   -- sin políticas: nadie la lee por la API
REVOKE ALL ON docs_flota_avisos FROM anon, authenticated;

CREATE OR REPLACE FUNCTION fn_docs_flota_tramo(p_estado TEXT, p_dias INT, p_horas INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_estado = 'vencido'   THEN 'vencido'
        WHEN p_horas IS NOT NULL    THEN 'h50'
        WHEN p_dias IS NULL         THEN 'd30'
        WHEN p_dias <= 7            THEN 'd7'
        WHEN p_dias <= 15           THEN 'd15'
        ELSE 'd30'
    END
$$;

CREATE OR REPLACE FUNCTION fn_docs_flota_cron(p_secreto TEXT, p_incluir_pruebas BOOLEAN DEFAULT false)
RETURNS TABLE(
    certificacion_id UUID, activo_id UUID, patente TEXT, codigo TEXT, nombre TEXT,
    cliente TEXT, estado_comercial TEXT, en_arriendo BOOLEAN, zona TEXT, faena TEXT,
    documento TEXT, fecha_vencimiento DATE, dias_restantes INT, horas_restantes INT,
    estado TEXT, bloqueante BOOLEAN, tramo TEXT, nuevo BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    WITH x AS (
        SELECT c.id AS cid, a.id AS aid,
               a.patente::TEXT AS pat, a.codigo::TEXT AS cod, a.nombre::TEXT AS nom,
               a.cliente_actual::TEXT AS cli, a.estado_comercial::TEXT AS ec,
               COALESCE(NULLIF(TRIM(a.operacion::TEXT), ''), 'Sin zona') AS zon,
               COALESCE(f.nombre::TEXT, NULLIF(a.ubicacion_actual::TEXT, '')) AS fae,
               c.etiqueta::TEXT AS doc, c.fecha_vencimiento AS fv,
               c.dias_restantes::INT AS dr, c.horas_restantes::INT AS hr,
               c.estado_real::TEXT AS est, COALESCE(c.bloqueante, false) AS blq
          FROM v_certificacion_actual c
          JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
          LEFT JOIN faenas f ON f.id = a.faena_id
         WHERE c.estado_real IN ('vencido', 'por_vencer')
           -- [MIG531] Modo prueba: SOLO el laboratorio. Modo real: NUNCA el laboratorio.
           AND (CASE WHEN p_incluir_pruebas THEN COALESCE(a.es_prueba, false)
                     ELSE NOT COALESCE(a.es_prueba, false) END)
    )
    SELECT x.cid, x.aid, x.pat, x.cod, x.nom, x.cli, x.ec,
           COALESCE(x.ec IN ('arrendado', 'leasing'), false),
           x.zon, x.fae, x.doc, x.fv, x.dr, x.hr, x.est, x.blq,
           fn_docs_flota_tramo(x.est, x.dr, x.hr),
           (av.tramo IS DISTINCT FROM fn_docs_flota_tramo(x.est, x.dr, x.hr))
      FROM x
      LEFT JOIN docs_flota_avisos av ON av.certificacion_id = x.cid
     ORDER BY COALESCE(x.ec IN ('arrendado', 'leasing'), false) DESC, x.zon, x.pat,
              (x.est = 'vencido') DESC, x.dr NULLS FIRST;
END;
$$;

-- Se llama DESPUÉS de enviar: deja registrado el tramo avisado de cada papel
-- y olvida los que ya no están en la lista (renovados), para que si vuelven a
-- acercarse al vencimiento se avisen de nuevo.
CREATE OR REPLACE FUNCTION fn_docs_flota_marcar_cron(p_secreto TEXT, p_items JSONB)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_n INT;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    DELETE FROM docs_flota_avisos d
     WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) e
                        WHERE (e->>'certificacion_id')::UUID = d.certificacion_id);
    INSERT INTO docs_flota_avisos (certificacion_id, tramo, avisado_at)
    SELECT (e->>'certificacion_id')::UUID, e->>'tramo', now()
      FROM jsonb_array_elements(p_items) e
    ON CONFLICT (certificacion_id) DO UPDATE
       SET tramo = EXCLUDED.tramo, avisado_at = EXCLUDED.avisado_at
     WHERE docs_flota_avisos.tramo IS DISTINCT FROM EXCLUDED.tramo;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION fn_docs_flota_cron(TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_docs_flota_marcar_cron(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_docs_flota_cron(TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_docs_flota_marcar_cron(TEXT, JSONB) TO anon, authenticated;

-- ── Cron diario 11:00 UTC (08:00 Chile), copiado del de RT con su secreto ───
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'documentos-flota-diario';
SELECT cron.schedule(
    'documentos-flota-diario',
    '0 11 * * *',
    replace((SELECT command FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer'),
            '/api/notificaciones/revision-tecnica/',
            '/api/notificaciones/documentos-flota/'));

SELECT cron.alter_job(jobid, active := false)
  FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';

-- ── Verificación ─────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_cmd TEXT; v_rt BOOLEAN;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    IF v_cmd IS NULL OR v_cmd NOT LIKE '%/api/notificaciones/documentos-flota/%'
       OR v_cmd NOT LIKE '%x-cron-secret%' THEN
        RAISE EXCEPTION 'FALLO: el job documentos-flota-diario no quedó bien armado';
    END IF;
    SELECT active INTO v_rt FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    IF v_rt THEN RAISE EXCEPTION 'FALLO: el job de RT sigue activo'; END IF;
    RAISE NOTICE 'OK: documentos-flota-diario programado; RT semanal pausado';
END $mig$;

COMMIT;
