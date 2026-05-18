-- ============================================================================
-- 60_historico_contrato_activo.sql
-- ----------------------------------------------------------------------------
-- Registra cada cambio de contrato_id en activos (vinculacion comercial).
-- Es la fuente de verdad para calcular "cuantos dias estuvo X activo con
-- el cliente Y" — clave para facturacion, comparaciones, churn.
--
-- Decision Manuel (2026-05-18): tabla dedicada, validacion = solo warning
-- en UI si esta arrendado (no se bloquea en BD).
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP - tabla activos no existe.';
    END IF;
END $$;


-- ============================================================================
-- 1. TABLA historico_contrato_activo
-- ============================================================================
CREATE TABLE IF NOT EXISTS historico_contrato_activo (
    id                       BIGSERIAL    PRIMARY KEY,
    activo_id                UUID         NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    contrato_anterior_id     UUID         REFERENCES contratos(id) ON DELETE SET NULL,
    contrato_nuevo_id        UUID         REFERENCES contratos(id) ON DELETE SET NULL,
    cambio_at                TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    cambio_por               UUID         REFERENCES auth.users(id),
    razon                    TEXT,
    -- Snapshot del activo al momento del cambio (auditoria comercial)
    estado_comercial_al_momento estado_comercial_enum,
    horometro                NUMERIC(12,1),
    kilometraje              NUMERIC(12,1),
    -- Duracion del contrato anterior (calculada al cierre)
    duracion_contrato_anterior_dias NUMERIC(10,2)
);

CREATE INDEX IF NOT EXISTS idx_hist_contrato_activo_fecha
    ON historico_contrato_activo (activo_id, cambio_at DESC);
CREATE INDEX IF NOT EXISTS idx_hist_contrato_anterior
    ON historico_contrato_activo (contrato_anterior_id) WHERE contrato_anterior_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_hist_contrato_nuevo
    ON historico_contrato_activo (contrato_nuevo_id) WHERE contrato_nuevo_id IS NOT NULL;


-- ============================================================================
-- 2. TRIGGER: AFTER UPDATE OF contrato_id en activos -> historico
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_registrar_historico_contrato_activo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_ultimo_cambio TIMESTAMPTZ;
    v_duracion_dias NUMERIC;
    v_horo          NUMERIC;
    v_km            NUMERIC;
BEGIN
    -- Solo registrar si realmente cambio (NULL <> NULL es false, NULL = X es null)
    IF NEW.contrato_id IS NOT DISTINCT FROM OLD.contrato_id THEN
        RETURN NEW;
    END IF;

    -- Calcular duracion del contrato anterior (desde su asignacion hasta ahora)
    SELECT MAX(cambio_at) INTO v_ultimo_cambio
      FROM historico_contrato_activo
     WHERE activo_id = NEW.id;
    IF v_ultimo_cambio IS NULL THEN
        v_ultimo_cambio := OLD.created_at;
    END IF;
    v_duracion_dias := EXTRACT(EPOCH FROM (NOW() - v_ultimo_cambio)) / 86400.0;

    -- Lectura GPS actual (si existe)
    IF to_regclass('public.gps_estado_actual') IS NOT NULL THEN
        SELECT horometro_hrs, odometro_km
          INTO v_horo, v_km
          FROM gps_estado_actual WHERE activo_id = NEW.id;
    END IF;

    INSERT INTO historico_contrato_activo (
        activo_id, contrato_anterior_id, contrato_nuevo_id,
        cambio_at, cambio_por,
        estado_comercial_al_momento, horometro, kilometraje,
        duracion_contrato_anterior_dias
    ) VALUES (
        NEW.id, OLD.contrato_id, NEW.contrato_id,
        NOW(), auth.uid(),
        NEW.estado_comercial, v_horo, v_km,
        ROUND(v_duracion_dias::numeric, 2)
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrar_historico_contrato ON activos;
CREATE TRIGGER trg_registrar_historico_contrato
    AFTER UPDATE OF contrato_id ON activos
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_historico_contrato_activo();


-- ============================================================================
-- 3. RPC rpc_cambiar_contrato_activo
-- ----------------------------------------------------------------------------
-- Wrapper sobre UPDATE para capturar la 'razon' del cambio (el trigger no
-- puede recibir contexto extra). Permite NULL para "quitar contrato".
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_cambiar_contrato_activo(
    p_activo_id        UUID,
    p_nuevo_contrato_id UUID,    -- NULL para quitar
    p_razon            TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activo  RECORD;
    v_id_hist BIGINT;
BEGIN
    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF v_activo.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    -- Validar nuevo contrato si no es NULL
    IF p_nuevo_contrato_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM contratos WHERE id = p_nuevo_contrato_id) THEN
            RAISE EXCEPTION 'Contrato % no existe', p_nuevo_contrato_id;
        END IF;
    END IF;

    -- Si no hay cambio, no hacer nada (trigger lo skipearia igual)
    IF v_activo.contrato_id IS NOT DISTINCT FROM p_nuevo_contrato_id THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    -- Aplicar el cambio (trigger registra historico)
    UPDATE activos SET contrato_id = p_nuevo_contrato_id WHERE id = p_activo_id;

    -- Actualizar la razon en el ultimo registro de historico (creado por trigger)
    SELECT id INTO v_id_hist
      FROM historico_contrato_activo
     WHERE activo_id = p_activo_id
     ORDER BY cambio_at DESC, id DESC
     LIMIT 1;

    IF v_id_hist IS NOT NULL AND p_razon IS NOT NULL THEN
        UPDATE historico_contrato_activo
           SET razon = p_razon
         WHERE id = v_id_hist;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'activo_id', p_activo_id,
        'contrato_anterior', v_activo.contrato_id,
        'contrato_nuevo', p_nuevo_contrato_id,
        'historico_id', v_id_hist
    );
