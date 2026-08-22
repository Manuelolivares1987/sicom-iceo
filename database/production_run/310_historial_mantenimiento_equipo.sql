-- ============================================================================
-- MIG310 · El equipo tiene historial de mantenimiento, no una lista de folios
-- ----------------------------------------------------------------------------
-- QUÉ FALTABA
--   La ficha del equipo mostraba las OT como folio + tipo + estado + costo. Lo
--   único que nunca aparecía era LO QUE SE HIZO. `observaciones` es la
--   descripción del problema al crear la OT, no el trabajo ejecutado; y al
--   finalizar en el taller no se consolidaba nada: las tareas quedaban sueltas
--   en checklist_ot, los repuestos en movimientos_inventario, las horas en
--   taller_ot_ejecuciones. Nadie podía responder "¿qué le hicieron a este
--   camión en marzo?" sin abrir cuatro pantallas.
--
-- QUÉ HACE
--   a) Al finalizar una ejecución en el taller se guarda un RESUMEN del trabajo
--      hecho, junto con el kilometraje y el horómetro de ese momento. Es una
--      foto: si mañana alguien edita la pauta, el historial no cambia. Eso es
--      lo que lo hace historial y no un reporte.
--   b) Vista v_historial_mantenimiento_equipo: una fila por intervención, con
--      las OT del sistema Y las órdenes de servicio antiguas que se importaron
--      (229 OS de 2024-2026, 39 equipos). "Completo" significa que incluye lo
--      que pasó antes de que existiera el sistema.
--   c) fn_historial_mantenimiento_equipo(activo): trae todo el detalle
--      —tareas, repuestos, hallazgos, evidencias— en una sola consulta, para
--      que la ficha no dispare veinte.
--   d) Se rellena el resumen de las OT ya terminadas, para que el historial no
--      empiece vacío.
-- ============================================================================

BEGIN;

-- ── a) La foto del trabajo hecho ───────────────────────────────────────────
ALTER TABLE public.ordenes_trabajo
    ADD COLUMN IF NOT EXISTS trabajo_realizado   TEXT,
    ADD COLUMN IF NOT EXISTS km_al_cierre        NUMERIC,
    ADD COLUMN IF NOT EXISTS horas_al_cierre     NUMERIC;

COMMENT ON COLUMN public.ordenes_trabajo.trabajo_realizado IS
  'Resumen de lo ejecutado, congelado al cerrar la OT. No se recalcula: editar la pauta despues no puede reescribir la historia. MIG310.';
COMMENT ON COLUMN public.ordenes_trabajo.km_al_cierre IS
  'Kilometraje del equipo al momento de cerrar. Sin esto no se puede decir "cada cuantos km se le hizo". MIG310.';

