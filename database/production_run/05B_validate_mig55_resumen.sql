-- ============================================================================
-- 05B_validate_mig55_resumen.sql  —  Solo lectura. Una fila final OK/STOP.
-- ----------------------------------------------------------------------------
-- Devuelve UNA fila con: resultado, detalle, y metricas.
-- Compatible con PostgreSQL/Supabase (sin operador "array - array").
-- ============================================================================

WITH
-- ── 1. Tablas encontradas (cast explicito a text) ───────────────────
tablas AS (
    SELECT COALESCE(array_agg(table_name::text ORDER BY table_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name::text IN (
        'proveedores','centros_costo','ordenes_compra','ordenes_compra_items',
        'recepciones_bodega','recepciones_bodega_items',
        'salidas_bodega','salidas_bodega_items',
        'ingresos_combustible','salidas_combustible','despachos_combustible'
      )
),
tablas_esperadas AS (
    SELECT ARRAY[
        'centros_costo','despachos_combustible','ingresos_combustible',
        'ordenes_compra','ordenes_compra_items',
        'proveedores','recepciones_bodega','recepciones_bodega_items',
        'salidas_bodega','salidas_bodega_items','salidas_combustible'
    ]::text[] AS lista
),
tablas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest((SELECT lista FROM tablas_esperadas)) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM tablas)) AS x
    ) s
),

-- ── 2. Funciones folio (cast explicito) ─────────────────────────────
funciones_folio AS (
    SELECT COALESCE(array_agg(p.proname::text ORDER BY p.proname::text), ARRAY[]::text[]) AS encontradas
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname::text IN (
        'fn_generar_folio_recepcion_bodega',
        'fn_generar_folio_salida_bodega',
        'fn_generar_folio_ingreso_combustible',
        'fn_generar_folio_salida_combustible',
        'fn_generar_folio_despacho_combustible'
      )
),
funciones_esperadas AS (
    SELECT ARRAY[
        'fn_generar_folio_despacho_combustible',
        'fn_generar_folio_ingreso_combustible',
        'fn_generar_folio_recepcion_bodega',
        'fn_generar_folio_salida_bodega',
        'fn_generar_folio_salida_combustible'
    ]::text[] AS lista
),
funciones_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest((SELECT lista FROM funciones_esperadas)) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM funciones_folio)) AS x
    ) s
),

-- ── 3. Proveedores minimos (cast explicito) ─────────────────────────
proveedores_min AS (
    SELECT COALESCE(array_agg(codigo::text ORDER BY codigo::text), ARRAY[]::text[]) AS encontrados
    FROM proveedores
    WHERE activo = true
      AND codigo::text IN ('ENEX','ESMAX','COPEC')
),
proveedores_esperados AS (
    SELECT ARRAY['COPEC','ENEX','ESMAX']::text[] AS lista
),
proveedores_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest((SELECT lista FROM proveedores_esperados)) AS x
        EXCEPT
        SELECT unnest((SELECT encontrados FROM proveedores_min)) AS x
    ) s
),

-- ── 4. CECO activos ──────────────────────────────────────────────────
ceco_count AS (
    SELECT COUNT(*)::int AS total FROM centros_costo WHERE activo = true
),

-- ── 5. UNIQUE proveedor+doc en recepciones_bodega ───────────────────
unique_recb AS (
    SELECT COUNT(*)::int AS encontrados
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name::text = 'recepciones_bodega'
      AND constraint_type::text = 'UNIQUE'
      AND constraint_name::text = 'uq_recepcion_doc_proveedor'
),

-- ── 6. CHECK constraints en despacho_combustible ────────────────────
check_despacho AS (
    SELECT COUNT(DISTINCT cc.constraint_name)::int AS encontrados
    FROM information_schema.check_constraints cc
    JOIN information_schema.constraint_column_usage ccu
      ON cc.constraint_name = ccu.constraint_name
    WHERE ccu.table_name::text = 'despachos_combustible'
      AND cc.constraint_name::text LIKE 'chk_despacho_%'
),

-- ── 7. Sequences de folio ────────────────────────────────────────────
sequences_folio AS (
    SELECT COUNT(*)::int AS encontrados
    FROM information_schema.sequences
    WHERE sequence_schema = 'public'
      AND sequence_name::text IN (
        'seq_folio_recepcion_bodega',
        'seq_folio_salida_bodega',
        'seq_folio_ingreso_combustible',
        'seq_folio_salida_combustible',
        'seq_folio_despacho_combustible'
      )
),

