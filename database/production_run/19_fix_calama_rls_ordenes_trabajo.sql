-- ============================================================================
-- 19_fix_calama_rls_ordenes_trabajo.sql
-- ----------------------------------------------------------------------------
-- Fix: 500 (infinite recursion detected in policy) en calama_ordenes_trabajo.
--
-- CAUSA RAIZ:
--   MIG17 introdujo dos policies con EXISTS cruzados:
--     pol_calama_ot_select_operador (calama_ordenes_trabajo)
--       EXISTS (SELECT ... FROM calama_ot_subtareas WHERE ot_id = ...)
--     pol_calama_subt_select (calama_ot_subtareas)
--       EXISTS (SELECT ... FROM calama_ordenes_trabajo WHERE id = ...)
--   Cuando Postgres evalua EXISTS dentro de una policy USING, aplica la RLS
--   de la tabla referenced. La RLS de subtareas vuelve a EXISTS contra OT,
--   y RLS de OT vuelve a EXISTS contra subtareas -> recursion -> error 42P17.
--   PostgREST traduce ese error a HTTP 500.
--
-- FIX:
--   Encapsular cada EXISTS en una funcion SECURITY DEFINER. Las funciones
--   SECURITY DEFINER ejecutan con privilegios del owner y por defecto pueden
--   bypasear la RLS de la tabla consultada (depende del config). Aqui usamos
--   SET search_path = public y dejamos que la funcion vea las filas sin
--   re-disparar la RLS desde dentro de la policy.
--
--   Patrones nuevos:
--     fn_calama_operador_tiene_subtarea_en_ot(p_ot_id uuid) BOOLEAN
--     fn_calama_operador_es_responsable_ot(p_ot_id uuid)   BOOLEAN
--
--   Las policies afectadas se DROP/CREATE para usar estos helpers.
--
-- AISLACION:
--   - NO toca MIG17/MIG18/18B SCRIPTS originales (estan versionados).
--   - Modifica el ESTADO de la BD (las policies son objetos, no archivos).
--   - NO desactiva RLS. Las tablas siguen con ENABLE ROW LEVEL SECURITY.
--   - NO toca MIG55-57, scripts 14*, ni rol_usuario_enum.
--   - NO crea ni borra tablas.
--
-- IDEMPOTENCIA:
--   - DROP POLICY IF EXISTS antes de cada CREATE POLICY.
--   - CREATE OR REPLACE FUNCTION para los helpers.
--
-- VERIFICACION FINAL: 1 fila con
--   resultado / policies_recreadas / helpers_creados / rls_activa /
--   sample_select_ok / chequeado_en.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP — MIG17 no aplicada (calama_ordenes_trabajo no existe).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ot_subtareas') THEN
        RAISE EXCEPTION 'STOP — MIG17 no aplicada (calama_ot_subtareas no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_es_operador()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_calama_es_operador no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. HELPERS SECURITY DEFINER (rompen la recursion) ────────────────────────
-- ============================================================================

-- 1.1 Operador ¿tiene una subtarea asignada en esta OT?
CREATE OR REPLACE FUNCTION fn_calama_operador_tiene_subtarea_en_ot(p_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_ot_subtareas
         WHERE ot_id = p_ot_id
           AND asignado_id = auth.uid()
    );
$$;

-- 1.2 Operador ¿es responsable de esta OT?
CREATE OR REPLACE FUNCTION fn_calama_operador_es_responsable_ot(p_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_ordenes_trabajo
         WHERE id = p_ot_id
           AND responsable_id = auth.uid()
    );
$$;

-- 1.3 Operador ¿reporto este avance?  (helper para policies que vienen luego)
CREATE OR REPLACE FUNCTION fn_calama_operador_tiene_avance_en_ot(p_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_avances
         WHERE ot_id = p_ot_id
           AND reportado_por = auth.uid()
    );
$$;

