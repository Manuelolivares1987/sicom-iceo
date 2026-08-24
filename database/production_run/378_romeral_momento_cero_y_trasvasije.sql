-- ============================================================================
-- MIG378 · Romeral: el momento cero, y cargar el camión
-- ----------------------------------------------------------------------------
-- El módulo de combustible de faena está construido desde MIG279 y NO se ha
-- usado nunca: cero despachos y cero recepciones registradas. Los litros que
-- hoy muestran los siete estanques vienen sembrados de una migración, no de
-- una varilla. Faltan las dos puntas para poder arrancar.
--
-- 1. EL MOMENTO CERO
-- Existía `rpc_registrar_stock_inicial_combustible`, pero no sirve acá: exige
-- litros > 0 (el LCSX-78 está vacío y hay que declararlo igual, si no queda sin
-- punto de partida), es de a un estanque, y no guarda ni la varilla ni quién
-- midió ni su firma. El momento cero es un acto único e irrepetible: se declara
-- una vez, con la varilla en la mano, y de ahí en adelante todo se compara
-- contra eso. Merece su propio registro.
--   · Los siete de una sola vez, en un solo lote, con una sola firma.
--   · Cero litros es una declaración válida, no un campo vacío.
--   · Foto de la varilla por estanque, o el motivo escrito de por qué no hay.
--   · Lo certifica quien puede cerrar el turno, no quien despacha: el que
--     entrega combustible no certifica cuánto había.
--
-- 2. CARGAR EL CAMIÓN
-- La recepción sólo acepta estanques fijos, y está bien: un aljibe no se llena
-- del camión proveedor, se llena por trasvasije desde una estación. Pero el
-- trasvasije estaba escondido dentro de la pantalla de despacho —había que
-- entrar por «despachar», elegir la estación como si fuera el camión del que
-- se despacha, y recién ahí marcar el destino—. Ahora tiene su propio camino.
--
-- CÓMO SE MUEVE EL STOCK DE LA FAENA (y por qué el despacho no lo baja)
-- El stock de Romeral es suyo y se mueve dentro de Romeral: no toca la bodega
-- de Coquimbo. Pero el mecanismo no es sumar y restar papeles — es la varilla.
-- `fn_comb_sincronizar_stock` lo dice textual desde MIG279: «el stock es una
-- consecuencia de la medición, no al revés». Al firmar el cierre, cada estanque
-- queda con la medida final que se leyó en terreno. En una faena con estanques
-- enterrados y camiones que van y vienen, la varilla es más confiable que la
-- suma de las boletas, y además el cierre ya cuadra tres lados: varilla,
-- contador y Orpak. Descontar además por despacho agregaría un cuarto número
-- que discutir, y no hay ninguno mejor que el que se midió.
--
-- El trasvasije es distinto y por eso sí mueve litros: no consume, REDISTRIBUYE
-- entre dos puntos de la misma faena, y el neto es cero. Si no los moviera, el
-- camión nunca tendría combustible en el sistema y «cuánto lleva el DJKL-18»
-- no tendría respuesta hasta el cierre siguiente.
--
-- Y para el rato que va entre un cierre y el otro está `v_comb_faena_estanque_ahora`:
-- estima en vivo, restando lo despachado y sumando lo recibido, SIN pisar la
-- columna que fija la varilla. Un estimado que se sabe estimado no compite con
-- la medición: la complementa.
-- ============================================================================

BEGIN;

-- ── 1. El stock inicial se acuerda de la varilla y de quién la leyó ────────
ALTER TABLE public.combustible_stock_inicial
    ADD COLUMN IF NOT EXISTS faena_id           UUID REFERENCES public.faenas(id),
    ADD COLUMN IF NOT EXISTS lote_id            UUID,
    ADD COLUMN IF NOT EXISTS medido_por_nombre  TEXT,
    ADD COLUMN IF NOT EXISTS firma_url          TEXT,
    ADD COLUMN IF NOT EXISTS lectura_varilla_cm NUMERIC,
    ADD COLUMN IF NOT EXISTS sin_foto_motivo    TEXT,
    ADD COLUMN IF NOT EXISTS client_uuid        TEXT;

