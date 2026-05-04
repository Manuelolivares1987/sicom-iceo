-- ============================================================================
-- 12B_regularizar_stock_inicial_combustible.sql
-- ----------------------------------------------------------------------------
-- Reemplaza el costo unitario PROVISORIO de stock_inicial por el COSTO REAL
-- validado por Finanzas. Idempotente. NO duplica kardex. NO altera litros.
--
-- DEPENDENCIAS PREVIAS:
--   - 12_seed_stock_inicial_combustible_produccion.sql ejecutado en MODO_PROVISORIO.
--   - Stock_inicial activo del estanque marcado con observacion '[PROVISORIO]'
--     y kardex_inicial con folio que empieza con 'STOCK-INICIAL-PROVISORIO-'.
--
-- COMPORTAMIENTO:
--   - Solo regulariza estanques cuyo stock_inicial activo este marcado como
--     [PROVISORIO]. Si ya esta regularizado → YA_REGULARIZADO (idempotente).
--   - Si no existe stock_inicial activo o no es provisorio → SIN_PROVISORIO.
--   - Exige costo_unitario_real > 0.
--   - Recalcula:
--       combustible_stock_inicial.costo_unitario_inicial
--           (valor_total_inicial es GENERATED → se recalcula auto)
--       combustible_estanques.costo_promedio_lt
--       combustible_estanques.valor_total_stock = stock_teorico_lt * costo_real
--       combustible_kardex_valorizado.costo_unitario_movimiento
--           (valor_entrada/valor_salida son GENERATED → se recalculan auto)
--       combustible_kardex_valorizado.costo_promedio_lt_despues
--       combustible_kardex_valorizado.valor_stock_despues
--       folio_movimiento del kardex inicial (de PROVISORIO → REGULARIZADO)
--       observacion (reemplaza marker [PROVISORIO] → [REGULARIZADO YYYY-MM-DD])
--   - NO toca litros (litros_iniciales / stock_lt_despues / stock_teorico_lt /
--     litros_entrada).
--   - NO inserta filas nuevas en combustible_kardex_valorizado.
--   - NO toca combustible_movimientos (movimientos historicos no relacionados
--     con stock_inicial quedan intactos).
--   - NO toca otros movimientos del kardex (solo el del stock_inicial).
--
-- DEVUELVE 1 fila final con:
--   resultado = OK_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE / WARNING / STOP
--   detalle, estanques_regularizados, estanques_omitidos,
--   delta_valor_total (suma de (litros * (costo_nuevo - costo_anterior))),
--   valor_total_post.
-- ============================================================================


-- ── 0. Precheck rapido ──────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_stock_inicial') THEN
        RAISE EXCEPTION 'STOP — combustible_stock_inicial no existe. Ejecutar primero paso 10 (mig 57).';
    END IF;
END $$;


-- ── 1. Tabla temporal acumuladora ───────────────────────────────────
DROP TABLE IF EXISTS _t_regularizar_stock_inicial_combustible;
CREATE TEMP TABLE _t_regularizar_stock_inicial_combustible (
    estanque_codigo  TEXT PRIMARY KEY,
    estado_proceso   TEXT,        -- OK_REGULARIZADO | YA_REGULARIZADO | SIN_PROVISORIO | SIN_STOCK_INICIAL | FALTA_DATOS | NO_ENCONTRADO | PLACEHOLDER
    detalle          TEXT,
    stock_inicial_id UUID,
    kardex_id        UUID,
    litros           NUMERIC,
    costo_anterior   NUMERIC,
    costo_nuevo      NUMERIC,
    valor_anterior   NUMERIC,
    valor_nuevo      NUMERIC
);


