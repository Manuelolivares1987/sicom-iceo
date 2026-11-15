-- ============================================================================
-- MIG691 · Control de combustible: horario, reporte semanal por operación con
--          justificación obligatoria, y validación de jefatura
-- ----------------------------------------------------------------------------
-- 1. Alerta nueva «fuera_horario»: carga fuera de lunes a viernes 07:00-19:00.
-- 2. La vista se parte en dos: v_combustible_tarjeta_cargas_base (interna, sin
--    filtro de permisos, solo para funciones SECURITY DEFINER: cron y enlace de
--    justificación) y v_combustible_tarjeta_cargas (la de siempre, con permisos).
-- 3. Reporte semanal por OPERACIÓN (activos.operacion). Calama → Jefe de
--    Operaciones Calama con copia a Manuel; solo ve vehículos de Calama.
--    Cada diferencia exige justificación por un enlace con token (30 días).
--    Lo que no se justifica sigue apareciendo cada semana y el jueves se
--    recuerda. Manuel acepta o rechaza; rechazada vuelve a pendiente.
-- 4. TCRB-71 y TSTB-48 siguen fuera: tarjetas de uso personal de jefatura
--    (decisión de Manuel, 15-11-2026). Se declaran como fuera de alcance.
-- ============================================================================

-- ── 1-2. Vista base + vista con permisos ────────────────────────────────────
CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas_base AS
 WITH c AS (
         SELECT c.id,
            c.importacion_id,
            c.proveedor,
            c.cod_autorizacion,
            c.fecha_hora,
            c.tarjeta,
            c.tipo_tarjeta,
            c.patente,
            c.activo_id,
            c.tipo_vehiculo,
            c.centro_costo,
            c.guia_despacho,
            c.factura,
            c.rut_chofer,
            c.odometro_declarado,
            c.producto,
            c.estacion,
            c.comuna,
            c.pizarra_l,
            c.litros,
            c.total_pizarra,
            c.total_descuento,
            c.total_pago,
            c.gps_lat,
            c.gps_lng,
            c.gps_ts,
            c.gps_dif_min,
            c.created_at,
            COALESCE(a.patente, c.patente::character varying) AS patente_ver,
            a.tipo::text AS tipo_sicom,
                CASE
                    WHEN a.tipo_equipamiento::text = 'aljibe_combustible'::text THEN 'abastecimiento'::text
                    ELSE 'flota'::text
                END AS grupo,
            (EXISTS ( SELECT 1
                   FROM gps_activo_mapeo g_1
                  WHERE g_1.activo_id = c.activo_id)) AS tiene_gps,
            o.km_fin AS odometro_gps,
            o.fecha AS odometro_fecha,
            COALESCE(a.capacidad_estanque_l,
                CASE
                    WHEN c.tipo_vehiculo ~~* 'camioneta%'::text THEN 80
                    WHEN c.tipo_vehiculo ~~* 'cami%'::text THEN 450
                    ELSE 80
                END::numeric) AS capacidad_l,
            hd.km AS km_dia,
            w30.km AS km_30d,
            w30.dias AS dias_gps_30d,
            l30.litros AS litros_30d
           FROM combustible_tarjeta_cargas c
             LEFT JOIN activos a ON a.id = c.activo_id
             LEFT JOIN combustible_tarjeta_excluidas x ON x.patente = c.patente
             LEFT JOIN LATERAL ( SELECT h.km_fin,
                    h.fecha
                   FROM ( SELECT a_1.km_fin,
                            a_1.fecha
                           FROM activo_horas_dia a_1
                          WHERE a_1.activo_id = c.activo_id AND a_1.fecha < c.fecha_hora::date AND a_1.km_fin > 0::numeric
                        UNION ALL
                         SELECT k.km_fin,
                            k.fecha
                           FROM combustible_km_historico k
                          WHERE k.activo_id = c.activo_id AND k.fecha < c.fecha_hora::date) h
                  ORDER BY h.fecha DESC
                 LIMIT 1) o ON c.activo_id IS NOT NULL
             LEFT JOIN v_combustible_km_dia hd ON hd.activo_id = c.activo_id AND hd.fecha = c.fecha_hora::date
             LEFT JOIN LATERAL ( SELECT GREATEST(c.fecha_hora::date - 29, LEAST(( SELECT min(h.fecha) AS min
                           FROM activo_horas_dia h
                          WHERE h.activo_id = c.activo_id AND h.km_fin > 0::numeric), ( SELECT min(k.fecha) AS min
                           FROM combustible_km_historico k
                          WHERE k.activo_id = c.activo_id))) AS desde) g ON c.activo_id IS NOT NULL
             LEFT JOIN LATERAL ( SELECT sum(d.km) AS km,
                    c.fecha_hora::date - g.desde + 1 AS dias
                   FROM v_combustible_km_dia d
                  WHERE d.activo_id = c.activo_id AND d.fecha >= g.desde AND d.fecha <= c.fecha_hora::date) w30 ON g.desde IS NOT NULL
             LEFT JOIN LATERAL ( SELECT sum(c2.litros) AS litros
                   FROM combustible_tarjeta_cargas c2
                  WHERE c2.patente = c.patente AND c2.fecha_hora::date >= g.desde AND c2.fecha_hora <= c.fecha_hora) l30 ON g.desde IS NOT NULL
          WHERE x.patente IS NULL
        ), t AS (
         SELECT c.id,
            c.importacion_id,
            c.proveedor,
            c.cod_autorizacion,
            c.fecha_hora,
            c.tarjeta,
            c.tipo_tarjeta,
            c.patente,
            c.activo_id,
            c.tipo_vehiculo,
            c.centro_costo,
            c.guia_despacho,
            c.factura,
            c.rut_chofer,
            c.odometro_declarado,
            c.producto,
            c.estacion,
            c.comuna,
            c.pizarra_l,
            c.litros,
            c.total_pizarra,
            c.total_descuento,
            c.total_pago,
            c.gps_lat,
            c.gps_lng,
            c.gps_ts,
            c.gps_dif_min,
            c.created_at,
            c.patente_ver,
            c.tipo_sicom,
            c.grupo,
            c.tiene_gps,
            c.odometro_gps,
            c.odometro_fecha,
            c.capacidad_l,
            c.km_dia,
            c.km_30d,
            c.dias_gps_30d,
            c.litros_30d,
                CASE
                    WHEN c.odometro_fecha >= (c.fecha_hora::date - 3) THEN c.odometro_gps
                    ELSE NULL::numeric
                END AS odo,
            count(*) OVER (PARTITION BY c.patente, (c.fecha_hora::date)) AS cargas_dia,
            sum(c.litros) OVER (PARTITION BY c.patente, (c.fecha_hora::date)) AS litros_dia,
            row_number() OVER (PARTITION BY c.patente, (c.fecha_hora::date) ORDER BY c.fecha_hora DESC) AS ultima_del_dia
           FROM c
        ), k AS (
         SELECT t.id,
            t.importacion_id,
            t.proveedor,
            t.cod_autorizacion,
            t.fecha_hora,
            t.tarjeta,
            t.tipo_tarjeta,
            t.patente,
            t.activo_id,
            t.tipo_vehiculo,
            t.centro_costo,
            t.guia_despacho,
            t.factura,
            t.rut_chofer,
            t.odometro_declarado,
            t.producto,
            t.estacion,
            t.comuna,
            t.pizarra_l,
            t.litros,
            t.total_pizarra,
            t.total_descuento,
            t.total_pago,
            t.gps_lat,
            t.gps_lng,
            t.gps_ts,
            t.gps_dif_min,
            t.created_at,
            t.patente_ver,
            t.tipo_sicom,
            t.grupo,
            t.tiene_gps,
            t.odometro_gps,
            t.odometro_fecha,
            t.capacidad_l,
            t.km_dia,
            t.km_30d,
            t.dias_gps_30d,
            t.litros_30d,
            t.odo,
            t.cargas_dia,
            t.litros_dia,
            t.ultima_del_dia,
            t.odo - lag(t.odo) OVER (PARTITION BY t.patente ORDER BY t.fecha_hora) AS km_bruto,
            lag(t.fecha_hora) OVER (PARTITION BY t.patente ORDER BY t.fecha_hora) AS carga_anterior
           FROM t
        ), k2 AS (
         SELECT k.id,
            k.importacion_id,
            k.proveedor,
            k.cod_autorizacion,
            k.fecha_hora,
            k.tarjeta,
            k.tipo_tarjeta,
            k.patente,
            k.activo_id,
            k.tipo_vehiculo,
            k.centro_costo,
            k.guia_despacho,
            k.factura,
            k.rut_chofer,
            k.odometro_declarado,
            k.producto,
            k.estacion,
            k.comuna,
            k.pizarra_l,
            k.litros,
            k.total_pizarra,
            k.total_descuento,
            k.total_pago,
            k.gps_lat,
            k.gps_lng,
            k.gps_ts,
            k.gps_dif_min,
            k.created_at,
            k.patente_ver,
            k.tipo_sicom,
            k.grupo,
            k.tiene_gps,
            k.odometro_gps,
            k.odometro_fecha,
            k.capacidad_l,
            k.km_dia,
            k.km_30d,
            k.dias_gps_30d,
            k.litros_30d,
            k.odo,
            k.cargas_dia,
            k.litros_dia,
            k.ultima_del_dia,
            k.km_bruto,
            k.carga_anterior,
                CASE
                    WHEN k.km_bruto >= 0::numeric AND k.km_bruto <= 5000::numeric THEN round(k.km_bruto)
                    ELSE NULL::numeric
                END AS km_tramo
           FROM k
        ), r AS (
         SELECT k2.id,
            k2.importacion_id,
            k2.proveedor,
            k2.cod_autorizacion,
            k2.fecha_hora,
            k2.tarjeta,
            k2.tipo_tarjeta,
            k2.patente,
            k2.activo_id,
            k2.tipo_vehiculo,
            k2.centro_costo,
            k2.guia_despacho,
            k2.factura,
            k2.rut_chofer,
            k2.odometro_declarado,
            k2.producto,
            k2.estacion,
            k2.comuna,
            k2.pizarra_l,
            k2.litros,
            k2.total_pizarra,
            k2.total_descuento,
            k2.total_pago,
            k2.gps_lat,
            k2.gps_lng,
            k2.gps_ts,
            k2.gps_dif_min,
            k2.created_at,
            k2.patente_ver,
            k2.tipo_sicom,
            k2.grupo,
            k2.tiene_gps,
            k2.odometro_gps,
            k2.odometro_fecha,
            k2.capacidad_l,
            k2.km_dia,
            k2.km_30d,
            k2.dias_gps_30d,
            k2.litros_30d,
            k2.odo,
            k2.cargas_dia,
            k2.litros_dia,
            k2.ultima_del_dia,
            k2.km_bruto,
            k2.carga_anterior,
            k2.km_tramo,
                CASE
                    WHEN k2.km_tramo > 0::numeric AND k2.litros > 0::numeric THEN round(k2.km_tramo / k2.litros, 1)
                    ELSE NULL::numeric
                END AS km_l_tramo
           FROM k2
        ), est AS (
         SELECT combustible_tarjeta_cargas.estacion,
            count(*) AS n,
            percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (combustible_tarjeta_cargas.gps_lat::double precision)) AS lat,
            percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (combustible_tarjeta_cargas.gps_lng::double precision)) AS lng
           FROM combustible_tarjeta_cargas
          WHERE combustible_tarjeta_cargas.gps_lat IS NOT NULL
          GROUP BY combustible_tarjeta_cargas.estacion
        ), med AS (
         SELECT r_1.patente,
            count(*) AS n,
            percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (r_1.km_l_tramo::double precision)) AS km_l
           FROM r r_1
          WHERE r_1.km_l_tramo IS NOT NULL
          GROUP BY r_1.patente
        ), r2 AS (
         SELECT r_1.id,
            r_1.importacion_id,
            r_1.proveedor,
            r_1.cod_autorizacion,
            r_1.fecha_hora,
            r_1.tarjeta,
            r_1.tipo_tarjeta,
            r_1.patente,
            r_1.activo_id,
            r_1.tipo_vehiculo,
            r_1.centro_costo,
            r_1.guia_despacho,
            r_1.factura,
            r_1.rut_chofer,
            r_1.odometro_declarado,
            r_1.producto,
            r_1.estacion,
            r_1.comuna,
            r_1.pizarra_l,
            r_1.litros,
            r_1.total_pizarra,
            r_1.total_descuento,
            r_1.total_pago,
            r_1.gps_lat,
            r_1.gps_lng,
            r_1.gps_ts,
            r_1.gps_dif_min,
            r_1.created_at,
            r_1.patente_ver,
            r_1.tipo_sicom,
            r_1.grupo,
            r_1.tiene_gps,
            r_1.odometro_gps,
            r_1.odometro_fecha,
            r_1.capacidad_l,
            r_1.km_dia,
            r_1.km_30d,
            r_1.dias_gps_30d,
            r_1.litros_30d,
            r_1.odo,
            r_1.cargas_dia,
            r_1.litros_dia,
            r_1.ultima_del_dia,
            r_1.km_bruto,
            r_1.carga_anterior,
            r_1.km_tramo,
            r_1.km_l_tramo,
            med.n AS med_n,
            med.km_l AS med_km_l,
                CASE
                    WHEN r_1.grupo = 'flota'::text AND med.n >= 4 AND r_1.dias_gps_30d >= 20 AND med.km_l > 0::double precision THEN r_1.litros_30d::double precision - (r_1.km_30d::double precision / med.km_l * 1.2::double precision + (r_1.capacidad_l * 1.1)::double precision)
                    ELSE NULL::double precision
                END AS litros_sin_explicar_30d
           FROM r r_1
             LEFT JOIN med ON med.patente = r_1.patente
        )
 SELECT r.id,
    r.importacion_id,
    r.cod_autorizacion,
    r.fecha_hora,
    r.patente,
    r.patente_ver,
    r.activo_id,
    r.tipo_vehiculo,
    r.tiene_gps,
    r.producto,
    r.estacion,
    r.comuna,
    r.tarjeta,
    r.rut_chofer,
    r.litros,
    r.pizarra_l,
    r.total_pago,
    r.guia_despacho,
    r.gps_lat,
    r.gps_lng,
    r.gps_dif_min,
    r.odo AS odometro_gps,
    r.carga_anterior,
    r.km_tramo,
    r.km_l_tramo,
    round(r.med_km_l::numeric, 1) AS km_l_mediana,
        CASE
            WHEN est.n >= 3 AND r.gps_lat IS NOT NULL THEN round(fn_distancia_haversine(r.gps_lat, r.gps_lng, est.lat::numeric, est.lng::numeric) / 1000::numeric, 1)
            ELSE NULL::numeric
        END AS dist_estacion_km,
    array_remove(ARRAY[
        CASE
            WHEN r.activo_id IS NULL THEN 'sin_ficha'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.activo_id IS NOT NULL AND NOT r.tiene_gps THEN 'sin_gps'::text
            ELSE NULL::text
        END,
        CASE
            WHEN est.n >= 3 AND r.gps_lat IS NOT NULL AND fn_distancia_haversine(r.gps_lat, r.gps_lng, est.lat::numeric, est.lng::numeric) > ((5::numeric + 1.2 * COALESCE(r.gps_dif_min, 0)::numeric) * 1000::numeric) THEN 'fuera_estacion'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.grupo = 'flota'::text AND r.litros > (r.capacidad_l * 1.1) THEN 'sobre_estanque'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.grupo = 'flota'::text AND r.km_tramo IS NOT NULL AND r.km_tramo < 5::numeric AND r.litros >= 15::numeric AND r.carga_anterior::date < r.fecha_hora::date THEN 'sin_movimiento'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.litros_sin_explicar_30d > 0::double precision THEN 'rendimiento_bajo'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.cargas_dia > 1 THEN 'dos_cargas_dia'::text
            ELSE NULL::text
        END,
        CASE
            -- [MIG691] horario normal de carga: lunes a viernes 07:00-19:00 (Manuel, 15-11-2026)
            WHEN r.grupo = 'flota'::text AND (EXTRACT(isodow FROM r.fecha_hora) IN (6, 7)
                  OR r.fecha_hora::time < '07:00'::time OR r.fecha_hora::time >= '19:00'::time) THEN 'fuera_horario'::text
            ELSE NULL::text
        END,
        CASE
            WHEN r.grupo = 'flota'::text AND r.cargas_dia > 1 AND r.ultima_del_dia = 1 AND r.litros_dia::double precision > ((r.capacidad_l * 1.1)::double precision + COALESCE(r.km_dia, 0::numeric)::double precision / COALESCE(NULLIF(r.med_km_l, 0::double precision), 10::double precision) * 1.3::double precision) THEN 'litros_dia_excede'::text
            ELSE NULL::text
        END], NULL::text) AS alertas,
    r.grupo,
    r.capacidad_l,
    round(r.litros_dia, 1) AS litros_dia,
    round(r.km_dia) AS km_dia,
    round(r.litros_30d, 1) AS litros_30d,
    round(r.km_30d) AS km_30d,
    round(r.litros_sin_explicar_30d::numeric, 1) AS litros_sin_explicar_30d
   FROM r2 r
     LEFT JOIN est ON est.estacion = r.estacion;
