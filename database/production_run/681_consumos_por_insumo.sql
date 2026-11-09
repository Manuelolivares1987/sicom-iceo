-- 681 — Consumos por insumo para negociar con proveedores (Manuel 09-11-2026).
-- Por cada insumo: acumulado y promedio desde Softland, y proyección según las pautas.
-- Solo agrega lectura: vistas y RPC nuevas. No cambia ningún dato.
--
-- Unidades: Softland cuenta unos aceites por litro y otros por envase (balde de 19 L a
-- $132.000 frente a tambor de 208 L a $2.500 el litro). Para comparar y sumar volúmenes
-- todo lubricante se lleva a litros (grasas a kilos) línea por línea, con el contenido que
-- dice su descripción. Si no lo dice y el precio es de envase, queda en «envase».

-- Contenido del envase según la descripción. Se toma el mayor número seguido de L o KG
-- porque «RIMULA R4 L 15W40 19LITROS» trae dos.
CREATE FUNCTION fn_insumo_contenido(p_des TEXT) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
    SELECT max(replace(m[1], ',', '.')::NUMERIC)
      FROM regexp_matches(upper(coalesce(p_des, '')),
           '(\d+(?:[.,]\d+)?)\s*(?:L\.?T?\.?S?\.?|LITROS?|KGS?|KILOS?)(?![A-Z0-9])', 'g') m
$$;

-- Litros (o kilos) por unidad de Softland en una línea. Bajo $15.000 ya es precio por litro.
CREATE FUNCTION fn_insumo_factor(p_cod TEXT, p_des TEXT, p_precio NUMERIC) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
    SELECT CASE
        WHEN NOT (p_cod LIKE 'CLULUB%' OR p_cod LIKE 'CLUGRA%' OR p_cod IN ('AFEADIABL001','AFEFERALP001')) THEN 1
        WHEN fn_insumo_contenido(p_des) IS NULL THEN 1
        WHEN p_precio >= 15000 THEN fn_insumo_contenido(p_des)
        WHEN fn_insumo_contenido(p_des) <= 25 AND upper(p_des) ~ 'BIDON|BALDE' THEN fn_insumo_contenido(p_des)
        ELSE 1
    END
$$;

CREATE VIEW v_insumo_linea AS
SELECT v.fuente, v.fecha, v.cod_prod, v.des_prod, v.origen, v.total,
       v.cantidad * fn_insumo_factor(v.cod_prod, v.des_prod, coalesce(nullif(v.precio_unit, 0), v.total / nullif(v.cantidad, 0))) AS cantidad,
       v.precio_unit
  FROM v_costos_linea v
 WHERE v.cod_prod IS NOT NULL AND NOT v.es_mercaderia AND v.cod_prod NOT LIKE 'SER%' AND v.cantidad > 0;
REVOKE ALL ON v_insumo_linea FROM PUBLIC, anon, authenticated;

-- Cada ítem de cada visita proyectada. Solo materiales: no servicios externos ni muestras.
-- clave = código Softland si existe; si la pauta no lo tiene, el nombre del ítem. Lo que está
-- «por cotizar» se separa por modelo: un filtro de Volvo no es el de Scania.
CREATE VIEW v_insumo_pauta AS
SELECT coalesce(p.cod_prod, CASE WHEN k.cod_softland = 'cotizar'
                                 THEN regexp_replace(k.item, '\s*\(.*$', '') || ' · ' || c.grupo_kit
                                 ELSE regexp_replace(k.item, '\s*\(.*$', '') END) AS clave,
       p.cod_prod,
       regexp_replace(k.item, '\s*\(.*$', '') AS item,
       k.unidad, k.precio_ref, k.cantidad, c.patente, c.grupo_kit, v.fecha, v.anio, v.mes, v.nivel
  FROM ppto_visita v
  JOIN ppto_camion c USING (patente)
  JOIN ppto_kit_item k ON k.grupo_kit = c.grupo_kit AND k.nivel = v.nivel
  LEFT JOIN LATERAL (SELECT k.cod_softland AS cod_prod WHERE k.cod_softland ~ '^[A-Z]{6}[A-Z0-9]*\d$') p ON true
 WHERE k.unidad NOT IN ('servicio', 'muestra');
REVOKE ALL ON v_insumo_pauta FROM PUBLIC, anon, authenticated;

