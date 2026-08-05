-- ============================================================================
-- SICOM-ICEO | 269 — Recepción IR-202607-00001: reconectar su checklist lleno
-- ============================================================================
-- Corrección de datos de un informe puntual (no cambia lógica).
--
-- Qué pasó: el activo 9ca9b860 (informe IR-202607-00001) tiene CUATRO instancias
-- de checklist de recepción. La que el inspector realmente llenó —169/169 ítems
-- respondidos y 33 fotos, creada el 24-jul 14:12— quedó colgada de la OT
-- PREVENTIVA OT-202607-00050, no de la OT de inspección OT-202607-00049 del
-- informe. De esa OT colgaba una instancia vacía (0 respondidos, 0 fotos).
--
-- Consecuencia: la pantalla del informe no encontraba checklist (busca por
-- informe_recepcion_id, que estaba NULL en las cuatro) y «Enviar a revisión»
-- fallaba, porque el trigger validar_cierre_ot veía 0 evidencias y 152 ítems
-- obligatorios pendientes en la instancia vacía.
--
-- Arreglo: el checklist lleno se vincula al informe y a su OT de inspección; la
-- instancia vacía se descuelga de esa OT (no se borra: queda disponible por si
-- hay que revisarla).
--
-- destructivo-ok: UPDATEs de datos intencionales sobre filas identificadas una a
-- una. No se borra nada.
-- ============================================================================

DO $$
DECLARE
    v_informe  CONSTANT UUID := 'cea96976-e6e5-4a21-8741-82b3931c8e03';
    v_ot_insp  CONSTANT UUID := '958c3bbe-1b7b-41d7-ba56-b99fa7e60061';
    v_llena    CONSTANT UUID := '7ff61302-93eb-47bc-ab15-a5ee4d6bfa51';
    v_vacia    CONSTANT UUID := 'ddd37b77-4641-4db1-a2e0-f8f4687b72be';
    v_resp     INT;
BEGIN
    -- Salvaguarda: solo mover la instancia si de verdad está llena.
    SELECT COUNT(*) INTO v_resp
      FROM checklist_v2_instance_item
     WHERE instance_id = v_llena AND resultado IS NOT NULL AND resultado <> 'pendiente';
    IF v_resp = 0 THEN
        RAISE EXCEPTION 'La instancia % no tiene respuestas: no se reconecta nada', v_llena;
    END IF;

    UPDATE checklist_v2_instance
       SET informe_recepcion_id = v_informe,
           ot_id                = v_ot_insp,
           updated_at           = NOW()
     WHERE id = v_llena;

    UPDATE checklist_v2_instance
       SET ot_id = NULL, updated_at = NOW()
     WHERE id = v_vacia;

    RAISE NOTICE 'Checklist % (% respuestas) reconectado al informe % / OT %', v_llena, v_resp, v_informe, v_ot_insp;
END $$;

-- ── VALIDACION ──────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'checklist_del_informe', (SELECT COUNT(*) FROM checklist_v2_instance
                               WHERE informe_recepcion_id = 'cea96976-e6e5-4a21-8741-82b3931c8e03'),
    'obligatorios_pendientes', (SELECT COUNT(*) FROM v_taller_ot_checklist_v3
                                 WHERE ot_id = '958c3bbe-1b7b-41d7-ba56-b99fa7e60061'
                                   AND excluido = false AND obligatorio
                                   AND (resultado IS NULL OR resultado = 'pendiente')),
    'fotos_evidencia', (SELECT COUNT(*) FROM checklist_v2_instance ci
                          JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                         WHERE ci.ot_id = '958c3bbe-1b7b-41d7-ba56-b99fa7e60061'
                           AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
) AS validacion;
