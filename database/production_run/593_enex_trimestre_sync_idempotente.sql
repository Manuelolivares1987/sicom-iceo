-- ============================================================================
-- SICOM-ICEO | 593 — ENEX: sincronizar la pauta trimestral es idempotente
-- ============================================================================
-- Correr la sincronización dos veces volvía a procesar el mismo registro y lo
-- asignaba al siguiente lugar con ese código: el 3.2 de microfiltrado Lomas 2
-- del 23/09 terminó marcando también el 3.2 de los racks. Ahora un registro
-- de informe ya asociado no se reasigna, y se deshace esa marca.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_enex_trimestre_sincronizar(p_faena_id uuid, p_trimestre_inicio date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r RECORD; v_li uuid; v_est text; v_n int := 0; v_v int := 0; v_fin date := (p_trimestre_inicio + interval '3 months')::date;
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sin sesión'; END IF;
    FOR r IN
        SELECT e.id AS ejecucion_id, e.fecha_ejecucion, p.instalacion_id, i.area, it.codigo
          FROM enex_ejecuciones e
          JOIN enex_programaciones p ON p.id = e.programacion_id
          JOIN enex_instalaciones i  ON i.id = p.instalacion_id
          JOIN enex_ejecucion_items x ON x.ejecucion_id = e.id
          JOIN enex_pauta_items it   ON it.id = x.pauta_item_id
         WHERE i.faena_id = p_faena_id
           AND e.estado IN ('ejecutada','cumplida')
           AND e.fecha_ejecucion >= p_trimestre_inicio AND e.fecha_ejecucion < v_fin
           AND it.periodicidad = 'trimestral'
           AND (x.valor_medicion IS NOT NULL OR (x.resultado IS NOT NULL AND x.resultado <> 'na'))
         ORDER BY e.fecha_ejecucion
    LOOP
        -- [MIG592] Primero, lo que la planilla ya dio por ejecutado ese mismo día
        -- sin informe: se le vincula el informe (evidencia). Luego lo no
        -- ejecutado. Al final, cualquier ejecutada sin informe.
        v_li := NULL;
        -- [MIG593] Cada registro del informe cuenta una sola vez: si ya quedó
        -- asociado a una actividad de ese código, no se asigna a otro lugar.
        CONTINUE WHEN EXISTS (
            SELECT 1 FROM enex_trimestre_actividades a
              JOIN v_enex_pauta_lugar_items v ON v.lugar_item_id = a.lugar_item_id
             WHERE a.trimestre_inicio = p_trimestre_inicio AND a.ejecucion_id = r.ejecucion_id AND v.codigo = r.codigo);
        SELECT v.lugar_item_id, coalesce(a.estado, 'pendiente') INTO v_li, v_est
          FROM v_enex_pauta_lugar_items v
          LEFT JOIN enex_trimestre_actividades a ON a.lugar_item_id = v.lugar_item_id AND a.trimestre_inicio = p_trimestre_inicio
         WHERE v.faena_id = p_faena_id AND v.area = r.area AND v.codigo = r.codigo AND v.periodicidad = 'trimestral'
           AND (coalesce(a.estado, 'pendiente') NOT IN ('ejecutada','no_aplica')
                OR (a.estado = 'ejecutada' AND a.ejecucion_id IS NULL))
         ORDER BY (a.estado = 'ejecutada' AND a.fecha_ejecucion = r.fecha_ejecucion) DESC NULLS LAST,
                  (coalesce(a.estado, 'pendiente') <> 'ejecutada') DESC,
                  (r.instalacion_id = ANY(v.instalacion_ids)) DESC, v.lugar_orden, v.orden
         LIMIT 1;
        CONTINUE WHEN v_li IS NULL;
        IF v_est = 'ejecutada' THEN
            UPDATE enex_trimestre_actividades SET ejecucion_id = r.ejecucion_id, updated_at = now()
             WHERE lugar_item_id = v_li AND trimestre_inicio = p_trimestre_inicio;
            v_v := v_v + 1;
            CONTINUE;
        END IF;

        INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_ejecucion, ejecucion_id, origen, updated_at)
        VALUES (v_li, p_trimestre_inicio, 'ejecutada', r.fecha_ejecucion, r.ejecucion_id, 'informe', now())
        ON CONFLICT (lugar_item_id, trimestre_inicio) DO UPDATE
           SET estado = 'ejecutada', fecha_ejecucion = EXCLUDED.fecha_ejecucion,
               ejecucion_id = EXCLUDED.ejecucion_id, origen = 'informe', updated_at = now();
        UPDATE enex_plan_tareas SET estado = 'hecha', ejecucion_id = r.ejecucion_id
         WHERE id IN (SELECT unnest(plan_tarea_ids) FROM enex_trimestre_actividades
                       WHERE lugar_item_id = v_li AND trimestre_inicio = p_trimestre_inicio);
        v_n := v_n + 1;
    END LOOP;
    RETURN jsonb_build_object('success', true, 'marcadas', v_n, 'vinculadas', v_v);
END $function$;
GRANT EXECUTE ON FUNCTION public.rpc_enex_trimestre_sincronizar(uuid, date) TO authenticated;

-- Deshacer la marca duplicada (racks Lomas 2, 3.2, puesta por el informe del 23/09).
DELETE FROM enex_trimestre_actividades a
 USING v_enex_pauta_lugar_items v, enex_faenas f
 WHERE v.lugar_item_id = a.lugar_item_id AND f.id = v.faena_id AND f.codigo = 'LB_LUB'
   AND a.trimestre_inicio = '2026-07-01' AND a.origen = 'informe'
   AND v.area = 'Truck Shop Lomas 2' AND v.lugar LIKE 'Lubricanteras%' AND v.codigo = '3.2';

DO $$ BEGIN RAISE NOTICE 'MIG593 OK: sincronización idempotente'; END $$;
