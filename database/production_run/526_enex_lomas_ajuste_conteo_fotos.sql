-- ============================================================================
-- SICOM-ICEO | 526 — Lomas 17/20-08: el conteo real de fotos era 22 + 36
-- ============================================================================
-- MIG525 referenció 23 fotos para el 17/08 y 35 para el 20/08; la subida real
-- dejó 22 y 36 (una foto contada en el lote equivocado). Se ajustan los
-- arrays de evidencia para que el informe no muestre una foto rota ni se
-- pierda la 036 del 20/08.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE v_base TEXT := 'https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-08/';
        v_n INT;
BEGIN
    UPDATE enex_ejecuciones e
       SET evidencia_urls = ARRAY(SELECT v_base || '17-lomas1-racks/registro/' || lpad(g::text,3,'0') || '.jpg' FROM generate_series(1,22) g)
      FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE p.id = e.programacion_id AND i.nombre = 'Truck Shop Lomas 1 - Rack 1' AND i.activo
       AND e.fecha_ejecucion = DATE '2026-08-17';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: ejecución del 17/08 no encontrada (%)', v_n; END IF;

    UPDATE enex_ejecuciones e
       SET evidencia_urls = ARRAY(SELECT v_base || '20-lomas2-racks/registro/' || lpad(g::text,3,'0') || '.jpg' FROM generate_series(1,36) g)
      FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id
     WHERE p.id = e.programacion_id AND i.nombre = 'Truck Shop Lomas 2 - Rack 1' AND i.activo
       AND e.fecha_ejecucion = DATE '2026-08-20';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: ejecución del 20/08 no encontrada (%)', v_n; END IF;

    RAISE NOTICE 'MIG526 OK · evidencias: 22 fotos (17/08) y 36 fotos (20/08)';
END
$mig$;

COMMIT;
