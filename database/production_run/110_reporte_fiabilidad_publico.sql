-- ============================================================================
-- SICOM-ICEO | 110 — Reporte de Fiabilidad PUBLICO (para enviar a la org)
-- ============================================================================
-- RPC SECURITY DEFINER que devuelve, en un rango, todo lo que necesita la
-- pagina publica /reporte-fiabilidad:
--   - categorias: KPIs por categoria (fn_calcular_fiabilidad_flota)
--   - equipos:    fiabilidad por patente (fn_calcular_fiabilidad_activo)
--   - matriz:     estado_diario_flota equipo x dia (para el historial al click)
-- Solo flota (camiones, camionetas, lubrimovil, equipo_menor). Sin exponer las
-- tablas crudas a anon: todo sale por esta funcion.
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
    ), '[]'::jsonb)
  );
$$;

COMMENT ON FUNCTION fn_reporte_fiabilidad_publico(DATE, DATE) IS
    'Reporte de fiabilidad de flota para la pagina publica /reporte-fiabilidad: '
    'KPIs por categoria, fiabilidad por patente y matriz dia x estado.';

GRANT EXECUTE ON FUNCTION fn_reporte_fiabilidad_publico(DATE, DATE) TO anon, authenticated;

-- ── Verificacion ───────────────────────────────────────────────────────────
DO $$
DECLARE v JSONB;
BEGIN
    v := fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    RAISE NOTICE '== Reporte fiabilidad publico ==';
    RAISE NOTICE 'categorias: % | equipos: % | matriz: %',
        jsonb_array_length(v->'categorias'),
        jsonb_array_length(v->'equipos'),
        jsonb_array_length(v->'matriz');
END $$;
