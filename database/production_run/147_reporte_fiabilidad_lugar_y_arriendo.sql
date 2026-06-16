-- ============================================================================
-- SICOM-ICEO | 147 — Reporte fiabilidad: lugar fisico + ultimo arriendo por equipo
-- ----------------------------------------------------------------------------
-- Al pulsar la patente en el reporte interactivo, ademas de la ficha tecnica,
-- mostrar el LUGAR FISICO (faena + ubicacion) y el ULTIMO ARRIENDO (quien lo
-- tuvo y donde). Extiende fn_reporte_fiabilidad_publico (base MIG 146) sumando
-- esos campos al bloque 'equipos'. Requiere MIG 145 (v_activo_ultimo_arriendo).
-- IDEMPOTENTE (CREATE OR REPLACE). No cambia el resto de la estructura.
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
        -- Lugar fisico (faena estructurada + detalle libre)
        'estado_comercial', a.estado_comercial,
        'faena', fa.nombre,
        'ubicacion', a.ubicacion_actual,
        'lugar_fisico', NULLIF(concat_ws(' · ', fa.nombre, NULLIF(a.ubicacion_actual,'')), ''),
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

-- Validacion
DO $$ DECLARE v JSONB;
BEGIN
    v := fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    RAISE NOTICE 'equipos: % | con lugar: % | con ultimo arriendo: %',
        jsonb_array_length(v->'equipos'),
        (SELECT count(*) FROM jsonb_array_elements(v->'equipos') e WHERE e->>'lugar_fisico' IS NOT NULL),
        (SELECT count(*) FROM jsonb_array_elements(v->'equipos') e WHERE e->>'ult_cliente' IS NOT NULL);
END $$;
