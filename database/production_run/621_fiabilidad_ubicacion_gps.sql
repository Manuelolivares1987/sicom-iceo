-- 621 — Ubicación y lugar físico del reporte de fiabilidad (2026-10-19). El Excel
-- que recibió la jefatura repetía en «Ubicación» y «Lugar físico» el mismo texto
-- libre (activos.ubicacion_actual, cargado en junio desde «Status cam» y editado
-- a mano): en 12 equipos el GPS de ese día decía otra cosa (SPRY-28 en Spence y
-- no en «Contrato ESM», RSCY-85 en Franke y no en el taller de Coquimbo, etc.).
-- La faena de la ficha tampoco sirve (JGBY-10 «Sobek» estando en el taller).
--
-- Regla nueva: Ubicación = GPS (geocerca de la última posición, con aviso si no
-- hay señal hace más de 3 días o si está fuera de geocerca). Lugar físico = lo
-- registrado. «coincide» marca cuando lo registrado contradice al GPS.

CREATE OR REPLACE FUNCTION fn_texto_comparable(p TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(regexp_replace(lower(translate(coalesce(p, ''), 'ÁÉÍÓÚÜáéíóúüÑñ', 'AEIOUUaeiouuNn')), '\s+', ' ', 'g'));
$$;

CREATE OR REPLACE VIEW v_activo_ubicacion_reporte AS
SELECT a.id AS activo_id,
       g.latitud, g.longitud,
       g.ts_gps AS gps_fecha,
       gz.nombre AS geocerca,
       round(gz.km::NUMERIC, 1) AS geocerca_km,
       g.ts_gps >= NOW() - INTERVAL '3 days' AS gps_al_dia,
       CASE
           WHEN g.ts_gps IS NULL THEN 'Sin GPS'
           WHEN g.ts_gps < NOW() - INTERVAL '3 days'
               THEN coalesce(gz.nombre, 'Sin geocerca') || ' (último GPS '
                    || to_char(g.ts_gps AT TIME ZONE 'America/Santiago', 'DD-MM-YYYY') || ')'
           ELSE coalesce(gz.nombre, 'Fuera de geocerca (en ruta o faena sin geocerca)')
       END AS ubicacion_gps,
       NULLIF(btrim(a.ubicacion_actual), '') AS lugar_registrado,
       -- Sólo se juzga con GPS al día y dentro de una geocerca. Si lo registrado
       -- trae «lugar, ciudad» se exigen las dos partes (si no, «Taller Pillado,
       -- Coquimbo» calzaría con «Taller Pillado, Calama»).
       CASE
           WHEN g.ts_gps IS NULL OR g.ts_gps < NOW() - INTERVAL '3 days' OR gz.nombre IS NULL
                OR NULLIF(btrim(a.ubicacion_actual), '') IS NULL THEN NULL
           ELSE position(fn_texto_comparable(split_part(gz.nombre, ',', 1)) IN fn_texto_comparable(a.ubicacion_actual)) > 0
                AND (fn_texto_comparable(split_part(gz.nombre, ',', 2)) = ''
                     OR position(',' IN a.ubicacion_actual) = 0
                     OR position(fn_texto_comparable(split_part(gz.nombre, ',', 2)) IN fn_texto_comparable(a.ubicacion_actual)) > 0)
       END AS coincide
  FROM activos a
  LEFT JOIN gps_estado_actual g ON g.activo_id = a.id
  LEFT JOIN LATERAL fn_geocerca_cercana(g.latitud::DOUBLE PRECISION, g.longitud::DOUBLE PRECISION) gz(nombre, km) ON true
 WHERE a.fecha_baja IS NULL AND NOT coalesce(a.es_prueba, false);

GRANT SELECT ON v_activo_ubicacion_reporte TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_publico(p_ini date DEFAULT (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))::date, p_fin date DEFAULT CURRENT_DATE, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        -- [MIG621] Ubicación = GPS de hoy; lugar físico = lo registrado a mano. Antes
      -- las dos columnas repetían activos.ubicacion_actual (texto libre viejo).
      'ubicacion', (SELECT u.ubicacion_gps FROM v_activo_ubicacion_reporte u WHERE u.activo_id = a.id),
      'lugar_fisico', NULLIF(btrim(a.ubicacion_actual), ''),
      'ubicacion_coincide', (SELECT u.coincide FROM v_activo_ubicacion_reporte u WHERE u.activo_id = a.id),
      'ubicacion_gps_fecha', (SELECT u.gps_fecha FROM v_activo_ubicacion_reporte u WHERE u.activo_id = a.id),
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
      WHERE (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
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
        AND e.estado_codigo <> 'B'   -- MIG585
        AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
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
      WHERE es_bodega   -- MIG393: la bodega de Coquimbo, por operación y no por nombre
    ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $function$;

SELECT count(*) FILTER (WHERE coincide IS FALSE) AS no_coinciden, count(*) FILTER (WHERE coincide) AS coinciden, count(*) FILTER (WHERE coincide IS NULL) AS sin_juicio FROM v_activo_ubicacion_reporte;
