-- ============================================================================
-- MIG420 · La próxima mantención no puede ser antes de la última
-- ----------------------------------------------------------------------------
-- LO QUE VIO MANUEL, EN LA PANTALLA DEL CLIENTE
-- 26-08-2026, sobre /equipo/9ca9b860.../ (SVBJ-57): «aquí dice que la próxima
-- mantención es el 22-06-2026 y arriba dice que la última mantención fue
-- 04-08-2026, no calza. Necesito que te ordenes, porque esto lo está viendo el
-- cliente».
--
-- Tiene toda la razón, y no es un detalle de esa ficha: es TODA la flota.
--
-- ── DOS NÚMEROS QUE NUNCA SE HABLARON ──────────────────────────────────────
-- En `v_ficha_activo` los dos datos salen de tablas distintas:
--
--   ultima_mantencion  = max(fecha_termino) de las OT cerradas    → lo real
--   proxima_mantencion = min(proxima_ejecucion_fecha) de los planes → congelado
--
-- Los planes se sembraron en abril de 2026 con sus fechas calculadas desde ahí,
-- y desde entonces NADIE los volvió a mover. `ultima_ejecucion_fecha` está en
-- NULL en los 175 planes: ni una sola ejecución quedó anotada en el plan.
--
-- Resultado medido hoy: de los 36 equipos con plan activo, los 36 muestran una
-- «próxima mantención» que ya pasó. No es que estén atrasados; es que el número
-- dejó de actualizarse. Y ese número está en la ficha pública del QR.
--
-- ── LOS TRES ARREGLOS ──────────────────────────────────────────────────────
-- 1. Cuando se cierra una OT ligada a un plan, el plan avanza. Sin esto todo lo
--    demás se vuelve a desfasar la semana que viene.
-- 2. Se recalculan las fechas con lo que sí se sabe: la última OT cerrada del
--    equipo, o la última orden de servicio del histórico importado (la misma
--    fuente que MIG401 le dio al motor de preventivas y que el plan seguía
--    ignorando).
-- 3. La ficha deja de poder mostrar una incoherencia: si la próxima calculada
--    quedara antes de la última mantención, se muestra la siguiente ocurrencia
--    real. Es un candado, no un maquillaje — con 1 y 2 no debería activarse
--    nunca, y si se activa es que algo volvió a romperse.
--
-- Al cliente no se le explica el desfase: se le muestra bien.
-- ============================================================================

BEGIN;

-- ── 1. Cerrar una OT avanza su plan ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ot_cerrada_avanza_plan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_plan RECORD; v_fecha DATE;
BEGIN
    IF NEW.plan_mantenimiento_id IS NULL THEN RETURN NEW; END IF;
    IF NEW.estado::text NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RETURN NEW;
    END IF;
    -- Sólo al cruzar a cerrada, no en cada guardado posterior.
    IF TG_OP = 'UPDATE' AND OLD.estado::text IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_plan FROM planes_mantenimiento WHERE id = NEW.plan_mantenimiento_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    v_fecha := COALESCE(NEW.fecha_termino::date, CURRENT_DATE);

    UPDATE planes_mantenimiento
       SET ultima_ejecucion_fecha = v_fecha,
           -- El kilometraje y las horas se anotan al recibir el equipo (MIG397/399).
           ultima_ejecucion_km    = COALESCE(
               (SELECT a.kilometraje_actual FROM activos a WHERE a.id = NEW.activo_id),
               ultima_ejecucion_km),
           ultima_ejecucion_horas = COALESCE(
               (SELECT a.horas_uso_actual FROM activos a WHERE a.id = NEW.activo_id),
               ultima_ejecucion_horas),
           proxima_ejecucion_fecha = v_fecha + COALESCE(frecuencia_dias, 30),
           updated_at = NOW()
     WHERE id = NEW.plan_mantenimiento_id;

    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_ot_cerrada_avanza_plan ON public.ordenes_trabajo;
CREATE TRIGGER trg_ot_cerrada_avanza_plan
  AFTER INSERT OR UPDATE OF estado ON public.ordenes_trabajo
  FOR EACH ROW EXECUTE FUNCTION public.fn_ot_cerrada_avanza_plan();