END;
$$;

REVOKE ALL ON FUNCTION rpc_cambiar_contrato_activo(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cambiar_contrato_activo(UUID, UUID, TEXT) TO authenticated;


-- ============================================================================
-- 4. VISTA v_historico_contrato_activo_enriquecido
-- ----------------------------------------------------------------------------
-- Para la UI: cada cambio con datos de contratos anterior y nuevo
-- (codigo + cliente), y nombre del usuario que lo hizo.
-- ============================================================================
CREATE OR REPLACE VIEW v_historico_contrato_activo_enriquecido AS
SELECT
    h.id,
    h.activo_id,
    a.codigo            AS activo_codigo,
    a.patente           AS activo_patente,
    h.cambio_at,
    h.cambio_por,
    u.email             AS cambio_por_email,
    h.contrato_anterior_id,
    ca.codigo           AS contrato_anterior_codigo,
    ca.cliente          AS cliente_anterior,
    h.contrato_nuevo_id,
    cn.codigo           AS contrato_nuevo_codigo,
    cn.cliente          AS cliente_nuevo,
    h.razon,
    h.estado_comercial_al_momento,
    h.horometro,
    h.kilometraje,
    h.duracion_contrato_anterior_dias
FROM historico_contrato_activo h
JOIN activos a               ON a.id = h.activo_id
LEFT JOIN contratos ca       ON ca.id = h.contrato_anterior_id
LEFT JOIN contratos cn       ON cn.id = h.contrato_nuevo_id
LEFT JOIN auth.users u       ON u.id = h.cambio_por;

GRANT SELECT ON v_historico_contrato_activo_enriquecido TO authenticated;


-- ============================================================================
-- 5. RLS
-- ============================================================================
ALTER TABLE historico_contrato_activo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_hist_contrato_select ON historico_contrato_activo;
CREATE POLICY pol_hist_contrato_select ON historico_contrato_activo
    FOR SELECT TO authenticated USING (true);

-- Los INSERTs son via trigger (SECURITY DEFINER bypass RLS naturally) y via
-- RPC rpc_cambiar_contrato_activo. No habilitamos INSERT directo desde frontend.


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_hist_contrato',     to_regclass('public.historico_contrato_activo') IS NOT NULL,
    'trigger_hist_contrato',   EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_registrar_historico_contrato'),
    'rpc_cambiar_contrato',    EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_cambiar_contrato_activo'),
    'vista_hist_enriquecido',  to_regclass('public.v_historico_contrato_activo_enriquecido') IS NOT NULL
) AS resultado;

NOTIFY pgrst, 'reload schema';
