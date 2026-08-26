-- ============================================================================
-- MIG421 · La pauta manda por horas, no por calendario
-- ----------------------------------------------------------------------------
-- LO QUE CORRIGIÓ MANUEL
-- 26-08-2026: «pero ojo, si subió el 04/08/2026 la próxima debe ser en las
-- próximas 300 horas ¿o no?».
--
-- Sí. MIG420 dejó las fechas coherentes entre sí, pero calculó la próxima
-- mantención sumando `frecuencia_dias` — el criterio que menos manda en un
-- camión. Las pautas Volvo están escritas con tres: «250h / 30 días / 12.500
-- km», y vale el que llegue primero. Usar sólo el calendario es cómodo y es
-- justamente lo que hace que una máquina llegue pasada de horas al taller.
--
-- ── EL CASO QUE LO DESTAPÓ ─────────────────────────────────────────────────
-- SVBJ-57, servicio L1 del 04-08-2026:
--
--                al servicio      hoy        consumido   pauta      falta
--   horómetro      1.862,4 h    2.104,9 h     242,5 h     250 h      7,5 h
--   kilómetros     21.240       23.133      1.893 km   12.500 km   10.607 km
--   días                —          22            22        30 d       8 d
--
-- Va a 11 horas por día. Las 7,5 horas que le quedan las quema mañana, y el
-- sistema mostraba 03-09: nueve días de más sobre un servicio de lubricación.
--
-- ── CÓMO SE CALCULA AHORA ──────────────────────────────────────────────────
-- Para cada plan se mira lo que falta por los tres criterios y manda el que
-- llegue primero. Para pasar horas y kilómetros a una fecha se usa el ritmo
-- MEDIDO de ese equipo desde su última mantención —(horas de hoy menos horas
-- del servicio) partido por los días transcurridos—, no un promedio de flota.
-- Es el dato más honesto disponible: sale de los medidores que el mecánico
-- anota al recibir (MIG397/399).
--
-- Cuando no hay ritmo que medir (equipo sin lecturas, o recién intervenido) se
-- cae al calendario, que es lo que había. Nunca se inventa un ritmo.
--
-- `v_plan_mantenimiento_estado` deja a la vista qué criterio manda y cuánto
-- falta, para que en el taller se pueda discutir el número en vez de creerle.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_plan_mantenimiento_estado AS
WITH base AS (
  SELECT pm.id AS plan_id, pm.activo_id, pm.nombre, pm.activo_plan,
         pm.frecuencia_dias, pm.frecuencia_horas, pm.frecuencia_km,
         pm.ultima_ejecucion_fecha::date AS ult_fecha,
         pm.ultima_ejecucion_horas AS ult_horas,
         pm.ultima_ejecucion_km    AS ult_km,
         a.horas_uso_actual        AS horas_hoy,
         a.kilometraje_actual      AS km_hoy,
         COALESCE(a.patente, a.codigo) AS patente,
         GREATEST(CURRENT_DATE - pm.ultima_ejecucion_fecha::date, 0) AS dias_corridos
    FROM planes_mantenimiento pm
    JOIN activos a ON a.id = pm.activo_id
   WHERE pm.activo_plan = true
), ritmo AS (
  SELECT b.*,
         -- Ritmo medido de ESTE equipo desde su última mantención. Se exige al
         -- menos un día y consumo positivo: con menos, el cociente se dispara.
         CASE WHEN b.dias_corridos >= 1 AND b.ult_horas IS NOT NULL
                   AND b.horas_hoy > b.ult_horas
              THEN (b.horas_hoy - b.ult_horas) / b.dias_corridos END AS horas_por_dia,
         CASE WHEN b.dias_corridos >= 1 AND b.ult_km IS NOT NULL
                   AND b.km_hoy > b.ult_km
              THEN (b.km_hoy - b.ult_km) / b.dias_corridos END AS km_por_dia
    FROM base b
), faltantes AS (
  SELECT r.*,
         CASE WHEN r.frecuencia_horas IS NOT NULL AND r.ult_horas IS NOT NULL AND r.horas_hoy IS NOT NULL
              THEN r.frecuencia_horas - (r.horas_hoy - r.ult_horas) END AS horas_faltan,
         CASE WHEN r.frecuencia_km IS NOT NULL AND r.ult_km IS NOT NULL AND r.km_hoy IS NOT NULL
              THEN r.frecuencia_km - (r.km_hoy - r.ult_km) END AS km_faltan,
         CASE WHEN r.frecuencia_dias IS NOT NULL AND r.ult_fecha IS NOT NULL
              THEN (r.ult_fecha + r.frecuencia_dias) - CURRENT_DATE END AS dias_faltan
    FROM ritmo r
), fechas AS (
  SELECT f.*,
         CASE WHEN f.horas_faltan IS NOT NULL AND f.horas_por_dia > 0
              THEN CURRENT_DATE + GREATEST(ceil(f.horas_faltan / f.horas_por_dia), 0)::INT END AS fecha_por_horas,
         CASE WHEN f.km_faltan IS NOT NULL AND f.km_por_dia > 0
              THEN CURRENT_DATE + GREATEST(ceil(f.km_faltan / f.km_por_dia), 0)::INT END AS fecha_por_km,
         CASE WHEN f.ult_fecha IS NOT NULL AND f.frecuencia_dias IS NOT NULL
              THEN f.ult_fecha + f.frecuencia_dias END AS fecha_por_dias
    FROM faltantes f
)
SELECT plan_id, activo_id, patente, nombre,
       frecuencia_dias, frecuencia_horas, frecuencia_km,
       ult_fecha, ult_horas, ult_km, horas_hoy, km_hoy,
       round(horas_por_dia, 2) AS horas_por_dia,
       round(km_por_dia, 1)    AS km_por_dia,
       round(horas_faltan, 1)  AS horas_faltan,
       round(km_faltan, 1)     AS km_faltan,
       dias_faltan,
       fecha_por_horas, fecha_por_km, fecha_por_dias,
       LEAST(COALESCE(fecha_por_horas, 'infinity'::date),
             COALESCE(fecha_por_km,    'infinity'::date),
             COALESCE(fecha_por_dias,  'infinity'::date)) AS proxima_estimada,
       -- Qué criterio manda. Sirve para explicarlo en el taller: no es lo mismo
       -- «vence el martes» que «le quedan 7 horas de motor».
       CASE
         WHEN LEAST(COALESCE(fecha_por_horas,'infinity'::date),
                    COALESCE(fecha_por_km,'infinity'::date),
                    COALESCE(fecha_por_dias,'infinity'::date)) = 'infinity'::date THEN NULL
         WHEN fecha_por_horas IS NOT NULL
              AND fecha_por_horas <= LEAST(COALESCE(fecha_por_km,'infinity'::date),
                                           COALESCE(fecha_por_dias,'infinity'::date)) THEN 'horas'
         WHEN fecha_por_km IS NOT NULL
              AND fecha_por_km <= COALESCE(fecha_por_dias,'infinity'::date) THEN 'km'
         ELSE 'dias'
       END AS criterio
  FROM fechas;

