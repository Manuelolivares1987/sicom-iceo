-- ============================================================================
-- SICOM-ICEO | Migracion 41 — OEE-Fiabilidad (metodologia Excel) + C2/C3
-- ============================================================================
-- Introduce:
--   (1) fn_calcular_oee_fiabilidad_activo: OEE crudo por equipo con las
--       formulas A/P/Q del archivo de analisis.
--   (2) fn_kpi_disponibilidad_flota_movil: activa el KPI C2 con
--       Disponibilidad Inherente (MTBF/(MTBF+MTTR)) desde mig 40.
--   (3) fn_kpi_mttr_moviles: activa el KPI C3 con MTTR en dias desde mig 40.
--   (4) fn_kpi_oee_fiabilidad_moviles: agregado que alimentara al KPI C8
--       (se inserta en kpi_definiciones en mig 42).
--
-- Nota: los KPI-functions reciben (contrato_id, faena_id, fecha_inicio,
-- fecha_fin) porque asi los invoca calcular_todos_kpi. Filtramos la flota
-- movil por tipo de activo igual que lo hace calcular_oee_flota.
-- ============================================================================

-- ============================================================================
-- 1. OEE-Fiabilidad por activo (formulas Excel: A x P x Q)
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
    dias_a          INTEGER,  -- Arrendado
    dias_d          INTEGER,  -- Disponible
    dias_h          INTEGER,  -- Habilitacion
    dias_r          INTEGER,  -- Recepcion
    dias_v          INTEGER,  -- Venta
    dias_u          INTEGER,  -- Uso interno
    dias_l          INTEGER,  -- Leasing
    dias_m          INTEGER,  -- Mantencion >1d
    dias_t          INTEGER,  -- Taller <1d
    dias_f          INTEGER,  -- Fuera servicio
    oee_a           NUMERIC,  -- Disponibilidad
    oee_p           NUMERIC,  -- Rendimiento (puede ser NULL si 100% U)
    oee_q           NUMERIC,  -- Calidad
    oee_total       NUMERIC   -- A x P x Q (NULL si P = NULL)
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
        COUNT(*) FILTER (WHERE estado_codigo = 'A'),
        COUNT(*) FILTER (WHERE estado_codigo = 'D'),
        COUNT(*) FILTER (WHERE estado_codigo = 'H'),
        COUNT(*) FILTER (WHERE estado_codigo = 'R'),
        COUNT(*) FILTER (WHERE estado_codigo = 'V'),
        COUNT(*) FILTER (WHERE estado_codigo = 'U'),
        COUNT(*) FILTER (WHERE estado_codigo = 'L'),
        COUNT(*) FILTER (WHERE estado_codigo = 'M'),
        COUNT(*) FILTER (WHERE estado_codigo = 'T'),
        COUNT(*) FILTER (WHERE estado_codigo = 'F')
      INTO v_total, v_a, v_d, v_h, v_r, v_v, v_u, v_l, v_m, v_t, v_f
      FROM estado_diario_flota
     WHERE activo_id = p_activo_id
       AND fecha BETWEEN p_fecha_inicio AND p_fecha_fin;

    v_down := COALESCE(v_m, 0) + COALESCE(v_t, 0) + COALESCE(v_f, 0);

    -- A = (Total - DOWN) / Total
    IF v_total > 0 THEN
        v_oee_a := ROUND((v_total - v_down)::NUMERIC / v_total, 4);
    ELSE
        v_oee_a := 0;
    END IF;

    -- P = (A + L) / (A + D + V + H + R + L)
    -- Si denominador = 0 (equipo 100% en U o con solo dias DOWN), P es NULL
    v_denom_p := COALESCE(v_a,0) + COALESCE(v_d,0) + COALESCE(v_v,0)
               + COALESCE(v_h,0) + COALESCE(v_r,0) + COALESCE(v_l,0);
    IF v_denom_p > 0 THEN
        v_oee_p := ROUND((COALESCE(v_a,0) + COALESCE(v_l,0))::NUMERIC / v_denom_p, 4);
    ELSE
        v_oee_p := NULL;
    END IF;

    -- Q = 1 - (F / Total)
    IF v_total > 0 THEN
        v_oee_q := ROUND(1 - (COALESCE(v_f,0)::NUMERIC / v_total), 4);
    ELSE
        v_oee_q := 1;
    END IF;

    -- OEE = A x P x Q. NULL si P es NULL.
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

