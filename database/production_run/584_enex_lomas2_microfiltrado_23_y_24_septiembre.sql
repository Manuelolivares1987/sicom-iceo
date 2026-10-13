-- ============================================================================
-- SICOM-ICEO | 584 — Lomas 2 · Sala de microfiltrado: servicios del 23 y 24
--                    de septiembre de 2026 (respaldo desde registro WhatsApp)
-- ============================================================================
-- Manuel programó en el panel ENEX (faena LB_LUB) dos servicios de mantención
-- para «Truck Shop Lomas 2 - Microfiltrado»: 23/09 y 24/09. El trabajo se
-- hizo en terreno fuera de la app y el respaldo llegó por WhatsApp (carpeta
-- Desktop/LOMAS LUBRICANTES/lomas 2/sala microfiltrado/23.09 y 24.09):
--   · 23/09: 2 fotos + 2 videos (recorrido de la sala de 60 s y prueba de
--     bomba de diafragma de 6 s). Los videos no traen narración; se
--     incorporaron cuadros como fotos (registro/001..007).
--   · 24/09: 21 fotos (una repetida, se descartó) + 1 video de 29 s con el
--     estado final de la sala y el tablero (registro/021..024 son cuadros).
-- Lo que se registra es lo que muestran las imágenes; el técnico ejecutor
-- no venía identificado y queda pendiente (se completa al firmar, MIG276).
-- Mismo criterio que MIG293/294/525: estado 'ejecutada', pasa a 'cumplida'
-- cuando ESM firme la recepción conforme.
-- Las fotos ya están en storage (subidas 13-10-2026 por la sesión de Manuel):
--   evidencias-verificacion/enex/2026-09/23-lomas2-microfiltrado/{antes,despues,registro}
--   evidencias-verificacion/enex/2026-09/24-lomas2-microfiltrado/registro
-- ADITIVA e IDEMPOTENTE.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.fn_url(p_dia TEXT, p_sub TEXT, VARIADIC p_n INT[]) RETURNS JSONB AS $$
    SELECT COALESCE(jsonb_agg(
        'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-09/'
        || p_dia || '-lomas2-microfiltrado/' || p_sub || '/' || lpad(n::text, 3, '0') || '.jpg' ORDER BY ord), '[]'::jsonb)
      FROM unnest(p_n) WITH ORDINALITY AS t(n, ord);
$$ LANGUAGE sql;

-- ── ejecución sobre la programación existente (instalación + fecha) ────────
CREATE OR REPLACE FUNCTION pg_temp.fn_ejec(p_fecha DATE, p_obs TEXT, p_evid JSONB) RETURNS UUID AS $$
DECLARE v_inst UUID; v_prog UUID; v_pauta UUID; v_ejec UUID; v_evid TEXT[];
BEGIN
    SELECT id INTO v_inst FROM enex_instalaciones WHERE nombre = 'Truck Shop Lomas 2 - Microfiltrado' AND activo;
    IF v_inst IS NULL THEN RAISE EXCEPTION 'No existe la instalación Truck Shop Lomas 2 - Microfiltrado'; END IF;
    SELECT id INTO v_prog FROM enex_programaciones
     WHERE instalacion_id = v_inst AND fecha_programada = p_fecha AND tipo_servicio = 'mantencion'
     ORDER BY created_at LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'No hay programación de mantención del % para el microfiltrado de Lomas 2', p_fecha; END IF;
    SELECT id INTO v_ejec FROM enex_ejecuciones WHERE programacion_id = v_prog LIMIT 1;
    IF v_ejec IS NOT NULL THEN
        RAISE NOTICE '% — ya tenía ejecución %, no se toca', p_fecha, v_ejec;
        RETURN NULL;
    END IF;
    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';
    SELECT ARRAY(SELECT jsonb_array_elements_text(p_evid)) INTO v_evid;
    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion, observacion, evidencia_urls)
    VALUES (v_prog, v_pauta, 'ejecutada', p_fecha, p_obs, NULLIF(v_evid, '{}'::text[]))
    RETURNING id INTO v_ejec;
    RAISE NOTICE '% — ejecución % creada sobre programación %', p_fecha, v_ejec, v_prog;
    RETURN v_ejec;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.fn_item(p_ejec UUID, p_cod TEXT, p_desc TEXT, p_res TEXT, p_obs TEXT,
                                          p_antes JSONB DEFAULT '[]'::jsonb, p_desp JSONB DEFAULT '[]'::jsonb) RETURNS VOID AS $$