REVOKE ALL ON public.v_combustible_tarjeta_cargas_base FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas AS
SELECT * FROM public.v_combustible_tarjeta_cargas_base
 WHERE fn_costos_operacion_puede_ver();

-- Motivo de exclusión visible (para declarar el alcance ante el directorio).
ALTER TABLE public.combustible_tarjeta_excluidas ADD COLUMN IF NOT EXISTS motivo_alcance TEXT;
UPDATE public.combustible_tarjeta_excluidas
   SET motivo_alcance = 'Uso personal de jefatura'
 WHERE patente IN ('TCRB71', 'TSTB48') AND motivo_alcance IS NULL;

-- ── 3. Revisiones: quién justificó, por dónde, y validación ─────────────────
ALTER TABLE public.combustible_tarjeta_revisiones
    ADD COLUMN IF NOT EXISTS autor_nombre    TEXT,
    ADD COLUMN IF NOT EXISTS origen          TEXT NOT NULL DEFAULT 'pantalla',
    ADD COLUMN IF NOT EXISTS reporte_id      UUID,
    ADD COLUMN IF NOT EXISTS validada_por    UUID,
    ADD COLUMN IF NOT EXISTS validada_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS nota_validacion TEXT;
-- Quien justifica por el enlace del correo no tiene cuenta: el autor queda en autor_nombre.
ALTER TABLE public.combustible_tarjeta_revisiones ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.combustible_tarjeta_revisiones DROP CONSTRAINT IF EXISTS combustible_tarjeta_revisiones_estado_check;
ALTER TABLE public.combustible_tarjeta_revisiones ADD CONSTRAINT combustible_tarjeta_revisiones_estado_check
    CHECK (estado IN ('justificada', 'escalada', 'aceptada', 'rechazada'));

