-- ============================================================================
-- 56_geocercas_y_eventos.sql
-- ----------------------------------------------------------------------------
-- Modulo de geocercas (V1 — solo circulos haversine). Cuando un activo
-- cruza el limite de una geocerca, se registra un evento entrada/salida y
-- se crea una alerta. NO cambia el estado_comercial del activo
-- automaticamente (decision de Manuel 2026-05-18 — modo seguro).
--
-- Crea:
--   - gps_geocercas              : catalogo (base_pillado, faena_cliente)
--   - gps_geocerca_eventos       : log de entradas/salidas
--   - fn_distancia_haversine     : utilidad metros entre 2 puntos lat/lng
--   - fn_punto_en_geocerca       : punto dentro de circulo
--   - fn_evaluar_geocercas_estado: trigger AFTER UPDATE gps_estado_actual
--                                  -> detecta crossings -> evento + alerta
--
-- POLIGONOS: diferido a V2 (requiere PostGIS o ray casting puro PG).
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='gps_estado_actual') THEN
        RAISE EXCEPTION 'STOP - MIG53 no aplicada (falta gps_estado_actual).';
    END IF;
END $$;


-- ============================================================================
-- 1. ENUMS
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_geocerca_enum') THEN
        CREATE TYPE tipo_geocerca_enum AS ENUM (
            'base_pillado',      -- sede / taller Pillado
            'faena_cliente',     -- faena de un cliente especifico (FK contrato)
            'bodega',            -- bodega central / combustible
            'taller_externo',    -- taller de tercero (SALFA, Kaufmann, etc.)
            'zona_restringida',  -- zona con prohibicion / alerta especial
            'punto_interes'      -- generico (peaje, control, etc.)
        );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_geocerca_evento_enum') THEN
        CREATE TYPE tipo_geocerca_evento_enum AS ENUM ('entrada', 'salida');
    END IF;
END $$;


-- ============================================================================
-- 2. TABLA gps_geocercas — catalogo de zonas
-- ============================================================================
CREATE TABLE IF NOT EXISTS gps_geocercas (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre        VARCHAR(200) NOT NULL,
    tipo          tipo_geocerca_enum NOT NULL,
    -- V1: solo circulos (centro + radio). V2: polygon_geom JSONB
    centro_lat    NUMERIC(10,7) NOT NULL,
    centro_lng    NUMERIC(10,7) NOT NULL,
    radio_m       NUMERIC(10,1) NOT NULL,
    -- Asociacion opcional
    contrato_id   UUID         REFERENCES contratos(id) ON DELETE SET NULL,
    color         VARCHAR(20)  DEFAULT '#3B82F6',     -- color del poligono en mapa
    descripcion   TEXT,
    activo        BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by    UUID         REFERENCES auth.users(id),
    CONSTRAINT chk_geo_lat    CHECK (centro_lat  BETWEEN -90 AND 90),
    CONSTRAINT chk_geo_lng    CHECK (centro_lng  BETWEEN -180 AND 180),
    CONSTRAINT chk_geo_radio  CHECK (radio_m > 0 AND radio_m <= 1000000)  -- max 1000 km
);

CREATE INDEX IF NOT EXISTS idx_geocercas_activo   ON gps_geocercas (activo) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_geocercas_tipo     ON gps_geocercas (tipo);
CREATE INDEX IF NOT EXISTS idx_geocercas_contrato ON gps_geocercas (contrato_id) WHERE contrato_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_geocercas_updated_at ON gps_geocercas;
CREATE TRIGGER trg_geocercas_updated_at
    BEFORE UPDATE ON gps_geocercas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 3. TABLA gps_geocerca_eventos — log entradas/salidas
