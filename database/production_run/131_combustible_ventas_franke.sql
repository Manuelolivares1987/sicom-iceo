-- ============================================================================
-- SICOM-ICEO | Migracion 131 — Ventas de combustible Franke (offline-safe)
-- ----------------------------------------------------------------------------
-- Venta de combustible en terreno desde un camion petrolero a un cliente.
-- Reusa el motor de salida valorizada (kardex/CPP/evidencia) con destino
-- 'venta_externa', y el precio vigente (fn_precio_venta_vigente / mig 73).
--
-- IDEMPOTENCIA OFFLINE: el RPC de salida no dedup por client_uuid; aqui se
-- agrega una tabla con client_uuid UNIQUE para que el reintento de sync de la
-- app del vendedor (offline) no genere ventas duplicadas.
--
-- REUSA: rpc_registrar_salida_combustible_valorizada (mig 77/78),
--        fn_precio_venta_vigente + precios_venta_combustible (mig 73).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. TABLA de ventas Franke (con dedup por client_uuid) ──────────────────
CREATE TABLE IF NOT EXISTS combustible_ventas_franke (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid        UUID UNIQUE NOT NULL,           -- idempotencia offline
    folio              VARCHAR(30),
    estanque_movil_id  UUID NOT NULL REFERENCES combustible_estanques(id),
    cliente_nombre     VARCHAR(160) NOT NULL,
    equipo_codigo      VARCHAR(60),                    -- equipo del cliente abastecido
    equipo_tipo        VARCHAR(60),
    litros             NUMERIC(12,1) NOT NULL,
    precio_clp_lt      NUMERIC(14,4),
    total_clp          NUMERIC(16,2),
    fecha              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    operador_nombre    VARCHAR(160),
    operador_rut       VARCHAR(20),
    nombre_receptor    VARCHAR(160),
    rut_receptor       VARCHAR(20),
    firma_receptor_url TEXT,
    foto_patente_url   TEXT,
    foto_medidor_inicial_url TEXT,
    foto_medidor_final_url   TEXT,
    lat                NUMERIC(10,6),
    lng                NUMERIC(10,6),
    documento_numero   VARCHAR(60),
    observacion        TEXT,
    kardex_id          UUID,
    origen             VARCHAR(12) NOT NULL DEFAULT 'online',  -- online | offline
    created_by         UUID REFERENCES auth.users(id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_vf_estanque ON combustible_ventas_franke(estanque_movil_id);
CREATE INDEX IF NOT EXISTS idx_vf_cliente ON combustible_ventas_franke(cliente_nombre);
CREATE INDEX IF NOT EXISTS idx_vf_fecha ON combustible_ventas_franke(fecha);

-- ── 2. RPC venta Franke (idempotente, reusa salida valorizada) ─────────────
CREATE OR REPLACE FUNCTION rpc_registrar_venta_franke(
    p_client_uuid        UUID,
    p_estanque_movil_id  UUID,
    p_cliente_nombre     VARCHAR,
    p_litros             NUMERIC,
    p_equipo_codigo      VARCHAR DEFAULT NULL,
    p_equipo_tipo        VARCHAR DEFAULT NULL,
    p_precio_clp_lt      NUMERIC DEFAULT NULL,
    p_operador_nombre    VARCHAR DEFAULT NULL,
    p_operador_rut       VARCHAR DEFAULT NULL,
    p_nombre_receptor    VARCHAR DEFAULT NULL,
    p_rut_receptor       VARCHAR DEFAULT NULL,
    p_firma_receptor_url TEXT DEFAULT NULL,
    p_foto_patente_url   TEXT DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    p_lat                NUMERIC DEFAULT NULL,
    p_lng                NUMERIC DEFAULT NULL,
    p_documento_numero   VARCHAR DEFAULT NULL,
    p_observacion        TEXT DEFAULT NULL,
    p_fecha              TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user    UUID := auth.uid();
    v_id      UUID;
    v_existe  RECORD;
    v_precio  NUMERIC;
    v_total   NUMERIC;
    v_res     JSONB;
    v_kardex  UUID;
    v_folio   VARCHAR;
    v_fecha   TIMESTAMPTZ := COALESCE(p_fecha, NOW());
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF p_client_uuid IS NULL THEN RAISE EXCEPTION 'client_uuid requerido (idempotencia).'; END IF;
    IF p_litros IS NULL OR p_litros <= 0 THEN RAISE EXCEPTION 'Litros invalidos.'; END IF;

    -- Dedup: si ya existe esa venta (reintento de sync), devolverla sin duplicar.
    SELECT id, kardex_id, total_clp, precio_clp_lt INTO v_existe
    FROM combustible_ventas_franke WHERE client_uuid = p_client_uuid;
    IF FOUND THEN
        RETURN jsonb_build_object('venta_id', v_existe.id, 'duplicado', true,
            'kardex_id', v_existe.kardex_id, 'total_clp', v_existe.total_clp,
            'precio_clp_lt', v_existe.precio_clp_lt);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM combustible_estanques WHERE id = p_estanque_movil_id AND tipo='movil') THEN
        RAISE EXCEPTION 'El origen no es un camion (estanque movil).';
    END IF;

    -- Precio: parametro o precio vigente del cliente.
    v_precio := COALESCE(p_precio_clp_lt, fn_precio_venta_vigente(p_cliente_nombre, NULL, v_fecha));
    v_total  := ROUND(p_litros * COALESCE(v_precio,0), 2);

    v_folio := 'VF-' || to_char(v_fecha,'YYYYMM') || '-' ||
        lpad(((SELECT count(*) FROM combustible_ventas_franke
               WHERE folio LIKE 'VF-'||to_char(v_fecha,'YYYYMM')||'-%') + 1)::TEXT, 4, '0');

    -- Reserva la fila (idempotente). Si otro proceso la inserto en paralelo, gana ON CONFLICT.
    INSERT INTO combustible_ventas_franke (
        client_uuid, folio, estanque_movil_id, cliente_nombre, equipo_codigo, equipo_tipo,
        litros, precio_clp_lt, total_clp, fecha, operador_nombre, operador_rut,
        nombre_receptor, rut_receptor, firma_receptor_url, foto_patente_url,
        foto_medidor_inicial_url, foto_medidor_final_url, lat, lng, documento_numero,
        observacion, origen, created_by
    ) VALUES (
        p_client_uuid, v_folio, p_estanque_movil_id, p_cliente_nombre, p_equipo_codigo, p_equipo_tipo,
        p_litros, v_precio, v_total, v_fecha, p_operador_nombre, p_operador_rut,
        p_nombre_receptor, p_rut_receptor, p_firma_receptor_url, p_foto_patente_url,
        p_foto_medidor_inicial_url, p_foto_medidor_final_url, p_lat, p_lng, p_documento_numero,
        p_observacion, 'online', v_user
    )
    ON CONFLICT (client_uuid) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        SELECT id, kardex_id, total_clp, precio_clp_lt INTO v_existe
        FROM combustible_ventas_franke WHERE client_uuid = p_client_uuid;
        RETURN jsonb_build_object('venta_id', v_existe.id, 'duplicado', true,
            'kardex_id', v_existe.kardex_id, 'total_clp', v_existe.total_clp);
    END IF;

    -- Salida valorizada (motor probado): venta externa desde el camion.
    v_res := rpc_registrar_salida_combustible_valorizada(
        p_estanque_id        => p_estanque_movil_id,
        p_litros             => p_litros,
        p_destino_tipo       => 'venta_externa',
        p_motivo             => 'Venta Franke a ' || p_cliente_nombre ||
                                COALESCE(' ('||p_equipo_codigo||')',''),
        p_cliente_nombre     => p_cliente_nombre,
        p_fecha_movimiento   => v_fecha,
        p_observacion        => p_observacion,
        p_foto_patente_url   => p_foto_patente_url,
        p_foto_medidor_inicial_url => p_foto_medidor_inicial_url,
        p_foto_medidor_final_url   => p_foto_medidor_final_url,
        p_firma_receptor_url => p_firma_receptor_url,
        p_nombre_receptor    => p_nombre_receptor,
        p_rut_receptor       => p_rut_receptor
    );
    v_kardex := COALESCE(NULLIF(v_res->>'kardex_id','')::UUID, NULLIF(v_res->>'movimiento_id','')::UUID);

    UPDATE combustible_ventas_franke SET kardex_id = v_kardex WHERE id = v_id;

    RETURN jsonb_build_object('venta_id', v_id, 'folio', v_folio, 'kardex_id', v_kardex,
        'precio_clp_lt', v_precio, 'total_clp', v_total, 'salida', v_res);
END $$;
GRANT EXECUTE ON FUNCTION rpc_registrar_venta_franke TO authenticated;

-- ── 3. VISTAS — ventas + resumen por cliente ───────────────────────────────
CREATE OR REPLACE VIEW v_ventas_franke AS
SELECT vf.id, vf.folio, vf.fecha, e.patente AS camion, e.codigo AS camion_codigo,
       vf.cliente_nombre, vf.equipo_codigo, vf.equipo_tipo, vf.litros,
       vf.precio_clp_lt, vf.total_clp, vf.operador_nombre, vf.origen, vf.kardex_id
FROM combustible_ventas_franke vf
JOIN combustible_estanques e ON e.id = vf.estanque_movil_id;

CREATE OR REPLACE VIEW v_ventas_franke_cliente AS
SELECT cliente_nombre,
       COUNT(*) AS n_ventas,
       COALESCE(SUM(litros),0) AS litros_total,
       COALESCE(SUM(total_clp),0) AS monto_total,
       MAX(fecha) AS ultima_venta
FROM combustible_ventas_franke
GROUP BY cliente_nombre;

-- ── 4. RLS ─────────────────────────────────────────────────────────────────
ALTER TABLE combustible_ventas_franke ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_vf_sel ON combustible_ventas_franke;
CREATE POLICY pol_vf_sel ON combustible_ventas_franke FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_vf_wr ON combustible_ventas_franke;
CREATE POLICY pol_vf_wr ON combustible_ventas_franke FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ── 5. VALIDACION ──────────────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM information_schema.tables WHERE table_name='combustible_ventas_franke') AS tabla,
    (SELECT count(*) FROM pg_proc WHERE proname='rpc_registrar_venta_franke') AS rpc,
    (SELECT count(*) FROM pg_views WHERE viewname IN ('v_ventas_franke','v_ventas_franke_cliente')) AS vistas,
    (SELECT count(*) FROM information_schema.tables WHERE table_name='precios_venta_combustible') AS precios_existe;
