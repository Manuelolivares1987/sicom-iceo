-- MIG635 · GPS de fábrica Renault Trucks (rFMS) como segundo proveedor
-- ============================================================================
-- Los Renault C440 nuevos (CC-20-04…09) llegaron sin tracker Radicom: en SICOM
-- tenían 0 h y 0 km. Traen de fábrica la telemática Renault, que se lee por
-- rFMS 2.1 (estándar europeo del Grupo Volvo) en api.renault-trucks.com/rfms
-- con usuario y clave (Basic). Lo que entrega el computador del camión:
-- posición, horómetro y odómetro de la ECU, litros consumidos totales y en
-- ralentí, nivel de estanque y AdBlue, rpm, peso y temperatura.
--
-- Renault guarda SOLO 14 DÍAS. SICOM lee cada 15 min desde un cursor
-- (ReceivedDateTime + VIN, como manda rFMS) y guarda en gps_eventos_log por
-- la misma RPC que Radicom: mapa, horas por día, preventivas por horas y
-- Centinela funcionan sin tocarlos.
--
-- Camino (sin service_role ni edge function, patrón MIG301):
--   pg_cron → POST /api/gps/renault/ (x-cron-secret) → la ruta lee la config
--   con fn_renault_rfms_config_cron, consulta Renault y entrega a
--   rpc_renault_ingestar_cron. Ambas exigen el secreto 'cron_alertas'.
--
-- Enlace camión ↔ activo: por VIN (activos.vin_chasis), automático en cada
-- lectura. Si el activo ya tiene otro GPS activo (TCJV-15 tiene Radicom), el
-- enlace Renault queda INACTIVO: dos fuentes sobre el mismo gps_estado_actual
-- se pisarían, y el horómetro Radicom de TCJV-15 va 211 h atrás de la ECU
-- (1.737,9 vs 1.948,9 al 22-10): cambiar de fuente mueve la base de sus
-- preventivas y lo decide Manuel.
--
-- Credenciales: NO van en este archivo. Se cargan aparte en
-- config_gps_proveedor.api_token como 'usuario:clave'.
--
-- ADITIVA. Idempotente.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. PROVEEDOR
-- ############################################################################

INSERT INTO config_gps_proveedor (nombre, activo, api_base_url, api_tipo_auth, config_mapeo)
SELECT 'Renault rFMS', TRUE, 'https://api.renault-trucks.com/rfms', 'basic',
       jsonb_build_object('cursor_ts', NULL, 'cursor_vin', NULL)
 WHERE NOT EXISTS (SELECT 1 FROM config_gps_proveedor WHERE nombre = 'Renault rFMS');


-- ############################################################################
-- 2. LO QUE RENAULT TRAE Y RADICOM NO
-- ############################################################################

ALTER TABLE gps_estado_actual
    ADD COLUMN IF NOT EXISTS combustible_pct     NUMERIC,
    ADD COLUMN IF NOT EXISTS adblue_pct          NUMERIC,
    ADD COLUMN IF NOT EXISTS combustible_total_l NUMERIC,
    ADD COLUMN IF NOT EXISTS rpm                 NUMERIC;

COMMENT ON COLUMN gps_estado_actual.combustible_pct IS
    '[MIG635] Nivel de estanque % (rFMS FuelLevel1). Solo GPS de fábrica.';
COMMENT ON COLUMN gps_estado_actual.adblue_pct IS
    '[MIG635] Nivel de AdBlue % (rFMS CatalystFuelLevel).';
COMMENT ON COLUMN gps_estado_actual.combustible_total_l IS
    '[MIG635] Litros consumidos en la vida del motor (rFMS EngineTotalFuelUsed).';

ALTER TABLE activo_horas_dia
    ADD COLUMN IF NOT EXISTS combustible_fin_l NUMERIC,
    ADD COLUMN IF NOT EXISTS ralenti_fin_l     NUMERIC,
    ADD COLUMN IF NOT EXISTS ralenti_fin_h     NUMERIC;

COMMENT ON COLUMN activo_horas_dia.combustible_fin_l IS
    '[MIG635] Último acumulado de litros del motor en el día (ECU Renault).';


-- Renault repite el registro de borde al paginar: un mismo VIN no puede tener
-- dos lecturas con la misma hora. Índice parcial, solo para este proveedor.
DO $idx$
DECLARE v_id UUID;
BEGIN
    SELECT id INTO v_id FROM config_gps_proveedor WHERE nombre = 'Renault rFMS';
    EXECUTE format(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_gps_eventos_renault ON gps_eventos_log (gps_device_id, ts_gps) WHERE proveedor_id = %L',
        v_id);
