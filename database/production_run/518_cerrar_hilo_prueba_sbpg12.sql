-- ============================================================================
-- MIG518 · Cerrar el hilo de prueba del SBPG-12 (NC → OS → OT aparte)
-- ============================================================================
--
-- Manuel (04-09-2026): «Hagamos la última, porque esto es una prueba».
--
-- El hilo: la OT-202609-00006 (descartada) dejó viva su NC «Lectura del
-- último error / advertencia registrada»; esa NC se planificó como OS con
-- «OT aparte», creando la OT-202609-00007 + OS-202609-00007-1 con Felipe
-- López asignado y sin fecha. Todo era una prueba del flujo: acá se cierra
-- entero, por los mismos caminos del sistema (no a mano por fuera):
--   1. La OS se finaliza (rpc_taller_os_finalizar) y la asignación de
--      Felipe se termina con motivo — queda libre para otra OS.
--   2. La NC se resuelve con la acción correctiva escrita.
--   3. La OT-202609-00007 se descarta (rpc_taller_sacar_ot_del_plan) y
--      desaparece de «viene de semanas anteriores».
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_admin UUID; v_ot UUID; v_os UUID; v_nc UUID; v_r JSONB;
    v_est TEXT; v_n INT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    SELECT id INTO v_ot FROM ordenes_trabajo WHERE folio = 'OT-202609-00007';
    SELECT id INTO v_os FROM taller_os WHERE folio = 'OS-202609-00007-1';
    IF v_ot IS NULL OR v_os IS NULL THEN
        RAISE EXCEPTION 'FALLO: no se encontró la OT o la OS de la prueba';
    END IF;
    SELECT no_conformidad_id INTO v_nc FROM taller_os_nc WHERE os_id = v_os LIMIT 1;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    -- 1 · Finalizar la OS y liberar a Felipe.
    v_r := rpc_taller_os_finalizar(v_os, 'Era una prueba del flujo NC → OS. Cerrada sin trabajo real.');
    RAISE NOTICE 'OS finalizada: %', v_r;
    UPDATE taller_os_asignacion
       SET hasta = NOW(), motivo_fin = 'Prueba cerrada — sin trabajo real'
     WHERE os_id = v_os AND hasta IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'asignaciones terminadas: %', v_n;

    -- 2 · Resolver la NC con su explicación.
    IF v_nc IS NOT NULL THEN
        UPDATE no_conformidades
           SET resuelto = TRUE,
               resuelto_en = NOW(),
               resuelto_por = v_admin,
               accion_correctiva = TRIM(COALESCE(accion_correctiva,'') ||
                   ' [04-09-2026] Cerrada como prueba del flujo NC → OS: no hubo trabajo real que ejecutar.'),
               updated_at = NOW()
         WHERE id = v_nc AND COALESCE(resuelto, FALSE) = FALSE;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        RAISE NOTICE 'NC resueltas: %', v_n;
    END IF;

    -- 3 · Descartar la OT aparte.
    v_r := rpc_taller_sacar_ot_del_plan(v_ot, TRUE, 'Era una prueba del flujo NC → OS', FALSE);
    RAISE NOTICE 'OT descartada: %', v_r;

    -- ── Verificación: el hilo quedó muerto de verdad ────────────────────────
    SELECT estado::TEXT INTO v_est FROM ordenes_trabajo WHERE id = v_ot;
    IF v_est <> 'cancelada' THEN RAISE EXCEPTION 'FALLO: la OT quedó «%»', v_est; END IF;

    SELECT estado INTO v_est FROM taller_os WHERE id = v_os;
    IF v_est <> 'finalizada' THEN RAISE EXCEPTION 'FALLO: la OS quedó «%»', v_est; END IF;

    SELECT count(*) INTO v_n FROM taller_os_asignacion WHERE os_id = v_os AND hasta IS NULL;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % asignación(es) siguen vigentes', v_n; END IF;

    SELECT count(*) INTO v_n FROM no_conformidades WHERE id = v_nc AND COALESCE(resuelto,FALSE) = FALSE;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: la NC sigue abierta'; END IF;

    SELECT count(*) INTO v_n FROM v_taller_ot_backlog WHERE ot_id = v_ot;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: la OT sigue en «viene de semanas anteriores»'; END IF;

    RAISE NOTICE 'MIG518 OK · hilo de prueba cerrado: OT cancelada, OS finalizada, NC resuelta, Felipe libre';
END
$mig$;

COMMIT;
