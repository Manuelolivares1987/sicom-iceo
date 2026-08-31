-- ============================================================================
-- MIG458 · Lo que falta y lo que sólo avisa
-- ============================================================================
--
-- ENCONTRADO PROBANDO EL CIERRE, ANTES DE QUE LO USARA NADIE
-- MIG456 puso la regla «no se cierra con huecos»: si alguna línea trae algo en
-- `falta`, el cierre se niega. Al probarlo contra el corte de agosto, se negó
-- por esto:
--
--     Falta información para cerrar. Yusdel Sarduy: reparto sin tiempo medido
--
-- Y eso NO es un hueco. «Reparto sin tiempo medido» significa que la cuadrilla
-- no tiene cronómetro en esa OT y el bono se repartió en partes iguales, que es
-- el respaldo previsto y documentado. Es información que hay que ver, no un
-- dato que falte. Con la regla como estaba, ningún corte se habría podido
-- cerrar hasta que TODAS las OT tuvieran tiempo medido — y el reloj recién se
-- conectó en MIG449.
--
-- Lo mismo con «la suma de las OT pasa el tope del cargo»: eso es el tope
-- haciendo su trabajo. Bloquear ahí sería castigar al sistema por funcionar.
--
-- LA DISTINCIÓN, ESCRITA EN EL MODELO Y NO EN UN IF
--
--   falta → lo que IMPIDE pagar. Sin cargo no hay tope; sin concepto no hay
--           estándar de días. No se puede poner un número. Bloquea el cierre.
--
--   aviso → lo que hay que SABER para leer el número. El reparto fue en partes
--           iguales; el tope recortó la suma. No bloquea nada, y va impreso en
--           la cartola del trabajador, que es quien tiene derecho a saberlo.
--
-- Un candado que se dispara con cosas que no son problemas termina desactivado
-- por quien lo usa. Prefiero un candado que sólo suena cuando de verdad hay
-- algo, y un aviso que se lee.
--
-- El cierre de MIG456 no cambia: sigue bloqueando con `falta`. Lo que cambia es
-- qué cae en `falta`.
-- ============================================================================

BEGIN;

-- Las columnas nuevas van al final: no se puede insertar al medio en una vista
-- ni cambiar el orden de un RETURNS TABLE sin recrearlo entero.
ALTER TABLE taller_bono_periodo_linea   ADD COLUMN IF NOT EXISTS aviso TEXT;
ALTER TABLE taller_bono_periodo_detalle ADD COLUMN IF NOT EXISTS aviso TEXT;

DROP FUNCTION IF EXISTS fn_taller_bono_resumen(DATE, DATE, NUMERIC);
DROP FUNCTION IF EXISTS fn_taller_bono_periodo(DATE, DATE);

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

-- El cierre guarda también el aviso: la cartola tiene que poder explicarse sola
-- dentro de un año, cuando nadie se acuerde de por qué ese reparto fue mitad y
-- mitad.
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

    -- [MIG458] Bloquea sólo lo que impide poner un número. Los avisos se
    -- guardan y se muestran, no frenan el cierre.
    SELECT string_agg(DISTINCT r.tecnico || ': ' || r.falta, ' · ')
      INTO v_faltan
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r
     WHERE r.falta IS NOT NULL;
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta información para cerrar. %', v_faltan;
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

REVOKE ALL ON FUNCTION fn_taller_bono_periodo(DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_bono_periodo(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; r RECORD; v_f INT := 0; v_a INT := 0;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_taller_bono_periodo';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: fn_taller_bono_periodo quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_taller_bono_resumen';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: fn_taller_bono_resumen quedó con % firmas', v_n; END IF;

    -- Sobre el primer corte con parámetros (septiembre), ¿qué cae de cada lado?
    FOR r IN SELECT * FROM fn_taller_bono_resumen(DATE '2026-09-01', DATE '2026-09-30') LOOP
        IF r.falta IS NOT NULL THEN v_f := v_f + 1; END IF;
        IF r.aviso IS NOT NULL THEN
            v_a := v_a + 1;
            RAISE NOTICE 'aviso · %: %', r.tecnico, r.aviso;
        END IF;
    END LOOP;
    RAISE NOTICE 'corte septiembre · % líneas bloquean el cierre, % sólo avisan', v_f, v_a;
END
$mig$;

COMMIT;