COMMENT ON FUNCTION fn_calcular_oee_fiabilidad_activo IS
    'OEE por equipo con metodologia Excel (vista comercial): A=disp, '
    'P=(A+L)/(A+D+V+H+R+L), Q=1-(F/Total), OEE=AxPxQ. P retorna NULL '
    'si el equipo esta 100% en uso interno (denominador cero).';


-- ============================================================================
-- 2. KPI C2 — Disponibilidad Inherente (flota movil)
-- ============================================================================
-- Reemplaza la intencion original de "horas_operativas/horas_totales".
-- Ahora agrega la Disp. Inherente (MTBF/(MTBF+MTTR)) de todos los equipos
-- moviles del contrato/faena en el periodo, en % 0-100.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_kpi_disponibilidad_flota_movil(
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_periodo_inicio DATE,
    p_periodo_fin    DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_disp NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE a.estado != 'dado_baja'
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT f.*
          FROM flota
     CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) f
    )
    SELECT ROUND(AVG(disponibilidad_inherente) * 100, 2)
      INTO v_disp
      FROM por_activo;

    RETURN COALESCE(v_disp, 0);
END;
$$;

COMMENT ON FUNCTION fn_kpi_disponibilidad_flota_movil IS
    'KPI C2 (Disponibilidad Inherente de flota movil). Promedio simple '
    'de MTBF/(MTBF+MTTR) por activo en %, metodologia mig 40.';


-- ============================================================================
-- 3. KPI C3 — MTTR en dias (flota movil)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_kpi_mttr_moviles(
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_periodo_inicio DATE,
    p_periodo_fin    DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_mttr NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE a.estado != 'dado_baja'
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT f.mttr_dias
          FROM flota
     CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) f
        -- Solo consideramos equipos que tuvieron al menos un evento de falla
         WHERE f.eventos_falla > 0
    )
    SELECT ROUND(AVG(mttr_dias), 2)
      INTO v_mttr
      FROM por_activo;

    RETURN COALESCE(v_mttr, 0);
END;
$$;

COMMENT ON FUNCTION fn_kpi_mttr_moviles IS
    'KPI C3 (MTTR en dias). Promedio del MTTR entre activos moviles que '
    'tuvieron al menos un evento de falla. Metodologia mig 40.';


-- ============================================================================
-- 4. KPI C8 — OEE-Fiabilidad (flota movil)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_kpi_oee_fiabilidad_moviles(
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_periodo_inicio DATE,
    p_periodo_fin    DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_oee NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE a.estado != 'dado_baja'
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT o.oee_total
          FROM flota
     CROSS JOIN LATERAL fn_calcular_oee_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) o
         WHERE o.oee_total IS NOT NULL  -- excluir equipos 100% uso interno
    )
    SELECT ROUND(AVG(oee_total) * 100, 2)
      INTO v_oee
      FROM por_activo;

    RETURN COALESCE(v_oee, 0);
END;
$$;

COMMENT ON FUNCTION fn_kpi_oee_fiabilidad_moviles IS
    'KPI C8 (OEE-Fiabilidad). Promedio de AxPxQ por activo movil, '
    'excluye equipos con 100% Uso Interno (P indefinido). Metodologia Excel.';


-- ============================================================================
-- 5. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_fn1_ok BOOLEAN;
    v_fn2_ok BOOLEAN;
    v_fn3_ok BOOLEAN;
    v_fn4_ok BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_calcular_oee_fiabilidad_activo') INTO v_fn1_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_kpi_disponibilidad_flota_movil') INTO v_fn2_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_kpi_mttr_moviles')              INTO v_fn3_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_kpi_oee_fiabilidad_moviles')    INTO v_fn4_ok;

    RAISE NOTICE '== Migracion 41 ==';
    RAISE NOTICE 'fn_calcular_oee_fiabilidad_activo ... %', v_fn1_ok;
    RAISE NOTICE 'fn_kpi_disponibilidad_flota_movil .... %', v_fn2_ok;
    RAISE NOTICE 'fn_kpi_mttr_moviles .................. %', v_fn3_ok;
    RAISE NOTICE 'fn_kpi_oee_fiabilidad_moviles ........ %', v_fn4_ok;

    IF NOT (v_fn1_ok AND v_fn2_ok AND v_fn3_ok AND v_fn4_ok) THEN
        RAISE EXCEPTION 'Migracion 41 incompleta.';
    END IF;
END $$;
