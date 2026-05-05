-- ============================================================================
-- 22_operacion_calama_avance_real_operador.sql
-- ----------------------------------------------------------------------------
-- Avance real operacional + auditoria + ejecucion del operador.
--
-- ALCANCE:
--   - ALTER calama_ordenes_trabajo: agregar avance_excel_pct numeric default 0.
--   - Tabla nueva: calama_ot_avance_eventos (auditoria de cambios de avance).
--   - 4 RPCs:
--       rpc_calama_actualizar_avance_ot(jsonb)              -- planificador / supervisor
--       rpc_calama_marcar_ot_completada_operador(jsonb)     -- operador completa al 100%
--       rpc_calama_registrar_avance_operador(jsonb)         -- operador avance parcial
--       rpc_calama_set_avance_excel_lote(jsonb)             -- bulk del importer
--   - Vistas actualizadas: v_calama_avance_por_area, v_calama_resumen_general
--     con avance Excel + Real + Desviacion + breakdown.
--
-- DIAGNOSTICO:
--   - calama_ordenes_trabajo ya tiene: id, folio, planificacion_id, avance_pct,
--     estado, responsable_id, horas_reales (MIG17). Agregamos avance_excel_pct.
--   - calama_ot_ejecuciones (MIG20) calcula tiempos efectivo/pausado/colacion.
--   - rpc_calama_finalizar_ejecucion_ot ya marca estado='finalizada' y avance_pct.
--   - No habia auditoria de cambios de avance hasta ahora.
--   - Estado 'completada' NO esta en chk_calama_ot_estado; usamos 'finalizada'.
--
-- AISLACION:
--   - NO toca MIG17/18/18B/19/20/21.
--   - NO toca QR (mig 14*), MIG55-57, ni rol_usuario_enum.
--   - NO modifica RPCs existentes (las dejamos validadas).
--   - Recrea vistas v_calama_* con CREATE OR REPLACE (compatible).
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_AVANCE_REAL / WARNING / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP - MIG17 no aplicada (calama_ordenes_trabajo no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ot_ejecuciones') THEN
        RAISE EXCEPTION 'STOP - MIG20 no aplicada (calama_ot_ejecuciones no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_puede_planificar()') IS NULL THEN
        RAISE EXCEPTION 'STOP - fn_calama_puede_planificar no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. ALTER calama_ordenes_trabajo: avance_excel_pct ────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='calama_ordenes_trabajo'
           AND column_name='avance_excel_pct'
    ) THEN
        ALTER TABLE calama_ordenes_trabajo
            ADD COLUMN avance_excel_pct NUMERIC(5,2) NOT NULL DEFAULT 0;

        ALTER TABLE calama_ordenes_trabajo
            ADD CONSTRAINT chk_calama_ot_avance_excel
            CHECK (avance_excel_pct BETWEEN 0 AND 100);
    END IF;
END $$;


-- ============================================================================
-- ── 2. TABLA calama_ot_avance_eventos ────────────────────────────────────────
-- ============================================================================
CREATE TABLE IF NOT EXISTS calama_ot_avance_eventos (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id                 UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    plan_semanal_ot_id    UUID REFERENCES calama_plan_semanal_ots(id) ON DELETE SET NULL,
    ejecucion_id          UUID REFERENCES calama_ot_ejecuciones(id) ON DELETE SET NULL,
    avance_anterior       NUMERIC(5,2),
    avance_nuevo          NUMERIC(5,2) NOT NULL,
    fuente                VARCHAR(20) NOT NULL,
    motivo                VARCHAR(60),
    comentario            TEXT,
    created_by            UUID REFERENCES auth.users(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_avancev_fuente CHECK (fuente IN
        ('excel','operador','planificador','supervisor','sistema')),
    CONSTRAINT chk_calama_avancev_pct CHECK (avance_nuevo BETWEEN 0 AND 100)
);
CREATE INDEX IF NOT EXISTS idx_calama_avancev_ot ON calama_ot_avance_eventos (ot_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calama_avancev_fuente ON calama_ot_avance_eventos (fuente);

ALTER TABLE calama_ot_avance_eventos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_calama_avancev_select ON calama_ot_avance_eventos;
CREATE POLICY pol_calama_avancev_select ON calama_ot_avance_eventos
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR created_by = auth.uid()
        OR fn_calama_operador_es_responsable_ot(ot_id)
    );
DROP POLICY IF EXISTS pol_calama_avancev_insert ON calama_ot_avance_eventos;
CREATE POLICY pol_calama_avancev_insert ON calama_ot_avance_eventos
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR fn_calama_operador_es_responsable_ot(ot_id)
    );


