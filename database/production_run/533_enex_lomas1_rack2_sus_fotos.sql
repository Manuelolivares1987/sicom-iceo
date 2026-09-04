-- ============================================================================
-- SICOM-ICEO | 533 — Lomas 1 Rack 2: sus fotos, sin duplicar con el Rack 1
-- ============================================================================
-- Manuel: el PDF del Rack 2 del 17/08 salió SIN fotos. MIG532 le había
-- asignado todo el registro del día al Rack 1 (los dos racks comparten
-- galpón y las fotos no traen rótulo de rack).
--
-- Reparto: las fotos cuyo contenido calza con las novedades DEL RACK 2 se
-- mueven a sus ítems — y salen de los ítems del Rack 1, para que el mismo
-- «antes» no aparezca en dos informes que firma el mandante:
--   · manguera cortada sin pistola (016) → R2 5.7 (carrete 2 «fuera de
--     servicio, falta pistola»)
--   · cable antilatigazo cortado (011)   → R2 5.7 (cables defectuosos)
--   · estación con cuentalitros y pistola colgando (014) → R2 5.1
--     (cuentalitros desconectado/defectuosos)
--   · pistola deteriorada (004) y pistolas con resortes (006) → R2 5.8
-- IDEMPOTENTE por reemplazo.
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
    SELECT COALESCE(jsonb_agg(p_base || lpad(n::text, 3, '0') || '.jpg'), '[]'::jsonb)
      INTO v_urls FROM unnest(p_nums) n;
    UPDATE enex_ejecucion_items x SET fotos_antes = v_urls
      FROM enex_pauta_items pi JOIN enex_pautas p ON p.id = pi.pauta_id
     WHERE pi.id = x.pauta_item_id AND x.ejecucion_id = p_ejec
       AND p.codigo = 'PAUTA-LUB' AND pi.codigo = p_cod AND pi.descripcion = p_desc;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN RAISE EXCEPTION 'No encontré el ítem % (%)', p_cod, p_desc; END IF;
END $$ LANGUAGE plpgsql;

DO $mig$
DECLARE
    v1 UUID; v2 UUID;
    b17 TEXT := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/17-lomas1-racks/registro/';
BEGIN
    v1 := pg_temp.fn_ejec('Truck Shop Lomas 1 - Rack 1', DATE '2026-08-17');
    v2 := pg_temp.fn_ejec('Truck Shop Lomas 1 - Rack 2', DATE '2026-08-17');

    -- Rack 1 conserva las fotos que calzan con SUS novedades (sin 4,6,11,14,16).
    PERFORM pg_temp.fn_fotos(v1, '5.1', 'Inspección estaciones de carrete', b17, ARRAY[3,8,10,13]);
    PERFORM pg_temp.fn_fotos(v1, '5.7', 'Inspección estado de carretes',     b17, ARRAY[7,17]);
    PERFORM pg_temp.fn_fotos(v1, '5.8', 'Inspección estado de pistolas',     b17, ARRAY[2,5,15,20]);

    -- Rack 2 recibe las suyas.
    PERFORM pg_temp.fn_fotos(v2, '5.1', 'Inspección estaciones de carrete', b17, ARRAY[14]);
    PERFORM pg_temp.fn_fotos(v2, '5.7', 'Inspección estado de carretes',     b17, ARRAY[11,16]);
    PERFORM pg_temp.fn_fotos(v2, '5.8', 'Inspección estado de pistolas',     b17, ARRAY[4,6]);

    UPDATE enex_ejecuciones SET informe_pdf_url = NULL,
           observacion = replace(observacion,
               'El registro fotográfico del día quedó como evidencia general en la ejecución del Rack 1 de esta misma visita.',
               'Las fotos del día compatibles con las novedades de este rack quedaron asignadas a sus ítems (MIG533).')
     WHERE id = v2;
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v1;

    -- ── Verificación: R2 con fotos y ninguna foto repetida entre R1 y R2 ────
    IF (SELECT count(*) FROM enex_ejecucion_items x
         WHERE x.ejecucion_id = v2
           AND jsonb_array_length(COALESCE(x.fotos_antes,'[]'::jsonb)) > 0) < 3 THEN
        RAISE EXCEPTION 'FALLO: el Rack 2 sigue sin fotos en sus ítems';
    END IF;
    IF EXISTS (
        SELECT u FROM (
            SELECT jsonb_array_elements_text(COALESCE(x.fotos_antes,'[]'::jsonb)) AS u
              FROM enex_ejecucion_items x WHERE x.ejecucion_id = v1) a
        INTERSECT
        SELECT u FROM (
            SELECT jsonb_array_elements_text(COALESCE(x.fotos_antes,'[]'::jsonb)) AS u
              FROM enex_ejecucion_items x WHERE x.ejecucion_id = v2) b
    ) THEN
        RAISE EXCEPTION 'FALLO: hay fotos repetidas entre Rack 1 y Rack 2';
    END IF;
    RAISE NOTICE 'MIG533 OK · Rack 2 con sus fotos (5) y Rack 1 con las suyas (13), sin repetidas';
END
$mig$;

COMMIT;
