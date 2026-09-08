-- ============================================================================
-- SICOM-ICEO | 294 — Lomas 1: requerimientos al mandante y hallazgos reales
-- ============================================================================
-- Los «Comentarios y mejoras» de cada jornada traían el texto en cuadros de
-- texto de Word (no en el cuerpo), así que en la primera lectura parecieron
-- documentos con puras fotos. Al leerlos aparecen dos cosas:
--
--   1. REQUERIMIENTOS AL MANDANTE — lo que se necesita y no se resuelve en la
--      visita. Van al bloque que MIG287 imprime en el informe que firma ESM.
--   2. HALLAZGOS que corrigen la carga de MIG293: tres ítems que se habían
--      marcado conformes NO lo están, y uno no se pudo verificar.
--
-- Correcciones del 12/08 (ambos racks):
--   · 5.2 Inspección de fugas          ok → NO APLICA. No se pudo verificar:
--     exige iniciar el rack, con mecánico lubricador y autorizaciones.
--   · 5.1 Inspección estaciones carrete ok → NO CONFORME (contador análogo malo)
--   · 5.7 Inspección estado de carretes ok → NO CONFORME (3 carretes no traban)
--   · 5.8 Inspección estado de pistolas ok → NO CONFORME (faltan 2 pistolas)
--
-- El texto se transcribe fiel; solo se corrigió ortografía y separación de
-- palabras («interperie» → intemperie, «señaleticaMantenimiento» → dos frases),
-- porque el informe lo lee el mandante.
--
-- Los hallazgos del 12 que no distinguen rack se rotulan «Racks 1 y 2» en los
-- dos informes, para que no se lean como defectos duplicados.
--
-- ADITIVA e IDEMPOTENTE.
-- ============================================================================

-- ── 1. Corrección de los ítems del 12/08 en ambos racks ─────────────────────
DO $$
DECLARE v_ejec UUID; v_inst TEXT; v_n INT := 0;
BEGIN
    FOREACH v_inst IN ARRAY ARRAY['Truck Shop Lomas 1 - Rack 1', 'Truck Shop Lomas 1 - Rack 2'] LOOP
        SELECT e.id INTO v_ejec
          FROM enex_ejecuciones e
          JOIN enex_programaciones p ON p.id = e.programacion_id
          JOIN enex_instalaciones i ON i.id = p.instalacion_id
         WHERE i.nombre = v_inst AND e.fecha_ejecucion = DATE '2026-08-12';
        IF v_ejec IS NULL THEN RAISE EXCEPTION 'No existe la ejecución de %', v_inst; END IF;

        -- No verificable: el rack estaba detenido.
        UPDATE enex_ejecucion_items x SET resultado = 'na',
               observacion = 'No verificable en esta visita: la detección de fugas exige iniciar el '
                             'funcionamiento del rack, lo que requiere coordinación con un mecánico '
                             'lubricador y las autorizaciones correspondientes.'
          FROM enex_pauta_items pi
         WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v_ejec
           AND pi.codigo = '5.2' AND pi.descripcion = 'Inspección de fugas';
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n = 0 THEN RAISE EXCEPTION 'No se encontró el ítem 5.2 en %', v_inst; END IF;

        UPDATE enex_ejecucion_items x SET resultado = 'no_ok',
               observacion = 'Contador análogo en mal estado (1 unidad).'
          FROM enex_pauta_items pi
         WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v_ejec
           AND pi.codigo = '5.1' AND pi.descripcion = 'Inspección estaciones de carrete';

        UPDATE enex_ejecucion_items x SET resultado = 'no_ok',
               observacion = 'Tres carretes con problemas mecánicos: el carrete no traba.'
          FROM enex_pauta_items pi
         WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v_ejec
           AND pi.codigo = '5.7' AND pi.descripcion = 'Inspección estado de carretes';

        UPDATE enex_ejecucion_items x SET resultado = 'no_ok',
               observacion = 'Se requiere el cambio de 2 pistolas.'
          FROM enex_pauta_items pi
         WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = v_ejec
           AND pi.codigo = '5.8' AND pi.descripcion = 'Inspección estado de pistolas';

        -- El informe guardado ya no dice lo mismo: se regenera.
        UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v_ejec;
        RAISE NOTICE 'Corregidos los ítems de %', v_inst;
    END LOOP;
END $$;