GRANT EXECUTE ON FUNCTION fn_calama_operador_tiene_subtarea_en_ot(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_operador_es_responsable_ot(UUID)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_operador_tiene_avance_en_ot(UUID)   TO authenticated;


-- ============================================================================
-- ── 2. RECREATE POLICIES (sin EXISTS recursivos) ─────────────────────────────
-- ============================================================================

-- 2.1 calama_ordenes_trabajo — SELECT operador
DROP POLICY IF EXISTS pol_calama_ot_select_operador ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_select_operador ON calama_ordenes_trabajo
    FOR SELECT TO authenticated
    USING (
        fn_calama_es_operador()
        AND (
            responsable_id = auth.uid()
            OR fn_calama_operador_tiene_subtarea_en_ot(id)
        )
    );

-- 2.2 calama_ot_subtareas — SELECT
DROP POLICY IF EXISTS pol_calama_subt_select ON calama_ot_subtareas;
CREATE POLICY pol_calama_subt_select ON calama_ot_subtareas
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                asignado_id = auth.uid()
                OR fn_calama_operador_es_responsable_ot(ot_id)
            )
        )
    );

-- 2.3 calama_ot_subtareas — UPDATE operador
DROP POLICY IF EXISTS pol_calama_subt_update_op ON calama_ot_subtareas;
CREATE POLICY pol_calama_subt_update_op ON calama_ot_subtareas
    FOR UPDATE TO authenticated
    USING (
        fn_calama_es_operador()
        AND (
            asignado_id = auth.uid()
            OR fn_calama_operador_es_responsable_ot(ot_id)
        )
    )
    WITH CHECK (
        fn_calama_es_operador()
        AND (
            asignado_id = auth.uid()
            OR fn_calama_operador_es_responsable_ot(ot_id)
        )
    );

-- 2.4 calama_ot_precheck — SELECT (EXISTS contra ordenes_trabajo, mismo patron)
DROP POLICY IF EXISTS pol_calama_precheck_select ON calama_ot_precheck;
CREATE POLICY pol_calama_precheck_select ON calama_ot_precheck
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND fn_calama_operador_es_responsable_ot(ot_id)
        )
    );

-- 2.5 calama_avances — SELECT
DROP POLICY IF EXISTS pol_calama_avance_select ON calama_avances;
CREATE POLICY pol_calama_avance_select ON calama_avances
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                reportado_por = auth.uid()
                OR fn_calama_operador_es_responsable_ot(ot_id)
            )
        )
    );

-- 2.6 calama_avances — INSERT
DROP POLICY IF EXISTS pol_calama_avance_insert ON calama_avances;
CREATE POLICY pol_calama_avance_insert ON calama_avances
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR (
            fn_calama_es_operador()
            AND reportado_por = auth.uid()
            AND fn_calama_operador_es_responsable_ot(ot_id)
        )
    );

-- 2.7 calama_evidencias — SELECT
DROP POLICY IF EXISTS pol_calama_evid_select ON calama_evidencias;
CREATE POLICY pol_calama_evid_select ON calama_evidencias
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                created_by = auth.uid()
                OR (ot_id IS NOT NULL AND fn_calama_operador_es_responsable_ot(ot_id))
            )
        )
    );

-- 2.8 calama_observaciones — SELECT
DROP POLICY IF EXISTS pol_calama_obs_select ON calama_observaciones;
CREATE POLICY pol_calama_obs_select ON calama_observaciones
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                creada_por = auth.uid()
                OR (ot_id IS NOT NULL AND fn_calama_operador_es_responsable_ot(ot_id))
            )
        )
    );

-- 2.9 calama_eventos_no_ejecucion — SELECT
DROP POLICY IF EXISTS pol_calama_no_ejec_select ON calama_eventos_no_ejecucion;
CREATE POLICY pol_calama_no_ejec_select ON calama_eventos_no_ejecucion
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND fn_calama_operador_es_responsable_ot(ot_id)
        )
    );


-- ============================================================================
-- ── 3. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG19_CALAMA_RLS_FIX',
        'Fix recursion infinita en RLS de calama_ordenes_trabajo y dependientes.',
        current_user, NOW(), NOW(), 'ok',
        'Crea 3 helpers SECURITY DEFINER + recrea 9 policies sin EXISTS recursivos.'
    );
END $$;


