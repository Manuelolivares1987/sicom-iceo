-- ============================================================================
-- Limpieza de datos de prueba E2E del 2026-07-12 (una sola vez, transaccional)
-- ============================================================================
-- Deja el sistema limpio para uso real: se anulan vales de prueba, se quitan
-- NCs/recursos/jornadas de las OTs de prueba, se cancelan esas OTs, se borra
-- el servicio ENEX de prueba (EESS Muelle julio) y las tareas de calidad demo.
-- El kardex NO se toca (las salidas/OC quedan como traza auditable).
-- ============================================================================

-- 1. ENEX: servicio de prueba EESS Muelle · julio 2026
DELETE FROM enex_ejecucion_items WHERE ejecucion_id IN (
  SELECT e.id FROM enex_ejecuciones e
  JOIN enex_programaciones p ON p.id = e.programacion_id
  JOIN enex_instalaciones i ON i.id = p.instalacion_id
  WHERE i.nombre = 'EESS Muelle' AND p.periodo_anio = 2026 AND p.periodo_mes = 7);

DELETE FROM enex_ejecuciones WHERE programacion_id IN (
  SELECT p.id FROM enex_programaciones p
  JOIN enex_instalaciones i ON i.id = p.instalacion_id
  WHERE i.nombre = 'EESS Muelle' AND p.periodo_anio = 2026 AND p.periodo_mes = 7);

DELETE FROM enex_programaciones p USING enex_instalaciones i
  WHERE i.id = p.instalacion_id AND i.nombre = 'EESS Muelle'
    AND p.periodo_anio = 2026 AND p.periodo_mes = 7;

-- 2. Plan semanal de calidad: tareas demo
DELETE FROM calidad_plan_tareas WHERE titulo ILIKE '%PRUEBA E2E%';

-- 3. Vales de prueba: anular (no borrar; las entregas SAL-* quedan como traza)
UPDATE bodega_tickets
   SET estado = 'anulado',
       observacion = TRIM(COALESCE(observacion,'') || ' [ANULADO: prueba E2E 12-07-2026]'),
       updated_at = NOW()
 WHERE folio IN ('TKT-202607-00004','TKT-202607-00005');

-- 4. Recursos solicitados de las OTs de prueba: rechazados (los ítems del vale
--    anulado los referencian, no se pueden borrar). Rechazado no aparece en
--    Seguimiento repuestos ni en la bandeja NC.
UPDATE ot_recursos_solicitados
   SET estado = 'rechazado',
       nota_jefe = TRIM(COALESCE(nota_jefe,'') || ' [limpieza prueba E2E 12-07-2026]')
 WHERE ot_id IN (SELECT id FROM ordenes_trabajo WHERE folio IN ('OT-202607-00043','OT-202607-00044'));

-- 5. NCs de las OTs de prueba
DELETE FROM no_conformidades
 WHERE ot_id IN (SELECT id FROM ordenes_trabajo WHERE folio IN ('OT-202607-00043','OT-202607-00044'));

-- 6. Jornadas de las OTs de prueba en el plan semanal del taller
DELETE FROM taller_plan_semanal_ots
 WHERE ot_id IN (SELECT id FROM ordenes_trabajo WHERE folio IN ('OT-202607-00043','OT-202607-00044'));

-- 7. Ejecuciones de taller de las OTs de prueba
DELETE FROM taller_ot_ejecuciones
 WHERE ot_id IN (SELECT id FROM ordenes_trabajo WHERE folio IN ('OT-202607-00043','OT-202607-00044'));

-- 8. Cancelar las OTs de prueba
UPDATE ordenes_trabajo SET estado = 'cancelada', updated_at = NOW()
 WHERE folio IN ('OT-202607-00043','OT-202607-00044');

DO $$
DECLARE v_enex INT; v_cal INT; v_rec INT; v_nc INT;
BEGIN
    SELECT count(*) INTO v_enex FROM enex_programaciones p JOIN enex_instalaciones i ON i.id=p.instalacion_id
     WHERE i.nombre='EESS Muelle' AND p.periodo_anio=2026 AND p.periodo_mes=7;
    SELECT count(*) INTO v_cal FROM calidad_plan_tareas WHERE titulo ILIKE '%PRUEBA E2E%';
    SELECT count(*) INTO v_rec FROM ot_recursos_solicitados
     WHERE (comentario ILIKE '%PRUEBA E2E%' OR descripcion ILIKE '%PRUEBA E2E%') AND estado <> 'rechazado';
    SELECT count(*) INTO v_nc FROM no_conformidades WHERE ot_id IN (SELECT id FROM ordenes_trabajo WHERE folio IN ('OT-202607-00043','OT-202607-00044'));
    RAISE NOTICE 'LIMPIEZA OK — restos: enex=%, calidad=%, recursos=%, nc=%', v_enex, v_cal, v_rec, v_nc;
END $$;
