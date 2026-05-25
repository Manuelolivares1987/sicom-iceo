-- ============================================================================
-- emergencia-recuperar-io.sql
-- Correr en Supabase SQL Editor EN CUANTO la DB responda tras el Restore.
-- Objetivo: romper el ciclo de I/O saturado encogiendo gps_eventos_log y
-- apagando el cron GPS para que al redesplegar no vuelva a hundirse.
--
-- IMPORTANTE: ejecuta los bloques EN ORDEN y de a uno. Si el editor responde
-- aunque sea lento, dale tiempo a cada uno.
-- ============================================================================


-- ── BLOQUE 1 — Apagar YA el cron GPS (1 statement, rapidisimo) ──────────────
-- Evita que el pg_cron de 60s siga disparando cuando redesplegues la funcion.
UPDATE cron.job SET active = false
WHERE command ILIKE '%gps-radicom-poll%';


-- ── BLOQUE 2 — Ver el tamaño del problema (solo lectura, liviano) ───────────
SELECT
  pg_size_pretty(pg_total_relation_size('gps_eventos_log')) AS tamano_log,
  (SELECT count(*) FROM gps_eventos_log) AS filas_log,
  pg_size_pretty(pg_total_relation_size('gps_estado_actual')) AS tamano_estado;


-- ── BLOQUE 3 — Encoger gps_eventos_log ──────────────────────────────────────
-- OPCION A (NUCLEAR, INSTANTANEA, minimo I/O): vacia TODO el historial granular.
--   - NO toca gps_estado_actual (posiciones ACTUALES del mapa se conservan).
--   - NO toca counters ya sincronizados a 'activos'.
--   - Pierdes solo el rastro historico de posiciones. Operacion sigue normal.
--   Descomenta para usar:
--
-- TRUNCATE TABLE gps_eventos_log;
--
--
-- OPCION B (CONSERVA lo reciente, MAS I/O — usar solo si la DB respondio bien):
--   Borra eventos de mas de 2 dias. Si son millones, puede tardar/recolgar.
--
-- DELETE FROM gps_eventos_log WHERE ts_gps < now() - interval '2 days';
-- VACUUM (ANALYZE) gps_eventos_log;


-- ── BLOQUE 4 — Verificar que quedo chica ────────────────────────────────────
SELECT pg_size_pretty(pg_total_relation_size('gps_eventos_log')) AS tamano_log_final,
       (SELECT count(*) FROM gps_eventos_log) AS filas_final;
