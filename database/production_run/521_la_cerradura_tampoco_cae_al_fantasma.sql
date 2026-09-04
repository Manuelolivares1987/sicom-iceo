-- ============================================================================
-- MIG521 · La cerradura tampoco cae al checklist fantasma
-- ============================================================================
--
-- LO QUE VIO MANUEL (04-09-2026, minutos después de MIG519)
-- Al cerrar la OT-202608-00009: «No se puede cerrar la OT. Existen 6 items
-- obligatorios del checklist sin completar».
--
-- POR QUÉ
-- MIG519 parchó rpc_transicion_ot — pero MIG472 lo dice textual: «Acá vive
-- la cerradura de verdad — el RPC es sólo la puerta». El TRIGGER
-- validar_cierre_ot() tiene el MISMO conteo con el MISMO fallback al
-- checklist_ot genérico pre-V03 que la app no muestra. Se parchó la puerta
-- y quedó la cerradura.
--
-- QUÉ SE HACE
-- El mismo parche de MIG519, sobre el trigger: el fallback al genérico solo
-- aplica cuando la OT no tiene NINGUNA fila de V03. Parche por línea sobre
-- la definición vigente (ocurrencia única verificada) + prueba con rollback
-- sobre la OT real.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_def   TEXT;
    v_viejo TEXT := 'IF COALESCE(v_checklist_total,0) = 0 THEN';
    v_nuevo TEXT := 'IF COALESCE(v_checklist_total,0) = 0'
                 || E'\n           -- [MIG521] El genérico solo manda si NO hay V03 (igual que MIG519 en el RPC).'
                 || E'\n           AND NOT EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v3chk'
                 || E'\n                            WHERE v3chk.ot_id = NEW.id) THEN';
    v_ot    UUID;
    v_admin UUID;
    v_r     JSONB;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'validar_cierre_ot';
    IF v_def IS NULL THEN RAISE EXCEPTION 'FALLO: validar_cierre_ot no existe'; END IF;

    IF position(v_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré la condición del fallback — revisar a mano';
    END IF;
    IF position(v_viejo IN substring(v_def FROM position(v_viejo IN v_def) + length(v_viejo))) > 0 THEN
        RAISE EXCEPTION 'FALLO: la condición aparece más de una vez — parchar a mano';
    END IF;

    EXECUTE replace(v_def, v_viejo, v_nuevo);
    RAISE NOTICE 'validar_cierre_ot parchada: el fallback exige que NO exista V03';

    -- ── Prueba con rollback sobre la OT de Joel ─────────────────────────────
    SELECT id INTO v_ot FROM ordenes_trabajo WHERE folio = 'OT-202608-00009';
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    IF v_ot IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
        BEGIN
            v_r := rpc_transicion_ot(v_ot, 'ejecutada_ok', v_admin);
            RAISE EXCEPTION 'ROLLBACK_MARKER %', v_r;
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
                RAISE NOTICE 'prueba OK: el cierre PASA entero (revertido — lo cierra Joel con su firma)';
            ELSIF SQLERRM ILIKE '%obligatorios%sin completar%' THEN
                RAISE EXCEPTION 'FALLO: la cerradura sigue cayendo al fantasma: %', SQLERRM;
            ELSE
                RAISE NOTICE 'prueba: el cierre contesta otro gate legítimo: %', SQLERRM;
            END IF;
        END;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='validar_cierre_ot'
           AND p.prosrc LIKE '%MIG521%'
    ) THEN
        RAISE EXCEPTION 'FALLO: el parche no quedó en el trigger';
    END IF;
    RAISE NOTICE 'MIG521 OK · puerta (MIG519) y cerradura (MIG521) cuentan lo mismo';
END
$mig$;

COMMIT;
