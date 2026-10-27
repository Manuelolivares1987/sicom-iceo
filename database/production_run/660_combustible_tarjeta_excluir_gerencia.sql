-- ============================================================================
-- MIG660 · Tarjeta Aramco: vehículos fuera del análisis de rendimiento
-- ----------------------------------------------------------------------------
-- TCRB-71 es la camioneta de gerencia (Manuel, 27-10-2026): no se analiza.
-- Las cargas se siguen guardando; solo salen de las vistas de rendimiento
-- (v_combustible_rendimiento_mes lee de v_combustible_tarjeta_cargas).
-- Para sacar otra patente basta una fila en combustible_tarjeta_excluidas.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_excluidas (
    patente     TEXT PRIMARY KEY,            -- normalizada: TCRB71
    motivo      TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.combustible_tarjeta_excluidas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_comb_tarjeta_excl_sel ON public.combustible_tarjeta_excluidas;
CREATE POLICY pol_comb_tarjeta_excl_sel ON public.combustible_tarjeta_excluidas
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());
REVOKE ALL ON public.combustible_tarjeta_excluidas FROM anon;
GRANT SELECT ON public.combustible_tarjeta_excluidas TO authenticated;

INSERT INTO public.combustible_tarjeta_excluidas (patente, motivo)
VALUES ('TCRB71', 'Camioneta de gerencia')
ON CONFLICT (patente) DO NOTHING;

CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas AS
WITH c AS (
    SELECT c.*, coalesce(a.patente, c.patente) AS patente_ver, a.tipo::text AS tipo_sicom,
           EXISTS (SELECT 1 FROM gps_activo_mapeo g WHERE g.activo_id = c.activo_id) AS tiene_gps,
           o.km_fin AS odometro_gps, o.fecha AS odometro_fecha
      FROM combustible_tarjeta_cargas c
      LEFT JOIN activos a ON a.id = c.activo_id
      -- [MIG660] Fuera del análisis (p. ej. la camioneta de gerencia).
      LEFT JOIN combustible_tarjeta_excluidas x ON x.patente = c.patente
      LEFT JOIN LATERAL (
            SELECT h.km_fin, h.fecha FROM activo_horas_dia h
             WHERE h.activo_id = c.activo_id AND h.fecha < c.fecha_hora::date AND h.km_fin > 0
             ORDER BY h.fecha DESC LIMIT 1) o ON c.activo_id IS NOT NULL
     WHERE x.patente IS NULL
), t AS (
    SELECT c.*,
           CASE WHEN c.odometro_fecha >= c.fecha_hora::date - 3 THEN c.odometro_gps END AS odo,
           count(*) OVER (PARTITION BY c.patente, c.fecha_hora::date) AS cargas_dia
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
)
SELECT r.id, r.importacion_id, r.cod_autorizacion, r.fecha_hora, r.patente, r.patente_ver,
       r.activo_id, r.tipo_vehiculo, r.tiene_gps, r.producto, r.estacion, r.comuna, r.tarjeta,
       r.rut_chofer, r.litros, r.pizarra_l, r.total_pago, r.guia_despacho,
       r.gps_lat, r.gps_lng, r.gps_dif_min, r.odo AS odometro_gps, r.carga_anterior, r.km_tramo, r.km_l_tramo,
       round(med.km_l::numeric, 1) AS km_l_mediana,
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
           CASE WHEN r.litros > CASE WHEN r.tipo_vehiculo ILIKE 'camioneta%' THEN 90
                                     WHEN r.tipo_vehiculo ILIKE 'cami%' THEN 450 ELSE 90 END
                THEN 'sobre_estanque' END,
           -- Con odómetro diario, dos cargas el mismo día dan 0 km: eso es «dos_cargas_dia», no esto.
           CASE WHEN r.km_tramo IS NOT NULL AND r.km_tramo < 5 AND r.litros >= 15
                 AND r.carga_anterior::date < r.fecha_hora::date THEN 'sin_movimiento' END,
           -- Tramos cortos son ruido (llenados parciales, resolución diaria).
           CASE WHEN med.n >= 4 AND r.km_tramo >= 150 AND r.km_l_tramo < 0.6 * med.km_l THEN 'rendimiento_bajo' END,
           CASE WHEN r.cargas_dia > 1 THEN 'dos_cargas_dia' END
       ], NULL) AS alertas
  FROM r
  LEFT JOIN est ON est.estacion = r.estacion
  LEFT JOIN med ON med.patente = r.patente
 WHERE public.fn_costos_operacion_puede_ver();