COMMENT ON COLUMN public.combustible_stock_inicial.lote_id IS
    '[MIG378] Agrupa la declaración de todos los estanques de una faena en un solo acto: se varillan juntos y se firman una vez.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_inicial_client_uuid
    ON public.combustible_stock_inicial (client_uuid)
    WHERE client_uuid IS NOT NULL;

-- El RPC viejo exige litros > 0. Para el momento cero, un estanque vacío es un
-- dato tan válido como uno lleno — y no declararlo lo dejaría sin ancla.
DO $ck$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'combustible_stock_inicial_litros_iniciales_check') THEN
        ALTER TABLE public.combustible_stock_inicial
            DROP CONSTRAINT combustible_stock_inicial_litros_iniciales_check;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_stock_inicial_litros_no_negativos') THEN
        ALTER TABLE public.combustible_stock_inicial
            ADD CONSTRAINT chk_stock_inicial_litros_no_negativos
            CHECK (litros_iniciales >= 0);
    END IF;
END
$ck$;

-- ── 2. Declarar el momento cero de toda la faena ──────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_stock_inicial(
    p_faena_id    uuid,
    p_fecha       date,
    p_medido_por  text,
    p_puntos      jsonb,
    p_firma_url   text,
    p_observacion text DEFAULT NULL,
    p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_lote     UUID;
    v_pt       JSONB;
    v_est      public.combustible_estanques%ROWTYPE;
    v_litros   NUMERIC;
    v_costo    NUMERIC;
    v_id       UUID;
    v_n        INT := 0;
    v_ya       TEXT[] := '{}';
    v_faltan   TEXT[] := '{}';
    v_hechos   JSONB := '[]'::jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Sesión requerida.' USING ERRCODE = '42501';
    END IF;
    -- El momento cero es una certificación, no una medición de rutina: lo firma
    -- quien puede cerrar el turno. El operador del camión no certifica cuánto
    -- había antes de empezar.
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'El stock inicial lo certifica el supervisor de turno o jefatura.'
            USING ERRCODE = '42501';
    END IF;
    IF COALESCE(length(trim(p_medido_por)), 0) < 3 THEN
        RAISE EXCEPTION 'Escriba quién midió: el momento cero queda a su nombre.'
            USING ERRCODE = '22023';
    END IF;
    IF COALESCE(length(trim(p_firma_url)), 0) = 0 THEN
        RAISE EXCEPTION 'Falta la firma: el momento cero es lo que ancla todo el control.'
            USING ERRCODE = '22023';
    END IF;
    IF p_puntos IS NULL OR jsonb_array_length(p_puntos) = 0 THEN
        RAISE EXCEPTION 'No vino ningún estanque que declarar.' USING ERRCODE = '22023';
    END IF;

    -- Reintento del teléfono sin señal: si el lote ya entró, se devuelve igual.
    IF p_client_uuid IS NOT NULL THEN
        SELECT lote_id INTO v_lote FROM public.combustible_stock_inicial
         WHERE client_uuid = p_client_uuid LIMIT 1;
        IF v_lote IS NOT NULL THEN
            RETURN jsonb_build_object('success', TRUE, 'lote_id', v_lote, 'duplicado', TRUE);
        END IF;
    END IF;

    v_lote := gen_random_uuid();

    FOR v_pt IN SELECT * FROM jsonb_array_elements(p_puntos)
    LOOP
        SELECT * INTO v_est FROM public.combustible_estanques
         WHERE id = (v_pt->>'estanque_id')::uuid FOR UPDATE;
        IF v_est.id IS NULL THEN
            RAISE EXCEPTION 'Un estanque de la lista no existe.' USING ERRCODE = '22023';
        END IF;
        IF v_est.faena_id IS DISTINCT FROM p_faena_id THEN
            RAISE EXCEPTION 'El estanque % no es de esta faena.', v_est.codigo
                USING ERRCODE = '42501';
        END IF;

        -- Ya declarado: se salta y se dice. El momento cero no se pisa.
        IF EXISTS (SELECT 1 FROM public.combustible_stock_inicial
                    WHERE estanque_id = v_est.id AND NOT anulado) THEN
            v_ya := v_ya || v_est.codigo::text;
            CONTINUE;
        END IF;

        v_litros := COALESCE((v_pt->>'litros')::numeric, -1);
        IF v_litros < 0 THEN
            RAISE EXCEPTION 'Falta la lectura del estanque %.', v_est.codigo
                USING ERRCODE = '22023';
        END IF;
        IF v_litros > COALESCE(v_est.capacidad_lt, v_litros) THEN
            RAISE EXCEPTION 'El estanque % no puede tener % L: su capacidad es % L.',
                v_est.codigo, v_litros, v_est.capacidad_lt USING ERRCODE = '22023';
        END IF;
        -- Sin foto de la varilla hay que decir por qué: un momento cero sin
        -- respaldo ni explicación es una cifra que nadie va a poder defender.
        IF COALESCE(NULLIF(trim(v_pt->>'foto_url'), ''), '') = ''
           AND COALESCE(length(trim(v_pt->>'sin_foto_motivo')), 0) < 5 THEN
            RAISE EXCEPTION 'Falta la foto de la varilla del % (o el motivo de por qué no la hay).',
                v_est.codigo USING ERRCODE = '22023';
        END IF;

        v_costo := COALESCE((v_pt->>'costo_unitario')::numeric, v_est.costo_promedio_lt, 0);

        INSERT INTO public.combustible_stock_inicial (
            id, estanque_id, faena_id, lote_id, fecha, litros_iniciales,
            costo_unitario_inicial, documento_respaldo_url, sin_foto_motivo,
            lectura_varilla_cm, medido_por_nombre, firma_url,
            registrado_por, observacion, created_by, client_uuid)
        VALUES (
            gen_random_uuid(), v_est.id, p_faena_id, v_lote, p_fecha, v_litros,
            v_costo, NULLIF(trim(v_pt->>'foto_url'), ''),
            NULLIF(trim(v_pt->>'sin_foto_motivo'), ''),
            (v_pt->>'lectura_cm')::numeric, trim(p_medido_por), p_firma_url,
            auth.uid(),
            COALESCE(NULLIF(trim(v_pt->>'observacion'), ''),
                     NULLIF(trim(p_observacion), ''),
                     'Momento cero declarado con varilla.'),
            auth.uid(),
            CASE WHEN v_n = 0 THEN p_client_uuid END)
        RETURNING id INTO v_id;

        UPDATE public.combustible_estanques
           SET stock_teorico_lt   = v_litros,
               costo_promedio_lt  = v_costo,
               valor_total_stock  = v_litros * v_costo,
               updated_at         = NOW()
         WHERE id = v_est.id;

        INSERT INTO public.combustible_kardex_valorizado (
            id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
            stock_inicial_id, litros_entrada, litros_salida, costo_unitario_movimiento,
            stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
            evidencia_url, observacion, created_by)
        VALUES (
            gen_random_uuid(), v_est.id, p_fecha::timestamptz, 'stock_inicial',
            'INI-' || to_char(p_fecha, 'YYYYMMDD') || '-' || v_est.codigo,
            v_id, v_litros, 0, v_costo,
            v_litros, v_costo, v_litros * v_costo,
            NULLIF(trim(v_pt->>'foto_url'), ''),
            'Momento cero · varilla leída por ' || trim(p_medido_por), auth.uid());

        v_n := v_n + 1;
        v_hechos := v_hechos || jsonb_build_object('codigo', v_est.codigo, 'litros', v_litros);
    END LOOP;

    -- Los que quedaron fuera: el momento cero sirve completo, no a medias.
    SELECT COALESCE(array_agg(e.codigo::text ORDER BY e.orden_cierre NULLS LAST), '{}')
      INTO v_faltan
      FROM public.combustible_estanques e
     WHERE e.faena_id = p_faena_id AND e.activo
       AND NOT EXISTS (SELECT 1 FROM public.combustible_stock_inicial si
                        WHERE si.estanque_id = e.id AND NOT si.anulado);

    RETURN jsonb_build_object(
        'success', TRUE, 'lote_id', v_lote, 'declarados', v_n,
        'detalle', v_hechos,
        'ya_tenian', v_ya,
        'faltan', v_faltan);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_stock_inicial(uuid, date, text, jsonb, text, text, text)
    TO authenticated;

-- ── 3. El trasvasije: registra Y mueve los litros ─────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_trasvasije(
    p_faena_id     uuid,
    p_fecha        date,
    p_turno        text,
    p_origen_id    uuid,
    p_destino_id   uuid,
    p_litros       numeric,
    p_operador     text,
    p_meter_inicial numeric DEFAULT NULL,
    p_meter_final   numeric DEFAULT NULL,
    p_foto_inicial  text DEFAULT NULL,
    p_foto_final    text DEFAULT NULL,
    p_sin_foto_motivo text DEFAULT NULL,
    p_observacion  text DEFAULT NULL,
    p_hora         time DEFAULT NULL,
    p_client_uuid  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_org    public.combustible_estanques%ROWTYPE;
    v_des    public.combustible_estanques%ROWTYPE;
    v_litros NUMERIC;
    v_id     UUID;
    v_costo  NUMERIC;
    v_org_despues NUMERIC;
    v_des_despues NUMERIC;
    v_aviso  TEXT := NULL;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Sesión requerida.' USING ERRCODE = '42501';
    END IF;
    IF p_origen_id = p_destino_id THEN
        RAISE EXCEPTION 'El origen y el destino no pueden ser el mismo estanque.'
            USING ERRCODE = '22023';
    END IF;

    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM public.combustible_faena_despachos
         WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', TRUE, 'despacho_id', v_id, 'duplicado', TRUE);
        END IF;
    END IF;

    -- Se toman en orden de id para que dos trasvasijes cruzados no se traben.
    IF p_origen_id < p_destino_id THEN
        SELECT * INTO v_org FROM public.combustible_estanques WHERE id = p_origen_id FOR UPDATE;
        SELECT * INTO v_des FROM public.combustible_estanques WHERE id = p_destino_id FOR UPDATE;
    ELSE
        SELECT * INTO v_des FROM public.combustible_estanques WHERE id = p_destino_id FOR UPDATE;
        SELECT * INTO v_org FROM public.combustible_estanques WHERE id = p_origen_id FOR UPDATE;
    END IF;
    IF v_org.id IS NULL OR v_des.id IS NULL THEN
        RAISE EXCEPTION 'Falta el estanque de origen o el de destino.' USING ERRCODE = '22023';
    END IF;
    IF v_org.faena_id IS DISTINCT FROM p_faena_id OR v_des.faena_id IS DISTINCT FROM p_faena_id THEN
        RAISE EXCEPTION 'Los dos estanques tienen que ser de la misma faena.' USING ERRCODE = '42501';
    END IF;

    v_litros := COALESCE(
        CASE WHEN p_meter_final IS NOT NULL AND p_meter_inicial IS NOT NULL
                  AND p_meter_final >= p_meter_inicial
             THEN p_meter_final - p_meter_inicial END,
        p_litros);
    IF v_litros IS NULL OR v_litros <= 0 THEN
        RAISE EXCEPTION 'Indique cuántos litros pasaron.' USING ERRCODE = '22023';
    END IF;
    IF (p_foto_inicial IS NULL OR trim(p_foto_inicial) = '')
       AND COALESCE(length(trim(p_sin_foto_motivo)), 0) < 5 THEN
        RAISE EXCEPTION 'Saque la foto del medidor, o escriba por qué no pudo.'
            USING ERRCODE = '22023';
    END IF;

    -- El destino no puede recibir más de lo que le cabe.
    IF v_des.capacidad_lt IS NOT NULL
       AND COALESCE(v_des.stock_teorico_lt, 0) + v_litros > v_des.capacidad_lt THEN
        RAISE EXCEPTION 'En el % no caben % L: tiene % y su capacidad es %.',
            v_des.codigo, v_litros, COALESCE(v_des.stock_teorico_lt, 0), v_des.capacidad_lt
            USING ERRCODE = '22023';
    END IF;
    -- Que el origen quede en negativo no se bloquea —la varilla manda y el
    -- teórico puede venir corrido— pero se dice, para que quede en la bitácora.
    IF COALESCE(v_org.stock_teorico_lt, 0) < v_litros THEN
        v_aviso := 'El teórico del ' || v_org.codigo || ' queda bajo cero ('
                || COALESCE(v_org.stock_teorico_lt, 0) || ' L antes de sacar ' || v_litros
                || ' L). Revisar con la varilla en el cierre.';
    END IF;

    INSERT INTO public.combustible_faena_despachos (
        faena_id, fecha, turno, estanque_id, destino_estanque_id, tipo_movimiento,
        meter_inicial, meter_final, litros, operador_id, operador_nombre,
        observacion, hora, client_uuid, created_by,
        foto_meter_inicial_url, foto_meter_final_url, sin_foto_motivo)
    VALUES (
        p_faena_id, COALESCE(p_fecha, CURRENT_DATE), NULLIF(trim(COALESCE(p_turno, '')), ''),
        p_origen_id, p_destino_id, 'trasvasije',
        p_meter_inicial, p_meter_final, v_litros, auth.uid(),
        NULLIF(trim(COALESCE(p_operador, '')), ''),
        NULLIF(trim(COALESCE(p_observacion, '')), ''), p_hora, p_client_uuid, auth.uid(),
        NULLIF(trim(COALESCE(p_foto_inicial, '')), ''),
        NULLIF(trim(COALESCE(p_foto_final, '')), ''),
        NULLIF(trim(COALESCE(p_sin_foto_motivo, '')), ''))
    RETURNING id INTO v_id;

    -- El combustible se mueve: sale de uno y entra al otro. El neto de la faena
    -- es cero, por eso esto no contradice que el despacho no consuma stock.
    v_org_despues := COALESCE(v_org.stock_teorico_lt, 0) - v_litros;
    v_des_despues := COALESCE(v_des.stock_teorico_lt, 0) + v_litros;
    v_costo := COALESCE(v_org.costo_promedio_lt, v_des.costo_promedio_lt, 0);

    UPDATE public.combustible_estanques
       SET stock_teorico_lt = v_org_despues,
           valor_total_stock = v_org_despues * COALESCE(costo_promedio_lt, 0),
           updated_at = NOW()
     WHERE id = v_org.id;

    UPDATE public.combustible_estanques
       SET stock_teorico_lt = v_des_despues,
           -- El costo del destino se promedia: entra combustible que puede
           -- haber costado distinto al que ya tenía.
           costo_promedio_lt = CASE
               WHEN v_des_despues > 0 THEN
                   ((COALESCE(v_des.stock_teorico_lt, 0) * COALESCE(v_des.costo_promedio_lt, 0))
                    + (v_litros * v_costo)) / v_des_despues
               ELSE COALESCE(v_des.costo_promedio_lt, 0) END,
           updated_at = NOW()
     WHERE id = v_des.id;

    UPDATE public.combustible_estanques
       SET valor_total_stock = stock_teorico_lt * COALESCE(costo_promedio_lt, 0)
     WHERE id = v_des.id;

    INSERT INTO public.combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        despacho_combustible_id, litros_entrada, litros_salida,
        costo_unitario_movimiento, stock_lt_despues, costo_promedio_lt_despues,
        valor_stock_despues, evidencia_url, observacion, created_by)
    VALUES
      (gen_random_uuid(), v_org.id, COALESCE(p_fecha, CURRENT_DATE)::timestamptz,
       'trasvasije_salida', 'TRV-' || to_char(COALESCE(p_fecha, CURRENT_DATE), 'YYYYMMDD') || '-' || v_org.codigo,
       v_id, 0, v_litros, v_costo, v_org_despues, COALESCE(v_org.costo_promedio_lt, 0),
       v_org_despues * COALESCE(v_org.costo_promedio_lt, 0),
       NULLIF(trim(COALESCE(p_foto_final, p_foto_inicial, '')), ''),
       'Trasvasije a ' || v_des.codigo || ' · ' || COALESCE(trim(p_operador), 'sin nombre'), auth.uid()),
      (gen_random_uuid(), v_des.id, COALESCE(p_fecha, CURRENT_DATE)::timestamptz,
       'trasvasije_entrada', 'TRV-' || to_char(COALESCE(p_fecha, CURRENT_DATE), 'YYYYMMDD') || '-' || v_des.codigo,
       v_id, v_litros, 0, v_costo, v_des_despues,
       (SELECT COALESCE(costo_promedio_lt, 0) FROM public.combustible_estanques WHERE id = v_des.id),
       (SELECT COALESCE(valor_total_stock, 0) FROM public.combustible_estanques WHERE id = v_des.id),
       NULLIF(trim(COALESCE(p_foto_final, p_foto_inicial, '')), ''),
       'Trasvasije desde ' || v_org.codigo || ' · ' || COALESCE(trim(p_operador), 'sin nombre'), auth.uid());

    RETURN jsonb_build_object(
        'success', TRUE, 'despacho_id', v_id, 'litros', v_litros,
        'origen', v_org.codigo, 'origen_queda', v_org_despues,
        'destino', v_des.codigo, 'destino_queda', v_des_despues,
        'aviso', v_aviso);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_trasvasije(uuid, date, text, uuid, uuid, numeric, text, numeric, numeric, text, text, text, text, time, text)
    TO authenticated;

-- ── 4. Los estanques de la faena, como los ve terreno ─────────────────────
-- Con lo único que hace falta para decidir: cuánto dice el sistema que tiene,
-- cuánto le cabe, y si ya tiene momento cero declarado.
CREATE OR REPLACE VIEW public.v_comb_faena_estanques AS
SELECT e.id, e.faena_id, e.codigo, e.nombre, e.tipo, e.patente,
       e.capacidad_lt, e.stock_teorico_lt, e.costo_promedio_lt,
       e.orden_cierre, e.activo,
       (si.id IS NOT NULL)          AS tiene_momento_cero,
       si.fecha                     AS momento_cero_fecha,
       si.litros_iniciales          AS momento_cero_litros,
       si.medido_por_nombre         AS momento_cero_medido_por,
       CASE WHEN e.capacidad_lt > 0
            THEN round(100 * COALESCE(e.stock_teorico_lt, 0) / e.capacidad_lt, 1)
       END                          AS llenado_pct
  FROM public.combustible_estanques e
  LEFT JOIN LATERAL (
        SELECT s.* FROM public.combustible_stock_inicial s
         WHERE s.estanque_id = e.id AND NOT s.anulado
         ORDER BY s.fecha DESC LIMIT 1
  ) si ON TRUE
 WHERE e.faena_id IS NOT NULL;

GRANT SELECT ON public.v_comb_faena_estanques TO authenticated;

-- ── 5. Cuánto lleva ahora, entre un cierre y el otro ──────────────────────
-- La columna `stock_teorico_lt` la fija la varilla al firmar el cierre. Entre
-- medio, quien va a cargar un camión necesita saber con qué cuenta. Esto lo
-- estima a partir del último ancla —el cierre firmado, o el momento cero si
-- todavía no hay cierre— y le aplica lo que pasó después. NO escribe nada:
-- es un cálculo, y la pantalla lo muestra como estimado.
CREATE OR REPLACE VIEW public.v_comb_faena_estanque_ahora AS
WITH ancla AS (
    SELECT e.id AS estanque_id,
           COALESCE(
             (SELECT c.fecha::timestamptz
                FROM public.combustible_faena_cierre_punto p
                JOIN public.combustible_faena_cierre c ON c.id = p.cierre_id
               WHERE p.estanque_id = e.id AND c.estado = 'firmado'
                 AND NOT p.sin_medicion AND p.mf IS NOT NULL
               ORDER BY c.fecha DESC, c.created_at DESC LIMIT 1),
             (SELECT si.fecha::timestamptz FROM public.combustible_stock_inicial si
               WHERE si.estanque_id = e.id AND NOT si.anulado LIMIT 1)
           ) AS desde,
           COALESCE(
             (SELECT p.mf
                FROM public.combustible_faena_cierre_punto p
                JOIN public.combustible_faena_cierre c ON c.id = p.cierre_id
               WHERE p.estanque_id = e.id AND c.estado = 'firmado'
                 AND NOT p.sin_medicion AND p.mf IS NOT NULL
               ORDER BY c.fecha DESC, c.created_at DESC LIMIT 1),
             (SELECT si.litros_iniciales FROM public.combustible_stock_inicial si
               WHERE si.estanque_id = e.id AND NOT si.anulado LIMIT 1)
           ) AS litros_ancla,
           (SELECT c.fecha
              FROM public.combustible_faena_cierre_punto p
              JOIN public.combustible_faena_cierre c ON c.id = p.cierre_id
             WHERE p.estanque_id = e.id AND c.estado = 'firmado'
               AND NOT p.sin_medicion AND p.mf IS NOT NULL
             ORDER BY c.fecha DESC, c.created_at DESC LIMIT 1) IS NOT NULL AS ancla_es_cierre
      FROM public.combustible_estanques e
     WHERE e.faena_id IS NOT NULL
)
SELECT v.*,
       a.desde        AS medido_desde,
       a.litros_ancla,
       a.ancla_es_cierre,
       -- Lo que salió del estanque después del ancla.
       COALESCE((SELECT sum(d.litros) FROM public.combustible_faena_despachos d
                  WHERE d.estanque_id = v.id AND NOT COALESCE(d.anulado, FALSE)
                    AND (a.desde IS NULL OR d.fecha::timestamptz > a.desde)), 0) AS salido_desde,
       -- Lo que entró: trasvasijes que lo tuvieron de destino, más recepciones.
       COALESCE((SELECT sum(d.litros) FROM public.combustible_faena_despachos d
                  WHERE d.destino_estanque_id = v.id AND NOT COALESCE(d.anulado, FALSE)
                    AND (a.desde IS NULL OR d.fecha::timestamptz > a.desde)), 0)
     + COALESCE((SELECT sum(rd.litros) FROM public.combustible_faena_recepcion_destino rd
                  JOIN public.combustible_faena_recepcion r ON r.id = rd.recepcion_id
                 WHERE rd.estanque_id = v.id
                   AND (a.desde IS NULL OR r.fecha::timestamptz > a.desde)), 0) AS entrado_desde,
       (a.litros_ancla IS NOT NULL) AS estimable
  FROM public.v_comb_faena_estanques v
  JOIN ancla a ON a.estanque_id = v.id;

GRANT SELECT ON public.v_comb_faena_estanque_ahora TO authenticated;

COMMIT;
