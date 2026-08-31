-- ============================================================================
-- MIG463 · Las jornadas que el bono no veía
-- ============================================================================
--
-- DE DÓNDE SALE ESTO
-- Al responder si el bono se calcula desde la sesión compartida quedó a la vista
-- un hueco: de 241 jornadas del plan del taller, 51 tienen la cuadrilla escrita
-- sólo como TEXTO —de antes de MIG451, que empezó a guardarla por persona— y 10
-- no tienen a nadie. El bono lee personas, no texto: esas 61 jornadas no le
-- pagan a nadie, aunque el trabajo se haya hecho.
--
-- QUÉ HAY REALMENTE EN ESOS TEXTOS
-- Cuatro nombres distintos, tres personas:
--
--     «Yusedl»          15 jornadas, las 15 en OT abierta   → Yusdel Sarduy
--     «Sergio»          14 jornadas, las 14 en OT abierta   → Sergio Cortes
--     «Marco»           13 jornadas, las 13 en OT abierta   → Marco Díaz
--     «Sergio Cortes»    9 jornadas,  3 en OT abierta       → Sergio Cortes
--
-- «Yusedl» no calzaba con ningún técnico porque es «Yusdel» mal escrito. Trece
-- jornadas de Marco Díaz y quince de Yusdel Sarduy —gente que sí está y sí
-- tiene cargo— quedaban fuera del bono por dos letras cambiadas de lugar.
--
-- SERGIO CORTES YA NO ESTÁ EN EL TALLER
-- Existe en el catálogo, marcado inactivo, y no aparece en las liquidaciones de
-- agosto. Sus 23 jornadas se vinculan igual, porque el registro de lo que pasó
-- no se corrige borrándolo. Lo que cambia es otra cosa: hasta ahora, un técnico
-- sin cargo hacía que el motor dijera «falta el cargo» y eso BLOQUEA el cierre
-- del período. Trabar el pago de todo el taller por el cargo de alguien que se
-- fue no tiene sentido.
--
-- La regla nueva: quien está inactivo y nunca tuvo cargo no genera línea de
-- bono. Quien está ACTIVO y no tiene cargo sigue apareciendo como `falta`,
-- porque ahí la pregunta está abierta de verdad —es el caso de Felipe López—.
--
-- LO QUE NO SE TOCA
-- Las 10 jornadas sin nadie asignado quedan como están: no hay a quién
-- vincular. Se listan al final para que la jefatura decida si les asigna
-- cuadrilla antes del primer corte o si eran trabajo que nunca se hizo.
-- ============================================================================

BEGIN;

-- ── 1 · El texto viejo se convierte en personas ─────────────────────────────
--
-- Mapa explícito, escrito a mano. Nada de parecidos automáticos: en algo que
-- decide un pago, «se parece a» no es un criterio.
WITH mapa(texto, nombre_tecnico) AS (
    VALUES ('Yusedl',        'Yusdel Sarduy'),
           ('Sergio',        'Sergio Cortes'),
           ('Sergio Cortes', 'Sergio Cortes'),
           ('Marco',         'Marco Díaz')
),
pendientes AS (
    -- Sólo jornadas de OT que todavía no se ejecutan. Un trigger de MIG446
    -- congela la cuadrilla al ejecutar —«su cuadrilla es la base del bono y no
    -- se puede cambiar»—, y está bien que así sea: reescribir quién trabajó en
    -- algo que ya se cerró es justo lo que un sistema antifraude debe impedir,
    -- aunque quien lo intente sea una migración.
    SELECT po.id AS plan_ot_id, TRIM(u.raw) AS texto
      FROM taller_plan_semanal_ots po
      JOIN ordenes_trabajo ot ON ot.id = po.ot_id,
           LATERAL unnest(string_to_array(po.cuadrilla, ',')) AS u(raw)
     WHERE NOT EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
       AND NULLIF(TRIM(u.raw), '') IS NOT NULL
       AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada','cancelada')
)
INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol)
SELECT DISTINCT p.plan_ot_id, t.id, 'titular'
  FROM pendientes p
  JOIN mapa m ON m.texto = p.texto
  JOIN taller_tecnicos t ON t.nombre = m.nombre_tecnico
