-- ============================================================================
-- MIG572 · Centinela de flota — Fase B: la zona de cada contrato
-- ============================================================================
--
-- LO QUE HABÍA
-- Las geocercas se crearon en mayo por clustering automático del GPS
-- (crear-geocercas-gps.mjs) y nadie las revisó:
--  · TRES geocercas se llaman «Taller Pillado, Coquimbo». Una está justo
--    donde se cortó KVWD-27 (a 70 km del taller): SICOM registró que el camión
--    «entró al taller» el mismo minuto en que desapareció. Otra, a la altura de
--    Chañaral, salió de un solo equipo (TRDP-97) y nunca tuvo un evento.
--  · Los 3 camiones de ESM están a ~60 km de la «zona ESM»; los de Boart
--    (Spence) duermen en Calama. Encender una alerta de salida de zona sobre
--    esto sería repetir el ruido que dejó 48 alertas sin leer.
--
-- LO QUE HACE
--  1. Desactiva las dos geocercas falsas «Taller Pillado, Coquimbo».
--  2. gps_geocercas.verificada_en/por: una zona vale para alertar CRÍTICO solo
--     si una persona la confirmó. SICOM la SUGIERE con los puntos reales de los
--     últimos 30 días (celdas de 0,25°, solo trackers que estaban reportando
--     — un tracker mudo repite su último punto cada hora e inventa zonas).
--  3. Regla FUERA DE ZONA: arrendado, con contacto fresco, a más de 5 km de
--     toda zona permitida (las de su contrato + talleres/bodegas Pillado).
--     Vigilar al tiro; CRÍTICO a las 12 h si todas las zonas de su contrato
--     están verificadas.
--  4. Regla FUERA DE HORARIO (opcional por contrato): andando fuera de las
--     horas que el contrato permite → ALTO, al resumen. No se cierra sola: hay
--     que explicarla.
--  5. Traslados autorizados: una ventana (máx. 15 días) en que el Centinela no
--     abre incidentes para ese camión — un ladrón no puede crear una.
--  6. El correo de recuperados incluye «volvió a su zona», y el resumen lista
--     los contratos cuya zona falta o no está verificada.
-- ============================================================================

BEGIN;

-- ── 1. Geocercas falsas ─────────────────────────────────────────────────────
UPDATE gps_geocercas
   SET activo = FALSE,
       nombre = 'Zona auto-GPS descartada (ex «Taller Pillado, Coquimbo»)',
       descripcion = COALESCE(descripcion, '') || ' [MIG572] Desactivada: el nombre era falso '
                  || '(no es el taller) y salió del GPS de un solo equipo.',
       updated_at = NOW()
 WHERE id IN ('61516b22-5704-4e40-9608-7b9caaf54e27',   -- donde se cortó KVWD-27
              '2a5668b4-241c-4af6-b089-18ccfd3aa270');  -- TRDP-97, 0 eventos

-- ── 2. Zonas verificadas ────────────────────────────────────────────────────
ALTER TABLE gps_geocercas
    ADD COLUMN IF NOT EXISTS verificada_en  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verificada_por UUID;

COMMENT ON COLUMN gps_geocercas.verificada_en IS
    '[MIG572] Una persona confirmó que esta zona corresponde. Solo las zonas '
    'verificadas pueden disparar el Centinela en CRÍTICO por salida de zona.';

