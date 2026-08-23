-- ============================================================================
-- MIG344 · Lo que se le pide a un turno no se pierde en el cambio de turno
-- ----------------------------------------------------------------------------
-- La queja del mandante: se le dice algo al turno de día, el turno de noche no
-- lo hace, y nadie se entera hasta que el mandante vuelve a preguntar. No hay
-- continuidad.
--
-- POR QUÉ FALLA HOY, Y POR QUÉ UN CAMPO DE OBSERVACIONES NO LO ARREGLA
-- Una instrucción hoy es una NOTA: alguien la dice, alguien la anota en un
-- cuaderno o en el campo de observaciones, y ahí muere. Una nota no obliga a
-- nadie porque no tiene tres cosas:
--   · no tiene dueño        — nadie es responsable de que se haga
--   · no tiene cierre       — nunca pasa de «anotada» a «hecha»
--   · no se lee             — el turno siguiente no está obligado a mirarla
-- Agregar otro campo de texto libre reproduce la misma falla con más letras.
--
-- QUÉ SE HACE EN CAMBIO
-- Un pendiente pasa a ser un objeto con estado. Nace abierto, y sigue abierto
-- hasta que alguien lo cierra diciendo qué hizo. Y —esto es lo que cambia todo—
-- vive DENTRO del cierre del turno, que es el único ritual que el turno ya está
-- obligado a completar. No es un módulo nuevo que nadie abre: aparece cuando el
-- supervisor empieza el recorrido y otra vez cuando va a firmar.
--
-- EL TRASPASO ES EL DATO, NO EL PENDIENTE
-- Cada turno que pasa deja su respuesta: hecho, no alcancé y por qué, o no
-- corresponde y por qué. La cadena de respuestas es lo que el mandante quiere
-- ver — no «¿lo anotaron?» sino «¿cuántos turnos lleva esto dando vueltas y
-- quién lo dejó pasar cada vez?».
--
-- Un pendiente que cruzó un turno es normal. Uno que cruzó cuatro es otro
-- problema, y con nombre y apellido en cada uno.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.combustible_faena_pendiente (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    texto       TEXT NOT NULL,
    -- De dónde viene la instrucción. El mandante pesa distinto que una nota
    -- interna, y quien la recibe tiene que poder verlo.
    origen      TEXT NOT NULL DEFAULT 'supervisor'
                CHECK (origen IN ('mandante','supervisor','oficina','sistema')),
    pedido_por  TEXT,
    prioridad   TEXT NOT NULL DEFAULT 'normal'
                CHECK (prioridad IN ('normal','alta')),
    estado      TEXT NOT NULL DEFAULT 'abierto'
                CHECK (estado IN ('abierto','cerrado')),
    creado_por  UUID,
    creado_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cerrado_at  TIMESTAMPTZ,
    cerrado_por TEXT,
    cerrado_comentario TEXT
);

COMMENT ON TABLE public.combustible_faena_pendiente IS
  'Lo que se le pidio a la faena y todavia no se ha hecho. No es una nota: nace abierto y sigue abierto hasta que un turno lo cierra diciendo que hizo. MIG344.';

CREATE INDEX IF NOT EXISTS idx_pendiente_abierto
    ON public.combustible_faena_pendiente(faena_id, estado);

CREATE TABLE IF NOT EXISTS public.combustible_faena_pendiente_traspaso (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pendiente_id UUID NOT NULL REFERENCES public.combustible_faena_pendiente(id) ON DELETE CASCADE,
    cierre_id    UUID REFERENCES public.combustible_faena_cierre(id) ON DELETE SET NULL,
    fecha        DATE NOT NULL,
    turno        TEXT,
    respuesta    TEXT NOT NULL
                 CHECK (respuesta IN ('hecho','no_alcanzo','no_corresponde')),
    comentario   TEXT,
    respondido_por TEXT,
    respondido_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (pendiente_id, cierre_id)
);

