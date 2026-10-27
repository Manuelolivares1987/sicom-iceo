-- ============================================================================
-- MIG659 · Tarjeta de flota Aramco + rendimiento km/L con GPS
-- ----------------------------------------------------------------------------
-- Las camionetas cargan con la tarjeta Aramco Fleet (portaltarjetas.cl). El
-- Excel del portal trae litros y monto por carga, pero el odómetro viene vacío
-- (el chofer no lo digita). Los km salen del GPS.
--
--   0. Hora local de una lectura GPS (Radicom venía -3 h antes de la MIG657).
--   1. activo_horas_dia también para equipos SIN horómetro (solo odómetro):
--      el trigger los saltaba y 7 camionetas no tenían km diario. Se rellena
--      con el historial que queda en gps_eventos_log (~30 días).
--   2. Tablas de la importación + RPC (no duplica: código de autorización).
--      La posición GPS a la hora de la carga se guarda UNA vez al importar,
--      porque el historial GPS se purga.
--   3. Vistas: carga a carga (km desde la anterior, alertas) y por mes
--      (tarjeta + Renault con su computador).
--
-- Carga para la base: ~7 filas nuevas/día en activo_horas_dia, sin cron nuevo;
-- la importación la lanza una persona (cientos de filas). Las vistas leen
-- tablas chicas por su llave primaria.
-- ============================================================================

-- ── 0. Hora local de una lectura GPS ────────────────────────────────────────
-- Antes de la MIG657 (27-10-2026 13:35 UTC) Radicom guardaba la hora local
-- como si fuera UTC. Después, ts_gps es la hora real.
CREATE OR REPLACE FUNCTION public.fn_gps_ts_local(p_ts TIMESTAMPTZ, p_proveedor UUID, p_ingestado TIMESTAMPTZ)
RETURNS TIMESTAMP LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_proveedor = '3a0e4dc7-b1ab-4b3a-ad4f-ddfe5fe49c0f'::uuid
         AND p_ingestado < '2026-10-27 13:35:00+00'::timestamptz
        THEN p_ts AT TIME ZONE 'UTC'
        ELSE p_ts AT TIME ZONE 'America/Santiago'
    END
$$;

-- ── 1. Km diario también sin horómetro ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_activo_horas_dia_registrar()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
    -- [MIG659] Basta horómetro U odómetro (las camionetas no tienen horómetro).
    IF NEW.activo_id IS NULL
       OR (coalesce(NEW.horometro_hrs, 0) <= 0 AND coalesce(NEW.odometro_km, 0) <= 0) THEN
        RETURN NEW;
    END IF;
    INSERT INTO activo_horas_dia AS h (activo_id, fecha, horometro_ini, horometro_fin,
                                       km_ini, km_fin, lecturas,
                                       combustible_fin_l, ralenti_fin_l, ralenti_fin_h)
    VALUES (NEW.activo_id, (NEW.ts_gps AT TIME ZONE 'America/Santiago')::DATE,
            nullif(NEW.horometro_hrs, 0), nullif(NEW.horometro_hrs, 0),
            nullif(NEW.odometro_km, 0), nullif(NEW.odometro_km, 0), 1,
            nullif(NEW.payload_raw->>'combustible_total_l', '')::NUMERIC,
            nullif(NEW.payload_raw->>'ralenti_l', '')::NUMERIC,
            nullif(NEW.payload_raw->>'ralenti_h', '')::NUMERIC)
    ON CONFLICT (activo_id, fecha) DO UPDATE SET
        horometro_ini = least(h.horometro_ini, EXCLUDED.horometro_ini),
        horometro_fin = greatest(h.horometro_fin, EXCLUDED.horometro_fin),
        km_ini = least(h.km_ini, EXCLUDED.km_ini),
        km_fin = greatest(h.km_fin, EXCLUDED.km_fin),
        lecturas = h.lecturas + 1,
        combustible_fin_l = greatest(h.combustible_fin_l, EXCLUDED.combustible_fin_l),
        ralenti_fin_l = greatest(h.ralenti_fin_l, EXCLUDED.ralenti_fin_l),
        ralenti_fin_h = greatest(h.ralenti_fin_h, EXCLUDED.ralenti_fin_h),
        actualizado_at = NOW();
    RETURN NEW;
