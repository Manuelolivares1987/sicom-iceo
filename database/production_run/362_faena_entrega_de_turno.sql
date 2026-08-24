-- ============================================================================
-- MIG362 · La entrega de turno deja de ser un archivo y pasa a ser un acto
-- ----------------------------------------------------------------------------
-- Hoy el turno que se va emite un PDF de diez capítulos. Nadie del turno que
-- entra firma que recibió, ni qué recibió. En un régimen 7×7 eso significa que
-- una semana entera puede correr sobre un supuesto equivocado antes de que
-- alguien lo note.
--
-- QUÉ SE FIRMA, Y POR QUÉ SON ESTAS CUATRO COSAS Y NO EL PDF
-- El PDF es el resultado; lo que se entrega es el estado de la faena. Cuatro
-- bloques, que son las cuatro preguntas que el turno entrante hace igual, de
-- palabra, apenas llega:
--
--   LOS CAMIONES   en qué estado quedan, con horómetro y kilometraje, y qué
--                  desviaciones tiene cada uno abiertas
--   LOS LITROS     cuánto hay, verificado, y con qué ticket se verificó
--   LOS PENDIENTES qué se le pidió al turno y qué hizo con cada cosa
--   LA BODEGA      si el inventario quedó cerrado
--
-- LO QUE SE FIRMA SE CONGELA
-- El bloque de camiones se guarda como fotografía del momento, no como una
-- consulta que se vuelve a correr. Un documento firmado tiene que decir lo que
-- era cierto cuando se firmó: si mañana el horómetro sube, la entrega de la
-- semana pasada no puede cambiar sola. Es el mismo criterio de MIG312 con el
-- historial de mantención.
--
-- EL TURNO NO SE ENTREGA SIN CONTESTAR LOS PENDIENTES
-- MIG344 y MIG345 ya hicieron esto para el cierre diario de Romeral: un
-- pendiente nace abierto y sigue abierto hasta que alguien lo cierra diciendo
-- qué hizo. Acá se aplica al cambio de turno, que es donde se pierde de verdad.
-- «Hecho» se explica solo; lo que necesita explicación es lo que NO se hizo,
-- porque sin motivo escrito el turno siguiente empieza de cero.
--
-- POR QUÉ EL ENTRANTE FIRMA APARTE Y PUEDE PONER REPAROS
-- Si la recepción fuera un tilde, se marcaría siempre. Que sea una firma con
-- espacio para reparos convierte «recibí» en una afirmación que cuesta algo. Y
-- el reparo es el dato más útil de todo esto: es la única vez que dos turnos
-- miran lo mismo y no coinciden.
--
-- Si el supervisor entrante no está —pasa, los vuelos se atrasan— firma el
-- Administrador de Contrato. Lo que no se puede es que firme el mismo que
-- entregó: eso es firmarse a sí mismo, y el sistema lo rechaza.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.faena_entrega_turno (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    turno_saliente TEXT NOT NULL,
    turno_entrante TEXT NOT NULL,
    desde       DATE NOT NULL,
    hasta       DATE NOT NULL,
    estado      TEXT NOT NULL DEFAULT 'abierta'
                CHECK (estado IN ('abierta','entregada','recibida')),

    -- Bloque LITROS. Se piden los dos números a propósito: el que se verificó
    -- físicamente y el que el sistema calcula. Quien captura ambos suele
    -- preguntar por qué no dan igual, y esa pregunta es el control.
    stock_fisico_lt   NUMERIC,
    stock_teorico_lt  NUMERIC,
    ticket_verificacion TEXT,
    conteo_fisico_hecho BOOLEAN NOT NULL DEFAULT FALSE,
    conteo_omitido_motivo TEXT,

    -- Bloque BODEGA.
    inventario_cerrado BOOLEAN NOT NULL DEFAULT FALSE,
    inventario_observacion TEXT,

    observacion_entrega   TEXT,
    observacion_recepcion TEXT,
    reparos               TEXT,

    entrega_por     UUID,
    entrega_nombre  TEXT,
    entrega_firma_url TEXT,
    entregado_at    TIMESTAMPTZ,

    recibe_por      UUID,
    recibe_nombre   TEXT,
    recibe_firma_url TEXT,
    recibido_at     TIMESTAMPTZ,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by  UUID,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Una entrega por faena y periodo. Si alguien vuelve a abrirla, retoma la
-- misma.
CREATE UNIQUE INDEX IF NOT EXISTS ux_faena_entrega_periodo
    ON public.faena_entrega_turno(faena_id, desde, hasta, turno_saliente);

COMMENT ON TABLE public.faena_entrega_turno IS
  'El cambio de turno como acto con dos firmas, no como PDF. Lo que se firma son cuatro cosas: camiones, litros, pendientes y bodega. MIG362.';

COMMENT ON COLUMN public.faena_entrega_turno.conteo_omitido_motivo IS
  'Por que no se hizo el conteo fisico. En julio 2026 no se hizo y se supo un mes despues, en el informe al mandante. Ahora se declara el mismo dia. MIG362.';


-- ── El estado de cada equipo, congelado al firmar ─────────────────────────
CREATE TABLE IF NOT EXISTS public.faena_entrega_equipo (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entrega_id  UUID NOT NULL REFERENCES public.faena_entrega_turno(id) ON DELETE CASCADE,
    activo_id   UUID NOT NULL REFERENCES public.activos(id) ON DELETE RESTRICT,
    -- Se copian y no se referencian: dentro de un año la patente puede haber
    -- cambiado de dueño y el documento tiene que seguir diciendo qué se entregó.
    patente     TEXT,
    equipo      TEXT,
    estado      TEXT NOT NULL DEFAULT 'operativo'
                CHECK (estado IN ('operativo','back_up','en_mantencion','fuera_de_faena','detenido')),
    horometro   NUMERIC,
    kilometraje NUMERIC,
    faltan_horas NUMERIC,
    faltan_km    NUMERIC,
    desviaciones INTEGER NOT NULL DEFAULT 0,
    desviaciones_detalle TEXT,
    observacion TEXT,
    UNIQUE (entrega_id, activo_id)
);

COMMENT ON TABLE public.faena_entrega_equipo IS
  'Fotografia del estado de cada equipo al momento de firmar la entrega. Se copia y no se referencia: un documento firmado no puede cambiar solo. MIG362.';


ALTER TABLE public.faena_entrega_turno  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faena_entrega_equipo ENABLE ROW LEVEL SECURITY;

DO $pol$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['faena_entrega_turno','faena_entrega_equipo']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_lectura ON public.%I', t, t);
        EXECUTE format($p$CREATE POLICY pol_%s_lectura ON public.%I
                          FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL)$p$, t, t);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    END LOOP;
