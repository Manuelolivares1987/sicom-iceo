-- ============================================================================
-- MIG395 · El vale sale solo, y bodega se entera sin que nadie se acuerde
-- ----------------------------------------------------------------------------
-- LA QUEJA
-- Gustavo (Bodega Coquimbo), 25-08-2026: «don Ricardo me avisa que realizó las
-- no conformidades del RSCY-85, pero no me llegó como vale ni aviso».
--
-- Y era cierto. El jefe aprobó 5 repuestos del RSCY-85 el 24 y el 25 de agosto,
-- y los 5 quedaron `aprobado` con `ticket_id` NULL. El vale no era automático:
-- era un botón «Generar vale (N)» que había que acordarse de apretar, y nada
-- avisaba que faltaba. Sistémico: 11 recursos aprobados sin vale, el más viejo
-- del 15 de julio.
--
-- Peor todavía: `rpc_ot_recurso_agregar` —el camino por el que la jefatura
-- agrega ítems ella misma, 20 de los 31 recursos del sistema— era el ÚNICO de
-- los tres RPC sin ninguna alerta. Nace `aprobado` con `validado_por` ya puesto,
-- así que se salta `rpc_ot_recurso_validar` por completo, que es justo donde
-- vivía el aviso a bodega. Todo lo que agregaba la jefatura era invisible.
--
-- LA DECISIÓN (Manuel, 25-08-2026)
-- «que se genere automáticamente y le llegue en plataforma a Gustavo».
--
-- CÓMO QUEDA
-- Aprobar un recurso ES emitir el vale. No hay paso intermedio que olvidar.
--
--   · UN VALE POR EQUIPO, NO UNO POR ÍTEM. Si el equipo ya tiene un vale
--     automático abierto y sin nada entregado, el ítem se suma a ese. El
--     operador va una vez a bodega, no cinco. Si bodega ya empezó a despachar,
--     el vale siguiente es nuevo: meterle ítems a un vale a medio entregar
--     mezcla lo que se retiró con lo que no.
--
--   · LA CAMPANITA NO SE REPITE. Si el aviso del vale sigue sin leer, se
--     actualiza con el conteo nuevo en vez de apilar cinco avisos del mismo
--     vale.
--
-- LO QUE SE PIERDE, Y CON QUÉ SE REEMPLAZA
-- El vale manual lleva la firma manuscrita del jefe (`firma_jefe_url`, que
-- `rpc_crear_ticket_bodega` exige). Un vale que sale solo no puede tenerla.
-- No se deja el campo en blanco y ya: el vale automático nace con
-- `origen = 'auto'` y con la autorización escrita en la observación —quién
-- aprobó, con qué cuenta y cuándo—. La aprobación en plataforma queda como el
-- acto que autoriza la salida, que es lo que de hecho ya era. El botón manual
-- con firma sigue existiendo intacto para cuando se quiera esa formalidad.
--
-- EL BOTÓN MANUAL NO SE TOCA
-- `rpc_crear_ticket_bodega` queda igual. Lo que cambia es que ya casi nunca va
-- a encontrar algo pendiente, porque el vale ya salió.
-- ============================================================================

BEGIN;

-- ── 1. El vale automático es un origen propio ─────────────────────────────
-- Distinguirlo importa: el impreso no puede mostrar una línea de firma vacía
-- como si el jefe no hubiera firmado, y la auditoría tiene que poder separar
-- lo que se autorizó a mano de lo que se autorizó en plataforma.
ALTER TABLE public.bodega_tickets DROP CONSTRAINT IF EXISTS chk_bodega_ticket_origen;
ALTER TABLE public.bodega_tickets ADD CONSTRAINT chk_bodega_ticket_origen
  CHECK (origen = ANY (ARRAY['ot'::text, 'manual'::text, 'oficina'::text, 'auto'::text]));

