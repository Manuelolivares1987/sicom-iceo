-- ============================================================================
-- MIG571 · Centinela de flota — Fase A: el camión que se calla, avisa
-- ============================================================================
--
-- LO QUE PASÓ
-- 23-09-2026: el cliente de KVWD-27 (Mina Ra, La Higuera) no contesta y el
-- camión «aparece en un lugar inhóspito». Revisado: el tracker se cortó el
-- 05-06 a las 13:24 yendo a 57 km/h, motor encendido, batería 100 %, y nunca
-- volvió. 110 días. El sistema SÍ lo vio — fn_gps_generar_alertas_sin_senal
-- dejó 48 alertas 'critical' en la tabla `alertas` — pero ahí quedaron,
-- revueltas con otras 39, sin correo, sin dueño y sin escalamiento.
--
-- LO QUE HACE ESTA MIGRACIÓN
--  1. gps_estado_actual.ts_ultimo_contacto: el último contacto REAL del
--     tracker (Navixy `last_update`). ts_gps es el último punto GPS, y un
--     camión estacionado con el tracker vivo no genera puntos: medir el
--     silencio por ts_gps llena de falsas alarmas. Ojo: Navixy entrega las
--     horas en la zona de la cuenta (Chile), no en UTC.
--  2. centinela_incidentes: UN incidente abierto por camión (no 48 alertas),
--     con acuse de recibo, escalamiento y cierre con motivo obligatorio.
--  3. fn_centinela_evaluar(): cada hora abre, sube de nivel o cierra solo
--     (cuando el tracker vuelve a hablar).
--  4. Funciones para el correo (patrón MIG301, secreto sin service_role) y
--     para la pantalla /dashboard/flota/centinela.
--
-- LAS REGLAS (calibradas contra 30 días de historial, 24-08 → 23-09)
--  · Corte EN MARCHA (motor encendido o en movimiento, batería ≥30 %):
--      ≥ 48 h → CRÍTICO, correo inmediato.
--      6–48 h → VIGILAR, solo panel y resumen diario.
--    En el mes hubo 173 cortes en marcha >2 h que se recuperaron solos (faenas
--    sin cobertura); 26 duraron >24 h. Con 2–4 h serían ~5 correos falsos al
--    día — el mismo ruido que hizo que nadie mirara las alertas. Con 48 h,
--    KVWD-27 habría avisado el 07-06.
--  · Sin contacto ≥ 7 días de un equipo fuera de casa (arrendado, leasing,
--    uso interno), aunque se haya callado detenido → CRÍTICO. KCBY-30 llevaba
--    139 días así y SPRY-26 50, ambos arrendados.
--  · Sin contacto ≥ 72 h estando detenido o sin batería → ALTO, resumen diario.
--  · Si la ingesta GPS misma está caída (>3 h sin polls) NO se evalúa: todo
--    el parque parecería mudo. Se avisa eso en su lugar.
--
-- Los umbrales viven en centinela_config: se ajustan sin migración.
--
-- ANTES DE APLICAR: nada. El secreto del cron se toma del job ya programado
-- 'revision-tecnica-por-vencer' (MIG504) y se verifica contra
-- sistema_secretos, así el valor nunca pasa por el repo ni por el chat.
-- ============================================================================

BEGIN;

-- ── 1. Último contacto real del tracker ─────────────────────────────────────

