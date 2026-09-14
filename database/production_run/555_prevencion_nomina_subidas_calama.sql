-- ============================================================================
-- MIG555 · Prevención: subidas con NÓMINA en Calama (quiénes subieron)
-- ============================================================================
-- Manuel (2026-09-14): «en asistentes que indique quiénes son; en Calama:
-- Arnold Ossandon, Joel Ossandon, Fabian Castillo, Jeison Paredes, Hersaly
-- Corey, Ivan Lobos, Cesar Torres, Bastian Zamora, Felipe Lopez. Para las
-- demás faenas, solo seleccionar la cantidad de personas.»
--
--   1. prevencion_personal_faena: la nómina por faena. Si la faena tiene
--      nómina, el formulario de subida muestra CHECKBOXES con los nombres y
--      la cantidad/HH salen solas; sin nómina (Romeral, Franke) sigue el
--      conteo simple. Los 9 de Calama quedan sembrados en las 4 faenas de la
--      zona (Lomas x2, Centinela, Spence).
--      OJO sexo: el E-200 separa hombres/mujeres. Se siembra todo 'M' por
--      defecto — si alguien de la nómina es mujer, se corrige con un UPDATE
--      (editable, no adivinamos).
--   2. prevencion_dotacion_diaria.asistentes (jsonb): los nombres marcados
--      quedan guardados en la subida — trazabilidad de quién estuvo en faena
--      ese día (útil ante fiscalización o incidente).
--   3. De la nómina sale el apellido de César: se completa su cuenta
--      (usuarios_perfil) y el experto de las fichas E-200 de la zona Calama
--      pasa de 'César' a 'César Torres'.
-- IDEMPOTENTE, ADITIVA.
-- ============================================================================

BEGIN;

-- ── 1. Nómina por faena ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS prevencion_personal_faena (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id  UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    nombre    VARCHAR(120) NOT NULL,
    sexo      CHAR(1) NOT NULL DEFAULT 'M' CHECK (sexo IN ('M','F')),
    activo    BOOLEAN NOT NULL DEFAULT true,
    orden     INTEGER NOT NULL DEFAULT 100,
    CONSTRAINT uq_prev_personal_faena UNIQUE (faena_id, nombre)
);

COMMENT ON TABLE prevencion_personal_faena IS
    'Nómina de subida por faena: si existe, el supervisor marca QUIÉNES subieron (checkbox) en vez de digitar cantidades. Sexo alimenta el split H/M del E-200. MIG555.';

ALTER TABLE prevencion_personal_faena ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_personal_select ON prevencion_personal_faena;
CREATE POLICY prev_personal_select ON prevencion_personal_faena
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_personal_admin ON prevencion_personal_faena;
CREATE POLICY prev_personal_admin ON prevencion_personal_faena
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT ON prevencion_personal_faena TO authenticated;
GRANT INSERT, UPDATE, DELETE ON prevencion_personal_faena TO authenticated;

-- Seed: los 9 de Calama en las 4 faenas de la zona.
INSERT INTO prevencion_personal_faena (faena_id, nombre, orden)
SELECT f.id, n.nombre, n.orden
FROM faenas f
CROSS JOIN (VALUES
    ('Arnold Ossandón', 10), ('Joel Ossandón', 20), ('Fabián Castillo', 30),
    ('Jeison Paredes', 40), ('Hersaly Corey', 50), ('Iván Lobos', 60),
    ('César Torres', 70), ('Bastián Zamora', 80), ('Felipe López', 90)
) AS n(nombre, orden)
WHERE f.codigo IN ('FAE-LOMASBAYAS', 'FAE-LOMASBAYAS-LUB', 'FAE-CENTINELA', 'FAE-SPENCE')
ON CONFLICT (faena_id, nombre) DO NOTHING;

-- ── 2. La subida guarda los nombres ─────────────────────────────────────────
ALTER TABLE prevencion_dotacion_diaria
    ADD COLUMN IF NOT EXISTS asistentes JSONB;

COMMENT ON COLUMN prevencion_dotacion_diaria.asistentes IS
    'Nombres marcados de la nómina (["Arnold Ossandón",…]). NULL en faenas de conteo simple. MIG555.';

-- ── 3. César con apellido ───────────────────────────────────────────────────
UPDATE usuarios_perfil
   SET nombre_completo = 'César Torres', updated_at = NOW()
 WHERE email = 'cesar@pillado.cl'
   AND nombre_completo LIKE 'César%'
   AND nombre_completo <> 'César Torres';

UPDATE prevencion_faena_config c
   SET datos = jsonb_set(c.datos, '{experto,nombre}', '"César Torres"'),
       updated_at = NOW()
  FROM faenas f
 WHERE f.id = c.faena_id
   AND f.codigo IN ('FAE-LOMASBAYAS', 'FAE-LOMASBAYAS-LUB', 'FAE-CENTINELA', 'FAE-SPENCE')
   AND c.datos->'experto'->>'nombre' IN ('César');

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.codigo, COUNT(*) AS nomina,
       (SELECT c.datos->'experto'->>'nombre' FROM prevencion_faena_config c WHERE c.faena_id = f.id) AS experto
FROM prevencion_personal_faena p JOIN faenas f ON f.id = p.faena_id
GROUP BY f.codigo, f.id ORDER BY f.codigo;
