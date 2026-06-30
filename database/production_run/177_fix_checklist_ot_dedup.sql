-- ============================================================================
-- SICOM-ICEO | 177 — Fix: OT sin checklist V03 cuando el equipo ya tiene una
--                    instancia en_progreso tomada por otra OT
-- ============================================================================
-- Sintoma (detectado 2026-06-30 en Plan Taller, ej. OT-202606-00043):
--   14 de 30 OT del plan no tenian checklist. Todas sobre aljibes con VARIAS
--   OT (AI-25-04, CC-05-11, CC-44-03, ...).
--
-- Causa raiz (trigger fn_auto_checklist_ot, MIG157):
--   El "dedup por equipo" busca una instancia recepcion_devolucion en_progreso
--   del activo y la engancha. Pero el SELECT NO filtraba por ot_id IS NULL:
--   encontraba una instancia YA enganchada a otra OT, intentaba el UPDATE con
--   WHERE ot_id IS NULL (0 filas), y hacia RETURN NEW SIN crear el checklist.
--   -> la OT nueva quedaba sin instancia.
--
-- Fix:
--   1. El SELECT de reuso solo considera instancias LIBRES (ot_id IS NULL).
--      Si no hay libre, cae a crear una instancia V03 nueva para la OT.
--   2. Backfill: crear la instancia V03 para las OT del plan sin checklist.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Trigger: reusar SOLO instancias libres, si no, crear nueva ────────────
CREATE OR REPLACE FUNCTION fn_auto_checklist_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
BEGIN
    BEGIN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true
         ORDER BY version DESC LIMIT 1;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        -- ya tiene checklist propio?
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- reusar SOLO una instancia LIBRE (ot_id IS NULL) del mismo equipo
        -- (p.ej. recepcion iniciada en terreno antes de existir la OT)
        SELECT id INTO v_inst FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id
           AND momento_uso = 'recepcion_devolucion'
           AND estado = 'en_progreso'
           AND ot_id IS NULL
         ORDER BY fecha_inicio DESC LIMIT 1;
        IF v_inst IS NOT NULL THEN
            UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;
            RETURN NEW;
        END IF;

        -- si no hay libre, crear una instancia V03 nueva para esta OT
        SELECT contrato_id, horas_uso_actual, kilometraje_actual
          INTO v_contrato, v_horas, v_km
          FROM activos WHERE id = NEW.activo_id;

        SELECT id INTO v_entrega FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id AND momento_uso='entrega_arriendo' AND estado='cerrado'
         ORDER BY fecha_cierre DESC LIMIT 1;

        v_inst := fn_inicializar_checklist_v2(
            v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
            NULL, v_horas, v_km, NULL, v_entrega
        );
        UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN NEW;
END $$;

COMMENT ON FUNCTION fn_auto_checklist_ot() IS
    'Al crear cualquier OT activa el checklist V03; reusa solo instancias libres del equipo, si no crea una nueva. MIG177 (corrige MIG157).';


-- ── 2. Backfill: instancia V03 para OT del plan sin checklist ────────────────
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
        SELECT DISTINCT t.ot_id, o.activo_id, o.contrato_id
          FROM taller_plan_semanal_ots t
          JOIN ordenes_trabajo o ON o.id = t.ot_id
         WHERE NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id = t.ot_id)
    LOOP
        BEGIN
            -- preferir una instancia LIBRE del equipo; si no, crear nueva
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
        EXCEPTION WHEN OTHERS THEN
            v_err := v_err + 1;  -- p.ej. activo sin tipo_equipamiento
        END;
    END LOOP;
    RAISE NOTICE 'Backfill V03 MIG177: % OT enlazadas, % con error', v_n, v_err;
END $$;


-- ── 3. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'ots_plan_total',   (SELECT COUNT(DISTINCT ot_id) FROM taller_plan_semanal_ots),
    'ots_plan_con_v03', (SELECT COUNT(DISTINCT t.ot_id) FROM taller_plan_semanal_ots t
        JOIN checklist_v2_instance ci ON ci.ot_id = t.ot_id),
    'ots_plan_sin_v03', (SELECT COUNT(DISTINCT t.ot_id) FROM taller_plan_semanal_ots t
        WHERE NOT EXISTS (SELECT 1 FROM checklist_v2_instance ci WHERE ci.ot_id = t.ot_id)),
    'ot_43_items', (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
        JOIN ordenes_trabajo o ON o.id = v.ot_id WHERE o.folio='OT-202606-00043')
) AS resultado;

NOTIFY pgrst, 'reload schema';
