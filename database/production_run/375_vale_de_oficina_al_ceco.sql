-- ============================================================================
-- MIG375 · El pedido de oficina sale con vale físico y se carga a su CECO
-- ----------------------------------------------------------------------------
-- MIG374 le dio a oficina una forma de pedir, pero lo que sale de ahí es una
-- solicitud: un mensaje. Del taller quien pide se lleva un papel con folio y
-- QR, firma al retirar y el consumo queda cargado al equipo. Administración se
-- llevaba el tóner sin nada de eso, y a fin de mes ese gasto no está en ningún
-- centro de costo.
--
-- ─────────────────────────────────────────────────────────────────────────
-- POR QUÉ ESTO NO ERA UNA PANTALLA MÁS
-- El vale existía sólo contra una orden de trabajo, y no por costumbre: TODA la
-- cadena de salida lo exigía en tres lugares distintos.
--
--   1. `chk_mov_salida_requiere_ot` — la restricción del kardex
--   2. `rpc_registrar_salida_bodega` — «MIG37 solo soporta salidas tipo ot»
--   3. `rpc_registrar_salida_inventario` — «No se permite salida sin OT»
--
-- La intención de las tres es la misma y es correcta: nada sale de bodega sin
-- un destino al que imputarlo. Lo que estaba incompleto era la lista de
-- destinos válidos — se escribieron cuando la OT era el único que existía.
--
-- Un centro de costo ES un destino imputable; de hecho es el destino, y la OT
-- lo que hace es apuntar a uno. Así que la regla pasa de «tiene que haber OT» a
-- «tiene que haber OT o CECO», que es lo que siempre quiso decir.
--
-- NO SE RELAJA NADA MÁS
-- Una salida sin OT y sin CECO sigue siendo imposible. El enum de tipos de
-- salida ya tenía `ceco` desde el principio, esperando: se habilita ése y sólo
-- ése. `persona`, `venta` y `ajuste_autorizado` siguen cerrados.
--
-- LOS CECO YA ESTABAN
-- CECO-ADMIN, CECO-PREVENCION, CECO-COMERCIAL, CECO-OPERACIONES y CECO-BODEGA
-- existen desde el maestro inicial. No hay nada que inventar: había que poder
-- usarlos.
--
-- EL COSTO NO SE PIERDE
-- Cuando el vale va contra una OT, el costo del material se suma a la OT como
-- siempre. Cuando va contra un CECO, queda en el movimiento con su centro de
-- costo — y por eso `movimientos_inventario` gana una columna: sin ella el
-- gasto sería imputable en la salida y anónimo en el kardex, que es el registro
-- que después se cuadra.
-- ============================================================================

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- 1. EL KARDEX ACEPTA UN CECO COMO DESTINO
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.movimientos_inventario
    ADD COLUMN IF NOT EXISTS ceco_id UUID REFERENCES public.centros_costo(id);

COMMENT ON COLUMN public.movimientos_inventario.ceco_id IS
  'Centro de costo al que se imputa la salida cuando no va contra una OT: lo que consume oficina, prevencion o comercial. MIG375.';

CREATE INDEX IF NOT EXISTS ix_mov_inv_ceco ON public.movimientos_inventario(ceco_id)
    WHERE ceco_id IS NOT NULL;

-- La regla siempre quiso decir «con destino imputable», no «con OT».
ALTER TABLE public.movimientos_inventario DROP CONSTRAINT IF EXISTS chk_mov_salida_requiere_ot;
DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_mov_salida_requiere_destino') THEN
        ALTER TABLE public.movimientos_inventario
            ADD CONSTRAINT chk_mov_salida_requiere_destino
            CHECK (tipo <> ALL (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])
                   OR ot_id IS NOT NULL
                   OR ceco_id IS NOT NULL);
    END IF;
END
$ck$;

COMMENT ON CONSTRAINT chk_mov_salida_requiere_destino ON public.movimientos_inventario IS
  'Nada sale de bodega sin destino imputable: una OT o un centro de costo. Reemplaza a chk_mov_salida_requiere_ot, que pedia OT porque era el unico destino que existia. MIG375.';


