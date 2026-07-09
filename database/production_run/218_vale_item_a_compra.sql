-- ============================================================================
-- SICOM-ICEO | 218 — Bodega decide qué entrega y qué manda a COMPRA desde el vale
-- ============================================================================
-- Pedido Manuel (2026-07-09): cuando la necesidad llega a bodega, Gustavo
-- selecciona lo que entrega y lo que no; lo que no hay (repuestos) genera una
-- solicitud de compra a adquisiciones CON TODOS LOS DATOS, visible en
-- /dashboard/bodega/seguimiento-repuestos.
--
-- Ya existe el pipeline (MIG201): aprobado sin stock → "por comprar" en el
-- tablero → Generar OC → en_compra → recibido (recepción FIFO) → vale.
-- Lo que falta es el GATILLO desde el despacho del vale:
--
--   rpc_ticket_item_a_compra(item, motivo):
--     * Si el ítem viene de un recurso (recurso_id, MIG197): lo devuelve a
--       'aprobado' → aparece en la pestaña "Por comprar" del seguimiento.
--     * Si el ítem nació directo de nc_materiales (vales MIG161 sin recurso):
--       crea el recurso 'aprobado' con los datos del ítem y lo enlaza.
--     * Alerta 'recurso_por_comprar' a adquisiciones (mismo patrón MIG201).
--     * El ítem queda pendiente en el vale (estado parcial): cuando llegue la
--       compra se despacha con el mismo vale.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='bodega_ticket_items' AND column_name='recurso_id') THEN
        RAISE EXCEPTION 'STOP — falta bodega_ticket_items.recurso_id (MIG197+).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ot_recursos_solicitados' AND column_name='oc_item_id') THEN
        RAISE EXCEPTION 'STOP — falta el seguimiento de compras (MIG201).';
    END IF;
END $$;


-- ── 1. RPC: mandar un ítem del vale a compra ─────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_ticket_item_a_compra(
    p_ticket_item_id UUID,
    p_motivo TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_it   RECORD;
    v_tk   RECORD;
    v_pendiente NUMERIC;
    v_recurso_id UUID;
    v_desc TEXT;
    v_nombre_user TEXT;
    v_u RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','supervisor','jefe_mantenimiento',
                     'subgerente_operaciones','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para enviar a compra', v_rol;
    END IF;

    SELECT * INTO v_it FROM bodega_ticket_items WHERE id = p_ticket_item_id;
    IF v_it.id IS NULL THEN RAISE EXCEPTION 'Item del vale no existe'; END IF;
    SELECT * INTO v_tk FROM bodega_tickets WHERE id = v_it.ticket_id;
    IF v_tk.estado = 'anulado' THEN RAISE EXCEPTION 'El vale % esta anulado', v_tk.folio; END IF;

    v_pendiente := v_it.cantidad_solicitada - COALESCE(v_it.cantidad_entregada, 0);
    IF v_pendiente <= 0 THEN
        RAISE EXCEPTION 'El item ya fue entregado completo — no hay nada que comprar';
    END IF;

    v_desc := COALESCE((SELECT nombre FROM productos WHERE id = v_it.producto_id),
                       v_it.descripcion, 'material');
    SELECT nombre_completo INTO v_nombre_user FROM usuarios_perfil WHERE id = v_user;

    IF v_it.recurso_id IS NOT NULL THEN
        -- Recurso existente: vuelve al pool "por comprar" del seguimiento
        -- (aprobado + sin OC + sin stock = pestaña Por comprar, MIG201).
        UPDATE ot_recursos_solicitados
           SET estado = 'aprobado',
               cantidad_aprobada = COALESCE(cantidad_aprobada, v_pendiente),
               comentario = TRIM(BOTH E'\n' FROM COALESCE(comentario,'') || E'\n'
                   || 'Bodega lo envió a COMPRA desde el vale ' || v_tk.folio
                   || COALESCE(' — ' || NULLIF(TRIM(p_motivo),''), '')
                   || ' (' || COALESCE(v_nombre_user,'bodega') || ')'),
               updated_at = NOW()
         WHERE id = v_it.recurso_id
           AND estado IN ('en_vale','aprobado','recibido');
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El recurso del item ya esta en compra o en otro estado — revisa el seguimiento';
        END IF;
        v_recurso_id := v_it.recurso_id;
    ELSE
        -- Ítem sin recurso (vale MIG161 desde nc_materiales): crear la
        -- solicitud de compra con los datos del ítem para que entre al tablero.
        INSERT INTO ot_recursos_solicitados (
            client_uuid, ot_id, producto_id, descripcion, unidad,
            cantidad, cantidad_aprobada, comentario, estado,
            solicitado_nombre, agregado_por_jefe, validado_por, validado_at,
            ticket_id, instance_item_id, created_at, updated_at
        ) VALUES (
            gen_random_uuid(), v_tk.ot_id, v_it.producto_id, v_it.descripcion, v_it.unidad,
            v_pendiente, v_pendiente,
            'Bodega lo envió a COMPRA desde el vale ' || v_tk.folio
                || COALESCE(' — ' || NULLIF(TRIM(p_motivo),''), '')
                || ' (' || COALESCE(v_nombre_user,'bodega') || ')',
            'aprobado',
            v_nombre_user, true, v_user, NOW(),
            v_it.ticket_id, NULL, NOW(), NOW()
        ) RETURNING id INTO v_recurso_id;

        UPDATE bodega_ticket_items SET recurso_id = v_recurso_id WHERE id = p_ticket_item_id;
    END IF;

    -- Alerta a adquisiciones (mismo patrón MIG201)
    BEGIN
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','operador_abastecimiento')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('recurso_por_comprar',
                    'Solicitud de compra desde bodega: ' || v_tk.folio,
                    'Bodega no puede entregar ' || v_pendiente || ' ' || COALESCE(v_it.unidad,'un')
                      || ' de ' || v_desc || ' (vale ' || v_tk.folio || ')'
                      || COALESCE('. Motivo: ' || NULLIF(TRIM(p_motivo),''), '')
                      || '. Revisar en Seguimiento repuestos.',
                    'warning', 'recurso_compra', v_recurso_id, v_u.id, false, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;  -- la alerta nunca bloquea la operación
    END;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_recurso_id,
        'cantidad', v_pendiente, 'vale', v_tk.folio);
END $$;

REVOKE EXECUTE ON FUNCTION rpc_ticket_item_a_compra(UUID, TEXT) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION rpc_ticket_item_a_compra(UUID, TEXT) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rpc_ok', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_ticket_item_a_compra')),
    'usa_recurso_id', (SELECT prosrc LIKE '%recurso_id%' FROM pg_proc
        WHERE proname='rpc_ticket_item_a_compra'),
    'alerta_adquisiciones', (SELECT prosrc LIKE '%recurso_por_comprar%' FROM pg_proc
        WHERE proname='rpc_ticket_item_a_compra')
) AS resultado;

NOTIFY pgrst, 'reload schema';
