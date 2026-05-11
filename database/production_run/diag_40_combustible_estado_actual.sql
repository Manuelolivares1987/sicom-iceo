-- ============================================================================
-- diag_40_combustible_estado_actual.sql
-- ----------------------------------------------------------------------------
-- Diagnostico read-only consolidado del estado de combustible antes de
-- avanzar con MIG40 (CPP movil + salida valorizada).
--
-- Devuelve 1 resultset con schema fijo (dx, key, val, extra) para copiar
-- completo desde Supabase como JSON.
--
-- NO TOCA DATOS. NO MODIFICA ENUMS NI TABLAS.
-- ============================================================================

WITH

-- ── Q1: Estanques con todas las columnas relevantes ────────────────────────
q1 AS (
    SELECT
        'Q1_estanque'::text                 AS dx,
        e.codigo                            AS key,
        e.stock_teorico_lt::text            AS val,
        jsonb_build_object(
            'estanque_id', e.id,
            'nombre', e.nombre,
            'capacidad_lt', e.capacidad_lt,
            'stock_teorico_lt', e.stock_teorico_lt,
            'stock_minimo_alerta_lt', e.stock_minimo_alerta_lt,
            'costo_promedio_lt',
                (SELECT value::numeric FROM jsonb_each_text(to_jsonb(e))
                  WHERE key='costo_promedio_lt' LIMIT 1),
            'valor_total_stock',
                (SELECT value::numeric FROM jsonb_each_text(to_jsonb(e))
                  WHERE key='valor_total_stock' LIMIT 1),
            'faena_id', e.faena_id,
            'activo', e.activo,
            'updated_at', e.updated_at
        )                                   AS extra
    FROM combustible_estanques e
),

-- ── Q2: Stock inicial activo por estanque (mig 57) ─────────────────────────
q2 AS (
    SELECT
        'Q2_stock_inicial'::text            AS dx,
        e.codigo                            AS key,
        COALESCE(si.litros_iniciales::text, 'sin_stock_inicial') AS val,
        jsonb_build_object(
            'estanque_id', e.id,
            'fecha', si.fecha,
            'litros_iniciales', si.litros_iniciales,
            'costo_unitario_inicial', si.costo_unitario_inicial,
            'valor_total_inicial', si.valor_total_inicial,
            'observacion', si.observacion,
            'anulado', si.anulado,
            'created_at', si.created_at
        )                                   AS extra
    FROM combustible_estanques e
    LEFT JOIN combustible_stock_inicial si
      ON si.estanque_id = e.id AND si.anulado = FALSE
),

-- ── Q3: Ultimo varillaje por estanque ──────────────────────────────────────
q3 AS (
    SELECT DISTINCT ON (e.id)
        'Q3_ultima_varilla'::text           AS dx,
        e.codigo                            AS key,
        cv.medicion_fisica_lt::text         AS val,
        jsonb_build_object(
            'estanque_id', e.id,
            'fecha', cv.fecha,
            'medicion_fisica_lt', cv.medicion_fisica_lt,
            'stock_teorico_snapshot_lt', cv.stock_teorico_snapshot_lt,
            'diferencia_lt', cv.diferencia_lt,
            'dias_desde', CASE WHEN cv.fecha IS NOT NULL
                THEN (CURRENT_DATE - cv.fecha) ELSE NULL END,
            'turno', cv.turno,
            'operador_id', cv.operador_id,
            'observaciones', cv.observaciones
        )                                   AS extra
    FROM combustible_estanques e
    LEFT JOIN combustible_varillaje cv ON cv.estanque_id = e.id
    ORDER BY e.id, cv.fecha DESC NULLS LAST, cv.created_at DESC NULLS LAST
),

