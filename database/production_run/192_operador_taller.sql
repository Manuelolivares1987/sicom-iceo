-- ============================================================================
-- SICOM-ICEO | 192 — Rol operador_taller: ejecuta SOLO las OTs que le asigna
--                    su jefatura (identidad real, no localStorage)
-- ============================================================================
-- Pedido Manuel (2026-07-06): perfiles Jefe de Taller y Operador para ejecutar
-- el plan del taller en vivo. El jefe de taller SIGUE siendo el rol
-- jefe_mantenimiento (MIG178). Lo nuevo es el OPERADOR:
--
--   * Rol nuevo 'operador_taller' (login propio, app /m/taller offline-first).
--   * Hoy el mecánico se auto-identifica eligiendo su nombre (localStorage) y
--     la vista v_taller_mecanico_ots muestra TODAS las OTs liberadas.
--   * Ahora: el operador con login solo VE y EJECUTA las OTs asignadas a él:
--       - ordenes_trabajo.responsable_id = auth.uid(), o
--       - jornada del plan (taller_plan_semanal_ots.responsable_id), o
--       - técnico vinculado (taller_tecnicos.usuario_perfil_id) vía tecnico_id
--         o vía su nombre dentro de la cuadrilla (texto del picker del jefe).
--   * El resto de roles conserva el comportamiento actual de la vista.
--
-- La ejecución (iniciar/pausar/finalizar con firma) ya corre por RPCs
-- SECURITY DEFINER (rpc_transicion_ot, rpc_taller_finalizar_mecanico) con
-- GRANT a authenticated — no requieren cambios. El único write directo del
-- mecánico es el checklist V03 (checklist_v2_instance_item.update), que hoy
-- NO permite a un rol nuevo => política dedicada acotada a SUS OTs.
--
-- NOTA enum: 'operador_taller' se agrega con ADD VALUE IF NOT EXISTS y luego
-- solo se referencia como TEXT (fn_user_rol()), nunca casteado al enum, para
-- ser seguro dentro de transacción (patrón MIG125).
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='taller_tecnicos') THEN
        RAISE EXCEPTION 'STOP — falta taller_tecnicos (MIG181).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='taller_plan_semanal_ots' AND column_name='tecnico_id') THEN
        RAISE EXCEPTION 'STOP — falta taller_plan_semanal_ots.tecnico_id (MIG182).';
    END IF;
END $$;


-- ── 1. Rol nuevo ─────────────────────────────────────────────────────────────
ALTER TYPE rol_usuario_enum ADD VALUE IF NOT EXISTS 'operador_taller';


-- ── 2. ¿La OT está asignada al usuario autenticado? ──────────────────────────
-- SECURITY DEFINER: se usa dentro de políticas RLS y de la vista del mecánico;
-- necesita leer ordenes_trabajo / plan semanal / taller_tecnicos sin depender
-- de las políticas del caller.
CREATE OR REPLACE FUNCTION fn_taller_ot_asignada_al_usuario(p_ot_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM ordenes_trabajo ot
        WHERE ot.id = p_ot_id
          AND (
            ot.responsable_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM taller_plan_semanal_ots t
                LEFT JOIN taller_tecnicos tt ON tt.id = t.tecnico_id
                WHERE t.ot_id = ot.id
                  AND (t.responsable_id = auth.uid() OR tt.usuario_perfil_id = auth.uid())
            )
            -- Cuadrilla es texto libre (el picker del jefe escribe nombres de
            -- taller_tecnicos): match por nombre completo o primer nombre.
            OR EXISTS (
                SELECT 1
                FROM taller_plan_semanal_ots t2
                JOIN taller_tecnicos me
                  ON me.usuario_perfil_id = auth.uid() AND me.activo
                WHERE t2.ot_id = ot.id
                  AND NULLIF(TRIM(t2.cuadrilla), '') IS NOT NULL
                  AND (t2.cuadrilla ILIKE '%' || me.nombre || '%'
                       OR t2.cuadrilla ILIKE '%' || split_part(me.nombre, ' ', 1) || '%')
            )
          )
    );
