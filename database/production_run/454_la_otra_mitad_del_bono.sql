-- ============================================================================
-- MIG454 · La otra mitad del bono, y el número que la decide
-- ============================================================================
--
-- LO QUE FALTABA
-- MIG452 dejó calculado el plan de incentivo: lo que se paga por cada trabajo
-- cerrado. Pero el bono del taller tiene DOS mitades, y la otra —el KPI de
-- disponibilidad de flota— quedó a medio construir: `fn_taller_bono_periodo`
-- recibía un parámetro `p_disponibilidad` que no usaba en ninguna línea. Un
-- parámetro que se declara y no se lee es peor que no tenerlo, porque quien
-- llame a la función va a creer que el KPI está adentro.
--
-- Se cierra aquí, y con las dos cosas que faltaban para que el número sea
-- pagable: el prorrateo por días de contrato y el tope mensual del cargo.
--
-- EL NÚMERO QUE DECIDE EL KPI ESTABA MAL, Y ES PLATA
--
-- La disponibilidad sale de `v_resumen_diario_flota`. Esa vista saca del
-- numerador los equipos en M, T, F y H. Pero NO saca la 'S' —siniestrado o
-- robado— de ninguna parte, así que hoy un camión robado cuenta como
-- disponible y sube el indicador.
--
-- MIG306 ya había decidido lo contrario: la 'S' sale del DENOMINADOR, no se
-- suma a los caídos ni a los buenos. La vista nunca se actualizó. Medido en el
-- corte del 24-jul al 23-ago:
--
--     con la 'S' adentro, como está hoy   85,40 %
--     con la 'S' afuera, como manda 306   85,23 %
--
-- Son 0,17 puntos sobre un umbral que está en 85 %. En ese corte no cambia el
-- tramo, pero el margen es ese: 19 días-equipo de un camión que no está.
--
-- Y una segunda cosa, más silenciosa: la vista promedia los porcentajes de
-- cada día. El promedio de razones no es la razón de los totales; un día con
-- pocos equipos registrados pesa lo mismo que un día completo. Para un
-- indicador que decide un pago se usa la razón de los totales del período.
-- Quedan los dos números a la vista para que nadie tenga que adivinar cuál se
-- usó.
--
-- QUÉ QUEDA CONSTRUIDO
--   1. `fn_taller_disponibilidad_periodo`  · el indicador, bien medido
--   2. `fn_taller_bono_kpi_periodo`        · la mitad de KPI, por técnico
--   3. `fn_taller_bono_resumen`            · las dos mitades y el total
--   4. `v_resumen_diario_flota`            · la 'S' sale del denominador
--
-- El juego de parámetros sigue en BORRADOR. Esto calcula; no paga.
-- ============================================================================

BEGIN;

