-- ============================================================================
-- MIG728 · Bono del taller: cada uno cobra lo que le corresponde
-- ============================================================================
--
-- LO QUE DECIDIÓ MANUEL (25-11-2026)
-- «Jorge Vargas es mecánico A, no hagas reparto de jornada, a cada viejo se le
-- paga lo que corresponde». Confirmado: «Sí, cada uno su trabajo completo».
-- «Brian se fue, Joel Coo también».
--
-- 1. Jorge Vargas no tenía cargo → sus líneas salían con «falta el cargo del
--    técnico» y bloqueaban el cierre. Queda Mecánico A desde el 28-10-2026
--    (día en que entró al sistema y a su primera cuadrilla).
--
-- 2. Se termina el reparto (reemplaza D2 de MIG483). Antes la línea de una OT
--    se partía entre la cuadrilla (tiempo medido, jornadas asignadas o partes
--    iguales). Ahora cada persona de la cuadrilla cobra la línea entera según
--    SU cargo: participación = 1. El tope por cargo de fn_taller_bono_resumen
--    sigue aplicando.
--
-- 3. Joel Coo sale del taller (activo = FALSE). Brian Alday ya estaba inactivo.
--    Su cargo NO se cierra: los trabajos que hicieron y que se cierran en el
--    corte se les siguen pagando. La mitad KPI, por regla existente, sólo la
--    cobra el personal activo.
--
-- Quién cobra sigue saliendo de taller_ot_cuadrilla (jefatura); el auditor
-- (participa_en_bono = FALSE) sigue fuera. No hay cortes cerrados: nada
-- congelado cambia.
-- ============================================================================

BEGIN;

-- ── 1. Cargo de Jorge Vargas ────────────────────────────────────────────────
INSERT INTO taller_tecnico_cargo (tecnico_id, cargo, desde, hasta)
SELECT t.id, 'Mecanico A', DATE '2026-10-28', NULL
  FROM taller_tecnicos t
 WHERE t.id = 'bcb33c21-edbb-4ef8-b1f7-3faa539c7db9'
   AND NOT EXISTS (SELECT 1 FROM taller_tecnico_cargo c WHERE c.tecnico_id = t.id);

-- ── 2. Joel Coo deja el taller ──────────────────────────────────────────────
UPDATE taller_tecnicos SET activo = FALSE
 WHERE id = 'f7418871-1ee7-4d48-8495-6027832b6619';

-- ── 3. Sin reparto: participación 1 para cada persona ───────────────────────
CREATE OR REPLACE VIEW v_taller_bono_reparto AS
 SELECT ot_id, ot_folio, ot_estado, fecha_termino, ejecutada_por_externo,
        genera_bono, tecnico_id, tecnico, rol, segundos, participacion,
        base_reparto, jornadas
   FROM ( WITH cuadrilla AS (
                 SELECT po.ot_id, c.tecnico_id, min(c.rol) AS rol,
                        count(*)::numeric AS jornadas
                   FROM taller_ot_cuadrilla c
                   JOIN taller_plan_semanal_ots po ON po.id = c.plan_ot_id
                  GROUP BY po.ot_id, c.tecnico_id
                ), tiempos AS (
                 SELECT e.ot_id, e.tecnico_id,
                        COALESCE(sum(e.tiempo_efectivo_segundos), 0::bigint)::numeric AS segundos
                   FROM taller_ot_ejecuciones e
                  WHERE e.tecnico_id IS NOT NULL
                  GROUP BY e.ot_id, e.tecnico_id
                ), base AS (
                 SELECT ot.id AS ot_id, ot.folio AS ot_folio, ot.estado::text AS ot_estado,
                        ot.fecha_termino, ot.ejecutada_por_externo,
                        cu.tecnico_id, t.nombre AS tecnico, cu.rol, cu.jornadas,
                        COALESCE(ti.segundos, 0::numeric) AS segundos,
                        count(*) OVER (PARTITION BY ot.id) AS n_cuadrilla
                   FROM cuadrilla cu
                   JOIN ordenes_trabajo ot ON ot.id = cu.ot_id
                   JOIN taller_tecnicos t ON t.id = cu.tecnico_id
                   LEFT JOIN tiempos ti ON ti.ot_id = cu.ot_id AND ti.tecnico_id = cu.tecnico_id
                  WHERE COALESCE(t.participa_en_bono, true)
                )
         SELECT b.ot_id, b.ot_folio, b.ot_estado, b.fecha_termino, b.ejecutada_por_externo,
                b.ejecutada_por_externo IS FALSE AS genera_bono,
                b.tecnico_id, b.tecnico, b.rol, b.segundos,
                round(1.0, 4) AS participacion,
                CASE WHEN b.n_cuadrilla > 1 THEN 'línea completa a cada uno'::text
                     ELSE 'individual'::text END AS base_reparto,
                b.jornadas
           FROM base b) _mig728
  WHERE fn_puede_ver_remuneraciones();

