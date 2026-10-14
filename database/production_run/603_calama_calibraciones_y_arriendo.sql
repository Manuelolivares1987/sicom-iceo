-- ============================================================================
-- SICOM-ICEO | 603 — Calama: calibraciones (servicio) y arriendo de camiones
-- ============================================================================
-- Manuel: «Centinela, Lomas Bayas y Spence corresponden a Calama, y ahí más que
-- flota hacemos calibraciones. Lo que sí tenemos es el arriendo de algunos
-- camiones a clientes que los tienen en esas faenas».
--
-- Entonces Calama tiene dos negocios que no se mezclan:
--   · Calibraciones (servicio): los CC de Calama (Operaciones/Proyectos/Taller
--     Calama). Antes se llamaba «Común Calama».
--   · Arriendo de camiones a clientes en Spence, Centinela (Contrato ESM),
--     Lomas Bayas, Ministro Hales, El Abra: subfaenas «Arriendo · …».
-- El Taller Calama sigue aparte.
-- ============================================================================

-- ESM = Esperanza Sur = Minera Centinela.
CREATE OR REPLACE FUNCTION fn_subfaena(p_grupo TEXT, p_ubicacion TEXT, p_faena_sicom TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_grupo = 'Calama' THEN CASE
            WHEN coalesce(p_ubicacion, '') ~* 'spence'          THEN 'Arriendo · Spence'
            WHEN coalesce(p_ubicacion, '') ~* 'centinela|esm'   THEN 'Arriendo · Centinela'
            WHEN coalesce(p_ubicacion, '') ~* 'lomas'           THEN 'Arriendo · Lomas Bayas'
            WHEN coalesce(p_ubicacion, '') ~* 'taller'          THEN 'Taller Calama'
            WHEN coalesce(p_ubicacion, '') ~* 'hales'           THEN 'Arriendo · Ministro Hales'
            WHEN coalesce(p_ubicacion, '') ~* 'abra'            THEN 'Arriendo · El Abra'
            WHEN coalesce(p_faena_sicom, '') ~* 'spence'        THEN 'Arriendo · Spence'
            WHEN coalesce(p_faena_sicom, '') ~* 'centinela'     THEN 'Arriendo · Centinela'
            WHEN coalesce(p_faena_sicom, '') ~* 'lomas'         THEN 'Arriendo · Lomas Bayas'
            WHEN coalesce(p_faena_sicom, '') ~* 'taller'        THEN 'Taller Calama'
            ELSE 'Arriendo · Calama sin detalle'
        END
        WHEN p_grupo = 'Otras faenas' THEN coalesce(nullif(btrim(split_part(p_ubicacion, ',', 1)), ''), 'Otras')
        WHEN p_grupo = 'Taller / sin contrato' THEN
            CASE WHEN coalesce(p_ubicacion, '') ~* 'fenix' THEN 'Taller externo (aseguradora)'
                 ELSE 'Taller Coquimbo / sin contrato' END
        ELSE p_grupo
    END;
$$;


-- Cada línea de bodega con todos sus cortes.
CREATE OR REPLACE FUNCTION fn_costos_lineas(p_desde DATE, p_fin DATE, p_con_admin BOOLEAN DEFAULT FALSE)
RETURNS TABLE (
    fecha DATE, mes DATE, total NUMERIC, cantidad NUMERIC,
    cod_prod TEXT, des_prod TEXT, familia TEXT, grupo_prod TEXT,
    activo_id UUID, patente TEXT, tipo_equipo TEXT,
    codi_cc TEXT, cc_desc TEXT, area TEXT,
    faena TEXT, subfaena TEXT,
    folio INTEGER, concepto TEXT, bodega TEXT, glosa TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT d.fecha, date_trunc('month', d.fecha)::DATE, l.total, l.cantidad,
           l.cod_prod::TEXT, l.des_prod, left(l.cod_prod, 6), left(l.cod_prod, 3),
           c.activo_id, a.patente::TEXT, coalesce(a.tipo_equipamiento::TEXT, a.tipo::TEXT),
           d.codi_cc::TEXT, c.descripcion, coalesce(c.area, 'sin_clasificar')::TEXT,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.grupo, 'Taller / sin contrato')
                WHEN d.codi_cc IS NULL THEN 'Sin centro de costo'
                ELSE fn_cc_faena(c.zona, c.area) END,
           CASE WHEN c.activo_id IS NOT NULL THEN coalesce(fs.subfaena, 'Taller Coquimbo / sin contrato')
                WHEN d.codi_cc IS NULL THEN 'Sin centro de costo'
                WHEN fn_cc_faena(c.zona, c.area) = 'Calama' THEN 'Calibraciones (servicio Calama)'
                WHEN fn_cc_faena(c.zona, c.area) = 'Taller / sin contrato' THEN 'Taller Coquimbo / sin contrato'
                WHEN fn_cc_faena(c.zona, c.area) = 'Otras faenas' THEN coalesce(c.zona, 'Otras')
                ELSE fn_cc_faena(c.zona, c.area) END,
           d.folio, d.concepto::TEXT, coalesce(d.bodega, d.cod_bode), d.glosa
      FROM softland_doc d
      JOIN softland_linea l USING (tipo, cod_bode, nro_int)
      LEFT JOIN softland_cc c ON c.codigo = d.codi_cc
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN LATERAL fn_activo_faena_sub_en(c.activo_id, d.fecha) fs ON c.activo_id IS NOT NULL
     WHERE d.fecha BETWEEN p_desde AND p_fin
       AND l.cod_prod <> 'CLUPETPET003'
       AND (p_con_admin OR coalesce(c.area, 'sin_clasificar') NOT IN ('administracion', 'comercial'));
$$;
REVOKE ALL ON FUNCTION fn_costos_lineas(DATE, DATE, BOOLEAN) FROM PUBLIC, anon, authenticated;



REFRESH MATERIALIZED VIEW mv_activo_faena_dia;

SELECT subfaena, count(*) FROM mv_activo_faena_dia WHERE grupo = 'Calama' GROUP BY 1 ORDER BY 2 DESC;