-- Navixy devuelve 'YYYY-MM-DD HH24:MI:SS' en la zona horaria de la cuenta
-- (Chile). Un texto raro no debe tumbar la ingesta: NULL y sigue.
CREATE OR REPLACE FUNCTION fn_navixy_ts(p_txt TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_txt IS NULL OR p_txt = '' THEN RETURN NULL; END IF;
    RETURN p_txt::TIMESTAMP AT TIME ZONE 'America/Santiago';
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

ALTER TABLE gps_estado_actual
    ADD COLUMN IF NOT EXISTS ts_ultimo_contacto TIMESTAMPTZ;

COMMENT ON COLUMN gps_estado_actual.ts_ultimo_contacto IS
    '[MIG571] Último contacto real del tracker (Navixy last_update, convertido '
    'desde hora de Chile). Mide el silencio del equipo; ts_gps es solo el '
    'último punto GPS y no avanza con el camión estacionado.';

-- Mismo cuerpo que el trigger vigente + ts_ultimo_contacto.
CREATE OR REPLACE FUNCTION public.fn_actualizar_estado_gps()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_contacto TIMESTAMPTZ := fn_navixy_ts(NEW.payload_raw->>'last_update');
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
        ts_ultimo_contacto
    ) VALUES (
        NEW.activo_id, NEW.proveedor_id, NEW.gps_device_id,
        NEW.ts_gps, NOW(),
        NEW.latitud, NEW.longitud, NEW.velocidad_kmh, NEW.heading,
        NEW.ignicion, NEW.movimiento, NEW.conexion,
        NEW.odometro_km, NEW.horometro_hrs, NEW.bateria_pct, NEW.gsm_red,
        v_contacto
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
                                         EXCLUDED.ts_ultimo_contacto)
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

-- Llenar el dato con el último poll de cada equipo.
UPDATE gps_estado_actual e
   SET ts_ultimo_contacto = l.contacto
  FROM (SELECT DISTINCT ON (activo_id)
               activo_id, fn_navixy_ts(payload_raw->>'last_update') AS contacto
          FROM gps_eventos_log
         WHERE activo_id IS NOT NULL
           AND ts_ingestado > NOW() - INTERVAL '3 days'
         ORDER BY activo_id, ts_ingestado DESC) l
 WHERE l.activo_id = e.activo_id
   AND l.contacto IS NOT NULL;

-- ── 2. Configuración y tabla de incidentes ──────────────────────────────────

