-- 683 — Litros y rótulos verificados de los lubricantes de las pautas (Manuel 09-11-2026).
-- Fuente: reports/Lubricantes por modelo flota Pillado.md. Lo que depende de leer la placa
-- queda marcado provisorio: Renault completo y todas las cajas.
-- Nota: el Presupuesto toma estos kits cuando se presione «Recalcular»; no se recalcula aquí.

ALTER TABLE ppto_kit_item ADD COLUMN provisorio BOOLEAN NOT NULL DEFAULT false;

-- Mack: 37 L es el volumen de cambio (42 L es el nominal con motor seco).
UPDATE ppto_kit_item SET cantidad = 37, item = 'Aceite motor 15W-40 Mack EOS-4.5 (cambio 37 L con filtros)'
 WHERE grupo_kit IN ('MACK_GU813_ALLISON','MACK_GU813_MEC') AND item LIKE 'Aceite motor 15W-40 Mack EOS-4.5%';

-- El refrigerante ANUAL de Mack dice «si no llegó a SM3», pero se contaba siempre.
UPDATE ppto_kit_item SET cantidad = 0
 WHERE grupo_kit IN ('MACK_GU813_ALLISON','MACK_GU813_MEC') AND nivel = 'ANUAL' AND item LIKE 'Refrigerante fully-formulated%';

-- Mercedes: los documentos Kaufmann admiten 228.3 15W-40, que es lo que apunta el código.
UPDATE ppto_kit_item SET item = 'Aceite motor MB 228.3 15W-40 (Delvac)'
 WHERE grupo_kit IN ('MB_ACCELO','MB_ACTROS_3336K','MB_ATEGO','MB_AXOR') AND item LIKE 'Aceite motor MB 228.5 10W-40%';
UPDATE ppto_kit_item SET cantidad = 29.3 WHERE grupo_kit = 'MB_AXOR' AND item = 'Aceite motor MB 228.3 15W-40 (Delvac)';
UPDATE ppto_kit_item SET cantidad = 29   WHERE grupo_kit = 'MB_ATEGO' AND item = 'Aceite motor MB 228.3 15W-40 (Delvac)';

-- Scania: se compra y está autorizado LDF-3; LDF-4 10W-40 no existe en Softland.
UPDATE ppto_kit_item SET item = 'Aceite motor Scania LDF-3 10W-40', cod_softland = 'CLULUBACE085', precio_ref = 4751, precio_vivo = false
 WHERE grupo_kit = 'SCANIA_P450' AND item LIKE 'Aceite motor Scania LDF-4%';

-- Renault y Volvo: el código y lo que se usa son 10W-30.
UPDATE ppto_kit_item SET item = 'Aceite motor Renault RLD-3 10W-30 (37 L)'
 WHERE grupo_kit = 'RENAULT_C440' AND item LIKE 'Aceite motor 15W-40 Renault%';
UPDATE ppto_kit_item SET item = 'Aceite motor Volvo VDS-4.5 10W-30'
 WHERE grupo_kit IN ('VOLVO_FMX','VOLVO_VM') AND item LIKE 'Aceite motor 15W-40 Volvo%';

-- FMX: el relleno de 2 L corresponde solo al SL; en un cambio se sumaba sobre los 37 L.
UPDATE ppto_kit_item SET cantidad = 0
 WHERE grupo_kit = 'VOLVO_FMX' AND item = 'Aceite motor relleno VDS-4.5' AND nivel <> 'SL';

-- Cajas: publicado cerca de 16 L, sujeto a confirmar modelo.
UPDATE ppto_kit_item SET cantidad = 16 WHERE grupo_kit IN ('RENAULT_C440','VOLVO_FMX') AND item LIKE 'Aceite caja%' AND cantidad = 14.3;

UPDATE ppto_kit_item SET provisorio = true
 WHERE unidad IN ('L','kg')
   AND ((grupo_kit = 'RENAULT_C440' AND item ~ '^(Aceite|Refrigerante)') OR item LIKE 'Aceite caja%');

CREATE OR REPLACE VIEW v_insumo_pauta AS
SELECT coalesce(p.cod_prod, CASE WHEN k.cod_softland = 'cotizar'
                                 THEN regexp_replace(k.item, '\s*\(.*$', '') || ' · ' || c.grupo_kit
                                 ELSE regexp_replace(k.item, '\s*\(.*$', '') END) AS clave,
       p.cod_prod,
       regexp_replace(k.item, '\s*\(.*$', '') AS item,
       k.unidad, k.precio_ref, k.cantidad, c.patente, c.grupo_kit, v.fecha, v.anio, v.mes, v.nivel,
       k.provisorio
  FROM ppto_visita v
  JOIN ppto_camion c USING (patente)
  JOIN ppto_kit_item k ON k.grupo_kit = c.grupo_kit AND k.nivel = v.nivel
  LEFT JOIN LATERAL (SELECT k.cod_softland AS cod_prod WHERE k.cod_softland ~ '^[A-Z]{6}[A-Z0-9]*\d$') p ON true
 WHERE k.unidad NOT IN ('servicio', 'muestra');
