-- ============================================================================
-- 18B_operacion_calama_materiales_por_zona.sql
-- ----------------------------------------------------------------------------
-- Patch sobre MIG18: re-define rpc_calama_importar_excel para que la
-- idempotencia de materiales discrimine por zona.
--
-- ALCANCE:
--   - CREATE OR REPLACE FUNCTION rpc_calama_importar_excel(jsonb).
--   - Materiales: cliente_uuid ahora incluye zona (codigo o '_sin_zona').
--   - Materiales: al importar se hace DELETE + re-INSERT del set completo
--     de la planificacion, garantizando que el resultado refleje siempre
--     el estado actual del Excel.
--   - Resto de la RPC (planificacion, zonas, tareas, OTs, subtareas,
--     contactos, observaciones) intacto.
--
-- IDEMPOTENCIA:
--   - Misma actividad + misma zona + misma descripcion + mismo bloque
--     -> 1 material (UPDATE en re-importacion).
--   - Misma actividad + distinta zona -> N materiales independientes.
--
-- AISLACION:
--   - NO toca MIG17, MIG18 estructura de tablas, MIG55-57, scripts 14*.
--   - NO toca rol_usuario_enum.
--   - Solo redefine la funcion. RLS y tablas siguen igual.
--
-- VERIFICACION FINAL: 1 fila con
--   resultado / materiales_antes / materiales_despues /
--   duplicados_misma_zona / duplicados_distinta_zona / chequeado_en.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF to_regprocedure('public.rpc_calama_importar_excel(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'STOP — MIG18 no aplicada (rpc_calama_importar_excel no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_materiales_planificados') THEN
        RAISE EXCEPTION 'STOP — calama_materiales_planificados no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_zonas_proyecto') THEN
        RAISE EXCEPTION 'STOP — calama_zonas_proyecto no existe.';
    END IF;
END $$;


-- ============================================================================
-- ── 1. SNAPSHOT antes del patch ──────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM calama_materiales_planificados;
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG18B_SNAPSHOT_PRE',
        'Snapshot pre-patch: count materiales antes de redefinir RPC',
        current_user, NOW(), NOW(), 'ok',
        'count=' || v_count
    );
END $$;


