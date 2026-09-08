-- ============================================================================
-- Registro de las ejecuciones de Truck Shop Lomas 1 — 11 y 12 de agosto 2026
-- ----------------------------------------------------------------------------
-- Los servicios se hicieron en terreno pero no se registraron en la app, así
-- que se cargan desde el respaldo fotográfico. Criterios acordados:
--   · 11/08 Microfiltrado  → ítems 1.1 a 1.4 (los del plan semanal de ese día),
--     con el antes y el después de la limpieza como evidencia del conjunto.
--   · 12/08 Rack 1 y Rack 2 → bloque 5 «Mantención Lubricanteras», solo los
--     ítems de INSPECCIÓN (5.1-5.4, 5.6-5.8). Los correctivos del bloque
--     (eliminar fugas, cambiar carretes/pistolas/Test Point) no se marcan:
--     no consta que se hayan hecho.
--   · Las fotos del 12 van como registro fotográfico general: no venían
--     separadas en antes y después y no se inventa esa distinción.
--   · Sin técnico ejecutor: se completa cuando se sepa, y ahí se pide su firma.
-- El estado queda en 'ejecutada'; pasa a 'cumplida' cuando ESM firme.
-- IDEMPOTENTE: no duplica si la ejecución ya existe.
-- ============================================================================


