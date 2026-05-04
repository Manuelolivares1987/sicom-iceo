-- ============================================================================
-- 12_seed_stock_inicial_combustible_produccion.sql
-- ----------------------------------------------------------------------------
-- Carga STOCK INICIAL de combustible por estanque.
-- Soporta DOS modos: definitivo (costo real validado) y PROVISORIO
-- (costo pendiente confirmacion Finanzas, regularizable luego con 12B).
--
-- DEPENDENCIAS PREVIAS:
--   - mig 55, 56, 57 aplicadas (pasos 04, 07, 10).
--   - 12A_precheck_stock_inicial_combustible.sql ya revisado.
--
-- COMPORTAMIENTO:
--   - Solo procesa estanques explicitamente listados (hoy: EST-15K, EST-1K).
--   - EST-600: EXCLUIDO (stock_teorico_lt = 0 segun 12A).
--   - Idempotente: si un estanque ya tiene stock_inicial activo, registra
--     YA_EXISTE y NO reinserta.
--   - Si TODA la configuracion esta vacia (NULLs) → STOP global, NO inserts.
--   - Reproduce la logica del RPC `rpc_registrar_stock_inicial_combustible`
--     (no se invoca el RPC porque desde SQL Editor de Supabase auth.uid()=NULL
--     y el RPC abortaria con "No autenticado"; mismo patron que 09_seed FIFO).
--
-- MODO PROVISORIO (`permitir_carga_provisoria = true`):
--   - Marca observacion con prefijo "[PROVISORIO] Carga provisoria - pendiente
--     Finanzas." (la frase literal exigida por la regla de paso 12).
--   - Folio del kardex inicial: "STOCK-INICIAL-PROVISORIO-<uuid4>".
--   - Relaja exigencia de email del responsable (puede quedar NULL).
--   - Resultado final: WARNING_STOCK_INICIAL_COMBUSTIBLE_PROVISORIO.
--   - Requiere ejecutar 12B_regularizar_stock_inicial_combustible.sql cuando
--     Finanzas confirme el costo real.
--
-- MODO DEFINITIVO (`permitir_carga_provisoria = false`, DEFAULT):
--   - Exige observacion >= 5 chars y responsable_em valido en usuarios_perfil.
--   - Folio del kardex inicial: "INI-YYYYMMDD-<uuid4>" (igual que RPC).
--   - Resultado final: OK_STOCK_INICIAL_COMBUSTIBLE.
--
-- DEVUELVE 1 fila final con:
--   resultado, detalle, estanques_procesados, estanques_pendientes,
--   litros_totales, valor_total (o valor_total_provisorio si aplica),
--   kardex_registros_creados, requiere_regularizacion, detalle_regularizacion.
-- ============================================================================


-- ── 0. Precheck rapido de dependencias ──────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_stock_inicial') THEN
        RAISE EXCEPTION 'STOP — combustible_stock_inicial no existe. Ejecutar primero paso 10 (mig 57).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP — combustible_kardex_valorizado no existe. Ejecutar primero paso 10 (mig 57).';
    END IF;
END $$;


-- ── 1. Tabla temporal acumuladora ───────────────────────────────────
DROP TABLE IF EXISTS _t_seed_stock_inicial_combustible;
CREATE TEMP TABLE _t_seed_stock_inicial_combustible (
    estanque_codigo  TEXT PRIMARY KEY,
    estado_proceso   TEXT,        -- OK | YA_EXISTE | FALTA_DATOS | NO_ENCONTRADO | PLACEHOLDER
    es_provisorio    BOOLEAN NOT NULL DEFAULT false,
    detalle          TEXT,
    stock_inicial_id UUID,
    kardex_id        UUID,
    litros           NUMERIC,
    costo            NUMERIC,
    valor            NUMERIC
);


