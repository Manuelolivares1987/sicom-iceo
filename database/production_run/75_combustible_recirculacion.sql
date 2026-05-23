-- ============================================================================
-- 75_combustible_recirculacion.sql
-- ----------------------------------------------------------------------------
-- Recirculacion de combustible para PRUEBA DE BOMBAS.
--
-- Operacion neutra de stock: se saca una X cantidad de combustible de un
-- estanque para alimentar un equipo de pillado / prueba de bomba, y se
-- DEVUELVE al mismo estanque la misma cantidad. Stock antes == stock despues.
--
-- Sin embargo el evento queda registrado con evidencia completa porque:
--   1. Pasa combustible por la maquinaria (riesgo de fraude / merma real).
--   2. Hay que poder auditar quien lo hizo y con que equipo.
--
-- Evidencia obligatoria (misma exigencia que despacho a vehiculo externo):
--   - foto patente del equipo de prueba / bomba
--   - foto del medidor del estanque ANTES (lectura inicial)
--   - foto del medidor del estanque DESPUES (debe volver a la misma lectura)
--   - foto del equipo de prueba conectado
--   - firma + nombre + RUT del operador que ejecuta la recirculacion
--   - motivo (>= 5 caracteres)
--
-- IMPORTANTE: no toca combustible_estanques.stock_teorico_lt, no afecta CPP
-- ni crea kardex valorizado. Es un evento auditable, no un movimiento.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_estanques') THEN
        RAISE EXCEPTION 'STOP - tabla combustible_estanques no existe (correr MIG50 primero).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_set_updated_at') THEN
        RAISE EXCEPTION 'STOP - falta fn_set_updated_at.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - falta fn_user_rol.';
    END IF;
END $$;


