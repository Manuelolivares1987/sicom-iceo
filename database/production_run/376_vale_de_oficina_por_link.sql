-- ============================================================================
-- MIG376 · El vale de oficina se saca por un link, sin cuenta
-- ----------------------------------------------------------------------------
-- MIG375 dejó a oficina emitiendo su vale, pero exige sesión. La gente que pide
-- tóner, resmas o cloro lo hace una vez al mes: crearle y mantenerle una cuenta
-- a cada uno cuesta más que el pedido. Este link se reenvía por WhatsApp y sale
-- el mismo papel.
--
-- LO QUE NO SE TRANSA: EL VALE TIENE NOMBRE
-- El vale existe para que el gasto quede con responsable y con centro de costo.
-- Un link anónimo lo dejaría con la mitad. Por eso, igual que el portal de
-- prevención de Romeral (MIG308/313), antes de pedir hay que decir quién es
-- uno, y ese nombre es el que se imprime en el papel y queda en la base.
-- No es tan fuerte como una cuenta —nadie verifica el RUT— pero es el mismo
-- control que ya se aceptó para el portal de prevención, y es infinitamente
-- más que el actual, que es de palabra.
--
-- EL LINK SALE MÁS APRETADO QUE LA PANTALLA CON SESIÓN
--   · Sólo las categorías que el token trae escritas (por omisión artículos de
--     oficina y aseo). Un repuesto de equipo no se puede cargar al CECO de
--     administración ni por error ni a propósito — cosa que hoy, con sesión,
--     sí se puede.
--   · Sólo los centros de costo que el token trae escritos.
--   · Sin texto libre: el vale descuenta stock, y no se descuenta lo que no
--     está en el catálogo. Lo que no aparece, no se pide por aquí.
--   · Tope de ítems por vale y de vales por ingreso, para que un link filtrado
--     no se convierta en una llave del pañol.
--
-- LA FIRMA VIAJA EN EL RPC, NO AL STORAGE
-- El bucket de firmas sólo acepta escritura de usuarios con sesión. Abrirlo a
-- anónimos para esto sería regalar un hosting público. El PNG del pad son unos
-- pocos KB: viaja como data URL dentro de la llamada, que ya va validada por
-- token, y se guarda en la misma columna que las demás firmas.
--
-- ORIGEN SIGUE SIENDO 'oficina'
-- El vale del portal ES un vale de oficina; lo único distinto es por dónde
-- entró. Manteniendo el origen, todo lo que MIG375 ya construyó —el papel
-- impreso, el panel de bodega, v_consumo_por_ceco— funciona sin tocar nada.
-- Lo que dice que vino de afuera es portal_acceso_id.
-- ============================================================================

BEGIN;

-- ── 1. El token y su alcance ───────────────────────────────────────────────
-- El token es una credencial: quien lo lee puede repartirlo. Por eso la fila
-- guarda escrito hasta dónde llega, y no depende de quién la use.
CREATE TABLE IF NOT EXISTS public.portales_vale_oficina (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token                  TEXT NOT NULL UNIQUE,
    nombre                 TEXT NOT NULL,
    -- A qué centros de costo puede cargar. Vacío = ninguno, no = todos.
    ceco_ids               UUID[] NOT NULL DEFAULT '{}',
    -- Qué familias del catálogo puede pedir.
    categorias             TEXT[] NOT NULL
                           DEFAULT ARRAY['articulos_de_oficina',
                                         'implementos_de_aseo_y_fungibles'],
    -- De dónde retira. NULL = la bodega que tenga el stock.
    bodega_id              UUID REFERENCES public.bodegas(id),
    activo                 BOOLEAN NOT NULL DEFAULT TRUE,
    expira_at              TIMESTAMPTZ,
    vigencia_ingreso_horas INT NOT NULL DEFAULT 12,
    max_items_por_vale     INT NOT NULL DEFAULT 15,
    max_vales_por_ingreso  INT NOT NULL DEFAULT 3,
    usos                   INT NOT NULL DEFAULT 0,
    last_used_at           TIMESTAMPTZ,
    observacion            TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by             UUID REFERENCES public.usuarios_perfil(id),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Quién entró por el link. Sin esto el vale tendría centro de costo pero no
-- responsable, que es justamente lo que el papel viene a resolver.
CREATE TABLE IF NOT EXISTS public.portal_vale_accesos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    portal_id   UUID NOT NULL REFERENCES public.portales_vale_oficina(id) ON DELETE CASCADE,
    nombre      TEXT NOT NULL,
    rut         TEXT,
    entrada_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    vales       INT NOT NULL DEFAULT 0,
    ip_hint     TEXT
);

