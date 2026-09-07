-- ============================================================================
-- MIG537 · La NC de una tarea a medida nace con su nombre
-- ============================================================================
-- Manuel preguntó: «si el mecánico dice NO OK en una tarea añadida, ¿sale
-- como NC?». SÍ (MIG282: la NC nace al marcar NO OK, sin esperar el cierre)
-- — pero el trigger sacaba la descripción de la PLANTILLA, y las tareas a
-- medida no tienen plantilla: la NC nacía sin nombre. Ahora: descripción de
-- la plantilla → o la de la tarea a medida → o el genérico.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_trg_nc_al_marcar_no_ok()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_inst   RECORD;
    v_desc   TEXT;
    v_nc     UUID;
BEGIN
    SELECT i.id, i.ot_id, i.activo_id, i.momento_uso
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.id = NEW.instance_id;

    IF v_inst.ot_id IS NULL OR v_inst.momento_uso <> 'recepcion_devolucion' THEN
        RETURN NEW;
    END IF;

    -- ── Se marcó NO OK: nace la no conformidad ──────────────────────────────
    IF NEW.resultado = 'no_ok' AND OLD.resultado IS DISTINCT FROM 'no_ok' THEN
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = NEW.id) THEN
            RETURN NEW;
        END IF;
        -- [MIG537] Las tareas a medida no tienen plantilla: su nombre vive en
        -- descripcion_custom. Antes la NC nacía sin nombre.
        v_desc := COALESCE(
            (SELECT ti.descripcion FROM checklist_template_v2_item ti WHERE ti.id = NEW.template_item_id),
            NULLIF(TRIM(NEW.descripcion_custom), ''),
            'Ítem de inspección');

        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen,
            checklist_item_ref, estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_inst.activo_id, v_inst.ot_id, 'otra',
            v_desc || COALESCE(' — ' || NULLIF(TRIM(NEW.observacion), ''), ''),
            CURRENT_DATE, 'media', 'inspeccion_ot',
            NEW.id, 'registrada', auth.uid(), auth.uid()
        );
        RETURN NEW;
    END IF;

    -- ── Se corrigió: la NC se retira, salvo que ya tenga vida propia ────────
    IF OLD.resultado = 'no_ok' AND NEW.resultado IS DISTINCT FROM 'no_ok' THEN
        SELECT id INTO v_nc FROM no_conformidades WHERE checklist_item_ref = NEW.id;
        IF v_nc IS NULL THEN RETURN NEW; END IF;

        IF EXISTS (SELECT 1 FROM no_conformidades n
                    WHERE n.id = v_nc
                      AND (n.estado_planificacion IS DISTINCT FROM 'registrada'
                           OR n.plan_ot_id IS NOT NULL
                           OR n.resuelto
                           OR EXISTS (SELECT 1 FROM nc_materiales m WHERE m.no_conformidad_id = n.id))) THEN
            RETURN NEW;
        END IF;

        DELETE FROM no_conformidades WHERE id = v_nc;
    END IF;

    RETURN NEW;
END $$;

-- ── Verificación con rollback: la «test 4» de PRUEBA-01 marcada NO OK ───────
DO $mig$
DECLARE v_item UUID; v_desc TEXT; v_admin UUID;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    SELECT ii.id INTO v_item
      FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
     WHERE i.ot_id = 'd7a64530-c77d-48e3-88fc-d1868589f987'
       AND ii.template_item_id IS NULL AND ii.descripcion_custom = 'test 4'
     LIMIT 1;
    IF v_item IS NULL THEN
        RAISE NOTICE 'sin «test 4» para probar: se verifica solo el parche';
    ELSE
        BEGIN
            UPDATE checklist_v2_instance_item SET resultado = 'no_ok' WHERE id = v_item;
            SELECT descripcion INTO v_desc FROM no_conformidades WHERE checklist_item_ref = v_item;
            IF v_desc IS NULL OR v_desc NOT LIKE 'test 4%' THEN
                RAISE EXCEPTION 'FALLO_REAL: la NC de la tarea a medida quedó como [%]', v_desc;
            END IF;
            RAISE EXCEPTION 'ROLLBACK_MARKER NC=[%]', v_desc;
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
                RAISE NOTICE 'prueba OK (revertida): %', SQLERRM;
            ELSE
                RAISE EXCEPTION '%', SQLERRM;
            END IF;
        END;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_trg_nc_al_marcar_no_ok'
                    AND prosrc LIKE '%descripcion_custom%') THEN
        RAISE EXCEPTION 'FALLO: el parche no quedó escrito';
    END IF;
    RAISE NOTICE 'MIG537 OK · la NC de una tarea a medida nace con su nombre';
END
$mig$;

COMMIT;
