-- ============================================================================
-- SICOM-ICEO | 171 — Congelar Disponibilidad Inherente = Disponibilidad Física
-- ----------------------------------------------------------------------------
-- MIG170 hizo que la Disp. Inherente (MTBF/(MTBF+MTTR) con MTTR=(M+T)) quedara
-- por ENCIMA de la Física, un cambio muy brusco. Mientras se validan los
-- indicadores, la Disp. Inherente vuelve a COINCIDIR con la Disp. Física.
--
-- Se mantiene TODO lo demás de MIG170: UP=A,C,L,U,D,V · DOWN=M,T,F,R,H ·
-- MTBF=UP/fallas · MTTR=(M+T)/fallas (indicador aparte) · disp_fisica=UP/Total.
-- Solo cambia: disponibilidad_inherente := disponibilidad_fisica.
-- Reaplicar la fórmula real es un simple cambio de esa línea cuando se valide.
-- IDEMPOTENTE.
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
        v_mtbf := v_up; v_mttr := 0;
    ELSE
        v_mtbf := ROUND(v_up::NUMERIC / v_eventos, 4);
        v_mttr := ROUND(v_mt::NUMERIC / v_eventos, 4);   -- solo M+T
    END IF;

    IF v_total > 0 THEN
        v_disp_fis := ROUND(v_up::NUMERIC / v_total, 4);
    ELSE
        v_disp_fis := 0;
    END IF;

    -- CONGELADO (en validación): Inherente = Física. La fórmula real sería
    -- v_mtbf/(v_mtbf+v_mttr); se reactiva cambiando solo esta línea.
    v_disp_inh := v_disp_fis;

    RETURN QUERY
    SELECT p_activo_id, a.patente, a.categoria_uso,
           v_total, v_up, v_down, v_eventos,
           v_mtbf, v_mttr, v_disp_inh, v_disp_fis
      FROM activos a
     WHERE a.id = p_activo_id;
END;
$$;

DO $$
DECLARE v_id UUID; r RECORD;
BEGIN
    SELECT activo_id INTO v_id FROM estado_diario_flota
     WHERE fecha >= date_trunc('month',CURRENT_DATE) AND estado_codigo IN ('F','R','H')
     GROUP BY activo_id ORDER BY count(*) DESC LIMIT 1;
    SELECT * INTO r FROM fn_calcular_fiabilidad_activo(v_id, date_trunc('month',CURRENT_DATE)::date, CURRENT_DATE);
    RAISE NOTICE 'fis=% inh=% (deben coincidir) | mtbf=% mttr=%',
        r.disponibilidad_fisica, r.disponibilidad_inherente, r.mtbf_dias, r.mttr_dias;
END $$;
