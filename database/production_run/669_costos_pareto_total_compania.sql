-- 669 — Pareto de costos: total compañía de cada familia y producto (Manuel 06-11-2026).
-- Al bajar a una faena o un equipo se perdía el orden de magnitud para comprar: ahora cada
-- familia y producto trae lo comprado (OC) y lo consumido (bodega) por toda la compañía en
-- el mismo período. Solo agrega campos; lo que ya devolvía la función no cambia. La firma
-- tampoco, así que se conservan los permisos.
CREATE OR REPLACE FUNCTION public.rpc_costos_pareto(p_desde date, p_hasta date, p_filtros jsonb, p_dimension text, p_con_admin boolean DEFAULT false, p_fuente text DEFAULT 'oc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$  -- VOLATILE: usa tabla temporal
DECLARE
    v_desde DATE := date_trunc('month', p_desde)::DATE;
    v_fin   DATE := LEAST((date_trunc('month', p_hasta) + INTERVAL '1 month - 1 day')::DATE,
                          (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    f JSONB := coalesce(p_filtros, '{}'::jsonb);
    r JSONB;
    v_meses NUMERIC;
    v_cia JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    IF p_dimension NOT IN ('faena','subfaena','equipo','familia','producto','centro_costo','mes','linea','proveedor') THEN
        RAISE EXCEPTION 'Dimensión no válida: %', p_dimension;
    END IF;

    v_meses := greatest((v_fin - v_desde + 1) / 30.4375, 1 / 30.4375);

    -- Total compañía de lo que se está mirando: mismo período, sin el filtro de faena
    -- o equipo y con todas las áreas (administración y comercial incluidas). Comprado
    -- sale de las OC y consumido de bodega, cualquiera sea la fuente elegida.
    IF coalesce(f->>'cod_prod', f->>'familia', f->>'grupo_prod') IS NOT NULL THEN
        SELECT jsonb_build_object(
            'nombre', CASE WHEN f->>'cod_prod' IS NOT NULL THEN max(v.des_prod)
                           ELSE (SELECT nombre FROM softland_familia
                                  WHERE prefijo = coalesce(f->>'familia', f->>'grupo_prod')) END,
            'unidades', f->>'cod_prod' IS NOT NULL,
            'meses', round(v_meses, 2),
            'comprado_total', coalesce(sum(v.total) FILTER (WHERE v.fuente = 'oc'), 0),
            'comprado_cantidad', coalesce(sum(v.cantidad) FILTER (WHERE v.fuente = 'oc'), 0),
            'consumido_total', coalesce(sum(v.total) FILTER (WHERE v.fuente = 'bodega'), 0),
            'consumido_cantidad', coalesce(sum(v.cantidad) FILTER (WHERE v.fuente = 'bodega'), 0))
          INTO v_cia
          FROM v_costos_linea v
         WHERE v.fecha BETWEEN v_desde AND v_fin
           AND NOT v.es_mercaderia
           AND (f->>'cod_prod' IS NULL OR v.cod_prod = f->>'cod_prod')
           AND (f->>'familia' IS NULL OR left(v.cod_prod, 6) = f->>'familia')
           AND (f->>'grupo_prod' IS NULL OR left(v.cod_prod, 3) = f->>'grupo_prod');
    END IF;

    CREATE TEMP TABLE _pl ON COMMIT DROP AS
    SELECT * FROM fn_costos_lineas(v_desde, v_fin, p_con_admin, p_fuente) l
     WHERE (f->>'faena' IS NULL OR l.faena = f->>'faena')
       AND (f->>'subfaena' IS NULL OR l.subfaena = f->>'subfaena')
       AND (f->>'activo_id' IS NULL OR l.activo_id = (f->>'activo_id')::UUID)
       AND (f->>'familia' IS NULL OR l.familia = f->>'familia')
       AND (f->>'grupo_prod' IS NULL OR l.grupo_prod = f->>'grupo_prod')
       AND (f->>'cod_prod' IS NULL OR l.cod_prod = f->>'cod_prod')
       AND (f->>'codi_cc' IS NULL
            OR (f->>'codi_cc' = '(SIN CC)' AND l.codi_cc IS NULL)
            OR l.codi_cc = ANY (string_to_array(upper(f->>'codi_cc'), ',')))
       AND (f->>'area' IS NULL OR l.area = f->>'area')
       AND (f->>'mes' IS NULL OR l.mes = (f->>'mes')::DATE)
       AND (f->>'tipo_equipo' IS NULL OR l.tipo_equipo = f->>'tipo_equipo')
       AND (f->>'proveedor' IS NULL OR l.bodega = f->>'proveedor');

    IF p_dimension = 'linea' THEN
        SELECT jsonb_build_object(
            'compania', v_cia,
            'total', (SELECT coalesce(sum(total), 0) FROM _pl),
            'lineas', (SELECT coalesce(jsonb_agg(x ORDER BY x.total DESC), '[]') FROM (
                SELECT fecha, folio, concepto, bodega, codi_cc, cod_prod, des_prod, cantidad,
                       CASE WHEN cantidad <> 0 THEN total / cantidad END AS precio_unit, total, glosa,
                       patente, subfaena
                  FROM _pl ORDER BY total DESC LIMIT 300) x)) INTO r;
        RETURN r;
    END IF;

    WITH g AS (
        SELECT CASE p_dimension
                 WHEN 'faena'        THEN faena
                 WHEN 'subfaena'     THEN subfaena
                 WHEN 'equipo'       THEN coalesce(activo_id::TEXT, 'cc:' || coalesce(codi_cc, '(SIN CC)'))
                 WHEN 'familia'      THEN familia
                 WHEN 'producto'     THEN cod_prod
                 WHEN 'centro_costo' THEN coalesce(codi_cc, '(SIN CC)')
                 WHEN 'mes'          THEN mes::TEXT
                 WHEN 'proveedor'    THEN coalesce(bodega, '(sin proveedor)')
               END AS clave,
               CASE p_dimension
                 WHEN 'equipo'       THEN coalesce(patente, cc_desc, codi_cc, 'Sin centro de costo')
                 WHEN 'familia'      THEN coalesce((SELECT nombre FROM softland_familia WHERE prefijo = familia),
                                                   (SELECT nombre FROM softland_familia WHERE prefijo = grupo_prod), familia)
                 WHEN 'producto'     THEN des_prod
                 WHEN 'centro_costo' THEN coalesce(cc_desc, codi_cc, 'Sin centro de costo')
                 ELSE NULL
               END AS etiqueta,
               total, cantidad
          FROM _pl
    ), a AS (
        SELECT clave, max(etiqueta) AS etiqueta, sum(total) AS total, sum(cantidad) AS cantidad, count(*) AS lineas
          FROM g GROUP BY clave
    ), o AS (
        SELECT a.*,
               100.0 * total / nullif(sum(total) OVER (), 0) AS pct,
               100.0 * sum(total) OVER (ORDER BY total DESC, clave ROWS UNBOUNDED PRECEDING)
                     / nullif(sum(total) OVER (), 0) AS pct_acum,
               row_number() OVER (ORDER BY total DESC, clave) AS rk
          FROM a
    ), cia AS (
        -- Solo familia y producto: «total compañía» de una faena o un equipo no significa nada.
        SELECT CASE p_dimension WHEN 'familia' THEN left(v.cod_prod, 6) ELSE v.cod_prod END AS clave,
               coalesce(sum(v.total) FILTER (WHERE v.fuente = 'oc'), 0)         AS comprado_total,
               coalesce(sum(v.cantidad) FILTER (WHERE v.fuente = 'oc'), 0)      AS comprado_cantidad,
               coalesce(sum(v.total) FILTER (WHERE v.fuente = 'bodega'), 0)     AS consumido_total,
               coalesce(sum(v.cantidad) FILTER (WHERE v.fuente = 'bodega'), 0)  AS consumido_cantidad
          FROM v_costos_linea v
         WHERE p_dimension IN ('familia', 'producto')
           AND v.fecha BETWEEN v_desde AND v_fin
           AND NOT v.es_mercaderia
         GROUP BY 1
    )
    SELECT jsonb_build_object(
        'dimension', p_dimension,
        'compania', v_cia,
        'meses', round(v_meses, 2),
        'total', (SELECT coalesce(sum(total), 0) FROM a),
        'n', (SELECT count(*) FROM a),
        -- Cuántos ítems hacen el 80 %: el primero que cruza el 80 % también cuenta.
        'vitales', (SELECT coalesce(min(rk), 0) FROM o WHERE pct_acum >= 80),
        'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'clave', clave, 'etiqueta', coalesce(etiqueta, clave), 'total', total,
                     'cantidad', cantidad, 'lineas', lineas, 'pct', pct, 'pct_acum', pct_acum,
                     'cia', CASE WHEN p_dimension IN ('familia', 'producto') THEN jsonb_build_object(
                         'comprado_total', coalesce(c.comprado_total, 0),
                         'comprado_cantidad', coalesce(c.comprado_cantidad, 0),
                         'consumido_total', coalesce(c.consumido_total, 0),
                         'consumido_cantidad', coalesce(c.consumido_cantidad, 0)) END)
                   ORDER BY rk), '[]') FROM o LEFT JOIN cia c USING (clave) WHERE rk <= 40),
        'resto', (SELECT jsonb_build_object('n', count(*), 'total', coalesce(sum(total), 0)) FROM o WHERE rk > 40)
    ) INTO r;
    RETURN r;
END $function$;
