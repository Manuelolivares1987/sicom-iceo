-- ============================================================================
-- 42_calama_modo_prueba_sandbox.sql
-- ----------------------------------------------------------------------------
-- Sandbox formal para jornadas de prueba de terreno Calama (FASES 1+2+3).
-- ADITIVA. IDEMPOTENTE.
--
-- Crea:
--   1. Columnas es_prueba / excluida_estadisticas / motivo_prueba en 5 tablas
--      (es_prueba ya existia en calama_plan_semanal_ots desde MIG32).
--   2. Indices parciales para queries rapidas de pruebas.
--   3. RPC rpc_calama_crear_jornada_prueba_terreno(p_payload jsonb).
--   4. Re-crea v_calama_resumen_general y v_calama_avance_por_area con
--      filtro de pruebas (excluye es_prueba/excluida_estadisticas).
--   5. Vista v_calama_pruebas_terreno (admin: ver pruebas en curso).
--
-- NO toca: avances reales, OTs reales, estadisticas reales, evidencias
-- reales. Las columnas nuevas tienen DEFAULT false, asi que registros
-- existentes quedan como "produccion".
-- ============================================================================


-- ── BLOQUE 0: PRECHECKS ────────────────────────────────────────────────────
DO $$
DECLARE v_rol TEXT;
BEGIN
    -- MIG33 requerida (RPCs PRO terreno presentes)
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_calama_finalizar_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG33 no aplicada (rpc_calama_finalizar_jornada falta)';
    END IF;
    -- MIG35 requerida (vistas avance por conteo)
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_calama_resumen_general') THEN
        RAISE EXCEPTION 'STOP - v_calama_resumen_general no existe (MIG21/34/35)';
    END IF;
    -- es_prueba ya en plan_semanal_ots (MIG32)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='calama_plan_semanal_ots'
                      AND column_name='es_prueba') THEN
        RAISE EXCEPTION 'STOP - es_prueba en calama_plan_semanal_ots no existe (MIG32 no aplicada)';
    END IF;

    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN
        RAISE NOTICE 'Aplicando MIG42 como rol de sistema (current_user=%). OK.', current_user;
    ELSIF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar MIG42 desde sesion autenticada requiere administrador';
    END IF;
    RAISE NOTICE '== MIG42 prechecks OK ==';
END $$;


-- ============================================================================
-- BLOQUE 1: ALTERs (columnas nuevas, defaults false, no toca datos)
-- ============================================================================

-- calama_ordenes_trabajo
ALTER TABLE calama_ordenes_trabajo ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE calama_ordenes_trabajo ADD COLUMN IF NOT EXISTS excluida_estadisticas BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE calama_ordenes_trabajo ADD COLUMN IF NOT EXISTS motivo_prueba TEXT;

-- calama_plan_semanal_ots (es_prueba ya en MIG32)
ALTER TABLE calama_plan_semanal_ots ADD COLUMN IF NOT EXISTS excluida_estadisticas BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE calama_plan_semanal_ots ADD COLUMN IF NOT EXISTS motivo_prueba TEXT;

-- calama_ot_ejecuciones
ALTER TABLE calama_ot_ejecuciones ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;

-- calama_ot_ejecucion_eventos
ALTER TABLE calama_ot_ejecucion_eventos ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;

-- calama_evidencias
ALTER TABLE calama_evidencias ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;

-- calama_firmas_jornada
ALTER TABLE calama_firmas_jornada ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;


-- ── Indices parciales para queries de pruebas ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_cot_es_prueba           ON calama_ordenes_trabajo (es_prueba) WHERE es_prueba = TRUE;
CREATE INDEX IF NOT EXISTS idx_cot_excluida            ON calama_ordenes_trabajo (excluida_estadisticas) WHERE excluida_estadisticas = TRUE;
CREATE INDEX IF NOT EXISTS idx_cpsots_es_prueba_v2     ON calama_plan_semanal_ots (es_prueba) WHERE es_prueba = TRUE;
CREATE INDEX IF NOT EXISTS idx_cejec_es_prueba         ON calama_ot_ejecuciones (es_prueba) WHERE es_prueba = TRUE;
CREATE INDEX IF NOT EXISTS idx_cejecev_es_prueba       ON calama_ot_ejecucion_eventos (es_prueba) WHERE es_prueba = TRUE;
CREATE INDEX IF NOT EXISTS idx_cevid_es_prueba         ON calama_evidencias (es_prueba) WHERE es_prueba = TRUE;
CREATE INDEX IF NOT EXISTS idx_cfirma_es_prueba        ON calama_firmas_jornada (es_prueba) WHERE es_prueba = TRUE;


