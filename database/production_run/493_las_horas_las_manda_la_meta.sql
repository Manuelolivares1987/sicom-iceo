-- ============================================================================
-- MIG493 · Las horas las manda la meta, y pasarse del normal se justifica
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 02-09-2026: «quiero que se siga a la meta y ahí el sistema calcule; donde se
-- coloquen más horas respecto del normal, ahí pida una justificación».
--
-- LO QUE CAMBIA RESPECTO DE MIG491
-- MIG491 hizo que el campo siguiera a los días marcados en el calendario. Es
-- una lectura razonable, pero no es la que manda: la meta es el compromiso. El
-- planificador declara optimizado o normal, y de ahí salen las horas. Los días
-- del calendario siguen siendo los que ocupan el taller, pero el número que se
-- compromete es el de la meta.
--
--   MPN optimizado (1 día)  →  8 h        MPN normal (2 días)   →  16 h
--   MTN optimizado (5 días) →  40 h       MTN normal (10 días)  →  80 h
--   RCR optimizado (5 días) →  40 h       RCR normal (10 días)  →  80 h
--   RSR optimizado (2 días) →  16 h       RSR normal (4 días)   →  32 h
--
-- EL TECHO
-- El tramo NORMAL es el límite de lo que se puede comprometer sin explicar. No
-- el optimizado: comprometerse a lo normal es una decisión legítima del
-- planificador y no tiene por qué justificarse. Pasarse del normal, sí — porque
-- ahí el equipo entra en el tramo de demora, que es donde el incentivo empieza
-- a castigar y donde el camión está detenido de más.
--
-- DÓNDE QUEDA LA JUSTIFICACIÓN
-- En la OT, con quién la escribió y cuándo. No en un log: es parte de por qué
-- esa visita costó lo que costó, y quien mire el bono el mes siguiente tiene que
-- poder leerla sin buscar en otra parte.
-- ============================================================================

BEGIN;

ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS horas_plan_justificacion   TEXT,
  ADD COLUMN IF NOT EXISTS horas_plan_justificada_por UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS horas_plan_justificada_at  TIMESTAMPTZ;

COMMENT ON COLUMN ordenes_trabajo.horas_plan_justificacion IS
    'Por qué esta visita se comprometió con más horas que el tramo normal de su '
    'tipo de tarea. Lo escribe el planificador al programar.';

-- ── Cuántas horas son la meta, y cuál es el techo sin justificar ────────────
CREATE OR REPLACE FUNCTION fn_taller_horas_meta(p_concepto TEXT, p_meta TEXT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT round(
        CASE WHEN COALESCE(p_meta,'normal') = 'optimizado' THEN c.dias_optimizado
             ELSE c.dias_normal END * fn_taller_horas_jornada(), 2)
      FROM taller_bono_concepto c
      JOIN taller_bono_parametros p ON p.id = c.parametros_id AND p.estado = 'vigente'
     WHERE c.concepto = p_concepto;
$$;

COMMENT ON FUNCTION fn_taller_horas_meta(TEXT, TEXT) IS
    'Las horas que compromete una meta: los días de ese tramo por la jornada '
    'del taller. Es lo que el planificador declara para la visita.';

CREATE OR REPLACE FUNCTION fn_taller_horas_tope_sin_justificar(p_concepto TEXT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT fn_taller_horas_meta(p_concepto, 'normal');
$$;

COMMENT ON FUNCTION fn_taller_horas_tope_sin_justificar(TEXT) IS
    'Hasta acá se puede comprometer sin explicar: el tramo normal. Más arriba '
    'el equipo entra en demora, y eso se escribe.';

-- ── Fijar las horas de la visita ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_ot_set_horas_plan(
    p_ot_id         UUID,
    p_horas         NUMERIC,
    p_justificacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_rol      TEXT;
    v_concepto TEXT;
    v_tope     NUMERIC;
    v_primera  UUID;
    v_just     TEXT := NULLIF(btrim(COALESCE(p_justificacion,'')), '');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado para fijar las horas del plan', v_rol;
    END IF;

    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Las horas de la visita tienen que ser mayores que cero.';
    END IF;

    SELECT COALESCE(ot.bono_concepto, fn_taller_ot_concepto(ot.id))
      INTO v_concepto FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
    IF v_concepto IS NULL THEN
        RAISE EXCEPTION 'Esa OT no existe o no se le pudo deducir el tipo de tarea.';
    END IF;

    v_tope := fn_taller_horas_tope_sin_justificar(v_concepto);

    -- El tramo normal es el límite de lo que se compromete sin explicar.
    IF v_tope IS NOT NULL AND p_horas > v_tope AND (v_just IS NULL OR length(v_just) < 10) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'requiere_justificacion', TRUE,
            'tope_normal', v_tope,
            'concepto', v_concepto,
            'motivo', 'Estás comprometiendo ' || p_horas || ' h y el tramo normal de '
                      || v_concepto || ' son ' || v_tope || ' h. Escribe por qué esta visita '
                      || 'necesita más: queda en la OT.');
    END IF;

    -- Las horas van en la PRIMERA jornada: son el total del equipo para la
    -- visita, no una cuota por día. La suma de las jornadas es el paraguas, así
    -- que repetirlas en cada día lo multiplicaría (misma regla que MIG476).
    SELECT po.id INTO v_primera
      FROM taller_plan_semanal_ots po
      JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
     WHERE po.ot_id = p_ot_id
       AND COALESCE(po.estado_plan,'planificada') <> 'cancelada'
     ORDER BY d.fecha
     LIMIT 1;

    IF v_primera IS NULL THEN
        RAISE EXCEPTION 'Esta OT todavía no tiene jornadas en el plan.';
    END IF;

    UPDATE taller_plan_semanal_ots SET horas_planificadas = NULL, updated_at = NOW()
     WHERE ot_id = p_ot_id AND id <> v_primera;
    UPDATE taller_plan_semanal_ots SET horas_planificadas = p_horas, updated_at = NOW()
     WHERE id = v_primera;

    UPDATE ordenes_trabajo
       SET horas_plan_justificacion   = v_just,
           horas_plan_justificada_por = CASE WHEN v_just IS NOT NULL THEN v_user END,
           horas_plan_justificada_at  = CASE WHEN v_just IS NOT NULL THEN NOW() END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', TRUE, 'horas', p_horas,
                              'tope_normal', v_tope, 'concepto', v_concepto,
                              'justificada', v_just IS NOT NULL);
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_horas_meta(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_horas_tope_sin_justificar(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_ot_set_horas_plan(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_horas_meta(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_horas_tope_sin_justificar(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_ot_set_horas_plan(UUID, NUMERIC, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT c.concepto,
                    fn_taller_horas_meta(c.concepto, 'optimizado') AS opt,
                    fn_taller_horas_meta(c.concepto, 'normal')     AS nor
               FROM taller_bono_concepto c
               JOIN taller_bono_parametros p ON p.id = c.parametros_id AND p.estado='vigente'
              ORDER BY c.concepto
    LOOP
        RAISE NOTICE '  %: optimizado % h · normal % h (sobre esto, se justifica)',
                     r.concepto, r.opt, r.nor;
    END LOOP;
END $mig$;

COMMIT;
