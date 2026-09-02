-- ============================================================================
-- MIG494 · La pauta que dice «hacer la otra pauta»
-- ============================================================================
--
-- LO QUE ENCONTRÓ MANUEL
-- 02-09-2026: «he planificado una actividad con SM3 y me dice a realizar el SM3
-- completo; yo necesito un checklist de qué es lo que tiene que hacer el
-- operador».
--
-- QUÉ PASA
-- Los servicios del fabricante son escalonados: el SM2 es «todo el SM1 más
-- esto», el SM3 es «todo el SM2 más esto». Y así está escrito en la base — el
-- primer ítem del SM3 del Actros es, literalmente, «SM2 completo».
--
-- Como catálogo eso es correcto y ahorra repetir. Como CHECKLIST es inútil: el
-- mecánico abre el teléfono, lee «SM2 completo» y tiene que saberse de memoria
-- qué incluía el SM2 — que a su vez empieza con «SM1 completo».
--
-- Son 19 pautas en 5 modelos. El Actros llega hasta el SM6, o sea seis niveles
-- de «completo» encadenados para llegar a los pasos de verdad.
--
-- LO QUE HACE ESTA MIGRACIÓN
-- Al copiar la pauta al checklist, esas referencias se ABREN: donde decía «SM2
-- completo» aparecen los pasos del SM2, y si el SM2 decía «SM1 completo», los
-- del SM1 también. El mecánico ve la lista completa de lo que tiene que hacer,
-- y cada paso heredado dice de dónde viene («SM1 · Cambio aceite motor»), para
-- que se entienda el escalón sin tener que abrir otra pantalla.
--
-- LO QUE NO SE TOCA
-- La pauta original. Sigue diciendo «SM2 completo», que es como la escribió el
-- fabricante y como conviene mantenerla: si mañana cambia el SM1, el SM3 hereda
-- el cambio solo. Lo que se expande es la COPIA que ve el mecánico.
-- ============================================================================

BEGIN;

