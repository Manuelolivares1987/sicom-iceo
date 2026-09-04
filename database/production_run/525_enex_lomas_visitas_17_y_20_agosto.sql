-- ============================================================================
-- SICOM-ICEO | 525 — Lomas: visitas de contingencia del 17 y 20 de agosto
-- ============================================================================
-- Los informes técnicos de Felipe López Vega (Report&Run, docs 7/8/9 + informe
-- Word «dom 30») registran inspecciones a los racks de lubricación de Minera
-- Lomas Bayas que se hicieron POR CONTINGENCIA fuera de la app. Manuel
-- (04-09-2026): «fue 17 y 20 de agosto por contingencia, pero debe quedar en
-- la plataforma igual que los otros» (los del 11/12 agosto, MIG293/294).
--
-- CRITERIOS (los mismos de MIG293/294):
--   · 17/08 → Truck Shop Lomas 1: Rack 1 y Rack 2 (docs 9 y 7 del 31/8).
--   · 20/08 → Truck Shop Lomas 2: Rack 1, Rack 2 y Rack 3 (docs 8 y 7 del
--     21/8 y 28/8, y el informe del 30/8). Los PDF dicen «20/08» en el cuerpo;
--     la fecha del Lomas 1 la fija Manuel (17/08).
--   · Solo ítems de INSPECCIÓN del bloque 5; lo silente en el informe queda
--     'ok' salvo Test Point (5.6), que ningún informe menciona → 'na'.
--   · El texto se transcribe fiel; se corrige solo ortografía.
--   · Las novedades que piden repuestos van como REQUERIMIENTOS AL MANDANTE
--     (MIG287 los imprime en el informe que firma ESM).
--   · Registro fotográfico del día como evidencia general en el Rack 1 de
--     cada visita (no venía separado por rack ni en antes/después):
--     17/08 → enex/2026-08/17-lomas1-racks/registro (23 fotos)
--     20/08 → enex/2026-08/20-lomas2-racks/registro (35 fotos)
--     (la subida de las fotos corre por separado; las rutas son éstas).
--   · Técnico ejecutor: Felipe López Vega. Estado 'ejecutada'; pasa a
--     'cumplida' cuando ESM firme (firma remota MIG276).
-- ADITIVA e IDEMPOTENTE.
-- ============================================================================

BEGIN;

-- ── util: crear programación si no existe ───────────────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.fn_prog(p_inst TEXT, p_fecha DATE) RETURNS UUID AS $$
DECLARE v_inst UUID; v_prog UUID;
BEGIN
    SELECT id INTO v_inst FROM enex_instalaciones WHERE nombre = p_inst AND activo;
    IF v_inst IS NULL THEN RAISE EXCEPTION 'No existe la instalación activa %', p_inst; END IF;
    SELECT id INTO v_prog FROM enex_programaciones
     WHERE instalacion_id = v_inst AND fecha_programada = p_fecha;
    IF v_prog IS NULL THEN
        INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes,
                                         fecha_programada, observacion)
        VALUES (v_inst, 'mantencion', 2026, 8, p_fecha,
                'Visita de contingencia registrada como respaldo (MIG525).')
        RETURNING id INTO v_prog;
    END IF;
    RETURN v_prog;
END $$ LANGUAGE plpgsql;

-- ── util: ejecución con sus 7 ítems de inspección ───────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.fn_ejec(
    p_inst TEXT, p_fecha DATE, p_obs TEXT, p_evid TEXT[],
    p_51 TEXT, p_52 TEXT, p_53 TEXT, p_54 TEXT, p_57 TEXT, p_58 TEXT
) RETURNS UUID AS $$
DECLARE v_prog UUID; v_pauta UUID; v_ejec UUID; v_item UUID;
        v_cod TEXT; v_desc TEXT; v_res TEXT; v_txt TEXT;