-- ¿Todas las zonas de faena del contrato están verificadas (y hay al menos una)?
CREATE OR REPLACE FUNCTION fn_centinela_zona_verificada(p_contrato_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT count(*) > 0 AND bool_and(verificada_en IS NOT NULL)
      FROM gps_geocercas
     WHERE contrato_id = p_contrato_id AND activo AND tipo = 'faena_cliente';
$$;

-- ── 3. Config, incidentes, permisos, horarios ───────────────────────────────
ALTER TABLE centinela_config
    ADD COLUMN IF NOT EXISTS margen_zona_km           NUMERIC NOT NULL DEFAULT 5,
    ADD COLUMN IF NOT EXISTS horas_fuera_zona_critico NUMERIC NOT NULL DEFAULT 12,
    ADD COLUMN IF NOT EXISTS dias_max_permiso         NUMERIC NOT NULL DEFAULT 15;

ALTER TABLE centinela_incidentes
    ADD COLUMN IF NOT EXISTS detalle       TEXT,
    ADD COLUMN IF NOT EXISTS km_fuera_zona NUMERIC,
    ADD COLUMN IF NOT EXISTS zona_nombre   TEXT,
    ADD COLUMN IF NOT EXISTS horas_fuera   NUMERIC;

ALTER TABLE centinela_incidentes DROP CONSTRAINT centinela_incidentes_regla_check;
ALTER TABLE centinela_incidentes ADD CONSTRAINT centinela_incidentes_regla_check
    CHECK (regla IN ('corte_en_marcha', 'sin_senal', 'fuera_de_zona', 'fuera_de_horario'));
ALTER TABLE centinela_incidentes DROP CONSTRAINT centinela_incidentes_motivo_cierre_check;
ALTER TABLE centinela_incidentes ADD CONSTRAINT centinela_incidentes_motivo_cierre_check
    CHECK (motivo_cierre IN (
        'senal_recuperada', 'normalizado', 'permiso_transito',
        'ubicado_con_evidencia', 'falla_gps', 'traslado_autorizado',
        'denuncia', 'falso_positivo', 'otro'));

CREATE TABLE IF NOT EXISTS centinela_permisos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id   UUID NOT NULL REFERENCES activos(id),
    desde       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hasta       TIMESTAMPTZ NOT NULL,
    motivo      TEXT NOT NULL,
    creado_por  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revocado_en TIMESTAMPTZ,
    revocado_por UUID,
    CHECK (hasta > desde)
);
CREATE INDEX IF NOT EXISTS ix_centinela_permisos_activo ON centinela_permisos (activo_id, hasta DESC);
ALTER TABLE centinela_permisos ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE centinela_permisos IS
    '[MIG572] Traslado o trabajo sin cobertura autorizado: mientras dure, el '
    'Centinela no abre incidentes para ese camión (y cierra el que haya).';

CREATE TABLE IF NOT EXISTS centinela_horario_contrato (
    contrato_id UUID PRIMARY KEY REFERENCES contratos(id),
    hora_desde  TIME NOT NULL,
    hora_hasta  TIME NOT NULL,
    dias        INT[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}',  -- ISO: 1 = lunes
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by  UUID
);
ALTER TABLE centinela_horario_contrato ENABLE ROW LEVEL SECURITY;

-- ── 4. Evaluador v2 ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_centinela_evaluar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    c             centinela_config%ROWTYPE;
    v_ultimo_poll TIMESTAMPTZ;
    v_local       TIMESTAMP := NOW() AT TIME ZONE 'America/Santiago';
    r             RECORD;
    h             RECORD;
    i             centinela_incidentes%ROWTYPE;
    v_rank CONSTANT JSONB := '{"vigilar":1,"alto":2,"critico":3}';
    -- silencio
    s_regla TEXT; s_sev TEXT;
    -- zona
    z_fuera BOOLEAN; z_km NUMERIC; z_zona TEXT; z_sev TEXT; z_horas NUMERIC; z_det TEXT;
    -- horario
    hr_sev TEXT; hr_det TEXT;
    -- elegido
    t_regla TEXT; t_sev TEXT; t_det TEXT;
    v_fresco    BOOLEAN;
    v_abiertos  INT := 0;
    v_subidos   INT := 0;
    v_cerrados  INT := 0;