-- ============================================================================
CREATE TABLE IF NOT EXISTS gps_geocerca_eventos (
    id             BIGSERIAL    PRIMARY KEY,
    geocerca_id    UUID         NOT NULL REFERENCES gps_geocercas(id) ON DELETE CASCADE,
    activo_id      UUID         NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    tipo_evento    tipo_geocerca_evento_enum NOT NULL,
    ts             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    latitud        NUMERIC(10,7),
    longitud       NUMERIC(10,7),
    velocidad_kmh  NUMERIC(6,2),
    contrato_id    UUID         REFERENCES contratos(id),
    alerta_id      UUID         REFERENCES alertas(id) ON DELETE SET NULL,
    notas          TEXT,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geo_eventos_activo_ts  ON gps_geocerca_eventos (activo_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_geo_eventos_geocerca   ON gps_geocerca_eventos (geocerca_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_geo_eventos_ts         ON gps_geocerca_eventos (ts DESC);


-- ============================================================================
-- 4. fn_distancia_haversine — metros entre 2 coordenadas lat/lng
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_distancia_haversine(
    lat1 NUMERIC, lng1 NUMERIC, lat2 NUMERIC, lng2 NUMERIC
) RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    R       NUMERIC := 6371000;   -- radio Tierra en metros
    dlat    NUMERIC;
    dlng    NUMERIC;
    a       NUMERIC;
BEGIN
    IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
        RETURN NULL;
    END IF;
    dlat := radians(lat2 - lat1);
    dlng := radians(lng2 - lng1);
    a := sin(dlat/2)^2 +
         cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng/2)^2;
    RETURN R * 2 * atan2(sqrt(a), sqrt(1 - a));
END;
$$;


-- ============================================================================
-- 5. fn_punto_en_geocerca — TRUE si el punto esta dentro del circulo
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_punto_en_geocerca(
    p_lat NUMERIC, p_lng NUMERIC, p_geocerca_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    g RECORD;
BEGIN
    IF p_lat IS NULL OR p_lng IS NULL OR p_geocerca_id IS NULL THEN
        RETURN false;
    END IF;
    SELECT centro_lat, centro_lng, radio_m INTO g
      FROM gps_geocercas WHERE id = p_geocerca_id AND activo = true;
    IF g IS NULL THEN RETURN false; END IF;
    RETURN fn_distancia_haversine(p_lat, p_lng, g.centro_lat, g.centro_lng) <= g.radio_m;
END;
$$;


-- ============================================================================
-- 6. fn_evaluar_geocercas_estado — trigger AFTER UPDATE gps_estado_actual
-- ----------------------------------------------------------------------------
-- Por cada cambio de posicion de un activo, evalua TODAS las geocercas
-- activas. Si detecta cross (estaba afuera y ahora dentro = entrada; o
-- al reves = salida), registra evento + alerta.
--
-- Estado anterior: se infiere consultando el ULTIMO gps_geocerca_evento
-- de cada (geocerca, activo). Si el ultimo fue 'entrada' -> estaba dentro.
-- Si 'salida' o no hay registros -> estaba afuera.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_evaluar_geocercas_estado()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    g           RECORD;
    estaba_dentro BOOLEAN;
    esta_dentro   BOOLEAN;
    v_alerta_id UUID;
    v_msg       TEXT;
    v_titulo    TEXT;
    v_activo_codigo VARCHAR;
BEGIN
    IF NEW.latitud IS NULL OR NEW.longitud IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT codigo INTO v_activo_codigo FROM activos WHERE id = NEW.activo_id;

    FOR g IN
        SELECT id, nombre, tipo, centro_lat, centro_lng, radio_m, contrato_id
          FROM gps_geocercas
         WHERE activo = true
    LOOP
        esta_dentro := fn_distancia_haversine(
            NEW.latitud, NEW.longitud, g.centro_lat, g.centro_lng
        ) <= g.radio_m;

        -- Inferir estado anterior desde ultimo evento
        SELECT (tipo_evento = 'entrada') INTO estaba_dentro
          FROM gps_geocerca_eventos
         WHERE geocerca_id = g.id AND activo_id = NEW.activo_id
         ORDER BY ts DESC
         LIMIT 1;

        estaba_dentro := COALESCE(estaba_dentro, false);

        -- Sin cambio -> skip
        IF esta_dentro = estaba_dentro THEN
            CONTINUE;
        END IF;

        -- Hay crossing: crear alerta primero
        IF esta_dentro THEN
            v_titulo := format('Entrada a %s: %s', g.tipo, g.nombre);
            v_msg    := format('Activo %s entro a la geocerca "%s" (%s).',
                               v_activo_codigo, g.nombre, g.tipo);
        ELSE
            v_titulo := format('Salida de %s: %s', g.tipo, g.nombre);
            v_msg    := format('Activo %s salio de la geocerca "%s" (%s).',
                               v_activo_codigo, g.nombre, g.tipo);
        END IF;

        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES (
            'incumplimiento',  -- tipo generico (alertas.chk_alertas_tipo restringido)
            v_titulo, v_msg, 'info', 'activo', NEW.activo_id
        )
        RETURNING id INTO v_alerta_id;

        -- Registrar evento
        INSERT INTO gps_geocerca_eventos (
            geocerca_id, activo_id, tipo_evento,
            ts, latitud, longitud, velocidad_kmh,
            contrato_id, alerta_id
        ) VALUES (
            g.id, NEW.activo_id,
            CASE WHEN esta_dentro THEN 'entrada'::tipo_geocerca_evento_enum
                 ELSE 'salida'::tipo_geocerca_evento_enum
            END,
            COALESCE(NEW.ts_gps, NOW()),
            NEW.latitud, NEW.longitud, NEW.velocidad_kmh,
            g.contrato_id, v_alerta_id
        );
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_geocercas_evaluar ON gps_estado_actual;
CREATE TRIGGER trg_geocercas_evaluar
    AFTER INSERT OR UPDATE OF latitud, longitud ON gps_estado_actual
    FOR EACH ROW EXECUTE FUNCTION fn_evaluar_geocercas_estado();


-- ============================================================================
-- 7. VISTA v_geocerca_ocupacion — quien esta DENTRO de cada geocerca AHORA
-- ============================================================================
CREATE OR REPLACE VIEW v_geocerca_ocupacion AS
WITH ultimo_evento AS (
    SELECT DISTINCT ON (geocerca_id, activo_id)
           geocerca_id, activo_id, tipo_evento, ts
      FROM gps_geocerca_eventos
     ORDER BY geocerca_id, activo_id, ts DESC
)
SELECT
    g.id            AS geocerca_id,
    g.nombre        AS geocerca_nombre,
    g.tipo          AS geocerca_tipo,
    g.contrato_id,
    c.codigo        AS contrato_codigo,
    c.cliente       AS cliente,
    a.id            AS activo_id,
    a.codigo        AS activo_codigo,
    a.patente       AS activo_patente,
    ue.ts           AS desde_ts,
    EXTRACT(EPOCH FROM (NOW() - ue.ts))::INTEGER / 60 AS minutos_dentro
  FROM ultimo_evento ue
  JOIN gps_geocercas g ON g.id = ue.geocerca_id AND g.activo = true
  JOIN activos a       ON a.id = ue.activo_id
  LEFT JOIN contratos c ON c.id = g.contrato_id
 WHERE ue.tipo_evento = 'entrada';

GRANT SELECT ON v_geocerca_ocupacion TO authenticated;


-- ============================================================================
-- 8. RLS
-- ============================================================================
ALTER TABLE gps_geocercas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_geocerca_eventos  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_geocercas_select ON gps_geocercas;
CREATE POLICY pol_geocercas_select ON gps_geocercas
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_geocercas_write ON gps_geocercas;
CREATE POLICY pol_geocercas_write ON gps_geocercas
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_geo_eventos_select ON gps_geocerca_eventos;
CREATE POLICY pol_geo_eventos_select ON gps_geocerca_eventos
    FOR SELECT TO authenticated USING (true);


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'enum_tipo_geocerca',     EXISTS(SELECT 1 FROM pg_type WHERE typname='tipo_geocerca_enum'),
    'tabla_gps_geocercas',    to_regclass('public.gps_geocercas') IS NOT NULL,
    'tabla_geo_eventos',      to_regclass('public.gps_geocerca_eventos') IS NOT NULL,
    'fn_haversine',           EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_distancia_haversine'),
    'fn_punto_en_geocerca',   EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_punto_en_geocerca'),
    'fn_evaluar_geocercas',   EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_evaluar_geocercas_estado'),
    'trigger_geo_evaluar',    EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_geocercas_evaluar'),
    'vista_ocupacion',        to_regclass('public.v_geocerca_ocupacion') IS NOT NULL
) AS resultado;

NOTIFY pgrst, 'reload schema';
