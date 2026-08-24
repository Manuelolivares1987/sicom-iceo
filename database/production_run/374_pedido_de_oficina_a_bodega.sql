-- ============================================================================
-- MIG374 · Oficina también le pide cosas a bodega
-- ----------------------------------------------------------------------------
-- Todo lo que hoy entra a bodega viene del taller: de un hallazgo, de una OT o
-- de un pedido manual contra una patente (MIG371). Pero también se piden
-- artículos desde oficina —tóner, resmas, útiles, cosas de aseo— y para eso no
-- hay ninguna pantalla: se piden de palabra o por WhatsApp, y bodega no tiene
-- cómo saber quién pidió qué ni desde cuándo espera.
--
-- LA SOLICITUD YA EXISTÍA; LE FALTABAN DOS COSAS
-- `bodega_solicitudes` es exactamente esto y ya está enchufada a la bandeja del
-- bodeguero. Sólo se podía crear colgando de una no conformidad, así que un
-- pedido de oficina no tenía por dónde entrar. Se agregan:
--
--   · el equipo, cuando corresponde — hay pedidos de oficina que igual son para
--     una patente, y sin eso el costo no se le carga a nadie;
--   · el área que pide, porque «tóner» sin saber para quién es no se puede ni
--     priorizar ni entregar.
--
-- POR QUÉ NO UN VALE
-- El vale de bodega mueve stock del kardex contra una OT y lleva firma del jefe
-- de taller. Un pedido de oficina no es eso: es una solicitud que bodega
-- resuelve —la tiene, la compra o la rechaza—. Meterla por el vale obligaría a
-- inventarle una OT a una resma de papel, y eso ensucia el costo por equipo,
-- que es justamente lo que el vale existe para cuidar.
-- ============================================================================

BEGIN;

ALTER TABLE public.bodega_solicitudes
    ADD COLUMN IF NOT EXISTS area TEXT;

COMMENT ON COLUMN public.bodega_solicitudes.area IS
  'Para quien es el pedido: oficina, prevencion, taller, terreno. Sin esto bodega no puede ni priorizar ni saber a quien entregar. MIG374.';


-- ── Pedir, ahora también desde oficina ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_solicitar_material_bodega(
    p_descripcion character varying,
    p_cantidad numeric DEFAULT 1,
    p_nc_id uuid DEFAULT NULL::uuid,
    p_observacion text DEFAULT NULL::text,
    p_foto_url text DEFAULT NULL::text,
    p_unidad character varying DEFAULT NULL::character varying,
    -- [MIG374] Lo nuevo, al final y con valor por omisión: quien ya llamaba a
    -- esta función con seis argumentos sigue funcionando igual.
    p_activo_id uuid DEFAULT NULL::uuid,
    p_area text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_foto TEXT := p_foto_url;
    v_obs  TEXT := p_observacion;
    v_act  UUID := p_activo_id;
    v_id   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF COALESCE(TRIM(p_descripcion), '') = '' THEN
        RAISE EXCEPTION 'Diga qué necesita: sin descripción bodega no tiene qué buscar.';
    END IF;
    IF COALESCE(p_cantidad, 0) <= 0 THEN
        RAISE EXCEPTION 'La cantidad tiene que ser mayor que cero.';
    END IF;

    -- La no conformidad, cuando el pedido nace de un hallazgo, sigue mandando:
    -- trae su equipo, su foto y su descripción.
    IF p_nc_id IS NOT NULL THEN
        SELECT activo_id, foto_url, descripcion INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
        v_act  := COALESCE(v_act, v_nc.activo_id);
        v_foto := COALESCE(v_foto, v_nc.foto_url);
        v_obs  := COALESCE(v_obs, v_nc.descripcion);
    END IF;

    IF v_act IS NOT NULL AND NOT EXISTS (SELECT 1 FROM activos WHERE id = v_act) THEN
        RAISE EXCEPTION 'El equipo indicado no existe.';
    END IF;

    INSERT INTO bodega_solicitudes (descripcion, cantidad, unidad, foto_url, observacion,
        no_conformidad_id, activo_id, solicitado_por, area)
    VALUES (p_descripcion, COALESCE(p_cantidad, 1), p_unidad, v_foto, v_obs,
        p_nc_id, v_act, v_user, NULLIF(TRIM(p_area), ''))
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('solicitud_id', v_id);
END $function$;

-- La firma de seis argumentos se borra para no dejar dos versiones vivas: es la
-- trampa que MIG340 tuvo que limpiar en el despacho de combustible.
DROP FUNCTION IF EXISTS public.fn_solicitar_material_bodega(
    character varying, numeric, uuid, text, text, character varying);

REVOKE ALL ON FUNCTION public.fn_solicitar_material_bodega(
    character varying, numeric, uuid, text, text, character varying, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_solicitar_material_bodega(
    character varying, numeric, uuid, text, text, character varying, uuid, text) TO authenticated;


-- ── La bandeja del bodeguero muestra quién pide y para qué área ───────────
-- CREATE OR REPLACE no puede insertar columnas en medio: se reemplaza entera.
DROP VIEW IF EXISTS public.v_bodega_solicitudes;

CREATE VIEW public.v_bodega_solicitudes AS
SELECT s.id, s.descripcion, s.cantidad, s.unidad, s.foto_url, s.observacion,
       s.no_conformidad_id, s.activo_id, s.estado, s.producto_id,
       s.area,
       a.patente, a.codigo AS activo_codigo, a.nombre AS activo_nombre,
       up.nombre_completo AS solicitado_por_nombre,
       up.cargo AS solicitado_por_cargo,
       s.nota_bodega, s.created_at, s.atendida_en,
       ub.nombre_completo AS atendida_por_nombre,
       (CURRENT_DATE - s.created_at::date)::int AS dias_esperando
  FROM bodega_solicitudes s
  LEFT JOIN activos a ON a.id = s.activo_id
  LEFT JOIN usuarios_perfil up ON up.id = s.solicitado_por
  LEFT JOIN usuarios_perfil ub ON ub.id = s.atendida_por;

GRANT SELECT ON public.v_bodega_solicitudes TO authenticated;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT oid::regprocedure::text FROM pg_proc WHERE proname='fn_solicitar_material_bodega';
-- SELECT area, count(*) FROM bodega_solicitudes GROUP BY 1;