-- Arma el resumen a partir de los hechos: tareas ejecutadas y repuestos.
CREATE OR REPLACE FUNCTION public.fn_ot_resumen_trabajo(p_ot_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_tareas   TEXT;
    v_no_ok    TEXT;
    v_repuesto TEXT;
    v_partes   TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT string_agg(c.descripcion, '; ' ORDER BY c.orden)
      INTO v_tareas
      FROM checklist_ot c
     WHERE c.ot_id = p_ot_id AND c.resultado = 'ok';

    SELECT string_agg(c.descripcion || COALESCE(' (' || NULLIF(c.observacion,'') || ')', ''),
                      '; ' ORDER BY c.orden)
      INTO v_no_ok
      FROM checklist_ot c
     WHERE c.ot_id = p_ot_id AND c.resultado = 'no_ok';

    SELECT string_agg(p.nombre || ' x' || trim(to_char(m.cantidad, 'FM999999.99')),
                      '; ' ORDER BY p.nombre)
      INTO v_repuesto
      FROM movimientos_inventario m
      JOIN productos p ON p.id = m.producto_id
     WHERE m.ot_id = p_ot_id AND m.tipo IN ('salida','merma');

    IF v_tareas   IS NOT NULL THEN v_partes := v_partes || ('Ejecutado: ' || v_tareas); END IF;
    IF v_no_ok    IS NOT NULL THEN v_partes := v_partes || ('Pendiente / no conforme: ' || v_no_ok); END IF;
    IF v_repuesto IS NOT NULL THEN v_partes := v_partes || ('Repuestos: ' || v_repuesto); END IF;

    RETURN NULLIF(array_to_string(v_partes, E'\n'), '');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_ot_resumen_trabajo(uuid) TO authenticated;

-- Congela el resumen + las lecturas del equipo en la OT.
CREATE OR REPLACE FUNCTION public.fn_ot_congelar_trabajo(p_ot_id uuid, p_observacion text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_resumen TEXT;
BEGIN
    v_resumen := public.fn_ot_resumen_trabajo(p_ot_id);

    -- La observación de cierre del técnico va primero: es lo que él quiso
    -- dejar dicho, y suele explicar lo que la pauta no cubre.
    IF NULLIF(trim(COALESCE(p_observacion,'')), '') IS NOT NULL THEN
        v_resumen := trim(p_observacion) || COALESCE(E'\n' || v_resumen, '');
    END IF;

    UPDATE ordenes_trabajo o
       SET trabajo_realizado = COALESCE(v_resumen, o.trabajo_realizado),
           km_al_cierre      = COALESCE(o.km_al_cierre,    a.kilometraje_actual),
           horas_al_cierre   = COALESCE(o.horas_al_cierre, a.horas_uso_actual),
           updated_at        = NOW()
      FROM activos a
     WHERE o.id = p_ot_id AND a.id = o.activo_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_ot_congelar_trabajo(uuid, text) TO authenticated;

-- ── b) Finalizar en el taller deja el registro ─────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_finalizar_ejecucion(
    p_ejecucion_id uuid,
    p_avance_final numeric DEFAULT 100,
    p_observacion text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_estado VARCHAR; v_last TIMESTAMPTZ; v_delta INT;
    v_started TIMESTAMPTZ; v_ot UUID; v_plan_ot UUID;
    v_t_efectivo INT; v_t_pausado INT; v_t_colacion INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT estado, last_event_at, started_at, ot_id, plan_semanal_ot_id,
           tiempo_efectivo_segundos, tiempo_pausado_segundos, tiempo_colacion_segundos
      INTO v_estado, v_last, v_started, v_ot, v_plan_ot,
           v_t_efectivo, v_t_pausado, v_t_colacion
      FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no existe'; END IF;
    IF v_estado IN ('finalizada','cancelada') THEN
        RAISE EXCEPTION 'Ejecucion ya esta %', v_estado;
    END IF;
    IF v_estado = 'en_ejecucion' THEN
        v_delta := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_last))::INT);
        v_t_efectivo := v_t_efectivo + v_delta;
    END IF;
    UPDATE taller_ot_ejecuciones
       SET estado = 'finalizada',
           finished_at = NOW(),
           tiempo_efectivo_segundos = v_t_efectivo,
           tiempo_total_segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_started))::INT),
           avance_final = p_avance_final,
           observacion_cierre = p_observacion,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;
    INSERT INTO taller_ot_ejecucion_eventos(ejecucion_id, ot_id, tipo, avance, comentario, created_by)
    VALUES (p_ejecucion_id, v_ot, 'finish', p_avance_final, p_observacion, v_user);
    IF v_plan_ot IS NOT NULL THEN
        UPDATE taller_plan_semanal_ots SET estado_plan = 'finalizada', updated_at = NOW()
         WHERE id = v_plan_ot;
    END IF;
    UPDATE ordenes_trabajo
       SET estado = CASE WHEN p_avance_final >= 100 THEN 'ejecutada_ok' ELSE 'ejecutada_con_observaciones' END,
           fecha_termino = NOW(),
           horas_hombre = COALESCE(horas_hombre, 0) + (v_t_efectivo::NUMERIC / 3600.0),
           updated_at = NOW()
     WHERE id = v_ot;

    -- [MIG310] Lo que se hizo queda escrito en la OT, con las lecturas del
    -- equipo de ese momento. Nunca puede tumbar el cierre del taller.
    BEGIN
        PERFORM public.fn_ot_congelar_trabajo(v_ot, p_observacion);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'No se pudo congelar el trabajo de la OT %: %', v_ot, SQLERRM;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'tiempo_efectivo_seg', v_t_efectivo,
        'tiempo_pausado_seg', v_t_pausado,
        'tiempo_colacion_seg', v_t_colacion,
        'avance_final', p_avance_final
    );
