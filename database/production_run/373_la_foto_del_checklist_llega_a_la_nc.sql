-- ============================================================================
-- MIG373 · La foto del checklist llega a la no conformidad
-- ----------------------------------------------------------------------------
-- Del taller llegó que las NC de inspección salen sin foto. Los números lo
-- confirman y son concluyentes:
--
--     origen ejecucion_ot    67 NC ·  49 con foto
--     origen inspeccion_ot   29 NC ·   0 con foto
--
-- Y la foto SÍ existe: seis de las últimas ocho NC de inspección cuelgan de un
-- ítem de checklist que tiene su foto guardada. Nunca se copió a la NC, y la
-- bandeja lee `no_conformidades.foto_url` — así que el jefe ve el hallazgo sin
-- evidencia, que es justamente lo que después se discute con el cliente.
--
-- POR QUÉ NO BASTA CON COPIARLA AL CREAR
-- Éste es el detalle que hace que el arreglo obvio no funcione. El trigger que
-- crea la NC salta cuando el ítem pasa a NO OK — y en ese instante la foto
-- todavía no está: en terreno se marca NO OK primero y se saca la foto después.
-- Copiar en ese momento seguiría dejando la NC vacía.
--
-- Por eso van las dos mitades:
--   · al crear la NC, se copia la foto si ya está;
--   · y cuando la foto llega después, se le pone a la NC que ya existe.
--
-- LA FOTO PUESTA A MANO EN LA NC NO SE PISA
-- Si alguien le cargó una foto directamente a la no conformidad, ésa manda: el
-- checklist sólo rellena el hueco. Una evidencia elegida a propósito vale más
-- que la que se arrastra sola.
--
-- MIG212 GUARDÓ LAS FOTOS EN DOS LUGARES
-- El ítem tiene `foto_url` (la primera) y `foto_urls` (todas). Se mira primero
-- la columna simple y después el arreglo, porque hay ítems que sólo tienen una
-- de las dos.
-- ============================================================================

BEGIN;

-- ── De dónde sale la foto de un ítem de checklist ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_foto_item_checklist(
    p_foto_url text, p_foto_urls text[]
)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    SELECT COALESCE(NULLIF(TRIM(p_foto_url), ''),
                    NULLIF(TRIM(COALESCE(p_foto_urls[1], '')), ''));
$f$;


-- ── 1. Al nacer la NC, se lleva la foto si ya está ────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_nc_al_marcar_no_ok()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
            checklist_item_ref, estado_planificacion, registrada_por, created_by,
            -- [MIG373] Muchas veces todavía es NULL acá: se marca NO OK y la
            -- foto se saca después. Para ese caso está el trigger de abajo.
            foto_url
        ) VALUES (
            v_inst.activo_id, v_inst.ot_id, 'otra',
            v_desc || COALESCE(' — ' || NULLIF(TRIM(NEW.observacion), ''), ''),
            CURRENT_DATE, 'media', 'inspeccion_ot',
            NEW.id, 'registrada', auth.uid(), auth.uid(),
            fn_foto_item_checklist(NEW.foto_url, NEW.foto_urls)
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
END $function$;


-- ── 2. Cuando la foto llega después, se le pone a la NC que ya existe ─────
-- Ésta es la mitad que faltaba. En terreno el orden real es: marcar NO OK,
-- escribir qué tiene, y recién ahí sacar la foto.
CREATE OR REPLACE FUNCTION public.fn_trg_foto_item_a_nc()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_foto TEXT;
BEGIN
    v_foto := fn_foto_item_checklist(NEW.foto_url, NEW.foto_urls);
    IF v_foto IS NULL THEN RETURN NEW; END IF;

    -- Sólo se rellena el hueco: una foto puesta a mano en la NC manda sobre la
    -- que se arrastra del checklist.
    UPDATE no_conformidades
       SET foto_url = v_foto, updated_at = NOW()
     WHERE checklist_item_ref = NEW.id
       AND COALESCE(TRIM(foto_url), '') = '';

    -- La observación del ítem también se escribe después de marcar NO OK, y la
    -- descripción de la NC quedaba con el nombre del ítem pelado.
    IF COALESCE(TRIM(NEW.observacion), '') <> ''
       AND COALESCE(TRIM(OLD.observacion), '') IS DISTINCT FROM COALESCE(TRIM(NEW.observacion), '') THEN
        UPDATE no_conformidades n
           SET descripcion = CASE
                 WHEN n.descripcion LIKE '%—%' THEN n.descripcion
                 ELSE n.descripcion || ' — ' || TRIM(NEW.observacion) END,
               updated_at = NOW()
         WHERE n.checklist_item_ref = NEW.id
           AND n.estado_planificacion = 'registrada';
    END IF;

    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_foto_item_a_nc ON public.checklist_v2_instance_item;
CREATE TRIGGER trg_foto_item_a_nc
    AFTER UPDATE OF foto_url, foto_urls, observacion
    ON public.checklist_v2_instance_item
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trg_foto_item_a_nc();

COMMENT ON FUNCTION public.fn_trg_foto_item_a_nc() IS
  'Le pone a la NC la foto del item de checklist cuando llega DESPUES de marcarlo NO OK, que es el orden real en terreno. MIG373.';


-- ── 3. Las que ya estaban sin foto ────────────────────────────────────────
DO $backfill$
DECLARE v_n INT;
BEGIN
    UPDATE no_conformidades n
       SET foto_url = fn_foto_item_checklist(i.foto_url, i.foto_urls),
           updated_at = NOW()
      FROM checklist_v2_instance_item i
     WHERE i.id = n.checklist_item_ref
       AND COALESCE(TRIM(n.foto_url), '') = ''
       AND fn_foto_item_checklist(i.foto_url, i.foto_urls) IS NOT NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'MIG373 · no conformidades que recuperaron su foto: %', v_n;
END
$backfill$;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT origen, count(*) AS n, count(foto_url) AS con_foto
--   FROM no_conformidades GROUP BY 1 ORDER BY 2 DESC;
