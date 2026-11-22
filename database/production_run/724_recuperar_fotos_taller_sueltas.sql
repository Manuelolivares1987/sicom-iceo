-- ============================================================================
-- MIG724 — Recuperar fotos de Taller que quedaron sueltas (22-11-2026)
-- ----------------------------------------------------------------------------
-- El 9 y 12-11 el mecánico sacó fotos de tareas; la foto llegó a Storage pero
-- el servidor no la anotó en la tarea (la OT ya no admitía cambios del
-- mecánico y el UPDATE bajo RLS pasa sin error). La app la daba por subida.
-- Arreglo de la app: PR #546. Esto anota en su tarea cada foto de checklist
-- de los últimos 30 días que está en Storage y no figura en ninguna tarea.
-- Solo AGREGA URLs a foto_urls (no borra ni cambia otra cosa). Idempotente.
-- ============================================================================

WITH refs AS (
  SELECT u
  FROM checklist_v2_instance_item i, unnest(coalesce(i.foto_urls, ARRAY[i.foto_url])) u
  WHERE u IS NOT NULL
),
sueltas AS (
  SELECT
    ii.id AS item_id,
    'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/' || o.name AS url,
    o.created_at
  FROM storage.objects o
  JOIN checklist_v2_instance_item ii
    ON ii.id::text = split_part(split_part(o.name, '/', 3), '_', 1)
   AND ii.instance_id::text = split_part(o.name, '/', 2)
  WHERE o.bucket_id = 'evidencias-verificacion'
    AND o.name LIKE 'checklist-v2/%'
    AND o.created_at > now() - interval '30 days'
    AND NOT EXISTS (
      SELECT 1 FROM refs r
      WHERE split_part(r.u, '?', 1) LIKE '%/evidencias-verificacion/' || o.name
    )
),
por_item AS (
  SELECT item_id, array_agg(url ORDER BY created_at) AS nuevas
  FROM sueltas GROUP BY item_id
)
UPDATE checklist_v2_instance_item ii
SET foto_urls = coalesce(ii.foto_urls, CASE WHEN ii.foto_url IS NOT NULL THEN ARRAY[ii.foto_url] ELSE ARRAY[]::text[] END) || p.nuevas,
    foto_url  = coalesce(ii.foto_url, p.nuevas[1])
FROM por_item p
WHERE ii.id = p.item_id;

-- Validación: cuántas fotos de checklist de los últimos 30 días siguen sueltas (debe ser 0).
SELECT count(*) AS siguen_sueltas
FROM storage.objects o
WHERE o.bucket_id = 'evidencias-verificacion' AND o.name LIKE 'checklist-v2/%'
  AND o.created_at > now() - interval '30 days'
  AND NOT EXISTS (
    SELECT 1 FROM checklist_v2_instance_item i, unnest(coalesce(i.foto_urls, ARRAY[i.foto_url])) u
    WHERE split_part(u, '?', 1) LIKE '%/evidencias-verificacion/' || o.name
  );
