-- ============================================================================
-- SICOM-ICEO | 275b — Carga del plan real de la semana 10-16/08 (Lomas Bayas)
-- ============================================================================
-- Es el "PLAN 07.08.xlsx" que trabajan los chicos esta semana. Se carga ya
-- publicado porque el trabajo está en ejecución: el lunes 10 y el martes 11 ya
-- pasaron y el miércoles 13 es el que viene.
--
--   LUN 10/08  Lomas 2  1.1–1.4   aseo de estantes de bombas, pretil y sala de
--                                 microfiltrado + tablero
--   MAR 11/08  Lomas 1  1.1–1.4   ídem
--   MIÉ 13/08  Lomas 1  5.1–5.8   racks 1 y 2 (sin 5.5, que es a requerimiento)
--
-- El aseo es del área completa (queda sin punto: el técnico elige dónde marca);
-- lo del miércoles se reparte en los dos racks, que es como lo dice el Excel.
-- IDEMPOTENTE: reejecutar reemplaza las tareas pendientes de esa semana.
-- ============================================================================

DO $$
DECLARE
    v_faena  UUID;
    v_plan   UUID;
    v_pauta  UUID;
    v_r1     UUID;
    v_r2     UUID;
    v_item   UUID;
    v_orden  INT := 0;
    v_prog   UUID;
    r        TEXT[];
    v_creadas INT := 0;
    -- fecha , area , codigo , alcance , comentario , punto ('', 'R1', 'R2')
    plan CONSTANT TEXT[][] := ARRAY[
        ARRAY['2026-08-10','Truck Shop Lomas 2','1.1','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-10','Truck Shop Lomas 2','1.2','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-10','Truck Shop Lomas 2','1.3','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-10','Truck Shop Lomas 2','1.4','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-11','Truck Shop Lomas 1','1.1','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-11','Truck Shop Lomas 1','1.2','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-11','Truck Shop Lomas 1','1.3','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-11','Truck Shop Lomas 1','1.4','','ASEO DE ESTANTES DE BOMBAS, PRETIL Y SALA DE MICROFILTRADO + TABLERO',''],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.1','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.1','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.2','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.2','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.3','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.3','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.4','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.4','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.6','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.6','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.7','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.7','Rack 1 / Rack 2','','R2'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.8','Rack 1 / Rack 2','','R1'],
        ARRAY['2026-08-13','Truck Shop Lomas 1','5.8','Rack 1 / Rack 2','','R2']
    ];
BEGIN
    SELECT id INTO v_faena FROM enex_faenas WHERE codigo = 'LB_LUB';
    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB' AND activo ORDER BY version DESC LIMIT 1;
    SELECT id INTO v_r1 FROM enex_instalaciones WHERE codigo = 'LB-TS1-R1';
    SELECT id INTO v_r2 FROM enex_instalaciones WHERE codigo = 'LB-TS1-R2';
    IF v_faena IS NULL OR v_pauta IS NULL THEN RAISE EXCEPTION 'MIG275b: falta faena LB_LUB o PAUTA-LUB'; END IF;

    INSERT INTO enex_planes (faena_id, semana_inicio, semana_fin, nombre, estado, observacion)
    VALUES (v_faena, DATE '2026-08-10', DATE '2026-08-16', 'Plan semana 10 al 16 de agosto', 'publicado',
            'Cargado del Excel de faena PLAN 07.08')
    ON CONFLICT (faena_id, semana_inicio) DO UPDATE
        SET nombre = EXCLUDED.nombre, estado = 'publicado'
    RETURNING id INTO v_plan;

    DELETE FROM enex_plan_tareas
     WHERE plan_id = v_plan AND estado = 'pendiente' AND ejecucion_id IS NULL;

    FOREACH r SLICE 1 IN ARRAY plan LOOP
        v_orden := v_orden + 1;
        -- Código repetido en la pauta (5.2, 5.6…): el plan semanal es del
        -- servicio trimestral, así que gana la actividad trimestral.
        SELECT id INTO v_item FROM enex_pauta_items
         WHERE pauta_id = v_pauta AND activo AND codigo = r[3]
         ORDER BY (periodicidad = 'trimestral') DESC, orden LIMIT 1;

        INSERT INTO enex_plan_tareas (plan_id, fecha, area, instalacion_id, pauta_item_id,
                                      codigo_item, alcance, comentario, orden)
        VALUES (v_plan, r[1]::date, r[2],
                CASE r[6] WHEN 'R1' THEN v_r1 WHEN 'R2' THEN v_r2 ELSE NULL END,
                v_item, r[3], NULLIF(r[4],''), NULLIF(r[5],''), v_orden);
    END LOOP;

    -- Publicar deja el trabajo ejecutable: servicio de mantención del mes para
    -- cada punto que el plan nombra (los racks del miércoles no tenían).
    FOR v_item IN
        SELECT DISTINCT instalacion_id FROM enex_plan_tareas
         WHERE plan_id = v_plan AND instalacion_id IS NOT NULL
    LOOP
        SELECT id INTO v_prog FROM enex_programaciones
         WHERE instalacion_id = v_item AND tipo_servicio = 'mantencion'
           AND periodo_anio = 2026 AND periodo_mes = 8 LIMIT 1;
        IF v_prog IS NULL THEN
            INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes,
                                             fecha_programada, observacion)
            VALUES (v_item, 'mantencion', 2026, 8, DATE '2026-08-13',
                    'Creada al publicar el plan semanal 10-16/08');
            v_creadas := v_creadas + 1;
        END IF;
    END LOOP;

    RAISE NOTICE 'MIG275b · plan % · tareas % · servicios creados %', v_plan, v_orden, v_creadas;
END $$;

SELECT fecha, area, coalesce(instalacion,'(toda el área)') AS punto, codigo_item, actividad, alcance
  FROM v_enex_plan_tareas
 WHERE semana_inicio = DATE '2026-08-10'
 ORDER BY fecha, orden;