COMMENT ON VIEW public.v_plan_mantenimiento_estado IS
  'MIG421: cuanto falta para cada plan por horas, km y dias, y cual de los tres manda. El ritmo es el medido de ese equipo desde su ultima mantencion.';

-- ── La ficha usa el criterio que manda ────────────────────────────────────
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
      WHEN e.proxima_estimada = 'infinity'::date THEN NULL
      -- Ya pasado su punto: la próxima es ahora, no una fecha del pasado.
      WHEN e.proxima_estimada < CURRENT_DATE THEN CURRENT_DATE
      WHEN e.proxima_estimada > COALESCE((SELECT f FROM ult), '1900-01-01'::date)
        THEN e.proxima_estimada
      ELSE CURRENT_DATE
    END)
    FROM v_plan_mantenimiento_estado e
   WHERE e.activo_id = p_activo_id
$function$;

-- ── Y `proxima_ejecucion_fecha` deja de mirar sólo el calendario ──────────
UPDATE planes_mantenimiento pm
   SET proxima_ejecucion_fecha = e.proxima_estimada,
       updated_at = NOW()
  FROM v_plan_mantenimiento_estado e
 WHERE e.plan_id = pm.id
   AND e.proxima_estimada <> 'infinity'::date
   AND pm.proxima_ejecucion_fecha IS DISTINCT FROM e.proxima_estimada;

-- El trigger de cierre de OT tiene que dejar anotado el medidor, que es lo que
-- hace posible todo lo anterior. Ya lo hacía (MIG420); acá sólo se documenta
-- que ese dato es el que sostiene el cálculo por horas.
COMMENT ON FUNCTION public.fn_ot_cerrada_avanza_plan() IS
  'MIG420/421: al cerrar la OT anota fecha, km y horas del servicio. Las horas son las que permiten calcular la proxima por pauta y no por calendario.';

DO $r$
DECLARE r RECORD; v_h INT; v_k INT; v_d INT;
BEGIN
    SELECT count(*) FILTER (WHERE criterio='horas'), count(*) FILTER (WHERE criterio='km'),
           count(*) FILTER (WHERE criterio='dias')
      INTO v_h, v_k, v_d FROM v_plan_mantenimiento_estado;
    RAISE NOTICE 'Planes que manda: horas=% km=% dias=%', v_h, v_k, v_d;
    FOR r IN
        SELECT nombre, horas_faltan, km_faltan, dias_faltan, horas_por_dia, criterio, proxima_estimada
          FROM v_plan_mantenimiento_estado WHERE patente='SVBJ-57' ORDER BY proxima_estimada LIMIT 3
    LOOP
        RAISE NOTICE '  % | faltan %h / %km / %d | ritmo %h/dia | manda % -> %',
            left(r.nombre,38), r.horas_faltan, r.km_faltan, r.dias_faltan, r.horas_por_dia, r.criterio, r.proxima_estimada;
    END LOOP;
END
$r$;

COMMIT;
