-- ============================================================================
-- 18_operacion_calama_import_excel.sql
-- ----------------------------------------------------------------------------
-- Modulo Operacion Calama — FASE 2B: importacion definitiva del Excel base.
--
-- ALCANCE:
--   - 4 tablas NUEVAS:
--       calama_zonas_proyecto, calama_materiales_planificados,
--       calama_contactos_mandante, calama_importaciones_log.
--   - 3 helpers: fn_calama_uuid_det, fn_calama_puede_importar,
--                fn_calama_sub_linea_heuristica.
--   - 1 RPC SECURITY DEFINER:
--       rpc_calama_importar_excel(p_payload jsonb)
--         Crea/actualiza calama_planificaciones, calama_zonas_proyecto,
--         calama_tareas_maestro, calama_ordenes_trabajo, calama_ot_subtareas,
--         calama_materiales_planificados, calama_contactos_mandante,
--         calama_observaciones (cuando hay match con OT) y registra
--         calama_importaciones_log.
--
-- IDEMPOTENCIA:
--   - cliente_uuid determinista vs ON CONFLICT por (codigo / folio / cliente_uuid).
--   - Re-importar el mismo Excel no duplica filas.
--   - OTs ya en ejecucion / finalizadas NO se sobreescriben (skip + warning).
--
-- AISLACION (REGLAS USUARIO):
--   - NO toca MIG17, MIG55-57, scripts 14*, ni rol_usuario_enum.
--   - Solo agrega tablas/funciones nuevas y crea policies para esas tablas.
--   - RLS estricta. anon SIN ACCESO.
--
-- ROLES AUTORIZADOS A IMPORTAR (fn_calama_puede_importar):
--   administrador, gerencia, subgerente_operaciones, supervisor, planificador
--   + calama_roles_proyecto.rol_calama = 'jefe_sucursal'.
--
-- VERIFICACION: 1 fila final OK_OPERACION_CALAMA_IMPORT / WARNING / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_planificaciones') THEN
        RAISE EXCEPTION 'STOP — MIG17 no ejecutada (calama_planificaciones no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP — MIG17 no ejecutada (calama_ordenes_trabajo no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_puede_planificar()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_calama_puede_planificar() no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. HELPERS ───────────────────────────────────────────────────────────────
-- ============================================================================

-- 1.1 UUID determinista a partir de un string semilla (md5-based, formato v5-like).
CREATE OR REPLACE FUNCTION fn_calama_uuid_det(p_seed TEXT)
RETURNS UUID LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    h TEXT := md5(COALESCE(p_seed, ''));
BEGIN
    RETURN (
        substring(h FROM 1 FOR 8) || '-' ||
        substring(h FROM 9 FOR 4) || '-' ||
        '5' || substring(h FROM 14 FOR 3) || '-' ||
        '8' || substring(h FROM 18 FOR 3) || '-' ||
        substring(h FROM 21 FOR 12)
    )::uuid;
END;
$$;

-- 1.2 Quien puede importar (literal segun spec FASE 2B).
CREATE OR REPLACE FUNCTION fn_calama_puede_importar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT
        fn_user_rol() IN (
            'administrador','gerencia','subgerente_operaciones',
            'supervisor','planificador'
        )
        OR fn_calama_rol_proyecto() = 'jefe_sucursal';
$$;

