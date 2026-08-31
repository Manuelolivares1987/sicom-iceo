-- ============================================================================
-- MIG452 · El motor del bono del taller
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 31-08-2026: «¿cómo sé el cálculo del bono?».
--
-- Hasta acá se construyó de qué se alimenta el bono —quién trabajó, en qué
-- fechas, qué tipo de trabajo, cuánto tiempo puso cada uno—. Faltaba lo que
-- convierte eso en pesos. Esto es eso.
--
-- PRINCIPIO DE DISEÑO
-- Una decisión de criterio cambia una FILA, no una migración. Los topes, los
-- coeficientes, los tramos y los estándares de días viven en tablas con
-- vigencia, no en el código. Cuando el acta resuelva D1 o D14, se edita un
-- parámetro y se recalcula; no se toca SQL.
--
-- LA FÓRMULA, TRANSCRITA LITERAL DEL ARCHIVO DE BONOS
--
--   =IF(d>0, IF(d<=opt,    coef_opt*tope*opt,
--             IF(d<=normal, d*coef_dia*tope,
--                           (demora-d)*coef_dia*tope)), 0)
--
-- donde d es el CONTADOR DE DÍAS de ese concepto en la línea. Se implementa tal
-- cual, sin corregirla, porque el objetivo de la marcha blanca es comparar el
-- sistema contra la planilla: si acá se corrige, la comparación no sirve.
--
-- PERO LA FÓRMULA TIENE TRES DEFECTOS, Y EL MOTOR CALCULA TAMBIÉN LA VERSIÓN
-- CORREGIDA, PARA QUE LA DIFERENCIA SE VEA EN VEZ DE DISCUTIRSE:
--
--   1. NO ES MONÓTONA. Para MTN y RCR, cerrar en 5 días paga 22,73% del tope,
--      exactamente lo mismo que cerrar en 10. Y entre 6 y 9 días paga MENOS
--      que cerrar en 10. Apurarse castiga.
--
--   2. PUEDE PAGAR NEGATIVO. El tramo de demora es (demora - d): una MTN
--      cerrada en 25 días da (20-25) = -5, o sea descuenta $18.181 del bono.
--      Nada en la planilla impide que una línea reste.
--
--   3. NO TIENE TOPE. El total es un SUM sin MIN contra el tope del cargo
--      (está en la hoja «36 Formulas fuente»: «No tiene MIN contra el tope: si
--      se agregan lineas puede superarlo»).
--
-- La versión corregida: interpola de 100% a 60% dentro del tramo normal y de
-- 60% a 0% dentro del de demora, nunca baja de cero, y aplica el tope al total.
-- Cerrar antes siempre paga más o igual. Es lo que propone la decisión D14.
--
-- LO QUE ESTE MOTOR NO INVENTA
-- El cargo de cada técnico no está en el sistema, así que la tabla queda creada
-- y vacía: sin cargo no hay tope, y sin tope el motor devuelve el trabajo
-- contado pero el monto en NULL, diciendo qué falta. Prefiero que diga «falta el
-- cargo de Joel Coo» a que invente un número.
-- ============================================================================

BEGIN;

-- ── 1 · Un juego de parámetros con vigencia ─────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_bono_parametros (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre         TEXT NOT NULL,
    vigencia_desde DATE NOT NULL,
    vigencia_hasta DATE,
    estado         TEXT NOT NULL DEFAULT 'borrador',
    notas          TEXT,
    creado_por     UUID REFERENCES usuarios_perfil(id),
    creado_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activado_por   UUID REFERENCES usuarios_perfil(id),
    activado_at    TIMESTAMPTZ,
    CONSTRAINT chk_bono_param_estado CHECK (estado IN ('borrador','vigente','archivado'))
);

COMMENT ON TABLE taller_bono_parametros IS
'Juego de parámetros del bono con vigencia. Una decisión de criterio cambia una fila, no una migración (MIG452).';

