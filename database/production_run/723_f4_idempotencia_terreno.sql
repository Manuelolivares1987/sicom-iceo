-- ============================================================================
-- MIG723 — F4: lo que sube desde terreno no se duplica ni se pierde (20-11-2026)
-- ----------------------------------------------------------------------------
-- Con mala señal el teléfono manda, la respuesta se pierde y vuelve a mandar.
-- El servidor tiene que reconocer «esto ya lo recibí» (el doble ✓ de WhatsApp)
-- en vez de duplicarlo o rechazarlo:
--   · Entrega de turno: firmar, recibir y declarar llevan el identificador del
--     teléfono (p_client_uuid). El reintento del mismo teléfono se da por
--     hecho; si la firmó OTRA persona, se rechaza diciendo quién y cuándo.
--     FOR UPDATE: dos envíos simultáneos no corren a la vez.
--   · Abrir la entrega sin señal: el teléfono trae su id (p_id) y una
--     plantilla bajada con señal (rpc_faena_entrega_plantilla, solo lectura).
--   · Pauta: un borrador que llega tarde no pisa la pauta ya cerrada; sin
--     carrera entre dos envíos del mismo cierre.
-- ============================================================================

ALTER TABLE public.faena_entrega_turno
  ADD COLUMN IF NOT EXISTS entrega_client_uuid UUID,
  ADD COLUMN IF NOT EXISTS recibe_client_uuid  UUID;

