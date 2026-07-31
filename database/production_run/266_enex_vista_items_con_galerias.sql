-- ============================================================================
-- SICOM-ICEO | 266 — La vista de ítems ejecutados expone las galerías
-- ----------------------------------------------------------------------------
-- MIG265 agregó fotos_antes / fotos_despues a enex_ejecucion_items, pero la
-- vista v_enex_ejecucion_items lista sus columnas una a una: sin recrearla, ni
-- la app de terreno (al reabrir un trabajo) ni el informe PDF del mandante ven
-- las fotos nuevas.
--
-- ADITIVA. Solo agrega columnas al final de la vista.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_enex_ejecucion_items AS
 SELECT ei.id,
    ei.ejecucion_id,
    ei.pauta_item_id,
    ei.resultado,
    ei.valor_medicion,
    ei.dentro_tolerancia,
    ei.foto_url,
    ei.observacion,
    ei.created_at,
    ei.foto_antes_url,
    ei.foto_despues_url,
    it.bloque,
    it.bloque_orden,
    it.orden,
    it.codigo AS item_codigo,
    it.descripcion,
    it.periodicidad,
    it.tipo_campo,
    it.unidad,
    it.valor_referencia,
    it.tolerancia_min,
    it.tolerancia_max,
    it.requiere_foto,
    it.critico,
    -- [MIG266] Las galerías completas (CREATE OR REPLACE exige agregarlas al final)
    ei.fotos_antes,
    ei.fotos_despues
   FROM enex_ejecucion_items ei
     JOIN enex_pauta_items it ON it.id = ei.pauta_item_id;

GRANT SELECT ON public.v_enex_ejecucion_items TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_cols INT;
BEGIN
    SELECT count(*) INTO v_cols FROM information_schema.columns
     WHERE table_name='v_enex_ejecucion_items' AND column_name IN ('fotos_antes','fotos_despues');
    IF v_cols <> 2 THEN
        RAISE EXCEPTION 'FALLO — la vista sigue sin exponer las galerías';
    END IF;
    RAISE NOTICE 'MIG266 OK — v_enex_ejecucion_items expone fotos_antes y fotos_despues';
END $$;

NOTIFY pgrst, 'reload schema';
