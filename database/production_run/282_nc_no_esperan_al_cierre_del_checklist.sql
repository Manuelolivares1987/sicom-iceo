-- ============================================================================
-- SICOM-ICEO | 282 — El hallazgo llega al jefe cuando se marca, no al cerrar
-- ============================================================================
-- Reporte de Ricardo (jefe de taller): no veía las no conformidades de RSCY-86
-- "aunque los mecánicos están pausando el checklist como corresponde".
--
-- Al revisarlo: los mecánicos habían hecho el trabajo completo — 160 de 160
-- ítems marcados, 21 NO conformes — pero el checklist quedó EN PROGRESO. Las
-- NC nacían solo con el trigger de cierre (`estado='cerrado'`), así que 21
-- hallazgos reales quedaron invisibles diez días, y con ellos la planificación
-- y el recobro.
--
-- El diseño pedía cerrar para materializar el hallazgo. Pero una inspección de
-- 160 ítems se hace en varias pasadas: se pausa, se sigue mañana, se cierra
-- cuando se puede. Esperar el cierre significa que el jefe se entera tarde de
-- algo que el mecánico ya vio.
--
-- Ahora la NC se crea EN CUANTO se marca NO OK. Y si el mecánico se corrige
-- (cambia a OK o N/A), la NC se retira sola — mientras nadie la haya
-- planificado ni pedido repuestos contra ella: a partir de ahí es historia y
-- se conserva.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='checklist_v2_instance_item') THEN
        RAISE EXCEPTION 'STOP — falta el checklist V2'; END IF;
END $$;


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

    -- Solo las inspecciones de recepción/devolución alimentan no conformidades:
    -- es el mismo criterio que ya usaba el cierre.
    IF v_inst.ot_id IS NULL OR v_inst.momento_uso <> 'recepcion_devolucion' THEN
        RETURN NEW;
    END IF;

    -- ── Se marcó NO OK: nace la no conformidad ──────────────────────────────
    IF NEW.resultado = 'no_ok' AND OLD.resultado IS DISTINCT FROM 'no_ok' THEN
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = NEW.id) THEN
            RETURN NEW;                       -- ya existía: idempotente
        END IF;
        SELECT COALESCE(ti.descripcion, 'Ítem de inspección') INTO v_desc
          FROM checklist_template_v2_item ti WHERE ti.id = NEW.template_item_id;

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

        -- Planificada, con OT, con insumos pedidos o ya resuelta: es historia.
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

DROP TRIGGER IF EXISTS trg_nc_al_marcar_no_ok ON checklist_v2_instance_item;
CREATE TRIGGER trg_nc_al_marcar_no_ok
    AFTER UPDATE OF resultado ON checklist_v2_instance_item
    FOR EACH ROW EXECUTE FUNCTION fn_trg_nc_al_marcar_no_ok();

COMMENT ON FUNCTION fn_trg_nc_al_marcar_no_ok() IS
    'La no conformidad aparece al marcar NO OK, sin esperar el cierre del checklist. '
    'Se retira si el mecánico se corrige, salvo que ya esté planificada o con insumos. MIG282.';


-- ── Recuperar lo que quedó atrás ────────────────────────────────────────────
-- Checklists de inspección todavía abiertos, con hallazgos NO OK que nunca se
-- materializaron porque nadie cerró. Es exactamente el caso de RSCY-86.
DO $$
DECLARE r RECORD; v_total INT := 0; v_res JSONB;
BEGIN
    FOR r IN
        SELECT DISTINCT i.ot_id, i.activo_id
          FROM checklist_v2_instance i
          JOIN checklist_v2_instance_item ii ON ii.instance_id = i.id
         WHERE i.momento_uso = 'recepcion_devolucion'
           AND i.ot_id IS NOT NULL
           AND i.estado <> 'cerrado'
           AND ii.resultado = 'no_ok'
           AND NOT EXISTS (SELECT 1 FROM no_conformidades n WHERE n.checklist_item_ref = ii.id)
    LOOP
        v_res := fn_generar_nc_desde_checklist_ot(r.ot_id);
        v_total := v_total + COALESCE((v_res->>'creadas')::int, 0);
    END LOOP;
    RAISE NOTICE 'MIG282: % no conformidades rescatadas de checklists abiertos', v_total;
END $$;


SELECT 'MIG282 OK' AS resultado,
       (SELECT count(*) FROM no_conformidades WHERE origen = 'inspeccion_ot') AS nc_de_inspeccion,
       (SELECT count(*) FROM checklist_v2_instance
         WHERE momento_uso='recepcion_devolucion' AND estado <> 'cerrado') AS checklists_abiertos;
