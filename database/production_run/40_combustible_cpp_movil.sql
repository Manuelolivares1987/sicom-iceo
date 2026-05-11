-- ============================================================================
-- 40_combustible_cpp_movil.sql
-- ----------------------------------------------------------------------------
-- Combustible — backend valorizado con CPP movil. ADITIVA. IDEMPOTENTE.
--
-- Crea 2 RPCs transaccionales y 3 vistas read-only:
--   1. rpc_registrar_ingreso_combustible_valorizado(...)
--   2. rpc_registrar_salida_combustible_valorizada(...)
--   3. v_combustible_stock_valorizado          (alias semantico)
--   4. v_combustible_movimientos_valorizados   (kardex con joins amigables)
--   5. v_combustible_control_kardex_varillaje  (control consolidado)
--
-- NO toca:
--   - stock_bodega
--   - inventario_capas / inventario_consumos_capas
--   - movimientos_inventario
--   - reconciliacion productos/FIFO
--   - combustible_movimientos legacy
--   - fn_registrar_movimiento_combustible / fn_registrar_varillaje_combustible
--   - stock_teorico_lt actual de los estanques
--   - enum global
--
-- Las nuevas RPCs operan SOLO sobre:
--   - combustible_estanques (UPDATE: stock_teorico_lt, costo_promedio_lt,
--     valor_total_stock, updated_at)
--   - combustible_kardex_valorizado (INSERT con tipo_movimiento del enum
--     existente mig 57)
--
-- Decisiones aplicadas:
--   - CPP movil aritmetico: nuevo_cpp = (stock*cpp + litros*costo) / total
--     Si stock=0, nuevo_cpp = costo (no dividir por 0).
--   - Salidas usan CPP vigente como costo unitario (no cambian CPP).
--   - Mapeo destino_tipo -> tipo_movimiento kardex:
--       equipo            -> 'salida_equipo'
--       ot/ceco/faena/    -> 'salida_despacho'
--       consumo_interno
--   - Validacion capacidad: stock + litros <= capacidad.
--   - Validacion stock: stock_teorico >= litros (salida).
--   - Roles permitidos: administrador, supervisor, subgerente_operaciones,
--     jefe_mantenimiento, operador_abastecimiento.
-- ============================================================================


-- ── BLOQUE 0: PRECHECKS ────────────────────────────────────────────────────
DO $$
DECLARE
    v_rol TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_estanques') THEN
        RAISE EXCEPTION 'STOP - combustible_estanques no existe (mig 50 base)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='combustible_estanques'
                      AND column_name='costo_promedio_lt') THEN
        RAISE EXCEPTION 'STOP - combustible_estanques.costo_promedio_lt no existe (mig 57 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - combustible_kardex_valorizado no existe (mig 57 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - fn_user_rol no existe';
    END IF;

    -- Sanidad: no debe haber stock negativo
    IF EXISTS (SELECT 1 FROM combustible_estanques WHERE stock_teorico_lt < 0) THEN
        RAISE EXCEPTION 'STOP - hay estanque con stock_teorico_lt < 0';
    END IF;

    -- Sanidad reconciliacion productos (proteccion paranoia)
    IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                AND viewname='v_bodega_reconciliacion_stock_fifo') THEN
        IF (SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo
             WHERE estado_reconciliacion <> 'cuadrado') > 0 THEN
            RAISE EXCEPTION 'STOP - reconciliacion productos/FIFO no esta cuadrada';
        END IF;
    END IF;

    -- Permitir contexto migracion (service_role / postgres)
    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN
        RAISE NOTICE 'Aplicando MIG40 como rol de sistema (current_user=%). OK.', current_user;
    ELSIF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar MIG40 desde sesion autenticada requiere rol administrador. Rol actual: %', v_rol;
    END IF;

    RAISE NOTICE '== MIG40 prechecks OK ==';
END $$;


