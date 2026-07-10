-- ============================================================================
-- SICOM-ICEO | 221 — v_taller_plan_semanal_ots_full expone preparacion_ok_at
-- ============================================================================
-- Para que el Kanban del jefe muestre qué OTs planificadas AÚN NO están
-- liberadas a ejecución (hallazgo QA 2026-07-09: 8 OTs planificadas sin
-- liberar → los mecánicos ven /m/taller vacío) y ofrezca liberar ahí mismo.
-- Misma definición vigente (MIG203) + ot.preparacion_ok_at. IDEMPOTENTE.
-- ============================================================================

DROP VIEW IF EXISTS v_taller_plan_semanal_ots_full;
CREATE VIEW v_taller_plan_semanal_ots_full AS
 SELECT t.id AS plan_ot_id,
    t.plan_semanal_id,
    t.plan_dia_id,
    d.fecha AS dia_fecha,
    d.nombre_dia AS dia_nombre,
    d.orden AS dia_orden,
    ps.fecha_inicio_semana,
    ps.fecha_fin_semana,
    ps.estado AS plan_estado,
    t.ot_id,
    ot.folio AS ot_folio,
    ot.tipo AS ot_tipo,
    ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad,
    ot.preparacion_ok_at,                                   -- [MIG221]
    ot.fecha_programada AS ot_fecha_programada,
    ot.plan_mantenimiento_id,
    pm.nombre AS pm_nombre,
    pm.proxima_ejecucion_fecha AS pm_proxima_fecha,
    ot.activo_id,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.patente AS activo_patente,
    a.tipo AS activo_tipo,
    ot.faena_id,
    f.nombre AS faena_nombre,
    ot.contrato_id,
    c.codigo AS contrato_codigo,
    c.cliente AS contrato_cliente,
    COALESCE(t.responsable_id, ot.responsable_id) AS responsable_id,
    COALESCE(up.nombre_completo, up_ot.nombre_completo) AS responsable,
    t.cuadrilla,
    t.horas_planificadas,
    t.avance_objetivo_pct,
    t.secuencia_jornada,
    t.estado_plan AS jornada_estado,
    t.observaciones,
    t.categoria,
    (t.ot_id IS NULL) AS es_tarea_libre,
    COALESCE(t.titulo, ot.folio) AS titulo,
    t.descripcion AS tarea_descripcion,
    t.equipo_externo,
    COALESCE(t.operacion, a.operacion) AS operacion,
    t.tecnico_id,
    tt.nombre AS tecnico_nombre,
    tt.especialidad AS tecnico_especialidad,
    ( SELECT count(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false) AS checklist_total,
    ( SELECT count(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false
         AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente'::resultado_item_enum) AS checklist_completados,
    ( SELECT COALESCE(sum(v.tiempo_min), 0::numeric) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false) AS tiempo_estimado_total_min,
    ( SELECT e.id FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado::text = ANY (ARRAY['en_ejecucion','pausada'])
       LIMIT 1) AS ejecucion_activa_id,
    ( SELECT e.estado FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado::text = ANY (ARRAY['en_ejecucion','pausada'])
       LIMIT 1) AS ejecucion_activa_estado,
    ( SELECT e.avance_final FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado::text = 'finalizada'
       ORDER BY e.finished_at DESC LIMIT 1) AS ultima_ejecucion_avance,
    t.created_at,
    t.updated_at
   FROM taller_plan_semanal_ots t
     JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     JOIN taller_planes_semanales ps ON ps.id = t.plan_semanal_id
     LEFT JOIN ordenes_trabajo ot ON ot.id = t.ot_id
     LEFT JOIN planes_mantenimiento pm ON pm.id = ot.plan_mantenimiento_id
     LEFT JOIN activos a ON a.id = ot.activo_id
     LEFT JOIN faenas f ON f.id = ot.faena_id
     LEFT JOIN contratos c ON c.id = ot.contrato_id
     LEFT JOIN usuarios_perfil up ON up.id = t.responsable_id
     LEFT JOIN usuarios_perfil up_ot ON up_ot.id = ot.responsable_id
     LEFT JOIN taller_tecnicos tt ON tt.id = t.tecnico_id;

GRANT SELECT ON v_taller_plan_semanal_ots_full TO authenticated;

SELECT jsonb_build_object(
    'col_ok', (SELECT position('preparacion_ok_at' in pg_get_viewdef('v_taller_plan_semanal_ots_full'::regclass)) > 0)
) AS resultado;

NOTIFY pgrst, 'reload schema';