BEGIN
    SELECT * INTO c FROM centinela_config WHERE id = 1;

    -- Si la ingesta está caída, todo el parque parecería mudo: no evaluar.
    SELECT max(ts_actualizado) INTO v_ultimo_poll FROM gps_estado_actual;
    IF v_ultimo_poll IS NULL
       OR v_ultimo_poll < NOW() - make_interval(secs => c.horas_ingesta_caida * 3600) THEN
        RETURN jsonb_build_object('ingesta_caida', true, 'ultimo_poll', v_ultimo_poll);
    END IF;

    FOR r IN
        SELECT a.id AS activo_id,
               a.estado_comercial::TEXT AS estado_comercial,
               a.cliente_actual::TEXT   AS cliente,
               a.contrato_id,
               e.latitud, e.longitud, e.velocidad_kmh, e.ignicion, e.bateria_pct, e.movimiento,
               COALESCE(e.ts_ultimo_contacto, e.ts_gps) AS contacto,
               EXTRACT(EPOCH FROM NOW() - COALESCE(e.ts_ultimo_contacto, e.ts_gps)) / 3600.0 AS horas,
               (   (COALESCE(e.ignicion, FALSE)
                    OR e.movimiento = 'moving'
                    OR COALESCE(e.velocidad_kmh, 0) > 5)
               AND COALESCE(e.bateria_pct, 100) >= c.bateria_min_pct) AS en_marcha,
               p.motivo AS permiso_motivo
          FROM gps_estado_actual e
          JOIN activos a ON a.id = e.activo_id
          LEFT JOIN LATERAL (
                SELECT pp.motivo FROM centinela_permisos pp
                 WHERE pp.activo_id = a.id AND pp.revocado_en IS NULL
                   AND NOW() BETWEEN pp.desde AND pp.hasta
                 ORDER BY pp.hasta DESC LIMIT 1) p ON TRUE
         WHERE a.fecha_baja IS NULL
           AND NOT COALESCE(a.es_prueba, FALSE)
           AND EXISTS (SELECT 1 FROM gps_activo_mapeo m
                        WHERE m.activo_id = a.id AND m.activo)
    LOOP
        s_regla := NULL; s_sev := NULL;
        z_fuera := FALSE; z_km := NULL; z_zona := NULL; z_sev := NULL; z_horas := NULL; z_det := NULL;
        hr_sev := NULL; hr_det := NULL;
        v_fresco := r.contacto IS NOT NULL AND r.horas < 2;

        SELECT * INTO i FROM centinela_incidentes
         WHERE activo_id = r.activo_id AND estado <> 'cerrado';

        -- ¿Dónde está respecto de su zona? (solo arrendado, con zona, fresco)
        IF v_fresco AND r.estado_comercial = 'arrendado' AND r.contrato_id IS NOT NULL
           AND r.latitud IS NOT NULL
           AND EXISTS (SELECT 1 FROM gps_geocercas g
                        WHERE g.activo AND g.tipo = 'faena_cliente' AND g.contrato_id = r.contrato_id) THEN
            SELECT round((fn_distancia_haversine(r.latitud, r.longitud, g.centro_lat, g.centro_lng)
                          - g.radio_m) / 1000.0, 1),
                   g.nombre
              INTO z_km, z_zona
              FROM gps_geocercas g
             WHERE g.activo
               AND (g.tipo IN ('base_pillado', 'taller_externo', 'bodega')
                    OR (g.tipo = 'faena_cliente' AND g.contrato_id = r.contrato_id))
             ORDER BY fn_distancia_haversine(r.latitud, r.longitud, g.centro_lat, g.centro_lng) - g.radio_m
             LIMIT 1;
            z_fuera := z_km > c.margen_zona_km;
        END IF;

        -- Cierres automáticos del incidente abierto
        IF i.id IS NOT NULL THEN
            IF r.permiso_motivo IS NOT NULL THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'permiso_transito',
                       detalle_cierre = 'Traslado autorizado: ' || r.permiso_motivo, evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            ELSIF i.regla IN ('corte_en_marcha', 'sin_senal')
                  AND r.contacto > i.ultimo_contacto + INTERVAL '1 minute' THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'senal_recuperada',
                       detalle_cierre = 'El tracker volvió a reportar el '
                           || to_char(r.contacto AT TIME ZONE 'America/Santiago', 'DD-MM HH24:MI'),
                       horas_sin_contacto = round(EXTRACT(EPOCH FROM r.contacto - i.ultimo_contacto) / 3600.0, 1),
                       evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            ELSIF i.regla = 'fuera_de_zona' AND v_fresco AND NOT z_fuera THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'normalizado',
                       detalle_cierre = CASE WHEN z_km IS NULL
                           THEN 'Ya no aplica (cambió su contrato o su estado comercial)'
                           ELSE 'Volvió a su zona (' || z_zona || ')' END,
                       evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            END IF;
        END IF;

        -- Con traslado autorizado no se abre nada.
        IF r.permiso_motivo IS NOT NULL THEN CONTINUE; END IF;

        -- Silencio (Fase A)
        IF r.contacto IS NOT NULL THEN
            IF r.en_marcha AND r.horas >= c.horas_critico_marcha THEN
                s_regla := 'corte_en_marcha'; s_sev := 'critico';
            ELSIF r.en_marcha AND r.horas >= c.horas_vigilar_marcha THEN
                s_regla := 'corte_en_marcha'; s_sev := 'vigilar';
            ELSIF r.horas >= c.horas_critico_en_cliente
                  AND r.estado_comercial IN ('arrendado', 'leasing', 'uso_interno') THEN
                s_regla := 'sin_senal'; s_sev := 'critico';
            ELSIF r.horas >= c.horas_alto_detenido THEN
                s_regla := 'sin_senal'; s_sev := 'alto';
            END IF;
        END IF;

        -- Fuera de zona: vigilar al tiro, crítico a las N horas si la zona está verificada.
        IF z_fuera THEN
            z_horas := CASE WHEN i.id IS NOT NULL AND i.regla = 'fuera_de_zona'
                            THEN round(EXTRACT(EPOCH FROM NOW() - i.abierto_en) / 3600.0, 1) ELSE 0 END;
            z_sev := CASE WHEN z_horas >= c.horas_fuera_zona_critico
                               AND fn_centinela_zona_verificada(r.contrato_id)
                          THEN 'critico' ELSE 'vigilar' END;
            z_det := format('A %s km de la zona permitida más cercana (%s)', z_km, z_zona)
                  || CASE WHEN NOT fn_centinela_zona_verificada(r.contrato_id)
                          THEN '. La zona del contrato no está verificada' ELSE '' END;
        END IF;

        -- Fuera de horario (solo contratos que lo configuraron)
        IF v_fresco AND r.estado_comercial = 'arrendado' AND r.contrato_id IS NOT NULL
           AND (COALESCE(r.velocidad_kmh, 0) > 5 OR r.movimiento = 'moving') THEN
            SELECT * INTO h FROM centinela_horario_contrato
             WHERE contrato_id = r.contrato_id AND activo;
            IF FOUND AND NOT (
                   EXTRACT(ISODOW FROM v_local)::INT = ANY (h.dias)
               AND CASE WHEN h.hora_desde <= h.hora_hasta
                        THEN v_local::TIME BETWEEN h.hora_desde AND h.hora_hasta
                        ELSE v_local::TIME >= h.hora_desde OR v_local::TIME <= h.hora_hasta END) THEN
                hr_sev := 'alto';
                hr_det := format('Andando a %s km/h el %s a las %s, fuera del horario del contrato (%s–%s)',
                                 round(COALESCE(r.velocidad_kmh, 0)), to_char(v_local, 'DD-MM'),
                                 to_char(v_local, 'HH24:MI'),
                                 to_char(h.hora_desde, 'HH24:MI'), to_char(h.hora_hasta, 'HH24:MI'));
            END IF;
        END IF;

        -- La más grave gana; empate: silencio > zona > horario.
        t_regla := s_regla; t_sev := s_sev; t_det := NULL;
        IF z_sev IS NOT NULL AND (t_sev IS NULL OR (v_rank->>z_sev)::INT > (v_rank->>t_sev)::INT) THEN
            t_regla := 'fuera_de_zona'; t_sev := z_sev; t_det := z_det;
        END IF;
        IF hr_sev IS NOT NULL AND (t_sev IS NULL OR (v_rank->>hr_sev)::INT > (v_rank->>t_sev)::INT) THEN
            t_regla := 'fuera_de_horario'; t_sev := hr_sev; t_det := hr_det;
        END IF;

        IF t_sev IS NULL THEN
            IF i.id IS NOT NULL THEN
                UPDATE centinela_incidentes
                   SET horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW()
                 WHERE id = i.id;
            END IF;
            CONTINUE;
        END IF;

        IF i.id IS NULL THEN
            INSERT INTO centinela_incidentes (
                activo_id, regla, severidad, ultimo_contacto,
                latitud, longitud, velocidad_kmh, ignicion, bateria_pct,
                estado_comercial, cliente, horas_sin_contacto, evaluado_en,
                detalle, km_fuera_zona, zona_nombre, horas_fuera)
            VALUES (
                r.activo_id, t_regla, t_sev, r.contacto,
                r.latitud, r.longitud, r.velocidad_kmh, r.ignicion, r.bateria_pct,
                r.estado_comercial, r.cliente, round(r.horas, 1), NOW(),
                t_det,
                CASE WHEN t_regla = 'fuera_de_zona' THEN z_km END,
                CASE WHEN t_regla = 'fuera_de_zona' THEN z_zona END,
                CASE WHEN t_regla = 'fuera_de_zona' THEN 0 END);
            v_abiertos := v_abiertos + 1;
        ELSIF (v_rank->>t_sev)::INT > (v_rank->>i.severidad)::INT THEN
            UPDATE centinela_incidentes
               SET regla = t_regla, severidad = t_sev, detalle = t_det,
                   km_fuera_zona = CASE WHEN t_regla = 'fuera_de_zona' THEN z_km END,
                   zona_nombre   = CASE WHEN t_regla = 'fuera_de_zona' THEN z_zona END,
                   horas_fuera   = CASE WHEN t_regla = 'fuera_de_zona' THEN z_horas END,
                   -- La foto pasa a ser la de ahora (dónde está al subir de nivel).
                   latitud = COALESCE(r.latitud, latitud), longitud = COALESCE(r.longitud, longitud),
                   horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW()
             WHERE id = i.id;
            v_subidos := v_subidos + 1;
        ELSE
            UPDATE centinela_incidentes
               SET horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW(),
                   detalle       = CASE WHEN regla = t_regla AND t_det IS NOT NULL THEN t_det ELSE detalle END,
                   km_fuera_zona = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN z_km ELSE km_fuera_zona END,
                   horas_fuera   = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN z_horas ELSE horas_fuera END,
                   latitud  = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN r.latitud  ELSE latitud  END,
                   longitud = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN r.longitud ELSE longitud END
             WHERE id = i.id;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('ingesta_caida', false, 'ultimo_poll', v_ultimo_poll,
        'abiertos', v_abiertos, 'subidos', v_subidos, 'cerrados', v_cerrados);
