-- ============================================================================
-- MIG490 · La pauta del fabricante es el checklist de la mantención
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 02-09-2026: «el sistema tiene cargadas pautas de mantenimiento que se cargan
-- al equipo; cuando va a realizar una MTN, ahí se debería activar el checklist
-- del fabricante».
--
-- LO QUE PASABA
-- Las pautas están: 85 activas, TODAS con sus ítems, para 9 modelos. Y están
-- enganchadas al equipo: 216 planes de mantenimiento apuntan a una pauta, y 29
-- OT preventivas nacieron de uno de esos planes.
--
-- Pero el checklist que se abre al ejecutar NO las mira. `fn_auto_checklist_ot`
-- abre siempre el mismo: el V03 de inspección, 188 ítems, el mismo para un
-- cambio de aceite que para una recepción de arriendo. De las 132 instancias de
-- checklist que existen, 127 son ese V03 y ninguna es una pauta de fabricante.
--
-- El mecánico que va a hacer el servicio de 300 h del Mack tiene delante 188
-- ítems de inspección general, y los 14 pasos que el fabricante manda hacer
-- están en un PDF que nadie abre.
--
-- LO QUE HACE ESTA MIGRACIÓN
-- Cada pauta se materializa como un template de checklist —una sola vez, y se
-- mantiene sola— y la OT preventiva que viene de un plan abre ESE checklist en
-- vez del V03 genérico.
--
-- DOS DETALLES QUE IMPORTAN
--
--   1. Los ítems de las pautas vienen en dos formas distintas en la base: unas
--      guardan texto suelto («Cambio aceite motor + filtro») y otras un objeto
--      con orden, obligatorio y si pide foto. Se leen las dos; no se normaliza
--      la fuente, se normaliza al materializar.
--
--   2. `fn_inicializar_checklist_v2` filtra los ítems por tipo de equipamiento.
--      Eso tiene sentido en el V03 genérico, que sirve para toda la flota. Una
--      pauta ya viene acotada a un modelo, así que sus ítems se marcan para
--      todos los tipos: si el filtro los descartara, el mecánico abriría un
--      checklist vacío.
-- ============================================================================

BEGIN;

-- ── 1 · El template sabe de qué pauta salió ─────────────────────────────────
ALTER TABLE checklist_template_v2
  ADD COLUMN IF NOT EXISTS pauta_fabricante_id UUID REFERENCES pautas_fabricante(id);

-- Un template VIGENTE por pauta. Los anteriores quedan: un checklist ya
-- respondido no se puede reescribir por debajo.
DROP INDEX IF EXISTS uq_template_por_pauta;
CREATE UNIQUE INDEX IF NOT EXISTS uq_template_por_pauta
    ON checklist_template_v2 (pauta_fabricante_id)
 WHERE pauta_fabricante_id IS NOT NULL AND activo = TRUE;

-- `uq_cl_v2_momento_activo` permitía UN template activo por momento de uso. Eso
-- vale para los genéricos —hay un solo V03 vigente, y así debe ser— pero no para
-- las pautas: son 85 y ninguna compite con otra, porque no se eligen por momento
-- sino por la pauta que el equipo tiene cargada.
DROP INDEX IF EXISTS uq_cl_v2_momento_activo;
CREATE UNIQUE INDEX IF NOT EXISTS uq_cl_v2_momento_activo
    ON checklist_template_v2 (momento_uso)
 WHERE activo = TRUE AND pauta_fabricante_id IS NULL;

COMMENT ON COLUMN checklist_template_v2.pauta_fabricante_id IS
    'De qué pauta del fabricante salió este template. Se materializa solo con '
    'fn_pauta_a_template: la fuente sigue siendo pautas_fabricante.';

