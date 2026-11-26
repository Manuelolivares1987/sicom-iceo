-- ============================================================================
-- SICOM-ICEO | 731 — Cuentas por cobrar: ficha del cliente
-- ============================================================================
-- Todas las facturas de 2026 de un cliente (pagadas y abiertas) con sus pagos,
-- notas de crédito y las patentes que factura cada una, ligadas al equipo de
-- SICOM. Lo usa la pantalla /dashboard/finanzas/cobranza (MIG730).
-- ADITIVA.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_cxc_cliente(p_cod_aux TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r JSONB;
BEGIN
    IF NOT fn_finanzas_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver finanzas.' USING ERRCODE = '42501';
    END IF;
    SELECT jsonb_build_object(
        'cliente', (SELECT to_jsonb(a) FROM softland_auxiliar a WHERE a.cod_aux = p_cod_aux),
        'documentos', (SELECT coalesce(jsonb_agg(x ORDER BY x.emision DESC, x.folio DESC), '[]') FROM (
            SELECT d.*,
                   (SELECT coalesce(jsonb_agg(jsonb_build_object(
                               'patente', e.patente, 'activo_id', e.activo_id, 'total', e.total) ORDER BY e.patente), '[]')
                      FROM v_cxc_factura_equipo e WHERE e.folio = d.folio AND e.cod_aux = d.cod_aux) AS equipos,
                   (SELECT coalesce(jsonb_agg(jsonb_build_object(
                               'fecha', coalesce(m.cpb_fec, m.fecha), 'tipo', m.ttd_cod, 'numero', m.num_doc,
                               'monto', m.haber - m.debe, 'glosa', m.glosa) ORDER BY coalesce(m.cpb_fec, m.fecha)), '[]')
                      FROM softland_cxc_mov m
                     WHERE m.cod_aux = d.cod_aux AND m.tip_ref = d.tipo AND m.num_ref = d.folio
                       AND m.ttd_cod <> m.tip_ref) AS movimientos
              FROM v_cxc_documento d WHERE d.cod_aux = p_cod_aux) x)
    ) INTO r;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_cxc_cliente(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_cxc_cliente(TEXT) TO authenticated;

COMMIT;