END
$idx$;


-- ############################################################################
-- 3. TRIGGERS: contacto, combustible y litros por día
-- ############################################################################

-- Igual a MIG571 + (a) el contacto también puede venir como 'contacto_utc'
-- (Renault: hora en que el camión transmitió), (b) combustible/AdBlue/rpm.
CREATE OR REPLACE FUNCTION public.fn_actualizar_estado_gps()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_contacto TIMESTAMPTZ := COALESCE(fn_navixy_ts(NEW.payload_raw->>'last_update'),
                                       NULLIF(NEW.payload_raw->>'contacto_utc', '')::TIMESTAMPTZ);
    v_comb_pct   NUMERIC := NULLIF(NEW.payload_raw->>'combustible_pct', '')::NUMERIC;
    v_adblue_pct NUMERIC := NULLIF(NEW.payload_raw->>'adblue_pct', '')::NUMERIC;
    v_comb_l     NUMERIC := NULLIF(NEW.payload_raw->>'combustible_total_l', '')::NUMERIC;
    v_rpm        NUMERIC := NULLIF(NEW.payload_raw->>'rpm', '')::NUMERIC;
BEGIN
    -- Solo procesar si tenemos activo_id (eventos sin mapeo se ignoran)
    IF NEW.activo_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Upsert estado actual (no sobrescribir si el evento que llego es mas viejo
    -- que el ultimo conocido — puede pasar con polling en lotes)
    INSERT INTO gps_estado_actual (
        activo_id, proveedor_id, gps_device_id,
        ts_gps, ts_actualizado,
        latitud, longitud, velocidad_kmh, heading,
        ignicion, movimiento, conexion,
        odometro_km, horometro_hrs, bateria_pct, gsm_red,
        ts_ultimo_contacto,
        combustible_pct, adblue_pct, combustible_total_l, rpm
    ) VALUES (
        NEW.activo_id, NEW.proveedor_id, NEW.gps_device_id,
        NEW.ts_gps, NOW(),
        NEW.latitud, NEW.longitud, NEW.velocidad_kmh, NEW.heading,
        NEW.ignicion, NEW.movimiento, NEW.conexion,
        NEW.odometro_km, NEW.horometro_hrs, NEW.bateria_pct, NEW.gsm_red,
        v_contacto,
        v_comb_pct, v_adblue_pct, v_comb_l, v_rpm
    )
    ON CONFLICT (activo_id) DO UPDATE
       SET proveedor_id   = EXCLUDED.proveedor_id,
           gps_device_id  = EXCLUDED.gps_device_id,
           ts_gps         = EXCLUDED.ts_gps,
           ts_actualizado = NOW(),
           latitud        = EXCLUDED.latitud,
           longitud       = EXCLUDED.longitud,
           velocidad_kmh  = EXCLUDED.velocidad_kmh,
           heading        = EXCLUDED.heading,
           ignicion       = EXCLUDED.ignicion,
           movimiento     = EXCLUDED.movimiento,
           conexion       = EXCLUDED.conexion,
           -- Counters: solo si vienen no-null Y son monotonos crecientes
           odometro_km    = CASE
                              WHEN EXCLUDED.odometro_km IS NOT NULL
                                   AND (gps_estado_actual.odometro_km IS NULL
                                        OR EXCLUDED.odometro_km >= gps_estado_actual.odometro_km)
                              THEN EXCLUDED.odometro_km
                              ELSE gps_estado_actual.odometro_km
                            END,
           horometro_hrs  = CASE
                              WHEN EXCLUDED.horometro_hrs IS NOT NULL
                                   AND (gps_estado_actual.horometro_hrs IS NULL
                                        OR EXCLUDED.horometro_hrs >= gps_estado_actual.horometro_hrs)
                              THEN EXCLUDED.horometro_hrs
                              ELSE gps_estado_actual.horometro_hrs
                            END,
           bateria_pct    = EXCLUDED.bateria_pct,
           gsm_red        = EXCLUDED.gsm_red,
           -- [MIG571] El contacto solo avanza (GREATEST ignora NULL).
           ts_ultimo_contacto = GREATEST(gps_estado_actual.ts_ultimo_contacto,
                                         EXCLUDED.ts_ultimo_contacto),
           -- [MIG635] Una lectura sin el dato no borra el último conocido.
           combustible_pct     = COALESCE(EXCLUDED.combustible_pct, gps_estado_actual.combustible_pct),
           adblue_pct          = COALESCE(EXCLUDED.adblue_pct, gps_estado_actual.adblue_pct),
           combustible_total_l = GREATEST(gps_estado_actual.combustible_total_l, EXCLUDED.combustible_total_l),
           rpm                 = EXCLUDED.rpm
       WHERE EXCLUDED.ts_gps IS NULL
          OR gps_estado_actual.ts_gps IS NULL
          OR EXCLUDED.ts_gps >= gps_estado_actual.ts_gps;

    -- Sincronizar counters al activo (alimenta pautas preventivas — mig 34)
    -- Solo si los counters vienen y son mayores a los actuales.
    IF NEW.odometro_km IS NOT NULL THEN
        UPDATE activos
           SET kilometraje_actual = NEW.odometro_km
         WHERE id = NEW.activo_id
           AND NEW.odometro_km > kilometraje_actual;
    END IF;

    IF NEW.horometro_hrs IS NOT NULL THEN
        UPDATE activos
           SET horas_uso_actual = NEW.horometro_hrs
         WHERE id = NEW.activo_id
           AND NEW.horometro_hrs > horas_uso_actual;
    END IF;

    RETURN NEW;
