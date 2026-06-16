-- ============================================================================
-- SICOM-ICEO | 149 — Reporte fiabilidad: ultimo contrato + dias en arriendo
-- ----------------------------------------------------------------------------
-- Al pulsar la patente, ademas del lugar fisico y el ultimo arriendo, mostrar:
--   - ULTIMO CONTRATO (codigo + cliente)
--   - DIAS EN ARRIENDO POR CONTRATO (desglose: cuantos dias estuvo el equipo
--     bajo cada contrato en estado A=arrendado o C=en contrato).
-- Extiende fn_reporte_fiabilidad_publico (base MIG 147). Los dias se cuentan de
-- estado_diario_flota (verdad diaria) sobre TODO el historico del equipo.
-- IDEMPOTENTE (CREATE OR REPLACE).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reporte_fiabilidad_publico(
    p_ini DATE DEFAULT date_trunc('month', CURRENT_DATE)::date,
    p_fin DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'desde', p_ini,
    'hasta', p_fin,
    'categorias', COALESCE((
      SELECT jsonb_agg(to_jsonb(k)) FROM fn_calcular_fiabilidad_flota(p_ini, p_fin) k
    ), '[]'::jsonb),
    'equipos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'activo_id', a.id,
        'patente', COALESCE(a.patente, a.codigo),
        'equipamiento', a.nombre,
        'categoria_uso', a.categoria_uso,
        'cliente', a.cliente_actual,
        'marca', mar.nombre,
        'modelo', mod.nombre,
        'anio', a.anio_fabricacion,
        'capacidad', a.capacidad,
        'potencia', a.potencia,
        'vin_chasis', a.vin_chasis,
        'numero_motor', a.numero_motor,
        -- Lugar fisico (faena + detalle libre)
        'estado_comercial', a.estado_comercial,
        'faena', fa.nombre,
        'ubicacion', a.ubicacion_actual,
        'lugar_fisico', NULLIF(concat_ws(' · ', fa.nombre, NULLIF(a.ubicacion_actual,'')), ''),
        -- Ultimo contrato (vigente del equipo)
        'contrato_codigo', co.codigo,
        'contrato_cliente', co.cliente,
        -- Dias en arriendo por contrato (A=arrendado, C=en contrato), todo el historico
        'contratos_dias', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'codigo',  COALESCE(cc.codigo, '(sin contrato)'),
                   'cliente', cc.cliente,
                   'dias',    d.dias
                 ) ORDER BY d.dias DESC)
          FROM (
            SELECT edf.contrato_id, COUNT(*)::int AS dias
            FROM estado_diario_flota edf
            WHERE edf.activo_id = a.id AND edf.estado_codigo IN ('A','C')
            GROUP BY edf.contrato_id
          ) d
          LEFT JOIN contratos cc ON cc.id = d.contrato_id
        ), '[]'::jsonb),
        'dias_arriendo_total', COALESCE((
          SELECT COUNT(*)::int FROM estado_diario_flota edf
          WHERE edf.activo_id = a.id AND edf.estado_codigo IN ('A','C')
        ), 0),
        -- Ultimo arriendo: quien lo tuvo y donde
        'ult_tipo',    ua.tipo_uso,
        'ult_cliente', ua.cliente,
        'ult_lugar',   ua.lugar,
        'ult_desde',   ua.fecha_inicio,
        'ult_hasta',   ua.fecha_fin,
        'ult_dias',    ua.dias,
        'ult_vigente', ua.vigente,
        'dias_observados', f.dias_observados,
        'dias_up', f.dias_up,
        'dias_down', f.dias_down,
        'eventos_falla', f.eventos_falla,
        'mtbf_dias', f.mtbf_dias,
        'mttr_dias', f.mttr_dias,
        'disponibilidad_inherente', f.disponibilidad_inherente,
        'disponibilidad_fisica', f.disponibilidad_fisica
      ) ORDER BY a.patente)
      FROM activos a
      LEFT JOIN modelos mod ON mod.id = a.modelo_id
      LEFT JOIN marcas mar ON mar.id = mod.marca_id
      LEFT JOIN faenas fa  ON fa.id = a.faena_id
      LEFT JOIN contratos co ON co.id = a.contrato_id
      LEFT JOIN v_activo_ultimo_arriendo ua ON ua.activo_id = a.id
      CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(a.id, p_ini, p_fin) f
      WHERE a.estado <> 'dado_baja'
        AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
        AND f.dias_observados > 0
    ), '[]'::jsonb),
    'matriz', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'activo_id', e.activo_id, 'fecha', e.fecha, 'estado', e.estado_codigo
      ))
      FROM estado_diario_flota e
      JOIN activos a ON a.id = e.activo_id
      WHERE e.fecha BETWEEN p_ini AND p_fin
        AND a.estado <> 'dado_baja'
        AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ), '[]'::jsonb)
  );
$$;
GRANT EXECUTE ON FUNCTION fn_reporte_fiabilidad_publico(DATE, DATE) TO anon, authenticated;

DO $$ DECLARE v JSONB;
BEGIN
    v := fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    RAISE NOTICE 'equipos: % | con contrato: % | con dias-por-contrato: %',
        jsonb_array_length(v->'equipos'),
        (SELECT count(*) FROM jsonb_array_elements(v->'equipos') e WHERE e->>'contrato_codigo' IS NOT NULL),
        (SELECT count(*) FROM jsonb_array_elements(v->'equipos') e WHERE jsonb_array_length(e->'contratos_dias') > 0);
END $$;