-- ============================================================================
-- BLOQUE 1: rpc_registrar_ingreso_combustible_valorizado
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_ingreso_combustible_valorizado(
    p_estanque_id        UUID,
    p_litros             NUMERIC,
    p_costo_unitario_clp NUMERIC,
    p_proveedor_id       UUID    DEFAULT NULL,
    p_doc_tipo           VARCHAR DEFAULT NULL,    -- ej. 'factura', 'guia'
    p_doc_numero         VARCHAR DEFAULT NULL,
    p_fecha_movimiento   TIMESTAMPTZ DEFAULT NULL, -- default NOW()
    p_observacion        TEXT    DEFAULT NULL,
    p_evidencia_url      TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_estanque     combustible_estanques%ROWTYPE;
    v_stock_post   NUMERIC;
    v_cpp_anterior NUMERIC;
    v_cpp_nuevo    NUMERIC;
    v_valor_anterior NUMERIC;
    v_valor_nuevo  NUMERIC;
    v_kardex_id    UUID;
    v_folio        VARCHAR;
    v_fecha        TIMESTAMPTZ;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para ingreso de combustible', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_costo_unitario_clp IS NULL OR p_costo_unitario_clp < 0 THEN
        RAISE EXCEPTION 'costo_unitario_clp debe ser >= 0';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    -- Lock estanque
    SELECT * INTO v_estanque
      FROM combustible_estanques
     WHERE id = p_estanque_id
     FOR UPDATE;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;

    v_stock_post := v_estanque.stock_teorico_lt + p_litros;
    IF v_stock_post > v_estanque.capacidad_lt THEN
        RAISE EXCEPTION 'Ingreso supera capacidad. Stock actual: % lt, capacidad: % lt, intento ingresar: % lt',
            v_estanque.stock_teorico_lt, v_estanque.capacidad_lt, p_litros;
    END IF;

    v_cpp_anterior   := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_valor_anterior := COALESCE(v_estanque.valor_total_stock, 0);

    -- CPP movil: si stock anterior = 0, el CPP nuevo es el costo del ingreso.
    IF v_estanque.stock_teorico_lt > 0 THEN
        v_cpp_nuevo := ROUND(
            (v_estanque.stock_teorico_lt * v_cpp_anterior + p_litros * p_costo_unitario_clp)
            / v_stock_post,
            4
        );
    ELSE
        v_cpp_nuevo := ROUND(p_costo_unitario_clp::numeric, 4);
    END IF;

    v_valor_nuevo := ROUND((v_stock_post * v_cpp_nuevo)::numeric, 2);

    -- Folio (reusa fn de mig 55 si existe)
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_ingreso_combustible') THEN
        SELECT fn_generar_folio_ingreso_combustible() INTO v_folio;
    ELSE
        v_folio := 'ICB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    -- Kardex valorizado: tipo 'ingreso_compra'
    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        proveedor_id, documento_numero,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, 'ingreso_compra', v_folio,
        p_proveedor_id, p_doc_numero,
        p_litros, 0, p_costo_unitario_clp,
        v_stock_post, v_cpp_nuevo, v_valor_nuevo,
        p_evidencia_url, p_observacion, v_user_id
    );

    -- Actualizar estanque
    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_post,
           costo_promedio_lt = v_cpp_nuevo,
           valor_total_stock = v_valor_nuevo,
           updated_at        = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success', true,
        'kardex_id', v_kardex_id,
        'folio', v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_ingresados', p_litros,
        'costo_unitario_ingreso', p_costo_unitario_clp,
        'cpp_anterior', v_cpp_anterior,
        'cpp_nuevo', v_cpp_nuevo,
        'stock_anterior', v_estanque.stock_teorico_lt,
        'stock_nuevo', v_stock_post,
        'valor_anterior', v_valor_anterior,
        'valor_nuevo', v_valor_nuevo
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_ingreso_combustible_valorizado IS
'Ingreso valorizado al estanque con CPP movil. Actualiza stock, CPP y valor. Inserta en combustible_kardex_valorizado con tipo=ingreso_compra. No toca movimientos legacy. MIG40.';


