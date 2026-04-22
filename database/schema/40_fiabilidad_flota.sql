-- ============================================================================
-- SICOM-ICEO | Migracion 40 — Fiabilidad de Flota (MTBF / MTTR / Disp. Inherente)
-- ============================================================================
-- Introduce las metricas de fiabilidad inspiradas en el analisis del archivo
-- "Analisis_Fiabilidad_OEE_Flota.xlsx". Sigue la misma metodologia:
--
--   Evento de falla = corrida consecutiva de dias en estados DOWN (M/T/F).
--   MTBF (dias)     = Dias UP / N Eventos de Falla.
--   MTTR (dias)     = Dias DOWN / N Eventos de Falla.
--   Disp. Inherente = MTBF / (MTBF + MTTR).
--
-- Tambien introduce la CATEGORIA DE USO del equipo como campo MANUAL en la
-- tabla activos (no se deriva del comportamiento). El usuario asigna:
--   - arriendo_comercial : spot / rotacion de clientes
--   - leasing_operativo  : contrato largo plazo
--   - uso_interno        : flota propia
--   - venta              : equipo dispuesto para venta
--
-- El resultado es el insumo crudo para el reporte estilo ejecutivo.
-- ============================================================================

-- ============================================================================
-- 1. ENUM y COLUMNA categoria_uso en activos
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE categoria_uso_enum AS ENUM (
        'arriendo_comercial',
        'leasing_operativo',
        'uso_interno',
        'venta'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS categoria_uso categoria_uso_enum;

COMMENT ON COLUMN activos.categoria_uso IS
    'Categoria comercial del equipo, asignada manualmente. Se usa para '
    'agrupar el reporte de fiabilidad. El usuario la ajusta segun el '
    'destino actual del equipo (no se infiere del estado).';

-- Backfill conservador: si el activo no tiene categoria definida, dejar NULL.
-- El reporte muestra como "Sin categoria" a los NULL y el usuario los va
-- completando desde el detalle del activo.


-- ============================================================================
-- 2. FUNCION: fiabilidad por activo
-- ============================================================================
-- Recibe (activo, rango). Devuelve metricas crudas contando corridas
-- consecutivas de dias DOWN en estado_diario_flota.
--
-- Tecnica gaps-and-islands: cada vez que el dia actual no es consecutivo al
-- anterior dentro del set DOWN, inicia una nueva "isla" (evento).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calcular_fiabilidad_activo(
    p_activo_id     UUID,
    p_fecha_inicio  DATE,
    p_fecha_fin     DATE
)
RETURNS TABLE (
    activo_id                UUID,
    patente                  VARCHAR,
    categoria_uso            categoria_uso_enum,
    dias_observados          INTEGER,
    dias_up                  INTEGER,
    dias_down                INTEGER,
    eventos_falla            INTEGER,
    mtbf_dias                NUMERIC,
    mttr_dias                NUMERIC,
    disponibilidad_inherente NUMERIC,
    disponibilidad_fisica    NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_total     INTEGER;
    v_up        INTEGER;
    v_down      INTEGER;
    v_eventos   INTEGER;
    v_mtbf      NUMERIC;
    v_mttr      NUMERIC;
    v_disp_inh  NUMERIC;
    v_disp_fis  NUMERIC;
BEGIN
    -- Total de dias observados (con fila en estado_diario_flota)
    SELECT COUNT(*)
      INTO v_total
      FROM estado_diario_flota
     WHERE activo_id = p_activo_id
       AND fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    -- Dias DOWN (M/T/F)
    SELECT COUNT(*)
      INTO v_down
      FROM estado_diario_flota
     WHERE activo_id = p_activo_id
       AND fecha BETWEEN p_fecha_inicio AND p_fecha_fin
       AND estado_codigo IN ('M','T','F');

    v_up := GREATEST(v_total - v_down, 0);

    -- Eventos de falla = corridas consecutivas en DOWN (gaps-and-islands)
    SELECT COUNT(DISTINCT grupo)
      INTO v_eventos
      FROM (
        SELECT fecha,
               SUM(CASE WHEN prev_fecha IS NULL OR (fecha - prev_fecha) > 1
                        THEN 1 ELSE 0 END)
                 OVER (ORDER BY fecha) AS grupo
          FROM (
            SELECT fecha,
                   LAG(fecha) OVER (ORDER BY fecha) AS prev_fecha
              FROM estado_diario_flota
             WHERE activo_id = p_activo_id
               AND fecha BETWEEN p_fecha_inicio AND p_fecha_fin
               AND estado_codigo IN ('M','T','F')
          ) t
      ) grouped;

    -- MTBF / MTTR / Disp. Inherente
    -- Convencion: si no hubo fallas, MTBF = dias UP (equipo nunca fallo en
    -- el periodo) y MTTR = 0. Disp. Inherente = 1.
    IF v_eventos = 0 THEN
        v_mtbf     := v_up;
        v_mttr     := 0;
        v_disp_inh := 1;
    ELSE
        v_mtbf     := ROUND(v_up::NUMERIC / v_eventos, 4);
        v_mttr     := ROUND(v_down::NUMERIC / v_eventos, 4);
        IF (v_mtbf + v_mttr) > 0 THEN
            v_disp_inh := ROUND(v_mtbf / (v_mtbf + v_mttr), 4);
        ELSE
            v_disp_inh := 0;
        END IF;
    END IF;

    -- Disp. Fisica = (Total - DOWN) / Total (A del OEE, es lo mismo que usa
    -- calcular_oee_activo pero en fraccion 0-1, no en %)
    IF v_total > 0 THEN
        v_disp_fis := ROUND((v_total - v_down)::NUMERIC / v_total, 4);
    ELSE
        v_disp_fis := 0;
    END IF;

    RETURN QUERY
    SELECT p_activo_id,
           a.patente,
           a.categoria_uso,
           v_total,
           v_up,
           v_down,
           v_eventos,
           v_mtbf,
           v_mttr,
           v_disp_inh,
           v_disp_fis
      FROM activos a
     WHERE a.id = p_activo_id;
END;
$$;

COMMENT ON FUNCTION fn_calcular_fiabilidad_activo IS
    'Metricas de fiabilidad por equipo en un rango: eventos de falla '
    '(corridas de dias DOWN), MTBF, MTTR, Disp. Inherente. Metodologia del '
    'archivo de analisis de flota.';


-- ============================================================================
-- 3. FUNCION: fiabilidad agregada por categoria o flota total
-- ============================================================================
-- Recibe rango y opcionalmente una categoria. Devuelve KPIs flota o por
-- categoria (misma forma del "KPIs por Categoria" del Excel).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calcular_fiabilidad_flota(
    p_fecha_inicio  DATE,
    p_fecha_fin     DATE,
    p_categoria     categoria_uso_enum DEFAULT NULL
)
RETURNS TABLE (
    categoria                categoria_uso_enum,
    total_equipos            BIGINT,
    dias_equipo              BIGINT,
    dias_up                  BIGINT,
    dias_down                BIGINT,
    eventos_falla_total      BIGINT,
    disponibilidad_fisica    NUMERIC,
    utilizacion_bruta        NUMERIC,
    mtbf_agregado            NUMERIC,
    mttr_agregado            NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT a.id,
               a.categoria_uso,
               edf.fecha,
               edf.estado_codigo
          FROM activos a
          JOIN estado_diario_flota edf ON edf.activo_id = a.id
         WHERE a.estado != 'dado_baja'
           AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
           AND (p_categoria IS NULL OR a.categoria_uso = p_categoria)
    ),
    por_activo AS (
        SELECT id,
               categoria_uso,
               COUNT(*)                                        AS dias_obs,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T','F')) AS dias_dn,
               COUNT(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F')) AS dias_ok,
               COUNT(*) FILTER (WHERE estado_codigo IN ('A','L')) AS dias_a_l
          FROM base
         GROUP BY id, categoria_uso
    ),
    eventos_por_activo AS (
        -- Conteo de corridas DOWN (islas) por activo
        SELECT id,
               categoria_uso,
               COUNT(DISTINCT grupo) AS eventos
          FROM (
            SELECT id, categoria_uso, fecha,
                   SUM(CASE WHEN prev_fecha IS NULL OR (fecha - prev_fecha) > 1
                            THEN 1 ELSE 0 END)
                     OVER (PARTITION BY id ORDER BY fecha) AS grupo
              FROM (
                SELECT id, categoria_uso, fecha,
                       LAG(fecha) OVER (PARTITION BY id ORDER BY fecha) AS prev_fecha
                  FROM base
                 WHERE estado_codigo IN ('M','T','F')
              ) t
          ) g
         GROUP BY id, categoria_uso
    ),
    combinado AS (
        SELECT pa.categoria_uso,
               pa.id,
               pa.dias_obs,
               pa.dias_ok,
               pa.dias_dn,
               pa.dias_a_l,
               COALESCE(ep.eventos, 0) AS eventos
          FROM por_activo pa
          LEFT JOIN eventos_por_activo ep ON ep.id = pa.id
    )
    SELECT c.categoria_uso,
           COUNT(DISTINCT c.id)::BIGINT                                         AS total_equipos,
           SUM(c.dias_obs)::BIGINT                                              AS dias_equipo,
           SUM(c.dias_ok)::BIGINT                                               AS dias_up,
           SUM(c.dias_dn)::BIGINT                                               AS dias_down,
           SUM(c.eventos)::BIGINT                                               AS eventos_falla_total,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0
                 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4)  AS disponibilidad_fisica,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0
                 THEN SUM(c.dias_a_l)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS utilizacion_bruta,
           ROUND(CASE WHEN SUM(c.eventos) > 0
                 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.eventos) ELSE SUM(c.dias_ok) END, 4) AS mtbf_agregado,
           ROUND(CASE WHEN SUM(c.eventos) > 0
                 THEN SUM(c.dias_dn)::NUMERIC / SUM(c.eventos) ELSE 0 END, 4)   AS mttr_agregado
      FROM combinado c
     GROUP BY c.categoria_uso
     ORDER BY c.categoria_uso;
END;
$$;

COMMENT ON FUNCTION fn_calcular_fiabilidad_flota IS
    'Agregado de fiabilidad por categoria de uso o flota total (si '
    'p_categoria es NULL, una fila por cada categoria presente). Replica '
    'la tabla "KPIs por Categoria" del analisis de flota.';


-- ============================================================================
-- 4. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_enum_ok BOOLEAN;
    v_col_ok  BOOLEAN;
    v_fn1_ok  BOOLEAN;
    v_fn2_ok  BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'categoria_uso_enum')
      INTO v_enum_ok;

    SELECT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'activos' AND column_name = 'categoria_uso')
      INTO v_col_ok;

    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_calcular_fiabilidad_activo')
      INTO v_fn1_ok;

    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_calcular_fiabilidad_flota')
      INTO v_fn2_ok;

    RAISE NOTICE '== Migracion 40 ==';
    RAISE NOTICE 'Enum categoria_uso_enum ...... %', v_enum_ok;
    RAISE NOTICE 'Columna activos.categoria_uso  %', v_col_ok;
    RAISE NOTICE 'fn_calcular_fiabilidad_activo  %', v_fn1_ok;
    RAISE NOTICE 'fn_calcular_fiabilidad_flota   %', v_fn2_ok;

    IF NOT (v_enum_ok AND v_col_ok AND v_fn1_ok AND v_fn2_ok) THEN
        RAISE EXCEPTION 'Migracion 40 incompleta.';
    END IF;
END $$;