-- ══════════════════════════════════════════════════════════════════════════
-- 2. LA SALIDA DEL KARDEX ACEPTA CECO
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rpc_registrar_salida_inventario(
    p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid,
    p_usuario_id uuid, p_activo_id uuid DEFAULT NULL::uuid,
    p_lote character varying DEFAULT NULL::character varying,
    p_motivo text DEFAULT NULL::text,
    p_ceco_id uuid DEFAULT NULL::uuid          -- [MIG375] el otro destino válido
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_stock          RECORD;
    v_ot             RECORD;
    v_movimiento_id  UUID;
    v_costo_unitario NUMERIC(15,4);
    v_nuevo_stock    NUMERIC(12,3);
    v_producto       RECORD;
    v_bodega_faena   UUID;
    -- El folio en una variable simple y no en el record: un RECORD sin asignar
    -- revienta al leerle un campo aunque el CASE nunca llegue a ese brazo.
    v_ot_folio       TEXT;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('inventario', 'create', ARRAY['administrador','bodeguero','operador_abastecimiento']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'inventario', 'inventario', 'create' USING ERRCODE = '42501';
    END IF;

    -- [MIG375] Destino imputable: una OT o un centro de costo. Sin ninguno de
    -- los dos, el consumo no se le carga a nadie y el costo del mes miente.
    IF p_ot_id IS NULL AND p_ceco_id IS NULL THEN
        RAISE EXCEPTION 'REGLA: toda salida necesita destino — una OT o un centro de costo.';
    END IF;

    IF p_ot_id IS NOT NULL THEN
        SELECT id, estado, folio, faena_id INTO v_ot
        FROM ordenes_trabajo WHERE id = p_ot_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
        END IF;
        IF v_ot.estado NOT IN ('asignada', 'en_ejecucion', 'pausada') THEN
            RAISE EXCEPTION 'No se puede retirar material de OT en estado "%".', v_ot.estado;
        END IF;
        v_ot_folio := v_ot.folio;

        -- La bodega tiene que ser de la faena de la OT.
        SELECT faena_id INTO v_bodega_faena FROM bodegas WHERE id = p_bodega_id;
        IF v_bodega_faena IS NOT NULL AND v_ot.faena_id IS NOT NULL
           AND v_bodega_faena <> v_ot.faena_id THEN
            RAISE EXCEPTION 'La bodega seleccionada no pertenece a la faena de la OT. Bodega faena: %, OT faena: %.',
                v_bodega_faena, v_ot.faena_id;
        END IF;
    ELSE
        -- Salida a centro de costo: no hay faena que calzar, pero el CECO tiene
        -- que existir y estar vigente.
        IF NOT EXISTS (SELECT 1 FROM centros_costo
                        WHERE id = p_ceco_id AND COALESCE(activo, TRUE)) THEN
            RAISE EXCEPTION 'El centro de costo no existe o está inactivo.';
        END IF;
    END IF;

    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
    END IF;

    SELECT id, nombre, stock_minimo INTO v_producto FROM productos WHERE id = p_producto_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;

    SELECT cantidad, costo_promedio INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe stock de "%" en la bodega indicada.', v_producto.nombre;
    END IF;
    IF v_stock.cantidad < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente de "%". Disponible: %, solicitado: %.',
            v_producto.nombre, v_stock.cantidad, p_cantidad;
    END IF;

    v_costo_unitario := v_stock.costo_promedio;
    v_nuevo_stock := v_stock.cantidad - p_cantidad;
    v_movimiento_id := gen_random_uuid();

    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        ot_id, ceco_id, activo_id, lote, motivo, usuario_id, created_at
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, 'salida', p_cantidad,
        v_costo_unitario, p_ot_id, p_ceco_id,
        COALESCE(p_activo_id, (SELECT activo_id FROM ordenes_trabajo WHERE id = p_ot_id)),
        p_lote, p_motivo, p_usuario_id, NOW()
    );

    UPDATE stock_bodega
       SET cantidad = v_nuevo_stock, ultimo_movimiento = NOW(), updated_at = NOW()
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;

    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_id, p_producto_id, v_movimiento_id, NOW(), 'salida',
        p_cantidad, v_stock.cantidad, v_nuevo_stock,
        v_costo_unitario, v_stock.costo_promedio, v_stock.costo_promedio,
        p_cantidad * v_costo_unitario, v_nuevo_stock * v_stock.costo_promedio
    );

    -- El costo se acumula en la OT sólo cuando hay OT. Cuando va a un CECO,
    -- vive en el movimiento con su centro de costo.
    IF p_ot_id IS NOT NULL THEN
        UPDATE ordenes_trabajo
           SET costo_materiales = COALESCE(costo_materiales, 0) + (p_cantidad * v_costo_unitario),
               updated_at = NOW()
         WHERE id = p_ot_id;
    END IF;

    IF v_nuevo_stock < v_producto.stock_minimo THEN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES ('stock_minimo', 'Stock bajo: ' || v_producto.nombre,
                'Stock: ' || v_nuevo_stock || '. Mínimo: ' || v_producto.stock_minimo,
                'warning', 'producto', p_producto_id);
    END IF;

    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'producto', v_producto.nombre,
        'cantidad', p_cantidad,
        'costo_unitario', v_costo_unitario,
        'costo_total', p_cantidad * v_costo_unitario,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'ot_folio', v_ot_folio,
        'ceco', (SELECT codigo FROM centros_costo WHERE id = p_ceco_id));