END;
$$;

REVOKE ALL ON FUNCTION fn_centinela_evaluar() FROM PUBLIC, anon, authenticated;

-- ── 5. Vista (se recrea: i.* se expande al crearla) ─────────────────────────
DROP VIEW IF EXISTS v_centinela_incidentes;
CREATE VIEW v_centinela_incidentes AS
SELECT i.*,
       a.patente::TEXT   AS patente,
       a.codigo::TEXT    AS codigo,
       a.nombre::TEXT    AS nombre,
       a.operacion::TEXT AS operacion,
       e.latitud  AS latitud_actual,
       e.longitud AS longitud_actual,
       e.ts_ultimo_contacto AS contacto_actual,
       (SELECT count(*) FROM centinela_incidentes x
         WHERE x.activo_id = i.activo_id AND x.id <> i.id
           AND x.motivo_cierre = 'senal_recuperada'
           AND x.abierto_en > NOW() - INTERVAL '60 days')::INT AS cortes_recuperados_60d
  FROM centinela_incidentes i
  JOIN activos a ON a.id = i.activo_id
  LEFT JOIN gps_estado_actual e ON e.activo_id = i.activo_id;
REVOKE ALL ON v_centinela_incidentes FROM PUBLIC, anon, authenticated;

-- ── 6. Zonas: sugerencia, listado y edición ─────────────────────────────────

