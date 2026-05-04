-- ============================================================================
-- 14C_validate_qr_checklist_mantencion.sql  —  SOLO LECTURA. 1 fila final.
-- ----------------------------------------------------------------------------
-- Estados:
--   - STOP_QR_CHECKLIST     : falta estructura, RLS, RPC, templates o cobertura < 100%
--   - WARNING_QR_CHECKLIST  : todo presente pero con observaciones (ej. anon
--                             puede leer historial, o algun sample falla)
--   - OK_QR_CHECKLIST       : 100% cobertura + RLS correcta + RPC ejecutables.
--
-- NO modifica datos. Hace 1 INSERT temporal en una temp table que se descarta.
-- ============================================================================

WITH
-- ── 1. Tablas obligatorias ───────────────────────────────────────────
tablas_esperadas AS (
    SELECT ARRAY[
        'qr_checklist_templates','qr_checklist_template_items','qr_checklist_template_asignaciones',
        'qr_checklist_respuestas','qr_checklist_respuesta_items','alertas_tempranas',
        'mantenciones_registro','archivos_evidencia','sync_queue_offline'
    ]::text[] AS lista
),
tablas_encontradas AS (
    SELECT COALESCE(array_agg(table_name::text ORDER BY table_name::text), ARRAY[]::text[]) AS lista
    FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name::text IN (
        'qr_checklist_templates','qr_checklist_template_items','qr_checklist_template_asignaciones',
        'qr_checklist_respuestas','qr_checklist_respuesta_items','alertas_tempranas',
        'mantenciones_registro','archivos_evidencia','sync_queue_offline'
    )
),
tablas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (SELECT unnest((SELECT lista FROM tablas_esperadas)) AS x
          EXCEPT
          SELECT unnest((SELECT lista FROM tablas_encontradas)) AS x) s
),

-- ── 2. RPC obligatorias ──────────────────────────────────────────────
rpcs_esperadas AS (
    SELECT ARRAY[
        'rpc_obtener_checklist_publico_por_qr','rpc_guardar_checklist_publico',
        'rpc_generar_alerta_temprana','rpc_historial_mantencion_activo',
        'rpc_registrar_mantencion_preventiva','rpc_cerrar_alerta_temprana'
    ]::text[] AS lista
),
rpcs_encontradas AS (
    SELECT COALESCE(array_agg(p.proname::text ORDER BY p.proname::text), ARRAY[]::text[]) AS lista
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname::text IN (
        'rpc_obtener_checklist_publico_por_qr','rpc_guardar_checklist_publico',
        'rpc_generar_alerta_temprana','rpc_historial_mantencion_activo',
        'rpc_registrar_mantencion_preventiva','rpc_cerrar_alerta_temprana'
    )
),
rpcs_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (SELECT unnest((SELECT lista FROM rpcs_esperadas)) AS x
          EXCEPT
          SELECT unnest((SELECT lista FROM rpcs_encontradas)) AS x) s
),

-- ── 3. Helpers obligatorios ──────────────────────────────────────────
helpers_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.fn_qr_familia_operacional(tipo_activo_enum)') IS NULL
             THEN 'fn_qr_familia_operacional' END,
        CASE WHEN to_regprocedure('public.fn_qr_es_rol_mantencion()') IS NULL
             THEN 'fn_qr_es_rol_mantencion' END,
        CASE WHEN to_regprocedure('public.fn_qr_resolver_template_para_activo(uuid)') IS NULL
             THEN 'fn_qr_resolver_template_para_activo' END,
        CASE WHEN to_regprocedure('public.fn_qr_evaluar_semaforo_respuesta(uuid)') IS NULL
             THEN 'fn_qr_evaluar_semaforo_respuesta' END
    ]::text[], NULL) AS faltan
),

-- ── 4. RLS habilitada en tablas sensibles ────────────────────────────
rls_estado AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='qr_checklist_respuestas')
             THEN 'qr_checklist_respuestas' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='qr_checklist_respuesta_items')
             THEN 'qr_checklist_respuesta_items' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='alertas_tempranas')
             THEN 'alertas_tempranas' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='mantenciones_registro')
             THEN 'mantenciones_registro' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='archivos_evidencia')
             THEN 'archivos_evidencia' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='sync_queue_offline')
             THEN 'sync_queue_offline' END
    ]::text[], NULL) AS sin_rls
),

