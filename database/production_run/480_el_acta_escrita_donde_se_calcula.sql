-- ============================================================================
-- MIG480 · El acta, escrita donde se calcula
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «pregúntame las decisiones del acta». Contestó las seis que
-- bloqueaban el cierre. Esta migración las deja escritas y las aplica.
--
-- LO QUE DECIDIÓ, LITERAL
--
--   D1 · Qué documento rige.
--        «Agosto ya está cerrado, con septiembre la idea es seguir la pauta del
--        2025». Rige la Estructura KPI 2025 escrita. Agosto no se toca: lo
--        pagado, pagado. Los parámetros salen de borrador y quedan vigentes.
--
--   D2 · Si el segundo técnico genera bono propio.
--        QUEDA ABIERTA. «Requiere más análisis... porque en rigor ambos
--        trabajaron». Hasta que se resuelva sigue el reparto de MIG462: el
--        tiempo medido de cada uno, que ya reconoce a los dos cuando los dos
--        marcaron reloj.
--
--   D4 · Un servicio, un concepto. La hoja «Definiciones» los describe como
--        excluyentes, y el sistema ya lo hace estructuralmente: el concepto es
--        una columna de la OT. Queda escrito para que no se «mejore» después.
--
--   D5 · Los días del tramo son los ACUMULADOS desde que se abrió el trabajo;
--        el monto se prorratea por los días que caen en el corte. Con la regla
--        anterior, una OT arrastrada tres meses nunca entraba en demora y
--        además cobraba entera en el mes en que se cerraba.
--
--   D6 · El KPI y el plan se prorratean por días de contrato, con mes comercial
--        de 30 días. Antes el divisor eran los días reales del corte, así que
--        la misma persona tenía dos reglas distintas en la misma liquidación.
--
--   D14 · Tope y curva, las dos. El motor ya calculaba la versión corregida en
--        `monto_propuesto` y aplicaba el tope en `plan_pagado`; lo que faltaba
--        era el acta que dice que ESO es lo que se paga. Queda declarado.
--
-- PRINCIPIO QUE SE MANTIENE
-- Una decisión de criterio cambia una fila, no una migración. Por eso el acta
-- es una tabla: la próxima decisión se escribe, no se programa.
-- ============================================================================

BEGIN;

-- ── 1 · El acta ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_bono_acta (
    codigo       TEXT PRIMARY KEY,
    pregunta     TEXT NOT NULL,
    decision     TEXT,
    estado       TEXT NOT NULL DEFAULT 'abierta'
                 CHECK (estado IN ('abierta','resuelta')),
    bloqueante   BOOLEAN NOT NULL DEFAULT FALSE,
    resuelta_por TEXT,
    resuelta_at  TIMESTAMPTZ,
    nota         TEXT
);

COMMENT ON TABLE taller_bono_acta IS
    'Las decisiones de criterio del bono, con quien las tomo y cuando. Lo que '
    'se le puede mostrar a un trabajador que pregunta por que le pagaron eso.';

INSERT INTO taller_bono_acta (codigo, pregunta, decision, estado, bloqueante, resuelta_por, resuelta_at, nota)
VALUES
 ('D1','Que documento rige las bases y los topes del bono',
  'Rige la Estructura KPI 2025 escrita. Agosto queda cerrado como se pago; desde septiembre manda el documento.',
  'resuelta', TRUE, 'Manuel Olivares', NOW(),
  'Diferencia medida: el KPI de los tres Mecanico A pasa de $24.000 a $30.000. $15.800 a favor de los trabajadores.'),
 ('D2','Cuando dos tecnicos trabajan la misma OS, el segundo genera bono propio?',
  NULL, 'abierta', TRUE, NULL, NULL,
  'Manuel pidio escenarios antes de decidir: «en rigor ambos trabajaron». Mientras tanto rige el reparto por tiempo medido de MIG462.'),
 ('D4','Una orden de servicio admite mas de un concepto?',
  'No: un servicio, un concepto.',
  'resuelta', TRUE, 'Manuel Olivares', NOW(),
  'La hoja Definiciones los describe como excluyentes. El sistema ya lo cumple: el concepto es una columna de la OT.'),
 ('D5','Que dias se usan para el tramo: los del periodo o los acumulados',
  'Los acumulados para evaluar el tramo; los del periodo para prorratear el monto.',
  'resuelta', TRUE, 'Manuel Olivares', NOW(),
  'Con los del periodo puro, una OT arrastrada nunca entraba al tramo de demora.'),
 ('D6','El KPI y el plan se prorratean por dias de contrato?',
  'Si, con mes comercial de 30 dias, igual que los bonos fijos.',
  'resuelta', TRUE, 'Manuel Olivares', NOW(),
  'Caso medido: Juan Valenzuela pasa de $24.000 a $15.200.'),
 ('D14','Se agrega el tope MIN a la formula y se corrige la curva?',
  'Las dos. Se paga la curva corregida, con el tope del cargo aplicado al total.',
  'resuelta', TRUE, 'Manuel Olivares', NOW(),
  'La formula de la planilla no es monotona (cerrar en 6 dias paga menos que en 10), puede pagar negativo y no tiene tope.')
