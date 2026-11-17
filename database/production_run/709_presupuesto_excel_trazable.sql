-- 709 — Excel del presupuesto trazable hasta la compra (Manuel 17-11-2026).
-- «Correctivo base 24m son puros valores pegados, no entiendo»: el Excel debe mostrar de dónde sale cada
-- número con fórmulas. Esta función entrega lo que el Excel necesita para rehacer el cálculo desde el
-- origen: cada compra de Softland/OS que usa el presupuesto, las horas GPS por mes, las preventivas
-- registradas una por una, los overhaul y componentes de 2027 y los parámetros de la ventana de medición.
-- Solo lectura; no cambia ningún cálculo.

CREATE OR REPLACE FUNCTION rpc_ppto_excel_trazable() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
    v_fin DATE := date_trunc('month', (now() AT TIME ZONE 'America/Santiago'))::DATE - 1;
    v_i12 DATE := (date_trunc('month', (now() AT TIME ZONE 'America/Santiago'))::DATE - INTERVAL '12 months')::DATE;
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'fin', v_fin,
        'ipc_historico', (SELECT valor FROM ppto_supuesto WHERE clave = 'ipc_historico'),
        -- Seguro: mediana de las cuotas (folios ≥ $2 MM) de los últimos 12 meses, igual que fn_ppto_recalcular.
        'seguro_cuota', (SELECT coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY s), 0)
                           FROM (SELECT folio, sum(total) AS s FROM v_ppto_real
                                  WHERE cod_prod = 'SERSEGSEG002' AND fecha >= v_i12 AND fecha <= v_fin
                                  GROUP BY folio HAVING sum(total) >= 2000000) q),
        -- Compras: [patente, fecha, línea, categoría correctivo, proveedor, folio, código, descripción, monto, es pluma Calama]
        'compras', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                        a.patente, v.fecha, v.linea,
                        CASE WHEN v.linea = 'A2' THEN fn_ppto_categoria_correctivo(v.des_prod, v.origen) END,
                        v.origen, v.folio, v.cod_prod, v.des_prod, v.total,
                        coalesce(a.tipo_equipamiento::TEXT = 'pluma_grua' AND a.operacion = 'Calama'
                                 AND v.origen ~* '(PM CHILE|BOLOGNESI|SANDOVAL Y ESPINO)', false))
                        ORDER BY v.linea, a.patente NULLS LAST, v.fecha), '[]'::JSONB)
                      FROM v_ppto_real v LEFT JOIN activos a ON a.id = v.activo_id),
        -- Horas GPS por mes completo de los últimos 18 meses: [patente, mes, horas]
        'gps', (SELECT coalesce(jsonb_agg(jsonb_build_array(c.patente, h.mes::DATE, h.horas) ORDER BY c.patente, h.mes), '[]'::JSONB)
                  FROM ppto_camion c JOIN v_activo_horas_mes h ON h.activo_id = c.activo_id
                 WHERE h.mes < date_trunc('month', v_hoy) AND h.mes >= date_trunc('month', v_hoy) - INTERVAL '18 months' AND h.horas > 0),
        -- Por equipo: ritmo de 18 meses, manual y de respaldo; desde cuándo se mide el cumplimiento de la pauta.
        'equipos', (SELECT coalesce(jsonb_object_agg(c.patente, jsonb_build_object(
                        'ritmo_18m', c.ritmo_18m,
                        'ritmo_manual', aj.ritmo_manual,
                        'ritmo_respaldo', CASE WHEN aj.ritmo_manual IS NULL AND c.ritmo_18m IS NULL AND c.ritmo_mejor_mes IS NULL THEN c.ritmo END,
                        'desde', greatest(DATE '2025-01-01', coalesce(a.fecha_alta::DATE, DATE '2025-01-01')))), '{}'::JSONB)
                      FROM ppto_camion c JOIN activos a ON a.id = c.activo_id
                      LEFT JOIN ppto_flota_ajuste aj ON aj.patente = c.patente),
        -- Preventivas registradas desde 2025: [patente, fecha, fuente, número]
        'preventivas', (SELECT coalesce(jsonb_agg(jsonb_build_array(x.patente, x.fecha, x.fuente, x.numero) ORDER BY x.patente, x.fecha), '[]'::JSONB) FROM (
            SELECT c.patente, min(os.fecha) AS fecha, 'Orden de servicio (historial)' AS fuente, os.num AS numero
              FROM ppto_camion c
              JOIN LATERAL (
                  SELECT o.os_numero::TEXT AS num, coalesce(coalesce(o.fecha_entrega, o.fecha_recepcion), make_date(o.anio, 7, 1)) AS fecha
                    FROM os_historico_importado o WHERE o.es_preventivo AND (o.activo_id = c.activo_id OR o.patente = c.patente)
                  UNION ALL
                  SELECT l.os_numero::TEXT, coalesce(coalesce(l.fecha_entrega, l.fecha_recepcion), make_date(l.anio, 7, 1))
                    FROM historial_os_legacy l WHERE l.flag_mant_prev AND l.activo_id = c.activo_id) os ON true
             WHERE os.fecha >= DATE '2025-01-01'
             GROUP BY c.patente, os.num
            UNION ALL
            SELECT c.patente, coalesce(ot.cerrada_at, ot.fecha_termino)::DATE, 'OT preventiva SICOM', coalesce(ot.folio::TEXT, ot.id::TEXT)
              FROM ppto_camion c JOIN ordenes_trabajo ot ON ot.activo_id = c.activo_id
             WHERE ot.tipo::TEXT = 'preventivo' AND ot.estado::TEXT IN ('cerrada', 'ejecutada_ok', 'ejecutada_con_observaciones')
               AND coalesce(ot.cerrada_at, ot.fecha_termino)::DATE >= DATE '2025-01-01'
            UNION ALL
            SELECT c.patente, min(v.fecha), 'Mantención comprada (Softland)', v.folio::TEXT
              FROM ppto_camion c JOIN v_ppto_real v ON v.activo_id = c.activo_id
             WHERE v.linea = 'A2' AND v.fecha >= DATE '2025-01-01'
               AND fn_ppto_categoria_correctivo(v.des_prod, v.origen) = 'Mantención preventiva (ya va en el preventivo)'
             GROUP BY c.patente, v.folio) x),
        -- Overhaul y componentes 2027: [patente, tipo, descripción, gatillo, grupo kit, nivel, horas, monto (solo overhaul)]
        'mayores', (SELECT coalesce(jsonb_agg(x.f ORDER BY x.p, x.o), '[]'::JSONB) FROM (
            SELECT pr.patente AS p, 1 AS o, jsonb_build_array(pr.patente, 'Overhaul programado', pr.descripcion, pr.gatillo, NULL, NULL, NULL, pr.monto) AS f
              FROM ppto_programa pr WHERE pr.tipo = 'overhaul' AND pr.anio = 2027
            UNION ALL
            SELECT vi.patente, 2, jsonb_build_array(vi.patente, 'Componente por pauta',
                       'Componente ' || vi.nivel || CASE WHEN vi.horas IS NULL THEN ' (por años de antigüedad)' ELSE ' a las ' || to_char(vi.horas, 'FM999G999') || ' h' END,
                       CASE WHEN vi.horas IS NULL THEN 'Le toca por años en 2027' ELSE 'Vence en 2027 (o ya venció y se compra en 2027)' END,
                       c.grupo_kit, vi.nivel, vi.horas, NULL)
              FROM ppto_visita vi JOIN ppto_camion c ON c.patente = vi.patente
             WHERE vi.tipo = 'componente' AND vi.anio = 2027) x),
        'opex', (SELECT coalesce(jsonb_agg(jsonb_build_array(descripcion, gatillo, monto) ORDER BY id), '[]'::JSONB)
                   FROM ppto_programa WHERE tipo = 'opex' AND anio = 2027)
    ) INTO r;
    RETURN r;
END $$;

REVOKE ALL ON FUNCTION rpc_ppto_excel_trazable() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_excel_trazable() TO authenticated;