-- ============================================================================
-- BLOQUE 2: rpc_registrar_salida_combustible_valorizada
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_salida_combustible_valorizada(
    p_estanque_id      UUID,
    p_litros           NUMERIC,
    p_destino_tipo     VARCHAR,   -- 'equipo','ot','ceco','faena','consumo_interno','venta_externa'
    p_motivo           TEXT,
    p_equipo_id        UUID    DEFAULT NULL,
    p_ot_id            UUID    DEFAULT NULL,
    p_ceco_id          UUID    DEFAULT NULL,
    p_faena_id         UUID    DEFAULT NULL,
    p_cliente_nombre   VARCHAR DEFAULT NULL,
    p_fecha_movimiento TIMESTAMPTZ DEFAULT NULL,
    p_observacion      TEXT    DEFAULT NULL,
    p_evidencia_url    TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_estanque    combustible_estanques%ROWTYPE;
    v_stock_post  NUMERIC;
    v_cpp_actual  NUMERIC;
    v_valor_post  NUMERIC;
    v_costo_total NUMERIC;
    v_kardex_id   UUID;
    v_folio       VARCHAR;
    v_fecha       TIMESTAMPTZ;
    v_tipo_kardex VARCHAR(30);
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para salida de combustible', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'motivo es obligatorio (min 5 caracteres)';
    END IF;
    IF p_destino_tipo NOT IN ('equipo','ot','ceco','faena','consumo_interno','venta_externa') THEN
        RAISE EXCEPTION 'destino_tipo invalido: %', p_destino_tipo;
    END IF;

    -- Coherencia FK por destino
    IF p_destino_tipo = 'equipo' AND p_equipo_id IS NULL THEN
        RAISE EXCEPTION 'destino=equipo requiere equipo_id';
    END IF;
    IF p_destino_tipo = 'ot' AND p_ot_id IS NULL THEN
        RAISE EXCEPTION 'destino=ot requiere ot_id';
    END IF;
    IF p_destino_tipo = 'ceco' AND p_ceco_id IS NULL THEN
        RAISE EXCEPTION 'destino=ceco requiere ceco_id';
    END IF;
    IF p_destino_tipo = 'faena' AND p_faena_id IS NULL THEN
        RAISE EXCEPTION 'destino=faena requiere faena_id';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    -- Lock estanque
    SELECT * INTO v_estanque FROM combustible_estanques WHERE id = p_estanque_id FOR UPDATE;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;

    IF v_estanque.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente en estanque %: actual % lt, solicitado % lt',
            v_estanque.codigo, v_estanque.stock_teorico_lt, p_litros;
    END IF;

    v_cpp_actual  := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_costo_total := ROUND((p_litros * v_cpp_actual)::numeric, 2);
    v_stock_post  := v_estanque.stock_teorico_lt - p_litros;
    -- CPP no cambia en salidas (CPP movil aritmetico)
    v_valor_post  := ROUND((v_stock_post * v_cpp_actual)::numeric, 2);

    v_tipo_kardex := CASE p_destino_tipo
        WHEN 'equipo'         THEN 'salida_equipo'
        WHEN 'venta_externa'  THEN 'salida_venta'
        ELSE                       'salida_despacho'
    END;

    -- Folio
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_salida_combustible') THEN
        SELECT fn_generar_folio_salida_combustible() INTO v_folio;
    ELSE
        v_folio := 'SCB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        equipo_id, ceco_id, cliente_nombre_manual,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_actual,
        v_stock_post, v_cpp_actual, v_valor_post,
        p_evidencia_url, COALESCE(p_observacion, p_motivo), v_user_id
    );

    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_post,
           valor_total_stock = v_valor_post,
           updated_at        = NOW()
     WHERE id = p_estanque_id;
    -- costo_promedio_lt NO cambia en salidas

    RETURN jsonb_build_object(
        'success', true,
        'kardex_id', v_kardex_id,
        'folio', v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_salida', p_litros,
        'destino_tipo', p_destino_tipo,
        'cpp_vigente', v_cpp_actual,
        'costo_total', v_costo_total,
        'stock_anterior', v_estanque.stock_teorico_lt,
        'stock_nuevo', v_stock_post,
        'tipo_movimiento_kardex', v_tipo_kardex
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_salida_combustible_valorizada IS
'Salida valorizada al CPP vigente. NO modifica CPP. Mapea destino_tipo a tipo_movimiento del kardex (equipo->salida_equipo, venta_externa->salida_venta, resto->salida_despacho). No toca movimientos legacy. MIG40.';


-- ============================================================================
-- BLOQUE 3: VISTAS
-- ============================================================================

-- 3.1 Stock valorizado (alias semantico — mismo set que mig 57 _actual)
DROP VIEW IF EXISTS public.v_combustible_stock_valorizado CASCADE;
CREATE VIEW v_combustible_stock_valorizado AS
SELECT
    e.id                       AS estanque_id,
    e.codigo                   AS estanque_codigo,
    e.nombre                   AS estanque_nombre,
    e.faena_id,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.stock_minimo_alerta_lt,
    e.costo_promedio_lt        AS cpp_actual,
    e.valor_total_stock        AS valor_total_clp,
    ROUND((e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0) * 100)::numeric, 1) AS pct_llenado,
    e.activo,
    e.updated_at