END;
$function$;

-- ── c) El historial, una fila por intervención ─────────────────────────────
CREATE OR REPLACE VIEW public.v_historial_mantenimiento_equipo AS
-- Las OT del sistema
SELECT
    o.activo_id,
    'ot'::text                                     AS origen,
    o.id                                           AS ref_id,
    o.folio::text                                  AS folio,
    o.tipo::text                                   AS tipo,
    o.estado::text                                 AS estado,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor,
             o.fecha_inicio, o.fecha_programada::timestamptz, o.created_at) AS fecha,
    o.fecha_inicio,
    o.fecha_termino,
    o.trabajo_realizado,
    NULLIF(o.observaciones, '')                    AS motivo,
    o.km_al_cierre,
    o.horas_al_cierre,
    o.horas_hombre,
    COALESCE(o.costo_mano_obra, 0) + COALESCE(o.costo_materiales, 0) AS costo,
    COALESCE(resp.nombre_completo, tec.nombre_completo) AS responsable,
    sup.nombre_completo                            AS supervisor,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id)                         AS tareas_total,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'ok')  AS tareas_ok,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'no_ok') AS tareas_no_ok,
    (SELECT count(*)::int FROM movimientos_inventario m
      WHERE m.ot_id = o.id AND m.tipo IN ('salida','merma'))                                AS repuestos_total,
    (SELECT count(*)::int FROM evidencias_ot e WHERE e.ot_id = o.id)                        AS evidencias_total,
    (SELECT count(*)::int FROM no_conformidades nc WHERE nc.ot_id = o.id)                   AS hallazgos_total
FROM ordenes_trabajo o
LEFT JOIN usuarios_perfil resp ON resp.id = o.responsable_id
LEFT JOIN usuarios_perfil tec  ON tec.id  = o.tecnico_id
LEFT JOIN usuarios_perfil sup  ON sup.id  = o.supervisor_cierre_id
WHERE o.activo_id IS NOT NULL

UNION ALL

-- Las órdenes de servicio anteriores al sistema. Sin esto el historial
-- empieza el día que arrancó SICOM y el equipo parece recién nacido.
SELECT
    h.activo_id,
    'os_legacy'::text,
    h.id,
    ('OS ' || COALESCE(h.os_cqbo, h.os_numero, left(h.id::text, 8)))::text,
    CASE WHEN h.flag_mant_prev THEN 'preventivo'
         WHEN h.flag_correctivo THEN 'correctivo'
         ELSE 'servicio' END,
    'cerrada'::text,
    h.fecha_recepcion::timestamptz,
    h.fecha_recepcion::timestamptz,
    h.fecha_entrega::timestamptz,
    NULLIF(concat_ws('. ',
        NULLIF(h.num_trabajos::text, '') || ' trabajo(s) registrados',
        CASE WHEN h.flag_neumaticos    THEN 'Neumáticos' END,
        CASE WHEN h.flag_rev_tec       THEN 'Revisión técnica' END,
        CASE WHEN h.flag_hab_estado    THEN 'Habilitación' END,
        CASE WHEN h.flag_serv_externo  THEN 'Servicio externo' END,
        NULLIF('Cumplimiento ' || h.cumplimiento_pct::text || '%', 'Cumplimiento %')
    ), ''),
    NULLIF(h.faena::text, ''),
    h.kilometraje::numeric,
    h.horometro::numeric,
    h.horas_mo::numeric,
    NULL::numeric,
    h.responsable,
    NULL::text,
    COALESCE(h.num_trabajos, 0)::int,
    COALESCE(h.num_trabajos, 0)::int,
    0, 0, 0, 0
