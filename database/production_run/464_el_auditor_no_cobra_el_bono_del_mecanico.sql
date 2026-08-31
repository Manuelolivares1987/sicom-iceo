-- ============================================================================
-- MIG464 · El auditor no cobra el bono del mecánico
-- ============================================================================
--
-- LO QUE ACLARÓ MANUEL
-- «Felipe López es el auditor general de la compañía, él es el que hace los
-- chequeos de calidad en taller por ejemplo, y si no los hace él, encargamos a
-- Juan que los haga o en su defecto chequeo cruzado de actividades».
--
-- Eso responde la pregunta que quedó abierta en MIG453 —Felipe con 41 jornadas
-- y sin liquidación del taller— y la respuesta no era «falta un dato»: es que
-- no le corresponde. Audita el trabajo, no lo ejecuta.
--
-- POR QUÉ IMPORTA, MEDIDO ANTES DE TOCAR NADA
-- Felipe está en la cuadrilla de 15 OT, con 43 jornadas. En seis de ellas
-- comparte cuadrilla con mecánicos, y ahí se estaba llevando plata de ellos:
--
--     OT-202607-00053   50 % de 4, junto a Marco Díaz, Sergio Cortes, Yusdel Sarduy
--     OT-202607-00040   50 % de 2, junto a Yusdel Sarduy
--     OT-202607-00023   50 % de 2, junto a Sergio Cortes
--
-- El auditor se llevaba la mitad del bono de la mantención que auditó.
--
-- Y EN NUEVE ES EL ÚNICO DE LA CUADRILLA
-- Ahí sacarlo no basta: esas OT quedan sin nadie a quien pagarle. No es que el
-- trabajo no se haya hecho; es que en el plan quedó anotado el auditor y no el
-- mecánico. Sacarlo en silencio convertiría nueve órdenes de trabajo en plata
-- que no le llega a nadie y de la que nadie se entera. Eso es peor que el
-- problema original.
--
-- QUÉ SE HACE
--
--   1. `participa_en_bono` en el catálogo de técnicos. Felipe en FALSE, con el
--      motivo escrito. Es una columna, no una lista en el código: si mañana
--      entra otro auditor, es un UPDATE de una fila.
--
--   2. El reparto lo excluye ANTES de calcular los porcentajes, así que su
--      parte no se pierde: se reparte entre los que sí ejecutaron. La
--      OT-202607-00040 pasa de 50/50 con Yusdel a 100 % de Yusdel.
--
--   3. El motor deja de listarlo. Su «falta el cargo del técnico» desaparece,
--      y con eso se destraba el cierre del período: era lo único que lo
--      bloqueaba.
--
--   4. Aparece un aviso nuevo, y bloquea: las OT cerradas dentro del corte que
--      no tienen a NADIE a quien pagarle. Sin esto, las nueve órdenes de Felipe
--      desaparecerían del bono sin dejar rastro.
--
-- LO QUE NO DECIDO YO
-- Cuando Juan Valenzuela hace el chequeo de calidad en vez de Felipe, ¿esa
-- jornada cuenta para SU bono de mecánico? Juan sí es Mecánico A y sí participa
-- del plan. Auditar no es reparar, pero es trabajo encargado por la jefatura.
-- Es criterio, no dato: va al acta, junto a D2 y D4.
-- ============================================================================

BEGIN;

-- ── 1 · Quién participa del plan de incentivo ───────────────────────────────
ALTER TABLE taller_tecnicos
  ADD COLUMN IF NOT EXISTS participa_en_bono BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE taller_tecnicos
  ADD COLUMN IF NOT EXISTS motivo_sin_bono TEXT;

COMMENT ON COLUMN taller_tecnicos.participa_en_bono IS
    'FALSE para quien trabaja en el taller pero no recibe plan de incentivo '
    '(auditoría, jefatura, apoyo externo). No entra al reparto y su parte se '
    'redistribuye entre quienes sí ejecutaron.';

