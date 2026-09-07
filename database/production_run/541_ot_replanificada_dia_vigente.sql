-- ============================================================================
-- MIG541 · La OT replanificada aparece en su día vigente, no en el original
-- ============================================================================
-- La OT-202609-00011 se planificó el jueves 4, se replanificó para lunes 7 a
-- miércoles 9, y en /m/taller seguía agrupada bajo «Viernes 4 · 3 días de
-- atraso»: la lista del mecánico agrupa por fecha_programada, que es la fecha
-- ORIGINAL y no se mueve con el plan. El mecánico abre la app para ver qué le
-- toca HOY, y lo de hoy estaba enterrado bajo diez grupos de atrasos.
--
-- La vista gana `fecha_grupo`: la próxima jornada vigente del plan (>= hoy);
-- si todas pasaron, la última; si no está en el plan, fecha_programada.
-- El frontend agrupa por esa columna.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_def TEXT;
BEGIN
    v_def := pg_get_viewdef('v_taller_mecanico_ots'::regclass, true);
    -- El def viene con «;» final: dentro del subquery es error de sintaxis.
    v_def := regexp_replace(v_def, ';\s*$', '');
    IF v_def NOT LIKE '%preparacion_ok_at IS NOT NULL%' THEN
        RAISE EXCEPTION 'FALLO: la vista no es la esperada';
    END IF;
    IF v_def LIKE '%fecha_grupo%' THEN
        RAISE NOTICE 'fecha_grupo ya existe: nada que hacer';
        RETURN;
    END IF;

    EXECUTE 'CREATE OR REPLACE VIEW v_taller_mecanico_ots AS '
         || 'SELECT sub.*, COALESCE( '
         || '  (SELECT min(d.fecha) FROM taller_plan_semanal_ots po '
         || '     JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id '
         || '    WHERE po.ot_id = sub.ot_id '
         || '      AND COALESCE(po.estado_plan, ''planificada'')::text <> ''cancelada'' '
         || '      AND d.fecha >= CURRENT_DATE), '
         || '  (SELECT max(d.fecha) FROM taller_plan_semanal_ots po '
         || '     JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id '
         || '    WHERE po.ot_id = sub.ot_id '
         || '      AND COALESCE(po.estado_plan, ''planificada'')::text <> ''cancelada''), '
         || '  sub.fecha_programada) AS fecha_grupo '
         || 'FROM (' || v_def || ') sub';
    RAISE NOTICE 'v_taller_mecanico_ots + fecha_grupo';
END
$mig$;

-- ── Verificación: la OT-00011 debe agrupar en su día vigente, no el 04-09 ───
DO $mig$
DECLARE v_fg DATE; v_fp DATE;
BEGIN
    SELECT fecha_grupo, fecha_programada INTO v_fg, v_fp
      FROM v_taller_mecanico_ots
     WHERE ot_id = 'c8986e71-afe1-456b-8617-cfbf7dd6eb88';
    IF v_fg IS NULL THEN
        RAISE NOTICE 'OT-00011 ya no está en la vista (¿cerrada?): se valida solo la columna';
    ELSIF v_fg <= v_fp THEN
        RAISE EXCEPTION 'FALLO: fecha_grupo=% no avanzó respecto de fecha_programada=%', v_fg, v_fp;
    ELSE
        RAISE NOTICE 'OK · OT-00011: fecha_programada=% → fecha_grupo=%', v_fp, v_fg;
    END IF;
END
$mig$;

COMMIT;
