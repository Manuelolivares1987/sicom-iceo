-- ============================================================================
-- SICOM-ICEO | 532 — Lomas: las 57 fotos analizadas y puestas en su ítem
-- ============================================================================
-- Manuel (04-09): «ninguno de los últimos informes tiene fotos… analiza en
-- profundidad las fotos y reportes y con ello genera los informes».
--
-- Se revisaron las 58 imágenes UNA A UNA. Hallazgos del análisis:
--   · La primera foto del lote del 17/08 era un PANTALLAZO del sistema
--     (modal «Finalizar OT») que se coló en la carpeta: se excluye.
--   · La libreta de terreno de F. López fotografiada dice «Lomas Bayas
--     20/8/26 — Rack 3 Truck Shop II Fortuna» y lista sus novedades: fecha
--     y contenido confirmados.
--   · Tarjetas de bloqueo fotografiadas: llave con FUGA tarjeteada el
--     17-08 (C. Zamora), carrete con fuga tarjeteado el 10-08 (Barraza),
--     línea de abastecimiento del 15W-40 fuera de servicio desde el 17-07.
--   · El manómetro del FRL (bomba de refrigerante, TS2 R1) fotografiado en
--     CERO; el tablero eléctrico del R3 con 4-5 luces de FALLA encendidas;
--     la tabla de distribución del R3 (línea SAE) visible en las vistas.
--   · Una bomba con tarjeta del 12-08 (visita MIG293) confirma que el lote
--     del galpón oscuro es LOMAS 1 y el del galpón claro (con CAEX) es TS2.
--
-- Con eso, cada foto queda en fotos_antes del ÍTEM que retrata (el informe
-- imprime ANTES|DESPUÉS por punto); lo no asignable queda como registro
-- general de su ejecución. Se enriquecen 3 observaciones con lo que las
-- fotos prueban (tarjetas y manómetro). ADITIVA e IDEMPOTENTE por REEMPLAZO.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.fn_ejec(p_inst TEXT, p_fecha DATE) RETURNS UUID AS $$
DECLARE v UUID;
BEGIN
    SELECT e.id INTO v
      FROM enex_ejecuciones e
      JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = p_inst AND i.activo AND e.fecha_ejecucion = p_fecha;
    IF v IS NULL THEN RAISE EXCEPTION 'No existe la ejecución de % el %', p_inst, p_fecha; END IF;
    RETURN v;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.fn_fotos(p_ejec UUID, p_cod TEXT, p_desc TEXT, p_base TEXT, p_nums INT[]) RETURNS VOID AS $$
DECLARE v_urls JSONB; v_n INT;
BEGIN
    SELECT jsonb_agg(p_base || lpad(n::text, 3, '0') || '.jpg') INTO v_urls FROM unnest(p_nums) n;
    UPDATE enex_ejecucion_items x SET fotos_antes = v_urls
      FROM enex_pauta_items pi JOIN enex_pautas p ON p.id = pi.pauta_id
     WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = p_ejec
       AND p.codigo = 'PAUTA-LUB' AND pi.codigo = p_cod AND pi.descripcion = p_desc;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN RAISE EXCEPTION 'No encontré el ítem % (%) en la ejecución %', p_cod, p_desc, p_ejec; END IF;
END $$ LANGUAGE plpgsql;

DO $mig$
DECLARE
    v UUID;
    b17 TEXT := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/17-lomas1-racks/registro/';
    b20 TEXT := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/20-lomas2-racks/registro/';