-- ── 4. El cálculo: sin el aviso «reparto por …» ─────────────────────────────
-- Mismo RETURNS que MIG579 → la puerta fn_taller_bono_periodo no cambia.
CREATE OR REPLACE FUNCTION public.fn_taller_bono_periodo_calc(p_desde date, p_hasta date)
 RETURNS TABLE(tecnico_id uuid, tecnico text, cargo text, ot_id uuid, ot_folio text, concepto text, dias numeric, tramo text, participacion numeric, base_reparto text, monto_formula numeric, monto_propuesto numeric, falta text, aviso text, dias_en_corte numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_par UUID;
BEGIN
    SELECT id INTO v_par FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran el período % a %.', p_desde, p_hasta;
    END IF;

    RETURN QUERY
    WITH cerradas AS (
        SELECT ot.id, ot.folio::TEXT AS folio,
               ot.fecha_inicio, ot.fecha_termino,
               fn_taller_ot_concepto(ot.id) AS concepto,
               GREATEST(1, CEIL(EXTRACT(EPOCH FROM (
                   ot.fecha_termino - COALESCE(ot.fecha_inicio, ot.created_at)
               )) / 86400.0))::NUMERIC AS dias,
               -- [MIG480 · D5] Los días de ESTA OT que caen dentro del corte.
               GREATEST(0, (LEAST(ot.fecha_termino::DATE, p_hasta)
                          - GREATEST(COALESCE(ot.fecha_inicio, ot.created_at)::DATE, p_desde)) + 1
               )::NUMERIC AS dias_en_corte
          FROM ordenes_trabajo ot
         WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
           AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta
           AND NOT COALESCE(ot.ejecutada_por_externo, FALSE)
           -- [MIG472] Un cierre con tareas pendientes no paga hasta que la
           -- jefatura lo valide.
           AND COALESCE(ot.cierre_validacion_estado, 'validado') <> 'por_validar'
    ),
    reparto AS (
        SELECT r.ot_id, r.tecnico_id, r.tecnico, r.participacion, r.base_reparto
          FROM v_taller_bono_reparto r
    )
    SELECT
        rp.tecnico_id,
        rp.tecnico::TEXT,
        tc.cargo,
        c.id,
        c.folio,
        c.concepto,
        c.dias,
        CASE
            WHEN co.concepto IS NULL THEN NULL
            WHEN c.dias <= co.dias_optimizado THEN 'optimizado'
            WHEN c.dias <= co.dias_normal     THEN 'normal'
            WHEN c.dias <= co.dias_demora     THEN 'con demora'
            ELSE 'fuera de plazo'
        END,
        rp.participacion,
        rp.base_reparto,
        -- La fórmula tal como está hoy en la planilla, sin corregir.
        CASE WHEN cg.plan_tope_clp IS NULL OR co.concepto IS NULL THEN NULL
             ELSE round(rp.participacion * cg.plan_tope_clp * CASE
                 WHEN c.dias <= co.dias_optimizado THEN co.coef_optimizado * co.dias_optimizado
                 WHEN c.dias <= co.dias_normal     THEN c.dias * co.coef_por_dia
                 ELSE (co.dias_demora - c.dias) * co.coef_por_dia
             END)
        END,
        -- La versión corregida: monótona, nunca negativa.
        CASE WHEN cg.plan_tope_clp IS NULL OR co.concepto IS NULL THEN NULL
             ELSE round(rp.participacion * cg.plan_tope_clp * co.coef_optimizado * co.dias_optimizado
                        -- [MIG480 · D5] La parte del trabajo que cae en el corte.
                        * LEAST(1.0, c.dias_en_corte / NULLIF(c.dias, 0))
                        * GREATEST(0, CASE
                 WHEN c.dias <= co.dias_optimizado THEN 1.0
                 WHEN c.dias <= co.dias_normal
                     THEN 1.0 - 0.4 * (c.dias - co.dias_optimizado)
                                    / NULLIF(co.dias_normal - co.dias_optimizado, 0)
                 WHEN c.dias <= co.dias_demora
                     THEN 0.6 - 0.6 * (c.dias - co.dias_normal)
                                    / NULLIF(co.dias_demora - co.dias_normal, 0)
                 ELSE 0.0
             END))
        END,
        -- `falta` es lo que IMPIDE pagar. Bloquea el cierre del período.
        NULLIF(concat_ws(' · ',
            CASE WHEN tc.cargo IS NULL THEN 'falta el cargo del técnico' END,
            CASE WHEN c.concepto IS NULL THEN 'no se pudo deducir el concepto' END
        ), ''),
        -- `aviso` es lo que hay que SABER. No bloquea nada.
        NULLIF(concat_ws(' · ',
            -- [MIG728] Ya no hay reparto: cada uno cobra su línea completa.
            CASE WHEN rp.base_reparto = 'línea completa a cada uno'
                 THEN 'trabajo compartido: cada uno cobra su línea completa' END,
            CASE WHEN c.dias_en_corte < c.dias
                 THEN 'viene de antes del corte: se paga ' || c.dias_en_corte || ' de ' || c.dias || ' días' END
        ), ''),
        c.dias_en_corte
      FROM cerradas c
      JOIN reparto rp ON rp.ot_id = c.id
      LEFT JOIN taller_tecnico_cargo tc
             ON tc.tecnico_id = rp.tecnico_id
            AND tc.desde <= p_hasta AND (tc.hasta IS NULL OR tc.hasta >= p_desde)
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = tc.cargo
      LEFT JOIN taller_bono_concepto co ON co.parametros_id = v_par AND co.concepto = c.concepto
      -- [MIG463] Quien ya no está en el taller y nunca tuvo cargo no genera línea.
      JOIN taller_tecnicos tt ON tt.id = rp.tecnico_id
     WHERE COALESCE(tt.activo, TRUE) OR tc.cargo IS NOT NULL
     ORDER BY rp.tecnico, c.folio;
END;
$function$;

-- ── 5. El acta queda escrita ────────────────────────────────────────────────
UPDATE taller_bono_acta
   SET decision = 'Sin reparto: cada persona de la cuadrilla cobra la línea completa según su cargo '
                  '(reemplaza el reparto por tiempo medido del 01-09).',
       estado = 'resuelta',
       resuelta_por = 'Manuel Olivares',
       resuelta_at = NOW(),
       nota = COALESCE(nota, '') || ' | 25-11-2026 (MIG728): «no hagas reparto de jornada, a cada '
              'viejo se le paga lo que corresponde». Sigue aplicando el tope por cargo.'
 WHERE codigo = 'D2';

UPDATE taller_bono_parametros
   SET notas = replace(notas,
        'D2 resuelta el 01-09: el trabajo compartido se reparte por tiempo medido, sin bono adicional.',
        'D2 cambiada el 25-11 (MIG728): sin reparto, cada uno cobra su línea completa según su cargo.')
 WHERE estado = 'vigente';

COMMIT;