-- 1.3 Heuristica de sub_linea en base a nombre de tarea (matchea CHECK MIG17).
CREATE OR REPLACE FUNCTION fn_calama_sub_linea_heuristica(p_linea TEXT, p_nombre TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_linea
        WHEN 'mejoras_civiles' THEN
            CASE
                WHEN COALESCE(p_nombre,'') ILIKE '%pintura%'      THEN 'pintura'
                WHEN COALESCE(p_nombre,'') ILIKE '%refacc%'       THEN 'refaccion'
                WHEN COALESCE(p_nombre,'') ILIKE '%reparac%'      THEN 'reparaciones'
                ELSE 'mejoras'
            END
        WHEN 'combustibles' THEN
            CASE
                WHEN COALESCE(p_nombre,'') ILIKE '%movil%'        THEN 'plataforma_movil'
                WHEN COALESCE(p_nombre,'') ILIKE '%calibrac%'     THEN 'calibracion'
                ELSE 'plataforma_fija'
            END
        WHEN 'lubricantes' THEN
            CASE
                WHEN COALESCE(p_nombre,'') ILIKE '%calibrac%'     THEN 'calibracion_equipos'
                WHEN COALESCE(p_nombre,'') ILIKE '%movil%'        THEN 'plataforma_movil'
                ELSE 'plataforma_fija'
            END
        ELSE NULL
    END;
$$;

GRANT EXECUTE ON FUNCTION fn_calama_uuid_det(TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_puede_importar()          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_sub_linea_heuristica(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- ── 2. TABLAS NUEVAS ─────────────────────────────────────────────────────────
-- ============================================================================

-- 2.1 Zonas del proyecto (jerarquia N.0.0 del Excel)
CREATE TABLE IF NOT EXISTS calama_zonas_proyecto (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    planificacion_id    UUID NOT NULL REFERENCES calama_planificaciones(id) ON DELETE CASCADE,
    codigo_zona         VARCHAR(40) NOT NULL,
    nombre              VARCHAR(250) NOT NULL,
    orden               INT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_calama_zona_plan UNIQUE (planificacion_id, codigo_zona)
);
CREATE INDEX IF NOT EXISTS idx_calama_zona_plan ON calama_zonas_proyecto (planificacion_id);

-- 2.2 Materiales planificados (importados desde "Itemizado materiale")
CREATE TABLE IF NOT EXISTS calama_materiales_planificados (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    planificacion_id        UUID NOT NULL REFERENCES calama_planificaciones(id) ON DELETE CASCADE,
    tarea_maestro_id        UUID REFERENCES calama_tareas_maestro(id),
    zona_proyecto_id        UUID REFERENCES calama_zonas_proyecto(id),
    actividad_relacionada   VARCHAR(250),
    descripcion             TEXT NOT NULL,
    unidad                  VARCHAR(20),
    cantidad                NUMERIC(14,2),
    precio_clp              NUMERIC(15,2),
    valor_uf                NUMERIC(10,2),
    porcentaje              NUMERIC(5,2),
    bloque                  VARCHAR(60),
    cliente_uuid            UUID UNIQUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_mat_plan ON calama_materiales_planificados (planificacion_id);
CREATE INDEX IF NOT EXISTS idx_calama_mat_tarea ON calama_materiales_planificados (tarea_maestro_id) WHERE tarea_maestro_id IS NOT NULL;

-- 2.3 Contactos mandante (importados desde Hoja1)
CREATE TABLE IF NOT EXISTS calama_contactos_mandante (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_calama_id     UUID NOT NULL REFERENCES calama_faenas(id),
    planificacion_id    UUID REFERENCES calama_planificaciones(id) ON DELETE CASCADE,
    codigo_actividad    VARCHAR(40),
    descripcion         VARCHAR(250) NOT NULL,
    telefono            VARCHAR(40),
    rol                 VARCHAR(120),
    cliente_uuid        UUID UNIQUE,
    activo              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_contacto_faena ON calama_contactos_mandante (faena_calama_id);
CREATE INDEX IF NOT EXISTS idx_calama_contacto_plan  ON calama_contactos_mandante (planificacion_id) WHERE planificacion_id IS NOT NULL;

-- 2.4 Log de importaciones
CREATE TABLE IF NOT EXISTS calama_importaciones_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archivo             VARCHAR(250),
    planificacion_id    UUID REFERENCES calama_planificaciones(id),
    faena_calama_id     UUID REFERENCES calama_faenas(id),
    linea_negocio       VARCHAR(40),
    resultado           VARCHAR(40) NOT NULL,
    detalle             TEXT,
    payload_resumen     JSONB,
    importado_por       UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_imp_log_fecha ON calama_importaciones_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calama_imp_log_plan  ON calama_importaciones_log (planificacion_id);


-- ============================================================================
-- ── 3. RLS ───────────────────────────────────────────────────────────────────
-- ============================================================================

ALTER TABLE calama_zonas_proyecto          ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_materiales_planificados ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_contactos_mandante      ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_importaciones_log       ENABLE ROW LEVEL SECURITY;

-- Zonas
DROP POLICY IF EXISTS pol_calama_zona_select ON calama_zonas_proyecto;
CREATE POLICY pol_calama_zona_select ON calama_zonas_proyecto
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_zona_modif ON calama_zonas_proyecto;
CREATE POLICY pol_calama_zona_modif ON calama_zonas_proyecto
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Materiales
DROP POLICY IF EXISTS pol_calama_mat_select ON calama_materiales_planificados;
CREATE POLICY pol_calama_mat_select ON calama_materiales_planificados
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_mat_modif ON calama_materiales_planificados;
CREATE POLICY pol_calama_mat_modif ON calama_materiales_planificados
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Contactos
DROP POLICY IF EXISTS pol_calama_contacto_select ON calama_contactos_mandante;
CREATE POLICY pol_calama_contacto_select ON calama_contactos_mandante
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_contacto_modif ON calama_contactos_mandante;
CREATE POLICY pol_calama_contacto_modif ON calama_contactos_mandante
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Log: solo admin global puede ver/modificar (auditoria)
DROP POLICY IF EXISTS pol_calama_imp_log_select ON calama_importaciones_log;
CREATE POLICY pol_calama_imp_log_select ON calama_importaciones_log
    FOR SELECT TO authenticated
    USING (fn_calama_es_admin_global() OR fn_calama_puede_importar());
DROP POLICY IF EXISTS pol_calama_imp_log_insert ON calama_importaciones_log;
CREATE POLICY pol_calama_imp_log_insert ON calama_importaciones_log
    FOR INSERT TO authenticated
    WITH CHECK (fn_calama_puede_importar());


-- ============================================================================
-- ── 4. RPC rpc_calama_importar_excel ─────────────────────────────────────────
-- ============================================================================
--
-- Payload esperado:
-- {
--   archivo: string,
--   faena_codigo: string,                -- 'CENTINELA' | 'LOMAS_BAYAS' | 'SPENCE'
--   linea_negocio: 'mejoras_civiles' | 'combustibles' | 'lubricantes',
--   plan_codigo: string,                 -- ej 'VA_25_042_CENTINELA'
--   plan_nombre: string,
--   plan_fecha_inicio: 'YYYY-MM-DD',
--   plan_fecha_termino: 'YYYY-MM-DD',
--   permitir_advertencias: boolean,
--   zonas: [{ codigo, nombre }],
--   tareas: [{
--      codigo, nombre, zona_codigo,
--      duracion_plan_dias, duracion_real_dias,
--      fecha_inicio_plan, fecha_fin_plan,
--      fecha_inicio_real, fecha_fin_real,
--      ot_referencia, verif
--   }],
--   subtareas: [{ codigo, descripcion, tarea_codigo, estado, fecha_real }],
--   materiales: [{
--      actividad_relacionada, descripcion, unidad, cantidad,
--      precio_clp, valor_uf, porcentaje, bloque
--   }],
--   contactos: [{ codigo_actividad, descripcion, telefono, rol }],
--   observaciones: [{ codigo_relacionado, texto }],
--   tiene_errores_mapeo: boolean
-- }

CREATE OR REPLACE FUNCTION rpc_calama_importar_excel(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_resultado TEXT := 'OK_IMPORTACION_CALAMA';
    v_errores TEXT[] := ARRAY[]::TEXT[];
    v_advertencias TEXT[] := ARRAY[]::TEXT[];

    v_faena_codigo TEXT := p_payload->>'faena_codigo';
    v_linea TEXT := p_payload->>'linea_negocio';
    v_plan_codigo TEXT := p_payload->>'plan_codigo';
    v_plan_nombre TEXT := COALESCE(p_payload->>'plan_nombre', v_plan_codigo);
    v_plan_inicio DATE := COALESCE((p_payload->>'plan_fecha_inicio')::DATE, CURRENT_DATE);
    v_plan_termino DATE := COALESCE((p_payload->>'plan_fecha_termino')::DATE, CURRENT_DATE + INTERVAL '180 days');
    v_archivo TEXT := p_payload->>'archivo';
    v_permitir_warn BOOLEAN := COALESCE((p_payload->>'permitir_advertencias')::BOOLEAN, false);
    v_tiene_err_map BOOLEAN := COALESCE((p_payload->>'tiene_errores_mapeo')::BOOLEAN, false);

    v_faena_id UUID;
    v_plan_id UUID;
    v_zona_id UUID;
    v_tarea_id UUID;
    v_ot_id UUID;
    v_existing_estado TEXT;

    v_zonas_ins INT := 0;
    v_zonas_upd INT := 0;
    v_tareas_ins INT := 0;
    v_tareas_upd INT := 0;
    v_ots_ins INT := 0;
    v_ots_upd INT := 0;
    v_ots_skip INT := 0;
    v_subt_ins INT := 0;
    v_subt_upd INT := 0;
    v_mat_ins INT := 0;
    v_cont_ins INT := 0;
    v_cont_upd INT := 0;
    v_obs_ins INT := 0;
    v_obs_skip INT := 0;
    v_fechas_ins INT := 0;

    v_tarea_codigo TEXT;
    v_subt_codigo TEXT;
    v_full_tarea_codigo TEXT;
    v_full_folio_ot TEXT;
    v_zona_codigo TEXT;
    v_orden INT;
    v_sub_linea TEXT;
    v_uuid_det UUID;
    v_is_insert BOOLEAN;
    v_payload_zonas JSONB := COALESCE(p_payload->'zonas', '[]'::jsonb);
    v_payload_tareas JSONB := COALESCE(p_payload->'tareas', '[]'::jsonb);
    v_payload_subt JSONB := COALESCE(p_payload->'subtareas', '[]'::jsonb);
    v_payload_mat JSONB := COALESCE(p_payload->'materiales', '[]'::jsonb);
    v_payload_cont JSONB := COALESCE(p_payload->'contactos', '[]'::jsonb);
    v_payload_obs JSONB := COALESCE(p_payload->'observaciones', '[]'::jsonb);
    v_item JSONB;
BEGIN
    -- ── Autenticacion + autorizacion ─────────────────────────────────────────
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;
    IF NOT fn_calama_puede_importar() THEN
        RAISE EXCEPTION 'Rol no autorizado para importar Excel Calama';
    END IF;

    -- ── Validaciones de payload ──────────────────────────────────────────────
    IF v_faena_codigo IS NULL OR v_linea IS NULL OR v_plan_codigo IS NULL THEN
        RAISE EXCEPTION 'payload invalido: faena_codigo, linea_negocio y plan_codigo son obligatorios';
    END IF;
    IF v_linea NOT IN ('combustibles','lubricantes','mejoras_civiles') THEN
        RAISE EXCEPTION 'linea_negocio invalida: %', v_linea;
    END IF;
    IF v_tiene_err_map THEN
        RAISE EXCEPTION 'No se permite importar con errores_de_mapeo. Corregir el Excel y reintentar.';
    END IF;

    -- ── Resolver faena ───────────────────────────────────────────────────────
    SELECT id INTO v_faena_id FROM calama_faenas
     WHERE codigo = v_faena_codigo AND activo = true;
    IF v_faena_id IS NULL THEN
        RAISE EXCEPTION 'faena_codigo % no encontrada o inactiva', v_faena_codigo;
    END IF;

    -- ── Validar linea_negocio existente ──────────────────────────────────────
    IF NOT EXISTS (SELECT 1 FROM calama_lineas_negocio WHERE codigo = v_linea AND activo = true) THEN
        RAISE EXCEPTION 'linea_negocio % no esta en calama_lineas_negocio', v_linea;
    END IF;

    -- ── Upsert planificacion ─────────────────────────────────────────────────
    INSERT INTO calama_planificaciones (
        codigo, nombre, faena_calama_id, linea_negocio,
        fecha_inicio_plan, fecha_termino_plan,
        estado, fuente_excel, created_by
    ) VALUES (
        v_plan_codigo, v_plan_nombre, v_faena_id, v_linea,
        v_plan_inicio, v_plan_termino,
        'planificada', v_archivo, v_uid
    )
    ON CONFLICT (codigo) DO UPDATE SET
        nombre = EXCLUDED.nombre,
        faena_calama_id = EXCLUDED.faena_calama_id,
        linea_negocio = EXCLUDED.linea_negocio,
        fecha_inicio_plan = EXCLUDED.fecha_inicio_plan,
        fecha_termino_plan = EXCLUDED.fecha_termino_plan,
        fuente_excel = EXCLUDED.fuente_excel,
        updated_at = NOW()
    RETURNING id INTO v_plan_id;

    -- ── Zonas ────────────────────────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_zonas) LOOP
        v_zona_codigo := v_item->>'codigo';
        IF v_zona_codigo IS NULL OR v_zona_codigo = '' THEN CONTINUE; END IF;
        v_orden := COALESCE(NULLIF(split_part(v_zona_codigo, '.', 1), '')::INT, NULL);

        INSERT INTO calama_zonas_proyecto (planificacion_id, codigo_zona, nombre, orden)
        VALUES (v_plan_id, v_zona_codigo, COALESCE(v_item->>'nombre', v_zona_codigo), v_orden)
        ON CONFLICT (planificacion_id, codigo_zona) DO UPDATE SET
            nombre = EXCLUDED.nombre,
            orden = EXCLUDED.orden,
            updated_at = NOW()
        RETURNING id, (xmax = 0) INTO v_zona_id, v_is_insert;

        IF v_is_insert THEN v_zonas_ins := v_zonas_ins + 1;
        ELSE                v_zonas_upd := v_zonas_upd + 1;
        END IF;
    END LOOP;

    -- ── Tareas (calama_tareas_maestro + calama_ordenes_trabajo 1:1) ─────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_tareas) LOOP
        v_tarea_codigo := v_item->>'codigo';
        IF v_tarea_codigo IS NULL OR v_tarea_codigo = '' THEN CONTINUE; END IF;

        v_full_tarea_codigo := v_plan_codigo || '_' || v_tarea_codigo;
        v_sub_linea := fn_calama_sub_linea_heuristica(v_linea, v_item->>'nombre');

        -- 1) Catalogo: calama_tareas_maestro (codigo UNIQUE global)
        INSERT INTO calama_tareas_maestro (
            codigo, nombre, linea_negocio, sub_linea,
            descripcion, horas_estimadas, activa
        ) VALUES (
            v_full_tarea_codigo,
            COALESCE(v_item->>'nombre', v_tarea_codigo),
            v_linea,
            v_sub_linea,
            v_item->>'nombre',
            NULLIF(v_item->>'duracion_plan_dias','')::NUMERIC * 8,
            true
        )
        ON CONFLICT (codigo) DO UPDATE SET
            nombre = EXCLUDED.nombre,
            linea_negocio = EXCLUDED.linea_negocio,
            sub_linea = EXCLUDED.sub_linea,
            descripcion = EXCLUDED.descripcion,
            horas_estimadas = EXCLUDED.horas_estimadas,
            updated_at = NOW()
        RETURNING id, (xmax = 0) INTO v_tarea_id, v_is_insert;

        IF v_is_insert THEN v_tareas_ins := v_tareas_ins + 1;
        ELSE                v_tareas_upd := v_tareas_upd + 1;
        END IF;

        -- 2) OT ejecutable: calama_ordenes_trabajo (folio UNIQUE)
        v_full_folio_ot := 'OT_' || v_plan_codigo || '_' || v_tarea_codigo;
        v_zona_codigo := v_item->>'zona_codigo';

        SELECT estado INTO v_existing_estado
          FROM calama_ordenes_trabajo WHERE folio = v_full_folio_ot;

        IF v_existing_estado IS NULL THEN
            INSERT INTO calama_ordenes_trabajo (
                folio, planificacion_id, tarea_maestro_id, faena_calama_id,
                titulo, descripcion,
                fecha_programada,
                horas_estimadas,
                estado, prioridad,
                cliente_uuid, created_by
            ) VALUES (
                v_full_folio_ot, v_plan_id, v_tarea_id, v_faena_id,
                COALESCE(v_item->>'nombre', v_tarea_codigo),
                v_item->>'nombre',
                COALESCE(NULLIF(v_item->>'fecha_inicio_plan','')::DATE, v_plan_inicio),
                NULLIF(v_item->>'duracion_plan_dias','')::NUMERIC * 8,
                'planificada', 'normal',
                fn_calama_uuid_det(v_full_folio_ot), v_uid
            );
            v_ots_ins := v_ots_ins + 1;
            v_fechas_ins := v_fechas_ins + 1;
        ELSIF v_existing_estado = 'planificada' THEN
            UPDATE calama_ordenes_trabajo SET
                titulo = COALESCE(v_item->>'nombre', titulo),
                descripcion = COALESCE(v_item->>'nombre', descripcion),
                fecha_programada = COALESCE(NULLIF(v_item->>'fecha_inicio_plan','')::DATE, fecha_programada),
                horas_estimadas = COALESCE(NULLIF(v_item->>'duracion_plan_dias','')::NUMERIC * 8, horas_estimadas),
                tarea_maestro_id = v_tarea_id,
                updated_at = NOW()
             WHERE folio = v_full_folio_ot;
            v_ots_upd := v_ots_upd + 1;
        ELSE
            v_ots_skip := v_ots_skip + 1;
            v_advertencias := array_append(v_advertencias,
                'OT ' || v_full_folio_ot || ' en estado ' || v_existing_estado || ' — no sobreescrita.');
        END IF;
    END LOOP;

    -- ── Subtareas (atadas a la OT correspondiente) ───────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_subt) LOOP
        v_subt_codigo := v_item->>'codigo';
        v_tarea_codigo := v_item->>'tarea_codigo';
        IF v_subt_codigo IS NULL OR v_tarea_codigo IS NULL THEN
            v_advertencias := array_append(v_advertencias,
                'Subtarea sin codigo o sin tarea_codigo, omitida: ' || COALESCE(v_subt_codigo,'?'));
            CONTINUE;
        END IF;

        v_full_folio_ot := 'OT_' || v_plan_codigo || '_' || v_tarea_codigo;
        SELECT id INTO v_ot_id FROM calama_ordenes_trabajo WHERE folio = v_full_folio_ot;
        IF v_ot_id IS NULL THEN
            v_advertencias := array_append(v_advertencias,
                'Subtarea ' || v_subt_codigo || ' sin OT padre encontrada (' || v_full_folio_ot || ').');
            CONTINUE;
        END IF;

        v_orden := COALESCE(
            NULLIF(split_part(v_subt_codigo, '.', 3), '')::INT,
            NULLIF(split_part(v_subt_codigo, '.', 2), '')::INT,
            1
        );
        v_uuid_det := fn_calama_uuid_det('subt:' || v_full_folio_ot || ':' || v_subt_codigo);

        INSERT INTO calama_ot_subtareas (
            ot_id, orden, descripcion, estado, cliente_uuid
        ) VALUES (
            v_ot_id, v_orden,
            COALESCE(v_item->>'descripcion', v_subt_codigo),
            CASE
                WHEN COALESCE(v_item->>'estado','') ILIKE '%realizad%' THEN 'completada'
                WHEN COALESCE(v_item->>'estado','') ILIKE '%ejec%'      THEN 'en_ejecucion'
                WHEN COALESCE(v_item->>'estado','') ILIKE '%aplica%'    THEN 'no_aplica'
                ELSE 'pendiente'
            END,
            v_uuid_det
        )
        ON CONFLICT (cliente_uuid) DO UPDATE SET
            descripcion = EXCLUDED.descripcion,
            estado = EXCLUDED.estado,
            updated_at = NOW()
        RETURNING (xmax = 0) INTO v_is_insert;

        IF v_is_insert THEN v_subt_ins := v_subt_ins + 1;
        ELSE                v_subt_upd := v_subt_upd + 1;
        END IF;
    END LOOP;

    -- ── Materiales ───────────────────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_mat) LOOP
        v_uuid_det := fn_calama_uuid_det(
            'mat:' || v_plan_codigo || ':' ||
            COALESCE(v_item->>'actividad_relacionada','') || ':' ||
            COALESCE(v_item->>'descripcion','') || ':' ||
            COALESCE(v_item->>'bloque','')
        );

        -- Buscar tarea relacionada por nombre (best effort)
        v_tarea_id := NULL;
        IF (v_item->>'actividad_relacionada') IS NOT NULL THEN
            SELECT id INTO v_tarea_id FROM calama_tareas_maestro
             WHERE codigo LIKE v_plan_codigo || '_%'
               AND nombre ILIKE (v_item->>'actividad_relacionada')
             LIMIT 1;
        END IF;

        INSERT INTO calama_materiales_planificados (
            planificacion_id, tarea_maestro_id,
            actividad_relacionada, descripcion, unidad, cantidad,
            precio_clp, valor_uf, porcentaje, bloque, cliente_uuid
        ) VALUES (
            v_plan_id, v_tarea_id,
            v_item->>'actividad_relacionada',
            COALESCE(v_item->>'descripcion','(sin descripcion)'),
            v_item->>'unidad',
            NULLIF(v_item->>'cantidad','')::NUMERIC,
            NULLIF(v_item->>'precio_clp','')::NUMERIC,
            NULLIF(v_item->>'valor_uf','')::NUMERIC,
            NULLIF(v_item->>'porcentaje','')::NUMERIC,
            v_item->>'bloque',
            v_uuid_det
        )
        ON CONFLICT (cliente_uuid) DO UPDATE SET
            tarea_maestro_id = EXCLUDED.tarea_maestro_id,
            actividad_relacionada = EXCLUDED.actividad_relacionada,
            descripcion = EXCLUDED.descripcion,
            unidad = EXCLUDED.unidad,
            cantidad = EXCLUDED.cantidad,
            precio_clp = EXCLUDED.precio_clp,
            valor_uf = EXCLUDED.valor_uf,
            porcentaje = EXCLUDED.porcentaje,
            bloque = EXCLUDED.bloque
        RETURNING (xmax = 0) INTO v_is_insert;

        IF v_is_insert THEN v_mat_ins := v_mat_ins + 1; END IF;
    END LOOP;

    -- ── Contactos ────────────────────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_cont) LOOP
        v_uuid_det := fn_calama_uuid_det(
            'cont:' || v_faena_codigo || ':' ||
            COALESCE(v_item->>'codigo_actividad','') || ':' ||
            COALESCE(v_item->>'telefono','')
        );

        INSERT INTO calama_contactos_mandante (
            faena_calama_id, planificacion_id,
            codigo_actividad, descripcion, telefono, rol, cliente_uuid
        ) VALUES (
            v_faena_id, v_plan_id,
            v_item->>'codigo_actividad',
            COALESCE(v_item->>'descripcion','(sin descripcion)'),
            v_item->>'telefono',
            v_item->>'rol',
            v_uuid_det
        )
        ON CONFLICT (cliente_uuid) DO UPDATE SET
            descripcion = EXCLUDED.descripcion,
            telefono = EXCLUDED.telefono,
            rol = EXCLUDED.rol,
            planificacion_id = EXCLUDED.planificacion_id,
            updated_at = NOW()
        RETURNING (xmax = 0) INTO v_is_insert;

        IF v_is_insert THEN v_cont_ins := v_cont_ins + 1;
        ELSE                v_cont_upd := v_cont_upd + 1;
        END IF;
    END LOOP;

    -- ── Observaciones (solo si hay match con OT) ─────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_obs) LOOP
        v_tarea_codigo := v_item->>'codigo_relacionado';
        IF v_tarea_codigo IS NULL THEN
            v_obs_skip := v_obs_skip + 1;
            CONTINUE;
        END IF;

        v_full_folio_ot := 'OT_' || v_plan_codigo || '_' || v_tarea_codigo;
        SELECT id INTO v_ot_id FROM calama_ordenes_trabajo WHERE folio = v_full_folio_ot;

        IF v_ot_id IS NULL THEN
            v_obs_skip := v_obs_skip + 1;
            v_advertencias := array_append(v_advertencias,
                'Observacion para ' || v_tarea_codigo || ' sin OT — omitida.');
            CONTINUE;
        END IF;

        v_uuid_det := fn_calama_uuid_det('obs:' || v_full_folio_ot || ':' || md5(COALESCE(v_item->>'texto','')));

        IF NOT EXISTS (
            SELECT 1 FROM calama_observaciones WHERE cliente_uuid = v_uuid_det
        ) THEN
            INSERT INTO calama_observaciones (
                ot_id, tipo, severidad, detalle, creada_por, cliente_uuid
            ) VALUES (
                v_ot_id, 'importacion_excel', 'info',
                COALESCE(v_item->>'texto','(sin texto)'),
                v_uid, v_uuid_det
            );
            v_obs_ins := v_obs_ins + 1;
        END IF;
    END LOOP;

    -- ── Estado final + advertencias ──────────────────────────────────────────
    IF array_length(v_advertencias, 1) > 0 AND NOT v_permitir_warn THEN
        v_resultado := 'WARNING_IMPORTACION_CALAMA';
    END IF;

    -- ── Bitacora ─────────────────────────────────────────────────────────────
    INSERT INTO calama_importaciones_log (
        archivo, planificacion_id, faena_calama_id, linea_negocio,
        resultado, detalle, payload_resumen, importado_por
    ) VALUES (
        v_archivo, v_plan_id, v_faena_id, v_linea,
        v_resultado,
        format(
            'zonas %s/%s, tareas %s/%s, OTs %s ins/%s upd/%s skip, subt %s/%s, mat %s, cont %s/%s, obs %s/%s skip',
            v_zonas_ins, v_zonas_upd, v_tareas_ins, v_tareas_upd,
            v_ots_ins, v_ots_upd, v_ots_skip, v_subt_ins, v_subt_upd,
            v_mat_ins, v_cont_ins, v_cont_upd, v_obs_ins, v_obs_skip
        ),
        jsonb_build_object(
            'plan_codigo', v_plan_codigo,
            'archivo', v_archivo,
            'advertencias_count', array_length(v_advertencias,1),
            'errores_count', array_length(v_errores,1)
        ),
        v_uid
    );

    -- ── Bitacora produccion (operacion_migraciones_log) — opcional, fire&forget
    BEGIN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'CALAMA_IMPORT_RPC',
            'Importacion Excel Calama via RPC',
            current_user, NOW(), NOW(), 'ok',
            'plan=' || v_plan_codigo || ' faena=' || v_faena_codigo
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'resultado', v_resultado,
        'plan_codigo', v_plan_codigo,
        'plan_id', v_plan_id,
        'faena_usada', v_faena_codigo,
        'linea_negocio_usada', v_linea,
        'zonas_insertadas', v_zonas_ins,
        'zonas_actualizadas', v_zonas_upd,
        'tareas_insertadas', v_tareas_ins,
        'tareas_actualizadas', v_tareas_upd,
        'ots_insertadas', v_ots_ins,
        'ots_actualizadas', v_ots_upd,
        'ots_skipped', v_ots_skip,
        'subtareas_insertadas', v_subt_ins,
        'subtareas_actualizadas', v_subt_upd,
        'materiales_insertados', v_mat_ins,
        'contactos_insertados', v_cont_ins,
        'contactos_actualizados', v_cont_upd,
        'observaciones_insertadas', v_obs_ins,
        'observaciones_skipped', v_obs_skip,
        'fechas_insertadas', v_fechas_ins,
        'errores', to_jsonb(v_errores),
        'advertencias', to_jsonb(v_advertencias)
    );
