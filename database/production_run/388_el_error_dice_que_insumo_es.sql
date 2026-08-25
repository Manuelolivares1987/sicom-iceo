-- ============================================================================
-- MIG388 · El error dice qué insumo es
-- ----------------------------------------------------------------------------
-- Probando MIG386, intentar despachar algo sin aprobar devolvía:
--
--     El insumo «sin nombre» está en «solicitado»
--
-- «Sin nombre» porque cuando el pedido viene del catálogo, `descripcion` queda
-- en NULL y el nombre vive en `productos`. Quien lee ese mensaje tiene diez
-- pedidos en pantalla y no sabe cuál de los diez es el que falta aprobar.
--
-- Un mensaje de error que no dice de qué está hablando obliga a adivinar, y
-- adivinar en bodega termina en un despacho equivocado.
-- ============================================================================

BEGIN;

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
        -- [MIG388] El nombre sale del catálogo cuando el pedido no trae texto:
        -- así el error puede decir de qué está hablando.
        SELECT r.*, COALESCE(r.cantidad_aprobada, r.cantidad) AS cant,
               COALESCE(r.descripcion, pr.nombre, 'un insumo') AS nombre_visible,
               pr.unidad_medida
          FROM public.ot_recursos_solicitados r
          LEFT JOIN public.productos pr ON pr.id = r.producto_id
         WHERE r.id = ANY (p_recurso_ids)
    LOOP
        IF v_r.estado <> 'aprobado' THEN
            RAISE EXCEPTION 'El insumo «%» está en «%»: sólo se despacha lo que el jefe aprobó.',
                v_r.nombre_visible, v_r.estado USING ERRCODE = '42501';
        END IF;

        INSERT INTO public.bodega_ticket_items
               (ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, comentario)
        VALUES (v_id, v_r.producto_id, v_r.nombre_visible,
                COALESCE(v_r.unidad, v_r.unidad_medida), v_r.cant, v_r.comentario);

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

COMMIT;
