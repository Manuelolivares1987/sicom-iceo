-- ============================================================================
-- MIG377 · Por el link también se pide que lo compren
-- ----------------------------------------------------------------------------
-- MIG376 dejó el link emitiendo vales, y probándolo apareció el dato que le
-- cambia el sentido: de los 357 productos de oficina, aseo y EPP del catálogo,
-- SÓLO 2 tienen stock. Los 117 artículos de oficina están en cero. Bodega no
-- guarda tóner ni resmas: los compra cuando alguien los pide.
--
-- O sea que un link que sólo sirva para retirar sirve para casi nada. El
-- camino que oficina va a usar de verdad es el otro: pedir que lo compren.
-- La pantalla con sesión ya tiene los dos; el link tenía uno.
--
-- LA SOLICITUD NO ES UN VALE, Y ESO SIGUE SIENDO A PROPÓSITO
-- El vale descuenta stock contra un centro de costo. Una solicitud no mueve
-- nada: es un encargo que bodega resuelve comprando, y el costo recién existe
-- cuando llega y se retira —con su vale—. Por eso acá no se pide CECO ni firma:
-- se pide qué, cuánto y para qué, y queda con nombre.
--
-- DE PASO: «Ana» NO ES UNA IDENTIFICACIÓN
-- El ingreso de MIG376 aceptaba tres letras. Un vale que dice «Ana» no
-- responsabiliza a nadie en una empresa con más de una Ana. Ahora se pide
-- nombre y apellido de verdad.
-- ============================================================================

BEGIN;

