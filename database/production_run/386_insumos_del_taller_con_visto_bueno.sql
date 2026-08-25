-- ============================================================================
-- MIG386 · El operador del taller pide insumos, y el jefe da el visto bueno
-- ----------------------------------------------------------------------------
-- Desde MIG197 el operador pide repuestos desde /m/taller, el jefe valida y de
-- ahí sale el vale. Funciona bien, pero TODO cuelga de una orden de trabajo:
-- `ot_recursos_solicitados.ot_id` es NOT NULL.
--
-- Los insumos no tienen OT. Guantes, trapos, cinta, discos de corte, un par de
-- botas: no son de ningún equipo, son del taller. Hoy se piden de palabra, y el
-- gasto del taller queda sin nombre y sin papel.
--
-- SE ESTIRA EL FLUJO QUE YA EXISTE, NO SE INVENTA OTRO
-- El circuito es el mismo —pide el operador, valida el jefe, sale el vale— y la
-- bandeja donde el jefe aprueba también. Duplicarlo en una tabla paralela
-- habría significado dos bandejas, dos pantallas y dos formas de aprobar lo
-- mismo. Lo único distinto es a qué se carga: la OT lleva el costo al equipo, el
-- CECO lo lleva al taller.
--
-- UN PEDIDO SIEMPRE TIENE DESTINO
-- `ot_id` pasa a ser opcional, pero no se vuelve libre: el CHECK exige OT **o**
-- CECO. Un pedido sin ninguno de los dos sería un costo sin dueño, que es
-- justamente lo que este circuito existe para evitar. Es la misma regla que
-- MIG375 le puso al kardex, y por eso el vale ya sabe despachar contra un CECO.
--
-- CADA PATENTE ES UN CECO, Y POR AHÍ NO SE PIDE
-- De los 63 centros de costo activos, 55 son de un equipo (`area = 'Flota'`) y
-- 8 son de área. Dejar que un insumo del taller se cargara al CECO de una
-- patente sería meter guantes y discos de corte en el costo de un camión sin
-- que ninguna OT lo explique — y el costo por equipo es justamente lo que el
-- sistema cuida. Si el insumo es PARA un equipo, el camino es la OT: ahí el
-- gasto queda con su trabajo, su hallazgo y su historia.
--
-- EL VISTO BUENO NO ES UN TRÁMITE
-- Sin él, «pedir insumos» sería un canal para sacar cosas de bodega sin que
-- nadie mire. El jefe puede ajustar la cantidad antes de aprobar —el mismo
-- botón que ya usa para los repuestos— y recién ahí se emite el papel.
-- ============================================================================

BEGIN;

-- ── 1. El pedido puede colgar de un centro de costo ───────────────────────
ALTER TABLE public.ot_recursos_solicitados
    ALTER COLUMN ot_id DROP NOT NULL;

ALTER TABLE public.ot_recursos_solicitados
    ADD COLUMN IF NOT EXISTS ceco_id UUID REFERENCES public.centros_costo(id);

COMMENT ON COLUMN public.ot_recursos_solicitados.ceco_id IS
    '[MIG386] El centro de costo cuando el pedido no es de un equipo sino del taller (insumos). Excluyente con ot_id.';

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_recurso_tiene_destino') THEN
        ALTER TABLE public.ot_recursos_solicitados
            ADD CONSTRAINT chk_recurso_tiene_destino
            CHECK (ot_id IS NOT NULL OR ceco_id IS NOT NULL);
    END IF;
END
$ck$;

CREATE INDEX IF NOT EXISTS idx_recursos_ceco
    ON public.ot_recursos_solicitados (ceco_id, estado)
    WHERE ceco_id IS NOT NULL;