-- Tabla principal: una fila por insumo con su histórico del período y su proyección.
CREATE FUNCTION rpc_insumos_consumo(p_fuente TEXT, p_desde DATE, p_hasta DATE) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_fuente NOT IN ('bodega', 'oc') OR p_desde IS NULL OR p_hasta IS NULL OR p_desde > p_hasta THEN
        RAISE EXCEPTION 'Período o fuente inválidos.';
    END IF;

    WITH hist AS (
        SELECT cod_prod, sum(cantidad) AS q, sum(total) AS t, count(*) AS movs,
               count(DISTINCT date_trunc('month', fecha)) AS meses_con,
               (array_agg(des_prod ORDER BY fecha DESC))[1] AS des,
               bool_or(fn_insumo_factor(cod_prod, des_prod, coalesce(nullif(precio_unit, 0), total / nullif(cantidad, 0))) > 1 OR precio_unit < 15000) AS en_litros
          FROM v_insumo_linea
         WHERE fuente = p_fuente AND fecha BETWEEN p_desde AND p_hasta
         GROUP BY 1
    ), prov AS (
        SELECT DISTINCT ON (cod_prod) cod_prod, origen AS proveedor
          FROM (SELECT cod_prod, origen, sum(total) AS t FROM v_insumo_linea
                 WHERE fuente = 'oc' AND fecha >= v_hoy - 730 AND origen IS NOT NULL GROUP BY 1, 2) x
         ORDER BY cod_prod, t DESC
    ), nprov AS (
        SELECT cod_prod, count(DISTINCT origen) AS n FROM v_insumo_linea
         WHERE fuente = 'oc' AND fecha >= v_hoy - 730 AND origen IS NOT NULL GROUP BY 1
    ), pauta AS (
        SELECT clave, max(cod_prod) AS cod_prod, min(item) AS item, min(unidad) AS unidad,
               avg(precio_ref) AS precio_ref,
               count(DISTINCT patente) AS camiones,
               sum(cantidad) FILTER (WHERE fecha BETWEEN v_hoy AND v_hoy + 364) AS p12,
               sum(cantidad) FILTER (WHERE anio = 2027) AS p27,
               sum(cantidad) FILTER (WHERE anio = 2028) AS p28,
               sum(cantidad) FILTER (WHERE anio = 2029) AS p29
          FROM v_insumo_pauta GROUP BY 1
    ), nombre AS (
        -- Insumos de pauta sin movimiento en el período: su última descripción conocida.
        SELECT DISTINCT ON (cod_prod) cod_prod, des_prod
          FROM v_insumo_linea WHERE cod_prod IN (SELECT cod_prod FROM pauta WHERE cod_prod IS NOT NULL)
         ORDER BY cod_prod, fecha DESC
    ), u AS (
        SELECT coalesce(h.cod_prod, pa.clave) AS clave,
               coalesce(h.cod_prod, pa.cod_prod) AS cod_prod,
               coalesce(h.des, n.des_prod, pa.item) AS descripcion,
               coalesce(h.q, 0) AS q, coalesce(h.t, 0) AS t, coalesce(h.movs, 0) AS movs, coalesce(h.meses_con, 0) AS meses_con,
               h.en_litros, pa.unidad AS unidad_pauta, pa.precio_ref, coalesce(pa.camiones, 0) AS camiones,
               pa.p12, pa.p27, pa.p28, pa.p29, pa.clave IS NOT NULL AS con_pauta
          FROM hist h
          FULL JOIN pauta pa ON pa.cod_prod = h.cod_prod
          LEFT JOIN nombre n ON n.cod_prod = pa.cod_prod
    )
    SELECT jsonb_build_object(
        'calculado_at', (SELECT calculado_at FROM ppto_version WHERE id = 1),
        'items', coalesce(jsonb_agg(jsonb_build_object(
            'clave', u.clave, 'cod_prod', u.cod_prod, 'descripcion', u.descripcion,
            'familia', coalesce(f6.nombre, f3.nombre, 'Sin código Softland'),
            'unidad', CASE
                WHEN u.en_litros IS NULL THEN coalesce(u.unidad_pauta, 'un')
                WHEN u.cod_prod LIKE 'CLUGRA%' THEN CASE WHEN u.en_litros THEN 'kg' ELSE 'envase' END
                WHEN u.cod_prod LIKE 'CLULUB%' AND u.cod_prod NOT LIKE 'CLULUBWD%' THEN CASE WHEN u.en_litros THEN 'L' ELSE 'envase' END
                ELSE coalesce(u.unidad_pauta, 'un') END,
            'acumulado', round(u.q, 2), 'monto', round(u.t), 'movimientos', u.movs, 'meses_con_consumo', u.meses_con,
            'precio_ref', round(u.precio_ref), 'camiones', u.camiones, 'con_pauta', u.con_pauta,
            'pauta_12m', round(u.p12, 2), 'pauta_2027', round(u.p27, 2), 'pauta_2028', round(u.p28, 2), 'pauta_2029', round(u.p29, 2),
            'proveedor', pr.proveedor, 'n_proveedores', coalesce(np.n, 0)
        ) ORDER BY u.t DESC, u.p12 DESC NULLS LAST), '[]'::JSONB)
    ) INTO r
      FROM u
      LEFT JOIN softland_familia f6 ON f6.prefijo = left(u.cod_prod, 6)
      LEFT JOIN softland_familia f3 ON f3.prefijo = left(u.cod_prod, 3)
      LEFT JOIN prov pr ON pr.cod_prod = u.cod_prod
      LEFT JOIN nprov np ON np.cod_prod = u.cod_prod;
    RETURN r;
