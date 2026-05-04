-- ============================================================================
-- 14D_storage_policy_qr_checklist_evidencias.sql
-- ----------------------------------------------------------------------------
-- Permite a anon subir evidencias (fotos) del checklist QR publico al bucket
-- 'documentos', restringido al prefijo de path 'qr-checklist/'.
--
-- Reglas:
--   - INSERT a anon: SOLO en bucket=documentos AND path LIKE 'qr-checklist/%'.
--   - SELECT/UPDATE/DELETE a anon: NO. Mantencion accede via authenticated.
--   - Las policies existentes para authenticated NO se tocan.
--
-- IDEMPOTENTE: DROP POLICY IF EXISTS + CREATE POLICY.
-- NO TOCA: backend QR validado, mig 55/56/57, otras policies.
--
-- ⚠️ NOTA CRITICA SOBRE PUBLIC FLAG DEL BUCKET:
--   Si storage.buckets.public = TRUE para 'documentos', cualquiera con la URL
--   directa (CDN getPublicUrl) puede LEER el archivo, bypaseando las policies.
--   Las policies solo aplican al endpoint REST autenticado, no al CDN publico.
--   Si tu bucket es publico (probablemente lo es porque certificaciones usan
--   getPublicUrl), considera migrar a un bucket privado dedicado para QR.
--   Este script verifica el flag y lo reporta abajo.
-- ============================================================================


-- ── 0. Garantizar que el bucket exista ──────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('documentos', 'documentos', false)
ON CONFLICT (id) DO NOTHING;


-- ── 1. Recrear policy de INSERT para anon ───────────────────────────
DROP POLICY IF EXISTS "storage_qr_checklist_anon_insert" ON storage.objects;

CREATE POLICY "storage_qr_checklist_anon_insert"
ON storage.objects
FOR INSERT
TO anon
WITH CHECK (
    bucket_id = 'documentos'
    AND (storage.foldername(name))[1] = 'qr-checklist'
);


-- ── 2. Bitacora ─────────────────────────────────────────────────────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG14D_STORAGE_QR',
            'Storage policy para evidencias QR (paso 14D).',
            current_user, NOW(), NOW(), 'ok',
            'Anon puede INSERT en documentos/qr-checklist/*. SELECT/UPDATE/DELETE bloqueados a nivel policy.'
        );
    END IF;
END $$;


-- ── 3. Verificacion final (1 fila) ──────────────────────────────────
WITH
bucket_existe AS (
    SELECT EXISTS (SELECT 1 FROM storage.buckets WHERE id='documentos') AS v
),
bucket_public AS (
    -- TRUE si el bucket es publico (CDN abierto bypaseando policies).
    SELECT COALESCE(
        (SELECT public FROM storage.buckets WHERE id='documentos'),
        false
    ) AS v
),
policy_insert AS (
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='storage' AND tablename='objects'
           AND policyname='storage_qr_checklist_anon_insert'
    ) AS v
),
anon_select AS (
    -- ¿Hay alguna policy SELECT a anon que cubra path qr-checklist/?
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='storage' AND tablename='objects'
           AND 'anon' = ANY(roles)
           AND cmd = 'SELECT'
           AND (
               COALESCE(qual, '')       ILIKE '%qr-checklist%'
            OR COALESCE(with_check, '') ILIKE '%qr-checklist%'
           )
    ) AS v
),
anon_update AS (
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='storage' AND tablename='objects'
           AND 'anon' = ANY(roles)
           AND cmd = 'UPDATE'
           AND (
               COALESCE(qual, '')       ILIKE '%qr-checklist%'
            OR COALESCE(with_check, '') ILIKE '%qr-checklist%'
           )
    ) AS v
),
anon_delete AS (
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
         WHERE schemaname='storage' AND tablename='objects'
           AND 'anon' = ANY(roles)
           AND cmd = 'DELETE'
           AND (
               COALESCE(qual, '')       ILIKE '%qr-checklist%'
            OR COALESCE(with_check, '') ILIKE '%qr-checklist%'
           )
    ) AS v
)
SELECT
    CASE
        WHEN NOT (SELECT v FROM bucket_existe)
            THEN 'STOP_BUCKET_NO_EXISTE'
        WHEN NOT (SELECT v FROM policy_insert)
            THEN 'STOP_POLICY_INSERT_NO_CREADA'
        WHEN (SELECT v FROM anon_select)
          OR (SELECT v FROM anon_update)
          OR (SELECT v FROM anon_delete)
            THEN 'STOP_ANON_TIENE_PERMISOS_DEMAS'
        WHEN (SELECT v FROM bucket_public)
            THEN 'WARNING_BUCKET_DOCUMENTOS_ES_PUBLICO'
        ELSE 'OK_STORAGE_QR_EVIDENCIAS'
    END                                         AS resultado,
    (SELECT v FROM bucket_existe)               AS bucket_documentos_existe,
    (SELECT v FROM policy_insert)               AS policy_insert_anon_existe,
    (SELECT v FROM anon_select)                 AS anon_select_publico_qr_checklist,
    (SELECT v FROM anon_update)                 AS anon_update_qr_checklist,
    (SELECT v FROM anon_delete)                 AS anon_delete_qr_checklist,
    (SELECT v FROM bucket_public)               AS bucket_documentos_es_publico_cdn,
    NOW()                                       AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_STORAGE_QR_EVIDENCIAS
--     Bucket existe + policy INSERT anon creada + anon SIN permisos extra +
--     bucket NO publico. Las evidencias QR se suben y solo mantencion las lee.
--
-- - resultado = WARNING_BUCKET_DOCUMENTOS_ES_PUBLICO
--     Todo OK a nivel policies, PERO el bucket es publico (CDN abierto).
--     Cualquiera con la URL directa puede leer la foto. Aceptable si la
--     URL no se difunde, pero NO cumple "No permitir SELECT publico" en
--     sentido estricto. Recomendacion: migrar evidencias QR a un bucket
--     privado dedicado y servir al mantenedor con signed URLs.
--
-- - resultado = STOP_BUCKET_NO_EXISTE
--     El bucket 'documentos' no existe. Crear desde Supabase Dashboard
--     antes de re-ejecutar (o el INSERT al inicio deberia haberlo creado).
--
-- - resultado = STOP_POLICY_INSERT_NO_CREADA
--     La policy no quedo creada. Revisar permisos del usuario que ejecuta
--     (debe tener privilegios sobre schema 'storage').
--
-- - resultado = STOP_ANON_TIENE_PERMISOS_DEMAS
--     Existen policies que dan SELECT/UPDATE/DELETE a anon en path
--     qr-checklist. Listar y revocar:
--       SELECT policyname, cmd FROM pg_policies
--        WHERE schemaname='storage' AND tablename='objects'
--          AND 'anon' = ANY(roles)
--          AND (qual ILIKE '%qr-checklist%' OR with_check ILIKE '%qr-checklist%');
-- ============================================================================


-- ROLLBACK:
-- DROP POLICY "storage_qr_checklist_anon_insert" ON storage.objects;