END;
$function$;

DROP FUNCTION IF EXISTS public.rpc_registrar_salida_inventario(
    uuid, uuid, numeric, uuid, uuid, uuid, character varying, text);


-- ══════════════════════════════════════════════════════════════════════════
-- 3. LA SALIDA DE BODEGA HABILITA EL TIPO «ceco»
-- ══════════════════════════════════════════════════════════════════════════
DO $sb$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(
        'public.rpc_registrar_salida_bodega(tipo_salida_bodega_enum,uuid,uuid,uuid,text,jsonb,character varying,uuid,uuid,text,text)'::regprocedure)
      INTO v_def;

    -- El enum siempre tuvo «ceco»; lo que faltaba era dejarlo pasar.
    v_def := replace(v_def,
      $o$    IF p_tipo_salida <> 'ot' THEN$o$,
      $n$    IF p_tipo_salida NOT IN ('ot', 'ceco') THEN$n$);
    v_def := replace(v_def,
      $o$'MIG37 solo soporta salidas tipo ot. Tipos persona/ceco/venta/ajuste_autorizado se habilitan en MIG38.'$o$,
      $n$'Por ahora solo se admiten salidas contra una OT o contra un centro de costo (MIG375). Los tipos persona, venta y ajuste_autorizado siguen cerrados.'$n$);

    -- La OT deja de ser obligatoria: lo es el destino.
    v_def := replace(v_def,
      $o$    IF p_ot_id IS NULL THEN$o$,
      $n$    IF p_tipo_salida = 'ot' AND p_ot_id IS NULL THEN$n$);

    -- La OT sólo se valida si viene.
    v_def := replace(v_def,
      $o$    IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN$o$,
      $n$    IF p_ot_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN$n$);

    -- Y el kardex legacy recibe el centro de costo.
    --
    -- El reemplazo va sobre UNA SOLA LÍNEA a propósito: `pg_get_functiondef`
    -- devuelve el cuerpo con los saltos de línea que tenga guardados —acá son
    -- CRLF— así que cualquier patrón multilínea escrito con \n no calza y el
    -- replace se pierde en silencio. Como los parámetros van con nombre, el
    -- orden da lo mismo y basta con colgarse de una línea que aparece una vez.
    v_def := replace(v_def,
      $o$p_lote        => NULL,$o$,
      $n$p_ceco_id => p_ceco_id, p_lote => NULL,$n$);

    IF v_def LIKE '%MIG37 solo soporta%' THEN
        RAISE EXCEPTION 'MIG375: no se pudo habilitar el tipo ceco en rpc_registrar_salida_bodega';
    END IF;
    IF v_def NOT LIKE '%p_ceco_id => p_ceco_id%' THEN
        RAISE EXCEPTION 'MIG375: la salida no está pasando el centro de costo al kardex — el vale de oficina no se podría entregar';
    END IF;
    EXECUTE v_def;
END
$sb$;