-- ── 4. Destinatarios por operación y reportes emitidos ──────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_reporte_destinatarios (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operacion   TEXT NOT NULL,                      -- = activos.operacion
    email       TEXT NOT NULL,
    nombre      TEXT,
    tipo        TEXT NOT NULL DEFAULT 'para' CHECK (tipo IN ('para', 'cc')),
    responsable BOOLEAN NOT NULL DEFAULT false,     -- quien debe justificar
    activo      BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (operacion, email)
);
ALTER TABLE public.combustible_tarjeta_reporte_destinatarios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS comb_tarjeta_dest_ver ON public.combustible_tarjeta_reporte_destinatarios;
CREATE POLICY comb_tarjeta_dest_ver ON public.combustible_tarjeta_reporte_destinatarios
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());

-- Calama → Jefe de Operaciones Calama; Coquimbo → Bodega (Gustavo). Copia a Manuel.
INSERT INTO public.combustible_tarjeta_reporte_destinatarios (operacion, email, nombre, tipo, responsable) VALUES
    ('Calama',   'hcorey@pillado.cl',                  'Hersaly Corey',   'para', true),
    ('Calama',   'manuel.olivares@pilladoempresas.cl', 'Manuel Olivares', 'cc',   false),
    ('Coquimbo', 'bodegacentral@pilladoempresas.cl',   'Gustavo (Bodega)', 'para', true),
    ('Coquimbo', 'manuel.olivares@pilladoempresas.cl', 'Manuel Olivares', 'cc',   false)