-- ── 2. El motor ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vale_auto_recurso(p_recurso_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_r RECORD; v_ot RECORD; v_tk UUID; v_folio TEXT; v_qr TEXT;
    v_periodo TEXT; v_sec INT; v_bodega UUID; v_pat TEXT;
    v_quien TEXT; v_n INT; v_u RECORD; v_msg TEXT; v_upd INT;
BEGIN
    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id;
    -- Sólo lo aprobado y todavía sin vale. Cualquier otra cosa se ignora en
    -- silencio: esta función se llama desde los RPC y no debe hacerlos fallar.
    IF v_r.id IS NULL OR v_r.estado <> 'aprobado' OR v_r.ticket_id IS NOT NULL THEN
        RETURN NULL;
    END IF;

    SELECT o.id, o.activo_id, o.faena_id, o.folio INTO v_ot
      FROM ordenes_trabajo o WHERE o.id = v_r.ot_id;
    IF v_ot.activo_id IS NULL THEN RETURN NULL; END IF;

    -- ¿Hay un vale automático abierto de este equipo al que todavía no le
    -- despachan nada? Ese es el que corresponde engordar.
    SELECT bt.id INTO v_tk
      FROM bodega_tickets bt
     WHERE bt.activo_id = v_ot.activo_id
       AND bt.estado = 'emitido'
       AND bt.origen = 'auto'
       AND NOT EXISTS (SELECT 1 FROM bodega_ticket_items bti
                        WHERE bti.ticket_id = bt.id AND bti.cantidad_entregada > 0)
     ORDER BY bt.created_at DESC
     LIMIT 1;

    IF v_tk IS NULL THEN
        -- La bodega de la faena de la OT. Si la faena no tiene, queda nula y el
        -- bodeguero la elige al despachar (el vale igual aparece en su bandeja).
        SELECT b.id INTO v_bodega
          FROM bodegas b
         WHERE b.faena_id = v_ot.faena_id
         ORDER BY (b.tipo = 'fija') DESC, b.codigo
         LIMIT 1;

        SELECT COALESCE(u.nombre_completo, u.email, 'jefatura') INTO v_quien
          FROM usuarios_perfil u WHERE u.id = COALESCE(v_r.validado_por, v_r.solicitado_por);

        PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
        v_periodo := to_char(now(),'YYYYMM');
        SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)),0)+1 INTO v_sec
          FROM bodega_tickets WHERE folio LIKE 'TKT-'||v_periodo||'-%';
        v_folio := 'TKT-'||v_periodo||'-'||LPAD(v_sec::text,5,'0');
        v_tk    := gen_random_uuid();
        v_qr    := 'SICOM-'||v_folio;

        INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, bodega_id,
                                   estado, emitido_por, firma_jefe_url, origen, observacion)
        VALUES (v_tk, v_folio, v_qr, v_ot.id, v_ot.activo_id, v_bodega,
                'emitido', COALESCE(v_r.validado_por, v_r.solicitado_por), NULL, 'auto',
                'Vale automático: se emite al aprobar el repuesto. Autorizado en plataforma por '
                || v_quien || ' el ' || to_char(NOW(), 'DD-MM-YYYY HH24:MI') || ' (sin firma manuscrita).');
    END IF;

    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad,
                                    cantidad_solicitada, recurso_id, comentario)
    SELECT v_tk, v_r.producto_id,
           COALESCE(v_r.descripcion, pr.nombre),
           COALESCE(v_r.unidad, pr.unidad_medida),
           COALESCE(v_r.cantidad_aprobada, v_r.cantidad),
           v_r.id, v_r.comentario
      FROM (SELECT 1) x
      LEFT JOIN productos pr ON pr.id = v_r.producto_id;

    UPDATE ot_recursos_solicitados
       SET estado = 'en_vale', ticket_id = v_tk, updated_at = NOW()
     WHERE id = p_recurso_id;

    -- ── La campanita a bodega ─────────────────────────────────────────────
    -- Nunca dejar que el aviso tumbe la aprobación.
    BEGIN
        SELECT folio, qr_code INTO v_folio, v_qr FROM bodega_tickets WHERE id = v_tk;
        SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id = v_tk;
        SELECT COALESCE(a.patente, a.codigo) INTO v_pat FROM activos a WHERE a.id = v_ot.activo_id;

        v_msg := 'Preparar entrega para ' || COALESCE(v_pat,'equipo') || ' — ' || v_n
              || ' ítem' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END
              || ' (' || COALESCE(v_ot.folio,'OT') || '). El operador retira con el vale (QR '
              || v_qr || ').';

        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','bodeguero','operador_abastecimiento')
        LOOP
            -- Si el aviso de ESTE vale sigue sin leer, se actualiza el conteo en
            -- vez de apilar un aviso por cada ítem aprobado.
            UPDATE alertas
               SET mensaje = v_msg, created_at = NOW()
             WHERE tipo = 'vale_emitido' AND entidad_tipo = 'ticket_bodega'
               AND entidad_id = v_tk AND destinatario_id = v_u.id AND leida = false;
            GET DIAGNOSTICS v_upd = ROW_COUNT;

            IF v_upd = 0 THEN
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                     destinatario_id, leida, created_at)
                VALUES ('vale_emitido', 'Vale de bodega: ' || v_folio, v_msg,
                        'info', 'ticket_bodega', v_tk, v_u.id, false, NOW());
            END IF;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN v_tk;
