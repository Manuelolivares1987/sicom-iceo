-- 679 — Informe semanal de cumplimiento a ENEX: registro de cada envío.
-- La pantalla arma el borrador, una persona lo revisa y lo envía; aquí queda
-- qué se mandó, a quién y quién lo autorizó. Nada sale automático.

CREATE TABLE IF NOT EXISTS enex_informes_semanales (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    semana_inicio     DATE NOT NULL,
    destinatarios     TEXT[] NOT NULL,
    copia             TEXT[] NOT NULL DEFAULT '{}',
    asunto            TEXT NOT NULL,
    contenido         JSONB NOT NULL,
    estado            TEXT NOT NULL DEFAULT 'enviando' CHECK (estado IN ('enviando','enviado','error')),
    error             TEXT,
    enviado_por       UUID DEFAULT auth.uid(),
    enviado_por_email TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    enviado_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_enex_inf_sem_semana ON enex_informes_semanales (semana_inicio, created_at DESC);
COMMENT ON TABLE enex_informes_semanales IS 'Informes semanales de cumplimiento enviados a ENEX (qué, a quién, quién autorizó). MIG679.';

ALTER TABLE enex_informes_semanales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_inf_sem_sel ON enex_informes_semanales;
CREATE POLICY pol_enex_inf_sem_sel ON enex_informes_semanales FOR SELECT TO authenticated USING (fn_enex_puede_gestionar());

CREATE OR REPLACE FUNCTION rpc_enex_informe_semanal_registrar(
    p_semana_inicio DATE, p_destinatarios TEXT[], p_copia TEXT[], p_asunto TEXT, p_contenido JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF COALESCE(array_length(p_destinatarios, 1), 0) = 0 THEN RAISE EXCEPTION 'Sin destinatarios'; END IF;
    INSERT INTO enex_informes_semanales (semana_inicio, destinatarios, copia, asunto, contenido, enviado_por_email)
    VALUES (p_semana_inicio, p_destinatarios, COALESCE(p_copia, '{}'), p_asunto, p_contenido, auth.jwt() ->> 'email')
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION rpc_enex_informe_semanal_resultado(p_id UUID, p_ok BOOLEAN, p_error TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    UPDATE enex_informes_semanales
       SET estado = CASE WHEN p_ok THEN 'enviado' ELSE 'error' END,
           error = p_error, enviado_at = CASE WHEN p_ok THEN NOW() END
     WHERE id = p_id AND enviado_por = auth.uid() AND estado = 'enviando';
END $$;

REVOKE ALL ON FUNCTION rpc_enex_informe_semanal_registrar(DATE, TEXT[], TEXT[], TEXT, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_informe_semanal_resultado(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_enex_informe_semanal_registrar(DATE, TEXT[], TEXT[], TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_informe_semanal_resultado(UUID, BOOLEAN, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
