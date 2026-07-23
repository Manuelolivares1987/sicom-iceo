-- ============================================================================
-- SICOM-ICEO | 246 — Fix: subir documentos de equipo (RLS certificaciones + storage)
-- ----------------------------------------------------------------------------
-- Bugs reportados (sugerencias 2026-07-22):
--   - "botón Agregar nuevo documento no guarda" / "new row violates row-level
--     security policy" al agregar/renovar documentación de un equipo.
--
-- Causa (2 huecos de RLS):
--   1) Tabla `certificaciones`: la única política de escritura es
--      pol_admin_all_certificaciones (solo 'administrador'). Jefe de Operaciones /
--      Jefe de Taller / planificador / supervisor quedaban bloqueados al Guardar.
--   2) Bucket de Storage `documentos`: no hay política INSERT/UPDATE para los
--      prefijos 'certificaciones/' (subida desde la ficha del activo) ni 'cert/'
--      (subida desde plan-semanal-taller). La subida del archivo fallaba con RLS.
--
-- Fix: política de escritura para roles operativos en `certificaciones`, y
-- políticas INSERT/UPDATE de storage para esos dos prefijos (authenticated).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tabla certificaciones: roles operativos pueden crear/actualizar docs ──
DROP POLICY IF EXISTS pol_docmgr_insert_certificaciones ON public.certificaciones;
CREATE POLICY pol_docmgr_insert_certificaciones ON public.certificaciones
  FOR INSERT TO authenticated
  WITH CHECK (public.fn_user_rol() IN
    ('administrador','jefe_operaciones','jefe_mantenimiento','planificador','supervisor'));

DROP POLICY IF EXISTS pol_docmgr_update_certificaciones ON public.certificaciones;
CREATE POLICY pol_docmgr_update_certificaciones ON public.certificaciones
  FOR UPDATE TO authenticated
  USING (public.fn_user_rol() IN
    ('administrador','jefe_operaciones','jefe_mantenimiento','planificador','supervisor'))
  WITH CHECK (public.fn_user_rol() IN
    ('administrador','jefe_operaciones','jefe_mantenimiento','planificador','supervisor'));


-- ── 2. Storage bucket 'documentos': subir archivo a certificaciones/ y cert/ ──
DROP POLICY IF EXISTS pol_documentos_cert_insert ON storage.objects;
CREATE POLICY pol_documentos_cert_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documentos'
    AND (name LIKE 'certificaciones/%' OR name LIKE 'cert/%')
  );

DROP POLICY IF EXISTS pol_documentos_cert_update ON storage.objects;
CREATE POLICY pol_documentos_cert_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documentos'
    AND (name LIKE 'certificaciones/%' OR name LIKE 'cert/%')
  )
  WITH CHECK (
    bucket_id = 'documentos'
    AND (name LIKE 'certificaciones/%' OR name LIKE 'cert/%')
  );


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE n_cert INT; n_stor INT;
BEGIN
    SELECT count(*) INTO n_cert FROM pg_policies
     WHERE tablename='certificaciones' AND policyname LIKE 'pol_docmgr_%';
    SELECT count(*) INTO n_stor FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'pol_documentos_cert_%';
    IF n_cert < 2 THEN RAISE EXCEPTION 'FALLO: faltan políticas en certificaciones'; END IF;
    IF n_stor < 2 THEN RAISE EXCEPTION 'FALLO: faltan políticas de storage'; END IF;
    RAISE NOTICE 'MIG246 OK: certificaciones write (%) + storage documentos (%)', n_cert, n_stor;
END $$;

NOTIFY pgrst, 'reload schema';
