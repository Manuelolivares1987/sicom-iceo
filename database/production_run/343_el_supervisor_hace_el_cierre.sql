-- ============================================================================
-- MIG343 · El supervisor de turno hace el cierre, el operador sólo carga
-- ----------------------------------------------------------------------------
-- El modelo de roles queda así, que es como opera la faena:
--
--   OPERADOR DEL CAMIÓN     registra las cargas que él hace, y nada más
--   SUPERVISOR DE TURNO     recibe la flota primaria, varilla los estanques,
--                           anota los numerales, verifica lo que se hizo en el
--                           turno y firma el cierre
--   SECRETARIO TÉCNICO      carga Orpak, resuelve excepciones, emite los
--                           entregables y reabre un cierre si hay que corregir
--
-- Hasta MIG340 el operador podía además recibir el camión, varillar y firmar.
-- No es un detalle de permisos: quien despacha y quien verifica cuánto salió
-- no pueden ser la misma firma, porque el cierre es el documento con el que se
-- le rinde al mandante. Un operador que registra sus propias cargas y después
-- certifica que el estanque cuadra está firmando su propio trabajo.
--
-- LAS TRES PUERTAS, Y POR QUÉ SON TRES Y NO UNA
-- Cada una pregunta por un permiso distinto del módulo de inventario, aunque
-- hoy los tres resuelvan a listas parecidas:
--
--   fn_comb_puede_operar        -> inventario:create   registrar una carga
--   fn_comb_puede_cerrar        -> inventario:edit     recibir, medir, firmar
--   fn_comb_puede_administrar   -> inventario:approve  Orpak, reabrir, CECO
--
-- Separarlas por permiso y no por lista de roles significa que mañana se puede
-- crear un rol «supervisor de turno» y darle edit sin darle approve desde la
-- pantalla de perfiles, sin tocar una migración.
-- ============================================================================

BEGIN;

-- ── Medir, recibir y firmar: el supervisor de turno ────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_puede_cerrar()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    -- Recibir la flota primaria, varillar los estanques, anotar los numerales
    -- y firmar el cierre. NO incluye al operador del camion: el que despacha
    -- no certifica cuanto salio.
    SELECT public.fn_tiene_permiso_modulo('inventario', 'edit', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','supervisor','planificador'
    ]);
$f$;

COMMENT ON FUNCTION public.fn_comb_puede_cerrar() IS
  'Quien recibe la flota primaria, mide los estanques y firma el cierre: el supervisor de turno. El operador del camion queda fuera a proposito. MIG327, acotada en MIG343.';

-- ── La recepción de flota primaria también es del supervisor ───────────────
-- Recibir un camión de 30.000 litros es aceptar una guía que después se paga.
-- destructivo-ok: se renombra el RPC de recepcion para ponerle una puerta
-- delante, igual que se hizo con el despacho en MIG340. La implementacion no
-- se toca y no se pierde ningun dato; lo que cambia es que ahora hay que tener
-- permiso para llamarla.
ALTER FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text)
    RENAME TO rpc_comb_faena_recepcion_interno;

REVOKE ALL ON FUNCTION public.rpc_comb_faena_recepcion_interno(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text) FROM authenticated, anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_recepcion(
    p_faena_id uuid, p_fecha date, p_destinos jsonb,
    p_guia text DEFAULT NULL, p_viaje text DEFAULT NULL, p_camion text DEFAULT NULL,
    p_proveedor text DEFAULT NULL, p_litros_guia numeric DEFAULT NULL,
    p_hora time DEFAULT NULL, p_recibido_por text DEFAULT NULL,
    p_sello text DEFAULT NULL, p_observacion text DEFAULT NULL,
    p_foto_guia text DEFAULT NULL, p_sin_foto_motivo text DEFAULT NULL,
    p_confirmar boolean DEFAULT false, p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Recibir el camión de flota primaria le corresponde al supervisor de turno: la guía que se acepta después se paga.'
            USING ERRCODE = '42501';
    END IF;
    RETURN public.rpc_comb_faena_recepcion_interno(
        p_faena_id, p_fecha, p_destinos, p_guia, p_viaje, p_camion, p_proveedor,
        p_litros_guia, p_hora, p_recibido_por, p_sello, p_observacion,
        p_foto_guia, p_sin_foto_motivo, p_confirmar, p_client_uuid);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time without time zone,
    text, text, text, text, text, boolean, text) TO authenticated;

COMMIT;
