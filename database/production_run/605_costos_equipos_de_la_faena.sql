-- ============================================================================
-- SICOM-ICEO | 605 — Qué equipos cuenta cada faena y por qué
-- ============================================================================
-- Manuel: «¿por qué en Franke aparecen 7 equipos? Eso es importante; hacer
-- clic y ver de qué se trata». Los 7 son todos los equipos que estuvieron en
-- Franke al menos un día del período: 4 permanentes (LLBP-96, HHWB-42,
-- HHWB-44, LCSX-78) y 3 de paso (RSCY-85 16 días desde el 29-09; KVDK-21 6
-- días sueltos; SLRK-82 1 día).
--
-- Esta RPC devuelve, por equipo: días en la faena, desde/hasta, de dónde sale
-- el dato (GPS / estado diario / arrastre), la faena de su ficha y cuánto
-- gastó en la faena. Así el número se puede auditar.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_costos_faena_equipos(
    p_desde DATE, p_hasta DATE, p_faena TEXT, p_subfaena TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    WITH d AS (
        SELECT m.activo_id, count(*) AS dias, min(m.fecha) AS desde, max(m.fecha) AS hasta,
               count(*) FILTER (WHERE m.fuente = 'gps') AS dias_gps,
               count(*) FILTER (WHERE m.fuente = 'estado_diario') AS dias_estado,
               count(*) FILTER (WHERE m.fuente IN ('arrastre', 'primer_dato')) AS dias_arrastre,
               string_agg(DISTINCT m.subfaena, ', ') AS subfaenas
          FROM mv_activo_faena_dia m
         WHERE m.grupo = p_faena
           AND (p_subfaena IS NULL OR m.subfaena = p_subfaena)
           AND m.fecha BETWEEN v_desde AND v_fin
         GROUP BY m.activo_id
    ), c AS (
        SELECT l.activo_id, sum(l.total) AS costo
          FROM fn_costos_lineas(v_desde, v_fin, FALSE) l
         WHERE l.faena = p_faena AND (p_subfaena IS NULL OR l.subfaena = p_subfaena)
           AND l.activo_id IS NOT NULL
         GROUP BY l.activo_id
    )
    SELECT jsonb_build_object(
        'dias_periodo', (v_fin - v_desde + 1),
        'equipos', coalesce(jsonb_agg(jsonb_build_object(
            'activo_id', coalesce(d.activo_id, c.activo_id),
            'patente', a.patente, 'tipo', coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT),
            'faena_ficha', fa.nombre,
            'dias', coalesce(d.dias, 0), 'desde', d.desde, 'hasta', d.hasta,
            'dias_gps', coalesce(d.dias_gps, 0), 'dias_estado', coalesce(d.dias_estado, 0),
            'dias_arrastre', coalesce(d.dias_arrastre, 0),
            'subfaenas', d.subfaenas,
            'costo', coalesce(c.costo, 0))
          ORDER BY coalesce(d.dias, 0) DESC, coalesce(c.costo, 0) DESC), '[]'))
      INTO r
      FROM d
      FULL JOIN c ON c.activo_id = d.activo_id
      JOIN activos a ON a.id = coalesce(d.activo_id, c.activo_id)
      LEFT JOIN faenas fa ON fa.id = a.faena_id;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_costos_faena_equipos(DATE, DATE, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_costos_faena_equipos(DATE, DATE, TEXT, TEXT) TO authenticated;