BEGIN
    v_prog := pg_temp.fn_prog(p_inst, p_fecha);
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_prog) THEN
        RAISE NOTICE '% · % — ya tenía ejecución, no se toca', p_fecha, p_inst;
        SELECT id INTO v_ejec FROM enex_ejecuciones WHERE programacion_id = v_prog LIMIT 1;
        RETURN v_ejec;
    END IF;

    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion,
                                  tecnico_nombre, observacion, evidencia_urls)
    VALUES (v_prog, v_pauta, 'ejecutada', p_fecha, 'Felipe López Vega', p_obs, p_evid)
    RETURNING id INTO v_ejec;

    FOR v_cod, v_desc, v_txt IN
        SELECT * FROM (VALUES
            ('5.1', 'Inspección estaciones de carrete',   p_51),
            ('5.2', 'Inspección de fugas',                p_52),
            ('5.3', 'Inspección de ductos de lubricantes', p_53),
            ('5.4', 'Inspección de válvulas manuales',    p_54),
            ('5.6', 'Inspección estado Test Point',       'NA'),
            ('5.7', 'Inspección estado de carretes',      p_57),
            ('5.8', 'Inspección estado de pistolas',      p_58)
        ) t(c, d, x)
    LOOP
        SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id = pi.pauta_id
         WHERE p.codigo = 'PAUTA-LUB' AND pi.codigo = v_cod AND pi.descripcion = v_desc AND pi.activo LIMIT 1;
        IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem % (%)', v_cod, v_desc; END IF;

        v_res := CASE WHEN v_txt = 'NA' THEN 'na' WHEN v_txt IS NULL THEN 'ok' ELSE 'no_ok' END;
        INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
        VALUES (v_ejec, v_item, v_res,
                CASE WHEN v_txt = 'NA'
                     THEN 'Los informes de terreno no registran revisión de Test Points en esta visita.'
                     ELSE v_txt END,
                '[]'::jsonb, '[]'::jsonb);
    END LOOP;

    RAISE NOTICE '% · % — ejecución % creada', p_fecha, p_inst, v_ejec;
    RETURN v_ejec;
END $$ LANGUAGE plpgsql;

-- ── util: requerimiento idempotente ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.fn_req(p_ejec UUID, p_titulo TEXT, p_desc TEXT) RETURNS VOID AS $$
DECLARE v_orden INT;
BEGIN
    IF EXISTS (SELECT 1 FROM enex_requerimientos WHERE ejecucion_id = p_ejec AND descripcion = p_desc) THEN RETURN; END IF;
    SELECT COALESCE(MAX(orden), 0) + 1 INTO v_orden FROM enex_requerimientos WHERE ejecucion_id = p_ejec;
    INSERT INTO enex_requerimientos (ejecucion_id, tipo, prioridad, titulo, descripcion, orden)
    VALUES (p_ejec, 'requerimiento', 'alta', p_titulo, p_desc, v_orden);
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = p_ejec;
END $$ LANGUAGE plpgsql;

DO $mig$
DECLARE
    v_ejec UUID;
    v_fotos17 TEXT[]; v_fotos20 TEXT[];
    v_base TEXT := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/';
    i INT;
    v_n INT;