CREATE TABLE IF NOT EXISTS taller_bono_concepto (
    parametros_id   UUID NOT NULL REFERENCES taller_bono_parametros(id) ON DELETE CASCADE,
    concepto        TEXT NOT NULL,
    descripcion     TEXT NOT NULL,
    dias_optimizado NUMERIC NOT NULL,
    dias_normal     NUMERIC NOT NULL,
    dias_demora     NUMERIC NOT NULL,
    coef_optimizado NUMERIC NOT NULL,
    coef_por_dia    NUMERIC NOT NULL,
    PRIMARY KEY (parametros_id, concepto),
    CONSTRAINT chk_bono_concepto CHECK (concepto IN ('MTN','MPN','RSR','RCR'))
);

CREATE TABLE IF NOT EXISTS taller_bono_tramo_kpi (
    parametros_id UUID NOT NULL REFERENCES taller_bono_parametros(id) ON DELETE CASCADE,
    desde_pct     NUMERIC NOT NULL,
    factor        NUMERIC NOT NULL,
    etiqueta      TEXT NOT NULL,
    PRIMARY KEY (parametros_id, desde_pct)
);

CREATE TABLE IF NOT EXISTS taller_bono_cargo (
    parametros_id UUID NOT NULL REFERENCES taller_bono_parametros(id) ON DELETE CASCADE,
    cargo         TEXT NOT NULL,
    kpi_base_clp  NUMERIC NOT NULL,
    plan_tope_clp NUMERIC NOT NULL,
    fuente        TEXT,
    PRIMARY KEY (parametros_id, cargo)
);

-- Qué cargo tiene cada técnico. Sin esto no hay tope, y sin tope no hay monto.
CREATE TABLE IF NOT EXISTS taller_tecnico_cargo (
    tecnico_id UUID NOT NULL REFERENCES taller_tecnicos(id),
    cargo      TEXT NOT NULL,
    desde      DATE NOT NULL DEFAULT CURRENT_DATE,
    hasta      DATE,
    PRIMARY KEY (tecnico_id, desde)
);

COMMENT ON TABLE taller_tecnico_cargo IS
'El cargo decide el tope y la base KPI. Nace vacía a propósito: es un dato de RRHH que nadie ha cargado, y el motor prefiere decir que falta antes que suponerlo (MIG452).';

-- ── 2 · El juego de septiembre, en borrador ─────────────────────────────────
DO $mig$
DECLARE v_id UUID;
BEGIN
    SELECT id INTO v_id FROM taller_bono_parametros WHERE nombre = 'Septiembre 2026 · borrador';
    IF v_id IS NOT NULL THEN
        RAISE NOTICE 'el juego de parámetros ya existe — sin cambios';
        RETURN;
    END IF;

    INSERT INTO taller_bono_parametros (nombre, vigencia_desde, estado, notas)
    VALUES ('Septiembre 2026 · borrador', DATE '2026-09-01', 'borrador',
            'Coeficientes transcritos del archivo de bonos de agosto y tramos de la Estructura KPI 2025. ' ||
            'Queda en BORRADOR: los topes por cargo dependen de la decisión D1 (qué documento rige) y la ' ||
            'curva de la decisión D14. Activar sólo cuando exista acta.')
    RETURNING id INTO v_id;

    -- Estándares de días y coeficientes, literales de la hoja «Definiciones»
    INSERT INTO taller_bono_concepto VALUES
      (v_id,'MTN','Mantención Total (post arriendo)',      5, 10, 20, 0.045454545454545, 0.0227272727272727),
      (v_id,'MPN','Mantención Preventiva (en arriendo)',   1,  2,  4, 0.045454545454545, 0.0227272727272727),
      (v_id,'RSR','Reparación Sin Reemplazo',              2,  4,  8, 0.0227272727272727, 0.0113636363636363),
      (v_id,'RCR','Reparación Con Reemplazo',              5, 10, 20, 0.045454545454545, 0.0227272727272727);

    -- Tramos del KPI de disponibilidad, de la Estructura KPI 2025
    INSERT INTO taller_bono_tramo_kpi VALUES
      (v_id, 0.85, 1.00, 'Cumplimiento del 85% o más'),
      (v_id, 0.82, 0.60, 'Igual o sobre 82% y bajo 85%'),
      (v_id, 0.80, 0.30, 'Igual o sobre 80% y bajo 82%'),
      (v_id, 0.00, 0.00, 'Bajo 80%');

    -- Topes por cargo · escenario B = la Estructura escrita, que es lo que la
    -- auditoría recomienda mientras no exista una versión 2026 firmada (D1).
    INSERT INTO taller_bono_cargo VALUES
      (v_id,'Mecanico A', 100000, 160000, 'Estructura KPI 2025, Técnico A'),
      (v_id,'Mecanico B',  80000, 130000, 'Estructura KPI 2025, Técnico B'),
      (v_id,'Mecanico C',  50000, 140000, 'Estructura KPI 2025, Técnico C'),
      (v_id,'Aprendiz',    40000, 120000, 'Estructura KPI 2025, Aprendiz'),
      (v_id,'Soldador',    80000, 160000, 'NO existe en la Estructura KPI: replica la práctica de agosto (decisión D9)'),
      (v_id,'Conductor',   80000,      0, 'NO existe en la Estructura KPI: su plan es 0 (decisión D9)');

    RAISE NOTICE 'juego de parámetros creado en BORRADOR';
