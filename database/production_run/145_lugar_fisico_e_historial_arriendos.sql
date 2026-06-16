-- ============================================================================
-- SICOM-ICEO | 145 — Lugar fisico del equipo + Historial de arriendos
-- ----------------------------------------------------------------------------
-- Pedido de comercial:
--   (a) el equipo, ademas del contrato, indica su LUGAR FISICO (faena + detalle);
--   (b) al pasar a 'en_recepcion' o 'disponible', ver el ULTIMO que lo arrendo
--       y DONDE;
--   (c) HISTORIAL DE ARRIENDOS del equipo.
--
-- Diseno (decisiones Manuel 2026-06-16):
--   - Lugar fisico = faena (estructurada, con coordenadas) + texto libre
--     (activos.faena_id + activos.ubicacion_actual). No se crean columnas nuevas
--     en activos: ya existen.
--   - Historial RECONSTRUIDO desde historico_estado_activo (sin doble captura).
--     Se enriquece ese registro para que capture cliente + lugar fisico en cada
--     cambio, y dos vistas reconstruyen los periodos de arriendo y el ultimo.
--
-- Requiere: historico_estado_activo (MIG 59). IDEMPOTENTE.
-- ============================================================================

-- ── 0. Precheck ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.historico_estado_activo') IS NULL THEN
        RAISE EXCEPTION 'STOP - falta historico_estado_activo (aplicar MIG 59).';
    END IF;
END $$;