BEGIN
    -- Rutas del registro fotográfico (la subida corre por separado).
    v_fotos17 := ARRAY(SELECT v_base || '17-lomas1-racks/registro/' || lpad(g::text, 3, '0') || '.jpg' FROM generate_series(1, 23) g);
    v_fotos20 := ARRAY(SELECT v_base || '20-lomas2-racks/registro/' || lpad(g::text, 3, '0') || '.jpg' FROM generate_series(1, 35) g);

    -- ════ 17/08 · Truck Shop Lomas 1 - Rack 1 (doc 9, 31/8 22:26) ════
    v_ejec := pg_temp.fn_ejec('Truck Shop Lomas 1 - Rack 1', DATE '2026-08-17',
        'Visita de contingencia registrada como respaldo desde el informe técnico de Felipe López Vega (Report&Run doc 9, emitido el 31/08). El rack cuenta con 8 carretes dispensadores, numerados por orden de montaje. El registro fotográfico del día va como evidencia general de esta ejecución (no venía separado por rack ni en antes/después).',
        v_fotos17,
        'Cuentalitros: carrete 1 defectuoso; carrete 5 sin cuentalitros; carrete 6 con cuentalitros análogo defectuoso y digital que no enciende; carrete 7 no se pudo revisar el funcionamiento del cuentalitros análogo.',
        'Carrete 3 (S4 CX10W): boquilla de pistola con fuga de aceite y llave de paso del producto con fuga de aceite. Carrete 6 (S4 CX50): sin llave de paso en la tubería de línea principal.',
        'Carrete 5 sin manguera y desconectado de la línea de alimentación. Línea de alimentación desde los TK al rack: faltan 3 manillas de llaves de paso.',
        'Llave de paso de aire comprimido (carrete 8) defectuosa, se debe cambiar. Faltan manillas en llaves de paso de las líneas de alimentación desde los TK.',
        'Carrete 1 no traba al extender la manguera; carrete 5 desarmado (sin manguera, sin pistola, sin cuentalitros); carrete 8 (aire comprimido) no traba al extender la manguera. Cables antilatigazo: faltante en carretes 3 y 7, defectuoso en carrete 6.',
        'Pistola defectuosa en carretes 1 y 6 (cambio); pistola con fuga en la boquilla en carrete 2; boquilla con fuga de aceite en carrete 3; pistola defectuosa en carrete 4 (se debe cambiar); carrete 5 sin pistola. Boquilla antigoteo faltante en carrete 1 y defectuosa en carrete 2.');
    PERFORM pg_temp.fn_req(v_ejec, 'Repuestos para recuperación del Rack 1',
        'Se requieren para recuperar el estado operacional del Rack 1: pistolas dispensadoras (carretes 1, 4, 5 y 6), boquillas antigoteo, cuentalitros análogos y digital (carretes 1, 5 y 6), cables antilatigazo (carretes 3, 6 y 7), manguera y conexión a línea de alimentación del carrete 5, llave de paso de la tubería principal del carrete 6, llave de paso de aire comprimido del carrete 8, y 3 manillas de llaves de paso de las líneas de alimentación desde los TK.');

    -- ════ 17/08 · Truck Shop Lomas 1 - Rack 2 (doc 7, 31/8 23:32) ════
    v_ejec := pg_temp.fn_ejec('Truck Shop Lomas 1 - Rack 2', DATE '2026-08-17',
        'Visita de contingencia registrada como respaldo desde el informe técnico de Felipe López Vega (Report&Run doc 7, emitido el 31/08). El rack cuenta con 8 carretes. El registro fotográfico del día quedó como evidencia general en la ejecución del Rack 1 de esta misma visita.',
        NULL,
        'Cuentalitros: desconectado en carrete 2; defectuoso en carretes 4 y 7; en mal estado en carrete 6. Conexión del carrete 5 al cuentalitros con fuga.',
        'Conexión del carrete 5 (S4 CX10W) al cuentalitros con fuga.',
        NULL,
        'Falta manilla en la llave de paso de la tubería (carrete 4, refrigerante). Falta llave de paso en la línea de salida de aire comprimido (carrete 8).',
        'Carrete 2 fuera de servicio: no traba al extender la manguera. Cables antilatigazo: defectuoso en carrete 1, fuera de posición en carretes 3 y 5, faltante en carretes 6 y 7. Falta freno de carrera de la manguera en el carrete 8 (aire comprimido).',
        'Carrete 2 sin pistola; pistola defectuosa en carrete 7. Boquillas antigoteo faltantes en carretes 1, 4, 5, 6 y 7.');
    PERFORM pg_temp.fn_req(v_ejec, 'Repuestos para recuperación del Rack 2',
        'Se requieren para recuperar el estado operacional del Rack 2: pistolas dispensadoras (carretes 2 y 7), boquillas antigoteo (carretes 1, 4, 5, 6 y 7), cuentalitros (carretes 2, 4, 6 y 7), cables antilatigazo (carretes 1, 3, 5, 6 y 7), manilla de llave de paso de la tubería del carrete 4, llave de paso de la línea de salida y freno de carrera del carrete de aire comprimido (8), y reparación de la conexión con fuga del carrete 5.');

    -- ════ 20/08 · Truck Shop Lomas 2 - Rack 1 (doc 8, 21/8 13:32) ════
    v_ejec := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 1', DATE '2026-08-20',
        'Visita de contingencia registrada como respaldo desde el informe técnico de Felipe López Vega (Report&Run doc 8, emitido el 21/08). Sector Fortuna, Truck Shop 2, sección Rack de Lubricación. El Truck Shop cuenta con tres racks. El registro fotográfico del día va como evidencia general de esta ejecución (no venía separado por rack ni en antes/después).',
        v_fotos20,
        'Cuentalitros no operacionales en carretes 1 (S5 CFD M60) y 2 (S4 CX50); defectuoso en carrete 4 (R4 MV15W40, cambio); falta cuentalitros en carrete 6 (S4 CX30).',
        'Fuga por conexión de carrete en el carrete 4 (R4 MV15W40).',
        'Bomba de diafragma 1 (refrigerante) no operacional: falta conector de la línea de aire comprimido y el reloj indicador de presión del FRL está dañado; no se pudo comprobar su funcionamiento. Bomba de diafragma 2 (aceite residual): no se pudo comprobar funcionamiento, falta mantenimiento.',
        'Falta manilla de accionamiento de la llave de paso al estanque (bomba de aceite residual).',
        'Cambio de manguera en carretes 4 y 5; cables antilatigazo faltantes en carretes 1, 2, 3 y 5, y deteriorado en carrete 6 (cambio); carrete 6 no traba. Se deben cambiar todos los logotipos que indican el producto de los carretes.',
        'Falta boquilla de pistola en carrete 2; pistola defectuosa en carrete 4 (cambio); cambio de boquilla de pistola en carrete 6. Faltan conectores antigoteo en carretes 1 y 2.');
    PERFORM pg_temp.fn_req(v_ejec, 'Repuestos para recuperación del Rack 1 (Truck Shop 2)',
        'Se requieren para recuperar el estado operacional del Rack 1 del Truck Shop 2: conector de línea de aire comprimido y reloj de presión FRL de la bomba de refrigerante; mantenimiento y manilla de llave de paso de la bomba de aceite residual; cuentalitros (carretes 1, 2, 4 y 6); mangueras (carretes 4 y 5); cables antilatigazo (carretes 1, 2, 3, 5 y 6); pistola del carrete 4 y boquillas de pistola (carretes 2 y 6); conectores antigoteo (carretes 1 y 2); y el recambio de todos los logotipos de producto del rack.');

    -- ════ 20/08 · Truck Shop Lomas 2 - Rack 2 (doc 7, 28/8 12:25) ════
    v_ejec := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 2', DATE '2026-08-20',
        'Visita de contingencia registrada como respaldo desde el informe técnico de Felipe López Vega (Report&Run doc 7, emitido el 28/08). Rack con 6 carretes de lubricante y 2 de producto residual conectados a bombas neumáticas, numerados por orden de montaje. El registro fotográfico del día quedó como evidencia general en la ejecución del Rack 1 de esta misma visita.',
        NULL,
        'Falta cuentalitros en carrete 1 (Spirax S5 CFD M60); cambiar el cuentalitros del carrete 7 (S4 CX30).',
        'Pistolas con fuga de aceite en carretes 2 (S4CX50) y 3 (S4 CX10W).',
        'Bomba neumática de diafragma del refrigerante usado (carrete 4) no operacional, fuera de servicio. Bomba de diafragma del aceite residual (carrete 8): falta mantenimiento.',
        'Falta manilla de accionamiento de la llave de paso (carrete 8, aceite residual).',
        'Faltan frenos de carrera de manguera en carretes 1, 2 y 7; cables antilatigazo faltantes en carretes 1, 2, 3 y 7, y por conectar en el carrete 5 (refrigerante). Carrete 6 (15W-40) fuera de servicio: no se pudo revisar.',
        'Falta pistola en carrete 1; pistolas con fuga en carretes 2 y 3. Boquillas antigoteo faltantes en carretes 1 y 3.');
    PERFORM pg_temp.fn_req(v_ejec, 'Repuestos para recuperación del Rack 2 (Truck Shop 2)',
        'Se requieren para recuperar el estado operacional del Rack 2 del Truck Shop 2: reparación o reposición de la bomba neumática del refrigerante usado (carrete 4) y mantenimiento de la bomba del aceite residual (carrete 8) con su manilla de llave de paso; pistola del carrete 1 y reparación de pistolas con fuga (carretes 2 y 3); cuentalitros (carretes 1 y 7); frenos de carrera de manguera (carretes 1, 2 y 7); cables antilatigazo (carretes 1, 2, 3 y 7); boquillas antigoteo (carretes 1 y 3); y revisión del carrete 6, fuera de servicio.');

    -- ════ 20/08 · Truck Shop Lomas 2 - Rack 3 (informe «dom 30») ════
    v_ejec := pg_temp.fn_ejec('Truck Shop Lomas 2 - Rack 3', DATE '2026-08-20',
        'Visita de contingencia registrada como respaldo desde el informe técnico de la comisión a Calama de Felipe López Vega (09 al 21 de agosto). Rack 3 compuesto de 8 carretes; los carretes 4 y 8 trabajan con bomba de diafragma; los productos están nombrados conforme a la tabla de distribución del rack. El registro fotográfico del día quedó como evidencia general en la ejecución del Rack 1 de esta misma visita.',
        NULL,
        'Cinco cuentalitros digitales en mal estado, se deben cambiar. Falta cuentalitros en carrete 2 (HD-50).',
        'Fuga por acople de pistola en carrete 3 (HD-10); llave de paso con fuga de aceite en carrete 7 (HD-30); línea de manguera con fuga de aceite en carrete 8 (HD-50).',
        'Carrete 8 (HD-50) fuera de servicio: falta la bomba de diafragma, faltan acoples y falta el filtro de succión. Bomba de diafragma del refrigerante (carrete 5) en mal estado. El tablero eléctrico mantiene encendidas las luces de advertencia de falla en los circuitos de bombas de: aceite XFD 60, MTHD 50, 15W-40 y HD 10W.',
        'Falta manilla de la llave de paso de la tubería de alimentación (carrete 5, refrigerante). Llave de paso con fuga de aceite en carrete 7.',
        'Falta el carrete completo del aceite XFD-60 (posición 1). Faltan frenos de carrera de manguera en carretes 5, 6 y 7. Falta cable antilatigazo en carrete 5.',
        'Faltan pistolas en carretes 6 (15W-40) y 7 (HD-30). Boquillas antigoteo faltantes en carretes 2 y 3.');
    PERFORM pg_temp.fn_req(v_ejec, 'Repuestos para recuperación del Rack 3 (Truck Shop 2)',
        'Se requieren para recuperar el estado operacional del Rack 3 del Truck Shop 2: carrete completo para el aceite XFD-60 (posición 1); bomba de diafragma, acoples y filtro de succión del carrete 8 (HD-50); reparación o reposición de la bomba de diafragma del refrigerante (carrete 5) y su manilla de llave de paso; 5 cuentalitros digitales; pistolas (carretes 6 y 7); boquillas antigoteo (carretes 2 y 3); frenos de carrera de manguera (carretes 5, 6 y 7); cable antilatigazo del carrete 5; y revisión del tablero eléctrico con alarmas de falla activas en 4 circuitos de bombas.');

    -- ── Verificación ────────────────────────────────────────────────────────
    SELECT count(*) INTO v_n
      FROM enex_ejecuciones e
      JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE e.fecha_ejecucion IN (DATE '2026-08-17', DATE '2026-08-20')
       AND i.nombre ILIKE 'Truck Shop Lomas%';
    IF v_n < 5 THEN RAISE EXCEPTION 'FALLO: hay % ejecuciones y deberían ser 5', v_n; END IF;

    SELECT count(*) INTO v_n
      FROM enex_ejecucion_items x
      JOIN enex_ejecuciones e ON e.id = x.ejecucion_id
     WHERE e.fecha_ejecucion IN (DATE '2026-08-17', DATE '2026-08-20');
    RAISE NOTICE 'MIG525 OK · 5 ejecuciones (2 del 17/08, 3 del 20/08) con % ítems y sus requerimientos', v_n;
END
$mig$;

COMMIT;