COMMENT ON TABLE public.combustible_faena_pendiente_traspaso IS
  'La respuesta de cada turno a cada pendiente. La cadena de respuestas es el dato: no «lo anotaron» sino cuantos turnos lleva y quien lo dejo pasar cada vez. MIG344.';

ALTER TABLE public.combustible_faena_pendiente          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combustible_faena_pendiente_traspaso ENABLE ROW LEVEL SECURITY;

DO $pol$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['combustible_faena_pendiente','combustible_faena_pendiente_traspaso']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_lectura ON public.%I', t, t);
        EXECUTE format($p$CREATE POLICY pol_%s_lectura ON public.%I
                          FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL)$p$, t, t);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    END LOOP;
END $pol$;

-- ── Lo que está abierto, y hace cuánto ─────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_pendientes_abiertos AS
SELECT p.id, p.faena_id, p.texto, p.origen, p.pedido_por, p.prioridad,
       p.creado_at,
       (CURRENT_DATE - p.creado_at::date)::integer AS dias_abierto,
       count(t.id)::integer AS turnos_sin_hacer,
       max(t.respondido_at) AS ultima_respuesta_at,
       (SELECT t2.comentario FROM combustible_faena_pendiente_traspaso t2
         WHERE t2.pendiente_id = p.id ORDER BY t2.respondido_at DESC LIMIT 1) AS ultimo_comentario,
       (SELECT t2.respondido_por FROM combustible_faena_pendiente_traspaso t2
         WHERE t2.pendiente_id = p.id ORDER BY t2.respondido_at DESC LIMIT 1) AS ultimo_turno_por,
       -- Uno que cruzo un turno es normal. Uno que cruzo cuatro es otro
       -- problema, y hay que mirarlo distinto.
       CASE
         WHEN count(t.id) = 0 THEN 'nuevo'
         WHEN count(t.id) <= 2 THEN 'arrastrando'
         ELSE 'atascado'
       END AS senal
FROM combustible_faena_pendiente p
LEFT JOIN combustible_faena_pendiente_traspaso t ON t.pendiente_id = p.id
WHERE p.estado = 'abierto'
GROUP BY p.id, p.faena_id, p.texto, p.origen, p.pedido_por, p.prioridad, p.creado_at;

GRANT SELECT ON public.v_comb_faena_pendientes_abiertos TO authenticated;

-- ── La cadena completa, que es lo que el mandante pide ver ─────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_pendiente_historia AS
SELECT p.faena_id, p.id AS pendiente_id, p.texto, p.origen, p.pedido_por,
       p.creado_at, p.estado, p.cerrado_at, p.cerrado_por,
       t.fecha, t.turno, t.respuesta, t.comentario, t.respondido_por, t.respondido_at
FROM combustible_faena_pendiente p
LEFT JOIN combustible_faena_pendiente_traspaso t ON t.pendiente_id = p.id
ORDER BY p.creado_at DESC, t.respondido_at;

GRANT SELECT ON public.v_comb_faena_pendiente_historia TO authenticated;

