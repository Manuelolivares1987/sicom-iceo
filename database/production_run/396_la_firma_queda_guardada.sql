-- ============================================================================
-- MIG396 · La firma del jefe queda guardada, y el vale automático sale firmado
-- ----------------------------------------------------------------------------
-- LA PREGUNTA
-- Manuel, 25-08-2026: «¿es factible cargar la firma, así hacemos más expedito
-- esto?». Sí, y el campo ya existía sin usarse: `usuarios_perfil.firma_url`,
-- vacío en las 20 cuentas activas.
--
-- CUÁL FIRMA — LA DISTINCIÓN QUE IMPORTA
-- El vale tiene tres líneas y NO son intercambiables:
--
--   1. «Jefe de Taller (autoriza)»  → autoriza que el material salga
--   2. «Operador (retira)»          → PRUEBA de que el operador lo recibió
--   3. «Bodega (entrega)»           → prueba de que bodega lo entregó
--
-- La que falta en el vale automático es la 1, y ésa sí se puede guardar: el
-- jefe autoriza al aprobar el repuesto, con su cuenta y con fecha. Guardar su
-- firma sólo le pone cara a un acto que ya ocurrió, y MEJORA el control frente
-- a MIG395, que dejaba el vale sin firma alguna.
--
-- Las 2 y 3 son otra cosa: son el recibo. Dejarlas pre-cargadas haría que el
-- sistema afirmara que el operador retiró un material antes de que lo retire, y
-- que bodega lo entregó antes de entregarlo. Eso no se guarda: se firma en el
-- mesón, que es el único momento en que esa firma significa algo. Por eso esta
-- migración toca únicamente la firma de quien autoriza.
--
-- CÓMO FUNCIONA
-- Si quien aprueba tiene firma guardada, el vale automático nace firmado por
-- él. Si no la tiene, sigue saliendo como en MIG395: «Autorizado en plataforma»
-- con nombre y fecha. Nunca queda una línea en blanco haciendo parecer que
-- nadie autorizó.
-- ============================================================================

BEGIN;

COMMENT ON COLUMN public.usuarios_perfil.firma_url IS
  'MIG396: firma guardada de quien AUTORIZA (jefatura). Se estampa sola en el vale automático. No sirve para las firmas de recibo (operador retira / bodega entrega): esas se firman en el mesón porque son la prueba de la entrega.';

-- ── 1. Cada uno guarda la suya ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_guardar_mi_firma(p_firma_url text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_user UUID := auth.uid();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- Sólo sobre la propia cuenta: la firma de otro no se carga por nadie más,
    -- o deja de ser una firma.
    UPDATE usuarios_perfil
       SET firma_url = NULLIF(TRIM(COALESCE(p_firma_url,'')),'')
     WHERE id = v_user;
    IF NOT FOUND THEN RAISE EXCEPTION 'El perfil no existe'; END IF;
    RETURN jsonb_build_object('success', true,
                              'guardada', NULLIF(TRIM(COALESCE(p_firma_url,'')),'') IS NOT NULL);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_guardar_mi_firma(text) TO authenticated;

-- ── 2. El vale automático la usa ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vale_auto_recurso(p_recurso_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_r RECORD; v_ot RECORD; v_tk UUID; v_folio TEXT; v_qr TEXT;
    v_periodo TEXT; v_sec INT; v_bodega UUID; v_pat TEXT;
    v_quien TEXT; v_firma TEXT; v_n INT; v_u RECORD; v_msg TEXT; v_upd INT;
    v_autoriza UUID;
BEGIN
    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id;
    IF v_r.id IS NULL OR v_r.estado <> 'aprobado' OR v_r.ticket_id IS NOT NULL THEN
        RETURN NULL;
    END IF;

    SELECT o.id, o.activo_id, o.faena_id, o.folio INTO v_ot
      FROM ordenes_trabajo o WHERE o.id = v_r.ot_id;
    IF v_ot.activo_id IS NULL THEN RETURN NULL; END IF;

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
        SELECT b.id INTO v_bodega
          FROM bodegas b
         WHERE b.faena_id = v_ot.faena_id
         ORDER BY (b.tipo = 'fija') DESC, b.codigo
         LIMIT 1;

        v_autoriza := COALESCE(v_r.validado_por, v_r.solicitado_por);
        -- [MIG396] Si quien autoriza tiene firma guardada, el vale sale firmado.
        SELECT COALESCE(u.nombre_completo, u.email, 'jefatura'), u.firma_url
          INTO v_quien, v_firma
          FROM usuarios_perfil u WHERE u.id = v_autoriza;

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
                'emitido', v_autoriza, v_firma, 'auto',
                'Vale automático: se emite al aprobar el repuesto. Autorizado en plataforma por '
                || v_quien || ' el ' || to_char(NOW(), 'DD-MM-YYYY HH24:MI')
                || CASE WHEN v_firma IS NULL THEN ' (sin firma manuscrita).'
                        ELSE ' (firma registrada).' END);
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

REVOKE ALL ON FUNCTION public.fn_vale_auto_recurso(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_vale_auto_recurso(uuid) FROM anon, authenticated;

COMMIT;