-- Dónde anduvieron de verdad los camiones del contrato en 30 días.
CREATE OR REPLACE FUNCTION fn_centinela_zonas_sugeridas(p_contrato_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH pts AS (
        SELECT l.latitud AS lat, l.longitud AS lng,
               floor(l.latitud / 0.25) AS gy, floor(l.longitud / 0.25) AS gx
          FROM gps_eventos_log l
          JOIN activos a ON a.id = l.activo_id
         WHERE a.contrato_id = p_contrato_id
           AND l.ts_ingestado > NOW() - INTERVAL '30 days'
           AND l.latitud IS NOT NULL AND l.latitud <> 0
           -- Solo trackers vivos en ese momento: el mudo repite su último punto.
           AND fn_navixy_ts(l.payload_raw->>'last_update') > l.ts_ingestado - INTERVAL '2 hours'
           AND NOT EXISTS (SELECT 1 FROM gps_geocercas g
                            WHERE g.activo AND g.tipo = 'base_pillado'
                              AND fn_distancia_haversine(l.latitud, l.longitud, g.centro_lat, g.centro_lng) <= g.radio_m)),
    tot AS (SELECT count(*) AS n FROM pts),
    cel AS (SELECT gy, gx, avg(lat) AS clat, avg(lng) AS clng, count(*) AS n FROM pts GROUP BY 1, 2),
    zon AS (
        SELECT c.clat, c.clng, c.n,
               greatest(3000, percentile_cont(0.95) WITHIN GROUP (
                   ORDER BY fn_distancia_haversine(p.lat, p.lng, c.clat, c.clng)) + 2000) AS radio_m
          FROM cel c
          JOIN pts p ON p.gy = c.gy AND p.gx = c.gx
         WHERE c.n >= 0.15 * (SELECT n FROM tot)
         GROUP BY c.gy, c.gx, c.clat, c.clng, c.n)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'lat', round(clat, 5), 'lng', round(clng, 5),
               'radio_m', round(radio_m::NUMERIC, -2),
               'pct', round(100.0 * n / (SELECT n FROM tot))) ORDER BY n DESC), '[]')
      FROM zon;
$$;
REVOKE ALL ON FUNCTION fn_centinela_zonas_sugeridas(UUID) FROM PUBLIC, anon, authenticated;