ON CONFLICT (operacion, email) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_reportes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token         TEXT NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(24), 'hex'),
    operacion     TEXT NOT NULL,
    semana_desde  DATE NOT NULL,
    semana_hasta  DATE NOT NULL,
    responsable   TEXT,
    expira_at     TIMESTAMPTZ NOT NULL DEFAULT NOW() + interval '30 days',
    enviado_at    TIMESTAMPTZ,
    recordado_at  TIMESTAMPTZ,
    envio_error   TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (operacion, semana_desde)
);
ALTER TABLE public.combustible_tarjeta_reportes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS comb_tarjeta_rep_ver ON public.combustible_tarjeta_reportes;
CREATE POLICY comb_tarjeta_rep_ver ON public.combustible_tarjeta_reportes
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());

-- Desde cuándo se exige justificar (inicio del control con km GPS).
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_inicio_control()
RETURNS DATE LANGUAGE sql IMMUTABLE AS $$ SELECT DATE '2026-09-01' $$;

-- ── 5. Diferencias de una operación (núcleo del reporte) ────────────────────
-- Diferencia = carga con alguna alerta salvo la informativa dos_cargas_dia.
-- Estado: pendiente (sin revisión o rechazada), por_validar (justificada por
-- correo), cerrada (justificada en pantalla por jefatura, o aceptada), escalada.
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_diferencias(p_operacion TEXT, p_hasta DATE)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT coalesce(jsonb_agg(x ORDER BY x->>'fecha_hora'), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
                 'carga_id', v.id, 'patente', v.patente_ver, 'fecha_hora', v.fecha_hora,
                 'estacion', v.estacion, 'comuna', v.comuna, 'litros', round(v.litros, 1),
                 'total_pago', round(v.total_pago), 'km_tramo', v.km_tramo, 'km_l_tramo', v.km_l_tramo,
                 'km_l_mediana', v.km_l_mediana, 'dist_estacion_km', v.dist_estacion_km,
                 'litros_sin_explicar_30d', v.litros_sin_explicar_30d,
                 'alertas', to_jsonb(array_remove(v.alertas, 'dos_cargas_dia')),
                 'chofer', c.chofer,
                 'estado', CASE WHEN rv.id IS NULL OR rv.estado = 'rechazada' THEN 'pendiente'
                                WHEN rv.estado = 'justificada' AND rv.origen = 'correo' THEN 'por_validar'
                                WHEN rv.estado = 'escalada' THEN 'escalada'
                                ELSE 'cerrada' END,
                 'comentario', rv.comentario, 'autor', rv.autor_nombre,
                 'justificada_at', rv.created_at, 'nota_validacion', rv.nota_validacion,
                 'rechazada', coalesce(rv.estado = 'rechazada', false)) AS x
          FROM v_combustible_tarjeta_cargas_base v
          JOIN combustible_tarjeta_cargas c ON c.id = v.id
          JOIN activos a ON a.id = v.activo_id
          LEFT JOIN combustible_tarjeta_revisiones rv ON rv.carga_id = v.id
         WHERE a.operacion = p_operacion
           AND v.fecha_hora >= fn_comb_tarjeta_inicio_control()
           AND v.fecha_hora < p_hasta + 1
           AND array_remove(v.alertas, 'dos_cargas_dia') <> '{}'
    ) s