-- ── 2. SECCION DE CONFIGURACION (operador completa antes de ejecutar) ─
DO $$
DECLARE
    -- =========================================================
    -- ⚠️  COMPLETAR CON COSTO REAL VALIDADO POR FINANZAS (NULL = placeholder)
    -- =========================================================

    -- EST-15K
    cfg_est15k_costo_real        NUMERIC := NULL;   -- ⚠️ Finanzas: costo unitario real validado
    cfg_est15k_observacion_extra TEXT    := NULL;   -- opcional: nota Finanzas (referencia factura/guia)
    cfg_est15k_responsable_em    TEXT    := NULL;   -- email del usuario que valida (admin/subgerente)

    -- EST-1K
    cfg_est1k_costo_real         NUMERIC := NULL;
    cfg_est1k_observacion_extra  TEXT    := NULL;
    cfg_est1k_responsable_em     TEXT    := NULL;

    -- =========================================================
    -- Variables internas
    -- =========================================================
    v_archivo_sin_completar BOOLEAN;
    v_fecha_reg DATE := CURRENT_DATE;

    v_codigo        TEXT;
    v_costo_real    NUMERIC;
    v_obs_extra     TEXT;
    v_resp_email    TEXT;

    v_estanque_id   UUID;
    v_responsable_id UUID;
    v_si_id         UUID;
    v_si_litros     NUMERIC;
    v_si_costo_ant  NUMERIC;
    v_si_obs_ant    TEXT;
    v_kardex_id     UUID;
    v_kardex_folio_ant TEXT;
    v_kardex_obs_ant TEXT;
    v_valor_ant     NUMERIC;
    v_valor_nvo     NUMERIC;
    v_obs_nva_si    TEXT;
    v_obs_nva_kx    TEXT;
    v_folio_nvo     TEXT;
