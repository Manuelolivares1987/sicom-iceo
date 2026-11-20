-- ============================================================================
-- MIG719 — HHWB-44: kilometraje con un dígito de más (19-11-2026)
-- ----------------------------------------------------------------------------
-- En el taller de Coquimbo se tipeó el odómetro del HHWB-44 con un «1» de más
-- desde el 05-10: 1.198.080 / 1.198.090 / 1.198.100 km. Quedó en la ficha, en
-- 3 OTs, 4 checklists, los planes SM2/SM3 y el texto de 3 informes técnicos.
--
-- El valor real NO es quitar el 1 (198.100): el GPS (Radicom) muestra que el
-- camión casi no se movió en el taller (196.797,6 km el 01-10 → 196.800,4 el
-- 12-11). El checklist del 01-10 anotó 197.080 en el tablero con el GPS en
-- 196.797,56 → el tablero va 282,44 km por delante del GPS. Cada valor se
-- recalcula con el GPS de su fecha + 282,44:
--   05-10 (OT-202606-00009)            1.198.080 → 197.081
--   14-10 (OT-202610-00004)            1.198.090 → 197.082
--   12-11 (OT-202610-00003, SM2+SM3)   1.198.100 → 197.083
--   ficha hoy (GPS 196.901,94 al 17-11) 1.198.100 → 197.184
-- Solo se tocan filas que tienen exactamente el valor malo; lo protegido por
-- trigger (OT cerrada definitivamente) se informa y NO se modifica. La nota del
-- checklist del 20-10 («medidor confirmado a mano…») se deja: es bitácora.
-- Pedido por Manuel 19-11.
-- ============================================================================

DO $$
DECLARE
    v_id UUID := (SELECT id FROM public.activos WHERE patente = 'HHWB-44');
    r RECORD;
    n INT;
BEGIN
    IF v_id IS NULL THEN RAISE EXCEPTION 'No existe HHWB-44'; END IF;

    UPDATE public.activos SET kilometraje_actual = 197184
     WHERE id = v_id AND kilometraje_actual = 1198100;
    GET DIAGNOSTICS n = ROW_COUNT; RAISE NOTICE 'activos: %', n;

    UPDATE public.planes_mantenimiento SET ultima_ejecucion_km = 197083
     WHERE activo_id = v_id AND ultima_ejecucion_km = 1198100;
    GET DIAGNOSTICS n = ROW_COUNT; RAISE NOTICE 'planes_mantenimiento: %', n;

    -- Fila por fila: una OT cerrada definitivamente está protegida por trigger
    -- (auditoría). No se salta: se informa y se deja como está.
    FOR r IN SELECT id, folio, km_al_cierre FROM public.ordenes_trabajo
              WHERE activo_id = v_id AND km_al_cierre IN (1198080, 1198090, 1198100) LOOP
        BEGIN
            UPDATE public.ordenes_trabajo
               SET km_al_cierre = CASE km_al_cierre WHEN 1198080 THEN 197081 WHEN 1198090 THEN 197082 ELSE 197083 END
             WHERE id = r.id;
            RAISE NOTICE 'OT % corregida', r.folio;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'OT % NO corregida (protegida): %', r.folio, SQLERRM;
        END;
    END LOOP;

    FOR r IN SELECT id, created_at::date AS f, kilometraje FROM public.checklist_v2_instance
              WHERE activo_id = v_id AND kilometraje IN (1198080, 1198090, 1198100) LOOP
        BEGIN
            UPDATE public.checklist_v2_instance
               SET kilometraje = CASE kilometraje WHEN 1198080 THEN 197081 WHEN 1198090 THEN 197082 ELSE 197083 END
             WHERE id = r.id;
            RAISE NOTICE 'checklist % corregido', r.f;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'checklist % NO corregido (protegido): %', r.f, SQLERRM;
        END;
    END LOOP;

    FOR r IN SELECT id, folio FROM public.informes_intervencion
              WHERE activo_id = v_id AND trabajo_realizado_resumen ~ '119808[0-9]|119809[0-9]|119810[0-9]' LOOP
        BEGIN
            UPDATE public.informes_intervencion
               SET trabajo_realizado_resumen = replace(replace(replace(trabajo_realizado_resumen,
                       '1198080', '197081'), '1198090', '197082'), '1198100', '197083')
             WHERE id = r.id;
            RAISE NOTICE 'informe % corregido', r.folio;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'informe % NO corregido (protegido): %', r.folio, SQLERRM;
        END;
    END LOOP;
END $$;

SELECT 'activo' AS donde, kilometraje_actual::text AS km FROM public.activos WHERE patente = 'HHWB-44'
UNION ALL
SELECT o.folio, o.km_al_cierre::text FROM public.ordenes_trabajo o
 WHERE o.activo_id = (SELECT id FROM public.activos WHERE patente = 'HHWB-44') AND o.km_al_cierre IS NOT NULL
UNION ALL
SELECT p.nombre, p.ultima_ejecucion_km::text FROM public.planes_mantenimiento p
 WHERE p.activo_id = (SELECT id FROM public.activos WHERE patente = 'HHWB-44') AND p.ultima_ejecucion_km IS NOT NULL;