-- ── 2. Requerimientos al mandante ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.fn_req(
    p_inst TEXT, p_fecha DATE, p_tipo TEXT, p_prioridad TEXT, p_titulo TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_ejec UUID; v_orden INT;
BEGIN
    SELECT e.id INTO v_ejec
      FROM enex_ejecuciones e
      JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = p_inst AND e.fecha_ejecucion = p_fecha;
    IF v_ejec IS NULL THEN RAISE EXCEPTION 'No existe la ejecución de % (%)', p_inst, p_fecha; END IF;

    -- Idempotente: el mismo requerimiento no se carga dos veces.
    IF EXISTS (SELECT 1 FROM enex_requerimientos WHERE ejecucion_id = v_ejec AND descripcion = p_desc) THEN
        RETURN;
    END IF;

    SELECT COALESCE(MAX(orden), 0) + 1 INTO v_orden FROM enex_requerimientos WHERE ejecucion_id = v_ejec;
    INSERT INTO enex_requerimientos (ejecucion_id, tipo, prioridad, titulo, descripcion, orden)
    VALUES (v_ejec, p_tipo, p_prioridad, p_titulo, p_desc, v_orden);

    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v_ejec;
END $$;


-- ── 11/08 · Microfiltrado ───────────────────────────────────────────────────
DO $$
DECLARE I TEXT := 'Truck Shop Lomas 1 - Microfiltrado'; F DATE := DATE '2026-08-11';
BEGIN
    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'alta', 'Reposición y reparación de bombas',
        'Bombas a la intemperie, falta de bombas y una bomba con filtración de aceite. Se solicita '
        'la reposición de la bomba, más su reparación y mantenimiento.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'alta', 'Tablero eléctrico fuera de norma',
        'Se requiere el mantenimiento del tablero y llevarlo a norma.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'alta', 'Extintor portátil fuera de norma',
        'El extintor portátil de la instalación se encuentra fuera de norma.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'media', 'Cambio de gabinete de bombas',
        'Cambio del gabinete, más la reparación y mantención de las bombas.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'media', 'Infraestructura de la sala',
        'Cambio de puerta de acceso, iluminación interior de la dependencia, limpieza y pintado de '
        'la sala, y señalética. Mantenimiento y recuperación del tablero eléctrico: se requiere '
        'definir quién bloquea, a quién pertenecen esos tableros y facilitar el acceso a los planos '
        'eléctricos. Mantenimiento de bomba y motor eléctrico.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'media', 'Sala de bombas techada',
        'Situación actual: bombas expuestas a la intemperie, sucias y sin rotulación. Se propone '
        'habilitar una sala de bombas techada.');

    PERFORM pg_temp.fn_req(I, F, 'requerimiento', 'media', 'Limpieza profunda y pintado del pretil',
        'Limpieza profunda del pretil (4 unidades) y pintado. Quedan por confirmar las unidades de '
        'bombeo con mangueras visibles.');

    RAISE NOTICE '11/08 Microfiltrado — 7 requerimientos';
END $$;


-- ── 12/08 · Rack 1 y Rack 2 ─────────────────────────────────────────────────
DO $$
DECLARE v_inst TEXT; F DATE := DATE '2026-08-12'; v_rack TEXT;
BEGIN
    FOREACH v_inst IN ARRAY ARRAY['Truck Shop Lomas 1 - Rack 1', 'Truck Shop Lomas 1 - Rack 2'] LOOP
        v_rack := CASE WHEN v_inst LIKE '%Rack 1' THEN 'Rack 1' ELSE 'Rack 2' END;

        -- Hallazgos que el registro de terreno no separa por rack: se rotulan
        -- como conjuntos para que no se lean como defectos duplicados.
        PERFORM pg_temp.fn_req(v_inst, F, 'requerimiento', 'alta',
            'Racks 1 y 2 — Carretes que no traban',
            'Tres carretes presentan problemas mecánicos: el carrete no traba. Hallazgo del '
            'conjunto de los racks 1 y 2, no de cada uno por separado.');

        PERFORM pg_temp.fn_req(v_inst, F, 'requerimiento', 'alta',
            'Racks 1 y 2 — Cambio de pistolas',
            'Se necesita el cambio de 2 pistolas. Hallazgo del conjunto de los racks 1 y 2, no de '
            'cada uno por separado.');

        PERFORM pg_temp.fn_req(v_inst, F, 'requerimiento', 'media',
            'Racks 1 y 2 — Coordinación para detectar fugas',
            'Para la detección de fugas se debe iniciar el funcionamiento del rack. Requiere '
            'coordinar un mecánico lubricador y gestionar las autorizaciones correspondientes. '
            'Mientras eso no ocurra, la inspección de fugas queda como no verificable.');

        PERFORM pg_temp.fn_req(v_inst, F, 'requerimiento', 'media',
            v_rack || ' — Contador análogo en mal estado',
            'Se detectó 1 contador análogo en mal estado en el ' || v_rack || '. Solución propuesta '
            'para la instalación: 8 contadores por rack, 16 contadores en total.');

        RAISE NOTICE '12/08 % — 4 requerimientos', v_inst;
    END LOOP;
END $$;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT i.nombre, e.fecha_ejecucion,
                    (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id=e.id AND x.resultado='ok') AS ok,
                    (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id=e.id AND x.resultado='no_ok') AS no_ok,
                    (SELECT count(*) FROM enex_ejecucion_items x WHERE x.ejecucion_id=e.id AND x.resultado='na') AS na,
                    (SELECT count(*) FROM enex_requerimientos q WHERE q.ejecucion_id=e.id) AS reqs,
                    e.informe_pdf_url IS NULL AS pdf_por_generar
               FROM enex_ejecuciones e
               JOIN enex_programaciones p ON p.id = e.programacion_id
               JOIN enex_instalaciones i ON i.id = p.instalacion_id
              WHERE e.fecha_ejecucion IN (DATE '2026-08-11', DATE '2026-08-12')
              ORDER BY e.fecha_ejecucion, i.nombre LOOP
        RAISE NOTICE '% | % | conformes=% no conformes=% n/a=% | % requerimientos | pdf por generar=%',
            r.fecha_ejecucion, r.nombre, r.ok, r.no_ok, r.na, r.reqs, r.pdf_por_generar;
    END LOOP;
END $$;