BEGIN
    v_archivo_sin_completar := (
        cfg_est15k_costo_real IS NULL AND cfg_est1k_costo_real IS NULL
    );

    IF v_archivo_sin_completar THEN
        INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (
            '__GLOBAL__', 'PLACEHOLDER',
            'Archivo sin completar. Todos los costo_real en NULL. NO se ejecutan updates.'
        );
        RAISE NOTICE 'STOP — placeholders detectados en TODA la configuracion. NO se ejecutan updates.';
        RETURN;
    END IF;

    -- ============================================================
    -- ── PROCESAR EST-15K ────────────────────────────────────────
    -- ============================================================
    v_codigo := 'EST-15K';
    v_costo_real := cfg_est15k_costo_real;
    v_obs_extra  := cfg_est15k_observacion_extra;
    v_resp_email := cfg_est15k_responsable_em;
    v_estanque_id := NULL; v_responsable_id := NULL;
    v_si_id := NULL; v_si_litros := NULL; v_si_costo_ant := NULL; v_si_obs_ant := NULL;
    v_kardex_id := NULL; v_kardex_folio_ant := NULL; v_kardex_obs_ant := NULL;
    v_valor_ant := NULL; v_valor_nvo := NULL; v_obs_nva_si := NULL; v_obs_nva_kx := NULL; v_folio_nvo := NULL;

    IF v_costo_real IS NULL THEN
        INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'PLACEHOLDER', 'cfg_est15k_costo_real = NULL. No se procesa.');
    ELSIF v_costo_real <= 0 THEN
        INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'costo_unitario_real debe ser > 0.');
    ELSE
        SELECT id INTO v_estanque_id
          FROM combustible_estanques
         WHERE codigo = v_codigo AND activo = true;

        IF v_estanque_id IS NULL THEN
            INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
            VALUES (v_codigo, 'NO_ENCONTRADO', 'Estanque no existe o no esta activo.');
        ELSE
            SELECT id, litros_iniciales, costo_unitario_inicial, observacion
              INTO v_si_id, v_si_litros, v_si_costo_ant, v_si_obs_ant
              FROM combustible_stock_inicial
             WHERE estanque_id = v_estanque_id AND anulado = false
             LIMIT 1;

            IF v_si_id IS NULL THEN
                INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
                VALUES (v_codigo, 'SIN_STOCK_INICIAL',
                        'No hay stock_inicial activo. Ejecutar 12 antes en MODO_PROVISORIO o DEFINITIVO.');
            ELSIF v_si_obs_ant IS NULL OR v_si_obs_ant NOT LIKE '[PROVISORIO]%' THEN
                IF v_si_obs_ant IS NOT NULL AND v_si_obs_ant LIKE '[REGULARIZADO%' THEN
                    INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle, stock_inicial_id)
                    VALUES (v_codigo, 'YA_REGULARIZADO',
                            'stock_inicial ya regularizado previamente. Idempotente: no se modifica.', v_si_id);
                ELSE
                    INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle, stock_inicial_id)
                    VALUES (v_codigo, 'SIN_PROVISORIO',
                            'stock_inicial activo NO esta marcado [PROVISORIO]. No requiere regularizacion.', v_si_id);
                END IF;
            ELSE
                -- Localizar kardex_inicial asociado
                SELECT id, folio_movimiento, observacion
                  INTO v_kardex_id, v_kardex_folio_ant, v_kardex_obs_ant
                  FROM combustible_kardex_valorizado
                 WHERE stock_inicial_id = v_si_id
                   AND tipo_movimiento = 'stock_inicial'
                 ORDER BY fecha_movimiento ASC
                 LIMIT 1;

                IF v_kardex_id IS NULL THEN
                    INSERT INTO _t_regularizar_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, detalle, stock_inicial_id
                    ) VALUES (
                        v_codigo, 'NO_ENCONTRADO',
                        'No se encontro kardex_inicial asociado al stock_inicial. Inconsistencia, revisar manualmente.',
                        v_si_id
                    );
                ELSE
                    -- Lookup responsable (opcional)
                    IF v_resp_email IS NOT NULL AND LENGTH(TRIM(v_resp_email)) > 0 THEN
                        SELECT id INTO v_responsable_id
                          FROM usuarios_perfil
                         WHERE LOWER(email) = LOWER(TRIM(v_resp_email)) AND activo = true
                         LIMIT 1;
                    END IF;

                    v_valor_ant := v_si_litros * v_si_costo_ant;
                    v_valor_nvo := v_si_litros * v_costo_real;

                    v_obs_nva_si := '[REGULARIZADO ' || TO_CHAR(v_fecha_reg, 'YYYY-MM-DD') || '] '
                                    || REPLACE(v_si_obs_ant, '[PROVISORIO] ', '')
                                    || CASE WHEN v_obs_extra IS NOT NULL AND LENGTH(TRIM(v_obs_extra)) > 0
                                            THEN ' | Finanzas: ' || TRIM(v_obs_extra) ELSE '' END;

                    v_obs_nva_kx := '[REGULARIZADO ' || TO_CHAR(v_fecha_reg, 'YYYY-MM-DD') || '] '
                                    || REPLACE(COALESCE(v_kardex_obs_ant, ''), '[PROVISORIO] ', '')
                                    || CASE WHEN v_obs_extra IS NOT NULL AND LENGTH(TRIM(v_obs_extra)) > 0
                                            THEN ' | Finanzas: ' || TRIM(v_obs_extra) ELSE '' END;

                    v_folio_nvo := 'REG-STOCK-INI-' || TO_CHAR(v_fecha_reg, 'YYYYMMDD') || '-' ||
                                   SUBSTRING(v_kardex_id::TEXT, 1, 4);

                    -- UPDATE stock_inicial (valor_total_inicial es GENERATED)
                    UPDATE combustible_stock_inicial
                       SET costo_unitario_inicial = v_costo_real,
                           observacion = v_obs_nva_si
                     WHERE id = v_si_id;

                    -- UPDATE estanque (costo_promedio + valor_total_stock)
                    UPDATE combustible_estanques
                       SET costo_promedio_lt = v_costo_real,
                           valor_total_stock = v_si_litros * v_costo_real,
                           updated_at = NOW()
                     WHERE id = v_estanque_id;

                    -- UPDATE kardex inicial (valor_entrada/valor_salida son GENERATED)
                    UPDATE combustible_kardex_valorizado
                       SET costo_unitario_movimiento = v_costo_real,
                           costo_promedio_lt_despues = v_costo_real,
                           valor_stock_despues = v_si_litros * v_costo_real,
                           folio_movimiento = v_folio_nvo,
                           observacion = v_obs_nva_kx
                     WHERE id = v_kardex_id;

                    INSERT INTO _t_regularizar_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, detalle,
                        stock_inicial_id, kardex_id, litros,
                        costo_anterior, costo_nuevo, valor_anterior, valor_nuevo
                    ) VALUES (
                        v_codigo, 'OK_REGULARIZADO',
                        'Costo provisorio reemplazado por costo real Finanzas.',
                        v_si_id, v_kardex_id, v_si_litros,
                        v_si_costo_ant, v_costo_real, v_valor_ant, v_valor_nvo
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- ============================================================
    -- ── PROCESAR EST-1K ─────────────────────────────────────────
    -- ============================================================
    v_codigo := 'EST-1K';
    v_costo_real := cfg_est1k_costo_real;
    v_obs_extra  := cfg_est1k_observacion_extra;
    v_resp_email := cfg_est1k_responsable_em;
    v_estanque_id := NULL; v_responsable_id := NULL;
    v_si_id := NULL; v_si_litros := NULL; v_si_costo_ant := NULL; v_si_obs_ant := NULL;
    v_kardex_id := NULL; v_kardex_folio_ant := NULL; v_kardex_obs_ant := NULL;
    v_valor_ant := NULL; v_valor_nvo := NULL; v_obs_nva_si := NULL; v_obs_nva_kx := NULL; v_folio_nvo := NULL;

    IF v_costo_real IS NULL THEN
        INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'PLACEHOLDER', 'cfg_est1k_costo_real = NULL. No se procesa.');
    ELSIF v_costo_real <= 0 THEN
        INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
        VALUES (v_codigo, 'FALTA_DATOS', 'costo_unitario_real debe ser > 0.');
    ELSE
        SELECT id INTO v_estanque_id
          FROM combustible_estanques
         WHERE codigo = v_codigo AND activo = true;

        IF v_estanque_id IS NULL THEN
            INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
            VALUES (v_codigo, 'NO_ENCONTRADO', 'Estanque no existe o no esta activo.');
        ELSE
            SELECT id, litros_iniciales, costo_unitario_inicial, observacion
              INTO v_si_id, v_si_litros, v_si_costo_ant, v_si_obs_ant
              FROM combustible_stock_inicial
             WHERE estanque_id = v_estanque_id AND anulado = false
             LIMIT 1;

            IF v_si_id IS NULL THEN
                INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle)
                VALUES (v_codigo, 'SIN_STOCK_INICIAL',
                        'No hay stock_inicial activo. Ejecutar 12 antes.');
            ELSIF v_si_obs_ant IS NULL OR v_si_obs_ant NOT LIKE '[PROVISORIO]%' THEN
                IF v_si_obs_ant IS NOT NULL AND v_si_obs_ant LIKE '[REGULARIZADO%' THEN
                    INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle, stock_inicial_id)
                    VALUES (v_codigo, 'YA_REGULARIZADO',
                            'stock_inicial ya regularizado previamente. Idempotente: no se modifica.', v_si_id);
                ELSE
                    INSERT INTO _t_regularizar_stock_inicial_combustible(estanque_codigo, estado_proceso, detalle, stock_inicial_id)
                    VALUES (v_codigo, 'SIN_PROVISORIO',
                            'stock_inicial activo NO esta marcado [PROVISORIO]. No requiere regularizacion.', v_si_id);
                END IF;
            ELSE
                SELECT id, folio_movimiento, observacion
                  INTO v_kardex_id, v_kardex_folio_ant, v_kardex_obs_ant
                  FROM combustible_kardex_valorizado
                 WHERE stock_inicial_id = v_si_id
                   AND tipo_movimiento = 'stock_inicial'
                 ORDER BY fecha_movimiento ASC
                 LIMIT 1;

                IF v_kardex_id IS NULL THEN
                    INSERT INTO _t_regularizar_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, detalle, stock_inicial_id
                    ) VALUES (
                        v_codigo, 'NO_ENCONTRADO',
                        'No se encontro kardex_inicial asociado al stock_inicial. Revisar manualmente.',
                        v_si_id
                    );
                ELSE
                    IF v_resp_email IS NOT NULL AND LENGTH(TRIM(v_resp_email)) > 0 THEN
                        SELECT id INTO v_responsable_id
                          FROM usuarios_perfil
                         WHERE LOWER(email) = LOWER(TRIM(v_resp_email)) AND activo = true
                         LIMIT 1;
                    END IF;

                    v_valor_ant := v_si_litros * v_si_costo_ant;
                    v_valor_nvo := v_si_litros * v_costo_real;

                    v_obs_nva_si := '[REGULARIZADO ' || TO_CHAR(v_fecha_reg, 'YYYY-MM-DD') || '] '
                                    || REPLACE(v_si_obs_ant, '[PROVISORIO] ', '')
                                    || CASE WHEN v_obs_extra IS NOT NULL AND LENGTH(TRIM(v_obs_extra)) > 0
                                            THEN ' | Finanzas: ' || TRIM(v_obs_extra) ELSE '' END;

                    v_obs_nva_kx := '[REGULARIZADO ' || TO_CHAR(v_fecha_reg, 'YYYY-MM-DD') || '] '
                                    || REPLACE(COALESCE(v_kardex_obs_ant, ''), '[PROVISORIO] ', '')
                                    || CASE WHEN v_obs_extra IS NOT NULL AND LENGTH(TRIM(v_obs_extra)) > 0
                                            THEN ' | Finanzas: ' || TRIM(v_obs_extra) ELSE '' END;

                    v_folio_nvo := 'REG-STOCK-INI-' || TO_CHAR(v_fecha_reg, 'YYYYMMDD') || '-' ||
                                   SUBSTRING(v_kardex_id::TEXT, 1, 4);

                    UPDATE combustible_stock_inicial
                       SET costo_unitario_inicial = v_costo_real,
                           observacion = v_obs_nva_si
                     WHERE id = v_si_id;

                    UPDATE combustible_estanques
                       SET costo_promedio_lt = v_costo_real,
                           valor_total_stock = v_si_litros * v_costo_real,
                           updated_at = NOW()
                     WHERE id = v_estanque_id;

                    UPDATE combustible_kardex_valorizado
                       SET costo_unitario_movimiento = v_costo_real,
                           costo_promedio_lt_despues = v_costo_real,
                           valor_stock_despues = v_si_litros * v_costo_real,
                           folio_movimiento = v_folio_nvo,
                           observacion = v_obs_nva_kx
                     WHERE id = v_kardex_id;

                    INSERT INTO _t_regularizar_stock_inicial_combustible(
                        estanque_codigo, estado_proceso, detalle,
                        stock_inicial_id, kardex_id, litros,
                        costo_anterior, costo_nuevo, valor_anterior, valor_nuevo
                    ) VALUES (
                        v_codigo, 'OK_REGULARIZADO',
                        'Costo provisorio reemplazado por costo real Finanzas.',
                        v_si_id, v_kardex_id, v_si_litros,
                        v_si_costo_ant, v_costo_real, v_valor_ant, v_valor_nvo
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
                    THEN 'STOP_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
                WHEN bool_or(estado_proceso IN ('FALTA_DATOS','NO_ENCONTRADO'))
                    THEN 'STOP_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
                WHEN bool_or(estado_proceso IN ('PLACEHOLDER','SIN_STOCK_INICIAL','SIN_PROVISORIO'))
                     AND NOT bool_or(estado_proceso = 'OK_REGULARIZADO')
                    THEN 'WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE'
                WHEN bool_or(estado_proceso IN ('PLACEHOLDER','SIN_STOCK_INICIAL','SIN_PROVISORIO'))
                    THEN 'WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PARCIAL'
                ELSE 'OK_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
            END,
            string_agg(estanque_codigo || '=' || estado_proceso, '; ' ORDER BY estanque_codigo)
          INTO v_resultado_str, v_detalle_str
        FROM _t_regularizar_stock_inicial_combustible;

        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_CPP_STOCK_INICIAL_REGULARIZACION',
            'Regularizacion stock inicial combustible (paso 12B) — costo real Finanzas reemplaza provisorio.',
            current_user,
            NOW(), NOW(),
            CASE WHEN v_resultado_str = 'OK_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE' THEN 'ok'
                 WHEN v_resultado_str LIKE 'WARNING_%' THEN 'warning'
                 ELSE 'pendiente' END,
            COALESCE(v_resultado_str, 'sin_filas') || ' | ' || COALESCE(v_detalle_str, '')
        );
    END IF;