-- ============================================================================
-- ── 3. HELPER: aplicar avance + registrar evento ─────────────────────────────
-- ============================================================================
-- Funcion privada (no se expone via GRANT) — uso interno por las RPCs.
CREATE OR REPLACE FUNCTION fn_calama_aplicar_avance_interno(
    p_ot_id          UUID,
    p_avance_nuevo   NUMERIC,
    p_fuente         TEXT,
    p_motivo         TEXT,
    p_comentario     TEXT,
    p_uid            UUID,
    p_ejecucion_id   UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_avance_prev NUMERIC;
    v_estado_actual TEXT;
    v_plan_ot_id UUID;
    v_evento_id UUID;
    v_avance_clamp NUMERIC;
BEGIN
    v_avance_clamp := LEAST(GREATEST(COALESCE(p_avance_nuevo, 0), 0), 100);

    SELECT avance_pct, estado INTO v_avance_prev, v_estado_actual
      FROM calama_ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;
    IF v_avance_prev IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;

    -- Buscar plan-OT relacionada (mas reciente)
    SELECT id INTO v_plan_ot_id FROM calama_plan_semanal_ots
     WHERE ot_id = p_ot_id ORDER BY created_at DESC LIMIT 1;

    -- Actualizar OT (no bajamos a 'finalizada' si ya esta cancelada)
    UPDATE calama_ordenes_trabajo
       SET avance_pct = v_avance_clamp,
           estado = CASE
               WHEN v_avance_clamp >= 100 AND estado NOT IN ('cancelada')
                    THEN 'finalizada'
               WHEN v_avance_clamp > 0 AND estado IN ('planificada','liberada')
                    THEN 'en_ejecucion'
               ELSE estado
           END,
           fecha_termino_real = CASE
               WHEN v_avance_clamp >= 100 AND estado NOT IN ('cancelada','finalizada')
                    THEN NOW()
               ELSE fecha_termino_real
           END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    -- Sincronizar plan-OT estado_plan
    IF v_plan_ot_id IS NOT NULL THEN
        UPDATE calama_plan_semanal_ots
           SET estado_plan = CASE
               WHEN v_avance_clamp >= 100 THEN 'finalizada'
               WHEN v_avance_clamp > 0 AND estado_plan IN ('planificada','asignada','liberada')
                    THEN 'en_ejecucion'
               ELSE estado_plan
           END,
           updated_at = NOW()
         WHERE id = v_plan_ot_id;
    END IF;

    INSERT INTO calama_ot_avance_eventos (
        ot_id, plan_semanal_ot_id, ejecucion_id,
        avance_anterior, avance_nuevo, fuente, motivo, comentario, created_by
    ) VALUES (
        p_ot_id, v_plan_ot_id, p_ejecucion_id,
        v_avance_prev, v_avance_clamp, p_fuente, p_motivo, p_comentario, p_uid
    ) RETURNING id INTO v_evento_id;

    RETURN jsonb_build_object(
        'success', true,
        'evento_id', v_evento_id,
        'ot_id', p_ot_id,
        'avance_anterior', v_avance_prev,
        'avance_nuevo', v_avance_clamp,
        'plan_semanal_ot_id', v_plan_ot_id
    );
END $$;
-- NO grant a authenticated: solo se invoca desde otras RPCs SECURITY DEFINER.


-- ============================================================================
-- ── 4. RPCs PUBLICAS ─────────────────────────────────────────────────────────
-- ============================================================================

-- 4.1 Actualizar avance manual (planificador / supervisor / admin)
CREATE OR REPLACE FUNCTION rpc_calama_actualizar_avance_ot(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_avance_nuevo NUMERIC := (p_payload->>'avance_nuevo')::NUMERIC;
    v_fuente TEXT := COALESCE(p_payload->>'fuente','planificador');
    v_motivo TEXT := p_payload->>'motivo';
    v_comentario TEXT := p_payload->>'comentario';
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para actualizar avance manualmente';
    END IF;
    IF v_ot_id IS NULL OR v_avance_nuevo IS NULL THEN
        RAISE EXCEPTION 'ot_id y avance_nuevo son obligatorios';
    END IF;
    IF v_fuente NOT IN ('planificador','supervisor','sistema') THEN
        v_fuente := 'planificador';
    END IF;
    -- Si avance es 100 manual, exigir comentario (acuerdo operativo)
    IF v_avance_nuevo >= 100 AND COALESCE(TRIM(v_comentario),'') = '' THEN
        RAISE EXCEPTION 'Comentario obligatorio cuando se marca 100%% manualmente';
    END IF;

    RETURN fn_calama_aplicar_avance_interno(
        v_ot_id, v_avance_nuevo, v_fuente, v_motivo, v_comentario, v_uid, NULL
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_actualizar_avance_ot(jsonb) TO authenticated;


-- 4.2 Operador marca completada (100%)
CREATE OR REPLACE FUNCTION rpc_calama_marcar_ot_completada_operador(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_ejecucion_id UUID := NULLIF(p_payload->>'ejecucion_id','')::UUID;
    v_comentario TEXT := COALESCE(p_payload->>'comentario','Tarea completada en terreno');
    v_es_responsable BOOLEAN;
    v_resultado JSONB;
    v_estado_ejec TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'ot_id obligatorio'; END IF;

    -- Permitido si es planificador, o si es responsable de la OT en plan semanal
    v_es_responsable := fn_calama_operador_es_responsable_ot(v_ot_id);
    IF NOT (fn_calama_puede_planificar() OR v_es_responsable) THEN
        RAISE EXCEPTION 'No tienes esta OT asignada';
    END IF;

    v_resultado := fn_calama_aplicar_avance_interno(
        v_ot_id, 100, 'operador', 'completada_en_terreno', v_comentario, v_uid, v_ejecucion_id
    );

    -- Si hay ejecucion abierta, finalizarla
    IF v_ejecucion_id IS NULL THEN
        SELECT id INTO v_ejecucion_id FROM calama_ot_ejecuciones
         WHERE ot_id = v_ot_id AND estado IN ('en_ejecucion','pausada')
         ORDER BY started_at DESC LIMIT 1;
    END IF;

    IF v_ejecucion_id IS NOT NULL THEN
        SELECT estado INTO v_estado_ejec FROM calama_ot_ejecuciones WHERE id = v_ejecucion_id;
        IF v_estado_ejec IN ('en_ejecucion','pausada') THEN
            PERFORM rpc_calama_finalizar_ejecucion_ot(v_ejecucion_id, 100, v_comentario);
        END IF;
    END IF;

    RETURN v_resultado;
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_marcar_ot_completada_operador(jsonb) TO authenticated;


-- 4.3 Operador registra avance parcial
CREATE OR REPLACE FUNCTION rpc_calama_registrar_avance_operador(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_avance_nuevo NUMERIC := (p_payload->>'avance_nuevo')::NUMERIC;
    v_comentario TEXT := p_payload->>'comentario';
    v_es_responsable BOOLEAN;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_ot_id IS NULL OR v_avance_nuevo IS NULL THEN
        RAISE EXCEPTION 'ot_id y avance_nuevo son obligatorios';
    END IF;
    IF v_avance_nuevo < 0 OR v_avance_nuevo > 100 THEN
        RAISE EXCEPTION 'avance_nuevo fuera de rango [0,100]';
    END IF;

    v_es_responsable := fn_calama_operador_es_responsable_ot(v_ot_id);
    IF NOT (fn_calama_puede_planificar() OR v_es_responsable) THEN
        RAISE EXCEPTION 'No tienes esta OT asignada';
    END IF;

    -- Si llega a 100 desde aqui, derivar a la RPC de completada (que ademas cierra ejecucion)
    IF v_avance_nuevo >= 100 THEN
        RETURN rpc_calama_marcar_ot_completada_operador(jsonb_build_object(
            'ot_id', v_ot_id,
            'comentario', COALESCE(v_comentario,'Avance al 100%')
        ));
    END IF;

    RETURN fn_calama_aplicar_avance_interno(
        v_ot_id, v_avance_nuevo, 'operador',
        CASE WHEN v_avance_nuevo > 0 THEN 'avance_parcial' ELSE 'sin_avance' END,
        v_comentario, v_uid, NULL
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_avance_operador(jsonb) TO authenticated;


-- 4.4 Importer Excel: set masivo de avance_excel_pct (col C de Carta Gantt)
-- Payload: { "plan_codigo": "...", "items": [{ "tarea_codigo_excel": "1.1.0", "avance_excel_pct": 100 }, ...] }
CREATE OR REPLACE FUNCTION rpc_calama_set_avance_excel_lote(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_plan_codigo TEXT := p_payload->>'plan_codigo';
    v_items JSONB := COALESCE(p_payload->'items','[]'::jsonb);
    v_item JSONB;
    v_folio TEXT;
    v_avance NUMERIC;
    v_count INT := 0;
    v_count_init_real INT := 0;
    v_ot_id UUID;
    v_avance_actual NUMERIC;
    v_estado_actual TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_importar() THEN
        RAISE EXCEPTION 'Rol no autorizado para actualizar avance Excel masivamente';
    END IF;
    IF v_plan_codigo IS NULL THEN RAISE EXCEPTION 'plan_codigo obligatorio'; END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
        v_folio := 'OT_' || v_plan_codigo || '_' || COALESCE(v_item->>'tarea_codigo_excel','');
        v_avance := COALESCE(NULLIF(v_item->>'avance_excel_pct','')::NUMERIC, 0);
        v_avance := LEAST(GREATEST(v_avance, 0), 100);

        SELECT id, avance_pct, estado INTO v_ot_id, v_avance_actual, v_estado_actual
          FROM calama_ordenes_trabajo WHERE folio = v_folio;
        IF v_ot_id IS NULL THEN CONTINUE; END IF;

        UPDATE calama_ordenes_trabajo
           SET avance_excel_pct = v_avance,
               -- Si avance_real esta en 0 y la OT no tiene ejecucion real (estado planificada/liberada),
               -- inicializamos avance_pct = avance_excel para tener un baseline.
               avance_pct = CASE
                   WHEN avance_pct = 0
                    AND estado IN ('planificada','liberada')
                    AND NOT EXISTS (SELECT 1 FROM calama_ot_ejecuciones WHERE ot_id = v_ot_id)
                       THEN v_avance
                   ELSE avance_pct
               END,
               estado = CASE
                   WHEN avance_pct = 0
                    AND estado IN ('planificada','liberada')
                    AND v_avance >= 100
                    AND NOT EXISTS (SELECT 1 FROM calama_ot_ejecuciones WHERE ot_id = v_ot_id)
                       THEN 'finalizada'
                   ELSE estado
               END,
               updated_at = NOW()
         WHERE id = v_ot_id;

        v_count := v_count + 1;

        IF v_avance_actual = 0 AND v_estado_actual IN ('planificada','liberada') THEN
            v_count_init_real := v_count_init_real + 1;
            -- Registrar evento solo cuando se inicializa avance_real desde excel
            INSERT INTO calama_ot_avance_eventos (
                ot_id, avance_anterior, avance_nuevo, fuente, motivo, comentario, created_by
            ) VALUES (
                v_ot_id, 0, v_avance, 'excel', 'inicial_desde_carta_gantt',
                'Avance inicial cargado desde columna C del Excel', v_uid
            );
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'plan_codigo', v_plan_codigo,
        'items_procesados', jsonb_array_length(v_items),
        'ots_actualizadas', v_count,
        'ots_inicializadas_avance_real', v_count_init_real
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_set_avance_excel_lote(jsonb) TO authenticated;


-- ============================================================================
-- ── 5. VISTAS ACTUALIZADAS (avance Excel + Real + desviacion) ────────────────
-- ============================================================================

CREATE OR REPLACE VIEW v_calama_avance_por_area AS
WITH ot_zona AS (
    SELECT
        o.id, o.planificacion_id, o.estado, o.avance_pct, o.avance_excel_pct,
        o.fecha_programada,
        fn_calama_zona_codigo_de_folio(o.folio) AS codigo_zona
    FROM calama_ordenes_trabajo o
),
plan_ots_resumen AS (
    SELECT
        po.plan_semanal_id, po.ot_id, po.responsable_id,
        po.estado_plan, po.observaciones,
        ps.planificacion_id, ps.fecha_inicio_semana, ps.fecha_fin_semana
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
)
SELECT
    p.id                                                    AS planificacion_id,
    p.codigo                                                AS planificacion_codigo,
    z.codigo_zona,
    z.nombre                                                AS lugar_fisico_nombre,
    z.id                                                    AS zona_proyecto_id,
    COUNT(o.id)                                             AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado = 'finalizada')      AS tareas_finalizadas,
    COUNT(o.id) FILTER (WHERE o.estado = 'en_ejecucion')    AS tareas_en_ejecucion,
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada','en_pausa'))
                                                            AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')    AS tareas_no_ejecutadas,
    COUNT(po.ot_id)                                         AS tareas_planificadas_semana,
    COUNT(po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                            AS tareas_sin_responsable,
    COUNT(po.observaciones) FILTER (WHERE po.observaciones IS NOT NULL AND po.observaciones <> '')
                                                            AS tareas_con_comentario,
    COUNT(o.id) FILTER (WHERE o.avance_pct >= 100)          AS tareas_al_100,
    COUNT(o.id) FILTER (WHERE o.avance_pct > 0 AND o.avance_pct < 100)
                                                            AS tareas_parciales,
    COUNT(o.id) FILTER (WHERE o.avance_pct = 0)             AS tareas_sin_avance,
    ROUND(COALESCE(AVG(o.avance_excel_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_excel_promedio_pct,
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_real_promedio_pct,
    ROUND(COALESCE(
        AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada')
      - AVG(o.avance_excel_pct) FILTER (WHERE o.estado <> 'cancelada')
    , 0)::numeric, 1)                                       AS desviacion_pct,
    -- Backwards-compat con MIG21
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_promedio_pct
FROM calama_zonas_proyecto z
JOIN calama_planificaciones p
       ON p.id = z.planificacion_id
LEFT JOIN ot_zona o
       ON o.planificacion_id = p.id
      AND o.codigo_zona = z.codigo_zona
LEFT JOIN plan_ots_resumen po
       ON po.ot_id = o.id
      AND po.planificacion_id = p.id
GROUP BY p.id, p.codigo, z.id, z.codigo_zona, z.nombre
ORDER BY p.codigo, z.codigo_zona;


CREATE OR REPLACE VIEW v_calama_resumen_general AS
WITH ots AS (
    SELECT
        o.planificacion_id, o.id, o.estado,
        o.avance_pct, o.avance_excel_pct, o.fecha_programada
    FROM calama_ordenes_trabajo o
),
plan_ots AS (
    SELECT
        ps.planificacion_id,
        po.ot_id, po.responsable_id, po.observaciones, po.estado_plan
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
),
zonas AS (
    SELECT planificacion_id, COUNT(*)::int AS total_zonas
    FROM calama_zonas_proyecto GROUP BY planificacion_id
),
eventos_resumen AS (
    SELECT
        o.planificacion_id,
        COUNT(DISTINCT e.ot_id) FILTER (WHERE e.fuente = 'operador')      AS ots_actualizadas_por_operador,
        COUNT(DISTINCT e.ot_id) FILTER (WHERE e.fuente IN ('planificador','supervisor'))
                                                                          AS ots_actualizadas_manualmente
    FROM calama_ot_avance_eventos e
    JOIN calama_ordenes_trabajo o ON o.id = e.ot_id
    GROUP BY o.planificacion_id
)
SELECT
    p.id                                              AS planificacion_id,
    p.codigo                                          AS planificacion_codigo,
    p.nombre                                          AS planificacion_nombre,
    p.linea_negocio,
    p.estado                                          AS estado_planificacion,
    COALESCE(z.total_zonas, 0)                        AS total_lugares_fisicos,
    COUNT(o.id)                                       AS total_tareas,
    COUNT(o.id) FILTER (WHERE o.estado = 'finalizada')        AS tareas_finalizadas,
    COUNT(o.id) FILTER (WHERE o.estado = 'en_ejecucion')      AS tareas_en_ejecucion,
    COUNT(o.id) FILTER (WHERE o.estado IN ('planificada','liberada','en_pausa'))
                                                              AS tareas_pendientes,
    COUNT(o.id) FILTER (WHERE o.estado = 'no_ejecutada')      AS tareas_no_ejecutadas,
    COUNT(DISTINCT po.ot_id)                                  AS tareas_planificadas_semanas,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                              AS tareas_sin_responsable,
    COUNT(DISTINCT po.ot_id) FILTER (
        WHERE po.observaciones IS NOT NULL AND po.observaciones <> ''
    )                                                          AS tareas_con_comentario,
    COUNT(o.id) FILTER (WHERE o.avance_pct >= 100)            AS tareas_al_100,
    COUNT(o.id) FILTER (WHERE o.avance_pct > 0 AND o.avance_pct < 100)
                                                              AS tareas_parciales,
    COUNT(o.id) FILTER (WHERE o.avance_pct = 0)               AS tareas_sin_avance,
    COALESCE(er.ots_actualizadas_por_operador, 0)             AS ots_actualizadas_por_operador,
    COALESCE(er.ots_actualizadas_manualmente, 0)              AS ots_actualizadas_manualmente,
    ROUND(COALESCE(AVG(o.avance_excel_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                              AS avance_excel_promedio_pct,
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                              AS avance_real_promedio_pct,
    ROUND(COALESCE(
        AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada')
      - AVG(o.avance_excel_pct) FILTER (WHERE o.estado <> 'cancelada')
    , 0)::numeric, 1)                                         AS desviacion_pct,
    -- Backwards-compat con MIG21
    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                              AS avance_promedio_pct
FROM calama_planificaciones p
LEFT JOIN zonas    z  ON z.planificacion_id = p.id
LEFT JOIN ots      o  ON o.planificacion_id = p.id
LEFT JOIN plan_ots po ON po.planificacion_id = p.id AND po.ot_id = o.id
LEFT JOIN eventos_resumen er ON er.planificacion_id = p.id
GROUP BY p.id, p.codigo, p.nombre, p.linea_negocio, p.estado, z.total_zonas,
         er.ots_actualizadas_por_operador, er.ots_actualizadas_manualmente
ORDER BY p.codigo;


-- ============================================================================
-- ── 6. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG22_CALAMA_AVANCE_REAL',
        'Avance real + auditoria + RPCs operador + columna avance_excel_pct',
        current_user, NOW(), NOW(), 'ok',
        '1 columna + 1 tabla eventos + 1 helper privado + 4 RPCs + 2 vistas actualizadas.'
    );
END $$;


-- ============================================================================
-- ── 7. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
WITH checks AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='calama_ordenes_trabajo'
                   AND column_name='avance_excel_pct')                                           AS columna_excel_ok,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_ot_avance_eventos')          AS tabla_eventos_ok,
        (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_avance_eventos')           AS rls_eventos,
        (to_regprocedure('public.fn_calama_aplicar_avance_interno(uuid,numeric,text,text,text,uuid,uuid)') IS NOT NULL) AS helper_ok,
        (to_regprocedure('public.rpc_calama_actualizar_avance_ot(jsonb)') IS NOT NULL)          AS rpc_actualizar_ok,
        (to_regprocedure('public.rpc_calama_marcar_ot_completada_operador(jsonb)') IS NOT NULL) AS rpc_completar_ok,
        (to_regprocedure('public.rpc_calama_registrar_avance_operador(jsonb)') IS NOT NULL)     AS rpc_avance_op_ok,
        (to_regprocedure('public.rpc_calama_set_avance_excel_lote(jsonb)') IS NOT NULL)         AS rpc_excel_lote_ok,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_avance_por_area')          AS vista_area_ok,
        EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema='public' AND table_name='v_calama_resumen_general')          AS vista_general_ok
),
faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT columna_excel_ok    THEN 'calama_ordenes_trabajo.avance_excel_pct' END,
        CASE WHEN NOT tabla_eventos_ok    THEN 'calama_ot_avance_eventos' END,
        CASE WHEN NOT COALESCE(rls_eventos,false) THEN 'RLS calama_ot_avance_eventos' END,
        CASE WHEN NOT helper_ok           THEN 'fn_calama_aplicar_avance_interno' END,
        CASE WHEN NOT rpc_actualizar_ok   THEN 'rpc_calama_actualizar_avance_ot' END,
        CASE WHEN NOT rpc_completar_ok    THEN 'rpc_calama_marcar_ot_completada_operador' END,
        CASE WHEN NOT rpc_avance_op_ok    THEN 'rpc_calama_registrar_avance_operador' END,
        CASE WHEN NOT rpc_excel_lote_ok   THEN 'rpc_calama_set_avance_excel_lote' END,
        CASE WHEN NOT vista_area_ok       THEN 'v_calama_avance_por_area' END,
        CASE WHEN NOT vista_general_ok    THEN 'v_calama_resumen_general' END
    ]::text[], NULL) AS objetos_faltantes
    FROM checks
)
SELECT
    CASE
        WHEN cardinality(objetos_faltantes) = 0
            THEN 'OK_OPERACION_CALAMA_AVANCE_REAL'
        ELSE 'STOP_OPERACION_CALAMA_AVANCE_REAL'
    END AS resultado,
    COALESCE(NULLIF(array_to_string(objetos_faltantes, ', '), ''),
             '1 columna + 1 tabla eventos + 1 helper + 4 RPCs + 2 vistas.') AS detalle,
    cardinality(objetos_faltantes) AS faltantes_count,
    NOW() AS chequeado_en
FROM faltantes;
