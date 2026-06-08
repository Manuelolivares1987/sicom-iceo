-- ============================================================================
-- SICOM-ICEO | Migracion 130 — Control de combustible Franke (fundacion)
-- ----------------------------------------------------------------------------
-- Replica el control de "despacho a vehiculo externo" para la operacion Franke,
-- agregando: carga de camiones petroleros en puntos de carga (compras), cuadre
-- diario de litros por camion (incluye trasvasije camion-a-camion), y ventas.
--
-- Decisiones (confirmadas):
--   - "Franke" = operacion de Pillado. Se segmenta con un tag operacion='Franke'
--     en las entidades de combustible (sin depender de faenas/contratos).
--   - Camiones petroleros = ESTANQUES MOVILES (reusa el motor probado: kardex,
--     CPP, traspaso entre estanques = trasvasije camion-a-camion, despacho).
--   - Catalogo de puntos de carga (EDS + surtidores) para control de compras.
--   - Cuadre diario por camion con alerta de descuadre (vs varillaje fisico).
--
-- REUSA: rpc_registrar_ingreso_combustible_valorizado (mig 66),
--        rpc_registrar_traspaso_combustible (mig 76),
--        rpc_registrar_salida_combustible_valorizada (mig 77/78),
--        combustible_kardex_valorizado, combustible_estanques, combustible_varillaje.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Estanques: soporte de moviles (camiones) + tag de operacion ─────────
ALTER TABLE combustible_estanques
    ADD COLUMN IF NOT EXISTS tipo      VARCHAR(10) NOT NULL DEFAULT 'fijo',
    ADD COLUMN IF NOT EXISTS patente   VARCHAR(20),
    ADD COLUMN IF NOT EXISTS activo_id UUID REFERENCES activos(id),
    ADD COLUMN IF NOT EXISTS operacion VARCHAR(60);

DO $$ BEGIN
    BEGIN
        ALTER TABLE combustible_estanques DROP CONSTRAINT IF EXISTS chk_est_tipo;
        ALTER TABLE combustible_estanques ADD CONSTRAINT chk_est_tipo CHECK (tipo IN ('fijo','movil'));
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ── 2. Seed camiones petroleros como estanques moviles (operacion Franke) ──
INSERT INTO combustible_estanques (codigo, nombre, capacidad_lt, tipo, patente, activo_id, operacion, stock_teorico_lt, activo)
SELECT v.codigo, v.nombre, v.cap, 'movil', v.patente,
       (SELECT id FROM activos a WHERE a.patente = v.patente LIMIT 1),
       'Franke', 0, true
FROM (VALUES
    ('CAM-HHWB42', 'Camion petrolero HHWB-42', 20000, 'HHWB-42'),
    ('CAM-HHWB44', 'Camion petrolero HHWB-44', 20000, 'HHWB-44'),
    ('CAM-JGBY10', 'Camion petrolero JGBY-10', 15000, 'JGBY-10'),
    ('CAM-LCSX78', 'Camion / estanque apoyo LCSX-78', 10000, 'LCSX-78'),
    ('CAM-KVWD27', 'Camion C. Tolva KVWD-27', 10000, 'KVWD-27')
) AS v(codigo, nombre, cap, patente)
WHERE NOT EXISTS (SELECT 1 FROM combustible_estanques e WHERE e.codigo = v.codigo);

-- ── 3. Catalogo de puntos de carga (EDS + surtidores) ──────────────────────
CREATE TABLE IF NOT EXISTS combustible_puntos_carga (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(30) UNIQUE NOT NULL,
    nombre      VARCHAR(120) NOT NULL,
    tipo        VARCHAR(20) NOT NULL DEFAULT 'surtidor',
    operacion   VARCHAR(60),
    ubicacion   VARCHAR(160),
    activo      BOOLEAN NOT NULL DEFAULT true,
    observacion TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_pc_tipo CHECK (tipo IN ('eds','surtidor'))
);

INSERT INTO combustible_puntos_carga (codigo, nombre, tipo, operacion, ubicacion, observacion)
SELECT v.codigo, v.nombre, v.tipo, 'Franke', v.ubic, v.obs
FROM (VALUES
    ('EDS-MINA',   'EDS Mina',     'eds',      'Mina',   'Estacion principal (externa) en la mina'),
    ('EDS-PILLADO','EDS Pillado',  'eds',      'Pillado','Estacion / estanque Pillado'),
    ('EDS-PLANTA', 'EDS Planta',   'eds',      'Planta', 'Carga en Planta'),
    ('SURT-3',     'Surtidor n°3', 'surtidor', 'Planta', 'Surtidor principal de carga'),
    ('SURT-1',     'Surtidor n°1', 'surtidor', 'Planta', 'Surtidor secundario')
) AS v(codigo, nombre, tipo, ubic, obs)
WHERE NOT EXISTS (SELECT 1 FROM combustible_puntos_carga p WHERE p.codigo = v.codigo);

