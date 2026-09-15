-- ============================================================================
-- MIG560 · Prevención: los reportes de las dos Lomas, como los pide el mandante
-- ============================================================================
-- Manuel (2026-09-14): en términos de reportes es clave que queden así:
--   · Lomas Bayas — Combustible ... E-200, GCOM, Anexo 10.2
--   · Lomas Bayas — Lubricantes ... E-200, GCOM, Anexo 10.2 y Actividades HS
--
-- Estado previo (MIG549/550): Combustible tenía E-200 + Actividades HS + GCOM
-- (las Actividades HS NO van ahí) y Lubricantes solo E-200 + Anexo 10.2.
--
-- Convergente y re-ejecutable:
--   1. Combustible: se le quita «Actividades HS — SAFEWORK» (DELETE si nunca
--      se marcó una entrega; si ya hay envíos, queda inactivo para no perder
--      historia) y se le agrega el Anexo 10.2.
--   2. Lubricantes: se le agregan GCOM y «Actividades HS — SAFEWORK».
--      OJO: el nombre del ítem HS debe ser EXACTAMENTE «Actividades HS —
--      SAFEWORK» — el generador ppt_evidencias filtra los registros por ese
--      nombre (TIPOS_PPT_POR_ITEM en prevencion-generar.ts).
-- Los chips de tipos de actividad (MIG552) no se tocan: ambas Lomas siguen
-- ofreciendo HS_SAFEWORK/CAPACITACION/CHARLA/GCOM/INSPECCION/ANEXO102.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_comb UUID;
    v_lub  UUID;
BEGIN
    SELECT id INTO v_comb FROM faenas WHERE codigo = 'FAE-LOMASBAYAS';
    SELECT id INTO v_lub  FROM faenas WHERE codigo = 'FAE-LOMASBAYAS-LUB';
    IF v_comb IS NULL OR v_lub IS NULL THEN
        RAISE EXCEPTION 'Falta una de las faenas Lomas (comb=%, lub=%)', v_comb, v_lub;
    END IF;

    -- ── 1a. Combustible: fuera «Actividades HS — SAFEWORK» ──────────────────
    DELETE FROM prevencion_reportabilidad_items i
     WHERE i.faena_id = v_comb
       AND i.nombre = 'Actividades HS — SAFEWORK'
       AND NOT EXISTS (SELECT 1 FROM prevencion_reportabilidad_envios e
                        WHERE e.item_id = i.id);
    UPDATE prevencion_reportabilidad_items
       SET activo = false
     WHERE faena_id = v_comb AND nombre = 'Actividades HS — SAFEWORK';

    -- ── 1b. Combustible: entra el Anexo 10.2 ────────────────────────────────
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, activo, orden, plantilla)
    SELECT v_comb,
           'PPT Lubricantes y Combustible — Anexo 10.2',
           'Presentación con evidencias de terreno y documentación de gestión.',
           'Evidencias de terreno + gestión preventiva',
           'Mandante Lomas Bayas', 5, true, 20, 'anexo_102'
    WHERE NOT EXISTS (SELECT 1 FROM prevencion_reportabilidad_items
                       WHERE faena_id = v_comb AND plantilla = 'anexo_102');

    -- ── 2a. Lubricantes: entra el GCOM ──────────────────────────────────────
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, activo, orden, plantilla)
    SELECT v_lub,
           'Seguimiento programa GCOM',
           'Respaldo de los GCOM mensuales de cada supervisor.',
           'Registros GCOM cargados por supervisores',
           'Plataforma GCOM', 5, true, 40, NULL
    WHERE NOT EXISTS (SELECT 1 FROM prevencion_reportabilidad_items
                       WHERE faena_id = v_lub AND nombre = 'Seguimiento programa GCOM');

    -- ── 2b. Lubricantes: entran las Actividades HS ──────────────────────────
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, activo, orden, plantilla)
    SELECT v_lub,
           'Actividades HS — SAFEWORK',
           'Evidencias de actividades HS ejecutadas en terreno.',
           'Registros HS_SAFEWORK cargados por supervisores',
           'Plataforma SAFEWORK', 5, true, 30, 'ppt_evidencias'
    WHERE NOT EXISTS (SELECT 1 FROM prevencion_reportabilidad_items
                       WHERE faena_id = v_lub AND nombre = 'Actividades HS — SAFEWORK');
END $mig$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN — debe quedar:
--   Combustible: E-200 (10), Anexo 10.2 (20), GCOM (40)
--   Lubricantes: E-200 (5), Anexo 10.2 (20), Actividades HS (30), GCOM (40)
-- ============================================================================
SELECT f.codigo, i.orden, i.nombre, i.plantilla, i.activo
FROM prevencion_reportabilidad_items i
JOIN faenas f ON f.id = i.faena_id
WHERE f.codigo LIKE 'FAE-LOMASBAYAS%' AND i.activo
ORDER BY f.codigo, i.orden;