REVOKE ALL ON v_insumo_pauta FROM PUBLIC, anon, authenticated;

-- Agrega «provisorio» y ubica en su familia a los lubricantes y grasas sin código Softland.
CREATE OR REPLACE FUNCTION rpc_insumos_consumo(p_fuente TEXT, p_desde DATE, p_hasta DATE) RETURNS JSONB
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
               count(DISTINCT patente) FILTER (WHERE cantidad > 0) AS camiones,
               coalesce(bool_or(provisorio) FILTER (WHERE cantidad > 0), false) AS provisorio,
               sum(cantidad) FILTER (WHERE fecha BETWEEN v_hoy AND v_hoy + 364) AS p12,
               sum(cantidad) FILTER (WHERE anio = 2027) AS p27,
               sum(cantidad) FILTER (WHERE anio = 2028) AS p28,
               sum(cantidad) FILTER (WHERE anio = 2029) AS p29
          FROM v_insumo_pauta GROUP BY 1
    ), nombre AS (
        SELECT DISTINCT ON (cod_prod) cod_prod, des_prod
          FROM v_insumo_linea WHERE cod_prod IN (SELECT cod_prod FROM pauta WHERE cod_prod IS NOT NULL)
         ORDER BY cod_prod, fecha DESC
    ), u AS (
        SELECT coalesce(h.cod_prod, pa.clave) AS clave,
               coalesce(h.cod_prod, pa.cod_prod) AS cod_prod,
               coalesce(h.des, n.des_prod, pa.item) AS descripcion,
               coalesce(h.q, 0) AS q, coalesce(h.t, 0) AS t, coalesce(h.movs, 0) AS movs, coalesce(h.meses_con, 0) AS meses_con,
               h.en_litros, pa.unidad AS unidad_pauta, pa.precio_ref, coalesce(pa.camiones, 0) AS camiones,
               pa.p12, pa.p27, pa.p28, pa.p29, pa.clave IS NOT NULL AS con_pauta,
               pa.item AS item_pauta, coalesce(pa.provisorio, false) AS provisorio
          FROM hist h
          FULL JOIN pauta pa ON pa.cod_prod = h.cod_prod
          LEFT JOIN nombre n ON n.cod_prod = pa.cod_prod
    )
    SELECT jsonb_build_object(
        'calculado_at', (SELECT calculado_at FROM ppto_version WHERE id = 1),
        'items', coalesce(jsonb_agg(jsonb_build_object(
            'clave', u.clave, 'cod_prod', u.cod_prod, 'descripcion', u.descripcion,
            'familia', coalesce(f6.nombre, f3.nombre, CASE
                WHEN u.item_pauta ~* '^grasa' THEN 'Grasas'
                WHEN u.item_pauta ~* '^(aceite|refrigerante)' THEN 'Lubricantes'
                ELSE 'Sin código Softland' END),
            'unidad', CASE
                WHEN u.en_litros IS NULL THEN coalesce(u.unidad_pauta, 'un')
                WHEN u.cod_prod LIKE 'CLUGRA%' THEN CASE WHEN u.en_litros THEN 'kg' ELSE 'envase' END
                WHEN u.cod_prod LIKE 'CLULUB%' AND u.cod_prod NOT LIKE 'CLULUBWD%' THEN CASE WHEN u.en_litros THEN 'L' ELSE 'envase' END
                ELSE coalesce(u.unidad_pauta, 'un') END,
            'acumulado', round(u.q, 2), 'monto', round(u.t), 'movimientos', u.movs, 'meses_con_consumo', u.meses_con,
            'precio_ref', round(u.precio_ref), 'camiones', u.camiones, 'con_pauta', u.con_pauta, 'provisorio', u.provisorio,
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

SELECT grupo_kit, round(sum(cantidad)) AS litros_motor_12m
  FROM v_insumo_pauta
 WHERE item LIKE 'Aceite motor%' AND fecha BETWEEN (now() AT TIME ZONE 'America/Santiago')::DATE AND (now() AT TIME ZONE 'America/Santiago')::DATE + 364
 GROUP BY 1 ORDER BY 1;
