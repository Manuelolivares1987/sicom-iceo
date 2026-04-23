-- ============================================================================
-- SICOM-ICEO | Migracion 46 — Storage bucket + seccion + trigger checklist
-- ============================================================================
-- (1) Bucket "evidencias-verificacion" con policies para imagenes.
-- (2) Columna checklist_ot.seccion (agrupacion UI del wizard).
-- (3) Trigger AFTER INSERT en ordenes_trabajo: si la OT no tiene items
--     pero existe una plantilla activa para su tipo, copia los items
--     (incluyendo seccion). Cubre OTs creadas directo (sin rpc_crear_ot),
--     como la de verificacion_disponibilidad (mig 45) y la OT auto-creada
--     al cambiar estado de flota (mig 39).
-- ============================================================================

-- ============================================================================
-- 1. STORAGE BUCKET
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'evidencias-verificacion',
    'evidencias-verificacion',
    true,
    10485760,
    ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS pol_verif_select ON storage.objects;
CREATE POLICY pol_verif_select ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'evidencias-verificacion');

DROP POLICY IF EXISTS pol_verif_insert ON storage.objects;
CREATE POLICY pol_verif_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'evidencias-verificacion');

DROP POLICY IF EXISTS pol_verif_update_own ON storage.objects;
CREATE POLICY pol_verif_update_own ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'evidencias-verificacion' AND owner = auth.uid());

DROP POLICY IF EXISTS pol_verif_delete_own ON storage.objects;
CREATE POLICY pol_verif_delete_own ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'evidencias-verificacion' AND owner = auth.uid());


-- ============================================================================
-- 2. Columna seccion en checklist_ot (agrupacion de items en UI)
-- ============================================================================

ALTER TABLE checklist_ot
    ADD COLUMN IF NOT EXISTS seccion VARCHAR(100);


-- ============================================================================
-- 3. Trigger: copiar checklist desde plantilla al crear OT
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_copiar_checklist_template_para_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_template_items JSONB;
BEGIN
    -- Si ya tiene items (flujo rpc_crear_ot), no duplicar
    IF EXISTS (SELECT 1 FROM checklist_ot WHERE ot_id = NEW.id) THEN
        RETURN NEW;
    END IF;

    -- Buscar plantilla activa para el tipo de OT
    SELECT items INTO v_template_items
      FROM checklist_templates
     WHERE tipo_ot = NEW.tipo
       AND activo = true
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_template_items IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO checklist_ot (
        id, ot_id, orden, descripcion, obligatorio, requiere_foto, seccion
    )
    SELECT
        gen_random_uuid(),
        NEW.id,
        (item->>'orden')::INTEGER,
        item->>'descripcion',
        COALESCE((item->>'obligatorio')::BOOLEAN, true),
        COALESCE((item->>'requiere_foto')::BOOLEAN, false),
        item->>'seccion'
    FROM jsonb_array_elements(v_template_items) AS item;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_copiar_checklist_para_ot ON ordenes_trabajo;

CREATE TRIGGER trg_copiar_checklist_para_ot
    AFTER INSERT ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION fn_copiar_checklist_template_para_ot();


-- ============================================================================
-- 4. Backfill seccion en items existentes desde plantilla (best-effort)
-- ============================================================================
-- Para items ya creados antes de este migration. Matchea por
-- (tipo_ot, orden, descripcion).

UPDATE checklist_ot co
   SET seccion = item->>'seccion'
  FROM ordenes_trabajo ot
  JOIN checklist_templates ct ON ct.tipo_ot = ot.tipo AND ct.activo = true
  CROSS JOIN LATERAL jsonb_array_elements(ct.items) AS item
 WHERE co.ot_id = ot.id
   AND co.seccion IS NULL
   AND co.orden = (item->>'orden')::INTEGER
   AND co.descripcion = item->>'descripcion';


-- ============================================================================
-- 5. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_bucket_ok  BOOLEAN;
    v_col_ok     BOOLEAN;
    v_trigger_ok BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'evidencias-verificacion')
      INTO v_bucket_ok;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'checklist_ot' AND column_name = 'seccion'
    ) INTO v_col_ok;

    SELECT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgname = 'trg_copiar_checklist_para_ot'
           AND tgrelid = 'ordenes_trabajo'::regclass
    ) INTO v_trigger_ok;

    RAISE NOTICE '== Migracion 46 ==';
    RAISE NOTICE 'Bucket evidencias-verificacion ....... %', v_bucket_ok;
    RAISE NOTICE 'Columna checklist_ot.seccion ......... %', v_col_ok;
    RAISE NOTICE 'Trigger copiar_checklist conectado ... %', v_trigger_ok;

    IF NOT (v_bucket_ok AND v_col_ok AND v_trigger_ok) THEN
        RAISE EXCEPTION 'Migracion 46 incompleta.';
    END IF;
END $$;
