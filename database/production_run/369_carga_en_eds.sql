-- ============================================================================
-- MIG369 · La carga del camión en la estación de servicio
-- ----------------------------------------------------------------------------
-- MIG363 le dio a la recepción las columnas —EDS, surtidor, folio y las dos
-- lecturas del medidor— y quedaron sin quién las escribiera. Sin ellas el
-- balance del periodo no tiene el lado de las entradas: en julio fueron 221.683
-- litros cargados, todos por el surtidor 3 de EDS Mina, y ese dato es el único
-- con el que se concilia contra la estación.
--
-- EN FRANKE EL CAMIÓN VA A LA ESTACIÓN, NO AL REVÉS
-- La recepción del módulo de faena se construyó para Romeral, donde llega un
-- camión de flota primaria con una guía que después se paga. En Franke el
-- movimiento es el mismo —combustible que entra al camión— pero el papel es
-- otro: no hay guía de proveedor, hay un ticket del surtidor. Por eso el
-- proveedor pasa a ser la EDS y la guía pasa a ser el folio.
--
-- SE PIDEN LOS DOS NÚMEROS A PROPÓSITO
-- Lo que marcó el surtidor y lo que entró según el medidor del camión. Quien
-- captura ambos suele preguntar por qué no dan igual, y esa pregunta —hecha en
-- la estación, no a fin de mes— es el control. Si se guarda uno solo, la
-- diferencia desaparece.
--
-- SE AGREGA COMO EN MIG364: firma nueva con los parámetros al final y valor por
-- omisión, y se BORRA la anterior. Dos versiones vivas de la misma función es
-- lo que casi hace que Romeral guardara un trasvasije como venta.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_recepcion(
    p_faena_id uuid, p_fecha date, p_destinos jsonb,
    p_guia text DEFAULT NULL::text,
    p_viaje text DEFAULT NULL::text,
    p_camion text DEFAULT NULL::text,
    p_proveedor text DEFAULT NULL::text,
    p_litros_guia numeric DEFAULT NULL::numeric,
    p_hora time without time zone DEFAULT NULL::time without time zone,
    p_recibido_por text DEFAULT NULL::text,
    p_sello text DEFAULT NULL::text,
    p_observacion text DEFAULT NULL::text,
    p_foto_guia text DEFAULT NULL::text,
    p_sin_foto_motivo text DEFAULT NULL::text,
    p_confirmar boolean DEFAULT false,
    p_client_uuid text DEFAULT NULL::text,
    p_sin_senal boolean DEFAULT false,
    -- [MIG369] Lo propio de una carga en estación de servicio.
    p_eds text DEFAULT NULL::text,
    p_surtidor text DEFAULT NULL::text,
    p_folio_ticket integer DEFAULT NULL::integer,
    p_meter_inicial numeric DEFAULT NULL::numeric,
    p_meter_final numeric DEFAULT NULL::numeric
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_out JSONB;
    v_id  UUID;
    v_med NUMERIC;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Registrar la carga del camión le corresponde al supervisor de turno: lo que entra es lo que después se factura.'
            USING ERRCODE = '42501';
    END IF;

    v_out := public.rpc_comb_faena_recepcion_interno(
        p_faena_id, p_fecha, p_destinos, p_guia, p_viaje, p_camion, p_proveedor,
        p_litros_guia, p_hora, p_recibido_por, p_sello, p_observacion,
        p_foto_guia, p_sin_foto_motivo, p_confirmar, p_client_uuid);

    v_id := NULLIF(v_out->>'recepcion_id', '')::uuid;

    IF p_sin_senal AND v_id IS NOT NULL THEN
        UPDATE combustible_faena_recepcion SET sin_senal = TRUE WHERE id = v_id;
    END IF;

    IF v_id IS NOT NULL AND (p_eds IS NOT NULL OR p_folio_ticket IS NOT NULL
                             OR p_meter_inicial IS NOT NULL) THEN
        UPDATE combustible_faena_recepcion SET
            eds           = COALESCE(NULLIF(trim(p_eds), ''), eds),
            surtidor      = COALESCE(NULLIF(trim(p_surtidor), ''), surtidor),
            folio_ticket  = COALESCE(p_folio_ticket, folio_ticket),
            meter_inicial = COALESCE(p_meter_inicial, meter_inicial),
            meter_final   = COALESCE(p_meter_final, meter_final),
            updated_at    = NOW()
         WHERE id = v_id;
    END IF;

    -- La diferencia entre lo que marcó el surtidor y lo que entró al camión.
    -- Va en la respuesta para que se vea en la estación, con el camión todavía
    -- ahí, y no a fin de mes cuando ya no se puede preguntar.
    IF p_meter_inicial IS NOT NULL AND p_meter_final IS NOT NULL THEN
        v_med := p_meter_final - p_meter_inicial;
    END IF;

    RETURN v_out || jsonb_build_object(
        'eds', p_eds, 'surtidor', p_surtidor, 'folio_ticket', p_folio_ticket,
        'litros_medidor', v_med,
        'diferencia_surtidor_medidor',
            CASE WHEN v_med IS NOT NULL AND p_litros_guia IS NOT NULL
                 THEN p_litros_guia - v_med END);
END;
$function$;

-- La firma anterior se borra a propósito.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric,
    time without time zone, text, text, text, text, text, boolean, text, boolean);

REVOKE ALL ON FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text, boolean,
    text, text, integer, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text, boolean,
    text, text, integer, numeric, numeric) TO authenticated;


-- ── Los puntos de carga que la faena usa ──────────────────────────────────
-- No es un catálogo nuevo: son las ubicaciones de la faena, marcadas. Que
-- estén escritas evita que cada supervisor teclee «Mina», «EDS mina» y «eds
-- Mina» y después nada agrupe.
INSERT INTO public.combustible_faena_ubicaciones (faena_id, nombre, orden)
SELECT f.id, v.nombre, v.orden
  FROM (VALUES ('EDS Mina', 900), ('EDS Planta', 910)) AS v(nombre, orden)
  CROSS JOIN public.faenas f
 WHERE f.codigo = 'FAE-FRANCKE'
ON CONFLICT (faena_id, lower(nombre)) DO NOTHING;

COMMIT;

-- ── Verificación: tiene que quedar UNA sola ───────────────────────────────
-- SELECT oid::regprocedure::text FROM pg_proc WHERE proname = 'rpc_comb_faena_recepcion';
