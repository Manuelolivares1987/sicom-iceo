-- ============================================================================
-- SICOM-ICEO | 242 — Gate ARRENDADO (checklist ENTREGA V02) = advertencia
-- ----------------------------------------------------------------------------
-- Pedido Manuel (2026-07-22): marcar ARRENDADO NO debe BLOQUEARSE por falta del
-- Check-List de ENTREGA V02. Misma decisión que el ready-to-rent (MIG240): es
-- advertencia, no muro. La gestión del checklist la hace el planificador.
--
-- fn_validar_arrendado_requiere_checklist_entrega: la REGLA pasa de
-- RAISE EXCEPTION a RAISE WARNING y permite el cambio. Se conserva el resto.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_validar_arrendado_requiere_checklist_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_existe BOOLEAN;
BEGIN
    -- Solo aplica al TRANSICIONAR a 'arrendado' (no si ya estaba arrendado).
    IF NEW.estado_comercial = 'arrendado'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial <> 'arrendado') THEN

        SELECT EXISTS(
            SELECT 1
              FROM checklist_v2_instance ci
             WHERE ci.activo_id = NEW.id
               AND ci.momento_uso = 'entrega_arriendo'
               AND ci.estado = 'cerrado'
               AND ci.firma_cliente_url  IS NOT NULL
               AND ci.firma_operador_url IS NOT NULL
               AND ci.fecha_cierre > NOW() - INTERVAL '48 hours'
        ) INTO v_existe;

        -- YA NO BLOQUEA (decisión Manuel 2026-07-22): solo advierte. El
        -- planificador gestiona el Check-List de ENTREGA V02.
        IF NOT v_existe THEN
            RAISE WARNING
              'ENTREGA V02: el equipo % se marca ARRENDADO sin Check-List de '
              'entrega cerrado y firmado en las ultimas 48h. El planificador '
              'debe gestionarlo.', NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

-- Validación
DO $$
DECLARE v_def text;
BEGIN
    v_def := pg_get_functiondef('public.fn_validar_arrendado_requiere_checklist_entrega()'::regprocedure);
    IF v_def LIKE '%RAISE EXCEPTION%ARRENDADO sin%' THEN
        RAISE EXCEPTION 'FALLO: el gate de arrendado sigue bloqueando';
    END IF;
    RAISE NOTICE 'MIG242 OK: gate ARRENDADO = advertencia (no bloquea)';
END $$;

NOTIFY pgrst, 'reload schema';