END $function$;

-- No es una puerta pública: se llama desde los RPC que ya validan quién aprueba.
REVOKE ALL ON FUNCTION public.fn_vale_auto_recurso(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_vale_auto_recurso(uuid) FROM anon, authenticated;

COMMENT ON FUNCTION public.fn_vale_auto_recurso(uuid) IS
  'MIG395: aprobar un recurso emite el vale. Suma al vale automático abierto del equipo si no tiene entregas, o crea uno nuevo. Avisa a bodega sin repetir la campanita.';

-- ── 3. Aprobar emite el vale ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_ot_recurso_validar(
    p_recurso_id uuid, p_accion text,
    p_cantidad_aprobada numeric DEFAULT NULL::numeric,
    p_nota text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_r RECORD; v_stock NUMERIC; v_folio TEXT; v_u RECORD; v_desc TEXT;
    v_tk UUID; v_tk_folio TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Solo la jefatura valida recursos (rol: %)', v_rol; END IF;
    IF p_accion NOT IN ('aprobar','rechazar') THEN
        RAISE EXCEPTION 'Acción inválida: % (aprobar|rechazar)', p_accion; END IF;

    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id FOR UPDATE;
    IF v_r.id IS NULL THEN RAISE EXCEPTION 'Recurso no existe'; END IF;
    IF v_r.estado NOT IN ('solicitado','aprobado','rechazado') THEN
        RAISE EXCEPTION 'El recurso ya está en % — se gestiona desde el seguimiento de compra/vale', v_r.estado; END IF;

    UPDATE ot_recursos_solicitados
       SET estado            = CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END,
           cantidad_aprobada = CASE WHEN p_accion = 'aprobar'
                                    THEN COALESCE(p_cantidad_aprobada, cantidad_aprobada, cantidad)
                                    ELSE NULL END,
           validado_por = v_user, validado_at = NOW(),
           nota_jefe = COALESCE(p_nota, nota_jefe),
           updated_at = NOW()
     WHERE id = p_recurso_id;

    -- [MIG201] Aprobado sin stock (o fuera de catálogo) ⇒ hay que COMPRAR:
    -- alerta a abastecimiento para que aparezca en el seguimiento.
    IF p_accion = 'aprobar' THEN
        SELECT COALESCE(SUM(sb.cantidad),0) INTO v_stock
          FROM stock_bodega sb WHERE sb.producto_id = v_r.producto_id;
        IF v_r.producto_id IS NULL OR COALESCE(v_stock,0) <= 0 THEN
            BEGIN
                SELECT ot.folio INTO v_folio FROM ordenes_trabajo ot WHERE ot.id = v_r.ot_id;
                v_desc := COALESCE(v_r.descripcion, (SELECT nombre FROM productos WHERE id = v_r.producto_id), 'material');
                FOR v_u IN
                    SELECT id FROM usuarios_perfil
                     WHERE activo = true AND rol IN ('administrador','operador_abastecimiento','bodeguero')
                LOOP
                    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                         destinatario_id, leida, created_at)
                    VALUES ('recurso_por_comprar',
                            'Repuesto por comprar: ' || COALESCE(v_folio, 'OT'),
                            'Aprobado sin stock: ' || COALESCE(p_cantidad_aprobada, v_r.cantidad) || ' '
                              || COALESCE(v_r.unidad, 'un') || ' de ' || v_desc
                              || CASE WHEN v_r.producto_id IS NULL THEN ' (fuera de catálogo)' ELSE '' END,
                            'warning', 'recurso_compra', v_r.id, v_u.id, false, NOW());
                END LOOP;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;

        -- [MIG395] Aprobar ES emitir el vale. Antes quedaba esperando a que
        -- alguien se acordara del botón, y bodega no se enteraba nunca.
        v_tk := fn_vale_auto_recurso(p_recurso_id);
        IF v_tk IS NOT NULL THEN
            SELECT folio INTO v_tk_folio FROM bodega_tickets WHERE id = v_tk;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'recurso_id', p_recurso_id,
        'estado', CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END,
        'ticket_id', v_tk, 'ticket_folio', v_tk_folio);
END $function$;

