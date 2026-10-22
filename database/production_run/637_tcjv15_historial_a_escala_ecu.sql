-- MIG637 · TCJV-15: historial de horas y km a la escala de la ECU
-- ============================================================================
-- Con MIG636 TCJV-15 pasó de Radicom al GPS de fábrica Renault. Su historial
-- diario (activo_horas_dia) quedó en escala Radicom y el día del cambio
-- mezclado: el 21-10 marcaba 352 km fantasma (la diferencia de odómetros) y
-- el ritmo de horas y el costo por hora lo arrastraban.
--
-- Diferencias medidas en el mismo instante (22-10 05:00 UTC, lectura de
-- contadores Radicom vs lectura ECU): horómetro 208,8 h, odómetro 348,44 km.
-- Los valores Radicom de este camión están todos bajo 1.900 h / 24.600 km y
-- los de la ECU sobre 1.944 h / 24.700 km: el umbral separa sin ambigüedad.
-- Idempotente: una vez corrido, nada queda bajo el umbral.
-- ============================================================================

BEGIN;

UPDATE activo_horas_dia h
   SET horometro_ini = CASE WHEN h.horometro_ini < 1900 THEN h.horometro_ini + 208.8 ELSE h.horometro_ini END,
       horometro_fin = CASE WHEN h.horometro_fin < 1900 THEN h.horometro_fin + 208.8 ELSE h.horometro_fin END,
       km_ini        = CASE WHEN h.km_ini < 24600 THEN h.km_ini + 348.44 ELSE h.km_ini END,
       km_fin        = CASE WHEN h.km_fin < 24600 THEN h.km_fin + 348.44 ELSE h.km_fin END,
       actualizado_at = NOW()
  FROM activos a
 WHERE a.id = h.activo_id
   AND upper(a.vin_chasis) = 'VF630N358PD000096'
   AND (h.horometro_ini < 1900 OR h.horometro_fin < 1900 OR h.km_ini < 24600 OR h.km_fin < 24600);

COMMIT;