-- ============================================================================
-- BLOQUE 2: RPC rpc_calama_crear_jornada_prueba_terreno
-- Crea OT + zona + plan semanal + plan dia + plan_semanal_ots de prueba.
-- Todo marcado es_prueba=true, excluida_estadisticas=true.
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_calama_crear_jornada_prueba_terreno(
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id        UUID := auth.uid();
    v_rol            TEXT;
    v_planificacion_id UUID;
    v_faena_id       UUID;
    v_responsable_id UUID;
    v_fecha_jornada  DATE;
    v_zona_id        UUID;
    v_ot_id          UUID;
    v_folio          VARCHAR;
    v_plan_semanal_id UUID;
    v_plan_dia_id    UUID;
    v_plan_ot_id     UUID;
    v_fecha_inicio_sem DATE;
    v_fecha_fin_sem  DATE;
    v_oocc_email     TEXT;
    v_nombre_dia     VARCHAR;
    v_orden_dia      INT;
BEGIN
    -- Auth + rol
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para crear jornada de prueba', v_rol;
    END IF;

    -- Inputs (con defaults razonables)
    v_planificacion_id := NULLIF(p_payload->>'planificacion_id', '')::UUID;
    v_faena_id         := NULLIF(p_payload->>'faena_id', '')::UUID;
    v_responsable_id   := NULLIF(p_payload->>'responsable_id', '')::UUID;
    v_fecha_jornada    := COALESCE(NULLIF(p_payload->>'fecha_jornada','')::DATE, CURRENT_DATE);

    -- Si no se paso planificacion, usar la primera activa
    IF v_planificacion_id IS NULL THEN
        SELECT id INTO v_planificacion_id FROM calama_planificaciones
         WHERE estado <> 'cancelada' ORDER BY created_at DESC LIMIT 1;
        IF v_planificacion_id IS NULL THEN
            RAISE EXCEPTION 'No hay planificacion Calama disponible. Pasar planificacion_id en p_payload.';
        END IF;
    END IF;

    -- Si no se paso faena, usar la primera disponible
    IF v_faena_id IS NULL THEN
        SELECT id INTO v_faena_id FROM calama_faenas
         WHERE COALESCE(activa, true) = true ORDER BY created_at LIMIT 1;
        IF v_faena_id IS NULL THEN
            RAISE EXCEPTION 'No hay faena Calama disponible. Pasar faena_id en p_payload.';
        END IF;
    END IF;

    -- Si no se paso responsable, intentar oocc@pillado.cl
    IF v_responsable_id IS NULL THEN
        SELECT up.id INTO v_responsable_id
          FROM usuarios_perfil up
         WHERE up.email = 'oocc@pillado.cl' AND up.activo = true
         LIMIT 1;
        IF v_responsable_id IS NULL THEN
            RAISE EXCEPTION 'No hay responsable: pasar responsable_id en p_payload (o crear oocc@pillado.cl)';
        END IF;
    END IF;

    -- ─ ZONA TEST: crear si no existe en esa planificacion ─
    SELECT id INTO v_zona_id FROM calama_zonas_proyecto
     WHERE planificacion_id = v_planificacion_id AND codigo_zona = 'TEST'
     LIMIT 1;
    IF v_zona_id IS NULL THEN
        INSERT INTO calama_zonas_proyecto (
            planificacion_id, codigo_zona, nombre, descripcion, cliente_uuid
        ) VALUES (
            v_planificacion_id, 'TEST', 'Zona de Pruebas Terreno',
            'Zona dedicada a pruebas de la app de terreno. NO mezclar con OTs reales.',
            md5(v_planificacion_id::text || ':TEST')::uuid
        )
        RETURNING id INTO v_zona_id;
    END IF;

    -- ─ OT TEST: folio unico por corrida ─
    v_folio := 'TEST-TERRENO-' || TO_CHAR(NOW(), 'YYYYMMDDHH24MISS');
    v_ot_id := gen_random_uuid();
    INSERT INTO calama_ordenes_trabajo (
        id, folio, planificacion_id, faena_calama_id,
        titulo, descripcion, fecha_programada,
        avance_pct, estado, prioridad, responsable_id,
        observaciones_apertura,
        es_prueba, excluida_estadisticas, motivo_prueba,
        created_by, cliente_uuid
    ) VALUES (
        v_ot_id, v_folio, v_planificacion_id, v_faena_id,
        'Prueba app terreno (' || v_folio || ')',
        'OT generada por sandbox MIG42 para validar fotos, offline, GPS, pausa, firma y cierre. NO afecta estadisticas reales.',
        v_fecha_jornada,
        0, 'liberada', 'baja', v_responsable_id,
        'Sandbox de pruebas terreno. Reset/anular cuando quieras.',
        true, true,
        'Sandbox app terreno (MIG42)',
        v_user_id, gen_random_uuid()
    );

    -- ─ Marcar precheck como liberado para que la jornada sea ejecutable ─
    INSERT INTO calama_ot_precheck (
        ot_id, epp_completo, herramientas_ok, vehiculo_confirmado,
        charla_ods_realizada, permisos_trabajo_ok,
        observaciones, revisado_por, revisado_at
    ) VALUES (
        v_ot_id, true, true, true, true, true,
        'Precheck OK por sandbox de pruebas', v_user_id, NOW()
    ) ON CONFLICT (ot_id) DO NOTHING;

    -- ─ PLAN SEMANAL: reusar el de la semana de la fecha_jornada ─
    -- Semana lunes-domingo (CL)
    v_fecha_inicio_sem := v_fecha_jornada - ((EXTRACT(ISODOW FROM v_fecha_jornada)::int - 1));
    v_fecha_fin_sem    := v_fecha_inicio_sem + 6;

    SELECT id INTO v_plan_semanal_id FROM calama_planes_semanales
     WHERE planificacion_id = v_planificacion_id
       AND fecha_inicio_semana = v_fecha_inicio_sem
     LIMIT 1;
    IF v_plan_semanal_id IS NULL THEN
        INSERT INTO calama_planes_semanales (
            planificacion_id, faena_calama_id,
            fecha_inicio_semana, fecha_fin_semana,
            estado, creado_por, observaciones
        ) VALUES (
            v_planificacion_id, v_faena_id,
            v_fecha_inicio_sem, v_fecha_fin_sem,
            'confirmado', v_user_id,
            'Plan semanal sandbox MIG42'
        )
        RETURNING id INTO v_plan_semanal_id;
    END IF;

    -- ─ PLAN DIA: reusar el de la fecha ─
    SELECT id INTO v_plan_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_semanal_id AND fecha = v_fecha_jornada
     LIMIT 1;
    IF v_plan_dia_id IS NULL THEN
        v_orden_dia := EXTRACT(ISODOW FROM v_fecha_jornada)::int;
        v_nombre_dia := CASE v_orden_dia
            WHEN 1 THEN 'Lunes'   WHEN 2 THEN 'Martes'    WHEN 3 THEN 'Miercoles'
            WHEN 4 THEN 'Jueves'  WHEN 5 THEN 'Viernes'   WHEN 6 THEN 'Sabado'
            WHEN 7 THEN 'Domingo' ELSE 'Dia' END;
        INSERT INTO calama_plan_semanal_dias (
            plan_semanal_id, fecha, nombre_dia, orden, estado, observaciones
        ) VALUES (
            v_plan_semanal_id, v_fecha_jornada, v_nombre_dia, v_orden_dia,
            'confirmado', 'Dia sandbox MIG42'
        )
        RETURNING id INTO v_plan_dia_id;
    END IF;

    -- ─ PLAN_SEMANAL_OTS: la jornada de prueba ─
    INSERT INTO calama_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id,
        responsable_id, prioridad, estado_plan,
        observaciones, created_by,
        es_prueba, excluida_estadisticas, motivo_prueba
    ) VALUES (
        v_plan_semanal_id, v_plan_dia_id, v_ot_id, v_zona_id,
        v_responsable_id, 0, 'liberada',
        'Jornada sandbox MIG42 — fotos, pausa, firma, offline.',
        v_user_id,
        true, true,
        'Sandbox app terreno (MIG42)'
    )
    RETURNING id INTO v_plan_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'ot_id', v_ot_id,
        'folio', v_folio,
        'plan_semanal_ot_id', v_plan_ot_id,
        'plan_semanal_id', v_plan_semanal_id,
        'plan_dia_id', v_plan_dia_id,
        'fecha_jornada', v_fecha_jornada,
        'responsable_id', v_responsable_id,
        'zona_id', v_zona_id,
        'planificacion_id', v_planificacion_id,
        'url_mobile', '/m/calama/ot/' || v_ot_id::text,
        'mensaje', 'Jornada de prueba creada. Esta OT es_prueba=true y NO afecta estadisticas reales.'
    );
