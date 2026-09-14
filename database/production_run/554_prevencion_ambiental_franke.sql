-- ============================================================================
-- MIG554 · Prevención: ambiental Franke — retiros semanales + insumos del mes
-- ============================================================================
-- Manuel (2026-09-14): «el supervisor de Franke debe ingresar semanalmente la
-- cantidad de retiro de residuos (Doméstico, Industrial, Peligroso, Botellas
-- plásticas, Aceite usado, Filtros usados — volumen m³) y el reporte de
-- insumos mensual (I agua potable L · II combustible L · III residuos
-- industriales no peligrosos m³ · IV residuos peligrosos m³ · V asimilables a
-- domésticos m³ · VI plásticos reciclables m³ · VII agua industrial/riego L)».
--
--   1. prevencion_ambiental_conceptos: catálogo POR FAENA (hoy Franke; si
--      otro mandante pide lo suyo, se le siembran sus conceptos).
--      grupo 'residuo_retiro' = semanal (fecha real del retiro);
--      grupo 'insumo'         = mensual (fecha = día 1 del mes).
--   2. prevencion_ambiental_registros: cantidad por concepto+fecha+autor.
--      UNIQUE(concepto, fecha, autor): reenviar corrige. Cantidad 0 SE
--      GUARDA — el formato del mandante exige informar el cero.
--   3. v_prevencion_ambiental_mensual: total del mes por concepto (los
--      retiros semanales se suman; el insumo mensual queda tal cual).
--      Alimenta la «Documentación ambiental» del informe Franke.
-- IDEMPOTENTE, ADITIVA.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS prevencion_ambiental_conceptos (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id  UUID NOT NULL REFERENCES faenas(id),
    grupo     VARCHAR(20) NOT NULL CHECK (grupo IN ('residuo_retiro','insumo')),
    codigo    VARCHAR(30) NOT NULL,
    nombre    VARCHAR(160) NOT NULL,
    unidad    VARCHAR(20) NOT NULL,
    -- semanal: se reporta con la fecha real del retiro; mensual: día 1 del mes
    frecuencia VARCHAR(10) NOT NULL CHECK (frecuencia IN ('semanal','mensual')),
    orden     INTEGER NOT NULL DEFAULT 100,
    activo    BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT uq_prev_amb_concepto UNIQUE (faena_id, codigo)
);

COMMENT ON TABLE prevencion_ambiental_conceptos IS
    'Catálogo ambiental por faena: qué residuos/insumos reporta el supervisor y con qué frecuencia. MIG554.';

CREATE TABLE IF NOT EXISTS prevencion_ambiental_registros (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    concepto_id  UUID NOT NULL REFERENCES prevencion_ambiental_conceptos(id) ON DELETE CASCADE,
    fecha        DATE NOT NULL,
    cantidad     NUMERIC(12,2) NOT NULL CHECK (cantidad >= 0),
    observacion  TEXT,
    creado_por   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    supervisor_nombre VARCHAR(160),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_prev_amb_registro UNIQUE (concepto_id, fecha, creado_por)
);

COMMENT ON TABLE prevencion_ambiental_registros IS
    'Cantidades reportadas (retiros semanales e insumos mensuales). Reenviar el mismo concepto+fecha corrige. El 0 se guarda: el mandante exige informarlo. MIG554.';

CREATE INDEX IF NOT EXISTS idx_prev_amb_reg_fecha
    ON prevencion_ambiental_registros (concepto_id, fecha DESC);

CREATE OR REPLACE FUNCTION public.fn_prevencion_ambiental_biu()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.supervisor_nombre IS NULL THEN
        SELECT nombre_completo INTO NEW.supervisor_nombre
          FROM usuarios_perfil WHERE id = NEW.creado_por;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_prevencion_ambiental_biu ON prevencion_ambiental_registros;
CREATE TRIGGER trg_prevencion_ambiental_biu
    BEFORE INSERT OR UPDATE ON prevencion_ambiental_registros
    FOR EACH ROW EXECUTE FUNCTION fn_prevencion_ambiental_biu();

ALTER TABLE prevencion_ambiental_conceptos ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_ambiental_registros ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_amb_conceptos_select ON prevencion_ambiental_conceptos;
CREATE POLICY prev_amb_conceptos_select ON prevencion_ambiental_conceptos
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_amb_conceptos_admin ON prevencion_ambiental_conceptos;
CREATE POLICY prev_amb_conceptos_admin ON prevencion_ambiental_conceptos
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

DROP POLICY IF EXISTS prev_amb_reg_select ON prevencion_ambiental_registros;
CREATE POLICY prev_amb_reg_select ON prevencion_ambiental_registros
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR creado_por = auth.uid())
           AND EXISTS (SELECT 1 FROM prevencion_ambiental_conceptos c
                        WHERE c.id = concepto_id AND fn_prevencion_faena_visible(c.faena_id)));