-- ── 1 · ¿Este ítem es una referencia a otra pauta? ──────────────────────────
--
-- «SM2 completo», «SM 2 completo», «Servicio SM1 completo» → SM2 / SM1.
-- Cualquier otra cosa devuelve NULL y se trata como un paso normal.
CREATE OR REPLACE FUNCTION fn_pauta_ref_codigo(p_texto TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT upper(replace((regexp_match(
        btrim(COALESCE(p_texto, '')),
        '^(?:servicio\s+)?(S[MLI]\s*[0-9]?|PM[0-9]?)\s+complet[oa]s?\.?$',
        'i'))[1], ' ', ''));
$$;

COMMENT ON FUNCTION fn_pauta_ref_codigo(TEXT) IS
    'El código de la pauta a la que apunta un ítem del tipo «SM2 completo». '
    'NULL si el ítem es un paso de verdad y no una referencia.';

-- ── 2 · Los pasos de una pauta, con las referencias abiertas ────────────────
CREATE OR REPLACE FUNCTION fn_pauta_items_expandidos(
    p_pauta_id UUID,
    p_nivel    INT DEFAULT 0
)
RETURNS TABLE (orden INT, descripcion TEXT, viene_de TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_items   JSONB;
    v_modelo  UUID;
    r         JSONB;
    v_desc    TEXT;
    v_cod     TEXT;
    v_ref     UUID;
    v_n       INT := 0;
    hijo      RECORD;
BEGIN
    -- Seis niveles alcanzan para el Actros, que llega al SM6. Más que eso es
    -- una pauta que se referencia a sí misma, y no se sigue.
    IF p_nivel > 6 THEN RETURN; END IF;

    SELECT p.items_checklist, p.modelo_id INTO v_items, v_modelo
      FROM pautas_fabricante p WHERE p.id = p_pauta_id;
    IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' THEN RETURN; END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(v_items)
    LOOP
        IF jsonb_typeof(r) = 'string' THEN
            v_desc := trim(both '"' FROM r::TEXT);
        ELSE
            v_desc := COALESCE(r ->> 'descripcion', r ->> 'item', r ->> 'nombre');
        END IF;
        v_desc := btrim(COALESCE(v_desc, ''));
        IF v_desc = '' THEN CONTINUE; END IF;

        v_cod := fn_pauta_ref_codigo(v_desc);
        v_ref := NULL;

        IF v_cod IS NOT NULL AND v_modelo IS NOT NULL THEN
            -- La pauta hermana del MISMO modelo cuyo nombre lleva ese código.
            SELECT p2.id INTO v_ref
              FROM pautas_fabricante p2
             WHERE p2.modelo_id = v_modelo
               AND p2.id <> p_pauta_id
               AND p2.activo
               AND p2.nombre ~* ('(^|[^a-z0-9])' || v_cod || '([^a-z0-9]|$)')
             ORDER BY p2.nombre
             LIMIT 1;
        END IF;

        IF v_ref IS NOT NULL THEN
            -- Se abre: los pasos del servicio anterior entran acá, marcados con
            -- su origen para que el mecánico entienda el escalón.
            FOR hijo IN SELECT * FROM fn_pauta_items_expandidos(v_ref, p_nivel + 1)
            LOOP
                v_n := v_n + 1;
                orden := v_n * 10;
                descripcion := hijo.descripcion;
                viene_de := COALESCE(hijo.viene_de, v_cod);
                RETURN NEXT;
            END LOOP;
        ELSE
            v_n := v_n + 1;
            orden := v_n * 10;
            descripcion := v_desc;
            viene_de := NULL;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION fn_pauta_items_expandidos(UUID, INT) IS
    'Los pasos de una pauta con las referencias abiertas: donde dice «SM2 '
    'completo» entran los pasos del SM2. `viene_de` dice de qué servicio se '
    'heredó cada paso.';

-- ── 3 · El checklist se arma con los pasos abiertos ─────────────────────────
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
    it       RECORD;
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
        RETURN NULL;
    END IF;

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
        UPDATE checklist_template_v2 SET activo = FALSE, updated_at = NOW() WHERE id = v_tpl;
        v_ver := v_ver + 1;
        v_tpl := NULL;
    ELSE
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

    -- [MIG494] Acá está el cambio: los pasos vienen ya expandidos, así que un
    -- «SM2 completo» llega convertido en los pasos del SM2.
    FOR it IN SELECT * FROM fn_pauta_items_expandidos(p_pauta_id, 0) ORDER BY orden
    LOOP
        v_n := v_n + 1;
        INSERT INTO checklist_template_v2_item (
            template_id, bloque, orden, codigo, descripcion,
            tipos_equipamiento, obligatorio, requiere_foto, tipo_respuesta, ayuda
        ) VALUES (
            v_tpl, 'a_trabajos_ot', it.orden,
            'P' || lpad(v_n::TEXT, 3, '0'),
            -- El paso heredado dice de dónde viene: el mecánico entiende el
            -- escalón sin abrir otra pantalla.
            CASE WHEN it.viene_de IS NOT NULL
                 THEN it.viene_de || ' · ' || it.descripcion
                 ELSE it.descripcion END,
            v_tipos, TRUE, FALSE, 'ok_no_ok',
            CASE WHEN it.viene_de IS NOT NULL
                 THEN 'Viene del servicio ' || it.viene_de || ', que este incluye completo.'
            END
        );
    END LOOP;

    RETURN v_tpl;
END;
$$;

-- ── 4 · Rehacer los 85 checklists con los pasos abiertos ────────────────────
DO $mig$
DECLARE r RECORD; v_ok INT := 0;
BEGIN
    FOR r IN SELECT id FROM pautas_fabricante WHERE activo LOOP
        IF fn_pauta_a_template(r.id) IS NOT NULL THEN v_ok := v_ok + 1; END IF;
    END LOOP;
    RAISE NOTICE 'checklists rehechos: %', v_ok;
END $mig$;

-- ── 5 · Y que el planificador vea lo mismo que el mecánico ─────────────────
--
-- El botón «ver las actividades» leía la pauta cruda, así que seguía mostrando
-- «SM2 completo». Tiene que mostrar lo mismo que va a ver el mecánico: si no,
-- el planificador aprueba una lista y el taller recibe otra.
CREATE OR REPLACE VIEW v_pauta_actividades AS
SELECT pm.id            AS plan_mantenimiento_id,
       pm.activo_id,
       p.id             AS pauta_id,
       p.nombre         AS pauta,
       p.duracion_estimada_hrs,
       i.orden,
       i.descripcion,
       i.ayuda
  FROM planes_mantenimiento pm
  JOIN pautas_fabricante p        ON p.id = pm.pauta_fabricante_id
  JOIN checklist_template_v2 t    ON t.pauta_fabricante_id = p.id AND t.activo
  JOIN checklist_template_v2_item i ON i.template_id = t.id;

COMMENT ON VIEW v_pauta_actividades IS
    'Los pasos que va a ver el mecánico para el plan de mantenimiento de un '
    'equipo, con las referencias entre servicios ya abiertas.';

GRANT SELECT ON v_pauta_actividades TO authenticated;

REVOKE ALL ON FUNCTION fn_pauta_items_expandidos(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_pauta_items_expandidos(UUID, INT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_antes INT; v_despues INT; v_ref INT;
BEGIN
    SELECT count(*) INTO v_ref FROM pautas_fabricante
     WHERE activo AND items_checklist::TEXT ~* '(SM[0-9]|SL|SI|PM)\s*complet';
    RAISE NOTICE 'pautas que referencian a otra: %', v_ref;

    FOR r IN
        SELECT p.nombre,
               jsonb_array_length(p.items_checklist) AS escritos,
               (SELECT count(*) FROM checklist_template_v2_item i
                 JOIN checklist_template_v2 t ON t.id = i.template_id
                WHERE t.pauta_fabricante_id = p.id AND t.activo) AS en_checklist
          FROM pautas_fabricante p
         WHERE p.activo AND p.nombre ILIKE '%SM3%'
         ORDER BY p.nombre LIMIT 4
    LOOP
        RAISE NOTICE '  %: % ítems escritos → % pasos para el mecánico',
                     r.nombre, r.escritos, r.en_checklist;
    END LOOP;

    -- Ningún checklist puede quedar con un «completo» sin abrir.
    SELECT count(*) INTO v_despues
      FROM checklist_template_v2_item i
      JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE t.pauta_fabricante_id IS NOT NULL AND t.activo
       AND fn_pauta_ref_codigo(i.descripcion) IS NOT NULL;
    RAISE NOTICE 'pasos que siguen diciendo «completo» sin abrir: %', v_despues;
END $mig$;

COMMIT;