-- ── 2. El operador pide insumos del taller ────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_insumo_solicitar(
    p_ceco_id      uuid,
    p_cantidad     numeric,
    p_producto_id  uuid DEFAULT NULL,
    p_descripcion  varchar DEFAULT NULL,
    p_unidad       varchar DEFAULT NULL,
    p_comentario   text DEFAULT NULL,
    p_solicitado_nombre varchar DEFAULT NULL,
    p_client_uuid  uuid DEFAULT NULL,
    p_fotos        text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user UUID := auth.uid();
    v_id   UUID;
    v_ceco RECORD;
    v_u    RECORD;
    v_desc TEXT;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Sesión requerida.' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(p_cantidad, 0) <= 0 THEN
        RAISE EXCEPTION 'La cantidad tiene que ser mayor que cero.' USING ERRCODE = '22023';
    END IF;
    IF p_producto_id IS NULL AND COALESCE(length(trim(p_descripcion)), 0) < 3 THEN
        RAISE EXCEPTION 'Diga qué necesita: elija del catálogo o escríbalo.' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_ceco FROM public.centros_costo
     WHERE id = p_ceco_id AND COALESCE(activo, TRUE);
    IF v_ceco.id IS NULL THEN
        RAISE EXCEPTION 'Elija a qué taller se carga el pedido.' USING ERRCODE = '22023';
    END IF;
    -- Cada patente es un CECO. Los insumos del taller no se cargan a un equipo:
    -- si son para un equipo, van por su orden de trabajo.
    IF lower(COALESCE(v_ceco.area, '')) = 'flota' THEN
        RAISE EXCEPTION 'El centro de costo «%» es de un equipo. Si el material es para ese equipo, pídalo desde su orden de trabajo; acá van los insumos del taller.',
            v_ceco.nombre USING ERRCODE = '22023';
    END IF;

    -- Reintento del teléfono sin señal: el mismo pedido no entra dos veces.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM public.ot_recursos_solicitados
         WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', TRUE, 'recurso_id', v_id, 'duplicado', TRUE);
        END IF;
    END IF;

    INSERT INTO public.ot_recursos_solicitados (
        client_uuid, ot_id, ceco_id, producto_id, descripcion, unidad, cantidad,
        comentario, estado, solicitado_por, solicitado_nombre,
        agregado_por_jefe, fotos)
    VALUES (
        p_client_uuid, NULL, p_ceco_id, p_producto_id,
        NULLIF(trim(COALESCE(p_descripcion, '')), ''),
        NULLIF(trim(COALESCE(p_unidad, '')), ''),
        p_cantidad, NULLIF(trim(COALESCE(p_comentario, '')), ''),
        'solicitado', v_user,
        NULLIF(trim(COALESCE(p_solicitado_nombre, '')), ''),
        FALSE, p_fotos)
    RETURNING id INTO v_id;

    -- El jefe se entera donde ya trabaja: la misma bandeja de los repuestos.
    BEGIN
        v_desc := COALESCE(NULLIF(trim(p_descripcion), ''),
                           (SELECT nombre FROM public.productos WHERE id = p_producto_id),
                           'insumo');
        FOR v_u IN
            SELECT id FROM public.usuarios_perfil
             WHERE activo AND rol IN ('administrador','jefe_mantenimiento','supervisor','planificador')
        LOOP
            INSERT INTO public.alertas (tipo, titulo, mensaje, severidad, entidad_tipo,
                                        entidad_id, destinatario_id, leida, created_at)
            VALUES ('recurso_solicitado',
                    'Insumos del taller por aprobar',
                    COALESCE(NULLIF(trim(p_solicitado_nombre), ''), 'Un operador')
                      || ' pidió ' || p_cantidad || ' ' || COALESCE(p_unidad, 'un')
                      || ' de ' || v_desc || ' para ' || v_ceco.nombre || '.',
                    'info', 'recurso_taller', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', TRUE, 'recurso_id', v_id,
                              'ceco', v_ceco.codigo, 'ceco_nombre', v_ceco.nombre);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_insumo_solicitar(uuid, numeric, uuid, varchar, varchar, text, varchar, uuid, text[])
    TO authenticated;

-- ── 3. Del visto bueno al papel ───────────────────────────────────────────
-- Los insumos aprobados de un mismo centro de costo se juntan en UN vale: el
-- operador va una vez a bodega, no una por artículo.
CREATE OR REPLACE FUNCTION public.rpc_taller_insumos_a_vale(
    p_recurso_ids uuid[],
    p_bodega_id   uuid DEFAULT NULL,
    p_observacion text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user    UUID := auth.uid();
    v_rol     TEXT := fn_user_rol();
    v_ceco    RECORD;
    v_cecos   INT;
    v_bodega  UUID;
    v_folio   TEXT;
    v_periodo TEXT;
    v_sec     INT;
    v_id      UUID;
    v_qr      TEXT;
    v_n       INT := 0;
    v_r       RECORD;
    v_motivo  TEXT;
    v_u       RECORD;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Sesión requerida.' USING ERRCODE = '42501';
    END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'supervisor','planificador','bodeguero','operador_abastecimiento') THEN
        RAISE EXCEPTION 'El vale de insumos lo emite la jefatura o bodega (rol: %).', v_rol
            USING ERRCODE = '42501';
    END IF;
    IF p_recurso_ids IS NULL OR array_length(p_recurso_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'No vino ningún insumo que despachar.' USING ERRCODE = '22023';
    END IF;

    -- Todos tienen que ir al mismo centro de costo: un vale es de un destino.
    SELECT count(DISTINCT ceco_id) INTO v_cecos
      FROM public.ot_recursos_solicitados
     WHERE id = ANY (p_recurso_ids) AND ceco_id IS NOT NULL;
    IF v_cecos <> 1 THEN
        RAISE EXCEPTION 'Un vale es de un solo centro de costo (vinieron %).', v_cecos
            USING ERRCODE = '22023';
    END IF;

    SELECT c.* INTO v_ceco
      FROM public.centros_costo c
      JOIN public.ot_recursos_solicitados r ON r.ceco_id = c.id
     WHERE r.id = ANY (p_recurso_ids) LIMIT 1;

    v_bodega := p_bodega_id;
    IF v_bodega IS NULL THEN
        SELECT b.id INTO v_bodega FROM public.bodegas b
         ORDER BY (SELECT count(*) FROM public.stock_bodega s
                    WHERE s.bodega_id = b.id AND s.cantidad > 0) DESC, b.created_at
         LIMIT 1;
    END IF;
    IF v_bodega IS NULL THEN RAISE EXCEPTION 'No hay bodegas configuradas.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)), 0) + 1 INTO v_sec
      FROM public.bodega_tickets WHERE folio LIKE 'TKT-' || v_periodo || '-%';
    v_folio := 'TKT-' || v_periodo || '-' || LPAD(v_sec::text, 5, '0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-' || v_folio;
    v_motivo := 'Insumos del taller aprobados por jefatura — ' || v_ceco.nombre;

    INSERT INTO public.bodega_tickets(
        id, folio, qr_code, ot_id, activo_id, ceco_id, bodega_id, estado,
        emitido_por, observacion, origen, motivo)
    VALUES (v_id, v_folio, v_qr, NULL, NULL, v_ceco.id, v_bodega, 'emitido',
            v_user, NULLIF(trim(p_observacion), ''), 'oficina', v_motivo);

    FOR v_r IN
        SELECT r.*, COALESCE(r.cantidad_aprobada, r.cantidad) AS cant
          FROM public.ot_recursos_solicitados r
         WHERE r.id = ANY (p_recurso_ids)
    LOOP
        IF v_r.estado <> 'aprobado' THEN
            RAISE EXCEPTION 'El insumo «%» está en «%»: sólo se despacha lo aprobado por el jefe.',
                COALESCE(v_r.descripcion, 'sin nombre'), v_r.estado USING ERRCODE = '42501';
        END IF;

        INSERT INTO public.bodega_ticket_items
               (ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, comentario)
        SELECT v_id, v_r.producto_id,
               COALESCE(v_r.descripcion, pr.nombre),
               COALESCE(v_r.unidad, pr.unidad_medida),
               v_r.cant, v_r.comentario
          FROM (SELECT 1) x
          LEFT JOIN public.productos pr ON pr.id = v_r.producto_id;

        UPDATE public.ot_recursos_solicitados
           SET estado = 'en_vale', ticket_id = v_id, updated_at = NOW()
         WHERE id = v_r.id;

        v_n := v_n + 1;
    END LOOP;

    BEGIN
        FOR v_u IN
            SELECT id FROM public.usuarios_perfil
             WHERE activo AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO public.alertas (tipo, titulo, mensaje, severidad, entidad_tipo,
                                        entidad_id, destinatario_id, leida, created_at)
            VALUES ('vale_emitido',
                    'Vale de insumos: ' || v_folio,
                    'Preparar entrega para ' || v_ceco.nombre || ' — ' || v_n ||
                    ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END ||
                    ' aprobados por jefatura (QR ' || v_qr || ').',
                    'info', 'ticket_bodega', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', TRUE, 'ticket_id', v_id, 'folio', v_folio,
                              'qr', v_qr, 'items', v_n,
                              'ceco', v_ceco.codigo, 'ceco_nombre', v_ceco.nombre);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_insumos_a_vale(uuid[], uuid, text) TO authenticated;

-- ── 4. La vista muestra a qué se carga ────────────────────────────────────
-- CREATE OR REPLACE no puede meter columnas en medio: se recrea.
DROP VIEW IF EXISTS public.v_ot_recursos CASCADE;
CREATE VIEW public.v_ot_recursos AS
SELECT r.id, r.client_uuid, r.ot_id, r.producto_id, r.instance_item_id,
       COALESCE(r.descripcion, pr.nombre) AS descripcion,
       COALESCE(r.unidad, pr.unidad_medida) AS unidad,
       r.cantidad, r.cantidad_aprobada, r.comentario, r.estado, r.fotos,
       r.solicitado_por, r.solicitado_nombre, r.agregado_por_jefe,
       r.validado_por, r.validado_at, r.nota_jefe, r.ticket_id, r.created_at,
       -- [MIG386] A qué se carga: el equipo de la OT, o el taller.
       r.ceco_id, cc.codigo AS ceco_codigo, cc.nombre AS ceco_nombre,
       (r.ot_id IS NULL AND r.ceco_id IS NOT NULL) AS es_insumo_taller,
       pr.codigo AS producto_codigo, pr.nombre AS producto_nombre,
       CASE WHEN r.producto_id IS NULL THEN NULL::numeric
            ELSE (SELECT COALESCE(sum(sb.cantidad), 0)
                    FROM stock_bodega sb WHERE sb.producto_id = r.producto_id)
       END AS stock_total,
       uv.nombre_completo AS validado_por_nombre,
       tk.folio AS ticket_folio, tk.estado AS ticket_estado,
       r.oc_id, r.oc_item_id,
       oc.numero_oc AS oc_numero, oc.numero_oc_externo AS oc_numero_externo,
       oc.estado AS oc_estado, oc.fecha_entrega AS oc_fecha_entrega,
       prov.nombre AS oc_proveedor, oci.cantidad_recibida AS oc_cantidad_recibida
  FROM ot_recursos_solicitados r
  LEFT JOIN productos pr ON pr.id = r.producto_id
  LEFT JOIN centros_costo cc ON cc.id = r.ceco_id
  LEFT JOIN usuarios_perfil uv ON uv.id = r.validado_por
  LEFT JOIN bodega_tickets tk ON tk.id = r.ticket_id
  LEFT JOIN ordenes_compra oc ON oc.id = r.oc_id
  LEFT JOIN ordenes_compra_items oci ON oci.id = r.oc_item_id
  LEFT JOIN proveedores prov ON prov.id = oc.proveedor_id;

GRANT SELECT ON public.v_ot_recursos TO authenticated;

COMMIT;