-- ── Anotar un pendiente ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_pendiente_crear(
    p_faena_id uuid,
    p_texto    text,
    p_origen   text DEFAULT 'supervisor',
    p_pedido_por text DEFAULT NULL,
    p_prioridad  text DEFAULT 'normal'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
    -- Cualquiera que opere la faena puede anotar un pendiente. Poner una
    -- barrera aqui seria el peor lugar: si cuesta anotarlo, no se anota.
    IF NOT public.fn_comb_puede_operar() THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    IF length(trim(COALESCE(p_texto,''))) < 5 THEN
        RAISE EXCEPTION 'Escriba qué hay que hacer.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO combustible_faena_pendiente
        (faena_id, texto, origen, pedido_por, prioridad, creado_por)
    VALUES (p_faena_id, trim(p_texto), COALESCE(p_origen,'supervisor'),
            p_pedido_por, COALESCE(p_prioridad,'normal'), auth.uid())
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('pendiente_id', v_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_pendiente_crear(uuid, text, text, text, text) TO authenticated;

-- ── Firmar el turno respondiendo a lo que quedó pendiente ──────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_responder_pendientes(
    p_faena_id uuid, p_cierre_id uuid, p_fecha date, p_turno text,
    p_por text, p_respuestas jsonb
)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_r        JSONB;
    v_id       UUID;
    v_resp     TEXT;
    v_com      TEXT;
    v_abiertos UUID[];
    v_contest  UUID[];
    v_faltan   TEXT;
    v_n        INTEGER := 0;
BEGIN
    SELECT array_agg(id) INTO v_abiertos
      FROM combustible_faena_pendiente
     WHERE faena_id = p_faena_id AND estado = 'abierto';

    IF v_abiertos IS NULL OR array_length(v_abiertos, 1) IS NULL THEN
        RETURN 0;
    END IF;

    SELECT array_agg((x->>'pendiente_id')::uuid) INTO v_contest
      FROM jsonb_array_elements(COALESCE(p_respuestas, '[]'::jsonb)) x;

    -- No se puede cerrar el turno ignorando lo que quedó pendiente. Ese es el
    -- punto entero: el turno que no contesta es el que rompe la continuidad.
    SELECT string_agg(left(p.texto, 60), ' · ') INTO v_faltan
      FROM combustible_faena_pendiente p
     WHERE p.id = ANY(v_abiertos)
       AND (v_contest IS NULL OR NOT (p.id = ANY(v_contest)));

    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta decir qué pasó con lo que quedó pendiente: %. Marque hecho, o escriba por qué no se alcanzó.',
            v_faltan USING ERRCODE = '22023';
    END IF;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_respuestas, '[]'::jsonb))
    LOOP
        v_id   := (v_r->>'pendiente_id')::uuid;
        v_resp := v_r->>'respuesta';
        v_com  := NULLIF(trim(COALESCE(v_r->>'comentario','')), '');

        IF NOT (v_id = ANY(v_abiertos)) THEN CONTINUE; END IF;

        -- «Hecho» se explica solo. Lo que necesita explicación es lo que NO se
        -- hizo: sin motivo, el turno siguiente recibe el mismo pendiente sin
        -- saber qué se intentó.
        IF v_resp <> 'hecho' AND v_com IS NULL THEN
            RAISE EXCEPTION 'Escriba por qué no se alcanzó a hacer: "%".',
                left((SELECT texto FROM combustible_faena_pendiente WHERE id = v_id), 60)
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO combustible_faena_pendiente_traspaso
            (pendiente_id, cierre_id, fecha, turno, respuesta, comentario, respondido_por)
        VALUES (v_id, p_cierre_id, p_fecha, p_turno, v_resp, v_com, p_por)
        ON CONFLICT (pendiente_id, cierre_id) DO UPDATE
            SET respuesta = EXCLUDED.respuesta,
                comentario = EXCLUDED.comentario,
                respondido_por = EXCLUDED.respondido_por,
                respondido_at = NOW();

        IF v_resp = 'hecho' THEN
            UPDATE combustible_faena_pendiente
               SET estado = 'cerrado', cerrado_at = NOW(),
                   cerrado_por = p_por, cerrado_comentario = v_com
             WHERE id = v_id;
        END IF;

        v_n := v_n + 1;
    END LOOP;

    RETURN v_n;
END;
$function$;

-- ── Un pendiente atascado entra a las excepciones del día ──────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_pendiente_atascado AS
SELECT a.faena_id, a.id AS pendiente_id, a.texto, a.origen, a.pedido_por,
       a.turnos_sin_hacer, a.dias_abierto, a.ultimo_comentario, a.ultimo_turno_por
FROM v_comb_faena_pendientes_abiertos a
WHERE a.senal = 'atascado' OR (a.prioridad = 'alta' AND a.turnos_sin_hacer >= 1);

GRANT SELECT ON public.v_comb_faena_pendiente_atascado TO authenticated;

COMMIT;
