-- ============================================================================
-- MIG422 · Un día tiene 24 horas
-- ----------------------------------------------------------------------------
-- Al revisar el resultado de MIG421 salió esto:
--
--   DJKL-18  Filtros de aire y combustible   faltan -21437 h   a 162,5 h/día
--   FSLZ-67  Filtros de aire y combustible   faltan -15249 h   a 116,7 h/día
--   KCBY-31  Filtros de aire y combustible   faltan  -8146 h   a  64,1 h/día
--
-- 162 horas por día. El error es mío y es de MIG420: al recalcular las fechas
-- puse `ultima_ejecucion_fecha` con la última mantención real, pero NO toqué
-- `ultima_ejecucion_horas`, que seguía con la lectura sembrada en abril. MIG421
-- entonces compara el horómetro de hoy contra una lectura de abril sobre una
-- fecha de agosto: horas de cuatro meses repartidas en veintidós días.
--
-- El número era absurdo y por eso se cachó al mirarlo. Los peligrosos son los
-- que quedan apenas fuera de rango y pasan por buenos.
--
-- ── LA REGLA ───────────────────────────────────────────────────────────────
-- Si el consumo implica más de 24 horas por día, la línea base no corresponde
-- al servicio que dice la fecha. No se ajusta ni se estima: el criterio de
-- horas se descarta para ese plan, se cae al calendario, y el plan queda
-- marcado para que alguien lea el horómetro y lo cuadre.
--
-- Descartar el dato malo importa más que rellenarlo. Un plan que dice «faltan
-- 8 días» cuando no se sabe es honesto; uno que dice «pasado por 21.437 horas»
-- no se puede ni discutir.
--
-- Lo mismo con los kilómetros: 2.000 km/día no los hace un camión de faena.
-- ============================================================================

BEGIN;

-- Se agregan columnas en medio, así que CREATE OR REPLACE no basta:
-- Postgres no deja renombrar columnas de una vista existente.
DROP VIEW IF EXISTS public.v_medidores_por_cuadrar;
DROP VIEW IF EXISTS public.v_plan_mantenimiento_estado;

