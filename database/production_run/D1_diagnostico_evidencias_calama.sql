-- ============================================================================
-- D1_diagnostico_evidencias_calama.sql
-- ----------------------------------------------------------------------------
-- DIAGNOSTICO consolidado (NO migracion, NO modifica datos).
--
-- Ejecuta TODO el archivo de una vez en el SQL Editor de Supabase. Devuelve
-- UNA sola fila con columna `diagnostico` (JSONB) que contiene los 8 bloques.
-- Esto evita el problema de Supabase que solo muestra el ultimo SELECT
-- cuando se ejecutan multiples sentencias.
--
-- Para leer comodo: click derecho sobre la celda -> "View cell" o copia el
-- valor a un viewer JSON. Tambien puedes correr esta misma query con
-- "select jsonb_pretty(diagnostico) ..." para formato indentado.
-- ============================================================================

WITH
-- BLOQUE 1: distribucion de sync_status
b1_sync_status AS (
    SELECT sync_status,
           COUNT(*) AS evidencias,
           MIN(created_at) AS primera,
           MAX(created_at) AS ultima
      FROM calama_evidencias
     GROUP BY sync_status
),

-- BLOQUE 2: evidencias por OT de prueba terreno
b2_por_ot_prueba AS (
    SELECT o.folio,
           o.id AS ot_id,
           COUNT(e.id) FILTER (WHERE e.tipo = 'foto')                          AS fotos,
           COUNT(e.id) FILTER (WHERE e.tipo = 'firma')                         AS firmas,
           COUNT(e.id) FILTER (WHERE e.contexto = 'jornada_antes')             AS evid_antes,
           COUNT(e.id) FILTER (WHERE e.contexto = 'jornada_durante')           AS evid_durante,
           COUNT(e.id) FILTER (WHERE e.contexto = 'jornada_despues')           AS evid_despues,
           COUNT(e.id) FILTER (WHERE e.contexto = 'llegada_faena')             AS evid_llegada,
           COUNT(e.id) FILTER (WHERE e.contexto = 'firma')                     AS evid_firma,
           COUNT(e.id) FILTER (WHERE e.contexto = 'interferencia_mandante')    AS evid_interferencia,
           COUNT(e.id)                                                         AS total_evidencias
      FROM calama_ordenes_trabajo o
      LEFT JOIN calama_evidencias e ON e.ot_id = o.id
     WHERE o.es_prueba = true
     GROUP BY o.folio, o.id
),

-- BLOQUE 3: evidencias rotas (sin archivo_url o sin storage_path)
b3_rotas AS (
    SELECT id, ot_id, contexto, momento, tipo, sync_status,
           (archivo_url  IS NULL OR length(archivo_url)  = 0) AS sin_url,
           (storage_path IS NULL OR length(storage_path) = 0) AS sin_path,
           created_at
      FROM calama_evidencias
     WHERE archivo_url  IS NULL OR length(archivo_url)  = 0
        OR storage_path IS NULL OR length(storage_path) = 0
     LIMIT 30
),

-- BLOQUE 4: storage bucket vs filas en BD
b4_storage_vs_bd AS (
    SELECT
        (SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'calama-evidencias') AS objetos_bucket_evidencias,
        (SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'calama-firmas')     AS objetos_bucket_firmas,
        (SELECT COUNT(*) FROM calama_evidencias)                                      AS filas_evidencias_total,
        (SELECT COUNT(*) FROM calama_evidencias
          WHERE archivo_url IS NOT NULL AND length(archivo_url) > 0)                  AS filas_evidencias_con_url,
        (SELECT COUNT(*) FROM calama_firmas_jornada)                                  AS filas_firmas_total
),

-- BLOQUE 5: buckets de Storage (publicos / privados)
b5_buckets AS (
    SELECT id, name, public, file_size_limit
      FROM storage.buckets
     WHERE id IN ('calama-evidencias','calama-firmas')
),

-- BLOQUE 6: RLS / visibilidad del usuario actual
b6_rls AS (
    SELECT
        auth.uid()                                  AS mi_uid,
        fn_user_rol()                               AS mi_rol_global,
        fn_calama_rol_proyecto()                    AS mi_rol_proyecto,
        fn_calama_es_admin_global()                 AS soy_admin_global,
        (SELECT COUNT(*) FROM calama_evidencias)    AS evidencias_visibles_para_mi,
        (SELECT COUNT(*) FROM calama_firmas_jornada) AS firmas_visibles_para_mi
),

-- BLOQUE 7: detalle de la OT TEST-TERRENO mas reciente (cada evidencia)
b7_detalle_ot_test AS (
    SELECT e.id, e.contexto, e.momento, e.tipo, e.sync_status,
           SUBSTRING(e.archivo_url FROM 1 FOR 80) AS url_prefijo,
           e.client_uuid, e.created_at, e.created_by,
           o.folio
      FROM calama_evidencias e
      JOIN calama_ordenes_trabajo o ON o.id = e.ot_id
     WHERE o.folio LIKE '%TEST-TERRENO%'
     ORDER BY e.created_at DESC
     LIMIT 50
),

-- BLOQUE 8: firmas (todas las de OTs de prueba)
b8_firmas AS (
    SELECT f.id, f.contexto, f.firmante_tipo, f.firmante_nombre,
           SUBSTRING(f.firma_url FROM 1 FOR 80) AS url_prefijo,
           f.client_uuid, f.created_at
      FROM calama_firmas_jornada f
      JOIN calama_plan_semanal_ots p ON p.id = f.plan_semanal_ot_id
      JOIN calama_ordenes_trabajo   o ON o.id = p.ot_id
     WHERE o.es_prueba = true
     ORDER BY f.created_at DESC
     LIMIT 30
)

SELECT jsonb_pretty(jsonb_build_object(
    'bloque_1_sync_status',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b1_sync_status)), '[]'::jsonb) FROM b1_sync_status),
    'bloque_2_por_ot_prueba',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b2_por_ot_prueba)), '[]'::jsonb) FROM b2_por_ot_prueba),
    'bloque_3_evidencias_rotas',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b3_rotas)), '[]'::jsonb) FROM b3_rotas),
    'bloque_4_storage_vs_bd',
        (SELECT to_jsonb(b4_storage_vs_bd) FROM b4_storage_vs_bd),
    'bloque_5_buckets',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b5_buckets)), '[]'::jsonb) FROM b5_buckets),
    'bloque_6_rls_admin',
        (SELECT to_jsonb(b6_rls) FROM b6_rls),
    'bloque_7_detalle_ot_test',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b7_detalle_ot_test)), '[]'::jsonb) FROM b7_detalle_ot_test),
    'bloque_8_firmas',
        (SELECT COALESCE(jsonb_agg(to_jsonb(b8_firmas)), '[]'::jsonb) FROM b8_firmas)
)) AS diagnostico;
