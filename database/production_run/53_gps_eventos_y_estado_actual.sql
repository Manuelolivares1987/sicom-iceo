-- ============================================================================
-- 53_gps_eventos_y_estado_actual.sql
-- ----------------------------------------------------------------------------
-- Objetivo: ingesta de telemetria GPS (Navixy/Radicom y futuros proveedores)
--           para soportar:
--             (a) Mapa en vivo de la flota (lat/lng + estado por activo)
--             (b) Horometro + Odometro -> alimenta pautas preventivas
--                 (mig 34 ya consume activos.kilometraje_actual y horas_uso_actual)
--
-- Crea:
--   - gps_eventos_log         : log granular de telemetria (alto volumen)
--   - gps_estado_actual       : 1 fila por activo con ultimo estado (lectura rapida)
--   - fn_actualizar_estado_gps: trigger AFTER INSERT en eventos -> upsert estado
--                               + sincroniza activos.{kilometraje,horas_uso}_actual
--   - rpc_ingestar_gps_batch  : RPC bulk insert llamado por Edge Function
--   - v_flota_posiciones      : vista para el mapa
--
-- NO INCLUYE (diferido):
--   - actividades_conductor (requiere tabla `conductores`)
--   - Deteccion automatica de actividad / alertas Ley 21.561
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP - tabla activos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='config_gps_proveedor') THEN
        RAISE EXCEPTION 'STOP - tabla config_gps_proveedor no existe (correr MIG52 primero).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='gps_activo_mapeo') THEN
        RAISE EXCEPTION 'STOP - tabla gps_activo_mapeo no existe (correr MIG52 primero).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - falta fn_user_rol().';
    END IF;
END $$;


-- ============================================================================
-- 1. gps_eventos_log — historial granular de telemetria
-- ============================================================================
CREATE TABLE IF NOT EXISTS gps_eventos_log (
    id              BIGSERIAL    PRIMARY KEY,
    proveedor_id    UUID         NOT NULL REFERENCES config_gps_proveedor(id) ON DELETE CASCADE,
    gps_device_id   VARCHAR(100) NOT NULL,
    activo_id       UUID         REFERENCES activos(id) ON DELETE SET NULL,

    -- Telemetria
    ts_gps          TIMESTAMPTZ  NOT NULL,                  -- Timestamp reportado por el GPS
    ts_ingestado    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    latitud         NUMERIC(10,7),
    longitud        NUMERIC(10,7),
    velocidad_kmh   NUMERIC(6,2),
    heading         NUMERIC(5,1),                           -- 0..359 grados
    altitud_m       NUMERIC(8,1),

    -- Motor / movimiento
    ignicion        BOOLEAN,
    movimiento      VARCHAR(20),                            -- 'moving','parked','idle'
    conexion        VARCHAR(20),                            -- 'online','idle','offline'

    -- Counters (vienen de tracker/get_counters)
    odometro_km     NUMERIC(12,2),
    horometro_hrs   NUMERIC(12,2),

    -- Energia / red
    bateria_pct     NUMERIC(5,1),
    gsm_red         VARCHAR(50),
    gsm_signal      NUMERIC(5,1),

    -- I/O y evento crudo
    inputs          JSONB,
    outputs         JSONB,
    payload_raw     JSONB,

    CONSTRAINT chk_gps_log_lat  CHECK (latitud  IS NULL OR (latitud  BETWEEN -90 AND 90)),
    CONSTRAINT chk_gps_log_lng  CHECK (longitud IS NULL OR (longitud BETWEEN -180 AND 180)),
    CONSTRAINT chk_gps_log_vel  CHECK (velocidad_kmh IS NULL OR velocidad_kmh >= 0)
);

CREATE INDEX IF NOT EXISTS idx_gps_log_device_ts ON gps_eventos_log (gps_device_id, ts_gps DESC);
CREATE INDEX IF NOT EXISTS idx_gps_log_activo_ts ON gps_eventos_log (activo_id, ts_gps DESC) WHERE activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gps_log_ts        ON gps_eventos_log (ts_gps DESC);
CREATE INDEX IF NOT EXISTS idx_gps_log_proveedor ON gps_eventos_log (proveedor_id);


-- ============================================================================
-- 2. gps_estado_actual — 1 fila por activo, lectura rapida para el mapa
-- ============================================================================
CREATE TABLE IF NOT EXISTS gps_estado_actual (
    activo_id        UUID         PRIMARY KEY REFERENCES activos(id) ON DELETE CASCADE,
    proveedor_id     UUID         NOT NULL REFERENCES config_gps_proveedor(id) ON DELETE CASCADE,
    gps_device_id    VARCHAR(100) NOT NULL,

    ts_gps           TIMESTAMPTZ,
    ts_actualizado   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    latitud          NUMERIC(10,7),
    longitud         NUMERIC(10,7),
    velocidad_kmh    NUMERIC(6,2),
    heading          NUMERIC(5,1),
    ignicion         BOOLEAN,
    movimiento       VARCHAR(20),
    conexion         VARCHAR(20),
    odometro_km      NUMERIC(12,2),
    horometro_hrs    NUMERIC(12,2),
    bateria_pct      NUMERIC(5,1),
    gsm_red          VARCHAR(50)
);