FROM historial_os_legacy h
WHERE h.activo_id IS NOT NULL;

GRANT SELECT ON public.v_historial_mantenimiento_equipo TO authenticated;

COMMENT ON VIEW public.v_historial_mantenimiento_equipo IS
  'Historial de mantencion por equipo: OT del sistema + OS importadas de antes. Una fila por intervencion. MIG310.';

-- ── d) El detalle completo, en una sola consulta ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_historial_mantenimiento_equipo(
    p_activo_id uuid,
    p_limite    integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.fecha DESC NULLS LAST), '[]'::jsonb)
    FROM (
        SELECT h.*,
               -- Las tareas, tal como quedaron marcadas por quien las hizo.
               CASE WHEN h.origen = 'ot' THEN COALESCE((
                   SELECT jsonb_agg(jsonb_build_object(
                            'descripcion', c.descripcion,
                            'seccion',     c.seccion,
                            'resultado',   c.resultado,
                            'observacion', NULLIF(c.observacion,''),
                            'foto_url',    c.foto_url
                          ) ORDER BY c.orden)
                     FROM checklist_ot c WHERE c.ot_id = h.ref_id
               ), '[]'::jsonb) ELSE '[]'::jsonb END AS tareas,
               -- Los repuestos que salieron de bodega contra esta OT.
               CASE WHEN h.origen = 'ot' THEN COALESCE((
                   SELECT jsonb_agg(jsonb_build_object(
                            'producto',  p.nombre,
                            'cantidad',  m.cantidad,
                            'costo',     m.costo_total
                          ) ORDER BY p.nombre)
                     FROM movimientos_inventario m
                     JOIN productos p ON p.id = m.producto_id
                    WHERE m.ot_id = h.ref_id AND m.tipo IN ('salida','merma')
               ), '[]'::jsonb) ELSE '[]'::jsonb END AS repuestos,
               -- Lo que se encontró y no se resolvió ahí mismo.
               CASE WHEN h.origen = 'ot' THEN COALESCE((
                   SELECT jsonb_agg(jsonb_build_object(
                            'descripcion', nc.descripcion,
                            'severidad',   nc.severidad,
                            'resuelto',    nc.resuelto,
                            'estado',      COALESCE(nc.estado_planificacion::text,
                                                    CASE WHEN nc.resuelto THEN 'resuelta' ELSE 'abierta' END)
                          ) ORDER BY nc.created_at)
                     FROM no_conformidades nc WHERE nc.ot_id = h.ref_id
               ), '[]'::jsonb) ELSE '[]'::jsonb END AS hallazgos
        FROM v_historial_mantenimiento_equipo h
        WHERE h.activo_id = p_activo_id
        ORDER BY h.fecha DESC NULLS LAST
        LIMIT p_limite
    ) x;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_historial_mantenimiento_equipo(uuid, integer) TO authenticated;

-- ── e) Que el historial no empiece vacío ───────────────────────────────────
-- Se rellena el resumen de las OT que ya se terminaron. Es reconstruido, no
-- capturado, pero sale de los mismos hechos y es mejor que una fila muda.
DO $backfill$
DECLARE r RECORD; v_n INT := 0;
BEGIN
    FOR r IN
        SELECT id FROM ordenes_trabajo
         WHERE trabajo_realizado IS NULL
           AND estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
    LOOP
        BEGIN
            PERFORM public.fn_ot_congelar_trabajo(r.id, NULL);
            v_n := v_n + 1;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    RAISE NOTICE 'MIG310: resumen reconstruido en % OT terminadas.', v_n;
END $backfill$;

COMMIT;