FROM combustible_estanques e;

COMMENT ON VIEW v_combustible_stock_valorizado IS
'Stock valorizado actual por estanque (alias con cpp_actual y valor_total_clp). MIG40.';


-- 3.2 Movimientos valorizados (kardex con joins amigables)
DROP VIEW IF EXISTS public.v_combustible_movimientos_valorizados CASCADE;
CREATE VIEW v_combustible_movimientos_valorizados AS
SELECT
    ckv.id                      AS kardex_id,
    ckv.fecha_movimiento,
    ckv.tipo_movimiento,
    ckv.folio_movimiento,
    ckv.estanque_id,
    e.codigo                    AS estanque_codigo,
    e.nombre                    AS estanque_nombre,
    ckv.litros_entrada,
    ckv.litros_salida,
    ckv.costo_unitario_movimiento,
    ckv.stock_lt_despues,
    ckv.costo_promedio_lt_despues AS cpp_despues,
    ckv.valor_stock_despues,
    ckv.proveedor_id,
    pr.nombre                   AS proveedor_nombre,
    ckv.equipo_id,
    a.codigo                    AS equipo_codigo,
    a.nombre                    AS equipo_nombre,
    ckv.ceco_id,
    cc.codigo                   AS ceco_codigo,
    cc.nombre                   AS ceco_nombre,
    ckv.cliente_nombre_manual,
    ckv.documento_numero,
    ckv.observacion,
    ckv.evidencia_url,
    ckv.created_by,
    ckv.created_at
FROM combustible_kardex_valorizado ckv
JOIN combustible_estanques e   ON e.id = ckv.estanque_id
LEFT JOIN proveedores pr       ON pr.id = ckv.proveedor_id
LEFT JOIN activos a            ON a.id = ckv.equipo_id
LEFT JOIN centros_costo cc     ON cc.id = ckv.ceco_id;

COMMENT ON VIEW v_combustible_movimientos_valorizados IS
'Kardex valorizado con joins amigables (proveedor, equipo, CECO). MIG40.';