ON CONFLICT (codigo) DO UPDATE
   SET decision = EXCLUDED.decision, estado = EXCLUDED.estado,
       resuelta_por = EXCLUDED.resuelta_por, resuelta_at = EXCLUDED.resuelta_at,
       nota = EXCLUDED.nota;

-- ── 2 · D1 · Los parametros salen de borrador ───────────────────────────────
--
-- Agosto no se toca: la vigencia empieza el 24-08, primer dia del corte de
-- septiembre (24 al 23). Lo pagado en agosto quedo pagado.
UPDATE taller_bono_parametros
   SET estado = 'vigente',
       nombre = 'Septiembre 2026 · Estructura KPI 2025',
       vigencia_desde = DATE '2026-08-24',
       activado_at = NOW(),
       notas = 'Acta del 01-09-2026. D1: rige la Estructura KPI 2025 escrita. '
               'D14: se paga la curva corregida con tope. D5 y D6 aplicadas en el motor. '
               'D2 sigue abierta y no impide calcular: rige el reparto por tiempo medido.'
 WHERE estado = 'borrador'
   AND nombre LIKE 'Septiembre 2026%';

-- ── 3 · D5 · El tramo por dias acumulados, el monto por los del corte ───────
DROP FUNCTION IF EXISTS fn_taller_bono_periodo_calc(DATE, DATE);

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
        -- El trabajo que el período paga: OT ejecutadas dentro del corte, que
        -- no sean de externo.
        SELECT ot.id, ot.folio::TEXT AS folio,
               ot.fecha_inicio, ot.fecha_termino,
               fn_taller_ot_concepto(ot.id) AS concepto,
               GREATEST(1, CEIL(EXTRACT(EPOCH FROM (
                   ot.fecha_termino - COALESCE(ot.fecha_inicio, ot.created_at)
               )) / 86400.0))::NUMERIC AS dias,
               -- [MIG480 · D5] Los días de ESTA OT que caen dentro del corte.
               -- El tramo se evalúa con los días acumulados (arriba); el monto
               -- se paga por lo que ocurrió en el período. Una OT arrastrada de
               -- meses ya no cobra entera en el mes en que se cierra.
               GREATEST(0, (LEAST(ot.fecha_termino::DATE, p_hasta)
                          - GREATEST(COALESCE(ot.fecha_inicio, ot.created_at)::DATE, p_desde)) + 1
               )::NUMERIC AS dias_en_corte
          FROM ordenes_trabajo ot
         WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
           AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta
           AND NOT COALESCE(ot.ejecutada_por_externo, FALSE)
           -- [MIG472] Un cierre con tareas pendientes no paga hasta que la
           -- jefatura lo valide. Sin esto, la puerta que abre MIG472 sería la
           -- más barata del sistema: cerrar 118 items con 4 hechos y cobrar el
           -- trabajo completo.
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
        -- La versión corregida: monótona, nunca negativa. Cerrar antes siempre
        -- paga más o igual.
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
            -- [MIG462] Tres formas de repartir, no dos. Cualquiera que no sea el
            -- tiempo medido de todos merece quedar dicho en la cartola.
            CASE WHEN rp.base_reparto <> 'tiempo medido'
                 THEN 'reparto por ' || rp.base_reparto END,
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
      -- No es un dato que falte: es alguien que se fue. Bloquear el cierre de un
      -- corte por el cargo de un ex trabajador sería una traba sin sentido.
      -- El que SÍ está activo y no tiene cargo sigue apareciendo como `falta`,
      -- porque ahí la pregunta está abierta de verdad.
      JOIN taller_tecnicos tt ON tt.id = rp.tecnico_id
     WHERE COALESCE(tt.activo, TRUE) OR tc.cargo IS NOT NULL
     ORDER BY rp.tecnico, c.folio;
END;
$function$;


