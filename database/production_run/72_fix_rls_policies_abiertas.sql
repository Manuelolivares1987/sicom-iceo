-- ============================================================================
-- 72_fix_rls_policies_abiertas.sql
-- ----------------------------------------------------------------------------
-- BRECHA DE SEGURIDAD: combustible_movimientos y combustible_kardex_valorizado
-- tienen policies PERMISSIVE con USING (true) que dan SELECT libre a TODOS los
-- usuarios authenticated, incluidos los del portal cliente. Las policies
-- restrictivas del portal (MIG63 + MIG71) son ignoradas porque PERMISSIVE
-- evalua con OR (basta UNA policy true para autorizar).
--
-- Sintoma: usuario portal lisset@pillado.cl ve TODOS los despachos, no solo
-- los de su empresa autorizada.
--
-- Fix:
--   1. DROP de las policies abiertas:
--        pol_ckv_select        (combustible_kardex_valorizado, USING true)
--        pol_cmov_all          (combustible_movimientos, USING true + WITH CHECK true)
--   2. CREATE de policies restrictivas para usuarios internos Pillado
--        (rol presente en fn_user_rol). Estos siguen pudiendo SELECT/INSERT/
--        UPDATE/DELETE como antes.
--   3. Las policies del portal cliente (MIG63 + MIG71) quedan intactas:
--        pol_combustible_mov_portal_cliente (SELECT con filtro contratos/empresas)
--        pol_kardex_valorizado_portal_cliente (idem en kardex)
--
-- Resultado:
--   - Internos: pase total (mismo comportamiento de antes).
--   - Portal cliente: solo ve filas que matchean su contrato o empresa externa.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. combustible_kardex_valorizado ───────────────────────────────────────
DROP POLICY IF EXISTS pol_ckv_select ON combustible_kardex_valorizado;

-- Policy interna: usuario con rol Pillado activo => pase a SELECT/INSERT/UPDATE/DELETE
DROP POLICY IF EXISTS pol_kardex_interno_all ON combustible_kardex_valorizado;
CREATE POLICY pol_kardex_interno_all
    ON combustible_kardex_valorizado
    FOR ALL
    TO authenticated
    USING (fn_user_rol() IS NOT NULL)
    WITH CHECK (fn_user_rol() IS NOT NULL);

-- La policy pol_kardex_valorizado_portal_cliente (MIG71) ya filtra para portal
-- y queda activa para SELECT con el criterio contratos/empresas externas.


-- ── 2. combustible_movimientos ─────────────────────────────────────────────
DROP POLICY IF EXISTS pol_cmov_all ON combustible_movimientos;

-- Policy interna equivalente: ALL para internos
DROP POLICY IF EXISTS pol_cmov_interno_all ON combustible_movimientos;
CREATE POLICY pol_cmov_interno_all
    ON combustible_movimientos
    FOR ALL
    TO authenticated
    USING (fn_user_rol() IS NOT NULL)
    WITH CHECK (fn_user_rol() IS NOT NULL);

-- La policy pol_combustible_mov_portal_cliente (MIG63) sigue filtrando portal.


-- ── 3. Asegurar que RLS esta REALMENTE habilitada en ambas ─────────────────
ALTER TABLE combustible_kardex_valorizado ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_movimientos       ENABLE ROW LEVEL SECURITY;


-- ============================================================================
-- VALIDACION: revisa que no queden policies con USING (true) ni WITH CHECK (true)
-- ============================================================================
SELECT jsonb_build_object(
    'policies_abiertas_residuales', (
        SELECT COUNT(*)
          FROM pg_policies
         WHERE tablename IN ('combustible_movimientos','combustible_kardex_valorizado')
           AND (qual = 'true' OR with_check = 'true')
    ),
    'policies_actuales', (
        SELECT jsonb_agg(jsonb_build_object(
            'tabla', tablename, 'name', policyname, 'cmd', cmd,
            'qual', qual, 'with_check', with_check
        ))
          FROM pg_policies
         WHERE tablename IN ('combustible_movimientos','combustible_kardex_valorizado')
    )
) AS resultado;