-- ══════════════════════════════════════════════════════════════════════════
-- 4. EL VALE PUEDE IR A UN CENTRO DE COSTO
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.bodega_tickets
    ADD COLUMN IF NOT EXISTS ceco_id UUID REFERENCES public.centros_costo(id);

COMMENT ON COLUMN public.bodega_tickets.ceco_id IS
  'Centro de costo del vale cuando no va contra un equipo: lo que retira oficina, prevencion o comercial. MIG375.';

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bodega_ticket_destino') THEN
        ALTER TABLE public.bodega_tickets
            ADD CONSTRAINT chk_bodega_ticket_destino
            CHECK (ot_id IS NOT NULL OR activo_id IS NOT NULL OR ceco_id IS NOT NULL);
    END IF;
END
$c$;

-- El origen ahora tiene tres formas de nacer.
ALTER TABLE public.bodega_tickets DROP CONSTRAINT IF EXISTS chk_bodega_ticket_origen;
ALTER TABLE public.bodega_tickets
    ADD CONSTRAINT chk_bodega_ticket_origen CHECK (origen IN ('ot', 'manual', 'oficina'));


CREATE OR REPLACE FUNCTION public.rpc_crear_vale_oficina(
    p_ceco_id       uuid,
    p_items         jsonb,
    p_motivo        text,
    p_firma_url     text,
    p_bodega_id     uuid DEFAULT NULL,
    p_observacion   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user    UUID := auth.uid();
    v_folio   TEXT;
    v_periodo TEXT;
    v_sec     INT;
    v_id      UUID;
    v_qr      TEXT;
    v_n       INT := 0;
    v_sin_cat INT := 0;
    v_bodega  UUID;
    v_ceco    RECORD;
    v_it      JSONB;
    v_u       RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    -- A diferencia del vale de taller, éste no lo firma el jefe de taller:
    -- lo firma quien retira, y el control es el centro de costo al que queda
    -- cargado más su nombre. Por eso basta con tener sesión y perfil activo.
    IF NOT EXISTS (SELECT 1 FROM usuarios_perfil WHERE id = v_user AND activo) THEN
        RAISE EXCEPTION 'Su cuenta no está activa para retirar de bodega.'
            USING ERRCODE = '42501';
    END IF;
    IF p_firma_url IS NULL OR length(trim(p_firma_url)) = 0 THEN
        RAISE EXCEPTION 'Falta su firma: el vale es el respaldo de lo que se retira.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Escriba para qué es el pedido: es lo único que va a explicar este gasto a fin de mes.';
    END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El vale necesita al menos un ítem';
    END IF;

    SELECT * INTO v_ceco FROM centros_costo
     WHERE id = p_ceco_id AND COALESCE(activo, TRUE);
    IF v_ceco.id IS NULL THEN
        RAISE EXCEPTION 'Elija a qué centro de costo se carga el pedido.';
    END IF;

    -- Sin OT no hay faena que calzar: sirve cualquier bodega activa, y por
    -- omisión la que tenga el stock del taller.
    v_bodega := p_bodega_id;
    IF v_bodega IS NULL THEN
        SELECT b.id INTO v_bodega FROM bodegas b
         ORDER BY (SELECT count(*) FROM stock_bodega s WHERE s.bodega_id = b.id AND s.cantidad > 0) DESC,
                  b.created_at
         LIMIT 1;
    END IF;
    IF v_bodega IS NULL THEN RAISE EXCEPTION 'No hay bodegas configuradas.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)), 0) + 1 INTO v_sec
      FROM bodega_tickets WHERE folio LIKE 'TKT-' || v_periodo || '-%';
    v_folio := 'TKT-' || v_periodo || '-' || LPAD(v_sec::text, 5, '0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-' || v_folio;

    INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, ceco_id, bodega_id,
                               estado, emitido_por, firma_jefe_url, observacion, origen, motivo)
    VALUES (v_id, v_folio, v_qr, NULL, NULL, p_ceco_id, v_bodega,
            'emitido', v_user, p_firma_url, p_observacion, 'oficina', trim(p_motivo));

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

    BEGIN
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('vale_emitido',
                    'Vale de oficina: ' || v_folio,
                    'Preparar entrega para ' || v_ceco.nombre || ' — ' || v_n ||
                    ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END || '. ' || trim(p_motivo) ||
                    ' (QR ' || v_qr || ').',
                    'info', 'ticket_bodega', v_id, v_u.id, FALSE, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object(
        'success', TRUE, 'ticket_id', v_id, 'folio', v_folio, 'qr', v_qr,
        'items', v_n, 'items_sin_catalogo', v_sin_cat,
        'bodega_id', v_bodega,
        'ceco', v_ceco.codigo, 'ceco_nombre', v_ceco.nombre);
END;
$fn$;

REVOKE ALL ON FUNCTION public.rpc_crear_vale_oficina(uuid, jsonb, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_crear_vale_oficina(uuid, jsonb, text, text, uuid, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 5. LA ENTREGA: SI NO HAY OT, LA SALIDA VA AL CECO DEL VALE
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
    v_tipo tipo_salida_bodega_enum;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','supervisor','jefe_mantenimiento','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para entregar', v_rol; END IF;

    SELECT * INTO v_tk FROM bodega_tickets WHERE id = p_ticket_id;
    IF v_tk.id IS NULL THEN RAISE EXCEPTION 'Ticket no existe'; END IF;
    IF v_tk.estado IN ('entregado','anulado') THEN
        RAISE EXCEPTION 'Ticket % ya esta % — no se puede volver a usar', v_tk.folio, v_tk.estado; END IF;
    IF p_bodega_id IS NULL THEN RAISE EXCEPTION 'Debe elegir la bodega de despacho'; END IF;

    -- [MIG375] Dos formas de imputar, según cómo nació el vale.
    v_tipo := CASE WHEN v_tk.ot_id IS NOT NULL THEN 'ot' ELSE 'ceco' END::tipo_salida_bodega_enum;

    IF v_tk.ceco_id IS NOT NULL THEN
        v_ceco := v_tk.ceco_id;                       -- el vale ya dice a qué CECO va
    ELSE
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
             WHERE faena_id = v_faena AND COALESCE(activo, TRUE) ORDER BY created_at LIMIT 1;
        END IF;
        IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE codigo = 'CECO-BODEGA' LIMIT 1; END IF;
        IF v_ceco IS NULL THEN SELECT id INTO v_ceco FROM centros_costo WHERE COALESCE(activo, TRUE) ORDER BY created_at LIMIT 1; END IF;
    END IF;

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
        v_tipo, p_bodega_id, v_ceco, v_tk.ot_id,
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


-- ── El vale muestra su centro de costo ────────────────────────────────────
DROP VIEW IF EXISTS public.v_bodega_ticket;

CREATE VIEW public.v_bodega_ticket AS
SELECT tk.id, tk.folio, tk.qr_code, tk.ot_id, tk.activo_id, tk.bodega_id, tk.estado,
       tk.emitido_por, tk.firma_jefe_url, tk.observacion, tk.entregado_por, tk.entregado_at,
       tk.created_at, tk.origen, tk.motivo,
       tk.ceco_id, cc.codigo AS ceco_codigo, cc.nombre AS ceco_nombre,
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


-- ── Lo que consumió cada centro de costo, que es la razón de todo esto ────
CREATE OR REPLACE VIEW public.v_consumo_por_ceco AS
SELECT cc.id AS ceco_id, cc.codigo, cc.nombre, cc.area,
       date_trunc('month', m.created_at)::date AS mes,
       count(*)::int AS movimientos,
       SUM(m.cantidad) AS unidades,
       SUM(m.cantidad * m.costo_unitario) AS costo_clp
  FROM movimientos_inventario m
  JOIN centros_costo cc ON cc.id = m.ceco_id
 WHERE m.tipo = 'salida'
 GROUP BY cc.id, cc.codigo, cc.nombre, cc.area, date_trunc('month', m.created_at);

GRANT SELECT ON public.v_consumo_por_ceco TO authenticated;

COMMENT ON VIEW public.v_consumo_por_ceco IS
  'Lo que consumio cada centro de costo por mes. Sin esto el gasto de oficina no aparecia en ninguna parte. MIG375.';

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT oid::regprocedure::text FROM pg_proc WHERE proname='rpc_registrar_salida_inventario';
-- SELECT * FROM v_consumo_por_ceco ORDER BY mes DESC;
