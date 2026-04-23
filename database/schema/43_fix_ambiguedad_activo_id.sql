-- ============================================================================
-- SICOM-ICEO | Migracion 43 — Fix ambiguedad de activo_id en fiabilidad/OEE
-- ============================================================================
-- Bug: fn_calcular_fiabilidad_activo y fn_calcular_oee_fiabilidad_activo
-- declaran RETURNS TABLE (activo_id UUID, ...). Dentro del cuerpo hacen
--   FROM estado_diario_flota WHERE activo_id = p_activo_id
-- y Postgres interpreta el `activo_id` del WHERE como la columna de salida
-- del RETURNS TABLE (shadowing), no la de la tabla. Eso hace que la funcion
-- devuelva 400 Bad Request cuando se llama desde PostgREST con plan
-- analizable.
--
-- Fix: calificar todas las referencias a `activo_id` con el alias de la
-- tabla (edf.activo_id). Mantiene firma y semantica.
-- ============================================================================

-- ============================================================================
-- 1. Fiabilidad por activo (mig 40 fix)
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
    SELECT COUNT(*)
      INTO v_total
      FROM estado_diario_flota edf
     WHERE edf.activo_id = p_activo_id
       AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    SELECT COUNT(*)
      INTO v_down
      FROM estado_diario_flota edf
     WHERE edf.activo_id = p_activo_id
       AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
       AND edf.estado_codigo IN ('M','T','F');

    v_up := GREATEST(v_total - v_down, 0);

    SELECT COUNT(DISTINCT grupo)
      INTO v_eventos
      FROM (
        SELECT f,
               SUM(CASE WHEN prev_f IS NULL OR (f - prev_f) > 1
                        THEN 1 ELSE 0 END)
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


-- ============================================================================
-- 2. OEE-Fiabilidad por activo (mig 41 fix)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calcular_oee_fiabilidad_activo(
    p_activo_id     UUID,
    p_fecha_inicio  DATE,
    p_fecha_fin     DATE
)
RETURNS TABLE (
    activo_id       UUID,
    patente         VARCHAR,
    total_dias      INTEGER,
    dias_a          INTEGER,
    dias_d          INTEGER,
    dias_h          INTEGER,
    dias_r          INTEGER,
    dias_v          INTEGER,
    dias_u          INTEGER,
    dias_l          INTEGER,
    dias_m          INTEGER,
    dias_t          INTEGER,
    dias_f          INTEGER,
    oee_a           NUMERIC,
    oee_p           NUMERIC,
    oee_q           NUMERIC,
    oee_total       NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_total INTEGER;
    v_a INTEGER; v_d INTEGER; v_h INTEGER; v_r INTEGER;
    v_v INTEGER; v_u INTEGER; v_l INTEGER;
    v_m INTEGER; v_t INTEGER; v_f INTEGER;
    v_down INTEGER;
    v_denom_p INTEGER;
    v_oee_a NUMERIC;
    v_oee_p NUMERIC;
    v_oee_q NUMERIC;
    v_oee   NUMERIC;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'A'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'D'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'H'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'R'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'V'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'U'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'L'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'M'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'T'),
        COUNT(*) FILTER (WHERE edf.estado_codigo = 'F')
      INTO v_total, v_a, v_d, v_h, v_r, v_v, v_u, v_l, v_m, v_t, v_f
      FROM estado_diario_flota edf
     WHERE edf.activo_id = p_activo_id
       AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    v_down := COALESCE(v_m, 0) + COALESCE(v_t, 0) + COALESCE(v_f, 0);

    IF v_total > 0 THEN
        v_oee_a := ROUND((v_total - v_down)::NUMERIC / v_total, 4);
    ELSE
        v_oee_a := 0;
    END IF;

    v_denom_p := COALESCE(v_a,0) + COALESCE(v_d,0) + COALESCE(v_v,0)
               + COALESCE(v_h,0) + COALESCE(v_r,0) + COALESCE(v_l,0);
    IF v_denom_p > 0 THEN
        v_oee_p := ROUND((COALESCE(v_a,0) + COALESCE(v_l,0))::NUMERIC / v_denom_p, 4);
    ELSE
        v_oee_p := NULL;
    END IF;

    IF v_total > 0 THEN
        v_oee_q := ROUND(1 - (COALESCE(v_f,0)::NUMERIC / v_total), 4);
    ELSE
        v_oee_q := 1;
    END IF;

    IF v_oee_p IS NULL THEN
        v_oee := NULL;
    ELSE
        v_oee := ROUND(v_oee_a * v_oee_p * v_oee_q, 4);
    END IF;

    RETURN QUERY
    SELECT p_activo_id,
           a.patente,
           v_total,
           v_a, v_d, v_h, v_r, v_v, v_u, v_l, v_m, v_t, v_f,
           v_oee_a, v_oee_p, v_oee_q, v_oee
      FROM activos a
     WHERE a.id = p_activo_id;
END;
$$;


-- ============================================================================
-- 3. SMOKE TEST — llamar cada funcion con un activo aleatorio
-- ============================================================================

DO $$
DECLARE
    v_activo_id UUID;
    v_row RECORD;
BEGIN
    SELECT id INTO v_activo_id
      FROM activos
     WHERE estado != 'dado_baja'
     LIMIT 1;

    IF v_activo_id IS NULL THEN
        RAISE NOTICE 'Sin activos para probar.';
        RETURN;
    END IF;

    SELECT * INTO v_row
      FROM fn_calcular_fiabilidad_activo(v_activo_id, CURRENT_DATE - 30, CURRENT_DATE);
    RAISE NOTICE 'fn_calcular_fiabilidad_activo(%) -> dias_obs=%',
                 v_activo_id, v_row.dias_observados;

    SELECT * INTO v_row
      FROM fn_calcular_oee_fiabilidad_activo(v_activo_id, CURRENT_DATE - 30, CURRENT_DATE);
    RAISE NOTICE 'fn_calcular_oee_fiabilidad_activo(%) -> total=% oee=%',
                 v_activo_id, v_row.total_dias, v_row.oee_total;
END $$;
