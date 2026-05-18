-- ============================================================================
-- 59_estado_por_geocerca_sugerencias_historico.sql
-- ----------------------------------------------------------------------------
-- Sistema de gestion de estado del activo segun geocerca:
--   1. Cada activo arrendado tiene una geocerca esperada (derivada del contrato)
--   2. Cron cada 15 min evalua si esta fuera de geocerca >= 2 horas continuas
--   3. Si esta fuera -> genera sugerencia de cambio estado (arrendado -> en_transito)
--   4. Si vuelve estando en en_transito -> sugiere volver a arrendado
--   5. Si lleva >= 24h en en_transito -> sugiere en_recepcion
--   6. Planificador aprueba/rechaza sugerencia (RPC)
--   7. Cualquier cambio en activos.estado_comercial queda en historico inmutable
--
-- Decisiones de Manuel (2026-05-18):
--   - Umbral fuera: 2 horas continuas
--   - Estado sugerido: en_transito (con auto-vuelta a arrendado/en_recepcion)
--   - Asignacion geocerca: automatica desde contrato
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='gps_geocercas') THEN
        RAISE EXCEPTION 'STOP - MIG56 no aplicada (falta gps_geocercas).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='gps_geocerca_eventos') THEN
        RAISE EXCEPTION 'STOP - MIG56 no aplicada (falta gps_geocerca_eventos).';
    END IF;
END $$;


-- ============================================================================
-- 0. EXTENDER estado_comercial_enum con 'en_transito'
-- ----------------------------------------------------------------------------
-- ALTER TYPE ... ADD VALUE no funciona dentro de un block/transaccion en PG.
-- Por eso este bloque corre standalone ANTES que los DO blocks siguientes.
-- IF NOT EXISTS lo hace idempotente desde PG 9.6+.
-- ============================================================================
ALTER TYPE estado_comercial_enum ADD VALUE IF NOT EXISTS 'en_transito';


-- ============================================================================
-- 1. ENUM accion_sugerencia
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='accion_sugerencia_enum') THEN
        CREATE TYPE accion_sugerencia_enum AS ENUM (
            'pendiente',   -- aun no revisada
            'aprobada',    -- planificador acepto -> se ejecuta cambio
            'rechazada',   -- planificador rechazo -> no se hace cambio
            'expirada',    -- pasaron N dias sin resolver
            'auto_revertida' -- el sistema mismo la cancelo (ej. volvio a geocerca)
        );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='origen_cambio_estado_enum') THEN
        CREATE TYPE origen_cambio_estado_enum AS ENUM (
            'manual',          -- usuario lo cambio directamente
            'sugerencia',      -- aprobado de sugerencias_estado
            'sistema',         -- automatico (trigger ready-to-rent, etc.)
            'importado'        -- data inicial
        );
    END IF;
END $$;


-- ============================================================================
-- 2. VISTA v_activo_geocerca_esperada
-- ----------------------------------------------------------------------------
-- Para cada activo arrendado, define la geocerca tipo 'faena_cliente' del
-- contrato vigente. Es la geocerca donde el activo DEBERIA estar.
-- ============================================================================
CREATE OR REPLACE VIEW v_activo_geocerca_esperada AS
SELECT
    a.id              AS activo_id,
    a.codigo          AS activo_codigo,
    a.patente         AS activo_patente,
    a.estado_comercial,
    a.contrato_id,
    c.codigo          AS contrato_codigo,
    c.cliente         AS cliente,
    g.id              AS geocerca_id,
    g.nombre          AS geocerca_nombre,
    g.centro_lat      AS geocerca_lat,
    g.centro_lng      AS geocerca_lng,
    g.radio_m         AS geocerca_radio_m
FROM activos a
LEFT JOIN contratos c       ON c.id = a.contrato_id
LEFT JOIN gps_geocercas g   ON g.contrato_id = a.contrato_id
                            AND g.tipo = 'faena_cliente'
                            AND g.activo = true
WHERE a.estado <> 'dado_baja'
  AND a.estado_comercial IN ('arrendado','en_transito','en_recepcion');

GRANT SELECT ON v_activo_geocerca_esperada TO authenticated;