-- ── 2. SECCION DE CONFIGURACION (operador completa antes de ejecutar) ─
DO $$
DECLARE
    -- =========================================================
    -- ⚠️  MODO DE CARGA
    -- =========================================================
    -- false = definitivo (default). true = provisorio (costo Finanzas pendiente).
    permitir_carga_provisoria BOOLEAN := true;   -- MODO PROVISORIO ACTIVO (pruebas tecnicas)

    -- =========================================================
    -- VALORES COMPLETADOS (modo provisorio).
    -- EST-600: EXCLUIDO (stock_teorico_lt = 0 segun 12A). NO incluir aqui.
    -- responsable_em y documento_url permanecen NULL — permitido en provisorio.
    -- =========================================================

    -- EST-15K (varillaje fisico Gustavo: 5414 lt; costo provisorio para pruebas)
    cfg_est15k_litros           NUMERIC := 5414;
    cfg_est15k_costo            NUMERIC := 1000;
    cfg_est15k_observacion      TEXT    := 'Carga provisoria para pruebas tecnicas. Pendiente costo real Finanzas.';
    cfg_est15k_responsable_em   TEXT    := NULL;
    cfg_est15k_documento_url    TEXT    := NULL;

    -- EST-1K (varillaje fisico Gustavo: 630 lt; costo provisorio para pruebas)
    cfg_est1k_litros            NUMERIC := 630;
    cfg_est1k_costo             NUMERIC := 1000;
    cfg_est1k_observacion       TEXT    := 'Carga provisoria para pruebas tecnicas. Pendiente costo real Finanzas.';
    cfg_est1k_responsable_em    TEXT    := NULL;
    cfg_est1k_documento_url     TEXT    := NULL;

    -- =========================================================
    -- Variables internas
    -- =========================================================
    v_archivo_sin_completar BOOLEAN;
    v_fecha     DATE := CURRENT_DATE;

    v_codigo        TEXT;
    v_litros        NUMERIC;
    v_costo         NUMERIC;
    v_obs_in        TEXT;
    v_resp_email    TEXT;
    v_doc_url       TEXT;

    v_estanque_id   UUID;
    v_responsable_id UUID;
    v_ya_existe     UUID;
    v_si_id         UUID;
    v_kardex_id     UUID;
    v_valor         NUMERIC;
    v_obs_final     TEXT;
    v_folio_kardex  TEXT;

    v_marca_provisorio CONSTANT TEXT := '[PROVISORIO] Carga provisoria - pendiente Finanzas.';
