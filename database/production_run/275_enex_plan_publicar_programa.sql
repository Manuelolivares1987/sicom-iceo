-- ============================================================================
-- SICOM-ICEO | 275 — Publicar el plan deja el trabajo listo para ejecutar
-- ============================================================================
-- El plan semanal dice "miércoles 13, Lomas 1, racks 1 y 2, ítems 5.1 a 5.8",
-- pero si esos puntos no tienen un servicio programado en el mes, el técnico
-- llega al teléfono y no tiene dónde entrar a marcar.
--
-- Publicar el plan ahora asegura la programación de mantención del período para
-- cada punto que el plan nombra explícitamente, con la fecha del plan. No toca
-- las que ya existen (no les pisa la fecha ni el trabajo hecho) y NO inventa
-- programaciones para las tareas que solo indican área: multiplicar puntos por
-- cuenta propia falsearía el cumplimiento del contrato.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_enex_plan_estado(p_plan_id UUID, p_estado TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_creadas INT := 0;
    v_sin_pto INT := 0;
    t         RECORD;
    v_prog    UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;
    IF p_estado NOT IN ('borrador','publicado','cerrado') THEN RAISE EXCEPTION 'Estado inválido'; END IF;

    UPDATE enex_planes SET estado = p_estado WHERE id = p_plan_id;

    IF p_estado = 'publicado' THEN
        -- Un servicio por punto y período, con la fecha más temprana del plan.
        FOR t IN
            SELECT instalacion_id, min(fecha) AS fecha
              FROM enex_plan_tareas
             WHERE plan_id = p_plan_id AND instalacion_id IS NOT NULL
             GROUP BY instalacion_id
        LOOP
            SELECT id INTO v_prog FROM enex_programaciones
             WHERE instalacion_id = t.instalacion_id
               AND tipo_servicio = 'mantencion'
               AND periodo_anio = EXTRACT(YEAR FROM t.fecha)::int
               AND periodo_mes  = EXTRACT(MONTH FROM t.fecha)::int
             LIMIT 1;

            IF v_prog IS NULL THEN
                INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes,
                                                 fecha_programada, observacion, creado_por)
                VALUES (t.instalacion_id, 'mantencion',
                        EXTRACT(YEAR FROM t.fecha)::int, EXTRACT(MONTH FROM t.fecha)::int,
                        t.fecha, 'Creada al publicar el plan semanal', auth.uid());
                v_creadas := v_creadas + 1;
            ELSE
                -- Solo se completa la fecha si el servicio no la tenía.
                UPDATE enex_programaciones SET fecha_programada = t.fecha
                 WHERE id = v_prog AND fecha_programada IS NULL;
            END IF;
        END LOOP;

        SELECT count(*) INTO v_sin_pto FROM enex_plan_tareas
         WHERE plan_id = p_plan_id AND instalacion_id IS NULL;
    END IF;

    RETURN jsonb_build_object('success', true, 'estado', p_estado,
                              'servicios_creados', v_creadas,
                              'tareas_sin_punto', v_sin_pto);
END $$;

GRANT EXECUTE ON FUNCTION rpc_enex_plan_estado(UUID, TEXT) TO authenticated;

SELECT 'MIG275 OK' AS resultado;