END;
$$;

COMMENT ON FUNCTION rpc_calama_crear_jornada_prueba_terreno IS
'Crea OT/jornada de prueba en zona TEST de una planificacion. Todo marcado es_prueba=true, excluida_estadisticas=true. NO contamina reportes. MIG42.';

GRANT EXECUTE ON FUNCTION rpc_calama_crear_jornada_prueba_terreno TO authenticated;


-- ============================================================================
-- BLOQUE 3: Re-crear vistas criticas con filtro de pruebas
-- (mantiene la logica MIG35 + WHERE es_prueba/excluida_estadisticas=false)
-- ============================================================================

-- ── v_calama_avance_por_area ───────────────────────────────────────────────
DROP VIEW IF EXISTS public.v_calama_avance_por_area CASCADE;
CREATE VIEW v_calama_avance_por_area AS
WITH ot_zona AS (
    SELECT
        o.id, o.planificacion_id, o.estado, o.avance_pct, o.fecha_programada,
        o.observaciones_apertura, o.observaciones_cierre,
        fn_calama_zona_codigo_de_folio(o.folio) AS codigo_zona
    FROM calama_ordenes_trabajo o
    WHERE COALESCE(o.es_prueba, false) = false
      AND COALESCE(o.excluida_estadisticas, false) = false
),
plan_ots_resumen AS (
    SELECT
        po.plan_semanal_id, po.ot_id, po.responsable_id, po.estado_plan,
        po.observaciones, po.plan_dia_id,
        ps.planificacion_id
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
    WHERE COALESCE(po.visible_en_kanban, true) = true
      AND po.desprogramada_at IS NULL
      AND po.anulada_at IS NULL
      AND COALESCE(po.es_prueba, false) = false
      AND COALESCE(po.excluida_estadisticas, false) = false
)
SELECT
    p.id                                                    AS planificacion_id,
    p.codigo                                                AS planificacion_codigo,
    z.codigo_zona,
    z.nombre                                                AS lugar_fisico_nombre,
    z.id                                                    AS zona_proyecto_id,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada')      AS total_tareas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                            AS tareas_finalizadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                            AS tareas_en_ejecucion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                            AS tareas_pendientes,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'no_ejecutada')    AS tareas_no_ejecutadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')
                                                            AS tareas_pendiente_aprobacion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'parcial') AS tareas_parciales,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'requiere_correccion')
                                                            AS tareas_requiere_correccion,
    COUNT(DISTINCT po.ot_id)                                AS tareas_planificadas_semana,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                            AS tareas_sin_responsable,
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                        AS tareas_con_comentario,

    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                            AS avance_promedio_pct,

    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_completitud_pct,

    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (
                WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                   'en_ejecucion','en_pausa','parcial',
                                   'pendiente_aprobacion','requiere_correccion')
            )::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_real_pct,

    ROUND(
        COALESCE(
            (
                COUNT(DISTINCT o.id) FILTER (
                    WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                       'en_ejecucion','en_pausa','parcial',
                                       'pendiente_aprobacion','requiere_correccion')
                )::numeric
                + COUNT(DISTINCT po.ot_id) FILTER (
                    WHERE po.ot_id IS NOT NULL
                      AND o.estado NOT IN ('finalizada','aceptada','cerrada',
                                           'en_ejecucion','en_pausa','parcial',
                                           'pendiente_aprobacion','requiere_correccion','cancelada')
                )::numeric
            ) * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                        AS avance_proyectado_pct
FROM calama_zonas_proyecto z
JOIN calama_planificaciones p ON p.id = z.planificacion_id
LEFT JOIN ot_zona o ON o.planificacion_id = p.id AND o.codigo_zona = z.codigo_zona
LEFT JOIN plan_ots_resumen po ON po.ot_id = o.id AND po.planificacion_id = p.id
WHERE z.codigo_zona <> 'TEST'   -- zona TEST nunca aparece en avance real
GROUP BY p.id, p.codigo, z.id, z.codigo_zona, z.nombre
ORDER BY p.codigo, z.codigo_zona;

GRANT SELECT ON v_calama_avance_por_area TO authenticated;
COMMENT ON VIEW v_calama_avance_por_area IS
    'MIG42: avance por area excluyendo OTs/jornadas/zonas de prueba.';


-- ── v_calama_resumen_general ───────────────────────────────────────────────
DROP VIEW IF EXISTS public.v_calama_resumen_general CASCADE;
CREATE VIEW v_calama_resumen_general AS
WITH ots AS (
    SELECT
        o.planificacion_id, o.id, o.estado, o.avance_pct,
        o.observaciones_apertura, o.observaciones_cierre
    FROM calama_ordenes_trabajo o
    WHERE COALESCE(o.es_prueba, false) = false
      AND COALESCE(o.excluida_estadisticas, false) = false
),
plan_ots AS (
    SELECT
        ps.planificacion_id, po.ot_id, po.responsable_id,
        po.observaciones, po.estado_plan
    FROM calama_plan_semanal_ots po
    JOIN calama_planes_semanales ps ON ps.id = po.plan_semanal_id
    WHERE COALESCE(po.visible_en_kanban, true) = true
      AND po.desprogramada_at IS NULL
      AND po.anulada_at IS NULL
      AND COALESCE(po.es_prueba, false) = false
      AND COALESCE(po.excluida_estadisticas, false) = false
),
zonas AS (
    SELECT planificacion_id, COUNT(*)::int AS total_zonas
    FROM calama_zonas_proyecto
    WHERE codigo_zona <> 'TEST'
    GROUP BY planificacion_id
)
SELECT
    p.id                                              AS planificacion_id,
    p.codigo                                          AS planificacion_codigo,
    p.nombre                                          AS planificacion_nombre,
    p.linea_negocio,
    p.estado                                          AS estado_planificacion,
    COALESCE(z.total_zonas, 0)                        AS total_lugares_fisicos,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada')  AS total_tareas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'cancelada')   AS tareas_canceladas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))
                                                                  AS tareas_finalizadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('en_ejecucion','en_pausa','parcial','pendiente_aprobacion','requiere_correccion'))
                                                                  AS tareas_en_ejecucion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('planificada','liberada'))
                                                                  AS tareas_pendientes,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'no_ejecutada') AS tareas_no_ejecutadas,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'pendiente_aprobacion')  AS tareas_pendiente_aprobacion,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'parcial')      AS tareas_parciales,
    COUNT(DISTINCT o.id) FILTER (WHERE o.estado = 'requiere_correccion')   AS tareas_requiere_correccion,
    COUNT(DISTINCT po.ot_id)                                       AS tareas_planificadas_semanas,
    COUNT(DISTINCT po.ot_id) FILTER (WHERE po.responsable_id IS NULL)
                                                                  AS tareas_sin_responsable,
    COUNT(DISTINCT o.id) FILTER (
        WHERE (po.observaciones IS NOT NULL AND po.observaciones <> '')
           OR (o.observaciones_apertura IS NOT NULL AND o.observaciones_apertura <> '')
           OR (o.observaciones_cierre   IS NOT NULL AND o.observaciones_cierre   <> '')
    )                                                              AS tareas_con_comentario,

    ROUND(COALESCE(AVG(o.avance_pct) FILTER (WHERE o.estado <> 'cancelada'), 0)::numeric, 1)
                                                                  AS avance_promedio_pct,

    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (WHERE o.estado IN ('finalizada','aceptada','cerrada'))::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_completitud_pct,

    ROUND(
        COALESCE(
            COUNT(DISTINCT o.id) FILTER (
                WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                   'en_ejecucion','en_pausa','parcial',
                                   'pendiente_aprobacion','requiere_correccion')
            )::numeric * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_real_pct,

    ROUND(
        COALESCE(
            (
                COUNT(DISTINCT o.id) FILTER (
                    WHERE o.estado IN ('finalizada','aceptada','cerrada',
                                       'en_ejecucion','en_pausa','parcial',
                                       'pendiente_aprobacion','requiere_correccion')
                )::numeric
                + COUNT(DISTINCT po.ot_id) FILTER (
                    WHERE po.ot_id IS NOT NULL
                      AND o.estado NOT IN ('finalizada','aceptada','cerrada',
                                           'en_ejecucion','en_pausa','parcial',
                                           'pendiente_aprobacion','requiere_correccion','cancelada')
                )::numeric
            ) * 100
            / NULLIF(COUNT(DISTINCT o.id) FILTER (WHERE o.estado <> 'cancelada'), 0)
        , 0)::numeric, 1
    )                                                              AS avance_proyectado_pct
FROM calama_planificaciones p
LEFT JOIN zonas    z ON z.planificacion_id = p.id
LEFT JOIN ots      o ON o.planificacion_id = p.id
LEFT JOIN plan_ots po ON po.planificacion_id = p.id AND po.ot_id = o.id
GROUP BY p.id, p.codigo, p.nombre, p.linea_negocio, p.estado, z.total_zonas
ORDER BY p.codigo;

GRANT SELECT ON v_calama_resumen_general TO authenticated;
COMMENT ON VIEW v_calama_resumen_general IS
    'MIG42: resumen general excluyendo OTs/jornadas/zonas de prueba.';


-- ============================================================================
-- BLOQUE 4: Vista admin para ver pruebas
-- ============================================================================
DROP VIEW IF EXISTS public.v_calama_pruebas_terreno CASCADE;
CREATE VIEW v_calama_pruebas_terreno AS
SELECT
    o.id                            AS ot_id,
    o.folio,
    o.titulo,
    o.estado                        AS ot_estado,
    o.avance_pct,
    o.fecha_programada,
    o.responsable_id,
    up.nombre_completo              AS responsable_nombre,
    up.email                        AS responsable_email,
    po.id                           AS plan_semanal_ot_id,
    po.estado_plan,
    po.llegada_faena_at,
    po.cierre_jornada_at,
    o.created_at,
    o.motivo_prueba,
    p.codigo                        AS planificacion_codigo,
    f.nombre                        AS faena_nombre,
    (SELECT COUNT(*) FROM calama_evidencias e
       WHERE e.ot_id = o.id AND COALESCE(e.es_prueba, true) = true)         AS evidencias_count,
    (SELECT COUNT(*) FROM calama_ot_ejecucion_eventos ev
       WHERE ev.ot_id = o.id AND COALESCE(ev.es_prueba, true) = true)       AS eventos_count,
    (SELECT COUNT(*) FROM calama_firmas_jornada fi
       WHERE fi.plan_semanal_ot_id = po.id AND COALESCE(fi.es_prueba, true) = true) AS firmas_count
FROM calama_ordenes_trabajo o
LEFT JOIN calama_plan_semanal_ots po ON po.ot_id = o.id
LEFT JOIN usuarios_perfil up ON up.id = o.responsable_id
LEFT JOIN calama_planificaciones p ON p.id = o.planificacion_id
LEFT JOIN calama_faenas f ON f.id = o.faena_calama_id
WHERE o.es_prueba = TRUE
ORDER BY o.created_at DESC;

GRANT SELECT ON v_calama_pruebas_terreno TO authenticated;
COMMENT ON VIEW v_calama_pruebas_terreno IS
    'Listado de OTs marcadas es_prueba=true con metadata para la pantalla admin /dashboard/operacion-calama/pruebas. MIG42.';


-- ============================================================================
-- BLOQUE 5: Validaciones post
-- ============================================================================
DO $$
DECLARE
    v_n_cols INT;
    v_rpc    INT;
    v_vistas INT;
BEGIN
    -- Columnas en las 5 tablas (es_prueba al menos)
    SELECT COUNT(*) INTO v_n_cols FROM information_schema.columns
     WHERE table_schema='public' AND column_name='es_prueba'
       AND table_name IN ('calama_ordenes_trabajo','calama_plan_semanal_ots',
                          'calama_ot_ejecuciones','calama_ot_ejecucion_eventos',
                          'calama_evidencias','calama_firmas_jornada');
    IF v_n_cols <> 6 THEN
        RAISE EXCEPTION 'STOP - es_prueba esta en % tablas, esperaba 6', v_n_cols;
    END IF;

    SELECT COUNT(*) INTO v_rpc FROM pg_proc
     WHERE proname='rpc_calama_crear_jornada_prueba_terreno';
    IF v_rpc <> 1 THEN
        RAISE EXCEPTION 'STOP - RPC rpc_calama_crear_jornada_prueba_terreno no creada';
    END IF;

    SELECT COUNT(*) INTO v_vistas FROM pg_views
     WHERE schemaname='public'
       AND viewname IN ('v_calama_avance_por_area','v_calama_resumen_general','v_calama_pruebas_terreno');
    IF v_vistas <> 3 THEN
        RAISE EXCEPTION 'STOP - faltan vistas: encontradas %', v_vistas;
    END IF;

    RAISE NOTICE '== MIG42 aplicada OK ==';
    RAISE NOTICE '   es_prueba en 6 tablas';
    RAISE NOTICE '   RPC crear jornada prueba creada';
    RAISE NOTICE '   3 vistas (avance/resumen filtran pruebas, v_calama_pruebas_terreno lista pruebas)';
END $$;


-- Resultset visible
SELECT 'col_es_prueba_calama_ordenes_trabajo'    AS dx,
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_ordenes_trabajo' AND column_name='es_prueba') AS val
UNION ALL SELECT 'col_excluida_estadisticas_ot',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_ordenes_trabajo' AND column_name='excluida_estadisticas')
UNION ALL SELECT 'col_es_prueba_evidencias',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_evidencias' AND column_name='es_prueba')
UNION ALL SELECT 'col_es_prueba_firmas',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_firmas_jornada' AND column_name='es_prueba')
UNION ALL SELECT 'col_es_prueba_ejecuciones',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_ot_ejecuciones' AND column_name='es_prueba')
UNION ALL SELECT 'col_es_prueba_eventos',
       (SELECT COUNT(*)::text FROM information_schema.columns
         WHERE table_name='calama_ot_ejecucion_eventos' AND column_name='es_prueba')
UNION ALL SELECT 'rpc_crear_jornada_prueba',
       (SELECT COUNT(*)::text FROM pg_proc WHERE proname='rpc_calama_crear_jornada_prueba_terreno')
UNION ALL SELECT 'v_calama_resumen_general',
       (SELECT COUNT(*)::text FROM pg_views WHERE viewname='v_calama_resumen_general')
UNION ALL SELECT 'v_calama_avance_por_area',
       (SELECT COUNT(*)::text FROM pg_views WHERE viewname='v_calama_avance_por_area')
UNION ALL SELECT 'v_calama_pruebas_terreno',
       (SELECT COUNT(*)::text FROM pg_views WHERE viewname='v_calama_pruebas_terreno');


-- Log
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG42_END',
            'MIG42 sandbox terreno Calama (es_prueba + RPC + vistas filtradas)',
            'ok',
            'UI admin pendiente en /dashboard/operacion-calama/pruebas'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK MANUAL
--   DROP VIEW v_calama_pruebas_terreno;
--   -- restaurar versiones mig35 de v_calama_avance_por_area / v_calama_resumen_general
--   --   ejecutar 35_calama_resumen_avance_por_conteo.sql nuevamente
--   DROP FUNCTION rpc_calama_crear_jornada_prueba_terreno(JSONB);
--   ALTER TABLE calama_ordenes_trabajo
--     DROP COLUMN es_prueba, DROP COLUMN excluida_estadisticas, DROP COLUMN motivo_prueba;
--   ALTER TABLE calama_plan_semanal_ots
--     DROP COLUMN excluida_estadisticas, DROP COLUMN motivo_prueba;
--     -- es_prueba NO se borra (es de MIG32).
--   ALTER TABLE calama_evidencias            DROP COLUMN es_prueba;
--   ALTER TABLE calama_ot_ejecuciones        DROP COLUMN es_prueba;
--   ALTER TABLE calama_ot_ejecucion_eventos  DROP COLUMN es_prueba;
--   ALTER TABLE calama_firmas_jornada        DROP COLUMN es_prueba;
-- ============================================================================
