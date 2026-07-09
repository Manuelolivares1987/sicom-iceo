-- ============================================================================
-- SICOM-ICEO | 211 — Consolidar las OTs de NC creadas ANTES de MIG209
-- ----------------------------------------------------------------------------
-- Reportado por Manuel (2026-07-09): en el Plan Semanal se debe agendar LA
-- PATENTE con sus NC, no cada NC. MIG209 ya agrupa hacia adelante (una OT por
-- equipo), pero las NC planificadas ANTES quedaron con una OT cada una (p.ej.
-- FJTJ-60: 4 OTs abiertas para 4 NC) y salen como 4 tarjetas.
--
-- Esta MIG consolida los datos históricos: por cada equipo con más de una OT
-- correctiva de NC abierta y SIN agendar, se conserva la más antigua, se
-- re-apuntan las NC (y recursos/tickets si hubiera) y las demás se cancelan.
-- IDEMPOTENTE (si no hay duplicados, no hace nada).
-- ============================================================================

DO $$
DECLARE
    v_act   RECORD;
    v_keep  UUID;
    v_folio TEXT;
    v_dups  UUID[];
    v_obs   TEXT;
    v_n     INT := 0;
BEGIN
    FOR v_act IN
        SELECT nc.activo_id
        FROM no_conformidades nc
        JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
        WHERE o.estado IN ('creada','asignada')
          AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots t WHERE t.ot_id = nc.plan_ot_id)
        GROUP BY nc.activo_id
        HAVING count(DISTINCT nc.plan_ot_id) > 1
    LOOP
        -- OT que se conserva: la más antigua del grupo
        SELECT o.id, o.folio INTO v_keep, v_folio
          FROM ordenes_trabajo o
         WHERE o.id IN (SELECT nc.plan_ot_id FROM no_conformidades nc
                         WHERE nc.activo_id = v_act.activo_id AND nc.plan_ot_id IS NOT NULL)
           AND o.estado IN ('creada','asignada')
           AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots t WHERE t.ot_id = o.id)
         ORDER BY o.created_at
         LIMIT 1;

        SELECT array_agg(DISTINCT o.id) INTO v_dups
          FROM ordenes_trabajo o
         WHERE o.id IN (SELECT nc.plan_ot_id FROM no_conformidades nc
                         WHERE nc.activo_id = v_act.activo_id AND nc.plan_ot_id IS NOT NULL)
           AND o.id <> v_keep
           AND o.estado IN ('creada','asignada')
           AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots t WHERE t.ot_id = o.id);

        IF v_dups IS NULL THEN CONTINUE; END IF;

        -- Juntar las observaciones (la descripción de cada NC) en la OT que queda
        SELECT string_agg(o.observaciones, E'\n') INTO v_obs
          FROM ordenes_trabajo o WHERE o.id = ANY(v_dups) AND o.observaciones IS NOT NULL;

        -- prioridad_enum está ordenado de más a menos urgente → la peor es LEAST/min
        UPDATE ordenes_trabajo
           SET observaciones = COALESCE(observaciones || E'\n', '') || COALESCE(v_obs, ''),
               prioridad = LEAST(prioridad, (SELECT min(o2.prioridad) FROM ordenes_trabajo o2 WHERE o2.id = ANY(v_dups))),
               updated_at = NOW()
         WHERE id = v_keep;

        -- Re-apuntar todo lo que colgaba de las OT duplicadas
        UPDATE no_conformidades SET plan_ot_id = v_keep, updated_at = NOW() WHERE plan_ot_id = ANY(v_dups);
        UPDATE ot_recursos_solicitados SET ot_id = v_keep WHERE ot_id = ANY(v_dups);
        UPDATE bodega_tickets SET ot_id = v_keep WHERE ot_id = ANY(v_dups);

        -- Cancelar las duplicadas
        UPDATE ordenes_trabajo
           SET estado = 'cancelada',
               observaciones = COALESCE(observaciones || E'\n', '') ||
                   '[Consolidada en ' || v_folio || ' — NC por equipo, MIG211]',
               updated_at = NOW()
         WHERE id = ANY(v_dups);

        v_n := v_n + array_length(v_dups, 1);
    END LOOP;

    RAISE NOTICE 'MIG211: % OTs duplicadas consolidadas', v_n;
END $$;

-- ── VALIDACION: ningún equipo debe quedar con más de una OT de NC abierta sin agendar
SELECT jsonb_build_object(
    'equipos_con_ots_duplicadas', (
        SELECT count(*) FROM (
            SELECT nc.activo_id
            FROM no_conformidades nc
            JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
            WHERE o.estado IN ('creada','asignada')
              AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots t WHERE t.ot_id = nc.plan_ot_id)
            GROUP BY nc.activo_id
            HAVING count(DISTINCT nc.plan_ot_id) > 1
        ) x),
    'tarjetas_por_agendar', (SELECT count(*) FROM v_nc_ot_por_agendar)
) AS resultado;