END
$mig$;

-- ── 3 · El concepto de cada OT, deducido ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_concepto(p_ot_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tipo      TEXT;
    v_contrato  UUID;
    v_repuestos BOOLEAN;
BEGIN
    SELECT ot.tipo::TEXT, ot.contrato_id INTO v_tipo, v_contrato
      FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
    IF v_tipo IS NULL THEN RETURN NULL; END IF;

    -- ¿Salió algo de bodega por esta OT? Es lo que separa una reparación con
    -- reemplazo de una sin reemplazo, y hoy depende de que el mecánico se
    -- acuerde. El kárdex se acuerda siempre.
    v_repuestos := EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = p_ot_id)
                OR EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = p_ot_id);

    RETURN CASE
        WHEN v_tipo IN ('correctivo') AND v_repuestos THEN 'RCR'
        WHEN v_tipo IN ('correctivo')                 THEN 'RSR'
        -- La mantención total es la que se hace cuando el equipo vuelve de
        -- arriendo: sin contrato vigente asociado.
        WHEN v_tipo IN ('preventivo','inspeccion') AND v_contrato IS NULL THEN 'MTN'
        WHEN v_tipo IN ('preventivo','inspeccion')                        THEN 'MPN'
        ELSE NULL
    END;
END;
$$;

COMMENT ON FUNCTION fn_taller_ot_concepto IS
'MTN/MPN/RSR/RCR deducidos de la OT: tipo, contrato y salidas de bodega. Antes lo escribía el mecánico a mano (MIG452).';

-- ── 4 · El motor ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_bono_periodo(
    p_desde DATE,
    p_hasta DATE,
    p_disponibilidad NUMERIC DEFAULT NULL
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

COMMENT ON FUNCTION fn_taller_bono_periodo IS
'El bono de un período, línea por línea: OT, concepto, días, tramo, reparto y monto. Calcula la fórmula actual y la corregida para poder compararlas (MIG452).';

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; v_lineas INT; v_par TEXT;
BEGIN
    SELECT count(*) INTO v_n FROM taller_bono_concepto;
    IF v_n < 4 THEN RAISE EXCEPTION 'FALLO: faltan conceptos (%)', v_n; END IF;

    SELECT nombre || ' · ' || estado INTO v_par FROM taller_bono_parametros ORDER BY creado_at DESC LIMIT 1;
    RAISE NOTICE 'parámetros: %', v_par;

    -- El primer período que este juego cubre: el corte de septiembre.
    SELECT count(*) INTO v_lineas FROM fn_taller_bono_periodo(DATE '2026-09-01', DATE '2026-09-30');
    RAISE NOTICE 'líneas de bono del corte de septiembre: % (empieza en cero: el mes no ha ocurrido)', v_lineas;

    SELECT count(*) INTO v_n FROM taller_tecnico_cargo;
    RAISE NOTICE 'técnicos con cargo cargado: % (sin cargo no hay tope, y el motor lo dice)', v_n;
END
$mig$;

COMMIT;
