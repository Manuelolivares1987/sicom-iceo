-- ============================================================================
-- SICOM-ICEO | Migración 30 — Estados Diarios Automáticos + Override Manual
-- ============================================================================
-- Propósito : Implementa la lógica de cascada que decide automáticamente el
--             estado_codigo de cada activo cada día, integrado con el sistema
--             de OTs. El jefe de operaciones / mantenimiento puede hacer
--             override manual desde la UI, y opcionalmente crear OT en el acto.
--
-- Cascada (mayor a menor prioridad):
--   1. Override manual del día (si existe) → respetar
--   2. OT abierta correctiva → T (taller)
--      OT abierta preventiva/inspección → M (mantención)
--   3. Certificación bloqueante vencida → F (fuera de servicio)
--   4. Verificación de disponibilidad vencida >15 días → F
--   5. estado_comercial del activo:
--        arrendado     → A
--        uso_interno   → U
--        leasing       → L
--        disponible    → D
--        en_recepcion  → R
--        en_venta      → V
--        comprometido  → A (reservado)
--        NULL          → H (habilitación / sin clasificar)
--   6. Default → D (disponible)
-- ============================================================================

-- ============================================================================
-- 1. EXTENDER estado_diario_flota CON CAMPOS DE OVERRIDE MANUAL
-- ============================================================================

ALTER TABLE estado_diario_flota
    ADD COLUMN IF NOT EXISTS override_manual  BOOLEAN     NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS motivo_override  TEXT,
    ADD COLUMN IF NOT EXISTS actualizado_por  UUID        REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS actualizado_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ot_relacionada_id UUID       REFERENCES ordenes_trabajo(id),
    ADD COLUMN IF NOT EXISTS calculado_auto   BOOLEAN     NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_estado_diario_override
    ON estado_diario_flota (override_manual) WHERE override_manual = true;

COMMENT ON COLUMN estado_diario_flota.override_manual IS
    'TRUE si el estado fue fijado manualmente y NO debe ser sobreescrito por la cascada automática.';
COMMENT ON COLUMN estado_diario_flota.calculado_auto IS
    'TRUE si el estado fue calculado por fn_calcular_estado_diario_automatico (no manual ni seed).';

-- ============================================================================
-- 2. FUNCIÓN: CALCULAR ESTADO DIARIO AUTOMÁTICO PARA UN ACTIVO
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calcular_estado_diario_automatico(
    p_activo_id UUID,
    p_fecha     DATE DEFAULT CURRENT_DATE
)
RETURNS CHAR(1)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_estado_comercial estado_comercial_enum;
    v_tiene_ot_correctiva BOOLEAN := false;
    v_tiene_ot_preventiva BOOLEAN := false;
    v_tiene_cert_vencida  BOOLEAN := false;
    v_checklist_vencido   BOOLEAN := false;
BEGIN
    -- Cargar el estado_comercial del activo (catálogo)
    SELECT estado_comercial INTO v_estado_comercial
    FROM activos
    WHERE id = p_activo_id;

    -- ── Paso 2: ¿OTs abiertas en la fecha? ──
    -- Una OT está "abierta" si su estado NO está cerrado/cancelado
    -- y su fecha_programada o fecha_inicio cae en o antes de p_fecha
    -- y aún no tiene fecha_termino (o termina después de p_fecha)
    SELECT
        BOOL_OR(tipo = 'correctivo'),
        BOOL_OR(tipo IN ('preventivo','inspeccion','lubricacion'))
    INTO v_tiene_ot_correctiva, v_tiene_ot_preventiva
    FROM ordenes_trabajo
    WHERE activo_id = p_activo_id
      AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                         'no_ejecutada','cancelada')
      AND COALESCE(fecha_programada, fecha_inicio::DATE, p_fecha) <= p_fecha
      AND (fecha_termino IS NULL OR fecha_termino::DATE >= p_fecha);

    IF v_tiene_ot_correctiva THEN
        RETURN 'T';  -- Taller correctivo
    END IF;

    IF v_tiene_ot_preventiva THEN
        RETURN 'M';  -- Mantención programada
    END IF;

    -- ── Paso 3: ¿Certificación bloqueante vencida? ──
    SELECT EXISTS (
        SELECT 1 FROM certificaciones
        WHERE activo_id = p_activo_id
          AND bloqueante = true
          AND fecha_vencimiento < p_fecha
    ) INTO v_tiene_cert_vencida;

    IF v_tiene_cert_vencida THEN
        RETURN 'F';  -- Fuera de servicio por documentación
    END IF;

    -- ── Paso 4: ¿Verificación de disponibilidad vencida >15 días? ──
    -- Si nunca se hizo verificación, también cuenta como vencida
    SELECT NOT EXISTS (
        SELECT 1 FROM verificaciones_disponibilidad
        WHERE activo_id = p_activo_id
          AND resultado IN ('aprobado', 'aprobado_con_observaciones')
          AND fecha_verificacion >= (p_fecha - INTERVAL '15 days')
    ) INTO v_checklist_vencido;

    -- Solo aplicar si el activo es de los que requieren checklist
    -- (camiones cisterna principalmente). Para no bloquear todo de golpe en
    -- producción, este paso queda comentado por defecto. Descomentar cuando
    -- el checklist esté operativizado.
    -- IF v_checklist_vencido AND EXISTS (
    --     SELECT 1 FROM activos WHERE id = p_activo_id
    --       AND tipo IN ('camion_cisterna','camion')
    -- ) THEN
    --     RETURN 'F';
    -- END IF;

    -- ── Paso 5: Mapear estado_comercial → estado_codigo del día ──
    RETURN CASE v_estado_comercial
        WHEN 'arrendado'    THEN 'A'
        WHEN 'uso_interno'  THEN 'U'
        WHEN 'leasing'      THEN 'L'
        WHEN 'disponible'   THEN 'D'
        WHEN 'en_recepcion' THEN 'R'
        WHEN 'en_venta'     THEN 'V'
        WHEN 'comprometido' THEN 'A'  -- Reservado, cuenta como ingreso
        ELSE 'H'  -- NULL u otros → habilitación / sin clasificar
    END;