$$;
REVOKE ALL ON FUNCTION public.fn_comb_tarjeta_diferencias(TEXT, DATE) FROM PUBLIC, anon, authenticated;

-- Resumen por vehículo de una operación en un rango (litros, $, km GPS, km/L).
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_resumen_vehiculos(p_operacion TEXT, p_desde DATE, p_hasta DATE)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    WITH car AS (
        SELECT v.activo_id, v.patente_ver, count(*) AS cargas, sum(v.litros) AS litros, sum(v.total_pago) AS pago,
               max(v.km_l_mediana) AS km_l_normal,
               -- litros sin explicar a 30 días en la última carga del rango (regla física MIG662)
               (array_agg(v.litros_sin_explicar_30d ORDER BY v.fecha_hora DESC))[1] AS sin_explicar_30d
          FROM v_combustible_tarjeta_cargas_base v JOIN activos a ON a.id = v.activo_id
         WHERE a.operacion = p_operacion AND v.fecha_hora >= p_desde AND v.fecha_hora < p_hasta + 1
         GROUP BY 1, 2
    ), km AS (
        SELECT d.activo_id, sum(d.km) AS km FROM v_combustible_km_dia d
         WHERE d.activo_id IN (SELECT activo_id FROM car) AND d.fecha BETWEEN p_desde AND p_hasta
         GROUP BY 1
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'patente', car.patente_ver, 'cargas', car.cargas, 'litros', round(car.litros, 1),
             'pago', round(car.pago), 'km', round(km.km),
             'km_l', CASE WHEN km.km > 0 AND car.litros > 0 THEN round(km.km / car.litros, 1) END,
             'km_l_normal', car.km_l_normal, 'sin_explicar_30d', car.sin_explicar_30d) ORDER BY car.patente_ver), '[]'::jsonb)
      FROM car LEFT JOIN km ON km.activo_id = car.activo_id