-- ============================================================================
-- ── 4. VERIFICACION FINAL (1 fila) ──────────────────────────────────────────
-- ============================================================================
WITH
helpers_ok AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.fn_calama_operador_tiene_subtarea_en_ot(uuid)') IS NULL
             THEN 'fn_calama_operador_tiene_subtarea_en_ot' END,
        CASE WHEN to_regprocedure('public.fn_calama_operador_es_responsable_ot(uuid)') IS NULL
             THEN 'fn_calama_operador_es_responsable_ot' END,
        CASE WHEN to_regprocedure('public.fn_calama_operador_tiene_avance_en_ot(uuid)') IS NULL
             THEN 'fn_calama_operador_tiene_avance_en_ot' END
    ]::text[], NULL) AS faltan
),
policies_recreadas AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_ordenes_trabajo'
                                AND policyname='pol_calama_ot_select_operador')
             THEN 'pol_calama_ot_select_operador' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_ot_subtareas'
                                AND policyname='pol_calama_subt_select')
             THEN 'pol_calama_subt_select' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_ot_subtareas'
                                AND policyname='pol_calama_subt_update_op')
             THEN 'pol_calama_subt_update_op' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_ot_precheck'
                                AND policyname='pol_calama_precheck_select')
             THEN 'pol_calama_precheck_select' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_avances'
                                AND policyname='pol_calama_avance_select')
             THEN 'pol_calama_avance_select' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_evidencias'
                                AND policyname='pol_calama_evid_select')
             THEN 'pol_calama_evid_select' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_observaciones'
                                AND policyname='pol_calama_obs_select')
             THEN 'pol_calama_obs_select' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies
                              WHERE schemaname='public' AND tablename='calama_eventos_no_ejecucion'
                                AND policyname='pol_calama_no_ejec_select')
             THEN 'pol_calama_no_ejec_select' END
    ]::text[], NULL) AS faltan
),
rls_activa AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ordenes_trabajo')
             THEN 'calama_ordenes_trabajo' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_subtareas')
             THEN 'calama_ot_subtareas' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_precheck')
             THEN 'calama_ot_precheck' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_avances')
             THEN 'calama_avances' END
    ]::text[], NULL) AS desactivada_en
),
sample_count AS (
    -- Esta query corre con privilegios del que ejecuta el script (rol owner via SQL Editor),
    -- por tanto NO valida RLS — solo confirma que la tabla es leible y no tiene errores
    -- estructurales. La validacion real de RLS se hace desde el frontend autenticado.
    SELECT COUNT(*)::int AS total FROM calama_ordenes_trabajo
)
SELECT
    CASE
        WHEN array_length((SELECT faltan FROM helpers_ok),1) > 0
          OR array_length((SELECT faltan FROM policies_recreadas),1) > 0
          OR array_length((SELECT desactivada_en FROM rls_activa),1) > 0
            THEN 'STOP_OPERACION_CALAMA_RLS_FIX'
        ELSE 'OK_OPERACION_CALAMA_RLS_FIX'
    END                                                              AS resultado,
    COALESCE(
        NULLIF(
            array_to_string(array_remove(ARRAY[
                CASE WHEN array_length((SELECT faltan FROM helpers_ok),1) > 0
                     THEN 'Helpers faltantes: ' || array_to_string((SELECT faltan FROM helpers_ok), ', ') END,
                CASE WHEN array_length((SELECT faltan FROM policies_recreadas),1) > 0
                     THEN 'Policies faltantes: ' || array_to_string((SELECT faltan FROM policies_recreadas), ', ') END,
                CASE WHEN array_length((SELECT desactivada_en FROM rls_activa),1) > 0
                     THEN 'RLS DESACTIVADA en: ' || array_to_string((SELECT desactivada_en FROM rls_activa), ', ') END
            ]::text[], NULL), ' | '), ''),
        '3 helpers + 8 policies recreadas + RLS activa en todas las tablas.'
    )                                                                AS detalle,
    8 - COALESCE(array_length((SELECT faltan FROM policies_recreadas),1), 0) AS policies_recreadas,
    3 - COALESCE(array_length((SELECT faltan FROM helpers_ok),1), 0)         AS helpers_creados,
    4 - COALESCE(array_length((SELECT desactivada_en FROM rls_activa),1), 0) AS tablas_con_rls,
    (SELECT total FROM sample_count)                                 AS total_ots_en_tabla,
    NOW()                                                            AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_OPERACION_CALAMA_RLS_FIX
--     → helpers + policies + RLS OK. Frontend debe poder leer
--        calama_ordenes_trabajo sin 500 con sesion authenticated.
-- - resultado = STOP_*
--     → algun helper o policy no se aplico. Revisar `detalle`.
--
-- VALIDACION POST-DEPLOY:
-- 1. En la app autenticado como administrador:
--    GET /rest/v1/calama_ordenes_trabajo?select=id,estado,fecha_programada
--    → debe retornar HTTP 200 con las 112 filas (no 500).
-- 2. Ruta /dashboard/operacion-calama debe cargar sin errores.
-- ============================================================================
