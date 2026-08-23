-- ============================================================================
-- MIG340 · Revisión previa a la entrega en terreno
-- ----------------------------------------------------------------------------
-- Antes de que la app la use gente de verdad, tres cosas que en una demo no se
-- notan y en un turno cuestan un mes de datos.
--
-- ══ 1. HABÍA DOS VERSIONES DE «REGISTRAR DESPACHO», Y LA VIEJA SIGUE VIVA ══
-- MIG318 le agregó parámetros al RPC de despacho (tipo de movimiento, CECO
-- anotado en terreno, estanque de destino). CREATE OR REPLACE con una firma
-- distinta NO reemplaza: crea una segunda función. Quedaron las dos.
--
-- Por qué importa el lunes: la app de terreno es una PWA y vive cacheada en el
-- teléfono. Un aparato que no alcance a actualizarse va a llamar a la versión
-- vieja — que no conoce el tipo de movimiento — y la columna tiene
-- DEFAULT 'venta'. O sea: un trasvasije de Mina al camión se guardaría como
-- una VENTA. Es textualmente el Ejemplo 1 del instructivo:
--
--     «Trasvasije registrado como venta. Consecuencia: el sistema descuenta
--      combustible del inventario, se genera una diferencia ficticia, el Mini
--      Cierre mostrará un faltante.»
--
-- Y el CECO que el operador anota a mano tampoco existiría: se perdería en
-- silencio, sin error, sin aviso.
--
-- ══ 2. CUALQUIER USUARIO PODÍA REGISTRAR UN DESPACHO ══════════════════════
-- El RPC sólo pedía sesión iniciada. Cualquiera de los 56 usuarios de la
-- empresa —el prevencionista, el comercial, un técnico— podía registrar un
-- despacho de combustible en Romeral. Ese registro es la evidencia con la que
-- se le cobra al mandante. Hoy hay 0 despachos en producción, así que acotar
-- ahora no le quita el acceso a nadie que lo esté usando.
--
-- ══ 3. MEDIR NO ES LO MISMO QUE ADMINISTRAR ═══════════════════════════════
-- El operador del camión tenía el mismo poder que el secretario técnico: podía
-- cargar el archivo de Orpak y reabrir un cierre ya firmado. Cargar Orpak
-- reescribe la imputación de un mes entero; reabrir un cierre cambia un
-- documento que ya se informó. Ninguna de las dos se hace desde la cabina de
-- un camión.
--
-- Firmar el cierre del día SÍ se queda con el operador, a propósito: a las
-- 18:00 el que está parado frente al estanque con la varilla en la mano es él,
-- y bloquearlo sería impedir que el día se cierre.
-- ============================================================================

BEGIN;

-- ── 1. Se va la versión vieja del despacho ─────────────────────────────────
-- destructivo-ok: se elimina una firma antigua de rpc_comb_faena_despachar que
-- quedo viva por accidente al ampliarla en MIG318. No borra datos: es una
-- funcion duplicada que, si la llama un telefono con la app cacheada, guarda
-- un trasvasije como venta y descarta el CECO anotado en terreno. La version
-- vigente (25 parametros) queda intacta.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text, time,
    text, text, text, numeric, numeric, text, text, text, text, text);

-- ── 2. Quién opera combustible en terreno ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_puede_operar()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    -- Registrar un despacho es firmar que salio combustible y a quien. Se acota
    -- a quien opera: el bodeguero entra porque en Coquimbo y Franke el
    -- combustible lo despacha bodega.
    SELECT public.fn_tiene_permiso_modulo('inventario', 'create', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','supervisor','planificador',
        'operador_combustible','bodeguero'
    ]);
$f$;

GRANT EXECUTE ON FUNCTION public.fn_comb_puede_operar() TO authenticated;

-- ── 3. Quién administra el control desde el escritorio ─────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_puede_administrar()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    -- Cargar Orpak reescribe la imputacion de un mes; reabrir un cierre cambia
    -- un documento ya informado; dar de alta un CECO decide a quien se le
    -- cobra. Es el trabajo del secretario tecnico, no el de la cabina.
    SELECT public.fn_tiene_permiso_modulo('inventario', 'approve', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','supervisor','planificador'
    ]);
$f$;

GRANT EXECUTE ON FUNCTION public.fn_comb_puede_administrar() TO authenticated;

-- ── El despacho pide permiso ───────────────────────────────────────────────
-- La implementación no se toca: se le pone una puerta delante. Reescribir un
-- RPC de 200 líneas para agregar un IF es la forma más segura de introducir un
-- error nuevo mientras se arregla uno viejo.
ALTER FUNCTION public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text,
    time without time zone, text, text, text, numeric, numeric, text, text,
    text, text, text, text, text, text, uuid)
    RENAME TO rpc_comb_faena_despachar_interno;