-- ── 1. Snapshot de cliente + lugar fisico en cada cambio de estado ───────────
ALTER TABLE historico_estado_activo
    ADD COLUMN IF NOT EXISTS faena_id        UUID REFERENCES faenas(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS cliente         VARCHAR(200),
    ADD COLUMN IF NOT EXISTS ubicacion_lugar VARCHAR(200);

COMMENT ON COLUMN historico_estado_activo.cliente IS
    'Cliente que tenia el equipo al momento del cambio (snapshot). Para "ultimo que lo arrendo".';
COMMENT ON COLUMN historico_estado_activo.ubicacion_lugar IS
    'Lugar fisico (texto libre, ej. faena/patio) al momento del cambio. Complementa faena_id.';


-- ── 2. Trigger: snapshot cliente/lugar/faena al cambiar estado_comercial ─────
CREATE OR REPLACE FUNCTION fn_registrar_historico_estado_activo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_ultimo_cambio TIMESTAMPTZ;
    v_duracion      NUMERIC;
    v_lat           NUMERIC;
    v_lng           NUMERIC;
    v_horo          NUMERIC;
    v_km            NUMERIC;
    v_cliente       VARCHAR(200);
    v_origen        origen_cambio_estado_enum := 'manual';
BEGIN
    IF NEW.estado_comercial IS NOT DISTINCT FROM OLD.estado_comercial THEN
        RETURN NEW;
    END IF;

    SELECT MAX(cambio_at) INTO v_ultimo_cambio
      FROM historico_estado_activo WHERE activo_id = NEW.id;
    IF v_ultimo_cambio IS NULL THEN
        v_ultimo_cambio := OLD.updated_at;
    END IF;
    v_duracion := EXTRACT(EPOCH FROM (NOW() - v_ultimo_cambio)) / 3600.0;

    IF to_regclass('public.gps_estado_actual') IS NOT NULL THEN
        SELECT latitud, longitud, horometro_hrs, odometro_km
          INTO v_lat, v_lng, v_horo, v_km
          FROM gps_estado_actual WHERE activo_id = NEW.id;
    END IF;

    -- Cliente al momento: el del activo, o el del contrato vigente
    v_cliente := COALESCE(NEW.cliente_actual,
                          (SELECT cliente FROM contratos WHERE id = NEW.contrato_id));

    INSERT INTO historico_estado_activo (
        activo_id, estado_anterior, estado_nuevo, cambio_at, cambio_por,
        origen, contrato_id, razon,
        latitud, longitud, horometro, kilometraje,
        duracion_estado_anterior_horas,
        faena_id, cliente, ubicacion_lugar
    ) VALUES (
        NEW.id, OLD.estado_comercial, NEW.estado_comercial, NOW(), auth.uid(),
        v_origen, NEW.contrato_id,
        format('Cambio %s -> %s', COALESCE(OLD.estado_comercial::text,'(null)'), NEW.estado_comercial::text),
        v_lat, v_lng, v_horo, v_km,
        ROUND(v_duracion::numeric, 2),
        NEW.faena_id, v_cliente, NEW.ubicacion_actual
    );

    RETURN NEW;
END;
$$;


-- ── 3. VISTA: historial de arriendos (reconstruido) ──────────────────────────
-- Cada periodo en que el equipo estuvo asignado a alguien (arrendado / leasing /
-- uso interno), con cliente, lugar fisico, inicio, fin y dias. El fin es el
-- siguiente cambio de estado del equipo (NULL = vigente).
CREATE OR REPLACE VIEW v_historial_arriendos AS
WITH periodos AS (
    SELECT
        h.activo_id,
        h.estado_nuevo,
        h.cambio_at AS fecha_inicio,
        LEAD(h.cambio_at) OVER (PARTITION BY h.activo_id ORDER BY h.cambio_at) AS fecha_fin,
        h.contrato_id,
        COALESCE(h.cliente, c.cliente)        AS cliente,
        COALESCE(NULLIF(h.ubicacion_lugar,''), f.nombre) AS lugar,
        h.faena_id,
        f.nombre  AS faena_nombre,
        f.region  AS faena_region,
        h.horometro, h.kilometraje, h.origen, h.cambio_at
    FROM historico_estado_activo h
    LEFT JOIN contratos c ON c.id = h.contrato_id
    LEFT JOIN faenas    f ON f.id = h.faena_id
    WHERE h.estado_nuevo IN ('arrendado','leasing','uso_interno')
)
SELECT
    p.activo_id, a.patente, a.codigo, a.nombre AS equipo,
    p.estado_nuevo AS tipo_uso,
    p.cliente, p.lugar, p.faena_id, p.faena_nombre, p.faena_region,
    p.contrato_id,
    p.fecha_inicio, p.fecha_fin,
    (COALESCE(p.fecha_fin, NOW())::date - p.fecha_inicio::date) AS dias,
    (p.fecha_fin IS NULL) AS vigente,
    p.horometro, p.kilometraje, p.origen
FROM periodos p
JOIN activos a ON a.id = p.activo_id;


-- ── 4. VISTA: ultimo arriendo por equipo ─────────────────────────────────────
-- "El ultimo que lo arrendo y donde". Util cuando el equipo ya esta en
-- recepcion o disponible: muestra de donde viene.
CREATE OR REPLACE VIEW v_activo_ultimo_arriendo AS
SELECT DISTINCT ON (activo_id)
    activo_id, patente, codigo, equipo,
    tipo_uso, cliente, lugar, faena_id, faena_nombre, faena_region,
    contrato_id, fecha_inicio, fecha_fin, dias, vigente
FROM v_historial_arriendos
ORDER BY activo_id, fecha_inicio DESC;


GRANT SELECT ON v_historial_arriendos    TO authenticated;
GRANT SELECT ON v_activo_ultimo_arriendo TO authenticated;


-- ── 5. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_faena_id',   (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                       WHERE table_name='historico_estado_activo' AND column_name='faena_id')),
    'col_cliente',    (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                       WHERE table_name='historico_estado_activo' AND column_name='cliente')),
    'col_lugar',      (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                       WHERE table_name='historico_estado_activo' AND column_name='ubicacion_lugar')),
    'vista_historial',(SELECT EXISTS(SELECT 1 FROM pg_views WHERE viewname='v_historial_arriendos')),
    'vista_ultimo',   (SELECT EXISTS(SELECT 1 FROM pg_views WHERE viewname='v_activo_ultimo_arriendo')),
    'filas_historico',(SELECT COUNT(*) FROM historico_estado_activo)
) AS resultado;

NOTIFY pgrst, 'reload schema';
