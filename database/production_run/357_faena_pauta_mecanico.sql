-- ============================================================================
-- MIG357 · El mecánico de faena deja de entregar una narración
-- ----------------------------------------------------------------------------
-- La entrega de turno del mecánico de Franke dice, textualmente, lo mismo los
-- siete días:
--
--     Día 2: 7-08-2026
--       · Revisión de equipos de faena.
--       · Toma de km y horas de equipos.
--       · Revisión de fluidos y niveles de equipos.
--
-- Eso no es una pauta. No dice qué fluidos, ni cuál estaba bajo, ni si se
-- rellenó. El único dato duro del documento aparece al final, en mayúsculas,
-- cuando algo ya se rompió: «HOJAS DE SUSPENSIÓN DELANTERAS RH ROTA». Un turno
-- que sólo registra lo que se rompió no anticipa nada, y no hay forma de saber
-- si el día que no se anotó nada fue porque estaba todo bien o porque no se
-- miró.
--
-- POR QUÉ UNA PAUTA POR MODELO Y NO UNA LISTA ÚNICA
-- Franke tiene dos modelos y nada más: el Mack GU 813 6×4 —HHWB-44, LCSX-78 y
-- HHWB-42— y la Toyota Hilux 2.8 de supervisión, LLBP-96. Revisar una pértiga
-- y el ticket printer en una camioneta es ruido, y ruido en una pauta es lo que
-- hace que se marque todo OK sin mirar. El sistema ya sabe qué modelo es cada
-- equipo: la pauta se arma sobre ese dato.
--
-- LAS TRES REGLAS QUE HACEN QUE ESTO NO SE DEGRADE
--
--   1. LO QUE SALE NO OK NO SE CIERRA CON UN TEXTO. Pide foto y levanta una no
--      conformidad con dueño. La hoja de suspensión rota deja de ser una línea
--      en mayúsculas y pasa a ser un trabajo con estado.
--
--   2. EL HORÓMETRO SE TOMA UNA VEZ. Hoy ese número se escribe tres veces —el
--      «Formato km hr», el programa de mantención y la entrega de turno—. Acá
--      se pide dentro de la pauta y de ahí sale todo lo demás, incluida la
--      ficha del activo.
--
--   3. NO SE PUEDE MARCAR OK UN EQUIPO QUE NO SE VIO. «No está en faena» es una
--      respuesta válida y explícita. Obligar a inventar un tilde es peor que
--      registrar el hueco: el HHWB-42 lleva meses en Coquimbo y en el
--      documento aparece revisado igual.
--
-- LO QUE SE ENCONTRÓ AL CRUZAR EL PROGRAMA DE MANTENCIÓN
-- La faena corre los camiones a 300 h —25.585 → 25.885 en el HHWB-44, 9.345 →
-- 9.645 en el LCSX-78— y SICOM tiene cargados los servicios de fábrica Mack a
-- 250 / 500 / 1.000 / 3.000 h. Son dos calendarios para el mismo camión y nadie
-- los compara. Y la camioneta, que en faena se atiende cada 10.000 km, no tiene
-- ningún plan cargado.
--
-- Se unifica dejando mandar al programa de faena, que es el que se ejecuta:
-- entra un servicio de 300 h con el horómetro real de cada camión, se apagan
-- los dos de fábrica que quedan por debajo de él (SL 250 h y SM1 500 h, que el
-- de 300 h absorbe), y se dejan vivos SM2 y SM3, que son servicios mayores que
-- el de 300 h no reemplaza. Si el criterio es otro, se cambia en la ficha del
-- plan sin tocar una migración.
-- ============================================================================

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- 1. LA PAUTA
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.faena_pauta (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    codigo      TEXT NOT NULL,
    nombre      TEXT NOT NULL,
    -- 'diaria' se ejecuta todos los días del turno; 'programada' vence por
    -- horómetro, kilometraje o calendario.
    tipo        TEXT NOT NULL DEFAULT 'diaria'
                CHECK (tipo IN ('diaria','programada')),
    -- A qué equipos aplica. Por modelo es lo más preciso; si el modelo es NULL
    -- aplica a todo equipo de la faena.
    modelo_id   UUID REFERENCES public.modelos(id) ON DELETE SET NULL,
    disparo_horas NUMERIC,
    disparo_km    NUMERIC,
    disparo_dias  INTEGER,
    -- Cuánto se avisa antes de que venza, para que el repuesto alcance a llegar.
    aviso_horas   NUMERIC NOT NULL DEFAULT 50,
    aviso_km      NUMERIC NOT NULL DEFAULT 1000,
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    observacion TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_faena_pauta_codigo
    ON public.faena_pauta(faena_id, lower(codigo));

COMMENT ON TABLE public.faena_pauta IS
  'Lo que hay que revisar en un equipo de faena, por modelo. Reemplaza las tres vinetas iguales de la entrega de turno del mecanico. MIG357.';


CREATE TABLE IF NOT EXISTS public.faena_pauta_item (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pauta_id    UUID NOT NULL REFERENCES public.faena_pauta(id) ON DELETE CASCADE,
    orden       INTEGER NOT NULL DEFAULT 0,
    bloque      TEXT NOT NULL DEFAULT 'General',
    texto       TEXT NOT NULL,
    ayuda       TEXT,
    -- 'ok_nok' es un tilde; 'numero' pide una lectura (horómetro, numeral,
    -- presión); 'texto' es para lo que no se puede tildar.
    tipo_respuesta TEXT NOT NULL DEFAULT 'ok_nok'
                CHECK (tipo_respuesta IN ('ok_nok','numero','texto')),
    unidad      TEXT,
    obligatorio BOOLEAN NOT NULL DEFAULT TRUE,
    -- Un NO OK sin foto es una afirmación sin respaldo, y es la que después se
    -- discute con el mandante.
    foto_si_nok BOOLEAN NOT NULL DEFAULT TRUE,
    -- Un crítico detiene el equipo: no se despacha combustible con la pértiga
    -- suelta ni con el extintor vencido.
    critico     BOOLEAN NOT NULL DEFAULT FALSE,
    -- El consumible que este ítem consume, para que el vale a bodega salga
    -- completo y no falte el filtro con el camión ya en el pozo.
    repuesto    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_faena_pauta_item_pauta
    ON public.faena_pauta_item(pauta_id, orden);

COMMENT ON COLUMN public.faena_pauta_item.repuesto IS
  'Consumible que pide el item. En julio el servicio de 300 h se hizo sin el filtro de trampa de agua porque no vino en el kit: el kit se arma desde aca. MIG357.';


-- ══════════════════════════════════════════════════════════════════════════
-- 2. LA EJECUCIÓN
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.faena_pauta_ejecucion (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    pauta_id    UUID NOT NULL REFERENCES public.faena_pauta(id) ON DELETE RESTRICT,
    activo_id   UUID NOT NULL REFERENCES public.activos(id) ON DELETE RESTRICT,
    fecha       DATE NOT NULL,
    turno       TEXT,
    estado      TEXT NOT NULL DEFAULT 'borrador'
                CHECK (estado IN ('borrador','cerrada','no_aplica')),
    horometro   NUMERIC,
    kilometraje NUMERIC,
    -- El equipo que no se pudo ver. Es una respuesta, no un hueco.
    motivo_no_aplica TEXT,
    observacion TEXT,
    ejecutado_por        UUID,
    ejecutado_por_nombre TEXT,
    iniciada_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cerrada_at  TIMESTAMPTZ,
    client_uuid TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Una pauta por equipo, por día y por turno. Si el mecánico vuelve a abrirla,
-- retoma la misma — no crea una segunda, que es el bug que MIG271 arregló en
-- las auditorías.
CREATE UNIQUE INDEX IF NOT EXISTS ux_faena_pauta_ejec_dia
    ON public.faena_pauta_ejecucion(pauta_id, activo_id, fecha, COALESCE(turno, ''));

CREATE INDEX IF NOT EXISTS ix_faena_pauta_ejec_faena
    ON public.faena_pauta_ejecucion(faena_id, fecha);


CREATE TABLE IF NOT EXISTS public.faena_pauta_ejecucion_item (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id  UUID NOT NULL REFERENCES public.faena_pauta_ejecucion(id) ON DELETE CASCADE,
    item_id       UUID NOT NULL REFERENCES public.faena_pauta_item(id) ON DELETE CASCADE,
    resultado     TEXT CHECK (resultado IN ('ok','nok','na')),
    valor         NUMERIC,
    texto         TEXT,
    observacion   TEXT,
    foto_url      TEXT,
    -- La NC que este hallazgo levantó. Que sea una columna y no una búsqueda
    -- por texto es lo que permite cerrar el círculo desde la bandeja.
    nc_id         UUID REFERENCES public.no_conformidades(id) ON DELETE SET NULL,
    respondido_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ejecucion_id, item_id)
);


-- ══════════════════════════════════════════════════════════════════════════
-- 3. QUIÉN PUEDE
-- ══════════════════════════════════════════════════════════════════════════
-- Igual que en el módulo de combustible: se pregunta por PERMISO y no por
-- rol, para que mañana se le pueda dar o quitar a alguien desde Admin →
-- Perfiles y roles sin tocar una migración.

CREATE OR REPLACE FUNCTION public.fn_faena_pauta_puede_ejecutar()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    SELECT public.fn_tiene_permiso_modulo('mantenimiento', 'create', ARRAY[
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor',
        'tecnico_mantenimiento','operador_taller'
    ]);
$f$;

COMMENT ON FUNCTION public.fn_faena_pauta_puede_ejecutar() IS
  'Quien ejecuta la pauta del mecanico en faena. MIG357.';


ALTER TABLE public.faena_pauta                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faena_pauta_item            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faena_pauta_ejecucion       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faena_pauta_ejecucion_item  ENABLE ROW LEVEL SECURITY;

DO $pol$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['faena_pauta','faena_pauta_item',
                             'faena_pauta_ejecucion','faena_pauta_ejecucion_item']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_lectura ON public.%I', t, t);
        EXECUTE format($p$CREATE POLICY pol_%s_lectura ON public.%I
                          FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL)$p$, t, t);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    END LOOP;
END $pol$;


-- ══════════════════════════════════════════════════════════════════════════
-- 4. LO QUE LE TOCA HOY AL MECÁNICO
-- ══════════════════════════════════════════════════════════════════════════
-- Una sola llamada devuelve la jornada completa: los equipos de la faena, y por
-- cada uno la pauta diaria más las programadas que ya vencieron o están por
-- vencer. El mecánico no elige qué revisar — el sistema se lo pone delante.

CREATE OR REPLACE VIEW public.v_faena_pauta_agenda AS
SELECT
    a.faena_id,
    a.id                AS activo_id,
    a.codigo            AS activo_codigo,
    a.patente,
    a.nombre            AS activo_nombre,
    a.estado            AS activo_estado,
    mo.nombre           AS modelo,
    a.horas_uso_actual,
    a.kilometraje_actual,
    p.id                AS pauta_id,
    p.codigo            AS pauta_codigo,
    p.nombre            AS pauta_nombre,
    p.tipo              AS pauta_tipo,
    p.disparo_horas,
    p.disparo_km,
    (SELECT count(*) FROM faena_pauta_item i WHERE i.pauta_id = p.id)::int AS items,
    -- Cuánto falta para el próximo servicio, contra la última ejecución
    -- registrada de ESTA pauta sobre ESTE equipo.
    ult.horometro       AS ultima_horometro,
    ult.kilometraje     AS ultima_kilometraje,
    ult.fecha           AS ultima_fecha,
    CASE WHEN p.disparo_horas IS NOT NULL AND ult.horometro IS NOT NULL
         THEN ROUND(ult.horometro + p.disparo_horas - COALESCE(a.horas_uso_actual, 0), 1)
    END                 AS faltan_horas,
    CASE WHEN p.disparo_km IS NOT NULL AND ult.kilometraje IS NOT NULL
         THEN ROUND(ult.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0), 1)
    END                 AS faltan_km
