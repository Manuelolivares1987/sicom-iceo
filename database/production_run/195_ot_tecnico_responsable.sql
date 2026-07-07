-- ============================================================================
-- SICOM-ICEO | 195 — La OT guarda su técnico responsable (catálogo taller)
--                    y la ficha "Editar Orden" usa la misma lista del plan
-- ============================================================================
-- Bug reportado por Manuel (2026-07-07): en la ficha de la OT → Editar Orden,
-- el selector "Responsable" lista TODAS las cuentas de la plataforma (no los
-- técnicos del taller) → no puede asignar a un mecánico. Además pregunta si,
-- al no tocar nada, queda el responsable de planificación: hoy la OT solo
-- guarda responsable_id (cuenta) y pierde al técnico sin cuenta.
--
--   1. ordenes_trabajo.tecnico_id (FK taller_tecnicos) — técnico responsable.
--   2. rpc_taller_editar_jornada sincroniza ese técnico a la OT (el plan es
--      la fuente: no tocar nada en la ficha = queda lo planificado).
--   3. fn_taller_ot_asignada_al_usuario también matchea por ot.tecnico_id.
--   4. v_taller_mecanico_ots muestra el nombre del técnico como responsable.
--   5. Backfill desde las jornadas del plan que ya tienen técnico.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_taller_editar_jornada'
                   AND pg_get_function_identity_arguments(oid) LIKE '%p_tecnico_id%') THEN
        RAISE EXCEPTION 'STOP — falta rpc_taller_editar_jornada con p_tecnico_id (MIG194).';
    END IF;
END $$;


-- ── 1. Columna en la OT ──────────────────────────────────────────────────────
ALTER TABLE ordenes_trabajo ADD COLUMN IF NOT EXISTS tecnico_id UUID REFERENCES taller_tecnicos(id);
COMMENT ON COLUMN ordenes_trabajo.tecnico_id IS
    'Tecnico responsable (catalogo taller_tecnicos). Se sincroniza desde el plan semanal taller. MIG195.';
CREATE INDEX IF NOT EXISTS idx_ot_tecnico ON ordenes_trabajo(tecnico_id) WHERE tecnico_id IS NOT NULL;


-- ── 2. La asignación por cuenta también mira ot.tecnico_id ───────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_asignada_al_usuario(p_ot_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM ordenes_trabajo ot
        WHERE ot.id = p_ot_id
          AND (
            ot.responsable_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM taller_tecnicos tt0
                WHERE tt0.id = ot.tecnico_id AND tt0.usuario_perfil_id = auth.uid()
            )
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


-- ── 3. El plan sincroniza el técnico a la OT ─────────────────────────────────
-- (misma firma de MIG194; solo cambia el bloque de sync a ordenes_trabajo)
CREATE OR REPLACE FUNCTION rpc_taller_editar_jornada(
    p_plan_ot_id          UUID,
    p_responsable_id      UUID    DEFAULT NULL,
    p_cuadrilla           VARCHAR DEFAULT NULL,
    p_horas_planificadas  NUMERIC DEFAULT NULL,
    p_avance_objetivo     NUMERIC DEFAULT NULL,
    p_observaciones       TEXT    DEFAULT NULL,
    p_sync_responsable_ot BOOLEAN DEFAULT TRUE,
    p_motivo              TEXT    DEFAULT NULL,
    p_tecnico_id          UUID    DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_ot   UUID; v_plan UUID; v_conf BOOLEAN;
    v_resp_old UUID; v_cuad_old VARCHAR; v_horas_old NUMERIC; v_tec_old UUID;
    v_resp_from_tec UUID;
    v_resp_nuevo UUID;
    v_cambia_personal BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para editar la jornada (rol: %)', v_rol;
    END IF;

    SELECT ot_id, plan_semanal_id, responsable_id, cuadrilla, horas_planificadas, tecnico_id
      INTO v_ot, v_plan, v_resp_old, v_cuad_old, v_horas_old, v_tec_old
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'Jornada no existe'; END IF;

    IF p_tecnico_id IS NOT NULL THEN
        SELECT usuario_perfil_id INTO v_resp_from_tec
          FROM taller_tecnicos WHERE id = p_tecnico_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Técnico no existe en el catálogo'; END IF;
    END IF;
    v_resp_nuevo := COALESCE(p_responsable_id, v_resp_from_tec);

    v_conf := fn_taller_plan_confirmado(v_plan);
    v_cambia_personal :=
        (p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old)
     OR (p_cuadrilla     IS NOT NULL AND p_cuadrilla     IS DISTINCT FROM v_cuad_old)
     OR (p_tecnico_id    IS NOT NULL AND p_tecnico_id    IS DISTINCT FROM v_tec_old);

    IF v_conf AND v_cambia_personal AND COALESCE(TRIM(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO: el plan esta confirmado; indica por que cambia el personal asignado.';
    END IF;

    UPDATE taller_plan_semanal_ots
       SET tecnico_id         = COALESCE(p_tecnico_id, tecnico_id),
           responsable_id     = COALESCE(v_resp_nuevo, responsable_id),
           cuadrilla          = COALESCE(p_cuadrilla, cuadrilla),
           horas_planificadas = COALESCE(p_horas_planificadas, horas_planificadas),
           avance_objetivo_pct= COALESCE(p_avance_objetivo, avance_objetivo_pct),
           estado_plan        = CASE WHEN estado_plan = 'planificada'
                                       AND (COALESCE(v_resp_nuevo, responsable_id) IS NOT NULL
                                            OR COALESCE(p_tecnico_id, tecnico_id) IS NOT NULL)
                                     THEN 'asignada' ELSE estado_plan END,
           observaciones      = COALESCE(p_observaciones, observaciones),
           updated_at         = NOW()
     WHERE id = p_plan_ot_id;

    -- El plan manda: técnico y/o cuenta responsable quedan también en la OT
    -- (así la ficha "Editar Orden" muestra lo planificado sin tocar nada).
    IF p_sync_responsable_ot AND (p_tecnico_id IS NOT NULL OR v_resp_nuevo IS NOT NULL) THEN
        UPDATE ordenes_trabajo
           SET tecnico_id     = COALESCE(p_tecnico_id, tecnico_id),
               responsable_id = COALESCE(v_resp_nuevo, responsable_id),
               updated_at     = NOW()
         WHERE id = v_ot;
    END IF;

    -- Bitacora
    IF p_tecnico_id IS NOT NULL AND p_tecnico_id IS DISTINCT FROM v_tec_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_campo := 'tecnico',
            p_valor_anterior := (SELECT nombre FROM taller_tecnicos WHERE id = v_tec_old),
            p_valor_nuevo    := (SELECT nombre FROM taller_tecnicos WHERE id = p_tecnico_id));
    ELSIF p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_responsable_anterior := v_resp_old, p_responsable_nuevo := p_responsable_id);
    END IF;
    IF p_cuadrilla IS NOT NULL AND p_cuadrilla IS DISTINCT FROM v_cuad_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_cuadrilla', p_motivo,
            p_cuadrilla_anterior := v_cuad_old, p_cuadrilla_nueva := p_cuadrilla);
    END IF;
    IF p_horas_planificadas IS NOT NULL AND p_horas_planificadas IS DISTINCT FROM v_horas_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_horas', p_motivo,
            p_campo := 'horas_planificadas',
            p_valor_anterior := v_horas_old::TEXT, p_valor_nuevo := p_horas_planificadas::TEXT);
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', p_plan_ot_id, 'ot_id', v_ot);
END;
$$;


