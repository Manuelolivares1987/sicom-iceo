-- ============================================================================
-- SICOM-ICEO | 151 — Completar operación (Calama/Coquimbo) desde el contrato
-- ----------------------------------------------------------------------------
-- Al asignar/cambiar el contrato (modal de Sugerencias GPS u otros), si el
-- equipo NO tiene operación, se completa con la operación DOMINANTE de los demás
-- equipos del mismo contrato. Así los equipos sin operación quedan clasificados
-- (Calama / Coquimbo) al trabajarlos en Sugerencias GPS, sin asignación masiva.
--
-- CREATE OR REPLACE idéntica a la versión viva (MIG 113) + el bloque de
-- operación. Solo rellena cuando está vacía (no pisa una operación manual).
-- IDEMPOTENTE.
-- ============================================================================

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

    IF v_activo.contrato_id IS NOT DISTINCT FROM p_nuevo_contrato_id THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    -- Aplicar el cambio + sincronizar cliente_actual con el nuevo contrato
    UPDATE activos
       SET contrato_id   = p_nuevo_contrato_id,
           cliente_actual = CASE WHEN p_nuevo_contrato_id IS NOT NULL
                                 THEN (SELECT cliente FROM contratos WHERE id = p_nuevo_contrato_id)
                                 ELSE 'Sin contrato' END
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

NOTIFY pgrst, 'reload schema';
