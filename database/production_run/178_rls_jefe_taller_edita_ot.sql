-- ============================================================================
-- SICOM-ICEO | 178 — El jefe de taller (jefe_mantenimiento) edita todo el taller
-- ============================================================================
-- Pedido Manuel (2026-06-30): "todo lo que está en taller debe ser editable por
--   el jefe de taller". Auditoría: casi todas las RPC de taller ya incluyen
--   jefe_mantenimiento, y el checklist V03 (checklist_v2_instance/_item), el plan
--   semanal y ot_materiales_planeados ya le dan escritura. El ÚNICO bloqueo real
--   son escrituras DIRECTAS del frontend (no via RPC SECURITY DEFINER) sobre tres
--   tablas del flujo de OT, donde RLS solo le daba SELECT:
--     - ordenes_trabajo   (updateOrdenTrabajo  -> .update)
--     - checklist_ot       (updateChecklistItem -> .update, checklist legacy)
--     - evidencias_ot      (addEvidenciaOT      -> .insert)
--   => esas operaciones fallaban en silencio para jefe_mantenimiento.
--
-- Este fix agrega políticas de ESCRITURA (INSERT/UPDATE, NO DELETE) para
-- jefe_mantenimiento sobre esas tres tablas. Alcance global (el jefe de taller no
-- está acotado a una faena), igual que el patrón del plan semanal (MIG82).
--
-- IMPORTANTE — decisiones de Manuel (2026-06-30):
--   * OT cerradas siguen INMUTABLES para todos los roles: los triggers
--     trg_bloquear_escritura_ot_cerrada / trg_checklist_ot_cerrada /
--     trg_evidencias_ot_cerrada se disparan igual y siguen protegiendo el cierre.
--   * Control de calidad NO se toca: la resolución de auditorías/chequeo cruzado
--     sigue reservada a auditor_calidad (segregación de funciones).
--
-- ADITIVA, IDEMPOTENTE. No usa DELETE ni FOR ALL (no habilita borrar OT).
-- ============================================================================

-- ── ordenes_trabajo: INSERT + UPDATE para jefe_mantenimiento (global) ────────
DROP POLICY IF EXISTS pol_jefe_mant_update_ordenes_trabajo ON ordenes_trabajo;
CREATE POLICY pol_jefe_mant_update_ordenes_trabajo ON ordenes_trabajo
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() = 'jefe_mantenimiento')
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');

DROP POLICY IF EXISTS pol_jefe_mant_insert_ordenes_trabajo ON ordenes_trabajo;
CREATE POLICY pol_jefe_mant_insert_ordenes_trabajo ON ordenes_trabajo
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');

-- ── checklist_ot (legacy): INSERT + UPDATE ───────────────────────────────────
DROP POLICY IF EXISTS pol_jefe_mant_insert_checklist_ot ON checklist_ot;
CREATE POLICY pol_jefe_mant_insert_checklist_ot ON checklist_ot
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');

DROP POLICY IF EXISTS pol_jefe_mant_update_checklist_ot ON checklist_ot;
CREATE POLICY pol_jefe_mant_update_checklist_ot ON checklist_ot
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() = 'jefe_mantenimiento')
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');

-- ── evidencias_ot: INSERT + UPDATE ────────────────────────────────────────────
DROP POLICY IF EXISTS pol_jefe_mant_insert_evidencias_ot ON evidencias_ot;
CREATE POLICY pol_jefe_mant_insert_evidencias_ot ON evidencias_ot
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');

DROP POLICY IF EXISTS pol_jefe_mant_update_evidencias_ot ON evidencias_ot;
CREATE POLICY pol_jefe_mant_update_evidencias_ot ON evidencias_ot
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() = 'jefe_mantenimiento')
    WITH CHECK (fn_user_rol() = 'jefe_mantenimiento');


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'policies_creadas', (SELECT array_agg(policyname ORDER BY policyname)
        FROM pg_policies
        WHERE policyname LIKE 'pol_jefe_mant_%'
          AND tablename IN ('ordenes_trabajo','checklist_ot','evidencias_ot')),
    'inmutabilidad_intacta', (SELECT array_agg(tgname ORDER BY tgname)
        FROM pg_trigger
        WHERE tgname IN ('trg_bloquear_escritura_ot_cerrada','trg_checklist_ot_cerrada','trg_evidencias_ot_cerrada')
           OR tgname LIKE 'trg_%cerrada%')
) AS resultado;

NOTIFY pgrst, 'reload schema';
