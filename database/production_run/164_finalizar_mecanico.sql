-- ============================================================================
-- SICOM-ICEO | 164 — Finalizar OT del mecánico: trigger V03-aware + firma técnico
-- ============================================================================
-- El trigger validar_cierre_ot exige (al pasar a ejecutada_*): evidencia,
-- checklist obligatorio completo y firma del técnico. Lo hacemos V03-aware
-- (cuenta fotos/obligatorios del checklist V03) y agregamos un RPC que el
-- mecánico usa para finalizar con su firma (setea firma_tecnico_url y transita).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Trigger de cierre: contar el checklist V03 ────────────────────────────
CREATE OR REPLACE FUNCTION public.validar_cierre_ot()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_evidencias_count    INTEGER;
    v_checklist_total     INTEGER;
    v_checklist_pendiente INTEGER;
BEGIN
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        -- 1. Evidencia: evidencias_ot + fotos del checklist V03 + fotos checklist_ot
        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = NEW.id)
             + (SELECT COUNT(*) FROM checklist_v2_instance ci
                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                 WHERE ci.ot_id = NEW.id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = NEW.id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)
          INTO v_evidencias_count;
        IF v_evidencias_count = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere al menos 1 evidencia fotografica o documental.', NEW.folio;
        END IF;

        -- 2. Obligatorios del checklist: V03 (no excluido); si no hay V03, checklist_ot
        SELECT COUNT(*) FILTER (WHERE obligatorio),
               COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
          INTO v_checklist_total, v_checklist_pendiente
          FROM v_taller_ot_checklist_v3 WHERE ot_id = NEW.id AND excluido = false;
        IF COALESCE(v_checklist_total,0) = 0 THEN
            SELECT COUNT(*) FILTER (WHERE obligatorio = true),
                   COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
              INTO v_checklist_total, v_checklist_pendiente
              FROM checklist_ot WHERE ot_id = NEW.id;
        END IF;
        IF COALESCE(v_checklist_pendiente,0) > 0 THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Existen % items obligatorios del checklist sin completar.',
                NEW.folio, v_checklist_pendiente;
        END IF;

        -- 3. Firma del técnico
        IF NEW.firma_tecnico_url IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere la firma del tecnico responsable.', NEW.folio;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;


-- ── 2. RPC: el mecánico finaliza con su firma ────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_finalizar_mecanico(
    p_ot_id UUID, p_firma_tecnico_url TEXT,
    p_con_observaciones BOOLEAN DEFAULT false, p_observaciones TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user UUID := auth.uid();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_firma_tecnico_url IS NULL OR length(trim(p_firma_tecnico_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del técnico es obligatoria para finalizar'; END IF;
    UPDATE ordenes_trabajo SET firma_tecnico_url = p_firma_tecnico_url, updated_at = NOW() WHERE id = p_ot_id;
    RETURN rpc_transicion_ot(
        p_ot_id,
        (CASE WHEN p_con_observaciones THEN 'ejecutada_con_observaciones' ELSE 'ejecutada_ok' END)::estado_ot_enum,
        v_user, NULL, NULL, p_observaciones, NULL);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_finalizar_mecanico(UUID,TEXT,BOOLEAN,TEXT) TO authenticated;

SELECT 'MIG164 OK' AS resultado;
NOTIFY pgrst, 'reload schema';