END $$;

-- Detalle de un insumo: meses históricos y proyectados, proveedores y camiones.
CREATE FUNCTION rpc_insumo_detalle(p_fuente TEXT, p_clave TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_fuente NOT IN ('bodega', 'oc') THEN RAISE EXCEPTION 'Fuente inválida.'; END IF;

    SELECT jsonb_build_object(
        'historico', (SELECT coalesce(jsonb_agg(jsonb_build_object('mes', m, 'cantidad', round(q, 2), 'monto', round(t)) ORDER BY m), '[]'::JSONB)
                        FROM (SELECT to_char(fecha, 'YYYY-MM') AS m, sum(cantidad) AS q, sum(total) AS t
                                FROM v_insumo_linea WHERE fuente = p_fuente AND cod_prod = p_clave AND fecha >= v_hoy - 1096 GROUP BY 1) x),
        'proyeccion', (SELECT coalesce(jsonb_agg(jsonb_build_object('mes', m, 'cantidad', round(q, 2)) ORDER BY m), '[]'::JSONB)
                         FROM (SELECT to_char(fecha, 'YYYY-MM') AS m, sum(cantidad) AS q
                                 FROM v_insumo_pauta WHERE clave = p_clave AND fecha BETWEEN v_hoy AND v_hoy + 729 GROUP BY 1) x),
        'proveedores', (SELECT coalesce(jsonb_agg(jsonb_build_object('proveedor', origen, 'cantidad', round(q, 2), 'monto', round(t), 'precio', round(t / nullif(q, 0)), 'ultima', ult) ORDER BY t DESC), '[]'::JSONB)
                          FROM (SELECT origen, sum(cantidad) AS q, sum(total) AS t, max(fecha) AS ult
                                  FROM v_insumo_linea WHERE fuente = 'oc' AND cod_prod = p_clave AND fecha >= v_hoy - 1096 AND origen IS NOT NULL GROUP BY 1) x),
        'camiones', (SELECT coalesce(jsonb_agg(jsonb_build_object('patente', patente, 'grupo', grupo_kit, 'visitas', n, 'cantidad', round(q, 2)) ORDER BY q DESC), '[]'::JSONB)
                       FROM (SELECT patente, grupo_kit, count(*) AS n, sum(cantidad) AS q
                               FROM v_insumo_pauta WHERE clave = p_clave AND fecha BETWEEN v_hoy AND v_hoy + 364 GROUP BY 1, 2) x)
    ) INTO r;
    RETURN r;
END $$;

REVOKE ALL ON FUNCTION rpc_insumos_consumo(TEXT, DATE, DATE), rpc_insumo_detalle(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_insumos_consumo(TEXT, DATE, DATE), rpc_insumo_detalle(TEXT, TEXT) TO authenticated;

SELECT count(*) AS lineas_12m, round(sum(total)) AS total_12m
  FROM v_insumo_linea WHERE fuente = 'bodega' AND fecha >= (now() AT TIME ZONE 'America/Santiago')::DATE - 365;
