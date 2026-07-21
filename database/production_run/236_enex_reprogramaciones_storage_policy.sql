-- ============================================================================
-- SICOM-ICEO | 236 — Storage: permitir subir PDFs de reprogramación ENEX
-- ============================================================================
-- El "Registro de Reprogramación de Actividades" (MIG234) se sube a
-- documentos/enex-reprogramaciones/<año>/. El bucket 'documentos' restringe
-- INSERT por prefijo de carpeta; faltaba la política para este prefijo, por lo
-- que el upload fallaba (RLS) y el PDF no quedaba guardado. Se agregan las
-- políticas INSERT/UPDATE para authenticated, en línea con enex-informes.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DROP POLICY IF EXISTS storage_enex_reprog_insert ON storage.objects;
CREATE POLICY storage_enex_reprog_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-reprogramaciones');

DROP POLICY IF EXISTS storage_enex_reprog_update ON storage.objects;
CREATE POLICY storage_enex_reprog_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-reprogramaciones')
  WITH CHECK (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-reprogramaciones');

SELECT jsonb_build_object(
  'politicas', (SELECT array_agg(policyname ORDER BY policyname) FROM pg_policies
                WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'storage_enex_reprog_%')
) AS resultado;
