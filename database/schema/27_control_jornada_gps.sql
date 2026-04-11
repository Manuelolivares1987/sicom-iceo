-- ============================================================================
-- SICOM-ICEO | Migración 27 — Control de Jornada en Tiempo Real + API GPS
-- ============================================================================
-- Propósito : Sistema de registro de actividades de conductores en tiempo real
--             (Fase 1: manual desde app, Fase 2: automático vía GPS API).
--             Control de tiempos de espera (Ley 21.561: máx 88 hrs/mes),
--             descansos obligatorios (cada 5 hrs conducción) y jornada.
-- ============================================================================

-- ============================================================================
-- 1. TIPOS ENUMERADOS
-- ============================================================================

-- Tipo de actividad del conductor (lo que está haciendo en este momento)
CREATE TYPE actividad_conductor_enum AS ENUM (
    'conduccion',         -- En ruta, vehículo en movimiento
    'espera',             -- Motor encendido, detenido (cola de carga, espera instrucciones)
    'carga_descarga',     -- En operación de carga o descarga activa
    'descanso',           -- Descanso obligatorio o voluntario
    'mantencion',         -- Realizando o esperando mantención del vehículo
    'pernocte',           -- Descanso nocturno / fin de turno
    'traslado_interno',   -- Movimiento dentro de faena (baja velocidad)
    'disponible'          -- En base, listo pero sin tarea asignada
);

-- Fuente del registro (cómo se capturó el dato)
CREATE TYPE fuente_registro_enum AS ENUM (
    'app_manual',         -- Conductor tocó botón en la app
    'gps_automatico',     -- Detectado automáticamente por GPS/telemetría
    'supervisor',         -- Registrado por supervisor
    'api_externa',        -- Recibido de sistema externo (GPS provider API)
    'sistema'             -- Generado por lógica del sistema (ej: cierre automático)
);

-- ============================================================================
-- 2. REGISTRO DE ACTIVIDADES EN TIEMPO REAL
-- ============================================================================
-- Cada vez que el conductor cambia de actividad, se cierra el registro anterior
-- y se abre uno nuevo. Esto permite calcular duraciones exactas.

CREATE TABLE IF NOT EXISTS actividades_conductor (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conductor_id    UUID        NOT NULL REFERENCES conductores(id),
    activo_id       UUID        REFERENCES activos(id),
    contrato_id     UUID        REFERENCES contratos(id),

    -- Actividad
    actividad       actividad_conductor_enum NOT NULL,
    fuente          fuente_registro_enum NOT NULL DEFAULT 'app_manual',

    -- Tiempo
    inicio          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fin             TIMESTAMPTZ,                           -- NULL = actividad en curso
    duracion_min    NUMERIC(8,1),                          -- Calculado al cerrar

    -- Ubicación (desde GPS o manual)
    latitud         NUMERIC(10,7),
    longitud        NUMERIC(10,7),
    ubicacion_texto VARCHAR(200),                          -- "Cola de carga - Spence"
    velocidad_kmh   NUMERIC(5,1),                          -- Velocidad al momento del registro

    -- Ruta
    origen          VARCHAR(200),
    destino         VARCHAR(200),
    km_recorridos   NUMERIC(10,1) DEFAULT 0,

    -- Geofence (para detección automática)
    geofence_id     VARCHAR(50),                           -- ID del geofence en el GPS
    geofence_nombre VARCHAR(200),                          -- "Zona carga Spence", "Taller Pillado"

    -- Datos GPS raw (para auditoría)
    gps_datos_raw   JSONB,                                 -- Payload completo del GPS

    -- Alertas generadas
    alerta_5hrs     BOOLEAN     DEFAULT false,             -- ¿Superó 5 hrs conducción continua?
    alerta_espera   BOOLEAN     DEFAULT false,             -- ¿Espera acumulada mes > 70 hrs?

    -- Auditoría
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID        REFERENCES auth.users(id),

    -- Si tiene fin, duracion debe estar calculada
    CONSTRAINT chk_actividad_duracion
        CHECK (fin IS NULL OR duracion_min IS NOT NULL)
);

CREATE INDEX idx_act_conductor ON actividades_conductor (conductor_id);
CREATE INDEX idx_act_activo ON actividades_conductor (activo_id);
CREATE INDEX idx_act_inicio ON actividades_conductor (inicio);
CREATE INDEX idx_act_actividad ON actividades_conductor (actividad);
CREATE INDEX idx_act_abierta ON actividades_conductor (conductor_id, fin)
    WHERE fin IS NULL;  -- Actividades en curso
