-- ============================================================================
-- SICOM-ICEO | 193 — Operador de taller VE TODAS las OTs liberadas y toma
--                    las que traen su nombre (ajuste sobre MIG192)
-- ============================================================================
-- Pedido Manuel (2026-07-06): el operador NO debe quedar limitado a sus OTs
-- asignadas — necesita ver todo lo liberado a ejecución y elegir las que
-- aparecen con su nombre (la cuadrilla la escribe el jefe como texto libre y
-- no siempre calza 1:1 con la cuenta).
--
--   * v_taller_mecanico_ots: se elimina el filtro por operador_taller (todos
--     los roles ven todas las OTs liberadas) y se agrega la columna
--     `asignada_a_mi` (fn_taller_ot_asignada_al_usuario) para que la app
--     destaque/ordene primero las OTs con el nombre del operador.
--   * pol_cl_inst_item_operador_taller: el operador puede marcar el checklist
--     de cualquier OT liberada a ejecución (mismo universo que ve la vista),
--     no solo de las asignadas.
--
-- fn_taller_ot_asignada_al_usuario (MIG192) queda vigente como marcador.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_taller_ot_asignada_al_usuario') THEN
        RAISE EXCEPTION 'STOP — falta fn_taller_ot_asignada_al_usuario (MIG192).';
    END IF;
END $$;


-- ── 1. Vista: todas las OTs liberadas + marcador asignada_a_mi ───────────────
DROP VIEW IF EXISTS v_taller_mecanico_ots;
CREATE VIEW v_taller_mecanico_ots AS
SELECT
    ot.id                       AS ot_id,
    ot.folio                    AS ot_folio,
    ot.tipo                     AS ot_tipo,
    ot.estado                   AS ot_estado,
    ot.prioridad                AS ot_prioridad,
    ot.preparacion_ok_at,
    ot.fecha_programada,
    ot.activo_id,
    a.codigo                    AS activo_codigo,
    a.nombre                    AS activo_nombre,
    a.patente                   AS activo_patente,
    (SELECT string_agg(DISTINCT t.cuadrilla, ', ')
       FROM taller_plan_semanal_ots t
      WHERE t.ot_id = ot.id AND NULLIF(TRIM(t.cuadrilla),'') IS NOT NULL) AS cuadrilla,
    ot.responsable_id,
    up.nombre_completo          AS responsable,
    -- TRUE si la OT trae el nombre/cuenta del usuario autenticado (responsable
    -- OT/jornada, técnico vinculado o nombre en cuadrilla). La app la usa para
    -- destacar "mis OTs" — ya NO restringe visibilidad (MIG193).
    fn_taller_ot_asignada_al_usuario(ot.id) AS asignada_a_mi,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false)                       AS checklist_total,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false
         AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente')       AS checklist_completados,
    (SELECT COALESCE(SUM(v.tiempo_min),0) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = ot.id AND v.excluido = false)                       AS tiempo_estimado_total_min
FROM ordenes_trabajo ot
JOIN activos a               ON a.id = ot.activo_id
LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
WHERE ot.preparacion_ok_at IS NOT NULL
  AND ot.estado IN ('asignada','en_ejecucion','pausada')
ORDER BY
    CASE ot.estado WHEN 'en_ejecucion' THEN 1 WHEN 'pausada' THEN 2 ELSE 3 END,
    CASE ot.prioridad WHEN 'emergencia' THEN 1 WHEN 'urgente' THEN 2 WHEN 'alta' THEN 3
                      WHEN 'normal' THEN 4 ELSE 5 END,
    ot.fecha_programada NULLS LAST;

COMMENT ON VIEW v_taller_mecanico_ots IS
    'OTs liberadas a ejecucion (todas, para todos los roles). asignada_a_mi marca las del usuario autenticado para destacarlas en /m/taller (MIG193).';
GRANT SELECT ON v_taller_mecanico_ots TO authenticated;


-- ── 2. Checklist V03: el operador marca items de cualquier OT liberada ───────
DROP POLICY IF EXISTS pol_cl_inst_item_operador_taller ON checklist_v2_instance_item;
CREATE POLICY pol_cl_inst_item_operador_taller ON checklist_v2_instance_item
    FOR UPDATE TO authenticated
    USING (
        fn_user_rol() = 'operador_taller'
        AND EXISTS (SELECT 1
                      FROM checklist_v2_instance ci
                      JOIN ordenes_trabajo ot ON ot.id = ci.ot_id
                     WHERE ci.id = checklist_v2_instance_item.instance_id
                       AND ot.preparacion_ok_at IS NOT NULL
                       AND ot.estado IN ('asignada','en_ejecucion','pausada'))
    )
    WITH CHECK (
        fn_user_rol() = 'operador_taller'
        AND EXISTS (SELECT 1
                      FROM checklist_v2_instance ci
                      JOIN ordenes_trabajo ot ON ot.id = ci.ot_id
                     WHERE ci.id = checklist_v2_instance_item.instance_id
                       AND ot.preparacion_ok_at IS NOT NULL
                       AND ot.estado IN ('asignada','en_ejecucion','pausada'))
    );


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'vista_ok', (SELECT EXISTS (
        SELECT 1 FROM information_schema.views WHERE table_name = 'v_taller_mecanico_ots')),
    'vista_con_asignada_a_mi', (SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'v_taller_mecanico_ots' AND column_name = 'asignada_a_mi')),
    'vista_sin_filtro_operador', (SELECT position('operador_taller' in pg_get_viewdef('v_taller_mecanico_ots'::regclass)) = 0),
    'pol_item_operador', (SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'checklist_v2_instance_item'
          AND policyname = 'pol_cl_inst_item_operador_taller')),
    'ots_liberadas', (SELECT COUNT(*) FROM v_taller_mecanico_ots)
) AS resultado;

NOTIFY pgrst, 'reload schema';