-- ── Q4: Conteo movimientos legacy por estanque ─────────────────────────────
q4 AS (
    SELECT
        'Q4_movimientos_legacy'::text       AS dx,
        e.codigo                            AS key,
        COUNT(cm.id)::text                  AS val,
        jsonb_build_object(
            'total', COUNT(cm.id),
            'ingresos', COUNT(cm.id) FILTER (WHERE cm.tipo = 'ingreso'),
            'despachos', COUNT(cm.id) FILTER (WHERE cm.tipo = 'despacho'),
            'ajustes', COUNT(cm.id) FILTER (WHERE cm.tipo = 'ajuste'),
            'mermas', COUNT(cm.id) FILTER (WHERE cm.tipo = 'merma'),
            'litros_totales_ingreso',
                COALESCE(SUM(cm.litros) FILTER (WHERE cm.tipo='ingreso'), 0),
            'litros_totales_despacho',
                COALESCE(SUM(cm.litros) FILTER (WHERE cm.tipo='despacho'), 0),
            'ultimo_movimiento', MAX(cm.fecha_hora)
        )                                   AS extra
    FROM combustible_estanques e
    LEFT JOIN combustible_movimientos cm ON cm.estanque_id = e.id
    GROUP BY e.id, e.codigo
),

-- ── Q5: Kardex valorizado (mig 57) — si esta vacio CPP no esta operativo ──
q5 AS (
    SELECT
        'Q5_kardex_valorizado'::text        AS dx,
        e.codigo                            AS key,
        (
            SELECT COUNT(*)::text
              FROM combustible_kardex_valorizado ckv
             WHERE ckv.estanque_id = e.id
        )                                   AS val,
        jsonb_build_object(
            'total_kardex',
                (SELECT COUNT(*) FROM combustible_kardex_valorizado ckv
                  WHERE ckv.estanque_id = e.id),
            'tipos',
                (SELECT jsonb_object_agg(tipo_movimiento, n)
                   FROM (
                     SELECT tipo_movimiento, COUNT(*) AS n
                       FROM combustible_kardex_valorizado
                      WHERE estanque_id = e.id
                      GROUP BY tipo_movimiento
                   ) sub),
            'ultimo_kardex',
                (SELECT MAX(fecha_movimiento) FROM combustible_kardex_valorizado
                  WHERE estanque_id = e.id)
        )                                   AS extra
    FROM combustible_estanques e
),

-- ── Q6: RPCs combustible activas en pg_proc ────────────────────────────────
q6 AS (
    SELECT
        'Q6_rpc_combustible'::text          AS dx,
        proname                             AS key,
        '1'                                 AS val,
        jsonb_build_object('exists', true) AS extra
    FROM pg_proc
    WHERE proname IN (
        'fn_registrar_movimiento_combustible',
        'fn_registrar_varillaje_combustible',
        'rpc_registrar_stock_inicial_combustible',
        'rpc_registrar_ingreso_combustible_valorizado',
        'rpc_registrar_salida_combustible_valorizada',
        'rpc_registrar_despacho_combustible_sellos',
        'rpc_registrar_despacho_combustible_con_sellos'
    )
),

-- ── Q7: Vistas combustible activas en pg_views ─────────────────────────────
q7 AS (
    SELECT
        'Q7_vistas_combustible'::text       AS dx,
        viewname                            AS key,
        '1'                                 AS val,
        jsonb_build_object('exists', true) AS extra
    FROM pg_views
    WHERE schemaname='public' AND viewname LIKE 'v_combustible%'
),

-- ── Q8: Columnas CPP en combustible_estanques (verifica mig57 aplicada) ───
q8 AS (
    SELECT
        'Q8_columnas_cpp_estanques'::text   AS dx,
        column_name                         AS key,
        data_type                           AS val,
        jsonb_build_object(
            'column_name', column_name,
            'data_type', data_type,
            'is_nullable', is_nullable,
            'column_default', column_default
        )                                   AS extra
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='combustible_estanques'
      AND column_name IN ('costo_promedio_lt','valor_total_stock',
                          'stock_teorico_lt','capacidad_lt','activo')
),

