-- ============================================================================
-- SICOM-ICEO | 244 — Reporte de fiabilidad: coordenada GPS por equipo
-- ----------------------------------------------------------------------------
-- Pedido Manuel (2026-07-22): en el reporte dinámico, un link al lado de la
-- patente ("ubicación GPS") que abra el mapa con el equipo donde está.
--
-- Se agrega gps_lat / gps_lng / gps_ts a cada equipo del bloque 'equipos'
-- (LEFT JOIN gps_estado_actual). El frontend arma el link a Google Maps. Como
-- la RPC es SECURITY DEFINER, el dato viaja también en el reporte por token
-- (correo a gerencia, sin login).
--
-- CREATE OR REPLACE idéntica a MIG200 + los 3 campos y el join. Misma firma
-- (date, date, text) → no hace falta DROP. IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_publico(
    p_ini DATE DEFAULT date_trunc('month', CURRENT_DATE)::date,
    p_fin DATE DEFAULT CURRENT_DATE,
    p_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_out JSONB;
    v_token_ok BOOLEAN := false;
BEGIN
    -- Guard MIG186 + MIG200: sesión con perfil, conexión admin directa
    -- (scripts de correo / cron como postgres), o token vigente del link.
    IF p_token IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM reporte_tokens t
             WHERE t.reporte = 'fiabilidad' AND t.token = p_token AND t.activo
               AND (t.expira_at IS NULL OR t.expira_at > NOW())
        ) INTO v_token_ok;
    END IF;

    IF session_user <> 'postgres'
       AND (auth.uid() IS NULL OR public.fn_user_rol() IS NULL)
       AND NOT v_token_ok THEN
        RAISE EXCEPTION 'Acceso no autorizado.';
    END IF;

    -- Traza de uso del token (nunca bloquear el reporte por esto)
    IF v_token_ok THEN
        BEGIN
            UPDATE reporte_tokens SET last_used_at = NOW(), usos = usos + 1
             WHERE reporte = 'fiabilidad' AND token = p_token;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

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
        'estado_comercial', a.estado_comercial,
        'faena', NULL,
        'ubicacion', a.ubicacion_actual,
        'lugar_fisico', NULLIF(a.ubicacion_actual, ''),
        'zona', a.operacion,
        -- NUEVO: coordenada GPS para el link al mapa
        'gps_lat', ge.latitud,
        'gps_lng', ge.longitud,
        'gps_ts',  ge.ts_gps,
        'contrato_codigo', co.codigo,
        'contrato_cliente', co.cliente,
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
      LEFT JOIN contratos co ON co.id = a.contrato_id
      LEFT JOIN v_activo_ultimo_arriendo ua ON ua.activo_id = a.id
      LEFT JOIN gps_estado_actual ge ON ge.activo_id = a.id
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
      WHERE estanque_codigo NOT LIKE 'CAM-%'
    ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $$;

COMMENT ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) IS
    'Reporte de fiabilidad (página /reporte-fiabilidad y correo). Acceso: sesión '
    'con perfil, conexión admin directa, o token vigente del link (?t=..., MIG200). '
    'MIG244: incluye gps_lat/gps_lng/gps_ts por equipo.';

REVOKE ALL ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) TO authenticated, anon;

-- Validación
DO $$
DECLARE v JSONB; n_gps INT;
BEGIN
    v := public.fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    SELECT count(*) INTO n_gps FROM jsonb_array_elements(v->'equipos') e
     WHERE e->>'gps_lat' IS NOT NULL;
    RAISE NOTICE 'MIG244 OK: equipos=% · con GPS=%',
        jsonb_array_length(v->'equipos'), n_gps;
END $$;

NOTIFY pgrst, 'reload schema';