$$;
COMMENT ON FUNCTION fn_taller_ot_asignada_al_usuario(UUID) IS
    'TRUE si la OT esta asignada al usuario autenticado (responsable OT/jornada, tecnico vinculado o nombre en cuadrilla). MIG192.';
GRANT EXECUTE ON FUNCTION fn_taller_ot_asignada_al_usuario(UUID) TO authenticated;


-- ── 3. Vista del mecánico: operador_taller solo ve SUS OTs ───────────────────
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
  -- El operador de taller SOLO ve lo que su jefatura le asignó.
  AND (fn_user_rol() <> 'operador_taller' OR fn_taller_ot_asignada_al_usuario(ot.id))
ORDER BY
    CASE ot.estado WHEN 'en_ejecucion' THEN 1 WHEN 'pausada' THEN 2 ELSE 3 END,
    CASE ot.prioridad WHEN 'emergencia' THEN 1 WHEN 'urgente' THEN 2 WHEN 'alta' THEN 3
                      WHEN 'normal' THEN 4 ELSE 5 END,
    ot.fecha_programada NULLS LAST;

COMMENT ON VIEW v_taller_mecanico_ots IS
    'OTs liberadas a ejecucion. operador_taller solo ve las asignadas a el (MIG192); resto de roles ve todas. App mecanico /m/taller.';
GRANT SELECT ON v_taller_mecanico_ots TO authenticated;


-- ── 4. Checklist V03: el operador marca items SOLO de sus OTs ────────────────
-- (pol_cl_inst_item_write de MIG55 no incluye roles nuevos; política aparte,
--  acotada por OT asignada — más restrictiva que la de los roles de taller.)
DROP POLICY IF EXISTS pol_cl_inst_item_operador_taller ON checklist_v2_instance_item;
CREATE POLICY pol_cl_inst_item_operador_taller ON checklist_v2_instance_item
    FOR UPDATE TO authenticated
    USING (
        fn_user_rol() = 'operador_taller'
        AND EXISTS (SELECT 1 FROM checklist_v2_instance ci
                    WHERE ci.id = checklist_v2_instance_item.instance_id
                      AND fn_taller_ot_asignada_al_usuario(ci.ot_id))
    )
    WITH CHECK (
        fn_user_rol() = 'operador_taller'
        AND EXISTS (SELECT 1 FROM checklist_v2_instance ci
                    WHERE ci.id = checklist_v2_instance_item.instance_id
                      AND fn_taller_ot_asignada_al_usuario(ci.ot_id))
    );


-- ── 5. Técnicos: el jefe vincula la cuenta del operador al catálogo ──────────
-- (la escritura de taller_tecnicos ya la tienen admin/jefe_mantenimiento/etc.
--  por pol_taller_tecnicos_write de MIG181 — sin cambios)
CREATE UNIQUE INDEX IF NOT EXISTS uq_taller_tecnicos_usuario_perfil
    ON taller_tecnicos (usuario_perfil_id) WHERE usuario_perfil_id IS NOT NULL;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rol_en_enum', (SELECT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'rol_usuario_enum' AND e.enumlabel = 'operador_taller')),
    'fn_asignada_ok', (SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'fn_taller_ot_asignada_al_usuario')),
    'vista_ok', (SELECT EXISTS (
        SELECT 1 FROM information_schema.views WHERE table_name = 'v_taller_mecanico_ots')),
    'vista_con_responsable_id', (SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'v_taller_mecanico_ots' AND column_name = 'responsable_id')),
    'pol_item_operador', (SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'checklist_v2_instance_item'
          AND policyname = 'pol_cl_inst_item_operador_taller')),
    'ots_liberadas', (SELECT COUNT(*) FROM v_taller_mecanico_ots)
) AS resultado;

NOTIFY pgrst, 'reload schema';
