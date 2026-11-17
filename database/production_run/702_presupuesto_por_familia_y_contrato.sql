-- 702 — Presupuesto por camión: familia, contrato de servicio y base del proyectado (Manuel 17-11-2026).
-- La pestaña «Por camión» se divide en los contratos de servicio de Pillado (se mantienen en
-- terreno: Romeral, Franke, Calama ENEX) y el resto de la flota por familia. Por equipo: gasto real
-- 2023, 2024, 2025, 2026 a la fecha y proyectado 2027, con qué toma cada parte del proyectado.

CREATE TABLE IF NOT EXISTS ppto_contrato_servicio (
    patente TEXT PRIMARY KEY,
    contrato TEXT NOT NULL,
    nota TEXT
);
ALTER TABLE ppto_contrato_servicio ENABLE ROW LEVEL SECURITY;

-- Según el PPTO Comercial REV1 (áreas Romeral, FRNKE y Contrato Calama/Franke/Romeral).
INSERT INTO ppto_contrato_servicio (patente, contrato, nota) VALUES
('DJKL-18', 'Romeral', 'Aljibe del contrato CMP Romeral'),
('FSLZ-67', 'Romeral', 'Aljibe del contrato CMP Romeral'),
('RZPC-83', 'Romeral', 'Camioneta del contrato Romeral'),
('HHWB-42', 'Franke', 'Aljibe del contrato Franke'),
('HHWB-44', 'Franke', 'Aljibe del contrato Franke'),
('LLBP-96', 'Franke', 'Camioneta del contrato Franke'),
('VRST-19', 'Calama ENEX', 'Camioneta del contrato Calama'),
('SPRY-28', 'Calama ENEX', 'Camioneta del contrato Calama')
ON CONFLICT (patente) DO NOTHING;

CREATE OR REPLACE FUNCTION rpc_ppto_camiones_detalle() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
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
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2026) AS r26
          FROM v_ppto_real WHERE linea LIKE 'A%' AND activo_id IS NOT NULL GROUP BY 1
    ), pp AS (
        SELECT patente,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A1') AS prev,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A2') AS corr,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A3') AS neu,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A4') AS may,
               sum(monto) FILTER (WHERE anio = 2028) AS t28, sum(monto) FILTER (WHERE anio = 2029) AS t29
          FROM ppto_resultado WHERE version_id = 1 AND patente IS NOT NULL GROUP BY 1
    ), vi AS (
        SELECT patente, jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'n', n, 'costo', costo, 'kit', kit) ORDER BY tipo, nivel) AS visitas
          FROM (SELECT patente, tipo, nivel, count(*) AS n, round(sum(costo)) AS costo, round(sum(costo_kit)) AS kit
                  FROM ppto_visita WHERE anio = 2027 GROUP BY 1, 2, 3) x GROUP BY 1
    ), ma AS (
        SELECT patente, jsonb_agg(jsonb_build_object('descripcion', coalesce(descripcion, 'Componente por horómetro'), 'monto', round(monto))) AS mayores
          FROM ppto_resultado WHERE version_id = 1 AND anio = 2027 AND linea = 'A4' AND patente IS NOT NULL GROUP BY 1
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
        'preventivo', round(coalesce(pp.prev, 0)), 'correctivo', round(coalesce(pp.corr, 0)),
        'neumaticos', round(coalesce(pp.neu, 0)), 'mayores', round(coalesce(pp.may, 0)),
        'total_2028', round(coalesce(pp.t28, 0)), 'total_2029', round(coalesce(pp.t29, 0)),
        'base', jsonb_build_object(
            'con_pauta', c.grupo_kit IS NOT NULL, 'grupo_kit', c.grupo_kit,
            'intervalo_horas', (SELECT intervalo_horas FROM ppto_modelo_grupo g WHERE g.modelo = c.modelo),
            'horometro', round(c.horometro), 'ritmo', round(c.ritmo, 2), 'ritmo_fuente', c.ritmo_fuente,
            'horas_2027', round(greatest(c.ritmo, 0) * 365.25),
            'visitas', coalesce(vi.visitas, '[]'::jsonb),
            'correctivo_base', round(coalesce(c.base_correctivo, 0)),
            'edad_equivalente', round(fa.e27, 1),
            'factor_edad', CASE WHEN c.grupo_kit IS NOT NULL THEN round(least(fa.c27 / nullif(fa.cw, 0), 1.5), 2) END,
            'piso_correctivo', CASE WHEN c.grupo_kit IS NOT NULL AND fa.e27 < 6 THEN round(s_mad * fa.c27 * 0.5) END,
            'neumatico_base', round(coalesce(c.base_neumatico, 0)),
            'neumatico_piso', CASE WHEN c.grupo_kit IS NOT NULL AND c.ritmo >= 1 AND fa.e27 >= 2 THEN s_neu END,
            'mayores', coalesce(ma.mayores, '[]'::jsonb))
    ) ORDER BY c.patente), '[]') INTO r
      FROM ppto_camion c
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN ppto_contrato_servicio cs ON cs.patente = c.patente
      LEFT JOIN re ON re.activo_id = c.activo_id
      LEFT JOIN pp ON pp.patente = c.patente
      LEFT JOIN vi ON vi.patente = c.patente
      LEFT JOIN ma ON ma.patente = c.patente
      LEFT JOIN fa ON fa.patente = c.patente;
    RETURN r;
END $$;

REVOKE ALL ON FUNCTION rpc_ppto_camiones_detalle() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_camiones_detalle() TO anon, authenticated;