-- ── 5. ANON NO puede leer historial sensible ─────────────────────────
-- Verifica que NO existan policies SELECT TO anon en tablas sensibles.
anon_lee_sensibles AS (
    SELECT COALESCE(array_agg(DISTINCT tablename::text ORDER BY tablename::text), ARRAY[]::text[]) AS tablas
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename::text IN ('qr_checklist_respuestas','qr_checklist_respuesta_items',
                              'alertas_tempranas','mantenciones_registro','sync_queue_offline')
      AND cmd = 'SELECT'
      AND 'anon' = ANY(roles)
),

-- ── 6. Templates: universal + minimo 13 activos ──────────────────────
templates_universal AS (
    SELECT COUNT(*)::int AS total FROM qr_checklist_templates WHERE es_universal=true AND activo=true
),
templates_count AS (
    SELECT COUNT(*)::int AS total FROM qr_checklist_templates WHERE activo=true
),

-- ── 7. Cobertura activos ─────────────────────────────────────────────
cobertura AS (
    SELECT
        COUNT(*)::int                                      AS total,
        COUNT(*) FILTER (WHERE tiene_checklist = true)::int  AS con_check,
        COUNT(*) FILTER (WHERE tiene_checklist = false)::int AS sin_check
    FROM v_qr_checklist_cobertura_activos
),

-- ── 8. Sample: anon puede llamar rpc_obtener_checklist_publico_por_qr ─
sample_activo AS (
    SELECT id FROM activos WHERE fecha_baja IS NULL LIMIT 1
),
sample_rpc_test AS (
    SELECT
        CASE
            WHEN (SELECT id FROM sample_activo) IS NULL THEN 'sin_activos_para_probar'
            WHEN to_regprocedure('public.rpc_obtener_checklist_publico_por_qr(uuid)') IS NULL THEN 'rpc_no_existe'
            WHEN (rpc_obtener_checklist_publico_por_qr((SELECT id FROM sample_activo)) ->> 'error') IS NULL
                 THEN 'rpc_responde_ok'
            ELSE 'rpc_responde_error'
        END AS resultado
),

-- ── 8.1 (14B2) Capa Control de Calidad ──────────────────────────────
calidad_cols_resp AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_respuestas' AND column_name='duracion_segundos')
             THEN 'qr_checklist_respuestas.duracion_segundos' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_respuestas' AND column_name='score_calidad')
             THEN 'qr_checklist_respuestas.score_calidad' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_respuestas' AND column_name='clasificacion_calidad')
             THEN 'qr_checklist_respuestas.clasificacion_calidad' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_respuestas' AND column_name='gps_inicial_lat')
             THEN 'qr_checklist_respuestas.gps_inicial_lat' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_respuestas' AND column_name='firma_declaracion')
             THEN 'qr_checklist_respuestas.firma_declaracion' END
    ]::text[], NULL) AS faltan
),
calidad_cols_items AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_template_items' AND column_name='requiere_foto_siempre')
             THEN 'requiere_foto_siempre' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_template_items' AND column_name='requiere_foto_si_falla')
             THEN 'requiere_foto_si_falla' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_template_items' AND column_name='solo_camara')
             THEN 'solo_camara' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_name='qr_checklist_template_items' AND column_name='es_control_aleatorio')
             THEN 'es_control_aleatorio' END
    ]::text[], NULL) AS faltan
),
calidad_funciones AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.fn_qr_calcular_score_calidad_checklist(uuid)') IS NULL
             THEN 'fn_qr_calcular_score_calidad_checklist' END,
        CASE WHEN to_regprocedure('public.fn_qr_evaluar_alertas_calidad(uuid)') IS NULL
             THEN 'fn_qr_evaluar_alertas_calidad' END,
        CASE WHEN to_regprocedure('public.fn_qr_clasificar_calidad(integer,integer,integer)') IS NULL
             THEN 'fn_qr_clasificar_calidad' END,
        CASE WHEN to_regprocedure('public.rpc_marcar_checklist_revisado(uuid,text,text)') IS NULL
             THEN 'rpc_marcar_checklist_revisado' END,
        CASE WHEN to_regprocedure('public.rpc_revisar_alerta_calidad(uuid,text,text)') IS NULL
             THEN 'rpc_revisar_alerta_calidad' END
    ]::text[], NULL) AS faltan
),
calidad_tabla AS (
    SELECT (SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema='public' AND table_name='qr_checklist_alertas_calidad')::int AS existe
),
templates_dur_min AS (
    -- Templates activos sin duracion_minima_segundos > 0
    SELECT COUNT(*)::int AS sin_dur_min
    FROM qr_checklist_templates
    WHERE activo = true
      AND COALESCE(duracion_minima_segundos, 0) <= 0
),
templates_con_aleatorios AS (
    -- Templates activos sin items de control aleatorio
    SELECT COUNT(*)::int AS sin_aleatorios
    FROM qr_checklist_templates t
    WHERE t.activo = true
      AND NOT EXISTS (
        SELECT 1 FROM qr_checklist_template_items i
         WHERE i.template_id = t.id AND i.es_control_aleatorio = true
      )
),
items_criticos_sin_evidencia AS (
    -- Items con criticidad rojo y sin requiere_foto_si_falla
    SELECT COUNT(*)::int AS sin_evidencia
    FROM qr_checklist_template_items
    WHERE criticidad_si_falla = 'rojo'
      AND requiere_foto_si_falla = false
),

