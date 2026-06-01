-- ============================================================================
-- SICOM-ICEO | 111 — Reporte fiabilidad publico: agregar stock de combustible
-- ============================================================================
-- Agrega la clave 'combustible' a fn_reporte_fiabilidad_publico para que la
-- pagina interactiva /reporte-fiabilidad muestre el stock por estanque.
-- (v_combustible_proyeccion_stock se lee via SECURITY DEFINER, no se expone a anon.)
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
    ), '[]'::jsonb),
    'combustible', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'estanque_codigo', estanque_codigo,
        'estanque_nombre', estanque_nombre,
        'capacidad_lt', capacidad_lt,
        'stock_actual', stock_actual,
        'stock_minimo', stock_minimo,
        'dias_cobertura', dias_cobertura,
        'fecha_agotamiento_estimada', fecha_agotamiento_estimada,
        'severidad', severidad
      ) ORDER BY severidad, estanque_codigo)
      FROM v_combustible_proyeccion_stock
    ), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION fn_reporte_fiabilidad_publico(DATE, DATE) TO anon, authenticated;

DO $$
DECLARE v JSONB;
BEGIN
    v := fn_reporte_fiabilidad_publico();
    RAISE NOTICE 'equipos: % | combustible (estanques): %',
        jsonb_array_length(v->'equipos'), jsonb_array_length(v->'combustible');
END $$;
