-- ============================================================================
-- SICOM-ICEO | Migración 38 — Fix OT automática cuando activo no tiene contrato
-- ============================================================================
-- Causa raíz del 400 persistente tras migración 37:
--   ordenes_trabajo.contrato_id y faena_id son NOT NULL. Cuando un activo
--   sin contrato/faena (ej. un Disponible sin asignar) cambia a M/T/F y se
--   pide crear OT, el INSERT falla y hace rollback de TODA la transacción.
--
-- Fix:
--   1. Crear un contrato "INTERNO" y una faena "INTERNA" si no existen.
--      Sirven como fallback para OTs internas (mantención de equipos
--      disponibles, pre-entregas, recepciones).
--
--   2. rpc_actualizar_estado_diario_manual ahora:
--      a) Usa el contrato/faena del activo si existen.
--      b) Si no, usa los fallback "INTERNO/INTERNA".
--      c) Si ni eso funciona (no debería), registra el override de estado
--         igualmente pero devuelve ot_creada=false con mensaje de alerta,
--         en vez de rollback 400.
--
--   3. Captura excepciones del INSERT de OT con EXCEPTION WHEN OTHERS para
--      no perder el cambio de estado aunque la OT falle por cualquier razón.
-- ============================================================================

-- ============================================================================
-- 1. CONTRATO Y FAENA DE USO INTERNO (fallback)
-- ============================================================================

DO $$
DECLARE
    v_contrato_interno_id UUID;
    v_faena_interna_id    UUID;
BEGIN
    -- Contrato INTERNO
    SELECT id INTO v_contrato_interno_id
    FROM contratos
    WHERE codigo = 'INTERNO';

    IF v_contrato_interno_id IS NULL THEN
        INSERT INTO contratos (
            codigo, nombre, cliente, descripcion,
            fecha_inicio, estado, moneda
        ) VALUES (
            'INTERNO',
            'Operación Interna Pillado',
            'Prefabricadas Premium',
            'Contrato marco interno para OTs sobre equipos sin contrato externo asignado (stand-by, habilitación, mantención pre-arriendo).',
            CURRENT_DATE, 'activo', 'CLP'
        )
        RETURNING id INTO v_contrato_interno_id;
        RAISE NOTICE 'Contrato INTERNO creado: %', v_contrato_interno_id;
    END IF;

    -- Faena INTERNA
    SELECT id INTO v_faena_interna_id
    FROM faenas
    WHERE codigo = 'FAENA-INTERNA';

    IF v_faena_interna_id IS NULL THEN
        INSERT INTO faenas (
            contrato_id, codigo, nombre, ubicacion, region, estado
        ) VALUES (
            v_contrato_interno_id,
            'FAENA-INTERNA',
            'Taller Central Pillado',
            'Taller interno / Base operaciones',
            'Coquimbo',
            'activa'
        )
        RETURNING id INTO v_faena_interna_id;
        RAISE NOTICE 'Faena INTERNA creada: %', v_faena_interna_id;
    END IF;
END $$;

-- ============================================================================
-- 2. HELPER: obtener contrato/faena INTERNO (para RPCs)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_contrato_interno_id()
RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT id FROM contratos WHERE codigo = 'INTERNO' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_faena_interna_id()
RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT id FROM faenas WHERE codigo = 'FAENA-INTERNA' LIMIT 1;
$$;

-- ============================================================================
-- 3. RPC ROBUSTO — no tumba el cambio de estado si la OT falla
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
    v_ot_folio           VARCHAR;
    v_ot_estado_inicial  estado_ot_enum;
    v_ot_contrato_id     UUID;
    v_ot_faena_id        UUID;
    v_ot_error           TEXT;
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
BEGIN
    -- ══════════════════════════════════════════════════════
    -- 1. AUTH
    -- ══════════════════════════════════════════════════════
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado. Inicie sesión para cambiar el estado de un equipo.';
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 2. VALIDAR CÓDIGO
    -- ══════════════════════════════════════════════════════
    IF p_nuevo_estado NOT IN ('A','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 3. CREAR OT AUTOMÁTICA (M, T, F)
    -- ══════════════════════════════════════════════════════
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        -- Fallback a contrato/faena INTERNO si el activo no tiene
        v_ot_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
        v_ot_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

        v_ot_folio := 'OT-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                      SUBSTRING(p_activo_id::TEXT, 1, 4);

        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        -- BLOQUE PROTEGIDO — si la OT falla, el cambio de estado sí se aplica
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

    -- ══════════════════════════════════════════════════════
    -- 4. UPSERT estado_diario_flota
    -- ══════════════════════════════════════════════════════
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

    -- ══════════════════════════════════════════════════════
    -- 5. SINCRONIZAR activos.estado + estado_comercial
    -- ══════════════════════════════════════════════════════
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

    -- ══════════════════════════════════════════════════════
    -- 6. NO CONFORMIDAD F+arrendado (protegida también)
    -- ══════════════════════════════════════════════════════
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
        EXCEPTION WHEN OTHERS THEN
            -- Si el tipo no existe en el enum o hay otro problema, no tumbar el cambio
            NULL;
        END;
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 7. RESULTADO
    -- ══════════════════════════════════════════════════════
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

COMMENT ON FUNCTION rpc_actualizar_estado_diario_manual IS
'v3 (mig 38): robusta — si la OT automática falla (sin contrato/faena, etc.) '
'se sigue aplicando el cambio de estado y se retorna ot_error con el detalle.';


-- ============================================================================
-- 4. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_contrato UUID;
    v_faena    UUID;
BEGIN
    v_contrato := fn_contrato_interno_id();
    v_faena    := fn_faena_interna_id();

    RAISE NOTICE '── Migración 38 aplicada ──';
    RAISE NOTICE 'Contrato INTERNO id:  %', v_contrato;
    RAISE NOTICE 'Faena INTERNA id:     %', v_faena;

    IF v_contrato IS NULL OR v_faena IS NULL THEN
        RAISE EXCEPTION 'Fallback contrato/faena INTERNO no creado correctamente.';
    END IF;
END $$;
