-- ============================================================================
-- SICOM-ICEO | 596 — Detalle de costos: las salidas sin centro de costo
-- ============================================================================
-- El panel agrupa las salidas sin CodiCC como '(SIN CC)', pero el detalle
-- buscaba ese texto literal y volvía vacío. Ahora '(SIN CC)' = codi_cc NULL.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_costos_operacion_detalle(
    p_desde DATE, p_hasta DATE, p_codi_cc TEXT DEFAULT NULL, p_familia TEXT DEFAULT NULL,
    p_limite INTEGER DEFAULT 500)
RETURNS TABLE (
    fecha DATE, folio INTEGER, concepto TEXT, bodega TEXT, codi_cc TEXT,
    cod_prod TEXT, des_prod TEXT, cantidad NUMERIC, precio_unit NUMERIC, total NUMERIC,
    glosa TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_codi_cc IS NULL AND p_familia IS NULL THEN
        RAISE EXCEPTION 'Indique centro de costo o familia.';
    END IF;

    RETURN QUERY
    SELECT d.fecha, d.folio, d.concepto::TEXT, coalesce(d.bodega, d.cod_bode), d.codi_cc::TEXT,
           l.cod_prod::TEXT, l.des_prod, l.cantidad, l.precio_unit, l.total, d.glosa
      FROM softland_doc d
      JOIN softland_linea l USING (tipo, cod_bode, nro_int)
     WHERE d.fecha >= p_desde AND d.fecha < (date_trunc('month', p_hasta) + INTERVAL '1 month')::DATE
       AND (p_codi_cc IS NULL
            OR (p_codi_cc = '(SIN CC)' AND d.codi_cc IS NULL)
            OR d.codi_cc = upper(p_codi_cc))
       AND (p_familia IS NULL OR left(l.cod_prod, length(p_familia)) = upper(p_familia))
     ORDER BY l.total DESC
     LIMIT least(coalesce(p_limite, 500), 2000);
END $$;
