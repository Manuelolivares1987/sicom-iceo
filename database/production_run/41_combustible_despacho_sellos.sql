-- ============================================================================
-- 41_combustible_despacho_sellos.sql
-- ----------------------------------------------------------------------------
-- Despacho de combustible con trazabilidad antifraude (sellos inicial/final
-- + receptor + GPS opcional). ADITIVA. IDEMPOTENTE.
--
-- Crea:
--   1. Tabla combustible_despachos_sellos
--   2. RPC rpc_registrar_despacho_combustible_con_sellos
--   3. Vista v_combustible_despachos_con_sellos
--
-- NO toca: stock_bodega, inventario_capas, FIFO productos, legacy
-- combustible. Internamente invoca rpc_registrar_salida_combustible_
-- valorizada (MIG40) para garantizar consistencia con CPP y kardex.
-- ============================================================================


-- ── Prechecks ───────────────────────────────────────────────────────────────
DO $$
DECLARE v_rol TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada') THEN
        RAISE EXCEPTION 'STOP - MIG40 no aplicada (rpc_registrar_salida_combustible_valorizada falta)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - combustible_kardex_valorizado no existe';
    END IF;
    -- Sanidad reconciliacion productos intacta
    IF (SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo
         WHERE estado_reconciliacion <> 'cuadrado') > 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion productos no esta cuadrada';
    END IF;
    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN
        RAISE NOTICE 'Aplicando MIG41 como rol de sistema (current_user=%). OK.', current_user;
    ELSIF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar MIG41 desde sesion autenticada requiere administrador';
    END IF;
    RAISE NOTICE '== MIG41 prechecks OK ==';
END $$;


