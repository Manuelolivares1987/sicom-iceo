-- ============================================================================
-- MIG581 · Copiloto: el jefe de operaciones lee el panel que el menú le ofrece
-- ============================================================================
--
-- 04-10-2026, Manuel: «necesito que el jefe de taller y jefe de operaciones
-- (Rodrigo) tenga acceso a mi copiloto».
--
-- El chat (/m/taller/copiloto) nunca tuvo candado por rol: basta la sesión.
-- Lo que estaba cojo es el panel de jefatura (/dashboard/mantenimiento/copiloto):
-- el menú lo muestra a jefe_operaciones y subgerente_operaciones, pero la
-- política de lectura de MIG542 solo nombraba a administrador, gerencia,
-- jefe_mantenimiento y planificador. Con esos dos roles el panel abría sin
-- error y mostraba SOLO las consultas propias: cero, como si nadie lo usara.
--
-- Se alinean las dos políticas con la lista de roles del menú:
--   · copiloto_consultas  SELECT  (ver lo que pregunta el taller)
--   · copiloto_diagnosticos UPDATE (corregir/cerrar un caso técnico)
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS copiloto_consultas_select ON copiloto_consultas;
CREATE POLICY copiloto_consultas_select ON copiloto_consultas FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM usuarios_perfil up
                WHERE up.id = auth.uid()
                  AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                 'jefe_operaciones','jefe_mantenimiento','planificador'))
  );

DROP POLICY IF EXISTS copiloto_dx_update ON copiloto_diagnosticos;
CREATE POLICY copiloto_dx_update ON copiloto_diagnosticos FOR UPDATE
  USING (usuario_id = auth.uid()
         OR EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                     AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                    'jefe_operaciones','jefe_mantenimiento','planificador')));

COMMIT;

SELECT policyname, cmd FROM pg_policies
 WHERE tablename IN ('copiloto_consultas','copiloto_diagnosticos')
   AND policyname IN ('copiloto_consultas_select','copiloto_dx_update');
