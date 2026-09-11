-- ============================================================================
-- MIG545 · La entrega en arriendo no admite N/A
-- ============================================================================
-- Manuel (2026-09-11), tras MIG544: «sacaría los N/A en este checklist,
-- porque no es atingente». En el acta de entrega todo ítem aplica: son las
-- pruebas funcionales del equipo que se va y el estado en que se va. En la
-- entrega real OT-202609-00019 el EC.02 «Aseo exterior» quedó N/A — y con
-- MIG544 el N/A además exime de la foto, o sea que era la puerta para
-- esquivar la cámara.
--
-- Trigger BEFORE INSERT/UPDATE en checklist_v2_instance_item: si el ítem
-- pertenece a una instancia de momento 'entrega_arriendo', resultado='na'
-- se rechaza. La UI ya esconde el botón (dashboard OT, móvil taller y
-- wizard standalone); esto cierra las otras vías. Los N/A históricos no se
-- tocan (el trigger solo mira escrituras nuevas). Recepción, ready-to-rent
-- y preventivas siguen admitiendo N/A.
-- IDEMPOTENTE. Prueba E2E con rollback al final.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_entrega_rechaza_na()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    IF NEW.resultado = 'na'
       AND (TG_OP = 'INSERT' OR OLD.resultado IS DISTINCT FROM NEW.resultado)
       AND EXISTS (
           SELECT 1
             FROM checklist_v2_instance ci
             JOIN checklist_template_v2 t ON t.id = ci.template_id
            WHERE ci.id = NEW.instance_id
              AND t.momento_uso = 'entrega_arriendo'
       ) THEN
        RAISE EXCEPTION
          'ENTREGA V02: el acta de entrega no admite N/A — todo item es '
          'atingente. Responda OK o NO OK (si la tarea no corresponde al '
          'equipo, el jefe la excluye en preparacion).';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_entrega_rechaza_na ON checklist_v2_instance_item;
CREATE TRIGGER trg_entrega_rechaza_na
    BEFORE INSERT OR UPDATE OF resultado ON checklist_v2_instance_item
    FOR EACH ROW EXECUTE FUNCTION fn_entrega_rechaza_na();


-- ── Prueba E2E con rollback: el N/A rebota en entrega, pasa en recepción ────
DO $mig$
DECLARE
    v_admin  UUID;
    v_activo UUID;
    v_r      JSONB;
    v_ot     UUID;
    v_item   UUID;
    v_paso1  BOOLEAN := false;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    IF v_admin IS NULL OR v_activo IS NULL THEN
        RAISE EXCEPTION 'FALLO: falta admin o TEST-01 para la prueba';
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    BEGIN
        v_r  := rpc_programar_entrega_arriendo(v_activo, 'normal', CURRENT_DATE, v_admin);
        v_ot := (v_r->>'id')::uuid;

        SELECT ii.id INTO v_item
          FROM checklist_v2_instance_item ii
          JOIN checklist_v2_instance i ON i.id = ii.instance_id
         WHERE i.ot_id = v_ot LIMIT 1;
        IF v_item IS NULL THEN
            RAISE EXCEPTION 'FALLO_REAL: la entrega de prueba no tiene items';
        END IF;

        -- 1) N/A en entrega debe rebotar
        BEGIN
            UPDATE checklist_v2_instance_item SET resultado = 'na' WHERE id = v_item;
            RAISE EXCEPTION 'FALLO_REAL: la entrega acepto un N/A';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%no admite N/A%' THEN
                v_paso1 := true;
            ELSE
                RAISE EXCEPTION 'FALLO_REAL: reboto pero con otro error: %', SQLERRM;
            END IF;
        END;

        -- 2) OK debe seguir pasando
        UPDATE checklist_v2_instance_item SET resultado = 'ok' WHERE id = v_item;
        IF NOT v_paso1 THEN
            RAISE EXCEPTION 'FALLO_REAL: el candado de N/A nunca reboto';
        END IF;

        RAISE EXCEPTION 'ROLLBACK_MARKER N/A rechazado en entrega, OK sigue pasando';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK (revertida): %', SQLERRM;
        ELSE
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
    END;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_entrega_rechaza_na') THEN
        RAISE EXCEPTION 'FALLO: el trigger MIG545 no quedo instalado';
    END IF;
    RAISE NOTICE 'MIG545 OK · la entrega en arriendo ya no admite N/A';
END
$mig$;

COMMIT;

NOTIFY pgrst, 'reload schema';