CREATE INDEX IF NOT EXISTS idx_gps_estado_ts ON gps_estado_actual (ts_gps DESC);


-- ============================================================================
-- 3. Trigger: cada INSERT en gps_eventos_log
--    (a) upserts estado actual (solo si el evento es mas nuevo que el estado)
--    (b) sincroniza activos.{kilometraje,horas_uso}_actual si vienen counters
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_actualizar_estado_gps()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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
        odometro_km, horometro_hrs, bateria_pct, gsm_red
    ) VALUES (
        NEW.activo_id, NEW.proveedor_id, NEW.gps_device_id,
        NEW.ts_gps, NOW(),
        NEW.latitud, NEW.longitud, NEW.velocidad_kmh, NEW.heading,
        NEW.ignicion, NEW.movimiento, NEW.conexion,
        NEW.odometro_km, NEW.horometro_hrs, NEW.bateria_pct, NEW.gsm_red
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
           gsm_red        = EXCLUDED.gsm_red
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
$$;

DROP TRIGGER IF EXISTS trg_gps_eventos_estado ON gps_eventos_log;
CREATE TRIGGER trg_gps_eventos_estado
    AFTER INSERT ON gps_eventos_log
    FOR EACH ROW EXECUTE FUNCTION fn_actualizar_estado_gps();


-- ============================================================================
-- 4. RPC: ingesta batch desde Edge Function
-- ============================================================================
-- La Edge Function consulta tracker/get_states + tracker/get_counters en Navixy
-- y envia un JSONB con N eventos. Esta RPC los inserta en bulk y dispara el
-- trigger por cada uno.
--
-- Formato esperado de p_eventos:
--   [
--     { "gps_device_id":"10442078", "ts_gps":"2026-05-17T12:00:00Z",
--       "lat":-22.44, "lng":-68.93, "speed":0, "heading":247,
--       "ignition":false, "movement":"parked", "connection":"idle",
--       "odometer_km":13140.95, "engine_hours":null,
--       "battery_pct":100, "gsm_network":"Entel",
--       "payload":{ ... raw ... } },
--     ...
--   ]
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_ingestar_gps_batch(
    p_proveedor_nombre TEXT,
    p_eventos          JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_proveedor_id UUID;
    v_ev           JSONB;
    v_activo_id    UUID;
    v_insertados   INTEGER := 0;
    v_sin_mapeo    INTEGER := 0;
    v_errores      INTEGER := 0;
BEGIN
    -- 1. Resolver proveedor
    SELECT id INTO v_proveedor_id
      FROM config_gps_proveedor
     WHERE nombre = p_proveedor_nombre
       AND activo = true
     LIMIT 1;

    IF v_proveedor_id IS NULL THEN
        RAISE EXCEPTION 'Proveedor GPS no encontrado o inactivo: %', p_proveedor_nombre;
    END IF;

    -- 2. Procesar cada evento
    FOR v_ev IN SELECT * FROM jsonb_array_elements(p_eventos)
    LOOP
        BEGIN
            -- Buscar mapeo dispositivo -> activo
            SELECT activo_id INTO v_activo_id
              FROM gps_activo_mapeo
             WHERE proveedor_id = v_proveedor_id
               AND gps_device_id = v_ev->>'gps_device_id'
               AND activo = true
             LIMIT 1;

            IF v_activo_id IS NULL THEN
                v_sin_mapeo := v_sin_mapeo + 1;
            END IF;

            INSERT INTO gps_eventos_log (
                proveedor_id, gps_device_id, activo_id,
                ts_gps,
                latitud, longitud, velocidad_kmh, heading, altitud_m,
                ignicion, movimiento, conexion,
                odometro_km, horometro_hrs,
                bateria_pct, gsm_red, gsm_signal,
                inputs, outputs, payload_raw
            ) VALUES (
                v_proveedor_id,
                v_ev->>'gps_device_id',
                v_activo_id,
                COALESCE(NULLIF(v_ev->>'ts_gps','')::TIMESTAMPTZ, NOW()),
                NULLIF(v_ev->>'lat','')::NUMERIC,
                NULLIF(v_ev->>'lng','')::NUMERIC,
                NULLIF(v_ev->>'speed','')::NUMERIC,
                NULLIF(v_ev->>'heading','')::NUMERIC,
                NULLIF(v_ev->>'altitude','')::NUMERIC,
                NULLIF(v_ev->>'ignition','')::BOOLEAN,
                NULLIF(v_ev->>'movement',''),
                NULLIF(v_ev->>'connection',''),
                NULLIF(v_ev->>'odometer_km','')::NUMERIC,
                NULLIF(v_ev->>'engine_hours','')::NUMERIC,
                NULLIF(v_ev->>'battery_pct','')::NUMERIC,
                NULLIF(v_ev->>'gsm_network',''),
                NULLIF(v_ev->>'gsm_signal','')::NUMERIC,
                v_ev->'inputs',
                v_ev->'outputs',
                v_ev->'payload'
            );
            v_insertados := v_insertados + 1;

        EXCEPTION WHEN OTHERS THEN
            v_errores := v_errores + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'insertados',   v_insertados,
        'sin_mapeo',    v_sin_mapeo,
        'errores',      v_errores,
        'proveedor_id', v_proveedor_id,
        'ts',           NOW()
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_ingestar_gps_batch(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ingestar_gps_batch(TEXT, JSONB) TO service_role;


-- ============================================================================
-- 5. Vista para el mapa: posicion actual + datos del activo + mapeo
-- ============================================================================
CREATE OR REPLACE VIEW v_flota_posiciones AS
SELECT
    a.id                   AS activo_id,
    a.codigo               AS activo_codigo,
    a.nombre               AS activo_nombre,
    a.tipo                 AS activo_tipo,
    a.estado               AS activo_estado,
    a.kilometraje_actual   AS km_actual,
    a.horas_uso_actual     AS horas_actual,
    gam.gps_device_id,
    gam.gps_device_name,
    gam.imei,
    p.nombre               AS proveedor,
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
    -- Estado simplificado para colorear pin en mapa.
    -- Usa `conexion` (Navixy connection_status) en vez de "ts_gps > 2h": un
    -- tracker idle parqueado por horas no reporta nueva posicion pero SI
    -- esta conectado -> se debe mostrar como 'detenido', no 'sin_senal'.
    CASE
        WHEN e.ts_gps IS NULL OR e.conexion IS NULL   THEN 'sin_datos'
        WHEN e.conexion = 'offline'                    THEN 'sin_senal'
        WHEN COALESCE(e.velocidad_kmh,0) >= 5         THEN 'en_ruta'
        WHEN e.ignicion = true                         THEN 'detenido_motor_on'
        ELSE                                                'detenido'
    END AS estado_pin,
    -- Minutos desde el ultimo reporte (util para mostrar "hace X min")
    CASE WHEN e.ts_gps IS NULL THEN NULL
         ELSE EXTRACT(EPOCH FROM (NOW() - e.ts_gps))::INTEGER / 60
    END AS minutos_desde_reporte
FROM gps_activo_mapeo gam
JOIN config_gps_proveedor p ON p.id = gam.proveedor_id
JOIN activos a              ON a.id = gam.activo_id
LEFT JOIN gps_estado_actual e ON e.activo_id = a.id
WHERE gam.activo = true
  AND p.activo  = true
  AND a.estado <> 'dado_baja';

GRANT SELECT ON v_flota_posiciones TO authenticated;


-- ============================================================================
-- 6. RLS
-- ============================================================================
ALTER TABLE gps_eventos_log    ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_estado_actual  ENABLE ROW LEVEL SECURITY;

-- gps_eventos_log: lectura abierta a authenticated. Solo service_role escribe
-- (la Edge Function entra con service_role via la RPC rpc_ingestar_gps_batch).
DROP POLICY IF EXISTS pol_gps_eventos_select ON gps_eventos_log;
CREATE POLICY pol_gps_eventos_select ON gps_eventos_log
    FOR SELECT TO authenticated USING (true);

-- INSERT solo permitido a admin desde la UI; produccion lo hace service_role
-- (que bypasea RLS) via rpc_ingestar_gps_batch.
DROP POLICY IF EXISTS pol_gps_eventos_insert ON gps_eventos_log;
CREATE POLICY pol_gps_eventos_insert ON gps_eventos_log
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones'));

-- gps_estado_actual: lectura abierta. Escritura solo via trigger (service_role).
DROP POLICY IF EXISTS pol_gps_estado_select ON gps_estado_actual;
CREATE POLICY pol_gps_estado_select ON gps_estado_actual
    FOR SELECT TO authenticated USING (true);


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_gps_eventos_log',     to_regclass('public.gps_eventos_log')   IS NOT NULL,
    'tabla_gps_estado_actual',   to_regclass('public.gps_estado_actual') IS NOT NULL,
    'fn_actualizar_estado_gps',  EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_actualizar_estado_gps'),
    'trigger_estado_creado',     EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_gps_eventos_estado'),
    'rpc_ingestar_gps_batch',    EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_ingestar_gps_batch'),
    'vista_flota_posiciones',    to_regclass('public.v_flota_posiciones') IS NOT NULL,
    'rls_eventos_log',           (SELECT relrowsecurity FROM pg_class WHERE relname='gps_eventos_log'),
    'rls_estado_actual',         (SELECT relrowsecurity FROM pg_class WHERE relname='gps_estado_actual')
) AS resultado;

NOTIFY pgrst, 'reload schema';
