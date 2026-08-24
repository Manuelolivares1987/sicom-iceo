-- ============================================================================
-- MIG371 · Pedirle algo a bodega sin esperar a que haya un hallazgo
-- ----------------------------------------------------------------------------
-- Hoy el vale sólo se puede emitir si el equipo ya tiene una OT y esa OT ya
-- tiene ítems: los materiales de un hallazgo (nc_materiales) o lo que el
-- operador pidió durante la ejecución (ot_recursos_solicitados). Si no hay
-- ninguno de los dos, el modal dice «No hay equipos con OT de taller para
-- emitir vale» y no hay camino.
--
-- Eso deja fuera el caso más común del día a día: hacen falta filtros, aceite,
-- una manguera o un juego de ampolletas para una patente, y no hay hallazgo ni
-- OT abierta. Hoy eso se pide por WhatsApp y se retira sin papel.
--
-- ─────────────────────────────────────────────────────────────────────────
-- POR QUÉ EL VALE MANUAL IGUAL CUELGA DE UNA OT
-- Parece más simple emitir un vale «suelto», amarrado sólo a la patente. No se
-- puede, y no por un capricho del modelo: la salida de bodega la bloquea una
-- restricción del kardex —`chk_mov_salida_requiere_ot`— que exige OT en toda
-- salida. Sin ella, el vale se emitiría bien y sería INDESPACHABLE: bodega lo
-- recibiría, prepararía el material y al confirmar la entrega reventaría. Es
-- exactamente el modo de fallar más caro, porque se descubre con el operador
-- esperando en el mesón.
--
-- Y la restricción tiene razón de ser: sin OT el consumo no se imputa a nada, y
-- el costo por equipo —que es para lo que existe todo esto— deja de ser cierto.
--
-- Así que el vale manual reutiliza o crea una OT de tipo `abastecimiento` del
-- equipo. Se eligió ese tipo y no `correctivo` a propósito:
--   · `abastecimiento` no tiene ni una sola OT en producción, así que no
--     ensucia nada que ya se esté usando;
--   · y no infla los indicadores de correctivas, que es lo que pasaría si un
--     pedido de aceite entrara como una falla.
--
-- La OT se reutiliza con `rpc_programar_ot_taller` (MIG256), o sea: tres pedidos
-- para la misma patente en la misma semana van a la MISMA OT de abastecimiento,
-- no a tres. Es la misma regla que ya se aplicó al planificar.
--
-- ─────────────────────────────────────────────────────────────────────────
-- EL MOTIVO ES OBLIGATORIO
-- Un vale que nace de un hallazgo se explica solo: ahí está la NC con su foto.
-- Uno manual no tiene de dónde agarrarse, y sin motivo escrito, a fin de mes
-- nadie puede decir por qué salieron 40 litros de aceite. No es burocracia: es
-- la única línea que va a quedar.
--
-- ─────────────────────────────────────────────────────────────────────────
-- DOS ARREGLOS QUE VAN DE PASO, PORQUE SIN ELLOS ESTO NO SE PUEDE DESPACHAR
--
-- 1. EL CECO SE BUSCABA POR LA OT Y NO POR EL EQUIPO. Al entregar, el centro de
--    costo salía de `ordenes_trabajo.activo_id`. El vale ya sabe cuál es su
--    equipo —lo guarda en su propia columna— y ese es el dato directo. Da lo
--    mismo en el caso normal y evita un salto de más acá.
--
-- 2. UN ÍTEM ESCRITO A MANO NO SE PODÍA ENTREGAR. La entrega sólo descuenta lo
--    que tiene producto del catálogo; un ítem de texto libre se saltaba en
--    silencio, y si TODOS lo eran, la entrega fallaba con «No hay cantidades a
--    entregar» sin decir por qué. Ahora bodega puede amarrar el ítem a su
--    producto en el momento de despachar —que es quien sabe cuál es— y el
--    mensaje dice qué falta.
-- ============================================================================

BEGIN;

-- ── De dónde viene el vale ────────────────────────────────────────────────
ALTER TABLE public.bodega_tickets
    ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'ot',
    ADD COLUMN IF NOT EXISTS motivo TEXT;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bodega_ticket_origen') THEN
        ALTER TABLE public.bodega_tickets
            ADD CONSTRAINT chk_bodega_ticket_origen CHECK (origen IN ('ot', 'manual'));
    END IF;
END
$c$;

