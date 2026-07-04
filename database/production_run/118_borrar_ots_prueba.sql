-- ============================================================================
-- SICOM-ICEO | 118 — Borrar OTs de prueba  [ONE-SHOT CERRADO — NO RE-EJECUTAR]
-- ============================================================================
-- ⛔ GUARD MIG-FASE-0 (auditoría 2026-07-03): este script contiene
--    `DELETE FROM ordenes_trabajo;` SIN WHERE. Fue un one-shot para borrar OTs
--    de prueba (jun-2026). Hoy producción tiene OTs REALES y una re-ejecución
--    las borraría en cascada sin backup. El bloque de abajo aborta SIEMPRE.
--    Se conserva el archivo solo por trazabilidad histórica.
--    Para reutilizar la lógica en un ambiente NUEVO y VACÍO, copiar el cuerpo
--    a un script nuevo revisado; no reactivar este.
-- destructivo-ok: one-shot histórico neutralizado con guard (auditoría Fase 0)
-- ============================================================================
DO $$
BEGIN
    RAISE EXCEPTION 'MIG118 es un one-shot YA CERRADO: borra TODAS las OTs. '
        'Ejecución bloqueada por guard de auditoría Fase 0 (2026-07-03).';
END $$;

-- ============================================================================
-- Las 35 OTs cargadas (mar-abr 2026) son de PRUEBA. Se eliminan.
-- Cascadean (ON DELETE CASCADE): checklist_ot, historial_estado_ot, evidencias_ot,
-- ot_materiales_planeados, taller_plan_semanal_ots, taller_ot_ejecuciones(_eventos).
-- Referencias NO-ACTION se desvinculan (ot_id -> NULL) para conservar el registro:
--   estado_diario_flota (4), verificaciones_disponibilidad (8), movimientos_inventario (5).
-- ============================================================================

BEGIN;

UPDATE estado_diario_flota         SET ot_relacionada_id = NULL WHERE ot_relacionada_id IS NOT NULL;
UPDATE verificaciones_disponibilidad SET ot_id = NULL WHERE ot_id IS NOT NULL;
UPDATE movimientos_inventario      SET ot_id = NULL WHERE ot_id IS NOT NULL;

DO $$
DECLARE v_ots INT; v_chk INT;
BEGIN
    SELECT count(*) INTO v_ots FROM ordenes_trabajo;
    SELECT count(*) INTO v_chk FROM checklist_ot;
    RAISE NOTICE 'Antes: % OTs, % items checklist_ot', v_ots, v_chk;
END $$;

DELETE FROM ordenes_trabajo;

DO $$
DECLARE v_ots INT; v_chk INT;
BEGIN
    SELECT count(*) INTO v_ots FROM ordenes_trabajo;
    SELECT count(*) INTO v_chk FROM checklist_ot;
    RAISE NOTICE 'Después: % OTs, % items checklist_ot (deben ser 0)', v_ots, v_chk;
    IF v_ots <> 0 THEN RAISE EXCEPTION 'Quedaron OTs sin borrar'; END IF;
END $$;

COMMIT;
