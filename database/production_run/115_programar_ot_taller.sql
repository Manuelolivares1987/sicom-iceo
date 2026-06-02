-- ============================================================================
-- SICOM-ICEO | 115 — Planificación de taller: programar OT desde un equipo
-- ============================================================================
-- 1. rpc_crear_ot ahora permite crear OT para activos en 'fuera_servicio'
--    (antes solo operativo/en_mantenimiento) — son justo los que hay que
--    programar para repararlos.
-- 2. rpc_programar_ot_taller(activo, tipo, ...): wrapper que resuelve
--    contrato (activo del equipo o interno) y faena, y llama a rpc_crear_ot.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_crear_ot(
    p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid,
    p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha_programada date DEFAULT NULL::date, p_responsable_id uuid DEFAULT NULL::uuid,
    p_plan_mantenimiento_id uuid DEFAULT NULL::uuid, p_usuario_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
    SELECT id, estado INTO v_contrato FROM contratos WHERE id = p_contrato_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Contrato no encontrado'; END IF;
    IF v_contrato.estado != 'activo' THEN RAISE EXCEPTION 'Contrato no activo'; END IF;

    SELECT id, estado, codigo INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activo no encontrado'; END IF;
    -- Permitir tambien 'fuera_servicio' (se programa OT para repararlo).
    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento', 'fuera_servicio') THEN
        RAISE EXCEPTION 'Activo en estado "%" no permite OT', v_activo.estado;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
      INTO v_secuencia FROM ordenes_trabajo WHERE folio LIKE 'OT-' || v_periodo || '-%';

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

    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist INTO v_pauta_items
          FROM planes_mantenimiento pm
          JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
         WHERE pm.id = p_plan_mantenimiento_id;
        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id, (item->>'orden')::INTEGER, item->>'descripcion',
                   COALESCE((item->>'obligatorio')::BOOLEAN, true),
                   COALESCE((item->>'requiere_foto')::BOOLEAN, false)
              FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    ELSE
        SELECT items INTO v_pauta_items FROM checklist_templates
         WHERE tipo_ot = p_tipo AND activo = true ORDER BY created_at DESC LIMIT 1;
        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id, (item->>'orden')::INTEGER, item->>'descripcion',
                   COALESCE((item->>'obligatorio')::BOOLEAN, true),
                   COALESCE((item->>'requiere_foto')::BOOLEAN, false)
              FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    END IF;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    RETURN jsonb_build_object('id', v_ot_id, 'folio', v_folio, 'estado', v_estado,
        'qr_code', v_qr_code, 'activo_codigo', v_activo.codigo);
END;
$function$;

-- ── Wrapper: programar OT desde el planificador de taller ───────────────────
CREATE OR REPLACE FUNCTION public.rpc_programar_ot_taller(
    p_activo_id uuid,
    p_tipo tipo_ot_enum,
    p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha date DEFAULT NULL::date,
    p_responsable_id uuid DEFAULT NULL::uuid,
    p_plan_mantenimiento_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_contrato_id uuid;
    v_faena_id    uuid;
    v_a_contrato  uuid;
    v_a_faena     uuid;
BEGIN
    SELECT contrato_id, faena_id INTO v_a_contrato, v_a_faena FROM activos WHERE id = p_activo_id;

    -- Contrato: el del activo si está activo; si no, el contrato interno.
    SELECT id INTO v_contrato_id FROM contratos WHERE id = v_a_contrato AND estado = 'activo';
    IF v_contrato_id IS NULL THEN v_contrato_id := fn_contrato_interno_id(); END IF;

    v_faena_id := COALESCE(v_a_faena, fn_faena_interna_id());

    RETURN rpc_crear_ot(p_tipo, v_contrato_id, v_faena_id, p_activo_id, p_prioridad,
                        p_fecha, p_responsable_id, p_plan_mantenimiento_id, auth.uid());
END;
$function$;

GRANT EXECUTE ON FUNCTION rpc_programar_ot_taller(uuid, tipo_ot_enum, prioridad_enum, date, uuid, uuid) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG115 OK: rpc_crear_ot permite fuera_servicio + rpc_programar_ot_taller creado'; END $$;