-- ============================================================================
-- 3. TABLA cambios_estado_sugeridos
-- ============================================================================
CREATE TABLE IF NOT EXISTS cambios_estado_sugeridos (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id       UUID         NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    -- Contexto
    geocerca_id     UUID         REFERENCES gps_geocercas(id) ON DELETE SET NULL,
    estado_anterior estado_comercial_enum,
    estado_sugerido estado_comercial_enum NOT NULL,
    razon           TEXT         NOT NULL,
    minutos_fuera   INT,                              -- cuanto tiempo lleva fuera al generar
    origen          VARCHAR(40)  NOT NULL DEFAULT 'geocerca_auto',
    -- Estado de revision
    accion          accion_sugerencia_enum NOT NULL DEFAULT 'pendiente',
    validado_at     TIMESTAMPTZ,
    validado_por    UUID         REFERENCES auth.users(id),
    comentario      TEXT,
    -- Auditoria
    generado_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_validacion CHECK (accion = 'pendiente' OR validado_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_sugerencias_activo_accion
    ON cambios_estado_sugeridos (activo_id, accion);
CREATE INDEX IF NOT EXISTS idx_sugerencias_pendientes
    ON cambios_estado_sugeridos (generado_at DESC) WHERE accion = 'pendiente';
CREATE UNIQUE INDEX IF NOT EXISTS uq_sugerencia_pendiente_activo
    ON cambios_estado_sugeridos (activo_id) WHERE accion = 'pendiente';


-- ============================================================================
-- 4. TABLA historico_estado_activo
-- ============================================================================
CREATE TABLE IF NOT EXISTS historico_estado_activo (
    id                  BIGSERIAL    PRIMARY KEY,
    activo_id           UUID         NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    estado_anterior     estado_comercial_enum,
    estado_nuevo        estado_comercial_enum NOT NULL,
    cambio_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    cambio_por          UUID         REFERENCES auth.users(id),
    origen              origen_cambio_estado_enum NOT NULL DEFAULT 'manual',
    sugerencia_id       UUID         REFERENCES cambios_estado_sugeridos(id) ON DELETE SET NULL,
    contrato_id         UUID         REFERENCES contratos(id) ON DELETE SET NULL,
    razon               TEXT,
    -- Lectura GPS al momento (para auditoria comercial)
    latitud             NUMERIC(10,7),
    longitud            NUMERIC(10,7),
    horometro           NUMERIC(12,1),
    kilometraje         NUMERIC(12,1),
    -- Calculo de duracion en el estado anterior
    duracion_estado_anterior_horas NUMERIC(10,2)
);

CREATE INDEX IF NOT EXISTS idx_hist_estado_activo_fecha
    ON historico_estado_activo (activo_id, cambio_at DESC);
CREATE INDEX IF NOT EXISTS idx_hist_estado_contrato
    ON historico_estado_activo (contrato_id, cambio_at DESC) WHERE contrato_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_hist_estado_nuevo
    ON historico_estado_activo (estado_nuevo, cambio_at DESC);


-- ============================================================================
-- 5. TRIGGER: AFTER UPDATE OF estado_comercial en activos -> historico
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_registrar_historico_estado_activo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_ultimo_cambio TIMESTAMPTZ;
    v_duracion      NUMERIC;
    v_lat           NUMERIC;
    v_lng           NUMERIC;
    v_horo          NUMERIC;
    v_km            NUMERIC;
    v_origen        origen_cambio_estado_enum := 'manual';
BEGIN
    -- Solo registrar si efectivamente cambio
    IF NEW.estado_comercial IS NOT DISTINCT FROM OLD.estado_comercial THEN
        RETURN NEW;
    END IF;

    -- Duracion en el estado anterior (desde el ultimo cambio o desde created_at)
    SELECT MAX(cambio_at) INTO v_ultimo_cambio
      FROM historico_estado_activo WHERE activo_id = NEW.id;
    IF v_ultimo_cambio IS NULL THEN
        v_ultimo_cambio := OLD.updated_at;
    END IF;
    v_duracion := EXTRACT(EPOCH FROM (NOW() - v_ultimo_cambio)) / 3600.0;

    -- Lectura GPS actual (si existe)
    IF to_regclass('public.gps_estado_actual') IS NOT NULL THEN
        SELECT latitud, longitud, horometro_hrs, odometro_km
          INTO v_lat, v_lng, v_horo, v_km
          FROM gps_estado_actual WHERE activo_id = NEW.id;
    END IF;

    INSERT INTO historico_estado_activo (
        activo_id, estado_anterior, estado_nuevo, cambio_at, cambio_por,
        origen, contrato_id, razon,
        latitud, longitud, horometro, kilometraje,
        duracion_estado_anterior_horas
    ) VALUES (
        NEW.id, OLD.estado_comercial, NEW.estado_comercial, NOW(), auth.uid(),
        v_origen, NEW.contrato_id,
        format('Cambio %s -> %s', COALESCE(OLD.estado_comercial::text,'(null)'), NEW.estado_comercial::text),
        v_lat, v_lng, v_horo, v_km,
        ROUND(v_duracion::numeric, 2)
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrar_historico_estado ON activos;
CREATE TRIGGER trg_registrar_historico_estado
    AFTER UPDATE OF estado_comercial ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_historico_estado_activo();


-- ============================================================================
-- 6. FUNCION fn_evaluar_activos_fuera_geocerca
-- ----------------------------------------------------------------------------
-- Llamada por cron cada 15 min. Logica:
--
-- A) Activos en 'arrendado': si estan FUERA de su geocerca esperada por
--    >= 2 horas continuas -> sugerir 'en_transito'
--
-- B) Activos en 'en_transito': si volvieron a estar DENTRO de su geocerca
--    esperada -> sugerir volver a 'arrendado'.
--    Si llevan >= 24h fuera todavia -> sugerir 'en_recepcion'.
--
-- No genera duplicados (uq_sugerencia_pendiente_activo).
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_evaluar_activos_fuera_geocerca()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_umbral_min       INT := 120;   -- 2 horas
    v_umbral_recep_min INT := 1440;  -- 24 horas en en_transito = sugerir en_recepcion
    v_row              RECORD;
    v_dentro           BOOLEAN;
    v_ultimo_salida    TIMESTAMPTZ;
    v_minutos_fuera    INT;
    v_inserts          INT := 0;
    v_revertidas       INT := 0;
BEGIN
    -- Limpiar sugerencias auto-revertidas: si el activo volvio dentro,
    -- cancelar sugerencias pendientes de 'arrendado -> en_transito'
    FOR v_row IN
        SELECT s.id, vge.activo_id, vge.geocerca_id, vge.geocerca_lat, vge.geocerca_lng, vge.geocerca_radio_m
          FROM cambios_estado_sugeridos s
          JOIN v_activo_geocerca_esperada vge ON vge.activo_id = s.activo_id
          JOIN gps_estado_actual ge          ON ge.activo_id = s.activo_id
         WHERE s.accion = 'pendiente'
           AND s.estado_sugerido = 'en_transito'
           AND vge.geocerca_id IS NOT NULL
    LOOP
        v_dentro := fn_distancia_haversine(
            (SELECT latitud FROM gps_estado_actual WHERE activo_id = v_row.activo_id),
            (SELECT longitud FROM gps_estado_actual WHERE activo_id = v_row.activo_id),
            v_row.geocerca_lat, v_row.geocerca_lng
        ) <= v_row.geocerca_radio_m;
        IF v_dentro THEN
            UPDATE cambios_estado_sugeridos
               SET accion = 'auto_revertida',
                   validado_at = NOW(),
                   comentario = 'Activo volvio a la geocerca antes de validar sugerencia'
             WHERE id = v_row.id;
            v_revertidas := v_revertidas + 1;
        END IF;
    END LOOP;

    -- A) Evaluar activos en 'arrendado' fuera de geocerca >= 2h
    FOR v_row IN
        SELECT vge.activo_id, vge.geocerca_id, vge.geocerca_lat, vge.geocerca_lng, vge.geocerca_radio_m,
               vge.estado_comercial, a.contrato_id, ge.latitud, ge.longitud
          FROM v_activo_geocerca_esperada vge
          JOIN activos a                    ON a.id = vge.activo_id
          JOIN gps_estado_actual ge         ON ge.activo_id = vge.activo_id
         WHERE vge.estado_comercial = 'arrendado'
           AND vge.geocerca_id IS NOT NULL
           AND ge.latitud IS NOT NULL
    LOOP
        -- Esta dentro? skip
        v_dentro := fn_distancia_haversine(
            v_row.latitud, v_row.longitud,
            v_row.geocerca_lat, v_row.geocerca_lng
        ) <= v_row.geocerca_radio_m;
        IF v_dentro THEN CONTINUE; END IF;

        -- Cuanto tiempo lleva fuera? Buscar ultimo evento 'salida' sin entrada posterior
        SELECT MAX(ts) INTO v_ultimo_salida
          FROM gps_geocerca_eventos
         WHERE activo_id = v_row.activo_id
           AND geocerca_id = v_row.geocerca_id
           AND tipo_evento = 'salida';

        IF v_ultimo_salida IS NULL THEN
            -- Sin registro de salida en geocerca_eventos: usar ultima fecha cambio_at del activo
            v_ultimo_salida := COALESCE(
                (SELECT MAX(cambio_at) FROM historico_estado_activo WHERE activo_id = v_row.activo_id),
                NOW() - INTERVAL '3 hours'
            );
        END IF;

        v_minutos_fuera := EXTRACT(EPOCH FROM (NOW() - v_ultimo_salida))::INT / 60;

        IF v_minutos_fuera < v_umbral_min THEN CONTINUE; END IF;

        -- Crear sugerencia (uq evita duplicados pendientes para mismo activo)
        BEGIN
            INSERT INTO cambios_estado_sugeridos (
                activo_id, geocerca_id, estado_anterior, estado_sugerido,
                razon, minutos_fuera, origen
            ) VALUES (
                v_row.activo_id, v_row.geocerca_id, 'arrendado', 'en_transito',
                format('Activo fuera de geocerca >= %s min (lleva %s min). Validar si esta en transito autorizado.',
                       v_umbral_min, v_minutos_fuera),
                v_minutos_fuera, 'geocerca_auto'
            );
            v_inserts := v_inserts + 1;
        EXCEPTION WHEN unique_violation THEN
            -- Ya existe pendiente, skip
            NULL;
        END;
    END LOOP;

    -- B) Activos en 'en_transito' >= 24h sin volver -> sugerir en_recepcion
    FOR v_row IN
        SELECT a.id AS activo_id, a.contrato_id,
               h.cambio_at AS desde_en_transito
          FROM activos a
          LEFT JOIN LATERAL (
              SELECT cambio_at FROM historico_estado_activo
               WHERE activo_id = a.id AND estado_nuevo = 'en_transito'
               ORDER BY cambio_at DESC LIMIT 1
          ) h ON true
         WHERE a.estado_comercial = 'en_transito'
           AND h.cambio_at IS NOT NULL
           AND EXTRACT(EPOCH FROM (NOW() - h.cambio_at)) / 60 >= v_umbral_recep_min
    LOOP
        BEGIN
            INSERT INTO cambios_estado_sugeridos (
                activo_id, estado_anterior, estado_sugerido,
                razon, minutos_fuera, origen
            ) VALUES (
                v_row.activo_id, 'en_transito', 'en_recepcion',
                format('Activo en en_transito hace >= %s horas. Considerar como devolucion.',
                       v_umbral_recep_min / 60),
                EXTRACT(EPOCH FROM (NOW() - v_row.desde_en_transito))::INT / 60,
                'geocerca_auto'
            );
            v_inserts := v_inserts + 1;
        EXCEPTION WHEN unique_violation THEN NULL;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'sugerencias_creadas',  v_inserts,
        'sugerencias_auto_revertidas', v_revertidas,
        'ts', NOW()
    );
