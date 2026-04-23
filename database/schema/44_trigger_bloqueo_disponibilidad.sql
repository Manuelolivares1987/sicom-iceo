-- ============================================================================
-- SICOM-ICEO | Migracion 44 — Trigger de bloqueo disponibilidad + invalidacion
-- ============================================================================
-- CONTEXTO: Incidente real — un equipo se marco como 'disponible' sin estar
-- realmente operativo, comercial lo arrendo y el cliente lo rechazo en faena.
--
-- BUG RAIZ: La funcion fn_validar_cambio_disponible() existe desde mig 25,
-- pero NUNCA se creo el TRIGGER que la invoque. La logica esta, pero
-- desconectada. Este migration la conecta y la refuerza con:
--   (1) Bloqueo BEFORE UPDATE OR INSERT sobre activos.
--   (2) Invalidacion automatica al entrar a M/T/F (sale de operativo).
--   (3) Invalidacion al cambiar contrato_id.
--   (4) Vista v_equipos_disponibles_para_arriendo que excluye los que
--       estan marcados 'disponible' pero sin verificacion vigente.
--
-- POLITICA DE TRANSICION:
-- No revertimos los equipos ya marcados 'disponible' sin verificacion. La
-- realidad de hoy queda intacta para no bloquear operacion. Pero la vista
-- comercial SOLO muestra los que tienen verificacion vigente, y al proximo
-- cambio de estado de cualquier equipo, el trigger exige checklist nuevo.
-- ============================================================================

