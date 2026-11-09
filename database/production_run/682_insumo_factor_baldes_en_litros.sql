-- 682 — Corrige la conversión a litros de la MIG681 (09-11-2026).
-- La regla «BIDON o BALDE = se cuenta por envase» multiplicaba de nuevo a los lubricantes
-- que Softland ya tenía en litros: 40 L de LDF-3 a $5.669 el litro quedaban en 800 L.
-- En lubricantes y grasas manda solo el precio. La regla del envase queda para los dos
-- productos baratos que sí se cuentan por bidón (AdBlue y limpiaparabrisas).

CREATE OR REPLACE FUNCTION fn_insumo_factor(p_cod TEXT, p_des TEXT, p_precio NUMERIC) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
    SELECT CASE
        WHEN NOT (p_cod LIKE 'CLULUB%' OR p_cod LIKE 'CLUGRA%' OR p_cod IN ('AFEADIABL001','AFEFERALP001')) THEN 1
        WHEN fn_insumo_contenido(p_des) IS NULL THEN 1
        WHEN p_cod IN ('AFEADIABL001','AFEFERALP001') THEN CASE WHEN upper(p_des) ~ 'BIDON|BALDE' THEN fn_insumo_contenido(p_des) ELSE 1 END
        WHEN p_precio >= 15000 THEN fn_insumo_contenido(p_des)
        ELSE 1
    END
$$;

SELECT round(sum(cantidad)) AS ldf3_litros_12m
  FROM v_insumo_linea
 WHERE fuente = 'bodega' AND cod_prod = 'CLULUBACE085'
   AND fecha >= (now() AT TIME ZONE 'America/Santiago')::DATE - 365;
