-- ============================================================================
-- SICOM-ICEO | 105 — Cierre de mes MAYO 2026 (estado_diario_flota)
-- ============================================================================
-- La generacion diaria de estado_diario_flota se corto el 2026-05-27 (cron
-- flota_estados_diarios inactivo). Para cerrar el mes se completan los dias
-- faltantes 28, 29, 30 y 31 replicando la ultima foto disponible (27-may):
--
--   28-may : replica EXACTA del 27 (SVBJ-55 sigue en 'M').
--   29-may : replica del 27, pero SVBJ-55 (68aeb437-...) pasa a 'A' (Arrendado).
--   30-may : igual al 29 (SVBJ-55 en 'A').
--   31-may : igual al 29 (SVBJ-55 en 'A').
--
-- Las filas se marcan override_manual=true para que queden congeladas como el
-- cierre oficial del mes y no las pise un recalculo automatico posterior.
-- Idempotente: ON CONFLICT (activo_id, fecha) DO NOTHING.
-- ============================================================================

BEGIN;

-- ── 28-may: replica exacta del 27 ──────────────────────────────────────────
INSERT INTO estado_diario_flota
  (activo_id, fecha, contrato_id, estado_codigo, conductor_id, cliente, ubicacion,
   operacion, horas_operativas, horas_disponibles, horas_mantencion, km_recorridos,
   observacion, override_manual, motivo_override, calculado_auto)
SELECT s.activo_id, '2026-05-28'::date, s.contrato_id, s.estado_codigo, s.conductor_id,
       s.cliente, s.ubicacion, s.operacion, s.horas_operativas, s.horas_disponibles,
       s.horas_mantencion, s.km_recorridos,
       'Cierre de mes mayo 2026 - replica del 2026-05-27',
       true, 'Cierre de mes mayo 2026', false
  FROM estado_diario_flota s
 WHERE s.fecha = '2026-05-27'
ON CONFLICT (activo_id, fecha) DO NOTHING;

-- ── 29, 30, 31-may: replica del 27 con SVBJ-55 -> 'A' ───────────────────────
INSERT INTO estado_diario_flota
  (activo_id, fecha, contrato_id, estado_codigo, conductor_id, cliente, ubicacion,
   operacion, horas_operativas, horas_disponibles, horas_mantencion, km_recorridos,
   observacion, override_manual, motivo_override, calculado_auto)
SELECT s.activo_id,
       d.fecha,
       s.contrato_id,
       CASE WHEN s.activo_id = '68aeb437-009d-4786-ad9f-2833fc72e91e'
            THEN 'A' ELSE s.estado_codigo END,
       s.conductor_id, s.cliente, s.ubicacion, s.operacion,
       s.horas_operativas, s.horas_disponibles, s.horas_mantencion, s.km_recorridos,
       CASE WHEN s.activo_id = '68aeb437-009d-4786-ad9f-2833fc72e91e'
            THEN 'Cierre de mes mayo 2026 - SVBJ-55 pasa a Arrendado (A) desde 29-may'
            ELSE 'Cierre de mes mayo 2026 - replica del 2026-05-27' END,
       true,
       CASE WHEN s.activo_id = '68aeb437-009d-4786-ad9f-2833fc72e91e'
            THEN 'Cierre de mes mayo 2026 / SVBJ-55 -> A'
            ELSE 'Cierre de mes mayo 2026' END,
       false
  FROM estado_diario_flota s
 CROSS JOIN (VALUES ('2026-05-29'::date), ('2026-05-30'::date), ('2026-05-31'::date)) AS d(fecha)
 WHERE s.fecha = '2026-05-27'
ON CONFLICT (activo_id, fecha) DO NOTHING;

-- ── Verificacion dentro de la misma transaccion ────────────────────────────
DO $$
DECLARE
    v28 INTEGER; v29 INTEGER; v30 INTEGER; v31 INTEGER;
    v_svbj_28 CHAR(1); v_svbj_29 CHAR(1); v_svbj_31 CHAR(1);
BEGIN
    SELECT count(*) INTO v28 FROM estado_diario_flota WHERE fecha = '2026-05-28';
    SELECT count(*) INTO v29 FROM estado_diario_flota WHERE fecha = '2026-05-29';
    SELECT count(*) INTO v30 FROM estado_diario_flota WHERE fecha = '2026-05-30';
    SELECT count(*) INTO v31 FROM estado_diario_flota WHERE fecha = '2026-05-31';
    SELECT estado_codigo INTO v_svbj_28 FROM estado_diario_flota
      WHERE fecha='2026-05-28' AND activo_id='68aeb437-009d-4786-ad9f-2833fc72e91e';
    SELECT estado_codigo INTO v_svbj_29 FROM estado_diario_flota
      WHERE fecha='2026-05-29' AND activo_id='68aeb437-009d-4786-ad9f-2833fc72e91e';
    SELECT estado_codigo INTO v_svbj_31 FROM estado_diario_flota
      WHERE fecha='2026-05-31' AND activo_id='68aeb437-009d-4786-ad9f-2833fc72e91e';

    RAISE NOTICE '== Cierre mayo 2026 ==';
    RAISE NOTICE 'Filas 28/29/30/31 = % / % / % / %', v28, v29, v30, v31;
    RAISE NOTICE 'SVBJ-55  28=% (esperado M)  29=% (esperado A)  31=% (esperado A)',
                 v_svbj_28, v_svbj_29, v_svbj_31;

    IF NOT (v28 = 55 AND v29 = 55 AND v30 = 55 AND v31 = 55) THEN
        RAISE EXCEPTION 'Conteo inesperado: se esperaban 55 filas por dia.';
    END IF;
    IF NOT (v_svbj_28 = 'M' AND v_svbj_29 = 'A' AND v_svbj_31 = 'A') THEN
        RAISE EXCEPTION 'SVBJ-55 no quedo con el estado esperado (28=M, 29/31=A).';
    END IF;
END $$;

COMMIT;