BEGIN
    -- ── 2.1 Deteccion de PLACEHOLDER GLOBAL ─────────────────────────
    -- En modo definitivo: TODOS los cfg obligatorios en NULL → STOP global.
    -- En modo provisorio: basta con que litros y costo de TODOS esten en NULL.
    IF permitir_carga_provisoria THEN
        v_archivo_sin_completar := (
            cfg_est15k_litros IS NULL AND cfg_est15k_costo IS NULL
            AND cfg_est1k_litros  IS NULL AND cfg_est1k_costo  IS NULL
        );
    ELSE
        v_archivo_sin_completar := (
            cfg_est15k_litros IS NULL AND cfg_est15k_costo IS NULL
            AND cfg_est15k_observacion IS NULL AND cfg_est15k_responsable_em IS NULL
            AND cfg_est1k_litros  IS NULL AND cfg_est1k_costo  IS NULL
            AND cfg_est1k_observacion  IS NULL AND cfg_est1k_responsable_em  IS NULL
        );
    END IF;

    IF v_archivo_sin_completar THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (
            '__GLOBAL__', 'PLACEHOLDER',
            'Archivo sin completar. Todos los cfg en NULL. NO se ejecutan inserts.'
        );
        RAISE NOTICE 'STOP — placeholders detectados en TODA la configuracion. NO se ejecutan inserts.';
        RETURN;
    END IF;

    -- ============================================================
    -- ── 2.2 PROCESAR EST-15K ────────────────────────────────────
    -- ============================================================
    v_codigo := 'EST-15K';
    v_litros := cfg_est15k_litros;
    v_costo  := cfg_est15k_costo;
    v_obs_in := cfg_est15k_observacion;
    v_resp_email := cfg_est15k_responsable_em;
    v_doc_url := cfg_est15k_documento_url;
    v_estanque_id := NULL;
    v_responsable_id := NULL;
    v_ya_existe := NULL;
    v_si_id := NULL;
    v_kardex_id := NULL;
    v_valor := NULL;

    IF v_litros IS NULL OR v_costo IS NULL
       OR (NOT permitir_carga_provisoria AND (v_obs_in IS NULL OR v_resp_email IS NULL)) THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'PLACEHOLDER',
                'Faltan valores obligatorios en CONFIGURACION (litros/costo' ||
                CASE WHEN NOT permitir_carga_provisoria THEN '/observacion/responsable_email' ELSE '' END ||
                ').');
    ELSIF v_litros <= 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'litros_iniciales debe ser > 0.');
    ELSIF v_costo <= 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS',
                CASE WHEN permitir_carga_provisoria
                     THEN 'costo_unitario_provisorio debe ser > 0.'
                     ELSE 'costo_unitario debe ser > 0.' END);
    ELSIF (NOT permitir_carga_provisoria) AND LENGTH(TRIM(v_obs_in)) < 5 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'observacion debe tener al menos 5 caracteres.');
    ELSIF (NOT permitir_carga_provisoria) AND LENGTH(TRIM(v_resp_email)) = 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'responsable_validacion (email) no puede estar vacio.');
    ELSE
        SELECT id INTO v_estanque_id
          FROM combustible_estanques
         WHERE codigo = v_codigo AND activo = true;

        IF v_estanque_id IS NULL THEN
            INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
            VALUES (v_codigo, 'NO_ENCONTRADO', 'Estanque no existe o no esta activo.');
        ELSE
            SELECT id INTO v_ya_existe
              FROM combustible_stock_inicial
             WHERE estanque_id = v_estanque_id AND anulado = false;

            IF v_ya_existe IS NOT NULL THEN
                INSERT INTO _t_seed_stock_inicial_combustible(
                    estanque_codigo, estado_proceso, detalle, stock_inicial_id
                ) VALUES (
                    v_codigo, 'YA_EXISTE',
                    'Ya existe stock_inicial activo. Idempotente: no se inserta.',
                    v_ya_existe
                );
            ELSE
                -- Lookup responsable (en provisorio puede ser NULL)
                IF v_resp_email IS NOT NULL AND LENGTH(TRIM(v_resp_email)) > 0 THEN
                    SELECT id INTO v_responsable_id
                      FROM usuarios_perfil
                     WHERE LOWER(email) = LOWER(TRIM(v_resp_email)) AND activo = true
                     LIMIT 1;

                    IF v_responsable_id IS NULL AND NOT permitir_carga_provisoria THEN
                        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
                        VALUES (v_codigo, 'NO_ENCONTRADO',
                                'Usuario responsable_validacion no encontrado/activo en usuarios_perfil: ' || v_resp_email);
                    END IF;
                END IF;

                IF (permitir_carga_provisoria) OR (v_responsable_id IS NOT NULL) THEN
                    -- Construir observacion y folio segun modo
                    IF permitir_carga_provisoria THEN
                        v_obs_final := v_marca_provisorio ||
                                       CASE WHEN v_obs_in IS NOT NULL AND LENGTH(TRIM(v_obs_in)) > 0
                                            THEN ' ' || TRIM(v_obs_in) ELSE '' END;
                        v_folio_kardex := 'STOCK-INICIAL-PROVISORIO-' || SUBSTRING(gen_random_uuid()::TEXT, 1, 4);
                    ELSE
                        v_obs_final := TRIM(v_obs_in);
                        v_folio_kardex := 'INI-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' ||
                                          SUBSTRING(v_estanque_id::TEXT, 1, 4);
                    END IF;

                    -- INSERT directo (replica RPC)
                    v_si_id     := gen_random_uuid();
                    v_kardex_id := gen_random_uuid();
                    v_valor     := v_litros * v_costo;

                    INSERT INTO combustible_stock_inicial (
                        id, estanque_id, fecha, litros_iniciales, costo_unitario_inicial,
                        documento_respaldo_url, registrado_por, observacion, created_by
                    ) VALUES (
                        v_si_id, v_estanque_id, v_fecha, v_litros, v_costo,
                        v_doc_url, v_responsable_id, v_obs_final, v_responsable_id
                    );

                    UPDATE combustible_estanques
                       SET stock_teorico_lt   = v_litros,
                           costo_promedio_lt  = v_costo,
                           valor_total_stock  = v_valor,
                           updated_at         = NOW()
                     WHERE id = v_estanque_id;

                    INSERT INTO combustible_kardex_valorizado (
                        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
                        stock_inicial_id, litros_entrada, litros_salida, costo_unitario_movimiento,
                        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
                        evidencia_url, observacion, created_by
                    ) VALUES (
                        v_kardex_id, v_estanque_id, v_fecha::TIMESTAMPTZ, 'stock_inicial', v_folio_kardex,
                        v_si_id, v_litros, 0, v_costo,
                        v_litros, v_costo, v_valor,
                        v_doc_url, v_obs_final, v_responsable_id
                    );

                    INSERT INTO _t_seed_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, es_provisorio, detalle,
                        stock_inicial_id, kardex_id, litros, costo, valor
                    ) VALUES (
                        v_codigo,
                        CASE WHEN permitir_carga_provisoria THEN 'OK_PROVISORIO' ELSE 'OK' END,
                        permitir_carga_provisoria,
                        CASE WHEN permitir_carga_provisoria
                             THEN 'Stock inicial PROVISORIO registrado. Regularizar con 12B cuando Finanzas confirme costo real.'
                             ELSE 'Stock inicial registrado correctamente.' END,
                        v_si_id, v_kardex_id, v_litros, v_costo, v_valor
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- ============================================================
    -- ── 2.3 PROCESAR EST-1K ─────────────────────────────────────
    -- ============================================================
    v_codigo := 'EST-1K';
    v_litros := cfg_est1k_litros;
    v_costo  := cfg_est1k_costo;
    v_obs_in := cfg_est1k_observacion;
    v_resp_email := cfg_est1k_responsable_em;
    v_doc_url := cfg_est1k_documento_url;
    v_estanque_id := NULL;
    v_responsable_id := NULL;
    v_ya_existe := NULL;
    v_si_id := NULL;
    v_kardex_id := NULL;
    v_valor := NULL;
    v_obs_final := NULL;
    v_folio_kardex := NULL;

    IF v_litros IS NULL OR v_costo IS NULL
       OR (NOT permitir_carga_provisoria AND (v_obs_in IS NULL OR v_resp_email IS NULL)) THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'PLACEHOLDER',
                'Faltan valores obligatorios en CONFIGURACION (litros/costo' ||
                CASE WHEN NOT permitir_carga_provisoria THEN '/observacion/responsable_email' ELSE '' END ||
                ').');
    ELSIF v_litros <= 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'litros_iniciales debe ser > 0.');
    ELSIF v_costo <= 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS',
                CASE WHEN permitir_carga_provisoria
                     THEN 'costo_unitario_provisorio debe ser > 0.'
                     ELSE 'costo_unitario debe ser > 0.' END);
    ELSIF (NOT permitir_carga_provisoria) AND LENGTH(TRIM(v_obs_in)) < 5 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'observacion debe tener al menos 5 caracteres.');
    ELSIF (NOT permitir_carga_provisoria) AND LENGTH(TRIM(v_resp_email)) = 0 THEN
        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'responsable_validacion (email) no puede estar vacio.');
    ELSE
        SELECT id INTO v_estanque_id
          FROM combustible_estanques
         WHERE codigo = v_codigo AND activo = true;

        IF v_estanque_id IS NULL THEN
            INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
            VALUES (v_codigo, 'NO_ENCONTRADO', 'Estanque no existe o no esta activo.');
        ELSE
            SELECT id INTO v_ya_existe
              FROM combustible_stock_inicial
             WHERE estanque_id = v_estanque_id AND anulado = false;

            IF v_ya_existe IS NOT NULL THEN
                INSERT INTO _t_seed_stock_inicial_combustible(
                    estanque_codigo, estado_proceso, detalle, stock_inicial_id
                ) VALUES (
                    v_codigo, 'YA_EXISTE',
                    'Ya existe stock_inicial activo. Idempotente: no se inserta.',
                    v_ya_existe
                );
            ELSE
                IF v_resp_email IS NOT NULL AND LENGTH(TRIM(v_resp_email)) > 0 THEN
                    SELECT id INTO v_responsable_id
                      FROM usuarios_perfil
                     WHERE LOWER(email) = LOWER(TRIM(v_resp_email)) AND activo = true
                     LIMIT 1;

                    IF v_responsable_id IS NULL AND NOT permitir_carga_provisoria THEN
                        INSERT INTO _t_seed_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
                        VALUES (v_codigo, 'NO_ENCONTRADO',
                                'Usuario responsable_validacion no encontrado/activo en usuarios_perfil: ' || v_resp_email);
                    END IF;
                END IF;

                IF (permitir_carga_provisoria) OR (v_responsable_id IS NOT NULL) THEN
                    IF permitir_carga_provisoria THEN
                        v_obs_final := v_marca_provisorio ||
                                       CASE WHEN v_obs_in IS NOT NULL AND LENGTH(TRIM(v_obs_in)) > 0
                                            THEN ' ' || TRIM(v_obs_in) ELSE '' END;
                        v_folio_kardex := 'STOCK-INICIAL-PROVISORIO-' || SUBSTRING(gen_random_uuid()::TEXT, 1, 4);
                    ELSE
                        v_obs_final := TRIM(v_obs_in);
                        v_folio_kardex := 'INI-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' ||
                                          SUBSTRING(v_estanque_id::TEXT, 1, 4);
                    END IF;

                    v_si_id     := gen_random_uuid();
                    v_kardex_id := gen_random_uuid();
                    v_valor     := v_litros * v_costo;

                    INSERT INTO combustible_stock_inicial (
                        id, estanque_id, fecha, litros_iniciales, costo_unitario_inicial,
                        documento_respaldo_url, registrado_por, observacion, created_by
                    ) VALUES (
                        v_si_id, v_estanque_id, v_fecha, v_litros, v_costo,
                        v_doc_url, v_responsable_id, v_obs_final, v_responsable_id
                    );

                    UPDATE combustible_estanques
                       SET stock_teorico_lt   = v_litros,
                           costo_promedio_lt  = v_costo,
                           valor_total_stock  = v_valor,
                           updated_at         = NOW()
                     WHERE id = v_estanque_id;

                    INSERT INTO combustible_kardex_valorizado (
                        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
                        stock_inicial_id, litros_entrada, litros_salida, costo_unitario_movimiento,
                        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
                        evidencia_url, observacion, created_by
                    ) VALUES (
                        v_kardex_id, v_estanque_id, v_fecha::TIMESTAMPTZ, 'stock_inicial', v_folio_kardex,
                        v_si_id, v_litros, 0, v_costo,
                        v_litros, v_costo, v_valor,
                        v_doc_url, v_obs_final, v_responsable_id
                    );

                    INSERT INTO _t_seed_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, es_provisorio, detalle,
                        stock_inicial_id, kardex_id, litros, costo, valor
                    ) VALUES (
                        v_codigo,
                        CASE WHEN permitir_carga_provisoria THEN 'OK_PROVISORIO' ELSE 'OK' END,
                        permitir_carga_provisoria,
                        CASE WHEN permitir_carga_provisoria
                             THEN 'Stock inicial PROVISORIO registrado. Regularizar con 12B cuando Finanzas confirme costo real.'
                             ELSE 'Stock inicial registrado correctamente.' END,
                        v_si_id, v_kardex_id, v_litros, v_costo, v_valor
                    );
                END IF;
            END IF;
        END IF;
    END IF;

