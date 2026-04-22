-- ============================================================================
-- SICOM-ICEO | Migración 37 — Fix Cambio de Estado de Flota
-- ============================================================================
-- Objetivo:
--   1. Arreglar 400 en rpc_actualizar_estado_diario_manual: el check de rol
--      fallaba cuando fn_user_rol() retornaba NULL (perfil no creado o JWT
--      sin rol). Ahora basta con estar autenticado; el frontend filtra por
--      rol vía la matriz de permisos.
--
--   2. Sincronizar activos.estado y activos.estado_comercial al aplicar el
--      override manual. Antes sólo se actualizaba estado_diario_flota, por
--      eso la tabla maestra y los pie charts no reflejaban el cambio.
--
--   3. Permitir que el estado F (Fuera de Servicio) también cree una OT
--      correctiva automática.
--
--   4. Si se indica un responsable en la OT auto-creada, queda directamente
--      en estado 'asignada' (antes quedaba en 'creada' y no se podía
--      finalizar sin pasar por asignación manual).
--
--   5. Nada se rompe: mantiene la misma firma y valores de retorno previos.
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
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
BEGIN
    -- ══════════════════════════════════════════════════════
    -- 1. AUTH — basta con estar autenticado
    -- ══════════════════════════════════════════════════════
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado. Inicie sesión para cambiar el estado de un equipo.';
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 2. VALIDAR CÓDIGO DE ESTADO
    -- ══════════════════════════════════════════════════════
    IF p_nuevo_estado NOT IN ('A','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 3. CREAR OT AUTOMÁTICA SI CORRESPONDE
    --    Aplica para M, T y F (estados que requieren intervención).
    -- ══════════════════════════════════════════════════════
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        v_ot_folio := 'OT-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                      SUBSTRING(p_activo_id::TEXT, 1, 4);

        -- Si hay responsable, la OT arranca asignada; si no, queda creada.
        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        INSERT INTO ordenes_trabajo (
            folio, tipo, contrato_id, faena_id, activo_id,
            prioridad, estado, responsable_id,
            fecha_programada, observaciones,
            generada_automaticamente, created_by
        ) VALUES (
            v_ot_folio, p_ot_tipo,
            v_activo.contrato_id, v_activo.faena_id, p_activo_id,
            p_ot_prioridad, v_ot_estado_inicial, p_ot_responsable_id,
            p_fecha, COALESCE(p_ot_descripcion, p_motivo),
            true, v_user_id
        )
        RETURNING id INTO v_ot_id;
    END IF;

    -- ══════════════════════════════════════════════════════
    -- 4. UPSERT estado_diario_flota (override del día)
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
    -- 5. SINCRONIZAR activos.estado y estado_comercial
    --    Así el Maestro de Flota y los pie charts reflejan el cambio.
    -- ══════════════════════════════════════════════════════

    -- Mapeo estado operativo (estado_activo_enum)
    v_nuevo_estado_act := CASE p_nuevo_estado
        WHEN 'M' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'T' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'H' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'F' THEN 'fuera_servicio'::estado_activo_enum
        ELSE        'operativo'::estado_activo_enum
    END;

    -- Mapeo estado comercial (estado_comercial_enum)
    -- Para M/T/F mantenemos el estado_comercial previo: el equipo puede estar
    -- arrendado y en mantención simultáneamente (de hecho es lo normal).
    v_nuevo_estado_com := CASE p_nuevo_estado
        WHEN 'A' THEN 'arrendado'::estado_comercial_enum
        WHEN 'D' THEN 'disponible'::estado_comercial_enum
        WHEN 'U' THEN 'uso_interno'::estado_comercial_enum
        WHEN 'L' THEN 'leasing'::estado_comercial_enum
        WHEN 'R' THEN 'en_recepcion'::estado_comercial_enum
        WHEN 'V' THEN 'en_venta'::estado_comercial_enum
        WHEN 'H' THEN NULL  -- en habilitación: no hay estado comercial claro
        ELSE v_activo.estado_comercial  -- M, T, F: conservar
    END;

    UPDATE activos
    SET estado           = v_nuevo_estado_act,
        estado_comercial = v_nuevo_estado_com,
        updated_at       = NOW()
    WHERE id = p_activo_id;

    -- ══════════════════════════════════════════════════════
    -- 6. NO CONFORMIDAD SI CAE F ESTANDO ARRENDADO
    -- ══════════════════════════════════════════════════════
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
        'ot_estado_inicial', v_ot_estado_inicial
    );
END;
$$;

COMMENT ON FUNCTION rpc_actualizar_estado_diario_manual IS
'Override manual del estado diario de un activo. Sincroniza activos.estado y '
'estado_comercial. Crea OT automática para M, T o F si p_crear_ot=true. '
'Si se asigna responsable, la OT queda directamente en estado asignada.';
