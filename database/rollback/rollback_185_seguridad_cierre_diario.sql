-- ============================================================================
-- ROLLBACK MIG185 — rollback técnico de EMERGENCIA
-- ----------------------------------------------------------------------------
-- ⚠️ REABRE la vulnerabilidad CRÍTICA C1: deja rpc_confirmar_cierre_diario y
--    fn_propuesta_cierre_diario ejecutables por anon SIN validación, y quita la
--    RLS de estado_diario_flota (anon vuelve a poder escribir la matriz).
--    Usar SOLO si el cierre diario queda inoperante para usuarios legítimos y no
--    se resuelve otorgando el permiso 'approve' del módulo flota en Admin.
-- Restaura la definición y grants EXACTOS previos a MIG185 (extraídos de prod).
-- ============================================================================
BEGIN;

-- 1. Restaurar rpc_confirmar_cierre_diario a su definición pre-185.
CREATE OR REPLACE FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_item      JSONB;
    v_activo    UUID;
    v_estado    CHAR(1);
    v_contrato  UUID;
    v_cliente   VARCHAR;
    v_estado_com estado_comercial_enum;
    v_n         INTEGER := 0;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_activo   := (v_item->>'activo_id')::uuid;
        v_estado   := upper(v_item->>'estado_codigo')::char(1);
        v_contrato := NULLIF(v_item->>'contrato_id', '')::uuid;

        IF v_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L') THEN
            RAISE EXCEPTION 'Estado invalido % para activo %', v_estado, v_activo;
        END IF;

        -- Cliente: del contrato si viene; si no, el actual del activo
        v_cliente := NULL;
        IF v_contrato IS NOT NULL THEN
            SELECT cliente INTO v_cliente FROM contratos WHERE id = v_contrato;
        END IF;
        IF v_cliente IS NULL THEN
            SELECT cliente_actual INTO v_cliente FROM activos WHERE id = v_activo;
        END IF;

        -- Upsert del estado del dia (congelado como cierre)
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo, cliente,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at, registrado_por, observacion
        ) VALUES (
            v_activo, p_fecha, v_contrato, v_estado, v_cliente,
            true, 'Cierre diario de flota', false,
            v_user, now(), v_user, 'Cierre diario confirmado'
        )
        ON CONFLICT (activo_id, fecha) DO UPDATE SET
            estado_codigo   = EXCLUDED.estado_codigo,
            contrato_id     = EXCLUDED.contrato_id,
            cliente         = EXCLUDED.cliente,
            override_manual = true,
            motivo_override = 'Cierre diario de flota',
            calculado_auto  = false,
            actualizado_por = EXCLUDED.actualizado_por,
            actualizado_at  = now(),
            updated_at      = now();

        -- Reverse-map a estado_comercial (solo codigos comerciales;
        -- M/T/F/H no cambian el comercial: un equipo arrendado en taller
        -- sigue comercialmente arrendado).
        v_estado_com := (CASE v_estado
            WHEN 'A' THEN 'arrendado'
            WHEN 'C' THEN 'arrendado'
            WHEN 'D' THEN 'disponible'
            WHEN 'U' THEN 'uso_interno'
            WHEN 'L' THEN 'leasing'
            WHEN 'R' THEN 'en_recepcion'
            WHEN 'V' THEN 'en_venta'
            ELSE NULL
        END)::estado_comercial_enum;

        -- Propagar a activos: contrato siempre; comercial + cliente solo si mapea
        UPDATE activos SET
            contrato_id      = v_contrato,
            estado_comercial = COALESCE(v_estado_com, estado_comercial),
            cliente_actual   = CASE WHEN v_estado_com IS NOT NULL THEN v_cliente
                                    ELSE cliente_actual END,
            updated_at       = now()
        WHERE id = v_activo;

        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'confirmados', v_n);
END $function$
;

-- 2. Restaurar grants previos (anon + authenticated) de las 2 funciones.
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(date, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_propuesta_cierre_diario(date)        TO anon, authenticated;

-- 3. Quitar RLS y policy de estado_diario_flota; restaurar grants de tabla a anon.
DROP POLICY IF EXISTS pol_edf_select_authenticated ON public.estado_diario_flota;
ALTER TABLE public.estado_diario_flota DISABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.estado_diario_flota TO anon, authenticated;

-- 4. Eliminar el helper introducido por MIG185.
DROP FUNCTION IF EXISTS public.fn_tiene_permiso_modulo(text, text, text[]);

-- 5. Validación posterior del rollback.
DO $$
BEGIN
    IF NOT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date, jsonb)','EXECUTE') THEN
        RAISE EXCEPTION 'ROLLBACK185 incompleto: anon no recuperó EXECUTE';
    END IF;
    IF (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') THEN
        RAISE EXCEPTION 'ROLLBACK185 incompleto: RLS sigue activa';
    END IF;
    RAISE NOTICE 'ROLLBACK185 aplicado (VULNERABILIDAD C1 REABIERTA).';
END $$;
COMMIT;
