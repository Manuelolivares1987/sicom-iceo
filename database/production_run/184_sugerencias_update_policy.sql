-- ============================================================================
-- SICOM-ICEO | 184 — Permitir cambiar el estado de las sugerencias (la ampolleta)
-- ============================================================================
-- La tabla sugerencias (MIG175) tenía RLS de SELECT + INSERT, pero no de UPDATE,
-- así que la pantalla de revisión no podía cambiar el estado
-- (nueva → en_proceso → aplicada → descartada). Se agrega política UPDATE para
-- roles operacionales.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DROP POLICY IF EXISTS pol_sugerencias_update ON sugerencias;
CREATE POLICY pol_sugerencias_update ON sugerencias
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','gerencia'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','gerencia'));

GRANT SELECT, INSERT, UPDATE ON sugerencias TO authenticated;

SELECT jsonb_build_object(
    'policy_ok', EXISTS(SELECT 1 FROM pg_policies WHERE tablename='sugerencias' AND policyname='pol_sugerencias_update')
) AS resultado;

NOTIFY pgrst, 'reload schema';
