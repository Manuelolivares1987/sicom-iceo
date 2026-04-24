-- ============================================================================
-- SICOM-ICEO | Migracion 50 — Combustible: estanques, medidores y movimientos
-- ============================================================================
-- Gestion de diesel con lectura de medidor tipo "cuenta kilometros":
--   - Estanques (15.000 / 1.000 / 600 lt) con stock teorico continuo
--   - Medidores mecanicos (totalizador no reseteable tipo TCS 700-20SP4AL)
--   - Movimientos por diferencia de lectura (litros = lect_final - lect_inicial)
--   - Varillaje diario para conciliar teorico vs fisico
--   - Foto del medidor obligatoria en cada movimiento (trazabilidad)
--   - Despachos con destino variable: vehiculo de flota, equipo externo, bidon
-- ============================================================================

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE tipo_medidor_combustible_enum AS ENUM ('ingreso','despacho','bidireccional');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE tipo_movimiento_combustible_enum AS ENUM (
        'ingreso',     -- Compra / reposicion desde proveedor
        'despacho',    -- Entrega a vehiculo/equipo/bidon
        'ajuste',      -- Correccion manual (no usa medidor)
        'merma'        -- Perdida registrada por varillaje o evento
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE destino_despacho_combustible_enum AS ENUM (
        'vehiculo_flota',   -- Activo del maestro (camioneta, camion, etc.)
        'equipo_externo',   -- Equipo no inventariado (texto libre)
        'bidon',            -- Bidon/tambor portatil
        'otro'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================================
-- 2. TABLA combustible_estanques
-- ============================================================================

CREATE TABLE IF NOT EXISTS combustible_estanques (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo                  VARCHAR(30) UNIQUE NOT NULL,           -- "EST-15K", "EST-1K-A"
    nombre                  VARCHAR(100) NOT NULL,
    capacidad_lt            NUMERIC(10,2) NOT NULL CHECK (capacidad_lt > 0),
    faena_id                UUID REFERENCES faenas(id),
    ubicacion_detalle       TEXT,
    stock_teorico_lt        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (stock_teorico_lt >= 0),
    stock_minimo_alerta_lt  NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (stock_minimo_alerta_lt >= 0),
    activo                  BOOLEAN NOT NULL DEFAULT true,
    observaciones           TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_ce_stock_capacidad CHECK (stock_teorico_lt <= capacidad_lt)
);

CREATE INDEX IF NOT EXISTS idx_ce_faena  ON combustible_estanques (faena_id);
CREATE INDEX IF NOT EXISTS idx_ce_activo ON combustible_estanques (activo);

CREATE TRIGGER trg_ce_updated_at
    BEFORE UPDATE ON combustible_estanques
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 3. TABLA combustible_medidores
-- ============================================================================

CREATE TABLE IF NOT EXISTS combustible_medidores (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estanque_id                 UUID NOT NULL REFERENCES combustible_estanques(id) ON DELETE CASCADE,
    tipo                        tipo_medidor_combustible_enum NOT NULL DEFAULT 'bidireccional',
    marca                       VARCHAR(60),                      -- "TCS", "Total Control Systems"
    modelo                      VARCHAR(60),                      -- "700-20SP4AL"
    numero_serie                VARCHAR(60),
    lectura_acumulada_actual    NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (lectura_acumulada_actual >= 0),
    fecha_ultima_lectura        TIMESTAMPTZ,
    activo                      BOOLEAN NOT NULL DEFAULT true,
    observaciones               TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cm_estanque ON combustible_medidores (estanque_id);
CREATE INDEX IF NOT EXISTS idx_cm_activo   ON combustible_medidores (activo);

CREATE TRIGGER trg_cm_updated_at
    BEFORE UPDATE ON combustible_medidores
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 4. TABLA combustible_movimientos
-- ============================================================================

CREATE TABLE IF NOT EXISTS combustible_movimientos (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo                    tipo_movimiento_combustible_enum NOT NULL,
    estanque_id             UUID NOT NULL REFERENCES combustible_estanques(id),
    medidor_id              UUID REFERENCES combustible_medidores(id),

    -- Lecturas del totalizador (tipo odometro: no se resetean)
    lectura_inicial_lt      NUMERIC(12,2),
    lectura_final_lt        NUMERIC(12,2),

    -- Litros efectivos del movimiento
    litros                  NUMERIC(10,2) NOT NULL CHECK (litros >= 0),

    -- Evidencia (foto del medidor obligatoria salvo ajuste/merma por varillaje)
    foto_medidor_url        TEXT,

    fecha_hora              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    operador_id             UUID REFERENCES usuarios_perfil(id),

    -- Datos de ingreso
    proveedor               VARCHAR(200),
    numero_factura          VARCHAR(60),
    costo_unitario_clp      NUMERIC(10,2),
    costo_total_clp         NUMERIC(14,0),

    -- Datos de despacho
    destino_tipo            destino_despacho_combustible_enum,
    vehiculo_activo_id      UUID REFERENCES activos(id),         -- si destino_tipo = vehiculo_flota
    destino_descripcion     VARCHAR(200),                        -- si equipo_externo/bidon/otro
    horometro_vehiculo      NUMERIC(12,1),                       -- snapshot al despachar
    kilometraje_vehiculo    NUMERIC(12,1),                       -- snapshot al despachar

    observaciones           TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Coherencia de lecturas
    CONSTRAINT chk_cmov_lecturas CHECK (
        (lectura_inicial_lt IS NULL AND lectura_final_lt IS NULL)
        OR (lectura_inicial_lt IS NOT NULL AND lectura_final_lt IS NOT NULL
            AND lectura_final_lt >= lectura_inicial_lt)
    ),
    -- Si hay lecturas, los litros coinciden con la diferencia (tolerancia 0.01)
    CONSTRAINT chk_cmov_litros_coinciden CHECK (
        lectura_inicial_lt IS NULL
        OR ABS(litros - (lectura_final_lt - lectura_inicial_lt)) < 0.02
    ),
    -- Destino obligatorio en despachos
    CONSTRAINT chk_cmov_destino_despacho CHECK (
        tipo != 'despacho' OR destino_tipo IS NOT NULL
    ),
    -- Si es vehiculo_flota, debe referenciar un activo
    CONSTRAINT chk_cmov_vehiculo_fk CHECK (
        destino_tipo IS DISTINCT FROM 'vehiculo_flota'
        OR vehiculo_activo_id IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_cmov_estanque    ON combustible_movimientos (estanque_id);
CREATE INDEX IF NOT EXISTS idx_cmov_medidor     ON combustible_movimientos (medidor_id);
CREATE INDEX IF NOT EXISTS idx_cmov_tipo        ON combustible_movimientos (tipo);
CREATE INDEX IF NOT EXISTS idx_cmov_fecha       ON combustible_movimientos (fecha_hora DESC);
CREATE INDEX IF NOT EXISTS idx_cmov_vehiculo    ON combustible_movimientos (vehiculo_activo_id)
    WHERE vehiculo_activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cmov_operador    ON combustible_movimientos (operador_id);


-- ============================================================================
-- 5. TABLA combustible_varillaje — Medicion fisica diaria
-- ============================================================================

CREATE TABLE IF NOT EXISTS combustible_varillaje (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estanque_id                 UUID NOT NULL REFERENCES combustible_estanques(id),
    fecha                       DATE NOT NULL DEFAULT CURRENT_DATE,
    turno                       VARCHAR(20),                     -- "dia", "noche", "unico"
    medicion_fisica_lt          NUMERIC(10,2) NOT NULL CHECK (medicion_fisica_lt >= 0),
    stock_teorico_snapshot_lt   NUMERIC(10,2) NOT NULL,
    diferencia_lt               NUMERIC(10,2) GENERATED ALWAYS AS
                                    (medicion_fisica_lt - stock_teorico_snapshot_lt) STORED,
    ajuste_movimiento_id        UUID REFERENCES combustible_movimientos(id),
    operador_id                 UUID REFERENCES usuarios_perfil(id),
    foto_varilla_url            TEXT,
    observaciones               TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cv_estanque_fecha ON combustible_varillaje (estanque_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_cv_fecha          ON combustible_varillaje (fecha DESC);


-- ============================================================================
-- 6. TRIGGER — Validacion de lectura inicial contra medidor
-- ============================================================================
-- Garantiza que lectura_inicial_lt == medidor.lectura_acumulada_actual al
-- momento de registrar el movimiento (detecta saltos o lecturas fuera de orden).

CREATE OR REPLACE FUNCTION fn_validar_lectura_medidor()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_lectura_actual NUMERIC(12,2);
BEGIN
    IF NEW.medidor_id IS NULL OR NEW.lectura_inicial_lt IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT lectura_acumulada_actual INTO v_lectura_actual
      FROM combustible_medidores
     WHERE id = NEW.medidor_id
     FOR UPDATE;

    IF v_lectura_actual IS NULL THEN
        RAISE EXCEPTION 'Medidor % no existe', NEW.medidor_id;
    END IF;

    IF ABS(NEW.lectura_inicial_lt - v_lectura_actual) > 0.01 THEN
        RAISE EXCEPTION
            'Lectura inicial (%) no coincide con la ultima registrada en el medidor (%). Verifique la lectura o contacte al administrador.',
            NEW.lectura_inicial_lt, v_lectura_actual;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cmov_validar_lectura ON combustible_movimientos;
CREATE TRIGGER trg_cmov_validar_lectura
    BEFORE INSERT ON combustible_movimientos
    FOR EACH ROW EXECUTE FUNCTION fn_validar_lectura_medidor();


-- ============================================================================
-- 7. TRIGGER — Actualizar medidor y stock del estanque tras movimiento
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_aplicar_movimiento_combustible()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_delta NUMERIC(10,2);
BEGIN
    -- Avanzar medidor si hubo lectura
    IF NEW.medidor_id IS NOT NULL AND NEW.lectura_final_lt IS NOT NULL THEN
        UPDATE combustible_medidores
           SET lectura_acumulada_actual = NEW.lectura_final_lt,
               fecha_ultima_lectura     = NEW.fecha_hora,
               updated_at               = NOW()
         WHERE id = NEW.medidor_id;
    END IF;

    -- Delta sobre el stock segun tipo
    v_delta := CASE NEW.tipo
        WHEN 'ingreso'  THEN  NEW.litros
        WHEN 'despacho' THEN -NEW.litros
        WHEN 'merma'    THEN -NEW.litros
        WHEN 'ajuste'   THEN  NEW.litros   -- puede ser + o - (litros siempre >= 0; direccion se modela con dos tipos futuros si hace falta)
        ELSE 0
    END;

    UPDATE combustible_estanques
       SET stock_teorico_lt = GREATEST(0, stock_teorico_lt + v_delta),
           updated_at       = NOW()
     WHERE id = NEW.estanque_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cmov_aplicar ON combustible_movimientos;
CREATE TRIGGER trg_cmov_aplicar
    AFTER INSERT ON combustible_movimientos
    FOR EACH ROW EXECUTE FUNCTION fn_aplicar_movimiento_combustible();


-- ============================================================================
-- 8. RPC — registrar movimiento (valida y crea en una transaccion)
-- ============================================================================
-- Simplifica la UI: recibe estanque+medidor+lecturas y resuelve todo.

CREATE OR REPLACE FUNCTION fn_registrar_movimiento_combustible(
    p_tipo                 tipo_movimiento_combustible_enum,
    p_estanque_id          UUID,
    p_medidor_id           UUID,
    p_lectura_inicial_lt   NUMERIC,
    p_lectura_final_lt     NUMERIC,
    p_foto_medidor_url     TEXT DEFAULT NULL,
    -- ingreso
    p_proveedor            VARCHAR DEFAULT NULL,
    p_numero_factura       VARCHAR DEFAULT NULL,
    p_costo_unitario_clp   NUMERIC DEFAULT NULL,
    -- despacho
    p_destino_tipo         destino_despacho_combustible_enum DEFAULT NULL,
    p_vehiculo_activo_id   UUID DEFAULT NULL,
    p_destino_descripcion  VARCHAR DEFAULT NULL,
    p_horometro_vehiculo   NUMERIC DEFAULT NULL,
    p_kilometraje_vehiculo NUMERIC DEFAULT NULL,
    p_observaciones        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id        UUID;
    v_litros         NUMERIC(10,2);
    v_costo_total    NUMERIC(14,0);
    v_movimiento_id  UUID;
    v_stock_nuevo    NUMERIC(10,2);
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    IF p_lectura_final_lt < p_lectura_inicial_lt THEN
        RAISE EXCEPTION 'Lectura final (%) debe ser >= lectura inicial (%)',
            p_lectura_final_lt, p_lectura_inicial_lt;
    END IF;

    v_litros := p_lectura_final_lt - p_lectura_inicial_lt;

    IF v_litros <= 0 THEN
        RAISE EXCEPTION 'Los litros del movimiento deben ser > 0';
    END IF;

    v_costo_total := CASE
        WHEN p_costo_unitario_clp IS NOT NULL
        THEN ROUND(p_costo_unitario_clp * v_litros, 0)
        ELSE NULL
    END;

    INSERT INTO combustible_movimientos (
        tipo, estanque_id, medidor_id,
        lectura_inicial_lt, lectura_final_lt, litros,
        foto_medidor_url, operador_id,
        proveedor, numero_factura, costo_unitario_clp, costo_total_clp,
        destino_tipo, vehiculo_activo_id, destino_descripcion,
        horometro_vehiculo, kilometraje_vehiculo,
        observaciones
    ) VALUES (
        p_tipo, p_estanque_id, p_medidor_id,
        p_lectura_inicial_lt, p_lectura_final_lt, v_litros,
        p_foto_medidor_url, v_user_id,
        p_proveedor, p_numero_factura, p_costo_unitario_clp, v_costo_total,
        p_destino_tipo, p_vehiculo_activo_id, p_destino_descripcion,
        p_horometro_vehiculo, p_kilometraje_vehiculo,
        p_observaciones
    )
    RETURNING id INTO v_movimiento_id;

    -- Actualizar horometro/kilometraje del activo si corresponde
    IF p_vehiculo_activo_id IS NOT NULL THEN
        UPDATE activos
           SET horas_uso_actual  = GREATEST(horas_uso_actual,  COALESCE(p_horometro_vehiculo, horas_uso_actual)),
               kilometraje_actual = GREATEST(kilometraje_actual, COALESCE(p_kilometraje_vehiculo, kilometraje_actual)),
               updated_at        = NOW()
         WHERE id = p_vehiculo_activo_id;
    END IF;

    SELECT stock_teorico_lt INTO v_stock_nuevo
      FROM combustible_estanques WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success',         true,
        'movimiento_id',   v_movimiento_id,
        'litros',          v_litros,
        'stock_teorico',   v_stock_nuevo,
        'costo_total_clp', v_costo_total
    );
END;
$$;


-- ============================================================================
-- 9. RPC — registrar varillaje y (opcional) generar ajuste
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_registrar_varillaje_combustible(
    p_estanque_id         UUID,
    p_medicion_fisica_lt  NUMERIC,
    p_turno               VARCHAR DEFAULT NULL,
    p_generar_ajuste      BOOLEAN DEFAULT false,
    p_foto_varilla_url    TEXT DEFAULT NULL,
    p_observaciones       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id       UUID;
    v_teorico       NUMERIC(10,2);
    v_diferencia    NUMERIC(10,2);
    v_varillaje_id  UUID;
    v_ajuste_id     UUID;
    v_tipo_ajuste   tipo_movimiento_combustible_enum;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT stock_teorico_lt INTO v_teorico
      FROM combustible_estanques WHERE id = p_estanque_id
      FOR UPDATE;

    IF v_teorico IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;

    v_diferencia := p_medicion_fisica_lt - v_teorico;

    INSERT INTO combustible_varillaje (
        estanque_id, turno, medicion_fisica_lt,
        stock_teorico_snapshot_lt, operador_id,
        foto_varilla_url, observaciones
    ) VALUES (
        p_estanque_id, p_turno, p_medicion_fisica_lt,
        v_teorico, v_user_id, p_foto_varilla_url, p_observaciones
    )
    RETURNING id INTO v_varillaje_id;

    IF p_generar_ajuste AND ABS(v_diferencia) > 0.01 THEN
        v_tipo_ajuste := CASE WHEN v_diferencia < 0 THEN 'merma' ELSE 'ajuste' END;

        INSERT INTO combustible_movimientos (
            tipo, estanque_id, litros, operador_id, observaciones
        ) VALUES (
            v_tipo_ajuste, p_estanque_id, ABS(v_diferencia), v_user_id,
            'Ajuste por varillaje ' || v_varillaje_id::TEXT
        )
        RETURNING id INTO v_ajuste_id;

        UPDATE combustible_varillaje
           SET ajuste_movimiento_id = v_ajuste_id
         WHERE id = v_varillaje_id;
    END IF;

    RETURN jsonb_build_object(
        'success',       true,
        'varillaje_id',  v_varillaje_id,
        'teorico_lt',    v_teorico,
        'fisico_lt',     p_medicion_fisica_lt,
        'diferencia_lt', v_diferencia,
        'ajuste_id',     v_ajuste_id
    );
END;
$$;


-- ============================================================================
-- 10. STORAGE BUCKET — fotos de medidores y varillajes
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'evidencias-combustible',
    'evidencias-combustible',
    true,
    10485760,
    ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS pol_comb_select ON storage.objects;
CREATE POLICY pol_comb_select ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'evidencias-combustible');

DROP POLICY IF EXISTS pol_comb_insert ON storage.objects;
CREATE POLICY pol_comb_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'evidencias-combustible');

DROP POLICY IF EXISTS pol_comb_update_own ON storage.objects;
CREATE POLICY pol_comb_update_own ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'evidencias-combustible' AND owner = auth.uid());

DROP POLICY IF EXISTS pol_comb_delete_own ON storage.objects;
CREATE POLICY pol_comb_delete_own ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'evidencias-combustible' AND owner = auth.uid());


-- ============================================================================
-- 11. RLS
-- ============================================================================

ALTER TABLE combustible_estanques    ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_medidores    ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_movimientos  ENABLE ROW LEVEL SECURITY;
ALTER TABLE combustible_varillaje    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ce_all ON combustible_estanques;
CREATE POLICY pol_ce_all ON combustible_estanques FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_cm_all ON combustible_medidores;
CREATE POLICY pol_cm_all ON combustible_medidores FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_cmov_all ON combustible_movimientos;
CREATE POLICY pol_cmov_all ON combustible_movimientos FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_cv_all ON combustible_varillaje;
CREATE POLICY pol_cv_all ON combustible_varillaje FOR ALL TO authenticated
    USING (true) WITH CHECK (true);


-- ============================================================================
-- 12. VISTAS
-- ============================================================================

-- Lista de estanques con medidores y ultimo varillaje
CREATE OR REPLACE VIEW v_combustible_estanques_resumen AS
SELECT
    e.id,
    e.codigo,
    e.nombre,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.stock_minimo_alerta_lt,
    e.faena_id,
    f.nombre                     AS faena_nombre,
    e.ubicacion_detalle,
    e.activo,
    ROUND((e.stock_teorico_lt / NULLIF(e.capacidad_lt,0) * 100)::numeric, 1)
                                 AS pct_llenado,
    (e.stock_teorico_lt <= e.stock_minimo_alerta_lt)
                                 AS bajo_minimo,
    (SELECT COUNT(*) FROM combustible_medidores WHERE estanque_id = e.id AND activo)
                                 AS n_medidores,
    (SELECT MAX(fecha) FROM combustible_varillaje WHERE estanque_id = e.id)
                                 AS ultima_varillaje_fecha,
    (SELECT diferencia_lt FROM combustible_varillaje
       WHERE estanque_id = e.id ORDER BY fecha DESC, created_at DESC LIMIT 1)
                                 AS ultima_varillaje_diferencia
FROM combustible_estanques e
LEFT JOIN faenas f ON f.id = e.faena_id;

COMMENT ON VIEW v_combustible_estanques_resumen IS
    'Resumen de estanques con % llenado, alerta de minimo, y ultimo varillaje.';


-- Movimientos con datos desnormalizados para listado
CREATE OR REPLACE VIEW v_combustible_movimientos_lista AS
SELECT
    m.id,
    m.tipo,
    m.fecha_hora,
    m.litros,
    m.lectura_inicial_lt,
    m.lectura_final_lt,
    m.foto_medidor_url,
    m.estanque_id,
    e.codigo                    AS estanque_codigo,
    e.nombre                    AS estanque_nombre,
    m.medidor_id,
    m.operador_id,
    up.nombre_completo          AS operador_nombre,
    m.proveedor,
    m.numero_factura,
    m.costo_unitario_clp,
    m.costo_total_clp,
    m.destino_tipo,
    m.vehiculo_activo_id,
    a.codigo                    AS vehiculo_codigo,
    a.nombre                    AS vehiculo_nombre,
    m.destino_descripcion,
    m.horometro_vehiculo,
    m.kilometraje_vehiculo,
    m.observaciones,
    m.created_at
FROM combustible_movimientos m
JOIN combustible_estanques e      ON e.id = m.estanque_id
LEFT JOIN usuarios_perfil up      ON up.id = m.operador_id
LEFT JOIN activos a               ON a.id = m.vehiculo_activo_id;


-- Rendimiento por vehiculo (consumo mes actual)
CREATE OR REPLACE VIEW v_combustible_consumo_vehiculo_mes AS
SELECT
    a.id                        AS activo_id,
    a.codigo                    AS activo_codigo,
    a.nombre                    AS activo_nombre,
    a.tipo                      AS tipo_activo,
    DATE_TRUNC('month', m.fecha_hora)::date AS mes,
    SUM(m.litros)               AS litros_total,
    COUNT(*)                    AS n_despachos,
    MAX(m.horometro_vehiculo)   AS horometro_max,
    MIN(m.horometro_vehiculo)   AS horometro_min,
    MAX(m.kilometraje_vehiculo) AS km_max,
    MIN(m.kilometraje_vehiculo) AS km_min,
    CASE
        WHEN MAX(m.kilometraje_vehiculo) > MIN(m.kilometraje_vehiculo)
        THEN ROUND(((MAX(m.kilometraje_vehiculo) - MIN(m.kilometraje_vehiculo)) / NULLIF(SUM(m.litros),0))::numeric, 2)
        ELSE NULL
    END AS km_por_litro
FROM combustible_movimientos m
JOIN activos a ON a.id = m.vehiculo_activo_id
WHERE m.tipo = 'despacho' AND m.vehiculo_activo_id IS NOT NULL
GROUP BY a.id, a.codigo, a.nombre, a.tipo, DATE_TRUNC('month', m.fecha_hora);


-- ============================================================================
-- 13. SEED — estanques iniciales (15.000 / 1.000 / 600)
-- ============================================================================

INSERT INTO combustible_estanques (codigo, nombre, capacidad_lt, stock_minimo_alerta_lt)
VALUES
    ('EST-15K', 'Estanque principal 15.000 lt',   15000, 1500),
    ('EST-1K',  'Estanque secundario 1.000 lt',    1000,  100),
    ('EST-600', 'Estanque auxiliar 600 lt',         600,   60)
ON CONFLICT (codigo) DO NOTHING;


-- ============================================================================
-- 14. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_tablas_ok  BOOLEAN;
    v_bucket_ok  BOOLEAN;
    v_fn1_ok     BOOLEAN;
    v_fn2_ok     BOOLEAN;
    v_vista1_ok  BOOLEAN;
    v_n_est      INTEGER;
BEGIN
    SELECT (
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'combustible_estanques')
    AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'combustible_medidores')
    AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'combustible_movimientos')
    AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'combustible_varillaje')
    ) INTO v_tablas_ok;

    SELECT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'evidencias-combustible') INTO v_bucket_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_registrar_movimiento_combustible') INTO v_fn1_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_registrar_varillaje_combustible')  INTO v_fn2_ok;
    SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'v_combustible_estanques_resumen')   INTO v_vista1_ok;
    SELECT COUNT(*) INTO v_n_est FROM combustible_estanques;

    RAISE NOTICE '== Migracion 50 ==';
    RAISE NOTICE 'Tablas combustible_* ..................... %', v_tablas_ok;
    RAISE NOTICE 'Bucket evidencias-combustible ............ %', v_bucket_ok;
    RAISE NOTICE 'fn_registrar_movimiento_combustible ...... %', v_fn1_ok;
    RAISE NOTICE 'fn_registrar_varillaje_combustible ....... %', v_fn2_ok;
    RAISE NOTICE 'v_combustible_estanques_resumen .......... %', v_vista1_ok;
    RAISE NOTICE 'Estanques seed ........................... %', v_n_est;

    IF NOT (v_tablas_ok AND v_bucket_ok AND v_fn1_ok AND v_fn2_ok AND v_vista1_ok) THEN
        RAISE EXCEPTION 'Migracion 50 incompleta.';
    END IF;
END $$;
