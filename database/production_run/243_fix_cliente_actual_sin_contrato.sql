-- ============================================================================
-- SICOM-ICEO | 243 — cliente_actual coherente con el contrato ("Sin contrato")
-- ----------------------------------------------------------------------------
-- Bug (Manuel 2026-07-22): JTYK-88 se pasó a "Sin contrato" pero el reporte de
-- Fiabilidad seguía mostrando el cliente viejo ("Drilling Service and S").
--
-- Causa: `activos.cliente_actual` quedó desincronizado de `contrato_id`.
-- `rpc_cambiar_contrato_activo` tiene un early-return cuando el contrato "no
-- cambia" (ya era NULL) → nunca corregía el cliente_actual viejo. Al re-elegir
-- "Sin contrato" no pasaba nada. 4 equipos afectados (contrato NULL + cliente
-- real): JTYK-88, KCBY-30, RSCY-85, TRDP-97.
--
-- Fix:
--   1) Data: cliente_actual = 'Sin contrato' para todo activo con contrato_id
--      NULL cuyo cliente_actual sea un cliente real.
--   2) rpc_cambiar_contrato_activo: aunque el contrato no cambie, re-sincroniza
--      cliente_actual con el contrato (o 'Sin contrato'). Así re-elegir la misma
--      opción corrige un cliente_actual stale.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Limpieza de datos ────────────────────────────────────────────────────
WITH corregidos AS (
    UPDATE activos
       SET cliente_actual = 'Sin contrato', updated_at = NOW()
     WHERE contrato_id IS NULL
       AND estado <> 'dado_baja'
       AND (cliente_actual IS NULL OR cliente_actual <> 'Sin contrato')
    RETURNING id
)
SELECT count(*) AS activos_sin_contrato_corregidos FROM corregidos;


-- ── 2. RPC re-sincroniza cliente_actual aun cuando el contrato no cambie ─────
CREATE OR REPLACE FUNCTION public.rpc_cambiar_contrato_activo(
    p_activo_id uuid,
    p_nuevo_contrato_id uuid,
    p_razon text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_activo  RECORD;
    v_id_hist BIGINT;
    v_oper    VARCHAR;
    v_cli_ok  VARCHAR;
BEGIN
    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF v_activo.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    IF p_nuevo_contrato_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM contratos WHERE id = p_nuevo_contrato_id) THEN
            RAISE EXCEPTION 'Contrato % no existe', p_nuevo_contrato_id;
        END IF;
    END IF;

    -- Cliente que corresponde al contrato objetivo (o 'Sin contrato').
    v_cli_ok := CASE WHEN p_nuevo_contrato_id IS NOT NULL
                     THEN (SELECT cliente FROM contratos WHERE id = p_nuevo_contrato_id)
                     ELSE 'Sin contrato' END;

    -- Si el contrato NO cambia: igual re-sincroniza cliente_actual por si quedó
    -- stale (ej. contrato ya NULL pero cliente_actual con cliente viejo).
    IF v_activo.contrato_id IS NOT DISTINCT FROM p_nuevo_contrato_id THEN
        IF v_activo.cliente_actual IS DISTINCT FROM v_cli_ok THEN
            UPDATE activos SET cliente_actual = v_cli_ok, updated_at = NOW()
             WHERE id = p_activo_id;
        END IF;
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true,
                                  'cliente_resincronizado', v_activo.cliente_actual IS DISTINCT FROM v_cli_ok);
    END IF;

    -- Aplicar el cambio + sincronizar cliente_actual con el nuevo contrato
    UPDATE activos
       SET contrato_id   = p_nuevo_contrato_id,
           cliente_actual = v_cli_ok
     WHERE id = p_activo_id;

    -- Completar operación (Calama/Coquimbo) desde el contrato si el equipo no la
    -- tiene: operación dominante de los demás equipos del mismo contrato.
    IF p_nuevo_contrato_id IS NOT NULL
       AND (v_activo.operacion IS NULL OR v_activo.operacion = '') THEN
        SELECT operacion INTO v_oper
          FROM activos
         WHERE contrato_id = p_nuevo_contrato_id
           AND operacion IS NOT NULL AND operacion <> ''
           AND id <> p_activo_id
         GROUP BY operacion
         ORDER BY COUNT(*) DESC
         LIMIT 1;
        IF v_oper IS NOT NULL THEN
            UPDATE activos SET operacion = v_oper WHERE id = p_activo_id;
        END IF;
    END IF;

    SELECT id INTO v_id_hist
      FROM historico_contrato_activo
     WHERE activo_id = p_activo_id
     ORDER BY cambio_at DESC, id DESC
     LIMIT 1;

    IF v_id_hist IS NOT NULL AND p_razon IS NOT NULL THEN
        UPDATE historico_contrato_activo SET razon = p_razon WHERE id = v_id_hist;
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'activo_id', p_activo_id,
        'contrato_anterior', v_activo.contrato_id,
        'contrato_nuevo', p_nuevo_contrato_id,
        'operacion_completada', v_oper,
        'historico_id', v_id_hist
    );
END;
$function$;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM activos
     WHERE contrato_id IS NULL AND estado<>'dado_baja'
       AND cliente_actual IS NOT NULL AND cliente_actual <> 'Sin contrato';
    IF n > 0 THEN
        RAISE EXCEPTION 'FALLO: aún quedan % activos sin contrato con cliente stale', n;
    END IF;
    RAISE NOTICE 'MIG243 OK: 0 activos sin contrato con cliente_actual stale';
END $$;

NOTIFY pgrst, 'reload schema';