$$;
REVOKE ALL ON FUNCTION public.fn_comb_tarjeta_resumen_vehiculos(TEXT, DATE, DATE) FROM PUBLIC, anon, authenticated;

-- ── 6. Cron: arma el reporte semanal (o el recordatorio del jueves) ─────────
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_semanal_cron(p_secreto TEXT, p_recordatorio BOOLEAN DEFAULT false)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_hoy    DATE := (now() AT TIME ZONE 'America/Santiago')::date;
    v_desde  DATE;
    v_hasta  DATE;
    v_op     TEXT;
    v_rep    combustible_tarjeta_reportes;
    v_out    JSONB := '[]'::jsonb;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    FOR v_op IN SELECT DISTINCT operacion FROM combustible_tarjeta_reporte_destinatarios WHERE activo ORDER BY 1 LOOP
        v_rep := NULL;
        IF p_recordatorio THEN
            SELECT * INTO v_rep FROM combustible_tarjeta_reportes
             WHERE operacion = v_op AND enviado_at IS NOT NULL ORDER BY semana_desde DESC LIMIT 1;
            CONTINUE WHEN v_rep.id IS NULL;
        ELSE
            v_desde := date_trunc('week', v_hoy)::date - 7;   -- lunes de la semana pasada
            v_hasta := date_trunc('week', v_hoy)::date - 1;   -- domingo
            INSERT INTO combustible_tarjeta_reportes (operacion, semana_desde, semana_hasta, responsable)
            VALUES (v_op, v_desde, v_hasta,
                    (SELECT nombre FROM combustible_tarjeta_reporte_destinatarios
                      WHERE operacion = v_op AND activo AND responsable LIMIT 1))
            ON CONFLICT (operacion, semana_desde) DO UPDATE SET expira_at = NOW() + interval '30 days'
            RETURNING * INTO v_rep;
        END IF;
        v_out := v_out || jsonb_build_object(
            'reporte_id', v_rep.id, 'token', v_rep.token, 'operacion', v_op,
            'semana_desde', v_rep.semana_desde, 'semana_hasta', v_rep.semana_hasta,
            'responsable', v_rep.responsable,
            'para', (SELECT coalesce(jsonb_agg(email), '[]') FROM combustible_tarjeta_reporte_destinatarios
                      WHERE operacion = v_op AND activo AND tipo = 'para'),
            'cc',   (SELECT coalesce(jsonb_agg(email), '[]') FROM combustible_tarjeta_reporte_destinatarios
                      WHERE operacion = v_op AND activo AND tipo = 'cc'),
            'vehiculos', fn_comb_tarjeta_resumen_vehiculos(v_op, v_rep.semana_desde, v_rep.semana_hasta),
            'diferencias', fn_comb_tarjeta_diferencias(v_op, greatest(v_rep.semana_hasta, v_hoy - 1)));
    END LOOP;
    RETURN v_out;
