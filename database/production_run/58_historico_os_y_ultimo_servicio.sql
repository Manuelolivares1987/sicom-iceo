-- ============================================================================
-- 58_historico_os_y_ultimo_servicio.sql
-- ----------------------------------------------------------------------------
-- Importa el historico de 230 OS del Excel "Historico OS Auditoria.xlsx"
-- (Pillado, 2025-2026). Crea las tablas, funcion y vista necesarias para
-- que las pautas preventivas (MIG57) tengan un "punto cero" calibrado
-- — sin esto todas las pautas saldrian "vencidas hace miles de horas".
--
-- Crea:
--   - os_historico_importado     : log granular de cada OS
--   - os_modelo_alias            : mapeo grafia Excel -> modelo canonico
--   - fn_ultimo_servicio_por_activo : retorna ultimo servicio (fecha, hor, km)
--   - v_pautas_estado_activo     : cruza activos x pautas x ultimo servicio
--                                  -> estado (al_dia / proxima / critica / vencida)
--
-- ADITIVA, IDEMPOTENTE. El seed bulk del final usa ON CONFLICT DO NOTHING.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP - tabla activos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='pautas_fabricante') THEN
        RAISE EXCEPTION 'STOP - tabla pautas_fabricante no existe (correr MIG57 primero).';
    END IF;
END $$;


-- ============================================================================
-- 1. TABLA os_historico_importado
-- ============================================================================
CREATE TABLE IF NOT EXISTS os_historico_importado (
    id              BIGSERIAL    PRIMARY KEY,
    -- Identificador OS
    os_numero       VARCHAR(50),                  -- "3194"
    os_codigo       VARCHAR(50),                  -- "CQBO-3194"
    anio            INT,
    -- Mapeo a entidades en BD
    patente         VARCHAR(20),
    activo_id       UUID         REFERENCES activos(id) ON DELETE SET NULL,
    modelo_id       UUID         REFERENCES modelos(id) ON DELETE SET NULL,
    modelo_original VARCHAR(200),                 -- grafia tal cual el Excel
    -- Tipo y contexto operacional
    tipo_servicio   VARCHAR(40)  NOT NULL DEFAULT 'otro',
    faena           VARCHAR(200),
    cliente         VARCHAR(200),
    ubicacion       VARCHAR(200),
    -- Tiempo de la OS
    fecha_recepcion DATE,
    fecha_entrega   DATE,
    -- Lectura de horometro/km al momento del servicio
    horometro       NUMERIC(12,1),
    kilometraje     NUMERIC(12,1),
    -- KPIs
    porcentaje_cumplimiento NUMERIC(5,1),
    responsable     VARCHAR(200),
    -- Flags del tipo de trabajo (puede haber varios)
    es_preventivo            BOOLEAN NOT NULL DEFAULT false,
    es_correctivo            BOOLEAN NOT NULL DEFAULT false,
    es_neumaticos            BOOLEAN NOT NULL DEFAULT false,
    es_revision_tecnica      BOOLEAN NOT NULL DEFAULT false,
    es_habilitacion_estanque BOOLEAN NOT NULL DEFAULT false,
    es_servicio_externo      BOOLEAN NOT NULL DEFAULT false,
    -- Conteo de trabajos
    cant_trabajos   INT,
    horas_mo        NUMERIC(8,1),
    -- Referencia a mantencion previa (segun lo que Pillado registro en Excel)
    ultima_mant_fecha DATE,
    ultima_mant_horas NUMERIC(12,1),
    frecuencia_texto  VARCHAR(100),
    -- Auditoria
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_os_hist_horometro CHECK (horometro IS NULL OR horometro >= 0),
    CONSTRAINT chk_os_hist_km        CHECK (kilometraje IS NULL OR kilometraje >= 0)
);

CREATE INDEX IF NOT EXISTS idx_os_hist_activo_fecha    ON os_historico_importado (activo_id, fecha_entrega DESC) WHERE activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_os_hist_patente_fecha   ON os_historico_importado (patente, fecha_entrega DESC);
CREATE INDEX IF NOT EXISTS idx_os_hist_anio_tipo       ON os_historico_importado (anio, tipo_servicio);
CREATE INDEX IF NOT EXISTS idx_os_hist_modelo          ON os_historico_importado (modelo_id) WHERE modelo_id IS NOT NULL;
-- UNIQUE plano (no partial): PG trata NULLs como distintos, asi que permite
-- multiples filas con os_codigo NULL pero un solo registro por cada os_codigo
-- no NULL. Necesario plano (no partial) para que ON CONFLICT (os_codigo) lo use.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.os_historico_importado'::regclass
           AND contype  = 'u'
           AND pg_get_constraintdef(oid) LIKE '%(os_codigo)%'
    ) THEN
        DROP INDEX IF EXISTS uq_os_hist_codigo;
        ALTER TABLE os_historico_importado
            ADD CONSTRAINT uq_os_hist_codigo UNIQUE (os_codigo);
    END IF;
END $$;


-- ============================================================================
-- 2. TABLA os_modelo_alias — mapeo grafia -> modelo (para re-importar)
-- ============================================================================
CREATE TABLE IF NOT EXISTS os_modelo_alias (
    grafia      TEXT PRIMARY KEY,         -- texto literal del Excel (lowercase)
    modelo_id   UUID REFERENCES modelos(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    notas       TEXT
);


-- ============================================================================
-- 3. RLS
-- ============================================================================
ALTER TABLE os_historico_importado ENABLE ROW LEVEL SECURITY;
ALTER TABLE os_modelo_alias        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_os_hist_select ON os_historico_importado;
CREATE POLICY pol_os_hist_select ON os_historico_importado
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_os_hist_write ON os_historico_importado;
CREATE POLICY pol_os_hist_write ON os_historico_importado
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_os_alias_all ON os_modelo_alias;
CREATE POLICY pol_os_alias_all ON os_modelo_alias
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));