-- ── 1. Nombre y apellido, no un apodo ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_vale_ingresar(
    p_token text, p_nombre text, p_rut text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p      public.portales_vale_oficina;
    v_acceso UUID;
    v_cecos  JSONB;
    v_nom    TEXT := trim(regexp_replace(COALESCE(p_nombre, ''), '\s+', ' ', 'g'));
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;

    -- El papel sale a este nombre y es lo único que responsabiliza el gasto.
    -- Dos palabras de al menos dos letras: «Ana» no sirve, «Ana Rojas» sí.
    IF v_nom !~ '^[[:alpha:]ÁÉÍÓÚÜÑáéíóúüñ''.-]{2,}( [[:alpha:]ÁÉÍÓÚÜÑáéíóúüñ''.-]{2,})+$' THEN
        RAISE EXCEPTION 'Escriba su nombre y apellido: el vale sale a su nombre.'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.portal_vale_accesos (portal_id, nombre, rut)
    VALUES (v_p.id, v_nom, NULLIF(trim(COALESCE(p_rut, '')), ''))
    RETURNING id INTO v_acceso;

    UPDATE public.portales_vale_oficina
       SET usos = usos + 1, last_used_at = NOW()
     WHERE id = v_p.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', c.id, 'codigo', c.codigo, 'nombre', c.nombre) ORDER BY c.nombre), '[]'::jsonb)
      INTO v_cecos
      FROM public.centros_costo c
     WHERE c.id = ANY (v_p.ceco_ids) AND COALESCE(c.activo, TRUE);

    RETURN jsonb_build_object(
        'acceso_id',    v_acceso,
        'nombre',       v_nom,
        'portal',       v_p.nombre,
        'cecos',        v_cecos,
        'vigencia_hrs', v_p.vigencia_ingreso_horas,
        'max_items',    v_p.max_items_por_vale,
        'max_vales',    v_p.max_vales_por_ingreso
    );
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_portal_vale_ingresar(text, text, text) TO anon, authenticated;

-- ── 2. La solicitud también se acuerda de quién pidió ──────────────────────
ALTER TABLE public.bodega_solicitudes
    ADD COLUMN IF NOT EXISTS solicitante_nombre TEXT,
    ADD COLUMN IF NOT EXISTS portal_acceso_id   UUID REFERENCES public.portal_vale_accesos(id);

COMMENT ON COLUMN public.bodega_solicitudes.solicitante_nombre IS
    '[MIG377] Quién pidió, cuando entró por link y no tiene cuenta.';

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_solicitud_portal_con_nombre') THEN
        ALTER TABLE public.bodega_solicitudes
            ADD CONSTRAINT chk_solicitud_portal_con_nombre
            CHECK (portal_acceso_id IS NULL
                   OR COALESCE(length(trim(solicitante_nombre)), 0) >= 5);
    END IF;
END
$ck$;

-- Un pedido tiene que tener autor: con cuenta o con nombre escrito.
DO $ck2$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_solicitud_tiene_autor') THEN
        ALTER TABLE public.bodega_solicitudes
            ADD CONSTRAINT chk_solicitud_tiene_autor
            CHECK (solicitado_por IS NOT NULL
                   OR COALESCE(length(trim(solicitante_nombre)), 0) >= 5);
    END IF;
END
$ck2$;

-- ── 3. La vista muestra al de afuera igual que al de adentro ───────────────
DROP VIEW IF EXISTS public.v_bodega_solicitudes;
CREATE VIEW public.v_bodega_solicitudes AS
SELECT s.id, s.descripcion, s.cantidad, s.unidad, s.foto_url, s.observacion,
       s.no_conformidad_id, s.activo_id, s.estado, s.producto_id,
       s.area,
       a.patente, a.codigo AS activo_codigo, a.nombre AS activo_nombre,
       -- Quién pidió, tenga cuenta o haya entrado por el link.
       COALESCE(up.nombre_completo, s.solicitante_nombre) AS solicitado_por_nombre,
       COALESCE(up.cargo, CASE WHEN s.portal_acceso_id IS NOT NULL
                               THEN 'Pidió por el link' END) AS solicitado_por_cargo,
       (s.portal_acceso_id IS NOT NULL) AS por_portal,
       s.nota_bodega, s.created_at, s.atendida_en,
       ub.nombre_completo AS atendida_por_nombre,
       (CURRENT_DATE - s.created_at::date)::int AS dias_esperando
  FROM bodega_solicitudes s
  LEFT JOIN activos a ON a.id = s.activo_id
  LEFT JOIN usuarios_perfil up ON up.id = s.solicitado_por
  LEFT JOIN usuarios_perfil ub ON ub.id = s.atendida_por;

GRANT SELECT ON public.v_bodega_solicitudes TO authenticated;

-- ── 4. Pedir por el link ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_portal_solicitud_crear(
    p_token       text,
    p_acceso_id   uuid,
    p_descripcion text,
    p_cantidad    numeric DEFAULT 1,
    p_unidad      text DEFAULT NULL,
    p_area        text DEFAULT NULL,
    p_observacion text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p   public.portales_vale_oficina;
    v_acc public.portal_vale_accesos;
    v_id  UUID;
    v_n   INT;
    v_u   RECORD;
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_portal_vale_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Su ingreso caducó. Vuelva a abrir el link y a identificarse.'
            USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_acc FROM public.portal_vale_accesos WHERE id = p_acceso_id;

    IF COALESCE(length(trim(p_descripcion)), 0) < 3 THEN
        RAISE EXCEPTION 'Diga qué necesita: sin descripción bodega no tiene qué buscar.'
            USING ERRCODE = '22023';
    END IF;
    IF COALESCE(p_cantidad, 0) <= 0 THEN
        RAISE EXCEPTION 'La cantidad tiene que ser mayor que cero.' USING ERRCODE = '22023';
    END IF;

    -- Un link filtrado no puede llenarle la bandeja a bodega. El mismo tope que
    -- para los vales, contado sobre lo que este ingreso ya pidió hoy.
    SELECT count(*) INTO v_n FROM public.bodega_solicitudes
     WHERE portal_acceso_id = p_acceso_id;
    IF v_n >= GREATEST(v_p.max_items_por_vale, 5) THEN
        RAISE EXCEPTION 'Ya hizo % pedidos en este ingreso. Vuelva a entrar por el link si necesita otro.',
            v_n USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.bodega_solicitudes
        (descripcion, cantidad, unidad, observacion, solicitado_por, area,
         solicitante_nombre, portal_acceso_id)
    VALUES (trim(p_descripcion), p_cantidad, NULLIF(trim(COALESCE(p_unidad, '')), ''),
            NULLIF(trim(COALESCE(p_observacion, '')), ''), NULL,
            NULLIF(trim(COALESCE(p_area, '')), ''), v_acc.nombre, p_acceso_id)
    RETURNING id INTO v_id;

    BEGIN
        FOR v_u IN
            SELECT id FROM public.usuarios_perfil
             WHERE activo AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO public.alertas (tipo, titulo, mensaje, severidad, entidad_tipo,
                                        entidad_id, destinatario_id, leida, created_at)
            VALUES ('solicitud_bodega',
                    'Pedido de oficina: ' || left(trim(p_descripcion), 60),
                    v_acc.nombre || ' pidió ' || p_cantidad ||
                    COALESCE(' ' || NULLIF(trim(COALESCE(p_unidad, '')), ''), '') ||
                    ' por el link.' ||
                    COALESCE(' ' || NULLIF(trim(COALESCE(p_observacion, '')), ''), ''),
                    'info', 'solicitud_bodega', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', TRUE, 'solicitud_id', v_id,
                              'solicitante', v_acc.nombre);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_portal_solicitud_crear(text, uuid, text, numeric, text, text, text)
    TO anon, authenticated;

-- ── 5. Lo que uno mismo pidió por el link ──────────────────────────────────
-- Sin esto hay que llamar a bodega para saber si el pedido llegó, que es
-- exactamente lo que este portal viene a evitar.
CREATE OR REPLACE FUNCTION public.fn_portal_vale_mis_pedidos(
    p_token text, p_acceso_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p   public.portales_vale_oficina;
    v_acc public.portal_vale_accesos;
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_portal_vale_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Su ingreso caducó. Vuelva a abrir el link.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_acc FROM public.portal_vale_accesos WHERE id = p_acceso_id;

    RETURN jsonb_build_object(
        -- Los vales de este ingreso, para volver a imprimirlos.
        'vales', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                      'id', t.id, 'folio', t.folio, 'estado', t.estado,
                      'ceco_nombre', t.ceco_nombre, 'n_items', t.n_items,
                      'created_at', t.created_at) ORDER BY t.created_at DESC), '[]'::jsonb)
                    FROM public.v_bodega_ticket t
                   WHERE t.portal_acceso_id = p_acceso_id),
        -- Las compras pedidas por esta persona, aunque hayan sido en otro
        -- ingreso: para eso se guarda el nombre.
        'solicitudes', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                            'id', s.id, 'descripcion', s.descripcion,
                            'cantidad', s.cantidad, 'unidad', s.unidad,
                            'estado', s.estado, 'nota_bodega', s.nota_bodega,
                            'created_at', s.created_at) ORDER BY s.created_at DESC), '[]'::jsonb)
                          FROM public.bodega_solicitudes s
                          JOIN public.portal_vale_accesos a ON a.id = s.portal_acceso_id
                         WHERE a.portal_id = v_p.id
                           AND lower(a.nombre) = lower(v_acc.nombre)
                         LIMIT 20));
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_portal_vale_mis_pedidos(text, uuid) TO anon, authenticated;

COMMIT;