-- ============================================================================
-- ── 2. CREATE OR REPLACE rpc_calama_importar_excel (zone-aware) ──────────────
-- ============================================================================

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
    v_payload_zonas JSONB := COALESCE(p_payload->'zonas', '[]'::jsonb);
    v_payload_tareas JSONB := COALESCE(p_payload->'tareas', '[]'::jsonb);
    v_payload_subt JSONB := COALESCE(p_payload->'subtareas', '[]'::jsonb);
    v_payload_mat JSONB := COALESCE(p_payload->'materiales', '[]'::jsonb);
    v_payload_cont JSONB := COALESCE(p_payload->'contactos', '[]'::jsonb);
    v_payload_obs JSONB := COALESCE(p_payload->'observaciones', '[]'::jsonb);
    v_item JSONB;
    v_is_insert BOOLEAN;
    v_zona_proyecto_id UUID;
    v_zona_seed TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_importar() THEN
        RAISE EXCEPTION 'Rol no autorizado para importar Excel Calama';
    END IF;

    IF v_faena_codigo IS NULL OR v_linea IS NULL OR v_plan_codigo IS NULL THEN
        RAISE EXCEPTION 'payload invalido: faena_codigo, linea_negocio y plan_codigo son obligatorios';
    END IF;
    IF v_linea NOT IN ('combustibles','lubricantes','mejoras_civiles') THEN
        RAISE EXCEPTION 'linea_negocio invalida: %', v_linea;
    END IF;
    IF v_tiene_err_map THEN
        RAISE EXCEPTION 'No se permite importar con errores_de_mapeo. Corregir el Excel y reintentar.';
    END IF;

    SELECT id INTO v_faena_id FROM calama_faenas
     WHERE codigo = v_faena_codigo AND activo = true;
    IF v_faena_id IS NULL THEN
        RAISE EXCEPTION 'faena_codigo % no encontrada o inactiva', v_faena_codigo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM calama_lineas_negocio WHERE codigo = v_linea AND activo = true) THEN
        RAISE EXCEPTION 'linea_negocio % no esta en calama_lineas_negocio', v_linea;
    END IF;

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

    -- ── Tareas + OTs ────────────────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_tareas) LOOP
        v_tarea_codigo := v_item->>'codigo';
        IF v_tarea_codigo IS NULL OR v_tarea_codigo = '' THEN CONTINUE; END IF;

        v_full_tarea_codigo := v_plan_codigo || '_' || v_tarea_codigo;
        v_sub_linea := fn_calama_sub_linea_heuristica(v_linea, v_item->>'nombre');

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

    -- ── Subtareas ───────────────────────────────────────────────────────────
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

    -- ── Materiales (ZONA-AWARE — patch 18B) ─────────────────────────────────
    -- Estrategia: clean slate. Eliminamos todos los materiales de esta
    -- planificacion antes de re-insertar. Esto garantiza que el resultado
    -- refleje exactamente el contenido del Excel actual y limpia orphans
    -- que pudieron quedar de imports previos con la formula vieja.
    DELETE FROM calama_materiales_planificados WHERE planificacion_id = v_plan_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_payload_mat) LOOP
        v_zona_codigo := v_item->>'zona_codigo';
        v_zona_seed := COALESCE(v_zona_codigo, '_sin_zona');
        v_zona_proyecto_id := NULL;

        IF v_zona_codigo IS NOT NULL AND v_zona_codigo <> '' THEN
            SELECT id INTO v_zona_proyecto_id
              FROM calama_zonas_proyecto
             WHERE planificacion_id = v_plan_id AND codigo_zona = v_zona_codigo;
        END IF;

        v_uuid_det := fn_calama_uuid_det(
            'mat:' || v_plan_codigo || ':' || v_zona_seed || ':' ||
            COALESCE(v_item->>'actividad_relacionada','') || ':' ||
            COALESCE(v_item->>'descripcion','') || ':' ||
            COALESCE(v_item->>'bloque','')
        );

        v_tarea_id := NULL;
        IF (v_item->>'actividad_relacionada') IS NOT NULL THEN
            SELECT id INTO v_tarea_id FROM calama_tareas_maestro
             WHERE codigo LIKE v_plan_codigo || '_%'
               AND nombre ILIKE (v_item->>'actividad_relacionada')
             LIMIT 1;
        END IF;

        INSERT INTO calama_materiales_planificados (
            planificacion_id, tarea_maestro_id, zona_proyecto_id,
            actividad_relacionada, descripcion, unidad, cantidad,
            precio_clp, valor_uf, porcentaje, bloque, cliente_uuid
        ) VALUES (
            v_plan_id, v_tarea_id, v_zona_proyecto_id,
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
            zona_proyecto_id = EXCLUDED.zona_proyecto_id,
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

    -- ── Contactos ───────────────────────────────────────────────────────────
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

    -- ── Observaciones ───────────────────────────────────────────────────────
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

        IF NOT EXISTS (SELECT 1 FROM calama_observaciones WHERE cliente_uuid = v_uuid_det) THEN
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

    IF array_length(v_advertencias, 1) > 0 AND NOT v_permitir_warn THEN
        v_resultado := 'WARNING_IMPORTACION_CALAMA';
    END IF;

    INSERT INTO calama_importaciones_log (
        archivo, planificacion_id, faena_calama_id, linea_negocio,
        resultado, detalle, payload_resumen, importado_por
    ) VALUES (
        v_archivo, v_plan_id, v_faena_id, v_linea,
        v_resultado,
        format(
            'zonas %s/%s, tareas %s/%s, OTs %s ins/%s upd/%s skip, subt %s/%s, mat %s, cont %s/%s, obs %s/%s skip [zone-aware]',
            v_zonas_ins, v_zonas_upd, v_tareas_ins, v_tareas_upd,
            v_ots_ins, v_ots_upd, v_ots_skip, v_subt_ins, v_subt_upd,
            v_mat_ins, v_cont_ins, v_cont_upd, v_obs_ins, v_obs_skip
        ),
        jsonb_build_object(
            'plan_codigo', v_plan_codigo,
            'archivo', v_archivo,
            'advertencias_count', array_length(v_advertencias,1),
            'errores_count', array_length(v_errores,1),
            'patch', '18B_zone_aware'
        ),
        v_uid
    );

    BEGIN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'CALAMA_IMPORT_RPC',
            'Importacion Excel Calama via RPC (zone-aware)',
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
-- ── 3. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG18B_ZONE_AWARE',
        'Patch 18B: rpc_calama_importar_excel ahora discrimina materiales por zona.',
        current_user, NOW(), NOW(), 'ok',
        'cliente_uuid materiales incluye zona_codigo. DELETE+re-INSERT por planificacion.'
    );