-- ── Q9: Estado RLS de tablas combustible ───────────────────────────────────
q9 AS (
    SELECT
        'Q9_rls_combustible'::text          AS dx,
        c.relname                           AS key,
        CASE WHEN c.relrowsecurity THEN 'ENABLED' ELSE 'DISABLED' END AS val,
        jsonb_build_object(
            'rls_enabled', c.relrowsecurity,
            'force_rls', c.relforcerowsecurity,
            'policies_count',
                (SELECT COUNT(*) FROM pg_policies p
                  WHERE p.schemaname='public' AND p.tablename=c.relname)
        )                                   AS extra
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname IN (
        'combustible_estanques','combustible_medidores',
        'combustible_movimientos','combustible_varillaje',
        'combustible_stock_inicial','combustible_kardex_valorizado',
        'ingresos_combustible','salidas_combustible','despachos_combustible'
      )
),

-- ── Q10: Resumen agregado global ───────────────────────────────────────────
q10 AS (
    SELECT
        'Q10_resumen_global'::text          AS dx,
        'agregado'                          AS key,
        ''                                  AS val,
        jsonb_build_object(
            'total_estanques',
                (SELECT COUNT(*) FROM combustible_estanques),
            'estanques_activos',
                (SELECT COUNT(*) FROM combustible_estanques WHERE activo),
            'estanques_con_stock',
                (SELECT COUNT(*) FROM combustible_estanques WHERE stock_teorico_lt > 0),
            'estanques_con_stock_inicial',
                (SELECT COUNT(*) FROM combustible_stock_inicial WHERE anulado = FALSE),
            'total_litros_teoricos',
                (SELECT COALESCE(SUM(stock_teorico_lt), 0) FROM combustible_estanques WHERE activo),
            'total_movimientos_legacy',
                (SELECT COUNT(*) FROM combustible_movimientos),
            'total_kardex_valorizado',
                (SELECT COUNT(*) FROM combustible_kardex_valorizado),
            'total_varillajes',
                (SELECT COUNT(*) FROM combustible_varillaje),
            'ultimo_varillaje_global',
                (SELECT MAX(fecha) FROM combustible_varillaje),
            'ultimo_movimiento_global',
                (SELECT MAX(fecha_hora) FROM combustible_movimientos)
        )                                   AS extra
)

SELECT dx, key, val, extra FROM q10
UNION ALL SELECT dx, key, val, extra FROM q1
UNION ALL SELECT dx, key, val, extra FROM q2
UNION ALL SELECT dx, key, val, extra FROM q3
UNION ALL SELECT dx, key, val, extra FROM q4
UNION ALL SELECT dx, key, val, extra FROM q5
UNION ALL SELECT dx, key, val, extra FROM q6
UNION ALL SELECT dx, key, val, extra FROM q7
UNION ALL SELECT dx, key, val, extra FROM q8
UNION ALL SELECT dx, key, val, extra FROM q9
ORDER BY dx, key;

-- ============================================================================
-- INSTRUCCIONES
-- Ejecutar el archivo completo en Supabase SQL Editor.
-- Devuelve 1 resultset con ~30-50 filas.
-- Pegar el JSON completo en el chat para que el agente decida si avanzar a
-- FASE 40-B (MIG40 CPP movil).
--
-- CRITERIO DE AVANCE:
--   - Q10 total_estanques >= 3 OK
--   - Q1 muestra los 3 estanques con stock_teorico definido
--   - Q2 al menos 1 estanque con stock inicial activo (sino, MIG40 deberia
--     pedir capturar stock inicial primero)
--   - Q6 confirma que rpc_registrar_ingreso/salida_valorizada NO existen
--     todavia (eso es lo que MIG40 va a crear)
--   - Q8 confirma columnas costo_promedio_lt y valor_total_stock existen
--     (mig57 base aplicada)
-- ============================================================================