END $$;
REVOKE ALL ON FUNCTION public.fn_comb_tarjeta_semanal_cron(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_comb_tarjeta_semanal_cron(TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_semanal_marcar_cron(
    p_secreto TEXT, p_reporte_id UUID, p_recordatorio BOOLEAN, p_ok BOOLEAN, p_error TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    UPDATE combustible_tarjeta_reportes
       SET enviado_at   = CASE WHEN p_ok AND NOT p_recordatorio THEN NOW() ELSE enviado_at END,
           recordado_at = CASE WHEN p_ok AND p_recordatorio THEN NOW() ELSE recordado_at END,
           envio_error  = CASE WHEN p_ok THEN NULL ELSE left(p_error, 500) END
     WHERE id = p_reporte_id;
END $$;
REVOKE ALL ON FUNCTION public.fn_comb_tarjeta_semanal_marcar_cron(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_comb_tarjeta_semanal_marcar_cron(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT) TO anon, authenticated;

-- ── 7. Enlace del correo: ver y justificar sin cuenta ───────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_tarjeta_reporte_token(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_rep combustible_tarjeta_reportes;
BEGIN
    SELECT * INTO v_rep FROM combustible_tarjeta_reportes WHERE token = p_token;
    IF v_rep.id IS NULL THEN RETURN jsonb_build_object('valido', false, 'motivo', 'Enlace no válido.'); END IF;
    IF v_rep.expira_at < NOW() THEN
        RETURN jsonb_build_object('valido', false, 'motivo', 'El enlace venció. Use el del último correo semanal.');
    END IF;
    RETURN jsonb_build_object(
        'valido', true, 'operacion', v_rep.operacion, 'responsable', v_rep.responsable,
        'semana_desde', v_rep.semana_desde, 'semana_hasta', v_rep.semana_hasta,
        'vehiculos', fn_comb_tarjeta_resumen_vehiculos(v_rep.operacion, v_rep.semana_desde, v_rep.semana_hasta),
        'diferencias', fn_comb_tarjeta_diferencias(v_rep.operacion, (now() AT TIME ZONE 'America/Santiago')::date));
END $$;
REVOKE ALL ON FUNCTION public.rpc_comb_tarjeta_reporte_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_comb_tarjeta_reporte_token(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_comb_tarjeta_justificar_token(
    p_token TEXT, p_carga_id UUID, p_comentario TEXT, p_nombre TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_rep combustible_tarjeta_reportes;
    v_rv  combustible_tarjeta_revisiones;
BEGIN
    SELECT * INTO v_rep FROM combustible_tarjeta_reportes WHERE token = p_token AND expira_at > NOW();
    IF v_rep.id IS NULL THEN RAISE EXCEPTION 'El enlace no es válido o venció.'; END IF;
    IF length(btrim(coalesce(p_nombre, ''))) < 3 THEN RAISE EXCEPTION 'Indique su nombre.'; END IF;
    IF length(btrim(coalesce(p_comentario, ''))) < 15 THEN
        RAISE EXCEPTION 'Explique la diferencia (mínimo 15 caracteres): qué pasó y quién cargó.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM v_combustible_tarjeta_cargas_base v JOIN activos a ON a.id = v.activo_id
         WHERE v.id = p_carga_id AND a.operacion = v_rep.operacion
           AND v.fecha_hora >= fn_comb_tarjeta_inicio_control()
           AND array_remove(v.alertas, 'dos_cargas_dia') <> '{}') THEN
        RAISE EXCEPTION 'Esa carga no es una diferencia de %.', v_rep.operacion;
    END IF;
    SELECT * INTO v_rv FROM combustible_tarjeta_revisiones WHERE carga_id = p_carga_id;
    IF v_rv.id IS NOT NULL AND (v_rv.estado IN ('aceptada', 'escalada')
                                OR (v_rv.estado = 'justificada' AND v_rv.origen = 'pantalla')) THEN
        RAISE EXCEPTION 'Esa diferencia ya fue cerrada por jefatura.';
    END IF;
    DELETE FROM combustible_tarjeta_revisiones WHERE carga_id = p_carga_id;
    INSERT INTO combustible_tarjeta_revisiones (carga_id, estado, comentario, autor_nombre, origen, reporte_id, created_by)
    VALUES (p_carga_id, 'justificada', btrim(p_comentario), btrim(p_nombre), 'correo', v_rep.id, NULL);
    RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public.rpc_comb_tarjeta_justificar_token(TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_comb_tarjeta_justificar_token(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

-- ── 8. Jefatura valida (acepta / rechaza) lo justificado por correo ─────────
CREATE OR REPLACE FUNCTION public.rpc_comb_tarjeta_validar(p_carga_id UUID, p_aceptar BOOLEAN, p_nota TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    IF NOT p_aceptar AND length(btrim(coalesce(p_nota, ''))) < 5 THEN
        RAISE EXCEPTION 'Al rechazar, indique qué falta.';
    END IF;
    UPDATE combustible_tarjeta_revisiones
       SET estado = CASE WHEN p_aceptar THEN 'aceptada' ELSE 'rechazada' END,
           validada_por = auth.uid(), validada_at = NOW(), nota_validacion = nullif(btrim(p_nota), '')
     WHERE carga_id = p_carga_id AND estado = 'justificada' AND origen = 'correo';
    IF NOT FOUND THEN RAISE EXCEPTION 'No hay una justificación por validar para esa carga.'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.rpc_comb_tarjeta_validar(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_comb_tarjeta_validar(UUID, BOOLEAN, TEXT) TO authenticated;

-- Para el tablero: diferencias por operación (requiere permiso de costos).
CREATE OR REPLACE FUNCTION public.rpc_comb_tarjeta_diferencias_todas()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::date;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN (SELECT coalesce(jsonb_object_agg(op, fn_comb_tarjeta_diferencias(op, v_hoy)), '{}'::jsonb)
              FROM (SELECT DISTINCT a.operacion AS op FROM combustible_tarjeta_cargas c
                      JOIN activos a ON a.id = c.activo_id WHERE a.operacion IS NOT NULL) o);
END $$;
REVOKE ALL ON FUNCTION public.rpc_comb_tarjeta_diferencias_todas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_comb_tarjeta_diferencias_todas() TO authenticated;

-- ── 9. Cron: lunes y jueves 11:00 UTC (08:00 Chile en verano) ───────────────
-- Copia el comando del cron de papeles de flota (mismo secreto, barra final,
-- timeout) cambiando solo la ruta: el secreto no queda en el repo.
DO $$
DECLARE v_cmd TEXT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    IF v_cmd IS NULL OR position('/api/notificaciones/documentos-flota/' IN v_cmd) = 0 THEN
        RAISE EXCEPTION 'No encuentro el cron documentos-flota-diario para copiar su configuración.';
    END IF;
    PERFORM cron.unschedule(jobname) FROM cron.job
     WHERE jobname IN ('combustible-semanal', 'combustible-recordatorio');
    PERFORM cron.schedule('combustible-semanal', '0 11 * * 1',
        replace(v_cmd, '/api/notificaciones/documentos-flota/', '/api/notificaciones/combustible-semanal/'));
    PERFORM cron.schedule('combustible-recordatorio', '0 11 * * 4',
        replace(v_cmd, '/api/notificaciones/documentos-flota/', '/api/notificaciones/combustible-semanal/?recordatorio=1'));
END $$;

SELECT 'MIG691 OK' AS resultado;
