-- ============================================================================
-- 11B_validate_mig57_combustible_cpp_resumen.sql  —  Solo lectura. 1 fila final.
-- ----------------------------------------------------------------------------
-- ESTADOS POSIBLES (en orden de prioridad):
--   - STOP_MIG57                              : falta estructura o datos invalidos.
--   - WARNING_MIG57_PENDIENTE_STOCK_INICIAL   : estanques con stock sin stock_inicial.
--   - OK_MIG57                                : todo correcto.
--
-- NOTA SOBRE NOMBRES DE COLUMNAS REALES (mig 57 / 10_apply_*.sql):
--   combustible_stock_inicial:
--     estanque_id, fecha (no 'fecha_stock'), litros_iniciales,
--     costo_unitario_inicial (no 'costo_unitario'),
--     valor_total_inicial (GENERATED, no 'valor_total'),
--     registrado_por (no 'responsable_validacion'), observacion.
--
--   combustible_kardex_valorizado:
--     estanque_id, fecha_movimiento, tipo_movimiento,
--     litros_entrada/litros_salida (no 'litros'),
--     costo_unitario_movimiento (no 'costo_unitario'),
--     valor_entrada/valor_salida (GENERATED, no 'valor_movimiento'),
--     stock_lt_despues (no 'saldo_litros'),
--     costo_promedio_lt_despues (no 'costo_promedio'),
--     valor_stock_despues (no 'saldo_valor').
--
-- NOTA SOBRE FUNCIONES:
--   10_apply_mig57_*.sql crea SOLO 1 RPC: rpc_registrar_stock_inicial_combustible.
--   Las RPCs `rpc_registrar_ingreso_combustible_valorizado` y
--   `rpc_registrar_salida_combustible_valorizada` NO se incluyeron en 10_apply
--   (igual que vistas FIFO faltantes en 07_apply). Se mencionan como nota,
--   no como bloqueo. Si se requieren, crear hotfix 10B.
-- ============================================================================

WITH
-- ── 1. Tablas CPP (2 esperadas) ─────────────────────────────────────
tablas AS (
    SELECT COALESCE(array_agg(table_name::text ORDER BY table_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name::text IN ('combustible_stock_inicial','combustible_kardex_valorizado')
),
tablas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY['combustible_stock_inicial','combustible_kardex_valorizado']::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM tablas)) AS x
    ) s
),

-- ── 2. Columnas críticas en combustible_stock_inicial (REALES, 6) ───
cols_stock AS (
    SELECT COALESCE(array_agg(column_name::text ORDER BY column_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name::text='combustible_stock_inicial'
      AND column_name::text IN (
        'estanque_id','fecha','litros_iniciales',
        'costo_unitario_inicial','valor_total_inicial','registrado_por'
      )
),
cols_stock_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'estanque_id','fecha','litros_iniciales',
            'costo_unitario_inicial','valor_total_inicial','registrado_por'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM cols_stock)) AS x
    ) s
),

-- ── 3. Columnas críticas en combustible_kardex_valorizado (REALES, 9) ─
cols_kardex AS (
    SELECT COALESCE(array_agg(column_name::text ORDER BY column_name::text), ARRAY[]::text[]) AS encontradas
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name::text='combustible_kardex_valorizado'
      AND column_name::text IN (
        'estanque_id','fecha_movimiento','tipo_movimiento',
        'litros_entrada','litros_salida','costo_unitario_movimiento',
        'stock_lt_despues','costo_promedio_lt_despues','valor_stock_despues'
      )
),
cols_kardex_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'estanque_id','fecha_movimiento','tipo_movimiento',
            'litros_entrada','litros_salida','costo_unitario_movimiento',
            'stock_lt_despues','costo_promedio_lt_despues','valor_stock_despues'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM cols_kardex)) AS x
    ) s
),

-- ── 4a. Función obligatoria CPP ─────────────────────────────────────
fn_obligatoria AS (
    SELECT COUNT(*)::int AS encontrada
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='rpc_registrar_stock_inicial_combustible'
),

-- ── 4b. Funciones complementarias (no obligatorias) ─────────────────
fn_complementarias AS (
    SELECT COALESCE(array_agg(p.proname::text ORDER BY p.proname::text), ARRAY[]::text[]) AS encontradas
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname::text IN (
        'rpc_registrar_ingreso_combustible_valorizado',
        'rpc_registrar_salida_combustible_valorizada'
      )
),
fn_complementarias_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY[
            'rpc_registrar_ingreso_combustible_valorizado',
            'rpc_registrar_salida_combustible_valorizada'
        ]::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM fn_complementarias)) AS x
    ) s
),

