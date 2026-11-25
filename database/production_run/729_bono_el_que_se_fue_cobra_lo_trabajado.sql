-- ============================================================================
-- MIG729 · Bono del taller: el que se fue cobra lo que trabajó
-- ============================================================================
--
-- POR QUÉ
-- El resumen (y por lo tanto el CIERRE, que congela desde el resumen) partía
-- de la lista de KPI, y la KPI sólo trae personal activo. Al marcar a Joel Coo
-- como inactivo (MIG728) sus $33.456 en trabajos del corte 24-10 → 23-11
-- desaparecían de la liquidación. «A cada viejo se le paga lo que corresponde».
--
-- QUÉ CAMBIA
-- El resumen junta KPI y trabajos con FULL JOIN. Quien no está en la KPI
-- (inactivo) pero tiene trabajos en el corte aparece con sus trabajos, KPI 0
-- y el tope de su cargo completo. Quien no tiene ni lo uno ni lo otro no
-- aparece, como hasta hoy.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_taller_bono_resumen_calc(p_desde date, p_hasta date, p_disponibilidad numeric DEFAULT NULL::numeric)
 RETURNS TABLE(tecnico_id uuid, tecnico text, cargo text, ots integer, plan_formula numeric, plan_calculado numeric, plan_tope numeric, plan_pagado numeric, kpi_pagado numeric, total numeric, dias_cargo integer, dias_corte integer, disponibilidad numeric, tramo text, falta text, aviso text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_par UUID;
    v_dias INT := (p_hasta - p_desde) + 1;
BEGIN
    SELECT id INTO v_par FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    RETURN QUERY
    WITH plan AS (
        SELECT b.tecnico_id AS tid,
               max(b.tecnico) AS tecnico,
               max(b.cargo)   AS cargo,
               count(*)::INT AS ots,
               sum(b.monto_formula)   AS f,
               sum(b.monto_propuesto) AS p,
               string_agg(DISTINCT b.falta, ' · ') AS falta,
               string_agg(DISTINCT b.aviso, ' · ') AS aviso
          FROM fn_taller_bono_periodo_calc(p_desde, p_hasta) b
         GROUP BY b.tecnico_id
    ),
    kpi AS (
        SELECT * FROM fn_taller_bono_kpi_periodo_calc(p_desde, p_hasta, p_disponibilidad)
    ),
    junto AS (
        SELECT COALESCE(k.tecnico_id, pl.tid)    AS tid,
               COALESCE(k.tecnico, pl.tecnico)   AS tecnico,
               COALESCE(k.cargo, pl.cargo)       AS cargo,
               -- [MIG729] Sin fila de KPI (ya no está): tope del cargo completo.
               COALESCE(k.prorrateo, 1.0)        AS prorrateo,
               k.monto_kpi,
               COALESCE(k.dias_cargo, v_dias)    AS dias_cargo,
               COALESCE(k.dias_corte, v_dias)    AS dias_corte,
               k.disponibilidad, k.tramo,
               k.falta AS k_falta,
               k.tecnico_id IS NULL              AS fuera_de_kpi,
               pl.ots, pl.f, pl.p, pl.falta AS p_falta, pl.aviso AS p_aviso
          FROM kpi k
          FULL JOIN plan pl ON pl.tid = k.tecnico_id
    )
    SELECT
        j.tid,
        j.tecnico,
        j.cargo,
        COALESCE(j.ots, 0),
        j.f,
        j.p,
        round(cg.plan_tope_clp * j.prorrateo),
        LEAST(COALESCE(j.p, 0), round(cg.plan_tope_clp * j.prorrateo)),
        CASE WHEN j.fuera_de_kpi THEN 0 ELSE j.monto_kpi END,
        LEAST(COALESCE(j.p, 0), round(cg.plan_tope_clp * j.prorrateo))
            + COALESCE(CASE WHEN j.fuera_de_kpi THEN 0 ELSE j.monto_kpi END, 0),
        j.dias_cargo,
        j.dias_corte,
        j.disponibilidad,
        j.tramo,
        -- Bloquea el cierre.
        NULLIF(concat_ws(' · ', j.k_falta, j.p_falta), ''),
        -- Sólo informa.
        NULLIF(concat_ws(' · ',
            CASE WHEN j.fuera_de_kpi
                 THEN 'ya no está en el taller: se le pagan sus trabajos, sin KPI' END,
            j.p_aviso,
            CASE WHEN COALESCE(j.p, 0) > round(cg.plan_tope_clp * j.prorrateo)
                 THEN 'la suma de las OT pasa el tope del cargo: se paga el tope' END
        ), '')
      FROM junto j
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = j.cargo
     ORDER BY j.tecnico;
END;
$function$;

COMMIT;
