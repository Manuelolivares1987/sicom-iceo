-- ============================================================================
-- MIG482 · Las sugerencias de GPS no las generaba nadie
-- ============================================================================
--
-- LO QUE DIJO MANUEL
-- 01-09-2026: «los estados de flota vienen de sugerencia GPS».
--
-- LO QUE ENCONTRÉ
-- Así está diseñado y así funciona la pantalla: el planificador entra a
-- /dashboard/flota/sugerencias, mira lo que el GPS propone y valida. Lo que no
-- existía era el paso anterior. `fn_evaluar_activos_fuera_geocerca()` —la
-- función que compara la posición contra la geocerca del contrato y propone el
-- cambio de estado— NO TENÍA CRON. Nadie la llamaba nunca.
--
-- Resultado: `cambios_estado_sugeridos` estaba en CERO filas históricas. La
-- pantalla del planificador llevaba meses mostrando una bandeja vacía, así que
-- el estado diario se cargaba enteramente a mano: los 55 equipos de cada día de
-- agosto vienen con override_manual = true y calculado_auto = 0. El GPS estaba
-- ahí, midiendo, sin que nadie leyera lo que decía.
--
-- Al ejecutarla una vez a mano salieron 10 sugerencias. Y dicen algo incómodo:
-- ocho equipos llevan entre 4 y 76 DÍAS fuera de su geocerca. Eso no es
-- «tránsito autorizado» —es que la geocerca del contrato ya no corresponde a
-- dónde está trabajando el equipo—. Por eso esto se propone y no se aplica: el
-- primer barrido no es una lista de cambios de estado, es una lista de
-- geocercas que hay que revisar.
--
-- LA FRECUENCIA
-- Una vez al día, a las 07:00 de Chile. No cada hora: en mayo un cron de GPS
-- cada 60 segundos se comió el presupuesto de I/O del tier Micro y tumbó la
-- base (ver prevencion-db-salud.sql). El estado de un camión no cambia tan
-- rápido como para justificar ese riesgo, y el planificador revisa la bandeja
-- una vez en la mañana.
--
-- LO QUE NO HACE ESTA MIGRACIÓN
-- No activa `flota_estados_diarios`. Ese cron aplica estados automáticos sobre
-- todos los activos, y hoy el estado diario lo decide el planificador —así lo
-- dejó MIG307: el estado lo manda el planificador, `activos.estado` es
-- derivado—. Encender eso es una decisión de operación, no de mantención.
-- ============================================================================

BEGIN;

-- ── 1 · Alguien que llame a la función ──────────────────────────────────────
SELECT cron.unschedule('gps-sugerencias-estado')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gps-sugerencias-estado');

SELECT cron.schedule(
    'gps-sugerencias-estado',
    '0 11 * * *',   -- 07:00 en Chile
    $cron$ SELECT fn_evaluar_activos_fuera_geocerca(); $cron$
);

-- ── 2 · Que la bandeja se pueda leer por fecha ──────────────────────────────
--
-- La retención de esta tabla queda para la rutina que ya existe
-- (prevencion-db-salud.sql): borrar filas de producción es una decisión que se
-- toma aparte, no de paso en una migración que enciende un cron.
CREATE INDEX IF NOT EXISTS idx_cambios_estado_sug_generado
    ON cambios_estado_sugeridos (generado_at DESC);

COMMENT ON TABLE cambios_estado_sugeridos IS
    'Lo que el GPS propone y el planificador valida. Lo llena el cron '
    'gps-sugerencias-estado (diario, 07:00 Chile) llamando a '
    'fn_evaluar_activos_fuera_geocerca. Nada de acá cambia un estado solo.';

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_cron INT; v_pend INT; v_viejas INT;
BEGIN
    SELECT count(*) INTO v_cron FROM cron.job
     WHERE jobname = 'gps-sugerencias-estado' AND active;
    SELECT count(*) INTO v_pend FROM cambios_estado_sugeridos WHERE validado_at IS NULL;
    SELECT count(*) INTO v_viejas FROM cambios_estado_sugeridos
     WHERE validado_at IS NULL AND minutos_fuera > 4 * 24 * 60;
    RAISE NOTICE 'cron activo: % · sugerencias por validar: % · de ellas con más de 4 días fuera: %',
                 v_cron, v_pend, v_viejas;
END $mig$;

COMMIT;