-- ── 1 · La 'S' sale del denominador, como decidió MIG306 ────────────────────
CREATE OR REPLACE VIEW v_resumen_diario_flota AS
 SELECT fecha,
    operacion,
    count(*) AS total_equipos,
    count(*) FILTER (WHERE estado_codigo = 'A') AS arrendados,
    count(*) FILTER (WHERE estado_codigo = 'D') AS disponibles,
    count(*) FILTER (WHERE estado_codigo = 'U') AS uso_interno,
    count(*) FILTER (WHERE estado_codigo = 'L') AS leasing,
    count(*) FILTER (WHERE estado_codigo = 'M') AS en_mantencion,
    count(*) FILTER (WHERE estado_codigo = 'T') AS en_terreno,
    count(*) FILTER (WHERE estado_codigo = 'F') AS fuera_servicio,
    count(*) FILTER (WHERE estado_codigo = 'H') AS en_habilitacion,
    count(*) FILTER (WHERE estado_codigo = 'R') AS en_recepcion,
    count(*) FILTER (WHERE estado_codigo = 'V') AS en_venta,
    -- El equipo siniestrado o robado no está: no se cuenta ni arriba ni abajo.
    round(count(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','H','S'))::numeric
          / NULLIF(count(*) FILTER (WHERE estado_codigo <> 'S'), 0)::numeric * 100, 1)
        AS disponibilidad_mecanica_pct,
    round(count(*) FILTER (WHERE estado_codigo = 'A')::numeric
          / NULLIF(count(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','H','V','S')), 0)::numeric * 100, 1)
        AS tasa_arriendo_pct,
    -- Columna nueva al final: CREATE OR REPLACE VIEW no deja insertarla al medio.
    count(*) FILTER (WHERE estado_codigo = 'S') AS siniestrados
   FROM estado_diario_flota edf
  GROUP BY fecha, operacion;

-- ── 2 · El indicador del período, medido para pagar ─────────────────────────
--
-- Devuelve la razón de los totales del período (no el promedio de los días) y,
-- al lado, el promedio diario, para que la diferencia sea visible en vez de
-- ser una discusión.
CREATE OR REPLACE FUNCTION fn_taller_disponibilidad_periodo(
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    disponibilidad_pct   NUMERIC,
    promedio_diario_pct  NUMERIC,
    dias_equipo          BIGINT,
    dias_equipo_buenos   BIGINT,
    dias_con_registro    BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH base AS (
        SELECT * FROM estado_diario_flota
         WHERE fecha BETWEEN p_desde AND p_hasta
           AND estado_codigo <> 'S'
    )
    SELECT
        round(100.0 * count(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','H'))::numeric
              / NULLIF(count(*), 0), 2),
        (SELECT round(avg(disponibilidad_mecanica_pct), 2)
           FROM v_resumen_diario_flota WHERE fecha BETWEEN p_desde AND p_hasta),
        count(*),
        count(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','H')),
        count(DISTINCT fecha)
      FROM base;
$$;

-- ── 3 · El plan sin el parámetro que no usaba ───────────────────────────────
--
-- Se elimina la firma de 3 argumentos y se deja UNA sola. Dos firmas donde una
-- tiene DEFAULT es la trampa de siempre: «function ... is not unique».
DROP FUNCTION IF EXISTS fn_taller_bono_periodo(DATE, DATE, NUMERIC);

CREATE OR REPLACE FUNCTION fn_taller_bono_periodo(
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
    falta             TEXT
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
        NULLIF(concat_ws(' · ',
            CASE WHEN tc.cargo IS NULL THEN 'falta el cargo del técnico' END,
            CASE WHEN c.concepto IS NULL THEN 'no se pudo deducir el concepto' END,
            CASE WHEN rp.base_reparto = 'partes iguales' THEN 'reparto sin tiempo medido' END
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


-- ── 4 · La mitad de KPI, técnico por técnico ────────────────────────────────
--
-- Es un monto mensual por persona, no por trabajo: la base de su cargo por el
-- factor del tramo que alcanzó la flota, prorrateado por los días que estuvo
-- contratado dentro del corte.
--
-- Los días de contrato salen de la ventana de `taller_tecnico_cargo`. No se
-- inventan: si alguien entró a mitad de mes, su cargo empieza a mitad de mes y
-- el prorrateo cae solo.
CREATE OR REPLACE FUNCTION fn_taller_bono_kpi_periodo(
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
     ORDER BY t.nombre;
END;
$$;

-- ── 5 · Las dos mitades y el total ──────────────────────────────────────────
--
-- Aquí aparece lo que la planilla no tiene: un TOPE. La fórmula actual
-- multiplica el tope del cargo por un coeficiente en cada línea, así que un mes
-- con muchas OT cerradas puede sumar por sobre el tope sin que nada avise.
-- `plan_calculado` es lo que da la suma; `plan_pagado` es lo que sale después
-- del tope, prorrateado por los días de contrato. La diferencia queda a la
-- vista en vez de perderse.
CREATE OR REPLACE FUNCTION fn_taller_bono_resumen(
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
    falta             TEXT
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
               string_agg(DISTINCT b.falta, ' · ') AS falta
          FROM fn_taller_bono_periodo(p_desde, p_hasta) b
         GROUP BY b.tecnico_id
    ),
    kpi AS (
        SELECT * FROM fn_taller_bono_kpi_periodo(p_desde, p_hasta, p_disponibilidad)
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
        NULLIF(concat_ws(' · ',
            k.falta,
            pl.falta,
            CASE WHEN COALESCE(pl.p, 0) > round(cg.plan_tope_clp * k.prorrateo)
                 THEN 'la suma de las OT pasa el tope del cargo: se paga el tope' END
        ), '')
      FROM kpi k
      LEFT JOIN plan pl ON pl.tid = k.tecnico_id
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = k.cargo
     ORDER BY k.tecnico;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_disponibilidad_periodo(DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_periodo(DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_kpi_periodo(DATE, DATE, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_disponibilidad_periodo(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_periodo(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_kpi_periodo(DATE, DATE, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_taller_disponibilidad_periodo','fn_taller_bono_kpi_periodo',
                         'fn_taller_bono_resumen');
    IF v_n <> 3 THEN RAISE EXCEPTION 'FALLO: faltan funciones del bono (%)', v_n; END IF;

    -- Una sola firma de fn_taller_bono_periodo, o vuelve el «is not unique».
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_taller_bono_periodo';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: fn_taller_bono_periodo quedó con % firmas', v_n; END IF;

    FOR r IN SELECT * FROM fn_taller_disponibilidad_periodo(DATE '2026-07-24', DATE '2026-08-23') LOOP
        RAISE NOTICE 'corte 24-jul a 23-ago · disponibilidad % (promedio diario %) · % dias-equipo en % dias',
            r.disponibilidad_pct, r.promedio_diario_pct, r.dias_equipo, r.dias_con_registro;
    END LOOP;

    SELECT count(*) INTO v_n FROM fn_taller_bono_resumen(DATE '2026-09-01', DATE '2026-09-30');
    RAISE NOTICE 'el resumen de septiembre ya responde: % técnicos en la cartola', v_n;
END
$mig$;

COMMIT;