-- ============================================================================
-- 1. Reforzar la funcion validadora: invalidar al salir de operativo
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_validar_cambio_disponible()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- ═══════════════════════════════════════════════════════════════
    -- REGLA A: no permitir 'disponible' sin verificacion vigente.
    -- ═══════════════════════════════════════════════════════════════
    IF NEW.estado_comercial = 'disponible'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial != 'disponible')
    THEN
        IF NOT EXISTS (
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

        -- Linkear la verificacion actual al activo
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
    -- REGLA B: al salir de 'operativo' (entra a mantencion / fuera),
    -- invalidar la verificacion vigente — ya no aplica al equipo "despues
    -- de haber sido intervenido" hay que volver a verificarlo.
    -- ═══════════════════════════════════════════════════════════════
    IF TG_OP = 'UPDATE'
       AND OLD.estado = 'operativo'
       AND NEW.estado IN ('en_mantenimiento', 'fuera_servicio')
    THEN
        -- Expirar la verificacion (sin borrarla — queda para auditoria)
        UPDATE verificaciones_disponibilidad
           SET vigente_hasta = NOW()
         WHERE activo_id = NEW.id
           AND resultado = 'aprobado'
           AND vigente_hasta > NOW();

        NEW.ultima_verificacion_id := NULL;
        NEW.verificacion_vigente_hasta := NULL;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA C: al cambiar contrato, la verificacion anterior ya no
    -- sirve — cada cliente tiene requerimientos propios.
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
    -- REGLA D (heredada): bloqueo DS 298 por antiguedad > 15 anios en
    -- transporte de sustancias peligrosas.
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
$$;

COMMENT ON FUNCTION fn_validar_cambio_disponible IS
    'Trigger de ready-to-rent: bloquea disponibilidad sin verificacion '
    'vigente (regla A), invalida verificacion al entrar a taller (B) o '
    'al cambiar contrato (C), y aplica DS 298 por antiguedad (D).';


-- ============================================================================
-- 2. Conectar el trigger (el bug central — nunca se habia creado)
-- ============================================================================

DROP TRIGGER IF EXISTS trg_validar_cambio_disponible ON activos;

CREATE TRIGGER trg_validar_cambio_disponible
    BEFORE INSERT OR UPDATE OF estado_comercial, estado, contrato_id, anio_fabricacion
    ON activos
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_cambio_disponible();


-- ============================================================================
-- 3. Vista comercial: equipos REALMENTE arrendables
-- ============================================================================

CREATE OR REPLACE VIEW v_equipos_disponibles_para_arriendo AS
SELECT
    a.id,
    a.patente,
    a.codigo,
    a.nombre,
    a.tipo,
    a.anio_fabricacion,
    a.operacion,
    a.ubicacion_actual,
    a.categoria_uso,
    a.contrato_id,
    a.faena_id,
    vd.id               AS verificacion_id,
    vd.vigente_hasta    AS verificacion_vigente_hasta,
    vd.aprobado_por     AS verificacion_aprobada_por,
    vd.aprobado_en      AS verificacion_aprobada_en,
    vd.items_ok,
    vd.items_total,
    EXTRACT(EPOCH FROM (vd.vigente_hasta - NOW())) / 3600 AS horas_restantes
FROM activos a
JOIN verificaciones_disponibilidad vd ON vd.activo_id = a.id
WHERE a.estado = 'operativo'
  AND a.estado_comercial = 'disponible'
  AND a.estado != 'dado_baja'
  AND vd.resultado = 'aprobado'
  AND vd.vigente_hasta > NOW();

COMMENT ON VIEW v_equipos_disponibles_para_arriendo IS
    'Equipos que comercial REALMENTE puede arrendar: operativos, marcados '
    'disponibles Y con verificacion ready-to-rent vigente. Excluye los que '
    'tienen la marca disponible pero sin checklist (legacy / incidente).';


-- ============================================================================
-- 4. Vista de monitoreo: disponibles MARCADOS pero sin verificacion
-- ============================================================================
-- Para que comercial / supervisor vea que hay equipos en estado inconsistente
-- y los pueda despachar a verificacion antes de usarlos.

CREATE OR REPLACE VIEW v_equipos_pendientes_verificacion AS
SELECT
    a.id,
    a.patente,
    a.codigo,
    a.nombre,
    a.estado_comercial,
    a.estado,
    a.updated_at,
    -- Ultima verificacion (aprobada o no) para dar contexto
    (
        SELECT jsonb_build_object(
            'id', vd.id,
            'resultado', vd.resultado,
            'vigente_hasta', vd.vigente_hasta,
            'fecha_verificacion', vd.fecha_verificacion
        )
        FROM verificaciones_disponibilidad vd
        WHERE vd.activo_id = a.id
        ORDER BY vd.created_at DESC
        LIMIT 1
    ) AS ultima_verificacion
FROM activos a
WHERE a.estado_comercial = 'disponible'
  AND a.estado = 'operativo'
  AND a.estado != 'dado_baja'
  AND NOT EXISTS (
      SELECT 1 FROM verificaciones_disponibilidad vd
       WHERE vd.activo_id = a.id
         AND vd.resultado = 'aprobado'
         AND vd.vigente_hasta > NOW()
  );

COMMENT ON VIEW v_equipos_pendientes_verificacion IS
    'Equipos MARCADOS disponibles pero sin verificacion vigente. '
    'Requieren ejecutar checklist para poder ser arrendados. '
    'Queda como lista de trabajo para el Jefe de Taller.';


-- ============================================================================
-- 5. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_trigger_ok BOOLEAN;
    v_view1_ok   BOOLEAN;
    v_view2_ok   BOOLEAN;
    v_cnt_real   INTEGER;
    v_cnt_pend   INTEGER;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgname = 'trg_validar_cambio_disponible'
           AND tgrelid = 'activos'::regclass
    ) INTO v_trigger_ok;

    SELECT EXISTS (
        SELECT 1 FROM pg_views WHERE viewname = 'v_equipos_disponibles_para_arriendo'
    ) INTO v_view1_ok;

    SELECT EXISTS (
        SELECT 1 FROM pg_views WHERE viewname = 'v_equipos_pendientes_verificacion'
    ) INTO v_view2_ok;

    SELECT COUNT(*) INTO v_cnt_real FROM v_equipos_disponibles_para_arriendo;
    SELECT COUNT(*) INTO v_cnt_pend FROM v_equipos_pendientes_verificacion;

    RAISE NOTICE '== Migracion 44 ==';
    RAISE NOTICE 'Trigger trg_validar_cambio_disponible conectado ... %', v_trigger_ok;
    RAISE NOTICE 'Vista v_equipos_disponibles_para_arriendo ........ %', v_view1_ok;
    RAISE NOTICE 'Vista v_equipos_pendientes_verificacion .......... %', v_view2_ok;
    RAISE NOTICE 'Equipos REALMENTE disponibles (con checklist)....: %', v_cnt_real;
    RAISE NOTICE 'Equipos marcados disponibles SIN checklist ......: %', v_cnt_pend;

    IF NOT (v_trigger_ok AND v_view1_ok AND v_view2_ok) THEN
        RAISE EXCEPTION 'Migracion 44 incompleta.';
    END IF;
END $$;
