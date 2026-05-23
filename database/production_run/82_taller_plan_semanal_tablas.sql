-- ============================================================================
-- 82_taller_plan_semanal_tablas.sql
-- ----------------------------------------------------------------------------
-- Plan semanal del TALLER de mantencion. Replica el patron exitoso de
-- Operacion Calama (MIG20, MIG28) pero aplicado a las ordenes_trabajo del
-- taller (preventivas + correctivas + inspecciones).
--
-- Tablas creadas:
--   1. taller_planes_semanales         -- plan por semana (lunes-domingo)
--   2. taller_plan_semanal_dias        -- 7 dias por plan (auto-creados)
--   3. taller_plan_semanal_ots         -- OT asignada a un dia + responsable
--                                         (multidia: UNIQUE plan+ot+dia)
--   4. taller_ot_ejecuciones           -- play/pause/finalizar
--   5. taller_ot_ejecucion_eventos     -- audit trail
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Plan semanal (uno por semana, global o por faena opcional) ──────────
CREATE TABLE IF NOT EXISTS taller_planes_semanales (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id               UUID REFERENCES faenas(id) ON DELETE SET NULL,
    fecha_inicio_semana    DATE NOT NULL,
    fecha_fin_semana       DATE NOT NULL,
    estado                 VARCHAR(20) NOT NULL DEFAULT 'borrador',
    creado_por             UUID REFERENCES auth.users(id),
    confirmado_por         UUID REFERENCES auth.users(id),
    confirmado_at          TIMESTAMPTZ,
    observaciones          TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_taller_plansem_estado CHECK (estado IN
        ('borrador','confirmado','en_ejecucion','cerrado','cancelado')),
    CONSTRAINT chk_taller_plansem_fechas CHECK (fecha_fin_semana >= fecha_inicio_semana),
    CONSTRAINT uq_taller_plansem UNIQUE (faena_id, fecha_inicio_semana)
);
CREATE INDEX IF NOT EXISTS idx_taller_plansem_estado ON taller_planes_semanales (estado);
CREATE INDEX IF NOT EXISTS idx_taller_plansem_fechas ON taller_planes_semanales (fecha_inicio_semana DESC);


-- ── 2. Dias del plan (lun-dom) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_plan_semanal_dias (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_id     UUID NOT NULL REFERENCES taller_planes_semanales(id) ON DELETE CASCADE,
    fecha               DATE NOT NULL,
    nombre_dia          VARCHAR(20) NOT NULL,
    orden               INT NOT NULL,
    estado              VARCHAR(20) NOT NULL DEFAULT 'borrador',
    observaciones       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_taller_plandia_estado CHECK (estado IN
        ('borrador','confirmado','en_ejecucion','cerrado')),
    CONSTRAINT uq_taller_plandia UNIQUE (plan_semanal_id, fecha)
);
CREATE INDEX IF NOT EXISTS idx_taller_plandia_plan ON taller_plan_semanal_dias (plan_semanal_id, orden);


-- ── 3. OT asignada al plan (multidia: misma OT en varios dias) ─────────────
CREATE TABLE IF NOT EXISTS taller_plan_semanal_ots (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_id     UUID NOT NULL REFERENCES taller_planes_semanales(id) ON DELETE CASCADE,
    plan_dia_id         UUID NOT NULL REFERENCES taller_plan_semanal_dias(id) ON DELETE CASCADE,
    ot_id               UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    responsable_id      UUID REFERENCES usuarios_perfil(id),
    cuadrilla           VARCHAR(80),
    horas_planificadas  NUMERIC(6,2),
    avance_objetivo_pct NUMERIC(5,2),
    secuencia_jornada   INT NOT NULL DEFAULT 1,
    reprogramada_desde_id UUID REFERENCES taller_plan_semanal_ots(id) ON DELETE SET NULL,
    prioridad           INT NOT NULL DEFAULT 0,
    estado_plan         VARCHAR(30) NOT NULL DEFAULT 'planificada',
    observaciones       TEXT,
    created_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_taller_planot_estado CHECK (estado_plan IN
        ('planificada','asignada','liberada','en_ejecucion','pausada',
         'finalizada','no_ejecutada','bloqueada','reprogramada','cancelada')),
    CONSTRAINT uq_taller_planot UNIQUE (plan_semanal_id, ot_id, plan_dia_id)
);
CREATE INDEX IF NOT EXISTS idx_taller_planot_dia          ON taller_plan_semanal_ots (plan_dia_id);
CREATE INDEX IF NOT EXISTS idx_taller_planot_ot           ON taller_plan_semanal_ots (ot_id);
CREATE INDEX IF NOT EXISTS idx_taller_planot_responsable  ON taller_plan_semanal_ots (responsable_id) WHERE responsable_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_taller_planot_estado       ON taller_plan_semanal_ots (estado_plan);


