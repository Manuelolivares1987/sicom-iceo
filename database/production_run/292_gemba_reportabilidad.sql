-- ============================================================================
-- SICOM-ICEO | 292 — Reportabilidad de Recorridos Gemba
-- ============================================================================
-- Hasta acá el módulo mostraba cuántos recorridos se hicieron, pero no si el
-- programa se está cumpliendo. Sin ese contraste el KPI engaña: 8 recorridos en
-- el mes suena bien hasta que uno recuerda que el del taller es DIARIO y que
-- deberían ser 22.
--
-- Esta migración agrega el avance real:
--   1. fn_gemba_esperados()  — cuántos recorridos debieron hacerse en un rango
--      según la cadencia del checklist (diaria cuenta días hábiles).
--   2. rpc_gemba_reporte()   — todo el reporte del período en una llamada:
--      · programa       → esperados vs realizados por checklist, con % de avance
--      · responsables   → quién recorre, cuándo fue la última vez
--      · items_criticos → los ítems que más fallan (90 días): la materia prima
--                         de la reunión de mejora, no un dato decorativo
--      · hallazgos      → plan de acción: abiertos, vencidos, cerrados en plazo
--                         y cuánto se demora en cerrar una acción
--
-- El avance del PROGRAMA (se recorre o no) y el % de cumplimiento del checklist
-- (qué tan bien salió) se muestran separados a propósito: el segundo sube
-- marcando "cumple", el primero no se puede falsear sin salir a terreno.
--
-- ADITIVA e IDEMPOTENTE. Solo lectura.
-- ============================================================================

-- ── 1. Cuántos recorridos se esperaban en un rango ──────────────────────────
CREATE OR REPLACE FUNCTION fn_gemba_esperados(
    p_cadencia TEXT, p_desde DATE, p_hasta DATE
) RETURNS INT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_cadencia IS NULL OR p_hasta < p_desde THEN 0
        -- Diaria = días hábiles. Contarla por días corridos exigiría recorrer
        -- sábado y domingo, y el programa quedaría siempre en rojo.
        WHEN p_cadencia = 'diaria' THEN (
            SELECT count(*)::int FROM generate_series(p_desde, p_hasta, '1 day') d
             WHERE EXTRACT(ISODOW FROM d) <= 5)
        WHEN p_cadencia = 'semanal'   THEN GREATEST(1, CEIL((p_hasta - p_desde + 1) / 7.0)::int)
        WHEN p_cadencia = 'quincenal' THEN GREATEST(1, CEIL((p_hasta - p_desde + 1) / 14.0)::int)
        WHEN p_cadencia = 'mensual'   THEN 1
        ELSE 0
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_gemba_esperados(TEXT, DATE, DATE) TO authenticated;


