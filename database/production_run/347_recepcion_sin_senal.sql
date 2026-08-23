-- ============================================================================
-- MIG347 · La recepción del camión también se registra sin señal
-- ----------------------------------------------------------------------------
-- El camión de flota primaria llega a las 06:30. Si en ese momento no hay
-- señal, hasta ahora no había forma de registrarlo: la pantalla llamaba
-- directo al servidor. Un camión de 30.000 litros que no se registra es la
-- diferencia más cara que puede aparecer en el cierre.
--
-- El RPC ya era idempotente por client_uuid, así que la cola del teléfono
-- puede reintentar sin miedo a duplicar. Lo único que faltaba era poder
-- decirle que la recepción se tomó sin conexión, para que quede marcado igual
-- que el cierre.
-- ============================================================================

BEGIN;

ALTER TABLE public.combustible_faena_recepcion
    ADD COLUMN IF NOT EXISTS sin_senal BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.combustible_faena_recepcion.sin_senal IS
  'La recepcion se tomo en el telefono sin conexion y subio despues. MIG347.';

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_recepcion(
    p_faena_id uuid, p_fecha date, p_destinos jsonb,
    p_guia text DEFAULT NULL, p_viaje text DEFAULT NULL, p_camion text DEFAULT NULL,
    p_proveedor text DEFAULT NULL, p_litros_guia numeric DEFAULT NULL,
    p_hora time DEFAULT NULL, p_recibido_por text DEFAULT NULL,
    p_sello text DEFAULT NULL, p_observacion text DEFAULT NULL,
    p_foto_guia text DEFAULT NULL, p_sin_foto_motivo text DEFAULT NULL,
    p_confirmar boolean DEFAULT false, p_client_uuid text DEFAULT NULL,
    p_sin_senal boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out JSONB;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Recibir el camión de flota primaria le corresponde al supervisor de turno: la guía que se acepta después se paga.'
            USING ERRCODE = '42501';
    END IF;
    v_out := public.rpc_comb_faena_recepcion_interno(
        p_faena_id, p_fecha, p_destinos, p_guia, p_viaje, p_camion, p_proveedor,
        p_litros_guia, p_hora, p_recibido_por, p_sello, p_observacion,
        p_foto_guia, p_sin_foto_motivo, p_confirmar, p_client_uuid);

    IF p_sin_senal AND (v_out->>'recepcion_id') IS NOT NULL THEN
        UPDATE combustible_faena_recepcion
           SET sin_senal = true
         WHERE id = (v_out->>'recepcion_id')::uuid;
    END IF;

    RETURN v_out;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text, boolean) TO authenticated;

-- destructivo-ok: se elimina la firma anterior (sin p_sin_senal) para que no
-- queden dos versiones del RPC. No borra datos.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text);

COMMIT;