-- 3.3 Control kardex vs varillaje (estado de control consolidado)
DROP VIEW IF EXISTS public.v_combustible_control_kardex_varillaje CASCADE;
CREATE VIEW v_combustible_control_kardex_varillaje AS
WITH ultima_varilla AS (
    SELECT DISTINCT ON (estanque_id)
        estanque_id,
        fecha             AS varilla_fecha,
        medicion_fisica_lt AS varilla_fisico_lt,
        stock_teorico_snapshot_lt,
        diferencia_lt,
        observaciones     AS varilla_observaciones
    FROM combustible_varillaje
    ORDER BY estanque_id, fecha DESC, created_at DESC
),
ultimo_kardex AS (
    SELECT DISTINCT ON (estanque_id)
        estanque_id,
        fecha_movimiento  AS kardex_fecha,
        tipo_movimiento   AS kardex_tipo,
        stock_lt_despues  AS kardex_stock_lt,
        costo_promedio_lt_despues AS kardex_cpp,
        valor_stock_despues AS kardex_valor
    FROM combustible_kardex_valorizado
    ORDER BY estanque_id, fecha_movimiento DESC, created_at DESC
)
SELECT
    e.id                        AS estanque_id,
    e.codigo                    AS estanque_codigo,
    e.nombre                    AS estanque_nombre,
    e.activo,
    e.faena_id,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.costo_promedio_lt         AS cpp_actual,
    e.valor_total_stock         AS valor_teorico_clp,
    uv.varilla_fecha            AS fecha_ultimo_varillaje,
    uv.varilla_fisico_lt        AS ultimo_varillaje_lt,
    uk.kardex_fecha             AS fecha_ultimo_movimiento,
    uk.kardex_tipo              AS tipo_ultimo_movimiento,
    -- delta fisico vs teorico actual
    CASE WHEN uv.varilla_fisico_lt IS NOT NULL
         THEN ROUND((uv.varilla_fisico_lt - e.stock_teorico_lt)::numeric, 2)
         ELSE NULL END          AS delta_lt,
    CASE WHEN uv.varilla_fisico_lt IS NOT NULL AND e.stock_teorico_lt > 0
         THEN ROUND(((uv.varilla_fisico_lt - e.stock_teorico_lt) / e.stock_teorico_lt * 100)::numeric, 2)
         ELSE NULL END          AS delta_pct,
    CASE WHEN uv.varilla_fecha IS NOT NULL
         THEN (CURRENT_DATE - uv.varilla_fecha)
         ELSE NULL END          AS dias_desde_varilla,
    -- estado consolidado
    CASE
        WHEN e.stock_teorico_lt < 0                                  THEN 'stock_negativo'
        WHEN uv.varilla_fecha IS NULL                                THEN 'sin_varillaje'
        WHEN (CURRENT_DATE - uv.varilla_fecha) > 7                    THEN 'varillaje_atrasado'
        WHEN uv.varilla_fisico_lt IS NOT NULL
             AND ABS(uv.varilla_fisico_lt - e.stock_teorico_lt) > 50 THEN 'desviacion_fisica'
        ELSE 'cuadrado'
    END                          AS estado,
    e.stock_minimo_alerta_lt,
    e.stock_teorico_lt <= e.stock_minimo_alerta_lt AS bajo_minimo
FROM combustible_estanques e
LEFT JOIN ultima_varilla uv ON uv.estanque_id = e.id
LEFT JOIN ultimo_kardex   uk ON uk.estanque_id = e.id
ORDER BY e.codigo;

COMMENT ON VIEW v_combustible_control_kardex_varillaje IS
'Control consolidado por estanque: stock teorico vs ultimo varillaje vs ultimo kardex valorizado. Estados: cuadrado/sin_varillaje/varillaje_atrasado/desviacion_fisica/stock_negativo. MIG40.';


-- ============================================================================
-- BLOQUE 4: GRANTs
-- ============================================================================
GRANT EXECUTE ON FUNCTION rpc_registrar_ingreso_combustible_valorizado TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_registrar_salida_combustible_valorizada  TO authenticated;
GRANT SELECT ON v_combustible_stock_valorizado            TO authenticated;
GRANT SELECT ON v_combustible_movimientos_valorizados     TO authenticated;
GRANT SELECT ON v_combustible_control_kardex_varillaje    TO authenticated;


-- ============================================================================
-- BLOQUE 5: VALIDACIONES POST
-- ============================================================================
DO $$
DECLARE
    v_n_funcs INT; v_n_vistas INT; v_n_estanques INT; v_neg INT;
    v_desviados INT;