CREATE INDEX IF NOT EXISTS idx_portal_vale_accesos_portal
    ON public.portal_vale_accesos (portal_id, entrada_at DESC);

ALTER TABLE public.portales_vale_oficina ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.portal_vale_accesos   ENABLE ROW LEVEL SECURITY;

-- El externo NUNCA consulta estas tablas: su token va en la URL y todo pasa por
-- funciones SECURITY DEFINER. Adentro las ve quien administra bodega.
DO $rls$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='portales_vale_oficina'
                      AND policyname='portales_vale_oficina_interno') THEN
        CREATE POLICY portales_vale_oficina_interno ON public.portales_vale_oficina
            FOR ALL TO authenticated
            USING (public.fn_tiene_permiso_modulo('bodega', 'ver',
                       ARRAY['administrador','bodeguero','operador_abastecimiento']))
            WITH CHECK (public.fn_tiene_permiso_modulo('bodega', 'editar',
                       ARRAY['administrador','bodeguero','operador_abastecimiento']));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='portal_vale_accesos'
                      AND policyname='portal_vale_accesos_interno') THEN
        CREATE POLICY portal_vale_accesos_interno ON public.portal_vale_accesos
            FOR SELECT TO authenticated
            USING (public.fn_tiene_permiso_modulo('bodega', 'ver',
                       ARRAY['administrador','bodeguero','operador_abastecimiento']));
    END IF;
END
$rls$;

-- ── 2. El vale se acuerda de quién lo pidió ────────────────────────────────
ALTER TABLE public.bodega_tickets
    ADD COLUMN IF NOT EXISTS solicitante_nombre TEXT,
    ADD COLUMN IF NOT EXISTS solicitante_rut    TEXT,
    ADD COLUMN IF NOT EXISTS portal_acceso_id   UUID REFERENCES public.portal_vale_accesos(id);

COMMENT ON COLUMN public.bodega_tickets.solicitante_nombre IS
    '[MIG376] Quién pidió, cuando entró por link y no tiene cuenta. El papel imprime esto donde el del taller imprime al jefe.';

-- Un vale que vino del portal tiene que decir de quién es: sin cuenta y sin
-- nombre escrito, el gasto quedaría sin responsable.
DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bodega_ticket_portal_con_nombre') THEN
        ALTER TABLE public.bodega_tickets
            ADD CONSTRAINT chk_bodega_ticket_portal_con_nombre
            CHECK (portal_acceso_id IS NULL
                   OR COALESCE(length(trim(solicitante_nombre)), 0) >= 3);
    END IF;
END
$ck$;

-- ── 3. La vista expone al solicitante ──────────────────────────────────────
-- CREATE OR REPLACE no puede meter columnas en medio de la lista.
DROP VIEW IF EXISTS public.v_bodega_ticket;
CREATE VIEW public.v_bodega_ticket AS
SELECT tk.id, tk.folio, tk.qr_code, tk.ot_id, tk.activo_id, tk.bodega_id, tk.estado,
       tk.emitido_por, tk.firma_jefe_url, tk.observacion, tk.entregado_por, tk.entregado_at,
       tk.created_at, tk.origen, tk.motivo,
       tk.ceco_id, cc.codigo AS ceco_codigo, cc.nombre AS ceco_nombre,
       tk.solicitante_nombre, tk.solicitante_rut,
       tk.portal_acceso_id, (tk.portal_acceso_id IS NOT NULL) AS por_portal,
       -- Quién responde por el vale, venga de donde venga.
       COALESCE(up.nombre_completo, tk.solicitante_nombre) AS pedido_por_nombre,
       ot.folio AS ot_folio,
       COALESCE(ot.faena_id, a.faena_id) AS faena_id,
       a.codigo AS activo_codigo, a.nombre AS activo_nombre, a.patente AS activo_patente,
       up.nombre_completo AS emitido_por_nombre,
       ub.nombre_completo AS entregado_por_nombre,
       (SELECT count(*) FROM bodega_ticket_items i WHERE i.ticket_id = tk.id) AS n_items,
       (SELECT count(*) FROM bodega_ticket_items i
         WHERE i.ticket_id = tk.id AND i.cantidad_entregada >= i.cantidad_solicitada) AS n_entregados,
       (SELECT count(*) FROM bodega_ticket_items i
         WHERE i.ticket_id = tk.id AND i.producto_id IS NULL) AS n_sin_producto
  FROM bodega_tickets tk
  LEFT JOIN ordenes_trabajo ot ON ot.id = tk.ot_id
  LEFT JOIN activos a ON a.id = tk.activo_id
  LEFT JOIN centros_costo cc ON cc.id = tk.ceco_id
  LEFT JOIN usuarios_perfil up ON up.id = tk.emitido_por
  LEFT JOIN usuarios_perfil ub ON ub.id = tk.entregado_por;