-- ── 4. Cargas de camion (compra en punto de carga -> ingreso al camion) ────
CREATE TABLE IF NOT EXISTS combustible_cargas_camion (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio              VARCHAR(30) UNIQUE,
    estanque_movil_id  UUID NOT NULL REFERENCES combustible_estanques(id),
    punto_carga_id     UUID REFERENCES combustible_puntos_carga(id),
    litros             NUMERIC(12,1) NOT NULL,
    costo_unitario_clp NUMERIC(12,2),
    costo_total_clp    NUMERIC(14,2),
    fecha              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    operador_nombre    VARCHAR(160),
    operador_rut       VARCHAR(20),
    firma_operador_url TEXT,
    foto_patente_url   TEXT,
    foto_medidor_inicial_url TEXT,
    foto_medidor_final_url   TEXT,
    lectura_medidor_inicial  NUMERIC(14,1),
    lectura_medidor_final    NUMERIC(14,1),
    documento_numero   VARCHAR(60),
    kardex_id          UUID,
    observacion        TEXT,
    created_by         UUID REFERENCES auth.users(id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cargas_estanque ON combustible_cargas_camion(estanque_movil_id);
CREATE INDEX IF NOT EXISTS idx_cargas_punto ON combustible_cargas_camion(punto_carga_id);
CREATE INDEX IF NOT EXISTS idx_cargas_fecha ON combustible_cargas_camion(fecha);

-- ── 5. RPC carga de camion (reusa el ingreso valorizado del motor probado) ─
CREATE OR REPLACE FUNCTION rpc_registrar_carga_camion(
    p_estanque_movil_id  UUID,
    p_punto_carga_id     UUID,
    p_litros             NUMERIC,
    p_costo_unitario_clp NUMERIC DEFAULT NULL,
    p_operador_nombre    VARCHAR DEFAULT NULL,
    p_operador_rut       VARCHAR DEFAULT NULL,
    p_firma_operador_url TEXT DEFAULT NULL,
    p_foto_patente_url   TEXT DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    p_lectura_medidor_inicial  NUMERIC DEFAULT NULL,
    p_lectura_medidor_final    NUMERIC DEFAULT NULL,
    p_documento_numero   VARCHAR DEFAULT NULL,
    p_observacion        TEXT DEFAULT NULL,
    p_fecha              TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_res    JSONB;
    v_kardex UUID;
    v_id     UUID;
    v_folio  VARCHAR;
    v_punto  VARCHAR;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF p_litros IS NULL OR p_litros <= 0 THEN RAISE EXCEPTION 'Litros invalidos.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM combustible_estanques WHERE id = p_estanque_movil_id AND tipo='movil') THEN
        RAISE EXCEPTION 'El estanque destino no es un camion (estanque movil).';
    END IF;

    SELECT nombre INTO v_punto FROM combustible_puntos_carga WHERE id = p_punto_carga_id;

    -- Ingreso valorizado al camion (motor probado: kardex + CPP + stock).
    v_res := rpc_registrar_ingreso_combustible_valorizado(
        p_estanque_id        => p_estanque_movil_id,
        p_litros             => p_litros,
        p_costo_unitario_clp => COALESCE(p_costo_unitario_clp, 0),
        p_doc_tipo           => 'carga_camion',
        p_doc_numero         => p_documento_numero,
        p_fecha_movimiento   => COALESCE(p_fecha, NOW()),
        p_observacion        => 'Carga en ' || COALESCE(v_punto,'punto de carga') || COALESCE('. '||p_observacion,''),
        p_foto_patente_url         => p_foto_patente_url,
        p_foto_medidor_inicial_url => p_foto_medidor_inicial_url,
        p_foto_medidor_final_url   => p_foto_medidor_final_url,
        p_lectura_medidor_inicial_lt => p_lectura_medidor_inicial,
        p_lectura_medidor_final_lt   => p_lectura_medidor_final
    );
    v_kardex := NULLIF(v_res->>'kardex_id','')::UUID;

    v_folio := 'CARGA-' || to_char(NOW(),'YYYYMM') || '-' ||
        lpad(((SELECT count(*) FROM combustible_cargas_camion
               WHERE folio LIKE 'CARGA-'||to_char(NOW(),'YYYYMM')||'-%') + 1)::TEXT, 4, '0');

    INSERT INTO combustible_cargas_camion (
        folio, estanque_movil_id, punto_carga_id, litros, costo_unitario_clp, costo_total_clp,
        fecha, operador_nombre, operador_rut, firma_operador_url, foto_patente_url,
        foto_medidor_inicial_url, foto_medidor_final_url, lectura_medidor_inicial,
        lectura_medidor_final, documento_numero, kardex_id, observacion, created_by
    ) VALUES (
        v_folio, p_estanque_movil_id, p_punto_carga_id, p_litros, p_costo_unitario_clp,
        ROUND(p_litros * COALESCE(p_costo_unitario_clp,0), 2),
        COALESCE(p_fecha, NOW()), p_operador_nombre, p_operador_rut, p_firma_operador_url,
        p_foto_patente_url, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_lectura_medidor_inicial, p_lectura_medidor_final, p_documento_numero, v_kardex,
        p_observacion, v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('carga_id', v_id, 'folio', v_folio, 'ingreso', v_res);
END $$;
GRANT EXECUTE ON FUNCTION rpc_registrar_carga_camion TO authenticated;

-- ── 6. VISTA — cuadre diario por camion (con descuadre vs varillaje) ───────
CREATE OR REPLACE VIEW v_combustible_cuadre_diario_franke AS
WITH moviles AS (
    SELECT id, codigo, nombre, patente FROM combustible_estanques
    WHERE tipo = 'movil' AND COALESCE(operacion,'') = 'Franke'
),
mov AS (
    SELECT k.estanque_id,
           date_trunc('day', k.fecha_movimiento)::date AS dia,
           SUM(k.litros_entrada) FILTER (WHERE k.tipo_movimiento='ingreso_compra')   AS cargado,
           SUM(k.litros_entrada) FILTER (WHERE k.tipo_movimiento='traspaso_entrada') AS trasvasije_in,
           SUM(k.litros_salida)  FILTER (WHERE k.tipo_movimiento='traspaso_salida')  AS trasvasije_out,
           SUM(k.litros_salida)  FILTER (WHERE k.tipo_movimiento IN ('salida_equipo','salida_despacho','salida_externa')) AS despachado,
           SUM(k.litros_salida)  FILTER (WHERE k.tipo_movimiento='salida_venta')     AS vendido,
           SUM(COALESCE(k.litros_entrada,0)-COALESCE(k.litros_salida,0)) FILTER (WHERE k.tipo_movimiento='ajuste') AS ajuste_neto
    FROM combustible_kardex_valorizado k
    JOIN moviles m ON m.id = k.estanque_id
    GROUP BY k.estanque_id, date_trunc('day', k.fecha_movimiento)::date
)
SELECT m.estanque_id, mv.codigo, mv.nombre AS camion, mv.patente, m.dia,
       COALESCE(m.cargado,0)       AS cargado,
       COALESCE(m.trasvasije_in,0) AS trasvasije_recibido,
       COALESCE(m.trasvasije_out,0) AS trasvasije_entregado,
       COALESCE(m.despachado,0)    AS despachado,
       COALESCE(m.vendido,0)       AS vendido,
       COALESCE(m.ajuste_neto,0)   AS ajuste,
       (COALESCE(m.cargado,0)+COALESCE(m.trasvasije_in,0)-COALESCE(m.trasvasije_out,0)
        -COALESCE(m.despachado,0)-COALESCE(m.vendido,0)+COALESCE(m.ajuste_neto,0)) AS movimiento_neto,
       va.medicion_fisica_lt,
       va.diferencia_lt AS descuadre_lt
FROM mov m
JOIN moviles mv ON mv.id = m.estanque_id
LEFT JOIN combustible_varillaje va ON va.estanque_id = m.estanque_id AND va.fecha = m.dia;

-- ── 7. VISTA — compras por punto de carga ──────────────────────────────────
CREATE OR REPLACE VIEW v_combustible_compras_punto_franke AS
SELECT p.id AS punto_id, p.codigo, p.nombre, p.tipo, p.operacion,
       COUNT(c.id) AS n_cargas,
       COALESCE(SUM(c.litros),0) AS litros_total,
       COALESCE(SUM(c.costo_total_clp),0) AS costo_total,
       MAX(c.fecha) AS ultima_carga
FROM combustible_puntos_carga p
LEFT JOIN combustible_cargas_camion c ON c.punto_carga_id = p.id
GROUP BY p.id, p.codigo, p.nombre, p.tipo, p.operacion;

-- ── 8. RLS ─────────────────────────────────────────────────────────────────
ALTER TABLE combustible_puntos_carga   ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_cargas_camion  ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['combustible_puntos_carga','combustible_cargas_camion'] LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_sel', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (true)', t||'_sel', t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_wr', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)', t||'_wr', t);
    END LOOP;
END $$;

-- ── 9. VALIDACION ──────────────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM combustible_estanques WHERE tipo='movil' AND operacion='Franke') AS camiones,
    (SELECT count(*) FROM combustible_puntos_carga WHERE operacion='Franke') AS puntos_carga,
    (SELECT count(*) FROM pg_proc WHERE proname='rpc_registrar_carga_camion') AS rpc,
    (SELECT count(*) FROM pg_views WHERE viewname IN ('v_combustible_cuadre_diario_franke','v_combustible_compras_punto_franke')) AS vistas;
