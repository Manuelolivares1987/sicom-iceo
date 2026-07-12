-- ============================================================================
-- SICOM-ICEO | 228 — Alertas de vencimiento documental (campanita)
-- ============================================================================
-- "La clave es tener una alerta cuando se aproxime el vencimiento" (Manuel).
-- Cron diario que alimenta la campanita (tabla alertas):
--   1. HITOS por vencer: cuando a un documento le quedan 30 / 15 / 7 / 1 días
--      → 1 alerta warning por documento (dedup 5 días).
--   2. RECIÉN VENCIDO: el día después del vencimiento → alerta critical.
--   3. RESUMEN por equipo: si un equipo tiene documentos vencidos acumulados
--      → 1 alerta critical por equipo, se repite cada 7 días hasta resolver.
-- Usa v_documentos_equipo_estado (último doc por tipo, solo flota viva).
-- Documentos "permanentes" (vencimiento 2099) quedan fuera.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_alertas_documentos_vencimiento()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_hitos INT; v_vencidos INT; v_resumen INT;
BEGIN
    -- 1. Hitos de aproximación: 30 / 15 / 7 / 1 días
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
    SELECT 'doc_por_vencer',
           'Documento por vencer: ' || initcap(replace(d.tipo, '_', ' ')) || ' — ' || COALESCE(d.patente, d.codigo),
           COALESCE(d.patente, d.codigo) || ' (' || COALESCE(d.nombre,'') || '): ' ||
             initcap(replace(d.tipo, '_', ' ')) || ' vence el ' || to_char(d.fecha_vencimiento, 'DD-MM-YYYY') ||
             ' (en ' || d.dias_restantes || ' día' || CASE WHEN d.dias_restantes = 1 THEN '' ELSE 's' END ||
             '). Renuévalo en Plan Semanal → Documentos con problemas.',
           'warning', 'activo', d.activo_id
      FROM v_documentos_equipo_estado d
     WHERE d.dias_restantes IN (30, 15, 7, 1)
       AND d.fecha_vencimiento < DATE '2099-01-01'
       AND NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_por_vencer'
              AND a.entidad_id = d.activo_id
              AND a.titulo LIKE '%' || initcap(replace(d.tipo, '_', ' ')) || '%'
              AND a.created_at > CURRENT_DATE - 5);
    GET DIAGNOSTICS v_hitos = ROW_COUNT;

    -- 2. Recién vencidos (venció ayer)
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
    SELECT 'doc_vencido',
           'Documento VENCIDO: ' || initcap(replace(d.tipo, '_', ' ')) || ' — ' || COALESCE(d.patente, d.codigo),
           COALESCE(d.patente, d.codigo) || ': ' || initcap(replace(d.tipo, '_', ' ')) ||
             ' venció el ' || to_char(d.fecha_vencimiento, 'DD-MM-YYYY') ||
             CASE WHEN d.bloqueante THEN ' — BLOQUEANTE para operar.' ELSE '. Gestionar renovación.' END,
           'critical', 'activo', d.activo_id
      FROM v_documentos_equipo_estado d
     WHERE d.fecha_vencimiento = CURRENT_DATE - 1
       AND NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_vencido' AND a.entidad_id = d.activo_id
              AND a.titulo LIKE '%' || initcap(replace(d.tipo, '_', ' ')) || '%'
              AND a.created_at > CURRENT_DATE - 5);
    GET DIAGNOSTICS v_vencidos = ROW_COUNT;

    -- 3. Resumen por equipo con vencidos acumulados (se repite cada 7 días)
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
    SELECT 'doc_vencidos_equipo',
           'Documentos vencidos: ' || COALESCE(x.patente, x.codigo) || ' (' || x.n || ')',
           COALESCE(x.patente, x.codigo) || ' tiene ' || x.n || ' documento' ||
             CASE WHEN x.n = 1 THEN '' ELSE 's' END || ' vencido' ||
             CASE WHEN x.n = 1 THEN '' ELSE 's' END || ': ' || x.lista ||
             '. Revisa Plan Semanal → Documentos con problemas.',
           'critical', 'activo', x.activo_id
      FROM (
        SELECT d.activo_id, d.patente, d.codigo, count(*) AS n,
               string_agg(initcap(replace(d.tipo, '_', ' ')), ', ' ORDER BY d.fecha_vencimiento) AS lista
          FROM v_documentos_equipo_estado d
         WHERE d.fecha_vencimiento < CURRENT_DATE
           AND d.fecha_vencimiento > CURRENT_DATE - INTERVAL '10 years'
         GROUP BY d.activo_id, d.patente, d.codigo
      ) x
     WHERE NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_vencidos_equipo' AND a.entidad_id = x.activo_id
              AND a.created_at > CURRENT_DATE - 7);
    GET DIAGNOSTICS v_resumen = ROW_COUNT;

    RETURN jsonb_build_object('hitos', v_hitos, 'vencidos_ayer', v_vencidos, 'resumen_equipos', v_resumen);
END $$;

-- ── Cron diario 07:30 (con log, mismo patrón que los demás jobs) ────────────
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'alertas-doc-vencimientos';
SELECT cron.schedule('alertas-doc-vencimientos', '30 7 * * *', $cron$
    DO $job$
    DECLARE
        v_start TIMESTAMPTZ := clock_timestamp();
        v_r JSONB;
    BEGIN
        v_r := fn_alertas_documentos_vencimiento();
        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, detalles, duracion_ms)
        VALUES ('alertas-doc-vencimientos', 'ok',
                COALESCE((v_r->>'hitos')::int,0) + COALESCE((v_r->>'vencidos_ayer')::int,0) + COALESCE((v_r->>'resumen_equipos')::int,0),
                v_r, EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('alertas-doc-vencimientos', 'error', SQLERRM);
    END $job$;
$cron$);

DO $$ BEGIN RAISE NOTICE 'MIG228 OK: alertas de vencimiento documental + cron diario 07:30'; END $$;
