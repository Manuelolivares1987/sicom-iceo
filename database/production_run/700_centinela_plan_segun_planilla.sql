-- 700 — Centinela: fechas del plan alineadas con la planilla de Manuel (foto del 16-11-2026).
-- Ajuste de fecha sin registro de reprogramación (equivale a «Mover» en la Gantt).
--   Petrolera Óxido  02-12 → 24-11
--   EESS Óxido       18-11 → 08-12
--   EESS Sulfuro     17-11 → 09-12
-- El resto ya coincidía con la planilla.

DO $$
DECLARE n int;
BEGIN
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id IN (
        '98ebe81a-4acb-439f-a430-4d3817f1638e','8fa278a8-9a35-4159-a113-689ee5799fbd',
        '78c3ae87-5de8-45db-8ccb-eee5c192556f','8585167b-fb16-4bd9-98c0-90bcf1b15aab',
        'b31e6716-7b3a-4522-bca6-39afef9875a1','30668f48-3ec6-4ccf-bae4-56e843830c9b')) THEN
        RAISE EXCEPTION 'Una de las programaciones ya tiene ejecución: no se mueve';
    END IF;

    UPDATE enex_programaciones SET fecha_programada = DATE '2026-11-24', observacion = 'Fecha según planilla de Manuel (antes 02-12)'
     WHERE id IN ('98ebe81a-4acb-439f-a430-4d3817f1638e','8fa278a8-9a35-4159-a113-689ee5799fbd') AND fecha_programada = DATE '2026-12-02';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'Petrolera Óxido: % filas', n; END IF;

    UPDATE enex_programaciones SET fecha_programada = DATE '2026-12-08', observacion = 'Fecha según planilla de Manuel (antes 18-11)'
     WHERE id IN ('78c3ae87-5de8-45db-8ccb-eee5c192556f','8585167b-fb16-4bd9-98c0-90bcf1b15aab') AND fecha_programada = DATE '2026-11-18';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'EESS Óxido: % filas', n; END IF;

    UPDATE enex_programaciones SET fecha_programada = DATE '2026-12-09', observacion = 'Fecha según planilla de Manuel (antes 17-11)'
     WHERE id IN ('b31e6716-7b3a-4522-bca6-39afef9875a1','30668f48-3ec6-4ccf-bae4-56e843830c9b') AND fecha_programada = DATE '2026-11-17';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'EESS Sulfuro: % filas', n; END IF;
END $$;

SELECT json_agg(json_build_object('f', p.fecha_programada, 'inst', i.nombre, 'ts', p.tipo_servicio, 'mes', p.periodo_mes) ORDER BY p.fecha_programada, i.nombre, p.tipo_servicio)
  FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id JOIN enex_faenas f ON f.id = i.faena_id
 WHERE f.codigo = 'CENTINELA' AND p.fecha_programada >= DATE '2026-11-16' AND NOT i.es_comodin;