-- ── 5. Vistas CPP (1 obligatoria de 10_apply) ───────────────────────
vistas AS (
    SELECT COALESCE(array_agg(viewname::text ORDER BY viewname::text), ARRAY[]::text[]) AS encontradas
    FROM pg_views
    WHERE schemaname='public'
      AND viewname::text IN ('v_combustible_stock_valorizado_actual')
),
vistas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (
        SELECT unnest(ARRAY['v_combustible_stock_valorizado_actual']::text[]) AS x
        EXCEPT
        SELECT unnest((SELECT encontradas FROM vistas)) AS x
    ) s
),

-- ── 6. Estanques con stock pero SIN stock_inicial activo ────────────
estanques_pendiente AS (
    SELECT COUNT(*)::int AS cantidad,
           COALESCE(array_agg(e.codigo::text ORDER BY e.codigo::text), ARRAY[]::text[]) AS codigos
    FROM combustible_estanques e
    WHERE e.activo = true
      AND e.stock_teorico_lt > 0
      AND NOT EXISTS (
          SELECT 1 FROM combustible_stock_inicial si
           WHERE si.estanque_id = e.id AND si.anulado = false
      )
),

-- ── 7. Estanques con stock activos (informativo) ────────────────────
estanques_con_stock AS (
    SELECT COUNT(*)::int AS cantidad
    FROM combustible_estanques
    WHERE activo = true AND stock_teorico_lt > 0
),

-- ── 8. Stock inicial con datos inválidos ────────────────────────────
stock_invalido AS (
    SELECT COUNT(*)::int AS cantidad
    FROM combustible_stock_inicial
    WHERE anulado = false
      AND (
            litros_iniciales        <= 0
         OR costo_unitario_inicial  <= 0
         OR valor_total_inicial     <= 0
      )
),

-- ── 9. Kardex con saldos inválidos ──────────────────────────────────
kardex_invalido AS (
    SELECT COUNT(*)::int AS cantidad
    FROM combustible_kardex_valorizado
    WHERE stock_lt_despues          < 0
       OR valor_stock_despues       < 0
       OR costo_promedio_lt_despues < 0
),

-- ── 10. Banderas de decisión ────────────────────────────────────────
flags AS (
    SELECT
        (   array_length((SELECT faltan FROM tablas_faltantes), 1) > 0
         OR array_length((SELECT faltan FROM cols_stock_faltantes), 1) > 0
         OR array_length((SELECT faltan FROM cols_kardex_faltantes), 1) > 0
         OR (SELECT encontrada FROM fn_obligatoria) = 0
         OR array_length((SELECT faltan FROM vistas_faltantes), 1) > 0
        ) AS falta_estructura,
        (   (SELECT cantidad FROM stock_invalido)  > 0
         OR (SELECT cantidad FROM kardex_invalido) > 0
        ) AS hay_datos_invalidos,
        ((SELECT cantidad FROM estanques_pendiente) > 0) AS hay_stock_inicial_pendiente
),

-- ── 11. Construir detalle ───────────────────────────────────────────
detalle AS (
    SELECT array_to_string(
        array_remove(ARRAY[
            CASE WHEN array_length((SELECT faltan FROM tablas_faltantes), 1) > 0
                 THEN 'Tablas CPP faltantes: ' ||
                      array_to_string((SELECT faltan FROM tablas_faltantes), ', ')
            END,
            CASE WHEN array_length((SELECT faltan FROM cols_stock_faltantes), 1) > 0
                 THEN 'Columnas faltantes en combustible_stock_inicial: ' ||
                      array_to_string((SELECT faltan FROM cols_stock_faltantes), ', ')
            END,
            CASE WHEN array_length((SELECT faltan FROM cols_kardex_faltantes), 1) > 0
                 THEN 'Columnas faltantes en combustible_kardex_valorizado: ' ||
                      array_to_string((SELECT faltan FROM cols_kardex_faltantes), ', ')
            END,
            CASE WHEN (SELECT encontrada FROM fn_obligatoria) = 0
                 THEN 'Funcion obligatoria rpc_registrar_stock_inicial_combustible NO existe'
            END,
            CASE WHEN array_length((SELECT faltan FROM vistas_faltantes), 1) > 0
                 THEN 'Vistas CPP faltantes: ' ||
                      array_to_string((SELECT faltan FROM vistas_faltantes), ', ')
            END,
            CASE WHEN (SELECT cantidad FROM stock_invalido) > 0
                 THEN 'Stock inicial con datos invalidos: ' ||
                      (SELECT cantidad FROM stock_invalido)::text
            END,
            CASE WHEN (SELECT cantidad FROM kardex_invalido) > 0
                 THEN 'Kardex con saldos negativos: ' ||
                      (SELECT cantidad FROM kardex_invalido)::text
            END,
            CASE WHEN array_length((SELECT faltan FROM fn_complementarias_faltantes), 1) > 0
                 THEN 'NOTA: Funciones CPP complementarias NO presentes (no bloqueantes): ' ||
                      array_to_string((SELECT faltan FROM fn_complementarias_faltantes), ', ') ||
                      ' (10_apply solo crea rpc_registrar_stock_inicial_combustible; las otras requieren hotfix 10B futuro)'
            END,
            CASE WHEN (SELECT cantidad FROM estanques_pendiente) > 0
                 THEN 'Estanques con stock SIN stock_inicial activo: ' ||
                      (SELECT cantidad FROM estanques_pendiente)::text || ' (' ||
                      array_to_string((SELECT codigos FROM estanques_pendiente), ', ') ||
                      ') — ejecutar paso 12 con Finanzas + varillaje'
            END
        ]::text[], NULL),
        ' | '
    ) AS texto
)