-- Índice compuesto para filtros por conductor + rango temporal.
-- Nota: no usamos (inicio::DATE) porque el cast TIMESTAMPTZ→DATE no es IMMUTABLE
-- (depende del timezone de sesión). Indexar sobre `inicio` permite los mismos
-- filtros por rango de fecha vía `inicio >= :d AND inicio < :d + 1`.
CREATE INDEX idx_act_fecha ON actividades_conductor (conductor_id, inicio);

-- ============================================================================
-- 3. CONFIGURACIÓN GPS / TELEMETRÍA POR PROVEEDOR
-- ============================================================================

CREATE TABLE IF NOT EXISTS config_gps_proveedor (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(100) NOT NULL,                 -- "Wialon", "Geotab", "Samsara"
    activo          BOOLEAN     NOT NULL DEFAULT true,

    -- Conexión API
    api_base_url    VARCHAR(500),                          -- "https://hst-api.wialon.com/wialon/ajax.html"
    api_token       VARCHAR(500),                          -- Token encriptado
    api_tipo_auth   VARCHAR(30)  DEFAULT 'token',          -- 'token', 'oauth2', 'api_key'
    webhook_secret  VARCHAR(200),                          -- Secret para validar webhooks entrantes

    -- Mapeo de datos
    config_mapeo    JSONB       NOT NULL DEFAULT '{}',
    -- Estructura esperada:
    -- {
    --   "campo_velocidad": "spd",
    --   "campo_ignicion": "in1",
    --   "campo_latitud": "lat",
    --   "campo_longitud": "lon",
    --   "umbral_velocidad_kmh": 5,        -- >5 km/h = conduciendo
    --   "umbral_idle_min": 3,             -- >3 min velocidad 0 + ignición ON = espera
    --   "umbral_parada_min": 15,          -- >15 min motor apagado = descanso
    --   "intervalo_polling_seg": 60
    -- }

    -- Geofences
    geofences       JSONB       DEFAULT '[]',
    -- [
    --   {"id": "gf001", "nombre": "Taller Pillado", "lat": -29.95, "lon": -71.34, "radio_m": 200, "tipo": "base"},
    --   {"id": "gf002", "nombre": "Spence - Zona Carga", "lat": -22.85, "lon": -68.83, "radio_m": 500, "tipo": "cliente"}
    -- ]

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_config_gps_updated_at
    BEFORE UPDATE ON config_gps_proveedor
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- 4. MAPEO GPS ↔ ACTIVO (qué dispositivo GPS tiene cada vehículo)
-- ============================================================================

CREATE TABLE IF NOT EXISTS gps_activo_mapeo (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID        NOT NULL REFERENCES activos(id),
    proveedor_id    UUID        NOT NULL REFERENCES config_gps_proveedor(id),

    -- Identificador del dispositivo en el sistema GPS
    gps_device_id   VARCHAR(100) NOT NULL,                 -- ID del equipo en Wialon/Geotab
    gps_device_name VARCHAR(200),                          -- Nombre en el sistema GPS
    imei            VARCHAR(20),                           -- IMEI del dispositivo

    activo          BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_gps_activo UNIQUE (activo_id, proveedor_id)
);

CREATE INDEX idx_gps_mapeo_device ON gps_activo_mapeo (gps_device_id);

-- ============================================================================
-- 5. LOG DE EVENTOS GPS (datos crudos recibidos del proveedor)
-- ============================================================================

CREATE TABLE IF NOT EXISTS gps_eventos_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    proveedor_id    UUID        REFERENCES config_gps_proveedor(id),
    gps_device_id   VARCHAR(100) NOT NULL,
    activo_id       UUID        REFERENCES activos(id),

    -- Datos del evento
    timestamp_gps   TIMESTAMPTZ NOT NULL,                  -- Timestamp del GPS
    latitud         NUMERIC(10,7),
    longitud        NUMERIC(10,7),
    velocidad_kmh   NUMERIC(5,1),
    ignicion        BOOLEAN,
    odometro_km     NUMERIC(12,1),
    horometro_hrs   NUMERIC(12,1),

    -- Evento detectado
    evento_tipo     VARCHAR(50),                           -- 'trip_start', 'trip_end', 'idle_start', 'geofence_enter', etc.
    geofence_id     VARCHAR(50),

    -- Raw payload
    payload_raw     JSONB,

    -- Procesado
    procesado       BOOLEAN     DEFAULT false,
    actividad_generada_id UUID  REFERENCES actividades_conductor(id),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Particionamos por fecha para rendimiento (tabla de alto volumen)
CREATE INDEX idx_gps_log_device_ts ON gps_eventos_log (gps_device_id, timestamp_gps);
CREATE INDEX idx_gps_log_no_procesado ON gps_eventos_log (procesado) WHERE procesado = false;
CREATE INDEX idx_gps_log_activo ON gps_eventos_log (activo_id, timestamp_gps);

-- ============================================================================
-- 6. FUNCIONES: Registro de actividad del conductor
-- ============================================================================

-- 6.1 Iniciar o cambiar actividad (cierra la anterior automáticamente)
CREATE OR REPLACE FUNCTION fn_registrar_actividad_conductor(
    p_conductor_id UUID,
    p_activo_id UUID,
    p_actividad actividad_conductor_enum,
    p_fuente fuente_registro_enum DEFAULT 'app_manual',
    p_ubicacion_texto VARCHAR DEFAULT NULL,
    p_latitud NUMERIC DEFAULT NULL,
    p_longitud NUMERIC DEFAULT NULL,
    p_velocidad NUMERIC DEFAULT NULL,
    p_origen VARCHAR DEFAULT NULL,
    p_destino VARCHAR DEFAULT NULL,
    p_geofence_id VARCHAR DEFAULT NULL,
    p_geofence_nombre VARCHAR DEFAULT NULL,
    p_gps_raw JSONB DEFAULT NULL,
    p_usuario_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_actividad_abierta RECORD;
    v_nueva_id UUID;
    v_duracion NUMERIC;
    v_conduccion_continua NUMERIC;
    v_espera_mes NUMERIC;
BEGIN
    -- 1. Cerrar actividad abierta del conductor (si existe)
    SELECT id, actividad, inicio
    INTO v_actividad_abierta
    FROM actividades_conductor
    WHERE conductor_id = p_conductor_id
      AND fin IS NULL
    ORDER BY inicio DESC
    LIMIT 1;

    IF v_actividad_abierta.id IS NOT NULL THEN
        v_duracion := EXTRACT(EPOCH FROM (NOW() - v_actividad_abierta.inicio)) / 60.0;

        UPDATE actividades_conductor
        SET fin = NOW(),
            duracion_min = ROUND(v_duracion, 1)
        WHERE id = v_actividad_abierta.id;
    END IF;

    -- 2. Crear nueva actividad
    INSERT INTO actividades_conductor (
        conductor_id, activo_id, actividad, fuente,
        inicio, ubicacion_texto, latitud, longitud, velocidad_kmh,
        origen, destino, geofence_id, geofence_nombre, gps_datos_raw,
        created_by
    ) VALUES (
        p_conductor_id, p_activo_id, p_actividad, p_fuente,
        NOW(), p_ubicacion_texto, p_latitud, p_longitud, p_velocidad,
        p_origen, p_destino, p_geofence_id, p_geofence_nombre, p_gps_raw,
        p_usuario_id
    )
    RETURNING id INTO v_nueva_id;

    -- 3. Verificar alerta: conducción continua > 5 hrs (Ley 21.561)
    IF p_actividad = 'conduccion' THEN
        SELECT COALESCE(SUM(duracion_min), 0)
        INTO v_conduccion_continua
        FROM actividades_conductor
        WHERE conductor_id = p_conductor_id
          AND actividad = 'conduccion'
          AND inicio > (
              -- Desde el último descanso
              SELECT COALESCE(MAX(fin), NOW() - INTERVAL '24 hours')
              FROM actividades_conductor
              WHERE conductor_id = p_conductor_id
                AND actividad IN ('descanso', 'pernocte')
                AND fin IS NOT NULL
          );

        IF v_conduccion_continua >= 300 THEN  -- 5 horas = 300 min
            UPDATE actividades_conductor SET alerta_5hrs = true WHERE id = v_nueva_id;

            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                'fatiga_conductor',
                'ALERTA Ley 21.561: Conductor supera 5 hrs conducción continua',
                format('Conductor con %s min de conducción continua. Requiere descanso mínimo de 2 hrs.',
                       v_conduccion_continua::INTEGER),
                'critical',
                'conductor',
                p_conductor_id
            );
        END IF;
    END IF;

    -- 4. Verificar alerta: horas de espera acumuladas en el mes
    IF p_actividad = 'espera' THEN
        SELECT COALESCE(SUM(duracion_min), 0) / 60.0
        INTO v_espera_mes
        FROM actividades_conductor
        WHERE conductor_id = p_conductor_id
          AND actividad = 'espera'
          AND inicio >= date_trunc('month', NOW());

        IF v_espera_mes >= 70 THEN  -- Alerta anticipada a 70 hrs
            UPDATE actividades_conductor SET alerta_espera = true WHERE id = v_nueva_id;

            IF NOT EXISTS (
                SELECT 1 FROM alertas
                WHERE entidad_id = p_conductor_id
                  AND tipo = 'fatiga_conductor'
                  AND created_at > NOW() - INTERVAL '1 day'
            ) THEN
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
                VALUES (
                    'fatiga_conductor',
                    CASE WHEN v_espera_mes >= 88
                        THEN 'BLOQUEO Ley 21.561: Conductor EXCEDE 88 hrs espera/mes'
                        ELSE format('ALERTA Ley 21.561: Conductor acumula %s hrs espera/mes', ROUND(v_espera_mes, 1))
                    END,
                    format('Horas de espera acumuladas: %s hrs. Límite legal: 88 hrs/mes.', ROUND(v_espera_mes, 1)),
                    CASE WHEN v_espera_mes >= 88 THEN 'critical' ELSE 'warning' END,
                    'conductor',
                    p_conductor_id
                );
            END IF;
        END IF;
    END IF;

    -- 5. Actualizar contador en tabla conductores
    UPDATE conductores
    SET horas_espera_mes_actual = (
        SELECT COALESCE(SUM(duracion_min), 0) / 60.0
        FROM actividades_conductor
        WHERE conductor_id = p_conductor_id
          AND actividad = 'espera'
          AND inicio >= date_trunc('month', NOW())
    )
    WHERE id = p_conductor_id;

    RETURN v_nueva_id;
END;
$$;

-- 6.2 Obtener actividad actual de un conductor
CREATE OR REPLACE FUNCTION fn_actividad_actual_conductor(p_conductor_id UUID)
RETURNS TABLE (
    actividad_id UUID,
    actividad actividad_conductor_enum,
    inicio TIMESTAMPTZ,
    duracion_actual_min NUMERIC,
    ubicacion VARCHAR,
    activo_patente VARCHAR
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ac.id,
        ac.actividad,
        ac.inicio,
        ROUND(EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0, 1),
        ac.ubicacion_texto,
        a.patente
    FROM actividades_conductor ac
    LEFT JOIN activos a ON a.id = ac.activo_id
    WHERE ac.conductor_id = p_conductor_id
      AND ac.fin IS NULL
    ORDER BY ac.inicio DESC
    LIMIT 1;
END;
$$;

-- 6.3 Resumen de jornada del día para un conductor
CREATE OR REPLACE FUNCTION fn_resumen_jornada_dia(
    p_conductor_id UUID,
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    actividad actividad_conductor_enum,
    total_minutos NUMERIC,
    total_horas NUMERIC,
    cantidad_registros BIGINT,
    porcentaje NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_total_dia NUMERIC;
BEGIN
    -- Total de minutos registrados en el día
    SELECT COALESCE(SUM(
        CASE WHEN ac.fin IS NOT NULL
            THEN ac.duracion_min
            ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
        END
    ), 0)
    INTO v_total_dia
    FROM actividades_conductor ac
    WHERE ac.conductor_id = p_conductor_id
      AND ac.inicio::DATE = p_fecha;

    RETURN QUERY
    SELECT
        ac.actividad,
        ROUND(SUM(
            CASE WHEN ac.fin IS NOT NULL
                THEN ac.duracion_min
                ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
            END
        ), 1) AS total_minutos,
        ROUND(SUM(
            CASE WHEN ac.fin IS NOT NULL
                THEN ac.duracion_min
                ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
            END
        ) / 60.0, 2) AS total_horas,
        COUNT(*),
        CASE WHEN v_total_dia > 0
            THEN ROUND(SUM(
                CASE WHEN ac.fin IS NOT NULL
                    THEN ac.duracion_min
                    ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
                END
            ) / v_total_dia * 100, 1)
            ELSE 0
        END
    FROM actividades_conductor ac
    WHERE ac.conductor_id = p_conductor_id
      AND ac.inicio::DATE = p_fecha
    GROUP BY ac.actividad
    ORDER BY total_minutos DESC;
END;
$$;

-- 6.4 Resumen mensual para un conductor (para Ley 21.561)
CREATE OR REPLACE FUNCTION fn_resumen_jornada_mes(
    p_conductor_id UUID,
    p_mes DATE DEFAULT date_trunc('month', CURRENT_DATE)::DATE
)
RETURNS TABLE (
    actividad actividad_conductor_enum,
    total_horas NUMERIC,
    dias_con_actividad BIGINT,
    limite_legal NUMERIC,
    porcentaje_limite NUMERIC,
    estado_cumplimiento VARCHAR
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ac.actividad,
        ROUND(SUM(
            CASE WHEN ac.fin IS NOT NULL
                THEN ac.duracion_min
                ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
            END
        ) / 60.0, 1) AS total_horas,
        COUNT(DISTINCT ac.inicio::DATE) AS dias_con_actividad,
        CASE ac.actividad
            WHEN 'espera' THEN 88.0    -- Ley 21.561: máx 88 hrs espera/mes
            WHEN 'conduccion' THEN NULL -- Sin límite mensual directo (es por tramo)
            ELSE NULL
        END AS limite_legal,
        CASE ac.actividad
            WHEN 'espera' THEN ROUND(SUM(
                CASE WHEN ac.fin IS NOT NULL
                    THEN ac.duracion_min
                    ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0
                END
            ) / 60.0 / 88.0 * 100, 1)
            ELSE NULL
        END AS porcentaje_limite,
        CASE ac.actividad
            WHEN 'espera' THEN
                CASE
                    WHEN SUM(CASE WHEN ac.fin IS NOT NULL THEN ac.duracion_min
                             ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0 END) / 60.0 >= 88
                        THEN 'EXCEDIDO'
                    WHEN SUM(CASE WHEN ac.fin IS NOT NULL THEN ac.duracion_min
                             ELSE EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0 END) / 60.0 >= 70
                        THEN 'ALERTA'
                    ELSE 'OK'
                END
            ELSE 'N/A'
        END::VARCHAR
    FROM actividades_conductor ac
    WHERE ac.conductor_id = p_conductor_id
      AND ac.inicio >= p_mes
      AND ac.inicio < (p_mes + INTERVAL '1 month')
    GROUP BY ac.actividad
    ORDER BY total_horas DESC;
END;
$$;

-- ============================================================================
-- 7. FUNCIÓN: Procesar evento GPS y generar actividad automáticamente
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_procesar_evento_gps(
    p_proveedor_id UUID,
    p_device_id VARCHAR,
    p_timestamp TIMESTAMPTZ,
    p_lat NUMERIC,
    p_lon NUMERIC,
    p_velocidad NUMERIC,
    p_ignicion BOOLEAN,
    p_odometro NUMERIC DEFAULT NULL,
    p_horometro NUMERIC DEFAULT NULL,
    p_evento_tipo VARCHAR DEFAULT NULL,
    p_geofence_id VARCHAR DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_log_id UUID;
    v_mapeo RECORD;
    v_conductor_id UUID;
    v_activo_id UUID;
    v_config JSONB;
    v_umbral_velocidad NUMERIC;
    v_umbral_idle NUMERIC;
    v_actividad_actual RECORD;
    v_nueva_actividad actividad_conductor_enum;
    v_actividad_id UUID;
BEGIN
    -- 1. Buscar mapeo GPS → Activo
    SELECT gam.activo_id, a.id AS activo_found
    INTO v_mapeo
    FROM gps_activo_mapeo gam
    JOIN activos a ON a.id = gam.activo_id
    WHERE gam.gps_device_id = p_device_id
      AND gam.proveedor_id = p_proveedor_id
      AND gam.activo = true
    LIMIT 1;

    IF v_mapeo IS NULL THEN
        -- Device no mapeado, solo guardar log
        INSERT INTO gps_eventos_log (proveedor_id, gps_device_id, timestamp_gps,
            latitud, longitud, velocidad_kmh, ignicion, odometro_km, horometro_hrs,
            evento_tipo, geofence_id, payload_raw)
        VALUES (p_proveedor_id, p_device_id, p_timestamp,
            p_lat, p_lon, p_velocidad, p_ignicion, p_odometro, p_horometro,
            p_evento_tipo, p_geofence_id, p_payload)
        RETURNING id INTO v_log_id;
        RETURN v_log_id;
    END IF;

    v_activo_id := v_mapeo.activo_id;

    -- 2. Obtener configuración del proveedor
    SELECT config_mapeo INTO v_config
    FROM config_gps_proveedor WHERE id = p_proveedor_id;

    v_umbral_velocidad := COALESCE((v_config->>'umbral_velocidad_kmh')::NUMERIC, 5);
    v_umbral_idle := COALESCE((v_config->>'umbral_idle_min')::NUMERIC, 3);

    -- 3. Buscar conductor asignado al vehículo hoy (del estado diario)
    SELECT edf.conductor_id INTO v_conductor_id
    FROM estado_diario_flota edf
    WHERE edf.activo_id = v_activo_id
      AND edf.fecha = CURRENT_DATE;

    -- 4. Guardar evento en log
    INSERT INTO gps_eventos_log (proveedor_id, gps_device_id, activo_id, timestamp_gps,
        latitud, longitud, velocidad_kmh, ignicion, odometro_km, horometro_hrs,
        evento_tipo, geofence_id, payload_raw)
    VALUES (p_proveedor_id, p_device_id, v_activo_id, p_timestamp,
        p_lat, p_lon, p_velocidad, p_ignicion, p_odometro, p_horometro,
        p_evento_tipo, p_geofence_id, p_payload)
    RETURNING id INTO v_log_id;

    -- 5. Determinar actividad basada en reglas
    IF v_conductor_id IS NOT NULL THEN
        -- Obtener actividad actual
        SELECT ac.id, ac.actividad, ac.inicio
        INTO v_actividad_actual
        FROM actividades_conductor ac
        WHERE ac.conductor_id = v_conductor_id AND ac.fin IS NULL
        ORDER BY ac.inicio DESC LIMIT 1;

        -- Reglas de detección de actividad:
        IF p_ignicion = false THEN
            -- Motor apagado → descanso o pernocte
            v_nueva_actividad := 'descanso';
        ELSIF p_velocidad > v_umbral_velocidad THEN
            -- En movimiento → conducción
            v_nueva_actividad := 'conduccion';
        ELSIF p_velocidad <= v_umbral_velocidad AND p_ignicion = true THEN
            -- Detenido con motor encendido → espera (o carga/descarga si en geofence de cliente)
            IF p_geofence_id IS NOT NULL THEN
                v_nueva_actividad := 'carga_descarga';
            ELSE
                v_nueva_actividad := 'espera';
            END IF;
        ELSE
            v_nueva_actividad := 'disponible';
        END IF;

        -- Solo cambiar si la actividad es diferente a la actual
        IF v_actividad_actual.id IS NULL
           OR v_actividad_actual.actividad != v_nueva_actividad THEN

            -- Buscar geofence nombre
            DECLARE
                v_gf_nombre VARCHAR;
            BEGIN
                SELECT gf->>'nombre' INTO v_gf_nombre
                FROM config_gps_proveedor cgp,
                     jsonb_array_elements(cgp.geofences) gf
                WHERE cgp.id = p_proveedor_id
                  AND gf->>'id' = p_geofence_id
                LIMIT 1;

                SELECT fn_registrar_actividad_conductor(
                    v_conductor_id, v_activo_id, v_nueva_actividad,
                    'gps_automatico', v_gf_nombre,
                    p_lat, p_lon, p_velocidad,
                    NULL, NULL,
                    p_geofence_id, v_gf_nombre, p_payload, NULL
                ) INTO v_actividad_id;
            END;

            -- Marcar log como procesado
            UPDATE gps_eventos_log
            SET procesado = true, actividad_generada_id = v_actividad_id
            WHERE id = v_log_id;
        END IF;
    END IF;

    -- 6. Actualizar odómetro/horómetro del activo si viene dato
    IF p_odometro IS NOT NULL THEN
        UPDATE activos SET kilometraje_actual = p_odometro WHERE id = v_activo_id;
    END IF;
    IF p_horometro IS NOT NULL THEN
        UPDATE activos SET horas_uso_actual = p_horometro WHERE id = v_activo_id;
    END IF;

    RETURN v_log_id;
END;
$$;

-- ============================================================================
-- 8. VISTA: Panel de conductores en tiempo real
-- ============================================================================

CREATE OR REPLACE VIEW v_conductores_tiempo_real AS
SELECT
    c.id AS conductor_id,
    c.nombre_completo,
    c.rut,
    c.tipo_licencia,
    c.semep_vigente,
    c.semep_vencimiento,
    c.horas_espera_mes_actual,

    -- Actividad actual
    ac.id AS actividad_id,
    ac.actividad AS actividad_actual,
    ac.inicio AS actividad_inicio,
    ROUND(EXTRACT(EPOCH FROM (NOW() - ac.inicio)) / 60.0, 1) AS minutos_en_actividad,
    ac.ubicacion_texto,
    ac.latitud,
    ac.longitud,
    ac.fuente,

    -- Vehículo
    a.id AS activo_id,
    a.patente,
    a.nombre AS activo_nombre,

    -- Resumen del día
    (SELECT COALESCE(SUM(duracion_min), 0) / 60.0
     FROM actividades_conductor
     WHERE conductor_id = c.id AND actividad = 'conduccion'
       AND inicio::DATE = CURRENT_DATE) AS hrs_conduccion_hoy,

    (SELECT COALESCE(SUM(duracion_min), 0) / 60.0
     FROM actividades_conductor
     WHERE conductor_id = c.id AND actividad = 'espera'
       AND inicio::DATE = CURRENT_DATE) AS hrs_espera_hoy,

    -- Conducción continua (desde último descanso)
    (SELECT COALESCE(SUM(duracion_min), 0) / 60.0
     FROM actividades_conductor
     WHERE conductor_id = c.id AND actividad = 'conduccion'
       AND inicio > COALESCE(
           (SELECT MAX(fin) FROM actividades_conductor
            WHERE conductor_id = c.id AND actividad IN ('descanso', 'pernocte') AND fin IS NOT NULL),
           NOW() - INTERVAL '24 hours'
       )) AS hrs_conduccion_continua,

    -- Alertas
    CASE
        WHEN c.horas_espera_mes_actual >= 88 THEN 'EXCEDIDO'
        WHEN c.horas_espera_mes_actual >= 70 THEN 'ALERTA'
        ELSE 'OK'
    END AS estado_espera_mes,

    CASE WHEN c.semep_vencimiento < CURRENT_DATE THEN true ELSE false END AS semep_vencido

FROM conductores c
LEFT JOIN LATERAL (
    SELECT * FROM actividades_conductor
    WHERE conductor_id = c.id AND fin IS NULL
    ORDER BY inicio DESC LIMIT 1
) ac ON true
LEFT JOIN activos a ON a.id = ac.activo_id
WHERE c.activo = true;

-- ============================================================================
-- 9. API ENDPOINT: Función para recibir webhook de GPS
-- ============================================================================
-- Esta función se expone como RPC de Supabase y puede ser llamada
-- por un webhook del proveedor GPS o por un middleware.

CREATE OR REPLACE FUNCTION rpc_webhook_gps(
    p_provider VARCHAR,        -- Nombre del proveedor
    p_secret VARCHAR,          -- Secret para validación
    p_events JSONB             -- Array de eventos
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_proveedor RECORD;
    v_event JSONB;
    v_processed INTEGER := 0;
    v_errors INTEGER := 0;
BEGIN
    -- Validar proveedor y secret
    SELECT id, config_mapeo INTO v_proveedor
    FROM config_gps_proveedor
    WHERE nombre = p_provider
      AND webhook_secret = p_secret
      AND activo = true;

    IF v_proveedor.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Proveedor no autorizado', 'processed', 0);
    END IF;

    -- Procesar cada evento
    FOR v_event IN SELECT * FROM jsonb_array_elements(p_events)
    LOOP
        BEGIN
            PERFORM fn_procesar_evento_gps(
                v_proveedor.id,
                v_event->>'device_id',
                (v_event->>'timestamp')::TIMESTAMPTZ,
                (v_event->>'lat')::NUMERIC,
                (v_event->>'lon')::NUMERIC,
                (v_event->>'speed')::NUMERIC,
                (v_event->>'ignition')::BOOLEAN,
                (v_event->>'odometer')::NUMERIC,
                (v_event->>'hourmeter')::NUMERIC,
                v_event->>'event_type',
                v_event->>'geofence_id',
                v_event
            );
            v_processed := v_processed + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'processed', v_processed,
        'errors', v_errors,
        'timestamp', NOW()
    );
END;
$$;

-- ============================================================================
-- 10. SINCRONIZACIÓN: Resumen diario automático desde actividades
-- ============================================================================
-- Al final del día, consolida actividades_conductor → registro_jornada_conductor

CREATE OR REPLACE FUNCTION fn_consolidar_jornada_diaria(p_fecha DATE DEFAULT CURRENT_DATE - 1)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_conductor RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_conductor IN
        SELECT DISTINCT conductor_id
        FROM actividades_conductor
        WHERE inicio::DATE = p_fecha
    LOOP
        INSERT INTO registro_jornada_conductor (
            conductor_id,
            activo_id,
            fecha,
            horas_conduccion,
            horas_espera,
            horas_descanso,
            km_recorridos,
            alerta_5hrs_sin_descanso,
            alerta_espera_acumulada
        )
        SELECT
            v_conductor.conductor_id,
            (SELECT activo_id FROM actividades_conductor
             WHERE conductor_id = v_conductor.conductor_id
               AND inicio::DATE = p_fecha AND activo_id IS NOT NULL
             LIMIT 1),
            p_fecha,
            COALESCE(SUM(duracion_min) FILTER (WHERE actividad = 'conduccion'), 0) / 60.0,
            COALESCE(SUM(duracion_min) FILTER (WHERE actividad = 'espera'), 0) / 60.0,
            COALESCE(SUM(duracion_min) FILTER (WHERE actividad IN ('descanso', 'pernocte')), 0) / 60.0,
            COALESCE(SUM(km_recorridos), 0),
            EXISTS (SELECT 1 FROM actividades_conductor WHERE conductor_id = v_conductor.conductor_id
                    AND inicio::DATE = p_fecha AND alerta_5hrs = true),
            EXISTS (SELECT 1 FROM actividades_conductor WHERE conductor_id = v_conductor.conductor_id
                    AND inicio::DATE = p_fecha AND alerta_espera = true)
        FROM actividades_conductor
        WHERE conductor_id = v_conductor.conductor_id
          AND inicio::DATE = p_fecha
        ON CONFLICT (conductor_id, fecha) DO UPDATE
        SET horas_conduccion = EXCLUDED.horas_conduccion,
            horas_espera = EXCLUDED.horas_espera,
            horas_descanso = EXCLUDED.horas_descanso,
            km_recorridos = EXCLUDED.km_recorridos,
            alerta_5hrs_sin_descanso = EXCLUDED.alerta_5hrs_sin_descanso,
            alerta_espera_acumulada = EXCLUDED.alerta_espera_acumulada;

        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;

-- ============================================================================
-- 11. COMENTARIOS
-- ============================================================================

COMMENT ON TABLE actividades_conductor IS
    'Registro granular de actividades en tiempo real. Cada cambio de estado '
    '(conducción→espera→descanso) genera un registro. Fuente: app manual o GPS automático.';

COMMENT ON TABLE config_gps_proveedor IS
    'Configuración de proveedores GPS/telemetría (Wialon, Geotab, Samsara, etc.). '
    'Incluye credenciales API, reglas de detección y geofences.';

COMMENT ON TABLE gps_activo_mapeo IS
    'Mapeo entre dispositivos GPS y activos del sistema. '
    'Permite vincular datos de telemetría con vehículos específicos.';

COMMENT ON TABLE gps_eventos_log IS
    'Log de alto volumen con datos crudos del GPS. '
    'Se procesa para generar actividades_conductor automáticamente.';

COMMENT ON FUNCTION fn_registrar_actividad_conductor IS
    'Registra cambio de actividad del conductor. Cierra actividad anterior, '
    'abre nueva, verifica alertas (5hrs conducción, 88hrs espera/mes).';

COMMENT ON FUNCTION fn_procesar_evento_gps IS
    'Procesa evento GPS y determina actividad del conductor por reglas: '
    'vel>5=conducción, vel=0+ignición=espera, motor apagado=descanso.';

COMMENT ON FUNCTION rpc_webhook_gps IS
    'Endpoint RPC expuesto para recibir datos de proveedores GPS vía webhook. '
    'Valida proveedor por secret, procesa batch de eventos.';
