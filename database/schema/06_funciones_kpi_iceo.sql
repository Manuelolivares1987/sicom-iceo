-- SICOM-ICEO | Fase 2 | Funciones de Calculo KPI, ICEO y Valorizacion
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 06_funciones_kpi_iceo.sql
-- Proposito : Funciones de calculo para cada KPI individual, el calculador
--             maestro de todos los KPI, el calculo del ICEO compuesto con
--             aplicacion de bloqueantes, y la valorizacion CPP de inventario.
-- Dependencias:
--   01_tipos_y_enums.sql        -> tipos enumerados
--   02_tablas_core.sql          -> contratos, faenas, activos, productos,
--                                  bodegas, stock_bodega
--   03_tablas_ot_inventario.sql -> ordenes_trabajo, movimientos_inventario,
--                                  conteos_inventario, conteo_detalle
--   04_tablas_kpi_iceo.sql      -> kpi_definiciones, kpi_tramos,
--                                  mediciones_kpi, iceo_periodos, iceo_detalle,
--                                  configuracion_iceo
--   05_tablas_operacionales.sql -> certificaciones, rutas_despacho, incidentes
-- ============================================================================

-- ============================================================================
-- SECCION 1: FUNCIONES INDIVIDUALES DE CALCULO KPI
-- ============================================================================
-- Todas las funciones KPI reciben los mismos parametros:
--   p_contrato_id  UUID  - Contrato de servicio
--   p_faena_id     UUID  - Faena (sitio minero)
--   p_periodo_inicio DATE - Inicio del periodo de medicion
--   p_periodo_fin    DATE - Fin del periodo de medicion
-- Y retornan NUMERIC con el valor calculado del indicador.
--
-- Se usa SECURITY DEFINER para que las funciones puedan leer todas las tablas
-- necesarias sin que las politicas RLS del usuario invocante las bloqueen.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- KPI-A1: Diferencia inventario combustibles
-- Formula: ABS(SUM(diferencia)) / SUM(stock_sistema) * 100
-- Mide la precision del inventario de combustibles comparando conteo fisico
-- vs sistema. Un valor menor indica mejor gestion de inventario.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a1(
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
    v_abs_diferencia NUMERIC;
    v_total_sistema  NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(ABS(cd.diferencia)), 0),
        COALESCE(NULLIF(SUM(cd.stock_sistema), 0), 1)
    INTO v_abs_diferencia, v_total_sistema
    FROM conteo_detalle cd
    JOIN conteos_inventario ci ON ci.id = cd.conteo_id
    JOIN bodegas b             ON b.id  = ci.bodega_id
    JOIN productos p           ON p.id  = cd.producto_id
    WHERE b.faena_id = p_faena_id
      AND p.categoria = 'combustible'
      AND ci.fecha_inicio >= p_periodo_inicio
      AND ci.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day')
      AND ci.estado IN ('completado', 'aprobado');

    RETURN ROUND(v_abs_diferencia / v_total_sistema * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a1(UUID,UUID,DATE,DATE) IS
    'KPI-A1: Diferencia porcentual de inventario de combustibles. Menor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-A2: Diferencia inventario lubricantes
-- Formula: ABS(SUM(diferencia)) / SUM(stock_sistema) * 100
-- Misma logica que A1 pero filtrada por categoria lubricante.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a2(
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
    v_abs_diferencia NUMERIC;
    v_total_sistema  NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(ABS(cd.diferencia)), 0),
        COALESCE(NULLIF(SUM(cd.stock_sistema), 0), 1)
    INTO v_abs_diferencia, v_total_sistema
    FROM conteo_detalle cd
    JOIN conteos_inventario ci ON ci.id = cd.conteo_id
    JOIN bodegas b             ON b.id  = ci.bodega_id
    JOIN productos p           ON p.id  = cd.producto_id
    WHERE b.faena_id = p_faena_id
      AND p.categoria = 'lubricante'
      AND ci.fecha_inicio >= p_periodo_inicio
      AND ci.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day')
      AND ci.estado IN ('completado', 'aprobado');

    RETURN ROUND(v_abs_diferencia / v_total_sistema * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a2(UUID,UUID,DATE,DATE) IS
    'KPI-A2: Diferencia porcentual de inventario de lubricantes. Menor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-A3: Exactitud inventario IRA (Inventory Record Accuracy)
-- Formula: items_sin_diferencia / total_items_contados * 100
-- Porcentaje de items que coinciden exactamente entre fisico y sistema.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a3(
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
    v_items_sin_diff NUMERIC;
    v_total_items    NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE cd.diferencia = 0), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_items_sin_diff, v_total_items
    FROM conteo_detalle cd
    JOIN conteos_inventario ci ON ci.id = cd.conteo_id
    JOIN bodegas b             ON b.id  = ci.bodega_id
    WHERE b.faena_id = p_faena_id
      AND ci.fecha_inicio >= p_periodo_inicio
      AND ci.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day')
      AND ci.estado IN ('completado', 'aprobado');

    RETURN ROUND(v_items_sin_diff / v_total_items * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a3(UUID,UUID,DATE,DATE) IS
    'KPI-A3: Exactitud de inventario IRA. Items sin diferencia / total contados * 100.';

-- ---------------------------------------------------------------------------
-- KPI-A4: Cumplimiento normativo
-- Formula: certificaciones_vigentes / certificaciones_requeridas * 100
-- Evalua el estado de las certificaciones regulatorias de los activos de la
-- faena. 100% significa todo en regla.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a4(
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
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.estado <> 'dado_baja';

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a4(UUID,UUID,DATE,DATE) IS
    'KPI-A4: Porcentaje de cumplimiento normativo (certificaciones vigentes).';

-- ---------------------------------------------------------------------------
-- KPI-A5: Cumplimiento abastecimiento programado
-- Formula: OTs abastecimiento ejecutadas / OTs abastecimiento programadas * 100
-- Solo considera OTs del tipo 'abastecimiento' con fecha programada en el
-- periodo. Estados exitosos: 'ejecutada_ok' y 'ejecutada_con_observaciones'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a5(
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
    v_ejecutadas   NUMERIC;
    v_programadas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (
            WHERE ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
        ), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_ejecutadas, v_programadas
    FROM ordenes_trabajo ot
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'abastecimiento'
      AND ot.fecha_programada >= p_periodo_inicio
      AND ot.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_ejecutadas / v_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a5(UUID,UUID,DATE,DATE) IS
    'KPI-A5: Cumplimiento de abastecimiento programado (% OTs ejecutadas).';

-- ---------------------------------------------------------------------------
-- KPI-A6: Rotacion de stock
-- Formula: SUM(costo_total salidas en periodo) / AVG(valor_total stock_bodega)
-- Mide cuantas veces se renueva el inventario. Se anualiza si el periodo
-- es menor a un ano.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a6(
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
    v_costo_salidas     NUMERIC;
    v_valor_inv_prom    NUMERIC;
    v_dias_periodo      NUMERIC;
    v_rotacion          NUMERIC;
BEGIN
    -- Costo total de salidas en el periodo
    SELECT COALESCE(SUM(mi.costo_total), 0)
    INTO v_costo_salidas
    FROM movimientos_inventario mi
    JOIN bodegas b ON b.id = mi.bodega_id
    WHERE b.faena_id = p_faena_id
      AND mi.tipo = 'salida'
      AND mi.created_at >= p_periodo_inicio
      AND mi.created_at <  (p_periodo_fin + INTERVAL '1 day');

    -- Valor promedio del inventario (snapshot actual simplificado)
    SELECT COALESCE(NULLIF(AVG(sb.valor_total), 0), 1)
    INTO v_valor_inv_prom
    FROM stock_bodega sb
    JOIN bodegas b ON b.id = sb.bodega_id
    WHERE b.faena_id = p_faena_id;

    -- Calcular rotacion del periodo
    v_rotacion := v_costo_salidas / v_valor_inv_prom;

    -- Anualizar si el periodo es menor a 365 dias
    v_dias_periodo := (p_periodo_fin - p_periodo_inicio + 1);
    IF v_dias_periodo > 0 AND v_dias_periodo < 365 THEN
        v_rotacion := v_rotacion * (365.0 / v_dias_periodo);
    END IF;

    RETURN ROUND(v_rotacion, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a6(UUID,UUID,DATE,DATE) IS
    'KPI-A6: Rotacion de stock anualizada. Mayor rotacion indica mejor gestion.';

-- ---------------------------------------------------------------------------
-- KPI-A7: Despacho oportuno
-- Formula: rutas completadas a tiempo / total rutas * 100
-- Evalua si las rutas de despacho se completaron en o antes de la fecha
-- programada.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a7(
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
    v_a_tiempo    NUMERIC;
    v_total       NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (
            WHERE rd.fecha_ejecucion <= rd.fecha_programada
              AND rd.estado = 'completada'
        ), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_a_tiempo, v_total
    FROM rutas_despacho rd
    WHERE rd.faena_id = p_faena_id
      AND rd.fecha_programada >= p_periodo_inicio
      AND rd.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_a_tiempo / v_total * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a7(UUID,UUID,DATE,DATE) IS
    'KPI-A7: Porcentaje de despachos realizados dentro del plazo programado.';

-- ---------------------------------------------------------------------------
-- KPI-A8: Costo merma sobre ventas (salidas)
-- Formula: SUM(costo mermas) / SUM(costo salidas) * 100
-- Porcentaje que representan las mermas respecto al total de salidas.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_a8(
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
    v_costo_mermas   NUMERIC;
    v_costo_salidas  NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(mi.costo_total) FILTER (WHERE mi.tipo = 'merma'), 0),
        COALESCE(NULLIF(SUM(mi.costo_total) FILTER (WHERE mi.tipo = 'salida'), 0), 1)
    INTO v_costo_mermas, v_costo_salidas
    FROM movimientos_inventario mi
    JOIN bodegas b ON b.id = mi.bodega_id
    WHERE b.faena_id = p_faena_id
      AND mi.tipo IN ('merma', 'salida')
      AND mi.created_at >= p_periodo_inicio
      AND mi.created_at <  (p_periodo_fin + INTERVAL '1 day');

    RETURN ROUND(v_costo_mermas / v_costo_salidas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_a8(UUID,UUID,DATE,DATE) IS
    'KPI-A8: Costo de mermas como porcentaje de las salidas totales. Menor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-B1: Disponibilidad operacional (puntos fijos)
-- Formula: (horas_operativas / horas_programadas) * 100
-- Se calcula como: total_activos * horas_periodo - horas_correctivo_downtime
-- dividido por total_activos * horas_periodo.
-- Aplica a activos tipo punto_fijo: surtidor, dispensador, estanque, bomba,
-- manguera, equipo_bombeo, herramienta_critica, pistola_captura.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b1(
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
    v_total_activos       NUMERIC;
    v_horas_periodo       NUMERIC;
    v_horas_programadas   NUMERIC;
    v_horas_downtime      NUMERIC;
BEGIN
    -- Tipos considerados punto fijo
    -- Contar activos fijos activos en la faena
    SELECT COUNT(*)
    INTO v_total_activos
    FROM activos a
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND a.estado <> 'dado_baja';

    IF v_total_activos = 0 THEN
        RETURN 100.00;  -- Sin activos, no hay indisponibilidad
    END IF;

    -- Horas del periodo (24h por dia)
    v_horas_periodo := (p_periodo_fin - p_periodo_inicio + 1) * 24.0;
    v_horas_programadas := v_total_activos * v_horas_periodo;

    -- Horas de downtime: sumar duracion de OTs correctivas para activos fijos
    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (
            COALESCE(ot.fecha_termino, NOW()) - ot.fecha_inicio
        )) / 3600.0
    ), 0)
    INTO v_horas_downtime
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND ot.fecha_inicio IS NOT NULL
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    IF v_horas_programadas = 0 THEN
        RETURN 100.00;
    END IF;

    RETURN ROUND((v_horas_programadas - v_horas_downtime) / v_horas_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b1(UUID,UUID,DATE,DATE) IS
    'KPI-B1: Disponibilidad operacional de puntos fijos. BLOQUEANTE (meta >= 97%).';

-- ---------------------------------------------------------------------------
-- KPI-B2: MTTR puntos fijos (Mean Time To Repair)
-- Formula: AVG(fecha_termino - fecha_inicio) en horas
-- Promedio de horas de reparacion para OTs correctivas de activos fijos.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b2(
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
    SELECT COALESCE(AVG(
        EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0
    ), 0)
    INTO v_mttr
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND ot.fecha_inicio  IS NOT NULL
      AND ot.fecha_termino IS NOT NULL
      AND ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    RETURN ROUND(v_mttr, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b2(UUID,UUID,DATE,DATE) IS
    'KPI-B2: MTTR puntos fijos en horas. Meta <= 4 hrs. Menor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-B3: Cumplimiento PM puntos fijos
-- Formula: OTs preventivo ejecutadas / OTs preventivo programadas * 100
-- Mide adherencia al plan de mantenimiento preventivo de activos fijos.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b3(
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
    v_ejecutadas   NUMERIC;
    v_programadas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (
            WHERE ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
        ), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_ejecutadas, v_programadas
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'preventivo'
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND ot.fecha_programada >= p_periodo_inicio
      AND ot.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_ejecutadas / v_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b3(UUID,UUID,DATE,DATE) IS
    'KPI-B3: Cumplimiento de mantenimiento preventivo de puntos fijos (%).';

-- ---------------------------------------------------------------------------
-- KPI-B4: Vigencia certificaciones puntos fijos
-- Formula: certificaciones vigentes / total requeridas * 100
-- Verifica que todas las certificaciones de activos fijos esten al dia.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b4(
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
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND a.estado <> 'dado_baja';

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b4(UUID,UUID,DATE,DATE) IS
    'KPI-B4: Vigencia de certificaciones de puntos fijos (%). BLOQUEANTE (meta 100%).';

-- ---------------------------------------------------------------------------
-- KPI-B5: Tasa de correctivos puntos fijos
-- Formula: OTs correctivo / (correctivo + preventivo) * 100
-- Un porcentaje alto de correctivos indica mantenimiento reactivo.
-- Meta: <= 20%.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b5(
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
    v_correctivos  NUMERIC;
    v_total        NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE ot.tipo = 'correctivo'), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_correctivos, v_total
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo IN ('correctivo', 'preventivo')
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND ot.fecha_programada >= p_periodo_inicio
      AND ot.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_correctivos / v_total * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b5(UUID,UUID,DATE,DATE) IS
    'KPI-B5: Tasa de correctivos sobre total de OTs (correctivo+preventivo) puntos fijos.';

-- ---------------------------------------------------------------------------
-- KPI-B6: Incidentes ambientales/seguridad puntos fijos
-- Formula: COUNT de incidentes tipo ambiental o seguridad
-- Meta ideal: 0 incidentes. Es bloqueante.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_b6(
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
    v_count NUMERIC;
BEGIN
    SELECT COALESCE(COUNT(*), 0)
    INTO v_count
    FROM incidentes i
    WHERE i.faena_id = p_faena_id
      AND i.contrato_id = p_contrato_id
      AND i.tipo IN ('ambiental', 'seguridad')
      AND i.fecha_incidente >= p_periodo_inicio
      AND i.fecha_incidente <  (p_periodo_fin + INTERVAL '1 day');

    -- Retorna conteo absoluto; la evaluacion contra meta se hace en el calculador
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION calcular_kpi_b6(UUID,UUID,DATE,DATE) IS
    'KPI-B6: Conteo de incidentes ambientales/seguridad en puntos fijos. BLOQUEANTE (meta 0).';

-- ---------------------------------------------------------------------------
-- KPI-C1: Disponibilidad flota (puntos moviles)
-- Formula: misma logica que B1 pero para activos tipo movil
-- Tipos moviles: camion_cisterna, lubrimovil, camioneta, camion, equipo_menor,
--                punto_movil
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c1(
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
    v_total_activos       NUMERIC;
    v_horas_periodo       NUMERIC;
    v_horas_programadas   NUMERIC;
    v_horas_downtime      NUMERIC;
BEGIN
    SELECT COUNT(*)
    INTO v_total_activos
    FROM activos a
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND a.estado <> 'dado_baja';

    IF v_total_activos = 0 THEN
        RETURN 100.00;
    END IF;

    v_horas_periodo := (p_periodo_fin - p_periodo_inicio + 1) * 24.0;
    v_horas_programadas := v_total_activos * v_horas_periodo;

    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (
            COALESCE(ot.fecha_termino, NOW()) - ot.fecha_inicio
        )) / 3600.0
    ), 0)
    INTO v_horas_downtime
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND ot.fecha_inicio IS NOT NULL
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    IF v_horas_programadas = 0 THEN
        RETURN 100.00;
    END IF;

    RETURN ROUND((v_horas_programadas - v_horas_downtime) / v_horas_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c1(UUID,UUID,DATE,DATE) IS
    'KPI-C1: Disponibilidad operacional de flota movil (%). BLOQUEANTE (meta >= 97%).';

-- ---------------------------------------------------------------------------
-- KPI-C2: Cumplimiento PM flota
-- Formula: OTs preventivo ejecutadas / programadas * 100 para activos moviles
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c2(
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
    v_ejecutadas   NUMERIC;
    v_programadas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (
            WHERE ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
        ), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_ejecutadas, v_programadas
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'preventivo'
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND ot.fecha_programada >= p_periodo_inicio
      AND ot.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_ejecutadas / v_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c2(UUID,UUID,DATE,DATE) IS
    'KPI-C2: Cumplimiento de mantenimiento preventivo de flota movil (%).';

-- ---------------------------------------------------------------------------
-- KPI-C3: Cumplimiento rutas/despachos
-- Formula: rutas completadas / rutas programadas * 100
-- Mide el cumplimiento general de las rutas de despacho planificadas.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c3(
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
    v_completadas  NUMERIC;
    v_programadas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE rd.estado = 'completada'), 0),
        COALESCE(NULLIF(COUNT(*), 0), 1)
    INTO v_completadas, v_programadas
    FROM rutas_despacho rd
    WHERE rd.faena_id = p_faena_id
      AND rd.fecha_programada >= p_periodo_inicio
      AND rd.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_completadas / v_programadas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c3(UUID,UUID,DATE,DATE) IS
    'KPI-C3: Porcentaje de rutas/despachos completados vs programados.';

-- ---------------------------------------------------------------------------
-- KPI-C4: MTTR flota (Mean Time To Repair)
-- Formula: AVG(fecha_termino - fecha_inicio) en horas para moviles
-- Meta <= 8 horas.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c4(
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
    SELECT COALESCE(AVG(
        EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0
    ), 0)
    INTO v_mttr
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND ot.fecha_inicio  IS NOT NULL
      AND ot.fecha_termino IS NOT NULL
      AND ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    RETURN ROUND(v_mttr, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c4(UUID,UUID,DATE,DATE) IS
    'KPI-C4: MTTR flota movil en horas. Meta <= 8 hrs. Menor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-C5: Rendimiento km/l
-- Formula: SUM(km_reales) / SUM(litros_despachados)
-- Mide la eficiencia de combustible de la flota movil.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c5(
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
    v_km_total     NUMERIC;
    v_litros_total NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(rd.km_reales), 0),
        COALESCE(NULLIF(SUM(rd.litros_despachados), 0), 1)
    INTO v_km_total, v_litros_total
    FROM rutas_despacho rd
    WHERE rd.faena_id = p_faena_id
      AND rd.fecha_programada >= p_periodo_inicio
      AND rd.fecha_programada <= p_periodo_fin;

    RETURN ROUND(v_km_total / v_litros_total, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c5(UUID,UUID,DATE,DATE) IS
    'KPI-C5: Rendimiento de combustible de la flota en km/l. Mayor es mejor.';

-- ---------------------------------------------------------------------------
-- KPI-C6: Vigencia documentacion legal moviles
-- Formula: documentos vigentes / total requeridos * 100
-- Incluye revision tecnica, SOAP, licencias, seguros, etc.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c6(
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
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND a.estado <> 'dado_baja';

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c6(UUID,UUID,DATE,DATE) IS
    'KPI-C6: Vigencia de documentacion legal de flota movil (%). BLOQUEANTE (meta 100%).';

-- ---------------------------------------------------------------------------
-- KPI-C7: Accidentes/incidentes de ruta
-- Formula: COUNT de incidentes tipo vehicular
-- Meta ideal: 0 incidentes. Es bloqueante.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_kpi_c7(
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
    v_count NUMERIC;
BEGIN
    SELECT COALESCE(COUNT(*), 0)
    INTO v_count
    FROM incidentes i
    WHERE i.faena_id = p_faena_id
      AND i.contrato_id = p_contrato_id
      AND i.tipo = 'vehicular'
      AND i.fecha_incidente >= p_periodo_inicio
      AND i.fecha_incidente <  (p_periodo_fin + INTERVAL '1 day');

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION calcular_kpi_c7(UUID,UUID,DATE,DATE) IS
    'KPI-C7: Conteo de accidentes/incidentes vehiculares en ruta. BLOQUEANTE (meta 0).';


-- ============================================================================
-- SECCION 2: CALCULADOR MAESTRO DE TODOS LOS KPI
-- ============================================================================
-- Itera sobre las definiciones activas de KPI, invoca la funcion de calculo
-- correspondiente, determina el tramo de puntaje, calcula el valor ponderado
-- y persiste los resultados en mediciones_kpi mediante UPSERT.
-- ============================================================================

-- Tipo compuesto para el retorno del calculador maestro
DROP TYPE IF EXISTS resultado_kpi CASCADE;
CREATE TYPE resultado_kpi AS (
    kpi_definicion_id   UUID,
    codigo              VARCHAR(10),
    nombre              VARCHAR(200),
    area                area_kpi_enum,
    valor_medido        NUMERIC,
    meta                NUMERIC,
    porcentaje_cumplimiento NUMERIC,
    puntaje             NUMERIC,
    peso                NUMERIC,
    valor_ponderado     NUMERIC,
    es_bloqueante       BOOLEAN,
    bloqueante_activado BOOLEAN
);

CREATE OR REPLACE FUNCTION calcular_todos_kpi(
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_periodo_inicio DATE,
    p_periodo_fin    DATE
)
RETURNS SETOF resultado_kpi
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_kpi             RECORD;
    v_resultado       resultado_kpi;
    v_valor_medido    NUMERIC;
    v_pct_cumplimiento NUMERIC;
    v_puntaje         NUMERIC;
    v_bloqueante_act  BOOLEAN;
BEGIN
    -- Iterar sobre cada KPI activo definido en el sistema
    FOR v_kpi IN
        SELECT
            kd.id,
            kd.codigo,
            kd.nombre,
            kd.area,
            kd.funcion_calculo,
            kd.meta,
            kd.peso,
            kd.es_bloqueante,
            kd.umbral_bloqueante,
            kd.efecto_bloqueante,
            kd.menor_es_mejor
        FROM kpi_definiciones kd
        WHERE kd.activo = true
        ORDER BY kd.area, kd.codigo
    LOOP
        -- ----------------------------------------------------------------
        -- Paso 1: Invocar la funcion de calculo individual via EXECUTE
        -- La columna funcion_calculo almacena el nombre de la funcion
        -- (ej: 'calcular_kpi_a1')
        -- ----------------------------------------------------------------
        BEGIN
            EXECUTE format(
                'SELECT %I($1, $2, $3, $4)',
                v_kpi.funcion_calculo
            )
            INTO v_valor_medido
            USING p_contrato_id, p_faena_id, p_periodo_inicio, p_periodo_fin;
        EXCEPTION WHEN OTHERS THEN
            -- Si la funcion falla, registrar NULL y continuar
            v_valor_medido := NULL;
        END;

        -- ----------------------------------------------------------------
        -- Paso 2: Calcular porcentaje de cumplimiento respecto a la meta
        -- Para KPIs donde menor_es_mejor (ej: MTTR, merma, incidentes),
        -- invertimos la logica.
        -- ----------------------------------------------------------------
        IF v_valor_medido IS NOT NULL AND v_kpi.meta IS NOT NULL AND v_kpi.meta <> 0 THEN
            IF v_kpi.menor_es_mejor THEN
                -- Para indicadores inversos: si el valor es menor que la meta, el
                -- cumplimiento es > 100%; si es mayor, es < 100%.
                -- Ej: meta 4 hrs, medido 3 hrs -> 133% cumplimiento
                v_pct_cumplimiento := ROUND(v_kpi.meta / NULLIF(v_valor_medido, 0) * 100, 2);
            ELSE
                v_pct_cumplimiento := ROUND(v_valor_medido / v_kpi.meta * 100, 2);
            END IF;
        ELSE
            v_pct_cumplimiento := 0;
        END IF;

        -- ----------------------------------------------------------------
        -- Paso 3: Buscar puntaje en la tabla de tramos
        -- Los tramos definen rangos de cumplimiento y su puntaje asociado.
        -- ----------------------------------------------------------------
        SELECT kt.puntaje
        INTO v_puntaje
        FROM kpi_tramos kt
        WHERE kt.kpi_definicion_id = v_kpi.id
          AND v_pct_cumplimiento >= kt.rango_min
          AND v_pct_cumplimiento <  kt.rango_max
        ORDER BY kt.rango_min DESC
        LIMIT 1;

        -- Si no se encuentra tramo, asignar 0
        v_puntaje := COALESCE(v_puntaje, 0);

        -- ----------------------------------------------------------------
        -- Paso 4: Verificar condicion bloqueante
        -- Un KPI bloqueante con valor bajo su umbral se marca activado
        -- ----------------------------------------------------------------
        v_bloqueante_act := false;
        IF v_kpi.es_bloqueante AND v_kpi.umbral_bloqueante IS NOT NULL THEN
            IF v_kpi.menor_es_mejor THEN
                -- Para indicadores inversos, el bloqueante se activa si el
                -- valor supera el umbral (ej: incidentes > 0)
                v_bloqueante_act := (COALESCE(v_valor_medido, 0) > v_kpi.umbral_bloqueante);
            ELSE
                v_bloqueante_act := (COALESCE(v_pct_cumplimiento, 0) < v_kpi.umbral_bloqueante);
            END IF;
        END IF;

        -- ----------------------------------------------------------------
        -- Paso 5: UPSERT en mediciones_kpi
        -- ----------------------------------------------------------------
        INSERT INTO mediciones_kpi (
            contrato_id,
            faena_id,
            kpi_definicion_id,
            periodo_inicio,
            periodo_fin,
            valor_medido,
            porcentaje_cumplimiento,
            puntaje,
            valor_ponderado,
            bloqueante_activado,
            calculado_en
        ) VALUES (
            p_contrato_id,
            p_faena_id,
            v_kpi.id,
            p_periodo_inicio,
            p_periodo_fin,
            v_valor_medido,
            v_pct_cumplimiento,
            v_puntaje,
            ROUND(v_puntaje * v_kpi.peso / 100.0, 4),
            v_bloqueante_act,
            NOW()
        )
        ON CONFLICT (contrato_id, faena_id, kpi_definicion_id, periodo_inicio, periodo_fin)
        DO UPDATE SET
            valor_medido            = EXCLUDED.valor_medido,
            porcentaje_cumplimiento = EXCLUDED.porcentaje_cumplimiento,
            puntaje                 = EXCLUDED.puntaje,
            valor_ponderado         = EXCLUDED.valor_ponderado,
            bloqueante_activado     = EXCLUDED.bloqueante_activado,
            calculado_en            = EXCLUDED.calculado_en;

        -- ----------------------------------------------------------------
        -- Paso 6: Armar fila de resultado
        -- ----------------------------------------------------------------
        v_resultado.kpi_definicion_id     := v_kpi.id;
        v_resultado.codigo                := v_kpi.codigo;
        v_resultado.nombre                := v_kpi.nombre;
        v_resultado.area                  := v_kpi.area;
        v_resultado.valor_medido          := v_valor_medido;
        v_resultado.meta                  := v_kpi.meta;
        v_resultado.porcentaje_cumplimiento := v_pct_cumplimiento;
        v_resultado.puntaje               := v_puntaje;
        v_resultado.peso                  := v_kpi.peso;
        v_resultado.valor_ponderado       := ROUND(v_puntaje * v_kpi.peso / 100.0, 4);
        v_resultado.es_bloqueante         := v_kpi.es_bloqueante;
        v_resultado.bloqueante_activado   := v_bloqueante_act;

        RETURN NEXT v_resultado;
    END LOOP;

    RETURN;
END;
$$;

COMMENT ON FUNCTION calcular_todos_kpi(UUID,UUID,DATE,DATE) IS
    'Calculador maestro: itera sobre KPI activos, calcula valores, determina tramos y puntajes, y persiste en mediciones_kpi.';


-- ============================================================================
-- SECCION 3: CALCULADOR DE ICEO
-- ============================================================================
-- Orquesta el calculo completo del Indice Compuesto de Excelencia Operacional:
--   1. Ejecuta calcular_todos_kpi
--   2. Agrega puntajes por area (A, B, C)
--   3. Aplica pesos por area desde configuracion_iceo
--   4. Calcula ICEO bruto
--   5. Procesa bloqueantes (anular, penalizar, descontar, bloquear_incentivo)
--   6. Determina clasificacion (deficiente/aceptable/bueno/excelencia)
--   7. Persiste en iceo_periodos e iceo_detalle
-- ============================================================================

-- Tipo compuesto para el retorno del ICEO
DROP TYPE IF EXISTS resultado_iceo CASCADE;
CREATE TYPE resultado_iceo AS (
    iceo_periodo_id     UUID,
    contrato_id         UUID,
    faena_id            UUID,
    periodo_inicio      DATE,
    periodo_fin         DATE,
    puntaje_area_a      NUMERIC,
    puntaje_area_b      NUMERIC,
    puntaje_area_c      NUMERIC,
    peso_area_a         NUMERIC,
    peso_area_b         NUMERIC,
    peso_area_c         NUMERIC,
    iceo_bruto          NUMERIC,
    iceo_final          NUMERIC,
    clasificacion       clasificacion_iceo_enum,
    incentivo_habilitado BOOLEAN,
    bloqueantes_activos  TEXT,
    calculado_en        TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION calcular_iceo(
    p_contrato_id    UUID,
    p_faena_id       UUID,
    p_periodo_inicio DATE,
    p_periodo_fin    DATE
)
RETURNS resultado_iceo
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resultado        resultado_iceo;
    v_kpi_row          resultado_kpi;
    v_puntaje_a        NUMERIC := 0;
    v_puntaje_b        NUMERIC := 0;
    v_puntaje_c        NUMERIC := 0;
    v_peso_a           NUMERIC;
    v_peso_b           NUMERIC;
    v_peso_c           NUMERIC;
    v_iceo_bruto       NUMERIC;
    v_iceo_final       NUMERIC;
    v_incentivo        BOOLEAN := true;
    v_clasificacion    clasificacion_iceo_enum;
    v_iceo_periodo_id  UUID;
    v_bloqueantes      TEXT[] := '{}';
    v_efecto           efecto_bloqueante_enum;
    v_factor           NUMERIC;
    v_puntos_desc      NUMERIC;
    v_efecto_mas_severo TEXT := NULL;
    v_factor_penal     NUMERIC := 1.0;
    v_puntos_total_desc NUMERIC := 0;
    v_anulado          BOOLEAN := false;
    v_bloq_incentivo   BOOLEAN := false;
BEGIN
    -- ====================================================================
    -- PASO 1: Calcular todos los KPI del periodo
    -- ====================================================================
    FOR v_kpi_row IN
        SELECT * FROM calcular_todos_kpi(p_contrato_id, p_faena_id, p_periodo_inicio, p_periodo_fin)
    LOOP
        -- Acumular valor ponderado por area
        CASE v_kpi_row.area
            WHEN 'administracion_combustibles' THEN
                v_puntaje_a := v_puntaje_a + COALESCE(v_kpi_row.valor_ponderado, 0);
            WHEN 'mantenimiento_fijos' THEN
                v_puntaje_b := v_puntaje_b + COALESCE(v_kpi_row.valor_ponderado, 0);
            WHEN 'mantenimiento_moviles' THEN
                v_puntaje_c := v_puntaje_c + COALESCE(v_kpi_row.valor_ponderado, 0);
        END CASE;

        -- Recopilar bloqueantes activados
        IF v_kpi_row.bloqueante_activado THEN
            v_bloqueantes := array_append(v_bloqueantes, v_kpi_row.codigo || ':' || v_kpi_row.nombre);
        END IF;
    END LOOP;

    -- ====================================================================
    -- PASO 2: Obtener pesos por area desde configuracion_iceo
    -- Defaults: A=0.35, B=0.35, C=0.30
    -- ====================================================================
    SELECT
        COALESCE(ci.peso_area_a, 0.35),
        COALESCE(ci.peso_area_b, 0.35),
        COALESCE(ci.peso_area_c, 0.30)
    INTO v_peso_a, v_peso_b, v_peso_c
    FROM configuracion_iceo ci
    WHERE ci.contrato_id = p_contrato_id
      AND ci.activo = true
    ORDER BY ci.created_at DESC
    LIMIT 1;

    -- Si no hay configuracion, usar defaults
    IF NOT FOUND THEN
        v_peso_a := 0.35;
        v_peso_b := 0.35;
        v_peso_c := 0.30;
    END IF;

    -- ====================================================================
    -- PASO 3: Calcular ICEO bruto
    -- ====================================================================
    v_iceo_bruto := ROUND(
        (v_puntaje_a * v_peso_a) +
        (v_puntaje_b * v_peso_b) +
        (v_puntaje_c * v_peso_c),
        2
    );
    v_iceo_final := v_iceo_bruto;

    -- ====================================================================
    -- PASO 4: Procesar bloqueantes
    -- Obtener las reglas de efecto de cada bloqueante activado y aplicar
    -- la mas severa. Severidad: anular > penalizar > descontar > bloquear_incentivo
    -- ====================================================================
    IF array_length(v_bloqueantes, 1) > 0 THEN
        -- Recorrer cada KPI bloqueante activado para determinar su efecto
        FOR v_kpi_row IN
            SELECT rk.*
            FROM calcular_todos_kpi(p_contrato_id, p_faena_id, p_periodo_inicio, p_periodo_fin) rk
            WHERE rk.bloqueante_activado = true
        LOOP
            -- Obtener efecto y factor del bloqueante desde la definicion
            SELECT
                kd.efecto_bloqueante,
                kd.factor_penalizacion,
                kd.puntos_descuento
            INTO v_efecto, v_factor, v_puntos_desc
            FROM kpi_definiciones kd
            WHERE kd.id = v_kpi_row.kpi_definicion_id;

            -- Evaluar y acumular efectos
            CASE v_efecto
                WHEN 'anular' THEN
                    v_anulado := true;
                WHEN 'penalizar' THEN
                    -- Tomar el factor mas severo (menor)
                    v_factor_penal := LEAST(v_factor_penal, COALESCE(v_factor, 0.5));
                WHEN 'descontar' THEN
                    v_puntos_total_desc := v_puntos_total_desc + COALESCE(v_puntos_desc, 0);
                WHEN 'bloquear_incentivo' THEN
                    v_bloq_incentivo := true;
            END CASE;
        END LOOP;

        -- Aplicar efecto mas severo
        IF v_anulado THEN
            -- Anular: ICEO = 0
            v_iceo_final := 0;
            v_incentivo := false;
        ELSIF v_factor_penal < 1.0 THEN
            -- Penalizar: multiplicar por factor
            v_iceo_final := ROUND(v_iceo_bruto * v_factor_penal, 2);
            v_incentivo := false;
        ELSIF v_puntos_total_desc > 0 THEN
            -- Descontar puntos directamente
            v_iceo_final := GREATEST(ROUND(v_iceo_bruto - v_puntos_total_desc, 2), 0);
            IF v_iceo_final < v_iceo_bruto * 0.5 THEN
                v_incentivo := false;
            END IF;
        END IF;

        -- Bloquear incentivo si corresponde (independiente de otros efectos)
        IF v_bloq_incentivo THEN
            v_incentivo := false;
        END IF;
    END IF;

    -- ====================================================================
    -- PASO 5: Determinar clasificacion ICEO
    -- Umbrales: < 70 deficiente, 70-84 aceptable, 85-94 bueno, >= 95 excelencia
    -- ====================================================================
    IF v_iceo_final < 70 THEN
        v_clasificacion := 'deficiente';
    ELSIF v_iceo_final < 85 THEN
        v_clasificacion := 'aceptable';
    ELSIF v_iceo_final < 95 THEN
        v_clasificacion := 'bueno';
    ELSE
        v_clasificacion := 'excelencia';
    END IF;

    -- ====================================================================
    -- PASO 6: UPSERT en iceo_periodos
    -- ====================================================================
    INSERT INTO iceo_periodos (
        contrato_id,
        faena_id,
        periodo_inicio,
        periodo_fin,
        puntaje_area_a,
        puntaje_area_b,
        puntaje_area_c,
        peso_area_a,
        peso_area_b,
        peso_area_c,
        iceo_bruto,
        iceo_final,
        clasificacion,
        incentivo_habilitado,
        bloqueantes_activos,
        calculado_en
    ) VALUES (
        p_contrato_id,
        p_faena_id,
        p_periodo_inicio,
        p_periodo_fin,
        v_puntaje_a,
        v_puntaje_b,
        v_puntaje_c,
        v_peso_a,
        v_peso_b,
        v_peso_c,
        v_iceo_bruto,
        v_iceo_final,
        v_clasificacion,
        v_incentivo,
        array_to_string(v_bloqueantes, ', '),
        NOW()
    )
    ON CONFLICT (contrato_id, faena_id, periodo_inicio, periodo_fin)
    DO UPDATE SET
        puntaje_area_a       = EXCLUDED.puntaje_area_a,
        puntaje_area_b       = EXCLUDED.puntaje_area_b,
        puntaje_area_c       = EXCLUDED.puntaje_area_c,
        peso_area_a          = EXCLUDED.peso_area_a,
        peso_area_b          = EXCLUDED.peso_area_b,
        peso_area_c          = EXCLUDED.peso_area_c,
        iceo_bruto           = EXCLUDED.iceo_bruto,
        iceo_final           = EXCLUDED.iceo_final,
        clasificacion        = EXCLUDED.clasificacion,
        incentivo_habilitado = EXCLUDED.incentivo_habilitado,
        bloqueantes_activos  = EXCLUDED.bloqueantes_activos,
        calculado_en         = EXCLUDED.calculado_en
    RETURNING id INTO v_iceo_periodo_id;

    -- ====================================================================
    -- PASO 7: Insertar detalle por KPI en iceo_detalle
    -- Primero eliminamos detalle anterior del mismo periodo, luego insertamos
    -- ====================================================================
    DELETE FROM iceo_detalle
    WHERE iceo_periodo_id = v_iceo_periodo_id;

    INSERT INTO iceo_detalle (
        iceo_periodo_id,
        kpi_definicion_id,
        valor_medido,
        porcentaje_cumplimiento,
        puntaje,
        peso,
        valor_ponderado,
        bloqueante_activado
    )
    SELECT
        v_iceo_periodo_id,
        mk.kpi_definicion_id,
        mk.valor_medido,
        mk.porcentaje_cumplimiento,
        mk.puntaje,
        kd.peso,
        mk.valor_ponderado,
        mk.bloqueante_activado
    FROM mediciones_kpi mk
    JOIN kpi_definiciones kd ON kd.id = mk.kpi_definicion_id
    WHERE mk.contrato_id    = p_contrato_id
      AND mk.faena_id       = p_faena_id
      AND mk.periodo_inicio = p_periodo_inicio
      AND mk.periodo_fin    = p_periodo_fin;

    -- ====================================================================
    -- PASO 8: Armar resultado de retorno
    -- ====================================================================
    v_resultado.iceo_periodo_id      := v_iceo_periodo_id;
    v_resultado.contrato_id          := p_contrato_id;
    v_resultado.faena_id             := p_faena_id;
    v_resultado.periodo_inicio       := p_periodo_inicio;
    v_resultado.periodo_fin          := p_periodo_fin;
    v_resultado.puntaje_area_a       := v_puntaje_a;
    v_resultado.puntaje_area_b       := v_puntaje_b;
    v_resultado.puntaje_area_c       := v_puntaje_c;
    v_resultado.peso_area_a          := v_peso_a;
    v_resultado.peso_area_b          := v_peso_b;
    v_resultado.peso_area_c          := v_peso_c;
    v_resultado.iceo_bruto           := v_iceo_bruto;
    v_resultado.iceo_final           := v_iceo_final;
    v_resultado.clasificacion        := v_clasificacion;
    v_resultado.incentivo_habilitado := v_incentivo;
    v_resultado.bloqueantes_activos  := array_to_string(v_bloqueantes, ', ');
    v_resultado.calculado_en         := NOW();

    RETURN v_resultado;
END;
$$;

COMMENT ON FUNCTION calcular_iceo(UUID,UUID,DATE,DATE) IS
    'Calculador ICEO: orquesta KPIs, agrega por area, aplica bloqueantes, clasifica y persiste resultado.';


-- ============================================================================
-- SECCION 4: FUNCION DE VALORIZACION CPP (Costo Promedio Ponderado)
-- ============================================================================
-- Calcula el nuevo costo promedio ponderado al ingresar stock.
-- Formula: ((qty_actual * cpp_actual) + (qty_nueva * costo_nuevo)) /
--          (qty_actual + qty_nueva)
-- Esta funcion NO modifica datos; solo calcula y retorna el nuevo CPP.
-- La actualizacion del stock se realiza en el trigger de movimientos.
-- ============================================================================

CREATE OR REPLACE FUNCTION calcular_cpp(
    p_bodega_id     UUID,
    p_producto_id   UUID,
    p_cantidad_nueva NUMERIC,
    p_costo_nuevo   NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_qty_actual  NUMERIC;
    v_cpp_actual  NUMERIC;
    v_nuevo_cpp   NUMERIC;
BEGIN
    -- Obtener stock y CPP actuales
    SELECT
        COALESCE(sb.cantidad, 0),
        COALESCE(sb.costo_promedio, 0)
    INTO v_qty_actual, v_cpp_actual
    FROM stock_bodega sb
    WHERE sb.bodega_id   = p_bodega_id
      AND sb.producto_id = p_producto_id;

    -- Si no existe registro de stock, el CPP es simplemente el costo nuevo
    IF NOT FOUND OR (v_qty_actual + p_cantidad_nueva) = 0 THEN
        RETURN COALESCE(p_costo_nuevo, 0);
    END IF;

    -- Formula CPP: valor_existente + valor_nuevo / cantidad_total
    v_nuevo_cpp := (
        (v_qty_actual * v_cpp_actual) + (p_cantidad_nueva * p_costo_nuevo)
    ) / (v_qty_actual + p_cantidad_nueva);

    RETURN ROUND(v_nuevo_cpp, 4);
END;
$$;

COMMENT ON FUNCTION calcular_cpp(UUID,UUID,NUMERIC,NUMERIC) IS
    'Calcula el nuevo Costo Promedio Ponderado (CPP) al ingresar stock sin modificar datos.';


-- ============================================================================
-- Fin de 06_funciones_kpi_iceo.sql
-- ============================================================================
