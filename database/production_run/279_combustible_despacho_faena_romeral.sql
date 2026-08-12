-- ============================================================================
-- SICOM-ICEO | 279 — Despacho de combustible en faena (registro que hoy es papel)
-- ============================================================================
-- Romeral: el camión del proveedor llega a CMP, los camiones de Pillado cargan
-- y salen a abastecer equipos en faena — palas, generadores, luminarias,
-- jumbos, CAEX. Cada equipo pertenece a un CECO (centro de costo, a veces de un
-- contratista distinto: Santa Elvira, Recomin, Enaex). Hoy todo eso se anota en
-- papel y alguien lo transcribe después, o no.
--
-- Esto registra el despacho tal como se anota en terreno: medidor inicial y
-- final, litros, a quién se cargó, en qué lugar, en qué turno y quién lo cargó.
--
-- SEPARACIÓN POR FAENA: todo cuelga de faena_id. Romeral no comparte catálogo,
-- stock ni reportes con Franke ni con la operación de Coquimbo — son negocios
-- distintos y mezclarlos arruinaría los informes de los tres.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='faenas') THEN
        RAISE EXCEPTION 'STOP — falta la tabla faenas'; END IF;
END $$;


-- ── 1. Centros de costo de la faena ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS combustible_faena_cecos (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id   UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    codigo     TEXT NOT NULL,                  -- "115037", "4016360 0070"
    empresa    TEXT,                           -- "Empresa Santa Elvira", "Recomin"
    activo     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_ceco_faena_codigo
    ON combustible_faena_cecos (faena_id, codigo);


-- ── 2. Lugares de la faena ──────────────────────────────────────────────────
-- "NIVEL 300", "BANCO 275", "ACOPIO DOMO", "CHANCADO"… donde se hace la carga.
CREATE TABLE IF NOT EXISTS combustible_faena_ubicaciones (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id   UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    nombre     TEXT NOT NULL,
    activo     BOOLEAN NOT NULL DEFAULT TRUE,
    orden      INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_ubic_faena_nombre
    ON combustible_faena_ubicaciones (faena_id, lower(nombre));


-- ── 3. Equipos que se abastecen ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS combustible_faena_equipos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    ceco_id     UUID REFERENCES combustible_faena_cecos(id) ON DELETE SET NULL,
    nombre      TEXT NOT NULL,                 -- como lo nombra el operador: "PALA 17"
    descripcion TEXT,                          -- nombre largo del listado del cliente
    tipo        TEXT,                          -- pala, generador, luminaria, CAEX…
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_equipo_faena_nombre
    ON combustible_faena_equipos (faena_id, lower(nombre));
CREATE INDEX IF NOT EXISTS ix_comb_equipo_ceco ON combustible_faena_equipos (ceco_id);


-- ── 4. El despacho: lo que hoy se anota en el papel ─────────────────────────
CREATE TABLE IF NOT EXISTS combustible_faena_despachos (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id       UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    fecha          DATE NOT NULL DEFAULT CURRENT_DATE,
    turno          TEXT,                        -- "Día" / "Noche" / "A" / "B"
    -- Desde qué camión se despachó (los camiones cisterna son estanques móviles)
    estanque_id    UUID REFERENCES combustible_estanques(id) ON DELETE SET NULL,
    camion_patente TEXT,                        -- respaldo si el camión no está en el catálogo
    -- A quién se cargó
    equipo_id      UUID REFERENCES combustible_faena_equipos(id) ON DELETE SET NULL,
    equipo_texto   TEXT,                        -- si el operador anota uno que no está en catálogo
    ceco_id        UUID REFERENCES combustible_faena_cecos(id) ON DELETE SET NULL,
    ubicacion_id   UUID REFERENCES combustible_faena_ubicaciones(id) ON DELETE SET NULL,
    ubicacion_texto TEXT,
    -- Lecturas del medidor del camión
    meter_inicial  NUMERIC(12,2),
    meter_final    NUMERIC(12,2),
    litros         NUMERIC(12,2) NOT NULL CHECK (litros >= 0),
    -- Quién cargó
    operador_id    UUID REFERENCES usuarios_perfil(id),
    operador_nombre TEXT,
    -- Evidencia opcional (se irá exigiendo más adelante)
    horometro      NUMERIC(12,1),
    kilometraje    NUMERIC(12,1),
    foto_medidor_url TEXT,
    firma_receptor_url TEXT,
    nombre_receptor TEXT,
    observacion    TEXT,
    hora           TIME,
    anulado        BOOLEAN NOT NULL DEFAULT FALSE,
    anulado_motivo TEXT,
    -- Para que la app de terreno pueda reintentar sin duplicar
    client_uuid    TEXT UNIQUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by     UUID REFERENCES usuarios_perfil(id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_comb_desp_faena_fecha ON combustible_faena_despachos (faena_id, fecha);
CREATE INDEX IF NOT EXISTS ix_comb_desp_ceco       ON combustible_faena_despachos (ceco_id);
CREATE INDEX IF NOT EXISTS ix_comb_desp_equipo     ON combustible_faena_despachos (equipo_id);

COMMENT ON TABLE combustible_faena_despachos IS
    'Despacho de combustible a equipos en faena — reemplaza el registro en papel. MIG279.';
COMMENT ON COLUMN combustible_faena_despachos.client_uuid IS
    'Id que genera el teléfono: si el envío se reintenta sin señal, no se duplica el despacho.';

CREATE OR REPLACE FUNCTION fn_comb_faena_touch() RETURNS TRIGGER
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS tg_comb_desp_touch ON combustible_faena_despachos;
CREATE TRIGGER tg_comb_desp_touch BEFORE UPDATE ON combustible_faena_despachos
    FOR EACH ROW EXECUTE FUNCTION fn_comb_faena_touch();


-- ── 5. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE combustible_faena_cecos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_faena_ubicaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_faena_equipos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_faena_despachos   ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['combustible_faena_cecos','combustible_faena_ubicaciones',
                             'combustible_faena_equipos','combustible_faena_despachos'] LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_sel ON %I', t, t);
        EXECUTE format('CREATE POLICY pol_%s_sel ON %I FOR SELECT USING (fn_user_rol() IS NOT NULL)', t, t);
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_wr ON %I', t, t);
        EXECUTE format('CREATE POLICY pol_%s_wr ON %I FOR ALL USING (fn_user_rol() IS NOT NULL) WITH CHECK (fn_user_rol() IS NOT NULL)', t, t);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO authenticated', t);
    END LOOP;
END $$;


-- ── 6. Registrar un despacho ────────────────────────────────────────────────
-- Los litros se calculan del medidor cuando vienen las dos lecturas: es lo que
-- manda en el papel. Si el operador anota los litros a mano (medidor con falla),
-- se respeta lo que escribió.
CREATE OR REPLACE FUNCTION rpc_comb_faena_despachar(
    p_faena_id     UUID,
    p_fecha        DATE,
    p_turno        TEXT,
    p_estanque_id  UUID,
    p_equipo_id    UUID,
    p_ubicacion_id UUID,
    p_meter_inicial NUMERIC,
    p_meter_final  NUMERIC,
    p_litros       NUMERIC,
    p_operador_nombre TEXT DEFAULT NULL,
    p_hora         TIME DEFAULT NULL,
    p_equipo_texto TEXT DEFAULT NULL,
    p_ubicacion_texto TEXT DEFAULT NULL,
    p_camion_patente TEXT DEFAULT NULL,
    p_horometro    NUMERIC DEFAULT NULL,
    p_kilometraje  NUMERIC DEFAULT NULL,
    p_observacion  TEXT DEFAULT NULL,
    p_client_uuid  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID; v_litros NUMERIC; v_ceco UUID;
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sesión requerida'; END IF;
    IF p_faena_id IS NULL THEN RAISE EXCEPTION 'Falta la faena'; END IF;

    -- Reintento del teléfono sin señal: si ya se guardó, se devuelve el mismo.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM combustible_faena_despachos WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', true, 'despacho_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    v_litros := COALESCE(
        CASE WHEN p_meter_final IS NOT NULL AND p_meter_inicial IS NOT NULL
                  AND p_meter_final >= p_meter_inicial
             THEN p_meter_final - p_meter_inicial END,
        p_litros);
    IF v_litros IS NULL OR v_litros < 0 THEN RAISE EXCEPTION 'Litros inválidos'; END IF;

    -- El CECO sale del equipo: el operador elige a quién carga, no un número.
    SELECT ceco_id INTO v_ceco FROM combustible_faena_equipos WHERE id = p_equipo_id;

    INSERT INTO combustible_faena_despachos (
        faena_id, fecha, turno, estanque_id, camion_patente,
        equipo_id, equipo_texto, ceco_id, ubicacion_id, ubicacion_texto,
        meter_inicial, meter_final, litros,
        operador_id, operador_nombre, horometro, kilometraje, observacion, hora,
        client_uuid, created_by)
    VALUES (
        p_faena_id, COALESCE(p_fecha, CURRENT_DATE), NULLIF(TRIM(COALESCE(p_turno,'')),''),
        p_estanque_id, NULLIF(TRIM(COALESCE(p_camion_patente,'')),''),
        p_equipo_id, NULLIF(TRIM(COALESCE(p_equipo_texto,'')),''), v_ceco,
        p_ubicacion_id, NULLIF(TRIM(COALESCE(p_ubicacion_texto,'')),''),
        p_meter_inicial, p_meter_final, v_litros,
        auth.uid(), NULLIF(TRIM(COALESCE(p_operador_nombre,'')),''),
        p_horometro, p_kilometraje, NULLIF(TRIM(COALESCE(p_observacion,'')),''),
        p_hora, p_client_uuid, auth.uid())
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'despacho_id', v_id, 'litros', v_litros);
END $$;

-- Anular sin borrar: el papel tampoco se rompe, se tacha con motivo.
CREATE OR REPLACE FUNCTION rpc_comb_faena_anular_despacho(p_id UUID, p_motivo TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sesión requerida'; END IF;
    IF NULLIF(TRIM(COALESCE(p_motivo,'')),'') IS NULL THEN RAISE EXCEPTION 'Indica el motivo'; END IF;
    UPDATE combustible_faena_despachos
       SET anulado = TRUE, anulado_motivo = p_motivo
     WHERE id = p_id AND NOT anulado;
    RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION rpc_comb_faena_despachar(UUID, DATE, TEXT, UUID, UUID, UUID, NUMERIC, NUMERIC,
    NUMERIC, TEXT, TIME, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_comb_faena_anular_despacho(UUID, TEXT) TO authenticated;


-- ── 7. Vistas para el día y para el reporte por CECO ────────────────────────
CREATE OR REPLACE VIEW v_comb_faena_despachos AS
SELECT d.id, d.faena_id, f.nombre AS faena, d.fecha, d.hora, d.turno,
       d.estanque_id, e.nombre AS camion, COALESCE(e.patente, d.camion_patente) AS camion_patente,
       d.equipo_id, COALESCE(eq.nombre, d.equipo_texto) AS equipo, eq.descripcion AS equipo_descripcion,
       d.ceco_id, c.codigo AS ceco, c.empresa AS ceco_empresa,
       d.ubicacion_id, COALESCE(u.nombre, d.ubicacion_texto) AS ubicacion,
       d.meter_inicial, d.meter_final, d.litros,
       d.operador_nombre, d.horometro, d.kilometraje, d.observacion,
       d.anulado, d.anulado_motivo, d.created_at
  FROM combustible_faena_despachos d
  JOIN faenas f ON f.id = d.faena_id
  LEFT JOIN combustible_estanques e ON e.id = d.estanque_id
  LEFT JOIN combustible_faena_equipos eq ON eq.id = d.equipo_id
  LEFT JOIN combustible_faena_cecos c ON c.id = d.ceco_id
  LEFT JOIN combustible_faena_ubicaciones u ON u.id = d.ubicacion_id;

GRANT SELECT ON v_comb_faena_despachos TO authenticated;

-- Consumo por CECO: es lo que el cliente pide para su control de costos.
CREATE OR REPLACE VIEW v_comb_faena_consumo_ceco AS
SELECT d.faena_id, f.nombre AS faena,
       date_trunc('month', d.fecha)::date AS periodo,
       c.id AS ceco_id, c.codigo AS ceco, c.empresa AS ceco_empresa,
       count(*) AS despachos,
       sum(d.litros) AS litros,
       count(DISTINCT d.equipo_id) AS equipos
  FROM combustible_faena_despachos d
  JOIN faenas f ON f.id = d.faena_id
  LEFT JOIN combustible_faena_cecos c ON c.id = d.ceco_id
 WHERE NOT d.anulado
 GROUP BY d.faena_id, f.nombre, date_trunc('month', d.fecha), c.id, c.codigo, c.empresa;

GRANT SELECT ON v_comb_faena_consumo_ceco TO authenticated;


SELECT 'MIG279 OK' AS resultado,
       (SELECT count(*) FROM combustible_faena_cecos)  AS cecos,
       (SELECT count(*) FROM combustible_faena_equipos) AS equipos;