CREATE TABLE IF NOT EXISTS centinela_config (
    id                          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    horas_vigilar_marcha        NUMERIC NOT NULL DEFAULT 6,
    horas_critico_marcha        NUMERIC NOT NULL DEFAULT 48,
    horas_alto_detenido         NUMERIC NOT NULL DEFAULT 72,
    horas_critico_en_cliente    NUMERIC NOT NULL DEFAULT 168,
    horas_escalar               NUMERIC NOT NULL DEFAULT 4,
    bateria_min_pct             NUMERIC NOT NULL DEFAULT 30,
    horas_ingesta_caida         NUMERIC NOT NULL DEFAULT 3,
    ingesta_caida_notificada_en TIMESTAMPTZ,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO centinela_config (id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS centinela_incidentes (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id            UUID NOT NULL REFERENCES activos(id),
    regla                TEXT NOT NULL CHECK (regla IN ('corte_en_marcha', 'sin_senal')),
    severidad            TEXT NOT NULL CHECK (severidad IN ('vigilar', 'alto', 'critico')),
    estado               TEXT NOT NULL DEFAULT 'abierto'
                             CHECK (estado IN ('abierto', 'acusado', 'cerrado')),
    abierto_en           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Foto del momento del corte: lo último que dijo el tracker.
    ultimo_contacto      TIMESTAMPTZ,
    latitud              NUMERIC,
    longitud             NUMERIC,
    velocidad_kmh        NUMERIC,
    ignicion             BOOLEAN,
    bateria_pct          NUMERIC,
    estado_comercial     TEXT,
    cliente              TEXT,
    horas_sin_contacto   NUMERIC,
    evaluado_en          TIMESTAMPTZ,
    -- Aviso y escalamiento
    notificado_en        TIMESTAMPTZ,
    severidad_notificada TEXT,
    escalado_en          TIMESTAMPTZ,
    -- Quién se hizo cargo
    acusado_en           TIMESTAMPTZ,
    acusado_por          UUID,
    nota_acuse           TEXT,
    -- Cierre
    cerrado_en           TIMESTAMPTZ,
    cerrado_por          UUID,
    motivo_cierre        TEXT CHECK (motivo_cierre IN (
                             'senal_recuperada', 'ubicado_con_evidencia', 'falla_gps',
                             'traslado_autorizado', 'denuncia', 'falso_positivo', 'otro')),
    detalle_cierre       TEXT,
    recuperado_notificado_en TIMESTAMPTZ,
    CHECK (estado <> 'cerrado' OR (cerrado_en IS NOT NULL AND motivo_cierre IS NOT NULL))
);

COMMENT ON TABLE centinela_incidentes IS
    '[MIG571] Un incidente por camión que dejó de reportar GPS. Uno abierto por '
    'activo a la vez. Se cierra solo si el tracker vuelve, o a mano con motivo.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_centinela_un_abierto_por_activo
    ON centinela_incidentes (activo_id) WHERE estado <> 'cerrado';
CREATE INDEX IF NOT EXISTS ix_centinela_cerrado_en
    ON centinela_incidentes (cerrado_en DESC) WHERE estado = 'cerrado';

-- Todo pasa por las funciones SECURITY DEFINER de abajo.
ALTER TABLE centinela_incidentes ENABLE ROW LEVEL SECURITY;
ALTER TABLE centinela_config     ENABLE ROW LEVEL SECURITY;

-- ── 3. El evaluador (cada hora, después del poll GPS) ───────────────────────

CREATE OR REPLACE FUNCTION fn_centinela_evaluar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    c            centinela_config%ROWTYPE;
    v_ultimo_poll TIMESTAMPTZ;
    r            RECORD;
    i            centinela_incidentes%ROWTYPE;
    v_regla      TEXT;
    v_sev        TEXT;
    v_abiertos   INT := 0;
    v_subidos    INT := 0;
    v_cerrados   INT := 0;
    v_rank CONSTANT JSONB := '{"vigilar":1,"alto":2,"critico":3}';
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
               e.latitud, e.longitud, e.velocidad_kmh, e.ignicion, e.bateria_pct,
               COALESCE(e.ts_ultimo_contacto, e.ts_gps) AS contacto,
               EXTRACT(EPOCH FROM NOW() - COALESCE(e.ts_ultimo_contacto, e.ts_gps)) / 3600.0 AS horas,
               (   (COALESCE(e.ignicion, FALSE)
                    OR e.movimiento = 'moving'
                    OR COALESCE(e.velocidad_kmh, 0) > 5)
               AND COALESCE(e.bateria_pct, 100) >= c.bateria_min_pct) AS en_marcha
          FROM gps_estado_actual e
          JOIN activos a ON a.id = e.activo_id
         WHERE a.fecha_baja IS NULL
           AND NOT COALESCE(a.es_prueba, FALSE)
           AND EXISTS (SELECT 1 FROM gps_activo_mapeo m
                        WHERE m.activo_id = a.id AND m.activo)
    LOOP
        v_regla := NULL; v_sev := NULL;
        IF r.contacto IS NOT NULL THEN
            IF r.en_marcha AND r.horas >= c.horas_critico_marcha THEN
                v_regla := 'corte_en_marcha'; v_sev := 'critico';
            ELSIF r.en_marcha AND r.horas >= c.horas_vigilar_marcha THEN
                v_regla := 'corte_en_marcha'; v_sev := 'vigilar';
            ELSIF r.horas >= c.horas_critico_en_cliente
                  AND r.estado_comercial IN ('arrendado', 'leasing', 'uso_interno') THEN
                v_regla := 'sin_senal'; v_sev := 'critico';
            ELSIF r.horas >= c.horas_alto_detenido THEN
                v_regla := 'sin_senal'; v_sev := 'alto';
            END IF;
        END IF;

        SELECT * INTO i FROM centinela_incidentes
         WHERE activo_id = r.activo_id AND estado <> 'cerrado';

        -- ¿Volvió a hablar desde que se abrió? Cierra solo. Si ya se volvió a
        -- cortar (episodio nuevo), se abre otro incidente abajo.
        IF i.id IS NOT NULL AND r.contacto > i.ultimo_contacto + INTERVAL '1 minute' THEN
            UPDATE centinela_incidentes
               SET estado = 'cerrado', cerrado_en = NOW(),
                   motivo_cierre = 'senal_recuperada',
                   detalle_cierre = 'El tracker volvió a reportar el '
                       || to_char(r.contacto AT TIME ZONE 'America/Santiago', 'DD-MM HH24:MI'),
                   horas_sin_contacto = round(EXTRACT(EPOCH FROM r.contacto - i.ultimo_contacto) / 3600.0, 1),
                   evaluado_en = NOW()
             WHERE id = i.id;
            v_cerrados := v_cerrados + 1;
            i.id := NULL;
        END IF;

        IF v_sev IS NULL THEN
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
                estado_comercial, cliente, horas_sin_contacto, evaluado_en)
            VALUES (
                r.activo_id, v_regla, v_sev, r.contacto,
                r.latitud, r.longitud, r.velocidad_kmh, r.ignicion, r.bateria_pct,
                r.estado_comercial, r.cliente, round(r.horas, 1), NOW());
            v_abiertos := v_abiertos + 1;
        ELSE
            IF (v_rank->>v_sev)::INT > (v_rank->>i.severidad)::INT THEN
                v_subidos := v_subidos + 1;
            END IF;
            UPDATE centinela_incidentes
               SET regla     = CASE WHEN (v_rank->>v_sev)::INT > (v_rank->>i.severidad)::INT
                                    THEN v_regla ELSE regla END,
                   severidad = CASE WHEN (v_rank->>v_sev)::INT > (v_rank->>i.severidad)::INT
                                    THEN v_sev ELSE severidad END,
                   horas_sin_contacto = round(r.horas, 1),
                   evaluado_en = NOW()
             WHERE id = i.id;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('ingesta_caida', false, 'ultimo_poll', v_ultimo_poll,
        'abiertos', v_abiertos, 'subidos', v_subidos, 'cerrados', v_cerrados);
END;
$$;

REVOKE ALL ON FUNCTION fn_centinela_evaluar() FROM PUBLIC, anon, authenticated;

-- ── 4. Vista de trabajo (la usan el correo y la pantalla) ───────────────────

CREATE OR REPLACE VIEW v_centinela_incidentes AS
SELECT i.*,
       a.patente::TEXT   AS patente,
       a.codigo::TEXT    AS codigo,
       a.nombre::TEXT    AS nombre,
       a.operacion::TEXT AS operacion,
       -- Dónde está AHORA (si volvió) — para el aviso de recuperado.
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

-- ── 5. Correo (cron con secreto, patrón MIG301) ─────────────────────────────

-- Lo que hay que avisar AHORA (modo 'inmediato') o el resumen del día.
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
            -- Avisar la caída una vez cada 12 h, no cada hora.
            'avisar', v_caida AND (c.ingesta_caida_notificada_en IS NULL
                         OR c.ingesta_caida_notificada_en < NOW() - INTERVAL '12 hours')),
        'horas_escalar', c.horas_escalar,
        -- Críticos que todavía no se avisaron a ese nivel.
        'nuevos', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.horas_sin_contacto DESC)
            FROM v_centinela_incidentes v
           WHERE v.estado <> 'cerrado' AND v.severidad = 'critico'
             AND v.severidad_notificada IS DISTINCT FROM 'critico'), '[]'),
        -- Críticos avisados que nadie tomó en N horas.
        'escalar', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.notificado_en)
            FROM v_centinela_incidentes v
           WHERE v.estado = 'abierto' AND v.severidad = 'critico'
             AND v.severidad_notificada = 'critico'
             AND v.escalado_en IS NULL
             AND v.notificado_en < NOW() - make_interval(secs => c.horas_escalar * 3600)), '[]'),
        -- Críticos avisados que volvieron solos: decirlo también.
        'recuperados', COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.cerrado_en)
            FROM v_centinela_incidentes v
           WHERE v.estado = 'cerrado' AND v.motivo_cierre = 'senal_recuperada'
             AND v.severidad_notificada = 'critico'
             AND v.recuperado_notificado_en IS NULL), '[]')
    );

    IF p_modo = 'resumen' THEN
        v_out := v_out || jsonb_build_object(
            'abiertos', COALESCE((SELECT jsonb_agg(to_jsonb(v)
                    ORDER BY CASE v.severidad WHEN 'critico' THEN 1 WHEN 'alto' THEN 2 ELSE 3 END,
                             v.horas_sin_contacto DESC)
                FROM v_centinela_incidentes v WHERE v.estado <> 'cerrado'), '[]'),
            -- Arrendados que no se pueden vigilar por zona (Fase B).
            'sin_geocerca', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'patente', g.activo_patente, 'codigo', g.activo_codigo,
                    'cliente', g.cliente, 'contrato', g.contrato_codigo) ORDER BY g.activo_patente)
                FROM v_activo_geocerca_esperada g
                JOIN activos a ON a.id = g.activo_id
               WHERE g.estado_comercial::TEXT = 'arrendado' AND g.geocerca_id IS NULL
                 AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, FALSE)), '[]'));
    END IF;
    RETURN v_out;
