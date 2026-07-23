-- ============================================================================
-- SICOM-ICEO | 247 — Fotos MÚLTIPLES por ítem de checklist (ejecución taller)
-- ----------------------------------------------------------------------------
-- Sugerencias de operadores: "solo se puede una foto por ítem; necesito varias,
-- elegir de la galería y subir video corto".
--
-- Se agrega `foto_urls TEXT[]` a checklist_v2_instance_item (la evidencia pasa a
-- ser una lista). Se conserva `foto_url` (= primera evidencia) por
-- compatibilidad con la generación de No Conformidades (MIG159/144, que copian
-- foto_url) y con datos existentes.
--
-- La vista v_taller_ot_checklist_v3 expone foto_urls (se AÑADE al final para
-- poder usar CREATE OR REPLACE VIEW sin DROP). IDEMPOTENTE.
-- ============================================================================

ALTER TABLE checklist_v2_instance_item
    ADD COLUMN IF NOT EXISTS foto_urls TEXT[];

COMMENT ON COLUMN checklist_v2_instance_item.foto_urls IS
    'Evidencias del ítem (fotos/videos). foto_url = primera, por compat con NC. MIG247.';

-- Backfill: la foto única existente pasa a ser el primer elemento del arreglo.
UPDATE checklist_v2_instance_item
   SET foto_urls = ARRAY[foto_url]
 WHERE foto_url IS NOT NULL
   AND (foto_urls IS NULL OR array_length(foto_urls, 1) IS NULL);

-- Vista efectiva por OT + foto_urls (añadida al final, tras `mediciones`, para
-- poder usar CREATE OR REPLACE VIEW). Reproduce la definición viva exacta.
CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS
 WITH inst AS (
         SELECT DISTINCT ON (checklist_v2_instance.ot_id) checklist_v2_instance.id,
            checklist_v2_instance.ot_id,
            checklist_v2_instance.activo_id,
            checklist_v2_instance.estado
           FROM checklist_v2_instance
          WHERE checklist_v2_instance.ot_id IS NOT NULL
          ORDER BY checklist_v2_instance.ot_id, checklist_v2_instance.fecha_inicio DESC
        )
 SELECT ii.id AS instance_item_id,
    inst.id AS instance_id,
    inst.ot_id,
    inst.estado AS instance_estado,
    COALESCE(ti.bloque::text, 'Tareas adicionales'::text) AS bloque,
    COALESCE(ti.bloque_orden, 999) AS bloque_orden,
    COALESCE(ti.orden, 9999) AS orden,
    ti.codigo,
    COALESCE(ii.descripcion_custom, ti.descripcion::character varying) AS descripcion,
    COALESCE(ii.tiempo_min_override, ti.tiempo_min::numeric) AS tiempo_min,
    ii.tiempo_min_override IS NOT NULL AS tiempo_editado,
    COALESCE(ti.requiere_foto, false) AS requiere_foto,
    COALESCE(ti.obligatorio, false) AS obligatorio,
    COALESCE(ti.critico, false) AS critico,
    ti.categoria_calidad,
    ii.resultado,
    ii.observacion,
    ii.foto_url,
    ii.excluido,
    ii.template_item_id IS NULL AS es_custom,
    ii.mediciones,
    ii.foto_urls
   FROM inst
     JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id;

GRANT SELECT ON v_taller_ot_checklist_v3 TO authenticated;

-- Validación
DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM information_schema.columns
     WHERE table_name='checklist_v2_instance_item' AND column_name='foto_urls';
    IF n < 1 THEN RAISE EXCEPTION 'FALLO: falta columna foto_urls'; END IF;
    PERFORM 1 FROM v_taller_ot_checklist_v3 LIMIT 1;
    RAISE NOTICE 'MIG247 OK: foto_urls en tabla y vista';
END $$;

NOTIFY pgrst, 'reload schema';
