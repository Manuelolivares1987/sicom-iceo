-- ============================================================================
-- SICOM-ICEO | 595 — Centro de costo Softland → equipo también por patente
-- ============================================================================
-- MIG594 llegaba al equipo solo por el CECO (activos.ceco_id). Hay equipos con
-- gasto en Softland cuyo CECO no está cargado en SICOM (RS-CY-85, plataformas
-- LK-PY, camiones WC-WR…): la patente viene en la descripción del CC
-- ("Camión de Servicio 6.000 KG RS CY 85") y se cruza con activos.patente.
--
-- Además el código Softland ya dice qué es: AI agua industrial, CC combustible,
-- CA camioneta, CP pluma, CS servicio, CH hookloader, CR cargo, EE especiales,
-- GH grúa horquilla, VC vehículo comercial. Y el prefijo de faena (FC Calama,
-- FK Franke, RO Romeral, OC oficina central Coquimbo, TC Copiapó…) da la zona.
--
-- El equipo queda guardado en softland_cc.activo_id (se recalcula en cada
-- sincronización) y la materializada lo lee de ahí.
-- ============================================================================

ALTER TABLE softland_cc ADD COLUMN IF NOT EXISTS activo_id UUID REFERENCES activos(id);

-- Patente al final de la descripción, normalizada: "RS CY 85" / "SP RY-29" /
-- "GDFV-16" → RSCY85.
CREATE OR REPLACE FUNCTION fn_softland_patente(p_desc TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT replace(replace(m[1], ' ', ''), '-', '')
      FROM regexp_match(upper(coalesce(p_desc, '')),
                        '([A-Z]{2}[ -]?[A-Z]{2}[ -]?[0-9]{2})\s*$') AS m;
$$;

CREATE OR REPLACE FUNCTION fn_softland_cc_activo(p_codigo TEXT, p_desc TEXT)
RETURNS UUID LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT coalesce(
        (SELECT a.id FROM centros_costo cc JOIN activos a ON a.ceco_id = cc.id
          WHERE upper(cc.codigo) = upper(p_codigo) AND NOT coalesce(a.es_prueba, false)
          ORDER BY a.fecha_baja NULLS FIRST LIMIT 1),
        (SELECT a.id FROM activos a
          WHERE fn_softland_patente(p_desc) IS NOT NULL
            AND regexp_replace(upper(a.patente), '[^A-Z0-9]', '', 'g') = fn_softland_patente(p_desc)
            AND NOT coalesce(a.es_prueba, false)
          ORDER BY a.fecha_baja NULLS FIRST LIMIT 1));
$$;

CREATE OR REPLACE FUNCTION fn_softland_cc_clasificar(p_codigo TEXT, p_desc TEXT)
RETURNS TABLE (area TEXT, zona TEXT)
LANGUAGE sql STABLE SET search_path = public AS $$
    WITH d AS (SELECT upper(coalesce(p_desc, '')) AS t, upper(p_codigo) AS c,
                      upper(left(p_codigo, 2)) AS p)
    SELECT
        CASE
            WHEN d.c IN ('OC-TA-03', 'OC-TA-04') THEN 'generico'
            WHEN fn_softland_cc_activo(d.c, p_desc) IS NOT NULL THEN 'equipo'
            WHEN d.p IN ('AI','CA','CC','CH','CP','CR','CS','EE','GH','VC') THEN 'equipo'
            WHEN d.t ~ 'ESTANQUE' THEN 'operacion'
            WHEN d.t ~ 'ADMINISTRACI|ADIMINISTRACI|GERENCIA|OFICINA' THEN 'administracion'
            WHEN d.t ~ 'COMERCIAL|MARKETING' THEN 'comercial'
            WHEN d.t ~ 'TALLER' THEN 'taller'
            WHEN d.t ~ 'PROYECTO' THEN 'proyectos'
            WHEN d.t ~ 'OPERACI' THEN 'operacion'
            -- Código de faena sin más detalle ("ROMERAL", "LAS CENIZAS", "BHP-INTI")
            WHEN d.p IN ('BH','CN','EM','FC','FK','LC','PL','RO','TC') THEN 'operacion'
            ELSE 'sin_clasificar'
        END,
        CASE
            WHEN d.t ~ 'CALAMA' OR d.p = 'FC' THEN 'Calama'
            WHEN d.t ~ 'FRANCKE|FRANKE|CENIZAS' OR d.p = 'FK' THEN 'Franke'
            WHEN d.t ~ 'ROMERAL' OR d.p = 'RO' THEN 'Romeral'
            WHEN d.t ~ 'COPIAP' OR d.p = 'TC' THEN 'Copiapó'
            WHEN d.t ~ 'COQUIMBO' OR d.p = 'OC' THEN 'Coquimbo'
            WHEN d.p = 'PL' THEN 'Pascua Lama'
            WHEN d.p = 'CN' THEN 'Cerro Negro Norte'
            WHEN d.p = 'LC' THEN 'Los Colorados'
            WHEN d.p = 'BH' THEN 'Inti (BHP)'
            WHEN d.p = 'EM' AND d.t !~ 'ESTANQUE' THEN 'El Morro'
            ELSE NULL
        END
    FROM d;
$$;

-- Reclasifica lo ya cargado (respeta lo corregido a mano).
UPDATE softland_cc c SET
    activo_id = fn_softland_cc_activo(c.codigo, c.descripcion),
    area = CASE WHEN c.area_manual THEN c.area
                ELSE (SELECT k.area FROM fn_softland_cc_clasificar(c.codigo, c.descripcion) k) END,
    zona = CASE WHEN c.area_manual THEN c.zona
                ELSE (SELECT k.zona FROM fn_softland_cc_clasificar(c.codigo, c.descripcion) k) END,
    updated_at = NOW();


-- El maestro guarda también el equipo.
CREATE OR REPLACE FUNCTION rpc_softland_cargar_cc(p_secreto TEXT, p_cc JSONB)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO softland_cc (codigo, descripcion, area, zona, activo_id, updated_at)
    SELECT x.codigo, x.descripcion, k.area, k.zona,
           fn_softland_cc_activo(x.codigo, x.descripcion), NOW()
      FROM (SELECT DISTINCT ON (upper(btrim(e->>'codigo')))
                   upper(btrim(e->>'codigo')) AS codigo,
                   nullif(btrim(e->>'descripcion'), '') AS descripcion
              FROM jsonb_array_elements(p_cc) e
             WHERE nullif(btrim(e->>'codigo'), '') IS NOT NULL) x
      CROSS JOIN LATERAL fn_softland_cc_clasificar(x.codigo, x.descripcion) k
    ON CONFLICT (codigo) DO UPDATE SET
        descripcion = EXCLUDED.descripcion,
        activo_id = EXCLUDED.activo_id,
        area = CASE WHEN softland_cc.area_manual THEN softland_cc.area ELSE EXCLUDED.area END,
        zona = CASE WHEN softland_cc.area_manual THEN softland_cc.zona ELSE EXCLUDED.zona END,
        updated_at = NOW();
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;


-- Materializada: el equipo sale de softland_cc.activo_id.
DROP MATERIALIZED VIEW IF EXISTS mv_softland_costo_mes;
CREATE MATERIALIZED VIEW mv_softland_costo_mes AS
SELECT
    date_trunc('month', d.fecha)::DATE                  AS mes,
    d.concepto,
    d.cod_bode,
    coalesce(d.bodega, d.cod_bode)                      AS bodega,
    coalesce(d.codi_cc, '(SIN CC)')                     AS codi_cc,
    coalesce(c.area, 'sin_clasificar')                  AS area,
    c.activo_id,
    coalesce(f.nombre, c.zona)                          AS zona,
    left(l.cod_prod, 3)                                 AS grupo,
    left(l.cod_prod, 6)                                 AS familia,
    (l.cod_prod = 'CLUPETPET003')                       AS es_petroleo,
    sum(l.cantidad)                                     AS cantidad,
    sum(l.total)                                        AS total,
    count(*)                                            AS lineas,
    count(*) FILTER (WHERE l.total = 0)                 AS lineas_sin_precio
FROM softland_doc d
JOIN softland_linea l USING (tipo, cod_bode, nro_int)
LEFT JOIN softland_cc c ON c.codigo = d.codi_cc
LEFT JOIN activos a ON a.id = c.activo_id
LEFT JOIN faenas f ON f.id = a.faena_id
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11;

CREATE INDEX IF NOT EXISTS idx_mv_softland_costo_mes_mes ON mv_softland_costo_mes (mes);
REVOKE ALL ON mv_softland_costo_mes FROM anon, authenticated;

SELECT area, count(*) AS ccs, count(activo_id) AS con_equipo
  FROM softland_cc GROUP BY area ORDER BY 2 DESC;
