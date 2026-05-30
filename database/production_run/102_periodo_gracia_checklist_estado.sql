-- ============================================================================
-- 102_periodo_gracia_checklist_estado.sql
-- ----------------------------------------------------------------------------
-- Manuel necesita "iniciar" el sistema: alinear los estados (incluido
-- estado_comercial = arrendado/disponible) con la verdad de la matriz SIN que
-- los gates de checklist lo bloqueen, HASTA el 31-may-2026. Desde el
-- 01-jun-2026 (lunes) los gates vuelven a exigir el checklist/verificacion,
-- como prueba de que el camion esta operativo/listo.
--
-- Se agrega un PERIODO DE GRACIA (CURRENT_DATE < 2026-06-01) a dos triggers:
--   1. fn_validar_arrendado_requiere_checklist_entrega  -> bypass total.
--   2. fn_validar_cambio_disponible REGLA A (verificacion) -> bypass.
-- NO se toca:
--   - REGLA B/C (expirar verificacion al ir a mantencion / cambiar contrato).
--   - REGLA D (BLOQUEO DS 298: > 15 anios en sustancias peligrosas) -> es LEY,
--     queda SIEMPRE activa, tambien durante el periodo de gracia.
--
-- La fecha esta embebida en el trigger: el gate se re-activa solo el 01-jun,
-- sin necesidad de cron ni intervencion. Idempotente.
-- ============================================================================

-- ── 1. Gate de ARRENDADO (checklist de entrega) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_validar_arrendado_requiere_checklist_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_existe BOOLEAN;
BEGIN
    -- PERIODO DE GRACIA: hasta el 31-may-2026 se permite marcar ARRENDADO sin
    -- checklist (inicio/alineacion del sistema). Desde el 01-jun el gate vuelve.
    IF CURRENT_DATE < DATE '2026-06-01' THEN
        RETURN NEW;
    END IF;

    -- Solo se aplica si esta cambiando A 'arrendado'
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

        IF NOT v_existe THEN
            RAISE EXCEPTION
              'No se puede marcar el activo como ARRENDADO sin un Check-List de ENTREGA V02 cerrado, '
              'firmado por operador Y cliente, en las ultimas 48 horas. '
              'Crea el checklist en /dashboard/flota/checklist-salida/% primero.', NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

-- ── 2. Gate de DISPONIBLE (verificacion) — solo REGLA A entra en gracia ──────
CREATE OR REPLACE FUNCTION public.fn_validar_cambio_disponible()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- ═══════════════════════════════════════════════════════════════
    -- REGLA A: no permitir 'disponible' sin verificacion vigente.
    --   (PERIODO DE GRACIA: el bloqueo solo aplica DESDE el 01-jun-2026.)
    -- ═══════════════════════════════════════════════════════════════
    IF NEW.estado_comercial = 'disponible'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial != 'disponible')
    THEN
        IF CURRENT_DATE >= DATE '2026-06-01'
           AND NOT EXISTS (
            SELECT 1 FROM verificaciones_disponibilidad vd
            WHERE vd.activo_id = NEW.id
              AND vd.resultado = 'aprobado'
              AND vd.vigente_hasta > NOW()
        ) THEN
            RAISE EXCEPTION
                'BLOQUEO READY-TO-RENT: el equipo % no tiene verificacion '
                'de disponibilidad aprobada y vigente. Antes de marcar '
                '"disponible para arriendo", ejecute el checklist de '
                'verificacion (OT tipo verificacion_disponibilidad) y '
                'obtenga la aprobacion del Jefe de Taller.',
                COALESCE(NEW.patente, NEW.codigo, NEW.id::text)
            USING HINT = 'Ver tabla verificaciones_disponibilidad.';
        END IF;

        -- Linkear la verificacion actual al activo (si existe)
        SELECT vd.id, vd.vigente_hasta
        INTO NEW.ultima_verificacion_id, NEW.verificacion_vigente_hasta
        FROM verificaciones_disponibilidad vd
        WHERE vd.activo_id = NEW.id
          AND vd.resultado = 'aprobado'
          AND vd.vigente_hasta > NOW()
        ORDER BY vd.vigente_hasta DESC
        LIMIT 1;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA B: al salir de 'operativo' invalidar la verificacion vigente.
    -- ═══════════════════════════════════════════════════════════════
    IF TG_OP = 'UPDATE'
       AND OLD.estado = 'operativo'
       AND NEW.estado IN ('en_mantenimiento', 'fuera_servicio')
    THEN
        UPDATE verificaciones_disponibilidad
           SET vigente_hasta = NOW()
         WHERE activo_id = NEW.id
           AND resultado = 'aprobado'
           AND vigente_hasta > NOW();

        NEW.ultima_verificacion_id := NULL;
        NEW.verificacion_vigente_hasta := NULL;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA C: al cambiar contrato, invalidar verificacion anterior.
    -- ═══════════════════════════════════════════════════════════════
    IF TG_OP = 'UPDATE'
       AND OLD.contrato_id IS DISTINCT FROM NEW.contrato_id
       AND NEW.contrato_id IS NOT NULL
    THEN
        UPDATE verificaciones_disponibilidad
           SET vigente_hasta = NOW()
         WHERE activo_id = NEW.id
           AND resultado = 'aprobado'
           AND vigente_hasta > NOW();

        NEW.ultima_verificacion_id := NULL;
        NEW.verificacion_vigente_hasta := NULL;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA D (LEY DS 298): bloqueo por antiguedad > 15 anios en transporte
    -- de sustancias peligrosas. SIEMPRE ACTIVA (no entra en gracia).
    -- ═══════════════════════════════════════════════════════════════
    IF NEW.anio_fabricacion IS NOT NULL
       AND (EXTRACT(YEAR FROM CURRENT_DATE) - NEW.anio_fabricacion) > 15
       AND NEW.estado_comercial IN ('disponible', 'arrendado')
       AND NEW.tipo IN ('camion_cisterna', 'camion')
    THEN
        RAISE EXCEPTION
            'BLOQUEO DS 298: vehiculo ano % supera 15 anios de antiguedad. '
            'No puede operar en transporte de sustancias peligrosas.',
            NEW.anio_fabricacion;
    END IF;

    RETURN NEW;
END;
$function$;

-- Verificacion
SELECT
  (SELECT pg_get_functiondef(oid) LIKE '%2026-06-01%' FROM pg_proc WHERE proname='fn_validar_arrendado_requiere_checklist_entrega') AS arrendado_con_gracia,
  (SELECT pg_get_functiondef(oid) LIKE '%CURRENT_DATE >= DATE ''2026-06-01''%' FROM pg_proc WHERE proname='fn_validar_cambio_disponible') AS disponible_con_gracia,
  (SELECT pg_get_functiondef(oid) LIKE '%DS 298%' FROM pg_proc WHERE proname='fn_validar_cambio_disponible') AS ds298_intacto;

NOTIFY pgrst, 'reload schema';