DROP FUNCTION IF EXISTS public.rpc_faena_entrega_abrir(uuid, date, date, text, text);
DROP FUNCTION IF EXISTS public.rpc_faena_entrega_declarar(uuid, jsonb, boolean, jsonb, boolean, text, text);
DROP FUNCTION IF EXISTS public.rpc_faena_entrega_firmar(uuid, text, text, jsonb, jsonb, numeric, text, boolean, text, boolean, text, text);
DROP FUNCTION IF EXISTS public.rpc_faena_entrega_recibir(uuid, text, text, text, text);

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_abrir(p_faena_id uuid, p_desde date, p_hasta date, p_turno_saliente text, p_turno_entrante text, p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        -- [MIG723] El teléfono que la abrió sin señal trae su propio id. Si otro
        -- la abrió antes, gana la que ya existe y el teléfono se acomoda a esa.
        INSERT INTO public.faena_entrega_turno
               (id, faena_id, desde, hasta, turno_saliente, turno_entrante, created_by)
        VALUES (COALESCE(p_id, gen_random_uuid()), p_faena_id, p_desde, p_hasta, p_turno_saliente, p_turno_entrante, auth.uid())
        ON CONFLICT (faena_id, desde, hasta, turno_saliente) DO NOTHING
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            SELECT id INTO v_id FROM public.faena_entrega_turno
             WHERE faena_id = p_faena_id AND desde = p_desde AND hasta = p_hasta
               AND turno_saliente = p_turno_saliente;
        END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_declarar(p_entrega_id uuid, p_camiones jsonb, p_terceros_hubo boolean, p_terceros jsonb, p_seguridad_sin_novedad boolean, p_seguridad_detalle text, p_verbal_modo text, p_client_uuid uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_e        faena_entrega_turno;
    v_faltan   TEXT;
    v_total    NUMERIC;
    v_t        RECORD;
    v_ns       UUID := 'c0f1e2d3-0697-4f00-8000-000000000697';
BEGIN
    SELECT * INTO v_e FROM faena_entrega_turno WHERE id = p_entrega_id FOR UPDATE;
    IF v_e.id IS NULL OR NOT fn_faena_comunicacion_puede(v_e.faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF v_e.estado <> 'abierta' THEN
        -- [MIG723] Reintento del mismo teléfono (se perdió la respuesta): ya está.
        IF p_client_uuid IS NOT NULL AND v_e.entrega_client_uuid = p_client_uuid THEN
            RETURN jsonb_build_object('ok', true, 'litros_total', v_e.stock_fisico_lt, 'ya_registrada', true);
        END IF;
        RAISE EXCEPTION 'La entrega ya la firmó % (%); no se puede cambiar lo declarado.',
            coalesce(v_e.entrega_nombre, 'otra persona'), to_char(v_e.entregado_at AT TIME ZONE 'America/Santiago', 'DD-MM HH24:MI')
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_terceros_hubo IS NULL THEN RAISE EXCEPTION 'Responda si se abasteció a otra empresa en el turno (sí o no).'; END IF;
    IF p_seguridad_sin_novedad IS NULL THEN RAISE EXCEPTION 'Responda la sección de seguridad.'; END IF;
    IF NOT p_seguridad_sin_novedad AND length(btrim(coalesce(p_seguridad_detalle, ''))) < 10 THEN
        RAISE EXCEPTION 'Describa la novedad de seguridad (mínimo 10 caracteres).';
    END IF;
    IF p_terceros_hubo AND coalesce(jsonb_array_length(p_terceros), 0) = 0 THEN
        RAISE EXCEPTION 'Dijo que se abasteció a otra empresa: agregue cada abastecimiento (empresa, litros, quién autorizó).';
    END IF;

    -- Litros por camión: todos los camiones-estanque activos de la faena.
    DELETE FROM faena_entrega_combustible WHERE entrega_id = p_entrega_id;
    INSERT INTO faena_entrega_combustible (entrega_id, estanque_id, patente, litros_teorico, litros_fisico, metodo, nota)
    SELECT p_entrega_id, s.id, s.patente, round(s.stock_teorico_lt, 1), x.litros, coalesce(x.metodo, 'cuentalitros'), nullif(btrim(x.nota), '')
      FROM jsonb_to_recordset(coalesce(p_camiones, '[]'::jsonb)) AS x(estanque_id UUID, litros NUMERIC, metodo TEXT, nota TEXT)
      JOIN v_comb_faena_estanque_ahora s ON s.id = x.estanque_id AND s.faena_id = v_e.faena_id
     WHERE x.litros IS NOT NULL;
    SELECT string_agg(coalesce(s.patente, s.codigo), ', ') INTO v_faltan
      FROM v_comb_faena_estanque_ahora s
     WHERE s.faena_id = v_e.faena_id AND s.activo
       AND NOT EXISTS (SELECT 1 FROM faena_entrega_combustible c WHERE c.entrega_id = p_entrega_id AND c.estanque_id = s.id);
    IF v_faltan IS NOT NULL THEN RAISE EXCEPTION 'Falta indicar con cuántos litros queda: %.', v_faltan; END IF;
    SELECT sum(litros_fisico) INTO v_total FROM faena_entrega_combustible WHERE entrega_id = p_entrega_id;

    DELETE FROM faena_entrega_terceros WHERE entrega_id = p_entrega_id;
    IF p_terceros_hubo THEN
        INSERT INTO faena_entrega_terceros (entrega_id, fecha, empresa, equipo, litros, desde_camion, autorizado_por, documento, nota)
        SELECT p_entrega_id, x.fecha, btrim(x.empresa), nullif(btrim(x.equipo), ''), x.litros, nullif(btrim(x.desde_camion), ''),
               btrim(x.autorizado_por), nullif(btrim(x.documento), ''), nullif(btrim(x.nota), '')
          FROM jsonb_to_recordset(p_terceros) AS x(fecha DATE, empresa TEXT, equipo TEXT, litros NUMERIC, desde_camion TEXT,
                                                    autorizado_por TEXT, documento TEXT, nota TEXT);
    END IF;

    UPDATE faena_entrega_turno
       SET terceros_hubo = p_terceros_hubo, seguridad_sin_novedad = p_seguridad_sin_novedad,
           seguridad_detalle = CASE WHEN p_seguridad_sin_novedad THEN NULL ELSE btrim(p_seguridad_detalle) END,
           verbal_modo = p_verbal_modo, declarado_at = NOW(),
           stock_fisico_lt = v_total, conteo_fisico_hecho = true, updated_at = NOW()
     WHERE id = p_entrega_id;

    -- A la bitácora, para que el otro turno lo lea (uuid determinístico = idempotente).
    IF p_terceros_hubo THEN
        FOR v_t IN SELECT * FROM faena_entrega_terceros WHERE entrega_id = p_entrega_id LOOP
            PERFORM rpc_faena_novedad_crear(v_e.faena_id, 'combustible', 'importante',
                format('Abastecimiento a otra empresa: %s%s, %s L%s. Autorizó: %s.', v_t.empresa,
                       coalesce(' (' || v_t.equipo || ')', ''), trim(to_char(v_t.litros, 'FM999G999D0')),
                       coalesce(' desde ' || v_t.desde_camion, ''), v_t.autorizado_por),
                NULL, NULL, NULL, md5(v_ns::text || p_entrega_id::text || v_t.empresa || v_t.litros::text)::uuid);
        END LOOP;
    END IF;
    IF NOT p_seguridad_sin_novedad THEN
        PERFORM rpc_faena_novedad_crear(v_e.faena_id, 'seguridad', 'importante',
            'Seguridad (entrega de turno): ' || btrim(p_seguridad_detalle), NULL, NULL, NULL,
            md5(v_ns::text || p_entrega_id::text || 'seguridad')::uuid);
    END IF;
    RETURN jsonb_build_object('ok', true, 'litros_total', v_total);
END $function$;

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_firmar(p_entrega_id uuid, p_nombre text, p_firma_url text, p_equipos jsonb DEFAULT '[]'::jsonb, p_pendientes jsonb DEFAULT '[]'::jsonb, p_stock_fisico numeric DEFAULT NULL::numeric, p_ticket text DEFAULT NULL::text, p_conteo_hecho boolean DEFAULT false, p_conteo_omitido_motivo text DEFAULT NULL::text, p_inventario_cerrado boolean DEFAULT false, p_inventario_observacion text DEFAULT NULL::text, p_observacion text DEFAULT NULL::text, p_client_uuid uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    -- [MIG723] FOR UPDATE: dos envíos del mismo teléfono (reintento con mala
    -- señal) no corren a la vez; el segundo ve la entrega ya firmada.
    SELECT * INTO v_e FROM public.faena_entrega_turno WHERE id = p_entrega_id FOR UPDATE;
    IF v_e.id IS NULL THEN RAISE EXCEPTION 'No existe esa entrega de turno.'; END IF;
    IF v_e.estado <> 'abierta' THEN
        IF p_client_uuid IS NOT NULL AND v_e.entrega_client_uuid = p_client_uuid THEN
            RETURN jsonb_build_object(
                'success', true, 'entrega_id', p_entrega_id, 'estado', v_e.estado, 'ya_registrada', true,
                'stock_fisico', v_e.stock_fisico_lt, 'stock_teorico', v_e.stock_teorico_lt,
                'comparable', v_e.stock_teorico_lt IS NOT NULL AND v_e.stock_fisico_lt IS NOT NULL,
                'por_que_no_comparable', NULL,
                'diferencia', CASE WHEN v_e.stock_teorico_lt IS NOT NULL AND v_e.stock_fisico_lt IS NOT NULL
                                   THEN v_e.stock_fisico_lt - v_e.stock_teorico_lt END);
        END IF;
        RAISE EXCEPTION 'Esta entrega ya está % (firmó % el %).', v_e.estado, coalesce(v_e.entrega_nombre, 'otra persona'),
            to_char(v_e.entregado_at AT TIME ZONE 'America/Santiago', 'DD-MM HH24:MI') USING ERRCODE = 'check_violation';
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
        entrega_firma_url = p_firma_url, entregado_at = NOW(), updated_at = NOW(),
        entrega_client_uuid = p_client_uuid
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
$function$;

CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_recibir(p_entrega_id uuid, p_nombre text, p_firma_url text, p_reparos text DEFAULT NULL::text, p_observacion text DEFAULT NULL::text, p_client_uuid uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_e RECORD;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'La recepción del turno la firma el supervisor entrante o el Administrador de Contrato.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_e FROM public.faena_entrega_turno WHERE id = p_entrega_id FOR UPDATE;
    IF v_e.id IS NULL THEN RAISE EXCEPTION 'No existe esa entrega de turno.'; END IF;
    -- [MIG723] Reintento del mismo teléfono: ya quedó recibida.
    IF v_e.estado = 'recibida' AND p_client_uuid IS NOT NULL AND v_e.recibe_client_uuid = p_client_uuid THEN
        RETURN jsonb_build_object('success', true, 'entrega_id', p_entrega_id, 'estado', 'recibida', 'ya_registrada', true);
    END IF;
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
        recibe_client_uuid = p_client_uuid,
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
$function$;

CREATE OR REPLACE FUNCTION public.rpc_faena_pauta_guardar(p_faena_id uuid, p_pauta_id uuid, p_activo_id uuid, p_fecha date, p_turno text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb, p_horometro numeric DEFAULT NULL::numeric, p_kilometraje numeric DEFAULT NULL::numeric, p_observacion text DEFAULT NULL::text, p_cerrar boolean DEFAULT false, p_ejecutado_por_nombre text DEFAULT NULL::text, p_no_aplica_motivo text DEFAULT NULL::text, p_client_uuid text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id       UUID;
    v_it       JSONB;
    v_item     RECORD;
    v_nc       UUID;
    v_faltan   TEXT[] := '{}';
    v_sin_foto TEXT[] := '{}';
    v_nok      INTEGER := 0;
    v_ncs      INTEGER := 0;
    v_estado   TEXT;
BEGIN
    IF NOT public.fn_faena_pauta_puede_ejecutar() THEN
        RAISE EXCEPTION 'La pauta de faena la ejecuta el mecánico de turno.'
            USING ERRCODE = '42501';
    END IF;

    -- Retomar, no duplicar: si ya hay una del mismo equipo, día y turno, se
    -- sigue esa.
    -- [MIG723] Sin carrera: dos envíos a la vez (reintento con mala señal)
    -- terminan en la misma ejecución, y el segundo espera al primero.
    INSERT INTO public.faena_pauta_ejecucion
           (faena_id, pauta_id, activo_id, fecha, turno, ejecutado_por,
            ejecutado_por_nombre, client_uuid)
    VALUES (p_faena_id, p_pauta_id, p_activo_id, p_fecha, p_turno, auth.uid(),
            p_ejecutado_por_nombre, p_client_uuid)
    ON CONFLICT (pauta_id, activo_id, fecha, (COALESCE(turno, ''::text))) DO NOTHING;

    SELECT id, estado INTO v_id, v_estado
      FROM public.faena_pauta_ejecucion
     WHERE pauta_id = p_pauta_id AND activo_id = p_activo_id
       AND fecha = p_fecha AND COALESCE(turno, '') = COALESCE(p_turno, '')
     FOR UPDATE;

    -- [MIG723] Un borrador que sube tarde (estaba en la cola sin señal) no
    -- pisa una pauta que ya se cerró: se da por recibido y no cambia nada.
    IF v_estado IN ('cerrada', 'no_aplica') AND NOT p_cerrar
       AND COALESCE(trim(p_no_aplica_motivo), '') = '' THEN
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', v_estado, 'sin_cambios', true);
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
            OR (i.tipo_respuesta = 'texto'  AND COALESCE(r.texto,'') = '')
            OR (i.tipo_respuesta = 'firma'  AND COALESCE(r.foto_url,'') = ''));

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

    -- 2b) [MIG721] El registro: foto del tablero, foto de lo realizado y firma.
    --     Lo mismo que pide el taller de Coquimbo. Sin registro no se cierra.
    v_sin_foto := NULL;
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_sin_foto
      FROM public.faena_pauta_item i
      JOIN public.faena_pauta_ejecucion_item r ON r.item_id = i.id AND r.ejecucion_id = v_id
     WHERE i.pauta_id = p_pauta_id AND i.foto_obligatoria
       AND (r.resultado IS NOT NULL OR r.valor IS NOT NULL OR i.tipo_respuesta = 'firma')
       AND COALESCE(r.foto_url, '') = '';

    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN
        RAISE EXCEPTION 'Falta el registro (foto o firma) de: %',
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
$function$;

-- Plantilla para abrir la entrega SIN señal. Solo lectura: lo mismo que
-- devolvería abrir + contexto para un periodo que todavía no existe.
CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_plantilla(p_faena_id uuid, p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'La entrega de turno la hace el supervisor de turno.' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object(
      'resumen', public.fn_faena_turno_resumen(p_faena_id, p_desde, p_hasta, NULL),
      'equipos', COALESCE(
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
        '[]'::jsonb),
      'contexto', jsonb_build_object(
        'camiones', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                        'estanque_id', s.id, 'patente', s.patente, 'nombre', s.nombre, 'capacidad', s.capacidad_lt,
                        'teorico', round(s.stock_teorico_lt), 'estimable', s.estimable,
                        'fisico', NULL, 'metodo', NULL, 'nota', NULL) ORDER BY s.orden_cierre NULLS LAST, s.codigo), '[]'::jsonb)
                       FROM v_comb_faena_estanque_ahora s
                      WHERE s.faena_id = p_faena_id AND s.activo),
        'terceros_hubo', NULL,
        'terceros', '[]'::jsonb,
        'ventas_registradas', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', v.fecha, 'cliente', v.cliente_nombre,
                                  'equipo', v.equipo_codigo, 'litros', v.litros) ORDER BY v.fecha), '[]'::jsonb)
                                 FROM combustible_ventas_franke v
                                WHERE v.fecha::date BETWEEN p_desde AND p_hasta),
        'despachos_sin_equipo', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', d.fecha, 'equipo', d.equipo_texto,
                                    'litros', d.litros, 'camion', d.camion_patente) ORDER BY d.fecha), '[]'::jsonb)
                                   FROM combustible_faena_despachos d
                                  WHERE d.faena_id = p_faena_id AND NOT coalesce(d.anulado, false) AND d.equipo_id IS NULL
                                    AND coalesce(d.tipo_movimiento, 'despacho') = 'despacho'
                                    AND d.fecha BETWEEN p_desde AND p_hasta),
        'seguridad_sin_novedad', NULL,
        'seguridad_detalle', NULL,
        'novedades_seguridad', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha_hora', n.fecha_hora, 'autor', n.autor_nombre,
                                   'severidad', n.severidad, 'texto', n.texto) ORDER BY n.fecha_hora), '[]'::jsonb)
                                  FROM faena_novedades n
                                 WHERE n.faena_id = p_faena_id AND (n.categoria = 'seguridad' OR n.severidad = 'critica')
                                   AND (n.fecha_hora AT TIME ZONE 'America/Santiago')::date BETWEEN p_desde AND p_hasta),
        'verbal_modo', NULL));
END $function$;

REVOKE ALL ON FUNCTION public.rpc_faena_entrega_abrir(uuid, date, date, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_abrir(uuid, date, date, text, text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_declarar(uuid, jsonb, boolean, jsonb, boolean, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_declarar(uuid, jsonb, boolean, jsonb, boolean, text, text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_firmar(uuid, text, text, jsonb, jsonb, numeric, text, boolean, text, boolean, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_firmar(uuid, text, text, jsonb, jsonb, numeric, text, boolean, text, boolean, text, text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_recibir(uuid, text, text, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_recibir(uuid, text, text, text, text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_plantilla(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_plantilla(uuid, date, date) TO authenticated;

NOTIFY pgrst, 'reload schema';
SELECT 'MIG723 ok' AS resultado;
