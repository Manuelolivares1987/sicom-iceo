-- ============================================================================
-- SICOM-ICEO | 170 — Redefinición de KPIs de fiabilidad (taller)
-- ----------------------------------------------------------------------------
-- Definiciones acordadas con operaciones:
--   Operativo (UP)     = A, C, L, U, D, V
--   No disponible(DOWN)= M, T, F, R, H   (Habilitación y Recepción bajan disp.)
--   Falla (evento)     = episodio (racha) de M/T/F  (H,R NO son falla)
--   Disp. Física       = UP / Total
--   MTBF               = UP / nº fallas
--   MTTR               = (M + T) / nº fallas   (solo reparación con HH; F sin HH
--                        no es reparación → excluida del MTTR)
--   Disp. Inherente    = MTBF / (MTBF + MTTR)  → ahora DISTINTA de la física
--   Utilización bruta  = (A + L + C) / Total
--
-- Cambios vs versión viva:
--   - DOWN pasa de (M,T,F) a (M,T,F,R,H) → afecta disp_fisica y dias_up/down.
--   - MTTR pasa de (M+T+F)/eventos a (M+T)/eventos.
--   - Utilización pasa de (A+L) a (A+L+C).
-- Afecta fn_calcular_fiabilidad_activo (detalle/público) y
-- fn_calcular_fiabilidad_flota (categorías). IDEMPOTENTE.
-- ============================================================================

-- ── 1. Por activo ───────────────────────────────────────────────────────────
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
    v_down      INTEGER;   -- M,T,F,R,H
    v_mt        INTEGER;   -- M,T (reparación con HH)
    v_up        INTEGER;
    v_eventos   INTEGER;   -- episodios de M/T/F
    v_mtbf      NUMERIC;
    v_mttr      NUMERIC;
    v_disp_inh  NUMERIC;
    v_disp_fis  NUMERIC;
BEGIN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T','F','R','H')),
           COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T'))
      INTO v_total, v_down, v_mt
      FROM estado_diario_flota edf
     WHERE edf.activo_id = p_activo_id
       AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    v_up := GREATEST(v_total - v_down, 0);

    -- Fallas = rachas de días consecutivos en M/T/F.
    SELECT COUNT(DISTINCT grupo)
      INTO v_eventos
      FROM (
        SELECT f,
               SUM(CASE WHEN prev_f IS NULL OR (f - prev_f) > 1 THEN 1 ELSE 0 END)
                 OVER (ORDER BY f) AS grupo
          FROM (
            SELECT edf.fecha AS f,
                   LAG(edf.fecha) OVER (ORDER BY edf.fecha) AS prev_f
              FROM estado_diario_flota edf
             WHERE edf.activo_id = p_activo_id
               AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
               AND edf.estado_codigo IN ('M','T','F')
          ) t
      ) grouped;

    IF v_eventos = 0 THEN
        v_mtbf := v_up; v_mttr := 0; v_disp_inh := 1;
    ELSE
        v_mtbf := ROUND(v_up::NUMERIC / v_eventos, 4);
        v_mttr := ROUND(v_mt::NUMERIC / v_eventos, 4);   -- solo M+T
        IF (v_mtbf + v_mttr) > 0 THEN
            v_disp_inh := ROUND(v_mtbf / (v_mtbf + v_mttr), 4);
        ELSE
            v_disp_inh := 0;
        END IF;
    END IF;

    IF v_total > 0 THEN
        v_disp_fis := ROUND(v_up::NUMERIC / v_total, 4);
    ELSE
        v_disp_fis := 0;
    END IF;

    RETURN QUERY
    SELECT p_activo_id, a.patente, a.categoria_uso,
           v_total, v_up, v_down, v_eventos,
           v_mtbf, v_mttr, v_disp_inh, v_disp_fis
      FROM activos a
     WHERE a.id = p_activo_id;
END;
$$;

-- ── 2. Por flota / categoría ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_calcular_fiabilidad_flota(
    p_fecha_inicio date,
    p_fecha_fin date,
    p_categoria categoria_uso_enum DEFAULT NULL::categoria_uso_enum
)
RETURNS TABLE(
    categoria categoria_uso_enum, total_equipos bigint, dias_equipo bigint,
    dias_up bigint, dias_down bigint, eventos_falla_total bigint,
    disponibilidad_fisica numeric, utilizacion_bruta numeric,
    mtbf_agregado numeric, mttr_agregado numeric
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT a.id, a.categoria_uso, edf.fecha, edf.estado_codigo
          FROM activos a
          JOIN estado_diario_flota edf ON edf.activo_id = a.id
         WHERE a.estado != 'dado_baja'
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
           AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
           AND (p_categoria IS NULL OR a.categoria_uso = p_categoria)
    ),
    por_activo AS (
        SELECT id, categoria_uso,
               COUNT(*) AS dias_obs,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T','F','R','H')) AS dias_dn,
               COUNT(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','R','H')) AS dias_ok,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T')) AS dias_mt,
               COUNT(*) FILTER (WHERE estado_codigo IN ('A','L','C')) AS dias_util
          FROM base
         GROUP BY id, categoria_uso
    ),
    eventos_por_activo AS (
        SELECT id, categoria_uso, COUNT(DISTINCT grupo) AS eventos
          FROM (
            SELECT id, categoria_uso, fecha,
                   SUM(CASE WHEN prev_fecha IS NULL OR (fecha - prev_fecha) > 1 THEN 1 ELSE 0 END)
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
        SELECT pa.categoria_uso, pa.id, pa.dias_obs, pa.dias_ok, pa.dias_dn,
               pa.dias_mt, pa.dias_util, COALESCE(ep.eventos, 0) AS eventos
          FROM por_activo pa
          LEFT JOIN eventos_por_activo ep ON ep.id = pa.id
    )
    SELECT c.categoria_uso,
           COUNT(DISTINCT c.id)::BIGINT AS total_equipos,
           SUM(c.dias_obs)::BIGINT AS dias_equipo,
           SUM(c.dias_ok)::BIGINT AS dias_up,
           SUM(c.dias_dn)::BIGINT AS dias_down,
           SUM(c.eventos)::BIGINT AS eventos_falla_total,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS disponibilidad_fisica,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_util)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS utilizacion_bruta,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.eventos) ELSE SUM(c.dias_ok) END, 4) AS mtbf_agregado,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_mt)::NUMERIC / SUM(c.eventos) ELSE 0 END, 4) AS mttr_agregado
      FROM combinado c
     GROUP BY c.categoria_uso
     ORDER BY c.categoria_uso;
END;
$$;

-- ── 3. Smoke test ───────────────────────────────────────────────────────────
DO $$
DECLARE v_id UUID; r RECORD;
BEGIN
    SELECT id INTO v_id FROM activos WHERE estado <> 'dado_baja'
      AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor') LIMIT 1;
    SELECT * INTO r FROM fn_calcular_fiabilidad_activo(v_id, date_trunc('month',CURRENT_DATE)::date, CURRENT_DATE);
    RAISE NOTICE 'activo: obs=% up=% down=% fallas=% mtbf=% mttr=% inh=% fis=%',
        r.dias_observados, r.dias_up, r.dias_down, r.eventos_falla, r.mtbf_dias, r.mttr_dias,
        r.disponibilidad_inherente, r.disponibilidad_fisica;
END $$;