GRANT SELECT ON public.v_bodega_ticket TO authenticated;

-- ── 4. Resolver el token (interno, no se expone) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_vale_resolver(p_token text)
RETURNS public.portales_vale_oficina
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
    SELECT p.* FROM public.portales_vale_oficina p
     WHERE p.token = p_token
       AND p.activo
       AND (p.expira_at IS NULL OR p.expira_at > NOW())
     LIMIT 1;
$fn$;

-- ── 5. Un ingreso vigente ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_vale_acceso_vigente(
    p_portal public.portales_vale_oficina, p_acceso_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
    SELECT EXISTS (
        SELECT 1 FROM public.portal_vale_accesos a
         WHERE a.id = p_acceso_id
           AND a.portal_id = p_portal.id
           AND a.entrada_at > NOW() - make_interval(hours => p_portal.vigencia_ingreso_horas)
    );
$fn$;

-- ── 6. Lo que se ve antes de identificarse ─────────────────────────────────
-- Sólo el nombre del portal. Ni los CECO ni el catálogo salen de aquí: si el
-- link se filtra, quien lo abra no aprende nada de la operación.
CREATE OR REPLACE FUNCTION public.fn_portal_vale_publico(p_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_p public.portales_vale_oficina;
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RETURN jsonb_build_object('valido', FALSE);
    END IF;
    RETURN jsonb_build_object('valido', TRUE, 'portal', v_p.nombre);
END;
$fn$;

-- ── 7. Entrar diciendo quién es uno ────────────────────────────────────────
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
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF length(trim(COALESCE(p_nombre, ''))) < 3 THEN
        RAISE EXCEPTION 'Escriba su nombre y apellido: el vale sale a su nombre.'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.portal_vale_accesos (portal_id, nombre, rut)
    VALUES (v_p.id, trim(p_nombre), NULLIF(trim(COALESCE(p_rut, '')), ''))
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
        'nombre',       trim(p_nombre),
        'portal',       v_p.nombre,
        'cecos',        v_cecos,
        'vigencia_hrs', v_p.vigencia_ingreso_horas,
        'max_items',    v_p.max_items_por_vale,
        'max_vales',    v_p.max_vales_por_ingreso
    );
END;
$fn$;

-- ── 8. El catálogo que el token deja ver ───────────────────────────────────
-- Devuelve código, nombre y unidad. NUNCA el costo: el buscador con sesión lo
-- trae en la respuesta aunque no lo pinte, y eso sin sesión sería regalar la
-- lista de precios completa.
CREATE OR REPLACE FUNCTION public.fn_portal_vale_catalogo(
    p_token text, p_acceso_id uuid, p_q text)
RETURNS TABLE (id uuid, codigo text, nombre text, unidad_medida text, hay_stock boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p public.portales_vale_oficina;
    v_q TEXT;
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_portal_vale_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Su ingreso caducó. Vuelva a abrir el link.' USING ERRCODE = '42501';
    END IF;

    v_q := trim(COALESCE(p_q, ''));
    IF length(v_q) < 2 THEN RETURN; END IF;

    RETURN QUERY
    SELECT pr.id,
           pr.codigo::text,
           pr.nombre::text,
           pr.unidad_medida::text,
           EXISTS (SELECT 1 FROM public.stock_bodega s
                    WHERE s.producto_id = pr.id
                      AND s.cantidad > 0
                      AND (v_p.bodega_id IS NULL OR s.bodega_id = v_p.bodega_id))
      FROM public.productos pr
     WHERE pr.categoria = ANY (v_p.categorias)
       AND (pr.nombre ILIKE '%' || v_q || '%' OR pr.codigo ILIKE '%' || v_q || '%')
     ORDER BY pr.nombre
     LIMIT 12;
END;
$fn$;

-- ── 9. Emitir el vale ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_portal_vale_crear(
    p_token       text,
    p_acceso_id   uuid,
    p_ceco_id     uuid,
    p_items       jsonb,
    p_motivo      text,
    p_firma       text,
    p_observacion text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p       public.portales_vale_oficina;
    v_acc     public.portal_vale_accesos;
    v_ceco    RECORD;
    v_bodega  UUID;
    v_folio   TEXT;
    v_periodo TEXT;
    v_sec     INT;
    v_id      UUID;
    v_qr      TEXT;
    v_n       INT := 0;
    v_it      JSONB;
    v_prod    UUID;
    v_u       RECORD;
BEGIN
    -- ══ Las puertas ══════════════════════════════════════════════════════
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_acc FROM public.portal_vale_accesos WHERE id = p_acceso_id;
    IF NOT public.fn_portal_vale_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Su ingreso caducó. Vuelva a abrir el link y a identificarse.'
            USING ERRCODE = '42501';
    END IF;
    IF v_acc.vales >= v_p.max_vales_por_ingreso THEN
        RAISE EXCEPTION 'Ya emitió % vales en este ingreso. Vuelva a entrar por el link si necesita otro.',
            v_acc.vales USING ERRCODE = '42501';
    END IF;

    IF p_firma IS NULL OR length(trim(p_firma)) = 0 THEN
        RAISE EXCEPTION 'Falta su firma: el vale es el respaldo de lo que se retira.';
    END IF;
    -- El pad son unos pocos KB. Un envío grande es un error o un abuso.
    IF length(p_firma) > 300000 THEN
        RAISE EXCEPTION 'La firma no se pudo procesar. Bórrela y fírmela de nuevo.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Escriba para qué es el pedido: es lo único que va a explicar este gasto a fin de mes.';
    END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El vale necesita al menos un ítem';
    END IF;
    IF jsonb_array_length(p_items) > v_p.max_items_por_vale THEN
        RAISE EXCEPTION 'Por este link se pueden pedir hasta % ítems por vale.',
            v_p.max_items_por_vale USING ERRCODE = '22023';
    END IF;

    -- El centro de costo tiene que venir escrito en el token, no elegido libre.
    IF NOT (p_ceco_id = ANY (v_p.ceco_ids)) THEN
        RAISE EXCEPTION 'Ese centro de costo no está habilitado para este link.'
            USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_ceco FROM public.centros_costo
     WHERE id = p_ceco_id AND COALESCE(activo, TRUE);
    IF v_ceco.id IS NULL THEN
        RAISE EXCEPTION 'Elija a qué centro de costo se carga el pedido.';
    END IF;

    v_bodega := v_p.bodega_id;
    IF v_bodega IS NULL THEN
        SELECT b.id INTO v_bodega FROM public.bodegas b
         ORDER BY (SELECT count(*) FROM public.stock_bodega s
                    WHERE s.bodega_id = b.id AND s.cantidad > 0) DESC, b.created_at
         LIMIT 1;
    END IF;
    IF v_bodega IS NULL THEN RAISE EXCEPTION 'No hay bodegas configuradas.'; END IF;

    -- ══ El vale ══════════════════════════════════════════════════════════
    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)), 0) + 1 INTO v_sec
      FROM public.bodega_tickets WHERE folio LIKE 'TKT-' || v_periodo || '-%';
    v_folio := 'TKT-' || v_periodo || '-' || LPAD(v_sec::text, 5, '0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-' || v_folio;

    INSERT INTO public.bodega_tickets(
        id, folio, qr_code, ot_id, activo_id, ceco_id, bodega_id, estado,
        emitido_por, firma_jefe_url, observacion, origen, motivo,
        solicitante_nombre, solicitante_rut, portal_acceso_id)
    VALUES (v_id, v_folio, v_qr, NULL, NULL, p_ceco_id, v_bodega, 'emitido',
            NULL, p_firma, p_observacion, 'oficina', trim(p_motivo),
            v_acc.nombre, v_acc.rut, p_acceso_id);

    FOR v_it IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod := NULLIF(v_it->>'producto_id', '')::uuid;

        -- Por el link no hay texto libre: el vale descuenta stock, y no se
        -- descuenta lo que no está en el catálogo.
        IF v_prod IS NULL THEN
            RAISE EXCEPTION 'Por este link sólo se puede pedir lo que está en el catálogo.'
                USING ERRCODE = '22023';
        END IF;
        IF COALESCE((v_it->>'cantidad')::numeric, 0) <= 0 THEN
            RAISE EXCEPTION 'La cantidad tiene que ser mayor que cero';
        END IF;

        -- Se revalida la familia: que el buscador sólo haya mostrado lo
        -- permitido no impide que alguien mande otro id a mano.
        IF NOT EXISTS (SELECT 1 FROM public.productos pr
                        WHERE pr.id = v_prod AND pr.categoria = ANY (v_p.categorias)) THEN
            RAISE EXCEPTION 'Ese artículo no se puede pedir por este link.'
                USING ERRCODE = '42501';
        END IF;

        INSERT INTO public.bodega_ticket_items
               (ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, comentario)
        SELECT v_id, pr.id, pr.nombre, pr.unidad_medida,
               (v_it->>'cantidad')::numeric,
               NULLIF(trim(v_it->>'comentario'), '')
          FROM public.productos pr WHERE pr.id = v_prod;

        v_n := v_n + 1;
    END LOOP;

    UPDATE public.portal_vale_accesos SET vales = vales + 1 WHERE id = p_acceso_id;

    -- ══ Bodega se entera ═════════════════════════════════════════════════
    BEGIN
        FOR v_u IN
            SELECT id FROM public.usuarios_perfil
             WHERE activo AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO public.alertas (tipo, titulo, mensaje, severidad, entidad_tipo,
                                        entidad_id, destinatario_id, leida, created_at)
            VALUES ('vale_emitido',
                    'Vale de oficina: ' || v_folio,
                    'Preparar entrega para ' || v_ceco.nombre || ' — ' || v_n ||
                    ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END ||
                    '. Pidió ' || v_acc.nombre || ' por el link. ' || trim(p_motivo) ||
                    ' (QR ' || v_qr || ').',
                    'info', 'ticket_bodega', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object(
        'success', TRUE, 'ticket_id', v_id, 'folio', v_folio, 'qr', v_qr,
        'items', v_n, 'ceco', v_ceco.codigo, 'ceco_nombre', v_ceco.nombre,
        'solicitante', v_acc.nombre);
END;
$fn$;

-- ── 10. El vale impreso, sin sesión ────────────────────────────────────────
-- Quien pidió por el link tiene que poder abrir e imprimir SU vale. Se pide el
-- ticket junto con el acceso que lo creó: sin ese par no se ve nada.
CREATE OR REPLACE FUNCTION public.fn_portal_vale_ver(
    p_token text, p_acceso_id uuid, p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_p  public.portales_vale_oficina;
    v_tk RECORD;
BEGIN
    v_p := public.fn_portal_vale_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_portal_vale_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Su ingreso caducó. Vuelva a abrir el link.' USING ERRCODE = '42501';
    END IF;

    SELECT t.* INTO v_tk FROM public.v_bodega_ticket t
     WHERE t.id = p_ticket_id AND t.portal_acceso_id = p_acceso_id;
    IF v_tk.id IS NULL THEN
        RAISE EXCEPTION 'Ese vale no es de este ingreso.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'ticket', to_jsonb(v_tk),
        'items', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                            'descripcion', i.descripcion,
                            'unidad', i.unidad,
                            'cantidad_solicitada', i.cantidad_solicitada,
                            'cantidad_entregada', i.cantidad_entregada)
                          ORDER BY i.created_at), '[]'::jsonb)
                    FROM public.bodega_ticket_items i WHERE i.ticket_id = p_ticket_id));