CREATE VIEW public.v_plan_mantenimiento_estado AS
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
         CASE WHEN b.dias_corridos >= 1 AND b.ult_horas IS NOT NULL AND b.horas_hoy > b.ult_horas
              THEN (b.horas_hoy - b.ult_horas) / b.dias_corridos END AS h_dia_crudo,
         CASE WHEN b.dias_corridos >= 1 AND b.ult_km IS NOT NULL AND b.km_hoy > b.ult_km
              THEN (b.km_hoy - b.ult_km) / b.dias_corridos END AS km_dia_crudo
    FROM base b
), sanidad AS (
  SELECT r.*,
         -- [MIG422] Un día tiene 24 horas. Por encima de eso la línea base no
         -- corresponde al servicio que dice la fecha: el dato no sirve.
         (r.h_dia_crudo  IS NOT NULL AND r.h_dia_crudo  > 24)    AS horometro_inconsistente,
         -- 2.000 km/día no los hace un camión de faena.
         (r.km_dia_crudo IS NOT NULL AND r.km_dia_crudo > 2000)  AS odometro_inconsistente
    FROM ritmo r
), limpio AS (
  SELECT s.*,
         CASE WHEN s.horometro_inconsistente THEN NULL ELSE s.h_dia_crudo  END AS horas_por_dia,
         CASE WHEN s.odometro_inconsistente  THEN NULL ELSE s.km_dia_crudo END AS km_por_dia
    FROM sanidad s
), faltantes AS (
  SELECT l.*,
         CASE WHEN NOT l.horometro_inconsistente AND l.frecuencia_horas IS NOT NULL
                   AND l.ult_horas IS NOT NULL AND l.horas_hoy IS NOT NULL
              THEN l.frecuencia_horas - (l.horas_hoy - l.ult_horas) END AS horas_faltan,
         CASE WHEN NOT l.odometro_inconsistente AND l.frecuencia_km IS NOT NULL
                   AND l.ult_km IS NOT NULL AND l.km_hoy IS NOT NULL
              THEN l.frecuencia_km - (l.km_hoy - l.ult_km) END AS km_faltan,
         CASE WHEN l.frecuencia_dias IS NOT NULL AND l.ult_fecha IS NOT NULL
              THEN (l.ult_fecha + l.frecuencia_dias) - CURRENT_DATE END AS dias_faltan
    FROM limpio l
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
       horometro_inconsistente, odometro_inconsistente,
       round(h_dia_crudo, 1)   AS ritmo_horas_descartado,
       fecha_por_horas, fecha_por_km, fecha_por_dias,
       LEAST(COALESCE(fecha_por_horas, 'infinity'::date),
             COALESCE(fecha_por_km,    'infinity'::date),
             COALESCE(fecha_por_dias,  'infinity'::date)) AS proxima_estimada,
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
  'MIG421/422: cuanto falta por horas, km y dias, y cual manda. El ritmo se descarta si implica mas de 24 h/dia o 2000 km/dia: eso significa que la linea base no corresponde al servicio.';

-- ── Rehacer las fechas ya sin los ritmos imposibles ───────────────────────
UPDATE planes_mantenimiento pm
   SET proxima_ejecucion_fecha = CASE WHEN e.proxima_estimada = 'infinity'::date THEN NULL
                                      ELSE e.proxima_estimada END,
       updated_at = NOW()
  FROM v_plan_mantenimiento_estado e
 WHERE e.plan_id = pm.id
   AND pm.proxima_ejecucion_fecha IS DISTINCT FROM
       (CASE WHEN e.proxima_estimada = 'infinity'::date THEN NULL ELSE e.proxima_estimada END);

-- ── Lo que hay que ir a leer ──────────────────────────────────────────────
-- Un plan con la línea base descuadrada no se arregla con SQL: hay que ir al
-- equipo, leer el horómetro y anotar contra qué servicio corresponde.
CREATE VIEW public.v_medidores_por_cuadrar AS
SELECT DISTINCT ON (e.activo_id)
       e.activo_id, e.patente,
       e.ult_fecha  AS ultima_mantencion,
       e.ult_horas  AS horas_anotadas_en_el_plan,
       e.horas_hoy  AS horas_del_equipo,
       e.ritmo_horas_descartado AS ritmo_imposible_h_dia,
       count(*) OVER (PARTITION BY e.activo_id) AS planes_afectados
  FROM v_plan_mantenimiento_estado e
 WHERE e.horometro_inconsistente OR e.odometro_inconsistente
 ORDER BY e.activo_id, e.ritmo_horas_descartado DESC NULLS LAST;

COMMENT ON VIEW public.v_medidores_por_cuadrar IS
  'MIG422: equipos cuyo horometro/odometro no cuadra con la fecha de su ultima mantencion. Hay que leerlo en terreno.';

DO $r$
DECLARE r RECORD; v_bad INT; v_eq INT;
BEGIN
    SELECT count(*) INTO v_bad FROM v_plan_mantenimiento_estado
     WHERE horometro_inconsistente OR odometro_inconsistente;
    SELECT count(*) INTO v_eq FROM v_medidores_por_cuadrar;
    RAISE NOTICE 'Ritmos imposibles descartados: % planes en % equipos', v_bad, v_eq;
    FOR r IN SELECT patente, ritmo_imposible_h_dia, horas_anotadas_en_el_plan, horas_del_equipo,
                    ultima_mantencion, planes_afectados
               FROM v_medidores_por_cuadrar ORDER BY ritmo_imposible_h_dia DESC NULLS LAST LIMIT 8
    LOOP
        RAISE NOTICE '  % : plan dice % h, equipo marca % h, ult. mant. % -> daba % h/dia (% planes)',
            rpad(r.patente,9), r.horas_anotadas_en_el_plan, r.horas_del_equipo,
            r.ultima_mantencion, r.ritmo_imposible_h_dia, r.planes_afectados;
    END LOOP;
    RAISE NOTICE '---';
    FOR r IN SELECT patente, left(nombre,30) AS nombre, horas_faltan, horas_por_dia, criterio, proxima_estimada
               FROM v_plan_mantenimiento_estado
              WHERE criterio='horas' AND proxima_estimada <= CURRENT_DATE + 10
              ORDER BY proxima_estimada LIMIT 6
    LOOP
        RAISE NOTICE '  URGENTE % % : faltan % h a % h/dia -> %',
            rpad(r.patente,9), rpad(r.nombre,30), r.horas_faltan, r.horas_por_dia, r.proxima_estimada;
    END LOOP;
END
$r$;

COMMIT;