END $$;

GRANT EXECUTE ON FUNCTION rpc_calama_importar_excel(jsonb) TO authenticated;


-- ============================================================================
-- ── 5. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG18_CALAMA_IMPORT',
        'FASE 2B Operacion Calama: 4 tablas + 3 helpers + RPC importar Excel.',
        current_user, NOW(), NOW(), 'ok',
        'Idempotente via cliente_uuid determinista. RLS estricta. anon sin acceso.'
    );
END $$;


-- ============================================================================
-- ── 6. VERIFICACION FINAL (1 fila) ──────────────────────────────────────────
-- ============================================================================
WITH
tablas_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.tables
                              WHERE table_schema='public' AND table_name='calama_zonas_proyecto')
             THEN 'calama_zonas_proyecto' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.tables
                              WHERE table_schema='public' AND table_name='calama_materiales_planificados')
             THEN 'calama_materiales_planificados' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.tables
                              WHERE table_schema='public' AND table_name='calama_contactos_mandante')
             THEN 'calama_contactos_mandante' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.tables
                              WHERE table_schema='public' AND table_name='calama_importaciones_log')
             THEN 'calama_importaciones_log' END
    ]::text[], NULL) AS faltan
),
helpers_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.fn_calama_uuid_det(text)') IS NULL
             THEN 'fn_calama_uuid_det' END,
        CASE WHEN to_regprocedure('public.fn_calama_puede_importar()') IS NULL
             THEN 'fn_calama_puede_importar' END,
        CASE WHEN to_regprocedure('public.fn_calama_sub_linea_heuristica(text,text)') IS NULL
             THEN 'fn_calama_sub_linea_heuristica' END,
        CASE WHEN to_regprocedure('public.rpc_calama_importar_excel(jsonb)') IS NULL
             THEN 'rpc_calama_importar_excel' END
    ]::text[], NULL) AS faltan
),
rls_faltante AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_zonas_proyecto')
             THEN 'calama_zonas_proyecto' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_materiales_planificados')
             THEN 'calama_materiales_planificados' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_contactos_mandante')
             THEN 'calama_contactos_mandante' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_importaciones_log')
             THEN 'calama_importaciones_log' END
    ]::text[], NULL) AS sin_rls
),
anon_lee_calama AS (
    SELECT COALESCE(array_agg(DISTINCT tablename::text ORDER BY tablename::text), ARRAY[]::text[]) AS tablas
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename::text IN ('calama_zonas_proyecto','calama_materiales_planificados',
                              'calama_contactos_mandante','calama_importaciones_log')
      AND 'anon' = ANY(roles)
),
detalle AS (
    SELECT array_to_string(array_remove(ARRAY[
        CASE WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
             THEN 'Tablas faltantes: ' || array_to_string((SELECT faltan FROM tablas_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM helpers_faltantes),1) > 0
             THEN 'Helpers/RPC faltantes: ' || array_to_string((SELECT faltan FROM helpers_faltantes), ', ') END,
        CASE WHEN array_length((SELECT sin_rls FROM rls_faltante),1) > 0
             THEN 'RLS DESHABILITADA en: ' || array_to_string((SELECT sin_rls FROM rls_faltante), ', ') END,
        CASE WHEN array_length((SELECT tablas FROM anon_lee_calama),1) > 0
             THEN 'ANON tiene acceso: ' || array_to_string((SELECT tablas FROM anon_lee_calama), ', ') END
    ]::text[], NULL), ' | ') AS texto
)
SELECT
    CASE
        WHEN COALESCE((SELECT texto FROM detalle), '') = ''
            THEN 'OK_OPERACION_CALAMA_IMPORT'
        WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
          OR array_length((SELECT faltan FROM helpers_faltantes),1) > 0
          OR array_length((SELECT sin_rls FROM rls_faltante),1) > 0
          OR array_length((SELECT tablas FROM anon_lee_calama),1) > 0
            THEN 'STOP_OPERACION_CALAMA_IMPORT'
        ELSE 'WARNING_OPERACION_CALAMA_IMPORT'
    END AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
        '4 tablas nuevas + 3 helpers + RPC + RLS + anon sin acceso.'
    ) AS detalle,
    NOW() AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- - OK_OPERACION_CALAMA_IMPORT      → frontend puede llamar rpc_calama_importar_excel.
-- - WARNING_OPERACION_CALAMA_IMPORT → revisar columna detalle.
-- - STOP_OPERACION_CALAMA_IMPORT    → estructura incompleta o anon con acceso.
-- ============================================================================
