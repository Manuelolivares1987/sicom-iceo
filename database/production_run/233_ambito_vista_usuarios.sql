-- ============================================================================
-- SICOM-ICEO | 233 — Ámbito de vista por usuario (Calama / Coquimbo / todos)
-- ============================================================================
-- Pedido de Manuel: el jefe de operaciones de Calama debe ver SOLO lo de
-- Calama (Operación Calama + Contrato ENEX) y Flota; los de Coquimbo deben
-- ver todo el resto MENOS Calama/ENEX. El ámbito filtra el menú (la vista);
-- los permisos de fondo siguen siendo los del rol.
--   · 'todos'    → vista completa (default, comportamiento actual)
--   · 'calama'   → Dashboard + Operación Calama + Contrato ENEX + Flota
--   · 'coquimbo' → todo menos Operación Calama y Contrato ENEX
-- ============================================================================

ALTER TABLE usuarios_perfil
  ADD COLUMN IF NOT EXISTS ambito TEXT NOT NULL DEFAULT 'todos'
  CHECK (ambito IN ('todos', 'calama', 'coquimbo'));

-- Asignación inicial según los usuarios existentes (ajustable después)
UPDATE usuarios_perfil SET ambito = 'calama'
 WHERE nombre_completo IN ('Supervisor Operación Calama', 'Supervisor Calama', 'Operacion Obras Civiles Calama');

UPDATE usuarios_perfil SET ambito = 'coquimbo'
 WHERE nombre_completo IN ('Supervisor Operación Coquimbo');

DO $$
DECLARE v_cal INT; v_cqb INT;
BEGIN
  SELECT count(*) INTO v_cal FROM usuarios_perfil WHERE ambito = 'calama';
  SELECT count(*) INTO v_cqb FROM usuarios_perfil WHERE ambito = 'coquimbo';
  RAISE NOTICE 'MIG233 OK: ambito de vista — calama: % usuario(s), coquimbo: % usuario(s), resto: todos', v_cal, v_cqb;
END $$;
