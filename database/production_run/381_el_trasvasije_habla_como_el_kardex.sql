-- ============================================================================
-- MIG381 · El trasvasije usa las palabras que el kardex ya tenía
-- ----------------------------------------------------------------------------
-- MIG378 escribía el kardex con `trasvasije_salida` / `trasvasije_entrada` y
-- rebotaba: el CHECK del kardex sólo acepta diez tipos, y entre ellos ya están
-- `traspaso_salida` y `traspaso_entrada` desde antes.
--
-- La faena le dice trasvasije y el kardex le dice traspaso — son la misma cosa
-- y ambas palabras se quedan donde estaban: `combustible_faena_despachos`
-- sigue guardando `tipo_movimiento = 'trasvasije'`, que es como habla terreno,
-- y el kardex sigue hablando de traspasos, que es como habla contabilidad.
-- Inventar un tipo nuevo habría partido en dos el historial de un movimiento
-- que ya tenía nombre.
-- ============================================================================

BEGIN;

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
       'traspaso_salida', 'TRV-' || to_char(COALESCE(p_fecha, CURRENT_DATE), 'YYYYMMDD') || '-' || v_org.codigo,
       v_id, 0, v_litros, v_costo, v_org_despues, COALESCE(v_org.costo_promedio_lt, 0),
       v_org_despues * COALESCE(v_org.costo_promedio_lt, 0),
       NULLIF(trim(COALESCE(p_foto_final, p_foto_inicial, '')), ''),
       'Trasvasije a ' || v_des.codigo || ' · ' || COALESCE(trim(p_operador), 'sin nombre'), auth.uid()),
      (gen_random_uuid(), v_des.id, COALESCE(p_fecha, CURRENT_DATE)::timestamptz,
       'traspaso_entrada', 'TRV-' || to_char(COALESCE(p_fecha, CURRENT_DATE), 'YYYYMMDD') || '-' || v_des.codigo,
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

COMMIT;
