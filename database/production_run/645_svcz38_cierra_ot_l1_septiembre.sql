-- MIG645 · SVCZ-38: cierre administrativo de la OT-202609-00010 (L1 del 07-09)
-- ============================================================================
-- La preventiva L1 se hizo el 07-09-2026 (certificado de mantención cargado),
-- pero la OT quedó «en ejecución» desde ese día: sin firma ni foto, con el
-- checklist completo (4/4). Manuel pidió cerrarla (23-10).
--
-- Se cierra como 'cerrada' con fecha 07-09. El cierre avanza la pauta al
-- horómetro de HOY (fn_ot_cerrada_avanza_plan), así que después se fija la
-- base real: 4.714 h = escala SICOM (horas_uso_actual) en esa fecha
-- (GPS 4.701,8 h + 21 h de desfase el 23-09 = 4.722,7 de la OT-202609-00011,
-- menos el uso GPS entre el 07-09 y el 23-09).
-- ============================================================================

BEGIN;

UPDATE taller_ot_ejecuciones
   SET estado = 'finalizada',
       finished_at = TIMESTAMPTZ '2026-09-07 18:00-03',
       observacion_cierre = 'Cierre administrativo 23-10: trabajo respaldado por certificado de mantención del 07-09.',
       updated_at = NOW()
 WHERE ot_id = '825079af-80d1-43c6-b1de-1913b2f99d77' AND estado = 'en_ejecucion';

UPDATE ordenes_trabajo
   SET estado = 'cerrada',
       fecha_termino = TIMESTAMPTZ '2026-09-07 18:00-03',
       horas_al_cierre = 4714,
       observaciones = concat_ws(E'\n', nullif(observaciones, ''),
           'Cierre administrativo 23-10-2026 (pedido por Manuel Olivares): L1 hecha el 07-09, respaldo = certificado de mantención cargado en documentos. Quedó en ejecución sin firma ni foto.'),
       updated_at = NOW()
 WHERE id = '825079af-80d1-43c6-b1de-1913b2f99d77' AND estado = 'en_ejecucion';

-- Base real de la L1 (el cierre la dejó en el horómetro de hoy).
INSERT INTO plan_mantenimiento_registro_manual (plan_id, activo_id, fecha, horas, km, nota, antes, absorbidos)
SELECT pm.id, pm.activo_id, DATE '2026-09-07', 4714, NULL,
       'OT-202609-00010 cerrada administrativamente; certificado de mantención 07-09. Horómetro estimado (GPS + desfase SICOM).',
       jsonb_build_object('fecha', DATE '2026-04-18', 'horas', 4259.0, 'km', pm.ultima_ejecucion_km), 0
  FROM planes_mantenimiento pm
 WHERE pm.id = (SELECT plan_mantenimiento_id FROM ordenes_trabajo WHERE id = '825079af-80d1-43c6-b1de-1913b2f99d77');

UPDATE planes_mantenimiento
   SET ultima_ejecucion_fecha = DATE '2026-09-07',
       ultima_ejecucion_horas = 4714,
       proxima_ejecucion_fecha = DATE '2026-09-07' + coalesce(frecuencia_dias, 30),
       updated_at = NOW()
 WHERE id = (SELECT plan_mantenimiento_id FROM ordenes_trabajo WHERE id = '825079af-80d1-43c6-b1de-1913b2f99d77');

COMMIT;
