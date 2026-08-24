-- ============================================================================
-- MIG380 · Un estanque vacío también se declara
-- ----------------------------------------------------------------------------
-- MIG378 reventaba con el LCSX-78, que está en cero: el kardex tiene un
-- `chk_kardex_una_dimension` que exige que todo movimiento tenga entrada o
-- salida, y sólo deja pasar 0/0 cuando el tipo es 'varillaje' o 'ajuste'.
--
-- El constraint tiene razón y no se toca: un movimiento de cero litros no es un
-- movimiento. Lo que estaba mal era el tipo. Declarar un estanque vacío no es
-- un ingreso de cero litros — es un VARILLAJE que dio cero, que es exactamente
-- la palabra que el kardex ya usa para «se midió y esto es lo que había».
--
-- Así el camión vacío queda con su ancla y con su línea en el kardex, sin
-- hueco en la trazabilidad y sin un ingreso fantasma.
-- ============================================================================

BEGIN;

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

        -- [MIG380] Un estanque con litros entra al kardex como 'stock_inicial'.
        -- Uno vacío entra como 'varillaje': se midió y dio cero, que es lo único
        -- que el kardex acepta con 0 de entrada y 0 de salida — y además es la
        -- palabra correcta para lo que pasó.
        INSERT INTO public.combustible_kardex_valorizado (
            id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
            stock_inicial_id, litros_entrada, litros_salida, costo_unitario_movimiento,
            stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
            evidencia_url, observacion, created_by)
        VALUES (
            gen_random_uuid(), v_est.id, p_fecha::timestamptz,
            CASE WHEN v_litros > 0 THEN 'stock_inicial' ELSE 'varillaje' END,
            'INI-' || to_char(p_fecha, 'YYYYMMDD') || '-' || v_est.codigo,
            v_id, v_litros, 0, v_costo,
            v_litros, v_costo, v_litros * v_costo,
            NULLIF(trim(v_pt->>'foto_url'), ''),
            CASE WHEN v_litros > 0
                 THEN 'Momento cero · varilla leída por ' || trim(p_medido_por)
                 ELSE 'Momento cero · el estanque se varilló y estaba vacío · '
                      || trim(p_medido_por) END,
            auth.uid());

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

COMMIT;
