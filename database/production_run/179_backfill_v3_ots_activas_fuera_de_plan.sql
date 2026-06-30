-- ============================================================================
-- SICOM-ICEO | 179 — Backfill checklist V03 para OT activas sin checklist
--                    (incluye OT fuera del plan taller)
-- ============================================================================
-- Sintoma (2026-06-30, ej. OT-202606-00045, creada):
--   OT activas creadas ANTES del fix del trigger (MIG177) quedaron sin checklist
--   por el mismo bug: el equipo ya tenia una instancia en_progreso tomada por
--   otra OT. El backfill de MIG177 solo cubrio las OT del PLAN taller; las OT
--   fuera del plan (no en taller_plan_semanal_ots) no se corrigieron.
--
-- Este backfill cubre TODA OT en estado activo/editable sin checklist V03,
-- este o no en el plan. NO toca OT inmutables (ejecutada_*/no_ejecutada/
-- cancelada/cerrada): ya pasaron su cierre y un checklist vacio no aporta.
--
-- El trigger fn_auto_checklist_ot ya quedo corregido en MIG177, asi que las OT
-- nuevas no requieren este backfill.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
DECLARE
    r       RECORD;
    v_tpl   UUID;
    v_inst  UUID;
    v_n     INT := 0;
    v_err   INT := 0;
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1;
    IF v_tpl IS NULL THEN RAISE NOTICE 'Sin template V03 activo; backfill omitido'; RETURN; END IF;

    FOR r IN
        SELECT o.id AS ot_id, o.activo_id, o.contrato_id, o.folio
          FROM ordenes_trabajo o
         WHERE o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                                'no_ejecutada','cancelada','cerrada')
           AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id = o.id)
    LOOP
        BEGIN
            -- preferir una instancia LIBRE del equipo; si no, crear una nueva
            SELECT id INTO v_inst FROM checklist_v2_instance
             WHERE activo_id = r.activo_id
               AND momento_uso='recepcion_devolucion'
               AND estado='en_progreso'
               AND ot_id IS NULL
             ORDER BY fecha_inicio DESC LIMIT 1;

            IF v_inst IS NULL THEN
                v_inst := fn_inicializar_checklist_v2(v_tpl, r.activo_id, r.contrato_id);
            END IF;

            UPDATE checklist_v2_instance SET ot_id = r.ot_id WHERE id = v_inst;
            v_n := v_n + 1;
            RAISE NOTICE 'Checklist V03 creado para % (%)', r.folio, r.ot_id;
        EXCEPTION WHEN OTHERS THEN
            v_err := v_err + 1;  -- p.ej. activo sin tipo_equipamiento
            RAISE NOTICE 'Error en % : %', r.folio, SQLERRM;
        END;
    END LOOP;
    RAISE NOTICE 'Backfill V03 MIG179: % OT enlazadas, % con error', v_n, v_err;
END $$;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'ots_activas_sin_v3', (SELECT COUNT(*) FROM ordenes_trabajo o
        WHERE o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                               'no_ejecutada','cancelada','cerrada')
          AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id=o.id)),
    'ot_45_items', (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
        JOIN ordenes_trabajo o ON o.id=v.ot_id WHERE o.folio='OT-202606-00045')
) AS resultado;

NOTIFY pgrst, 'reload schema';
