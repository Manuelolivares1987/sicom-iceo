-- ============================================================================
-- SICOM-ICEO | 158 — Backfill checklist V03 para TODAS las OT abiertas
-- ============================================================================
-- MIG157 hizo backfill solo de las OT que ya estaban en el plan. Las OT del
-- backlog (creadas antes de MIG157, aun no agregadas al plan) no tienen
-- instancia V03 — y el trigger solo la crea al CREAR la OT, no al planificarla.
-- Resultado: al planificar una OT vieja, aparecia sin checklist.
--
-- Este backfill crea la instancia V03 para toda OT abierta sin checklist
-- (creada/asignada/pausada/en_ejecucion). El maestro CL-INSPECCION-V03 cubre
-- todos los tipos de equipo presentes (incl. aljibe_agua/aljibe_combustible),
-- asi que no se generan checklists vacios.
--
-- IDEMPOTENTE (solo crea las que faltan).
-- ============================================================================

DO $$
DECLARE
    r       RECORD;
    v_tpl   UUID;
    v_inst  UUID;
    v_ok    INT := 0;
    v_skip  INT := 0;
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1;
    IF v_tpl IS NULL THEN RAISE EXCEPTION 'Sin template V03 activo'; END IF;

    FOR r IN
        SELECT o.id AS ot_id, o.activo_id, o.contrato_id
          FROM ordenes_trabajo o
         WHERE o.estado IN ('creada','asignada','pausada','en_ejecucion')
           AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id = o.id)
    LOOP
        BEGIN
            v_inst := fn_inicializar_checklist_v2(v_tpl, r.activo_id, r.contrato_id);
            UPDATE checklist_v2_instance SET ot_id = r.ot_id WHERE id = v_inst;
            v_ok := v_ok + 1;
        EXCEPTION WHEN OTHERS THEN
            v_skip := v_skip + 1;  -- p.ej. activo sin tipo_equipamiento
        END;
    END LOOP;
    RAISE NOTICE 'Backfill V03 OT abiertas: % creadas, % omitidas', v_ok, v_skip;
END $$;

-- Validacion: cuantas OT abiertas siguen sin V03 (deberia ser 0 o solo las sin equipo)
SELECT jsonb_build_object(
    'abiertas_total',  (SELECT COUNT(*) FROM ordenes_trabajo WHERE estado IN ('creada','asignada','pausada','en_ejecucion')),
    'abiertas_con_v03',(SELECT COUNT(*) FROM ordenes_trabajo o WHERE o.estado IN ('creada','asignada','pausada','en_ejecucion')
         AND EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id=o.id)),
    'abiertas_sin_v03',(SELECT COUNT(*) FROM ordenes_trabajo o WHERE o.estado IN ('creada','asignada','pausada','en_ejecucion')
         AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id=o.id))
) AS resultado;
