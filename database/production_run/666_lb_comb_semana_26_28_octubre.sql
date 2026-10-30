-- 666 — Lomas Bayas Combustibles, semana 26 al 28-10-2026: lo realizado, desde
-- los papeles firmados (carpeta «Semana actual Calama» de Manuel, 30-10-2026).
--
-- Cada servicio queda con su ejecución, las lecturas del certificado en la
-- pauta y, como informe PDF, el papel escaneado con la firma de ESM (subido a
-- documentos/enex-informes/lb-comb-2026-10/). La firma del mandante está en el
-- papel: firma_mandante_url apunta a ese mismo PDF (igual que MIG655).
--
--   26-10 SCCC60   calibración 1.000 L ×3, +0,1 %        — ESM: firma en el certificado
--   26-10 SKOL82   calibración 1.000 L ×3, +0,3/0,2/0,2 % — ESM: firma en el certificado
--   27-10 KVXH64   calibración 1.000 L ×3, +0,2/0,1/0,1 % — ESM: Fernando Vega (Jefe de Turno)
--   28-10 SM Fortuna  calibración 1.000 L ×3, +0,2 %
--   28-10 SM Fortuna  mantención intermedia, OT Kizeo 13:00–14:00, todo «Bueno»
--
-- Cambio de tarea (MIG658): el 26-10 tocaba la EESS Valle Amanda y el 27-10 el
-- brazo de carga; las dos veces ESM pidió calibrar camiones. Las 4 tareas
-- desplazadas quedan «pendiente_adc» (siguen atrasadas hasta que llegue el
-- correo del ADC o se reprogramen desde la Gantt). Las calibraciones de los
-- camiones quedan como sus reemplazos. Los 3 camiones no estaban en el maestro
-- de LB_COMB: se crean como en terreno (creada_en_terreno).
-- Supervisor: Roberto Cáceres. Verificaron: Fabián Castillo (mecánico), Jaison
-- Paredes (eléctrico, SKOL82) y Bastián (KVXH64, apellido ilegible).

CREATE OR REPLACE FUNCTION pg_temp.it(p_ejec uuid, p_pauta uuid, p_cod text, p_res text, p_val numeric, p_obs text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, valor_medicion, dentro_tolerancia, observacion)
    SELECT p_ejec, i.id, p_res, p_val, CASE WHEN p_val IS NOT NULL THEN true END, p_obs
      FROM enex_pauta_items i WHERE i.pauta_id = p_pauta AND i.codigo = p_cod AND i.activo
    ON CONFLICT (ejecucion_id, pauta_item_id) DO UPDATE
       SET resultado = EXCLUDED.resultado, valor_medicion = EXCLUDED.valor_medicion,
           dentro_tolerancia = EXCLUDED.dentro_tolerancia, observacion = EXCLUDED.observacion;
$$;

