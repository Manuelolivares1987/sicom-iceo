-- SICOM-ICEO | Checklist Templates + Auto-assign to manual OTs
-- ============================================================================
-- Ejecutar DESPUÉS de 21_fix_rls_lectura_general.sql
--
-- 1. Tabla de plantillas de checklist por tipo de OT
-- 2. Seed templates para cada tipo de OT
-- 3. Actualiza rpc_crear_ot para auto-asignar checklist desde template
-- ============================================================================


-- ############################################################################
-- 1. TABLA DE PLANTILLAS DE CHECKLIST
-- ############################################################################

CREATE TABLE IF NOT EXISTS checklist_templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo_ot     tipo_ot_enum NOT NULL,
    nombre      VARCHAR(200) NOT NULL,
    descripcion TEXT,
    items       JSONB NOT NULL DEFAULT '[]',
    activo      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checklist_templates_tipo ON checklist_templates (tipo_ot, activo);

-- RLS
ALTER TABLE checklist_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_authenticated_select_checklist_templates ON checklist_templates
    FOR SELECT TO authenticated USING (true);


-- ############################################################################
-- 2. SEED DATA — Plantillas genéricas por tipo de OT
-- ############################################################################

INSERT INTO checklist_templates (tipo_ot, nombre, items) VALUES
('preventivo', 'Checklist General Preventivo', '[
  {"orden": 1, "descripcion": "Inspección visual general del equipo", "obligatorio": true, "requiere_foto": false},
  {"orden": 2, "descripcion": "Verificar niveles de aceite y fluidos", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Verificar estado de filtros", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Verificar presión de neumáticos (si aplica)", "obligatorio": false, "requiere_foto": false},
  {"orden": 5, "descripcion": "Verificar sistema eléctrico y luces", "obligatorio": true, "requiere_foto": false},
  {"orden": 6, "descripcion": "Verificar estado de mangueras y conexiones", "obligatorio": true, "requiere_foto": true},
  {"orden": 7, "descripcion": "Limpieza general del equipo", "obligatorio": false, "requiere_foto": true},
  {"orden": 8, "descripcion": "Registrar lectura de horómetro/odómetro", "obligatorio": true, "requiere_foto": true}
]'),
('correctivo', 'Checklist General Correctivo', '[
  {"orden": 1, "descripcion": "Identificar y documentar la falla", "obligatorio": true, "requiere_foto": true},
  {"orden": 2, "descripcion": "Evaluar daños colaterales", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Ejecutar reparación", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Verificar funcionamiento post-reparación", "obligatorio": true, "requiere_foto": false},
  {"orden": 5, "descripcion": "Registrar causa raíz de la falla", "obligatorio": true, "requiere_foto": false},
  {"orden": 6, "descripcion": "Foto estado final del equipo", "obligatorio": true, "requiere_foto": true}
]'),
('inspeccion', 'Checklist Inspección General', '[
  {"orden": 1, "descripcion": "Inspección visual externa", "obligatorio": true, "requiere_foto": true},
  {"orden": 2, "descripcion": "Verificar señalética y etiquetas de seguridad", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Verificar extintores y elementos de emergencia", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Verificar estado de pintura y corrosión", "obligatorio": false, "requiere_foto": true},
  {"orden": 5, "descripcion": "Registrar observaciones generales", "obligatorio": true, "requiere_foto": false}
]'),
('abastecimiento', 'Checklist Abastecimiento', '[
  {"orden": 1, "descripcion": "Verificar nivel inicial del estanque", "obligatorio": true, "requiere_foto": true},
  {"orden": 2, "descripcion": "Verificar conexión de manguera sin fugas", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Registrar volumen despachado", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Verificar nivel final del estanque", "obligatorio": true, "requiere_foto": true},
  {"orden": 5, "descripcion": "Verificar ausencia de derrames", "obligatorio": true, "requiere_foto": true}
]'),
('lubricacion', 'Checklist Lubricación', '[
  {"orden": 1, "descripcion": "Identificar puntos de lubricación", "obligatorio": true, "requiere_foto": false},
  {"orden": 2, "descripcion": "Aplicar lubricante según pauta", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Verificar ausencia de fugas post-lubricación", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Registrar tipo y cantidad de lubricante usado", "obligatorio": true, "requiere_foto": false},
  {"orden": 5, "descripcion": "Foto evidencia de lubricación completada", "obligatorio": true, "requiere_foto": true}
]'),
('inventario', 'Checklist Conteo Inventario', '[
  {"orden": 1, "descripcion": "Verificar acceso a bodega/ubicación", "obligatorio": true, "requiere_foto": false},
  {"orden": 2, "descripcion": "Realizar conteo físico de productos", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Comparar conteo con sistema", "obligatorio": true, "requiere_foto": false},
  {"orden": 4, "descripcion": "Documentar diferencias encontradas", "obligatorio": true, "requiere_foto": true},
  {"orden": 5, "descripcion": "Registrar observaciones de estado de productos", "obligatorio": false, "requiere_foto": false}
]'),
('regularizacion', 'Checklist Regularización', '[
  {"orden": 1, "descripcion": "Identificar la irregularidad a corregir", "obligatorio": true, "requiere_foto": true},
  {"orden": 2, "descripcion": "Ejecutar acción correctiva", "obligatorio": true, "requiere_foto": false},
  {"orden": 3, "descripcion": "Verificar que la regularización quedó correcta", "obligatorio": true, "requiere_foto": true},
  {"orden": 4, "descripcion": "Documentar motivo de la regularización", "obligatorio": true, "requiere_foto": false}
]')
ON CONFLICT DO NOTHING;


-- ############################################################################
-- 3. ACTUALIZAR rpc_crear_ot — auto-asignar checklist desde template
-- ############################################################################
-- Re-create the function with the template fallback logic added after the PM checklist block.

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
    -- == VALIDACIONES PREVIAS ==

    -- Validar contrato activo
    SELECT id, estado INTO v_contrato
    FROM contratos WHERE id = p_contrato_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contrato no encontrado: %', p_contrato_id;
    END IF;

    IF v_contrato.estado != 'activo' THEN
        RAISE EXCEPTION 'No se puede crear OT en contrato con estado "%".', v_contrato.estado;
    END IF;

    -- Validar activo existe y está operativo
    SELECT id, estado, codigo INTO v_activo
    FROM activos WHERE id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado: %', p_activo_id;
    END IF;

    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento') THEN
        RAISE EXCEPTION 'No se puede crear OT para activo en estado "%". Solo operativo o en_mantenimiento.', v_activo.estado;
    END IF;

    -- == GENERAR FOLIO ATÓMICO ==
    v_periodo := TO_CHAR(NOW(), 'YYYYMM');

    SELECT COALESCE(MAX(
        CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
    ), 0) + 1
    INTO v_secuencia
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%'
    FOR UPDATE;

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    v_estado := CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'creada' END;

    -- == INSERTAR OT ==
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

    -- == COPIAR CHECKLIST DESDE PAUTA (PM) ==
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist
        INTO v_pauta_items
        FROM planes_mantenimiento pm
        JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
        WHERE pm.id = p_plan_mantenimiento_id;

        IF v_pauta_items IS NOT NULL THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT
                gen_random_uuid(),
                v_ot_id,
                (item->>'orden')::INTEGER,
                item->>'descripcion',
                COALESCE((item->>'obligatorio')::BOOLEAN, true),
                COALESCE((item->>'requiere_foto')::BOOLEAN, false)
            FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    ELSE
        -- == FALLBACK: COPIAR CHECKLIST DESDE TEMPLATE GENÉRICO ==
        SELECT items INTO v_pauta_items
        FROM checklist_templates
        WHERE tipo_ot = p_tipo AND activo = true
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT
                gen_random_uuid(),
                v_ot_id,
                (item->>'orden')::INTEGER,
                item->>'descripcion',
                COALESCE((item->>'obligatorio')::BOOLEAN, true),
                COALESCE((item->>'requiere_foto')::BOOLEAN, false)
            FROM jsonb_array_elements(v_pauta_items) AS item;
        END IF;
    END IF;

    -- == HISTORIAL ==
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    -- == RETORNAR ==
    RETURN jsonb_build_object(
        'id', v_ot_id,
        'folio', v_folio,
        'estado', v_estado,
        'qr_code', v_qr_code,
        'activo_codigo', v_activo.codigo
    );
END;
$$;