-- ── 4 · D6 · Mes comercial de 30 dias para el KPI y para el tope del plan ───
-- (No cambia el tipo de retorno: basta CREATE OR REPLACE.)

CREATE OR REPLACE FUNCTION public.fn_taller_bono_kpi_periodo_calc(p_desde date, p_hasta date, p_disponibilidad numeric DEFAULT NULL::numeric)
 RETURNS TABLE(tecnico_id uuid, tecnico text, cargo text, disponibilidad numeric, tramo text, factor numeric, kpi_base numeric, dias_cargo integer, dias_corte integer, prorrateo numeric, monto_kpi numeric, falta text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_par  UUID;
    v_disp NUMERIC;
    v_dias INT := (p_hasta - p_desde) + 1;
BEGIN
    SELECT id INTO v_par FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran el período % a %.', p_desde, p_hasta;
    END IF;

    -- Se puede pasar a mano (un acta que fija el indicador del mes) o dejar que
    -- lo mida el sistema. Lo que se usó queda en la columna, siempre.
    v_disp := COALESCE(p_disponibilidad,
                       (SELECT d.disponibilidad_pct
                          FROM fn_taller_disponibilidad_periodo(p_desde, p_hasta) d));

    RETURN QUERY
    SELECT
        t.id,
        t.nombre::TEXT,
        tc.cargo,
        v_disp,
        tr.etiqueta,
        tr.factor,
        cg.kpi_base_clp,
        d.dias,
        v_dias,
        -- [MIG480 · D6] Mes comercial de 30 días, la misma base con la que ya se
        -- prorratean los bonos fijos. Antes el divisor eran los días reales del
        -- corte (30 o 31), así que la misma persona tenía dos reglas distintas
        -- en la misma liquidación. Tope en 1: un corte de 31 días no paga 1,03.
        LEAST(1.0, round(d.dias::NUMERIC / 30.0, 4)),
        CASE WHEN cg.kpi_base_clp IS NULL OR tr.factor IS NULL THEN NULL
             ELSE round(cg.kpi_base_clp * tr.factor * LEAST(1.0, d.dias::NUMERIC / 30.0))
        END,
        NULLIF(concat_ws(' · ',
            CASE WHEN tc.cargo IS NULL THEN 'falta el cargo del técnico' END,
            CASE WHEN v_disp IS NULL   THEN 'no hay disponibilidad medida en el corte' END,
            CASE WHEN cg.cargo IS NULL AND tc.cargo IS NOT NULL
                 THEN 'el cargo no tiene base de KPI en el juego de parámetros' END
        ), '')
      FROM taller_tecnicos t
      LEFT JOIN taller_tecnico_cargo tc
             ON tc.tecnico_id = t.id
            AND tc.desde <= p_hasta AND (tc.hasta IS NULL OR tc.hasta >= p_desde)
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = tc.cargo
      LEFT JOIN LATERAL (
          SELECT GREATEST(0, (LEAST(p_hasta, COALESCE(tc.hasta, p_hasta))
                            - GREATEST(p_desde, COALESCE(tc.desde, p_desde))) + 1) AS dias
      ) d ON TRUE
      LEFT JOIN LATERAL (
          SELECT k.etiqueta, k.factor
            FROM taller_bono_tramo_kpi k
           WHERE k.parametros_id = v_par
             AND v_disp IS NOT NULL
             AND k.desde_pct <= v_disp / 100.0
           ORDER BY k.desde_pct DESC
           LIMIT 1
      ) tr ON TRUE
     WHERE COALESCE(t.activo, TRUE)
       -- [MIG464] El auditor tampoco cobra la mitad de KPI. El plan de
       -- incentivo del taller es uno solo: o se participa de las dos mitades o
       -- de ninguna.
       AND COALESCE(t.participa_en_bono, TRUE)
     ORDER BY t.nombre;
END;
$function$;


-- ── 5 · Permisos (el DROP se llevo los GRANT) ───────────────────────────────
REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) TO authenticated;

-- ── Verificacion (solo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_ab INT; v_par TEXT; v_est TEXT;
BEGIN
    SELECT count(*) INTO v_ab FROM taller_bono_acta WHERE estado = 'abierta' AND bloqueante;
    SELECT nombre, estado INTO v_par, v_est FROM taller_bono_parametros
     ORDER BY vigencia_desde DESC LIMIT 1;
    RAISE NOTICE 'parametros: % (%) · decisiones bloqueantes abiertas: %', v_par, v_est, v_ab;
END $mig$;

COMMIT;
