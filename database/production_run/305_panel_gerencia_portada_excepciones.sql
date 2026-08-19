-- ############################################################################
-- MIG305 · Panel de Gerencia — portada, excepciones y compromisos
-- ----------------------------------------------------------------------------
-- MIG295-297 dejaron el panel completo pero plano: dos columnas donde una
-- fluctuación de estanque pesa lo mismo que 43 OT arrastradas. El gerente abre
-- y no sabe dónde mirar.
--
-- Esta migración le da al RPC lo que le falta para que el panel se pueda leer
-- de arriba hacia abajo:
--
--   1. `resumen`      — los KPI del negocio COMPLETO (Coquimbo + Calama) con su
--                       valor del período anterior, para que cada número diga
--                       si vamos mejor o peor. Sin esto un 87% no significa
--                       nada.
--   2. `excepciones`  — lo que está fuera de norma, en UNA lista ordenada por
--                       severidad y cruzando los cuatro dominios (equipos,
--                       contrato ENEX, combustible, taller, calidad del dato).
--                       Es la agenda de la reunión.
--   3. `compromisos`  — los planes de acción con responsable y fecha, sacados
--                       de su escondite dentro de cada equipo y consolidados,
--                       con estado propio para poder cerrarlos. Un compromiso
--                       que no se puede marcar cumplido no es un compromiso.
--
-- Nada de lo anterior se elimina: el detalle de MIG295-297 sigue igual y el
-- frontend lo muestra colapsado abajo.
-- ############################################################################

-- ############################################################################
-- 1. ESTADO DEL COMPROMISO
-- ----------------------------------------------------------------------------
-- panel_comentarios ya guardaba plan_accion + responsable + fecha_compromiso,
-- pero no había forma de cerrarlos: la lista sólo crecía y a la tercera semana
-- nadie la mira. Se agrega el ciclo de vida mínimo (pendiente → cumplido) con
-- quién y cuándo, que es lo que se pregunta en la reunión siguiente.
-- ############################################################################

ALTER TABLE panel_comentarios
    ADD COLUMN IF NOT EXISTS compromiso_estado VARCHAR(12) NOT NULL DEFAULT 'pendiente',
    ADD COLUMN IF NOT EXISTS cumplido_at       TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cumplido_por      UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'panel_comentarios_compromiso_estado_chk'
    ) THEN
        ALTER TABLE panel_comentarios
            ADD CONSTRAINT panel_comentarios_compromiso_estado_chk
            CHECK (compromiso_estado IN ('pendiente', 'cumplido', 'anulado'));
    END IF;
END $$;

COMMENT ON COLUMN panel_comentarios.compromiso_estado IS
    'Ciclo de vida del plan de acción: pendiente | cumplido | anulado. MIG305.';

-- Índice para la bandeja de compromisos: se consulta por estado y fecha, no
-- por semana (un compromiso de hace tres semanas sigue vivo si nadie lo cerró).
CREATE INDEX IF NOT EXISTS idx_panel_comentarios_compromiso
    ON panel_comentarios (compromiso_estado, fecha_compromiso)
    WHERE plan_accion IS NOT NULL;


-- ── 1.1 Cerrar / reabrir un compromiso ─────────────────────────────────────
DROP FUNCTION IF EXISTS fn_panel_compromiso_estado(UUID, TEXT);
CREATE FUNCTION fn_panel_compromiso_estado(
    p_id     UUID,
    p_estado TEXT
)
RETURNS JSONB
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_fila panel_comentarios%ROWTYPE;
BEGIN
    IF NOT fn_panel_gerencia_puede_comentar() THEN
        RAISE EXCEPTION 'No autorizado para cerrar compromisos del Panel de Gerencia.'
            USING ERRCODE = '42501';
    END IF;

    IF p_estado NOT IN ('pendiente', 'cumplido', 'anulado') THEN
        RAISE EXCEPTION 'Estado de compromiso inválido: %', p_estado
            USING ERRCODE = '22023';
    END IF;

    UPDATE panel_comentarios
       SET compromiso_estado = p_estado,
           -- Reabrir limpia la firma: si vuelve a pendiente, nadie lo cumplió.
           cumplido_at  = CASE WHEN p_estado = 'pendiente' THEN NULL ELSE NOW() END,
           cumplido_por = CASE WHEN p_estado = 'pendiente' THEN NULL ELSE auth.uid() END
     WHERE id = p_id
    RETURNING * INTO v_fila;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el comentario %', p_id USING ERRCODE = 'P0002';
    END IF;

    RETURN to_jsonb(v_fila);
END $$;