-- ============================================================================
-- 4. FUNCION fn_ultimo_servicio_por_activo
-- ----------------------------------------------------------------------------
-- Devuelve el ultimo servicio (por tipo_servicio o cualquiera) para un activo.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_ultimo_servicio_por_activo(
    p_activo_id    UUID,
    p_tipo_servicio VARCHAR DEFAULT NULL  -- NULL = cualquiera
)
RETURNS TABLE (
    os_codigo            VARCHAR,
    fecha_entrega        DATE,
    horometro            NUMERIC,
    kilometraje          NUMERIC,
    tipo_servicio        VARCHAR,
    dias_desde_servicio  INT,
    horas_desde_servicio NUMERIC,
    km_desde_servicio    NUMERIC
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_horas_actual NUMERIC;
    v_km_actual    NUMERIC;
BEGIN
    SELECT a.horas_uso_actual, a.kilometraje_actual
      INTO v_horas_actual, v_km_actual
      FROM activos a WHERE a.id = p_activo_id;

    RETURN QUERY
    SELECT
        oh.os_codigo,
        oh.fecha_entrega,
        oh.horometro,
        oh.kilometraje,
        oh.tipo_servicio,
        CASE WHEN oh.fecha_entrega IS NULL THEN NULL
             ELSE (CURRENT_DATE - oh.fecha_entrega)::INT END,
        CASE WHEN oh.horometro IS NULL OR v_horas_actual IS NULL THEN NULL
             ELSE GREATEST(v_horas_actual - oh.horometro, 0) END,
        CASE WHEN oh.kilometraje IS NULL OR v_km_actual IS NULL THEN NULL
             ELSE GREATEST(v_km_actual - oh.kilometraje, 0) END
      FROM os_historico_importado oh
     WHERE oh.activo_id = p_activo_id
       AND (p_tipo_servicio IS NULL OR oh.tipo_servicio = p_tipo_servicio)
       AND oh.fecha_entrega IS NOT NULL
     ORDER BY oh.fecha_entrega DESC, oh.id DESC
     LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_ultimo_servicio_por_activo(UUID, VARCHAR) TO authenticated;


-- ============================================================================
-- 5. VISTA v_pautas_estado_activo
-- ----------------------------------------------------------------------------
-- Cruza cada activo con sus pautas aplicables (por modelo_id) y calcula:
--   - proximo_horometro / proximo_km / proximo_dia
--   - horas_restantes / km_restantes / dias_restantes
--   - estado_pauta (al_dia / proxima / critica / vencida)
-- ============================================================================
CREATE OR REPLACE VIEW v_pautas_estado_activo AS
WITH ultimo_por_activo AS (
    -- Ultimo servicio (cualquiera) por activo
    SELECT DISTINCT ON (activo_id)
           activo_id, fecha_entrega, horometro, kilometraje
      FROM os_historico_importado
     WHERE activo_id IS NOT NULL
       AND fecha_entrega IS NOT NULL
     ORDER BY activo_id, fecha_entrega DESC, id DESC
)
SELECT
    a.id            AS activo_id,
    a.codigo        AS activo_codigo,
    a.patente       AS activo_patente,
    a.tipo_equipamiento,
    a.horas_uso_actual AS horas_actuales,
    a.kilometraje_actual AS km_actuales,
    pf.id           AS pauta_id,
    pf.nombre       AS pauta_nombre,
    pf.tipo_plan,
    pf.frecuencia_horas,
    pf.frecuencia_km,
    pf.frecuencia_dias,
    pf.duracion_estimada_hrs,
    upa.fecha_entrega    AS ultima_fecha,
    upa.horometro        AS ultimo_horometro,
    upa.kilometraje      AS ultimo_km,
    -- Calculo de proximo
    CASE WHEN pf.frecuencia_horas IS NOT NULL AND upa.horometro IS NOT NULL
         THEN upa.horometro + pf.frecuencia_horas END AS proximo_horometro,
    CASE WHEN pf.frecuencia_km IS NOT NULL AND upa.kilometraje IS NOT NULL
         THEN upa.kilometraje + pf.frecuencia_km END AS proximo_km,
    CASE WHEN pf.frecuencia_dias IS NOT NULL AND upa.fecha_entrega IS NOT NULL
         THEN upa.fecha_entrega + pf.frecuencia_dias END AS proximo_dia,
    -- Restante
    CASE WHEN pf.frecuencia_horas IS NOT NULL AND upa.horometro IS NOT NULL AND a.horas_uso_actual IS NOT NULL
         THEN (upa.horometro + pf.frecuencia_horas) - a.horas_uso_actual END AS horas_restantes,
    CASE WHEN pf.frecuencia_km IS NOT NULL AND upa.kilometraje IS NOT NULL AND a.kilometraje_actual IS NOT NULL
         THEN (upa.kilometraje + pf.frecuencia_km) - a.kilometraje_actual END AS km_restantes,
    CASE WHEN pf.frecuencia_dias IS NOT NULL AND upa.fecha_entrega IS NOT NULL
         THEN ((upa.fecha_entrega + pf.frecuencia_dias) - CURRENT_DATE)::INT END AS dias_restantes,
    -- Semaforo estado_pauta:
    -- Toma el mas critico de los 3 ejes (horas, km, dias) si aplican.
    CASE
        WHEN upa.activo_id IS NULL                                          THEN 'sin_historico'
        -- VENCIDA: cualquier eje aplicable supero el limite
        WHEN (pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL
              AND a.horas_uso_actual > (upa.horometro + pf.frecuencia_horas))
          OR (pf.frecuencia_km IS NOT NULL AND a.kilometraje_actual IS NOT NULL
              AND a.kilometraje_actual > (upa.kilometraje + pf.frecuencia_km))
          OR (pf.frecuencia_dias IS NOT NULL
              AND CURRENT_DATE > (upa.fecha_entrega + pf.frecuencia_dias))
        THEN 'vencida'
        -- CRITICA: queda <10% del ciclo
        WHEN (pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL
              AND ((upa.horometro + pf.frecuencia_horas) - a.horas_uso_actual) <= (pf.frecuencia_horas * 0.10))
          OR (pf.frecuencia_km IS NOT NULL AND a.kilometraje_actual IS NOT NULL
              AND ((upa.kilometraje + pf.frecuencia_km) - a.kilometraje_actual) <= (pf.frecuencia_km * 0.10))
          OR (pf.frecuencia_dias IS NOT NULL
              AND ((upa.fecha_entrega + pf.frecuencia_dias) - CURRENT_DATE) <= (pf.frecuencia_dias * 0.10))
        THEN 'critica'
        -- PROXIMA: queda <50%
        WHEN (pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL
              AND ((upa.horometro + pf.frecuencia_horas) - a.horas_uso_actual) <= (pf.frecuencia_horas * 0.50))
          OR (pf.frecuencia_km IS NOT NULL AND a.kilometraje_actual IS NOT NULL
              AND ((upa.kilometraje + pf.frecuencia_km) - a.kilometraje_actual) <= (pf.frecuencia_km * 0.50))
          OR (pf.frecuencia_dias IS NOT NULL
              AND ((upa.fecha_entrega + pf.frecuencia_dias) - CURRENT_DATE) <= (pf.frecuencia_dias * 0.50))
        THEN 'proxima'
        ELSE 'al_dia'
    END AS estado_pauta
FROM activos a
JOIN pautas_fabricante pf ON pf.modelo_id = a.modelo_id AND pf.activo = true
LEFT JOIN ultimo_por_activo upa ON upa.activo_id = a.id
WHERE a.estado <> 'dado_baja';

GRANT SELECT ON v_pautas_estado_activo TO authenticated;


-- ============================================================================
-- 6. SEED — Importacion de 230 OS desde el Excel (auto-generado)
-- ----------------------------------------------------------------------------
-- Bulk insert a tabla temporal, luego JOIN con activos (por patente) y
-- modelos (por nombre) para resolver FKs antes de INSERT a tabla final.
-- ============================================================================
-- ===========================================================================

-- Tabla temporal para staging y normalizacion antes de mover a os_historico_importado
CREATE TEMP TABLE tmp_os_seed (
  os_numero VARCHAR, os_cqbo VARCHAR, anio INT, patente VARCHAR,
  modelo_canonico VARCHAR, modelo_original VARCHAR,
  tipo_servicio VARCHAR,
  faena VARCHAR, cliente VARCHAR, ubicacion VARCHAR,
  fecha_recepcion DATE, fecha_entrega DATE,
  horometro NUMERIC, kilometraje NUMERIC, pct_cumpl NUMERIC, responsable VARCHAR,
  es_prev BOOLEAN, es_corr BOOLEAN, es_neum BOOLEAN,
  es_rt BOOLEAN, es_he BOOLEAN, es_se BOOLEAN,
  cant_trabajos INT, horas_mo NUMERIC,
  ult_man_fecha DATE, ult_man_horas NUMERIC, frecuencia VARCHAR
);

INSERT INTO tmp_os_seed VALUES
  ('3194', 'CQBO-3194', 2025, 'KVWW-69', 'Actros 3336 K', 'ACTROS', 'otro', NULL, 'DMC', 'TALLER COQUIMBO', '0025-04-28', NULL, 6337, 83940, 100, 'CESAR + MIGUEL', false, false, false, false, false, false, 11, 16.5, NULL, NULL, 'FRECUENCIA'),
  ('3354', 'CQBO-3354', 2026, 'ROME-RAL', NULL, NULL, 'otro', NULL, NULL, NULL, '2026-04-20', '2026-04-20', NULL, NULL, 100, 'Joel Coo', false, false, false, false, false, false, 2, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3348', 'CQBO-3348', 2026, 'KVWD-27', 'Accelo 1016/44', 'M.Benz ACCELO 1016/44', 'otro', 'San Geronimo', 'Pillado', 'Taller', '2026-04-17', '2026-04-22', 6133, 59687, 100, 'Felipe Rojas', false, false, false, false, false, false, 6, 17.0, NULL, NULL, 'FRECUENCIA'),
  ('3349', 'CQBO-3349', 2026, 'JGBY-10', 'Axor 2633', 'M,Benz Axor 2633', 'otro', NULL, 'Drilling Service and', 'Taller', '2026-04-17', '2026-04-17', 8872, 106458, 100, 'Sergio Cortes', false, false, false, false, false, false, 3, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3350', 'CQBO-3350', 2026, 'SVCZ-38', 'VM 350', 'Volvo VM 350', 'otro', 'Andacollo', 'Rentamaq', 'Taller', '2026-04-15', '2026-04-18', 4107, 65256, 100, 'Joel Coo/Yusdel Sarduy', false, false, false, false, false, false, 8, 35.0, NULL, NULL, 'FRECUENCIA'),
  ('3352', 'CQBO-3352', 2026, 'JDKH-31', NULL, NULL, 'otro', 'Pillado', 'Pillado', 'Taller', '2026-04-15', NULL, NULL, NULL, 100, 'Felipe Rojas', false, false, false, false, false, false, 2, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3344', 'CQBO-3344', 2026, 'TGGF-57', 'FMX 420', 'Volvo FMX420', 'otro', 'Viene de Calama', 'N/A', 'Taller', '2026-04-08', NULL, 702, 15802, 100, 'Sergio Cortes', false, false, false, false, false, false, 22, 44.5, NULL, NULL, 'FRECUENCIA'),
  ('3347', 'CQBO-3347', 2026, 'SVBJ-55', 'VM 350', 'Volvo VM350', 'otro', 'Andacollo', 'RENTAMAQ', 'Taller', '2026-04-07', '2026-04-09', 1318, 24097, 100, 'Joel Coo', false, false, false, false, false, false, 7, 17.0, NULL, NULL, 'FRECUENCIA'),
  ('3345', 'CQBO-3345', 2026, 'DJKL-18', 'Actros 3341', 'M:Benz Actros 3341', 'otro', 'Romeral', 'CMP', 'Taller', '2026-04-06', '2026-04-06', 21213, 214041, 100, 'Joel Coo', false, false, false, false, false, false, 8, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3346', 'CQBO-3346', 2026, 'LCSX-78', 'GU 813 autom', 'Mack GU 813', 'otro', 'Romeral', 'N/A', 'Taller', '2026-03-27', NULL, 9038, 85962, 100, 'Sergio Cortes', false, false, false, false, false, false, 14, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3342', 'CQBO-3342', 2026, 'LKPY-18', 'GU 813 autom', 'Mack GU 813', 'otro', 'Andacollo', 'RENTAMAQ', 'Taller', '2026-03-19', NULL, 6280, 74337, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 11, 26.0, NULL, NULL, 'FRECUENCIA'),
  ('3340', 'CQBO-3340', 2026, 'TGGF-60', 'FMX 540', 'Volvo FMX 540', 'otro', 'Calama', 'Boart longyear', 'Taller', '2026-03-16', NULL, 1267, 16676, 100, 'Sergio Cortes', false, false, false, false, false, false, 20, 38.0, NULL, NULL, 'FRECUENCIA'),
  ('3341', 'CQBO-3341', 2026, 'TRDP-97', 'FMX 420', 'Volvo FMX420', 'otro', NULL, 'Mountain Drilling', 'Taller', '2026-03-16', NULL, 1207, 20643, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 14, 27.0, NULL, NULL, 'FRECUENCIA'),
  ('3343', 'CQBO-3343', 2026, 'FJTJ-60', 'Atego 1624A 4x4', 'M.Benz Atego 1624A', 'otro', 'San Antonio', 'San Antonio', 'Taller', '2026-03-14', '2026-04-14', 4342, 261495, 100, 'Joel Coo', false, false, false, false, false, false, 13, 59.0, NULL, NULL, 'FRECUENCIA'),
  ('3339', 'CQBO-3339', 2026, 'SVBJ-55', 'VM 350', 'Volvo VM 350', 'otro', 'Andacollo', 'Rentamaq', 'Taller', '2026-03-12', NULL, NULL, NULL, 100, 'Sergio Cortes', false, false, false, false, false, false, 5, 19.0, NULL, NULL, 'FRECUENCIA'),
  ('3338', 'CQBO-3338', 2026, 'FSLZ-67', 'Actros 3341', 'M.Benz Actros 3341', 'otro', 'Romeral', 'Romeral', 'Taller', '2026-03-11', NULL, 15503, 127157, 100, 'Joel Coo', false, false, false, false, false, false, 16, 46.0, NULL, NULL, 'FRECUENCIA'),
  ('3331', 'CQBO-3331', 2026, 'JTYK-88', 'Actros 3336 K', 'M.Benz Actros 3336K', 'otro', 'Tambillo', 'GALCEA', 'Taller', '2026-03-04', NULL, 7746, 136245, 100, 'Sergio Cortes', false, false, false, false, false, false, 24, 61.0, NULL, NULL, 'FRECUENCIA'),
  ('3337', 'CQBO-3337', 2026, 'KVWD-27', 'Accelo 1016/44', 'M.Benz Accelo 1016/44', 'otro', 'San Geronimo', 'N/A', 'Taller', '2026-03-04', NULL, 5703, 57910, 100, 'Joel Coo', false, false, false, false, false, false, 8, 19.0, NULL, NULL, 'FRECUENCIA'),
  ('3336', 'CQBO-3336', 2026, 'KVDK-20', 'NP300 Dob Cab', 'Nissan NP300', 'otro', 'N/A', 'Pillado', 'Taller', '2026-03-03', '2026-03-03', NULL, 166033, 100, 'Felipe Rojas', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3332', 'CQBO-3332', 2026, 'HKSR-81', 'Axor 2633', 'M.Benz Axor 2633', 'otro', 'TPC', 'TPC', 'Taller', '2026-03-02', '2026-03-02', 5211, 83278, 100, 'Felipe Rojas', false, false, false, false, false, false, 4, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3334', 'CQBO-3334', 2026, 'FJTJ-60', 'Atego 1624A 4x4', 'M.Benz Atego1624A', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', '2026-03-02', '2026-03-03', 4192, 260862, 100, 'Sergio Cotes', false, false, false, false, false, false, 7, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3329', 'CQBO-3329', 2026, 'RZPC-83', 'T60 4x4 DX', 'Maxus  T60', 'otro', 'CMP', 'CMP', 'CMP', '2026-02-27', NULL, NULL, 101475, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 14, 32.0, NULL, NULL, 'FRECUENCIA'),
  ('3330', 'CQBO-3330', 2026, 'LCSX-78', 'GU 813 autom', 'Mack GR64BX', 'otro', 'CMP', 'CMP', 'Taller', '2026-02-26', '2026-02-27', 8616, 52933, 100, 'Joel Coo', false, false, false, false, false, false, 2, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3335', 'CQBO-3335', 2026, 'FSLZ-67', 'Actros 3341', 'M.Benz Actros 3341', 'otro', 'Romeral', 'CMP', 'Romeral', '2026-02-26', '2026-02-26', 15398, 126482, 100, 'Joel - Yusdel', false, false, false, false, false, false, 2, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3333', 'CQBO-3333', 2026, 'FJTJ-60', 'Atego 1624A 4x4', 'M.Benz Atego 1624A', 'otro', 'San Geronimo', 'San Geronimo', 'San Geronimo', '2026-02-25', '2026-02-25', 4163, 9036, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 1, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3327', 'CQBO-3327', 2026, 'RZPC-83', 'T60 4x4 DX', 'Maxus  T60', 'otro', 'CMP', 'CMP', 'CMP', '2026-02-24', '2026-02-24', NULL, 101423, 100, 'Joel Coo', false, false, false, false, false, false, 1, 3.0, NULL, NULL, 'FRECUENCIA'),
  ('3328', 'CQBO-3328', 2026, 'SVBJ-55', 'VM 350', 'Volvo VM350', 'otro', 'Andacollo', 'RENTAMAQ', 'Andacollo', '2026-02-24', '2026-02-24', 1049, 21749, 100, 'Sergio Cortes', false, false, false, false, false, false, 1, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3324', 'CQBO-3324', 2026, 'SVBJ-55', 'VM 350', 'Volvo VMX 350', 'otro', 'Andacollo', 'Rentamaq', 'Andacollo', '2026-02-20', '2026-02-20', 1045, 21721, 100, 'Sergio Cortres - Felipe R', false, false, false, false, false, false, 1, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3323', 'CQBO-3323', 2026, 'SVCZ-38', 'VM 350', 'Volvo VM350', 'otro', 'Andacollo', 'Rentamaq', 'Andacollo', '2026-02-19', '2026-02-19', 3824, 62610, 100, 'Sergio- Felipe R.', false, false, false, false, false, false, 1, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3325', 'CQBO-XXXX', 2026, 'DCHD-83', NULL, NULL, 'otro', 'N/A', 'Pillado', 'Talleres Pillado', '2026-02-18', NULL, NULL, NULL, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 3, 10.0, NULL, NULL, 'FRECUENCIA'),
  ('3321', 'CQBO-3321', 2026, 'FJTJ-60', 'Atego 1624A 4x4', 'M. Benz Atego 1624A', 'otro', 'San Geronimo', 'San Geronimo', 'San Geronimo', '2026-02-17', '2026-02-17', 4043, 26030, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 1, 2.0, NULL, NULL, 'FRECUENCIA'),
  ('3319', 'CQBO-319', 2026, 'DJKL-18', 'Actros 3341', 'M.Benz Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2026-02-16', '2026-02-18', 21051, 213188, 100, 'Joel Coo', false, false, false, false, false, false, 9, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3320', 'CQBO-3320', 2026, 'N/A', NULL, 'N/A', 'otro', 'Dominga', 'Dominga', 'Dominga', '2026-02-16', '2026-02-16', NULL, NULL, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3318', 'CQBO-3318', 2026, 'RZPC-83', 'T60 4x4 DX', 'Maxus T60', 'otro', 'Romeral', 'Pillado', 'Romeral', '2026-02-13', '2026-02-13', NULL, 100968, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 3, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3317', 'CQBO-3317', 2026, 'JTYK-88', 'Actros 3336 K', 'M. Benz Actros 3336', 'otro', 'DSS', 'DSS', 'Taller', '2026-02-10', NULL, 7629, 133950, 100, 'Sergio Cortes', false, false, false, false, false, false, 13, 27.0, NULL, NULL, 'FRECUENCIA'),
  ('3316', 'CQBO-3316', 2026, 'KVWD-27', 'Accelo 1016/44', 'M.Benz Acceli 1016', 'otro', 'San Geronimo', 'Pillado', 'Taller', '2026-02-09', NULL, 5629, 57535, 100, 'Sergio Cortes', false, false, false, false, false, false, 6, 11.0, NULL, NULL, 'FRECUENCIA'),
  ('3313', 'CQBO-3313', 2026, 'GGHB-32', 'GU813E Mec', 'Mack GU813E', 'otro', 'Tambillo', 'Galcea', 'Taller', '2026-02-06', NULL, 9433, 115679, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 24, 80.0, NULL, NULL, 'FRECUENCIA'),
  ('3314', 'CQBO-3314', 2026, 'FSLZ-67', 'Actros 3336 K', 'M.Benz Actros', 'otro', 'Romera', 'Romeral', 'Taller', '2026-02-06', '2026-02-06', NULL, 125423, 100, 'Joel Coo', false, false, false, false, false, false, 1, 3.0, NULL, NULL, 'FRECUENCIA'),
  ('3315', 'CQBO-3315', 2026, 'DJKL-18', 'Actros 3341', 'M. Benz', 'otro', 'Romeral', 'Romeral', 'Romeral', '2026-02-05', '2026-02-05', 21035, 213081, 100, 'Joel Coo', false, false, false, false, false, false, 1, 3.0, NULL, NULL, 'FRECUENCIA'),
  ('3310', 'CQBO-3310', 2026, 'FJTJ-60', 'Atego 1624A 4x4', 'M. Benz Atego 1624A', 'otro', 'San Gerónimo', 'San Gerónimo', 'Taller', '2026-02-04', NULL, 3890, 259757, 100, 'Sergio Cortes', false, false, false, false, false, false, 8, 20.0, NULL, NULL, 'FRECUENCIA'),
  ('3311', 'CQBO-3311', 2026, 'LCSX-78', 'GU 813 autom', 'Mack GR64BX', 'otro', 'N/A', 'Pillado', 'Taller', '2026-02-03', '2026-02-16', 8896, 52664, 100, 'Joel Coo', false, false, false, false, false, false, 11, 50.5, NULL, NULL, 'FRECUENCIA'),
  ('3312', 'CQBO-3312', 2026, 'FSLZ-67', 'Actros 3341', 'M. Benz Actros 3341', 'otro', 'Romeral', 'Romeral', 'Romeral', '2026-02-03', '1900-01-03', 15180, 125234, 100, 'Joel Coo', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3308', 'CQBO-3308', 2026, 'LKPY-18', 'GU 813 autom', 'MACK GR64BX', 'otro', 'N/A', 'Pillado', 'Taller', '2026-02-02', NULL, 6257, 74080, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 9, 29.0, NULL, NULL, 'FRECUENCIA'),
  ('3304', 'CQBO-3304', 2026, 'DJKL-18', 'Actros 3341', 'M. Benz Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2026-01-28', '2026-01-28', 21016, 212970, 100, 'Joel Coo', false, false, false, false, false, false, 3, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3302', 'CQBO-3302', 2026, 'JGBY-10', 'Axor 2633', 'M.Benz Axor 2633', 'otro', 'Faena Sobek, Copiapó', 'Drilling service and', 'Taller', '2026-01-27', '2026-01-27', 8659, 98373, 100, 'Sergio Cortes', false, false, false, false, false, false, 4, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3303', 'CQBO-3303', 2026, 'DJKL-18', 'Actros 3341', 'M. Benz / Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2026-01-27', NULL, 21016, 212970, 100, 'Joel Coo', false, false, false, false, false, false, 2, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3305', 'CQBO-3305', 2026, 'GGHB-32', 'GU 813 autom', 'MACK GU813 E', 'otro', 'Tambillo', 'GALCECA', 'Taller', '2026-01-27', NULL, 9425, 115554, 100, 'Sergio Cortes', false, false, false, false, false, false, 12, 28.0, NULL, NULL, 'FRECUENCIA'),
  ('3307', 'CQBO-3307', 2026, 'RSCY-85', 'Accelo 1016/44', 'M.Benz Accelo 1016', 'otro', 'N/A', 'Pillado', 'Taller', '2026-01-26', NULL, 3861, 125617, 100, 'Sergio Cortez', false, false, false, false, false, false, 27, 62.0, NULL, NULL, 'FRECUENCIA'),
  ('3299', 'CQBO-3299', 2026, 'DCHD-83', 'Canter 7.5', 'MITSUBISHI CANTER', 'otro', 'Uso interno', 'Pillado', 'Taller', '2026-01-23', NULL, 58.3, 102414, 100, 'Felipe Rojas', false, false, false, false, false, false, 7, 24.0, NULL, NULL, 'FRECUENCIA'),
  ('3297', 'CQBO-3297', 2026, 'FSLZ-67', 'Actros 3341', 'M.Benz Actros 3341', 'otro', 'Romeral', 'Pillado', 'Resortes Estadio', '2026-01-20', NULL, 15131, 124912, 100, 'Joel Coo', false, false, false, false, false, false, 4, 54.0, NULL, NULL, 'FRECUENCIA'),
  ('3293', 'CQBO-3293', 2026, 'DJKL-18', 'Actros 3341', 'M.Benz Actros 3341', 'otro', 'Romaral', 'Pillado', 'Taller', '2026-01-19', NULL, 20981, 212699, 100, 'Joel Coo - Yusdel Sarduy', false, false, false, false, false, false, 16, 44.0, NULL, NULL, 'FRECUENCIA'),
  ('3294', 'CQBO-3294', 2026, 'TRSS-16', 'P450B', 'SCANIA P450', 'otro', 'N/A', 'Pillado', 'Taller', '2026-01-19', NULL, 524, 10892, 100, 'Sergio Cortes', false, false, false, false, false, false, 7, 17.5, NULL, NULL, 'FRECUENCIA'),
  ('3301', 'CQBO-3301', 2026, 'FJTJ-60', 'Actros 3336 K', 'M. Benz Actros', 'otro', 'San Geronimo', 'San Geronimo', 'San Geronimo', '2026-01-16', NULL, 3645, 258882, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 1, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3300', 'CQBO-XXXX', 2026, 'TRDP-97', 'FMX 420', 'VOLVO FMX 420', 'otro', 'Cupita', 'Muonting Drilling', 'Taller', '2026-01-14', NULL, 1108, 17042, 100, 'Sergio Cortez', false, false, false, false, false, false, 6, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3291', 'CQBO-3291', 2026, 'KVWD-27', 'Accelo 1016/44', 'M. Benz Accelo 1016', 'otro', 'Guayacan', 'Pillado', 'Taller', '2026-01-13', NULL, 5593, 57316, 100, 'Sergio Cortes', false, false, false, false, false, false, 2, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3296', 'CQBO-3296', 2026, 'FJTJ-61', 'Atego 1624A 4x4', 'M. Benz Atego 1624A', 'otro', 'N/A', 'Pillado', 'Taller', '2026-01-13', NULL, 3574, 46656, 100, 'Sergio Cortes', false, false, false, false, false, false, 4, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3289', 'CQBO-3289', 2026, 'JKPY-19', 'GU 813 autom', 'MACK GR64BX', 'otro', 'N/A', 'Pillado', 'Taller', '2026-01-12', NULL, 644, 9567, 100, 'Sergio C. - Felipe R.', false, false, false, false, false, false, 4, 7.0, NULL, NULL, 'FRECUENCIA'),
  ('3286', 'CQBO-3286', 2026, 'RZPC-83', 'T60 4x4 DX', 'Maxus', 'otro', 'Romeral', 'Pillado', 'Taller', '2026-01-08', NULL, NULL, 99731, 0, 'Joel-Yusdel-Felipe R.', false, false, false, false, false, false, 10, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3288', 'CQBO-3288', 2026, 'JGBY-10', 'Axor 2633', 'M. Benz Axor 2633', 'otro', 'Famesa', 'Famesa', 'Famesa', '2026-01-06', NULL, NULL, 14639, 100, 'Yusdel Sarduy', false, false, false, false, false, false, 12, 18.5, NULL, NULL, 'FRECUENCIA'),
  ('3285', 'CQBO-3285', 2025, 'FSLZ-67', 'Actros 3341', 'M. Benz Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2026-01-05', NULL, 15097, 124619, 0, 'Joel Coo - Felipe Rojas', false, false, false, false, false, false, 18, 47.0, NULL, NULL, 'FRECUENCIA'),
  ('3287', 'CQBO-3297', 2025, 'SVBJ-55', 'VM 350', 'Volvo VM 350', 'otro', 'Andacollo', 'Rentamaq', 'Andacollo', '2025-12-30', NULL, 766, 18747, 100, 'Sergio C. y Felipe R.', false, false, false, false, false, false, 1, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3115T', 'CQBO-3115T', 2025, 'SVBJ-55', 'VM 350', 'VOLVO VMX 350', 'otro', 'LOMAS BAYAS', 'GODIESEL', 'SIERRA GORDA', '2025-12-24', NULL, NULL, NULL, 100, 'JAIME ROJAS / Volvo Calam', false, false, false, false, false, false, 13, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3283', 'CQBO-3283', 2025, 'DJKL-18', 'Actros 3341', 'M.B. Actros 341', 'otro', 'CMP', 'Pillado', 'Taller', '2025-12-24', NULL, 20836, 211765, 0, 'Joel Coo - Yusdel Sarduy', false, false, false, false, false, false, 24, 80.5, NULL, NULL, 'FRECUENCIA'),
  ('3282', 'CQBO-3282', 2025, 'SVCZ-38', 'VM 350', 'Volvo VM-350', 'otro', 'Andacollo', 'RENTAMAQ', 'Andacollo', '2025-12-23', NULL, 3481, 59299, 0, 'Sergio Cortes - Felipe Ro', false, false, false, false, false, false, 1, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3295', 'CQBO-3295', 2026, 'GCHT-12', 'GU813E Mec', 'MACK-GU813E', 'otro', 'Tampillo', 'Galcea', 'Taller', '2025-12-22', NULL, 7669, 110251, 100, 'Marcos Diaz', false, false, false, false, false, false, 4, 10.0, NULL, NULL, 'FRECUENCIA'),
  ('3280', 'CQBO-3280', 2025, 'KVDK-20', 'NP300 Dob Cab', 'Nissan NP-300', 'otro', 'Pillado', 'Pillado', 'Taller', '2025-12-22', NULL, NULL, 164217, 0, 'Felipe Rojas', false, false, false, false, false, false, 1, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3281', 'CQBO-3281', 2025, 'SLRK-82', 'Berlingo K9 1.6 Diesel', 'Citroen-Berlingo K9', 'otro', 'Pillado', 'Pillado', 'Taller', '2025-12-22', NULL, NULL, 63976, 0, 'Sergio Cortes', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3278', 'CQBO-3278', 2025, 'LKPY-18', 'GU 813 autom', 'MACK GR64BX', 'otro', 'Caserones', 'TPM', 'Taller', '2025-12-21', NULL, NULL, NULL, 0, 'Yusdel', false, false, false, false, false, false, 12, 39.0, NULL, NULL, 'FRECUENCIA'),
  ('3284', 'CQBO-3284', 2025, 'GGHB-32', 'GU 813 autom', 'MACK GU813', 'otro', 'Tambillo', 'Galcea', 'Tambillo', '2025-12-19', NULL, 9369, 113499, 0, 'Sergio Cortes', false, false, false, false, false, false, 2, 10.0, NULL, NULL, 'FRECUENCIA'),
  ('3273', 'CQBO-3273', 2025, 'FSLZ-67', 'Actros 3341', 'M.B. Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2025-12-12', NULL, 14997, 124012, 0, 'Sergio Cortes', false, false, false, false, false, false, 16, 59.5, NULL, NULL, 'FRECUENCIA'),
  ('3277', 'CQBO-3277', 2025, 'TRDP-97', 'FMX 420', 'Volvo  FMX 420', 'otro', 'Taller', 'Pillado', 'Taller', '2025-12-11', NULL, 1102, 16964, 0, 'Felipe Rojas', false, false, false, false, false, false, 3, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3272', 'CQBO-3272', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'M.B. Atego', 'otro', NULL, NULL, NULL, '2025-12-10', NULL, 3198, 257144, 0, 'Joel Coo', false, false, false, false, false, false, 8, 14.5, NULL, NULL, 'FRECUENCIA'),
  ('3276', 'CQBO-3276', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'M.B. ATEGO', 'otro', 'SanGeronimo', 'San Geronimo', 'San Geronimo- taller', '2025-12-09', '2025-12-12', 3200, 257171, 0, 'Joel Coo', false, false, false, false, false, false, 5, 16.0, NULL, NULL, 'FRECUENCIA'),
  ('3271', 'CQBO-3271', 2025, 'KVWD-27', 'Accelo 1016/44', 'M.B. Accelo1016', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', '2025-12-04', NULL, 5564, 57085, 0, 'Joel Coo', false, false, false, false, false, false, 12, 20.0, NULL, NULL, 'FRECUENCIA'),
  ('3275', 'CQBO-3275', 2025, 'KVWD-27', 'Accelo 1016/44', 'M.B. ACCELO', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', '2025-12-03', NULL, 5566, 57113, 0, NULL, false, false, false, false, false, false, 14, 29.0, NULL, NULL, 'FRECUENCIA'),
  ('3269', 'CQBO-3269', 2025, 'FJTJ-60', NULL, NULL, 'otro', 'San Geronimo', 'San Geronimo', 'Taller', '2025-11-24', NULL, 3082, 236515, 0, 'Sergio-Felipe R.', false, false, false, false, false, false, 10, 34.0, NULL, NULL, 'FRECUENCIA'),
  ('3268', 'CQBO-3268', 2025, 'DJKL-18', 'Actros 3341', 'M. Benz Actros 3341', 'otro', 'Romeral', 'Pillado', 'Taller', '2025-11-20', NULL, 20679, 210766, 0, 'Joel Coo - Yusdel Sarduy', false, false, false, false, false, false, 20, 94.0, NULL, NULL, 'FRECUENCIA'),
  ('3270', 'CQBO-3270', 2025, 'JGBY-10', 'Axor 2633', 'M. Benz AXOR 2633', 'otro', NULL, NULL, NULL, '2025-11-20', NULL, 8622, 97234, 0, 'Sergio - Felipe R.', false, false, false, false, false, false, 19, 47.0, NULL, NULL, 'FRECUENCIA'),
  ('3260', 'CQBO-3260', 2025, 'GGHB-12', NULL, NULL, 'otro', 'N/A', 'Pillado', 'Taller', '2025-11-07', NULL, NULL, NULL, 0, 'Yusdel Sarduy', false, false, false, false, false, false, 5, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3262', 'CQBO-3262', 2025, 'GCSY-66', '02-7FDA50', 'Toyota', 'otro', 'Taller', 'Pillado', 'Taller', '2025-11-07', '2026-11-07', NULL, NULL, 0, 'Joel Coo', false, false, false, false, false, false, 3, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3257', 'CQBO-3258', 2025, 'RZPC-83', 'T60 4x4 DX', 'MAXUS', 'otro', 'Romeral', 'Pillado', 'Taller', '2025-11-05', NULL, NULL, 96488, 0, 'Sergio Cortes', false, false, false, false, false, false, 9, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3258', 'CQBO-3258', 2025, 'RZPC-83', 'T60 4x4 DX', 'MAXUS', 'otro', 'Romeral', 'Pillado', 'Taller', '2025-11-05', NULL, NULL, 96488, 0, 'Sergio Cortes', false, false, false, false, false, false, 9, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3259', 'CQBO-3259', 2025, 'SBPG-12', 'New Hilux 4x4 2.4 MT DX', 'Toyota- Hilux', 'otro', 'Salvador', NULL, 'Taller AV. Copiapo T', '2025-11-05', NULL, NULL, 17131, 0, 'Yusdel Sarduy', false, false, false, false, false, false, 19, 36.0, NULL, NULL, 'FRECUENCIA'),
  ('3255', 'CQBO-3255', 2025, 'LCSX-78', 'GU 813 autom', 'Mack Granite', 'otro', 'Coquimbo', 'Pillado', 'Taller', '2025-10-28', NULL, 8781, 83927, 0, 'Felipe Lopez', false, false, false, false, false, false, 6, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3254', 'CQBO-3254', 2025, 'KVWD-27', NULL, NULL, 'otro', 'San Geronimo', 'Pillado', 'Taller', '2025-10-27', NULL, NULL, NULL, 0, 'Joel Coo', false, false, false, false, false, false, 19, 74.0, NULL, NULL, 'FRECUENCIA'),
  ('3251', 'CQBO-3251', 2025, 'KVWW-69', 'Actros 3336 K', 'Actros 3336K', 'otro', 'Calama', 'Calama', 'Taller', '2025-10-07', NULL, 6663, 89730, 0, 'Sergio Cortes', false, false, false, false, false, false, 27, 73.0, NULL, NULL, 'FRECUENCIA'),
  ('3252', 'CQBO-3252', 2025, 'FSLZ-67', NULL, NULL, 'otro', 'Romeral', 'Romeral', 'Taller', '2025-10-07', NULL, NULL, NULL, 0, 'Sergio Cortes', false, false, false, false, false, false, 16, 42.0, NULL, NULL, 'FRECUENCIA'),
  ('3249', 'CQBO-3249', 2025, 'HHWB-44', 'GU 813 autom', 'Mack Granite GU813E', 'otro', 'Franke', 'Pillado', 'Taller', '2025-09-29', NULL, 24233, 183263, 0, 'Luis Montt', false, false, false, false, false, false, 43, 130.0, NULL, NULL, 'FRECUENCIA'),
  ('3249', 'CQBO-3249', 2025, 'HHWB-44', 'GU 813 autom', 'Mack Granite GU813E', 'otro', 'Franke', 'Pillado', 'Taller', '2025-09-29', NULL, 24233, 183263, 0, 'Joel-Yusdel Sergio', false, false, false, false, false, false, 43, 130.0, NULL, NULL, 'FRECUENCIA'),
  ('3244', 'CQBO-3244', 2025, 'DJKL-18', 'Actros 3341', 'Actros 3341', 'otro', 'Romeral', 'Romeral', 'Taller', '2025-09-15', NULL, 20345, 208609, 0, 'Luis -Yusdel-Cesar-Joel', false, false, false, false, false, false, 13, 32.5, NULL, NULL, 'FRECUENCIA'),
  ('3241', 'CQBO-3241', 2025, 'LCSX-78', 'GU 813 autom', 'Mack GR 65BX', 'otro', 'Pillado', 'Pillado', 'Taller', '2025-08-21', NULL, 8723, 82719, 0, 'Luis Montt', false, false, false, false, false, false, 16, 51.5, NULL, NULL, 'FRECUENCIA'),
  ('3239', 'CQBO-3239', 2025, 'HHWB-42', 'GU 813 autom', 'Granite', 'otro', 'Pillado & CIA. LTDA.', 'Pillado & CIA. LTDA.', 'Taller', '2025-08-15', NULL, 22318, 163463, 0, 'Luis Montt', false, false, false, false, false, false, 30, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3237', 'CQBO-3237', 2025, 'JGBY-10', 'Axor 2633', 'Mecedes Axor', 'otro', NULL, 'Pillado', NULL, '2025-08-06', NULL, 8162, 193273, 0, 'Luis Mnontt', false, false, false, false, false, false, 27, 56.0, NULL, NULL, 'FRECUENCIA'),
  ('3236', 'CQBO-3226', 2025, 'GGHB-32', 'GU 813 autom', 'Mack/Granite GU813', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', '2025-08-04', NULL, 9258, 112555, 0, 'Joel Coo', false, false, false, false, false, false, 20, 45.0, NULL, NULL, 'FRECUENCIA'),
  ('3235', 'CQBO-3235', 2025, 'KVWD-27', 'Accelo 1016/44', 'Accelo 1016', 'otro', 'Uso Interno', 'Taller', 'Taller', '2025-07-24', NULL, 4852, 8346, 0, 'Cesasr Ahumada', false, false, false, false, false, false, 15, 34.0, NULL, NULL, 'FRECUENCIA'),
  ('3232', 'CQBO-3232', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'Mercedes B / Atego 1624', 'otro', 'San Geronimo', 'Minera San Geronimo', 'Taller', '2025-07-11', NULL, 2023, 251939, 0, 'Joel Coo', false, false, false, false, false, false, 28, 66.0, NULL, NULL, 'FRECUENCIA'),
  ('3233', 'CQBO-3233', 2025, 'LCSX-78', 'GU 813 autom', 'Mack Granite GU 813', 'otro', 'CMP Romeral', 'CMP Romeral', 'Taller', '2025-07-11', NULL, 8704, 82512, 0, 'Yusdel / Cesar', false, false, false, false, false, false, 11, 13.0, NULL, NULL, 'FRECUENCIA'),
  ('3231', 'CQBO-3231', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'Mercedes B/Atego1624A', 'otro', 'San Gerónimo', 'San Gerónimo', 'Taller', '2025-07-10', NULL, 3460, 45883, 0, 'Yusdel', false, false, false, false, false, false, 9, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3228', 'CQBO-3228', 2025, 'LCSX-78', 'GU 813 autom', 'Mack / Granite', 'otro', 'CMP Romeral', 'CMP', 'Garita', '2025-06-28', '2025-06-28', 8691, 82436, 0, 'Felipe', false, false, false, false, false, false, 1, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3227', 'CQBO-3227', 2025, 'RZPC-83', 'T60 4x4 DX', 'Maxus', 'otro', 'Romeral', NULL, 'Taller', '2025-06-26', NULL, NULL, 85909, 0, 'Cesar', false, false, false, false, false, false, 3, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3230', 'CQBO-3230', 2025, 'JTYK-88', 'Actros 3336 K', 'M.Benz/Actros 3336K', 'otro', 'San Gerónimo', NULL, 'San Gerónimo', '2025-06-26', NULL, 7141, 127826, 0, 'Luis Montt', false, false, false, false, false, false, 31, 132.0, NULL, NULL, 'FRECUENCIA'),
  ('3223', 'CQBO-3223', 2025, 'DJKL-18', 'Actros 3336 K', 'Mercedes / Actros', 'otro', 'Romeral', NULL, NULL, '2025-06-25', NULL, 6037, 206202, 0, 'Yusdel- Cesar', false, false, false, false, false, false, 23, 81.0, NULL, NULL, 'FRECUENCIA'),
  ('3226', 'CQBO-3226', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'Mercedes / Atego', 'otro', 'San Geronimo', NULL, 'San Geronimo', '2025-06-24', '2025-06-24', 874, 250842, 0, 'Yusdel', false, false, false, false, false, false, 1, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3219', 'CQBO-3219', 2025, 'KVDK-20', 'NP300 Dob Cab', 'NISSAN NP 300 4x4', 'otro', NULL, NULL, NULL, '2025-06-18', '2025-06-18', NULL, 152047, 0, 'Cesar Ahumada', false, false, false, false, false, false, 1, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3220', 'CQBO-3220', 2025, 'FSLZ-67', 'Actros 3336 K', 'Mercedes Benz/Actros', 'otro', 'Romeral', NULL, 'Taller', '2025-06-16', NULL, 5317, 121883, 0, 'Joel Coo', false, false, false, false, false, false, 17, 42.0, NULL, NULL, 'FRECUENCIA'),
  ('3218', 'CQBO-3218', 2025, 'KVWD-27', 'Accelo 1016/44', 'Mercedes Benz / Acelo', 'otro', 'San Geronimo', 'San Geronimo', NULL, '2025-06-11', NULL, 4821, 8121, 0, 'Cesar', false, false, false, false, false, false, 9, 20.5, NULL, NULL, 'FRECUENCIA'),
  ('3215', 'CQBO-3215', 2025, 'KCBY-30', 'Actros 3336 K', 'ACTROS 3336K', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', '2025-06-04', NULL, NULL, NULL, 0, 'CESAR - JOEL - LUIS', false, false, false, false, false, false, 9, 59.0, NULL, NULL, 'FRECUENCIA'),
  ('3216', 'CQBO-3216', 2025, 'SVBJ-57', 'VM 350', 'VOLVO / VM 350', 'otro', 'LOS BRONCES / LOS ANDES', 'ORBIT GARANT', 'SANTIAGO', '2025-06-02', NULL, 1592, 19547, 0, NULL, false, false, false, false, false, false, 3, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3212', 'CQBO-3212', 2025, 'SVCZ-38', 'VM 350', 'VOLVO VMX', 'otro', 'SAN GERÓNIMO', 'PILLADO', NULL, '2025-05-29', NULL, 3270, 56885, 0, 'Cesar Ahunada', false, false, false, false, false, false, 3, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3214', 'CQBO-3214', 2025, 'SBPG-12', 'New Hilux 4x4 2.4 MT DX', 'TOYOTA HILUX', 'otro', 'ANDINA', 'BOART LONGYEAR', NULL, '2025-05-29', NULL, NULL, 11861, 0, 'YUSDEL + CESAR + JOEL', false, false, false, false, false, false, 11, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3213', 'CQBO-3213', 2025, 'PRET-APAII', NULL, 'Gilbarco JH1500', 'otro', 'Romeral', 'Esmax', NULL, '2025-05-28', NULL, 113922, NULL, 0, 'Felipe López + Miguel Vel', false, false, false, false, false, false, 9, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3211', 'CQBO-3211', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'Mercedes Benz Atego 1624', 'otro', 'San Gerónimo', NULL, NULL, '2025-05-27', NULL, 1608, 249936, 0, 'Joel Coo', false, false, false, false, false, false, 24, 45.5, NULL, NULL, 'FRECUENCIA'),
  ('3208', 'CQBO-3207', 2025, 'LCSX-78', 'GU 813 autom', 'MACK', 'otro', NULL, 'PILLADO', 'TALLER PILLADO', '2025-05-22', NULL, NULL, NULL, 100, 'YUSDEL + CESAR + JOEL', false, false, false, false, false, false, 3, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3209', 'CQBO-3209', 2025, 'SBPG-12', 'New Hilux 4x4 2.4 MT DX', 'TOYOTA HILUX', 'otro', 'ANDINA', 'BOART LONGYEAR', NULL, '2025-05-22', NULL, NULL, 11861, 0, 'JOEL + YUSDEL + CESAR', false, false, false, false, false, false, 13, 19.0, NULL, NULL, 'FRECUENCIA'),
  ('3207', 'CQBO-3207', 2025, 'HKSR-81', 'Axor 2633', 'AXOR', 'otro', NULL, 'PILLADO', 'TALLER PILLADO', '2025-05-20', NULL, 5112, 82385, 100, 'HERNÁN + CÉSAR', false, false, false, false, false, false, 5, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3206', 'CQBO-3206', 2025, 'GCHT-12', 'GU 813 autom', 'MACK GU813', 'otro', NULL, 'PILLADO', 'TALLER PILLADO', '2025-05-19', NULL, 7637, 109872, 0, 'HERNÁN + CÉSAR', false, false, false, false, false, false, 9, 22.0, NULL, NULL, 'FRECUENCIA'),
  ('3210', 'CQBO-3210', 2025, 'LKPY-22', 'GU 813 autom', 'MACK / GU816E', 'otro', NULL, NULL, NULL, '2025-05-16', NULL, 10313, 85520, 0, NULL, false, false, false, false, false, false, 22, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3205', 'CQBO-3205', 2025, 'GGHB-32', 'GU813E Mec', 'MACK GU813E', 'otro', 'Galcea', NULL, NULL, '2025-05-15', NULL, 108969, 9042, 0, NULL, false, false, false, false, false, false, 24, 26.0, NULL, NULL, 'FRECUENCIA'),
  ('3201', 'CQBO-3201', 2025, 'JTYK-88', 'Actros 3336 K', 'M.Benz Actros 3336 K', 'otro', 'San Geronimo', NULL, 'Taller Mecanico Pill', '2025-05-12', NULL, 6911, 123615, 55, 'JOEL + YUSDEL', false, false, false, false, false, false, 25, 55.0, NULL, NULL, 'FRECUENCIA'),
  ('3212', 'CQBO-3212', 2025, 'LKPY-18', 'GU 813 autom', 'MACK 7 GRANITE', 'otro', NULL, NULL, NULL, '2025-05-07', NULL, 6187, 72363, 0, 'Yusdel', false, false, false, false, false, false, 29, 164.5, NULL, NULL, 'FRECUENCIA'),
  ('3197', 'CQBO-3197', 2025, 'FSLZ-67', 'Actros 3341', 'ACTROS 3341', 'otro', 'ROMERAL', 'PILLADO', 'LA SERENA', '2025-05-02', NULL, 1467, 121756, 100, 'LÓPEZ + YUSDEL', false, false, false, false, false, false, 5, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3195', 'CQBO-3195', 2025, 'JGBY-10', 'Axor 2633', 'AXOR', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', '2025-04-28', NULL, 8052, 92429, 0, 'HERNÁN + CESAR', false, false, false, false, false, false, 52, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3193', 'CQBO-3193', 2025, 'JTYK-88', 'Actros 3336 K', 'ACTROS', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-04-25', '2025-04-25', 6734, 120504, 100, 'HERNÁN + CÉSAR', false, false, false, false, false, false, 3, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3191', 'CQBO-3191', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-04-22', '2025-04-22', 1937, 247604, 100, 'HERNÁN + CESAR', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3183', 'CQBO-3183', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'Atego', 'otro', 'SAN ANTONIO', 'SAN GERONIMO', 'TALLER', '2025-04-07', NULL, 247075, 1215, 100, 'Hernan Cortes y Carlos Fu', false, false, false, false, false, false, 8, 33.0, NULL, NULL, 'FRECUENCIA'),
  ('3181', 'CQBO-3181', 2025, 'DCHD-83', 'Canter 7.5', 'CANTER', 'otro', NULL, 'TALLER', 'TALLER', '2025-04-04', NULL, 9930, 99880, 100, 'Hernan Cortes', false, false, false, false, false, false, 9, 13.0, NULL, NULL, 'FRECUENCIA'),
  ('3182', 'CQBO-3182', 2025, 'ESMAX-ROM', NULL, 'Viking ak4195', 'otro', 'Romeral', 'Esmax', 'Romeral', '2025-04-04', '2025-04-04', NULL, NULL, 100, 'FELIPE LÓPEZ', false, false, false, false, false, false, 19, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3179', 'CQBO-3179', 2025, 'FSLZ-67', 'Actros 3341', 'MER. BENZ/ACTROS 3341', 'otro', 'ROMERAL', 'CMP', NULL, '2025-04-01', '2025-04-04', 14607, 121338, 100, 'Felipe Lopez y Hernan Cor', false, false, false, false, false, false, 19, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3178', 'CQBO-3178', 2025, 'SPRY-29', 'Berlingo K9 1.6 Diesel', 'CITROEN', 'otro', 'TALLER', NULL, NULL, '2025-03-31', NULL, NULL, 52243, 100, 'Hernan Cortes', false, false, false, false, false, false, 7, 5.5, NULL, NULL, 'FRECUENCIA'),
  ('3180', 'CQBO-3180', 2025, 'DJKL-18', 'Actros 3341', 'ACTROS 3341', 'otro', 'ROMERAL', 'CMP', NULL, '2025-03-31', '2025-03-31', 19569, 203308, 100, 'Hernan Cortes y Felipe Lo', false, false, false, false, false, false, 5, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3176', 'CQBO-3176', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO 1624', 'otro', 'san antonio', 'san geronimo', NULL, '2025-03-28', NULL, 1167, 247024, 100, 'Carlos Fuentes y Pedro Ve', false, false, false, false, false, false, 4, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3177', 'CQBO-3177', 2025, 'KVWD-27', 'Accelo 1016/44', 'ACCELO/1016', 'otro', 'San Antonio', 'San Geronimo', NULL, '2025-03-28', '2025-03-28', 4367, 50991, 100, 'Carlos Fuentes y Pedro Ve', false, false, false, false, false, false, 5, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3175', 'CQBO-3175', 2025, 'DJKL-18', 'Actros 3341', 'ACTROS 3341', 'otro', 'ROMERAL', 'CMP', NULL, '2025-03-27', '2025-03-28', 19566, 203271, 100, 'Hernan Cortes', false, false, false, false, false, false, 17, 20.5, NULL, NULL, 'FRECUENCIA'),
  ('3174T', 'CQBO-3174', 2025, 'HHWB-44', 'GU 813 autom', 'MACK', 'otro', 'FRANCKE', NULL, 'COPIAPO', '2025-03-26', NULL, NULL, NULL, 100, 'Hugo Settra', false, false, false, false, false, false, 9, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3169', 'CQBO-3169', 2025, 'HZSF-21', NULL, 'Chevrolet/ npr816', 'otro', 'Terminal Puerto Coquimbo', 'TPC', 'Coquimbo', '2025-03-20', NULL, NULL, 5260, 100, 'Hernan Cortes', false, false, false, false, false, false, 19, 26.0, NULL, NULL, 'FRECUENCIA'),
  ('3171T', 'CQBO-3171', 2025, 'KCBY-30', 'Actros 3336 K', 'ACTROS 3336K', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', '2025-03-19', NULL, NULL, 51148, 0, 'HERNAN', false, false, false, false, false, false, 79, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3170', 'CQBO-3170', 2025, 'ESMAX-ROM', NULL, NULL, 'otro', 'Romeral', 'Esmax', 'la Serena', '2025-03-18', NULL, NULL, NULL, 100, 'Felipe López', false, false, false, false, false, false, 8, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3167', 'CQBO-3167', 2025, 'RSCY-86', 'Accelo 1016/44', 'ACCELO', 'otro', NULL, NULL, 'Taller', '2025-03-17', NULL, NULL, NULL, 100, 'VPARABRISAS', false, false, false, false, false, false, 1, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3168', 'CQBO-3168', 2025, 'JTYK-88', 'Actros 3336 K', 'ACTROS', 'otro', NULL, 'San Geronimo', 'San Antonio', '2025-03-17', NULL, 6580, 117859, 100, 'Felipe Lopez y Jorge Agui', false, false, false, false, false, false, 19, 40.0, NULL, NULL, 'FRECUENCIA'),
  ('3165', 'CQBO-3165', 2025, 'ESMAX-ROM', NULL, 'bimodal', 'otro', 'ROMERAL', NULL, NULL, '2025-03-14', NULL, NULL, NULL, 100, 'FELIPE LÓPEZ', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3166', 'CQBO-3166', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-03-14', NULL, 104, 246496, 100, 'HERNÁN + PEDRO', false, false, false, false, false, false, 5, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3162', 'CQBO-3162', 2025, 'JTYK-88', 'Actros 3336 K', 'ACTROS 3336K', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-03-06', NULL, 6472, 116030, 100, 'HERNAN + PEDRO', false, false, false, false, false, false, 5, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3163', 'CQBO-3163', 2025, 'GCHT-12', 'GU 813 autom', 'MACK GU813', 'otro', 'TALLER PILLADO', 'PILLADO', 'TALLER PILLADO', '2025-03-06', NULL, 7382, 106587, 100, 'LÓPEZ', false, false, false, false, false, false, 4, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3156T', 'CQBO-3156T', 2025, 'SVBJ-57', 'VM 350', 'VOLVO VMX', 'otro', NULL, NULL, NULL, '2025-02-26', NULL, 1507, 18312, 100, 'VOLVO LA SERENA / Lopez/ ', false, false, false, false, false, false, 23, 42.0, NULL, NULL, 'FRECUENCIA'),
  ('3159', 'CQBO-3159', 2025, 'GGHB-32', 'GU 813 autom', 'MACK GU813', 'otro', 'TAMBILLOS', 'GALCEA', 'COQUIMBO', '2025-02-26', '2025-02-27', NULL, NULL, 100, 'FELIPE/ CARLOS/PEDRO', false, false, false, false, false, false, 8, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3157', 'CQBO-3157', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO 4X4', 'otro', 'SAN ANTONIO', 'SAN GERPONIMO', 'LAMBERT', '2025-02-25', NULL, NULL, NULL, 100, 'CARLOS+PEDRO+MIGUEL', false, false, false, false, false, false, 7, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3158', 'CQBO-3158', 2025, 'FSLZ-67', 'Actros 3336 K', 'ACTROS', 'otro', 'ROMERAL', 'PILLADO', 'LA SERENA', '2025-02-25', NULL, 14548, 120841, 100, 'HERNAN CORTES', false, false, false, false, false, false, 6, 18.0, NULL, NULL, 'FRECUENCIA'),
  ('3155', 'CQBO-3155', 2025, 'KVDK-21', 'NP300 Dob Cab', 'NISSAN NP300', 'otro', 'TALLER COQUIMBO', 'PILLADO', 'TALLER COQUIMBO', '2025-02-24', NULL, NULL, NULL, 100, 'CARLOS + PEDRO', false, false, false, false, false, false, 8, 28.0, NULL, NULL, 'FRECUENCIA'),
  ('3151', 'CQBO-3151', 2025, 'TRDP-97', 'FMX 540', 'VOLVO FMX', 'otro', 'JUNTA VALERIANO', 'COLINA VERDE', 'VALLENAR', '2025-02-18', '2025-02-20', 645, 11788, 100, 'Felipe Lopez y Miguel Vel', false, false, false, false, false, false, 10, 18.0, NULL, NULL, 'FRECUENCIA'),
  ('3149', 'CQBO-3150', 2025, 'DJKL-18', 'Actros 3336 K', 'ACTROS', 'otro', 'ROMERAL', 'CONTRATO ESMAX ROM', 'LA SERENA', '2025-02-17', '2025-02-20', 19389, 202103, 100, 'Hernán Cortés y Miguel Ve', false, false, false, false, false, false, 6, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3150', 'CQBO-3150', 2025, 'JDKH-31', NULL, NULL, 'otro', NULL, NULL, NULL, '2025-02-17', NULL, NULL, NULL, 100, 'Herna Cortes', false, false, false, false, false, false, 4, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3148', 'CQBO-3148', 2025, 'LKPY-20', 'GU 813 autom', 'MACK', 'otro', NULL, NULL, NULL, '2025-02-12', NULL, 10460, 88710, 68, NULL, false, false, false, false, false, false, 16, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3147', 'CQBO-3148', 2025, 'LKPY-21', 'GU 813 autom', 'MACK', 'otro', NULL, NULL, NULL, '2025-02-11', NULL, 7170, 78037, 87, NULL, false, false, false, false, false, false, 16, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3145', 'CQBO-3145', 2025, 'KCBY-31', 'Actros 3336 K', 'ACTROS', 'otro', NULL, NULL, NULL, '2025-02-07', NULL, 7973, 99237, 100, 'Felipe Lopez', false, false, false, false, false, false, 3, 15.0, NULL, NULL, 'FRECUENCIA'),
  ('3144', 'CQBO-3144', 2025, 'YALE', NULL, NULL, 'otro', 'RECINTO INDUSTRIAL', 'INMOBILIARIA PAN DE ', 'COQUIMBO', '2025-02-06', NULL, 1186, NULL, 100, 'KEYBER RODRIGUEZ', false, false, false, false, false, false, 5, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3143', 'CQBO-3143', 2025, 'JTYK-82', 'Actros 3336 K', 'ACTROS', 'otro', 'TALLER PILLADO', 'PILLADO', 'COQUIMBO', '2025-02-05', NULL, NULL, NULL, 100, 'MIGUEL VELIZ', false, false, false, false, false, false, 15, 24.0, NULL, NULL, 'FRECUENCIA'),
  ('3142', 'CQBO-3142', 2025, 'KVWW-69', 'Actros 3336 K', 'ACTROS 3336K', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-02-04', NULL, 6278, 83221, 100, 'HERNAN + KEYBER', false, false, false, false, false, false, 9, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3138', 'CQBO-3138', 2025, 'GCHT-12', 'GU 813 autom', 'MACK GU813', 'otro', NULL, NULL, NULL, '2025-01-31', NULL, 7352, NULL, NULL, 'Hernan Cortes', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3136', 'CQBO-3136', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'san antonio', NULL, NULL, '2025-01-29', '2025-01-29', 3324, 43604, 100, 'Hernan Cortes y Carlos Fu', false, false, false, false, false, false, 3, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3130', 'CQBO-3130', 2025, 'GCSY-66', '02-7FDA50', 'toyota', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', '2025-01-28', NULL, NULL, NULL, 100, 'Keyber Rodriguez y Miguel', false, false, false, false, false, false, 15, 23.0, NULL, NULL, 'FRECUENCIA'),
  ('3140', 'CQBO-3140', 2025, 'ESMAX', NULL, 'EDS Bimodal', 'otro', 'ROMERAL', 'ESMAX', 'LA SERENA', '2025-01-28', '2025-01-28', NULL, NULL, 100, 'LÓPEZ + DIEGO', false, false, false, false, false, false, 3, 6.0, NULL, NULL, 'FRECUENCIA'),
  ('3135', 'CQBO-3135', 2025, 'RSCY-86', 'Accelo 1016/44', 'ACCELO 1016', 'otro', NULL, 'Salfa andina', 'los andes', '2025-01-24', '2025-01-29', 696, 69000, 100, 'Hernan Cortes y Diego Pin', false, false, false, false, false, false, 26, 41.0, NULL, NULL, 'FRECUENCIA'),
  ('3133T', 'CQBO-3133T', 2025, 'HHWB-44', 'GU 813 autom', 'MACK GU813', 'otro', 'FRANKE', 'PILLADO', 'TALTAL', '2025-01-22', NULL, NULL, NULL, 100, 'HUGO SETTRA', false, false, false, false, false, false, 9, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3134', 'CQBO-3134', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', '2025-01-21', '2025-01-22', 9335, 243299, 100, 'HERNAN + KEYBER', false, false, false, false, false, false, 8, 13.5, NULL, NULL, 'FRECUENCIA'),
  ('3131', 'CQBO-3131', 2025, 'FSLZ-67', 'Actros 3341', 'ACTROS 3341', 'otro', 'ROMERAL', 'CONTRATO ROM', 'LA SERENA', '2025-01-20', '2025-01-20', NULL, NULL, 100, 'HERNAN + DIEGO', false, false, false, false, false, false, 5, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3132', 'CQBO-3132', 2025, 'SVCZ-38', 'VM 350', 'Volvo VMX 350', 'otro', 'LOMAS BAYAS', 'GODIESEL', 'SIERRA GORDA', '2025-01-20', NULL, NULL, NULL, 100, 'JAIME ROJAS', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3127', 'CQBO-3127', 2025, 'RSCY-85', NULL, NULL, 'otro', NULL, NULL, 'Taller', '2025-01-15', NULL, 3133, 104584, NULL, 'Hernan Cortes y Diego Pin', false, false, false, false, false, false, 24, 38.0, NULL, NULL, 'FRECUENCIA'),
  ('3129', 'CQBO-3129', 2025, 'LKPY-18', 'GU 813 autom', 'MACK GU 813', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', '2025-01-15', NULL, 6182, 72362, 100, 'HERNAN + DIEGO', false, false, false, false, false, false, 2, 2.0, NULL, NULL, 'FRECUENCIA'),
  ('3120', 'CQBO-3117', 2025, 'SBPG-12', 'New Hilux 4x4 2.4 MT DX', 'TOYOTA HILUX', 'otro', NULL, 'PILLADO', 'TALLER PILLADO', '2025-01-09', '2025-01-10', NULL, 8148, 100, 'Keyber Rodriguez', false, false, false, false, false, false, 11, 15.5, NULL, NULL, 'FRECUENCIA'),
  ('3124T', 'CQBO-0000', 2025, 'TCJV-15', 'C440', 'RENAULT C440', 'otro', 'EL ABRA', 'ORBIT', 'CALAMA', '2025-01-09', '2025-01-11', NULL, NULL, 100, 'JAIME ROJAS', false, false, false, false, false, false, 4, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3125', 'CQBO-3125', 2025, 'RZ-PC-83', 'T60 4x4 DX', 'MAXUS', 'otro', 'ROMERAL', 'PILLADO ROMERAL', 'TALLER', '2025-01-08', NULL, NULL, 72580, 100, 'Daniel + Miguel', false, false, false, false, false, false, 15, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3126T', 'CQBO-3126T', 2025, 'SVBJ-56', 'VM 350', 'VOLVO VMX 350', 'otro', 'EL ABRA', 'ORBIT GARANT', 'CALAMA', '2025-01-08', NULL, NULL, NULL, 0, 'JAIME ROJAS / VOLVO', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3124', 'CQBO-3124', 2025, 'RSCY-85', 'Accelo 1016/44', 'ACCELO 1016', 'otro', 'ANDINA', 'SALFA MONTAJES', 'LOS ANDES', '2025-01-06', '2025-01-10', 3126, 104090, 100, 'HERNÁN + DIEGO', false, false, false, false, false, false, 15, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3123', 'CQBO-3123', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'san geronimo', NULL, 'Taller', '2025-01-03', '2025-01-03', 9091, 242076, 100, 'Hernan Cortes y Diego Pin', false, false, false, false, false, false, 13, 18.0, NULL, NULL, 'FRECUENCIA'),
  ('3112T', 'CQBO-3113T', 2025, 'KVWW-68', 'Actros 3336 K', 'ACTROS 3336K', 'otro', 'DMH', 'BOART', 'CALAMA', '2024-12-23', NULL, NULL, NULL, 43, 'JAIME ROJAS', false, false, false, false, false, false, 8, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3153', 'CQBO-3153', 2025, 'DJKL-18', 'Actros 3341', 'ACTROS 3341', 'otro', 'ROM', 'ROM', 'LA SERENA', '2024-02-21', NULL, NULL, NULL, 100, 'LÓPEZ + MIGUEL', false, false, false, false, false, false, 6, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3121', 'CQBO-3121', 2025, 'GCHT-12', 'GU 813 autom', 'MACK GU813', 'otro', NULL, NULL, 'Taller', '2024-01-02', NULL, 7352, 106518, 71, 'Herna Cortes y Diego Pint', false, false, false, false, false, false, 18, 26.0, NULL, NULL, 'FRECUENCIA'),
  ('3253', 'CQBO-3253', 2025, 'TRSS-16', 'P450B', 'SCANIA-P450B', 'otro', NULL, 'Pillado', 'Taller', NULL, NULL, 419, 9294, 0, 'Sergio Cortes', false, false, false, false, false, false, 14, 28.0, NULL, NULL, 'FRECUENCIA'),
  ('3326', 'CQBO-3326', 2026, 'SVBJ-56', 'VM 350', 'Volvo VM 350', 'otro', 'ESMAX', 'ESMAX', 'Copiaó', '2026-05-18', '2026-05-18', 2432, 42342, 100, 'Hugo Settra', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3292', 'CQBO-3292', 2026, 'JTYK-88', 'Actros 3341', 'M. Benz', 'otro', 'S/F', 'Pillado', 'Taller', NULL, NULL, 7462, 132340, 100, 'Sergio cortes', false, false, false, false, false, false, 3, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3353', 'CQBO-3353', 2026, 'DJKL-18', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, NULL, false, false, false, false, false, false, 7, 14.0, NULL, NULL, 'FRECUENCIA'),
  ('3122', 'CQBO-3122', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'ATEGO', 'otro', NULL, NULL, 'taller', NULL, NULL, 3305, 43481, 61, 'Keyber Rodriguez y Miguel', false, false, false, false, false, false, 24, 40.5, NULL, NULL, 'FRECUENCIA'),
  ('3128', 'CQBO-3128', 2025, 'DJKL-18', 'Actros 3336 K', 'Mercedes Benz/ Actros', 'otro', NULL, NULL, 'Taller', NULL, NULL, 19285, NULL, NULL, 'Daniel Castillo y Miguel ', false, false, false, false, false, false, 36, 68.0, NULL, NULL, 'FRECUENCIA'),
  ('3137', 'CQBO-3137', 2025, 'KVWD-27', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, 4270, NULL, 100, 'Hernan Cortes y Keyber Ro', false, false, false, false, false, false, 20, 42.0, NULL, NULL, 'FRECUENCIA'),
  ('3139', 'CQBO-3139', 2025, 'FJLZ-67', 'Actros 3341', 'actros 3341', 'otro', 'romeral', 'contrato rom', 'la serena', NULL, NULL, 14496, 120487, 100, 'Hernan Cortes', false, false, false, false, false, false, 31, 50.0, NULL, NULL, 'FRECUENCIA'),
  ('3141', 'CQBO-3141', 2025, 'SITEC', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 'HERNAN CORTES', false, false, false, false, false, false, 3, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3152', 'CQBO-3152', 2025, 'LCSX-78', 'GU 813 autom', 'Mack GU813', 'otro', NULL, NULL, NULL, NULL, NULL, 8589, 81829, 100, 'Hernan Cortes', false, false, false, false, false, false, 38, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3153', 'CQBO-3153', 2025, 'KCBY-31', 'Actros 3336 K', 'ACTROS', 'otro', NULL, NULL, NULL, NULL, NULL, NULL, 81829, 100, 'Carlos Fuentes y Pedro Ve', false, false, false, false, false, false, 13, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3154', 'CQBO-3154', 2025, 'KVWW-69', 'Actros 3336 K', 'ACTROS', 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 'Felipe Lopez y Carlos Fue', false, false, false, false, false, false, 10, 22.0, NULL, NULL, 'FRECUENCIA'),
  ('3160', 'CQBO-3160', 2025, 'JGBY-10', 'Axor 2633', 'AXOR', 'otro', NULL, 'Hugo Settra', 'Copiapo', NULL, NULL, 8044, 92060, 0, NULL, false, false, false, false, false, false, 52, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3161', 'CQBO-3161', 2025, 'SVCZ-38', 'VM 350', 'VMX', 'otro', NULL, NULL, NULL, NULL, NULL, 3140, 54407, 100, 'Hernan Cortes', false, false, false, false, false, false, 18, 27.0, NULL, NULL, 'FRECUENCIA'),
  ('3164', 'CQBO-3164', 2025, 'KCBY-31', 'Actros 3336 K', 'ACTROS', 'otro', NULL, NULL, NULL, NULL, NULL, 7979, 99291, 100, 'HERNAN', false, false, false, false, false, false, 8, 13.0, NULL, NULL, 'FRECUENCIA'),
  ('3168', 'CQBO-3168-2', 2025, 'JTYK-88', 'Actros 3336 K', 'ACTROS', 'otro', NULL, 'San Geronimo', 'San Antonio', NULL, NULL, 6580, 117859, 100, 'Yusdel Sarduy y Cesar Ahu', false, false, false, false, false, false, 22, 36.5, NULL, NULL, 'FRECUENCIA'),
  ('3172T', 'CQBO-3172T', 2025, 'SVCZ-38', 'VM 350', 'VOLVO VMX 350', 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 'VOLVO LA SERENA', false, false, false, false, false, false, 7, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3173', 'CQBO-3173', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'ATEGO', 'otro', 'SAN ANTONIO', 'SAN GERÓNIMO', 'LAMBERT', NULL, NULL, 1117, 246980, 100, 'Hernan Cortes', false, false, false, false, false, false, 14, 25.0, NULL, NULL, 'FRECUENCIA'),
  ('3184', 'CQBO-3184', 2025, 'RSCY-86', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 'Miguel Velez', false, false, false, false, false, false, 8, 24.0, NULL, NULL, 'FRECUENCIA'),
  ('3185', 'CQBO-3185', 2025, 'LKPY-18', 'GU 813 autom', 'MACK/GU813', 'otro', NULL, NULL, 'TALLER', NULL, NULL, 6182, 72363, 0, 'YUSDEL + JOEL', false, false, false, false, false, false, 11, 47.0, NULL, NULL, 'FRECUENCIA'),
  ('3186', 'CQBO-3186', 2025, 'GCHT-12', 'GU 813 autom', 'mack gu813', 'otro', NULL, NULL, NULL, NULL, NULL, 7631, 109829, 100, 'HERNAN + CESAR', false, false, false, false, false, false, 5, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3187', 'CQBO-3187', 2025, 'GCHT-12', 'GU 813 autom', 'MACK GU813', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', NULL, NULL, 7632, 109830, 100, 'YUSDEL + JOEL + FELIPE', false, false, false, false, false, false, 5, 16.0, NULL, NULL, 'FRECUENCIA'),
  ('3188', 'CQBO-3188', 2025, 'KVWD-27', 'Accelo 1016/44', 'ACCELO', 'otro', NULL, 'PILLADO', 'TALLER COQUIMBO', NULL, NULL, 4633, 6940, 100, 'HERNÁN + CESAR', false, false, false, false, false, false, 13, 26.0, NULL, NULL, 'FRECUENCIA'),
  ('3190', 'CQBO-3190', 2025, 'RSCY-86', 'Accelo 1016/44', 'ACCELO 1016', 'otro', NULL, NULL, NULL, NULL, NULL, 9150, 141742, 100, 'YUSDEL + JOEL', false, false, false, false, false, false, 9, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3192', 'CQBO-3192', 2025, 'DJKL-18', 'Actros 3336 K', 'ACTROS', 'otro', NULL, NULL, NULL, NULL, NULL, 19706, 204189, 100, NULL, false, false, false, false, false, false, 3, 16.0, NULL, NULL, 'FRECUENCIA'),
  ('3199', 'CQBO-3199', 2025, 'RSCY-85', 'Accelo 1016/44', 'M.Benz - Accelo 1016', 'otro', 'Salfa Montajes', 'Salfa Montajes', NULL, NULL, NULL, 3513, 115561, 100, NULL, false, false, false, false, false, false, 20, 40.0, NULL, NULL, 'FRECUENCIA'),
  ('3200', 'CQBO-3200', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'M.Benz  - Atego 1624', 'otro', NULL, NULL, 'Taller Mecánico Pill', NULL, NULL, 3456, 45845, 73, NULL, false, false, false, false, false, false, 24, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3200', 'CQBO-3200', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'M.Benz  - Atego 1624', 'otro', NULL, NULL, 'Taller Mecánico Pill', NULL, NULL, 3456, 45845, 73, NULL, false, false, false, false, false, false, 24, 41.0, NULL, NULL, 'FRECUENCIA'),
  ('3202', 'CQBO-3202', 2025, 'TRDP-97', 'FMX 540', 'VOLVO FMX', 'otro', 'RECEPCIÓN TERMINO ARRIENDO', 'COLINA VERDE', 'TALLER PILLADO', NULL, NULL, 1937, 16911, 0, 'JOEL + YUSDEL', false, false, false, false, false, false, 13, 31.0, NULL, NULL, 'FRECUENCIA'),
  ('3203', 'CQBO-3203', 2025, 'SLRK-82', 'Berlingo K9 1.6 Diesel', 'CITROEN BERLINGO', 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 'MIGUEL VELIZ', false, false, false, false, false, false, 2, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3204', 'CQBO-3204', 2025, 'PRET-APAII', NULL, NULL, 'otro', 'Romeral', 'Esmax', NULL, NULL, NULL, NULL, NULL, 0, 'Felipe López', false, false, false, false, false, false, 20, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3221', 'CQBO-3221', 2025, 'JDKH-31', 'NP300 Dob Cab', 'NISSAN', 'otro', 'TALLER', 'PILLADO', 'TALLER', NULL, NULL, NULL, 239896, 0, 'Cesar-Yusdel', false, false, false, false, false, false, 1, 4.0, NULL, NULL, 'FRECUENCIA'),
  ('3222', 'CQBO-3222', 2025, 'JTYK-88', 'Actros 3336 K', 'Mercedes Benz', 'otro', 'San Geronimo', NULL, 'San Geronimo', NULL, NULL, 7130, 127588, 0, 'Yusdel', false, false, false, false, false, false, 7, 21.0, NULL, NULL, 'FRECUENCIA'),
  ('3224', 'CQBO-3224', 2025, 'JGBY-10', 'Axor 2633', 'Mercedes Benz / Axor', 'otro', 'CMP El Romeral', NULL, 'Taller', NULL, NULL, 8868, 92604, 0, 'Felipe+Miguel+Yusdel+Cesa', false, false, false, false, false, false, 7, 16.0, NULL, NULL, 'FRECUENCIA'),
  ('3229', 'CQBO-3229', 2025, 'LCSX-78', 'GU 813 autom', 'Mack / Granite', 'otro', 'CMP  Romeral', 'CMP', 'Garita', NULL, NULL, 8690, 82431, 0, 'JOEL', false, false, false, false, false, false, 4, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3234', 'CQBO-3234', 2025, 'FJTJ-61', 'Atego 1624A 4x4', 'Atego 1624A', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', NULL, NULL, 3556, 46448, 0, 'Cesar Ahumada', false, false, false, false, false, false, 18, 36.0, NULL, NULL, 'FRECUENCIA'),
  ('3238', 'CQBO-3238', 2025, 'SVBJ-55', 'VM 350', 'Volvo VMX-350', 'otro', 'Pillado', 'Pillado', 'Taller Coquimbo', NULL, NULL, 601, 14935, 0, 'Cesar Ahumada', false, false, false, false, false, false, 13, 27.0, NULL, NULL, 'FRECUENCIA'),
  ('3240', 'CQBO-3240', 2025, 'RSCY-85', 'Accelo 1016/44', 'Mercedes Accelo 1016 44', 'otro', 'Los Andes', 'Pillado', 'Taller', NULL, NULL, 3855, 125483, 0, 'Luis Montt', false, false, false, false, false, false, 32, 68.0, NULL, NULL, 'FRECUENCIA'),
  ('3242', 'CQBO-3242', 2025, 'EDSB-IMODAL', NULL, 'Trenes', 'otro', 'Minas El Romeral', 'Esmax', NULL, NULL, NULL, NULL, NULL, 0, 'Joel + César', false, false, false, false, false, false, 1, 0.0, NULL, NULL, 'FRECUENCIA'),
  ('3245', 'CQBO-3245', 2025, 'LKPY-19', 'GU 813 autom', 'MACK- GRANITE', 'otro', 'Pillado', 'Pillado', 'Taller central', NULL, NULL, 638, 9551, 0, 'Joel Coo', false, false, false, false, false, false, 5, 11.0, NULL, NULL, 'FRECUENCIA'),
  ('3246', 'CQBO-3246', 2025, 'FJTJ-60', 'Atego 1624A 4x4', 'MB Atego 1624', 'otro', 'San Geronimo', 'San Geronimo', 'Taller', NULL, NULL, 2696, 254947, 0, 'Joel Coo', false, false, false, false, false, false, 32, 102.0, NULL, NULL, 'FRECUENCIA'),
  ('3247', 'CQBO-3247', 2025, 'LCSX-78', 'GU 813 autom', 'Mack Granite', 'otro', 'Pillado', 'Pillado', 'Taller', NULL, NULL, 8761, 83020, 0, 'Felipe Lopez + Yusdel Sar', false, false, false, false, false, false, 20, 29.5, NULL, NULL, 'FRECUENCIA'),
  ('3248', 'CQBO-3248', 2025, 'JTYK-88', 'Actros 3336 K', 'ACTROS 3336K', 'otro', 'Pillado', 'Pillado', 'Taller', NULL, NULL, 7441, 132177, 0, 'Yusdel', false, false, false, false, false, false, 29, 81.0, NULL, NULL, 'FRECUENCIA'),
  ('3250', 'CQBO-3250', 2025, 'HZSF-21', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'Sergio Cortes', false, false, false, false, false, false, 9, 36.0, NULL, NULL, 'FRECUENCIA'),
  ('3256', 'CQBO-3256', 2025, 'GCHT-12', 'GU 813 autom', 'Mack Granite', 'otro', 'Coquimbo', 'Pillado', 'Taller', NULL, NULL, NULL, NULL, 0, 'Felipe Rojas', false, false, false, false, false, false, 13, 64.0, NULL, NULL, 'FRECUENCIA'),
  ('3261', 'CQBO-3261', 2025, 'GDP-30TK', NULL, NULL, 'otro', NULL, 'Pillado', 'Taller', NULL, NULL, NULL, NULL, 0, 'Joel Coo', false, false, false, false, false, false, 3, 11.0, NULL, NULL, 'FRECUENCIA'),
  ('3263', 'CQBO-3263', 2025, 'FSLZ-67', NULL, NULL, 'otro', 'Romeral', 'CMP', 'Taller', NULL, NULL, NULL, NULL, 0, 'Sergio Cortes', false, false, false, false, false, false, 3, 8.0, NULL, NULL, 'FRECUENCIA'),
  ('3264', 'CQBO-3264', 2025, 'TRDP-97', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'Joel Coo', false, false, false, false, false, false, 3, 10.0, NULL, NULL, 'FRECUENCIA'),
  ('3265', 'CQBO-3265', 2025, 'TRSS-16', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL, false, false, false, false, false, false, 5, 17.0, NULL, NULL, 'FRECUENCIA'),
  ('3266', 'CQBO-3266', 2025, 'DJKL-18', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'Felipe Lopes- Joel Coo', false, false, false, false, false, false, 5, 31.0, NULL, NULL, 'FRECUENCIA'),
  ('3267', 'CQBO-3267', 2025, 'SLRK-82', NULL, NULL, 'otro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 'Felipe Rojas', false, false, false, false, false, false, 2, 5.0, NULL, NULL, 'FRECUENCIA'),
  ('3274', 'CQBO-3274', 2025, 'SVBJ-55', 'VM 350', 'Volvo MX', 'otro', 'Andacollo', NULL, 'Taller', NULL, '2025-12-04', 642, 17325, 0, NULL, false, false, false, false, false, false, 7, 12.0, NULL, NULL, 'FRECUENCIA'),
  ('3279', 'CQBO-3279', 2025, 'HKSR-81', 'Axor 2633', 'M.B. Axor 2633', 'otro', 'TPM', 'TPM', 'Taller', NULL, NULL, 655, 1085, 0, 'Marcos Diaz', false, false, false, false, false, false, 2, 10.0, NULL, NULL, 'FRECUENCIA');

-- Resumen para verificacion
SELECT COUNT(*) AS total_seed, MIN(anio) AS desde, MAX(anio) AS hasta FROM tmp_os_seed;


-- ============================================================================
-- 7. Mover de tmp_os_seed -> os_historico_importado resolviendo FKs
-- ============================================================================
INSERT INTO os_historico_importado (
    os_numero, os_codigo, anio, patente,
    activo_id, modelo_id, modelo_original,
    tipo_servicio, faena, cliente, ubicacion,
    fecha_recepcion, fecha_entrega, horometro, kilometraje,
    porcentaje_cumplimiento, responsable,
    es_preventivo, es_correctivo, es_neumaticos,
    es_revision_tecnica, es_habilitacion_estanque, es_servicio_externo,
    cant_trabajos, horas_mo,
    ultima_mant_fecha, ultima_mant_horas, frecuencia_texto
)
SELECT
    t.os_numero, t.os_cqbo, t.anio, t.patente,
    -- Resolver activo por patente (UPPER match)
    a.id, COALESCE(m.id, a.modelo_id), t.modelo_original,
    t.tipo_servicio, t.faena, t.cliente, t.ubicacion,
    t.fecha_recepcion, t.fecha_entrega, t.horometro, t.kilometraje,
    t.pct_cumpl, t.responsable,
    t.es_prev, t.es_corr, t.es_neum, t.es_rt, t.es_he, t.es_se,
    t.cant_trabajos, t.horas_mo,
    t.ult_man_fecha, t.ult_man_horas, t.frecuencia
  FROM tmp_os_seed t
  LEFT JOIN activos a ON UPPER(TRIM(a.patente)) = UPPER(TRIM(t.patente))
  LEFT JOIN modelos m ON m.nombre = t.modelo_canonico
ON CONFLICT (os_codigo) DO NOTHING;

DROP TABLE IF EXISTS tmp_os_seed;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'total_os_importadas',     (SELECT COUNT(*) FROM os_historico_importado),
    'con_activo_resuelto',     (SELECT COUNT(*) FROM os_historico_importado WHERE activo_id IS NOT NULL),
    'sin_activo_resuelto',     (SELECT COUNT(*) FROM os_historico_importado WHERE activo_id IS NULL),
    'con_modelo_resuelto',     (SELECT COUNT(*) FROM os_historico_importado WHERE modelo_id IS NOT NULL),
    'fechas_validas',          (SELECT COUNT(*) FROM os_historico_importado WHERE fecha_entrega IS NOT NULL),
    'tabla_alias',             to_regclass('public.os_modelo_alias') IS NOT NULL,
    'funcion_ultimo_servicio', EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_ultimo_servicio_por_activo'),
    'vista_pautas_estado',     to_regclass('public.v_pautas_estado_activo') IS NOT NULL
) AS resultado;

-- Resumen del estado de pautas (al aplicar)
SELECT estado_pauta, COUNT(*) AS cantidad
  FROM v_pautas_estado_activo
 GROUP BY estado_pauta
 ORDER BY cantidad DESC;

NOTIFY pgrst, 'reload schema';