DROP POLICY IF EXISTS prev_amb_reg_insert ON prevencion_ambiental_registros;
CREATE POLICY prev_amb_reg_insert ON prevencion_ambiental_registros
    FOR INSERT TO authenticated
    WITH CHECK (fn_prevencion_reporta_puede_crear() AND creado_por = auth.uid());

DROP POLICY IF EXISTS prev_amb_reg_update ON prevencion_ambiental_registros;
CREATE POLICY prev_amb_reg_update ON prevencion_ambiental_registros
    FOR UPDATE TO authenticated
    USING (fn_prevencion_reporta_puede_admin()
           OR (creado_por = auth.uid() AND fecha > CURRENT_DATE - INTERVAL '45 days'));

DROP POLICY IF EXISTS prev_amb_reg_delete ON prevencion_ambiental_registros;
CREATE POLICY prev_amb_reg_delete ON prevencion_ambiental_registros
    FOR DELETE TO authenticated
    USING (fn_prevencion_reporta_puede_admin()
           OR (creado_por = auth.uid() AND fecha > CURRENT_DATE - INTERVAL '45 days'));

GRANT SELECT ON prevencion_ambiental_conceptos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON prevencion_ambiental_conceptos TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_ambiental_registros TO authenticated;

-- ── Seed Franke ─────────────────────────────────────────────────────────────
DO $seed$
DECLARE v_franke UUID;
BEGIN
    SELECT id INTO v_franke FROM faenas WHERE codigo = 'FAE-FRANCKE';
    IF v_franke IS NULL THEN RAISE EXCEPTION 'FAE-FRANCKE no existe'; END IF;

    INSERT INTO prevencion_ambiental_conceptos (faena_id, grupo, codigo, nombre, unidad, frecuencia, orden) VALUES
        -- Retiro semanal de residuos (volumen m³)
        (v_franke, 'residuo_retiro', 'DOMESTICO',  'Doméstico',           'm³', 'semanal', 10),
        (v_franke, 'residuo_retiro', 'INDUSTRIAL', 'Industrial',          'm³', 'semanal', 20),
        (v_franke, 'residuo_retiro', 'PELIGROSO',  'Peligroso',           'm³', 'semanal', 30),
        (v_franke, 'residuo_retiro', 'BOTELLAS',   'Botellas plásticas',  'm³', 'semanal', 40),
        (v_franke, 'residuo_retiro', 'ACEITE',     'Aceite usado',        'm³', 'semanal', 50),
        (v_franke, 'residuo_retiro', 'FILTROS',    'Filtros usados',      'm³', 'semanal', 60),
        -- Reporte de insumos mensual (numeración del formato del mandante)
        (v_franke, 'insumo', 'AGUA_POTABLE', 'I. Consumo de agua potable',                              'Litros', 'mensual', 110),
        (v_franke, 'insumo', 'COMBUSTIBLE',  'II. Consumo de combustible',                              'Litros', 'mensual', 120),
        (v_franke, 'insumo', 'RES_IND_NP',   'III. Generación de residuos industriales no peligrosos',  'm³',     'mensual', 130),
        (v_franke, 'insumo', 'RES_PEL',      'IV. Generación de residuos peligrosos',                   'm³',     'mensual', 140),
        (v_franke, 'insumo', 'RES_DOM',      'V. Generación de residuos asimilables a domésticos',      'm³',     'mensual', 150),
        (v_franke, 'insumo', 'RES_PLAST',    'VI. Generación de residuos plásticos (reciclables)',      'm³',     'mensual', 160),
        (v_franke, 'insumo', 'AGUA_IND',     'VII. Consumo de agua industrial (riego)',                 'Litros', 'mensual', 170)
    ON CONFLICT (faena_id, codigo) DO NOTHING;
END $seed$;

-- ── Consolidado mensual ─────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_prevencion_ambiental_mensual
WITH (security_invoker = true) AS
SELECT
    c.faena_id,
    EXTRACT(YEAR  FROM r.fecha)::int AS anio,
    EXTRACT(MONTH FROM r.fecha)::int AS mes,
    c.grupo, c.codigo, c.nombre, c.unidad, c.frecuencia, c.orden,
    SUM(r.cantidad)  AS total,
    COUNT(*)         AS reportes
FROM prevencion_ambiental_registros r
JOIN prevencion_ambiental_conceptos c ON c.id = r.concepto_id
GROUP BY c.faena_id, 2, 3, c.grupo, c.codigo, c.nombre, c.unidad, c.frecuencia, c.orden;

GRANT SELECT ON v_prevencion_ambiental_mensual TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT grupo, COUNT(*) AS conceptos FROM prevencion_ambiental_conceptos GROUP BY grupo ORDER BY grupo;