-- Nadie la llama directo: sólo la puerta, que corre como duena de la funcion.
REVOKE ALL ON FUNCTION public.rpc_comb_faena_despachar_interno(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text,
    time without time zone, text, text, text, numeric, numeric, text, text,
    text, text, text, text, text, text, uuid) FROM authenticated, anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_despachar(
    p_faena_id uuid, p_fecha date, p_turno text, p_estanque_id uuid,
    p_equipo_id uuid, p_ubicacion_id uuid, p_meter_inicial numeric,
    p_meter_final numeric, p_litros numeric, p_operador_nombre text DEFAULT NULL,
    p_hora time DEFAULT NULL, p_equipo_texto text DEFAULT NULL,
    p_ubicacion_texto text DEFAULT NULL, p_camion_patente text DEFAULT NULL,
    p_horometro numeric DEFAULT NULL, p_kilometraje numeric DEFAULT NULL,
    p_observacion text DEFAULT NULL, p_client_uuid text DEFAULT NULL,
    p_foto_meter_inicial text DEFAULT NULL, p_foto_meter_final text DEFAULT NULL,
    p_sin_foto_motivo text DEFAULT NULL, p_ceco_texto text DEFAULT NULL,
    p_tipo_movimiento text DEFAULT 'venta', p_flota text DEFAULT NULL,
    p_destino_estanque_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT public.fn_comb_puede_operar() THEN
        RAISE EXCEPTION 'No autorizado para registrar despachos de combustible.'
            USING ERRCODE = '42501';
    END IF;
    RETURN public.rpc_comb_faena_despachar_interno(
        p_faena_id, p_fecha, p_turno, p_estanque_id, p_equipo_id, p_ubicacion_id,
        p_meter_inicial, p_meter_final, p_litros, p_operador_nombre, p_hora,
        p_equipo_texto, p_ubicacion_texto, p_camion_patente, p_horometro,
        p_kilometraje, p_observacion, p_client_uuid, p_foto_meter_inicial,
        p_foto_meter_final, p_sin_foto_motivo, p_ceco_texto, p_tipo_movimiento,
        p_flota, p_destino_estanque_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_despachar(
    uuid, date, text, uuid, uuid, uuid, numeric, numeric, numeric, text, time,
    text, text, text, numeric, numeric, text, text, text, text, text, text,
    text, text, uuid) TO authenticated;

-- ── Orpak, alta de CECO y reapertura: sólo escritorio ──────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_orpak_dar_de_alta_cecos(p_faena_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_creados INT := 0; v_ligados INT := 0; v_usuario TEXT;
BEGIN
    IF NOT public.fn_comb_puede_administrar() THEN
        RAISE EXCEPTION 'No autorizado para dar de alta CECO.' USING ERRCODE = '42501';
    END IF;

    SELECT u.nombre_completo INTO v_usuario FROM usuarios_perfil u WHERE u.id = auth.uid();

    WITH nuevos AS (
        SELECT d.ceco_codigo AS codigo,
               public.fn_orpak_ceco_nombre(d.departamento) AS empresa
          FROM v_comb_orpak_ceco_desconocido d
         WHERE d.faena_id = p_faena_id
    ), insertados AS (
        INSERT INTO combustible_faena_cecos
            (faena_id, codigo, empresa, activo, origen, confirmado, anotado_por,
             anotado_at, observacion)
        SELECT p_faena_id, n.codigo, n.empresa, true, 'orpak', false,
               COALESCE(v_usuario, 'carga de Orpak'), NOW(),
               'Creado desde el archivo de Orpak. Revisar la razon social antes de facturar.'
          FROM nuevos n
         WHERE NOT EXISTS (SELECT 1 FROM combustible_faena_cecos c
                            WHERE c.faena_id = p_faena_id AND c.codigo = n.codigo)
        RETURNING 1
    )
    SELECT count(*) INTO v_creados FROM insertados;

    UPDATE combustible_orpak_transaccion t
       SET ceco_id = c.id
      FROM combustible_faena_cecos c
     WHERE c.faena_id = t.faena_id AND c.codigo = t.ceco_codigo AND c.activo
       AND t.faena_id = p_faena_id AND t.ceco_id IS NULL;
    GET DIAGNOSTICS v_ligados = ROW_COUNT;

    RETURN jsonb_build_object('creados', v_creados, 'transacciones_imputadas', v_ligados);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_reabrir_cierre(
    p_cierre_id uuid, p_motivo text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_estado TEXT; v_n INT;
BEGIN
    IF NOT public.fn_comb_puede_administrar() THEN
        RAISE EXCEPTION 'Reabrir un cierre firmado le corresponde al supervisor o al jefe de operaciones.'
            USING ERRCODE = '42501';
    END IF;
    IF length(trim(COALESCE(p_motivo,''))) < 10 THEN
        RAISE EXCEPTION 'Escriba por qué se reabre. Un cierre firmado ya se informó.'
            USING ERRCODE = '22023';
    END IF;

    SELECT estado, reaperturas INTO v_estado, v_n
      FROM combustible_faena_cierre WHERE id = p_cierre_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'El cierre no existe.'; END IF;
    IF v_estado <> 'firmado' THEN
        RAISE EXCEPTION 'Ese cierre no está firmado, se puede editar directamente.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE combustible_faena_cierre
       SET estado = 'borrador', reaperturas = reaperturas + 1,
           reabierto_at = NOW(), reabierto_por = auth.uid(),
           motivo_reapertura = trim(p_motivo), updated_at = NOW()
     WHERE id = p_cierre_id;

    INSERT INTO combustible_faena_cierre_bitacora (cierre_id, accion, motivo, usuario_id, usuario)
    VALUES (p_cierre_id, 'reabierto', trim(p_motivo), auth.uid(),
            (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = auth.uid()));

    RETURN jsonb_build_object('cierre_id', p_cierre_id, 'reaperturas', v_n + 1);
END;
$function$;

COMMIT;
