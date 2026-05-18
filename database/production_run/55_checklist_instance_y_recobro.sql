-- ============================================================================
-- 55_checklist_instance_y_recobro.sql
-- ----------------------------------------------------------------------------
-- Flujo recobro entrega vs recepcion (depende de MIG54 templates V02).
--
-- Crea:
--   - checklist_v2_instance       : cabecera de checklist llenado (entrega o recepcion)
--   - checklist_v2_instance_item  : respuesta por cada item del template
--   - Trigger: estado_comercial -> 'arrendado' EXIGE checklist entrega cerrado con firma cliente
--   - Trigger: estado_comercial -> 'en_recepcion' auto-crea instance + informe_recepcion
--   - fn_comparar_checklists      : devuelve diff items que cambiaron OK->NO_OK + costo
--   - rpc_cerrar_checklist_v2     : valida obligatorios + firmas y cierra el instance
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='checklist_template_v2') THEN
        RAISE EXCEPTION 'STOP - MIG54 no aplicada (falta checklist_template_v2).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='informes_recepcion') THEN
        RAISE EXCEPTION 'STOP - falta informes_recepcion (MIG49).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - falta fn_user_rol().';
    END IF;
END $$;


-- ============================================================================
-- 1. Enum: resultado de cada item llenado
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='resultado_item_enum') THEN
        CREATE TYPE resultado_item_enum AS ENUM (
            'ok',           -- cumple
            'no_ok',        -- hallazgo (genera diff vs entrega -> recobro)
            'na',           -- no aplica
            'pendiente'     -- aun no chequeado
        );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='estado_instance_enum') THEN
        CREATE TYPE estado_instance_enum AS ENUM (
            'en_progreso',  -- operador llenando
            'cerrado',      -- firmado por ambas partes
            'anulado'
        );
    END IF;
END $$;


-- ============================================================================
-- 2. checklist_v2_instance — cabecera (entrega o recepcion)
-- ============================================================================
CREATE TABLE IF NOT EXISTS checklist_v2_instance (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id     UUID         NOT NULL REFERENCES checklist_template_v2(id),
    momento_uso     momento_checklist_enum NOT NULL,    -- denormalizado para query rapida
    activo_id       UUID         NOT NULL REFERENCES activos(id),
    contrato_id     UUID         REFERENCES contratos(id),
    informe_recepcion_id UUID    REFERENCES informes_recepcion(id),  -- solo si recepcion
    -- Contexto temporal
    fecha_inicio    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    fecha_cierre    TIMESTAMPTZ,
    estado          estado_instance_enum NOT NULL DEFAULT 'en_progreso',
    -- Lectura al momento (auditoria)
    horometro       NUMERIC(12,2),
    kilometraje     NUMERIC(12,2),
    -- Personas
    operador_id     UUID         REFERENCES auth.users(id),
    operador_rut    VARCHAR(20),
    operador_nombre VARCHAR(200),
    cliente_rut     VARCHAR(20),
    cliente_nombre  VARCHAR(200),
    -- Firmas (URLs storage bucket; obligatoriedad la valida rpc_cerrar)
    firma_operador_url TEXT,
    firma_cliente_url  TEXT,
    -- Comparacion (solo recepcion: referencia al checklist de entrega de mismo arriendo)
    instance_entrega_id UUID REFERENCES checklist_v2_instance(id),
    observaciones   TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_inst_horometro CHECK (horometro IS NULL OR horometro >= 0),
    CONSTRAINT chk_inst_km        CHECK (kilometraje IS NULL OR kilometraje >= 0),
    CONSTRAINT chk_inst_cierre    CHECK (estado <> 'cerrado' OR fecha_cierre IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_cl_inst_activo_momento
    ON checklist_v2_instance (activo_id, momento_uso, estado, fecha_cierre DESC);
CREATE INDEX IF NOT EXISTS idx_cl_inst_contrato
    ON checklist_v2_instance (contrato_id) WHERE contrato_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cl_inst_informe
    ON checklist_v2_instance (informe_recepcion_id) WHERE informe_recepcion_id IS NOT NULL;


-- ============================================================================
-- 3. checklist_v2_instance_item — respuesta por cada item del template
-- ============================================================================
CREATE TABLE IF NOT EXISTS checklist_v2_instance_item (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id       UUID         NOT NULL REFERENCES checklist_v2_instance(id) ON DELETE CASCADE,
    template_item_id  UUID         NOT NULL REFERENCES checklist_template_v2_item(id),
    -- Respuesta
    resultado         resultado_item_enum NOT NULL DEFAULT 'pendiente',
    valor_numerico    NUMERIC,                          -- horometro, mm, kPa, °C, etc
    observacion       TEXT,
    foto_url          TEXT,
    -- Override de cobrable (si default no aplica al caso)
    cobrable_override default_cobrable_enum,
    costo_estimado    NUMERIC,                          -- costo real estimado por tecnico
    -- Trazabilidad
    respondido_at     TIMESTAMPTZ,
    respondido_por    UUID         REFERENCES auth.users(id),
    CONSTRAINT uq_cl_inst_item UNIQUE (instance_id, template_item_id),
    CONSTRAINT chk_cl_inst_num CHECK (valor_numerico IS NULL OR valor_numerico >= 0)
);

CREATE INDEX IF NOT EXISTS idx_cl_inst_item_instance
    ON checklist_v2_instance_item (instance_id, resultado);


-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_cl_inst_updated_at ON checklist_v2_instance;
CREATE TRIGGER trg_cl_inst_updated_at
    BEFORE UPDATE ON checklist_v2_instance
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 4. RLS — operador llena, supervisor cierra, admin auditea
-- ============================================================================
ALTER TABLE checklist_v2_instance       ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_v2_instance_item  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_cl_inst_select ON checklist_v2_instance;
CREATE POLICY pol_cl_inst_select ON checklist_v2_instance
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_cl_inst_write ON checklist_v2_instance;
CREATE POLICY pol_cl_inst_write ON checklist_v2_instance
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','tecnico','supervisor_calama'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','tecnico','supervisor_calama'));