END $$;


-- ── 4. FILA FINAL RESUMEN ───────────────────────────────────────────
SELECT
    CASE
        WHEN MAX(CASE WHEN estanque_codigo='__GLOBAL__' AND estado_proceso='PLACEHOLDER' THEN 1 ELSE 0 END) = 1
            THEN 'STOP_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
        WHEN bool_or(estado_proceso IN ('FALTA_DATOS','NO_ENCONTRADO'))
            THEN 'STOP_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
        WHEN bool_or(estado_proceso IN ('PLACEHOLDER','SIN_STOCK_INICIAL','SIN_PROVISORIO'))
             AND NOT bool_or(estado_proceso = 'OK_REGULARIZADO')
            THEN 'WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE'
        WHEN bool_or(estado_proceso IN ('PLACEHOLDER','SIN_STOCK_INICIAL','SIN_PROVISORIO'))
            THEN 'WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PARCIAL'
        ELSE 'OK_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE'
    END                                                                       AS resultado,
    string_agg(
        estanque_codigo || '=' || estado_proceso ||
        CASE WHEN detalle IS NOT NULL AND detalle <> ''
             THEN ' (' || detalle || ')' ELSE '' END,
        ' | ' ORDER BY estanque_codigo
    )                                                                         AS detalle,
    COUNT(*) FILTER (WHERE estado_proceso = 'OK_REGULARIZADO')::int           AS estanques_regularizados,
    COUNT(*) FILTER (
        WHERE estanque_codigo <> '__GLOBAL__'
          AND estado_proceso IN ('PLACEHOLDER','FALTA_DATOS','NO_ENCONTRADO',
                                 'SIN_STOCK_INICIAL','SIN_PROVISORIO','YA_REGULARIZADO')
    )::int                                                                     AS estanques_omitidos,
    COALESCE(SUM(CASE WHEN estado_proceso = 'OK_REGULARIZADO'
                      THEN (valor_nuevo - valor_anterior) END), 0)            AS delta_valor_total,
    COALESCE(SUM(CASE WHEN estado_proceso = 'OK_REGULARIZADO'
                      THEN valor_nuevo END), 0)                               AS valor_total_post
