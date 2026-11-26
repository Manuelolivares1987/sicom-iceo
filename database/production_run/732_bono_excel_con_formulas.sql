-- ============================================================================
-- SICOM-ICEO | 732 — Bono del taller: parámetros para el Excel con fórmulas
-- ============================================================================
-- Manuel (26-11-2026): «el Excel que descargo de acá, todo venga con fórmulas».
-- Autorizada: «si, aplica la 732».
-- Para que el Excel recalcule cada monto necesita los mismos parámetros que usó
-- el motor en ese corte: plazos y coeficientes por concepto, tope del plan y
-- base de KPI por cargo, y los tramos de disponibilidad. Se eligen igual que en
-- rpc_taller_bono_trabajos_excel (el juego del período cerrado, o el vigente).
-- ADITIVA. Solo lectura: no cambia ningún monto ni cálculo.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_bono_parametros_excel(p_desde DATE, p_hasta DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_par UUID;
BEGIN
    PERFORM fn_taller_bono_exigir_vista();

    SELECT p.parametros_id INTO v_par
      FROM taller_bono_periodo p
     WHERE p.desde = p_desde AND p.hasta = p_hasta
     ORDER BY p.cerrado_at DESC LIMIT 1;
    IF v_par IS NULL THEN
        SELECT id INTO v_par FROM taller_bono_parametros
         WHERE vigencia_desde <= p_hasta
           AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
         ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
         LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'nombre', (SELECT nombre FROM taller_bono_parametros WHERE id = v_par),
        'conceptos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'concepto', concepto, 'descripcion', descripcion,
                'dias_optimizado', dias_optimizado, 'dias_normal', dias_normal, 'dias_demora', dias_demora,
                'coef_optimizado', coef_optimizado, 'coef_por_dia', coef_por_dia) ORDER BY concepto), '[]')
              FROM taller_bono_concepto WHERE parametros_id = v_par),
        'cargos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'cargo', cargo, 'plan_tope', plan_tope_clp, 'kpi_base', kpi_base_clp) ORDER BY cargo), '[]')
              FROM taller_bono_cargo WHERE parametros_id = v_par),
        'tramos_kpi', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'desde_pct', desde_pct, 'factor', factor, 'etiqueta', etiqueta) ORDER BY desde_pct), '[]')
              FROM taller_bono_tramo_kpi WHERE parametros_id = v_par)
    );
END $$;
REVOKE ALL ON FUNCTION rpc_taller_bono_parametros_excel(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_parametros_excel(DATE, DATE) TO authenticated;

COMMIT;
