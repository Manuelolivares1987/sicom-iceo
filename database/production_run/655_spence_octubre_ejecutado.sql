-- 655 — Spence octubre 2026: lo ejecutado del 19 al 21-10, desde los papeles
-- firmados (carpeta «SPENCE OCTUBRE» de Manuel, 26-10-2026).
--
-- Cada servicio queda con su ejecución, las lecturas del certificado en la
-- pauta y, como informe PDF, el papel escaneado con la firma de ESM (subido a
-- documentos/enex-informes/spence-2026-10/). La firma del mandante está en el
-- papel: firma_mandante_url apunta a ese mismo PDF.
--
--   19-10 EDS Spence (EESS S1)  calibración isla 1 (surt. 1-2) + isla 2 (surt. 3-4), 20 L ×3, 0 %
--   19-10 EDS Spence (EESS S1)  mantención intermedia, OT Kizeo 286491214 (filtros: requiere cambio)
--   20-10 SZBD35, SZBK99        calibración 1.000 L ×3, 0 %   — ESM: Héctor Navarrete Contreras
--   21-10 SZBD71, SZBS36        calibración 1.000 L ×3, 0 %   — ESM: Marcelo Garrido Rojas
--   21-10 SHHR16                calibración 1.000 L ×3, 0 %   — NO estaba planificado ni en el
--                               maestro de camiones de Spence: se crea (creada_en_terreno) y su
--                               servicio queda «fuera de plan» (origen terreno).
-- Verificó Fabián Castillo (mecánico); sellos Iván Lobos.

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
CREATE OR REPLACE FUNCTION pg_temp.ejec(p_prog uuid, p_fecha date, p_pdf text, p_firmante text, p_obs text,
                                        p_ot text DEFAULT NULL, p_ini timestamptz DEFAULT NULL, p_fin timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; v_url text := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/documentos/enex-informes/spence-2026-10/' || p_pdf;
BEGIN
    INSERT INTO enex_ejecuciones (programacion_id, estado, fecha_ejecucion, ot_numero, ejecutor, observacion, evidencia_urls,
                                  firma_mandante_url, firmante_mandante_nombre, firmante_mandante_at, pauta_id,
                                  tecnico_nombre, informe_pdf_url, inicio_at, fin_at, duracion_segundos, notificado_at)
    VALUES (p_prog, 'cumplida', p_fecha, p_ot, 'Fabián Castillo (mecánico) · sellos Iván Lobos', p_obs, ARRAY[v_url],
            v_url, p_firmante, (p_fecha + time '18:00') AT TIME ZONE 'America/Santiago', fn_enex_pauta_de_programacion(p_prog),
            'Fabián Castillo', v_url, p_ini, p_fin,
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

-- Calibración de camión (1.000 L ×3 a 0 %).
CREATE OR REPLACE FUNCTION pg_temp.camion(p_prog uuid, p_fecha date, p_pat text, p_pdf text, p_firmante text,
                                          p_ajuste text, p_cab text, p_cpo text, p_ini numeric, p_fin numeric, p_rec numeric, p_llenado int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v uuid; p uuid := fn_enex_pauta_de_programacion(p_prog);
        v_obs text := format('Se realizó llenado de línea con %s L y recirculación con 3.000 L. Patrón 1.000 L ×3: 0 %% de error.', p_llenado);
BEGIN
    v := pg_temp.ejec(p_prog, p_fecha, p_pdf, p_firmante, 'Certificado de verificación de volúmenes NCh1436. ' || v_obs);
    PERFORM pg_temp.it(v, p, 'ID.SELLO_AJUSTE', NULL, NULL, p_ajuste);
    PERFORM pg_temp.it(v, p, 'ID.SELLOS_CAB', NULL, NULL, p_cab);
    PERFORM pg_temp.it(v, p, 'ID.SELLOS_CPO', NULL, NULL, p_cpo);
    PERFORM pg_temp.it(v, p, 'ID.MODELO', NULL, NULL, '700-25SR4AL');
    PERFORM pg_temp.it(v, p, 'ID.COMBUSTIBLE', NULL, NULL, 'Diésel');
    PERFORM pg_temp.it(v, p, 'ID.SURTIDOR', NULL, NULL, 'Boca N°1 · W150');
    PERFORM pg_temp.it(v, p, 'TOT.INI', NULL, p_ini, NULL);
    PERFORM pg_temp.it(v, p, 'TOT.FIN', NULL, p_fin, NULL);
    PERFORM pg_temp.it(v, p, 'TOT.REC', NULL, p_rec, NULL);
    PERFORM pg_temp.it(v, p, c, NULL, 1000, NULL) FROM unnest(ARRAY['C1.MED','C1.PAT','C2.MED','C2.PAT','C3.MED','C3.PAT']) c;
    PERFORM pg_temp.it(v, p, 'CIE.SELLOS_OK', 'ok', NULL, 'Inspección de sellos: Iván Lobos');
    PERFORM pg_temp.it(v, p, 'CIE.AJUSTE', NULL, NULL, 'No (0 % de error en las 3 corridas)');
    PERFORM pg_temp.it(v, p, 'CIE.OBS', NULL, NULL, v_obs);
    PERFORM pg_temp.it(v, p, '0', NULL, NULL, p_pat);
END $$;

DO $$
DECLARE
    v_spence uuid := (SELECT id FROM enex_faenas WHERE codigo = 'SPENCE');
    v_shhr uuid; v_prog uuid := 'c0a8f1e2-5b7d-4e3a-9f21-655000000016';  -- id fijo: la migración es idempotente
    v uuid; p uuid;
    fH text := 'Héctor Navarrete Contreras (Jefe de Turno ESM, RUT 13.216.046-5)';
    fM text := 'Marcelo Garrido Rojas (Jefe de Turno ESM)';
BEGIN
    -- SHHR16: camión que no estaba en el maestro de Spence.
    SELECT id INTO v_shhr FROM enex_instalaciones
     WHERE faena_id = v_spence AND tipo = 'camion' AND fn_enex_patente_norm(patente) = 'SHHR16';
    IF v_shhr IS NULL THEN
        INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, patente, activo, orden, creada_en_terreno)
        VALUES (v_spence, 'SHHR16', 'Aljibe SHHR16', 'camion', 'combustible', 'SHHR16', true, 500, true)
        RETURNING id INTO v_shhr;
    END IF;
    INSERT INTO enex_programaciones (id, instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, origen)
    VALUES (v_prog, v_shhr, 'calibracion', 2026, 10, DATE '2026-10-21',
            'Calibración no planificada: camión entregado por la operación el 21-10 (certificado firmado ESM)', 'terreno')
    ON CONFLICT (id) DO NOTHING;

    -- Camiones
    PERFORM pg_temp.camion('a2717ee8-6817-4ad4-b4d8-9ab67d4b2943', DATE '2026-10-20', 'SZBD35', 'spence_20261020_calib_SZBD35.pdf', fH,
                           '6368', '16486', '16486', 6473469, 6476974, 3505, 505);
    PERFORM pg_temp.camion('b5c1d495-77d8-4fa2-ae79-91a3d99a8694', DATE '2026-10-20', 'SZBK99', 'spence_20261020_calib_SZBK99.pdf', fH,
                           '16180', '16483', '16483', 12641961, 12645464, 3503, 503);
    PERFORM pg_temp.camion('feca4f24-3811-4b14-8f31-2648e130ddd4', DATE '2026-10-21', 'SZBD71', 'spence_20261021_calib_SZBD71.pdf', fM,
                           '6323', '16328', NULL, 12294036, 12297544, 3508, 508);
    PERFORM pg_temp.camion('29e077b7-9c5d-4574-a141-0fddf0173940', DATE '2026-10-21', 'SZBS36', 'spence_20261021_calib_SZBS36.pdf', fM,
                           '16113', '16487', NULL, 1656847, 1660349, 3502, 502);
    PERFORM pg_temp.camion(v_prog, DATE '2026-10-21', 'SHHR16', 'spence_20261021_calib_SHHR16.pdf', fM,
                           NULL, NULL, NULL, 105314, 108801, 3487, 487);

    -- EDS: calibración isla 1 + isla 2 (20 L ×3 por surtidor, 0 %)
    p := fn_enex_pauta_de_programacion('cf4a44c7-ad34-4854-99e7-94fcc0331238');
    v := pg_temp.ejec('cf4a44c7-ad34-4854-99e7-94fcc0331238', DATE '2026-10-19', 'spence_20261019_calib_EDS_isla1_isla2.pdf',
                      'Representante ESM (firma en los certificados de isla 1 e isla 2)',
                      'Certificados NCh1436 isla 1 y 2 (4 surtidores Gilbarco 912). Patrón 20 L ×3 por surtidor: 0 % de error en todos.');
    PERFORM pg_temp.it(v, p, 'ID.SELLO_AJUSTE', NULL, NULL, 'Isla 1: 052417 · Isla 2: 2007');
    PERFORM pg_temp.it(v, p, 'ID.MODELO', NULL, NULL, 'Gilbarco 912 · T19334');
    PERFORM pg_temp.it(v, p, 'ID.COMBUSTIBLE', NULL, NULL, 'Diésel');
    PERFORM pg_temp.it(v, p, 'ID.SURTIDOR', NULL, NULL, 'Isla 1: surtidores 1 y 2 · Isla 2: surtidores 3 y 4');
    PERFORM pg_temp.it(v, p, c, NULL, 20, NULL) FROM unnest(ARRAY['C1.MED','C1.PAT','C2.MED','C2.PAT','C3.MED','C3.PAT']) c;
    PERFORM pg_temp.it(v, p, 'CIE.SELLOS_OK', 'ok', NULL, 'Inspección de sellos: Iván Lobos');
    PERFORM pg_temp.it(v, p, 'CIE.AJUSTE', NULL, NULL, 'No (0 % de error en los 4 surtidores)');
    PERFORM pg_temp.it(v, p, 'CIE.OBS', NULL, NULL,
        'Surt. 1: tot. 4.139.775 → 4.140.472, 69,7 L recirculados (9,7 L llenado de línea). '
     || 'Surt. 2: tot. 9.590.703 → 9.591.403, 70 L (10 L llenado). '
     || 'Surt. 3: tot. 3.142.276 → 3.142.975, 69,9 L (9,9 L llenado). '
     || 'Surt. 4: tot. 3.682.289 → 3.682.990, 70,1 L (10,1 L llenado). Corridas de 20 L en cada surtidor.');

    -- EDS: mantención intermedia (OT Kizeo 286491214, 10:00–13:34)
    p := fn_enex_pauta_de_programacion('d3fec794-0cc1-477c-a6d4-16cf570cd0b0');
    v := pg_temp.ejec('d3fec794-0cc1-477c-a6d4-16cf570cd0b0', DATE '2026-10-19', 'spence_20261019_mant_EDS_OT286491214.pdf',
                      'Rodolfo Urra (revisado por, RUT 15.004.801-K)',
                      'Mantenimiento programado EDS (OT Kizeo 286491214). Todo en buen estado salvo filtros: requieren cambio '
                   || '(se encuentran filtros sueltos); coordinar la entrega de filtros para cambiarlos.',
                      '286491214', timestamptz '2026-10-19 10:00-03', timestamptz '2026-10-19 13:34-03');
    PERFORM pg_temp.it(v, p, 'DS.MOTIVO', NULL, NULL, 'Mantenimiento programado (preventivo)');
    PERFORM pg_temp.it(v, p, 'DS.HORA_INI', NULL, NULL, '10:00');
    PERFORM pg_temp.it(v, p, 'DS.HORA_FIN', NULL, NULL, '13:34');
    PERFORM pg_temp.it(v, p, 'DS.RUT_TEC', NULL, NULL,
        'Roberto Cáceres García 13.356.767-4 · Fabián Castillo 20.735.095-8 · Iván Lobos 19.204.631-9');
    PERFORM pg_temp.it(v, p, '2.2', 'ok', NULL, 'Medición de continuidad de mangueras: bueno');
    PERFORM pg_temp.it(v, p, '2.3', 'ok', NULL, 'Revisión de cabezal / eliminación de fugas y detector de fuga: bueno');
    PERFORM pg_temp.it(v, p, '3.1', 'no_ok', NULL, 'Limpieza de filtros: requiere corrección. Solicitar cambio de filtros; filtros sueltos');
    PERFORM pg_temp.it(v, p, '4.1', 'ok', NULL, 'Revisión de parada de emergencia y carretes a tierra: bueno');

    -- Última calibración conocida de cada camión.
    UPDATE enex_instalaciones SET ultima_calibracion = DATE '2026-10-20' WHERE faena_id = v_spence AND patente IN ('SZBD35','SZBK99');
    UPDATE enex_instalaciones SET ultima_calibracion = DATE '2026-10-21' WHERE faena_id = v_spence AND patente IN ('SZBD71','SZBS36','SHHR16');
END $$;

SELECT json_agg(json_build_object('fecha', p.fecha_ejecucion, 'instalacion', p.instalacion, 'servicio', p.tipo_servicio,
                                  'estado', p.estado, 'cumplida', p.cumplida, 'items', (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id = p.ejecucion_id),
                                  'pdf', p.informe_pdf_url IS NOT NULL) ORDER BY p.fecha_ejecucion, p.instalacion) AS resultado
  FROM v_enex_panel_mensual p
 WHERE p.faena_codigo = 'SPENCE' AND p.fecha_ejecucion BETWEEN '2026-10-19' AND '2026-10-21';