-- ── 2 · Materializar una pauta como checklist ───────────────────────────────
CREATE OR REPLACE FUNCTION fn_pauta_a_template(p_pauta_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_p      RECORD;
    v_tpl    UUID;
    v_tipos  tipo_equipamiento_enum[];
    v_n      INT := 0;
    v_ver    INT;
    v_en_uso BOOLEAN := FALSE;
    r        JSONB;
    v_desc   TEXT;
    v_orden  INT;
BEGIN
    SELECT p.id, p.nombre, p.descripcion, p.items_checklist, p.duracion_estimada_hrs,
           p.tipo_plan, m.nombre AS modelo
      INTO v_p
      FROM pautas_fabricante p
      LEFT JOIN modelos m ON m.id = p.modelo_id
     WHERE p.id = p_pauta_id;

    IF v_p.id IS NULL THEN RAISE EXCEPTION 'Esa pauta no existe.'; END IF;
    IF v_p.items_checklist IS NULL
       OR jsonb_typeof(v_p.items_checklist) <> 'array'
       OR jsonb_array_length(v_p.items_checklist) = 0 THEN
        RETURN NULL;   -- una pauta sin ítems no es un checklist
    END IF;

    -- Una pauta ya viene acotada a un modelo: sus ítems valen para cualquier
    -- tipo de equipamiento que la tenga cargada.
    SELECT array_agg(e) INTO v_tipos
      FROM unnest(enum_range(NULL::tipo_equipamiento_enum)) e;

    SELECT id, version INTO v_tpl, v_ver FROM checklist_template_v2
     WHERE pauta_fabricante_id = p_pauta_id AND activo
     ORDER BY version DESC LIMIT 1;

    IF v_tpl IS NOT NULL THEN
        SELECT EXISTS (SELECT 1 FROM checklist_v2_instance i WHERE i.template_id = v_tpl)
          INTO v_en_uso;
    END IF;

    IF v_tpl IS NULL THEN
        v_ver := 1;
    ELSIF v_en_uso THEN
        -- La pauta cambió y su checklist ya se usó. No se reescribe: los ítems
        -- que un mecánico respondió cuelgan de estas filas, y borrarlas dejaría
        -- respuestas sin pregunta. Se cierra esta versión y nace la siguiente;
        -- las OT que ya están andando siguen con la que empezaron.
        UPDATE checklist_template_v2 SET activo = FALSE, updated_at = NOW() WHERE id = v_tpl;
        v_ver := v_ver + 1;
        v_tpl := NULL;
    ELSE
        -- Nadie la ha usado todavía: se rehace en el mismo lugar.
        UPDATE checklist_template_v2
           SET nombre = v_p.nombre, activo = TRUE, updated_at = NOW()
         WHERE id = v_tpl;
        DELETE FROM checklist_template_v2_item WHERE template_id = v_tpl;
    END IF;

    IF v_tpl IS NULL THEN
        INSERT INTO checklist_template_v2 (codigo, nombre, momento_uso, version, descripcion,
                                           activo, pauta_fabricante_id)
        VALUES ('PAUTA-' || left(replace(p_pauta_id::TEXT, '-', ''), 8)
                  || CASE WHEN v_ver > 1 THEN '-v' || v_ver ELSE '' END,
                v_p.nombre, 'preventiva', v_ver,
                COALESCE(v_p.descripcion, 'Pauta del fabricante')
                  || COALESCE(' · ' || v_p.modelo, ''),
                TRUE, p_pauta_id)
        RETURNING id INTO v_tpl;
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(v_p.items_checklist)
    LOOP
        v_n := v_n + 1;

        IF jsonb_typeof(r) = 'string' THEN
            v_desc  := trim(both '"' FROM r::TEXT);
            v_orden := v_n * 10;
        ELSE
            v_desc  := COALESCE(r ->> 'descripcion', r ->> 'item', r ->> 'nombre');
            v_orden := COALESCE((r ->> 'orden')::INT, v_n * 10);
        END IF;

        IF COALESCE(btrim(v_desc), '') = '' THEN CONTINUE; END IF;

        INSERT INTO checklist_template_v2_item (
            template_id, bloque, orden, codigo, descripcion,
            tipos_equipamiento, obligatorio, requiere_foto, tipo_respuesta
        ) VALUES (
            -- `bloque` es un enum: se usa el que ya existe para el trabajo de
            -- la OT. Los pasos de una pauta son exactamente eso.
            v_tpl, 'a_trabajos_ot', v_orden,
            'P' || lpad(v_n::TEXT, 3, '0'), v_desc,
            v_tipos,
            CASE WHEN jsonb_typeof(r) = 'object'
                 THEN COALESCE((r ->> 'obligatorio')::BOOLEAN, TRUE) ELSE TRUE END,
            CASE WHEN jsonb_typeof(r) = 'object'
                 THEN COALESCE((r ->> 'requiere_foto')::BOOLEAN, FALSE) ELSE FALSE END,
            'ok_no_ok'
        );
    END LOOP;

    RETURN v_tpl;
END;
$$;

COMMENT ON FUNCTION fn_pauta_a_template(UUID) IS
    'Copia una pauta del fabricante a un template de checklist. Idempotente: '
    'volver a llamarla rehace los ítems desde la pauta, que es la fuente.';

-- ── 3 · Materializar las que ya están cargadas ──────────────────────────────
DO $mig$
DECLARE r RECORD; v_ok INT := 0; v_sin INT := 0;
BEGIN
    FOR r IN SELECT id FROM pautas_fabricante WHERE activo LOOP
        IF fn_pauta_a_template(r.id) IS NULL THEN v_sin := v_sin + 1;
        ELSE v_ok := v_ok + 1; END IF;
    END LOOP;
    RAISE NOTICE 'pautas materializadas: % · sin ítems: %', v_ok, v_sin;
END $mig$;

-- ── 4 · Que la pauta se mantenga sola ───────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_pauta_sincronizar_template()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Sólo cuando cambia lo que el checklist copia.
    IF TG_OP = 'UPDATE'
       AND NEW.items_checklist IS NOT DISTINCT FROM OLD.items_checklist
       AND NEW.nombre IS NOT DISTINCT FROM OLD.nombre
       AND NEW.activo IS NOT DISTINCT FROM OLD.activo THEN
        RETURN NEW;
    END IF;

    IF NEW.activo THEN
        PERFORM fn_pauta_a_template(NEW.id);
    ELSE
        -- Pauta apagada, checklist apagado: no se ofrece más en OT nuevas. Las
        -- instancias que ya existen no se tocan.
        UPDATE checklist_template_v2 SET activo = FALSE, updated_at = NOW()
         WHERE pauta_fabricante_id = NEW.id AND activo;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Editar una pauta nunca puede fallar por culpa de su copia.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pauta_sincronizar_template ON pautas_fabricante;
CREATE TRIGGER trg_pauta_sincronizar_template
    AFTER INSERT OR UPDATE ON pautas_fabricante
    FOR EACH ROW EXECUTE FUNCTION fn_pauta_sincronizar_template();

-- ── 5 · La OT preventiva abre la pauta, no el V03 ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_auto_checklist_ot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
    v_es_pauta   BOOLEAN := FALSE;
BEGIN
    BEGIN
        -- ya tiene checklist propio?
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- [MIG490] Si esta OT nació de un plan de mantenimiento, el trabajo es
        -- la pauta del fabricante. Ese es el checklist, no la inspección
        -- general: el mecánico tiene que ver los pasos del servicio.
        IF NEW.plan_mantenimiento_id IS NOT NULL THEN
            SELECT t.id INTO v_tpl
              FROM planes_mantenimiento pm
              JOIN checklist_template_v2 t ON t.pauta_fabricante_id = pm.pauta_fabricante_id
             WHERE pm.id = NEW.plan_mantenimiento_id AND t.activo;
            v_es_pauta := v_tpl IS NOT NULL;
        END IF;

        IF v_tpl IS NULL THEN
            SELECT id INTO v_tpl FROM checklist_template_v2
             WHERE momento_uso='recepcion_devolucion' AND activo=true
             ORDER BY version DESC LIMIT 1;
        END IF;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        -- Reusar una instancia LIBRE del mismo equipo sólo aplica a la
        -- inspección: una pauta de fabricante no se empieza en terreno.
        IF NOT v_es_pauta THEN
            SELECT id INTO v_inst FROM checklist_v2_instance
             WHERE activo_id = NEW.activo_id
               AND momento_uso = 'recepcion_devolucion'
               AND estado = 'en_progreso'
               AND ot_id IS NULL
             ORDER BY fecha_inicio DESC LIMIT 1;
            IF v_inst IS NOT NULL THEN
                UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;
                IF NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                                WHERE ii.instance_id = v_inst
                                  AND COALESCE(ii.resultado, 'pendiente') <> 'pendiente') THEN
                    BEGIN
                        PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END IF;
                RETURN NEW;
            END IF;
        END IF;

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

        -- El arrastre de NC es de la inspección: en una pauta del fabricante
        -- los pasos son los del servicio, no los hallazgos de la visita pasada.
        IF NOT v_es_pauta THEN
            BEGIN
                PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN NEW;
