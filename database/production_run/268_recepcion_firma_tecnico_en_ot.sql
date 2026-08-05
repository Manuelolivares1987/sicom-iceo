-- ============================================================================
-- SICOM-ICEO | 268 — Recepción: la firma del inspector también va a la OT
-- ============================================================================
-- Problema (detectado en IR-202607-00001 / OT-202607-00049):
--   «Enviar a revisión» nunca podía cerrar la inspección. fn_cerrar_inspeccion_
--   recepcion pasa la OT de inspección a 'ejecutada_ok', y el trigger
--   validar_cierre_ot exige tres cosas: evidencia fotográfica, ítems
--   obligatorios del checklist respondidos y FIRMA DEL TÉCNICO EN LA OT
--   (ordenes_trabajo.firma_tecnico_url).
--
--   Las dos primeras dependen del trabajo del inspector y está bien exigirlas.
--   La tercera era un callejón sin salida: el inspector firma en pantalla, pero
--   esa firma solo se guardaba en informes_recepcion.inspector_firma_url. Nada
--   en todo el flujo de recepción escribe ordenes_trabajo.firma_tecnico_url, así
--   que aunque el checklist quedara perfecto el cierre igual fallaba con
--   «Se requiere la firma del tecnico responsable».
--
-- Arreglo: la misma firma que ya se recibe por parámetro se estampa en la OT
--   junto con el cierre. Es la firma del responsable del trabajo, que es
--   exactamente lo que el trigger pide.
--
-- No afecta las otras dos exigencias: una recepción sin checklist ni fotos
-- sigue sin poder cerrarse (a propósito).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_cerrar_inspeccion_recepcion(
    p_informe_id UUID,
    p_firma_tecnico_url TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_user_id  UUID;
    v_informe  RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = p_informe_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Informe % no existe', p_informe_id;
    END IF;

    IF v_informe.estado NOT IN ('en_inspeccion') THEN
        RAISE EXCEPTION 'Informe en estado % no puede cerrarse como inspeccion', v_informe.estado;
    END IF;

    UPDATE informes_recepcion
       SET estado              = 'borrador',
           inspector_id        = COALESCE(inspector_id, v_user_id),
           inspector_firma_url = p_firma_tecnico_url,
           updated_at          = NOW()
     WHERE id = p_informe_id;

    -- Cerrar OT de inspeccion. La firma del inspector viaja a la OT: es la
    -- firma del tecnico responsable que exige validar_cierre_ot, y sin ella el
    -- cierre era imposible por diseno.
    UPDATE ordenes_trabajo
       SET estado            = 'ejecutada_ok',
           firma_tecnico_url = COALESCE(firma_tecnico_url, p_firma_tecnico_url),
           fecha_termino     = NOW(),
           updated_at        = NOW()
     WHERE id = v_informe.ot_inspeccion_id;

    RETURN jsonb_build_object('success', true, 'informe_id', p_informe_id, 'estado', 'borrador');
END $$;

GRANT EXECUTE ON FUNCTION fn_cerrar_inspeccion_recepcion(UUID, TEXT) TO authenticated;

-- ── VALIDACION ──────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'funcion_actualizada', (SELECT prosrc ILIKE '%firma_tecnico_url = COALESCE%'
                              FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                             WHERE n.nspname = 'public' AND p.proname = 'fn_cerrar_inspeccion_recepcion'),
    'informes_en_inspeccion', (SELECT COUNT(*) FROM informes_recepcion WHERE estado = 'en_inspeccion')
) AS validacion;