DROP POLICY IF EXISTS pol_cl_inst_item_select ON checklist_v2_instance_item;
CREATE POLICY pol_cl_inst_item_select ON checklist_v2_instance_item
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_cl_inst_item_write ON checklist_v2_instance_item;
CREATE POLICY pol_cl_inst_item_write ON checklist_v2_instance_item
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','tecnico','supervisor_calama'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','tecnico','supervisor_calama'));


-- ============================================================================
-- 5. fn_inicializar_checklist_v2 — crea instance + filas para CADA item del template
--    aplicable al tipo_equipamiento del activo
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_inicializar_checklist_v2(
    p_template_id   UUID,
    p_activo_id     UUID,
    p_contrato_id   UUID DEFAULT NULL,
    p_operador_id   UUID DEFAULT NULL,
    p_horometro     NUMERIC DEFAULT NULL,
    p_kilometraje   NUMERIC DEFAULT NULL,
    p_informe_id    UUID DEFAULT NULL,
    p_entrega_ref   UUID DEFAULT NULL  -- referencia al instance entrega si es recepcion
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_instance_id UUID;
    v_momento     momento_checklist_enum;
    v_tipo_eq     tipo_equipamiento_enum;
BEGIN
    -- Cargar momento del template y tipo equipamiento del activo
    SELECT momento_uso INTO v_momento
      FROM checklist_template_v2 WHERE id = p_template_id;

    SELECT tipo_equipamiento INTO v_tipo_eq
      FROM activos WHERE id = p_activo_id;

    IF v_momento IS NULL THEN
        RAISE EXCEPTION 'Template % no encontrado', p_template_id;
    END IF;
    IF v_tipo_eq IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    -- 1. Crear cabecera
    INSERT INTO checklist_v2_instance (
        template_id, momento_uso, activo_id, contrato_id,
        informe_recepcion_id, instance_entrega_id,
        horometro, kilometraje, operador_id, estado
    ) VALUES (
        p_template_id, v_momento, p_activo_id, p_contrato_id,
        p_informe_id, p_entrega_ref,
        p_horometro, p_kilometraje, p_operador_id, 'en_progreso'
    )
    RETURNING id INTO v_instance_id;

    -- 2. Pre-popular filas para cada item del template que aplica al tipo_equipamiento
    INSERT INTO checklist_v2_instance_item (instance_id, template_item_id, resultado)
    SELECT v_instance_id, ti.id, 'pendiente'
      FROM checklist_template_v2_item ti
     WHERE ti.template_id = p_template_id
       AND v_tipo_eq = ANY(ti.tipos_equipamiento);

    RETURN v_instance_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_inicializar_checklist_v2(UUID,UUID,UUID,UUID,NUMERIC,NUMERIC,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_inicializar_checklist_v2(UUID,UUID,UUID,UUID,NUMERIC,NUMERIC,UUID,UUID) TO authenticated;


-- ============================================================================
-- 6. rpc_cerrar_checklist_v2 — valida obligatorios + firmas y cierra
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_cerrar_checklist_v2(
    p_instance_id UUID,
    p_firma_operador_url TEXT,
    p_firma_cliente_url  TEXT,
    p_operador_rut       VARCHAR DEFAULT NULL,
    p_operador_nombre    VARCHAR DEFAULT NULL,
    p_cliente_rut        VARCHAR DEFAULT NULL,
    p_cliente_nombre     VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inst      RECORD;
    v_pendientes INTEGER;
    v_faltan_obligatorios INTEGER;
BEGIN
    SELECT * INTO v_inst FROM checklist_v2_instance WHERE id = p_instance_id;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Checklist % no encontrado', p_instance_id;
    END IF;

    IF v_inst.estado = 'cerrado' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Checklist ya esta cerrado');
    END IF;

    -- Validar firma operador (siempre obligatoria)
    IF p_firma_operador_url IS NULL OR length(trim(p_firma_operador_url)) = 0 THEN
        RAISE EXCEPTION 'Firma del operador es obligatoria';
    END IF;

    -- Validar firma cliente (obligatoria para entrega y recepcion)
    IF v_inst.momento_uso IN ('entrega_arriendo','recepcion_devolucion')
       AND (p_firma_cliente_url IS NULL OR length(trim(p_firma_cliente_url)) = 0) THEN
        RAISE EXCEPTION 'Firma del cliente es obligatoria para recobro (% )', v_inst.momento_uso;
    END IF;

    -- Validar que no haya items obligatorios pendientes
    SELECT COUNT(*) INTO v_faltan_obligatorios
      FROM checklist_v2_instance_item ii
      JOIN checklist_template_v2_item  ti ON ti.id = ii.template_item_id
     WHERE ii.instance_id = p_instance_id
       AND ti.obligatorio = true
       AND ii.resultado = 'pendiente';

    IF v_faltan_obligatorios > 0 THEN
        RAISE EXCEPTION 'Faltan % items obligatorios por responder', v_faltan_obligatorios;
    END IF;

    -- Validar fotos obligatorias
    SELECT COUNT(*) INTO v_pendientes
      FROM checklist_v2_instance_item ii
      JOIN checklist_template_v2_item  ti ON ti.id = ii.template_item_id
     WHERE ii.instance_id = p_instance_id
       AND ti.requiere_foto = true
       AND ti.obligatorio   = true
       AND (ii.foto_url IS NULL OR length(trim(ii.foto_url)) = 0);

    IF v_pendientes > 0 THEN
        RAISE EXCEPTION 'Faltan % fotos obligatorias', v_pendientes;
    END IF;

    -- Cerrar
    UPDATE checklist_v2_instance
       SET estado             = 'cerrado',
           fecha_cierre       = NOW(),
           firma_operador_url = p_firma_operador_url,
           firma_cliente_url  = p_firma_cliente_url,
           operador_rut       = COALESCE(p_operador_rut, operador_rut),
           operador_nombre    = COALESCE(p_operador_nombre, operador_nombre),
           cliente_rut        = COALESCE(p_cliente_rut, cliente_rut),
           cliente_nombre     = COALESCE(p_cliente_nombre, cliente_nombre)
     WHERE id = p_instance_id;

    RETURN jsonb_build_object('ok', true, 'instance_id', p_instance_id, 'cerrado_at', NOW());
END;
$$;

REVOKE ALL ON FUNCTION rpc_cerrar_checklist_v2(UUID,TEXT,TEXT,VARCHAR,VARCHAR,VARCHAR,VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cerrar_checklist_v2(UUID,TEXT,TEXT,VARCHAR,VARCHAR,VARCHAR,VARCHAR) TO authenticated;


-- ============================================================================
-- 7. TRIGGER: pasar estado_comercial -> 'arrendado' exige checklist_entrega
--    cerrado con firma cliente
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_validar_arrendado_requiere_checklist_entrega()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_existe BOOLEAN;
BEGIN
    -- Solo se aplica si esta cambiando A 'arrendado'
    IF NEW.estado_comercial = 'arrendado'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial <> 'arrendado') THEN

        SELECT EXISTS(
            SELECT 1
              FROM checklist_v2_instance ci
             WHERE ci.activo_id = NEW.id
               AND ci.momento_uso = 'entrega_arriendo'
               AND ci.estado = 'cerrado'
               AND ci.firma_cliente_url  IS NOT NULL
               AND ci.firma_operador_url IS NOT NULL
               -- vigencia: cerrado en las ultimas 48h
               AND ci.fecha_cierre > NOW() - INTERVAL '48 hours'
        ) INTO v_existe;

        IF NOT v_existe THEN
            RAISE EXCEPTION
              'No se puede marcar el activo como ARRENDADO sin un Check-List de ENTREGA V02 cerrado, '
              'firmado por operador Y cliente, en las ultimas 48 horas. '
              'Crea el checklist en /dashboard/flota/checklist-salida/% primero.', NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_arrendado_checklist ON activos;
CREATE TRIGGER trg_validar_arrendado_checklist
    BEFORE UPDATE OF estado_comercial ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_validar_arrendado_requiere_checklist_entrega();


-- ============================================================================
-- 8. TRIGGER: pasar a 'en_recepcion' auto-crea instance + informe_recepcion
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_auto_iniciar_recepcion_devolucion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_template_id   UUID;
    v_entrega_ref   UUID;
    v_informe_id    UUID;
    v_contrato_id   UUID;
    v_estado_actual_horas NUMERIC;
    v_estado_actual_km    NUMERIC;
BEGIN
    -- Solo si entra a en_recepcion desde otro estado
    IF NEW.estado_comercial = 'en_recepcion'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial <> 'en_recepcion') THEN

        -- Template activo para recepcion
        SELECT id INTO v_template_id
          FROM checklist_template_v2
         WHERE momento_uso = 'recepcion_devolucion'
           AND activo = true
         LIMIT 1;

        IF v_template_id IS NULL THEN
            RAISE WARNING 'No hay template activo para recepcion_devolucion. Skip auto-init.';
            RETURN NEW;
        END IF;

        -- Ultimo checklist de entrega cerrado de este activo (para comparacion)
        SELECT id, contrato_id INTO v_entrega_ref, v_contrato_id
          FROM checklist_v2_instance
         WHERE activo_id = NEW.id
           AND momento_uso = 'entrega_arriendo'
           AND estado = 'cerrado'
         ORDER BY fecha_cierre DESC
         LIMIT 1;

        -- Si ya existe un instance recepcion abierto para este activo, no crear otro
        IF EXISTS (
            SELECT 1 FROM checklist_v2_instance
             WHERE activo_id = NEW.id
               AND momento_uso = 'recepcion_devolucion'
               AND estado = 'en_progreso'
        ) THEN
            RETURN NEW;
        END IF;

        -- Crear informe_recepcion vacio (si tabla existe)
        IF to_regclass('public.informes_recepcion') IS NOT NULL THEN
            INSERT INTO informes_recepcion (activo_id, contrato_id, estado)
            VALUES (NEW.id, v_contrato_id, 'en_inspeccion')
            RETURNING id INTO v_informe_id;
        END IF;

        -- Tomar lectura actual desde gps_estado_actual si existe (MIG53)
        IF to_regclass('public.gps_estado_actual') IS NOT NULL THEN
            SELECT horometro_hrs, odometro_km
              INTO v_estado_actual_horas, v_estado_actual_km
              FROM gps_estado_actual WHERE activo_id = NEW.id;
        END IF;

        -- Crear instance recepcion (sin operador, lo asigna quien empieza el llenado)
        PERFORM fn_inicializar_checklist_v2(
            v_template_id, NEW.id, v_contrato_id, NULL,
            v_estado_actual_horas, v_estado_actual_km,
            v_informe_id, v_entrega_ref
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_iniciar_recepcion ON activos;
CREATE TRIGGER trg_auto_iniciar_recepcion
    AFTER UPDATE OF estado_comercial ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_auto_iniciar_recepcion_devolucion();


-- ============================================================================
-- 9. fn_comparar_checklists_entrega_recepcion
-- ----------------------------------------------------------------------------
-- Devuelve UNA fila por item donde haya cambio relevante para recobro:
--   - entrega = ok    y recepcion = no_ok  -> hallazgo nuevo (cobrable)
--   - entrega = no_ok y recepcion = no_ok  -> hallazgo pre-existente (no cobrable)
--   - entrega = ok    y recepcion = ok     -> sin cambio (omitido)
--   - diff numerico relevante (banda mm: bajo umbral, voltaje, etc.)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_comparar_checklists_entrega_recepcion(
    p_recepcion_id UUID
)
RETURNS TABLE (
    template_item_id  UUID,
    codigo_item       VARCHAR,
    bloque            bloque_checklist_enum,
    descripcion       TEXT,
    resultado_entrega resultado_item_enum,
    resultado_recepcion resultado_item_enum,
    valor_entrega     NUMERIC,
    valor_recepcion   NUMERIC,
    delta_valor       NUMERIC,
    foto_entrega_url  TEXT,
    foto_recepcion_url TEXT,
    default_cobrable  default_cobrable_enum,
    cobrable_final    default_cobrable_enum,
    costo_referencial NUMERIC,
    costo_estimado_real NUMERIC,
    es_hallazgo_nuevo BOOLEAN
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_entrega_id UUID;
BEGIN
    SELECT instance_entrega_id INTO v_entrega_id
      FROM checklist_v2_instance WHERE id = p_recepcion_id;

    IF v_entrega_id IS NULL THEN
        -- No hay entrega referenciada: devolver todo lo no_ok como hallazgo cobrable_default
        RETURN QUERY
        SELECT
            ti.id, ti.codigo, ti.bloque, ti.descripcion,
            NULL::resultado_item_enum,
            ii_r.resultado,
            NULL::NUMERIC,
            ii_r.valor_numerico,
            NULL::NUMERIC,
            NULL::TEXT,
            ii_r.foto_url,
            ti.default_cobrable,
            COALESCE(ii_r.cobrable_override, ti.default_cobrable),
            ti.costo_referencial_clp,
            ii_r.costo_estimado,
            true
          FROM checklist_v2_instance_item ii_r
          JOIN checklist_template_v2_item  ti   ON ti.id = ii_r.template_item_id
         WHERE ii_r.instance_id = p_recepcion_id
           AND ii_r.resultado = 'no_ok'
         ORDER BY ti.bloque, ti.orden;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        ti.id,
        ti.codigo,
        ti.bloque,
        ti.descripcion,
        ii_e.resultado,
        ii_r.resultado,
        ii_e.valor_numerico,
        ii_r.valor_numerico,
        (ii_r.valor_numerico - ii_e.valor_numerico),
        ii_e.foto_url,
        ii_r.foto_url,
        ti.default_cobrable,
        COALESCE(ii_r.cobrable_override, ti.default_cobrable),
        ti.costo_referencial_clp,
        ii_r.costo_estimado,
        -- Es hallazgo nuevo si recepcion=no_ok Y entrega estaba en ok/pendiente
        (ii_r.resultado = 'no_ok' AND COALESCE(ii_e.resultado, 'ok') = 'ok')
      FROM checklist_template_v2_item ti
      LEFT JOIN checklist_v2_instance_item ii_e
             ON ii_e.template_item_id = ti.id AND ii_e.instance_id = v_entrega_id
      LEFT JOIN checklist_v2_instance_item ii_r
             ON ii_r.template_item_id = ti.id AND ii_r.instance_id = p_recepcion_id
     WHERE ii_r.id IS NOT NULL
       AND (
           ii_r.resultado = 'no_ok'   -- hallazgo en recepcion
           OR (ti.rango_min IS NOT NULL
               AND ii_r.valor_numerico IS NOT NULL
               AND ii_r.valor_numerico < ti.rango_min)
           OR (ti.rango_max IS NOT NULL
               AND ii_r.valor_numerico IS NOT NULL
               AND ii_r.valor_numerico > ti.rango_max)
       )
     ORDER BY ti.bloque, ti.orden;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_comparar_checklists_entrega_recepcion(UUID) TO authenticated;


-- ============================================================================
-- 10. rpc_aplicar_diff_a_informe — vuelca el diff como hallazgos/costos al informe
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_aplicar_diff_a_informe(
    p_recepcion_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_informe_id    UUID;
    v_insertados    INTEGER := 0;
    v_diff RECORD;
    v_gravedad VARCHAR;
BEGIN
    SELECT informe_recepcion_id INTO v_informe_id
      FROM checklist_v2_instance WHERE id = p_recepcion_id;

    IF v_informe_id IS NULL THEN
        RAISE EXCEPTION 'Checklist recepcion % no tiene informe_recepcion asociado', p_recepcion_id;
    END IF;

    FOR v_diff IN
        SELECT * FROM fn_comparar_checklists_entrega_recepcion(p_recepcion_id)
         WHERE es_hallazgo_nuevo = true
    LOOP
        v_gravedad := CASE
            WHEN COALESCE(v_diff.costo_estimado_real, v_diff.costo_referencial, 0) >= 300000 THEN 'mayor'
            WHEN COALESCE(v_diff.costo_estimado_real, v_diff.costo_referencial, 0) >= 80000  THEN 'menor'
            ELSE 'menor'
        END;

        -- Hallazgo (estructura conforme MIG49)
        INSERT INTO informe_recepcion_hallazgos (
            informe_id, descripcion, gravedad, atribuible_cliente, observacion
        ) VALUES (
            v_informe_id,
            format('[%s] %s', v_diff.codigo_item, v_diff.descripcion),
            v_gravedad,
            (v_diff.cobrable_final = 'cliente'),
            CASE WHEN v_diff.foto_recepcion_url IS NOT NULL
                 THEN format('Foto recepcion: %s', v_diff.foto_recepcion_url)
                 ELSE NULL
            END
        );

        -- Costo asociado (si tenemos referencia)
        IF COALESCE(v_diff.costo_estimado_real, v_diff.costo_referencial) IS NOT NULL THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, descripcion, cantidad, precio_unitario, cobrable_cliente
            ) VALUES (
                v_informe_id,
                'otro',
                format('Recobro %s — %s', v_diff.codigo_item, v_diff.descripcion),
                1,
                COALESCE(v_diff.costo_estimado_real, v_diff.costo_referencial),
                (v_diff.cobrable_final = 'cliente')
            );
        END IF;

        v_insertados := v_insertados + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'ok',           true,
        'informe_id',   v_informe_id,
        'hallazgos_insertados', v_insertados
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_aplicar_diff_a_informe(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_aplicar_diff_a_informe(UUID) TO authenticated;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_instance',         to_regclass('public.checklist_v2_instance')      IS NOT NULL,
    'tabla_instance_item',    to_regclass('public.checklist_v2_instance_item') IS NOT NULL,
    'fn_inicializar',         EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_inicializar_checklist_v2'),
    'fn_cerrar',              EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_cerrar_checklist_v2'),
    'trigger_arrendado',      EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_validar_arrendado_checklist'),
    'trigger_recepcion_auto', EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_auto_iniciar_recepcion'),
    'fn_comparar',            EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_comparar_checklists_entrega_recepcion'),
    'rpc_aplicar_diff',       EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_aplicar_diff_a_informe')
) AS resultado;

NOTIFY pgrst, 'reload schema';