-- ── 9. Construir detalle ─────────────────────────────────────────────
detalle AS (
    SELECT array_to_string(array_remove(ARRAY[
        CASE WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
             THEN 'Tablas faltantes: ' || array_to_string((SELECT faltan FROM tablas_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM rpcs_faltantes),1) > 0
             THEN 'RPCs faltantes: ' || array_to_string((SELECT faltan FROM rpcs_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM helpers_faltantes),1) > 0
             THEN 'Helpers faltantes: ' || array_to_string((SELECT faltan FROM helpers_faltantes), ', ') END,
        CASE WHEN array_length((SELECT sin_rls FROM rls_estado),1) > 0
             THEN 'RLS DESHABILITADA en: ' || array_to_string((SELECT sin_rls FROM rls_estado), ', ') END,
        CASE WHEN array_length((SELECT tablas FROM anon_lee_sensibles),1) > 0
             THEN 'ANON tiene SELECT en tablas sensibles: ' || array_to_string((SELECT tablas FROM anon_lee_sensibles), ', ') END,
        CASE WHEN (SELECT total FROM templates_universal) = 0
             THEN 'Falta template UNIVERSAL activo (es_universal=true).' END,
        CASE WHEN (SELECT total FROM templates_count) < 13
             THEN 'Templates insuficientes (encontrados: ' || (SELECT total FROM templates_count)::text || ' de 13 minimos).' END,
        CASE WHEN (SELECT sin_check FROM cobertura) > 0
             THEN 'Cobertura incompleta: ' || (SELECT sin_check FROM cobertura)::text || ' activos SIN checklist resuelto.' END,
        CASE WHEN (SELECT resultado FROM sample_rpc_test) = 'rpc_responde_error'
             THEN 'rpc_obtener_checklist_publico_por_qr respondio con error en sample.' END,
        -- 14B2: Capa control de calidad
        CASE WHEN array_length((SELECT faltan FROM calidad_cols_resp),1) > 0
             THEN 'Columnas calidad faltantes en respuestas: ' || array_to_string((SELECT faltan FROM calidad_cols_resp), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM calidad_cols_items),1) > 0
             THEN 'Columnas calidad faltantes en template_items: ' || array_to_string((SELECT faltan FROM calidad_cols_items), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM calidad_funciones),1) > 0
             THEN 'Funciones/RPCs calidad faltantes: ' || array_to_string((SELECT faltan FROM calidad_funciones), ', ') END,
        CASE WHEN (SELECT existe FROM calidad_tabla) = 0
             THEN 'Tabla qr_checklist_alertas_calidad no existe (ejecutar 14B2).' END,
        CASE WHEN (SELECT sin_dur_min FROM templates_dur_min) > 0
             THEN 'Templates sin duracion_minima_segundos > 0: ' || (SELECT sin_dur_min FROM templates_dur_min)::text END,
        CASE WHEN (SELECT sin_aleatorios FROM templates_con_aleatorios) > 0
             THEN 'Templates sin items de control aleatorio: ' || (SELECT sin_aleatorios FROM templates_con_aleatorios)::text END,
        CASE WHEN (SELECT sin_evidencia FROM items_criticos_sin_evidencia) > 0
             THEN 'Items rojos sin requiere_foto_si_falla: ' || (SELECT sin_evidencia FROM items_criticos_sin_evidencia)::text END
    ]::text[], NULL), ' | ') AS texto
)

