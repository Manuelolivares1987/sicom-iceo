-- ============================================================================
-- SICOM-ICEO | 166 — Bucket 'documentos' a público (alinear con el resto)
-- ============================================================================
-- Problema: el bucket 'documentos' estaba como PRIVADO (public=false), pero todo
-- el código que sube ahí (RT en Plan Taller, OC de bodega, checklist cliente,
-- certificaciones) usa getPublicUrl(). En un bucket privado esa URL no abre, así
-- que los documentos subidos quedaban con enlace roto al intentar verlos.
--
-- El resto de buckets de la app (calama-evidencias, calama-firmas,
-- evidencias-combustible, evidencias-verificacion) son TODOS públicos + getPublicUrl.
-- 'documentos' era la única anomalía. Lo alineamos: público.
-- IDEMPOTENTE.
-- ============================================================================

UPDATE storage.buckets SET public = true WHERE id = 'documentos';

SELECT id, public FROM storage.buckets WHERE id = 'documentos';
