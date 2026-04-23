-- ============================================================================
-- SICOM-ICEO | Migracion 47 — Filtrar fiabilidad a flota movil unicamente
-- ============================================================================
-- fn_calcular_fiabilidad_flota no filtraba por tipo de activo, entonces
-- incluia equipos fijos (surtidor, bomba, estanque, equipo_bombeo) en el
-- agregado. Esos equipos no tienen sentido en el analisis de fiabilidad
-- vehicular — no viajan, no tienen road-test, y arrastraban los KPIs.
--
-- Fix: filtrar por tipos vehiculares. Alineado con calcular_oee_flota
-- (mig 25) + equipo_menor (grua horquilla movil, etc.).
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
           AND a.tipo IN (
               'camion_cisterna','camion','camioneta','lubrimovil','equipo_menor'
           )
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
    'Agregado de fiabilidad por categoria SOLO sobre flota movil '
    '(camion_cisterna/camion/camioneta/lubrimovil/equipo_menor). '
    'Excluye equipos fijos (surtidor/bomba/estanque/equipo_bombeo) que '
    'no tienen sentido en este analisis vehicular.';


-- ============================================================================
-- SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_total_rows INTEGER;
    v_total_equipos BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total_rows
      FROM fn_calcular_fiabilidad_flota(
          (CURRENT_DATE - 30)::date,
          CURRENT_DATE,
          NULL
      );

    SELECT SUM(total_equipos) INTO v_total_equipos
      FROM fn_calcular_fiabilidad_flota(
          (CURRENT_DATE - 30)::date,
          CURRENT_DATE,
          NULL
      );

    RAISE NOTICE '== Migracion 47 ==';
    RAISE NOTICE 'Filas categorias devueltas: %', v_total_rows;
    RAISE NOTICE 'Total equipos moviles (sin fijos): %', v_total_equipos;
END $$;