END $$;


-- ── 3. Bitacora ─────────────────────────────────────────────────────
DO $$
DECLARE
    v_resultado_str TEXT;
    v_detalle_str   TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN

        SELECT
            CASE
                WHEN MAX(CASE WHEN estanque_codigo='__GLOBAL__' AND estado_proceso='PLACEHOLDER' THEN 1 ELSE 0 END) = 1
                    THEN 'STOP_STOCK_INICIAL_COMBUSTIBLE'
                WHEN bool_or(estado_proceso IN ('FALTA_DATOS','NO_ENCONTRADO'))
                    THEN 'STOP_STOCK_INICIAL_COMBUSTIBLE'
                WHEN bool_or(estado_proceso = 'PLACEHOLDER')
                    THEN 'WARNING_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE'
                WHEN bool_or(es_provisorio = true)
                    THEN 'WARNING_STOCK_INICIAL_COMBUSTIBLE_PROVISORIO'
                ELSE 'OK_STOCK_INICIAL_COMBUSTIBLE'
            END,
            string_agg(estanque_codigo || '=' || estado_proceso, '; ' ORDER BY estanque_codigo)
          INTO v_resultado_str, v_detalle_str
        FROM _t_seed_stock_inicial_combustible;

        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_CPP_STOCK_INICIAL',
            'Stock inicial combustible (paso 12) — manual con Finanzas + varillaje fisico.',
            current_user,
            NOW(), NOW(),
            CASE WHEN v_resultado_str = 'OK_STOCK_INICIAL_COMBUSTIBLE' THEN 'ok'
                 WHEN v_resultado_str = 'WARNING_STOCK_INICIAL_COMBUSTIBLE_PROVISORIO' THEN 'warning'
                 ELSE 'pendiente' END,
            COALESCE(v_resultado_str, 'sin_filas') || ' | ' || COALESCE(v_detalle_str, '')
        );
    END IF;
