-- ============================================================================
-- MIG462 · Apretar play no puede llevarse el bono del compañero
-- ============================================================================
--
-- ENCONTRADO RESPONDIENDO UNA PREGUNTA DE MANUEL
-- «Si hoy ejecutan desde la sesión compartida, pero ejecutan la OT que se les
-- asignó, ¿calcula el bono?»
--
-- La respuesta corta es sí. Simulado de punta a punta contra producción, sobre
-- la OT-202606-00041, cuya cuadrilla asignó el jefe a Joel Coo y Marco Díaz:
--
--     Joel arranca desde la cuenta compartida declarando su nombre, 3 h
--     La OT se cierra dentro del corte
--     → Joel Coo · Mecanico A · RSR · 1 día · optimizado · $7.273
--
-- La cadena completa funciona. Pero al mirar la segunda línea apareció esto:
--
--     Joel Coo      participación 100 %  (tiempo medido)  $7.273
--     Marco Díaz    participación   0 %  (tiempo medido)      $0
--
-- Marco estaba en la cuadrilla, trabajó, y se lleva cero. Y no es que no haya
-- apretado play por flojo: NO PUEDE. Hay un índice único, `uq_taller_ejec_activa_ot`,
-- que sólo permite UNA ejecución abierta por OT. Mientras Joel tenga la suya
-- corriendo o pausada, la de Marco es rechazada por la base.
--
-- O sea: en una cuadrilla, el primero que aprieta play se lleva el 100 % del
-- bono de la OT, y el segundo no tiene forma de defenderse. Desde una cuenta
-- compartida, además, basta declararse a uno mismo. Es el incentivo perverso
-- más caro que puede tener un sistema de incentivos.
--
-- Sin que nadie apriete play el reparto era correcto —50 % y 50 %—, así que el
-- sistema premiaba exactamente la conducta que hay que evitar.
--
-- LA REGLA NUEVA
-- El tiempo medido sólo reparte si está medido PARA TODOS los de la cuadrilla.
-- Si falta el tiempo de alguno, el tiempo no sirve de base y se reparte por las
-- JORNADAS que la jefatura le asignó a cada uno en el plan — que es un dato de
-- jefatura, no del teléfono. Si tampoco eso distingue, partes iguales.
--
--     tiempo medido       todos tienen reloj: reparte el reloj
--     jornadas asignadas  no todos: reparte lo que el jefe planificó
--     partes iguales      ni siquiera hay jornadas que distinguir
--
-- Con la regla nueva, el mismo caso da 50 % y 50 %: Joel no gana nada por
-- apretar play primero, y Marco no pierde por no poder.
--
-- Lo que esto NO resuelve es el índice único. Que dos personas puedan medir su
-- tiempo por separado en la misma OT es un cambio más grande, y hasta que
-- exista, «tiempo medido» va a ser raro en cuadrilla. Está bien: la base honesta
-- es la que planificó el jefe.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW v_taller_bono_reparto AS
 WITH cuadrilla AS (
         SELECT po.ot_id,
            c.tecnico_id,
            min(c.rol)  AS rol,
            count(*)::numeric AS jornadas   -- días que el jefe le asignó en el plan
           FROM taller_ot_cuadrilla c
             JOIN taller_plan_semanal_ots po ON po.id = c.plan_ot_id
          GROUP BY po.ot_id, c.tecnico_id
        ), tiempos AS (
         SELECT e.ot_id,
            e.tecnico_id,
            COALESCE(sum(e.tiempo_efectivo_segundos), 0::bigint)::numeric AS segundos
           FROM taller_ot_ejecuciones e
          WHERE e.tecnico_id IS NOT NULL
          GROUP BY e.ot_id, e.tecnico_id
        ), base AS (
         SELECT ot.id AS ot_id,
            ot.folio AS ot_folio,
            ot.estado::text AS ot_estado,
            ot.fecha_termino,
            ot.ejecutada_por_externo,
            cu.tecnico_id,
            t.nombre AS tecnico,
            cu.rol,
            cu.jornadas,
            COALESCE(ti.segundos, 0::numeric) AS segundos,
            count(*)          OVER (PARTITION BY ot.id) AS n_cuadrilla,
            count(*) FILTER (WHERE COALESCE(ti.segundos, 0::numeric) > 0::numeric)
                              OVER (PARTITION BY ot.id) AS n_con_tiempo,
            sum(COALESCE(ti.segundos, 0::numeric))
                              OVER (PARTITION BY ot.id) AS seg_total,
            sum(cu.jornadas)  OVER (PARTITION BY ot.id) AS jor_total
           FROM cuadrilla cu
             JOIN ordenes_trabajo ot ON ot.id = cu.ot_id
             JOIN taller_tecnicos t ON t.id = cu.tecnico_id
             LEFT JOIN tiempos ti ON ti.ot_id = cu.ot_id AND ti.tecnico_id = cu.tecnico_id
        )
 SELECT b.ot_id,
    b.ot_folio,
    b.ot_estado,
    b.fecha_termino,
    b.ejecutada_por_externo,
    b.ejecutada_por_externo IS FALSE AS genera_bono,
    b.tecnico_id,
    b.tecnico,
    b.rol,
    b.segundos,
        CASE
            -- El reloj sólo reparte si está medido para TODOS. Si falta uno, el
            -- que apretó play se llevaría lo del que no pudo.
            WHEN b.seg_total > 0::numeric AND b.n_con_tiempo = b.n_cuadrilla
                THEN round(b.segundos / b.seg_total, 4)
            WHEN b.jor_total > 0::numeric
                THEN round(b.jornadas / b.jor_total, 4)
            ELSE round(1.0 / b.n_cuadrilla::numeric, 4)
        END AS participacion,
        CASE
            WHEN b.seg_total > 0::numeric AND b.n_con_tiempo = b.n_cuadrilla
                THEN 'tiempo medido'::text
            WHEN b.jor_total > 0::numeric AND b.n_cuadrilla > 1
                THEN 'jornadas asignadas'::text
            ELSE 'partes iguales'::text
        END AS base_reparto,
    -- Columna nueva al final: CREATE OR REPLACE VIEW no deja meterla al medio.
    b.jornadas
   FROM base b;