UPDATE taller_tecnicos
   SET participa_en_bono = FALSE,
       motivo_sin_bono = 'Auditor general de la compañía: hace los chequeos de '
                         'calidad en taller, no ejecuta la mantención.',
       updated_at = NOW()
 WHERE nombre = 'Felipe López';

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
          -- [MIG464] Quien no participa del plan de incentivo no entra al
          -- reparto. Al filtrar acá —antes de las ventanas— los porcentajes se
          -- recalculan solos sobre los que quedan: su parte no se pierde, se
          -- reparte entre quienes sí ejecutaron.
          WHERE COALESCE(t.participa_en_bono, TRUE)
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
      -- [MIG463] Quien ya no está en el taller y nunca tuvo cargo no genera línea.
      -- No es un dato que falte: es alguien que se fue. Bloquear el cierre de un
      -- corte por el cargo de un ex trabajador sería una traba sin sentido.
      -- El que SÍ está activo y no tiene cargo sigue apareciendo como `falta`,
      -- porque ahí la pregunta está abierta de verdad.
      JOIN taller_tecnicos tt ON tt.id = rp.tecnico_id
     WHERE COALESCE(tt.activo, TRUE) OR tc.cargo IS NOT NULL
     ORDER BY rp.tecnico, c.folio;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon, authenticated;