-- ── 10. Resultado final (1 fila) ─────────────────────────────────────
SELECT
    CASE
        WHEN COALESCE((SELECT texto FROM detalle), '') = ''
             AND (SELECT total FROM cobertura) > 0
             AND (SELECT sin_check FROM cobertura) = 0
        THEN 'OK_QR_CHECKLIST'
        WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
          OR array_length((SELECT faltan FROM rpcs_faltantes),1) > 0
          OR array_length((SELECT faltan FROM helpers_faltantes),1) > 0
          OR array_length((SELECT sin_rls FROM rls_estado),1) > 0
          OR array_length((SELECT tablas FROM anon_lee_sensibles),1) > 0
          OR (SELECT total FROM templates_universal) = 0
          OR (SELECT total FROM templates_count) < 13
          OR (SELECT sin_check FROM cobertura) > 0
          OR array_length((SELECT faltan FROM calidad_cols_resp),1) > 0
          OR array_length((SELECT faltan FROM calidad_cols_items),1) > 0
          OR array_length((SELECT faltan FROM calidad_funciones),1) > 0
          OR (SELECT existe FROM calidad_tabla) = 0
          OR (SELECT sin_dur_min FROM templates_dur_min) > 0
          OR (SELECT sin_aleatorios FROM templates_con_aleatorios) > 0
        THEN 'STOP_QR_CHECKLIST'
        ELSE 'WARNING_QR_CHECKLIST'
    END                                                                AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
        '9 tablas + 6 RPCs base + 5 RPCs/fn calidad + RLS habilitada + anon sin SELECT a sensibles + universal + 13+ templates + duracion_min + items aleatorios + cobertura 100%.'
    )                                                                  AS detalle,
    COALESCE(array_length((SELECT lista FROM tablas_encontradas),1), 0)  AS tablas_encontradas,
    COALESCE(array_length((SELECT lista FROM rpcs_encontradas),1), 0)    AS rpcs_encontradas,
    (SELECT total FROM templates_count)                                  AS templates_activos,
    (SELECT total FROM templates_universal)                              AS template_universal,
    (SELECT total      FROM cobertura)                                   AS total_activos_activos,
    (SELECT con_check  FROM cobertura)                                   AS activos_con_checklist,
    (SELECT sin_check  FROM cobertura)                                   AS activos_sin_checklist,
    CASE WHEN (SELECT total FROM cobertura) = 0 THEN 0
         ELSE ROUND(
             ((SELECT con_check FROM cobertura)::NUMERIC * 100.0)
              / (SELECT total FROM cobertura)::NUMERIC, 2)
    END                                                                  AS porcentaje_cobertura,
    (SELECT resultado FROM sample_rpc_test)                              AS sample_rpc_publica,
    -- Capa control de calidad (14B2)
    (SELECT existe FROM calidad_tabla)                                   AS tabla_alertas_calidad,
    (SELECT sin_dur_min FROM templates_dur_min)                          AS templates_sin_duracion_min,
    (SELECT sin_aleatorios FROM templates_con_aleatorios)                AS templates_sin_items_aleatorios,
    (SELECT sin_evidencia FROM items_criticos_sin_evidencia)             AS items_rojos_sin_evidencia,
    NOW()                                                                AS chequeado_en;


-- ── 11. Detalle de activos sin checklist (para debug si STOP) ────────
-- Esta query auxiliar lista activos sin asignacion. NO modifica datos.
SELECT
    activo_id, codigo, nombre, marca, modelo, tipo, familia_operacional,
    'SIN_CHECKLIST' AS motivo
FROM v_qr_checklist_cobertura_activos
WHERE tiene_checklist = false
ORDER BY codigo
LIMIT 50;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_QR_CHECKLIST  → todo en orden, frontend puede consumir.
-- - resultado = WARNING_*        → leer columna `detalle`.
-- - resultado = STOP_*           → leer `detalle` + query auxiliar de activos
--                                  sin checklist al final del archivo.
--
-- Cobertura 100% es OBLIGATORIA para OK. La asignacion universal garantiza
-- que ningun activo activo (fecha_baja IS NULL) quede sin checklist.
-- ============================================================================
