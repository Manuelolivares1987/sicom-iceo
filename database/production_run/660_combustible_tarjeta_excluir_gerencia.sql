-- ============================================================================
-- MIG660 · Tarjeta Aramco: gerencia fuera del análisis y aljibes como abastecimiento
-- ----------------------------------------------------------------------------
-- TCRB-71 es la camioneta de gerencia (Manuel, 27-10-2026): no se analiza.
-- Las cargas se siguen guardando; solo salen de las vistas de rendimiento
-- (v_combustible_rendimiento_mes lee de v_combustible_tarjeta_cargas).
-- Para sacar otra patente basta una fila en combustible_tarjeta_excluidas.
--
-- Los aljibes de combustible (DCHD-83, HKSR-81) cargan con la tarjeta para
-- llenar su estanque y abastecer a otros equipos: van en el grupo
-- «abastecimiento», sin km/L ni la alerta de litros sobre el estanque.
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
           CASE WHEN a.tipo_equipamiento::text = 'aljibe_combustible' THEN 'abastecimiento' ELSE 'flota' END AS grupo,
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
           CASE WHEN r.grupo = 'flota' AND r.litros > CASE WHEN r.tipo_vehiculo ILIKE 'camioneta%' THEN 90
                                     WHEN r.tipo_vehiculo ILIKE 'cami%' THEN 450 ELSE 90 END
                THEN 'sobre_estanque' END,
           -- Con odómetro diario, dos cargas el mismo día dan 0 km: eso es «dos_cargas_dia», no esto.
           CASE WHEN r.grupo = 'flota' AND r.km_tramo IS NOT NULL AND r.km_tramo < 5 AND r.litros >= 15
                 AND r.carga_anterior::date < r.fecha_hora::date THEN 'sin_movimiento' END,
           -- Tramos cortos son ruido (llenados parciales, resolución diaria).
           CASE WHEN r.grupo = 'flota' AND med.n >= 4 AND r.km_tramo >= 150 AND r.km_l_tramo < 0.6 * med.km_l THEN 'rendimiento_bajo' END,
           CASE WHEN r.cargas_dia > 1 THEN 'dos_cargas_dia' END
       ], NULL) AS alertas,
       r.grupo
  FROM r
  LEFT JOIN est ON est.estacion = r.estacion
  LEFT JOIN med ON med.patente = r.patente
 WHERE public.fn_costos_operacion_puede_ver();

-- ── Por mes (igual que MIG659 + grupo). Por mes: tarjeta (litros pagados) y Renault (litros del computador) ──
CREATE OR REPLACE VIEW public.v_combustible_rendimiento_mes AS
-- km/L de la tarjeta = km de los tramos ÷ litros de esos mismos tramos (lleno a
-- lleno). Así un mes con días sin GPS no da un rendimiento falso: solo cuenta lo
-- que tiene odómetro en las dos puntas.
WITH tar AS (
    SELECT c.activo_id, c.patente, max(c.tipo_vehiculo) AS tipo,
           date_trunc('month', c.fecha_hora)::date AS mes,
           count(*) AS cargas, sum(c.litros) AS litros, sum(c.total_pago) AS monto,
           sum(c.km_tramo) AS km_tramos,
           sum(c.litros) FILTER (WHERE c.km_tramo IS NOT NULL) AS litros_tramos,
           sum(c.total_pago) FILTER (WHERE c.km_tramo IS NOT NULL) AS monto_tramos,
           count(*) FILTER (WHERE c.km_tramo IS NOT NULL) AS cargas_medidas,
           max(c.grupo) AS grupo
      FROM v_combustible_tarjeta_cargas c
     GROUP BY 1, 2, 4
), precio AS (   -- $/L diésel pagado con la tarjeta, por mes
    SELECT date_trunc('month', fecha_hora)::date AS mes, sum(total_pago) / nullif(sum(litros), 0) AS pl
      FROM combustible_tarjeta_cargas WHERE producto ILIKE '%diesel%' GROUP BY 1
), km AS (
    SELECT d.activo_id, date_trunc('month', d.fecha)::date AS mes,
           sum(d.km) AS km, count(d.km) AS dias_gps
      FROM v_activo_horas_dia d
     WHERE d.activo_id IN (SELECT activo_id FROM combustible_tarjeta_cargas WHERE activo_id IS NOT NULL)
     GROUP BY 1, 2
), ren AS (
    SELECT c.activo_id, date_trunc('month', c.fecha)::date AS mes,
           sum(c.litros) AS litros, sum(c.km) AS km, sum(c.horas) AS horas,
           sum(c.litros_ralenti) AS litros_ralenti, count(c.litros) AS dias_gps
      FROM v_activo_consumo_dia c WHERE c.litros IS NOT NULL
     GROUP BY 1, 2
)
SELECT 'tarjeta'::text AS fuente, t.activo_id, coalesce(a.patente, t.patente) AS patente,
       t.tipo, t.mes, t.cargas, round(t.litros, 1) AS litros, round(t.monto) AS monto, true AS monto_real,
       round(k.km) AS km_gps, k.dias_gps, NULL::numeric AS horas, NULL::numeric AS litros_ralenti,
       t.cargas_medidas, round(t.km_tramos) AS km_medidos,
       CASE WHEN t.grupo = 'flota' AND t.km_tramos >= 100 THEN round(t.km_tramos / nullif(t.litros_tramos, 0), 1) END AS km_l,
       CASE WHEN t.grupo = 'flota' AND t.km_tramos >= 100 THEN round(t.monto_tramos / t.km_tramos) END AS costo_km,
       t.grupo
  FROM tar t
  LEFT JOIN activos a ON a.id = t.activo_id
  LEFT JOIN km k ON k.activo_id = t.activo_id AND k.mes = t.mes
 WHERE public.fn_costos_operacion_puede_ver()
UNION ALL
SELECT 'computador', r.activo_id, a.patente, a.tipo::text, r.mes, NULL, round(r.litros, 1),
       round(r.litros * coalesce(p.pl, (SELECT pl FROM precio ORDER BY mes DESC LIMIT 1))), false,
       round(r.km), r.dias_gps, round(r.horas, 1), round(r.litros_ralenti, 1),
       r.dias_gps, round(r.km),
       round(r.km / nullif(r.litros, 0), 2),
       round(r.litros * coalesce(p.pl, (SELECT pl FROM precio ORDER BY mes DESC LIMIT 1)) / nullif(r.km, 0)),
       'flota'
  FROM ren r
  JOIN activos a ON a.id = r.activo_id
  LEFT JOIN precio p ON p.mes = r.mes
 WHERE public.fn_costos_operacion_puede_ver();