FROM public.activos a
JOIN public.faena_pauta p
      ON p.faena_id = a.faena_id
     AND p.activo
     AND (p.modelo_id IS NULL OR p.modelo_id = a.modelo_id)
LEFT JOIN public.modelos mo ON mo.id = a.modelo_id
LEFT JOIN LATERAL (
    SELECT e.horometro, e.kilometraje, e.fecha
      FROM public.faena_pauta_ejecucion e
     WHERE e.pauta_id = p.id AND e.activo_id = a.id AND e.estado = 'cerrada'
     ORDER BY e.fecha DESC, e.cerrada_at DESC
     LIMIT 1
) ult ON TRUE
WHERE a.fecha_baja IS NULL;

GRANT SELECT ON public.v_faena_pauta_agenda TO authenticated;

COMMENT ON VIEW public.v_faena_pauta_agenda IS
  'Lo que le toca revisar al mecanico, por equipo. El sistema se lo pone delante en vez de que el elija. MIG357.';


-- ══════════════════════════════════════════════════════════════════════════
-- 5. GUARDAR LA PAUTA
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rpc_faena_pauta_guardar(
    p_faena_id    uuid,
    p_pauta_id    uuid,
    p_activo_id   uuid,
    p_fecha       date,
    p_turno       text DEFAULT NULL,
    p_items       jsonb DEFAULT '[]'::jsonb,
    p_horometro   numeric DEFAULT NULL,
    p_kilometraje numeric DEFAULT NULL,
    p_observacion text DEFAULT NULL,
    p_cerrar      boolean DEFAULT false,
    p_ejecutado_por_nombre text DEFAULT NULL,
    p_no_aplica_motivo text DEFAULT NULL,
    p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_id       UUID;
    v_it       JSONB;
    v_item     RECORD;
    v_nc       UUID;
    v_faltan   TEXT[] := '{}';
    v_sin_foto TEXT[] := '{}';
    v_nok      INTEGER := 0;
    v_ncs      INTEGER := 0;
BEGIN
    IF NOT public.fn_faena_pauta_puede_ejecutar() THEN
        RAISE EXCEPTION 'La pauta de faena la ejecuta el mecánico de turno.'
            USING ERRCODE = '42501';
    END IF;

    -- Retomar, no duplicar: si ya hay una del mismo equipo, día y turno, se
    -- sigue esa.
    SELECT id INTO v_id
      FROM public.faena_pauta_ejecucion
     WHERE pauta_id = p_pauta_id AND activo_id = p_activo_id
       AND fecha = p_fecha AND COALESCE(turno, '') = COALESCE(p_turno, '');

    IF v_id IS NULL THEN
        INSERT INTO public.faena_pauta_ejecucion
               (faena_id, pauta_id, activo_id, fecha, turno, ejecutado_por,
                ejecutado_por_nombre, client_uuid)
        VALUES (p_faena_id, p_pauta_id, p_activo_id, p_fecha, p_turno, auth.uid(),
                p_ejecutado_por_nombre, p_client_uuid)
        RETURNING id INTO v_id;
    END IF;

    -- El equipo que no se pudo ver. Se cierra sin ítems y con motivo: es una
    -- respuesta, no un hueco.
    IF p_no_aplica_motivo IS NOT NULL AND length(trim(p_no_aplica_motivo)) > 0 THEN
        UPDATE public.faena_pauta_ejecucion
           SET estado = 'no_aplica', motivo_no_aplica = p_no_aplica_motivo,
               cerrada_at = NOW(), updated_at = NOW()
         WHERE id = v_id;
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'no_aplica');
    END IF;

    -- ── Las respuestas ────────────────────────────────────────────────────
    FOR v_it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
    LOOP
        INSERT INTO public.faena_pauta_ejecucion_item
               (ejecucion_id, item_id, resultado, valor, texto, observacion, foto_url)
        VALUES (v_id,
                (v_it->>'item_id')::uuid,
                NULLIF(v_it->>'resultado',''),
                NULLIF(v_it->>'valor','')::numeric,
                NULLIF(v_it->>'texto',''),
                NULLIF(v_it->>'observacion',''),
                NULLIF(v_it->>'foto_url',''))
        ON CONFLICT (ejecucion_id, item_id) DO UPDATE SET
                resultado   = EXCLUDED.resultado,
                valor       = EXCLUDED.valor,
                texto       = EXCLUDED.texto,
                observacion = EXCLUDED.observacion,
                foto_url    = COALESCE(EXCLUDED.foto_url, faena_pauta_ejecucion_item.foto_url),
                respondido_at = NOW();
    END LOOP;

    UPDATE public.faena_pauta_ejecucion
       SET horometro   = COALESCE(p_horometro, horometro),
           kilometraje = COALESCE(p_kilometraje, kilometraje),
           observacion = COALESCE(p_observacion, observacion),
           ejecutado_por_nombre = COALESCE(p_ejecutado_por_nombre, ejecutado_por_nombre),
           updated_at  = NOW()
     WHERE id = v_id;

    IF NOT p_cerrar THEN
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'borrador');
    END IF;

    -- ── Cerrar: acá es donde la pauta se pone exigente ────────────────────
    -- 1) No queda ningún obligatorio sin contestar.
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_faltan
      FROM public.faena_pauta_item i
      LEFT JOIN public.faena_pauta_ejecucion_item r
             ON r.item_id = i.id AND r.ejecucion_id = v_id
     WHERE i.pauta_id = p_pauta_id AND i.obligatorio
       AND (r.id IS NULL
            OR (i.tipo_respuesta = 'ok_nok' AND r.resultado IS NULL)
            OR (i.tipo_respuesta = 'numero' AND r.valor IS NULL)
            OR (i.tipo_respuesta = 'texto'  AND COALESCE(r.texto,'') = ''));

    IF v_faltan IS NOT NULL AND array_length(v_faltan, 1) > 0 THEN
        RAISE EXCEPTION 'Falta contestar: %', array_to_string(v_faltan[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2) Todo NO OK que pide foto la tiene. Sin foto es una afirmación sin
    --    respaldo, y es la que después se discute con el mandante.
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_sin_foto
      FROM public.faena_pauta_ejecucion_item r
      JOIN public.faena_pauta_item i ON i.id = r.item_id
     WHERE r.ejecucion_id = v_id AND r.resultado = 'nok'
       AND i.foto_si_nok AND COALESCE(r.foto_url, '') = '';

    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN
        RAISE EXCEPTION 'Estos hallazgos necesitan foto: %',
            array_to_string(v_sin_foto[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3) Cada NO OK levanta su no conformidad, una sola vez.
    FOR v_item IN
        SELECT r.id AS resp_id, r.observacion, r.foto_url, i.texto, i.critico, i.bloque
          FROM public.faena_pauta_ejecucion_item r
          JOIN public.faena_pauta_item i ON i.id = r.item_id
         WHERE r.ejecucion_id = v_id AND r.resultado = 'nok' AND r.nc_id IS NULL
    LOOP
        INSERT INTO public.no_conformidades
               (activo_id, tipo, descripcion, fecha_evento, severidad, origen,
                foto_url, registrada_por, created_by, estado_planificacion, resuelto)
        VALUES (p_activo_id, 'falla_en_terreno',
                v_item.bloque || ' · ' || v_item.texto
                  || COALESCE(' — ' || NULLIF(v_item.observacion, ''), ''),
                p_fecha,
                CASE WHEN v_item.critico THEN 'alta' ELSE 'media' END,
                'pauta_faena', v_item.foto_url, auth.uid(), auth.uid(),
                'registrada', FALSE)
        RETURNING id INTO v_nc;

        UPDATE public.faena_pauta_ejecucion_item SET nc_id = v_nc WHERE id = v_item.resp_id;
        v_ncs := v_ncs + 1;
    END LOOP;

    SELECT count(*) INTO v_nok
      FROM public.faena_pauta_ejecucion_item
     WHERE ejecucion_id = v_id AND resultado = 'nok';

    UPDATE public.faena_pauta_ejecucion
       SET estado = 'cerrada', cerrada_at = NOW(), updated_at = NOW()
     WHERE id = v_id;

    -- 4) El horómetro se tomó una vez y de acá sale para todos lados. Nunca
    --    hacia atrás: un contador que retrocede es un error de tecleo, y
    --    pisarle la ficha al activo con él arrastra el error a la mantención.
    UPDATE public.activos
       SET horas_uso_actual   = GREATEST(COALESCE(horas_uso_actual, 0),   COALESCE(p_horometro, 0)),
           kilometraje_actual = GREATEST(COALESCE(kilometraje_actual, 0), COALESCE(p_kilometraje, 0)),
           updated_at = NOW()
     WHERE id = p_activo_id
       AND (p_horometro IS NOT NULL OR p_kilometraje IS NOT NULL);

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'cerrada',
                              'hallazgos', v_nok, 'no_conformidades', v_ncs);
END;
$fn$;

REVOKE ALL ON FUNCTION public.rpc_faena_pauta_guardar(uuid,uuid,uuid,date,text,jsonb,numeric,numeric,text,boolean,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_pauta_guardar(uuid,uuid,uuid,date,text,jsonb,numeric,numeric,text,boolean,text,text,text) TO authenticated;

COMMIT;
