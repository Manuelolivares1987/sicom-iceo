-- ============================================================================
-- SICOM-ICEO | Migración 39 — Fix folio OT en cambio de estado manual
-- ============================================================================
-- Bug: el folio generado en rpc_actualizar_estado_diario_manual tenía formato
--      'OT-YYYYMMDD-HH24MISS-XXXX' = 23 caracteres, pero la columna
--      ordenes_trabajo.folio es VARCHAR(20). Error 22001: value too long.
--
-- Este bug existía desde la migración 30. La migración 38 lo mantuvo.
--
-- Fix: usar el mismo patrón secuencial estándar del sistema:
--      'OT-YYYYMM-NNNNN' = 15 caracteres (secuencia por mes con advisory lock).
--
-- Bonus: horas_reales como vista — se calcula automáticamente entre
--        fecha_inicio y fecha_termino. Así Jefe de Taller no ingresa horas
--        manualmente, sólo pone "Iniciar OT" / "Finalizar OT" y las horas
--        de trabajo se calculan solas.
-- ============================================================================

-- ============================================================================
-- 1. RPC con folio corregido (formato secuencial estándar)
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
    v_user_id            UUID;
    v_activo             RECORD;
    v_ot_id              UUID;
    v_ot_folio           VARCHAR(20);
    v_ot_estado_inicial  estado_ot_enum;
    v_ot_contrato_id     UUID;
    v_ot_faena_id        UUID;
    v_ot_error           TEXT;
    v_periodo            VARCHAR(6);
    v_secuencia          INTEGER;
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
BEGIN
    -- 1. AUTH
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- 2. VALIDAR CÓDIGO
    IF p_nuevo_estado NOT IN ('A','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- 3. CREAR OT AUTOMÁTICA (M, T, F)
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        v_ot_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
        v_ot_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        -- Advisory lock para serializar la secuencia
        PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(
            CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
        ), 0) + 1
        INTO v_secuencia
        FROM ordenes_trabajo
        WHERE folio LIKE 'OT-' || v_periodo || '-%';

        -- Formato estándar: OT-YYYYMM-NNNNN (15 chars, cabe en VARCHAR(20))
        v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

        BEGIN
            INSERT INTO ordenes_trabajo (
                folio, tipo, contrato_id, faena_id, activo_id,
                prioridad, estado, responsable_id,
                fecha_programada, observaciones,
                generada_automaticamente, created_by
            ) VALUES (
                v_ot_folio, p_ot_tipo,
                v_ot_contrato_id, v_ot_faena_id, p_activo_id,
                p_ot_prioridad, v_ot_estado_inicial, p_ot_responsable_id,
                p_fecha, COALESCE(p_ot_descripcion, p_motivo),
                true, v_user_id
            )
            RETURNING id INTO v_ot_id;
        EXCEPTION WHEN OTHERS THEN
            v_ot_error := SQLERRM;
            v_ot_id := NULL;
            v_ot_folio := NULL;
        END;
    END IF;

    -- 4. UPSERT estado_diario_flota
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
        SET estado_codigo     = p_nuevo_estado,
            override_manual   = true,
            motivo_override   = p_motivo,
            actualizado_por   = v_user_id,
            actualizado_at    = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion       = p_motivo,
            updated_at        = NOW()
        WHERE id = v_existente;
    END IF;

    -- 5. SINCRONIZAR activos.estado + estado_comercial
    v_nuevo_estado_act := CASE p_nuevo_estado
        WHEN 'M' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'T' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'H' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'F' THEN 'fuera_servicio'::estado_activo_enum
        ELSE        'operativo'::estado_activo_enum
    END;

    v_nuevo_estado_com := CASE p_nuevo_estado
        WHEN 'A' THEN 'arrendado'::estado_comercial_enum
        WHEN 'D' THEN 'disponible'::estado_comercial_enum
        WHEN 'U' THEN 'uso_interno'::estado_comercial_enum
        WHEN 'L' THEN 'leasing'::estado_comercial_enum
        WHEN 'R' THEN 'en_recepcion'::estado_comercial_enum
        WHEN 'V' THEN 'en_venta'::estado_comercial_enum
        WHEN 'H' THEN NULL
        ELSE v_activo.estado_comercial
    END;

    UPDATE activos
    SET estado           = v_nuevo_estado_act,
        estado_comercial = v_nuevo_estado_com,
        updated_at       = NOW()
    WHERE id = p_activo_id;

    -- 6. NO CONFORMIDAD F+arrendado (protegida)
    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        BEGIN
            INSERT INTO no_conformidades (
                activo_id, fecha_evento, tipo, severidad, descripcion, created_by
            ) VALUES (
                p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
                'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
                v_user_id
            )
            ON CONFLICT DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 7. RESULTADO
    RETURN jsonb_build_object(
        'success',           true,
        'estado_aplicado',   p_nuevo_estado,
        'activo_estado',     v_nuevo_estado_act,
        'activo_comercial',  v_nuevo_estado_com,
        'ot_creada',         v_ot_id IS NOT NULL,
        'ot_id',             v_ot_id,
        'ot_folio',          v_ot_folio,
        'ot_estado_inicial', v_ot_estado_inicial,
        'ot_error',          v_ot_error
    );
