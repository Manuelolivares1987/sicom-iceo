-- ============================================================================
-- MIG662 · Tarjeta Aramco: alertas sin el ruido del odómetro diario y de los viajes
-- ----------------------------------------------------------------------------
-- Revisión de octubre-2026 (Manuel, 28-10): las 12 cargas con alerta eran ruido.
--
-- 1. «Rendimiento muy bajo» por tramo: el GPS manda el odómetro UNA vez al día.
--    Si se carga en la tarde, los km de ese día caen en el tramo siguiente:
--    SPRY-28 dio 4,0 km/L y luego 33 km/L (su mes: 11,2 vs normal 11,5).
--    Ventanas de 2 o 3 tramos tampoco sirven en viajes largos (500 km/día).
--    Ahora la regla es física y no depende de la hora de la carga: en los
--    30 días que terminan en la carga, lo cargado NO puede superar lo gastado
--    andando (km GPS ÷ km/L normal del vehículo, +20 %) más un estanque
--    completo (la diferencia de nivel nunca pasa de su capacidad). Si lo
--    supera, hay litros que no fueron al motor de ese vehículo. La ventana
--    empieza cuando el vehículo ya tenía km GPS y exige 20 días. El km/L de cada tramo se sigue mostrando, pero
--    ya no alerta solo.
--
-- 2. «Dos o más cargas el mismo día»: casi siempre son viajes (KVDK-21
--    Coquimbo↔Copiapó). Queda como dato (gris en la pantalla). La alerta nueva
--    «litros_dia_excede» salta solo si lo cargado en el día supera lo que cabe
--    en el estanque MÁS lo que gastó andando ese día (km GPS del día ÷ km/L
--    normal, con 30 % de holgura). Se marca en la última carga del día.
--
-- 3. Capacidad real del estanque en la ficha (activos.capacidad_estanque_l).
--    «Más litros de los que caben» usa la capacidad + 10 % (cuello de llenado).
--    Sin dato: 80 L camioneta/furgón, 450 L camión. Valores de fábrica:
--    Nissan NP300 80 L, Toyota Hilux 80 L, Maxus T60 80 L, Citroën Berlingo
--    K9 50 L (las cargas máximas reales: 63, 62, 67 y 51 L).
--
-- Las columnas nuevas de la vista van al final (CREATE OR REPLACE VIEW lo exige;
-- v_combustible_rendimiento_mes depende de esta vista y no cambia).
-- ============================================================================

ALTER TABLE public.activos ADD COLUMN IF NOT EXISTS capacidad_estanque_l NUMERIC
    CHECK (capacidad_estanque_l IS NULL OR capacidad_estanque_l > 0);
COMMENT ON COLUMN public.activos.capacidad_estanque_l IS
    'Litros del estanque de combustible del vehículo (fábrica). Lo usa la alerta de la tarjeta Aramco (MIG662).';

UPDATE public.activos a SET capacidad_estanque_l = v.l
  FROM (VALUES ('NP300', 80), ('Hilux', 80), ('T60', 80), ('Berlingo', 50)) v(modelo, l),
       public.modelos m
 WHERE m.id = a.modelo_id AND m.nombre ILIKE '%' || v.modelo || '%'
   AND a.tipo_equipamiento::text = 'camioneta' AND a.capacidad_estanque_l IS NULL;

CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas AS
WITH c AS (
    SELECT c.*, coalesce(a.patente, c.patente) AS patente_ver, a.tipo::text AS tipo_sicom,
           CASE WHEN a.tipo_equipamiento::text = 'aljibe_combustible' THEN 'abastecimiento' ELSE 'flota' END AS grupo,
           EXISTS (SELECT 1 FROM gps_activo_mapeo g WHERE g.activo_id = c.activo_id) AS tiene_gps,
           o.km_fin AS odometro_gps, o.fecha AS odometro_fecha,
           -- [MIG662] capacidad del estanque y km GPS del día de la carga
           coalesce(a.capacidad_estanque_l,
                    CASE WHEN c.tipo_vehiculo ILIKE 'camioneta%' THEN 80
                         WHEN c.tipo_vehiculo ILIKE 'cami%' THEN 450 ELSE 80 END) AS capacidad_l,
           hd.km AS km_dia, w30.km AS km_30d, w30.dias AS dias_gps_30d, l30.litros AS litros_30d
      FROM combustible_tarjeta_cargas c
      LEFT JOIN activos a ON a.id = c.activo_id
      -- [MIG660] Fuera del análisis (p. ej. la camioneta de gerencia).
      LEFT JOIN combustible_tarjeta_excluidas x ON x.patente = c.patente
      LEFT JOIN LATERAL (
            SELECT h.km_fin, h.fecha FROM activo_horas_dia h
             WHERE h.activo_id = c.activo_id AND h.fecha < c.fecha_hora::date AND h.km_fin > 0
             ORDER BY h.fecha DESC LIMIT 1) o ON c.activo_id IS NOT NULL
      LEFT JOIN v_activo_horas_dia hd ON hd.activo_id = c.activo_id AND hd.fecha = c.fecha_hora::date
      -- [MIG662] ventana de 30 días, pero nunca antes de que el vehículo tuviera km GPS
      -- (si no, se suman cargas de días sin km y todo parece «sin explicar»).
      LEFT JOIN LATERAL (
            SELECT greatest(c.fecha_hora::date - 29, min(h.fecha)) AS desde
              FROM activo_horas_dia h WHERE h.activo_id = c.activo_id AND h.km_fin > 0) g ON c.activo_id IS NOT NULL
      LEFT JOIN LATERAL (
            SELECT sum(d.km) AS km, (c.fecha_hora::date - g.desde + 1) AS dias FROM v_activo_horas_dia d
             WHERE d.activo_id = c.activo_id
               AND d.fecha >= g.desde AND d.fecha <= c.fecha_hora::date) w30 ON g.desde IS NOT NULL
      LEFT JOIN LATERAL (
            SELECT sum(c2.litros) AS litros FROM combustible_tarjeta_cargas c2
             WHERE c2.patente = c.patente AND c2.fecha_hora::date >= g.desde AND c2.fecha_hora <= c.fecha_hora) l30
             ON g.desde IS NOT NULL
     WHERE x.patente IS NULL
), t AS (
    SELECT c.*,
           CASE WHEN c.odometro_fecha >= c.fecha_hora::date - 3 THEN c.odometro_gps END AS odo,
           count(*) OVER (PARTITION BY c.patente, c.fecha_hora::date) AS cargas_dia,
           sum(c.litros) OVER (PARTITION BY c.patente, c.fecha_hora::date) AS litros_dia,
           row_number() OVER (PARTITION BY c.patente, c.fecha_hora::date ORDER BY c.fecha_hora DESC) AS ultima_del_dia
      FROM c
), k AS (
    SELECT t.*,
           t.odo - lag(t.odo) OVER (PARTITION BY t.patente ORDER BY t.fecha_hora) AS km_bruto,
           lag(t.fecha_hora) OVER (PARTITION BY t.patente ORDER BY t.fecha_hora) AS carga_anterior
      FROM t
), k2 AS (
    SELECT k.*,
           CASE WHEN k.km_bruto BETWEEN 0 AND 5000 THEN round(k.km_bruto) END AS km_tramo
      FROM k
), r AS (
    SELECT k2.*,
           CASE WHEN k2.km_tramo > 0 AND k2.litros > 0 THEN round(k2.km_tramo / k2.litros, 1) END AS km_l_tramo
      FROM k2
), est AS (
    SELECT estacion, count(*) AS n,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY gps_lat) AS lat,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY gps_lng) AS lng
      FROM combustible_tarjeta_cargas WHERE gps_lat IS NOT NULL GROUP BY estacion
), med AS (
    SELECT patente, count(*) AS n, percentile_cont(0.5) WITHIN GROUP (ORDER BY km_l_tramo) AS km_l
      FROM r WHERE km_l_tramo IS NOT NULL GROUP BY patente
), r2 AS (   -- [MIG662] litros que no explican ni los km de 30 días ni un estanque completo
    SELECT r.*, med.n AS med_n, med.km_l AS med_km_l,
           CASE WHEN r.grupo = 'flota' AND med.n >= 4 AND r.dias_gps_30d >= 20 AND med.km_l > 0
                THEN r.litros_30d - (r.km_30d / med.km_l * 1.2 + r.capacidad_l * 1.1) END AS litros_sin_explicar_30d
      FROM r LEFT JOIN med ON med.patente = r.patente
)
SELECT r.id, r.importacion_id, r.cod_autorizacion, r.fecha_hora, r.patente, r.patente_ver,
       r.activo_id, r.tipo_vehiculo, r.tiene_gps, r.producto, r.estacion, r.comuna, r.tarjeta,
       r.rut_chofer, r.litros, r.pizarra_l, r.total_pago, r.guia_despacho,
       r.gps_lat, r.gps_lng, r.gps_dif_min, r.odo AS odometro_gps, r.carga_anterior, r.km_tramo, r.km_l_tramo,
       round(r.med_km_l::numeric, 1) AS km_l_mediana,
       CASE WHEN est.n >= 3 AND r.gps_lat IS NOT NULL
            THEN round(public.fn_distancia_haversine(r.gps_lat, r.gps_lng, est.lat::numeric, est.lng::numeric) / 1000, 1) END
            AS dist_estacion_km,
       array_remove(ARRAY[
           CASE WHEN r.activo_id IS NULL THEN 'sin_ficha' END,
           CASE WHEN r.activo_id IS NOT NULL AND NOT r.tiene_gps THEN 'sin_gps' END,
           CASE WHEN est.n >= 3 AND r.gps_lat IS NOT NULL
                 -- metros; la lectura GPS puede estar hasta 90 min de la carga: se toleran
                 -- 5 km + 1,2 km por minuto de diferencia (un vehículo a ~70 km/h).
                 AND public.fn_distancia_haversine(r.gps_lat, r.gps_lng, est.lat::numeric, est.lng::numeric)
                     > (5 + 1.2 * coalesce(r.gps_dif_min, 0)) * 1000
                THEN 'fuera_estacion' END,
           -- [MIG662] capacidad real del estanque + 10 % de cuello de llenado.
           CASE WHEN r.grupo = 'flota' AND r.litros > r.capacidad_l * 1.1 THEN 'sobre_estanque' END,
           -- Con odómetro diario, dos cargas el mismo día dan 0 km: eso es «dos_cargas_dia», no esto.
           CASE WHEN r.grupo = 'flota' AND r.km_tramo IS NOT NULL AND r.km_tramo < 5 AND r.litros >= 15
                 AND r.carga_anterior::date < r.fecha_hora::date THEN 'sin_movimiento' END,
           -- [MIG662] 30 días: cargó más de lo que gastó andando + un estanque.
           CASE WHEN r.litros_sin_explicar_30d > 0 THEN 'rendimiento_bajo' END,
           CASE WHEN r.cargas_dia > 1 THEN 'dos_cargas_dia' END,
           -- [MIG662] en el día cargó más de lo que cabe + lo que gastó andando ese día.
           CASE WHEN r.grupo = 'flota' AND r.cargas_dia > 1 AND r.ultima_del_dia = 1
                 AND r.litros_dia > r.capacidad_l * 1.1
                                    + coalesce(r.km_dia, 0) / coalesce(nullif(r.med_km_l, 0), 10) * 1.3
                THEN 'litros_dia_excede' END
       ], NULL) AS alertas,
       r.grupo,
       r.capacidad_l, round(r.litros_dia, 1) AS litros_dia, round(r.km_dia) AS km_dia,
       round(r.litros_30d, 1) AS litros_30d, round(r.km_30d) AS km_30d,
       round(r.litros_sin_explicar_30d::numeric, 1) AS litros_sin_explicar_30d
  FROM r2 r
  LEFT JOIN est ON est.estacion = r.estacion
 WHERE public.fn_costos_operacion_puede_ver();

GRANT SELECT ON public.v_combustible_tarjeta_cargas TO authenticated;

SELECT a.patente, a.capacidad_estanque_l FROM public.activos a
 WHERE a.capacidad_estanque_l IS NOT NULL ORDER BY 1;
