-- ============================================================================
-- SICOM-ICEO | 142 — Cierre parcial diario de la inspección de recepción
-- ----------------------------------------------------------------------------
-- Una inspección de recepción puede durar varios días. Cada día el grupo hace
-- un "cierre parcial": se generan las No Conformidades de lo evaluado hasta ese
-- momento (idempotente, no duplica), SIN cerrar todo el informe. El cierre
-- final (fn_cerrar_inspeccion_recepcion) genera lo que falte y cierra.
-- IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS recepcion_cierres_parciales (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id    UUID NOT NULL REFERENCES informes_recepcion(id) ON DELETE CASCADE,
    fecha         DATE NOT NULL DEFAULT CURRENT_DATE,
    cerrado_por   UUID REFERENCES usuarios_perfil(id),
    nc_generadas  INT NOT NULL DEFAULT 0,
    observacion   TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cpr_informe ON recepcion_cierres_parciales(informe_id);

ALTER TABLE recepcion_cierres_parciales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_cpr_sel ON recepcion_cierres_parciales;
CREATE POLICY pol_cpr_sel ON recepcion_cierres_parciales FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_cpr_wr ON recepcion_cierres_parciales;
CREATE POLICY pol_cpr_wr ON recepcion_cierres_parciales FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- RPC — cierre parcial del día: genera NC de lo evaluado, registra el cierre.
CREATE OR REPLACE FUNCTION fn_cierre_parcial_recepcion(
    p_informe_id  UUID,
    p_observacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_est  TEXT;
    v_gen  JSONB;
    v_n    INT;
    v_id   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT estado INTO v_est FROM informes_recepcion WHERE id = p_informe_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Informe % no existe', p_informe_id; END IF;
    IF v_est <> 'en_inspeccion' THEN
        RAISE EXCEPTION 'El informe ya no está en inspección (estado %).', v_est;
    END IF;

    v_gen := fn_generar_nc_desde_recepcion(p_informe_id);   -- idempotente
    v_n := COALESCE((v_gen->>'creadas')::INT, 0);

    INSERT INTO recepcion_cierres_parciales (informe_id, cerrado_por, nc_generadas, observacion)
    VALUES (p_informe_id, v_user, v_n, p_observacion)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('cierre_id', v_id, 'nc_generadas', v_n);
END $$;
GRANT EXECUTE ON FUNCTION fn_cierre_parcial_recepcion TO authenticated;

-- Vista — cierres parciales por informe (para mostrar el historial).
CREATE OR REPLACE VIEW v_cierres_parciales_recepcion AS
SELECT cp.id, cp.informe_id, cp.fecha, cp.nc_generadas, cp.observacion, cp.created_at,
       up.nombre_completo AS cerrado_por_nombre
FROM recepcion_cierres_parciales cp
LEFT JOIN usuarios_perfil up ON up.id = cp.cerrado_por;

SELECT (SELECT count(*) FROM pg_proc WHERE proname='fn_cierre_parcial_recepcion') AS rpc,
       (SELECT count(*) FROM information_schema.tables WHERE table_name='recepcion_cierres_parciales') AS tabla;
