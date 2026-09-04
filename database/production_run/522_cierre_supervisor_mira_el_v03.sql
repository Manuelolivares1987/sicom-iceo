-- ============================================================================
-- MIG522 · El cierre de supervisor también mira el V03
-- ============================================================================
--
-- LO QUE VIO MANUEL (04-09-2026)
-- La OT-202608-00009 quedó ejecutada_ok (Joel finalizó tras MIG521), pero el
-- «Cierre Supervisor» del escritorio no avanzaba. El error (que la página
-- muestra arriba, lejos del botón): «Hay 6 ítems obligatorios sin completar».
--
-- POR QUÉ
-- rpc_cerrar_ot_supervisor es anterior al checklist V03 y quedó con DOS
-- conteos viejos:
--   · obligatorios: cuenta SOLO checklist_ot (el genérico invisible) — ni
--     mira el V03. Tercera copia de la trampa de MIG519/521.
--   · evidencia: cuenta SOLO evidencias_ot — las fotos del checklist V03 no
--     le valen, aunque a rpc_transicion_ot sí.
--
-- QUÉ SE HACE
-- Mismo criterio que MIG519/521, parchado por línea sobre la definición
-- vigente: si la OT tiene V03, los obligatorios se cuentan ahí (visibles);
-- el genérico solo manda si no hay V03. Y la evidencia suma las tres
-- fuentes, igual que en rpc_transicion_ot. Prueba con rollback sobre la OT
-- real: el cierre pasa.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_def TEXT;
    v_ev_viejo TEXT := 'SELECT COUNT(*) INTO v_count_evidence FROM evidencias_ot WHERE ot_id = p_ot_id;';
    v_ev_nuevo TEXT :=
        '-- [MIG522] La evidencia vale de donde venga: igual que rpc_transicion_ot.' || E'\n' ||
        '        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = p_ot_id)' || E'\n' ||
        '             + (SELECT COUNT(*) FROM checklist_v2_instance ci' || E'\n' ||
        '                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id' || E'\n' ||
        '                 WHERE ci.ot_id = p_ot_id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)' || E'\n' ||
        '             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = p_ot_id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)' || E'\n' ||
        '          INTO v_count_evidence;';
    -- OJO: el cuerpo vigente en prod se aplicó desde un archivo con CRLF —
    -- el separador de líneas del target es \r\n, no \n.
    v_ck_viejo TEXT := 'SELECT COUNT(*) INTO v_count_checklist_pending' || E'\r\n' ||
        '        FROM checklist_ot WHERE ot_id = p_ot_id AND obligatorio = true AND resultado IS NULL;';
    v_ck_nuevo TEXT :=
        '-- [MIG522] Si la OT tiene V03, él manda (criterio MIG519/521); el' || E'\n' ||
        '        -- genérico invisible solo cuenta cuando no hay V03.' || E'\n' ||
        '        IF EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v3chk WHERE v3chk.ot_id = p_ot_id) THEN' || E'\n' ||
        '            SELECT COUNT(*) INTO v_count_checklist_pending' || E'\n' ||
        '              FROM v_taller_ot_checklist_v3' || E'\n' ||
        '             WHERE ot_id = p_ot_id AND excluido = false AND obligatorio' || E'\n' ||
        '               AND (resultado IS NULL OR resultado = ''pendiente'');' || E'\n' ||
        '        ELSE' || E'\n' ||
        '            SELECT COUNT(*) INTO v_count_checklist_pending' || E'\n' ||
        '              FROM checklist_ot WHERE ot_id = p_ot_id AND obligatorio = true AND resultado IS NULL;' || E'\n' ||
        '        END IF;';
    v_ot UUID; v_admin UUID; v_r JSONB;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_cerrar_ot_supervisor';
    IF v_def IS NULL THEN RAISE EXCEPTION 'FALLO: rpc_cerrar_ot_supervisor no existe'; END IF;

    IF position(v_ev_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré el conteo de evidencia — revisar a mano';
    END IF;
    IF position(v_ck_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré el conteo de obligatorios — revisar a mano';
    END IF;

    EXECUTE replace(replace(v_def, v_ev_viejo, v_ev_nuevo), v_ck_viejo, v_ck_nuevo);
    RAISE NOTICE 'rpc_cerrar_ot_supervisor parchada: V03 primero, evidencia de las tres fuentes';

    -- ── Prueba con rollback sobre la OT real ────────────────────────────────
    SELECT id INTO v_ot FROM ordenes_trabajo WHERE folio = 'OT-202608-00009';
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    IF v_ot IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
        BEGIN
            v_r := rpc_cerrar_ot_supervisor(v_ot, v_admin, 'Prueba MIG522');
            RAISE EXCEPTION 'ROLLBACK_MARKER %', v_r;
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
                RAISE NOTICE 'prueba OK: el cierre supervisor PASA (revertido — el clic lo da Manuel): %', SQLERRM;
            ELSIF SQLERRM ILIKE '%obligatorios sin completar%' OR SQLERRM ILIKE '%sin evidencia%' THEN
                RAISE EXCEPTION 'FALLO: el cierre sigue trancado: %', SQLERRM;
            ELSE
                RAISE NOTICE 'prueba: el cierre contesta otro gate: %', SQLERRM;
            END IF;
        END;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='rpc_cerrar_ot_supervisor'
           AND p.prosrc LIKE '%MIG522%'
    ) THEN
        RAISE EXCEPTION 'FALLO: el parche no quedó en la función';
    END IF;
    RAISE NOTICE 'MIG522 OK · las tres puertas del cierre cuentan lo mismo (MIG519+521+522)';
END
$mig$;

COMMIT;
