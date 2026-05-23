-- ============================================================================
-- 76_combustible_traspaso_entre_estanques.sql
-- ----------------------------------------------------------------------------
-- Traspaso de combustible entre estanques (ej: del estanque 15K al 1K).
--
-- Mecanica:
--   - Origen: descuento de litros, valorizado al CPP del origen.
--   - Destino: ingreso de litros al costo unitario = CPP del origen.
--     -> CPP destino se recalcula con fórmula móvil (igual que un ingreso).
--   - Ambos lados quedan registrados en combustible_kardex_valorizado con
--     tipos 'traspaso_salida' y 'traspaso_entrada', enlazados por
--     combustible_traspasos.id.
--
-- Evidencia obligatoria (misma exigencia que despacho externo):
--   - foto medidor origen inicial + final
--   - foto medidor destino inicial + final
--   - foto del manguerado entre estanques
--   - firma + nombre + RUT del operador que ejecuta
--   - motivo (>= 5 caracteres)
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - combustible_kardex_valorizado no existe (correr MIG40).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_estanques') THEN
        RAISE EXCEPTION 'STOP - combustible_estanques no existe (correr MIG50).';
    END IF;
END $$;


-- ============================================================================
-- 1. TABLA combustible_traspasos
-- ============================================================================
CREATE TABLE IF NOT EXISTS combustible_traspasos (
    id                              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    folio                           VARCHAR(40)  NOT NULL UNIQUE,

    estanque_origen_id              UUID         NOT NULL REFERENCES combustible_estanques(id),
    estanque_destino_id             UUID         NOT NULL REFERENCES combustible_estanques(id),
    litros                          NUMERIC(10,2) NOT NULL CHECK (litros > 0),

    -- Snapshot del CPP usado (el del origen al momento del traspaso)
    cpp_origen_snapshot             NUMERIC(14,4) NOT NULL,
    costo_total_traspaso            NUMERIC(14,0) NOT NULL,

    -- Lecturas medidores (opcional; recomendado)
    lectura_medidor_origen_inicial  NUMERIC(12,2),
    lectura_medidor_origen_final    NUMERIC(12,2),
    lectura_medidor_destino_inicial NUMERIC(12,2),
    lectura_medidor_destino_final   NUMERIC(12,2),

    -- Fotos OBLIGATORIAS
    foto_medidor_origen_inicial_url  TEXT NOT NULL,
    foto_medidor_origen_final_url    TEXT NOT NULL,
    foto_medidor_destino_inicial_url TEXT NOT NULL,
    foto_medidor_destino_final_url   TEXT NOT NULL,
    foto_manguerado_url              TEXT NOT NULL,

    -- Operador que ejecuta (OBLIGATORIO)
    nombre_operador                 VARCHAR(200) NOT NULL,
    rut_operador                    VARCHAR(20)  NOT NULL,
    firma_operador_url              TEXT         NOT NULL,

    motivo                          TEXT         NOT NULL CHECK (length(trim(motivo)) >= 5),
    observacion                     TEXT,

    -- Enlace al kardex (se llenan tras crear las filas)
    kardex_salida_id                UUID         REFERENCES combustible_kardex_valorizado(id) ON DELETE SET NULL,
    kardex_entrada_id               UUID         REFERENCES combustible_kardex_valorizado(id) ON DELETE SET NULL,

    -- Snapshots de stock (auditoria)
    stock_origen_anterior           NUMERIC(10,2),
    stock_origen_nuevo              NUMERIC(10,2),
    stock_destino_anterior          NUMERIC(10,2),
    stock_destino_nuevo             NUMERIC(10,2),
    cpp_destino_anterior            NUMERIC(14,4),
    cpp_destino_nuevo               NUMERIC(14,4),

    -- Geolocalizacion
    lat                             NUMERIC(10,7),
    lng                             NUMERIC(10,7),
    accuracy                        NUMERIC(8,2),
    geolocation_status              VARCHAR(20),

    fecha_traspaso                  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    operador_id                     UUID         REFERENCES usuarios_perfil(id),
    created_by                      UUID         REFERENCES auth.users(id),
    created_at                      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_traspaso_estanques_distintos CHECK (estanque_origen_id <> estanque_destino_id)
);