END;
$function$;


-- Igual a MIG597 + los acumulados de litros (total y ralentí) y horas de ralentí.
CREATE OR REPLACE FUNCTION fn_activo_horas_dia_registrar()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.activo_id IS NULL OR coalesce(NEW.horometro_hrs, 0) <= 0 THEN
        RETURN NEW;
    END IF;
    INSERT INTO activo_horas_dia AS h (activo_id, fecha, horometro_ini, horometro_fin,
                                       km_ini, km_fin, lecturas,
                                       combustible_fin_l, ralenti_fin_l, ralenti_fin_h)
    VALUES (NEW.activo_id, (NEW.ts_gps AT TIME ZONE 'America/Santiago')::DATE,
            NEW.horometro_hrs, NEW.horometro_hrs,
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
END $$;


-- ############################################################################
-- 4. CONSUMO POR DÍA (mismo criterio que v_activo_horas_dia)
-- ############################################################################
-- Litros del día = último acumulado del día − último del día anterior con dato.
-- Más de 1.000 L por día de diferencia no es consumo (cambio de ECU o error).
CREATE OR REPLACE VIEW v_activo_consumo_dia AS
SELECT d.activo_id, d.fecha, d.horas, d.km, d.litros, d.litros_ralenti, d.horas_ralenti,
       round(d.litros / nullif(d.horas, 0), 1)        AS litros_hora,
       round(d.km / nullif(d.litros, 0), 2)           AS km_litro,
       round(100 * d.litros_ralenti / nullif(d.litros, 0)) AS pct_ralenti
  FROM (
    SELECT h.activo_id, h.fecha, v.horas, v.km,
           CASE WHEN p.combustible_fin_l IS NULL OR h.combustible_fin_l IS NULL THEN NULL
                WHEN h.combustible_fin_l - p.combustible_fin_l < 0
                  OR h.combustible_fin_l - p.combustible_fin_l > 1000 * (h.fecha - p.fecha) THEN NULL
                ELSE round(h.combustible_fin_l - p.combustible_fin_l, 1) END AS litros,
           CASE WHEN p.ralenti_fin_l IS NULL OR h.ralenti_fin_l IS NULL
                  OR h.ralenti_fin_l < p.ralenti_fin_l THEN NULL
                ELSE round(h.ralenti_fin_l - p.ralenti_fin_l, 1) END AS litros_ralenti,
           CASE WHEN p.ralenti_fin_h IS NULL OR h.ralenti_fin_h IS NULL
                  OR h.ralenti_fin_h - p.ralenti_fin_h NOT BETWEEN 0 AND 24 * (h.fecha - p.fecha) THEN NULL
                ELSE round(h.ralenti_fin_h - p.ralenti_fin_h, 1) END AS horas_ralenti
      FROM activo_horas_dia h
      JOIN v_activo_horas_dia v ON v.activo_id = h.activo_id AND v.fecha = h.fecha
      LEFT JOIN LATERAL (SELECT a.fecha, a.combustible_fin_l, a.ralenti_fin_l, a.ralenti_fin_h
                           FROM activo_horas_dia a
                          WHERE a.activo_id = h.activo_id AND a.fecha < h.fecha
                            AND a.combustible_fin_l IS NOT NULL
                          ORDER BY a.fecha DESC LIMIT 1) p ON TRUE
     WHERE h.combustible_fin_l IS NOT NULL
  ) d;

COMMENT ON VIEW v_activo_consumo_dia IS
    'Litros, ralentí y rendimiento por equipo y día desde la ECU (GPS de fábrica). MIG635.';
GRANT SELECT ON v_activo_consumo_dia TO authenticated;


-- ############################################################################
-- 5. MAPA: mismas columnas + las de fábrica al final
-- ############################################################################
CREATE OR REPLACE VIEW v_flota_posiciones AS
 SELECT a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.patente AS activo_patente,
    a.nombre AS activo_nombre,
    a.tipo AS activo_tipo,
    a.tipo_equipamiento,
    a.estado AS activo_estado,
    a.estado_comercial AS activo_estado_comercial,
    a.kilometraje_actual AS km_actual,
    a.horas_uso_actual AS horas_actual,
    c.id AS contrato_id,
    c.codigo AS contrato_codigo,
    c.cliente,
    gam.gps_device_id,
    gam.gps_device_name,
    gam.imei,
    p.nombre AS proveedor,
    e.ts_gps,
    e.ts_actualizado,
    e.latitud,
    e.longitud,
    e.velocidad_kmh,
    e.heading,
    e.ignicion,
    e.movimiento,
    e.conexion,
    e.odometro_km,
    e.horometro_hrs,
    e.bateria_pct,
    e.gsm_red,
        CASE
            WHEN e.ts_gps IS NULL OR e.conexion IS NULL THEN 'sin_datos'::text
            WHEN e.conexion::text = 'offline'::text THEN 'sin_senal'::text
            WHEN COALESCE(e.velocidad_kmh, 0::numeric) >= 5::numeric THEN 'en_ruta'::text
            WHEN e.ignicion = true THEN 'detenido_motor_on'::text
            ELSE 'detenido'::text
        END AS estado_pin,
        CASE
            WHEN e.ts_gps IS NULL THEN NULL::integer
            ELSE EXTRACT(epoch FROM now() - e.ts_gps)::integer / 60
        END AS minutos_desde_reporte,
    e.combustible_pct,
    e.adblue_pct,
    e.rpm
   FROM gps_activo_mapeo gam
     JOIN config_gps_proveedor p ON p.id = gam.proveedor_id
     JOIN activos a ON a.id = gam.activo_id
     LEFT JOIN gps_estado_actual e ON e.activo_id = a.id
     LEFT JOIN contratos c ON c.id = a.contrato_id
  WHERE gam.activo = true AND p.activo = true AND a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false);