BEGIN
    SELECT COUNT(*) INTO v_n_funcs FROM pg_proc
     WHERE proname IN ('rpc_registrar_ingreso_combustible_valorizado',
                       'rpc_registrar_salida_combustible_valorizada');
    IF v_n_funcs <> 2 THEN
        RAISE EXCEPTION 'STOP - esperaba 2 RPCs nuevas, encontre %', v_n_funcs;
    END IF;

    SELECT COUNT(*) INTO v_n_vistas FROM pg_views
     WHERE schemaname='public'
       AND viewname IN ('v_combustible_stock_valorizado',
                        'v_combustible_movimientos_valorizados',
                        'v_combustible_control_kardex_varillaje');
    IF v_n_vistas <> 3 THEN
        RAISE EXCEPTION 'STOP - esperaba 3 vistas nuevas, encontre %', v_n_vistas;
    END IF;

    -- Confirmar que el control devuelve los estanques
    SELECT COUNT(*) INTO v_n_estanques FROM v_combustible_control_kardex_varillaje;
    IF v_n_estanques = 0 THEN
        RAISE EXCEPTION 'STOP - v_combustible_control_kardex_varillaje no retorna estanques';
    END IF;

    -- Sanidad: no debe haber stock negativo
    SELECT COUNT(*) INTO v_neg FROM combustible_estanques WHERE stock_teorico_lt < 0;
    IF v_neg <> 0 THEN
        RAISE EXCEPTION 'STOP - hay % estanques con stock negativo tras mig', v_neg;
    END IF;

    -- Sanidad: reconciliacion productos sigue cuadrada
    SELECT COUNT(*) INTO v_desviados FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados <> 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion productos/FIFO se rompio (% desviados)', v_desviados;
    END IF;

    RAISE NOTICE '== MIG40 aplicada OK ==';
    RAISE NOTICE '   2 RPCs nuevas: rpc_registrar_ingreso/salida_combustible_valorizada';
    RAISE NOTICE '   3 vistas nuevas: v_combustible_stock_valorizado, _movimientos_valorizados, _control_kardex_varillaje';
    RAISE NOTICE '   % estanques en control, 0 stock negativo, reconciliacion productos intacta', v_n_estanques;
END $$;


-- Resultset de verificacion
SELECT 'rpc_ingreso_valorizado'         AS dx, COUNT(*)::text AS val FROM pg_proc WHERE proname='rpc_registrar_ingreso_combustible_valorizado'
UNION ALL SELECT 'rpc_salida_valorizada',       COUNT(*)::text FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada'
UNION ALL SELECT 'v_combustible_stock_valorizado', COUNT(*)::text FROM pg_views WHERE viewname='v_combustible_stock_valorizado'
UNION ALL SELECT 'v_combustible_movimientos_valorizados', COUNT(*)::text FROM pg_views WHERE viewname='v_combustible_movimientos_valorizados'
UNION ALL SELECT 'v_combustible_control_kardex_varillaje', COUNT(*)::text FROM pg_views WHERE viewname='v_combustible_control_kardex_varillaje'
UNION ALL SELECT 'estanques_en_control',          COUNT(*)::text FROM v_combustible_control_kardex_varillaje
UNION ALL SELECT 'estanques_stock_negativo',      COUNT(*)::text FROM combustible_estanques WHERE stock_teorico_lt < 0
UNION ALL SELECT 'reconciliacion_productos_cuadrado',
                  (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion='cuadrado')
UNION ALL SELECT 'reconciliacion_productos_desviado',
                  (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion<>'cuadrado');


-- Log
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG40_END',
            'MIG40 combustible CPP movil + 3 vistas aplicada',
            'ok',
            'Smoke test en smoke_test_40_combustible_cpp.sql'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK (manual, si nadie ejecuto las RPCs todavia)
-- ----------------------------------------------------------------------------
-- DROP VIEW IF EXISTS v_combustible_control_kardex_varillaje;
-- DROP VIEW IF EXISTS v_combustible_movimientos_valorizados;
-- DROP VIEW IF EXISTS v_combustible_stock_valorizado;
-- DROP FUNCTION IF EXISTS rpc_registrar_salida_combustible_valorizada(UUID,NUMERIC,VARCHAR,TEXT,UUID,UUID,UUID,UUID,VARCHAR,TIMESTAMPTZ,TEXT,TEXT);
-- DROP FUNCTION IF EXISTS rpc_registrar_ingreso_combustible_valorizado(UUID,NUMERIC,NUMERIC,UUID,VARCHAR,VARCHAR,TIMESTAMPTZ,TEXT,TEXT);
-- ============================================================================
