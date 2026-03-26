-- SICOM-ICEO | Fix: FOR UPDATE incompatible con MAX() en rpc_crear_ot
-- ============================================================================
-- PostgreSQL no permite FOR UPDATE con funciones aggregate (MAX).
-- Solución: usar pg_advisory_xact_lock para serializar generación de folios.
-- ============================================================================

DROP FUNCTION IF EXISTS rpc_crear_ot(tipo_ot_enum, UUID, UUID, UUID, prioridad_enum, DATE, UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION rpc_crear_ot(
    p_tipo           tipo_ot_enum,
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_activo_id      UUID,
    p_prioridad      prioridad_enum DEFAULT 'normal',
    p_fecha_programada DATE DEFAULT NULL,
    p_responsable_id UUID DEFAULT NULL,
    p_plan_mantenimiento_id UUID DEFAULT NULL,
    p_usuario_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_folio       VARCHAR(20);
    v_periodo     TEXT;
    v_secuencia   INTEGER;
    v_ot_id       UUID;
    v_qr_code     VARCHAR(100);
    v_estado      estado_ot_enum;
    v_pauta_items JSONB;
    v_activo      RECORD;
    v_contrato    RECORD;
BEGIN
    -- Validar contrato
    SELECT id, estado INTO v_contrato FROM contratos WHERE id = p_contrato_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Contrato no encontrado'; END IF;
    IF v_contrato.estado != 'activo' THEN RAISE EXCEPTION 'Contrato no activo'; END IF;

    -- Validar activo
    SELECT id, estado, codigo INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activo no encontrado'; END IF;
    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento') THEN
        RAISE EXCEPTION 'Activo en estado "%" no permite OT', v_activo.estado;
    END IF;

    -- Advisory lock para serializar folios (reemplaza FOR UPDATE con MAX)
    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(
        CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
    ), 0) + 1
    INTO v_secuencia
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%';

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    v_estado := CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'creada' END;

    INSERT INTO ordenes_trabajo (
        id, folio, tipo, contrato_id, faena_id, activo_id,
        plan_mantenimiento_id, prioridad, estado,
        responsable_id, fecha_programada, qr_code,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_id, v_folio, p_tipo, p_contrato_id, p_faena_id, p_activo_id,
        p_plan_mantenimiento_id, p_prioridad, v_estado,
        p_responsable_id, p_fecha_programada, v_qr_code,
        (p_plan_mantenimiento_id IS NOT NULL), p_usuario_id
    );

    -- Checklist desde pauta PM
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist INTO v_pauta_items
        FROM planes_mantenimiento pm
        JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
        WHERE pm.id = p_plan_mantenimiento_id;

        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id,
                (item->>'orden')::INTEGER, item->>'descripcion',
                COALESCE((item->>'obligatorio')::BOOLEAN, true),
                COALESCE((item->>'requiere_foto')::BOOLEAN, false)
            FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    ELSE
        -- Checklist desde template genérico
        SELECT items INTO v_pauta_items
        FROM checklist_templates
        WHERE tipo_ot = p_tipo AND activo = true
        ORDER BY created_at DESC LIMIT 1;

        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id,
                (item->>'orden')::INTEGER, item->>'descripcion',
                COALESCE((item->>'obligatorio')::BOOLEAN, true),
                COALESCE((item->>'requiere_foto')::BOOLEAN, false)
            FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    END IF;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    RETURN jsonb_build_object(
        'id', v_ot_id, 'folio', v_folio, 'estado', v_estado,
        'qr_code', v_qr_code, 'activo_codigo', v_activo.codigo
    );
END;
$$;
