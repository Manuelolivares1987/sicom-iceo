-- ============================================================================
-- SICOM-ICEO | 232 — Plan de calidad: copiar la semana anterior
-- ============================================================================
-- Las rutinas del encargado de calidad se repiten semana a semana (auditorías,
-- chequeos cruzados, revisión documental). Un clic copia el plan de la semana
-- anterior a la actual, manteniendo el día relativo (lunes→lunes, etc.).
-- Solo copia tareas no canceladas y las deja como pendientes. Idempotente:
-- no copia si el título ya existe ese día en la semana destino.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_calidad_copiar_semana(p_lunes_origen date, p_lunes_destino date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_n INT;
BEGIN
    PERFORM fn_calidad_plan_autorizado();

    INSERT INTO calidad_plan_tareas (fecha, titulo, descripcion, tipo, equipo_texto, responsable, horas_estimadas, created_by)
    SELECT p_lunes_destino + (t.fecha - p_lunes_origen),
           t.titulo, t.descripcion, t.tipo, t.equipo_texto, t.responsable, t.horas_estimadas, auth.uid()
      FROM calidad_plan_tareas t
     WHERE t.fecha >= p_lunes_origen AND t.fecha < p_lunes_origen + 7
       AND t.estado <> 'cancelada'
       AND NOT EXISTS (
           SELECT 1 FROM calidad_plan_tareas d
            WHERE d.fecha = p_lunes_destino + (t.fecha - p_lunes_origen)
              AND d.titulo = t.titulo);
    GET DIAGNOSTICS v_n = ROW_COUNT;

    RETURN jsonb_build_object('success', true, 'copiadas', v_n);
END $$;

GRANT EXECUTE ON FUNCTION rpc_calidad_copiar_semana(date, date) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG232 OK: copiar semana del plan de calidad'; END $$;
