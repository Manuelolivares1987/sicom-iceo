-- ============================================================================
-- MIG580 · El Excel de los trabajos del bono
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 28-09-2026: «que el sistema me descargue un Excel donde se especifiquen los
-- trabajos asignados y la duración de cada uno, para entender los cobros».
--
-- QUÉ DEVUELVE
-- Una fila por técnico × OT pagada en el corte, con todo lo que hace falta
-- para rehacer el número a mano: cuándo empezó y terminó la OT, cuántos días
-- acumuló (el tramo) y cuántos cayeron en el corte (el prorrateo), los plazos
-- del concepto, el tope del cargo, quiénes más estaban en la cuadrilla, las
-- jornadas y las horas medidas de cada uno, y los dos montos.
--
-- Si el corte ya está cerrado, el detalle sale de lo CONGELADO (lo que se
-- pagó), no de un recálculo. Las fechas y la cuadrilla se leen de la OT viva:
-- sirven para entender, no para pagar.
--
-- Pasa por el mismo candado que el resto del bono (MIG460).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_taller_bono_trabajos_excel(p_desde date, p_hasta date)
 RETURNS TABLE(
    fuente            text,
    tecnico           text,
    cargo             text,
    ot_folio          text,
    ot_tipo           text,
    equipo            text,
    concepto          text,
    concepto_nombre   text,
    fecha_inicio      timestamptz,
    fecha_termino     timestamptz,
    horas_calendario  numeric,
    dias              numeric,
    dias_en_corte     numeric,
    plazo_optimizado  numeric,
    plazo_normal      numeric,
    plazo_demora      numeric,
    tramo             text,
    tope_cargo        numeric,
    monto_ot_completa numeric,
    rol               text,
    jornadas          numeric,
    horas_medidas     numeric,
    cuadrilla         text,
    participacion     numeric,
    base_reparto      text,
    monto_formula     numeric,
    monto_propuesto   numeric,
    falta             text,
    aviso             text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_per UUID;
    v_par UUID;
BEGIN
    PERFORM fn_taller_bono_exigir_vista();

    SELECT p.id, p.parametros_id INTO v_per, v_par
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

    RETURN QUERY
    WITH filas AS (
        -- Cerrado: lo que se congeló. Abierto: el borrador de hoy.
        SELECT 'cerrado'::TEXT AS fuente, d.tecnico_id, l.tecnico, l.cargo,
               d.ot_id, d.ot_folio, d.concepto, d.dias, d.dias_en_corte, d.tramo,
               d.participacion, d.base_reparto, d.monto_formula, d.monto_propuesto,
               d.falta, d.aviso
          FROM taller_bono_periodo_detalle d
          LEFT JOIN taller_bono_periodo_linea l
                 ON l.periodo_id = d.periodo_id AND l.tecnico_id = d.tecnico_id
         WHERE v_per IS NOT NULL AND d.periodo_id = v_per
        UNION ALL
        SELECT 'borrador', b.tecnico_id, b.tecnico, b.cargo,
               b.ot_id, b.ot_folio, b.concepto, b.dias, b.dias_en_corte, b.tramo,
               b.participacion, b.base_reparto, b.monto_formula, b.monto_propuesto,
               b.falta, b.aviso
          FROM fn_taller_bono_periodo_calc(p_desde, p_hasta) b
         WHERE v_per IS NULL
    ),
    equipo_ot AS (
        SELECT r.ot_id,
               string_agg(r.tecnico || ' (' || r.jornadas || ' jor · '
                          || round(r.segundos / 3600.0, 1) || ' h)', ', '
                          ORDER BY r.tecnico) AS cuadrilla
          FROM v_taller_bono_reparto r
         WHERE r.ot_id IN (SELECT f.ot_id FROM filas f)
         GROUP BY r.ot_id
    )
    SELECT
        f.fuente,
        f.tecnico::TEXT,
        f.cargo::TEXT,
        f.ot_folio::TEXT,
        ot.tipo::TEXT,
        NULLIF(concat_ws(' · ', a.codigo, a.patente), '')::TEXT,
        f.concepto::TEXT,
        co.descripcion::TEXT,
        ot.fecha_inicio,
        ot.fecha_termino,
        round(EXTRACT(EPOCH FROM (ot.fecha_termino
              - COALESCE(ot.fecha_inicio, ot.created_at))) / 3600.0, 1),
        f.dias,
        f.dias_en_corte,
        co.dias_optimizado,
        co.dias_normal,
        co.dias_demora,
        f.tramo::TEXT,
        cg.plan_tope_clp,
        -- Lo que vale la OT cerrada en plazo optimizado, antes de repartirla.
        round(cg.plan_tope_clp * co.coef_optimizado * co.dias_optimizado),
        r.rol::TEXT,
        r.jornadas,
        round(COALESCE(r.segundos, 0) / 3600.0, 1),
        e.cuadrilla,
        f.participacion,
        f.base_reparto::TEXT,
        f.monto_formula,
        f.monto_propuesto,
        f.falta::TEXT,
        f.aviso::TEXT
      FROM filas f
      LEFT JOIN ordenes_trabajo ot ON ot.id = f.ot_id
      LEFT JOIN activos a          ON a.id = ot.activo_id
      LEFT JOIN taller_bono_concepto co
             ON co.parametros_id = v_par AND co.concepto = f.concepto
      LEFT JOIN taller_bono_cargo cg
             ON cg.parametros_id = v_par AND cg.cargo = f.cargo
      LEFT JOIN v_taller_bono_reparto r
             ON r.ot_id = f.ot_id AND r.tecnico_id = f.tecnico_id
      LEFT JOIN equipo_ot e ON e.ot_id = f.ot_id
     ORDER BY f.tecnico, f.ot_folio;
END;
$function$;

REVOKE ALL ON FUNCTION rpc_taller_bono_trabajos_excel(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_trabajos_excel(DATE, DATE) TO authenticated;

COMMIT;
