-- ============================================================================
-- MIG553 · Prevención: subidas a faena — dotación diaria del supervisor → HH E-200
-- ============================================================================
-- Manuel (2026-09-14): «el supervisor debe ingresar las faenas que visitó
-- durante la semana y la cantidad de personal que subió, incluyéndolo a él.
-- La plataforma calcula 8 × personas para el total de HH que va al E-200.
-- El E-200 es por faena.»
--
--   1. prevencion_dotacion_diaria: una fila por supervisor + faena + día con
--      hombres y mujeres que subieron (el E-200 declara por género). UNIQUE
--      (faena, fecha, creado_por): si el supervisor se equivocó, corrige la
--      misma fila (upsert); si suben DOS cuadrillas distintas el mismo día,
--      cada supervisor reporta la suya y se SUMAN.
--   2. v_prevencion_dotacion_mensual: por faena+mes —
--         HH = 8 × Σ personas-día (la regla de Manuel, por género)
--         dotación sugerida = máximo simultáneo del mes (el peak diario,
--         sumando cuadrillas del mismo día)
--      Prevención lo ve en la pestaña Indicadores y el formulario «Cargar
--      mes» se PRELLENA con estos números — los valida y guarda, y de ahí
--      sale el E-200. El cálculo no pisa nada solo: prevención siempre
--      confirma.
-- IDEMPOTENTE, ADITIVA.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS prevencion_dotacion_diaria (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id     UUID NOT NULL REFERENCES faenas(id),
    fecha        DATE NOT NULL DEFAULT CURRENT_DATE,
    hombres      INTEGER NOT NULL DEFAULT 0 CHECK (hombres >= 0),
    mujeres      INTEGER NOT NULL DEFAULT 0 CHECK (mujeres >= 0),
    observacion  TEXT,
    creado_por   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    supervisor_nombre VARCHAR(160),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_dotacion_alguien CHECK (hombres + mujeres > 0),
    CONSTRAINT uq_prev_dotacion UNIQUE (faena_id, fecha, creado_por)
);

COMMENT ON TABLE prevencion_dotacion_diaria IS
    'Subidas a faena reportadas por el supervisor (personas por día, él incluido). HH del E-200 = 8 × personas-día, por faena. MIG553.';

CREATE INDEX IF NOT EXISTS idx_prev_dotacion_faena_fecha
    ON prevencion_dotacion_diaria (faena_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_prev_dotacion_autor
    ON prevencion_dotacion_diaria (creado_por, fecha DESC);

CREATE OR REPLACE FUNCTION public.fn_prevencion_dotacion_biu()
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

DROP TRIGGER IF EXISTS trg_prevencion_dotacion_biu ON prevencion_dotacion_diaria;
CREATE TRIGGER trg_prevencion_dotacion_biu
    BEFORE INSERT OR UPDATE ON prevencion_dotacion_diaria
    FOR EACH ROW EXECUTE FUNCTION fn_prevencion_dotacion_biu();

ALTER TABLE prevencion_dotacion_diaria ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_dot_select ON prevencion_dotacion_diaria;
CREATE POLICY prev_dot_select ON prevencion_dotacion_diaria
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR creado_por = auth.uid())
           AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_dot_insert ON prevencion_dotacion_diaria;
CREATE POLICY prev_dot_insert ON prevencion_dotacion_diaria
    FOR INSERT TO authenticated
    WITH CHECK (fn_prevencion_reporta_puede_crear() AND creado_por = auth.uid());

-- El autor corrige su fila (el mismo día o la semana: la ventana es más
-- amplia que en registros porque las subidas se reportan «durante la semana»);
-- prevención/administración siempre.
DROP POLICY IF EXISTS prev_dot_update ON prevencion_dotacion_diaria;
CREATE POLICY prev_dot_update ON prevencion_dotacion_diaria
    FOR UPDATE TO authenticated
    USING (fn_prevencion_reporta_puede_admin()
           OR (creado_por = auth.uid() AND fecha > CURRENT_DATE - INTERVAL '14 days'));

DROP POLICY IF EXISTS prev_dot_delete ON prevencion_dotacion_diaria;
CREATE POLICY prev_dot_delete ON prevencion_dotacion_diaria
    FOR DELETE TO authenticated
    USING (fn_prevencion_reporta_puede_admin()
           OR (creado_por = auth.uid() AND fecha > CURRENT_DATE - INTERVAL '14 days'));

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_dotacion_diaria TO authenticated;

-- ── Consolidado mensual: la regla 8 × personas ──────────────────────────────
CREATE OR REPLACE VIEW v_prevencion_dotacion_mensual
WITH (security_invoker = true) AS
WITH por_dia AS (
    -- Cuadrillas de distintos supervisores el mismo día se SUMAN.
    SELECT faena_id,
           EXTRACT(YEAR  FROM fecha)::int AS anio,
           EXTRACT(MONTH FROM fecha)::int AS mes,
           fecha,
           SUM(hombres) AS hombres_dia,
           SUM(mujeres) AS mujeres_dia
    FROM prevencion_dotacion_diaria
    GROUP BY faena_id, 2, 3, fecha
)
SELECT
    faena_id, anio, mes,
    COUNT(*)                       AS dias_reportados,
    SUM(hombres_dia) * 8           AS hh_hombres,
    SUM(mujeres_dia) * 8           AS hh_mujeres,
    (SUM(hombres_dia) + SUM(mujeres_dia)) * 8 AS hh_total,
    MAX(hombres_dia)               AS dotacion_max_hombres,
    MAX(mujeres_dia)               AS dotacion_max_mujeres,
    MIN(fecha)                     AS primer_dia,
    MAX(fecha)                     AS ultimo_dia
FROM por_dia
GROUP BY faena_id, anio, mes;

GRANT SELECT ON v_prevencion_dotacion_mensual TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT COUNT(*) AS filas_dotacion,
       (SELECT COUNT(*) FROM pg_policy WHERE polrelid = 'prevencion_dotacion_diaria'::regclass) AS politicas
FROM prevencion_dotacion_diaria;
