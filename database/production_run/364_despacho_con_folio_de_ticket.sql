-- ============================================================================
-- MIG364 · La carga se registra con su folio de ticket
-- ----------------------------------------------------------------------------
-- MIG363 le dio a la carga una columna para el folio; falta que quien despacha
-- lo pueda escribir. En Franke el ticket printer es la fuente de verdad de la
-- transacción: sin el folio, la carga registrada no se puede amarrar al papel
-- que quedó arriba del camión, y el control de continuidad no tiene con qué.
--
-- CÓMO SE AGREGA SIN ROMPER LOS TELÉFONOS QUE YA ESTÁN EN TERRENO
-- Ésta es la trampa que MIG340 tuvo que limpiar: `CREATE OR REPLACE` con una
-- firma distinta NO reemplaza la función, crea una segunda. Y como la app de
-- terreno es una PWA que vive cacheada, un teléfono desactualizado seguiría
-- llamando a la vieja — que no conoce el folio— y el dato se perdería en
-- silencio, sin error y sin aviso.
--
-- Por eso: se crea la nueva, se BORRA explícitamente la firma anterior, y el
-- parámetro va al final con valor por omisión. Un teléfono viejo llama con
-- menos argumentos, resuelve a la única función que queda y registra la carga
-- igual — sin folio, que es exactamente lo que hace hoy.
--
-- POR QUÉ SE TOCA SÓLO LA ENVOLTURA
-- El cuerpo real vive en `rpc_comb_faena_despachar_interno`, que ya está
-- probado y es compartido con Romeral. La envoltura es la que pone la puerta de
-- permisos (MIG340); acá además escribe el folio sobre la carga recién creada.
-- Menos superficie tocada, menos riesgo para la faena que ya está operando.
--
-- UN FOLIO REPETIDO DETIENE LA CARGA ENTERA
-- El índice único de MIG363 salta y la transacción completa se revierte. Es lo
-- correcto: un folio que ya se usó significa que alguien se equivocó al
-- teclearlo o que la carga ya estaba registrada. Guardar la segunda con el
-- mismo número deja dos verdades y ninguna forma de saber cuál es.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_despachar(
    p_faena_id uuid, p_fecha date, p_turno text, p_estanque_id uuid,
    p_equipo_id uuid, p_ubicacion_id uuid,
    p_meter_inicial numeric, p_meter_final numeric, p_litros numeric,
    p_operador_nombre text DEFAULT NULL::text,
    p_hora time without time zone DEFAULT NULL::time without time zone,
    p_equipo_texto text DEFAULT NULL::text,
    p_ubicacion_texto text DEFAULT NULL::text,
    p_camion_patente text DEFAULT NULL::text,
    p_horometro numeric DEFAULT NULL::numeric,
    p_kilometraje numeric DEFAULT NULL::numeric,
    p_observacion text DEFAULT NULL::text,
    p_client_uuid text DEFAULT NULL::text,
    p_foto_meter_inicial text DEFAULT NULL::text,
    p_foto_meter_final text DEFAULT NULL::text,
    p_sin_foto_motivo text DEFAULT NULL::text,
    p_ceco_texto text DEFAULT NULL::text,
    p_tipo_movimiento text DEFAULT 'venta'::text,
    p_flota text DEFAULT NULL::text,
    p_destino_estanque_id uuid DEFAULT NULL::uuid,
    p_folio_ticket integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_r  JSONB;
    v_id UUID;
BEGIN
    IF NOT public.fn_comb_puede_operar() THEN
        RAISE EXCEPTION 'No autorizado para registrar despachos de combustible.'
            USING ERRCODE = '42501';
    END IF;

    v_r := public.rpc_comb_faena_despachar_interno(
        p_faena_id, p_fecha, p_turno, p_estanque_id, p_equipo_id, p_ubicacion_id,
        p_meter_inicial, p_meter_final, p_litros, p_operador_nombre, p_hora,
        p_equipo_texto, p_ubicacion_texto, p_camion_patente, p_horometro,
        p_kilometraje, p_observacion, p_client_uuid, p_foto_meter_inicial,
        p_foto_meter_final, p_sin_foto_motivo, p_ceco_texto, p_tipo_movimiento,
        p_flota, p_destino_estanque_id);

    v_id := NULLIF(v_r->>'despacho_id', '')::uuid;

    -- Al reenviar una carga que ya se había subido (la app sin señal reintenta)
    -- el interno la reconoce por client_uuid y devuelve duplicado=true. En ese
    -- caso el folio ya está escrito y volver a escribirlo es inofensivo, pero
    -- no hay que tratarlo como error.
    IF p_folio_ticket IS NOT NULL AND v_id IS NOT NULL THEN
        BEGIN
            UPDATE public.combustible_faena_despachos
               SET folio_ticket = p_folio_ticket, updated_at = NOW()
             WHERE id = v_id;
        EXCEPTION WHEN unique_violation THEN
            RAISE EXCEPTION 'El folio % ya está registrado en esta faena. Revise el ticket: o está mal tecleado, o esta carga ya se había guardado.', p_folio_ticket
                USING ERRCODE = 'unique_violation';
        END;
    END IF;

    RETURN v_r || jsonb_build_object('folio_ticket', p_folio_ticket);
END;
$function$;

-- La firma anterior se borra a propósito: dos versiones vivas de la misma
-- función es lo que dejó a Romeral a un teléfono desactualizado de guardar un
-- trasvasije como venta.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text,
    time without time zone, text, text, text, numeric, numeric, text, text,
    text, text, text, text, text, text, uuid);

REVOKE ALL ON FUNCTION public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text,
    time without time zone, text, text, text, numeric, numeric, text, text,
    text, text, text, text, text, text, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text,
    time without time zone, text, text, text, numeric, numeric, text, text,
    text, text, text, text, text, text, uuid, integer) TO authenticated;

COMMIT;

-- ── Verificación: tiene que quedar UNA sola ───────────────────────────────
-- SELECT oid::regprocedure::text FROM pg_proc
--  WHERE proname = 'rpc_comb_faena_despachar';