END $pol$;


-- ══════════════════════════════════════════════════════════════════════════
-- CÓMO VA EL TURNO
-- ══════════════════════════════════════════════════════════════════════════
-- Lo que el supervisor mira en cualquier momento de la semana, y lo que el
-- documento resume al final. No hay que esperar al día 7 para saber cómo va.

CREATE OR REPLACE FUNCTION public.fn_faena_turno_resumen(
    p_faena_id uuid, p_desde date, p_hasta date, p_turno text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    SELECT jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'turno', p_turno,
      'litros', (
        SELECT jsonb_build_object(
                 'venta',         COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'venta'), 0),
                 'trasvasije',    COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'trasvasije'), 0),
                 'recirculacion', COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'recirculacion'), 0),
                 'calibracion',   COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'calibracion'), 0),
                 'total',         COALESCE(SUM(litros), 0),
                 'cargas',        count(*))
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p_faena_id AND NOT d.anulado
           AND d.fecha BETWEEN p_desde AND p_hasta
           AND (p_turno IS NULL OR d.turno = p_turno)),
      'litros_por_dia', COALESCE((
        SELECT jsonb_agg(x ORDER BY x->>'fecha')
          FROM (SELECT jsonb_build_object(
                         'fecha', d.fecha,
                         'dia',   COALESCE(SUM(d.litros) FILTER (WHERE d.turno = 'Día'), 0),
                         'noche', COALESCE(SUM(d.litros) FILTER (WHERE d.turno = 'Noche'), 0)) AS x
                  FROM combustible_faena_despachos d
                 WHERE d.faena_id = p_faena_id AND NOT d.anulado
                   AND d.tipo_movimiento = 'venta'
                   AND d.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY d.fecha) s), '[]'::jsonb),
      'pauta', (
        SELECT jsonb_build_object(
                 'ejecuciones', count(*) FILTER (WHERE e.estado = 'cerrada'),
                 'no_aplica',   count(*) FILTER (WHERE e.estado = 'no_aplica'),
                 'hallazgos',   COALESCE((SELECT count(*) FROM faena_pauta_ejecucion_item i
                                            JOIN faena_pauta_ejecucion e2 ON e2.id = i.ejecucion_id
                                           WHERE e2.faena_id = p_faena_id
                                             AND e2.fecha BETWEEN p_desde AND p_hasta
                                             AND i.resultado = 'nok'), 0))
          FROM faena_pauta_ejecucion e
         WHERE e.faena_id = p_faena_id AND e.fecha BETWEEN p_desde AND p_hasta),
      'pendientes', (
        SELECT jsonb_build_object(
                 'abiertos',    count(*),
                 'atascados',   count(*) FILTER (WHERE senal = 'atascado'),
                 'arrastrando', count(*) FILTER (WHERE senal = 'arrastrando'))
          FROM v_comb_faena_pendientes_abiertos p WHERE p.faena_id = p_faena_id)
    );