-- Ejecución cumplida con el papel firmado como informe y firma del mandante.
CREATE OR REPLACE FUNCTION pg_temp.ejec(p_prog uuid, p_fecha date, p_pdf text, p_firmante text, p_ejecutor text, p_tecnico text,
                                        p_obs text, p_ot text DEFAULT NULL, p_ini timestamptz DEFAULT NULL, p_fin timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; v_url text := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/documentos/enex-informes/lb-comb-2026-10/' || p_pdf;
BEGIN
    INSERT INTO enex_ejecuciones (programacion_id, estado, fecha_ejecucion, ot_numero, ejecutor, observacion, evidencia_urls,
                                  firma_mandante_url, firmante_mandante_nombre, firmante_mandante_at, pauta_id,
                                  tecnico_nombre, informe_pdf_url, inicio_at, fin_at, duracion_segundos, notificado_at)
    VALUES (p_prog, 'cumplida', p_fecha, p_ot, p_ejecutor, p_obs, ARRAY[v_url],
            v_url, p_firmante, (p_fecha + time '18:00') AT TIME ZONE 'America/Santiago', fn_enex_pauta_de_programacion(p_prog),
            p_tecnico, v_url, p_ini, p_fin,
            CASE WHEN p_ini IS NOT NULL AND p_fin IS NOT NULL THEN extract(epoch FROM p_fin - p_ini)::int END, NOW())
    ON CONFLICT (programacion_id) DO UPDATE SET
        estado = EXCLUDED.estado, fecha_ejecucion = EXCLUDED.fecha_ejecucion, ot_numero = EXCLUDED.ot_numero,
        ejecutor = EXCLUDED.ejecutor, observacion = EXCLUDED.observacion, evidencia_urls = EXCLUDED.evidencia_urls,
        firma_mandante_url = EXCLUDED.firma_mandante_url, firmante_mandante_nombre = EXCLUDED.firmante_mandante_nombre,
        firmante_mandante_at = EXCLUDED.firmante_mandante_at, pauta_id = EXCLUDED.pauta_id,
        tecnico_nombre = EXCLUDED.tecnico_nombre, informe_pdf_url = EXCLUDED.informe_pdf_url,
        inicio_at = EXCLUDED.inicio_at, fin_at = EXCLUDED.fin_at, duracion_segundos = EXCLUDED.duracion_segundos,
        updated_at = NOW()
    RETURNING id INTO v;
    RETURN v;
END $$;

-- Calibración 1.000 L ×3 (camión o semimóvil): lecturas del patrón tal como están en el papel.
CREATE OR REPLACE FUNCTION pg_temp.calib(p_prog uuid, p_fecha date, p_pat text, p_pdf text, p_firmante text, p_ejecutor text, p_tecnico text,
                                         p_ajuste text, p_cab text, p_cpo text, p_modelo text,
                                         p_ini numeric, p_fin numeric, p_rec numeric, p_llenado int, p_recirc int,
                                         p1 numeric, p2 numeric, p3 numeric, p_nota text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v uuid; p uuid := fn_enex_pauta_de_programacion(p_prog);
        -- error en % con coma decimal, como en el papel (1.002 L de patrón = +0,2 %)
        v_err text := format('+%s / +%s / +%s %%', replace(round((p1 - 1000) / 10, 1)::text, '.', ','),
                             replace(round((p2 - 1000) / 10, 1)::text, '.', ','), replace(round((p3 - 1000) / 10, 1)::text, '.', ','));
        v_obs text := format('Se realizó llenado de línea con %s L y recirculación con %s L. Patrón 1.000 L ×3: lecturas %s, %s y %s L (error %s).',
                             p_llenado, p_recirc, p1, p2, p3, v_err) || coalesce(' ' || p_nota, '');
BEGIN
    v := pg_temp.ejec(p_prog, p_fecha, p_pdf, p_firmante, p_ejecutor, p_tecnico, 'Certificado de verificación de volúmenes NCh1436. ' || v_obs);
    PERFORM pg_temp.it(v, p, 'ID.SELLO_AJUSTE', NULL, NULL, p_ajuste);
    PERFORM pg_temp.it(v, p, 'ID.SELLOS_CAB', NULL, NULL, p_cab);
    PERFORM pg_temp.it(v, p, 'ID.SELLOS_CPO', NULL, NULL, p_cpo);
    PERFORM pg_temp.it(v, p, 'ID.MODELO', NULL, NULL, p_modelo);
    PERFORM pg_temp.it(v, p, 'ID.COMBUSTIBLE', NULL, NULL, 'Diésel');
    PERFORM pg_temp.it(v, p, 'ID.SURTIDOR', NULL, NULL, 'Boca N°1 · Wiggins 150');
    PERFORM pg_temp.it(v, p, 'TOT.INI', NULL, p_ini, NULL);
    PERFORM pg_temp.it(v, p, 'TOT.FIN', NULL, p_fin, NULL);
    PERFORM pg_temp.it(v, p, 'TOT.REC', NULL, p_rec, NULL);
    PERFORM pg_temp.it(v, p, c, NULL, 1000, NULL) FROM unnest(ARRAY['C1.MED','C2.MED','C3.MED']) c;
    PERFORM pg_temp.it(v, p, 'C1.PAT', NULL, p1, NULL);
    PERFORM pg_temp.it(v, p, 'C2.PAT', NULL, p2, NULL);
    PERFORM pg_temp.it(v, p, 'C3.PAT', NULL, p3, NULL);
    PERFORM pg_temp.it(v, p, 'CIE.AJUSTE', NULL, NULL, 'No (error ' || v_err || ')');
    PERFORM pg_temp.it(v, p, 'CIE.OBS', NULL, NULL, v_obs);
    IF p_pat IS NOT NULL THEN PERFORM pg_temp.it(v, p, '0', NULL, NULL, p_pat); END IF;
END $$;

DO $$
DECLARE
    v_faena uuid := (SELECT id FROM enex_faenas WHERE codigo = 'LB_COMB');
    -- Tareas desplazadas por ESM
    p_eess_cal uuid := '50f04c33-10b9-4a35-a39e-eb5fb97bce9a';
    p_eess_man uuid := '0182b7a1-95f3-450f-9d5a-5e1f6c50c14b';
    p_brazo_cal uuid := 'c9a154c9-2ac6-45de-bb7e-28fa7922f845';
    p_brazo_man uuid := '331739be-fcaa-4860-ac2f-fb8ff266f356';
    -- Reemplazos (camión por asignar del 26-10 = SCCC60; ids fijos: la migración es idempotente)
    p_sccc uuid := '12428146-5cc5-4b6b-8427-b47ed9d6734c';
    p_skol uuid := 'c0a8f1e2-5b7d-4e3a-9f21-666000000001';
    p_kvxh uuid := 'c0a8f1e2-5b7d-4e3a-9f21-666000000002';
    -- Semimóvil Fortuna (planificado)
    p_fort_cal uuid := 'c2460e7e-2a9a-483f-9ca3-0c3622e36be3';
    p_fort_man uuid := '9941208b-36a8-4b90-8f42-5f3c92dac2aa';
    c26 uuid; c27 uuid; i_sccc uuid; i_skol uuid; i_kvxh uuid; v uuid; p uuid; pat text;
    fESM text := 'Representante ESM (firma en el certificado)';
BEGIN
    IF v_faena IS NULL THEN RAISE EXCEPTION 'No existe la faena LB_COMB'; END IF;

    -- 1) Camiones que no estaban en el maestro de LB_COMB
    FOREACH pat IN ARRAY ARRAY['SCCC60', 'SKOL82', 'KVXH64'] LOOP
        IF NOT EXISTS (SELECT 1 FROM enex_instalaciones WHERE faena_id = v_faena AND tipo = 'camion' AND NOT es_comodin
                          AND fn_enex_patente_norm(patente) = pat) THEN
            INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, patente, activo, orden, creada_en_terreno)
            VALUES (v_faena, pat, 'Aljibe ' || pat, 'camion', 'combustible', pat, true, 500, true);
        END IF;
    END LOOP;
    SELECT id INTO i_sccc FROM enex_instalaciones WHERE faena_id = v_faena AND tipo = 'camion' AND NOT es_comodin AND fn_enex_patente_norm(patente) = 'SCCC60' LIMIT 1;
    SELECT id INTO i_skol FROM enex_instalaciones WHERE faena_id = v_faena AND tipo = 'camion' AND NOT es_comodin AND fn_enex_patente_norm(patente) = 'SKOL82' LIMIT 1;
    SELECT id INTO i_kvxh FROM enex_instalaciones WHERE faena_id = v_faena AND tipo = 'camion' AND NOT es_comodin AND fn_enex_patente_norm(patente) = 'KVXH64' LIMIT 1;

    -- 2) Cambios de tarea (MIG658): las 4 desplazadas quedan esperando el correo del ADC
    INSERT INTO enex_cambios_tarea (programacion_id, fecha, solicitante_esm, motivo, destino) VALUES
        (p_eess_cal,  DATE '2026-10-26', 'ESM (jefe de turno en faena)', 'ESM pidió calibrar los camiones SCCC-60 y SKOL-82 en lugar de la EESS Valle Amanda', 'pendiente_adc'),
        (p_eess_man,  DATE '2026-10-26', 'ESM (jefe de turno en faena)', 'ESM pidió calibrar los camiones SCCC-60 y SKOL-82 en lugar de la EESS Valle Amanda', 'pendiente_adc'),
        (p_brazo_cal, DATE '2026-10-27', 'ESM (jefe de turno en faena)', 'ESM pidió calibrar el camión KVXH-64 en lugar del brazo de carga Valle Amanda', 'pendiente_adc'),
        (p_brazo_man, DATE '2026-10-27', 'ESM (jefe de turno en faena)', 'ESM pidió calibrar el camión KVXH-64 en lugar del brazo de carga Valle Amanda', 'pendiente_adc')
    ON CONFLICT (programacion_id) DO NOTHING;
    SELECT id INTO c26 FROM enex_cambios_tarea WHERE programacion_id = p_eess_cal;
    SELECT id INTO c27 FROM enex_cambios_tarea WHERE programacion_id = p_brazo_cal;
    UPDATE enex_programaciones SET por_reprogramar_at = NULL, por_reprogramar_motivo = NULL, por_reprogramar_por = NULL
     WHERE id IN (p_eess_cal, p_eess_man, p_brazo_cal, p_brazo_man);

    -- 3) Reemplazos: el camión por asignar del 26-10 pasa a SCCC60; SKOL82 (26-10) y KVXH64 (27-10) se agregan
    UPDATE enex_programaciones SET instalacion_id = i_sccc, cambio_tarea_id = c26 WHERE id = p_sccc;
    INSERT INTO enex_programaciones (id, instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, origen, cambio_tarea_id) VALUES
        (p_skol, i_skol, 'calibracion', 2026, 10, DATE '2026-10-26', 'En reemplazo de EESS Valle Amanda (calibración), pedido por ESM', 'cambio_esm', c26),
        (p_kvxh, i_kvxh, 'calibracion', 2026, 10, DATE '2026-10-27', 'En reemplazo de Brazo de carga Valle Amanda (calibración), pedido por ESM', 'cambio_esm', c27)
    ON CONFLICT (id) DO NOTHING;

    -- 4) Calibraciones (lecturas del certificado)
    PERFORM pg_temp.calib(p_sccc, DATE '2026-10-26', 'SCCC60', 'lbcomb_20261026_calib_SCCC60.pdf', fESM,
                          'Fabián Castillo (mecánico) · supervisor Roberto Cáceres', 'Fabián Castillo',
                          '0203', '0218', '0253', 'M-10-1', 2053758, 2057265, 3507, 504, 3003, 1001, 1001, 1001);
    PERFORM pg_temp.calib(p_skol, DATE '2026-10-26', 'SKOL82', 'lbcomb_20261026_calib_SKOL82.pdf', fESM,
                          'Jaison Paredes (eléctrico) · supervisor Roberto Cáceres', 'Jaison Paredes',
                          '1493', '1641', '1644', NULL, 16087813, 16091352, 3539, 532, 3007, 1003, 1002, 1002);
    PERFORM pg_temp.calib(p_kvxh, DATE '2026-10-27', 'KVXH64', 'lbcomb_20261027_calib_KVXH64.pdf',
                          'Fernando Vega (Jefe de Turno ESM, RUT 15.036.539-2)',
                          'Bastián (apellido ilegible) y Fabián Castillo (mecánico) · supervisor Roberto Cáceres', 'Fabián Castillo',
                          '2635', '1349', '1405', 'M-10-1', 25196261, 25198830, 3569, 569, 3000, 1002, 1001, 1001,
                          'Totalizador final según el papel: 25.198.830 (inicio + 3.569 L recirculados daría 25.199.830).');
    PERFORM pg_temp.calib(p_fort_cal, DATE '2026-10-28', NULL, 'lbcomb_20261028_calib_SM_Fortuna.pdf', fESM,
                          'Fabián Castillo (mecánico) · supervisor Roberto Cáceres', 'Fabián Castillo',
                          '1381', '1034', '4533', 'M-25-1', 84509298, 84512803, 3505, 499, 3006, 1002, 1002, 1002);

    -- 5) Mantención intermedia del Semimóvil Fortuna (OT Kizeo 28-10, 13:00–14:00)
    p := fn_enex_pauta_de_programacion(p_fort_man);
    v := pg_temp.ejec(p_fort_man, DATE '2026-10-28', 'lbcomb_20261028_mant_SM_Fortuna_OT_Kizeo.pdf',
                      'Cristian Leyton (firma de la OT, RUT 14.106.818-0)',
                      'Roberto Cáceres García · Jaison Paredes · Fabián Castillo (registró Hersaly Corey)', 'Roberto Cáceres García',
                      'Mantenimiento preventivo intermedio del semimóvil Fortuna (OT Kizeo). Todos los puntos revisados en buen estado, sin observaciones.',
                      NULL, timestamptz '2026-10-28 13:00-03', timestamptz '2026-10-28 14:00-03');
    PERFORM pg_temp.it(v, p, 'DS.MOTIVO', NULL, NULL, 'Mantenimiento preventivo');
    PERFORM pg_temp.it(v, p, 'DS.HORA_INI', NULL, NULL, '13:00');
    PERFORM pg_temp.it(v, p, 'DS.HORA_FIN', NULL, NULL, '14:00');
    PERFORM pg_temp.it(v, p, 'DS.RUT_TEC', NULL, NULL,
        'Roberto Cáceres García 13.356.767-4 · Jaison Paredes 26.341.839-5 · Fabián Castillo 20.735.095-8');
    PERFORM pg_temp.it(v, p, c, 'ok', NULL, 'Bueno. Sin observaciones')
       FROM unnest(ARRAY['EST.1','EST.2','EST.3','EST.4','TUB.1','TUB.2','TAB.1','TAB.2','TAB.3','TAB.4']) c;

    -- Última calibración conocida
    UPDATE enex_instalaciones SET ultima_calibracion = DATE '2026-10-26' WHERE id IN (i_sccc, i_skol);
    UPDATE enex_instalaciones SET ultima_calibracion = DATE '2026-10-27' WHERE id = i_kvxh;
    UPDATE enex_instalaciones SET ultima_calibracion = DATE '2026-10-28'
     WHERE id = (SELECT instalacion_id FROM enex_programaciones WHERE id = p_fort_cal);
END $$;

SELECT json_agg(json_build_object('fecha', p.fecha_programada, 'instalacion', i.nombre, 'servicio', p.tipo_servicio,
                                  'origen', p.origen, 'ejecucion', e.estado, 'cambio', ct.destino) ORDER BY p.fecha_programada, i.nombre)
  FROM enex_programaciones p
  JOIN enex_instalaciones i ON i.id = p.instalacion_id
  JOIN enex_faenas f ON f.id = i.faena_id AND f.codigo = 'LB_COMB'
  LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id
  LEFT JOIN enex_cambios_tarea ct ON ct.programacion_id = p.id
 WHERE p.fecha_programada BETWEEN DATE '2026-10-26' AND DATE '2026-10-28';