END;
$$;

REVOKE ALL ON FUNCTION fn_evaluar_activos_fuera_geocerca() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_evaluar_activos_fuera_geocerca() TO service_role;


-- ============================================================================
-- 7. RPC rpc_validar_sugerencia
-- ----------------------------------------------------------------------------
-- Llamada por la UI del planificador.
-- accion = 'aprobar' -> ejecuta el cambio en activos.estado_comercial (trigger
--   historico se dispara). Marca sugerencia como aprobada.
-- accion = 'rechazar' -> solo marca rechazada con comentario.
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_validar_sugerencia(
    p_sugerencia_id UUID,
    p_accion        VARCHAR,   -- 'aprobar' | 'rechazar'
    p_comentario    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sug    RECORD;
    v_nueva  accion_sugerencia_enum;
BEGIN
    SELECT * INTO v_sug
      FROM cambios_estado_sugeridos
     WHERE id = p_sugerencia_id;

    IF v_sug.id IS NULL THEN
        RAISE EXCEPTION 'Sugerencia % no encontrada', p_sugerencia_id;
    END IF;
    IF v_sug.accion <> 'pendiente' THEN
        RAISE EXCEPTION 'Sugerencia ya fue resuelta como % en %', v_sug.accion, v_sug.validado_at;
    END IF;

    IF p_accion NOT IN ('aprobar','rechazar') THEN
        RAISE EXCEPTION 'Accion debe ser aprobar o rechazar (recibido: %)', p_accion;
    END IF;

    v_nueva := CASE p_accion WHEN 'aprobar' THEN 'aprobada'::accion_sugerencia_enum
                              ELSE 'rechazada'::accion_sugerencia_enum END;

    UPDATE cambios_estado_sugeridos
       SET accion = v_nueva,
           validado_at = NOW(),
           validado_por = auth.uid(),
           comentario = p_comentario
     WHERE id = p_sugerencia_id;

    IF p_accion = 'aprobar' THEN
        -- Ejecutar el cambio en activos. El trigger registra historico.
        UPDATE activos
           SET estado_comercial = v_sug.estado_sugerido
         WHERE id = v_sug.activo_id;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'sugerencia_id', p_sugerencia_id,
        'accion', v_nueva::text,
        'activo_id', v_sug.activo_id
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_validar_sugerencia(UUID, VARCHAR, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_validar_sugerencia(UUID, VARCHAR, TEXT) TO authenticated;


-- ============================================================================
-- 8. VISTA v_sugerencias_pendientes_con_contexto
-- ----------------------------------------------------------------------------
-- Para la UI Bandeja del Planificador. Incluye datos del activo, contrato,
-- ubicacion actual, distancia a geocerca esperada.
-- ============================================================================
CREATE OR REPLACE VIEW v_sugerencias_pendientes_con_contexto AS
SELECT
    s.id              AS sugerencia_id,
    s.activo_id,
    a.codigo          AS activo_codigo,
    a.patente         AS activo_patente,
    a.tipo_equipamiento,
    s.estado_anterior,
    s.estado_sugerido,
    s.razon,
    s.minutos_fuera,
    s.generado_at,
    EXTRACT(EPOCH FROM (NOW() - s.generado_at))::INT / 60 AS minutos_desde_sugerencia,
    g.id              AS geocerca_id,
    g.nombre          AS geocerca_nombre,
    c.codigo          AS contrato_codigo,
    c.cliente         AS cliente,
    ge.latitud        AS pos_actual_lat,
    ge.longitud       AS pos_actual_lng,
    CASE WHEN g.id IS NOT NULL AND ge.latitud IS NOT NULL
         THEN fn_distancia_haversine(ge.latitud, ge.longitud, g.centro_lat, g.centro_lng)
         END         AS distancia_a_geocerca_m
FROM cambios_estado_sugeridos s
JOIN activos a               ON a.id = s.activo_id
LEFT JOIN gps_geocercas g    ON g.id = s.geocerca_id
LEFT JOIN contratos c        ON c.id = a.contrato_id
LEFT JOIN gps_estado_actual ge ON ge.activo_id = s.activo_id
WHERE s.accion = 'pendiente'
ORDER BY s.minutos_fuera DESC NULLS LAST, s.generado_at DESC;

GRANT SELECT ON v_sugerencias_pendientes_con_contexto TO authenticated;


-- ============================================================================
-- 9. RLS
-- ============================================================================
ALTER TABLE cambios_estado_sugeridos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE historico_estado_activo    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_sug_select ON cambios_estado_sugeridos;
CREATE POLICY pol_sug_select ON cambios_estado_sugeridos
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_sug_insert ON cambios_estado_sugeridos;
CREATE POLICY pol_sug_insert ON cambios_estado_sugeridos
    FOR INSERT TO authenticated
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_sug_update ON cambios_estado_sugeridos;
CREATE POLICY pol_sug_update ON cambios_estado_sugeridos
    FOR UPDATE TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_hist_estado_select ON historico_estado_activo;
CREATE POLICY pol_hist_estado_select ON historico_estado_activo
    FOR SELECT TO authenticated USING (true);


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'enum_accion_sug',          EXISTS(SELECT 1 FROM pg_type WHERE typname='accion_sugerencia_enum'),
    'enum_origen_cambio',       EXISTS(SELECT 1 FROM pg_type WHERE typname='origen_cambio_estado_enum'),
    'vista_geocerca_esperada',  to_regclass('public.v_activo_geocerca_esperada') IS NOT NULL,
    'tabla_sugerencias',        to_regclass('public.cambios_estado_sugeridos') IS NOT NULL,
    'tabla_historico',          to_regclass('public.historico_estado_activo') IS NOT NULL,
    'trigger_historico',        EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_registrar_historico_estado'),
    'fn_evaluar',               EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_evaluar_activos_fuera_geocerca'),
    'rpc_validar',              EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_validar_sugerencia'),
    'vista_sug_pendientes',     to_regclass('public.v_sugerencias_pendientes_con_contexto') IS NOT NULL
) AS resultado;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- DESPUES DE APLICAR ESTA MIGRACION:
-- ----------------------------------------------------------------------------
-- Programar cron cada 15 min para evaluar geocercas:
--
--   SELECT cron.schedule(
--     'evaluar-geocercas-cada-15min',
--     '*/15 * * * *',
--     $$ SELECT fn_evaluar_activos_fuera_geocerca(); $$
--   );
--
-- Verificar que quedo:
--   SELECT jobname, schedule FROM cron.job WHERE jobname LIKE '%geocerca%';
-- ============================================================================
