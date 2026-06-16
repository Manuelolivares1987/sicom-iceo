-- ============================================================================
-- SICOM-ICEO | 152 — Historial de cambios de contrato / operación / lugar
-- ----------------------------------------------------------------------------
-- Registra cada cambio de contrato, operación (Calama/Coquimbo) y lugar físico
-- del equipo, para mostrarlo SIEMPRE en el modal de Sugerencias GPS (la historia
-- queda y se ve, aunque cambie el valor actual). Trigger AFTER UPDATE en activos,
-- aplica venga el cambio de donde venga.
-- IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS historico_equipo_atributo (
    id              BIGSERIAL   PRIMARY KEY,
    activo_id       UUID        NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    campo           VARCHAR(20) NOT NULL,   -- 'contrato' | 'operacion' | 'ubicacion'
    valor_anterior  TEXT,
    valor_nuevo     TEXT,
    cambio_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cambio_por      UUID        REFERENCES auth.users(id),
    CONSTRAINT chk_hea_campo CHECK (campo IN ('contrato','operacion','ubicacion'))
);
CREATE INDEX IF NOT EXISTS idx_hea_activo ON historico_equipo_atributo (activo_id, cambio_at DESC);

ALTER TABLE historico_equipo_atributo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_hea_sel ON historico_equipo_atributo;
CREATE POLICY pol_hea_sel ON historico_equipo_atributo FOR SELECT TO authenticated USING (true);

-- Trigger: registrar cambios de contrato / operación / ubicación
CREATE OR REPLACE FUNCTION fn_log_equipo_atributo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_old TEXT; v_new TEXT;
BEGIN
    IF NEW.contrato_id IS DISTINCT FROM OLD.contrato_id THEN
        SELECT codigo || COALESCE(' · ' || cliente, '') INTO v_old FROM contratos WHERE id = OLD.contrato_id;
        SELECT codigo || COALESCE(' · ' || cliente, '') INTO v_new FROM contratos WHERE id = NEW.contrato_id;
        INSERT INTO historico_equipo_atributo (activo_id, campo, valor_anterior, valor_nuevo, cambio_por)
        VALUES (NEW.id, 'contrato', v_old, v_new, auth.uid());
    END IF;
    IF NEW.operacion IS DISTINCT FROM OLD.operacion THEN
        INSERT INTO historico_equipo_atributo (activo_id, campo, valor_anterior, valor_nuevo, cambio_por)
        VALUES (NEW.id, 'operacion', OLD.operacion, NEW.operacion, auth.uid());
    END IF;
    IF NEW.ubicacion_actual IS DISTINCT FROM OLD.ubicacion_actual THEN
        INSERT INTO historico_equipo_atributo (activo_id, campo, valor_anterior, valor_nuevo, cambio_por)
        VALUES (NEW.id, 'ubicacion', OLD.ubicacion_actual, NEW.ubicacion_actual, auth.uid());
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_log_equipo_atributo ON activos;
CREATE TRIGGER trg_log_equipo_atributo
    AFTER UPDATE OF contrato_id, operacion, ubicacion_actual ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_log_equipo_atributo();

-- Vista cómoda (con nombre legible del campo y patente)
CREATE OR REPLACE VIEW v_historico_equipo_atributo AS
SELECT h.id, h.activo_id, a.patente, a.codigo,
       h.campo,
       CASE h.campo WHEN 'contrato' THEN 'Contrato'
                    WHEN 'operacion' THEN 'Operación / zona'
                    WHEN 'ubicacion' THEN 'Lugar físico'
                    ELSE h.campo END AS campo_label,
       h.valor_anterior, h.valor_nuevo, h.cambio_at, h.cambio_por
FROM historico_equipo_atributo h
JOIN activos a ON a.id = h.activo_id;
GRANT SELECT ON v_historico_equipo_atributo TO authenticated;

SELECT
    (SELECT to_regclass('public.historico_equipo_atributo') IS NOT NULL) AS tabla_ok,
    (SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_log_equipo_atributo')) AS trigger_ok,
    (SELECT EXISTS(SELECT 1 FROM pg_views WHERE viewname='v_historico_equipo_atributo')) AS vista_ok;

NOTIFY pgrst, 'reload schema';