-- ============================================================================
-- 1. TABLA combustible_recirculaciones
-- ============================================================================
CREATE TABLE IF NOT EXISTS combustible_recirculaciones (
    id                              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    folio                           VARCHAR(40)  NOT NULL UNIQUE,
    estanque_id                     UUID         NOT NULL REFERENCES combustible_estanques(id),
    litros                          NUMERIC(10,2) NOT NULL CHECK (litros > 0),

    -- Equipo de prueba / bomba
    equipo_prueba_descripcion       VARCHAR(200) NOT NULL,
    patente_equipo_prueba           VARCHAR(20),
    foto_patente_equipo_url         TEXT         NOT NULL,
    foto_equipo_url                 TEXT         NOT NULL,

    -- Lectura del medidor del estanque (debe volver a la misma)
    lectura_medidor_inicial_lt      NUMERIC(12,2),
    lectura_medidor_final_lt        NUMERIC(12,2),
    foto_medidor_inicial_url        TEXT         NOT NULL,
    foto_medidor_final_url          TEXT         NOT NULL,

    -- Operador que ejecuta
    nombre_operador                 VARCHAR(200) NOT NULL,
    rut_operador                    VARCHAR(20)  NOT NULL,
    firma_operador_url              TEXT         NOT NULL,

    motivo                          TEXT         NOT NULL CHECK (length(trim(motivo)) >= 5),
    observacion                     TEXT,

    -- Geolocalizacion (best-effort, no obligatoria)
    lat                             NUMERIC(10,7),
    lng                             NUMERIC(10,7),
    accuracy                        NUMERIC(8,2),
    geolocation_status              VARCHAR(20),

    fecha_inicio                    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    fecha_cierre                    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    operador_id                     UUID         REFERENCES usuarios_perfil(id),
    created_by                      UUID         REFERENCES auth.users(id),
    created_at                      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_recirc_lecturas CHECK (
        (lectura_medidor_inicial_lt IS NULL AND lectura_medidor_final_lt IS NULL)
        OR (lectura_medidor_inicial_lt IS NOT NULL AND lectura_medidor_final_lt IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_recirc_estanque ON combustible_recirculaciones (estanque_id);
CREATE INDEX IF NOT EXISTS idx_recirc_fecha    ON combustible_recirculaciones (fecha_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_recirc_operador ON combustible_recirculaciones (operador_id) WHERE operador_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_recirc_updated_at ON combustible_recirculaciones;
CREATE TRIGGER trg_recirc_updated_at
    BEFORE UPDATE ON combustible_recirculaciones
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE combustible_recirculaciones IS
    'Recirculaciones de combustible para prueba de bombas. Operacion neutra de stock con evidencia completa. MIG75.';


-- ============================================================================
-- 2. RPC rpc_registrar_recirculacion_combustible
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_recirculacion_combustible(
    p_estanque_id                  UUID,
    p_litros                       NUMERIC,
    p_equipo_prueba_descripcion    VARCHAR,
    p_foto_patente_equipo_url      TEXT,
    p_foto_equipo_url              TEXT,
    p_foto_medidor_inicial_url     TEXT,
    p_foto_medidor_final_url       TEXT,
    p_nombre_operador              VARCHAR,
    p_rut_operador                 VARCHAR,
    p_firma_operador_url           TEXT,
    p_motivo                       TEXT,
    p_patente_equipo_prueba        VARCHAR DEFAULT NULL,
    p_lectura_medidor_inicial_lt   NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt     NUMERIC DEFAULT NULL,
    p_observacion                  TEXT    DEFAULT NULL,
    p_lat                          NUMERIC DEFAULT NULL,
    p_lng                          NUMERIC DEFAULT NULL,
    p_accuracy                     NUMERIC DEFAULT NULL,
    p_geolocation_status           VARCHAR DEFAULT NULL,
    p_fecha_inicio                 TIMESTAMPTZ DEFAULT NULL,
    p_fecha_cierre                 TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id    UUID := auth.uid();
    v_rol        TEXT;
    v_estanque   combustible_estanques%ROWTYPE;
    v_folio      VARCHAR;
    v_recirc_id  UUID;
    v_operador_perfil UUID;
    v_fecha_ini  TIMESTAMPTZ;
    v_fecha_fin  TIMESTAMPTZ;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para recirculacion de combustible', v_rol;
    END IF;

    -- Validar litros y estanque
    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    SELECT * INTO v_estanque FROM combustible_estanques WHERE id = p_estanque_id;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;
    IF v_estanque.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente para recirculacion en %: actual % lt, solicitado % lt',
            v_estanque.codigo, v_estanque.stock_teorico_lt, p_litros;
    END IF;

    -- Evidencia obligatoria (misma exigencia que despacho a externo)
    IF p_equipo_prueba_descripcion IS NULL OR length(trim(p_equipo_prueba_descripcion)) < 3 THEN
        RAISE EXCEPTION 'Descripcion del equipo de prueba obligatoria (min 3 caracteres).';
    END IF;
    IF p_foto_patente_equipo_url IS NULL OR length(trim(p_foto_patente_equipo_url)) = 0 THEN
        RAISE EXCEPTION 'Foto de la patente del equipo de prueba es OBLIGATORIA.';
    END IF;
    IF p_foto_equipo_url IS NULL OR length(trim(p_foto_equipo_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del equipo de prueba conectado es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del medidor INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del medidor FINAL (tras retornar el combustible) es OBLIGATORIA.';
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

    -- Lecturas (si vienen ambas, validar coherencia: tras retornar debe ser igual o casi igual)
    IF p_lectura_medidor_inicial_lt IS NOT NULL AND p_lectura_medidor_final_lt IS NOT NULL THEN
        IF p_lectura_medidor_final_lt < p_lectura_medidor_inicial_lt THEN
            RAISE EXCEPTION 'Lectura final (%) no puede ser menor a la inicial (%) — el medidor es no reseteable.',
                p_lectura_medidor_final_lt, p_lectura_medidor_inicial_lt;
        END IF;
    END IF;

    v_fecha_ini := COALESCE(p_fecha_inicio, NOW());
    v_fecha_fin := COALESCE(p_fecha_cierre, v_fecha_ini);

    -- Folio: RCB-YYYYMMDD-HHMMSS
    v_folio := 'RCB-' || TO_CHAR(v_fecha_ini, 'YYYYMMDD-HH24MISS');

    -- Resolver operador_id en usuarios_perfil
    SELECT id INTO v_operador_perfil FROM usuarios_perfil WHERE user_id = v_user_id LIMIT 1;

    v_recirc_id := gen_random_uuid();
    INSERT INTO combustible_recirculaciones (
        id, folio, estanque_id, litros,
        equipo_prueba_descripcion, patente_equipo_prueba,
        foto_patente_equipo_url, foto_equipo_url,
        lectura_medidor_inicial_lt, lectura_medidor_final_lt,
        foto_medidor_inicial_url, foto_medidor_final_url,
        nombre_operador, rut_operador, firma_operador_url,
        motivo, observacion,
        lat, lng, accuracy, geolocation_status,
        fecha_inicio, fecha_cierre,
        operador_id, created_by
    ) VALUES (
        v_recirc_id, v_folio, p_estanque_id, p_litros,
        TRIM(p_equipo_prueba_descripcion), NULLIF(TRIM(p_patente_equipo_prueba), ''),
        p_foto_patente_equipo_url, p_foto_equipo_url,
        p_lectura_medidor_inicial_lt, p_lectura_medidor_final_lt,
        p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        TRIM(p_nombre_operador), TRIM(p_rut_operador), p_firma_operador_url,
        TRIM(p_motivo), p_observacion,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        v_fecha_ini, v_fecha_fin,
        v_operador_perfil, v_user_id
    );

    -- NO se actualiza stock_teorico_lt: operacion neutra.

    RETURN jsonb_build_object(
        'success',         true,
        'recirculacion_id', v_recirc_id,
        'folio',           v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros',          p_litros,
        'stock_no_cambia', v_estanque.stock_teorico_lt,
        'fecha_inicio',    v_fecha_ini,
        'fecha_cierre',    v_fecha_fin
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_recirculacion_combustible IS
    'Registra una recirculacion de combustible (prueba de bomba). Operacion neutra de stock con evidencia completa obligatoria. MIG75.';


-- ============================================================================
-- 3. VISTA v_combustible_recirculaciones
-- ============================================================================
DROP VIEW IF EXISTS public.v_combustible_recirculaciones CASCADE;
CREATE VIEW v_combustible_recirculaciones AS
SELECT
    r.id                            AS recirculacion_id,
    r.folio,
    r.fecha_inicio,
    r.fecha_cierre,
    r.estanque_id,
    e.codigo                        AS estanque_codigo,
    e.nombre                        AS estanque_nombre,
    r.litros,
    r.equipo_prueba_descripcion,
    r.patente_equipo_prueba,
    r.foto_patente_equipo_url,
    r.foto_equipo_url,
    r.lectura_medidor_inicial_lt,
    r.lectura_medidor_final_lt,
    r.foto_medidor_inicial_url,
    r.foto_medidor_final_url,
    r.nombre_operador,
    r.rut_operador,
    r.firma_operador_url,
    r.motivo,
    r.observacion,
    r.lat, r.lng, r.accuracy, r.geolocation_status,
    r.operador_id,
    up.nombre_completo              AS operador,
    r.created_by,
    r.created_at
FROM combustible_recirculaciones r
JOIN combustible_estanques e   ON e.id = r.estanque_id
LEFT JOIN usuarios_perfil up   ON up.id = r.operador_id;

COMMENT ON VIEW v_combustible_recirculaciones IS
    'Listado de recirculaciones de combustible con evidencia. MIG75.';


-- ============================================================================
-- 4. RLS
-- ============================================================================
ALTER TABLE combustible_recirculaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_recirc_select ON combustible_recirculaciones;
CREATE POLICY pol_recirc_select ON combustible_recirculaciones
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_recirc_write ON combustible_recirculaciones;
CREATE POLICY pol_recirc_write ON combustible_recirculaciones
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones',
                                  'jefe_mantenimiento','operador_abastecimiento','bodeguero'))
    WITH CHECK (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones',
                                  'jefe_mantenimiento','operador_abastecimiento','bodeguero'));


GRANT EXECUTE ON FUNCTION rpc_registrar_recirculacion_combustible TO authenticated;
GRANT SELECT  ON v_combustible_recirculaciones TO authenticated;


-- ============================================================================
-- VALIDACION
-- ============================================================================
DO $$
DECLARE v_tabla INT; v_rpc INT; v_vista INT;
BEGIN
    SELECT COUNT(*) INTO v_tabla FROM information_schema.tables
     WHERE table_schema='public' AND table_name='combustible_recirculaciones';
    IF v_tabla <> 1 THEN RAISE EXCEPTION 'STOP - tabla combustible_recirculaciones no creada'; END IF;

    SELECT COUNT(*) INTO v_rpc FROM pg_proc
     WHERE proname='rpc_registrar_recirculacion_combustible';
    IF v_rpc <> 1 THEN RAISE EXCEPTION 'STOP - RPC no creada'; END IF;

    SELECT COUNT(*) INTO v_vista FROM pg_views
     WHERE schemaname='public' AND viewname='v_combustible_recirculaciones';
    IF v_vista <> 1 THEN RAISE EXCEPTION 'STOP - vista no creada'; END IF;

    RAISE NOTICE '== MIG75 aplicada OK ==';
    RAISE NOTICE '   tabla combustible_recirculaciones creada';
    RAISE NOTICE '   RPC rpc_registrar_recirculacion_combustible creada';
    RAISE NOTICE '   vista v_combustible_recirculaciones creada';
END $$;


SELECT jsonb_build_object(
    'tabla_recirculaciones', to_regclass('public.combustible_recirculaciones') IS NOT NULL,
    'rpc_creada',            EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_recirculacion_combustible'),
    'vista_creada',          EXISTS(SELECT 1 FROM pg_views WHERE viewname='v_combustible_recirculaciones')
) AS resultado;

NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- ROLLBACK manual
--   DROP VIEW IF EXISTS v_combustible_recirculaciones;
--   DROP FUNCTION IF EXISTS rpc_registrar_recirculacion_combustible(UUID,NUMERIC,VARCHAR,TEXT,TEXT,TEXT,TEXT,VARCHAR,VARCHAR,TEXT,TEXT,VARCHAR,NUMERIC,NUMERIC,TEXT,NUMERIC,NUMERIC,NUMERIC,VARCHAR,TIMESTAMPTZ,TIMESTAMPTZ);
--   DROP TABLE IF EXISTS combustible_recirculaciones;
-- ============================================================================
