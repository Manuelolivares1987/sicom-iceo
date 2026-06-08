-- ============================================================================
-- SICOM-ICEO | 135 — Fix rpc_crear_ot: pautas con items_checklist como STRINGS
-- ============================================================================
-- Error reportado al armar el plan semanal:
--   null value in column "descripcion" of relation "checklist_ot" violates
--   not-null constraint
--
-- Causa: 75 pautas tienen items_checklist como ARRAY DE STRINGS (ej:
--   ["Cambio aceite I-Shift", "Revisar frenos", ...]) en vez de array de
--   objetos {descripcion:...}. El insert hacia checklist_ot hacia
--   item->>'descripcion', que para un string JSON devuelve NULL -> viola NOT NULL.
--
-- Fix: la descripcion ahora soporta AMBOS formatos:
--   - item string  -> el texto del string (item #>> '{}')
--   - item objeto  -> descripcion / item / nombre / tarea (con fallbacks)
--   y se saltan los items que igual queden sin descripcion.
-- Reproduce el cuerpo de MIG 117, solo cambia el bloque del INSERT del checklist.
-- IDEMPOTENTE (CREATE OR REPLACE).
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

    -- El trigger trg_copiar_checklist_para_ot copia el checklist del template aquí.
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

    -- Si la OT viene de un PLAN, reemplazar el checklist genérico (del trigger)
    -- por el específico de la pauta del fabricante.
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist INTO v_pauta_items
          FROM planes_mantenimiento pm
          JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
         WHERE pm.id = p_plan_mantenimiento_id;
        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            DELETE FROM checklist_ot WHERE ot_id = v_ot_id;
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id, t.ord::INTEGER,
                   -- soporta items como string (texto) o como objeto {descripcion/...}
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

DO $$ BEGIN RAISE NOTICE 'MIG135 OK: rpc_crear_ot soporta items_checklist string/objeto'; END $$;