-- ── 4. Ejecuciones (play/pausa/finalizar) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_ot_ejecuciones (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id                       UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    plan_semanal_ot_id          UUID REFERENCES taller_plan_semanal_ots(id) ON DELETE SET NULL,
    ejecutor_id                 UUID NOT NULL REFERENCES usuarios_perfil(id),
    estado                      VARCHAR(20) NOT NULL DEFAULT 'en_ejecucion',
    started_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at                 TIMESTAMPTZ,
    last_event_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tiempo_total_segundos       INT NOT NULL DEFAULT 0,
    tiempo_pausado_segundos     INT NOT NULL DEFAULT 0,
    tiempo_colacion_segundos    INT NOT NULL DEFAULT 0,
    tiempo_efectivo_segundos    INT NOT NULL DEFAULT 0,
    avance_final                NUMERIC(5,2),
    observacion_inicio          TEXT,
    observacion_cierre          TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_taller_ejec_estado CHECK (estado IN
        ('en_ejecucion','pausada','finalizada','cancelada'))
);
CREATE INDEX IF NOT EXISTS idx_taller_ejec_ot          ON taller_ot_ejecuciones (ot_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_taller_ejec_ejecutor    ON taller_ot_ejecuciones (ejecutor_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_taller_ejec_activa_ot
    ON taller_ot_ejecuciones (ot_id) WHERE estado IN ('en_ejecucion','pausada');


-- ── 5. Eventos de ejecucion (audit trail) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_ot_ejecucion_eventos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id    UUID NOT NULL REFERENCES taller_ot_ejecuciones(id) ON DELETE CASCADE,
    ot_id           UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    tipo            VARCHAR(20) NOT NULL,
    motivo          VARCHAR(40),
    comentario      TEXT,
    avance          NUMERIC(5,2),
    created_by      UUID REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_taller_ejecev_tipo CHECK (tipo IN
        ('start','pause','resume','finish','cancel','avance','comentario'))
);
CREATE INDEX IF NOT EXISTS idx_taller_ejecev_ejec ON taller_ot_ejecucion_eventos (ejecucion_id, created_at);
CREATE INDEX IF NOT EXISTS idx_taller_ejecev_ot   ON taller_ot_ejecucion_eventos (ot_id, created_at DESC);


-- ── 6. Triggers updated_at ─────────────────────────────────────────────────
DO $$
DECLARE v_tabla TEXT;
BEGIN
    FOR v_tabla IN SELECT unnest(ARRAY[
        'taller_planes_semanales','taller_plan_semanal_dias',
        'taller_plan_semanal_ots','taller_ot_ejecuciones'
    ]) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_%I_updated_at ON %I', v_tabla, v_tabla);
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()',
            v_tabla, v_tabla
        );
    END LOOP;
END $$;


-- ── 7. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE taller_planes_semanales         ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_plan_semanal_dias        ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_plan_semanal_ots         ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_ot_ejecuciones           ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_ot_ejecucion_eventos     ENABLE ROW LEVEL SECURITY;

-- SELECT abierto a authenticated; WRITE restringido por rol via RPCs
DO $$
DECLARE v_tabla TEXT;
BEGIN
    FOR v_tabla IN SELECT unnest(ARRAY[
        'taller_planes_semanales','taller_plan_semanal_dias','taller_plan_semanal_ots',
        'taller_ot_ejecuciones','taller_ot_ejecucion_eventos'
    ]) LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%I_select ON %I', v_tabla, v_tabla);
        EXECUTE format(
            'CREATE POLICY pol_%I_select ON %I FOR SELECT TO authenticated USING (true)',
            v_tabla, v_tabla
        );
        -- Permitir INSERT/UPDATE/DELETE solo a roles internos (las RPCs SECURITY DEFINER bypasean)
        EXECUTE format('DROP POLICY IF EXISTS pol_%I_write ON %I', v_tabla, v_tabla);
        EXECUTE format(
            'CREATE POLICY pol_%I_write ON %I FOR ALL TO authenticated
              USING (fn_user_rol() IN (''administrador'',''supervisor'',''subgerente_operaciones'',''jefe_mantenimiento''))
              WITH CHECK (fn_user_rol() IN (''administrador'',''supervisor'',''subgerente_operaciones'',''jefe_mantenimiento''))',
            v_tabla, v_tabla
        );
    END LOOP;
END $$;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM information_schema.tables
     WHERE table_schema='public' AND table_name LIKE 'taller_%';
    IF v_count < 5 THEN
        RAISE EXCEPTION 'STOP - faltan tablas taller_*. Creadas: %', v_count;
    END IF;
    RAISE NOTICE '== MIG82 OK == % tablas taller_* creadas', v_count;
END $$;

NOTIFY pgrst, 'reload schema';
