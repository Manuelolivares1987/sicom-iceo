-- ============================================================================
-- SICOM-ICEO | 568 — El bucket de evidencias acepta lo que el teléfono ofrece
-- ============================================================================
-- Manuel (2026-09-17), OT-202609-00037 (entrega en arriendo): «el operador ha
-- colocado fotos pero no las puedo ver en mi pc».
--
-- En el servidor no había NINGUNA foto de esa OT, y el usuario (iPhone) jamás
-- había subido una. El botón de foto del checklist en /m/taller acepta
-- "image/*,video/*", pero evidencias-verificacion solo admitía JPG/PNG/WEBP
-- hasta 10 MB: la HEIC del iPhone y cualquier video rebotaban en la cola
-- offline, y en el teléfono la foto se seguía viendo (desde el teléfono).
--
-- El frontend ahora convierte toda imagen a JPEG antes de subir; esto es la red
-- de seguridad para lo que no se pueda convertir (y para los videos, que el
-- botón ofrece desde siempre y nunca pudieron subir).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
           'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
           'video/mp4', 'video/quicktime', 'video/webm'],
       file_size_limit = 52428800   -- 50 MB (un video corto de celular)
 WHERE id = 'evidencias-verificacion';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM storage.buckets
                    WHERE id = 'evidencias-verificacion'
                      AND 'image/heic' = ANY (allowed_mime_types)
                      AND 'video/quicktime' = ANY (allowed_mime_types)) THEN
        RAISE EXCEPTION 'MIG568: el bucket evidencias-verificacion no quedó actualizado';
    END IF;
    RAISE NOTICE 'MIG568 OK · evidencias-verificacion acepta HEIC y video hasta 50 MB';
END $$;

SELECT id, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'evidencias-verificacion';
