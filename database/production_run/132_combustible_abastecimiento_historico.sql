-- ============================================================================
-- SICOM-ICEO | Migracion 132 — Histórico de abastecimiento (auditoría forense)
-- ----------------------------------------------------------------------------
-- Tabla para cargar el detalle de abastecimiento por cliente/equipo desde el
-- Excel de auditoría forense de combustible (hoja "Abastecimiento Detalle").
-- Sirve de baseline histórico para el control de ventas/abastecimiento Franke.
-- La carga la hace scripts/cargar-abastecimiento-historico.mjs.
-- IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS combustible_abastecimiento_historico (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente       VARCHAR(160) NOT NULL,
    equipo_codigo VARCHAR(80),
    equipo_tipo   VARCHAR(120),
    litros        NUMERIC(14,1) NOT NULL DEFAULT 0,
    n_despachos   INTEGER,
    fuente        VARCHAR(60) NOT NULL DEFAULT 'excel_auditoria',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_abast_hist UNIQUE (fuente, cliente, equipo_codigo)
);
CREATE INDEX IF NOT EXISTS idx_abast_cliente ON combustible_abastecimiento_historico(cliente);

ALTER TABLE combustible_abastecimiento_historico ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_abast_sel ON combustible_abastecimiento_historico;
CREATE POLICY pol_abast_sel ON combustible_abastecimiento_historico FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_abast_wr ON combustible_abastecimiento_historico;
CREATE POLICY pol_abast_wr ON combustible_abastecimiento_historico FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Resumen por cliente
CREATE OR REPLACE VIEW v_abastecimiento_historico_cliente AS
SELECT cliente,
       COUNT(*) AS n_equipos,
       COALESCE(SUM(litros),0) AS litros_total,
       COALESCE(SUM(n_despachos),0) AS despachos_total
FROM combustible_abastecimiento_historico
GROUP BY cliente;

SELECT (SELECT count(*) FROM information_schema.tables WHERE table_name='combustible_abastecimiento_historico') AS tabla,
       (SELECT count(*) FROM combustible_abastecimiento_historico) AS filas;
