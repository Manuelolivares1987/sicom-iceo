-- 707 — Revisión de kits y preventivas hechas, para el Excel del presupuesto (Manuel 17-11-2026).
-- Manuel: «claramente no se hacían las preventivas en el taller, por eso tanto correctivo». El Excel suma
-- el detalle de cada kit (cantidad, precio de referencia, precio real Softland, precio usado) y, por equipo,
-- las preventivas registradas (OS históricas 2025-2026 sin repetir + OT SICOM) y el gasto real en preventivo.

CREATE OR REPLACE FUNCTION public.rpc_ppto_camiones_detalle()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    s_hedad NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'horas_por_anio_edad'), 2500);
    s_mad NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'correctivo_maduro'), 0);
    s_neu NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'neumatico_maduro'), 0);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    WITH re AS (
        SELECT activo_id,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2023) AS r23,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2024) AS r24,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2025) AS r25,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2026) AS r26,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2023 AND linea = 'A3') AS n23,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2024 AND linea = 'A3') AS n24,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2025 AND linea = 'A3') AS n25,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2026 AND linea = 'A3') AS n26,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2023 AND linea = 'A1') AS p23,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2024 AND linea = 'A1') AS p24,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2025 AND linea = 'A1') AS p25,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2026 AND linea = 'A1') AS p26
          FROM v_ppto_real WHERE linea LIKE 'A%' AND activo_id IS NOT NULL GROUP BY 1
    ), pp AS (
        SELECT patente,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A1') AS prev,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A2') AS corr,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A3') AS neu,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A4') AS may,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'B4') AS cert,
               sum(monto) FILTER (WHERE anio = 2028 AND linea LIKE 'A%') AS t28, sum(monto) FILTER (WHERE anio = 2029 AND linea LIKE 'A%') AS t29
          FROM ppto_resultado WHERE version_id = 1 AND patente IS NOT NULL GROUP BY 1
    ), vi AS (
        SELECT patente, jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'n', n, 'costo', costo, 'kit', kit) ORDER BY tipo, nivel) AS visitas
          FROM (SELECT patente, tipo, nivel, count(*) AS n, round(sum(costo)) AS costo, round(sum(costo_kit)) AS kit
                  FROM ppto_visita WHERE anio = 2027 GROUP BY 1, 2, 3) x GROUP BY 1
    ), ma AS (
        SELECT patente, jsonb_agg(jsonb_build_object('descripcion', coalesce(descripcion, 'Componente por horómetro'), 'monto', round(monto))) AS mayores
          FROM ppto_resultado WHERE version_id = 1 AND anio = 2027 AND linea = 'A4' AND patente IS NOT NULL GROUP BY 1
    ), ce AS (
        SELECT patente, jsonb_agg(jsonb_build_object('anio', anio, 'descripcion', descripcion, 'monto', round(monto)) ORDER BY anio) AS certs
          FROM ppto_resultado WHERE version_id = 1 AND linea = 'B4' AND patente IS NOT NULL GROUP BY 1
    ), pa AS (
        SELECT patente, jsonb_agg(jsonb_build_object('descripcion', descripcion, 'monto', round(monto))) AS partidas
          FROM ppto_resultado WHERE version_id = 1 AND anio = 2027 AND linea = 'A2' AND descripcion IS NOT NULL AND patente IS NOT NULL GROUP BY 1
    ), ed AS (
        -- Edad equivalente y factor de la curva, igual que fn_ppto_recalcular para 2027.
        SELECT c.patente,
               greatest(coalesce(2027 - c.anio_fab, 99), (c.horometro + greatest(c.ritmo, 0) * 365.25 * 0.5) / s_hedad) AS e27,
               greatest(coalesce(2025.5 - c.anio_fab, 99), (c.horometro - greatest(c.ritmo, 0) * 365.25) / s_hedad, 0) AS ew
          FROM ppto_camion c
    ), fa AS (
        SELECT ed.patente, ed.e27,
               coalesce((SELECT factor FROM ppto_curva_edad WHERE edad = least(floor(greatest(ed.e27, 0))::INT, 6)), 1) AS c27,
               coalesce((SELECT factor FROM ppto_curva_edad WHERE edad = least(floor(ed.ew)::INT, 6)), 1) AS cw
          FROM ed
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'patente', c.patente, 'codigo', a.codigo, 'nombre', a.nombre, 'modelo', c.modelo, 'anio_fab', c.anio_fab,
        'familia', CASE coalesce(a.tipo_equipamiento::TEXT, '')
            WHEN 'aljibe_combustible' THEN 'Aljibe combustible' WHEN 'aljibe_agua' THEN 'Aljibe agua / riego'
            WHEN 'camioneta' THEN 'Camioneta' WHEN 'pluma_grua' THEN 'Camión pluma' WHEN 'grua_horquilla' THEN 'Grúa horquilla'
            WHEN 'ampliroll' THEN 'Polibrazo' WHEN 'generico' THEN 'Carrocería plana' ELSE 'Otros' END,
        'contrato', cs.contrato, 'faena', c.faena, 'estado_comercial', c.estado_comercial,
        'real', jsonb_build_object('2023', coalesce(re.r23, 0), '2024', coalesce(re.r24, 0), '2025', coalesce(re.r25, 0), '2026', coalesce(re.r26, 0)),
        'real_neumaticos', jsonb_build_object('2023', coalesce(re.n23, 0), '2024', coalesce(re.n24, 0), '2025', coalesce(re.n25, 0), '2026', coalesce(re.n26, 0)),
        'real_preventivo', jsonb_build_object('2023', coalesce(re.p23, 0), '2024', coalesce(re.p24, 0), '2025', coalesce(re.p25, 0), '2026', coalesce(re.p26, 0)),
        'preventivas_hechas', (SELECT jsonb_build_object('2025', count(*) FILTER (WHERE y = 2025), '2026', count(*) FILTER (WHERE y = 2026)) FROM (
              SELECT DISTINCT os_numero::TEXT, y FROM (
                SELECT o.os_numero::TEXT, coalesce(extract(year FROM coalesce(o.fecha_entrega, o.fecha_recepcion))::INT, o.anio) AS y
                  FROM os_historico_importado o WHERE o.es_preventivo AND (o.activo_id = a.id OR o.patente = c.patente)
                UNION
                SELECT l.os_numero::TEXT, coalesce(extract(year FROM coalesce(l.fecha_entrega, l.fecha_recepcion))::INT, l.anio)
                  FROM historial_os_legacy l WHERE l.flag_mant_prev AND l.activo_id = a.id) os
              UNION ALL
              SELECT ot.folio::TEXT, extract(year FROM coalesce(ot.cerrada_at, ot.fecha_termino))::INT
                FROM ordenes_trabajo ot WHERE ot.activo_id = a.id AND ot.tipo::TEXT = 'preventivo'
                 AND ot.estado::TEXT IN ('cerrada', 'ejecutada_ok', 'ejecutada_con_observaciones')) h),
        'tipo_equipamiento', a.tipo_equipamiento, 'operacion', a.operacion,
        'tc8_vence', (SELECT tc.fecha_vencimiento FROM certificaciones tc WHERE tc.activo_id = a.id AND tc.tipo::TEXT = 'tc8_sec' AND tc.anulado_at IS NULL ORDER BY tc.fecha_vencimiento DESC NULLS LAST LIMIT 1),
        'preventivo', round(coalesce(pp.prev, 0)), 'correctivo', round(coalesce(pp.corr, 0)),
        'neumaticos', round(coalesce(pp.neu, 0)), 'mayores', round(coalesce(pp.may, 0)),
        'certificaciones', round(coalesce(pp.cert, 0)),
        'total_2028', round(coalesce(pp.t28, 0)), 'total_2029', round(coalesce(pp.t29, 0)),
        'base', jsonb_build_object(
            'con_pauta', c.grupo_kit IS NOT NULL, 'grupo_kit', c.grupo_kit,
            'intervalo_horas', (SELECT intervalo_horas FROM ppto_modelo_grupo g WHERE g.modelo = c.modelo),
            'horometro', round(c.horometro), 'ritmo', round(c.ritmo, 2), 'ritmo_fuente', c.ritmo_fuente,
            'ritmo_18m', round(c.ritmo_18m, 2), 'ritmo_mejor_mes', round(c.ritmo_mejor_mes, 2), 'mejor_mes', c.mejor_mes,
            'horas_2027', round(greatest(c.ritmo, 0) * 365.25),
            'visitas', coalesce(vi.visitas, '[]'::jsonb),
            'correctivo_base', round(coalesce(c.base_correctivo, 0)),
            'edad_equivalente', round(fa.e27, 1),
            'factor_edad', CASE WHEN c.grupo_kit IS NOT NULL THEN round(least(fa.c27 / nullif(fa.cw, 0), 1.5), 2) END,
            'piso_correctivo', CASE WHEN c.grupo_kit IS NOT NULL AND fa.e27 < 6 THEN round(s_mad * fa.c27 * 0.5) END,
            'neumatico_base', round(coalesce(c.base_neumatico, 0)),
            'neumatico_piso', CASE WHEN c.grupo_kit IS NOT NULL AND c.ritmo >= 1 AND fa.e27 >= 2 THEN s_neu END,
            'mayores', coalesce(ma.mayores, '[]'::jsonb),
            'certificaciones', coalesce(ce.certs, '[]'::jsonb),
            'partidas_correctivo', coalesce(pa.partidas, '[]'::jsonb))
    ) ORDER BY c.patente), '[]') INTO r
      FROM ppto_camion c
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN ppto_contrato_servicio cs ON cs.patente = c.patente
      LEFT JOIN re ON re.activo_id = c.activo_id
      LEFT JOIN pp ON pp.patente = c.patente
      LEFT JOIN vi ON vi.patente = c.patente
      LEFT JOIN ma ON ma.patente = c.patente
      LEFT JOIN ce ON ce.patente = c.patente
      LEFT JOIN pa ON pa.patente = c.patente
      LEFT JOIN fa ON fa.patente = c.patente;
    RETURN r;