END;
$$;


-- ============================================================================
-- 2. VISTA con horas reales calculadas automáticamente
-- ============================================================================
-- Jefe de Taller no ingresa horas manualmente: basta con que las transiciones
-- "iniciar OT" y "finalizar OT" pongan fecha_inicio y fecha_termino.
-- La vista v_ot_con_horas expone las horas reales trabajadas (incluye pausas
-- como tiempo bruto; si se requiere descontar pausas, se calcula desde
-- historial_estado_ot).
-- ============================================================================

CREATE OR REPLACE VIEW v_ot_con_horas AS
SELECT
    ot.*,
    -- Horas brutas (inicio → término)
    CASE
        WHEN ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0, 2)
        ELSE NULL
    END AS horas_reales,

    -- Horas netas (descontando tiempo en pausa)
    CASE
        WHEN ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL
        THEN GREATEST(
            0,
            ROUND(
                EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0
                - COALESCE((
                    SELECT SUM(EXTRACT(EPOCH FROM (h_fin.created_at - h_ini.created_at)) / 3600.0)
                    FROM historial_estado_ot h_ini
                    JOIN historial_estado_ot h_fin ON h_fin.ot_id = h_ini.ot_id
                    WHERE h_ini.ot_id = ot.id
                      AND h_ini.estado_nuevo = 'pausada'
                      AND h_fin.estado_nuevo = 'en_ejecucion'
                      AND h_fin.created_at > h_ini.created_at
                      AND NOT EXISTS (
                          SELECT 1 FROM historial_estado_ot h_mid
                          WHERE h_mid.ot_id = h_ini.ot_id
                            AND h_mid.created_at BETWEEN h_ini.created_at AND h_fin.created_at
                            AND h_mid.id NOT IN (h_ini.id, h_fin.id)
                      )
                ), 0),
                2
            )
        )
        ELSE NULL
    END AS horas_netas
FROM ordenes_trabajo ot;

COMMENT ON VIEW v_ot_con_horas IS
'Expone OTs con horas_reales (bruto) y horas_netas (descontando pausas). '
'Jefe de Taller no necesita ingresar horas manualmente.';


-- ============================================================================
-- 3. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_test_folio VARCHAR;
    v_test_length INTEGER;
BEGIN
    v_test_folio := 'OT-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD('99999', 5, '0');
    v_test_length := LENGTH(v_test_folio);

    RAISE NOTICE '── Migración 39 aplicada ──';
    RAISE NOTICE 'Formato folio:  %', v_test_folio;
    RAISE NOTICE 'Longitud:       % (max permitido 20)', v_test_length;

    IF v_test_length > 20 THEN
        RAISE EXCEPTION 'Folio demasiado largo: % chars', v_test_length;
    END IF;
END $$;