END;
$$;

COMMENT ON FUNCTION fn_calcular_estado_diario_automatico(UUID, DATE) IS
    'Aplica la cascada de fuentes de verdad para inferir el estado_codigo del día. '
    'NO escribe en la tabla — solo retorna el código calculado.';

-- ============================================================================
-- 3. FUNCIÓN: APLICAR ESTADOS AUTOMÁTICOS A TODA LA FLOTA EN UNA FECHA
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_aplicar_estados_diarios_automaticos(
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    procesados INTEGER,
    nuevos     INTEGER,
    actualizados INTEGER,
    saltados_override INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo RECORD;
    v_estado_calculado CHAR(1);
    v_estado_actual CHAR(1);
    v_override BOOLEAN;
    v_procesados INTEGER := 0;
    v_nuevos INTEGER := 0;
    v_actualizados INTEGER := 0;
    v_saltados INTEGER := 0;
BEGIN
    FOR v_activo IN
        SELECT id, contrato_id, cliente_actual, ubicacion_actual, operacion
        FROM activos
        WHERE estado != 'dado_baja'
    LOOP
        v_procesados := v_procesados + 1;

        -- ¿Existe ya un registro para este activo en esa fecha?
        SELECT estado_codigo, override_manual
        INTO v_estado_actual, v_override
        FROM estado_diario_flota
        WHERE activo_id = v_activo.id AND fecha = p_fecha;

        -- Si existe override manual, no tocar
        IF v_override = true THEN
            v_saltados := v_saltados + 1;
            CONTINUE;
        END IF;

        -- Calcular estado nuevo
        v_estado_calculado := fn_calcular_estado_diario_automatico(v_activo.id, p_fecha);

        IF v_estado_actual IS NULL THEN
            -- INSERT nuevo
            INSERT INTO estado_diario_flota (
                activo_id, fecha, contrato_id, estado_codigo,
                cliente, ubicacion, operacion,
                calculado_auto, override_manual
            ) VALUES (
                v_activo.id, p_fecha, v_activo.contrato_id, v_estado_calculado,
                v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
                true, false
            )
            ON CONFLICT (activo_id, fecha) DO NOTHING;
            v_nuevos := v_nuevos + 1;
        ELSIF v_estado_actual != v_estado_calculado THEN
            -- UPDATE solo si cambió
            UPDATE estado_diario_flota
            SET estado_codigo = v_estado_calculado,
                calculado_auto = true,
                updated_at = NOW()
            WHERE activo_id = v_activo.id AND fecha = p_fecha;
            v_actualizados := v_actualizados + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_procesados, v_nuevos, v_actualizados, v_saltados;
END;
$$;

COMMENT ON FUNCTION fn_aplicar_estados_diarios_automaticos(DATE) IS
    'Recorre todos los activos no dados de baja y aplica fn_calcular_estado_diario_automatico, '
    'respetando los registros marcados como override_manual.';

-- ============================================================================
-- 4. RPC: ACTUALIZAR ESTADO DIARIO MANUALMENTE (con auto-creación de OT)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_actualizar_estado_diario_manual(
    p_activo_id        UUID,
    p_fecha            DATE,
    p_nuevo_estado     CHAR(1),
    p_motivo           TEXT,
    p_crear_ot         BOOLEAN DEFAULT false,
    p_ot_tipo          tipo_ot_enum DEFAULT NULL,
    p_ot_prioridad     prioridad_enum DEFAULT 'normal',
    p_ot_responsable_id UUID DEFAULT NULL,
    p_ot_descripcion   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_activo RECORD;
    v_ot_id UUID;
    v_ot_folio VARCHAR;
    v_existente UUID;
BEGIN
    -- Quién hizo el cambio
    v_user_id := auth.uid();

    -- Validaciones básicas
    IF p_nuevo_estado NOT IN ('A','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- Crear OT si se pide y el estado lo justifica
    IF p_crear_ot AND p_nuevo_estado IN ('M','T') THEN
        -- Validar tipo de OT congruente con el estado
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                              ELSE 'preventivo' END;
        END IF;

        -- Folio: F-<año>-<count+1> (formato simple, replicable)
        v_ot_folio := 'OT-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                      SUBSTRING(p_activo_id::TEXT, 1, 4);

        INSERT INTO ordenes_trabajo (
            folio, tipo, contrato_id, faena_id, activo_id,
            prioridad, estado, responsable_id,
            fecha_programada, observaciones,
            generada_automaticamente, created_by
        ) VALUES (
            v_ot_folio,
            p_ot_tipo,
            v_activo.contrato_id,
            v_activo.faena_id,
            p_activo_id,
            p_ot_prioridad,
            'creada',
            p_ot_responsable_id,
            p_fecha,
            COALESCE(p_ot_descripcion, p_motivo),
            true,
            v_user_id
        )
        RETURNING id INTO v_ot_id;
    END IF;

    -- Upsert del estado_diario_flota con override_manual=true
    SELECT id INTO v_existente
    FROM estado_diario_flota
    WHERE activo_id = p_activo_id AND fecha = p_fecha;

    IF v_existente IS NULL THEN
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo,
            cliente, ubicacion, operacion,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at,
            ot_relacionada_id, observacion, registrado_por
        ) VALUES (
            p_activo_id, p_fecha, v_activo.contrato_id, p_nuevo_estado,
            v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
            true, p_motivo, false,
            v_user_id, NOW(),
            v_ot_id, p_motivo, v_user_id
        );
    ELSE
        UPDATE estado_diario_flota
        SET estado_codigo = p_nuevo_estado,
            override_manual = true,
            motivo_override = p_motivo,
            actualizado_por = v_user_id,
            actualizado_at = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion = p_motivo,
            updated_at = NOW()
        WHERE id = v_existente;
    END IF;

    -- Si pasó a F (fuera de servicio) en estado arrendado → registrar no conformidad
    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        INSERT INTO no_conformidades (
            activo_id, fecha_evento, tipo, severidad, descripcion, created_by
        ) VALUES (
            p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
            'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
            v_user_id
        )
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'estado_aplicado', p_nuevo_estado,
        'ot_creada', v_ot_id IS NOT NULL,
        'ot_id', v_ot_id,
        'ot_folio', v_ot_folio
    );
END;
$$;

COMMENT ON FUNCTION rpc_actualizar_estado_diario_manual IS
    'Endpoint para que la UI actualice el estado del día con override manual. '
    'Opcionalmente crea OT correctiva/preventiva y no_conformidad si aplica.';

-- ============================================================================
-- 5. TRIGGER: Recalcular estado del activo cuando cambia una OT
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_fn_recalcular_estado_por_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_calc CHAR(1);
    v_es_override BOOLEAN;
BEGIN
    -- Solo actuar cuando cambia el estado de la OT
    IF TG_OP = 'UPDATE' AND OLD.estado IS NOT DISTINCT FROM NEW.estado THEN
        RETURN NEW;
    END IF;

    -- ¿El estado del día actual de este activo es manual? Si sí, no tocar.
    SELECT override_manual INTO v_es_override
    FROM estado_diario_flota
    WHERE activo_id = NEW.activo_id AND fecha = CURRENT_DATE;

    IF v_es_override = true THEN
        RETURN NEW;
    END IF;

    -- Recalcular y aplicar
    v_estado_calc := fn_calcular_estado_diario_automatico(NEW.activo_id, CURRENT_DATE);

    INSERT INTO estado_diario_flota (
        activo_id, fecha, estado_codigo, calculado_auto, override_manual
    ) VALUES (
        NEW.activo_id, CURRENT_DATE, v_estado_calc, true, false
    )
    ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo,
        calculado_auto = true,
        updated_at = NOW()
    WHERE estado_diario_flota.override_manual = false;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalcular_estado_por_ot ON ordenes_trabajo;
CREATE TRIGGER trg_recalcular_estado_por_ot
    AFTER INSERT OR UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION trg_fn_recalcular_estado_por_ot();

-- ============================================================================
-- 6. CRON: Ejecutar cálculo automático cada mañana a las 06:00 hora Chile
-- ============================================================================
-- Nota: cron.schedule espera UTC. 06:00 Chile = 09:00 UTC en horario estándar
-- (Chile usa UTC-3 en verano y UTC-4 en invierno; ajustar si es necesario)

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Eliminar job previo si existe (idempotencia)
        PERFORM cron.unschedule('flota_estados_diarios')
        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'flota_estados_diarios');

        PERFORM cron.schedule(
            'flota_estados_diarios',
            '0 9 * * *',  -- 09:00 UTC = ~06:00 Chile
            $job$ SELECT fn_aplicar_estados_diarios_automaticos(CURRENT_DATE); $job$
        );
    END IF;
END $$;

-- ============================================================================
-- 7. EJECUCIÓN INICIAL: aplicar estados automáticos para HOY
-- ============================================================================
-- Esto pobla estado_diario_flota para CURRENT_DATE para todos los activos
-- que no tengan ya un registro override.

SELECT * FROM fn_aplicar_estados_diarios_automaticos(CURRENT_DATE);