FROM _t_regularizar_stock_inicial_combustible;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE
--     Todos los provisorios fueron regularizados al costo real Finanzas.
--     Avanzar al paso 13 (validate roles/dashboards).
--
-- - resultado = WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PARCIAL
--     Algunos regularizados, otros omitidos (YA_REGULARIZADO, SIN_PROVISORIO,
--     SIN_STOCK_INICIAL o cfg en NULL). Revisar `detalle`.
--
-- - resultado = WARNING_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE_PENDIENTE
--     Ningun estanque fue regularizado en este run.
--
-- - resultado = STOP_REGULARIZACION_STOCK_INICIAL_COMBUSTIBLE
--     - GLOBAL=PLACEHOLDER → archivo sin completar, NO se ejecuto nada.
--     - FALTA_DATOS / NO_ENCONTRADO → leer columna `detalle` y corregir.
--
-- VERIFICACION POST (manual):
--   SELECT codigo, costo_promedio_lt, valor_total_stock
--     FROM combustible_estanques
--    WHERE codigo IN ('EST-15K','EST-1K');
--
--   SELECT folio_movimiento, observacion, costo_unitario_movimiento, valor_stock_despues
--     FROM combustible_kardex_valorizado
--    WHERE tipo_movimiento = 'stock_inicial'
--    ORDER BY fecha_movimiento DESC;
-- ============================================================================