-- ── 4. Y agregar también, que era el camino mudo ──────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_ot_recurso_agregar(
    p_ot_id uuid, p_cantidad numeric,
    p_producto_id uuid DEFAULT NULL::uuid,
    p_descripcion character varying DEFAULT NULL::character varying,
    p_unidad character varying DEFAULT NULL::character varying,
    p_comentario text DEFAULT NULL::text,
    p_instance_item_id uuid DEFAULT NULL::uuid,
    p_fotos text[] DEFAULT NULL::text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_id UUID; v_unidad VARCHAR; v_tk UUID; v_tk_folio TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Solo la jefatura agrega recursos (rol: %)', v_rol; END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el producto del catálogo o una descripción'; END IF;
    IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN
        RAISE EXCEPTION 'OT no existe'; END IF;
    IF p_producto_id IS NOT NULL THEN
        SELECT unidad_medida INTO v_unidad FROM productos WHERE id = p_producto_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        ot_id, producto_id, descripcion, unidad, cantidad, cantidad_aprobada,
        comentario, estado, solicitado_por, agregado_por_jefe, validado_por, validado_at,
        instance_item_id, fotos)
    VALUES (
        p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad),
        p_cantidad, p_cantidad, p_comentario, 'aprobado', v_user, true, v_user, NOW(),
        p_instance_item_id, NULLIF(p_fotos, ARRAY[]::TEXT[]))
    RETURNING id INTO v_id;

    -- [MIG395] Este era el único de los tres RPC sin ninguna alerta: nace
    -- aprobado con validado_por puesto, así que se salta rpc_ot_recurso_validar
    -- —donde vivía el aviso a bodega— y todo lo que agregaba la jefatura
    -- quedaba invisible. Ahora emite el vale igual que aprobar, que es lo que
    -- de hecho está haciendo.
    v_tk := fn_vale_auto_recurso(v_id);
    IF v_tk IS NOT NULL THEN
        SELECT folio INTO v_tk_folio FROM bodega_tickets WHERE id = v_tk;
    END IF;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id,
                              'ticket_id', v_tk, 'ticket_folio', v_tk_folio);
END $function$;

-- ── 5. Los que quedaron esperando ─────────────────────────────────────────
-- 11 recursos aprobados sin vale, el más viejo del 15 de julio. Los 5 del
-- RSCY-85 son los que Ricardo está esperando.
DO $r$
DECLARE v_r RECORD; v_tk UUID; v_n INT := 0; v_vales UUID[] := '{}';
BEGIN
    FOR v_r IN
        SELECT r.id, o.folio, a.patente, a.codigo
          FROM ot_recursos_solicitados r
          JOIN ordenes_trabajo o ON o.id = r.ot_id
          JOIN activos a ON a.id = o.activo_id
         WHERE r.estado = 'aprobado' AND r.ticket_id IS NULL
         ORDER BY o.activo_id, r.created_at
    LOOP
        v_tk := fn_vale_auto_recurso(v_r.id);
        IF v_tk IS NOT NULL THEN
            v_n := v_n + 1;
            IF NOT (v_tk = ANY(v_vales)) THEN v_vales := v_vales || v_tk; END IF;
        END IF;
    END LOOP;
    RAISE NOTICE 'Rezagados: % ítems en % vale(s)', v_n, array_length(v_vales,1);

    FOR v_r IN
        SELECT bt.folio, COALESCE(a.patente, a.codigo) AS eq, count(bti.id) AS items
          FROM bodega_tickets bt
          LEFT JOIN activos a ON a.id = bt.activo_id
          LEFT JOIN bodega_ticket_items bti ON bti.ticket_id = bt.id
         WHERE bt.id = ANY(v_vales)
         GROUP BY bt.folio, a.patente, a.codigo
         ORDER BY bt.folio
    LOOP
        RAISE NOTICE '  % · % · % ítems', v_r.folio, v_r.eq, v_r.items;
    END LOOP;
END
$r$;

-- ── 6. Que no quede ninguno ───────────────────────────────────────────────
DO $r$
DECLARE v_q INT;
BEGIN
    SELECT count(*) INTO v_q FROM ot_recursos_solicitados
     WHERE estado = 'aprobado' AND ticket_id IS NULL;
    IF v_q > 0 THEN
        RAISE WARNING 'Quedan % recursos aprobados sin vale (revisar: OT sin activo_id).', v_q;
    ELSE
        RAISE NOTICE 'No queda ningún recurso aprobado sin vale.';
    END IF;
END
$r$;

COMMIT;
