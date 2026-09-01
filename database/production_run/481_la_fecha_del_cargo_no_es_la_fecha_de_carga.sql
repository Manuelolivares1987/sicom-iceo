-- ============================================================================
-- MIG481 · La fecha del cargo no es la fecha en que se cargó
-- ============================================================================
--
-- LO QUE APARECIÓ AL APLICAR D6
-- El acta decidió prorratear el KPI por días de contrato (mes comercial de 30).
-- Al calcular el corte de septiembre, los ocho técnicos aparecieron con
-- `dias_cargo = 23` y un prorrateo de 76,67%: a todos les faltaban 7 días.
--
-- No es que hayan entrado el 1 de septiembre. Es que `taller_tecnico_cargo.desde`
-- se sembró con la fecha en que se cargó la tabla, y el prorrateo —que hasta
-- ayer no se aplicaba al KPI— convirtió ese dato administrativo en plata: 7 de
-- 30 días, más de $18.000 menos para un Mecánico A, sin que nadie lo decidiera.
--
-- LO QUE SE CORRIGE
-- Los que ya estaban trabajando arrancan el corte completo (24-08, primer día
-- del período de septiembre). No se inventa una fecha de contratación: se deja
-- de castigar por una fecha que el sistema se puso solo.
--
-- LO QUE QUEDA PENDIENTE, DICHO
-- Las fechas reales de contrato no están en el sistema. Mientras no se carguen,
-- quien entre a mitad de mes hay que ponerlo a mano en `desde` — y ahí el
-- prorrateo sí va a decir la verdad. Esta migración no lo puede saber.
-- ============================================================================

BEGIN;

UPDATE taller_tecnico_cargo
   SET desde = DATE '2026-08-24'
 WHERE desde = DATE '2026-09-01'
   AND hasta IS NULL;

COMMENT ON COLUMN taller_tecnico_cargo.desde IS
    'Desde cuándo la persona tiene ese cargo. Es la fecha que usa el prorrateo '
    'del KPI y del tope del plan (acta D6): no es la fecha de carga del dato. '
    'Si alguien entra a mitad de mes, va acá su fecha real.';

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT tecnico, cargo, dias_cargo, prorrateo, monto_kpi
          FROM fn_taller_bono_kpi_periodo_calc(DATE '2026-08-24', DATE '2026-09-23', NULL)
         WHERE cargo IS NOT NULL
         ORDER BY tecnico
    LOOP
        RAISE NOTICE '% (%): % días · prorrateo % · KPI %',
                     r.tecnico, r.cargo, r.dias_cargo, r.prorrateo, r.monto_kpi;
    END LOOP;
END $mig$;

COMMIT;
