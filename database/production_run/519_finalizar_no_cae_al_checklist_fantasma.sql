-- ============================================================================
-- MIG519 · Finalizar la OT no cae al checklist fantasma
-- ============================================================================
--
-- LO QUE VIO MANUEL (04-09-2026, foto del teléfono de Joel)
-- Joel firma para finalizar la OT-202608-00009 (preventivo DJKL-18) y sale:
-- «No se pudo finalizar: Hay 6 de 6 ítems obligatorios sin completar».
-- Pero Joel SÍ terminó: sus 8 trabajos (los NO OK heredados de la
-- inspección, regla MIG270) están todos marcados ok en el V03.
--
-- POR QUÉ
-- rpc_transicion_ot cuenta los OBLIGATORIOS del V03 visible; en esta OT los
-- 8 visibles son heredados (obligatorio=false) y los otros 169 están
-- excluidos, así que el conteo da 0 y el RPC concluye «no hay V03» — y cae
-- al fallback: el checklist_ot GENÉRICO de 2026-06 (6 obligatorios), que la
-- app del mecánico no muestra ni puede marcar desde que existe el V03.
-- Una trampa sin salida: lo que bloquea es invisible.
--
-- QUÉ SE HACE
-- El fallback al checklist_ot genérico se activa SOLO cuando la OT no tiene
-- ninguna fila de V03. Si el V03 existe, él es la única vara — aunque sus
-- visibles no sean obligatorios (ese es justamente el caso MIG270: la OT
-- trae solo los NO OK, y esos se terminan marcándolos, no por obligación
-- del template).
--
-- Se parcha por línea sobre la definición vigente en prod (patrón MIG379:
-- no se reescribe una función grande a mano), con verificación de que la
-- condición exista y sea única, y una prueba con rollback sobre la OT de
-- Joel: después del parche, finalizar ya no dice «obligatorios sin
-- completar».
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_def   TEXT;
    v_viejo TEXT := 'IF COALESCE(v_count_checklist_total,0) = 0 THEN';
    v_nuevo TEXT := 'IF COALESCE(v_count_checklist_total,0) = 0'
                 || E'\n           -- [MIG519] El genérico solo manda si NO hay V03: si el V03 existe,'
                 || E'\n           -- él es la única vara (aunque sus visibles no sean obligatorios).'
                 || E'\n           AND NOT EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v3chk'
                 || E'\n                            WHERE v3chk.ot_id = p_ot_id) THEN';
    v_ot    UUID;
    v_admin UUID;
    v_r     JSONB;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_transicion_ot';
    IF v_def IS NULL THEN RAISE EXCEPTION 'FALLO: rpc_transicion_ot no existe'; END IF;

    IF position(v_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré la condición del fallback — la función cambió, revisar a mano';
    END IF;
    IF position(v_viejo IN substring(v_def FROM position(v_viejo IN v_def) + length(v_viejo))) > 0 THEN
        RAISE EXCEPTION 'FALLO: la condición aparece más de una vez — parchar a mano';
    END IF;

    EXECUTE replace(v_def, v_viejo, v_nuevo);
    RAISE NOTICE 'rpc_transicion_ot parchada: el fallback exige que NO exista V03';

    -- ── Prueba con rollback: la OT de Joel ya puede finalizar ───────────────
    SELECT id INTO v_ot FROM ordenes_trabajo WHERE folio = 'OT-202608-00009';
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    IF v_ot IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
        BEGIN
            v_r := rpc_transicion_ot(v_ot, 'ejecutada_ok', v_admin);
            RAISE EXCEPTION 'ROLLBACK_MARKER %', v_r;
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
                RAISE NOTICE 'prueba OK: finalizar pasa (%) — y quedó revertida, la firma la pone Joel', SQLERRM;
            ELSIF SQLERRM ILIKE '%obligatorios sin completar%' THEN
                RAISE EXCEPTION 'FALLO: sigue cayendo al checklist fantasma: %', SQLERRM;
            ELSE
                -- Otro gate legítimo (evidencia, medidores…): se informa, no aborta.
                RAISE NOTICE 'prueba: finalizar contesta otro gate (no el fantasma): %', SQLERRM;
            END IF;
        END;
    END IF;

    -- La condición nueva quedó escrita de verdad.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='rpc_transicion_ot'
           AND p.prosrc LIKE '%MIG519%'
    ) THEN
        RAISE EXCEPTION 'FALLO: el parche no quedó en la función';
    END IF;
    RAISE NOTICE 'MIG519 OK · el checklist genérico ya no bloquea a quien trabaja con el V03';
END
$mig$;

COMMIT;
