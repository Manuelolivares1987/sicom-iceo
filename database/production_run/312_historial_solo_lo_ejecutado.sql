-- ============================================================================
-- MIG312 · El historial no puede contener el futuro
-- ----------------------------------------------------------------------------
-- La vista de MIG310 fechaba cada OT con
--   COALESCE(fecha_termino, fecha_cierre_supervisor, fecha_inicio, fecha_programada)
-- Para una OT abierta eso cae en fecha_programada, que puede ser mañana. El
-- FSLZ-67 aparecía con una intervención el 10-10-2026 — una preventiva que
-- todavía no ocurre. Un historial con trabajo que no se hizo no sirve para
-- responderle a un mandante.
--
-- El historial ahora incluye sólo lo que efectivamente pasó: OT ejecutadas,
-- cerradas, o que al menos empezaron. El trabajo pendiente ya se muestra
-- aparte, en "En curso", que es donde corresponde.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_historial_mantenimiento_equipo AS
SELECT
    o.activo_id,
    'ot'::text                                     AS origen,
    o.id                                           AS ref_id,
    o.folio::text                                  AS folio,
    o.tipo::text                                   AS tipo,
    o.estado::text                                 AS estado,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio) AS fecha,
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
    (SELECT count(*)::int FROM no_conformidades nc WHERE nc.ot_id = o.id)                   AS hallazgos_total,
    NULL::text                                     AS fuente
FROM ordenes_trabajo o
LEFT JOIN usuarios_perfil resp ON resp.id = o.responsable_id
LEFT JOIN usuarios_perfil tec  ON tec.id  = o.tecnico_id
LEFT JOIN usuarios_perfil sup  ON sup.id  = o.supervisor_cierre_id
WHERE o.activo_id IS NOT NULL
  -- Sólo lo que pasó. Una OT programada es trabajo pendiente, no historia.
  AND (o.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
       OR o.fecha_inicio IS NOT NULL)
  AND COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio) <= NOW()

UNION ALL

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
    COALESCE(h.detalle_trabajos, NULLIF(concat_ws('. ',
        NULLIF(h.num_trabajos::text, '') || ' trabajo(s) registrados',
        CASE WHEN h.flag_neumaticos    THEN 'Neumáticos' END,
        CASE WHEN h.flag_rev_tec       THEN 'Revisión técnica' END,
        CASE WHEN h.flag_hab_estado    THEN 'Habilitación' END,
        CASE WHEN h.flag_serv_externo  THEN 'Servicio externo' END,
        NULLIF('Cumplimiento ' || h.cumplimiento_pct::text || '%', 'Cumplimiento %')
    ), '')),
    COALESCE(NULLIF(h.observacion, ''), NULLIF(h.ubicacion::text, ''), NULLIF(h.faena::text, '')),
    h.kilometraje::numeric,
    h.horometro::numeric,
    h.horas_mo::numeric,
    NULL::numeric,
    h.responsable,
    NULL::text,
    COALESCE(h.num_trabajos, 0)::int,
    COALESCE(h.num_trabajos, 0)::int,
    0, 0, 0, 0,
    h.fuente
FROM historial_os_legacy h
WHERE h.activo_id IS NOT NULL
  AND h.fecha_recepcion <= CURRENT_DATE;

GRANT SELECT ON public.v_historial_mantenimiento_equipo TO authenticated;

COMMIT;