GRANT EXECUTE ON FUNCTION fn_panel_compromiso_estado(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_panel_compromiso_estado(UUID, TEXT) IS
    'Marca un plan de acción como cumplido / anulado / pendiente. MIG305.';


-- ############################################################################
-- 2. COMPROMISOS CONSOLIDADOS
-- ----------------------------------------------------------------------------
-- Los planes de acción viven dentro de cada equipo y cada faena, uno por
-- semana. Aquí se juntan todos los que siguen pendientes —da igual en qué
-- semana se escribieron— más los cerrados de la semana en curso, para que se
-- vea lo que sí se cumplió.
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_compromisos(DATE, INTEGER);
CREATE FUNCTION fn_panel_compromisos(
    p_semana   DATE,
    p_semanas_atras INTEGER DEFAULT 12
)
RETURNS TABLE (
    id                UUID,
    semana            DATE,
    ambito            TEXT,
    cuadrante         TEXT,
    activo_id         UUID,
    enex_faena_id     UUID,
    referencia        TEXT,
    plan_accion       TEXT,
    texto             TEXT,
    responsable       TEXT,
    fecha_compromiso  DATE,
    compromiso_estado TEXT,
    cumplido_at       TIMESTAMPTZ,
    dias_restantes    INTEGER,
    vencido           BOOLEAN,
    antiguedad_dias   INTEGER
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT c.id,
           c.semana,
           c.ambito::TEXT,
           COALESCE(
               c.cuadrante,
               CASE WHEN c.enex_faena_id IS NOT NULL THEN 'calama' END,
               lower(a.operacion)
           )::TEXT,
           c.activo_id,
           c.enex_faena_id,
           -- Cómo se nombra el compromiso en la lista. Sin esto el gerente ve
           -- "reparar bomba" sin saber de qué equipo hablamos.
           COALESCE(
               a.codigo,
               ef.nombre,
               initcap(c.cuadrante),
               'Semana'
           )::TEXT,
           c.plan_accion,
           c.texto,
           c.responsable::TEXT,
           c.fecha_compromiso,
           c.compromiso_estado::TEXT,
           c.cumplido_at,
           (c.fecha_compromiso - CURRENT_DATE)::INTEGER,
           (c.compromiso_estado = 'pendiente'
            AND c.fecha_compromiso IS NOT NULL
            AND c.fecha_compromiso < CURRENT_DATE),
           (CURRENT_DATE - c.semana)::INTEGER
      FROM panel_comentarios c
      LEFT JOIN activos     a  ON a.id  = c.activo_id
      LEFT JOIN enex_faenas ef ON ef.id = c.enex_faena_id
     WHERE c.plan_accion IS NOT NULL
       AND btrim(c.plan_accion) <> ''
       AND c.semana >  p_semana - (GREATEST(p_semanas_atras, 1) * 7)
       AND c.semana <= p_semana
       -- Lo pendiente arrastra de semanas anteriores; lo cerrado sólo se
       -- muestra en su propia semana, para no acumular historia muerta.
       AND (c.compromiso_estado = 'pendiente' OR c.semana = p_semana)
     ORDER BY
           -- Vencido primero, después por fecha comprometida; los sin fecha al
           -- final porque no se les puede exigir nada.
           (c.compromiso_estado <> 'pendiente'),
           (c.fecha_compromiso IS NULL),
           c.fecha_compromiso ASC,
           c.semana ASC;
$$;

GRANT EXECUTE ON FUNCTION fn_panel_compromisos(DATE, INTEGER) TO authenticated;

COMMENT ON FUNCTION fn_panel_compromisos(DATE, INTEGER) IS
    'Planes de acción consolidados de todos los ámbitos, con estado y vencimiento. MIG305.';


-- ############################################################################
-- 3. EXCEPCIONES — la agenda de la reunión
-- ----------------------------------------------------------------------------
-- Una sola lista con todo lo que está fuera de norma, cruzando dominios que
-- hoy están en tarjetas separadas. Ordenada por severidad y, dentro de la
-- misma severidad, por impacto económico o por antigüedad.
--
-- Umbrales (los de gestión, no inventados aquí):
--   · equipo detenido      → 10 días de corrido = crítico; 5 = alto
--   · disponibilidad       → meta 90%; bajo 70% en el mes = alto
--   · fluctuación estanque → 0,5% habitual en combustible; 1,5% = crítico
--   · backlog de OT        → 30 días de antigüedad promedio
--   · rezago del dato      → 3 días sin cargar invalida el resto del panel
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_excepciones(DATE, DATE, DATE);
CREATE FUNCTION fn_panel_excepciones(
    p_semana   DATE,
    p_mes_ini  DATE,
    p_mes_fin  DATE
)
RETURNS TABLE (
    clave         TEXT,
    cuadrante     TEXT,
    categoria     TEXT,
    severidad     TEXT,
    orden         INTEGER,
    titulo        TEXT,
    detalle       TEXT,
    metrica       TEXT,
    impacto_clp   NUMERIC,
    href          TEXT,
    activo_id     UUID,
    enex_faena_id UUID,
    tiene_plan    BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
WITH
-- ── Equipos detenidos ──────────────────────────────────────────────────────
det AS (
    SELECT d.*,
           lower(d.operacion) AS cuad
      FROM fn_panel_equipos_detenidos(p_mes_ini, p_mes_fin, NULL, 40, p_semana) d
),
eq AS (
    SELECT ('eq:' || d.activo_id)::TEXT AS clave,
           CASE WHEN d.cuad IN ('coquimbo','calama') THEN d.cuad ELSE 'global' END AS cuadrante,
           'equipo'::TEXT AS categoria,
           CASE WHEN d.dias_consecutivos >= 10                     THEN 'critica'
                WHEN d.dias_consecutivos >= 5                      THEN 'alta'
                WHEN COALESCE(d.pct_detenido, 0) >= 30             THEN 'alta'
                ELSE 'media' END AS severidad,
           (d.codigo || COALESCE(' · ' || d.patente, ''))::TEXT AS titulo,
           (CASE WHEN d.dias_consecutivos > 0
                 THEN 'Detenido ' || d.dias_consecutivos || ' días de corrido'
                 ELSE d.dias_detenido || ' de ' || d.dias_obs || ' días del mes detenido' END
            || ' · ' ||
            CASE WHEN d.ot_folio IS NOT NULL
                 THEN 'OT ' || d.ot_folio || ' (' || d.ot_estado || ')'
                 ELSE 'SIN OT ABIERTA' END
            || CASE WHEN d.plan_accion IS NULL OR btrim(d.plan_accion) = ''
                    THEN ' · sin plan de acción' ELSE '' END)::TEXT AS detalle,
           (COALESCE(NULLIF(d.dias_consecutivos, 0), d.dias_detenido) || ' d')::TEXT AS metrica,
           NULL::NUMERIC AS impacto_clp,
           ('/dashboard/activos/' || d.activo_id)::TEXT AS href,
           d.activo_id,
           NULL::UUID AS enex_faena_id,
           (d.plan_accion IS NOT NULL AND btrim(d.plan_accion) <> '') AS tiene_plan
      FROM det d
     -- Debajo de estos umbrales es ruido operacional, no materia de gerencia.
     WHERE d.dias_consecutivos >= 3 OR COALESCE(d.pct_detenido, 0) >= 15
),

-- ── Contrato ENEX ──────────────────────────────────────────────────────────
enex AS (
    SELECT * FROM fn_panel_calama_enex(
        EXTRACT(YEAR  FROM p_semana)::INTEGER,
        EXTRACT(MONTH FROM p_semana)::INTEGER,
        p_semana)
),
enex_sin_plan AS (
    SELECT ('enex_plan:' || e.faena_id)::TEXT,
           'calama'::TEXT,
           'contrato'::TEXT,
           'critica'::TEXT,
           (e.nombre || ' sin plan cargado')::TEXT,
           ('No tiene instalaciones ni programación cargadas, así que no hay '
            || 'avance que medir. Es ' || COALESCE(round(e.pct_facturacion, 1)::TEXT, '—')
            || '% de la facturación del contrato sin control.')::TEXT,
           'SIN PLAN'::TEXT,
           e.facturacion_mensual,
           '/dashboard/enex/plan'::TEXT,
           NULL::UUID,
           e.faena_id,
           (e.plan_accion IS NOT NULL AND btrim(e.plan_accion) <> '')
      FROM enex e
     WHERE e.sin_plan
),
enex_avance AS (
    SELECT ('enex_avance:' || e.faena_id)::TEXT,
           'calama'::TEXT,
           'contrato'::TEXT,
           CASE WHEN COALESCE(e.cumplimiento_pct, 0) < 50 THEN 'alta' ELSE 'media' END::TEXT,
           (e.nombre || ' al ' || COALESCE(round(e.cumplimiento_pct, 0)::TEXT, '0') || '% del plan')::TEXT,
           (e.ejecutados || ' de ' || e.programados || ' servicios ejecutados en el mes'
            || COALESCE(' · última ejecución ' || to_char(e.ultima_ejecucion, 'DD-MM'), ' · sin ejecuciones'))::TEXT,
           (COALESCE(round(e.cumplimiento_pct, 0)::TEXT, '0') || '%')::TEXT,
           e.facturacion_mensual,
           '/dashboard/enex'::TEXT,
           NULL::UUID,
           e.faena_id,
           (e.plan_accion IS NOT NULL AND btrim(e.plan_accion) <> '')
      FROM enex e
     WHERE NOT e.sin_plan
       AND e.programados > 0
       AND COALESCE(e.cumplimiento_pct, 0) < 80
),
enex_firmas AS (
    SELECT ('enex_firma:' || e.faena_id)::TEXT,
           'calama'::TEXT,
           'contrato'::TEXT,
           CASE WHEN e.requerimientos_sin_firmar >= 10 THEN 'alta' ELSE 'media' END::TEXT,
           (e.requerimientos_sin_firmar || ' requerimientos sin firma — ' || e.nombre)::TEXT,
           ('Trabajo ejecutado que el mandante todavía no firma. Sin firma no se '
            || 'factura ni se defiende en la revisión del contrato.')::TEXT,
           (e.requerimientos_sin_firmar || ' sin firmar')::TEXT,
           NULL::NUMERIC,
           '/dashboard/enex/informes'::TEXT,
           NULL::UUID,
           e.faena_id,
           FALSE
      FROM enex e
     WHERE e.requerimientos_sin_firmar > 0
),

-- ── Combustible: fluctuación por estanque ──────────────────────────────────
comb AS (
    SELECT fn_panel_combustible_coquimbo(p_mes_ini, p_mes_fin) AS j
),
comb_puntos AS (
    SELECT f.value ->> 'nombre'                       AS faena,
           p.value ->> 'punto'                        AS punto,
           (p.value ->> 'fluctuacion_pct')::NUMERIC   AS fl_pct,
           (p.value ->> 'fluctuacion_lt')::NUMERIC    AS fl_lt,
           (p.value ->> 'litros_despachados')::NUMERIC AS lt_desp
      FROM comb c,
           jsonb_array_elements(c.j -> 'faenas') f,
           jsonb_array_elements(f.value -> 'puntos') p
     WHERE p.value ->> 'fluctuacion_pct' IS NOT NULL
),
comb_exc AS (
    SELECT ('comb:' || cp.faena || ':' || cp.punto)::TEXT,
           'coquimbo'::TEXT,
           'combustible'::TEXT,
           CASE WHEN abs(cp.fl_pct) * 100 > 1.5 THEN 'critica' ELSE 'alta' END::TEXT,
           ('Fluctuación fuera de umbral — ' || cp.punto)::TEXT,
           (cp.faena || ' · ' || COALESCE(round(cp.fl_lt, 0)::TEXT || ' L', 'litros no declarados')
            || COALESCE(' sobre ' || round(cp.lt_desp, 0)::TEXT || ' L despachados', '')
            || ' · umbral de gestión 0,5%')::TEXT,
           (round(cp.fl_pct * 100, 2)::TEXT || '%')::TEXT,
           NULL::NUMERIC,
           '/dashboard/combustible/control'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM comb_puntos cp
     WHERE abs(cp.fl_pct) * 100 > 0.5
),
comb_sin_cierre AS (
    SELECT 'comb:sin_cierre'::TEXT,
           'coquimbo'::TEXT,
           'combustible'::TEXT,
           'alta'::TEXT,
           'Sin cierre de combustible cargado este mes'::TEXT,
           ('Ninguna faena tiene el cierre mensual cargado, así que no hay '
            || 'litros ni fluctuación que revisar. El control existe en planilla '
            || 'pero no llegó al panel.')::TEXT,
           '0 faenas'::TEXT,
           NULL::NUMERIC,
           '/dashboard/combustible/control'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM comb c
     WHERE (c.j ->> 'con_cierre_cargado')::INTEGER = 0
),

-- ── Taller: backlog y NC ───────────────────────────────────────────────────
tal AS (
    SELECT o.op,
           fn_panel_taller(p_mes_ini, p_mes_fin, o.op) AS j
      FROM (VALUES ('Coquimbo'), ('Calama')) o(op)
),
tal_backlog AS (
    SELECT ('taller_backlog:' || t.op)::TEXT,
           lower(t.op)::TEXT,
           'taller'::TEXT,
           CASE WHEN (t.j -> 'arrastre' ->> 'ot_dias_prom')::NUMERIC > 60 THEN 'critica'
                ELSE 'alta' END::TEXT,
           ((t.j -> 'arrastre' ->> 'ot_abiertas') || ' OT arrastradas de meses anteriores — ' || t.op)::TEXT,
           ('Antigüedad promedio ' || (t.j -> 'arrastre' ->> 'ot_dias_prom') || ' días · la más '
            || 'antigua desde ' || COALESCE(to_char((t.j -> 'arrastre' ->> 'ot_mas_antigua')::DATE, 'DD-MM-YYYY'), '—')
            || '. Es pasivo del proceso anterior: o se cierra o se anula, pero no '
            || 'puede seguir contándose como trabajo vivo.')::TEXT,
           ((t.j -> 'arrastre' ->> 'ot_dias_prom') || ' d')::TEXT,
           NULL::NUMERIC,
           '/dashboard/mantenimiento/plan-semanal-taller'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM tal t
     WHERE COALESCE((t.j -> 'arrastre' ->> 'ot_dias_prom')::NUMERIC, 0) > 30
       AND COALESCE((t.j -> 'arrastre' ->> 'ot_abiertas')::INTEGER, 0) > 0
),
tal_sin_resp AS (
    SELECT ('taller_sin_resp:' || t.op)::TEXT,
           lower(t.op)::TEXT,
           'taller'::TEXT,
           'media'::TEXT,
           ((t.j ->> 'ot_sin_responsable') || ' OT abiertas sin responsable — ' || t.op)::TEXT,
           ('Nadie tiene asignado el trabajo, así que nadie responde por su avance '
            || 'en la reunión.')::TEXT,
           ((t.j ->> 'ot_sin_responsable') || ' OT')::TEXT,
           NULL::NUMERIC,
           '/dashboard/mantenimiento/plan-semanal-taller'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM tal t
     WHERE COALESCE((t.j ->> 'ot_sin_responsable')::INTEGER, 0) > 0
),
nc_viejas AS (
    -- Agregada, no una fila por NC: 50 líneas de NC no son una agenda.
    SELECT ('nc_viejas:' || COALESCE(lower(a.operacion), 'sin_op'))::TEXT,
           CASE WHEN lower(a.operacion) IN ('coquimbo','calama')
                THEN lower(a.operacion) ELSE 'global' END::TEXT,
           'taller'::TEXT,
           'alta'::TEXT,
           (count(*) || ' no conformidades de severidad alta sin resolver'
            || COALESCE(' — ' || a.operacion, ''))::TEXT,
           ('Abiertas hace más de 15 días · la más antigua del '
            || to_char(min(nc.created_at)::DATE, 'DD-MM-YYYY')
            || '. Una NC alta que envejece es un riesgo aceptado sin decidirlo.')::TEXT,
           (count(*) || ' NC')::TEXT,
           NULL::NUMERIC,
           '/dashboard/mantenimiento/no-conformidades'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM no_conformidades nc
      LEFT JOIN activos a ON a.id = nc.activo_id
     WHERE NOT nc.resuelto
       AND nc.severidad::TEXT IN ('critica', 'alta')
       AND nc.created_at < NOW() - INTERVAL '15 days'
     GROUP BY a.operacion
    HAVING count(*) > 0
),

-- ── Calidad del dato ───────────────────────────────────────────────────────
cal AS (SELECT fn_panel_calidad_dato(p_mes_ini, p_mes_fin) AS j),
cal_exc AS (
    SELECT 'dato:rezago'::TEXT,
           'global'::TEXT,
           'dato'::TEXT,
           CASE WHEN (c.j ->> 'dias_rezago')::INTEGER > 5 THEN 'critica' ELSE 'alta' END::TEXT,
           ('El estado diario de flota lleva ' || (c.j ->> 'dias_rezago') || ' días sin cargar')::TEXT,
           ('Último día cargado: ' || COALESCE(c.j ->> 'ultimo_dia', '—')
            || ' · cobertura del mes ' || COALESCE(c.j ->> 'cobertura_pct', '—') || '%. '
            || 'Mientras no se cargue, la disponibilidad del panel está calculada '
            || 'sobre menos días y sale mejor de lo que es.')::TEXT,
           ((c.j ->> 'dias_rezago') || ' d')::TEXT,
           NULL::NUMERIC,
           '/dashboard/flota/sugerencias'::TEXT,
           NULL::UUID,
           NULL::UUID,
           FALSE
      FROM cal c
     WHERE (c.j ->> 'dias_rezago')::INTEGER > 2
),

todo AS (
    SELECT * FROM eq
    UNION ALL SELECT * FROM enex_sin_plan
    UNION ALL SELECT * FROM enex_avance
    UNION ALL SELECT * FROM enex_firmas
    UNION ALL SELECT * FROM comb_exc
    UNION ALL SELECT * FROM comb_sin_cierre
    UNION ALL SELECT * FROM tal_backlog
    UNION ALL SELECT * FROM tal_sin_resp
    UNION ALL SELECT * FROM nc_viejas
    UNION ALL SELECT * FROM cal_exc
)
SELECT t.clave, t.cuadrante, t.categoria, t.severidad,
       (CASE t.severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 ELSE 3 END)::INTEGER,
       t.titulo, t.detalle, t.metrica, t.impacto_clp, t.href,
       t.activo_id, t.enex_faena_id, t.tiene_plan
  FROM todo t
 ORDER BY (CASE t.severidad WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 ELSE 3 END),
          -- Dentro de la misma severidad manda la plata, y después lo que no
          -- tiene plan escrito: eso es exactamente lo que hay que decidir hoy.
          t.impacto_clp DESC NULLS LAST,
          t.tiene_plan ASC,
          t.titulo;
$$;

GRANT EXECUTE ON FUNCTION fn_panel_excepciones(DATE, DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_excepciones(DATE, DATE, DATE) IS
    'Todo lo fuera de norma en una sola lista ordenada por severidad e impacto. MIG305.';


-- ############################################################################
-- 4. RESUMEN EJECUTIVO CON PERÍODO ANTERIOR
-- ----------------------------------------------------------------------------
-- Los KPI del negocio completo, cada uno con su valor del mismo tramo del mes
-- anterior. La comparación es a igual cantidad de días transcurridos: comparar
-- 18 días de agosto contra 31 de julio haría ver una caída donde sólo falta
-- que pase el mes.
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_resumen(DATE, DATE, DATE);
CREATE FUNCTION fn_panel_resumen(
    p_semana  DATE,
    p_mes_ini DATE,
    p_mes_fin DATE
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_dias      INTEGER := p_mes_fin - p_mes_ini;   -- tramo transcurrido
    v_ant_ini   DATE;
    v_ant_fin   DATE;
    v_mes_ant   DATE;
    v_tal_coq   JSONB;
    v_tal_cal   JSONB;
    v_tal_coq_a JSONB;
    v_tal_cal_a JSONB;
    v_comb      JSONB;
    v_comb_ant  JSONB;
    v_disp      JSONB;
    v_disp_ant  NUMERIC;
    v_enex      JSONB;
    v_enex_ant  NUMERIC;
    v_comp      JSONB;
BEGIN
    v_mes_ant := (p_mes_ini - INTERVAL '1 month')::DATE;
    v_ant_ini := v_mes_ant;
    -- Mismo número de días, sin desbordar al mes siguiente.
    v_ant_fin := LEAST(v_mes_ant + v_dias, p_mes_ini - 1);

    v_tal_coq   := fn_panel_taller(p_mes_ini, p_mes_fin, 'Coquimbo');
    v_tal_cal   := fn_panel_taller(p_mes_ini, p_mes_fin, 'Calama');
    v_tal_coq_a := fn_panel_taller(v_ant_ini, v_ant_fin, 'Coquimbo');
    v_tal_cal_a := fn_panel_taller(v_ant_ini, v_ant_fin, 'Calama');
    v_comb      := fn_panel_combustible_coquimbo(p_mes_ini, p_mes_fin);
    v_comb_ant  := fn_panel_combustible_coquimbo(v_ant_ini, v_ant_fin);

    -- Cada helper se recorre UNA vez y se agrega aquí. La versión ingenua
    -- llamaba a fn_panel_disponibilidad tres veces y a fn_panel_calama_enex
    -- cuatro sólo para armar la portada; en el tier actual eso se nota.
    SELECT jsonb_build_object(
               'actual',    ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1),
               'equipos',   count(*),
               'bajo_meta', count(*) FILTER (WHERE disponibilidad_pct < 90))
      INTO v_disp
      FROM fn_panel_disponibilidad(p_mes_ini, p_mes_fin, NULL);

    SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
      INTO v_disp_ant
      FROM fn_panel_disponibilidad(v_ant_ini, v_ant_fin, NULL);

    SELECT jsonb_build_object(
               'actual',   ROUND(100.0 * SUM(ejecutados) / NULLIF(SUM(programados), 0), 1),
               'faenas',   count(*),
               'sin_plan', count(*) FILTER (WHERE sin_plan),
               'facturacion_sin_control',
                   COALESCE(SUM(facturacion_mensual) FILTER (WHERE sin_plan), 0))
      INTO v_enex
      FROM fn_panel_calama_enex(EXTRACT(YEAR  FROM p_semana)::INTEGER,
                                EXTRACT(MONTH FROM p_semana)::INTEGER, p_semana);

    SELECT ROUND(100.0 * SUM(ejecutados) / NULLIF(SUM(programados), 0), 1)
      INTO v_enex_ant
      FROM fn_panel_calama_enex(EXTRACT(YEAR  FROM v_mes_ant)::INTEGER,
                                EXTRACT(MONTH FROM v_mes_ant)::INTEGER, NULL);

    SELECT jsonb_build_object(
               'pendientes', count(*) FILTER (WHERE compromiso_estado = 'pendiente'),
               'vencidos',   count(*) FILTER (WHERE vencido),
               'cumplidos',  count(*) FILTER (WHERE compromiso_estado = 'cumplido'))
      INTO v_comp
      FROM fn_panel_compromisos(p_semana);

    RETURN jsonb_build_object(
        'periodo',          jsonb_build_object('desde', p_mes_ini, 'hasta', p_mes_fin),
        'periodo_anterior', jsonb_build_object('desde', v_ant_ini, 'hasta', v_ant_fin),
        'dias_comparados',  v_dias + 1,

        -- Disponibilidad de TODA la flota, no de un cuadrante: es el número que
        -- el Gerente General pregunta primero.
        'disponibilidad', v_disp
                          || jsonb_build_object('anterior', v_disp_ant, 'meta', 90),

        -- Flujo de taller: lo que importa no es cuántas OT hay, sino si se
        -- cierran más de las que se abren.
        'taller', jsonb_build_object(
            'creadas',          (v_tal_coq -> 'periodo' ->> 'ot_creadas')::INTEGER
                              + (v_tal_cal -> 'periodo' ->> 'ot_creadas')::INTEGER,
            'cerradas',         (v_tal_coq -> 'periodo' ->> 'ot_cerradas')::INTEGER
                              + (v_tal_cal -> 'periodo' ->> 'ot_cerradas')::INTEGER,
            'creadas_ant',      (v_tal_coq_a -> 'periodo' ->> 'ot_creadas')::INTEGER
                              + (v_tal_cal_a -> 'periodo' ->> 'ot_creadas')::INTEGER,
            'cerradas_ant',     (v_tal_coq_a -> 'periodo' ->> 'ot_cerradas')::INTEGER
                              + (v_tal_cal_a -> 'periodo' ->> 'ot_cerradas')::INTEGER,
            'abiertas_total',   (v_tal_coq ->> 'ot_abiertas')::INTEGER
                              + (v_tal_cal ->> 'ot_abiertas')::INTEGER,
            'arrastre',         (v_tal_coq -> 'arrastre' ->> 'ot_abiertas')::INTEGER
                              + (v_tal_cal -> 'arrastre' ->> 'ot_abiertas')::INTEGER,
            'sin_responsable',  (v_tal_coq ->> 'ot_sin_responsable')::INTEGER
                              + (v_tal_cal ->> 'ot_sin_responsable')::INTEGER
        ),

        'nc', jsonb_build_object(
            'creadas',      (v_tal_coq -> 'periodo' ->> 'nc_creadas')::INTEGER
                          + (v_tal_cal -> 'periodo' ->> 'nc_creadas')::INTEGER,
            'creadas_ant',  (v_tal_coq_a -> 'periodo' ->> 'nc_creadas')::INTEGER
                          + (v_tal_cal_a -> 'periodo' ->> 'nc_creadas')::INTEGER,
            'abiertas',     (v_tal_coq ->> 'nc_abiertas')::INTEGER
                          + (v_tal_cal ->> 'nc_abiertas')::INTEGER,
            'criticas',     (v_tal_coq ->> 'nc_criticas_abiertas')::INTEGER
                          + (v_tal_cal ->> 'nc_criticas_abiertas')::INTEGER
        ),

        -- Contrato ENEX: cumplimiento ponderado por servicios, no promedio de
        -- porcentajes —una faena con 2 servicios no pesa igual que una con 40—.
        'enex', v_enex || jsonb_build_object(
            'anterior', v_enex_ant,
            'facturacion_total',
                (SELECT SUM(facturacion_mensual_clp) FROM enex_faenas WHERE activo)
        ),

        'combustible', jsonb_build_object(
            'litros',        (v_comb ->> 'litros_total_periodo')::NUMERIC,
            'litros_ant',    (v_comb_ant ->> 'litros_total_periodo')::NUMERIC,
            'puntos_fuera',  (v_comb ->> 'puntos_fuera_umbral')::INTEGER,
            'con_cierre',    (v_comb ->> 'con_cierre_cargado')::INTEGER,
            'fluctuacion_peor_pct', (
                SELECT MAX(abs((p.value ->> 'fluctuacion_pct')::NUMERIC))
                  FROM jsonb_array_elements(v_comb -> 'faenas') f,
                       jsonb_array_elements(f.value -> 'puntos') p
                 WHERE p.value ->> 'fluctuacion_pct' IS NOT NULL)
        ),

        'compromisos', v_comp
    );
END $$;

GRANT EXECUTE ON FUNCTION fn_panel_resumen(DATE, DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_resumen(DATE, DATE, DATE) IS
    'KPI del negocio completo con su valor a igual tramo del mes anterior. MIG305.';


-- ############################################################################
-- 5. fn_panel_gerencia — se le cuelgan los tres bloques nuevos
-- ----------------------------------------------------------------------------
-- Mismo contrato de MIG295-297 (nada se quita), más `resumen`, `excepciones`
-- y `compromisos`. Sigue siendo UNA sola llamada: el panel se abre en reunión
-- y no puede quedar pestañeando mientras cargan seis consultas.
-- ############################################################################

CREATE OR REPLACE FUNCTION fn_panel_gerencia(p_semana DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_semana     DATE;
    v_sem_fin    DATE;
    v_mes_ini    DATE;
    v_mes_fin    DATE;
    v_hoy        DATE := CURRENT_DATE;
    v_resultado  JSONB;
BEGIN
    IF NOT fn_panel_gerencia_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado para ver el Panel de Gerencia.'
            USING ERRCODE = '42501';
    END IF;

    v_semana  := date_trunc('week', COALESCE(p_semana, v_hoy))::DATE;
    v_sem_fin := v_semana + 6;
    v_mes_ini := date_trunc('month', v_semana)::DATE;
    -- El mes se corta en el día de hoy: no tiene sentido contar como "detenidos"
    -- días que todavía no ocurren.
    v_mes_fin := LEAST((v_mes_ini + INTERVAL '1 month - 1 day')::DATE, v_hoy);

    SELECT jsonb_build_object(
        'semana',        jsonb_build_object(
            'inicio', v_semana, 'fin', v_sem_fin,
            'mes_inicio', v_mes_ini, 'mes_fin', v_mes_fin,
            'generado_at', NOW()
        ),

        -- Encabezado de confianza: se lee ANTES que cualquier número, porque
        -- define si los demás números sirven para decidir.
        'calidad_dato',  fn_panel_calidad_dato(v_mes_ini, v_mes_fin),

        -- ── PORTADA (MIG305) ────────────────────────────────────────────────
        'resumen',       fn_panel_resumen(v_semana, v_mes_ini, v_mes_fin),
        'excepciones',   (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.orden,
                                                    x.impacto_clp DESC NULLS LAST,
                                                    x.titulo), '[]'::JSONB)
                            FROM fn_panel_excepciones(v_semana, v_mes_ini, v_mes_fin) x),
        'compromisos',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                            FROM fn_panel_compromisos(v_semana) x),

        -- ── CUADRANTE COQUIMBO ──────────────────────────────────────────────
        'coquimbo', jsonb_build_object(
            'taller',       fn_panel_taller(v_mes_ini, v_mes_fin, 'Coquimbo'),
            'combustible',  fn_panel_combustible_coquimbo(v_mes_ini, v_mes_fin),
            'disponibilidad', jsonb_build_object(
                'equipos',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'promedio',  (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'bajo_90',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')
                               WHERE disponibilidad_pct < 90),
                'detalle',   (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::JSONB)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo') d)
            ),
            'detenidos',    (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                               FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Coquimbo', 10, v_semana) x),
            'comentario',   (SELECT to_jsonb(c) FROM panel_comentarios c
                              WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'coquimbo'
                                AND c.semana = v_semana)
        ),

        -- ── CUADRANTE CALAMA ────────────────────────────────────────────────
        'calama', jsonb_build_object(
            'faenas',      (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) x),
            'facturacion_total', (SELECT SUM(facturacion_mensual_clp) FROM enex_faenas WHERE activo),
            'faenas_sin_plan',   (SELECT count(*) FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) WHERE sin_plan),
            'taller',      fn_panel_taller(v_mes_ini, v_mes_fin, 'Calama'),
            'disponibilidad', jsonb_build_object(
                'equipos',  (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')),
                'promedio', (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                               FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')),
                'bajo_90',  (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')
                              WHERE disponibilidad_pct < 90),
                'detalle',  (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::JSONB)
                               FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama') d)
            ),
            'detenidos',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Calama', 5, v_semana) x),
            'comentario',  (SELECT to_jsonb(c) FROM panel_comentarios c
                             WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'calama'
                               AND c.semana = v_semana)
        ),

        -- ── COMENTARIO DE LA SEMANA ─────────────────────────────────────────
        'comentario_semana', (SELECT to_jsonb(c) FROM panel_comentarios c
                               WHERE c.ambito = 'semana' AND c.semana = v_semana)
    ) INTO v_resultado;

    RETURN v_resultado;
END $$;

GRANT EXECUTE ON FUNCTION fn_panel_gerencia(DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_gerencia(DATE) IS
    'Panel de Gerencia completo en una llamada: portada (resumen + excepciones + '
    'compromisos) y detalle por cuadrante. MIG295, ampliado en MIG305.';