-- Contratos con equipos arrendados: sus zonas, si están verificadas, horario.
CREATE OR REPLACE FUNCTION rpc_centinela_zonas()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'view', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones','supervisor','jefe_mantenimiento','comercial']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para ver el Centinela de flota';
    END IF;
    RETURN jsonb_build_object(
        'contratos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'contrato_id', k.id, 'codigo', k.codigo, 'cliente', k.cliente,
                'equipos', (SELECT jsonb_agg(a.patente ORDER BY a.patente) FROM activos a
                             WHERE a.contrato_id = k.id AND a.estado_comercial = 'arrendado'
                               AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, FALSE)),
                'verificada', fn_centinela_zona_verificada(k.id),
                'zonas', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                             'id', g.id, 'nombre', g.nombre, 'lat', g.centro_lat, 'lng', g.centro_lng,
                             'radio_m', g.radio_m, 'verificada_en', g.verificada_en,
                             'verificada_por', (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = g.verificada_por))
                             ORDER BY g.nombre)
                           FROM gps_geocercas g
                          WHERE g.contrato_id = k.id AND g.activo AND g.tipo = 'faena_cliente'), '[]'),
                'horario', (SELECT to_jsonb(h) FROM centinela_horario_contrato h WHERE h.contrato_id = k.id))
                ORDER BY fn_centinela_zona_verificada(k.id), k.codigo)
              FROM contratos k
             WHERE EXISTS (SELECT 1 FROM activos a WHERE a.contrato_id = k.id
                             AND a.estado_comercial = 'arrendado' AND a.fecha_baja IS NULL
                             AND NOT COALESCE(a.es_prueba, FALSE))), '[]'),
        -- Arrendados sin contrato: el Centinela no puede saber cuál es su zona.
        'sin_contrato', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('activo_id', a.id, 'patente', a.patente,
                             'codigo', a.codigo, 'cliente', a.cliente_actual) ORDER BY a.patente)
              FROM activos a
             WHERE a.estado_comercial = 'arrendado' AND a.contrato_id IS NULL
               AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, FALSE)), '[]'),
        'permisos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('id', p.id, 'patente', a.patente, 'desde', p.desde,
                             'hasta', p.hasta, 'motivo', p.motivo, 'revocado_en', p.revocado_en,
                             'vigente', p.revocado_en IS NULL AND NOW() BETWEEN p.desde AND p.hasta,
                             'creado_por', (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = p.creado_por))
                             ORDER BY p.hasta DESC)
              FROM centinela_permisos p JOIN activos a ON a.id = p.activo_id
             WHERE p.hasta > NOW() - INTERVAL '14 days'), '[]'));
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_sugerir_zonas(p_contrato_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'view', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones','supervisor','jefe_mantenimiento','comercial']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para ver el Centinela de flota';
    END IF;
    RETURN fn_centinela_zonas_sugeridas(p_contrato_id);
END;
$$;

-- Guardar = verificar: quien la guarda responde por ella.
CREATE OR REPLACE FUNCTION rpc_centinela_guardar_zona(
    p_contrato_id UUID, p_geocerca_id UUID, p_nombre TEXT,
    p_lat NUMERIC, p_lng NUMERIC, p_radio_m NUMERIC)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para editar zonas del Centinela';
    END IF;
    IF length(trim(COALESCE(p_nombre, ''))) < 3 THEN RAISE EXCEPTION 'Ponle un nombre a la zona'; END IF;
    IF p_lat NOT BETWEEN -56 AND -17 OR p_lng NOT BETWEEN -76 AND -66 THEN
        RAISE EXCEPTION 'Las coordenadas no están en Chile';
    END IF;
    IF p_radio_m NOT BETWEEN 300 AND 200000 THEN
        RAISE EXCEPTION 'El radio debe estar entre 0,3 y 200 km';
    END IF;
    IF p_geocerca_id IS NULL THEN
        INSERT INTO gps_geocercas (nombre, tipo, centro_lat, centro_lng, radio_m, contrato_id,
                                   descripcion, activo, created_by, verificada_en, verificada_por)
        VALUES (trim(p_nombre), 'faena_cliente', p_lat, p_lng, p_radio_m, p_contrato_id,
                '[MIG572] Creada desde el Centinela', TRUE, auth.uid(), NOW(), auth.uid())
        RETURNING id INTO v_id;
    ELSE
        UPDATE gps_geocercas
           SET nombre = trim(p_nombre), centro_lat = p_lat, centro_lng = p_lng, radio_m = p_radio_m,
               verificada_en = NOW(), verificada_por = auth.uid(), updated_at = NOW()
         WHERE id = p_geocerca_id AND contrato_id = p_contrato_id AND tipo = 'faena_cliente'
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'La zona no es de este contrato'; END IF;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_desactivar_zona(p_geocerca_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para editar zonas del Centinela';
    END IF;
    UPDATE gps_geocercas SET activo = FALSE, updated_at = NOW(),
           descripcion = COALESCE(descripcion, '') || ' [Centinela] Desactivada el '
                       || to_char(NOW() AT TIME ZONE 'America/Santiago', 'DD-MM-YYYY')
     WHERE id = p_geocerca_id AND tipo = 'faena_cliente';
    IF NOT FOUND THEN RAISE EXCEPTION 'Zona no encontrada'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_guardar_horario(
    p_contrato_id UUID, p_desde TIME, p_hasta TIME, p_dias INT[], p_activo BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para editar el horario del contrato';
    END IF;
    IF p_activo AND (p_desde IS NULL OR p_hasta IS NULL OR COALESCE(array_length(p_dias, 1), 0) = 0) THEN
        RAISE EXCEPTION 'Indica horas y al menos un día';
    END IF;
    INSERT INTO centinela_horario_contrato (contrato_id, hora_desde, hora_hasta, dias, activo, updated_at, updated_by)
    VALUES (p_contrato_id, COALESCE(p_desde, '00:00'), COALESCE(p_hasta, '23:59'),
            COALESCE(p_dias, '{1,2,3,4,5,6,7}'), p_activo, NOW(), auth.uid())
    ON CONFLICT (contrato_id) DO UPDATE
       SET hora_desde = EXCLUDED.hora_desde, hora_hasta = EXCLUDED.hora_hasta,
           dias = EXCLUDED.dias, activo = EXCLUDED.activo,
           updated_at = NOW(), updated_by = auth.uid();
END;
$$;

-- ── 7. Traslados autorizados ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_centinela_autorizar_traslado(
    p_activo_id UUID, p_hasta TIMESTAMPTZ, p_motivo TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID; v_max NUMERIC;
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para autorizar traslados';
    END IF;
    SELECT dias_max_permiso INTO v_max FROM centinela_config WHERE id = 1;
    IF p_hasta <= NOW() THEN RAISE EXCEPTION 'La fecha de término ya pasó'; END IF;
    IF p_hasta > NOW() + make_interval(days => v_max::INT) THEN
        RAISE EXCEPTION 'Un traslado se autoriza por máximo % días', v_max;
    END IF;
    IF length(trim(COALESCE(p_motivo, ''))) < 10 THEN
        RAISE EXCEPTION 'Explica el traslado (mínimo 10 caracteres): destino, quién lo pidió';
    END IF;
    INSERT INTO centinela_permisos (activo_id, hasta, motivo, creado_por)
    VALUES (p_activo_id, p_hasta, trim(p_motivo), auth.uid())
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_revocar_traslado(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para revocar traslados';
    END IF;
    UPDATE centinela_permisos SET revocado_en = NOW(), revocado_por = auth.uid()
     WHERE id = p_id AND revocado_en IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'El traslado ya estaba revocado'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION rpc_centinela_zonas() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_sugerir_zonas(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_guardar_zona(UUID, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_desactivar_zona(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_guardar_horario(UUID, TIME, TIME, INT[], BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_autorizar_traslado(UUID, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_revocar_traslado(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_centinela_zonas() TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_sugerir_zonas(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_guardar_zona(UUID, UUID, TEXT, NUMERIC, NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_desactivar_zona(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_guardar_horario(UUID, TIME, TIME, INT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_autorizar_traslado(UUID, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_revocar_traslado(UUID) TO authenticated;

-- ── 8. Correo: recuperados incluye «volvió a su zona»; resumen de zonas ─────
CREATE OR REPLACE FUNCTION fn_centinela_correo_cron(p_secreto TEXT, p_modo TEXT DEFAULT 'inmediato')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    c        centinela_config%ROWTYPE;
    v_poll   TIMESTAMPTZ;
    v_caida  BOOLEAN;
    v_out    JSONB;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    SELECT * INTO c FROM centinela_config WHERE id = 1;
    SELECT max(ts_actualizado) INTO v_poll FROM gps_estado_actual;
    v_caida := v_poll IS NULL
            OR v_poll < NOW() - make_interval(secs => c.horas_ingesta_caida * 3600);

    v_out := jsonb_build_object(
        'ingesta', jsonb_build_object(
            'ultimo_poll', v_poll,
            'caida', v_caida,
            'avisar', v_caida AND (c.ingesta_caida_notificada_en IS NULL
                         OR c.ingesta_caida_notificada_en < NOW() - INTERVAL '12 hours')),
        'horas_escalar', c.horas_escalar,
        'nuevos', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.horas_sin_contacto DESC)
            FROM v_centinela_incidentes v
           WHERE v.estado <> 'cerrado' AND v.severidad = 'critico'
             AND v.severidad_notificada IS DISTINCT FROM 'critico'), '[]'),
        'escalar', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.notificado_en)
            FROM v_centinela_incidentes v
           WHERE v.estado = 'abierto' AND v.severidad = 'critico'
             AND v.severidad_notificada = 'critico'
             AND v.escalado_en IS NULL
             AND v.notificado_en < NOW() - make_interval(secs => c.horas_escalar * 3600)), '[]'),
        'recuperados', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.cerrado_en)
            FROM v_centinela_incidentes v
           WHERE v.estado = 'cerrado'
             AND v.motivo_cierre IN ('senal_recuperada', 'normalizado', 'permiso_transito')
             AND v.severidad_notificada = 'critico'
             AND v.recuperado_notificado_en IS NULL), '[]')
    );

    IF p_modo = 'resumen' THEN
        v_out := v_out || jsonb_build_object(
            'abiertos', COALESCE((SELECT jsonb_agg(to_jsonb(v)
                    ORDER BY CASE v.severidad WHEN 'critico' THEN 1 WHEN 'alto' THEN 2 ELSE 3 END,
                             v.horas_sin_contacto DESC)
                FROM v_centinela_incidentes v WHERE v.estado <> 'cerrado'), '[]'),
            -- (compat. con el correo de MIG571 hasta que se publique el nuevo)
            'sin_geocerca', '[]'::JSONB,
            -- Contratos con arrendados cuya zona falta o no está verificada, y
            -- arrendados sin contrato: el Centinela no puede vigilar su zona.
            'zonas_por_verificar', COALESCE((
                SELECT jsonb_agg(x ORDER BY x->>'contrato') FROM (
                    SELECT jsonb_build_object(
                        'contrato', k.codigo, 'cliente', k.cliente,
                        'problema', CASE WHEN NOT EXISTS (SELECT 1 FROM gps_geocercas g
                                              WHERE g.contrato_id = k.id AND g.activo AND g.tipo = 'faena_cliente')
                                         THEN 'Sin zona' ELSE 'Zona sin verificar' END,
                        'equipos', (SELECT string_agg(a.patente, ', ' ORDER BY a.patente) FROM activos a
                                     WHERE a.contrato_id = k.id AND a.estado_comercial = 'arrendado'
                                       AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, FALSE))) AS x
                      FROM contratos k
                     WHERE NOT fn_centinela_zona_verificada(k.id)
                       AND EXISTS (SELECT 1 FROM activos a WHERE a.contrato_id = k.id
                                     AND a.estado_comercial = 'arrendado' AND a.fecha_baja IS NULL
                                     AND NOT COALESCE(a.es_prueba, FALSE))
                    UNION ALL
                    SELECT jsonb_build_object('contrato', '— sin contrato —', 'cliente', a.cliente_actual,
                                              'problema', 'Arrendado sin contrato', 'equipos', a.patente)
                      FROM activos a
                     WHERE a.estado_comercial = 'arrendado' AND a.contrato_id IS NULL
                       AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, FALSE)) z), '[]'));
    END IF;
    RETURN v_out;
END;
$$;

SELECT fn_centinela_evaluar();

COMMIT;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; v_z INT; v_falsas INT; v_sug JSONB;
BEGIN
    SELECT count(*) INTO v_falsas FROM gps_geocercas WHERE activo AND nombre = 'Taller Pillado, Coquimbo';
    IF v_falsas <> 1 THEN RAISE EXCEPTION 'FALLO: quedan % «Taller Pillado, Coquimbo» activas', v_falsas; END IF;
    SELECT count(*) INTO v_n FROM centinela_incidentes WHERE estado <> 'cerrado';
    SELECT count(*) INTO v_z FROM centinela_incidentes WHERE estado <> 'cerrado' AND regla = 'fuera_de_zona';
    SELECT fn_centinela_zonas_sugeridas(id) INTO v_sug FROM contratos WHERE codigo = 'CTR-ORBIT-2025';
    RAISE NOTICE 'Centinela zonas OK · % incidentes abiertos (% fuera de zona, todos VIGILAR mientras no haya zonas verificadas) · sugerencia ORBIT: %',
        v_n, v_z, v_sug;
END
$mig$;