END $function$;

-- Relleno: solo equipos que nunca tuvieron fila (los que el trigger saltaba).
INSERT INTO activo_horas_dia (activo_id, fecha, km_ini, km_fin, lecturas)
SELECT l.activo_id, public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado)::date,
       min(l.odometro_km), max(l.odometro_km), count(*)
  FROM gps_eventos_log l
 WHERE l.activo_id IS NOT NULL AND l.odometro_km > 0
   AND NOT EXISTS (SELECT 1 FROM activo_horas_dia h WHERE h.activo_id = l.activo_id)
 GROUP BY 1, 2
ON CONFLICT (activo_id, fecha) DO NOTHING;

-- ── 2. Importación de la tarjeta ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_importaciones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proveedor   TEXT NOT NULL DEFAULT 'aramco',
    archivo     TEXT,
    filas       INT NOT NULL DEFAULT 0,
    nuevas      INT NOT NULL DEFAULT 0,
    repetidas   INT NOT NULL DEFAULT 0,
    desde       TIMESTAMP,
    hasta       TIMESTAMP,
    created_by  UUID DEFAULT auth.uid(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_cargas (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    importacion_id    UUID REFERENCES public.combustible_tarjeta_importaciones(id) ON DELETE SET NULL,
    proveedor         TEXT NOT NULL DEFAULT 'aramco',
    cod_autorizacion  TEXT NOT NULL,
    fecha_hora        TIMESTAMP NOT NULL,          -- hora local de Chile, como la da el portal
    tarjeta           TEXT,
    tipo_tarjeta      TEXT,
    patente           TEXT NOT NULL,               -- normalizada: SPRY28
    activo_id         UUID REFERENCES public.activos(id) ON DELETE SET NULL,
    tipo_vehiculo     TEXT,
    centro_costo      TEXT,
    guia_despacho     TEXT,
    factura           TEXT,
    rut_chofer        TEXT,
    odometro_declarado NUMERIC,
    producto          TEXT,
    estacion          TEXT,
    comuna            TEXT,
    pizarra_l         NUMERIC,
    litros            NUMERIC NOT NULL CHECK (litros >= 0),
    total_pizarra     NUMERIC,
    total_descuento   NUMERIC,
    total_pago        NUMERIC,
    gps_lat           NUMERIC(10,7),               -- dónde estaba el vehículo a esa hora
    gps_lng           NUMERIC(10,7),
    gps_ts            TIMESTAMP,
    gps_dif_min       INT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (proveedor, cod_autorizacion)
);
CREATE INDEX IF NOT EXISTS idx_comb_tarjeta_activo_fecha ON public.combustible_tarjeta_cargas (activo_id, fecha_hora);
CREATE INDEX IF NOT EXISTS idx_comb_tarjeta_fecha ON public.combustible_tarjeta_cargas (fecha_hora);

ALTER TABLE public.combustible_tarjeta_importaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combustible_tarjeta_cargas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_comb_tarjeta_imp_sel ON public.combustible_tarjeta_importaciones;
CREATE POLICY pol_comb_tarjeta_imp_sel ON public.combustible_tarjeta_importaciones
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());
DROP POLICY IF EXISTS pol_comb_tarjeta_sel ON public.combustible_tarjeta_cargas;
CREATE POLICY pol_comb_tarjeta_sel ON public.combustible_tarjeta_cargas
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());
REVOKE ALL ON public.combustible_tarjeta_importaciones, public.combustible_tarjeta_cargas FROM anon;
GRANT SELECT ON public.combustible_tarjeta_importaciones, public.combustible_tarjeta_cargas TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_puede_cargar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_tiene_permiso_modulo('gerencia', 'view', ARRAY[
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento'])
$$;
GRANT EXECUTE ON FUNCTION public.fn_comb_tarjeta_puede_cargar() TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_combustible_tarjeta_importar(p_archivo TEXT, p_filas JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_imp      UUID;
    v_total    INT;
    v_nuevas   INT;
    v_desde    TIMESTAMP;
    v_hasta    TIMESTAMP;
    v_sin      TEXT[];
    v_con_gps  INT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'No autorizado para cargar la tarjeta de combustible.' USING ERRCODE = '42501';
    END IF;
    IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' OR jsonb_array_length(p_filas) = 0 THEN
        RAISE EXCEPTION 'El archivo no trae cargas.';
    END IF;
    IF jsonb_array_length(p_filas) > 5000 THEN
        RAISE EXCEPTION 'Máximo 5.000 cargas por archivo; exporte un período más corto.';
    END IF;
    v_total := jsonb_array_length(p_filas);

    INSERT INTO combustible_tarjeta_importaciones (archivo, filas) VALUES (p_archivo, v_total)
    RETURNING id INTO v_imp;

    WITH f AS (
        SELECT x.*, regexp_replace(upper(coalesce(x.patente, '')), '[^A-Z0-9]', '', 'g') AS pat
          FROM jsonb_to_recordset(p_filas) AS x(
                cod_autorizacion TEXT, fecha_hora TIMESTAMP, tarjeta TEXT, tipo_tarjeta TEXT,
                patente TEXT, tipo_vehiculo TEXT, centro_costo TEXT, guia_despacho TEXT,
                factura TEXT, rut_chofer TEXT, odometro NUMERIC, producto TEXT, estacion TEXT,
                comuna TEXT, pizarra NUMERIC, litros NUMERIC, total_pizarra NUMERIC,
                total_descuento NUMERIC, total_pago NUMERIC)
         WHERE nullif(trim(x.cod_autorizacion), '') IS NOT NULL AND x.fecha_hora IS NOT NULL
           AND x.litros IS NOT NULL AND x.litros >= 0
    ), ins AS (
        INSERT INTO combustible_tarjeta_cargas (
            importacion_id, cod_autorizacion, fecha_hora, tarjeta, tipo_tarjeta, patente, activo_id,
            tipo_vehiculo, centro_costo, guia_despacho, factura, rut_chofer, odometro_declarado,
            producto, estacion, comuna, pizarra_l, litros, total_pizarra, total_descuento, total_pago)
        SELECT v_imp, trim(f.cod_autorizacion), f.fecha_hora, f.tarjeta, f.tipo_tarjeta, f.pat,
               (SELECT a.id FROM activos a
                 WHERE regexp_replace(upper(a.patente), '[^A-Z0-9]', '', 'g') = f.pat
                 ORDER BY (a.fecha_baja IS NULL) DESC LIMIT 1),
               f.tipo_vehiculo, nullif(f.centro_costo, ''), f.guia_despacho, nullif(f.factura, ''),
               f.rut_chofer, nullif(f.odometro, 0), f.producto, f.estacion, f.comuna, f.pizarra,
               f.litros, f.total_pizarra, f.total_descuento, f.total_pago
          FROM f
        ON CONFLICT (proveedor, cod_autorizacion) DO NOTHING
        RETURNING 1
    )
    SELECT count(*) INTO v_nuevas FROM ins;

    -- Dónde estaba el vehículo a la hora de la carga (±90 min). El rango sobre
    -- ts_gps cubre la hora vieja (-3 h) y la nueva, y usa el índice.
    UPDATE combustible_tarjeta_cargas c
       SET gps_lat = s.latitud, gps_lng = s.longitud, gps_ts = s.ts_local, gps_dif_min = s.dif
      FROM (
        SELECT DISTINCT ON (c2.id) c2.id, l.latitud, l.longitud,
               public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado) AS ts_local,
               round(abs(extract(epoch FROM public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado)
                                            - c2.fecha_hora)) / 60)::int AS dif
          FROM combustible_tarjeta_cargas c2
          JOIN gps_eventos_log l
            ON l.activo_id = c2.activo_id AND l.latitud IS NOT NULL
           AND l.ts_gps BETWEEN ((c2.fecha_hora - interval '2 hours') AT TIME ZONE 'UTC')
                            AND ((c2.fecha_hora + interval '6 hours') AT TIME ZONE 'UTC')
         WHERE c2.importacion_id = v_imp AND c2.activo_id IS NOT NULL
         ORDER BY c2.id, abs(extract(epoch FROM public.fn_gps_ts_local(l.ts_gps, l.proveedor_id, l.ts_ingestado)
                                              - c2.fecha_hora))
      ) s
     WHERE s.id = c.id AND s.dif <= 90;
    GET DIAGNOSTICS v_con_gps = ROW_COUNT;

    SELECT min(fecha_hora), max(fecha_hora),
           array_agg(DISTINCT patente) FILTER (WHERE activo_id IS NULL)
      INTO v_desde, v_hasta, v_sin
      FROM combustible_tarjeta_cargas WHERE importacion_id = v_imp;

    UPDATE combustible_tarjeta_importaciones
       SET nuevas = v_nuevas, repetidas = v_total - v_nuevas, desde = v_desde, hasta = v_hasta
     WHERE id = v_imp;

    RETURN jsonb_build_object(
        'importacion_id', v_imp, 'filas', v_total, 'nuevas', v_nuevas,
        'repetidas', v_total - v_nuevas, 'con_posicion_gps', v_con_gps,
        'desde', v_desde, 'hasta', v_hasta, 'patentes_sin_ficha', coalesce(v_sin, '{}'));
END $$;
REVOKE ALL ON FUNCTION public.rpc_combustible_tarjeta_importar(TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_combustible_tarjeta_importar(TEXT, JSONB) TO authenticated;

-- ── 3a. Carga a carga ───────────────────────────────────────────────────────
-- km del tramo = odómetro GPS al cierre del día anterior a esta carga menos el
-- de la carga anterior (lleno a lleno: los litros de ESTA carga reponen lo que
-- se gastó en el tramo). Resolución diaria: el GPS manda el odómetro ~1 vez al día.
CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas AS
WITH c AS (
    SELECT c.*, coalesce(a.patente, c.patente) AS patente_ver, a.tipo::text AS tipo_sicom,
           EXISTS (SELECT 1 FROM gps_activo_mapeo g WHERE g.activo_id = c.activo_id) AS tiene_gps,
           o.km_fin AS odometro_gps, o.fecha AS odometro_fecha
      FROM combustible_tarjeta_cargas c
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN LATERAL (
            SELECT h.km_fin, h.fecha FROM activo_horas_dia h
             WHERE h.activo_id = c.activo_id AND h.fecha < c.fecha_hora::date AND h.km_fin > 0
             ORDER BY h.fecha DESC LIMIT 1) o ON c.activo_id IS NOT NULL
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

-- ── 3b. Por mes: tarjeta (litros pagados) y Renault (litros del computador) ──
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
           count(*) FILTER (WHERE c.km_tramo IS NOT NULL) AS cargas_medidas
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
       CASE WHEN t.km_tramos >= 100 THEN round(t.km_tramos / nullif(t.litros_tramos, 0), 1) END AS km_l,
       CASE WHEN t.km_tramos >= 100 THEN round(t.monto_tramos / t.km_tramos) END AS costo_km
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
       round(r.litros * coalesce(p.pl, (SELECT pl FROM precio ORDER BY mes DESC LIMIT 1)) / nullif(r.km, 0))
  FROM ren r
  JOIN activos a ON a.id = r.activo_id
  LEFT JOIN precio p ON p.mes = r.mes
 WHERE public.fn_costos_operacion_puede_ver();

REVOKE ALL ON public.v_combustible_tarjeta_cargas, public.v_combustible_rendimiento_mes FROM anon;
GRANT SELECT ON public.v_combustible_tarjeta_cargas, public.v_combustible_rendimiento_mes TO authenticated;