-- ############################################################################
-- 6. LAS DOS FUNCIONES QUE EL CRON NECESITA (secreto 'cron_alertas', MIG301)
-- ############################################################################

CREATE OR REPLACE FUNCTION fn_renault_rfms_config_cron(p_secreto TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE p config_gps_proveedor%ROWTYPE;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    SELECT * INTO p FROM config_gps_proveedor WHERE nombre = 'Renault rFMS';
    IF NOT FOUND OR NOT p.activo THEN
        RETURN jsonb_build_object('activo', FALSE);
    END IF;
    RETURN jsonb_build_object(
        'activo',     TRUE,
        'base_url',   p.api_base_url,
        'credencial', p.api_token,
        'cursor_ts',  p.config_mapeo->>'cursor_ts',
        'cursor_vin', p.config_mapeo->>'cursor_vin');
END $$;

COMMENT ON FUNCTION fn_renault_rfms_config_cron(TEXT) IS
    'Config + cursor del poll Renault rFMS para /api/gps/renault. MIG635.';


-- p_vehiculos: [{vin, modelo, ...}] de /vehicles → enlaza por VIN.
-- p_eventos:   formato de rpc_ingestar_gps_batch (gps_device_id = VIN).
-- p_cursor_*:  hasta dónde se leyó; solo avanza.
CREATE OR REPLACE FUNCTION rpc_renault_ingestar_cron(
    p_secreto    TEXT,
    p_vehiculos  JSONB,
    p_eventos    JSONB,
    p_cursor_ts  TEXT,
    p_cursor_vin TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_prov      UUID;
    v_nuevos    JSONB;
    v_enlazados INTEGER := 0;
    v_res       JSONB := '{}'::jsonb;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    SELECT id INTO v_prov FROM config_gps_proveedor WHERE nombre = 'Renault rFMS' AND activo;
    IF v_prov IS NULL THEN
        RAISE EXCEPTION 'Proveedor Renault rFMS no configurado o inactivo';
    END IF;

    -- 1. Enlace por VIN. Activo con otro GPS activo → enlace inactivo (ver cabecera).
    WITH v AS (
        SELECT DISTINCT upper(trim(x->>'vin')) AS vin, x->>'modelo' AS modelo
          FROM jsonb_array_elements(coalesce(p_vehiculos, '[]'::jsonb)) x
         WHERE coalesce(x->>'vin', '') <> ''
    ), ins AS (
        INSERT INTO gps_activo_mapeo (activo_id, proveedor_id, gps_device_id, gps_device_name, activo)
        SELECT a.id, v_prov, v.vin, 'Renault ' || coalesce(v.modelo, ''),
               NOT EXISTS (SELECT 1 FROM gps_activo_mapeo o
                            WHERE o.activo_id = a.id AND o.proveedor_id <> v_prov AND o.activo)
          FROM v
          JOIN activos a ON upper(trim(a.vin_chasis)) = v.vin AND a.estado <> 'dado_baja'
         WHERE NOT EXISTS (SELECT 1 FROM gps_activo_mapeo m
                            WHERE m.proveedor_id = v_prov
                              AND (m.gps_device_id = v.vin OR m.activo_id = a.id))
        RETURNING 1
    )
    SELECT count(*) INTO v_enlazados FROM ins;

    -- 2. Solo camiones enlazados y activos, y sin repetir lo ya guardado
    --    (Renault devuelve el registro de borde de nuevo en cada página).
    SELECT coalesce(jsonb_agg(e), '[]'::jsonb) INTO v_nuevos
      FROM jsonb_array_elements(coalesce(p_eventos, '[]'::jsonb)) e
     WHERE EXISTS (SELECT 1 FROM gps_activo_mapeo m
                    WHERE m.proveedor_id = v_prov AND m.activo
                      AND m.gps_device_id = e->>'gps_device_id')
       AND NOT EXISTS (SELECT 1 FROM gps_eventos_log l
                        WHERE l.proveedor_id = v_prov
                          AND l.gps_device_id = e->>'gps_device_id'
                          AND l.ts_gps = (e->>'ts_gps')::TIMESTAMPTZ);

    IF jsonb_array_length(v_nuevos) > 0 THEN
        v_res := rpc_ingestar_gps_batch('Renault rFMS', v_nuevos);
    END IF;

    -- 3. Cursor: solo avanza.
    IF p_cursor_ts IS NOT NULL THEN
        UPDATE config_gps_proveedor
           SET config_mapeo = coalesce(config_mapeo, '{}'::jsonb)
                              || jsonb_build_object('cursor_ts', p_cursor_ts,
                                                    'cursor_vin', p_cursor_vin,
                                                    'ultimo_poll', NOW()),
               updated_at = NOW()
         WHERE id = v_prov
           AND (config_mapeo->>'cursor_ts' IS NULL
                OR (config_mapeo->>'cursor_ts')::TIMESTAMPTZ <= p_cursor_ts::TIMESTAMPTZ);
    END IF;

    RETURN jsonb_build_object(
        'enlazados_nuevos', v_enlazados,
        'recibidos',        jsonb_array_length(coalesce(p_eventos, '[]'::jsonb)),
        'nuevos',           jsonb_array_length(v_nuevos),
        'ingesta',          v_res);
END $$;

COMMENT ON FUNCTION rpc_renault_ingestar_cron(TEXT, JSONB, JSONB, TEXT, TEXT) IS
    'Enlace por VIN + ingesta + cursor del poll Renault rFMS. MIG635.';

-- Protegidas por el secreto: anon sola no abre nada (MIG301).
REVOKE ALL ON FUNCTION fn_renault_rfms_config_cron(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_renault_ingestar_cron(TEXT, JSONB, JSONB, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_renault_rfms_config_cron(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_renault_ingestar_cron(TEXT, JSONB, JSONB, TEXT, TEXT) TO anon, authenticated;

COMMIT;


-- ############################################################################
-- 7. CRON cada 15 min (secreto reutilizado y verificado, como MIG571)
-- ############################################################################
DO $cron$
DECLARE
    v_cmd TEXT;
    v_sec TEXT;
    v_ok  BOOLEAN;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF v_sec IS NULL OR NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: no hay un CRON_SECRET vigente que reutilizar';
    END IF;

    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname = 'gps-renault-rfms';
    PERFORM cron.schedule('gps-renault-rfms', '*/15 * * * *', format($p$
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/gps/renault/',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', %L),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000);
    $p$, v_sec));

    RAISE NOTICE 'Renault rFMS: cron gps-renault-rfms cada 15 min';
END
$cron$;