DECLARE v_item UUID;
BEGIN
    SELECT pi.id INTO v_item FROM enex_pauta_items pi JOIN enex_pautas p ON p.id = pi.pauta_id
     WHERE p.codigo = 'PAUTA-LUB' AND pi.codigo = p_cod AND pi.descripcion = p_desc AND pi.activo LIMIT 1;
    IF v_item IS NULL THEN RAISE EXCEPTION 'No existe el ítem % (%)', p_cod, p_desc; END IF;
    INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, observacion, fotos_antes, fotos_despues)
    VALUES (p_ejec, v_item, p_res, p_obs, p_antes, p_desp);
END $$ LANGUAGE plpgsql;

DO $mig$
DECLARE v_ejec UUID; v_n INT;
BEGIN
    -- ════ 23/09 · Inspección de la sala + reemplazo de la unidad FRL ════
    v_ejec := pg_temp.fn_ejec(DATE '2026-09-23',
        'Servicio registrado como respaldo a partir del registro de terreno enviado por WhatsApp (2 fotografías y 2 videos; los cuadros de los videos se incorporaron como fotografías del registro). Recorrido de inspección de la sala de microfiltrado del Truck Shop Lomas 2 (unidades de bombeo 1, 2 y 3, pretil, rejillas y líneas) y reemplazo de la unidad FRL de aire comprimido de la bomba de diafragma, con prueba de funcionamiento posterior. Técnico ejecutor pendiente de identificar.',
        pg_temp.fn_url('23', 'registro', 1, 3));
    IF v_ejec IS NOT NULL THEN
        PERFORM pg_temp.fn_item(v_ejec, 'DS.MOTIVO', 'Motivo del llamado', NULL,
            'Inspección de la sala de microfiltrado y reemplazo de la unidad FRL (filtro-regulador) de aire de la bomba de diafragma.');
        PERFORM pg_temp.fn_item(v_ejec, '2.4', 'Inspección de manómetros de presión', 'ok',
            'Unidad FRL de aire comprimido de la bomba de diafragma con el manómetro sin lectura y el cuerpo con suciedad y aceite: se retiró la unidad y se instaló una de reemplazo, que quedó con lectura de presión de regulación en el manómetro.',
            pg_temp.fn_url('23', 'antes', 1), pg_temp.fn_url('23', 'despues', 1));
        PERFORM pg_temp.fn_item(v_ejec, '3.2', 'Mantención bombas de diafragma 2"', 'ok',
            'Prueba de funcionamiento de la bomba de diafragma tras el reemplazo de la unidad FRL de su línea de aire: la bomba quedó operativa (registro en video).',
            '[]'::jsonb, pg_temp.fn_url('23', 'registro', 7));
        PERFORM pg_temp.fn_item(v_ejec, '2.9', 'Inspección de fugas', 'no_ok',
            'Residuos de aceite y suciedad acumulados en el pretil y las bandejas bajo las unidades de bombeo; en el recorrido no se identifica un punto de fuga activo. Se programó la limpieza profunda de la sala para el 24/09.',
            pg_temp.fn_url('23', 'registro', 4, 5, 6));
        PERFORM pg_temp.fn_item(v_ejec, '1.4', 'Revisión y limpieza de piso interior pretil', 'no_ok',
            'Pretil con residuos de aceite, suciedad y pintura desprendida; rejillas con material acumulado. Limpieza programada para el día siguiente (24/09).',
            pg_temp.fn_url('23', 'registro', 2, 4, 5));
    END IF;

    -- ════ 24/09 · Limpieza profunda de la sala de microfiltrado ════
    v_ejec := pg_temp.fn_ejec(DATE '2026-09-24',
        'Servicio registrado como respaldo a partir del registro de terreno enviado por WhatsApp (20 fotografías y 1 video; los cuadros del video, con el estado final de la sala y el tablero, se incorporaron como fotografías del registro). Limpieza profunda de la sala de microfiltrado del Truck Shop Lomas 2 programada tras la inspección del 23/09: pretil, rejillas, unidades de filtrado, bombas y líneas, con retiro de residuos en sacos. Trabajo ejecutado por tres personas con traje de protección. El registro fotográfico general muestra el trabajo en ejecución y el tablero eléctrico de la sala. Técnico ejecutor pendiente de identificar.',
        pg_temp.fn_url('24', 'registro', 5, 6, 9, 11, 12, 17, 24));
    IF v_ejec IS NOT NULL THEN
        PERFORM pg_temp.fn_item(v_ejec, 'DS.MOTIVO', 'Motivo del llamado', NULL,
            'Limpieza profunda de la sala de microfiltrado: pretil, rejillas, unidades de filtrado, bombas y líneas.');
        PERFORM pg_temp.fn_item(v_ejec, '1.1', 'Limpieza exterior de líneas de lubricantes', 'ok',
            'Limpieza exterior de las líneas, válvulas y rejillas del recorrido de la sala (líneas de aceite usado y refrigerante usado).',
            pg_temp.fn_url('24', 'registro', 4, 8), pg_temp.fn_url('24', 'registro', 16, 20, 21));
        PERFORM pg_temp.fn_item(v_ejec, '1.2', 'Limpieza exterior de equipos de filtrado', 'ok',
            'Limpieza exterior de las unidades de filtrado y de los conjuntos motor-bomba de las unidades 1, 2 y 3.',
            pg_temp.fn_url('24', 'registro', 1, 7, 10), pg_temp.fn_url('24', 'registro', 13, 14, 15, 18, 22, 23));
        PERFORM pg_temp.fn_item(v_ejec, '1.4', 'Revisión y limpieza de piso interior pretil', 'ok',
            'Retiro de residuos de aceite y suciedad del piso interior del pretil y de las bandejas bajo las bombas; material retirado en sacos. El pretil mantiene pintura desprendida.',
            pg_temp.fn_url('24', 'registro', 2, 3), pg_temp.fn_url('24', 'registro', 19));
        IF NOT EXISTS (SELECT 1 FROM enex_requerimientos WHERE ejecucion_id = v_ejec AND titulo = 'Pintado del pretil') THEN
            INSERT INTO enex_requerimientos (ejecucion_id, tipo, prioridad, titulo, descripcion, orden)
            VALUES (v_ejec, 'comentario', 'media', 'Pintado del pretil',
                'El pretil de la sala presenta pintura desprendida. Se reitera la propuesta planteada el 10/08 de pintar el pretil para facilitar la inspección de fugas.', 1);
        END IF;
    END IF;

    -- ── Verificación ────────────────────────────────────────────────────────
    SELECT count(*) INTO v_n
      FROM enex_ejecuciones e JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE i.nombre = 'Truck Shop Lomas 2 - Microfiltrado' AND e.fecha_ejecucion IN (DATE '2026-09-23', DATE '2026-09-24');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FALLO: hay % ejecuciones del microfiltrado en sept y deberían ser 2', v_n; END IF;
    SELECT count(*) INTO v_n FROM enex_ejecucion_items x JOIN enex_ejecuciones e ON e.id = x.ejecucion_id
     WHERE e.fecha_ejecucion IN (DATE '2026-09-23', DATE '2026-09-24');
    RAISE NOTICE 'MIG584 OK · 2 ejecuciones (23/09 y 24/09) con % ítems', v_n;
END
$mig$;

COMMIT;