$f$;

GRANT EXECUTE ON FUNCTION public.fn_faena_turno_resumen(uuid, date, date, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- ABRIR LA ENTREGA
-- ══════════════════════════════════════════════════════════════════════════
-- Devuelve la entrega y el borrador del bloque de camiones, sacado de lo que el
-- sistema ya sabe: estado del activo, horómetro, kilometraje, cuánto falta para
-- la próxima mantención y las desviaciones que tiene abiertas. El supervisor
-- corrige lo que haga falta; no transcribe nada.

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_abrir(
    p_faena_id uuid,
    p_desde    date,
    p_hasta    date,
    p_turno_saliente text,
    p_turno_entrante text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_id UUID;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'La entrega de turno la hace el supervisor de turno.'
            USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_id FROM public.faena_entrega_turno
     WHERE faena_id = p_faena_id AND desde = p_desde AND hasta = p_hasta
       AND turno_saliente = p_turno_saliente;

    IF v_id IS NULL THEN
        INSERT INTO public.faena_entrega_turno
               (faena_id, desde, hasta, turno_saliente, turno_entrante, created_by)
        VALUES (p_faena_id, p_desde, p_hasta, p_turno_saliente, p_turno_entrante, auth.uid())
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object(
      'entrega_id', v_id,
      'entrega', (SELECT to_jsonb(e) FROM faena_entrega_turno e WHERE e.id = v_id),
      'resumen', public.fn_faena_turno_resumen(p_faena_id, p_desde, p_hasta, NULL),
      -- Lo ya guardado manda; si no hay nada, el borrador que arma el sistema.
      'equipos', COALESCE(
        (SELECT jsonb_agg(to_jsonb(q) ORDER BY q.patente)
           FROM faena_entrega_equipo q WHERE q.entrega_id = v_id),
        (SELECT jsonb_agg(jsonb_build_object(
                   'activo_id', a.id,
                   'patente',   a.patente,
                   'equipo',    COALESCE(a.nombre, a.codigo),
                   'estado',    CASE a.estado
                                  WHEN 'operativo'       THEN 'operativo'
                                  WHEN 'en_mantenimiento' THEN 'en_mantencion'
                                  ELSE 'detenido' END,
                   'horometro',   a.horas_uso_actual,
                   'kilometraje', a.kilometraje_actual,
                   'faltan_horas', ag.faltan_horas,
                   'faltan_km',    ag.faltan_km,
                   'desviaciones', COALESCE(nc.abiertas, 0),
                   'desviaciones_detalle', nc.detalle)
                 ORDER BY a.patente)
           FROM activos a
           LEFT JOIN LATERAL (
                SELECT v.faltan_horas, v.faltan_km FROM v_faena_pauta_agenda v
                 WHERE v.activo_id = a.id AND v.pauta_tipo = 'programada'
                 ORDER BY v.faltan_horas NULLS LAST, v.faltan_km NULLS LAST LIMIT 1) ag ON TRUE
           LEFT JOIN LATERAL (
                SELECT count(*)::int AS abiertas,
                       string_agg(n.descripcion, ' · ' ORDER BY n.fecha_evento DESC) AS detalle
                  FROM no_conformidades n
                 WHERE n.activo_id = a.id AND NOT n.resuelto
                   AND n.origen = 'pauta_faena') nc ON TRUE
          WHERE a.faena_id = p_faena_id AND a.fecha_baja IS NULL),
        '[]'::jsonb),
      'pendientes', COALESCE(
        (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.prioridad DESC, p.creado_at)
           FROM v_comb_faena_pendientes_abiertos p WHERE p.faena_id = p_faena_id),
        '[]'::jsonb));
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_abrir(uuid, date, date, text, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- FIRMAR LA ENTREGA
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_firmar(
    p_entrega_id uuid,
    p_nombre     text,
    p_firma_url  text,
    p_equipos    jsonb DEFAULT '[]'::jsonb,
    p_pendientes jsonb DEFAULT '[]'::jsonb,
    p_stock_fisico numeric DEFAULT NULL,
    p_ticket     text DEFAULT NULL,
    p_conteo_hecho boolean DEFAULT FALSE,
    p_conteo_omitido_motivo text DEFAULT NULL,
    p_inventario_cerrado boolean DEFAULT FALSE,
    p_inventario_observacion text DEFAULT NULL,
    p_observacion text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_e      RECORD;
    v_it     JSONB;
    v_faltan INTEGER;
    v_teo    NUMERIC;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'La entrega de turno la firma el supervisor de turno.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_e FROM public.faena_entrega_turno WHERE id = p_entrega_id;
    IF v_e IS NULL THEN RAISE EXCEPTION 'No existe esa entrega de turno.'; END IF;
    IF v_e.estado <> 'abierta' THEN
        RAISE EXCEPTION 'Esta entrega ya está %.', v_e.estado USING ERRCODE = 'check_violation';
    END IF;
    IF COALESCE(trim(p_nombre), '') = '' OR COALESCE(trim(p_firma_url), '') = '' THEN
        RAISE EXCEPTION 'Falta el nombre y la firma de quien entrega.' USING ERRCODE = 'check_violation';
    END IF;

    -- No se entrega sin decir por qué no se contó. Es exactamente lo que pasó
    -- en julio de 2026: no se hizo el conteo físico y se supo un mes después,
    -- en el informe al mandante.
    IF NOT p_conteo_hecho AND COALESCE(trim(p_conteo_omitido_motivo), '') = '' THEN
        RAISE EXCEPTION 'Si no se hizo el conteo físico de cierre, hay que decir por qué.'
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_conteo_hecho AND p_stock_fisico IS NULL THEN
        RAISE EXCEPTION 'Indique cuántos litros quedaron según el conteo físico.'
            USING ERRCODE = 'check_violation';
    END IF;

    -- ── Los pendientes: el turno que no contesta es el que rompe la cadena ──
    FOR v_it IN SELECT * FROM jsonb_array_elements(COALESCE(p_pendientes, '[]'::jsonb))
    LOOP
        IF (v_it->>'respuesta') <> 'hecho'
           AND COALESCE(trim(v_it->>'comentario'), '') = '' THEN
            RAISE EXCEPTION 'Lo que no se hizo necesita un motivo escrito: el turno que entra recibe el pendiente sin saber qué se intentó.'
                USING ERRCODE = 'check_violation';
        END IF;

        INSERT INTO public.combustible_faena_pendiente_traspaso
               (pendiente_id, fecha, turno, respuesta, comentario, respondido_por)
        VALUES ((v_it->>'pendiente_id')::uuid, v_e.hasta, v_e.turno_saliente,
                v_it->>'respuesta', NULLIF(v_it->>'comentario',''), p_nombre);

        -- «Hecho» lo cierra; lo demás sigue abierto y cruza al turno siguiente.
        IF (v_it->>'respuesta') = 'hecho' THEN
            UPDATE public.combustible_faena_pendiente
               SET estado = 'cerrado', cerrado_at = NOW(), cerrado_por = p_nombre,
                   cerrado_comentario = NULLIF(v_it->>'comentario','')
             WHERE id = (v_it->>'pendiente_id')::uuid;
        END IF;
    END LOOP;

    SELECT count(*) INTO v_faltan
      FROM v_comb_faena_pendientes_abiertos p
     WHERE p.faena_id = v_e.faena_id
       AND p.id NOT IN (SELECT (x->>'pendiente_id')::uuid
                          FROM jsonb_array_elements(COALESCE(p_pendientes,'[]'::jsonb)) x);
    IF v_faltan > 0 THEN
        RAISE EXCEPTION 'Quedan % pendiente(s) sin contestar. El turno no se entrega sin decir qué pasó con cada uno.', v_faltan
            USING ERRCODE = 'check_violation';
    END IF;

    -- ── La fotografía de los equipos ──────────────────────────────────────
    DELETE FROM public.faena_entrega_equipo WHERE entrega_id = p_entrega_id;
    INSERT INTO public.faena_entrega_equipo
           (entrega_id, activo_id, patente, equipo, estado, horometro, kilometraje,
            faltan_horas, faltan_km, desviaciones, desviaciones_detalle, observacion)
    SELECT p_entrega_id,
           (x->>'activo_id')::uuid, x->>'patente', x->>'equipo',
           COALESCE(NULLIF(x->>'estado',''), 'operativo'),
           NULLIF(x->>'horometro','')::numeric, NULLIF(x->>'kilometraje','')::numeric,
           NULLIF(x->>'faltan_horas','')::numeric, NULLIF(x->>'faltan_km','')::numeric,
           COALESCE(NULLIF(x->>'desviaciones','')::int, 0),
           NULLIF(x->>'desviaciones_detalle',''), NULLIF(x->>'observacion','')
      FROM jsonb_array_elements(COALESCE(p_equipos, '[]'::jsonb)) x;

    -- El teórico se calcula acá y se guarda junto al físico. Que los dos
    -- números queden uno al lado del otro es lo que hace que alguien pregunte.
    SELECT COALESCE(SUM(stock_teorico_lt), 0) INTO v_teo
      FROM combustible_estanques WHERE faena_id = v_e.faena_id AND activo;

    UPDATE public.faena_entrega_turno SET
        estado = 'entregada',
        stock_fisico_lt = p_stock_fisico,
        stock_teorico_lt = v_teo,
        ticket_verificacion = NULLIF(trim(p_ticket), ''),
        conteo_fisico_hecho = p_conteo_hecho,
        conteo_omitido_motivo = NULLIF(trim(p_conteo_omitido_motivo), ''),
        inventario_cerrado = p_inventario_cerrado,
        inventario_observacion = NULLIF(trim(p_inventario_observacion), ''),
        observacion_entrega = NULLIF(trim(p_observacion), ''),
        entrega_por = auth.uid(), entrega_nombre = p_nombre,
        entrega_firma_url = p_firma_url, entregado_at = NOW(), updated_at = NOW()
     WHERE id = p_entrega_id;

    RETURN jsonb_build_object('success', true, 'entrega_id', p_entrega_id,
                              'estado', 'entregada',
                              'stock_fisico', p_stock_fisico, 'stock_teorico', v_teo,
                              'diferencia', COALESCE(p_stock_fisico, 0) - v_teo);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_firmar(uuid, text, text, jsonb, jsonb, numeric, text, boolean, text, boolean, text, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- FIRMAR LA RECEPCIÓN
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_recibir(
    p_entrega_id uuid,
    p_nombre     text,
    p_firma_url  text,
    p_reparos    text DEFAULT NULL,
    p_observacion text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_e RECORD;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'La recepción del turno la firma el supervisor entrante o el Administrador de Contrato.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_e FROM public.faena_entrega_turno WHERE id = p_entrega_id;
    IF v_e IS NULL THEN RAISE EXCEPTION 'No existe esa entrega de turno.'; END IF;
    IF v_e.estado <> 'entregada' THEN
        RAISE EXCEPTION 'No se puede recibir un turno que está %.', v_e.estado
            USING ERRCODE = 'check_violation';
    END IF;
    -- Firmarse a sí mismo no es recibir.
    IF v_e.entrega_por IS NOT NULL AND v_e.entrega_por = auth.uid() THEN
        RAISE EXCEPTION 'Quien entregó el turno no puede firmar también la recepción.'
            USING ERRCODE = '42501';
    END IF;
    IF COALESCE(trim(p_nombre), '') = '' OR COALESCE(trim(p_firma_url), '') = '' THEN
        RAISE EXCEPTION 'Falta el nombre y la firma de quien recibe.' USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.faena_entrega_turno SET
        estado = 'recibida',
        recibe_por = auth.uid(), recibe_nombre = p_nombre,
        recibe_firma_url = p_firma_url, recibido_at = NOW(),
        reparos = NULLIF(trim(p_reparos), ''),
        observacion_recepcion = NULLIF(trim(p_observacion), ''),
        updated_at = NOW()
     WHERE id = p_entrega_id;

    -- Un reparo no es un comentario: es algo que el turno entrante quiere que
    -- se resuelva. Nace como pendiente, con dueño, igual que todo lo demás.
    IF COALESCE(trim(p_reparos), '') <> '' THEN
        INSERT INTO public.combustible_faena_pendiente
               (faena_id, texto, origen, pedido_por, prioridad, creado_por)
        VALUES (v_e.faena_id,
                'Reparo del turno ' || v_e.turno_entrante || ' al recibir el periodo '
                  || v_e.desde || ' al ' || v_e.hasta || ': ' || trim(p_reparos),
                'supervisor', p_nombre, 'alta', auth.uid());
    END IF;

    RETURN jsonb_build_object('success', true, 'entrega_id', p_entrega_id, 'estado', 'recibida');
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_recibir(uuid, text, text, text, text) TO authenticated;


-- ── El documento, para la oficina y para el mandante ──────────────────────
CREATE OR REPLACE VIEW public.v_faena_entrega_turno AS
SELECT e.*,
       f.codigo AS faena_codigo,
       f.nombre AS faena_nombre,
       (SELECT count(*) FROM faena_entrega_equipo q WHERE q.entrega_id = e.id)::int AS equipos,
       (SELECT COALESCE(SUM(q.desviaciones), 0) FROM faena_entrega_equipo q WHERE q.entrega_id = e.id)::int AS desviaciones,
       CASE WHEN e.stock_fisico_lt IS NOT NULL AND e.stock_teorico_lt IS NOT NULL
            THEN e.stock_fisico_lt - e.stock_teorico_lt END AS diferencia_lt
  FROM faena_entrega_turno e
  JOIN faenas f ON f.id = e.faena_id;

GRANT SELECT ON public.v_faena_entrega_turno TO authenticated;

COMMIT;
