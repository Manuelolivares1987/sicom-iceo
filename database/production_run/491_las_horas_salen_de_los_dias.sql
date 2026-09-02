-- ============================================================================
-- MIG491 · Las horas de la visita salen de los días que se planifican
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 02-09-2026: «el tiempo del equipo para esta visita, que aparece a la hora de
-- programar, no coincide con los días a planificar. Esperaría que el sistema
-- calcule solo las horas en función a los días que el planificador coloque».
--
-- LO QUE PASABA
-- MIG476 puso ahí las horas del TIPO DE TAREA: una MTN son 32,5 h, vengan de
-- donde vengan los días. Así que el planificador elegía 3 días y el campo
-- seguía diciendo 32,5; elegía 8 días y decía 32,5 igual. El número no mentía
-- —es el estándar de la tarea— pero no era el tiempo de ESA visita, que es lo
-- que el campo promete.
--
-- LA REGLA NUEVA
-- El tiempo del equipo para la visita es lo que el equipo va a estar en el
-- taller: los días que puso el planificador por la jornada del taller. Si son
-- 3 días, son 24 horas. Se recalcula solo al agregar o quitar días.
--
-- QUÉ PASA CON EL ESTÁNDAR DEL TIPO DE TAREA
-- No se va: se muestra al lado. Son dos cosas distintas y conviene verlas
-- juntas. El estándar dice cuánto TRABAJO tiene una MTN (32,5 h medidas sobre
-- 43 OS históricas); los días dicen cuánto va a estar el camión detenido. Que
-- 5 días de taller den 40 h para 32,5 h de trabajo no es un error: es la
-- holgura del plan, y verla es justamente el punto.
--
-- LA JORNADA ES UNA FILA, NO UN NÚMERO EN EL CÓDIGO
-- 8 horas por día. Si el taller cambia de turno, se edita el parámetro y todo
-- lo que se planifique después usa el nuevo — sin tocar SQL.
-- ============================================================================

BEGIN;

ALTER TABLE taller_bono_parametros
  ADD COLUMN IF NOT EXISTS horas_jornada NUMERIC(5,2) NOT NULL DEFAULT 8.0;

COMMENT ON COLUMN taller_bono_parametros.horas_jornada IS
    'Cuántas horas de taller tiene un día planificado. De acá sale el tiempo '
    'del equipo para una visita: días × jornada.';

/**
 * Las horas de taller que tiene un día, según los parámetros vigentes.
 */
CREATE OR REPLACE FUNCTION fn_taller_horas_jornada()
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT p.horas_jornada FROM taller_bono_parametros p
          WHERE p.estado = 'vigente'
          ORDER BY p.vigencia_desde DESC LIMIT 1),
        8.0);
$$;

/**
 * El tiempo que le corresponde a una visita de N días.
 *
 * Existe como función y no como multiplicación suelta en la pantalla porque el
 * mismo número lo van a necesitar el planificador, el techo de las OS y
 * cualquier informe que compare lo planificado con lo real.
 */
CREATE OR REPLACE FUNCTION fn_taller_horas_por_dias(p_dias INT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT CASE WHEN COALESCE(p_dias, 0) <= 0 THEN NULL
                ELSE round(p_dias * 8.0, 2) END;
$$;

COMMENT ON FUNCTION fn_taller_horas_por_dias(INT) IS
    'Días planificados por la jornada del taller. IMMUTABLE a propósito: se usa '
    'en cálculos y no puede depender de una lectura de tabla. Si cambia la '
    'jornada, se cambia acá y en fn_taller_horas_jornada.';

-- ── Lo que ya está planificado, para ver cuánto se desvía ───────────────────
--
-- No se corrige nada de lo existente: las horas que puso el planificador son
-- suyas. Pero conviene poder mirar dónde el número no calza con los días, que
-- es exactamente lo que Manuel vio.
CREATE OR REPLACE VIEW v_taller_ot_horas_vs_dias AS
SELECT ot.id AS ot_id,
       ot.folio,
       a.patente,
       ot.bono_concepto AS concepto,
       count(po.id)::INT                      AS dias_planificados,
       sum(po.horas_planificadas)             AS horas_planificadas,
       fn_taller_horas_por_dias(count(po.id)::INT) AS horas_por_los_dias,
       c.horas_estandar                       AS horas_estandar_del_tipo
  FROM ordenes_trabajo ot
  JOIN activos a ON a.id = ot.activo_id
  JOIN taller_plan_semanal_ots po ON po.ot_id = ot.id
  LEFT JOIN taller_bono_concepto c
         ON c.concepto = ot.bono_concepto
        AND c.parametros_id = (SELECT id FROM taller_bono_parametros
                                WHERE estado = 'vigente'
                                ORDER BY vigencia_desde DESC LIMIT 1)
 WHERE COALESCE(po.estado_plan,'planificada') <> 'cancelada'
 GROUP BY ot.id, ot.folio, a.patente, ot.bono_concepto, c.horas_estandar;

GRANT SELECT ON v_taller_ot_horas_vs_dias TO authenticated;

REVOKE ALL ON FUNCTION fn_taller_horas_jornada() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_horas_por_dias(INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_horas_jornada() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_horas_por_dias(INT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_j NUMERIC; v_desv INT; v_tot INT; r RECORD;
BEGIN
    SELECT fn_taller_horas_jornada() INTO v_j;
    SELECT count(*) INTO v_tot FROM v_taller_ot_horas_vs_dias WHERE horas_planificadas IS NOT NULL;
    SELECT count(*) INTO v_desv FROM v_taller_ot_horas_vs_dias
     WHERE horas_planificadas IS NOT NULL
       AND horas_planificadas <> horas_por_los_dias;
    RAISE NOTICE 'jornada: % h · OT con horas puestas: % · de ellas, que no calzan con sus días: %',
                 v_j, v_tot, v_desv;
    FOR r IN SELECT folio, patente, dias_planificados, horas_planificadas, horas_por_los_dias
               FROM v_taller_ot_horas_vs_dias
              WHERE horas_planificadas IS NOT NULL
                AND horas_planificadas <> horas_por_los_dias
              ORDER BY folio LIMIT 8
    LOOP
        RAISE NOTICE '  % (%): % días planificados, % h puestas, le corresponderían %',
                     r.folio, r.patente, r.dias_planificados, r.horas_planificadas, r.horas_por_los_dias;
    END LOOP;
END $mig$;

COMMIT;
