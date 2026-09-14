-- ============================================================================
-- MIG552 · Prevención: tipos de actividad POR FAENA (catálogo del mandante)
-- ============================================================================
-- Manuel (2026-09-14): cada faena muestra SOLO las herramientas que su
-- mandante pide:
--   · Centinela — Combustible ...... Charla, Capacitación, Campaña, PGR
--   · Spence — Combustible ......... Actividad miscelánea (no piden info
--                                    habitualmente; que igual se pueda subir)
--   · Lomas Bayas — Combustible .... HS-SAFEWORK, Capacitación, Charla,
--     y Lomas Bayas — Lubricantes    GCOM, Inspección
--   · CMP — Romeral ................ RIT, VAT, VCT, Capacitación, Check List EPF
--   · Franke ....................... Inspección, Capacitación, Desviación,
--                                    Control PIAPE, Charla de Seguridad
--
--   1. Tipos nuevos: EPF (herramienta GRP CMP — ya aparecía en su lámina:
--      «RIT/VAT/VCT/INSTRUCTIVOS/EPF»), DESVIACION (Franke; con cierre: una
--      desviación queda abierta hasta resolverse), PIAPE (Franke — «Control
--      PIAPE» sale en su informe TA.DPR), MISCELANEA (Spence: título libre).
--   2. prevencion_faena_tipos: qué tipos ofrece cada faena. El formulario
--      filtra los chips según la faena elegida. Faena SIN mapeo = ve todos
--      (fallback, para no dejar ciega una faena nueva).
--   3. El seed CONVERGE: borra de esas 6 faenas los tipos que sobren y
--      agrega los que falten (re-ejecutable).
-- ============================================================================

BEGIN;

-- ── 1. Tipos nuevos ─────────────────────────────────────────────────────────
INSERT INTO prevencion_actividad_tipos (codigo, nombre, descripcion, requiere_cierre, orden) VALUES
    ('EPF',        'Check List EPF',       'Herramienta GRP CMP: check list de Estándares de Prevención de Fatalidades.', false, 32),
    ('DESVIACION', 'Desviación',           'Desviación detectada en terreno (Franke). Queda abierta hasta cerrar la medida.', true, 63),
    ('PIAPE',      'Control PIAPE',        'Control PIAPE (Franke — aparece en el informe de gestión TA.DPR).',          false, 64),
    ('MISCELANEA', 'Actividad miscelánea', 'Cualquier actividad preventiva no catalogada (Spence u otros mandantes que no piden formato).', false, 120)
ON CONFLICT (codigo) DO NOTHING;

-- ── 2. Mapeo faena ↔ tipos ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS prevencion_faena_tipos (
    faena_id    UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    tipo_codigo VARCHAR(30) NOT NULL REFERENCES prevencion_actividad_tipos(codigo) ON DELETE CASCADE,
    PRIMARY KEY (faena_id, tipo_codigo)
);

COMMENT ON TABLE prevencion_faena_tipos IS
    'Qué tipos de actividad ofrece cada faena (catálogo del mandante). Faena sin filas = ve todos los tipos. MIG552.';

ALTER TABLE prevencion_faena_tipos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_faena_tipos_select ON prevencion_faena_tipos;
CREATE POLICY prev_faena_tipos_select ON prevencion_faena_tipos
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_faena_tipos_admin ON prevencion_faena_tipos;
CREATE POLICY prev_faena_tipos_admin ON prevencion_faena_tipos
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, DELETE ON prevencion_faena_tipos TO authenticated;

-- ── 3. Seed convergente ─────────────────────────────────────────────────────
DO $seed$
DECLARE
    v_mapa CONSTANT JSONB := '{
        "FAE-CENTINELA":      ["CHARLA","CAPACITACION","CAMPANA","PGR"],
        "FAE-SPENCE":         ["MISCELANEA"],
        "FAE-LOMASBAYAS":     ["HS_SAFEWORK","CAPACITACION","CHARLA","GCOM","INSPECCION"],
        "FAE-LOMASBAYAS-LUB": ["HS_SAFEWORK","CAPACITACION","CHARLA","GCOM","INSPECCION"],
        "FAE-CMP-ROMERAL":    ["RIT","VAT","VCT","CAPACITACION","EPF"],
        "FAE-FRANCKE":        ["INSPECCION","CAPACITACION","DESVIACION","PIAPE","CHARLA"]
    }'::jsonb;
    v_codigo TEXT;
    v_faena  UUID;
BEGIN
    FOR v_codigo IN SELECT jsonb_object_keys(v_mapa) LOOP
        SELECT id INTO v_faena FROM faenas WHERE codigo = v_codigo;
        IF v_faena IS NULL THEN
            RAISE EXCEPTION 'Faena % no existe', v_codigo;
        END IF;

        DELETE FROM prevencion_faena_tipos
         WHERE faena_id = v_faena
           AND tipo_codigo NOT IN (SELECT jsonb_array_elements_text(v_mapa->v_codigo));

        INSERT INTO prevencion_faena_tipos (faena_id, tipo_codigo)
        SELECT v_faena, t FROM jsonb_array_elements_text(v_mapa->v_codigo) t
        ON CONFLICT DO NOTHING;
    END LOOP;
END $seed$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.nombre, string_agg(ft.tipo_codigo, ', ' ORDER BY t.orden) AS tipos
FROM prevencion_faena_tipos ft
JOIN faenas f ON f.id = ft.faena_id
JOIN prevencion_actividad_tipos t ON t.codigo = ft.tipo_codigo
GROUP BY f.nombre ORDER BY f.nombre;