CREATE OR REPLACE FUNCTION fn_taller_bono_periodo_calc(
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    tecnico_id        UUID,
    tecnico           TEXT,
    cargo             TEXT,
    ot_id             UUID,
    ot_folio          TEXT,
    concepto          TEXT,
    dias              NUMERIC,
    tramo             TEXT,
    participacion     NUMERIC,
    base_reparto      TEXT,
    monto_formula     NUMERIC,
    monto_propuesto   NUMERIC,
    falta             TEXT,
    aviso             TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
               )) / 86400.0))::NUMERIC AS dias
          FROM ordenes_trabajo ot
         WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
           AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta
           AND NOT COALESCE(ot.ejecutada_por_externo, FALSE)
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
             ELSE round(rp.participacion * cg.plan_tope_clp * co.coef_optimizado * co.dias_optimizado * GREATEST(0, CASE
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
                 THEN 'reparto por ' || rp.base_reparto END
        ), '')
      FROM cerradas c
      JOIN reparto rp ON rp.ot_id = c.id
      LEFT JOIN taller_tecnico_cargo tc
             ON tc.tecnico_id = rp.tecnico_id
            AND tc.desde <= p_hasta AND (tc.hasta IS NULL OR tc.hasta >= p_desde)
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = tc.cargo
      LEFT JOIN taller_bono_concepto co ON co.parametros_id = v_par AND co.concepto = c.concepto
     ORDER BY rp.tecnico, c.folio;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon, authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
--
-- Se comprueba sobre el caso real que destapó el problema: la OT-202606-00041,
-- con cuadrilla de dos, y sólo uno con tiempo medido. Es una prueba que ESCRIBE,
-- así que va dentro de un bloque que se deshace solo: se mide, se compara y se
-- borra lo escrito antes de que la migración termine.
DO $mig$
DECLARE
    v_ot UUID; v_joel UUID; v_marco UUID;
    v_ejec UUID;
    r RECORD;
    v_joel_pct NUMERIC; v_marco_pct NUMERIC; v_base TEXT;
BEGIN
    SELECT id INTO v_ot    FROM ordenes_trabajo WHERE folio = 'OT-202606-00041';
    SELECT id INTO v_joel  FROM taller_tecnicos WHERE nombre = 'Joel Coo';
    SELECT id INTO v_marco FROM taller_tecnicos WHERE nombre = 'Marco Díaz';

    IF v_ot IS NULL OR v_joel IS NULL OR v_marco IS NULL THEN
        RAISE NOTICE 'no está el caso de prueba en esta base; se omite la comprobación';
        RETURN;
    END IF;

    -- Se le pone reloj SÓLO a Joel, que es exactamente lo que pasa hoy cuando
    -- uno aprieta play y el otro no puede.
    INSERT INTO taller_ot_ejecuciones (ot_id, tecnico_id, ejecutor_id, estado,
                                       started_at, last_event_at, tiempo_efectivo_segundos)
    VALUES (v_ot, v_joel, (SELECT id FROM usuarios_perfil WHERE nombre_completo = 'Jefe de Taller'),
            'finalizada', NOW(), NOW(), 3*3600)
    RETURNING id INTO v_ejec;

    SELECT max(participacion) FILTER (WHERE tecnico_id = v_joel),
           max(participacion) FILTER (WHERE tecnico_id = v_marco),
           min(base_reparto)
      INTO v_joel_pct, v_marco_pct, v_base
      FROM v_taller_bono_reparto WHERE ot_id = v_ot;

    DELETE FROM taller_ot_ejecuciones WHERE id = v_ejec;

    RAISE NOTICE 'OT-202606-00041 · cuadrilla de 2 · sólo Joel con reloj';
    RAISE NOTICE '   Joel % por ciento  ·  Marco % por ciento  ·  base: %',
        round(v_joel_pct*100), round(v_marco_pct*100), v_base;

    IF v_marco_pct = 0 THEN
        RAISE EXCEPTION 'FALLO: el que no pudo apretar play sigue quedando en cero';
    END IF;
    IF v_base = 'tiempo medido' THEN
        RAISE EXCEPTION 'FALLO: repartió por tiempo con la mitad de la cuadrilla sin medir';
    END IF;
    RAISE NOTICE 'apretar play ya no se lleva el bono del compañero';

    -- Y donde el reloj SÍ está completo, sigue mandando el reloj.
    SELECT count(*) INTO v_joel_pct FROM v_taller_bono_reparto WHERE base_reparto = 'tiempo medido';
    RAISE NOTICE 'lineas que hoy reparten por tiempo medido (cuadrilla completa): %', v_joel_pct;

    SELECT count(*) INTO v_marco_pct FROM v_taller_bono_reparto WHERE base_reparto = 'jornadas asignadas';
    RAISE NOTICE 'lineas que reparten por las jornadas que asignó el jefe:        %', v_marco_pct;
END
$mig$;

COMMIT;