END;
$fn$;

-- ── 11. Las puertas que el anónimo puede tocar ─────────────────────────────
REVOKE ALL ON FUNCTION public.fn_portal_vale_resolver(text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_portal_vale_publico(text)                       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_portal_vale_ingresar(text, text, text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_portal_vale_catalogo(text, uuid, text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_portal_vale_crear(text, uuid, uuid, jsonb, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_portal_vale_ver(text, uuid, uuid)               TO anon, authenticated;

-- ── 12. El primer link: la oficina ─────────────────────────────────────────
INSERT INTO public.portales_vale_oficina
    (token, nombre, ceco_ids, categorias, observacion)
SELECT
    replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
    'Vale de bodega — Oficina',
    ARRAY(SELECT id FROM public.centros_costo
           WHERE codigo IN ('CECO-ADMIN','CECO-PREVENCION','CECO-COMERCIAL','CECO-BODEGA')
             AND COALESCE(activo, TRUE)),
    ARRAY['articulos_de_oficina','implementos_de_aseo_y_fungibles'],
    'Creado en MIG376. Se reparte por WhatsApp a la gente de oficina. Revocable desde el panel de bodega.'
WHERE NOT EXISTS (
    SELECT 1 FROM public.portales_vale_oficina WHERE nombre = 'Vale de bodega — Oficina'
);

COMMIT;