COMMENT ON COLUMN public.bodega_tickets.origen IS
  'De donde nacio el vale: «ot» si sus items vienen de hallazgos o de lo que pidio el operador; «manual» si el jefe lo pidio directo contra la patente. MIG371.';
COMMENT ON COLUMN public.bodega_tickets.motivo IS
  'Por que se pidio. Obligatorio en el vale manual: no tiene una NC de donde agarrarse y sin esto, a fin de mes, nadie puede decir por que salio el material. MIG371.';


-- ══════════════════════════════════════════════════════════════════════════
-- EL VALE MANUAL
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rpc_crear_vale_manual(
    p_activo_id     uuid,
    p_items         jsonb,
    p_motivo        text,
    p_firma_jefe_url text,
    p_bodega_id     uuid DEFAULT NULL,
    p_observacion   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user    UUID := auth.uid();
    v_rol     TEXT := fn_user_rol();
    v_ot      JSONB;
    v_ot_id   UUID;
    v_folio   TEXT;
    v_periodo TEXT;
    v_sec     INT;
    v_id      UUID;
    v_qr      TEXT;
    v_n       INT := 0;
    v_sin_cat INT := 0;
    v_faena   UUID;
    v_bodega  UUID;
    v_it      JSONB;
    v_pat     TEXT;
    v_u       RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- La misma puerta que el vale de OT: el que firma es quien responde por lo
    -- que sale de bodega.
    IF v_rol NOT IN ('administrador','jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo el jefe de taller o el supervisor emiten vales (rol: %)', v_rol;
    END IF;
    IF p_firma_jefe_url IS NULL OR length(trim(p_firma_jefe_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del jefe es obligatoria';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Escriba para qué es el pedido. Un vale manual no tiene una no conformidad de dónde agarrarse: este texto es lo único que va a quedar.';
    END IF;
    IF p_activo_id IS NULL OR NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Elija la patente o el equipo al que va el pedido';
    END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El vale necesita al menos un ítem';
    END IF;

    -- ── La OT que sostiene el pedido ──────────────────────────────────────
    -- Se reutiliza la de abastecimiento abierta del equipo si la hay (MIG256):
    -- tres pedidos para la misma patente en la semana no son tres OT.
    v_ot := rpc_programar_ot_taller(
        p_activo_id, 'abastecimiento'::tipo_ot_enum, 'normal'::prioridad_enum,
        CURRENT_DATE, NULL, NULL, TRUE);
    v_ot_id := (v_ot->>'id')::uuid;
    IF v_ot_id IS NULL THEN
        RAISE EXCEPTION 'No se pudo preparar la orden de trabajo del pedido';
    END IF;

    -- La OT nace en «creada» y el kardex no deja retirar material contra ese
    -- estado: sólo contra asignada, en ejecución o pausada. Sin esto el vale se
    -- emitiría bien y reventaría al entregarlo, con el operador en el mesón.
    -- Se deja asignada a quien lo pide, que es exactamente lo que es: un pedido
    -- con dueño.
    UPDATE ordenes_trabajo
       SET estado = 'asignada'::estado_ot_enum,
           responsable_id = COALESCE(responsable_id, v_user),
           updated_at = NOW()
     WHERE id = v_ot_id AND estado = 'creada'::estado_ot_enum;

    -- ── La bodega que va a despachar, verificada ACÁ y no al entregar ─────
    -- La salida exige que la bodega sea de la misma faena que la OT. Si eso se
    -- descubre al momento de la entrega, el vale ya está impreso y el operador
    -- está esperando — es el bug que ya apareció una vez. Se resuelve al
    -- emitir: si no se eligió bodega se toma la de la faena, y si se eligió una
    -- que no corresponde se dice antes de emitir nada.
    SELECT faena_id INTO v_faena FROM ordenes_trabajo WHERE id = v_ot_id;
    IF p_bodega_id IS NULL THEN
        SELECT id INTO v_bodega FROM bodegas
         WHERE faena_id = v_faena
         ORDER BY created_at LIMIT 1;
        IF v_bodega IS NULL THEN
            RAISE EXCEPTION 'El taller de este equipo no tiene bodega asociada, así que el vale no se podría despachar. Cree la bodega de la faena o elija otra al emitir.'
                USING ERRCODE = 'check_violation';
        END IF;
    ELSE
        SELECT id INTO v_bodega FROM bodegas
         WHERE id = p_bodega_id AND faena_id = v_faena;
        IF v_bodega IS NULL THEN
            RAISE EXCEPTION 'Esa bodega no es de la faena del taller que atiende al equipo: no podría despachar el vale.'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- ── El folio, con el mismo correlativo que los demás vales ────────────
    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)), 0) + 1 INTO v_sec
      FROM bodega_tickets WHERE folio LIKE 'TKT-' || v_periodo || '-%';
    v_folio := 'TKT-' || v_periodo || '-' || LPAD(v_sec::text, 5, '0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-' || v_folio;

    INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, bodega_id, estado,
                               emitido_por, firma_jefe_url, observacion, origen, motivo)
    VALUES (v_id, v_folio, v_qr, v_ot_id, p_activo_id, v_bodega, 'emitido',
            v_user, p_firma_jefe_url, p_observacion, 'manual', trim(p_motivo));

    -- ── Los ítems, tal como los escribió quien pide ───────────────────────
    FOR v_it IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF COALESCE((v_it->>'cantidad')::numeric, 0) <= 0 THEN
            RAISE EXCEPTION 'La cantidad de «%» tiene que ser mayor que cero',
                COALESCE(v_it->>'descripcion', 'un ítem');
        END IF;
        IF (v_it->>'producto_id') IS NULL
           AND COALESCE(trim(v_it->>'descripcion'), '') = '' THEN
            RAISE EXCEPTION 'Cada ítem necesita un producto del catálogo o una descripción';
        END IF;

        INSERT INTO bodega_ticket_items
               (ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, comentario)
        SELECT v_id,
               NULLIF(v_it->>'producto_id', '')::uuid,
               COALESCE(NULLIF(trim(v_it->>'descripcion'), ''), pr.nombre),
               COALESCE(NULLIF(trim(v_it->>'unidad'), ''), pr.unidad_medida),
               (v_it->>'cantidad')::numeric,
               NULLIF(trim(v_it->>'comentario'), '')
          FROM (SELECT 1) x
          LEFT JOIN productos pr ON pr.id = NULLIF(v_it->>'producto_id', '')::uuid;

        v_n := v_n + 1;
        IF (v_it->>'producto_id') IS NULL THEN v_sin_cat := v_sin_cat + 1; END IF;
    END LOOP;

    -- ── Le llega a bodega, igual que cualquier otro vale ──────────────────
    BEGIN
        SELECT COALESCE(a.patente, a.codigo) INTO v_pat FROM activos a WHERE a.id = p_activo_id;
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = TRUE AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('vale_emitido',
                    'Pedido a bodega: ' || v_folio,
                    'Pedido manual para ' || COALESCE(v_pat, 'equipo') || ' — ' || v_n ||
                    ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END || '. ' || trim(p_motivo) ||
                    ' (QR ' || v_qr || ').',
                    'info', 'ticket_bodega', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object(
        'success', TRUE, 'ticket_id', v_id, 'folio', v_folio, 'qr', v_qr,
        'items', v_n,
        'items_sin_catalogo', v_sin_cat,
        'bodega_id', v_bodega,
        'ot_id', v_ot_id, 'ot_folio', v_ot->>'folio',
        'ot_reutilizada', COALESCE((v_ot->>'reutilizada')::boolean, FALSE));
END;
$fn$;

REVOKE ALL ON FUNCTION public.rpc_crear_vale_manual(uuid, jsonb, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_crear_vale_manual(uuid, jsonb, text, text, uuid, text) TO authenticated;

COMMENT ON FUNCTION public.rpc_crear_vale_manual(uuid, jsonb, text, text, uuid, text) IS
  'Pedido manual a bodega contra una patente, sin esperar a que haya un hallazgo. Cuelga de una OT de abastecimiento reutilizable porque el kardex exige OT en toda salida. MIG371.';


-- ══════════════════════════════════════════════════════════════════════════
-- BODEGA PUEDE AMARRAR UN ÍTEM DE TEXTO LIBRE A SU PRODUCTO
-- ══════════════════════════════════════════════════════════════════════════
-- Quien pide no siempre sabe el código; quien despacha sí. Sin esto, un ítem
-- escrito a mano se saltaba en silencio al entregar y el stock nunca bajaba.
CREATE OR REPLACE FUNCTION public.rpc_ticket_item_producto(
    p_item_id uuid, p_producto_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_ti  RECORD;
    v_pr  RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','operador_abastecimiento',
                     'jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT bti.*, bt.estado AS ticket_estado INTO v_ti
      FROM bodega_ticket_items bti
      JOIN bodega_tickets bt ON bt.id = bti.ticket_id
     WHERE bti.id = p_item_id;
    IF v_ti.id IS NULL THEN RAISE EXCEPTION 'El ítem no existe'; END IF;
    IF v_ti.ticket_estado IN ('entregado','anulado') THEN
        RAISE EXCEPTION 'El vale ya está %: no se puede cambiar', v_ti.ticket_estado;
    END IF;
    IF v_ti.cantidad_entregada > 0 THEN
        RAISE EXCEPTION 'Este ítem ya tiene entrega parcial: cambiarle el producto dejaría el descuento en otro artículo';
    END IF;

    SELECT * INTO v_pr FROM productos WHERE id = p_producto_id;
    IF v_pr.id IS NULL THEN RAISE EXCEPTION 'El producto no existe'; END IF;

    UPDATE bodega_ticket_items
       SET producto_id = p_producto_id,
           unidad = COALESCE(unidad, v_pr.unidad_medida),
           -- Lo que escribió quien pide no se pierde: pasa al comentario, que
           -- es donde sirve para saber si bodega entendió lo mismo.
           comentario = CASE
               WHEN COALESCE(descripcion, '') <> '' AND COALESCE(descripcion, '') <> v_pr.nombre
               THEN COALESCE(comentario || ' · ', '') || 'Pedido como: ' || descripcion
               ELSE comentario END,
           descripcion = v_pr.nombre
     WHERE id = p_item_id;

    RETURN jsonb_build_object('success', TRUE, 'producto', v_pr.nombre);
END;
$fn$;

REVOKE ALL ON FUNCTION public.rpc_ticket_item_producto(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_ticket_item_producto(uuid, uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- LA ENTREGA: CECO POR EL EQUIPO DEL VALE, Y DECIR QUÉ FALTA
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rpc_entregar_ticket_bodega(
    p_ticket_id uuid, p_bodega_id uuid, p_entregas jsonb,
    p_entregado_a character varying DEFAULT NULL, p_firma_bodeguero_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_tk RECORD; v_ti RECORD; e RECORD;
    v_activo UUID; v_faena UUID; v_ceco UUID;
    v_items JSONB := '[]'::JSONB; v_salida JSONB; v_folio TEXT; v_falta INT;
    v_sin_prod TEXT[] := '{}';
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','supervisor','jefe_mantenimiento','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para entregar', v_rol; END IF;

    SELECT * INTO v_tk FROM bodega_tickets WHERE id = p_ticket_id;
    IF v_tk.id IS NULL THEN RAISE EXCEPTION 'Ticket no existe'; END IF;
    IF v_tk.estado IN ('entregado','anulado') THEN
        RAISE EXCEPTION 'Ticket % ya esta % — no se puede volver a usar', v_tk.folio, v_tk.estado; END IF;
    IF p_bodega_id IS NULL THEN RAISE EXCEPTION 'Debe elegir la bodega de despacho'; END IF;

    -- [MIG371] El CECO sale del equipo DEL VALE. Antes se buscaba por la OT, un
    -- salto de más que además dejaba sin CECO a los vales que no tienen OT.
    v_activo := v_tk.activo_id;
    SELECT faena_id INTO v_faena FROM ordenes_trabajo WHERE id = v_tk.ot_id;
    IF v_activo IS NULL THEN
        SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id = v_tk.ot_id;
    END IF;
    SELECT ceco_id INTO v_ceco FROM activos WHERE id = v_activo;
    IF v_ceco IS NULL AND v_faena IS NULL THEN
        SELECT faena_id INTO v_faena FROM activos WHERE id = v_activo;
    END IF;
    IF v_ceco IS NULL THEN
        SELECT id INTO v_ceco FROM centros_costo
         WHERE faena_id = v_faena AND COALESCE(activo, TRUE) = TRUE ORDER BY created_at LIMIT 1;
    END IF;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE codigo = 'CECO-BODEGA' LIMIT 1; END IF;
    IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE COALESCE(activo, TRUE) = TRUE ORDER BY created_at LIMIT 1; END IF;

    FOR e IN SELECT * FROM jsonb_to_recordset(p_entregas) AS x(ticket_item_id UUID, cantidad NUMERIC)
    LOOP
        IF e.cantidad IS NULL OR e.cantidad <= 0 THEN CONTINUE; END IF;
        SELECT * INTO v_ti FROM bodega_ticket_items WHERE id = e.ticket_item_id AND ticket_id = p_ticket_id;
        IF v_ti.id IS NULL THEN RAISE EXCEPTION 'Item no pertenece al ticket'; END IF;
        IF e.cantidad > (v_ti.cantidad_solicitada - v_ti.cantidad_entregada) THEN
            RAISE EXCEPTION 'Cantidad supera lo pendiente en "%"', COALESCE(v_ti.descripcion, 'item'); END IF;
        IF v_ti.producto_id IS NOT NULL THEN
            v_items := v_items || jsonb_build_object('producto_id', v_ti.producto_id,
                                                    'cantidad', e.cantidad, 'unidad', v_ti.unidad);
        ELSE
            -- [MIG371] Antes se saltaba en silencio y el stock no bajaba.
            v_sin_prod := v_sin_prod || COALESCE(v_ti.descripcion, 'un ítem')::text;
        END IF;
    END LOOP;

    IF array_length(v_sin_prod, 1) > 0 THEN
        RAISE EXCEPTION 'Falta decir qué producto del catálogo es: %. Asígnelo en el vale y vuelva a entregar — sin producto el stock no baja.',
            array_to_string(v_sin_prod, ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    IF jsonb_array_length(v_items) = 0 THEN RAISE EXCEPTION 'No hay cantidades a entregar'; END IF;

    v_salida := rpc_registrar_salida_bodega(
        'ot', p_bodega_id, v_ceco, v_tk.ot_id,
        'Despacho ticket ' || v_tk.folio, v_items,
        p_entregado_a, NULL, v_tk.emitido_por, p_firma_bodeguero_url,
        'Ticket bodega ' || v_tk.folio);
    v_folio := v_salida->>'folio';

    FOR e IN SELECT * FROM jsonb_to_recordset(p_entregas) AS x(ticket_item_id UUID, cantidad NUMERIC)
    LOOP
        IF e.cantidad IS NULL OR e.cantidad <= 0 THEN CONTINUE; END IF;
        UPDATE bodega_ticket_items SET cantidad_entregada = cantidad_entregada + e.cantidad
         WHERE id = e.ticket_item_id AND ticket_id = p_ticket_id;
    END LOOP;

    SELECT COUNT(*) INTO v_falta FROM bodega_ticket_items
     WHERE ticket_id = p_ticket_id AND cantidad_entregada < cantidad_solicitada;

    UPDATE bodega_tickets
       SET estado = CASE WHEN v_falta = 0 THEN 'entregado' ELSE 'parcial' END,
           bodega_id = COALESCE(bodega_id, p_bodega_id),
           entregado_por = v_user,
           entregado_at = CASE WHEN v_falta = 0 THEN NOW() ELSE entregado_at END,
           updated_at = NOW()
     WHERE id = p_ticket_id;

    RETURN jsonb_build_object('success', TRUE, 'despacho_folio', v_folio,
                              'estado', CASE WHEN v_falta = 0 THEN 'entregado' ELSE 'parcial' END);
END;
$fn$;

REVOKE ALL ON FUNCTION public.rpc_entregar_ticket_bodega(uuid, uuid, jsonb, character varying, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_entregar_ticket_bodega(uuid, uuid, jsonb, character varying, text) TO authenticated;


-- ── El listado del vale muestra de dónde viene ────────────────────────────
-- CREATE OR REPLACE no puede insertar columnas en medio de una vista: hay que
-- reemplazarla entera. Nada cuelga de ella salvo el front, que se despliega
-- junto con esto.
DROP VIEW IF EXISTS public.v_bodega_ticket;

CREATE VIEW public.v_bodega_ticket AS
SELECT tk.id, tk.folio, tk.qr_code, tk.ot_id, tk.activo_id, tk.bodega_id, tk.estado,
       tk.emitido_por, tk.firma_jefe_url, tk.observacion, tk.entregado_por, tk.entregado_at,
       tk.created_at,
       tk.origen, tk.motivo,
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
  LEFT JOIN usuarios_perfil up ON up.id = tk.emitido_por
  LEFT JOIN usuarios_perfil ub ON ub.id = tk.entregado_por;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT folio, origen, motivo, activo_patente, n_items, n_sin_producto
--   FROM v_bodega_ticket ORDER BY created_at DESC LIMIT 10;