-- ── 11/08 · Truck Shop Lomas 1 - Microfiltrado ──────────────────────────────────────────────
DO $$
DECLARE v_prog UUID; v_pauta UUID; v_ejec UUID; v_item UUID; v_n INT := 0;
BEGIN
    SELECT p.id INTO v_prog
      FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = 'Truck Shop Lomas 1 - Microfiltrado' AND p.fecha_programada = DATE '2026-08-11';
    IF v_prog IS NULL THEN RAISE EXCEPTION 'No existe la programación de % el %', 'Truck Shop Lomas 1 - Microfiltrado', '2026-08-11'; END IF;

    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_prog) THEN
        RAISE NOTICE '11/08 · Truck Shop Lomas 1 - Microfiltrado — ya tenía ejecución, no se toca'; RETURN;
    END IF;

    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion,
                                  observacion, evidencia_urls)
    VALUES (v_prog, v_pauta, 'ejecutada', DATE '2026-08-11',
            'Ejecución registrada como respaldo de terreno a partir del registro fotográfico del día (PAUTA LOMAS / Ejecución / Agosto). Pendiente la identificación y firma del técnico ejecutor.', NULL)
    RETURNING id INTO v_ejec;

    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='1.1' AND pi.descripcion='Limpieza exterior de líneas de lubricantes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 1.1 (Limpieza exterior de líneas de lubricantes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', 'Registro fotográfico del antes y el después de la limpieza del sector; corresponde al conjunto de los ítems 1.1 a 1.4 de la jornada.', '["https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/001.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/002.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/003.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/004.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/005.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/antes/006.jpg"]'::jsonb, '["https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/001.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/002.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/003.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/004.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/005.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/006.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/007.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/008.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/009.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/010.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/011.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/012.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/013.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/014.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/015.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/016.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/017.jpg", "https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/11-lomas1-microfiltrado/despues/018.jpg"]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='1.2' AND pi.descripcion='Limpieza exterior de equipos de filtrado' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 1.2 (Limpieza exterior de equipos de filtrado)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='1.3' AND pi.descripcion='Limpieza de bocatomas de carga de lubricantes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 1.3 (Limpieza de bocatomas de carga de lubricantes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='1.4' AND pi.descripcion='Revisión y limpieza de piso interior pretil' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 1.4 (Revisión y limpieza de piso interior pretil)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    RAISE NOTICE '11/08 · Truck Shop Lomas 1 - Microfiltrado — ejecucion % con % items', v_ejec, v_n;
END $$;


-- ── 12/08 · Truck Shop Lomas 1 - Rack 1 ──────────────────────────────────────────────
DO $$
DECLARE v_prog UUID; v_pauta UUID; v_ejec UUID; v_item UUID; v_n INT := 0;
BEGIN
    SELECT p.id INTO v_prog
      FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = 'Truck Shop Lomas 1 - Rack 1' AND p.fecha_programada = DATE '2026-08-12';
    IF v_prog IS NULL THEN RAISE EXCEPTION 'No existe la programación de % el %', 'Truck Shop Lomas 1 - Rack 1', '2026-08-12'; END IF;

    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_prog) THEN
        RAISE NOTICE '12/08 · Truck Shop Lomas 1 - Rack 1 — ya tenía ejecución, no se toca'; RETURN;
    END IF;

    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion,
                                  observacion, evidencia_urls)
    VALUES (v_prog, v_pauta, 'ejecutada', DATE '2026-08-12',
            'Ejecución registrada como respaldo de terreno a partir del registro fotográfico del día (PAUTA LOMAS / Ejecución / Agosto). Pendiente la identificación y firma del técnico ejecutor. El registro fotográfico va como evidencia general del servicio: las fotos no venían separadas en antes y después.', ARRAY['https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/001.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/002.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/003.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/004.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/005.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/006.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/007.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/008.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/009.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/010.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/011.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/012.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/013.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/014.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/015.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/016.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/017.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/018.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/019.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/020.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/021.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/022.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/023.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/024.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/025.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/026.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/027.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/028.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/029.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/030.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/031.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/032.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/033.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/034.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/035.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/036.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/037.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/038.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/039.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/040.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/041.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/042.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack1/registro/043.jpg']::text[])
    RETURNING id INTO v_ejec;

    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.1' AND pi.descripcion='Inspección estaciones de carrete' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.1 (Inspección estaciones de carrete)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.2' AND pi.descripcion='Inspección de fugas' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.2 (Inspección de fugas)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.3' AND pi.descripcion='Inspección de ductos de lubricantes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.3 (Inspección de ductos de lubricantes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.4' AND pi.descripcion='Inspección de válvulas manuales' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.4 (Inspección de válvulas manuales)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.6' AND pi.descripcion='Inspección estado Test Point' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.6 (Inspección estado Test Point)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.7' AND pi.descripcion='Inspección estado de carretes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.7 (Inspección estado de carretes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.8' AND pi.descripcion='Inspección estado de pistolas' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.8 (Inspección estado de pistolas)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    RAISE NOTICE '12/08 · Truck Shop Lomas 1 - Rack 1 — ejecucion % con % items', v_ejec, v_n;
END $$;


-- ── 12/08 · Truck Shop Lomas 1 - Rack 2 ──────────────────────────────────────────────
DO $$
DECLARE v_prog UUID; v_pauta UUID; v_ejec UUID; v_item UUID; v_n INT := 0;
BEGIN
    SELECT p.id INTO v_prog
      FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = 'Truck Shop Lomas 1 - Rack 2' AND p.fecha_programada = DATE '2026-08-12';
    IF v_prog IS NULL THEN RAISE EXCEPTION 'No existe la programación de % el %', 'Truck Shop Lomas 1 - Rack 2', '2026-08-12'; END IF;

    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_prog) THEN
        RAISE NOTICE '12/08 · Truck Shop Lomas 1 - Rack 2 — ya tenía ejecución, no se toca'; RETURN;
    END IF;

    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion,
                                  observacion, evidencia_urls)
    VALUES (v_prog, v_pauta, 'ejecutada', DATE '2026-08-12',
            'Ejecución registrada como respaldo de terreno a partir del registro fotográfico del día (PAUTA LOMAS / Ejecución / Agosto). Pendiente la identificación y firma del técnico ejecutor. El registro fotográfico va como evidencia general del servicio: las fotos no venían separadas en antes y después.', ARRAY['https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/001.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/002.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/003.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/004.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/005.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/006.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/007.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/008.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/009.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/010.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/011.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/012.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/013.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/014.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/015.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/016.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/017.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/018.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/019.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/020.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/021.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/022.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/023.jpg','https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/12-lomas1-rack2/registro/024.jpg']::text[])
    RETURNING id INTO v_ejec;

    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.1' AND pi.descripcion='Inspección estaciones de carrete' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.1 (Inspección estaciones de carrete)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.2' AND pi.descripcion='Inspección de fugas' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.2 (Inspección de fugas)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.3' AND pi.descripcion='Inspección de ductos de lubricantes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.3 (Inspección de ductos de lubricantes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.4' AND pi.descripcion='Inspección de válvulas manuales' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.4 (Inspección de válvulas manuales)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.6' AND pi.descripcion='Inspección estado Test Point' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.6 (Inspección estado Test Point)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.7' AND pi.descripcion='Inspección estado de carretes' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.7 (Inspección estado de carretes)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id=pi.pauta_id
     WHERE p.codigo='PAUTA-LUB' AND pi.codigo='5.8' AND pi.descripcion='Inspección estado de pistolas' AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem 5.8 (Inspección estado de pistolas)'; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (v_ejec, v_item, 'ok', NULL, '[]'::jsonb, '[]'::jsonb);
    v_n := v_n + 1;
    RAISE NOTICE '12/08 · Truck Shop Lomas 1 - Rack 2 — ejecucion % con % items', v_ejec, v_n;
END $$;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT i.nombre, e.fecha_ejecucion, e.estado,
                    (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id = e.id) AS items,
                    coalesce(array_length(e.evidencia_urls, 1), 0) AS evidencias,
                    (SELECT coalesce(sum(jsonb_array_length(x.fotos_antes) + jsonb_array_length(x.fotos_despues)), 0)
                       FROM enex_ejecucion_items x WHERE x.ejecucion_id = e.id) AS fotos_items
               FROM enex_ejecuciones e
               JOIN enex_programaciones p ON p.id = e.programacion_id
               JOIN enex_instalaciones i ON i.id = p.instalacion_id
              WHERE e.fecha_ejecucion IN (DATE '2026-08-11', DATE '2026-08-12')
              ORDER BY e.fecha_ejecucion, i.nombre LOOP
        RAISE NOTICE '% | % | % | % ítems | % fotos en ítems | % evidencias',
            r.fecha_ejecucion, r.nombre, r.estado, r.items, r.fotos_items, r.evidencias;
    END LOOP;
END $$;