-- ── 12. Resultado final (1 fila) ────────────────────────────────────
SELECT
    CASE
        WHEN (SELECT falta_estructura          FROM flags) THEN 'STOP_MIG57'
        WHEN (SELECT hay_datos_invalidos       FROM flags) THEN 'STOP_MIG57'
        WHEN (SELECT hay_stock_inicial_pendiente FROM flags) THEN 'WARNING_MIG57_PENDIENTE_STOCK_INICIAL'
        ELSE 'OK_MIG57'
    END AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
        '2 tablas + columnas + RPC stock_inicial + vista + sin stock invalido ni kardex negativo + estanques con stock_inicial. Listo para paso 13 (validar roles) y 15 (GO/NO GO).'
    ) AS detalle,
    -- Métricas
    COALESCE(array_length((SELECT encontradas FROM tablas), 1), 0)            AS tablas_cpp_encontradas,
    -- funciones_cpp_encontradas = obligatoria + complementarias
    ((SELECT encontrada FROM fn_obligatoria)
     + COALESCE(array_length((SELECT encontradas FROM fn_complementarias), 1), 0)
    )                                                                         AS funciones_cpp_encontradas,
    COALESCE(array_length((SELECT encontradas FROM vistas), 1), 0)            AS vistas_cpp_encontradas,
    (SELECT cantidad FROM estanques_con_stock)                                AS estanques_con_stock,
    (SELECT cantidad FROM estanques_pendiente)                                AS estanques_sin_stock_inicial,
    (SELECT cantidad FROM stock_invalido)                                     AS stock_inicial_invalido,
    (SELECT cantidad FROM kardex_invalido)                                    AS kardex_saldos_invalidos,
    NOW()                                                                     AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- - resultado = 'OK_MIG57':
--     Estructura completa, stock inicial registrado para todos los estanques
--     con stock, sin datos invalidos. Listo para paso 13 (roles) y 15 (GO/NO GO).
--
-- - resultado = 'WARNING_MIG57_PENDIENTE_STOCK_INICIAL':
--     Estructura completa pero hay estanques con stock_teorico_lt > 0 sin
--     stock_inicial activo. Ejecutar paso 12 con Finanzas + varillaje fisico.
--     NO bloquea avanzar al paso 13, pero idealmente registrar antes para que
--     v_combustible_stock_valorizado_actual muestre valores coherentes.
--
-- - resultado = 'STOP_MIG57':
--     Falta estructura (tablas/columnas/función/vista) o hay datos invalidos
--     (stock con litros<=0/costo<=0, o kardex con saldos negativos).
--     Acciones tipicas:
--       * 'Tablas/Columnas/Funcion/Vista faltantes' → re-ejecutar
--          10_apply_mig57_combustible_cpp_produccion.sql.
--       * 'Stock inicial con datos invalidos' → investigar (no deberian
--          existir; las CHECK constraints lo bloquean).
--       * 'Kardex con saldos negativos' → idem.
--
-- NOTA: las RPCs complementarias (ingreso/salida valorizadas) NO se crean en
-- 10_apply. Para tenerlas, crear hotfix 10B (analogo a 08C de FIFO). Por ahora
-- el flujo CPP solo tiene la RPC base de stock inicial — operacion completa
-- de movimientos valorizados requiere las RPCs adicionales.
-- ============================================================================
