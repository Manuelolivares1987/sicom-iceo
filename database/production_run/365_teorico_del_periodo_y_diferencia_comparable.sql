-- ============================================================================
-- MIG365 · El teórico que se compara tiene que ser el del periodo
-- ----------------------------------------------------------------------------
-- Dos defectos que aparecieron al probar la entrega de turno de punta a punta.
-- Los dos son de la misma familia: un número que se muestra al lado de otro sin
-- que signifiquen lo mismo. Es el peor tipo de error en un documento que se
-- firma, porque no se ve — se ve una diferencia, y la diferencia parece real.
--
-- ══ 1. EL TEÓRICO SALÍA DE UNA CONTABILIDAD QUE FRANKE NO LLEVA ══════════
-- Al firmar, el stock teórico se tomaba de `combustible_estanques.stock_teorico_lt`,
-- que es el saldo del kardex de bodega. Franke nunca alimentó ese kardex: sus
-- camiones están en cero. Resultado de la prueba: 9.800 L físicos contra 0 L
-- teóricos, diferencia de 9.800 L. Un supervisor que firma eso está firmando
-- una pérdida que no existe.
--
-- El teórico correcto es el del periodo, y es el que el informe de gestión
-- calcula a mano todos los meses:
--
--     stock inicial verificado + cargas − ventas
--
-- ══ 2. UNA DIFERENCIA CONTRA UN INICIAL QUE NADIE VERIFICÓ NO ES UNA CIFRA ══
-- El balance daba «diferencia 10.600 L, 1.325 %» porque no había stock inicial
-- verificado y el cálculo lo trataba como cero. Ese porcentaje no significa
-- nada, y sin embargo es exactamente el tipo de número que termina en una
-- diapositiva.
--
-- Cuando falta el inicial verificado, el balance ahora dice que no se puede
-- comparar. Es literalmente el caso de julio de 2026: el cierre físico no se
-- hizo, y el informe igual presentó un stock final «teórico» y una diferencia.
-- Preferimos un hueco declarado a una cifra que se defiende sola.
-- ============================================================================

BEGIN;

-- ── El balance dice cuándo NO se puede comparar ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_faena_balance_periodo(
    p_faena_id uuid, p_desde date, p_hasta date
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
DECLARE
    v_ini    NUMERIC;
    v_cargas NUMERIC;
    v_ventas NUMERIC;
    v_tras   NUMERIC;
    v_otros  NUMERIC;
    v_fis    NUMERIC;
    v_teo    NUMERIC;
    v_comparable BOOLEAN;
BEGIN
    -- El stock inicial es el físico que dejó firmado la entrega anterior. Si no
    -- hay ninguna, no se inventa un cero: queda nulo y el balance lo dice.
    SELECT e.stock_fisico_lt INTO v_ini
      FROM faena_entrega_turno e
     WHERE e.faena_id = p_faena_id AND e.hasta < p_desde
       AND e.conteo_fisico_hecho AND e.stock_fisico_lt IS NOT NULL
     ORDER BY e.hasta DESC LIMIT 1;

    SELECT COALESCE(SUM(r.litros_guia), 0) INTO v_cargas
      FROM combustible_faena_recepcion r
     WHERE r.faena_id = p_faena_id AND NOT r.anulada
       AND r.fecha BETWEEN p_desde AND p_hasta;

    SELECT COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta'), 0),
           COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije'), 0),
           COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento IN ('recirculacion','calibracion')), 0)
      INTO v_ventas, v_tras, v_otros
      FROM combustible_faena_despachos d
     WHERE d.faena_id = p_faena_id AND NOT d.anulado
       AND d.fecha BETWEEN p_desde AND p_hasta;

    SELECT e.stock_fisico_lt INTO v_fis
      FROM faena_entrega_turno e
     WHERE e.faena_id = p_faena_id AND e.hasta BETWEEN p_desde AND p_hasta
       AND e.conteo_fisico_hecho AND e.stock_fisico_lt IS NOT NULL
     ORDER BY e.hasta DESC LIMIT 1;

    -- El trasvasije entre camiones del propio servicio no sale del inventario:
    -- cambia de estanque, no de dueño.
    v_teo := CASE WHEN v_ini IS NOT NULL THEN v_ini + v_cargas - v_ventas END;
    v_comparable := v_ini IS NOT NULL AND v_fis IS NOT NULL;

    RETURN jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'stock_inicial', v_ini,
      'stock_inicial_verificado', v_ini IS NOT NULL,
      'cargas', v_cargas,
      'ventas', v_ventas,
      'trasvasijes', v_tras,
      'recirculacion_calibracion', v_otros,
      'movimiento_neto', v_cargas - v_ventas,
      'stock_teorico', v_teo,
      'stock_fisico', v_fis,
      'stock_fisico_verificado', v_fis IS NOT NULL,
      'comparable', v_comparable,
      'por_que_no_comparable', CASE
          WHEN v_ini IS NULL AND v_fis IS NULL
            THEN 'No hay conteo físico verificado ni al inicio ni al cierre del periodo.'
          WHEN v_ini IS NULL
            THEN 'Falta el conteo físico de cierre del periodo anterior: sin stock inicial verificado no hay contra qué comparar.'
          WHEN v_fis IS NULL
            THEN 'Falta el conteo físico de cierre de este periodo.'
      END,
      'diferencia',     CASE WHEN v_comparable THEN v_fis - v_teo END,
      'diferencia_pct', CASE WHEN v_comparable AND v_ventas > 0
                            THEN ROUND(100.0 * (v_fis - v_teo) / v_ventas, 3) END,
      'transacciones', (SELECT count(*) FROM combustible_faena_despachos d
                         WHERE d.faena_id = p_faena_id AND NOT d.anulado
                           AND d.fecha BETWEEN p_desde AND p_hasta),
      'folios', (SELECT jsonb_build_object(
                          'desde', MIN(folio_ticket), 'hasta', MAX(folio_ticket),
                          'emitidos', count(folio_ticket),
                          'faltantes', (SELECT count(*) FROM fn_faena_folios_faltantes(p_faena_id, p_desde, p_hasta)))
                   FROM combustible_faena_despachos d
                  WHERE d.faena_id = p_faena_id AND NOT d.anulado
                    AND d.fecha BETWEEN p_desde AND p_hasta),
      'ventas_por_ceco', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('ceco', c.codigo, 'empresa', c.empresa, 'litros', s.lt)
                         ORDER BY s.lt DESC)
          FROM (SELECT d.ceco_id, SUM(d.litros) AS lt
                  FROM combustible_faena_despachos d
                 WHERE d.faena_id = p_faena_id AND NOT d.anulado
                   AND d.tipo_movimiento = 'venta'
                   AND d.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY d.ceco_id) s
          LEFT JOIN combustible_faena_cecos c ON c.id = s.ceco_id), '[]'::jsonb));