END $function$;

-- ── 6 · Ver qué checklist le tocó a cada OT ─────────────────────────────────
CREATE OR REPLACE VIEW v_ot_checklist_origen AS
SELECT i.ot_id,
       i.id           AS instance_id,
       t.nombre       AS checklist,
       t.momento_uso::TEXT AS momento,
       (t.pauta_fabricante_id IS NOT NULL) AS es_pauta_fabricante,
       p.nombre       AS pauta,
       p.duracion_estimada_hrs,
       (SELECT count(*) FROM checklist_v2_instance_item ii WHERE ii.instance_id = i.id) AS items
  FROM checklist_v2_instance i
  JOIN checklist_template_v2 t ON t.id = i.template_id
  LEFT JOIN pautas_fabricante p ON p.id = t.pauta_fabricante_id
 WHERE i.ot_id IS NOT NULL;

GRANT SELECT ON v_ot_checklist_origen TO authenticated;

REVOKE ALL ON FUNCTION fn_pauta_a_template(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_pauta_a_template(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_tpl INT; v_items INT; v_planes INT;
BEGIN
    SELECT count(*) INTO v_tpl FROM checklist_template_v2 WHERE pauta_fabricante_id IS NOT NULL;
    SELECT count(*) INTO v_items FROM checklist_template_v2_item i
     JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE t.pauta_fabricante_id IS NOT NULL;
    SELECT count(*) INTO v_planes FROM planes_mantenimiento pm
     JOIN checklist_template_v2 t ON t.pauta_fabricante_id = pm.pauta_fabricante_id AND t.activo;
    RAISE NOTICE 'templates de pauta: % · ítems: % · planes del equipo que ya tienen checklist: %',
                 v_tpl, v_items, v_planes;
END $mig$;

COMMIT;