END $function$
;
REVOKE ALL ON FUNCTION rpc_ppto_camiones_detalle() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_camiones_detalle() TO anon, authenticated;

CREATE OR REPLACE FUNCTION rpc_ppto_kit_items() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    RETURN (
    WITH ventana AS (
        -- Mismo criterio que fn_ppto_recalcular: precio de los últimos 6 meses, si no de 18.
        SELECT l.cod_prod,
               sum(l.total) FILTER (WHERE o.fecha_oc >= v_hoy - 183) AS t6, sum(l.cantidad) FILTER (WHERE o.fecha_oc >= v_hoy - 183) AS q6,
               sum(l.total) AS t18, sum(l.cantidad) AS q18, max(o.fecha_oc) AS ult,
               (array_agg(l.det_prod ORDER BY o.fecha_oc DESC))[1] AS det
          FROM softland_oc o JOIN softland_oc_linea l USING (num_inter_oc)
         WHERE o.estado = 'AP' AND o.fecha_oc >= v_hoy - 548 AND l.cantidad > 0
           AND l.cod_prod IN (SELECT DISTINCT cod_softland FROM ppto_kit_item)
         GROUP BY 1
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'grupo_kit', k.grupo_kit, 'nivel', k.nivel, 'item', k.item, 'cantidad', k.cantidad, 'unidad', k.unidad,
        'cod_softland', k.cod_softland, 'precio_ref', round(k.precio_ref),
        'precio_softland', round(coalesce(v.t6 / nullif(v.q6, 0), v.t18 / nullif(v.q18, 0))),
        'descripcion_softland', v.det, 'ultima_compra', v.ult,
        'usa_precio_real', k.precio_vivo AND coalesce(v.t6 / nullif(v.q6, 0), v.t18 / nullif(v.q18, 0)) BETWEEN k.precio_ref * 0.5 AND k.precio_ref * 2,
        'fil_lub', k.fil_lub, 'provisorio', k.provisorio
    ) ORDER BY k.grupo_kit, k.nivel, k.fil_lub DESC, k.item), '[]')
      FROM ppto_kit_item k LEFT JOIN ventana v ON v.cod_prod = k.cod_softland);
END $$;
REVOKE ALL ON FUNCTION rpc_ppto_kit_items() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_kit_items() TO anon, authenticated;
