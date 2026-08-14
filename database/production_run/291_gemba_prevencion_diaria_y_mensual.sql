-- ============================================================================
-- SICOM-ICEO | 291 — Prevención: caminata diaria + inspección planificada mensual
-- ============================================================================
-- El checklist de prevención era uno solo de 36 ítems, y con eso el
-- prevencionista quedaba obligado a elegir entre estar en terreno todos los días
-- o hacer la inspección completa. Son dos cosas distintas y se separan:
--
--   · GEMBA-PREV-DIA (diaria, 6 ítems) — OBSERVACIÓN DE CONDUCTA. Mirar una
--     tarea completa de principio a fin, hablar con quien la hace y corregir en
--     el momento. Es presencia, no auditoría: 10 minutos.
--   · GEMBA-PREV (mensual, 36 ítems) — INSPECCIÓN PLANIFICADA. Los 8 bloques
--     completos. Es el respaldo formal del programa preventivo, y por eso se
--     quiere entera y no en pedazos: aquí la exhaustividad SÍ es el punto.
--
-- Nota de diseño: el Jefe de Taller resolvió su recorrido diario con rotación
-- (MIG290) porque su checklist es de operación y se puede repartir. El de
-- prevención no se reparte: una inspección planificada a la que le falta un
-- bloque deja de servir como evidencia del programa. Por eso acá van dos
-- plantillas y no una rotativa.
--
-- ADITIVA e IDEMPOTENTE.
-- ============================================================================

-- ── 1. La inspección completa pasa a ser mensual y se llama por su nombre ────
UPDATE gemba_plantillas SET
  cadencia = 'mensual',
  nombre = 'Inspección planificada mensual — Prevención de Riesgos',
  descripcion = 'Inspección completa del taller: EPP, orden y aseo, máquinas, riesgo eléctrico, sustancias peligrosas, emergencias, ergonomía y comportamientos. Es el respaldo formal del programa preventivo, por eso va entera.'
WHERE codigo = 'GEMBA-PREV';


-- ── 2. La caminata diaria: conducta y riesgo crítico ────────────────────────
INSERT INTO gemba_plantillas (codigo, nombre, cargo, ambito, roles, cadencia, descripcion, secciones) VALUES
('GEMBA-PREV-DIA', 'Caminata diaria de seguridad — Prevención de Riesgos', 'prevencionista', 'ambos',
 ARRAY['prevencionista'], 'diaria',
 'Recorrido diario de 10 minutos: observar una tarea completa, conversar con quien la ejecuta y corregir en el momento. No reemplaza la inspección planificada mensual.',
 '[
  {"titulo": "Todos los días · Observación de conducta y riesgo crítico", "items": [
    "Se observó al menos una tarea en ejecución completa, de principio a fin.",
    "Los trabajadores de la tarea observada conocen sus riesgos y sus medidas de control.",
    "No se observaron actos inseguros (atajos, bromas, celular en operación); si los hubo, se corrigieron en el momento.",
    "Los trabajos de alto riesgo en curso tienen permiso vigente y su ART/AST aplicado.",
    "Se le preguntó a un trabajador qué necesita para trabajar más seguro y quedó registrado.",
    "No hubo condiciones de peligro grave e inminente; si las hubo, se detuvo la tarea de inmediato."
  ]}
 ]'::jsonb)
ON CONFLICT (codigo) DO NOTHING;

-- Se re-afirma en cada corrida (mismo criterio que MIG288 con el resto).
UPDATE gemba_plantillas SET roles = ARRAY['prevencionista'], cadencia = 'diaria'
 WHERE codigo = 'GEMBA-PREV-DIA'
   AND (roles IS DISTINCT FROM ARRAY['prevencionista'] OR cadencia IS DISTINCT FROM 'diaria');

NOTIFY pgrst, 'reload schema';


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE r RECORD; v_diarias INT;
BEGIN
    FOR r IN SELECT codigo, cadencia, roles,
                    (SELECT sum(jsonb_array_length(s->'items')) FROM jsonb_array_elements(secciones) s) AS items
               FROM gemba_plantillas WHERE activo ORDER BY cadencia, codigo LOOP
        RAISE NOTICE 'MIG291 — % | % | % ítems | roles=%', r.codigo, r.cadencia, r.items, r.roles;
    END LOOP;

    -- El prevencionista queda con dos checklists: uno diario y uno mensual.
    SELECT count(*) INTO v_diarias FROM gemba_plantillas
     WHERE activo AND 'prevencionista' = ANY(roles);
    IF v_diarias <> 2 THEN
        RAISE EXCEPTION 'FALLO — prevención debe tener 2 checklists (diario y mensual), tiene %', v_diarias;
    END IF;
    RAISE NOTICE 'MIG291 OK — prevención: caminata diaria (6) + inspección planificada mensual (36)';
END $$;