BEGIN
    -- ════ 17/08 · Lomas 1 - Rack 1 ════
    v := pg_temp.fn_ejec('Truck Shop Lomas 1 - Rack 1', DATE '2026-08-17');
    PERFORM pg_temp.fn_fotos(v, '5.1', 'Inspección estaciones de carrete', b17, ARRAY[3,8,10,13,14]);
    PERFORM pg_temp.fn_fotos(v, '5.2', 'Inspección de fugas',               b17, ARRAY[18]);
    PERFORM pg_temp.fn_fotos(v, '5.4', 'Inspección de válvulas manuales',   b17, ARRAY[9]);
    PERFORM pg_temp.fn_fotos(v, '5.7', 'Inspección estado de carretes',     b17, ARRAY[7,11,16,17]);
    PERFORM pg_temp.fn_fotos(v, '5.8', 'Inspección estado de pistolas',     b17, ARRAY[2,4,5,6,15,20]);
    -- El registro general queda con lo no asignable; el pantallazo (001) se excluye.
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL,
           evidencia_urls = ARRAY[b17||'012.jpg', b17||'021.jpg', b17||'022.jpg'],
           observacion = observacion || ' [MIG532] Las fotos del día fueron analizadas y asignadas al ítem que retratan; la imagen 001 del lote era un pantallazo ajeno y se excluyó.'
     WHERE id = v AND observacion NOT LIKE '%[MIG532]%';
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v;

    -- ════ 20/08 · TS2 (Lomas 2) - Rack 1 ════
    v := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 1', DATE '2026-08-20');
    PERFORM pg_temp.fn_fotos(v, '5.1', 'Inspección estaciones de carrete', b20, ARRAY[3,29,30,31]);
    PERFORM pg_temp.fn_fotos(v, '5.3', 'Inspección de ductos de lubricantes', b20, ARRAY[14,15,18,27,36]);
    PERFORM pg_temp.fn_fotos(v, '5.7', 'Inspección estado de carretes',     b20, ARRAY[28,32,33]);
    PERFORM pg_temp.fn_fotos(v, '5.8', 'Inspección estado de pistolas',     b20, ARRAY[17]);
    UPDATE enex_ejecucion_items x
       SET observacion = x.observacion || ' El manómetro del FRL se fotografió marcando cero.'
      FROM enex_pauta_items pi
     WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v AND pi.codigo = '5.3'
       AND x.observacion NOT LIKE '%manómetro del FRL%';
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL,
           evidencia_urls = ARRAY[b20||'011.jpg']
     WHERE id = v;

    -- ════ 20/08 · TS2 - Rack 2 ════
    v := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 2', DATE '2026-08-20');
    PERFORM pg_temp.fn_fotos(v, '5.3', 'Inspección de ductos de lubricantes', b20, ARRAY[12]);
    PERFORM pg_temp.fn_fotos(v, '5.4', 'Inspección de válvulas manuales',   b20, ARRAY[34]);
    PERFORM pg_temp.fn_fotos(v, '5.7', 'Inspección estado de carretes',     b20, ARRAY[2,22]);
    PERFORM pg_temp.fn_fotos(v, '5.8', 'Inspección estado de pistolas',     b20, ARRAY[19,35]);
    UPDATE enex_ejecucion_items x
       SET observacion = x.observacion || ' La línea de abastecimiento del 15W-40 está tarjeteada «fuera de servicio» desde el 17-07, lo que consta en terreno y explica que el carrete no pudiera revisarse.'
      FROM enex_pauta_items pi
     WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v AND pi.codigo = '5.7'
       AND x.observacion NOT LIKE '%tarjeteada «fuera de servicio»%';
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL, evidencia_urls = NULL WHERE id = v;

    -- ════ 20/08 · TS2 - Rack 3 ════
    v := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 3', DATE '2026-08-20');
    PERFORM pg_temp.fn_fotos(v, '5.1', 'Inspección estaciones de carrete', b20, ARRAY[6,26]);
    PERFORM pg_temp.fn_fotos(v, '5.2', 'Inspección de fugas',               b20, ARRAY[4,10]);
    PERFORM pg_temp.fn_fotos(v, '5.3', 'Inspección de ductos de lubricantes', b20, ARRAY[5,20,21,23]);
    PERFORM pg_temp.fn_fotos(v, '5.7', 'Inspección estado de carretes',     b20, ARRAY[1,7,9,13,16,24]);
    UPDATE enex_ejecucion_items x
       SET observacion = x.observacion || ' En terreno constan dos bloqueos previos por fuga, fotografiados: la llave tarjeteada el 17-08 (C. Zamora) y un carrete tarjeteado el 10-08 (Barraza).'
      FROM enex_pauta_items pi
     WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v AND pi.codigo = '5.2'
       AND x.observacion NOT LIKE '%bloqueos previos por fuga%';
    -- La libreta de terreno (20/8, Rack 3) y las vistas restantes, como registro.
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL,
           evidencia_urls = ARRAY[b17||'019.jpg', b20||'008.jpg', b20||'025.jpg']
     WHERE id = v;

    -- ── Verificación ────────────────────────────────────────────────────────
    IF (SELECT count(*) FROM enex_ejecucion_items x
         JOIN enex_ejecuciones e ON e.id = x.ejecucion_id
        WHERE e.fecha_ejecucion IN (DATE '2026-08-17', DATE '2026-08-20')
          AND jsonb_array_length(COALESCE(x.fotos_antes,'[]'::jsonb)) > 0) < 15 THEN
        RAISE EXCEPTION 'FALLO: menos ítems con fotos de los esperados';
    END IF;
    RAISE NOTICE 'MIG532 OK · % ítems con fotos asignadas en las 4 ejecuciones con registro',
        (SELECT count(*) FROM enex_ejecucion_items x
          JOIN enex_ejecuciones e ON e.id = x.ejecucion_id
         WHERE e.fecha_ejecucion IN (DATE '2026-08-17', DATE '2026-08-20')
           AND jsonb_array_length(COALESCE(x.fotos_antes,'[]'::jsonb)) > 0);
END
$mig$;

COMMIT;