-- ============================================================================
-- 1. TABLA combustible_despachos_sellos
-- ============================================================================
CREATE TABLE IF NOT EXISTS combustible_despachos_sellos (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    movimiento_combustible_id   UUID REFERENCES combustible_kardex_valorizado(id) ON DELETE SET NULL,
    estanque_id                 UUID NOT NULL REFERENCES combustible_estanques(id),
    destino_tipo                VARCHAR(30) NOT NULL,
    destino_id                  UUID,  -- campo generico opcional para uso futuro
    equipo_id                   UUID REFERENCES activos(id),
    ot_id                       UUID REFERENCES ordenes_trabajo(id),
    ceco_id                     UUID REFERENCES centros_costo(id),
    faena_id                    UUID REFERENCES faenas(id),
    sello_inicial               VARCHAR(60) NOT NULL,
    sello_final                 VARCHAR(60) NOT NULL,
    foto_sello_inicial_url      TEXT,
    foto_sello_final_url        TEXT,
    foto_odometro_url           TEXT,
    foto_equipo_url             TEXT,
    litros_despachados          NUMERIC(12,2) NOT NULL CHECK (litros_despachados > 0),
    operador_id                 UUID REFERENCES usuarios_perfil(id),
    receptor_nombre             VARCHAR(200),
    receptor_rut                VARCHAR(20),
    firma_receptor_url          TEXT,
    lat                         NUMERIC(10,7),
    lng                         NUMERIC(10,7),
    accuracy                    NUMERIC(8,2),
    geolocation_status          VARCHAR(20),
    observacion                 TEXT,
    created_by                  UUID REFERENCES auth.users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CHECK destino_tipo idempotente
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
         WHERE constraint_schema='public' AND table_name='combustible_despachos_sellos'
           AND constraint_name='chk_cds_destino_tipo'
    ) THEN
        ALTER TABLE combustible_despachos_sellos
            ADD CONSTRAINT chk_cds_destino_tipo
            CHECK (destino_tipo IN ('equipo','ot','ceco','faena','consumo_interno','venta_externa'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cds_estanque ON combustible_despachos_sellos (estanque_id);
CREATE INDEX IF NOT EXISTS idx_cds_movimiento ON combustible_despachos_sellos (movimiento_combustible_id);
CREATE INDEX IF NOT EXISTS idx_cds_destino_tipo ON combustible_despachos_sellos (destino_tipo);
CREATE INDEX IF NOT EXISTS idx_cds_created_at ON combustible_despachos_sellos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cds_equipo ON combustible_despachos_sellos (equipo_id) WHERE equipo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cds_ot ON combustible_despachos_sellos (ot_id) WHERE ot_id IS NOT NULL;

ALTER TABLE combustible_despachos_sellos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_cds_select ON combustible_despachos_sellos;
CREATE POLICY pol_cds_select ON combustible_despachos_sellos FOR SELECT TO authenticated USING (true);


-- ============================================================================
-- 2. RPC: rpc_registrar_despacho_combustible_con_sellos
-- Envuelve rpc_registrar_salida_combustible_valorizada (MIG40) y agrega
-- el registro de sellos. La salida valorizada hace las validaciones de
-- stock, CPP, motivo, destino y kardex.
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_despacho_combustible_con_sellos(
    p_estanque_id            UUID,
    p_litros                 NUMERIC,
    p_destino_tipo           VARCHAR,
    p_sello_inicial          VARCHAR,
    p_sello_final            VARCHAR,
    p_motivo                 TEXT,
    p_equipo_id              UUID    DEFAULT NULL,
    p_ot_id                  UUID    DEFAULT NULL,
    p_ceco_id                UUID    DEFAULT NULL,
    p_faena_id               UUID    DEFAULT NULL,
    p_cliente_nombre         VARCHAR DEFAULT NULL,
    p_receptor_nombre        VARCHAR DEFAULT NULL,
    p_receptor_rut           VARCHAR DEFAULT NULL,
    p_foto_sello_inicial_url TEXT    DEFAULT NULL,
    p_foto_sello_final_url   TEXT    DEFAULT NULL,
    p_foto_odometro_url      TEXT    DEFAULT NULL,
    p_foto_equipo_url        TEXT    DEFAULT NULL,
    p_firma_receptor_url     TEXT    DEFAULT NULL,
    p_lat                    NUMERIC DEFAULT NULL,
    p_lng                    NUMERIC DEFAULT NULL,
    p_accuracy               NUMERIC DEFAULT NULL,
    p_geolocation_status     VARCHAR DEFAULT NULL,
    p_fecha_movimiento       TIMESTAMPTZ DEFAULT NULL,
    p_observacion            TEXT    DEFAULT NULL,
    p_evidencia_url          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_resp        JSONB;
    v_kardex_id   UUID;
    v_folio       TEXT;
    v_despacho_id UUID;
    v_cpp         NUMERIC;
    v_costo_total NUMERIC;
    v_stock_final NUMERIC;
    v_destino_id  UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para despacho con sellos', v_rol;
    END IF;

    -- Validaciones sellos (la salida valorizada valida el resto)
    IF p_sello_inicial IS NULL OR LENGTH(TRIM(p_sello_inicial)) = 0 THEN
        RAISE EXCEPTION 'sello_inicial es obligatorio';
    END IF;
    IF p_sello_final IS NULL OR LENGTH(TRIM(p_sello_final)) = 0 THEN
        RAISE EXCEPTION 'sello_final es obligatorio';
    END IF;

    -- Llamar a la salida valorizada (MIG40) — valida stock, CPP, destino, motivo
    v_resp := rpc_registrar_salida_combustible_valorizada(
        p_estanque_id      => p_estanque_id,
        p_litros           => p_litros,
        p_destino_tipo     => p_destino_tipo,
        p_motivo           => p_motivo,
        p_equipo_id        => p_equipo_id,
        p_ot_id            => p_ot_id,
        p_ceco_id          => p_ceco_id,
        p_faena_id         => p_faena_id,
        p_cliente_nombre   => p_cliente_nombre,
        p_fecha_movimiento => p_fecha_movimiento,
        p_observacion      => p_observacion,
        p_evidencia_url    => p_evidencia_url
    );

    v_kardex_id   := (v_resp->>'kardex_id')::UUID;
    v_folio       := v_resp->>'folio';
    v_cpp         := (v_resp->>'cpp_vigente')::NUMERIC;
    v_costo_total := (v_resp->>'costo_total')::NUMERIC;
    v_stock_final := (v_resp->>'stock_nuevo')::NUMERIC;

    -- destino_id (espejo del FK especifico segun destino, para uso futuro)
    v_destino_id := COALESCE(p_equipo_id, p_ot_id, p_ceco_id, p_faena_id);

    -- Registrar sellos ligados al movimiento
    v_despacho_id := gen_random_uuid();
    INSERT INTO combustible_despachos_sellos (
        id, movimiento_combustible_id, estanque_id, destino_tipo, destino_id,
        equipo_id, ot_id, ceco_id, faena_id,
        sello_inicial, sello_final,
        foto_sello_inicial_url, foto_sello_final_url,
        foto_odometro_url, foto_equipo_url,
        litros_despachados, operador_id,
        receptor_nombre, receptor_rut, firma_receptor_url,
        lat, lng, accuracy, geolocation_status,
        observacion, created_by
    ) VALUES (
        v_despacho_id, v_kardex_id, p_estanque_id, p_destino_tipo, v_destino_id,
        p_equipo_id, p_ot_id, p_ceco_id, p_faena_id,
        TRIM(p_sello_inicial), TRIM(p_sello_final),
        p_foto_sello_inicial_url, p_foto_sello_final_url,
        p_foto_odometro_url, p_foto_equipo_url,
        p_litros, v_user_id,
        p_receptor_nombre, p_receptor_rut, p_firma_receptor_url,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        p_observacion, v_user_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'despacho_id', v_despacho_id,
        'movimiento_id', v_kardex_id,
        'folio_movimiento', v_folio,
        'stock_final', v_stock_final,
        'cpp_usado', v_cpp,
        'costo_total', v_costo_total,
        'destino_tipo', p_destino_tipo,
        'litros', p_litros
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_despacho_combustible_con_sellos IS
'Despacho de combustible con sellos antifraude. Envuelve rpc_registrar_salida_combustible_valorizada (MIG40) + registra sellos. MIG41.';


-- ============================================================================
-- 3. VISTA: v_combustible_despachos_con_sellos
-- ============================================================================
DROP VIEW IF EXISTS public.v_combustible_despachos_con_sellos CASCADE;
CREATE VIEW v_combustible_despachos_con_sellos AS
SELECT
    d.id                            AS despacho_id,
    d.created_at                    AS fecha,
    d.movimiento_combustible_id,
    ckv.folio_movimiento,
    ckv.fecha_movimiento,
    d.estanque_id,
    e.codigo                        AS estanque_codigo,
    e.nombre                        AS estanque_nombre,
    d.destino_tipo,
    d.litros_despachados            AS litros,
    ckv.costo_unitario_movimiento   AS cpp_usado,
    ROUND(COALESCE(ckv.costo_unitario_movimiento * d.litros_despachados, 0)::numeric, 2)
                                    AS costo_total,
    d.sello_inicial,
    d.sello_final,
    d.foto_sello_inicial_url,
    d.foto_sello_final_url,
    d.foto_odometro_url,
    d.foto_equipo_url,
    d.receptor_nombre,
    d.receptor_rut,
    d.firma_receptor_url,
    d.lat, d.lng, d.accuracy, d.geolocation_status,
    d.equipo_id,
    a.codigo                        AS equipo_codigo,
    a.nombre                        AS equipo_nombre,
    d.ot_id,
    ot.folio                        AS ot_folio,
    d.ceco_id,
    cc.codigo                       AS ceco_codigo,
    cc.nombre                       AS ceco_nombre,
    d.faena_id,
    f.nombre                        AS faena_nombre,
    d.operador_id,
    up.nombre_completo              AS operador,
    d.observacion,
    d.created_by
FROM combustible_despachos_sellos d
JOIN combustible_estanques e ON e.id = d.estanque_id
LEFT JOIN combustible_kardex_valorizado ckv ON ckv.id = d.movimiento_combustible_id
LEFT JOIN usuarios_perfil up ON up.id = d.operador_id
LEFT JOIN activos a ON a.id = d.equipo_id
LEFT JOIN ordenes_trabajo ot ON ot.id = d.ot_id
LEFT JOIN centros_costo cc ON cc.id = d.ceco_id
LEFT JOIN faenas f ON f.id = d.faena_id;

COMMENT ON VIEW v_combustible_despachos_con_sellos IS
'Despachos de combustible con sellos enlazados al kardex valorizado. MIG41.';


-- ── GRANTs ──────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION rpc_registrar_despacho_combustible_con_sellos TO authenticated;
GRANT SELECT ON v_combustible_despachos_con_sellos TO authenticated;


-- ── Validaciones post ──────────────────────────────────────────────────────
DO $$
DECLARE v_tabla INT; v_rpc INT; v_vista INT; v_desviados INT;
BEGIN
    SELECT COUNT(*) INTO v_tabla FROM information_schema.tables
     WHERE table_schema='public' AND table_name='combustible_despachos_sellos';
    IF v_tabla <> 1 THEN RAISE EXCEPTION 'STOP - tabla combustible_despachos_sellos no creada'; END IF;

    SELECT COUNT(*) INTO v_rpc FROM pg_proc
     WHERE proname='rpc_registrar_despacho_combustible_con_sellos';
    IF v_rpc <> 1 THEN RAISE EXCEPTION 'STOP - RPC no creada'; END IF;

    SELECT COUNT(*) INTO v_vista FROM pg_views
     WHERE schemaname='public' AND viewname='v_combustible_despachos_con_sellos';
    IF v_vista <> 1 THEN RAISE EXCEPTION 'STOP - vista no creada'; END IF;

    SELECT COUNT(*) INTO v_desviados FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados <> 0 THEN RAISE EXCEPTION 'STOP - reconciliacion productos se rompio'; END IF;

    RAISE NOTICE '== MIG41 aplicada OK ==';
    RAISE NOTICE '   tabla combustible_despachos_sellos creada';
    RAISE NOTICE '   RPC rpc_registrar_despacho_combustible_con_sellos creada';
    RAISE NOTICE '   vista v_combustible_despachos_con_sellos creada';
    RAISE NOTICE '   reconciliacion productos intacta';
END $$;


-- Resultset visible
SELECT 'tabla_despachos_sellos'         AS dx, COUNT(*)::text AS val FROM information_schema.tables WHERE table_name='combustible_despachos_sellos'
UNION ALL SELECT 'rpc_despacho_con_sellos', COUNT(*)::text FROM pg_proc WHERE proname='rpc_registrar_despacho_combustible_con_sellos'
UNION ALL SELECT 'vista_despachos_con_sellos', COUNT(*)::text FROM pg_views WHERE viewname='v_combustible_despachos_con_sellos'
UNION ALL SELECT 'reconciliacion_productos_cuadrado',
                  (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion='cuadrado')
UNION ALL SELECT 'reconciliacion_productos_desviado',
                  (SELECT COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion<>'cuadrado');


-- Log
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG41_END',
            'MIG41 despacho combustible con sellos aplicada',
            'ok',
            'Smoke en smoke_test_41_combustible_sellos.sql. UI: /dashboard/combustible/despacho'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK manual
--   DROP VIEW v_combustible_despachos_con_sellos;
--   DROP FUNCTION rpc_registrar_despacho_combustible_con_sellos(UUID,NUMERIC,VARCHAR,VARCHAR,VARCHAR,TEXT,UUID,UUID,UUID,UUID,VARCHAR,VARCHAR,VARCHAR,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC,VARCHAR,TIMESTAMPTZ,TEXT,TEXT);
--   DROP TABLE combustible_despachos_sellos;
-- ============================================================================