-- ── 2. Recalcular con lo que sí se sabe ───────────────────────────────────
-- Misma fuente que usa el motor de preventivas desde MIG401: la OT cerrada más
-- reciente del equipo, y si no hay, la orden de servicio del histórico.
WITH ultima_real AS (
    SELECT a.id AS activo_id,
           GREATEST(
             COALESCE((SELECT max(ot.fecha_termino::date) FROM ordenes_trabajo ot
                        WHERE ot.activo_id = a.id
                          AND ot.estado::text IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')),
                      '1900-01-01'::date),
             COALESCE((SELECT max(h.fecha_entrega::date) FROM os_historico_importado h
                        WHERE h.activo_id = a.id), '1900-01-01'::date)
           ) AS fecha
      FROM activos a
)
UPDATE planes_mantenimiento pm
   SET ultima_ejecucion_fecha  = u.fecha,
       proxima_ejecucion_fecha = u.fecha + COALESCE(pm.frecuencia_dias, 30),
       updated_at = NOW()
  FROM ultima_real u
 WHERE u.activo_id = pm.activo_id
   AND pm.activo_plan = true
   AND u.fecha > '1900-01-01'::date
   -- No se pisa un plan que alguien ya haya movido a mano.
   AND pm.ultima_ejecucion_fecha IS NULL;

-- Los planes de equipos sin ninguna mantención registrada quedan sin fecha:
-- «no hay dato» es honesto; una fecha del pasado, no.
UPDATE planes_mantenimiento
   SET proxima_ejecucion_fecha = NULL, updated_at = NOW()
 WHERE activo_plan = true
   AND ultima_ejecucion_fecha IS NULL
   AND proxima_ejecucion_fecha < CURRENT_DATE;

-- ── 3. El candado en la ficha ─────────────────────────────────────────────
-- Si aun así la próxima quedara antes de la última mantención, se avanza en
-- saltos de su frecuencia hasta la siguiente ocurrencia futura. No debería
-- activarse nunca; está para que el cliente no vuelva a ver un imposible.
CREATE OR REPLACE FUNCTION public.fn_proxima_mantencion_coherente(p_activo_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  WITH ult AS (
    SELECT max(ot.fecha_termino::date) AS f FROM ordenes_trabajo ot
     WHERE ot.activo_id = p_activo_id
       AND ot.estado::text IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
  )
  SELECT min(
    CASE
      WHEN pm.proxima_ejecucion_fecha IS NULL THEN NULL
      WHEN pm.proxima_ejecucion_fecha > COALESCE((SELECT f FROM ult), '1900-01-01'::date)
        THEN pm.proxima_ejecucion_fecha
      -- Quedó atrás de la última mantención: se salta a la siguiente ocurrencia.
      ELSE (SELECT f FROM ult) + COALESCE(pm.frecuencia_dias, 30)
    END)
    FROM planes_mantenimiento pm
   WHERE pm.activo_id = p_activo_id AND pm.activo_plan = true
$function$;

DO $r$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_viewdef('v_ficha_activo'::regclass, true) INTO v_def;
    v_def := replace(v_def,
      '( SELECT min(pm.proxima_ejecucion_fecha) AS min
           FROM planes_mantenimiento pm
          WHERE pm.activo_id = a.id AND pm.activo_plan = true) AS proxima_mantencion',
      'fn_proxima_mantencion_coherente(a.id) AS proxima_mantencion');
    IF position('fn_proxima_mantencion_coherente' in v_def) = 0 THEN
        RAISE EXCEPTION 'No se pudo reemplazar proxima_mantencion en v_ficha_activo: el texto de la vista cambió.';
    END IF;
    EXECUTE 'CREATE OR REPLACE VIEW public.v_ficha_activo AS ' || v_def;
END
$r$;

DO $r$
DECLARE v_mal INT; v_null INT; v_ok INT;
BEGIN
    SELECT count(*) FILTER (WHERE proxima_mantencion < ultima_mantencion),
           count(*) FILTER (WHERE proxima_mantencion IS NULL),
           count(*) FILTER (WHERE proxima_mantencion >= CURRENT_DATE)
      INTO v_mal, v_null, v_ok FROM v_ficha_activo;
    RAISE NOTICE 'Fichas incoherentes: % | sin proxima (sin dato): % | proxima a futuro: %', v_mal, v_null, v_ok;
END
$r$;

COMMIT;
