-- ============================================================================
-- SICOM-ICEO | 121 — Borrar OTs de prueba "limpias" (conservar las con bodega)
-- ============================================================================
-- Se borran las 32 OTs de prueba SIN salidas de bodega. Se CONSERVAN las 3 que
-- tienen movimientos de inventario (salidas) para no tocar el kardex.
-- Cascadean: checklist_ot, historial_estado_ot, evidencias_ot, ejecuciones, etc.
-- Refs NO-ACTION que apunten a las borradas se desvinculan (ot_id -> NULL):
--   estado_diario_flota, verificaciones_disponibilidad.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _keep ON COMMIT DROP AS
  SELECT DISTINCT ot_id AS id FROM movimientos_inventario WHERE ot_id IS NOT NULL;

UPDATE estado_diario_flota         SET ot_relacionada_id = NULL
 WHERE ot_relacionada_id IS NOT NULL AND ot_relacionada_id NOT IN (SELECT id FROM _keep);
UPDATE verificaciones_disponibilidad SET ot_id = NULL
 WHERE ot_id IS NOT NULL AND ot_id NOT IN (SELECT id FROM _keep);

DO $$ DECLARE v INT; BEGIN SELECT count(*) INTO v FROM ordenes_trabajo; RAISE NOTICE 'Antes: % OTs', v; END $$;

DELETE FROM ordenes_trabajo WHERE id NOT IN (SELECT id FROM _keep);

DO $$
DECLARE v_ots INT; v_keep INT;
BEGIN
    SELECT count(*) INTO v_ots FROM ordenes_trabajo;
    SELECT count(*) INTO v_keep FROM _keep;
    RAISE NOTICE 'Después: % OTs (conservadas con bodega: %)', v_ots, v_keep;
    IF v_ots <> v_keep THEN RAISE EXCEPTION 'Conteo inesperado'; END IF;
END $$;

COMMIT;
