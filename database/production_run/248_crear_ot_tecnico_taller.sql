-- ============================================================================
-- SICOM-ICEO | 248 — Crear OT: asignar el TÉCNICO real (taller_tecnicos)
-- ----------------------------------------------------------------------------
-- Sugerencia (Jefe de Taller, 💡): "al crear una OT actualizar los nombres de
-- los técnicos y mecánicos". El selector salía de usuarios_perfil (todos los
-- usuarios), no de los mecánicos reales del taller (tabla taller_tecnicos:
-- Danny Guerra, Felipe López, Joel Coo, Marcos Diaz, etc.).
--
-- ordenes_trabajo ya tiene la columna tecnico_id (FK → taller_tecnicos), pero
-- rpc_crear_ot no la seteaba. Se agrega p_tecnico_id. La OT queda 'asignada' si
-- hay técnico O responsable.
--
-- Agregar un parámetro crea un OVERLOAD nuevo → primero se elimina la firma
-- antigua de 9 args para evitar ambigüedad en PostgREST. IDEMPOTENTE.
-- ============================================================================

DROP FUNCTION IF EXISTS public.rpc_crear_ot(
    tipo_ot_enum, uuid, uuid, uuid, prioridad_enum, date, uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION public.rpc_crear_ot(
    p_tipo tipo_ot_enum,
    p_contrato_id uuid,
    p_faena_id uuid,
    p_activo_id uuid,
    p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha_programada date DEFAULT NULL::date,
    p_responsable_id uuid DEFAULT NULL::uuid,
    p_plan_mantenimiento_id uuid DEFAULT NULL::uuid,
    p_usuario_id uuid DEFAULT NULL::uuid,
    p_tecnico_id uuid DEFAULT NULL::uuid    -- NUEVO: mecánico de taller_tecnicos
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
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
    -- [MIG189] Autorización fail-closed.
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'create', ARRAY['administrador','jefe_mantenimiento','jefe_operaciones','planificador','supervisor']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'create' USING ERRCODE = '42501';
    END IF;

    SELECT id, estado INTO v_contrato FROM contratos WHERE id = p_contrato_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Contrato no encontrado'; END IF;
    IF v_contrato.estado != 'activo' THEN RAISE EXCEPTION 'Contrato no activo'; END IF;

    SELECT id, estado, codigo INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activo no encontrado'; END IF;
    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento', 'fuera_servicio') THEN
        RAISE EXCEPTION 'Activo en estado "%" no permite OT', v_activo.estado;
    END IF;

    -- Validar técnico si se envía.
    IF p_tecnico_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM taller_tecnicos WHERE id = p_tecnico_id) THEN
        RAISE EXCEPTION 'Técnico % no existe', p_tecnico_id;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
      INTO v_secuencia FROM ordenes_trabajo WHERE folio LIKE 'OT-' || v_periodo || '-%';

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    -- 'asignada' si hay técnico O responsable.
    v_estado := CASE WHEN p_responsable_id IS NOT NULL OR p_tecnico_id IS NOT NULL
                     THEN 'asignada' ELSE 'creada' END;

    INSERT INTO ordenes_trabajo (
        id, folio, tipo, contrato_id, faena_id, activo_id,
        plan_mantenimiento_id, prioridad, estado,
        responsable_id, tecnico_id, fecha_programada, qr_code,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_id, v_folio, p_tipo, p_contrato_id, p_faena_id, p_activo_id,
        p_plan_mantenimiento_id, p_prioridad, v_estado,
        p_responsable_id, p_tecnico_id, p_fecha_programada, v_qr_code,
        (p_plan_mantenimiento_id IS NOT NULL), p_usuario_id
    );

    -- Si la OT viene de un PLAN, reemplazar el checklist genérico por el de la pauta.
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist INTO v_pauta_items
          FROM planes_mantenimiento pm
          JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
         WHERE pm.id = p_plan_mantenimiento_id;
        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            DELETE FROM checklist_ot WHERE ot_id = v_ot_id;
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id, t.ord::INTEGER,
                   CASE WHEN jsonb_typeof(t.item) = 'string' THEN t.item #>> '{}'
                        ELSE COALESCE(NULLIF(TRIM(t.item->>'descripcion'),''),
                                      NULLIF(TRIM(t.item->>'item'),''),
                                      NULLIF(TRIM(t.item->>'nombre'),''),
                                      NULLIF(TRIM(t.item->>'tarea'),''))
                   END,
                   COALESCE((t.item->>'obligatorio')::BOOLEAN, true),
                   COALESCE((t.item->>'requiere_foto')::BOOLEAN, false)
              FROM jsonb_array_elements(v_pauta_items) WITH ORDINALITY AS t(item, ord)
             WHERE (CASE WHEN jsonb_typeof(t.item) = 'string' THEN t.item #>> '{}'
                         ELSE COALESCE(NULLIF(TRIM(t.item->>'descripcion'),''),
                                       NULLIF(TRIM(t.item->>'item'),''),
                                       NULLIF(TRIM(t.item->>'nombre'),''),
                                       NULLIF(TRIM(t.item->>'tarea'),''))
                    END) IS NOT NULL;
        END IF;
    END IF;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    RETURN jsonb_build_object('id', v_ot_id, 'folio', v_folio, 'estado', v_estado,
        'qr_code', v_qr_code, 'activo_codigo', v_activo.codigo);
END;
$function$;

-- Validación
DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace nm ON nm.oid=p.pronamespace
     WHERE p.proname='rpc_crear_ot' AND nm.nspname='public'
       AND pg_get_function_identity_arguments(p.oid) LIKE '%p_tecnico_id%';
    IF n < 1 THEN RAISE EXCEPTION 'FALLO: rpc_crear_ot no tiene p_tecnico_id'; END IF;
    RAISE NOTICE 'MIG248 OK: rpc_crear_ot acepta p_tecnico_id';
END $$;

NOTIFY pgrst, 'reload schema';