ON CONFLICT DO NOTHING;

-- ── 2 · El texto se re-deriva sólo donde todavía es plan ────────────────────
UPDATE taller_plan_semanal_ots po
   SET cuadrilla = (SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre)
                      FROM taller_ot_cuadrilla c
                      JOIN taller_tecnicos t ON t.id = c.tecnico_id
                     WHERE c.plan_ot_id = po.id),
       updated_at = NOW()
 WHERE EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
   AND EXISTS (SELECT 1 FROM ordenes_trabajo ot
                WHERE ot.id = po.ot_id
                  AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada','cancelada'));

-- ── 3 · Quien ya no está y nunca tuvo cargo no traba el cierre ──────────────
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

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    r RECORD;
    v_con INT; v_texto INT; v_nadie INT; v_ot_ok INT; v_ot INT;
BEGIN
    SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)),
           count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
                              AND NULLIF(TRIM(po.cuadrilla),'') IS NOT NULL),
           count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
                              AND NULLIF(TRIM(po.cuadrilla),'') IS NULL)
      INTO v_con, v_texto, v_nadie
      FROM taller_plan_semanal_ots po;

    RAISE NOTICE 'jornadas con cuadrilla por persona: %  (antes 180)', v_con;
    RAISE NOTICE 'jornadas con sólo texto, sin personas: %  (antes 51)', v_texto;
    RAISE NOTICE 'jornadas sin nadie asignado: %', v_nadie;

    IF v_texto > 0 THEN
        FOR r IN
            SELECT DISTINCT TRIM(u.raw) AS texto
              FROM taller_plan_semanal_ots po,
                   LATERAL unnest(string_to_array(po.cuadrilla, ',')) AS u(raw)
             WHERE NOT EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
               AND NULLIF(TRIM(u.raw), '') IS NOT NULL
        LOOP
            RAISE NOTICE '   sigue sin persona: «%»', r.texto;
        END LOOP;
    END IF;

    -- Lo que de verdad importa: cuántas OT abiertas le pagarían a alguien.
    SELECT count(DISTINCT ot.id) INTO v_ot
      FROM ordenes_trabajo ot
     WHERE ot.estado::text NOT IN ('cerrada','cancelada','ejecutada_ok','ejecutada_con_observaciones');
    SELECT count(DISTINCT ot.id) INTO v_ot_ok
      FROM ordenes_trabajo ot
      JOIN taller_plan_semanal_ots po ON po.ot_id = ot.id
      JOIN taller_ot_cuadrilla c ON c.plan_ot_id = po.id
     WHERE ot.estado::text NOT IN ('cerrada','cancelada','ejecutada_ok','ejecutada_con_observaciones');
    RAISE NOTICE 'OT abiertas que generarían bono al cerrarse: % de %  (antes 31 de 40)', v_ot_ok, v_ot;

    -- Y las que quedan huérfanas, con nombre y apellido, para que la jefatura decida.
    FOR r IN
        SELECT ot.folio, ot.estado::text est
          FROM ordenes_trabajo ot
         WHERE ot.estado::text NOT IN ('cerrada','cancelada','ejecutada_ok','ejecutada_con_observaciones')
           AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots po
                             JOIN taller_ot_cuadrilla c ON c.plan_ot_id = po.id
                            WHERE po.ot_id = ot.id)
         ORDER BY ot.folio
    LOOP
        RAISE NOTICE '   sin cuadrilla, no le pagaría a nadie: % (%)', r.folio, r.est;
    END LOOP;

    -- Sergio Cortes ya no traba el cierre.
    SELECT count(*) INTO v_con
      FROM fn_taller_bono_periodo_calc(DATE '2026-09-01', DATE '2026-09-30') b
      JOIN taller_tecnicos t ON t.id = b.tecnico_id
     WHERE NOT COALESCE(t.activo, TRUE);
    IF v_con > 0 THEN
        RAISE EXCEPTION 'FALLO: % líneas de bono siguen siendo de técnicos que ya no están', v_con;
    END IF;
    RAISE NOTICE 'ningún técnico inactivo sin cargo genera línea de bono';
END
$mig$;

COMMIT;