-- ── 4. Vista del mecánico: responsable = técnico del catálogo si existe ──────
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
    COALESCE(tt.nombre, up.nombre_completo) AS responsable,
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
LEFT JOIN taller_tecnicos tt ON tt.id = ot.tecnico_id
LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
WHERE ot.preparacion_ok_at IS NOT NULL
  AND ot.estado IN ('asignada','en_ejecucion','pausada')
ORDER BY
    CASE ot.estado WHEN 'en_ejecucion' THEN 1 WHEN 'pausada' THEN 2 ELSE 3 END,
    CASE ot.prioridad WHEN 'emergencia' THEN 1 WHEN 'urgente' THEN 2 WHEN 'alta' THEN 3
                      WHEN 'normal' THEN 4 ELSE 5 END,
    ot.fecha_programada NULLS LAST;

COMMENT ON VIEW v_taller_mecanico_ots IS
    'OTs liberadas a ejecucion (todas). responsable prefiere el tecnico del catalogo (ot.tecnico_id). asignada_a_mi marca las del usuario autenticado. MIG195.';
GRANT SELECT ON v_taller_mecanico_ots TO authenticated;


-- ── 5. Backfill: técnico más reciente de las jornadas del plan ───────────────
UPDATE ordenes_trabajo ot
   SET tecnico_id = sub.tecnico_id
  FROM (SELECT DISTINCT ON (ot_id) ot_id, tecnico_id
          FROM taller_plan_semanal_ots
         WHERE tecnico_id IS NOT NULL
         ORDER BY ot_id, updated_at DESC) sub
 WHERE sub.ot_id = ot.id
   AND ot.tecnico_id IS NULL;

-- Jornadas antiguas sin tecnico_id: el primer nombre de la cuadrilla, si calza
-- exactamente con UN técnico del catálogo, pasa a ser el técnico de la OT.
UPDATE ordenes_trabajo ot
   SET tecnico_id = sub.tecnico_id
  FROM (SELECT DISTINCT ON (t.ot_id) t.ot_id, tt.id AS tecnico_id
          FROM taller_plan_semanal_ots t
          JOIN taller_tecnicos tt
            ON LOWER(TRIM(tt.nombre)) = LOWER(TRIM(split_part(t.cuadrilla, ',', 1)))
           AND tt.activo
         WHERE NULLIF(TRIM(t.cuadrilla), '') IS NOT NULL
         ORDER BY t.ot_id, t.updated_at DESC) sub
 WHERE sub.ot_id = ot.id
   AND ot.tecnico_id IS NULL;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_ok', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='ordenes_trabajo' AND column_name='tecnico_id')),
    'fn_con_ot_tecnico', (SELECT prosrc LIKE '%ot.tecnico_id%' FROM pg_proc
        WHERE proname='fn_taller_ot_asignada_al_usuario'),
    'rpc_sync_ot_tecnico', (SELECT prosrc LIKE '%SET tecnico_id     = COALESCE(p_tecnico_id, tecnico_id)%'
        FROM pg_proc WHERE proname='rpc_taller_editar_jornada'),
    'vista_resp_tecnico', (SELECT position('tt.nombre' in pg_get_viewdef('v_taller_mecanico_ots'::regclass)) > 0),
    'ots_backfill', (SELECT COUNT(*) FROM ordenes_trabajo WHERE tecnico_id IS NOT NULL)
) AS resultado;

NOTIFY pgrst, 'reload schema';