CREATE INDEX IF NOT EXISTS idx_traspaso_origen   ON combustible_traspasos (estanque_origen_id);
CREATE INDEX IF NOT EXISTS idx_traspaso_destino  ON combustible_traspasos (estanque_destino_id);
CREATE INDEX IF NOT EXISTS idx_traspaso_fecha    ON combustible_traspasos (fecha_traspaso DESC);
CREATE INDEX IF NOT EXISTS idx_traspaso_operador ON combustible_traspasos (operador_id) WHERE operador_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_traspaso_kardex_salida  ON combustible_traspasos (kardex_salida_id);
CREATE INDEX IF NOT EXISTS idx_traspaso_kardex_entrada ON combustible_traspasos (kardex_entrada_id);

DROP TRIGGER IF EXISTS trg_traspaso_updated_at ON combustible_traspasos;
CREATE TRIGGER trg_traspaso_updated_at
    BEFORE UPDATE ON combustible_traspasos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE combustible_traspasos IS
    'Traspasos de combustible entre estanques (origen -> destino). Genera 2 entradas en kardex enlazadas. MIG76.';


-- ============================================================================
-- 2. Columna opcional en kardex para enlazar al traspaso (auditoria desde kardex)
-- ============================================================================
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS traspaso_id UUID REFERENCES combustible_traspasos(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_kardex_traspaso ON combustible_kardex_valorizado (traspaso_id) WHERE traspaso_id IS NOT NULL;


-- ============================================================================
-- 3. RPC rpc_registrar_traspaso_combustible
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_traspaso_combustible(
    p_estanque_origen_id              UUID,
    p_estanque_destino_id             UUID,
    p_litros                          NUMERIC,
    p_foto_medidor_origen_inicial_url  TEXT,
    p_foto_medidor_origen_final_url    TEXT,
    p_foto_medidor_destino_inicial_url TEXT,
    p_foto_medidor_destino_final_url   TEXT,
    p_foto_manguerado_url              TEXT,
    p_nombre_operador                 VARCHAR,
    p_rut_operador                    VARCHAR,
    p_firma_operador_url              TEXT,
    p_motivo                          TEXT,
    p_lectura_medidor_origen_inicial  NUMERIC DEFAULT NULL,
    p_lectura_medidor_origen_final    NUMERIC DEFAULT NULL,
    p_lectura_medidor_destino_inicial NUMERIC DEFAULT NULL,
    p_lectura_medidor_destino_final   NUMERIC DEFAULT NULL,
    p_observacion                     TEXT    DEFAULT NULL,
    p_lat                             NUMERIC DEFAULT NULL,
    p_lng                             NUMERIC DEFAULT NULL,
    p_accuracy                        NUMERIC DEFAULT NULL,
    p_geolocation_status              VARCHAR DEFAULT NULL,
    p_fecha_traspaso                  TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_origen       combustible_estanques%ROWTYPE;
    v_destino      combustible_estanques%ROWTYPE;
    v_folio        VARCHAR;
    v_fecha        TIMESTAMPTZ;
    v_traspaso_id  UUID;
    v_kardex_sal   UUID;
    v_kardex_ent   UUID;
    v_cpp_origen   NUMERIC;
    v_cpp_dest_old NUMERIC;
    v_cpp_dest_new NUMERIC;
    v_stk_ori_old  NUMERIC;
    v_stk_ori_new  NUMERIC;
    v_stk_dst_old  NUMERIC;
    v_stk_dst_new  NUMERIC;
    v_val_ori_post NUMERIC;
    v_val_dst_post NUMERIC;
    v_costo_total  NUMERIC;
    v_operador_pf  UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para traspaso entre estanques', v_rol;
    END IF;

    -- Validar parametros base
    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_estanque_origen_id = p_estanque_destino_id THEN
        RAISE EXCEPTION 'Estanque origen y destino no pueden ser el mismo';
    END IF;

    -- Evidencia OBLIGATORIA
    IF p_foto_medidor_origen_inicial_url IS NULL OR length(trim(p_foto_medidor_origen_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor ORIGEN INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_origen_final_url IS NULL OR length(trim(p_foto_medidor_origen_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor ORIGEN FINAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_destino_inicial_url IS NULL OR length(trim(p_foto_medidor_destino_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor DESTINO INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_destino_final_url IS NULL OR length(trim(p_foto_medidor_destino_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor DESTINO FINAL es OBLIGATORIA.';
    END IF;
    IF p_foto_manguerado_url IS NULL OR length(trim(p_foto_manguerado_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del manguerado entre estanques es OBLIGATORIA.';
    END IF;
    IF p_nombre_operador IS NULL OR length(trim(p_nombre_operador)) < 3 THEN
        RAISE EXCEPTION 'Nombre del operador es OBLIGATORIO (min 3 caracteres).';
    END IF;
    IF p_rut_operador IS NULL OR length(trim(p_rut_operador)) < 7 THEN
        RAISE EXCEPTION 'RUT del operador es OBLIGATORIO.';
    END IF;
    IF p_firma_operador_url IS NULL OR length(trim(p_firma_operador_url)) = 0 THEN
        RAISE EXCEPTION 'Firma del operador es OBLIGATORIA.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Motivo es OBLIGATORIO (min 5 caracteres).';
    END IF;

    v_fecha := COALESCE(p_fecha_traspaso, NOW());

    -- Lock ambos estanques (orden estable por id para evitar deadlocks)
    IF p_estanque_origen_id < p_estanque_destino_id THEN
        SELECT * INTO v_origen  FROM combustible_estanques WHERE id = p_estanque_origen_id  FOR UPDATE;
        SELECT * INTO v_destino FROM combustible_estanques WHERE id = p_estanque_destino_id FOR UPDATE;
    ELSE
        SELECT * INTO v_destino FROM combustible_estanques WHERE id = p_estanque_destino_id FOR UPDATE;
        SELECT * INTO v_origen  FROM combustible_estanques WHERE id = p_estanque_origen_id  FOR UPDATE;
    END IF;

    IF v_origen.id IS NULL THEN RAISE EXCEPTION 'Estanque origen no existe'; END IF;
    IF v_destino.id IS NULL THEN RAISE EXCEPTION 'Estanque destino no existe'; END IF;
    IF NOT v_origen.activo THEN RAISE EXCEPTION 'Estanque origen % no esta activo', v_origen.codigo; END IF;
    IF NOT v_destino.activo THEN RAISE EXCEPTION 'Estanque destino % no esta activo', v_destino.codigo; END IF;

    IF v_origen.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente en origen %: actual % lt, solicitado % lt',
            v_origen.codigo, v_origen.stock_teorico_lt, p_litros;
    END IF;

    -- Validar capacidad destino
    IF (v_destino.stock_teorico_lt + p_litros) > v_destino.capacidad_lt THEN
        RAISE EXCEPTION 'Capacidad insuficiente en destino %: stock % + traspaso % > capacidad % lt',
            v_destino.codigo, v_destino.stock_teorico_lt, p_litros, v_destino.capacidad_lt;
    END IF;

    -- Snapshots
    v_cpp_origen   := COALESCE(v_origen.costo_promedio_lt, 0);
    v_cpp_dest_old := COALESCE(v_destino.costo_promedio_lt, 0);
    v_stk_ori_old  := v_origen.stock_teorico_lt;
    v_stk_dst_old  := v_destino.stock_teorico_lt;

    v_stk_ori_new  := v_stk_ori_old - p_litros;
    v_stk_dst_new  := v_stk_dst_old + p_litros;
    v_costo_total  := ROUND((p_litros * v_cpp_origen)::numeric, 0);

    -- CPP movil del destino: valor previo + valor entrante / stock total
    IF v_stk_dst_new > 0 THEN
        v_cpp_dest_new := ROUND(
            (((v_stk_dst_old * v_cpp_dest_old) + (p_litros * v_cpp_origen))::numeric / v_stk_dst_new)::numeric
        , 4);
    ELSE
        v_cpp_dest_new := v_cpp_origen;
    END IF;

    v_val_ori_post := ROUND((v_stk_ori_new * v_cpp_origen)::numeric, 2);
    v_val_dst_post := ROUND((v_stk_dst_new * v_cpp_dest_new)::numeric, 2);

    -- Folio TRA-YYYYMMDD-HHMMSS
    v_folio := 'TRA-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');

    -- Operador perfil
    SELECT id INTO v_operador_pf FROM usuarios_perfil WHERE user_id = v_user_id LIMIT 1;

    -- Crear traspaso (sin kardex aun)
    v_traspaso_id := gen_random_uuid();
    INSERT INTO combustible_traspasos (
        id, folio, estanque_origen_id, estanque_destino_id, litros,
        cpp_origen_snapshot, costo_total_traspaso,
        lectura_medidor_origen_inicial, lectura_medidor_origen_final,
        lectura_medidor_destino_inicial, lectura_medidor_destino_final,
        foto_medidor_origen_inicial_url, foto_medidor_origen_final_url,
        foto_medidor_destino_inicial_url, foto_medidor_destino_final_url,
        foto_manguerado_url,
        nombre_operador, rut_operador, firma_operador_url,
        motivo, observacion,
        stock_origen_anterior, stock_origen_nuevo,
        stock_destino_anterior, stock_destino_nuevo,
        cpp_destino_anterior, cpp_destino_nuevo,
        lat, lng, accuracy, geolocation_status,
        fecha_traspaso, operador_id, created_by
    ) VALUES (
        v_traspaso_id, v_folio, p_estanque_origen_id, p_estanque_destino_id, p_litros,
        v_cpp_origen, v_costo_total,
        p_lectura_medidor_origen_inicial,  p_lectura_medidor_origen_final,
        p_lectura_medidor_destino_inicial, p_lectura_medidor_destino_final,
        p_foto_medidor_origen_inicial_url,  p_foto_medidor_origen_final_url,
        p_foto_medidor_destino_inicial_url, p_foto_medidor_destino_final_url,
        p_foto_manguerado_url,
        TRIM(p_nombre_operador), TRIM(p_rut_operador), p_firma_operador_url,
        TRIM(p_motivo), p_observacion,
        v_stk_ori_old, v_stk_ori_new,
        v_stk_dst_old, v_stk_dst_new,
        v_cpp_dest_old, v_cpp_dest_new,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        v_fecha, v_operador_pf, v_user_id
    );

    -- Kardex SALIDA (origen)
    v_kardex_sal := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        observacion, created_by, traspaso_id
    ) VALUES (
        v_kardex_sal, p_estanque_origen_id, v_fecha, 'traspaso_salida', v_folio || '-S',
        0, p_litros, v_cpp_origen,
        v_stk_ori_new, v_cpp_origen, v_val_ori_post,
        'Traspaso a ' || v_destino.codigo || ' (' || COALESCE(p_motivo,'') || ')',
        v_user_id, v_traspaso_id
    );

    -- Kardex ENTRADA (destino)
    v_kardex_ent := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        observacion, created_by, traspaso_id
    ) VALUES (
        v_kardex_ent, p_estanque_destino_id, v_fecha, 'traspaso_entrada', v_folio || '-E',
        p_litros, 0, v_cpp_origen,
        v_stk_dst_new, v_cpp_dest_new, v_val_dst_post,
        'Traspaso desde ' || v_origen.codigo || ' (' || COALESCE(p_motivo,'') || ')',
        v_user_id, v_traspaso_id
    );

    -- Enlazar kardex en traspaso
    UPDATE combustible_traspasos
       SET kardex_salida_id  = v_kardex_sal,
           kardex_entrada_id = v_kardex_ent
     WHERE id = v_traspaso_id;

    -- Actualizar estanques
    UPDATE combustible_estanques
       SET stock_teorico_lt = v_stk_ori_new,
           updated_at       = NOW()
     WHERE id = p_estanque_origen_id;

    UPDATE combustible_estanques
       SET stock_teorico_lt   = v_stk_dst_new,
           costo_promedio_lt  = v_cpp_dest_new,
           updated_at         = NOW()
     WHERE id = p_estanque_destino_id;

    RETURN jsonb_build_object(
        'success',            true,
        'traspaso_id',        v_traspaso_id,
        'folio',              v_folio,
        'origen_codigo',      v_origen.codigo,
        'destino_codigo',     v_destino.codigo,
        'litros',             p_litros,
        'cpp_origen',         v_cpp_origen,
        'cpp_destino_antes',  v_cpp_dest_old,
        'cpp_destino_despues', v_cpp_dest_new,
        'stock_origen_antes', v_stk_ori_old,
        'stock_origen_despues', v_stk_ori_new,
        'stock_destino_antes', v_stk_dst_old,
        'stock_destino_despues', v_stk_dst_new,
        'costo_total',        v_costo_total,
        'kardex_salida_id',   v_kardex_sal,
        'kardex_entrada_id',  v_kardex_ent
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_traspaso_combustible IS
    'Traspasa combustible de un estanque a otro. Genera 2 entradas en kardex (salida origen + entrada destino al CPP del origen). CPP destino se recalcula con formula movil. Evidencia obligatoria. MIG76.';


-- ============================================================================
-- 4. VISTA v_combustible_traspasos
-- ============================================================================
DROP VIEW IF EXISTS public.v_combustible_traspasos CASCADE;
CREATE VIEW v_combustible_traspasos AS
SELECT
    t.id                              AS traspaso_id,
    t.folio,
    t.fecha_traspaso,
    t.estanque_origen_id,
    eo.codigo                         AS origen_codigo,
    eo.nombre                         AS origen_nombre,
    t.estanque_destino_id,
    ed.codigo                         AS destino_codigo,
    ed.nombre                         AS destino_nombre,
    t.litros,
    t.cpp_origen_snapshot,
    t.costo_total_traspaso,
    t.stock_origen_anterior,
    t.stock_origen_nuevo,
    t.stock_destino_anterior,
    t.stock_destino_nuevo,
    t.cpp_destino_anterior,
    t.cpp_destino_nuevo,
    t.lectura_medidor_origen_inicial,
    t.lectura_medidor_origen_final,
    t.lectura_medidor_destino_inicial,
    t.lectura_medidor_destino_final,
    t.foto_medidor_origen_inicial_url,
    t.foto_medidor_origen_final_url,
    t.foto_medidor_destino_inicial_url,
    t.foto_medidor_destino_final_url,
    t.foto_manguerado_url,
    t.nombre_operador,
    t.rut_operador,
    t.firma_operador_url,
    t.motivo,
    t.observacion,
    t.lat, t.lng, t.accuracy, t.geolocation_status,
    t.kardex_salida_id,
    t.kardex_entrada_id,
    t.operador_id,
    up.nombre_completo                AS operador,
    t.created_by,
    t.created_at
FROM combustible_traspasos t
JOIN combustible_estanques eo ON eo.id = t.estanque_origen_id
JOIN combustible_estanques ed ON ed.id = t.estanque_destino_id
LEFT JOIN usuarios_perfil up ON up.id = t.operador_id;

COMMENT ON VIEW v_combustible_traspasos IS
    'Listado de traspasos entre estanques con evidencia y delta CPP destino. MIG76.';


-- ============================================================================
-- 5. RLS
-- ============================================================================
ALTER TABLE combustible_traspasos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_traspaso_select ON combustible_traspasos;
CREATE POLICY pol_traspaso_select ON combustible_traspasos
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_traspaso_write ON combustible_traspasos;
CREATE POLICY pol_traspaso_write ON combustible_traspasos
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones',
                                  'jefe_mantenimiento','operador_abastecimiento','bodeguero'))
    WITH CHECK (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones',
                                  'jefe_mantenimiento','operador_abastecimiento','bodeguero'));


GRANT EXECUTE ON FUNCTION rpc_registrar_traspaso_combustible TO authenticated;
GRANT SELECT  ON v_combustible_traspasos TO authenticated;


-- ============================================================================
-- VALIDACION
-- ============================================================================
DO $$
DECLARE v_tabla INT; v_rpc INT; v_vista INT; v_col INT;
BEGIN
    SELECT COUNT(*) INTO v_tabla FROM information_schema.tables
     WHERE table_schema='public' AND table_name='combustible_traspasos';
    IF v_tabla <> 1 THEN RAISE EXCEPTION 'STOP - tabla combustible_traspasos no creada'; END IF;

    SELECT COUNT(*) INTO v_rpc FROM pg_proc
     WHERE proname='rpc_registrar_traspaso_combustible';
    IF v_rpc <> 1 THEN RAISE EXCEPTION 'STOP - RPC no creada'; END IF;

    SELECT COUNT(*) INTO v_vista FROM pg_views
     WHERE schemaname='public' AND viewname='v_combustible_traspasos';
    IF v_vista <> 1 THEN RAISE EXCEPTION 'STOP - vista no creada'; END IF;

    SELECT COUNT(*) INTO v_col FROM information_schema.columns
     WHERE table_name='combustible_kardex_valorizado' AND column_name='traspaso_id';
    IF v_col <> 1 THEN RAISE EXCEPTION 'STOP - columna traspaso_id no agregada al kardex'; END IF;

    RAISE NOTICE '== MIG76 aplicada OK ==';
END $$;


SELECT jsonb_build_object(
    'tabla_traspasos', to_regclass('public.combustible_traspasos') IS NOT NULL,
    'rpc_creada',      EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_traspaso_combustible'),
    'vista_creada',    EXISTS(SELECT 1 FROM pg_views WHERE viewname='v_combustible_traspasos'),
    'col_kardex_traspaso_id', EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='combustible_kardex_valorizado' AND column_name='traspaso_id')
) AS resultado;

NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- ROLLBACK manual
--   DROP VIEW IF EXISTS v_combustible_traspasos;
--   DROP FUNCTION IF EXISTS rpc_registrar_traspaso_combustible(UUID,UUID,NUMERIC,TEXT,TEXT,TEXT,TEXT,TEXT,VARCHAR,VARCHAR,TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,NUMERIC,NUMERIC,NUMERIC,VARCHAR,TIMESTAMPTZ);
--   ALTER TABLE combustible_kardex_valorizado DROP COLUMN IF EXISTS traspaso_id;
--   DROP TABLE IF EXISTS combustible_traspasos;
-- ============================================================================
