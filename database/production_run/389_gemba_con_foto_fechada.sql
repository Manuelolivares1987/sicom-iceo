-- ============================================================================
-- MIG389 · El Gemba exige foto, y la foto trae fecha y hora
-- ----------------------------------------------------------------------------
-- `gemba_respuestas` no tenía dónde guardar una foto. Un recorrido terminaba
-- siendo una lista de «no cumple» sin nada detrás: quien lo lee después no
-- puede saber qué se vio, y quien lo hizo no tiene con qué respaldarlo.
--
-- LA FOTO SE EXIGE DONDE IMPORTA
-- No en los 40 ítems —eso convierte el recorrido en una sesión de fotografía y
-- termina en fotos del piso para poder avanzar— sino en los que se marcan «no
-- cumple». Ahí la foto ES el hallazgo: sin ella, la observación es la palabra
-- de uno contra la del otro dos semanas después.
--
-- Y EL RECORRIDO NO SE CIERRA SIN ELLAS
-- Poner la regla sólo al guardar la respuesta dejaría cerrar el recorrido con
-- los «no cumple» a medio documentar. El trigger la revisa al cerrar, que es
-- cuando el recorrido pasa a ser un documento.
--
-- LA FECHA Y LA HORA VIENEN DE LA CAPTURA
-- `foto_tomada_at` la escribe el teléfono en el momento de sacarla, y queda
-- separada de `created_at` a propósito: una foto sacada a las 9 y subida a las
-- 6 de la tarde son dos hechos distintos, y confundirlos haría pasar por
-- reciente algo que no lo es. La app además la estampa sobre la imagen, para
-- que el papel impreso también lo diga.
--
-- LO QUE YA ESTÁ NO SE TOCA
-- Hay 4 recorridos cerrados con 4 «no cumple» sin foto. El CHECK aplica a lo
-- que venga, no a lo que ya pasó: un recorrido cerrado es inmutable desde
-- MIG288, y volverlo inválido retroactivamente sólo dejaría un dato imposible
-- de arreglar.
-- ============================================================================

BEGIN;

-- ── 1. La respuesta guarda su evidencia ───────────────────────────────────
ALTER TABLE public.gemba_respuestas
    ADD COLUMN IF NOT EXISTS foto_url       TEXT,
    ADD COLUMN IF NOT EXISTS foto_tomada_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS foto_lat       NUMERIC,
    ADD COLUMN IF NOT EXISTS foto_lng       NUMERIC,
    ADD COLUMN IF NOT EXISTS sin_foto_motivo TEXT;

COMMENT ON COLUMN public.gemba_respuestas.foto_tomada_at IS
    '[MIG389] Cuándo se sacó la foto, según el teléfono. Distinto de created_at, que es cuándo llegó al servidor.';
COMMENT ON COLUMN public.gemba_respuestas.sin_foto_motivo IS
    '[MIG389] Por qué no hay foto. Es la salida honesta para lo que no se puede fotografiar; queda escrita y a la vista.';

-- ── 2. Al cerrar, los hallazgos tienen que estar respaldados ──────────────
CREATE OR REPLACE FUNCTION public.fn_gemba_cerrar_exige_evidencia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_faltan TEXT;
    v_n      INT;
BEGIN
    -- Sólo al pasar a cerrado. Mientras está en curso se puede ir y volver.
    IF NEW.estado <> 'cerrado' OR COALESCE(OLD.estado, '') = 'cerrado' THEN
        RETURN NEW;
    END IF;

    SELECT count(*), string_agg(left(r.item, 60), ' · ' ORDER BY r.orden)
      INTO v_n, v_faltan
      FROM public.gemba_respuestas r
     WHERE r.recorrido_id = NEW.id
       AND r.evaluacion = 'no_cumple'
       AND COALESCE(NULLIF(trim(r.foto_url), ''), '') = ''
       AND COALESCE(length(trim(r.sin_foto_motivo)), 0) < 5;

    IF v_n > 0 THEN
        RAISE EXCEPTION 'No se puede cerrar: % hallazgo(s) sin foto ni motivo — %',
            v_n, left(v_faltan, 200)
            USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_gemba_cerrar_exige_evidencia ON public.gemba_recorridos;
CREATE TRIGGER trg_gemba_cerrar_exige_evidencia
    BEFORE UPDATE ON public.gemba_recorridos
    FOR EACH ROW EXECUTE FUNCTION public.fn_gemba_cerrar_exige_evidencia();

-- ── 3. Los autos estacionados afuera del taller ───────────────────────────
-- Va en la sección de orden y tránsito porque es lo que es: un vehículo mal
-- estacionado afuera bloquea la salida de emergencia y el paso de un camión.
DO $item$
DECLARE
    v_id       UUID;
    v_secs     JSONB;
    v_nueva    JSONB;
    v_s        JSONB;
    v_puesto   BOOLEAN;
    v_texto    TEXT := 'No hay vehículos particulares estacionados fuera del taller de Pillado obstruyendo el acceso, la salida de emergencia o el tránsito de equipos.';
BEGIN
    FOR v_id IN
        SELECT id FROM public.gemba_plantillas
         WHERE cargo = 'prevencionista' AND activo
    LOOP
        SELECT secciones INTO v_secs FROM public.gemba_plantillas WHERE id = v_id;

        -- Si ya está, no se repite: esta migración puede correr dos veces.
        IF v_secs::text ILIKE '%estacionados fuera del taller%' THEN
            CONTINUE;
        END IF;

        v_nueva := '[]'::jsonb;
        v_puesto := FALSE;

        FOR v_s IN SELECT * FROM jsonb_array_elements(v_secs)
        LOOP
            -- Entra en la sección de orden y aseo si existe; si no, al final.
            IF NOT v_puesto AND (v_s->>'titulo') ILIKE '%orden%' THEN
                v_s := jsonb_set(v_s, '{items}', (v_s->'items') || to_jsonb(v_texto));
                v_puesto := TRUE;
            END IF;
            v_nueva := v_nueva || v_s;
        END LOOP;

        -- La caminata diaria tiene una sola sección: ahí va igual.
        IF NOT v_puesto THEN
            IF jsonb_array_length(v_nueva) > 0 THEN
                v_s := v_nueva->0;
                v_s := jsonb_set(v_s, '{items}', (v_s->'items') || to_jsonb(v_texto));
                v_nueva := jsonb_set(v_nueva, '{0}', v_s);
            ELSE
                v_nueva := jsonb_build_array(jsonb_build_object(
                    'titulo', 'Entorno del taller', 'items', jsonb_build_array(v_texto)));
            END IF;
        END IF;

        UPDATE public.gemba_plantillas
           SET secciones = v_nueva, updated_at = NOW()
         WHERE id = v_id;
    END LOOP;
END
$item$;

-- ── 4. Que quedó donde tenía que quedar ───────────────────────────────────
DO $verif$
DECLARE v_r RECORD;
BEGIN
    FOR v_r IN
        SELECT p.codigo,
               (SELECT s->>'titulo' FROM jsonb_array_elements(p.secciones) s
                 WHERE s::text ILIKE '%estacionados fuera del taller%' LIMIT 1) AS seccion
          FROM public.gemba_plantillas p
         WHERE p.cargo = 'prevencionista' AND p.activo
    LOOP
        IF v_r.seccion IS NULL THEN
            RAISE EXCEPTION 'La plantilla % quedó sin la pregunta de los autos.', v_r.codigo;
        END IF;
        RAISE NOTICE '% -> la pregunta quedó en «%»', v_r.codigo, v_r.seccion;
    END LOOP;
END
$verif$;

COMMIT;
