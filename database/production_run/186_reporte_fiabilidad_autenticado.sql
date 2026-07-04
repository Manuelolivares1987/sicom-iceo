-- ============================================================================
-- SICOM-ICEO | 186 — Reporte fiabilidad: exigir sesión + restaurar combustible
-- ----------------------------------------------------------------------------
-- Fase 0 auditoría, hallazgos C3 y C6 (validados en prod 2026-07-03):
--   C3: fn_reporte_fiabilidad_publico tenía GRANT a anon y devolvía, sin
--       autenticación: activo_id (UUID), patente, cliente, contratos con días
--       de arriendo, VIN de chasis y número de motor de toda la flota.
--   C6: MIG146 reescribió la función y PERDIÓ la sección 'combustible'
--       (agregada en MIG111, filtrada en MIG134). El frontend la sigue
--       consumiendo y caía en silencio a lista vacía desde ~2026-06-16.
--
-- Fix:
--   1. La función exige sesión (auth.uid()) + perfil con rol (fn_user_rol()).
--      Excepción: session_user = 'postgres' (scripts administrativos como
--      generar-reporte-fiabilidad-outlook.mjs y jobs pg_cron, que se conectan
--      directo sin JWT).
--   2. Se restaura la clave 'combustible' (v_combustible_proyeccion_stock,
--      excluyendo CAM-% igual que MIG134).
--   3. REVOKE a PUBLIC y anon; GRANT solo authenticated.
--   4. Se mantienen vin_chasis / numero_motor / cliente / contratos_dias:
--      la ficha técnica y el export Excel de la página los usan, y ahora solo
--      los ve personal autenticado (ver tabla campo-por-campo en
--      docs/auditoria/validacion-hallazgos-2026-07.md).
--
-- El sistema es de uso interno: NO se implementa token público. Si a futuro se
-- necesita acceso externo sin usuario, ver la alternativa diseñada en
-- docs/arquitectura/decisiones-pendientes-auditoria.md (token aleatorio con
-- hash + expiración + alcance mínimo), que NO es esta función.
--
-- Cuerpo de datos: idéntico a MIG169 (última versión) + sección combustible.
-- IDEMPOTENTE. No modifica datos. Rollback: re-aplicar MIG169 (deja de exigir
-- sesión y pierde combustible de nuevo).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_publico(
    p_ini DATE DEFAULT date_trunc('month', CURRENT_DATE)::date,
    p_fin DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_out JSONB;
BEGIN
    -- Guard MIG186: reporte interno. Sesión con perfil, o conexión admin
    -- directa (scripts de correo / cron ejecutan como postgres, sin JWT).
    IF session_user <> 'postgres'
       AND (auth.uid() IS NULL OR public.fn_user_rol() IS NULL) THEN
        RAISE EXCEPTION 'Acceso no autorizado.';
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
    -- Restaurado MIG186 (venía de MIG111 + filtro Franke de MIG134; MIG146 lo perdió)
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

COMMENT ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE) IS
    'Reporte de fiabilidad (página /reporte-fiabilidad y correo). Desde MIG186 '
    'exige sesión con perfil (o conexión admin directa); ya NO es anónimo. '
    'Incluye categorias/equipos/matriz/combustible.';

REVOKE ALL ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE) TO authenticated;

-- ── Verificación (contrato RPC↔frontend + grants) ───────────────────────────
DO $$
DECLARE v JSONB;
BEGIN
    -- Se aplica como postgres → el guard permite la llamada de smoke test.
    v := public.fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    IF NOT (v ? 'categorias' AND v ? 'equipos' AND v ? 'matriz' AND v ? 'combustible') THEN
        RAISE EXCEPTION 'FALLO contrato: faltan claves en la respuesta (%).', (SELECT string_agg(k,',') FROM jsonb_object_keys(v) k);
    END IF;
    RAISE NOTICE 'MIG186 OK: equipos=% combustible=% (claves completas)',
        jsonb_array_length(v->'equipos'), jsonb_array_length(v->'combustible');

    IF has_function_privilege('anon', 'public.fn_reporte_fiabilidad_publico(date, date)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon aún puede ejecutar fn_reporte_fiabilidad_publico';
    END IF;
    IF NOT has_function_privilege('authenticated', 'public.fn_reporte_fiabilidad_publico(date, date)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: authenticated perdió EXECUTE del reporte';
    END IF;
END $$;

SELECT has_function_privilege('anon', 'public.fn_reporte_fiabilidad_publico(date, date)', 'EXECUTE') AS anon_execute;