-- ── 3a · Y tampoco cobra la mitad de KPI ────────────────────────────────────
--
-- La primera versión de esta migración sacó a Felipe del reparto del plan de
-- incentivo y lo dejó en el KPI: seguía apareciendo con «falta el cargo del
-- técnico», que es justo lo que bloquea el cierre. Media exclusión no sirve de
-- nada. El plan de incentivo del taller es uno solo: o se participa de las dos
-- mitades o de ninguna.
CREATE OR REPLACE FUNCTION fn_taller_bono_kpi_periodo_calc(
    p_desde DATE,
    p_hasta DATE,
    p_disponibilidad NUMERIC DEFAULT NULL
)
RETURNS TABLE (
    tecnico_id       UUID,
    tecnico          TEXT,
    cargo            TEXT,
    disponibilidad   NUMERIC,
    tramo            TEXT,
    factor           NUMERIC,
    kpi_base         NUMERIC,
    dias_cargo       INT,
    dias_corte       INT,
    prorrateo        NUMERIC,
    monto_kpi        NUMERIC,
    falta            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
        round(d.dias::NUMERIC / NULLIF(v_dias, 0), 4),
        CASE WHEN cg.kpi_base_clp IS NULL OR tr.factor IS NULL THEN NULL
             ELSE round(cg.kpi_base_clp * tr.factor * d.dias::NUMERIC / NULLIF(v_dias, 0))
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
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_kpi_periodo_calc(DATE, DATE, NUMERIC) FROM PUBLIC, anon, authenticated;

-- ── 3b · El cuerpo llama al cuerpo, no a la puerta ──────────────────────────
--
-- DEFECTO QUE INTRODUJO MIG460 Y APARECIÓ AL VERIFICAR ESTA MIGRACIÓN.
-- Al envolver el cálculo con el candado de acceso, `fn_taller_bono_resumen_calc`
-- —que es el CUERPO— quedó llamando a `fn_taller_bono_periodo`, que es la
-- PUERTA. Resultado: el motor se pedía permiso a sí mismo. Para un usuario web
-- no se nota, porque pasa las dos veces; pero cualquier uso interno —una
-- verificación, un cron, otra función— se estrella con «No autenticado».
--
-- Es el mismo error de diseño que un candado puesto dos veces en la misma
-- puerta: no protege más y traba lo que debería pasar.
CREATE OR REPLACE FUNCTION fn_taller_bono_resumen_calc(
    p_desde DATE,
    p_hasta DATE,
    p_disponibilidad NUMERIC DEFAULT NULL
)
RETURNS TABLE (
    tecnico_id        UUID,
    tecnico           TEXT,
    cargo             TEXT,
    ots               INT,
    plan_formula      NUMERIC,
    plan_calculado    NUMERIC,
    plan_tope         NUMERIC,
    plan_pagado       NUMERIC,
    kpi_pagado        NUMERIC,
    total             NUMERIC,
    dias_cargo        INT,
    dias_corte        INT,
    disponibilidad    NUMERIC,
    tramo             TEXT,
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

    RETURN QUERY
    WITH plan AS (
        SELECT b.tecnico_id AS tid,
               count(*)::INT AS ots,
               sum(b.monto_formula)   AS f,
               sum(b.monto_propuesto) AS p,
               string_agg(DISTINCT b.falta, ' · ') AS falta,
               string_agg(DISTINCT b.aviso, ' · ') AS aviso
          -- [MIG464] El cuerpo llama al cuerpo, no a la puerta. Llamar al
          -- envoltorio con candado desde acá hacía que el resumen exigiera
          -- sesión web incluso cuando lo invoca otra función del propio motor.
          FROM fn_taller_bono_periodo_calc(p_desde, p_hasta) b
         GROUP BY b.tecnico_id
    ),
    kpi AS (
        SELECT * FROM fn_taller_bono_kpi_periodo_calc(p_desde, p_hasta, p_disponibilidad)
    )
    SELECT
        k.tecnico_id,
        k.tecnico,
        k.cargo,
        COALESCE(pl.ots, 0),
        pl.f,
        pl.p,
        round(cg.plan_tope_clp * k.prorrateo),
        LEAST(COALESCE(pl.p, 0), round(cg.plan_tope_clp * k.prorrateo)),
        k.monto_kpi,
        LEAST(COALESCE(pl.p, 0), round(cg.plan_tope_clp * k.prorrateo)) + COALESCE(k.monto_kpi, 0),
        k.dias_cargo,
        k.dias_corte,
        k.disponibilidad,
        k.tramo,
        -- Bloquea el cierre.
        NULLIF(concat_ws(' · ', k.falta, pl.falta), ''),
        -- Sólo informa: pasar el tope es el sistema funcionando, no un error.
        NULLIF(concat_ws(' · ',
            pl.aviso,
            CASE WHEN COALESCE(pl.p, 0) > round(cg.plan_tope_clp * k.prorrateo)
                 THEN 'la suma de las OT pasa el tope del cargo: se paga el tope' END
        ), '')
      FROM kpi k
      LEFT JOIN plan pl ON pl.tid = k.tecnico_id
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = k.cargo
     ORDER BY k.tecnico;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_resumen_calc(DATE, DATE, NUMERIC) FROM PUBLIC, anon, authenticated;

-- ── 4 · Trabajo cerrado que no le paga a nadie ──────────────────────────────
--
-- Una OT que se cierra dentro del corte y no tiene a nadie en la cuadrilla no
-- aparece en el bono: no falla, simplemente no existe. Y eso es lo peligroso.
-- Que se vea, y que frene el cierre hasta que la jefatura diga quién trabajó o
-- confirme que no corresponde pagarla.
CREATE OR REPLACE FUNCTION fn_taller_bono_ot_sin_dueno(p_desde DATE, p_hasta DATE)
RETURNS TABLE (
    ot_id         UUID,
    ot_folio      TEXT,
    estado        TEXT,
    fecha_termino TIMESTAMPTZ,
    motivo        TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT ot.id, ot.folio::TEXT, ot.estado::TEXT, ot.fecha_termino,
           CASE
               WHEN NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po WHERE po.ot_id = ot.id)
                    THEN 'no está en el plan semanal: nadie tiene jornada en ella'
               WHEN NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po
                                  JOIN taller_ot_cuadrilla c ON c.plan_ot_id = po.id
                                 WHERE po.ot_id = ot.id)
                    THEN 'está en el plan pero sin cuadrilla asignada'
               ELSE 'los únicos de la cuadrilla no participan del plan de incentivo'
           END
      FROM ordenes_trabajo ot
     WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
       AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta
       AND NOT COALESCE(ot.ejecutada_por_externo, FALSE)
       AND NOT EXISTS (SELECT 1 FROM v_taller_bono_reparto r WHERE r.ot_id = ot.id)
     ORDER BY ot.folio;
$$;

CREATE OR REPLACE FUNCTION rpc_taller_bono_ot_sin_dueno(p_desde DATE, p_hasta DATE)
RETURNS TABLE (
    ot_id         UUID,
    ot_folio      TEXT,
    estado        TEXT,
    fecha_termino TIMESTAMPTZ,
    motivo        TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY SELECT * FROM fn_taller_bono_ot_sin_dueno(p_desde, p_hasta);
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_ot_sin_dueno(DATE, DATE) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION rpc_taller_bono_ot_sin_dueno(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_ot_sin_dueno(DATE, DATE) TO authenticated;

-- ── 5 · El cierre se frena si hay trabajo sin dueño ─────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_cerrar_periodo(
    p_nombre         TEXT,
    p_desde          DATE,
    p_hasta          DATE,
    p_disponibilidad NUMERIC DEFAULT NULL,
    p_notas          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_par    UUID;
    v_estado TEXT;
    v_faltan TEXT;
    v_solapa TEXT;
    v_huerf  TEXT;
    v_per    UUID;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Tu perfil no puede cerrar un período de bono.';
    END IF;

    IF p_hasta < p_desde THEN
        RAISE EXCEPTION 'El corte termina antes de empezar.';
    END IF;

    SELECT string_agg(nombre || ' (' || desde || ' a ' || hasta || ')', ', ')
      INTO v_solapa
      FROM taller_bono_periodo
     WHERE desde <= p_hasta AND hasta >= p_desde;
    IF v_solapa IS NOT NULL THEN
        RAISE EXCEPTION 'Este corte se pisa con otro que ya está cerrado: %.', v_solapa;
    END IF;

    SELECT id, estado INTO v_par, v_estado
      FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran % a %.', p_desde, p_hasta;
    END IF;
    IF v_estado <> 'vigente' THEN
        RAISE EXCEPTION 'Los parámetros de este corte están en «%». Un período no se '
                        'cierra sobre una propuesta: primero el acta que fija topes y '
                        'curva, después el cierre.', v_estado;
    END IF;

    SELECT string_agg(DISTINCT r.tecnico || ': ' || r.falta, ' · ')
      INTO v_faltan
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r
     WHERE r.falta IS NOT NULL;
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta información para cerrar. %', v_faltan;
    END IF;

    -- [MIG464] Trabajo cerrado en el corte que no le paga a nadie. Dejarlo pasar
    -- sería perder plata en silencio.
    SELECT string_agg(o.ot_folio || ' (' || o.motivo || ')', ' · ')
      INTO v_huerf
      FROM fn_taller_bono_ot_sin_dueno(p_desde, p_hasta) o;
    IF v_huerf IS NOT NULL THEN
        RAISE EXCEPTION 'Hay trabajo cerrado en el corte que no le paga a nadie: %. '
                        'Asígnales cuadrilla en el Plan Semanal, o confirma que no '
                        'corresponde pagarlas.', v_huerf;
    END IF;

    INSERT INTO taller_bono_periodo (
        nombre, desde, hasta, parametros_id, disponibilidad_pct,
        disponibilidad_fuente, notas, cerrado_por)
    VALUES (
        p_nombre, p_desde, p_hasta, v_par,
        COALESCE(p_disponibilidad,
                 (SELECT d.disponibilidad_pct FROM fn_taller_disponibilidad_periodo(p_desde, p_hasta) d)),
        CASE WHEN p_disponibilidad IS NULL THEN 'medida por el sistema'
             ELSE 'fijada al cerrar' END,
        p_notas, v_user)
    RETURNING id INTO v_per;

    INSERT INTO taller_bono_periodo_linea (
        periodo_id, tecnico_id, tecnico, cargo, ots, plan_formula, plan_calculado,
        plan_tope, plan_pagado, kpi_pagado, total, dias_cargo, dias_corte, tramo,
        falta, aviso)
    SELECT v_per, r.tecnico_id, r.tecnico, r.cargo, r.ots, r.plan_formula,
           r.plan_calculado, r.plan_tope, r.plan_pagado, r.kpi_pagado, r.total,
           r.dias_cargo, r.dias_corte, r.tramo, r.falta, r.aviso
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r;

    INSERT INTO taller_bono_periodo_detalle (
        periodo_id, tecnico_id, ot_id, ot_folio, concepto, dias, tramo,
        participacion, base_reparto, monto_formula, monto_propuesto, falta, aviso)
    SELECT v_per, b.tecnico_id, b.ot_id, b.ot_folio, b.concepto, b.dias, b.tramo,
           b.participacion, b.base_reparto, b.monto_formula, b.monto_propuesto,
           b.falta, b.aviso
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b;

    SELECT COALESCE(sum(total), 0), count(*) INTO v_total, v_n
      FROM taller_bono_periodo_linea WHERE periodo_id = v_per;

    UPDATE taller_bono_periodo SET total_clp = v_total WHERE id = v_per;

    RETURN jsonb_build_object('success', true, 'periodo_id', v_per,
                              'personas', v_n, 'total_clp', v_total);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    r RECORD; v_n INT; v_pct NUMERIC;
BEGIN
    SELECT count(*) INTO v_n FROM taller_tecnicos WHERE NOT participa_en_bono;
    RAISE NOTICE 'técnicos que NO participan del plan de incentivo: %', v_n;
    FOR r IN SELECT nombre, motivo_sin_bono FROM taller_tecnicos WHERE NOT participa_en_bono LOOP
        RAISE NOTICE '   % · %', r.nombre, r.motivo_sin_bono;
    END LOOP;

    SELECT count(*) INTO v_n FROM v_taller_bono_reparto WHERE tecnico = 'Felipe López';
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: Felipe sigue en % líneas del reparto', v_n; END IF;
    RAISE NOTICE 'Felipe López ya no aparece en ninguna línea del reparto';

    -- Su parte se redistribuyó, no se perdió.
    SELECT round(participacion*100) INTO v_pct
      FROM v_taller_bono_reparto WHERE ot_folio = 'OT-202607-00040' AND tecnico = 'Yusdel Sarduy';
    RAISE NOTICE 'OT-202607-00040 · Yusdel Sarduy pasa de 50 a % por ciento', COALESCE(v_pct::text,'(sin linea)');

    -- Alias distinto de `r`: dentro de un DO, plpgsql resuelve `r.falta` contra
    -- la variable RECORD declarada arriba y no contra la tabla.
    SELECT count(*) INTO v_n
      FROM fn_taller_bono_resumen_calc(DATE '2026-09-01', DATE '2026-09-30') res
     WHERE res.falta IS NOT NULL;
    RAISE NOTICE 'lineas que todavía bloquean el cierre de septiembre: %', v_n;

    -- Trabajo cerrado sin dueño, contado sobre TODO lo que hay cerrado.
    SELECT count(*) INTO v_n FROM fn_taller_bono_ot_sin_dueno(DATE '2026-01-01', DATE '2026-12-31');
    RAISE NOTICE 'OT cerradas en 2026 que no le pagarían a nadie: %', v_n;
    FOR r IN SELECT * FROM fn_taller_bono_ot_sin_dueno(DATE '2026-01-01', DATE '2026-12-31') LIMIT 8 LOOP
        RAISE NOTICE '   % (%) · %', rpad(r.ot_folio,20), r.estado, r.motivo;
    END LOOP;
END
$mig$;

COMMIT;