END $$;


-- ── 4. FILA FINAL RESUMEN ───────────────────────────────────────────
SELECT
    CASE
        WHEN MAX(CASE WHEN estanque_codigo='__GLOBAL__' AND estado_proceso='PLACEHOLDER' THEN 1 ELSE 0 END) = 1
            THEN 'STOP_STOCK_INICIAL_COMBUSTIBLE'
        WHEN bool_or(estado_proceso IN ('FALTA_DATOS','NO_ENCONTRADO'))
            THEN 'STOP_STOCK_INICIAL_COMBUSTIBLE'
        WHEN bool_or(estado_proceso = 'PLACEHOLDER')
            THEN 'WARNING_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE'
        WHEN bool_or(es_provisorio = true)
            THEN 'WARNING_STOCK_INICIAL_COMBUSTIBLE_PROVISORIO'
        ELSE 'OK_STOCK_INICIAL_COMBUSTIBLE'
    END                                                                       AS resultado,
    string_agg(
        estanque_codigo || '=' || estado_proceso ||
        CASE WHEN detalle IS NOT NULL AND detalle <> ''
             THEN ' (' || detalle || ')' ELSE '' END,
        ' | ' ORDER BY estanque_codigo
    )                                                                         AS detalle,
    COUNT(*) FILTER (WHERE estado_proceso IN ('OK','OK_PROVISORIO'))::int     AS estanques_procesados,
    COUNT(*) FILTER (
        WHERE estanque_codigo <> '__GLOBAL__'
          AND estado_proceso IN ('FALTA_DATOS','NO_ENCONTRADO','PLACEHOLDER')
    )::int                                                                     AS estanques_pendientes,
    COALESCE(SUM(CASE WHEN estado_proceso IN ('OK','OK_PROVISORIO') THEN litros END), 0) AS litros_totales,
    COALESCE(SUM(CASE WHEN estado_proceso = 'OK' THEN valor END), 0)          AS valor_total,
    COALESCE(SUM(CASE WHEN estado_proceso = 'OK_PROVISORIO' THEN valor END), 0) AS valor_total_provisorio,
    COUNT(*) FILTER (
        WHERE estado_proceso IN ('OK','OK_PROVISORIO') AND kardex_id IS NOT NULL
    )::int                                                                     AS kardex_registros_creados,
    bool_or(es_provisorio = true)                                              AS requiere_regularizacion,
    CASE WHEN bool_or(es_provisorio = true)
         THEN 'Reemplazar costo provisorio por costo real validado por Finanzas (ejecutar 12B_regularizar_stock_inicial_combustible.sql).'
         ELSE NULL END                                                         AS detalle_regularizacion
FROM _t_seed_stock_inicial_combustible;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_STOCK_INICIAL_COMBUSTIBLE
--     Todos los configurados quedaron OK o YA_EXISTE. Avanzar al paso 13.
--
-- - resultado = WARNING_STOCK_INICIAL_COMBUSTIBLE_PROVISORIO
--     Al menos un estanque se cargo con costo PROVISORIO. requiere_regularizacion=true.
--     Coordinar con Finanzas y ejecutar 12B cuando entreguen el costo real.
--
-- - resultado = WARNING_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE
--     Algun estanque quedo sin completar (PLACEHOLDER). Completar y re-ejecutar.
--
-- - resultado = STOP_STOCK_INICIAL_COMBUSTIBLE
--     - GLOBAL=PLACEHOLDER → archivo sin completar, NO se inserto nada.
--     - FALTA_DATOS / NO_ENCONTRADO → leer columna `detalle` y corregir.
--
-- VERIFICACION POST (manual):
--   SELECT * FROM v_combustible_stock_valorizado_actual ORDER BY estanque_codigo;
--   SELECT folio_movimiento, observacion FROM combustible_kardex_valorizado
--    WHERE tipo_movimiento='stock_inicial' ORDER BY fecha_movimiento DESC;
-- ============================================================================