END;
$$;

-- El correo salió: dejar constancia para no repetirlo.
CREATE OR REPLACE FUNCTION fn_centinela_marcar_cron(
    p_secreto     TEXT,
    p_nuevos      UUID[] DEFAULT '{}',
    p_escalados   UUID[] DEFAULT '{}',
    p_recuperados UUID[] DEFAULT '{}',
    p_ingesta     BOOLEAN DEFAULT FALSE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    UPDATE centinela_incidentes
       SET notificado_en = NOW(), severidad_notificada = severidad
     WHERE id = ANY(p_nuevos);
    UPDATE centinela_incidentes SET escalado_en = NOW() WHERE id = ANY(p_escalados);
    UPDATE centinela_incidentes SET recuperado_notificado_en = NOW() WHERE id = ANY(p_recuperados);
    IF p_ingesta THEN
        UPDATE centinela_config SET ingesta_caida_notificada_en = NOW() WHERE id = 1;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_centinela_correo_cron(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_centinela_marcar_cron(TEXT, UUID[], UUID[], UUID[], BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_centinela_correo_cron(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_centinela_marcar_cron(TEXT, UUID[], UUID[], UUID[], BOOLEAN) TO anon, authenticated;

-- ── 6. Pantalla: listar, acusar recibo, cerrar ──────────────────────────────

CREATE OR REPLACE FUNCTION rpc_centinela_listar(p_dias_cerrados INT DEFAULT 14)
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
    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(v) || jsonb_build_object(
                   'acusado_por_nombre', (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = v.acusado_por),
                   'cerrado_por_nombre', (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = v.cerrado_por))
               ORDER BY (v.estado = 'cerrado'),
                        CASE v.severidad WHEN 'critico' THEN 1 WHEN 'alto' THEN 2 ELSE 3 END,
                        v.horas_sin_contacto DESC NULLS LAST, v.cerrado_en DESC NULLS LAST)
          FROM v_centinela_incidentes v
         WHERE v.estado <> 'cerrado'
            OR v.cerrado_en > NOW() - make_interval(days => p_dias_cerrados)), '[]');
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_acusar(p_id UUID, p_nota TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para gestionar incidentes del Centinela';
    END IF;
    UPDATE centinela_incidentes
       SET estado = 'acusado', acusado_en = NOW(), acusado_por = auth.uid(),
           nota_acuse = NULLIF(trim(p_nota), '')
     WHERE id = p_id AND estado = 'abierto';
    IF NOT FOUND THEN RAISE EXCEPTION 'El incidente no está abierto'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_centinela_cerrar(p_id UUID, p_motivo TEXT, p_detalle TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','jefe_operaciones',
            'planificador','subgerente_operaciones']::TEXT[]) THEN
        RAISE EXCEPTION 'Sin permiso para gestionar incidentes del Centinela';
    END IF;
    IF p_motivo IS NULL OR p_motivo NOT IN ('ubicado_con_evidencia', 'falla_gps',
            'traslado_autorizado', 'denuncia', 'falso_positivo', 'otro') THEN
        RAISE EXCEPTION 'Motivo de cierre inválido';
    END IF;
    -- Cerrar sin decir qué se hizo es lo que dejó a KVWD-27 110 días a ciegas.
    IF length(trim(COALESCE(p_detalle, ''))) < 10 THEN
        RAISE EXCEPTION 'Cuenta qué se verificó (mínimo 10 caracteres): quién lo vio, foto, N° de OT o de denuncia';
    END IF;
    UPDATE centinela_incidentes
       SET estado = 'cerrado', cerrado_en = NOW(), cerrado_por = auth.uid(),
           motivo_cierre = p_motivo, detalle_cierre = trim(p_detalle),
           acusado_en  = COALESCE(acusado_en, NOW()),
           acusado_por = COALESCE(acusado_por, auth.uid())
     WHERE id = p_id AND estado <> 'cerrado';
    IF NOT FOUND THEN RAISE EXCEPTION 'El incidente ya está cerrado'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION rpc_centinela_listar(INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_acusar(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_centinela_cerrar(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_centinela_listar(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_acusar(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_centinela_cerrar(UUID, TEXT, TEXT) TO authenticated;

-- Primera pasada: deja abiertos los casos de hoy (KVWD-27 incluido).
SELECT fn_centinela_evaluar();

COMMIT;

-- ── 7. Crons ────────────────────────────────────────────────────────────────
-- Evaluar a los :15 (el poll GPS es a los :00 y a veces tarda), avisar a los
-- :20, y el resumen del día a las 11:00 UTC (08:00 Chile en horario de
-- verano, 07:00 en invierno).
DO $cron$
DECLARE
    v_cmd TEXT;
    v_sec TEXT;
    v_ok  BOOLEAN;
    v_post TEXT := $p$
    SELECT net.http_post(
        url     := 'https://pilladoiceo.netlify.app/api/notificaciones/centinela/',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', %L),
        body    := %L::jsonb,
        timeout_milliseconds := 30000);
    $p$;
BEGIN
    -- El secreto vigente se toma del job de MIG504 y se verifica (regla MIG501).
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    SELECT (hash = encode(digest(v_sec, 'sha256'), 'hex')) INTO v_ok
      FROM sistema_secretos WHERE codigo = 'cron_alertas';
    IF v_sec IS NULL OR NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: no hay un CRON_SECRET vigente que reutilizar';
    END IF;

    PERFORM cron.unschedule(jobname) FROM cron.job
     WHERE jobname IN ('centinela-evaluar', 'centinela-correo', 'centinela-resumen');

    PERFORM cron.schedule('centinela-evaluar', '15 * * * *', 'SELECT fn_centinela_evaluar();');
    PERFORM cron.schedule('centinela-correo',  '20 * * * *',
                          format(v_post, v_sec, '{"modo":"inmediato"}'));
    PERFORM cron.schedule('centinela-resumen', '0 11 * * *',
                          format(v_post, v_sec, '{"modo":"resumen"}'));

    RAISE NOTICE 'Centinela: 3 crons programados';
END
$cron$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_kvwd RECORD; v_n INT; v_null INT;
BEGIN
    SELECT count(*) FILTER (WHERE ts_ultimo_contacto IS NULL) INTO v_null FROM gps_estado_actual;
    SELECT count(*) INTO v_n FROM centinela_incidentes WHERE estado <> 'cerrado';
    SELECT i.severidad, i.horas_sin_contacto INTO v_kvwd
      FROM centinela_incidentes i JOIN activos a ON a.id = i.activo_id
     WHERE a.patente = 'KVWD-27' AND i.estado <> 'cerrado';
    IF v_kvwd.severidad IS DISTINCT FROM 'critico' THEN
        RAISE EXCEPTION 'FALLO: KVWD-27 debería quedar CRÍTICO y quedó %', v_kvwd.severidad;
    END IF;
    RAISE NOTICE 'Centinela OK · % incidentes abiertos · KVWD-27 crítico con % h sin contacto · % equipos sin último contacto',
        v_n, v_kvwd.horas_sin_contacto, v_null;
END
$mig$;

SELECT i.severidad, a.patente, a.estado_comercial, i.horas_sin_contacto,
       i.velocidad_kmh, i.bateria_pct
  FROM centinela_incidentes i JOIN activos a ON a.id = i.activo_id
 WHERE i.estado <> 'cerrado'
 ORDER BY CASE i.severidad WHEN 'critico' THEN 1 WHEN 'alto' THEN 2 ELSE 3 END,
          i.horas_sin_contacto DESC;
