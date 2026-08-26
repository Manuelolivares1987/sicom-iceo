-- ============================================================================
-- MIG423 · Un cero no es una lectura
-- ----------------------------------------------------------------------------
-- MIG422 descartó los ritmos imposibles con un tope de 24 h/día y destapó la
-- causa de fondo: 51 planes tienen `ultima_ejecucion_horas = 0` y 32 tienen
-- `ultima_ejecucion_km = 0`. No son lecturas: son el valor por defecto de la
-- siembra de abril. Ese plan nunca se ejecutó.
--
-- Tratar el cero como una lectura real hace que todo el uso de la vida del
-- equipo se cuente como consumido desde la última mantención. El DJKL-18 marca
-- 21.937 horas de horómetro; contra una base de 0 aparece «pasado por 21.437
-- horas» en un servicio de 500.
--
-- El tope de 24 h/día atrapaba a los más ruidosos, pero no a todos: el KCBY-30
-- pasaba con 23,3 h/día y −2.146 horas. Ese es exactamente el caso peligroso
-- que se anotó en MIG422 — el que queda apenas dentro de rango y pasa por
-- bueno. Se ataja por la causa y no por el síntoma.
--
-- ── LA REGLA ───────────────────────────────────────────────────────────────
-- Cero horas y cero kilómetros se leen como «no hay línea base». El plan cae al
-- calendario y queda en la lista de medidores por cuadrar. Cuando el mecánico
-- anote el horómetro al recibir el equipo (MIG397/399) y se cierre la primera
-- OT contra ese plan, la base queda buena sola (MIG420).
-- ============================================================================

BEGIN;

DROP VIEW IF EXISTS public.v_medidores_por_cuadrar;
DROP VIEW IF EXISTS public.v_plan_mantenimiento_estado;

CREATE VIEW public.v_plan_mantenimiento_estado AS
WITH base AS (
  SELECT pm.id AS plan_id, pm.activo_id, pm.nombre, pm.activo_plan,
         pm.frecuencia_dias, pm.frecuencia_horas, pm.frecuencia_km,
         pm.ultima_ejecucion_fecha::date AS ult_fecha,
         -- [MIG423] Un cero es el valor sembrado, no una lectura del horómetro.
         NULLIF(pm.ultima_ejecucion_horas, 0) AS ult_horas,
         NULLIF(pm.ultima_ejecucion_km, 0)    AS ult_km,
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
         -- [MIG422] Segundo candado: aunque haya base, un día tiene 24 horas.
         (r.h_dia_crudo  IS NOT NULL AND r.h_dia_crudo  > 24)   AS horometro_inconsistente,
         (r.km_dia_crudo IS NOT NULL AND r.km_dia_crudo > 2000) AS odometro_inconsistente,
         -- [MIG423] Sin línea base no se puede calcular por pauta. Es distinto
         -- de un dato inconsistente: acá simplemente nunca se anotó.
         (r.ult_horas IS NULL AND r.frecuencia_horas IS NOT NULL) AS sin_base_horas,
         (r.ult_km    IS NULL AND r.frecuencia_km    IS NOT NULL) AS sin_base_km
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
       sin_base_horas, sin_base_km,
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
  'MIG421/422/423: cuanto falta por horas, km y dias, y cual manda. Un cero de horas/km es la siembra de abril, no una lectura: sin linea base se cae al calendario.';

CREATE VIEW public.v_medidores_por_cuadrar AS
SELECT DISTINCT ON (e.activo_id)
       e.activo_id, e.patente,
       e.ult_fecha  AS ultima_mantencion,
       e.ult_horas  AS horas_anotadas_en_el_plan,
       e.horas_hoy  AS horas_del_equipo,
       e.ritmo_horas_descartado AS ritmo_imposible_h_dia,
       bool_or(e.sin_base_horas) OVER (PARTITION BY e.activo_id) AS falta_linea_base,
       bool_or(e.horometro_inconsistente OR e.odometro_inconsistente)
         OVER (PARTITION BY e.activo_id) AS medidor_inconsistente,
       count(*) OVER (PARTITION BY e.activo_id) AS planes_afectados
  FROM v_plan_mantenimiento_estado e
 WHERE e.horometro_inconsistente OR e.odometro_inconsistente
    OR e.sin_base_horas OR e.sin_base_km
 ORDER BY e.activo_id, e.ritmo_horas_descartado DESC NULLS LAST;

COMMENT ON VIEW public.v_medidores_por_cuadrar IS
  'MIG422/423: equipos sin linea base de horometro/odometro, o cuya lectura no cuadra con la fecha de su ultima mantencion. Hay que leerlo en terreno.';

UPDATE planes_mantenimiento pm
   SET proxima_ejecucion_fecha = CASE WHEN e.proxima_estimada = 'infinity'::date THEN NULL
                                      ELSE e.proxima_estimada END,
       updated_at = NOW()
  FROM v_plan_mantenimiento_estado e
 WHERE e.plan_id = pm.id
   AND pm.proxima_ejecucion_fecha IS DISTINCT FROM
       (CASE WHEN e.proxima_estimada = 'infinity'::date THEN NULL ELSE e.proxima_estimada END);

DO $r$
DECLARE r RECORD; v_sb INT; v_inc INT; v_eq INT; v_neg INT;
BEGIN
    SELECT count(*) FILTER (WHERE sin_base_horas OR sin_base_km),
           count(*) FILTER (WHERE horometro_inconsistente OR odometro_inconsistente),
           count(*) FILTER (WHERE horas_faltan < 0)
      INTO v_sb, v_inc, v_neg FROM v_plan_mantenimiento_estado;
    SELECT count(*) INTO v_eq FROM v_medidores_por_cuadrar;
    RAISE NOTICE 'Sin linea base: % planes | inconsistentes: % | equipos por cuadrar: % | con horas negativas: %',
        v_sb, v_inc, v_eq, v_neg;
    FOR r IN SELECT patente, left(nombre,32) AS nombre, horas_faltan, horas_por_dia, criterio, proxima_estimada
               FROM v_plan_mantenimiento_estado
              WHERE criterio = 'horas' ORDER BY proxima_estimada LIMIT 8
    LOOP
        RAISE NOTICE '  % % faltan % h a % h/dia -> %',
            rpad(r.patente,9), rpad(r.nombre,32), r.horas_faltan, r.horas_por_dia, r.proxima_estimada;
    END LOOP;
END
$r$;

COMMIT;