-- ── 2. El reporte del período, en una sola llamada ──────────────────────────
CREATE OR REPLACE FUNCTION rpc_gemba_reporte(p_anio INT, p_mes INT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_desde DATE; v_hasta DATE; v_out JSONB;
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sin sesión'; END IF;
    IF p_anio IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Período inválido'; END IF;

    v_desde := make_date(p_anio, p_mes, 1);
    -- Un mes en curso se mide hasta hoy, no hasta el día 31: si no, el avance
    -- del día 5 sale en 16% y parece un desastre.
    v_hasta := LEAST((v_desde + INTERVAL '1 month - 1 day')::date, CURRENT_DATE);

    SELECT jsonb_build_object(
      'periodo', jsonb_build_object('anio', p_anio, 'mes', p_mes,
                                    'desde', v_desde, 'hasta', v_hasta,
                                    'en_curso', v_hasta < (v_desde + INTERVAL '1 month - 1 day')::date),

      -- ── Programa: lo que debía recorrerse vs lo que se recorrió ──
      'programa', COALESCE((
        SELECT jsonb_agg(x ORDER BY x->>'cadencia', x->>'codigo') FROM (
          SELECT jsonb_build_object(
                   'plantilla_id', p.id,
                   'codigo', p.codigo,
                   'nombre', p.nombre,
                   'cargo', p.cargo,
                   'cadencia', p.cadencia,
                   'esperados', fn_gemba_esperados(p.cadencia, v_desde, v_hasta),
                   'realizados', (SELECT count(*) FROM gemba_recorridos r
                                   WHERE r.plantilla_id = p.id AND r.fecha BETWEEN v_desde AND v_hasta),
                   'cerrados', (SELECT count(*) FROM gemba_recorridos r
                                 WHERE r.plantilla_id = p.id AND r.estado = 'cerrado'
                                   AND r.fecha BETWEEN v_desde AND v_hasta),
                   'hallazgos', (SELECT count(*) FROM gemba_hallazgos h
                                   JOIN gemba_recorridos r ON r.id = h.recorrido_id
                                  WHERE r.plantilla_id = p.id AND r.fecha BETWEEN v_desde AND v_hasta),
                   -- Cumplimiento del checklist, ponderado por ítem.
                   'pct_checklist', (
                     SELECT CASE WHEN sum(res.cumple + res.no_cumple) = 0 THEN NULL
                                 ELSE ROUND(100.0 * sum(res.cumple) / sum(res.cumple + res.no_cumple), 1) END
                       FROM vw_gemba_recorrido_resumen res
                       JOIN gemba_recorridos r ON r.id = res.recorrido_id
                      WHERE r.plantilla_id = p.id AND r.fecha BETWEEN v_desde AND v_hasta)
                 ) AS x
            FROM gemba_plantillas p WHERE p.activo
        ) t), '[]'::jsonb),

      -- ── Quién recorre ──
      'responsables', COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'recorridos')::int DESC) FROM (
          SELECT jsonb_build_object(
                   'responsable_id', r.responsable_id,
                   'nombre', COALESCE(up.nombre_completo, 'Sin identificar'),
                   'rol', up.rol,
                   'recorridos', count(*),
                   'cerrados', count(*) FILTER (WHERE r.estado = 'cerrado'),
                   'ultimo', max(r.fecha),
                   'dias_sin_recorrer', (CURRENT_DATE - max(r.fecha)),
                   'hallazgos', (SELECT count(*) FROM gemba_hallazgos h
                                  WHERE h.recorrido_id IN (
                                        SELECT r2.id FROM gemba_recorridos r2
                                         WHERE r2.responsable_id = r.responsable_id
                                           AND r2.fecha BETWEEN v_desde AND v_hasta))
                 ) AS x
            FROM gemba_recorridos r
            LEFT JOIN usuarios_perfil up ON up.id = r.responsable_id
           WHERE r.fecha BETWEEN v_desde AND v_hasta
           GROUP BY r.responsable_id, up.nombre_completo, up.rol
        ) t), '[]'::jsonb),

      -- ── Lo que más falla (90 días) ──
      -- Es el dato que convierte los recorridos en mejora: un ítem que falla
      -- ocho veces no es un descuido, es un proceso que no está.
      'items_criticos', COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'veces')::int DESC) FROM (
          SELECT jsonb_build_object(
                   'item', q.item, 'seccion', q.seccion,
                   'veces', q.veces, 'evaluado', q.evaluado,
                   'pct_falla', ROUND(100.0 * q.veces / NULLIF(q.evaluado, 0), 0)
                 ) AS x
            FROM (
              SELECT x.item, min(x.seccion) AS seccion,
                     count(*) FILTER (WHERE x.evaluacion = 'no_cumple') AS veces,
                     count(*) FILTER (WHERE x.evaluacion IN ('cumple','no_cumple')) AS evaluado
                FROM gemba_respuestas x
                JOIN gemba_recorridos r ON r.id = x.recorrido_id
               WHERE r.fecha >= CURRENT_DATE - 90
               GROUP BY x.item
              HAVING count(*) FILTER (WHERE x.evaluacion = 'no_cumple') > 0
               ORDER BY 3 DESC LIMIT 10
            ) q
        ) t), '[]'::jsonb),

      -- ── Plan de acción ──
      'hallazgos', (
        SELECT jsonb_build_object(
          'abiertos',   count(*) FILTER (WHERE estado = 'abierta'),
          'en_proceso', count(*) FILTER (WHERE estado = 'en_proceso'),
          'cerrados',   count(*) FILTER (WHERE estado = 'cerrada'),
          'vencidos',   count(*) FILTER (WHERE estado <> 'cerrada' AND fecha_compromiso IS NOT NULL
                                           AND fecha_compromiso < CURRENT_DATE),
          'sin_plazo',  count(*) FILTER (WHERE estado <> 'cerrada' AND fecha_compromiso IS NULL),
          -- De los cerrados, cuántos llegaron dentro del plazo comprometido.
          'cerrados_en_plazo', count(*) FILTER (WHERE estado = 'cerrada' AND fecha_compromiso IS NOT NULL
                                                  AND fecha_cierre <= fecha_compromiso),
          'cerrados_con_plazo', count(*) FILTER (WHERE estado = 'cerrada' AND fecha_compromiso IS NOT NULL),
          'dias_promedio_cierre', ROUND(AVG(fecha_cierre - created_at::date)
                                        FILTER (WHERE estado = 'cerrada' AND fecha_cierre IS NOT NULL), 1)
        ) FROM gemba_hallazgos)
    ) INTO v_out;

    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION rpc_gemba_reporte(INT, INT) TO authenticated;

COMMENT ON FUNCTION rpc_gemba_reporte(INT, INT) IS
    'Reporte de avance de Recorridos Gemba de un mes: programa (esperados vs realizados), responsables, ítems que más fallan y estado del plan de acción. MIG292.';

NOTIFY pgrst, 'reload schema';


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v INT;
BEGIN
    -- Agosto 2026 arranca en sábado: del 1 al 14 hay 10 días hábiles.
    SELECT fn_gemba_esperados('diaria', DATE '2026-08-01', DATE '2026-08-14') INTO v;
    IF v <> 10 THEN RAISE EXCEPTION 'FALLO — días hábiles mal contados: % (esperado 10)', v; END IF;

    SELECT fn_gemba_esperados('quincenal', DATE '2026-08-01', DATE '2026-08-31') INTO v;
    IF v <> 3 THEN RAISE EXCEPTION 'FALLO — quincenal mal contada: %', v; END IF;

    SELECT fn_gemba_esperados('mensual', DATE '2026-08-01', DATE '2026-08-31') INTO v;
    IF v <> 1 THEN RAISE EXCEPTION 'FALLO — mensual mal contada: %', v; END IF;

    RAISE NOTICE 'MIG292 OK — reporte de avance disponible (rpc_gemba_reporte)';
END $$;
