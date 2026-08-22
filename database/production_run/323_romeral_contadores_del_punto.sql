-- ============================================================================
-- MIG323 · Un punto sin ninguna lectura no puede aparecer como completo
-- ----------------------------------------------------------------------------
-- EL ERROR
--   En v_comb_faena_cierre_punto, `medidores_total` contaba las filas de
--   combustible_faena_cierre_medidor — es decir, los contadores que alguien
--   ANOTÓ en ese cierre. No los que el punto TIENE.
--
--   Consecuencia: si nadie tocaba los contadores de un punto, el resultado era
--   `0 de 0`, que MIG322 interpretaba como "todos leídos" y por lo tanto
--   comparable. La prueba lo mostró: Mina 1 con sus dos contadores en blanco
--   salió "cuadrado", con v_mec = 0 y una diferencia de 8.250 L que nadie iba
--   a mirar porque el semáforo estaba verde.
--
--   Es el caso exacto de los días 7 y 8 de agosto en el libro: varilla medida,
--   numeral en blanco. Ese día no cuadró ni descuadró — no se puede saber, y el
--   sistema tiene que decir eso y no otra cosa.
--
-- EL ARREGLO
--   `medidores_total` sale del maestro de contadores del punto.
--   `medidores_leidos` sale del cierre, contando sólo los que tienen numeral
--   final. Así `0 de 2` es lo que es: un punto sin control cruzado.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_comb_faena_cierre_punto AS
SELECT
    c.id                AS cierre_id,
    c.faena_id,
    c.fecha,
    c.turno,
    c.estado,
    c.medido_por,
    e.id                AS estanque_id,
    e.codigo            AS estanque_codigo,
    e.nombre            AS estanque_nombre,
    e.clave_cierre,
    e.orden_cierre,
    e.tipo              AS estanque_tipo,
    e.capacidad_lt,
    e.capacidad_llenado_lt,
    p.mi, p.rfp, p.rt, p.mf, p.agua_mm, p.temperatura_c,
    p.sin_medicion, p.motivo_sin_medicion,
    (COALESCE(p.mi,0) + COALESCE(p.rfp,0) + COALESCE(p.rt,0) - COALESCE(p.mf,0)) AS v_fis,
    COALESCE(m.v_mec, 0) AS v_mec,
    COALESCE(m.v_mec, 0)
      - (COALESCE(p.mi,0) + COALESCE(p.rfp,0) + COALESCE(p.rt,0) - COALESCE(p.mf,0)) AS var1,
    -- Cuántos contadores TIENE el punto. Del maestro, no del cierre: si sale
    -- del cierre, un punto que nadie tocó dice "0 de 0" y parece completo.
    COALESCE(md.total, 0)  AS medidores_total,
    COALESCE(m.leidos, 0)  AS medidores_leidos,
    CASE WHEN e.capacidad_llenado_lt > 0 AND p.mf IS NOT NULL
         THEN ROUND(p.mf / e.capacidad_llenado_lt, 4) END AS pct_llenado
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
JOIN combustible_estanques e          ON e.id = p.estanque_id
LEFT JOIN LATERAL (
    SELECT COUNT(*)::int AS total
      FROM combustible_faena_medidores x
     WHERE x.estanque_id = e.id AND x.activo
) md ON TRUE
LEFT JOIN LATERAL (
    SELECT SUM(COALESCE(cm.numeral_fin,0) - COALESCE(cm.numeral_ini,0) - COALESCE(cm.calibracion,0))
             FILTER (WHERE cm.numeral_fin IS NOT NULL)                     AS v_mec,
           COUNT(*) FILTER (WHERE cm.numeral_fin IS NOT NULL)::int         AS leidos
      FROM combustible_faena_cierre_medidor cm
      JOIN combustible_faena_medidores mdd ON mdd.id = cm.medidor_id
     WHERE cm.cierre_id = c.id AND mdd.estanque_id = e.id
) m ON TRUE;

GRANT SELECT ON public.v_comb_faena_cierre_punto TO authenticated;

COMMENT ON VIEW public.v_comb_faena_cierre_punto IS
  'Cierre fisico por punto. medidores_total sale del maestro del punto, no del cierre: un punto sin lecturas dice "0 de 2" y no "0 de 0". MIG323.';

COMMIT;