-- ── 8. Construir el detalle ─────────────────────────────────────────
detalle AS (
    SELECT
        array_to_string(
            array_remove(ARRAY[
                CASE WHEN array_length((SELECT faltan FROM tablas_faltantes), 1) > 0
                     THEN 'Tablas faltantes: ' || array_to_string((SELECT faltan FROM tablas_faltantes), ', ')
                END,
                CASE WHEN array_length((SELECT faltan FROM funciones_faltantes), 1) > 0
                     THEN 'Funciones folio faltantes: ' || array_to_string((SELECT faltan FROM funciones_faltantes), ', ')
                END,
                CASE WHEN (SELECT encontrados FROM sequences_folio) < 5
                     THEN 'Sequences folio faltantes (encontradas: ' ||
                          (SELECT encontrados FROM sequences_folio)::text || ' de 5)'
                END,
                CASE WHEN array_length((SELECT faltan FROM proveedores_faltantes), 1) > 0
                     THEN 'Proveedores minimos faltantes: ' ||
                          array_to_string((SELECT faltan FROM proveedores_faltantes), ', ') ||
                          ' (ejecutar 06_seed_datos_maestros_produccion.sql)'
                END,
                CASE WHEN (SELECT total FROM ceco_count) < 3
                     THEN 'CECO activos insuficientes (encontrados: ' ||
                          (SELECT total FROM ceco_count)::text ||
                          ' de >=3 minimos. Ejecutar 06_seed_datos_maestros_produccion.sql)'
                END,
                CASE WHEN (SELECT encontrados FROM unique_recb) = 0
                     THEN 'Falta UNIQUE constraint uq_recepcion_doc_proveedor en recepciones_bodega'
                END,
                CASE WHEN (SELECT encontrados FROM check_despacho) < 2
                     THEN 'Faltan CHECK constraints de despacho con sellos (encontrados: ' ||
                          (SELECT encontrados FROM check_despacho)::text || ' de 2)'
                END
            ]::text[], NULL),
            ' | '
        ) AS texto
)

-- ── 9. Resultado final (1 fila) ─────────────────────────────────────
SELECT
    CASE
        WHEN COALESCE((SELECT texto FROM detalle), '') = ''
        THEN 'OK_MIG55'
        ELSE 'STOP_MIG55'
    END                                                                 AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
             '11 tablas + 5 funciones folio + 5 sequences + UNIQUE recepciones + 2 CHECK despacho + ENEX/ESMAX/COPEC + >=3 CECO. Listo para paso 07 (mig 56 FIFO).'
    )                                                                   AS detalle,
    -- Métricas auxiliares
    COALESCE(array_length((SELECT encontradas FROM tablas), 1), 0)         AS tablas_encontradas,
    COALESCE(array_length((SELECT encontradas FROM funciones_folio), 1), 0) AS funciones_folio_encontradas,
    (SELECT encontrados FROM sequences_folio)                              AS sequences_encontradas,
    (SELECT encontrados FROM unique_recb)                                  AS unique_recepciones,
    (SELECT encontrados FROM check_despacho)                               AS checks_despacho,
    COALESCE(array_length((SELECT encontrados FROM proveedores_min), 1), 0) AS proveedores_minimos,
    (SELECT total FROM ceco_count)                                         AS ceco_activos,
    NOW()                                                                  AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- - Si `resultado` = 'OK_MIG55':
--     todo en orden, listo para paso 07 (mig 56 FIFO).
--
-- - Si `resultado` = 'STOP_MIG55':
--     leer la columna `detalle` para saber qué falta. Acciones típicas:
--       * "Tablas faltantes: ..."   → re-ejecutar 04_apply_mig55_produccion.sql
--       * "Funciones folio ..."     → idem
--       * "Sequences folio ..."     → idem
--       * "Proveedores ..."         → ejecutar 06_seed_datos_maestros_produccion.sql
--       * "CECO ..."                → idem
--       * "UNIQUE constraint ..."   → re-ejecutar 04_apply_mig55_produccion.sql
--       * "CHECK constraints ..."   → idem
-- ============================================================================