END;
$f$;


-- ── Al firmar, el teórico es el del periodo ───────────────────────────────
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
    v_bal    JSONB;
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

    IF NOT p_conteo_hecho AND COALESCE(trim(p_conteo_omitido_motivo), '') = '' THEN
        RAISE EXCEPTION 'Si no se hizo el conteo físico de cierre, hay que decir por qué.'
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_conteo_hecho AND p_stock_fisico IS NULL THEN
        RAISE EXCEPTION 'Indique cuántos litros quedaron según el conteo físico.'
            USING ERRCODE = 'check_violation';
    END IF;

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

    -- [MIG365] El teórico del PERIODO, no el saldo del kardex de bodega —que en
    -- Franke está en cero porque esa contabilidad nunca se alimentó—. Si no hay
    -- stock inicial verificado, el teórico queda nulo: no hay contra qué
    -- comparar, y eso se dice en vez de mostrar una diferencia inventada.
    v_bal := public.fn_faena_balance_periodo(v_e.faena_id, v_e.desde, v_e.hasta);
    v_teo := NULLIF(v_bal->>'stock_teorico', '')::numeric;

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

    -- El balance se calculó ANTES de escribir el conteo de esta entrega, así
    -- que su explicación todavía no lo conoce. Acá sí: lo que falta, si falta,
    -- es el inicial.
    RETURN jsonb_build_object(
        'success', true, 'entrega_id', p_entrega_id, 'estado', 'entregada',
        'stock_fisico', p_stock_fisico,
        'stock_teorico', v_teo,
        'comparable', v_teo IS NOT NULL AND p_stock_fisico IS NOT NULL,
        'por_que_no_comparable', CASE
            WHEN p_stock_fisico IS NULL
              THEN 'No se hizo el conteo físico de cierre de este periodo.'
            WHEN v_teo IS NULL
              THEN 'Falta el conteo físico de cierre del periodo anterior: sin stock inicial verificado no hay contra qué comparar. El de hoy queda registrado y sirve de inicial para el próximo turno.'
        END,
        'diferencia', CASE WHEN v_teo IS NOT NULL AND p_stock_fisico IS NOT NULL
                           THEN p_stock_fisico - v_teo END);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_firmar(uuid, text, text, jsonb, jsonb, numeric, text, boolean, text, boolean, text, text) TO authenticated;

COMMIT;
