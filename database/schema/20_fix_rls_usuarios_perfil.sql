-- SICOM-ICEO | Fix RLS: permitir lectura de usuarios_perfil a autenticados
-- ============================================================================
-- PROBLEMA: El join responsable:usuarios_perfil en queries de OTs falla
-- porque RLS solo permite leer el propio perfil (auth.uid() = id).
-- Los joins a otros usuarios (responsable de OT, supervisor, etc.) retornan
-- error 406 o datos vacíos.
--
-- SOLUCIÓN: Agregar política que permita SELECT a cualquier autenticado.
-- Esto es seguro porque usuarios_perfil no contiene datos sensibles
-- (no tiene passwords, solo nombre, cargo, rol, faena).
-- ============================================================================

-- Primero eliminar la política restrictiva si existe
DROP POLICY IF EXISTS pol_authenticated_read_own_perfil ON usuarios_perfil;

-- Crear política que permite a TODOS los autenticados leer TODOS los perfiles
-- (necesario para joins en OTs, historial, reportes, etc.)
CREATE POLICY pol_authenticated_select_all_perfil ON usuarios_perfil
    FOR SELECT TO authenticated
    USING (true);

-- Verificar
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_policies
    WHERE tablename = 'usuarios_perfil'
      AND policyname = 'pol_authenticated_select_all_perfil';

    IF v_count > 0 THEN
        RAISE NOTICE 'OK: Política de lectura de usuarios_perfil para autenticados activa';
    ELSE
        RAISE EXCEPTION 'ERROR: Política no se creó correctamente';
    END IF;
END $$;
