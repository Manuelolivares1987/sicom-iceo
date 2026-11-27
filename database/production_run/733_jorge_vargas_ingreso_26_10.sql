-- ============================================================================
-- MIG733 · Jorge Vargas: Mecánico A desde su ingreso real (26-10-2026)
-- ============================================================================
-- Manuel (26-11-2026): «ingreso el 26/10» · «si aplica la 733 con el 26-10».
-- MIG728 le puso el cargo desde el 28-10-2026 (el día que entró al sistema).
-- Su ingreso real es el 26-10: el cargo se corre a esa fecha. Por la regla del
-- acta (D6, prorrateo por días de contrato) queda 29/30 en el corte
-- 24-10 → 23-11: tope $154.672 y KPI $96.667 (antes $144.000 y $90.000).
-- No hay cortes cerrados: nada congelado cambia.
-- ============================================================================

BEGIN;

UPDATE taller_tecnico_cargo
   SET desde = DATE '2026-10-26'
 WHERE tecnico_id = 'bcb33c21-edbb-4ef8-b1f7-3faa539c7db9'
   AND cargo = 'Mecanico A'
   AND desde = DATE '2026-10-28';

DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM taller_tecnico_cargo
     WHERE tecnico_id = 'bcb33c21-edbb-4ef8-b1f7-3faa539c7db9' AND desde = DATE '2026-10-26';
    IF n <> 1 THEN RAISE EXCEPTION 'Esperaba 1 cargo de Jorge Vargas desde 26-10, hay %', n; END IF;
END $$;

COMMIT;