END $$;


-- ============================================================================
-- ── 4. VERIFICACION FINAL (1 fila) ──────────────────────────────────────────
-- ============================================================================
WITH
materiales_total AS (
    SELECT COUNT(*)::int AS n FROM calama_materiales_planificados
),
materiales_con_zona AS (
    SELECT COUNT(*)::int AS n FROM calama_materiales_planificados WHERE zona_proyecto_id IS NOT NULL
),
-- Duplicados con MISMA zona (deberian ser 0 cuando se aplica el patch + reimport):
-- 2 filas con misma (plan, zona, actividad, descripcion, bloque) son duplicados.
dup_misma_zona AS (
    SELECT COALESCE(SUM(c - 1), 0)::int AS n
      FROM (
          SELECT COUNT(*) AS c
            FROM calama_materiales_planificados
           GROUP BY planificacion_id, zona_proyecto_id,
                    COALESCE(actividad_relacionada,''), descripcion, COALESCE(bloque,'')
          HAVING COUNT(*) > 1
      ) g
),
-- "Duplicados" entre distintas zonas: misma actividad+descripcion+bloque pero
-- separados en zonas diferentes. NO son problema — son legitimos.
dup_distinta_zona AS (
    SELECT COUNT(*)::int AS n
      FROM (
          SELECT planificacion_id,
                 COALESCE(actividad_relacionada,'') AS act,
                 descripcion,
                 COALESCE(bloque,'') AS bloque
            FROM calama_materiales_planificados
           GROUP BY planificacion_id, act, descripcion, bloque
          HAVING COUNT(DISTINCT COALESCE(zona_proyecto_id::text, '_')) > 1
      ) g
),
-- "antes" = el snapshot que dejamos en operacion_migraciones_log
materiales_antes AS (
    SELECT COALESCE(
        NULLIF(regexp_replace(detalle, '^count=', ''), '')::int,
        0
    ) AS n
      FROM operacion_migraciones_log
     WHERE codigo_paso = 'PROD_MIG18B_SNAPSHOT_PRE'
     ORDER BY fecha_inicio DESC LIMIT 1
),
patch_estado AS (
    SELECT EXISTS (
        SELECT 1 FROM operacion_migraciones_log
         WHERE codigo_paso = 'PROD_MIG18B_ZONE_AWARE'
    ) AS aplicado
),
rpc_existe AS (
    SELECT to_regprocedure('public.rpc_calama_importar_excel(jsonb)') IS NOT NULL AS v
)
SELECT
    CASE
        WHEN NOT (SELECT v FROM rpc_existe) THEN 'STOP_OPERACION_CALAMA_PATCH18B'
        WHEN NOT (SELECT aplicado FROM patch_estado) THEN 'WARNING_OPERACION_CALAMA_PATCH18B'
        WHEN (SELECT n FROM dup_misma_zona) > 0 THEN 'WARNING_OPERACION_CALAMA_PATCH18B'
        ELSE 'OK_OPERACION_CALAMA_PATCH18B'
    END                                                               AS resultado,
    (SELECT n FROM materiales_antes)                                  AS materiales_antes,
    (SELECT n FROM materiales_total)                                  AS materiales_despues,
    (SELECT n FROM materiales_con_zona)                               AS materiales_con_zona_asignada,
    (SELECT n FROM dup_misma_zona)                                    AS duplicados_misma_zona,
    (SELECT n FROM dup_distinta_zona)                                 AS duplicados_distinta_zona,
    NOW()                                                             AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_OPERACION_CALAMA_PATCH18B
--     → patch aplicado y ningun duplicado dentro de misma zona.
-- - resultado = WARNING_*
--     → patch aplicado pero con advertencias (ej. duplicados_misma_zona > 0
--        antes de reimportar — aun hay rows con UUIDs viejos).
-- - resultado = STOP_*
--     → la RPC no existe o el snapshot fallo.
--
-- DESPUES DE ESTE PATCH:
--   1. Re-importar el Excel desde la UI (la RPC limpia y reinserta).
--   2. Los materiales nuevos tendran zona_proyecto_id poblada.
--   3. Volver a ejecutar la query de verificacion final para revisar
--      materiales_despues / duplicados_misma_zona.
--
-- NOTA: la primera vez que se ejecuta esta verificacion (sin reimportar),
-- materiales_antes y materiales_despues son iguales. Recien tras un re-import
-- desde la UI los conteos cambian.
-- ============================================================================
