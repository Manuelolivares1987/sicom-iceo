-- ============================================================================
-- 20_operacion_calama_planificacion_semanal.sql
-- ----------------------------------------------------------------------------
-- Modulo Plan Semanal Calama (Kanban) + Ejecucion basica (PLAY/PAUSA/FINALIZAR)
--
-- ALCANCE:
--   Tablas (6):
--     - calama_planes_semanales
--     - calama_plan_semanal_dias
--     - calama_plan_semanal_ots
--     - calama_plan_semanal_materiales
--     - calama_ot_ejecuciones
--     - calama_ot_ejecucion_eventos
--   Helpers SECURITY DEFINER (sin recursion):
--     - fn_calama_uid_es_responsable_plan_ot(uuid)
--   RPCs:
--     - rpc_calama_get_or_create_plan_semanal(planificacion_id, fecha_inicio)
--     - rpc_calama_mover_ot_plan_semanal(plan_semanal_id, ot_id, fecha_destino, responsable_id?)
--     - rpc_calama_quitar_ot_plan_semanal(plan_semanal_id, ot_id)
--     - rpc_calama_asignar_responsable_ot_semana(plan_semanal_id, ot_id, responsable_id)
--     - rpc_calama_confirmar_plan_semanal(plan_semanal_id)
--     - rpc_calama_iniciar_ejecucion_ot(ot_id)            (variante con eventos)
--     - rpc_calama_pausar_ejecucion_ot(ejecucion_id, motivo)
--     - rpc_calama_reanudar_ejecucion_ot(ejecucion_id)
--     - rpc_calama_finalizar_ejecucion_ot(ejecucion_id, avance, observacion?)
--   RLS estricta. anon SIN ACCESO.
--
-- AISLACION (REGLAS USUARIO):
--   - NO toca MIG17/18/18B/19.
--   - NO toca QR (mig 14*), MIG55-57, ni rol_usuario_enum.
--   - Solo agrega tablas/funciones nuevas y crea policies para esas tablas.
--   - Patron SECURITY DEFINER aprendido en MIG19 — sin EXISTS recursivo.
--
-- VERIFICACION FINAL: 1 fila OK_OPERACION_CALAMA_PLAN_SEMANAL / WARNING / STOP.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP — MIG17 no aplicada (calama_ordenes_trabajo no existe).';
    END IF;
    IF to_regprocedure('public.fn_calama_puede_planificar()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_calama_puede_planificar() no existe (MIG17).';
    END IF;
    IF to_regprocedure('public.fn_calama_es_admin_global()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_calama_es_admin_global() no existe (MIG17).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. TABLAS ────────────────────────────────────────────────────────────────
-- ============================================================================

-- 1.1 Planes semanales (un plan por planificacion + semana)
CREATE TABLE IF NOT EXISTS calama_planes_semanales (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    planificacion_id       UUID NOT NULL REFERENCES calama_planificaciones(id) ON DELETE CASCADE,
    faena_calama_id        UUID REFERENCES calama_faenas(id),
    fecha_inicio_semana    DATE NOT NULL,
    fecha_fin_semana       DATE NOT NULL,
    estado                 VARCHAR(20) NOT NULL DEFAULT 'borrador',
    creado_por             UUID REFERENCES auth.users(id),
    confirmado_por         UUID REFERENCES auth.users(id),
    confirmado_at          TIMESTAMPTZ,
    observaciones          TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_plansem_estado CHECK (estado IN
        ('borrador','confirmado','en_ejecucion','cerrado','cancelado')),
    CONSTRAINT chk_calama_plansem_fechas CHECK (fecha_fin_semana >= fecha_inicio_semana),
    CONSTRAINT uq_calama_plansem UNIQUE (planificacion_id, fecha_inicio_semana)
);
CREATE INDEX IF NOT EXISTS idx_calama_plansem_plan ON calama_planes_semanales (planificacion_id);
CREATE INDEX IF NOT EXISTS idx_calama_plansem_estado ON calama_planes_semanales (estado);

-- 1.2 Dias del plan semanal
CREATE TABLE IF NOT EXISTS calama_plan_semanal_dias (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_id     UUID NOT NULL REFERENCES calama_planes_semanales(id) ON DELETE CASCADE,
    fecha               DATE NOT NULL,
    nombre_dia          VARCHAR(20) NOT NULL,
    orden               INT NOT NULL,
    estado              VARCHAR(20) NOT NULL DEFAULT 'borrador',
    observaciones       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_plandia_estado CHECK (estado IN
        ('borrador','confirmado','en_ejecucion','cerrado')),
    CONSTRAINT uq_calama_plandia UNIQUE (plan_semanal_id, fecha)
);
CREATE INDEX IF NOT EXISTS idx_calama_plandia_plan ON calama_plan_semanal_dias (plan_semanal_id, orden);

-- 1.3 OTs en el plan semanal (asignacion a un dia)
CREATE TABLE IF NOT EXISTS calama_plan_semanal_ots (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_id     UUID NOT NULL REFERENCES calama_planes_semanales(id) ON DELETE CASCADE,
    plan_dia_id         UUID NOT NULL REFERENCES calama_plan_semanal_dias(id) ON DELETE CASCADE,
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    zona_proyecto_id    UUID REFERENCES calama_zonas_proyecto(id),
    responsable_id      UUID REFERENCES usuarios_perfil(id),
    prioridad           INT NOT NULL DEFAULT 0,
    estado_plan         VARCHAR(20) NOT NULL DEFAULT 'planificada',
    observaciones       TEXT,
    created_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_planot_estado CHECK (estado_plan IN
        ('planificada','asignada','liberada','en_ejecucion','pausada','finalizada','no_ejecutada','bloqueada')),
    CONSTRAINT uq_calama_planot UNIQUE (plan_semanal_id, ot_id)
);
CREATE INDEX IF NOT EXISTS idx_calama_planot_dia          ON calama_plan_semanal_ots (plan_dia_id);
CREATE INDEX IF NOT EXISTS idx_calama_planot_ot           ON calama_plan_semanal_ots (ot_id);
CREATE INDEX IF NOT EXISTS idx_calama_planot_responsable  ON calama_plan_semanal_ots (responsable_id) WHERE responsable_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_planot_estado       ON calama_plan_semanal_ots (estado_plan);

-- 1.4 Materiales requeridos del plan semanal (vista calculada/snapshot)
CREATE TABLE IF NOT EXISTS calama_plan_semanal_materiales (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_semanal_id         UUID NOT NULL REFERENCES calama_planes_semanales(id) ON DELETE CASCADE,
    plan_dia_id             UUID REFERENCES calama_plan_semanal_dias(id) ON DELETE CASCADE,
    ot_id                   UUID REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    material_planificado_id UUID REFERENCES calama_materiales_planificados(id),
    descripcion             TEXT NOT NULL,
    unidad                  VARCHAR(20),
    cantidad_requerida      NUMERIC(14,2),
    cantidad_disponible     NUMERIC(14,2),
    cantidad_faltante       NUMERIC(14,2),
    estado_material         VARCHAR(20) NOT NULL DEFAULT 'no_controlado',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_planmat_estado CHECK (estado_material IN ('ok','faltante','no_controlado'))
);
CREATE INDEX IF NOT EXISTS idx_calama_planmat_plan ON calama_plan_semanal_materiales (plan_semanal_id);
CREATE INDEX IF NOT EXISTS idx_calama_planmat_ot   ON calama_plan_semanal_materiales (ot_id) WHERE ot_id IS NOT NULL;

-- 1.5 Ejecuciones de OT (PLAY/PAUSA/FINALIZAR)
CREATE TABLE IF NOT EXISTS calama_ot_ejecuciones (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id                       UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    plan_semanal_ot_id          UUID REFERENCES calama_plan_semanal_ots(id) ON DELETE SET NULL,
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
    CONSTRAINT chk_calama_ejec_estado CHECK (estado IN
        ('en_ejecucion','pausada','finalizada','cancelada'))
);
CREATE INDEX IF NOT EXISTS idx_calama_ejec_ot          ON calama_ot_ejecuciones (ot_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_calama_ejec_ejecutor    ON calama_ot_ejecuciones (ejecutor_id);
-- Solo una ejecucion ACTIVA por OT (no finalizada/cancelada)
CREATE UNIQUE INDEX IF NOT EXISTS uq_calama_ejec_activa_ot
    ON calama_ot_ejecuciones (ot_id) WHERE estado IN ('en_ejecucion','pausada');

-- 1.6 Eventos de ejecucion
CREATE TABLE IF NOT EXISTS calama_ot_ejecucion_eventos (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id    UUID NOT NULL REFERENCES calama_ot_ejecuciones(id) ON DELETE CASCADE,
    ot_id           UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    tipo            VARCHAR(20) NOT NULL,
    motivo          VARCHAR(40),
    comentario      TEXT,
    avance          NUMERIC(5,2),
    created_by      UUID REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_ejecev_tipo CHECK (tipo IN
        ('start','pause','resume','finish','cancel','avance','comentario'))
);
CREATE INDEX IF NOT EXISTS idx_calama_ejecev_ejec ON calama_ot_ejecucion_eventos (ejecucion_id, created_at);
CREATE INDEX IF NOT EXISTS idx_calama_ejecev_ot   ON calama_ot_ejecucion_eventos (ot_id, created_at DESC);


-- ============================================================================
-- ── 2. TRIGGERS updated_at ───────────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_tabla TEXT;
BEGIN
    FOR v_tabla IN SELECT unnest(ARRAY[
        'calama_planes_semanales','calama_plan_semanal_dias','calama_plan_semanal_ots',
        'calama_plan_semanal_materiales','calama_ot_ejecuciones'
    ]) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger WHERE tgname = 'trg_' || v_tabla || '_updated_at'
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I
                 FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();',
                v_tabla, v_tabla
            );
        END IF;
    END LOOP;
END $$;


-- ============================================================================
-- ── 3. HELPERS RLS (SECURITY DEFINER, sin recursion) ─────────────────────────
-- ============================================================================

-- 3.1 ¿El usuario es responsable de esta plan-OT?
CREATE OR REPLACE FUNCTION fn_calama_uid_es_responsable_plan_ot(p_plan_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_plan_semanal_ots
         WHERE id = p_plan_ot_id AND responsable_id = auth.uid()
    );
$$;

-- 3.2 ¿El usuario es responsable de alguna plan-OT de esta OT?
CREATE OR REPLACE FUNCTION fn_calama_uid_es_responsable_ot_en_plan(p_ot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_plan_semanal_ots
         WHERE ot_id = p_ot_id AND responsable_id = auth.uid()
    );
$$;

-- 3.3 ¿El usuario tiene una ejecucion activa de esta OT?
CREATE OR REPLACE FUNCTION fn_calama_uid_es_ejecutor_de_ejecucion(p_ejecucion_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM calama_ot_ejecuciones
         WHERE id = p_ejecucion_id AND ejecutor_id = auth.uid()
    );
$$;

GRANT EXECUTE ON FUNCTION fn_calama_uid_es_responsable_plan_ot(UUID)        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_uid_es_responsable_ot_en_plan(UUID)     TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_uid_es_ejecutor_de_ejecucion(UUID)      TO authenticated;


-- ============================================================================
-- ── 4. RLS ───────────────────────────────────────────────────────────────────
-- ============================================================================

ALTER TABLE calama_planes_semanales         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_plan_semanal_dias        ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_plan_semanal_ots         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_plan_semanal_materiales  ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_ot_ejecuciones           ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_ot_ejecucion_eventos     ENABLE ROW LEVEL SECURITY;

-- Planes semanales: SELECT amplio, modif solo planificadores
DROP POLICY IF EXISTS pol_calama_plansem_select ON calama_planes_semanales;
CREATE POLICY pol_calama_plansem_select ON calama_planes_semanales
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_plansem_modif ON calama_planes_semanales;
CREATE POLICY pol_calama_plansem_modif ON calama_planes_semanales
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Dias: igual
DROP POLICY IF EXISTS pol_calama_plandia_select ON calama_plan_semanal_dias;
CREATE POLICY pol_calama_plandia_select ON calama_plan_semanal_dias
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_plandia_modif ON calama_plan_semanal_dias;
CREATE POLICY pol_calama_plandia_modif ON calama_plan_semanal_dias
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Plan-OTs: planificador/admin todos, operador solo las suyas
DROP POLICY IF EXISTS pol_calama_planot_select ON calama_plan_semanal_ots;
CREATE POLICY pol_calama_planot_select ON calama_plan_semanal_ots
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR responsable_id = auth.uid()
    );
DROP POLICY IF EXISTS pol_calama_planot_modif ON calama_plan_semanal_ots;
CREATE POLICY pol_calama_planot_modif ON calama_plan_semanal_ots
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Materiales del plan: SELECT amplio
DROP POLICY IF EXISTS pol_calama_planmat_select ON calama_plan_semanal_materiales;
CREATE POLICY pol_calama_planmat_select ON calama_plan_semanal_materiales
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_planmat_modif ON calama_plan_semanal_materiales;
CREATE POLICY pol_calama_planmat_modif ON calama_plan_semanal_materiales
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- Ejecuciones: planificador/admin todos, ejecutor solo las propias
DROP POLICY IF EXISTS pol_calama_ejec_select ON calama_ot_ejecuciones;
CREATE POLICY pol_calama_ejec_select ON calama_ot_ejecuciones
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR ejecutor_id = auth.uid()
    );
-- INSERT/UPDATE: por RPC SECURITY DEFINER. Para safety adicional, tambien permitimos
-- al ejecutor actualizar las propias.
DROP POLICY IF EXISTS pol_calama_ejec_insert ON calama_ot_ejecuciones;
CREATE POLICY pol_calama_ejec_insert ON calama_ot_ejecuciones
    FOR INSERT TO authenticated
    WITH CHECK (ejecutor_id = auth.uid() OR fn_calama_puede_planificar());
DROP POLICY IF EXISTS pol_calama_ejec_update ON calama_ot_ejecuciones;
CREATE POLICY pol_calama_ejec_update ON calama_ot_ejecuciones
    FOR UPDATE TO authenticated
    USING (ejecutor_id = auth.uid() OR fn_calama_puede_planificar())
    WITH CHECK (ejecutor_id = auth.uid() OR fn_calama_puede_planificar());

-- Eventos: SELECT por planning roles + ejecutor; INSERT por ejecutor
DROP POLICY IF EXISTS pol_calama_ejecev_select ON calama_ot_ejecucion_eventos;
CREATE POLICY pol_calama_ejecev_select ON calama_ot_ejecucion_eventos
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR fn_calama_uid_es_ejecutor_de_ejecucion(ejecucion_id)
    );
DROP POLICY IF EXISTS pol_calama_ejecev_insert ON calama_ot_ejecucion_eventos;
CREATE POLICY pol_calama_ejecev_insert ON calama_ot_ejecucion_eventos
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR fn_calama_uid_es_ejecutor_de_ejecucion(ejecucion_id)
    );


-- ============================================================================
-- ── 5. RPCs PLANIFICACION ────────────────────────────────────────────────────
-- ============================================================================

-- 5.1 Get-or-create plan semanal: crea las 7 filas dia (lun-dom) si no existen.
CREATE OR REPLACE FUNCTION rpc_calama_get_or_create_plan_semanal(
    p_planificacion_id UUID,
    p_fecha_inicio DATE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id UUID;
    v_faena UUID;
    v_lunes DATE := p_fecha_inicio - ((EXTRACT(DOW FROM p_fecha_inicio)::INT + 6) % 7);
    v_dom   DATE := v_lunes + 6;
    v_dias_es CONSTANT TEXT[] := ARRAY['Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo'];
    v_i INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para gestionar plan semanal';
    END IF;

    SELECT faena_calama_id INTO v_faena FROM calama_planificaciones WHERE id = p_planificacion_id;
    IF v_faena IS NULL THEN RAISE EXCEPTION 'planificacion_id % no encontrada', p_planificacion_id; END IF;

    SELECT id INTO v_id FROM calama_planes_semanales
     WHERE planificacion_id = p_planificacion_id AND fecha_inicio_semana = v_lunes;

    IF v_id IS NULL THEN
        INSERT INTO calama_planes_semanales (
            planificacion_id, faena_calama_id, fecha_inicio_semana, fecha_fin_semana,
            estado, creado_por
        ) VALUES (
            p_planificacion_id, v_faena, v_lunes, v_dom, 'borrador', v_uid
        ) RETURNING id INTO v_id;

        FOR v_i IN 1..7 LOOP
            INSERT INTO calama_plan_semanal_dias (
                plan_semanal_id, fecha, nombre_dia, orden, estado
            ) VALUES (
                v_id, v_lunes + (v_i - 1), v_dias_es[v_i], v_i, 'borrador'
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'plan_semanal_id', v_id,
        'fecha_inicio', v_lunes,
        'fecha_fin', v_dom
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_get_or_create_plan_semanal(UUID, DATE) TO authenticated;


-- 5.2 Mover OT a un dia (asigna o cambia plan_dia_id)
CREATE OR REPLACE FUNCTION rpc_calama_mover_ot_plan_semanal(
    p_plan_semanal_id UUID,
    p_ot_id UUID,
    p_fecha_destino DATE,
    p_responsable_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_dia_id UUID;
    v_zona UUID;
    v_estado_plan TEXT;
    v_existing_id UUID;
    v_existing_estado TEXT;
    v_plan_estado TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Rol no autorizado para mover OTs';
    END IF;

    SELECT estado INTO v_plan_estado FROM calama_planes_semanales WHERE id = p_plan_semanal_id;
    IF v_plan_estado IS NULL THEN RAISE EXCEPTION 'plan_semanal_id no encontrado'; END IF;
    IF v_plan_estado IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_plan_estado;
    END IF;

    SELECT id INTO v_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha_destino;
    IF v_dia_id IS NULL THEN RAISE EXCEPTION 'fecha_destino % no pertenece a este plan', p_fecha_destino; END IF;

    -- Derivar zona desde folio de OT (formato OT_<plan>_<n.m.k>)
    SELECT z.id INTO v_zona
      FROM calama_ordenes_trabajo o
      JOIN calama_planificaciones p ON p.id = o.planificacion_id
      LEFT JOIN calama_zonas_proyecto z
             ON z.planificacion_id = p.id
            AND z.codigo_zona = (regexp_match(o.folio, '(\d+)\.\d+\.\d+$'))[1] || '.0.0'
     WHERE o.id = p_ot_id
     LIMIT 1;

    SELECT id, estado_plan INTO v_existing_id, v_existing_estado
      FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    IF v_existing_id IS NOT NULL THEN
        IF v_existing_estado IN ('en_ejecucion','finalizada') THEN
            RAISE EXCEPTION 'OT en estado_plan % no puede moverse', v_existing_estado;
        END IF;
        UPDATE calama_plan_semanal_ots
           SET plan_dia_id = v_dia_id,
               zona_proyecto_id = COALESCE(v_zona, zona_proyecto_id),
               responsable_id = COALESCE(p_responsable_id, responsable_id),
               estado_plan = CASE WHEN p_responsable_id IS NOT NULL AND estado_plan = 'planificada'
                                  THEN 'asignada' ELSE estado_plan END,
               updated_at = NOW()
         WHERE id = v_existing_id;
        v_estado_plan := 'updated';
    ELSE
        INSERT INTO calama_plan_semanal_ots (
            plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id, responsable_id,
            estado_plan, created_by
        ) VALUES (
            p_plan_semanal_id, v_dia_id, p_ot_id, v_zona, p_responsable_id,
            CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'planificada' END,
            v_uid
        ) RETURNING id INTO v_existing_id;
        v_estado_plan := 'inserted';
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_existing_id, 'op', v_estado_plan);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_mover_ot_plan_semanal(UUID, UUID, DATE, UUID) TO authenticated;


-- 5.3 Quitar OT del plan
CREATE OR REPLACE FUNCTION rpc_calama_quitar_ot_plan_semanal(
    p_plan_semanal_id UUID,
    p_ot_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_estado TEXT;
    v_plan_estado TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    SELECT estado INTO v_plan_estado FROM calama_planes_semanales WHERE id = p_plan_semanal_id;
    IF v_plan_estado IN ('cerrado','cancelado') THEN
        RAISE EXCEPTION 'plan en estado % no admite cambios', v_plan_estado;
    END IF;

    SELECT estado_plan INTO v_estado FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;
    IF v_estado IN ('en_ejecucion','finalizada') THEN
        RAISE EXCEPTION 'OT en estado_plan % no puede quitarse', v_estado;
    END IF;

    DELETE FROM calama_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_quitar_ot_plan_semanal(UUID, UUID) TO authenticated;


-- 5.4 Asignar responsable
CREATE OR REPLACE FUNCTION rpc_calama_asignar_responsable_ot_semana(
    p_plan_semanal_id UUID,
    p_ot_id UUID,
    p_responsable_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    UPDATE calama_plan_semanal_ots
       SET responsable_id = p_responsable_id,
           estado_plan = CASE WHEN estado_plan = 'planificada' THEN 'asignada' ELSE estado_plan END,
           updated_at = NOW()
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada en este plan'; END IF;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_asignar_responsable_ot_semana(UUID, UUID, UUID) TO authenticated;


-- 5.5 Confirmar plan semanal
CREATE OR REPLACE FUNCTION rpc_calama_confirmar_plan_semanal(p_plan_semanal_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_count INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_planificar() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    SELECT COUNT(*) INTO v_count FROM calama_plan_semanal_ots WHERE plan_semanal_id = p_plan_semanal_id;
    IF v_count = 0 THEN RAISE EXCEPTION 'plan vacio: agrega OTs antes de confirmar'; END IF;

    UPDATE calama_planes_semanales
       SET estado = 'confirmado', confirmado_por = v_uid, confirmado_at = NOW(), updated_at = NOW()
     WHERE id = p_plan_semanal_id AND estado = 'borrador';
    IF NOT FOUND THEN RAISE EXCEPTION 'plan no esta en borrador o no existe'; END IF;

    UPDATE calama_plan_semanal_dias SET estado = 'confirmado', updated_at = NOW()
     WHERE plan_semanal_id = p_plan_semanal_id AND estado = 'borrador';

    RETURN jsonb_build_object('success', true, 'ots_confirmadas', v_count);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_confirmar_plan_semanal(UUID) TO authenticated;


-- ============================================================================
-- ── 6. RPCs EJECUCION (PLAY/PAUSA/REANUDAR/FINALIZAR) ────────────────────────
-- ============================================================================

-- 6.1 Iniciar ejecucion (PLAY)
CREATE OR REPLACE FUNCTION rpc_calama_iniciar_ejecucion_ot(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ejecutor_perfil_id UUID;
    v_existing UUID;
    v_plan_ot_id UUID;
    v_ot_estado TEXT;
    v_id UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT id INTO v_ejecutor_perfil_id FROM usuarios_perfil WHERE id = v_uid;
    IF v_ejecutor_perfil_id IS NULL THEN RAISE EXCEPTION 'Perfil no encontrado'; END IF;

    SELECT id INTO v_existing FROM calama_ot_ejecuciones
     WHERE ot_id = p_ot_id AND estado IN ('en_ejecucion','pausada');
    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'Ya existe una ejecucion activa para esta OT';
    END IF;

    -- ¿Operador tiene otra ejecucion activa?
    IF EXISTS (
        SELECT 1 FROM calama_ot_ejecuciones
         WHERE ejecutor_id = v_ejecutor_perfil_id AND estado IN ('en_ejecucion','pausada')
    ) AND NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Ya tienes otra OT en ejecucion. Finalizala antes de iniciar otra.';
    END IF;

    SELECT estado INTO v_ot_estado FROM calama_ordenes_trabajo WHERE id = p_ot_id;
    IF v_ot_estado IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;
    IF v_ot_estado NOT IN ('planificada','liberada','en_pausa') THEN
        RAISE EXCEPTION 'OT en estado % no puede iniciarse', v_ot_estado;
    END IF;

    SELECT id INTO v_plan_ot_id FROM calama_plan_semanal_ots
     WHERE ot_id = p_ot_id ORDER BY created_at DESC LIMIT 1;

    INSERT INTO calama_ot_ejecuciones (
        ot_id, plan_semanal_ot_id, ejecutor_id, estado,
        started_at, last_event_at
    ) VALUES (
        p_ot_id, v_plan_ot_id, v_ejecutor_perfil_id, 'en_ejecucion',
        NOW(), NOW()
    ) RETURNING id INTO v_id;

    INSERT INTO calama_ot_ejecucion_eventos (ejecucion_id, ot_id, tipo, created_by)
    VALUES (v_id, p_ot_id, 'start', v_uid);

    UPDATE calama_ordenes_trabajo
       SET estado = 'en_ejecucion',
           fecha_inicio_real = COALESCE(fecha_inicio_real, NOW()),
           updated_at = NOW()
     WHERE id = p_ot_id;

    IF v_plan_ot_id IS NOT NULL THEN
        UPDATE calama_plan_semanal_ots SET estado_plan = 'en_ejecucion', updated_at = NOW()
         WHERE id = v_plan_ot_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_iniciar_ejecucion_ot(UUID) TO authenticated;


-- 6.2 Pausar
CREATE OR REPLACE FUNCTION rpc_calama_pausar_ejecucion_ot(
    p_ejecucion_id UUID,
    p_motivo TEXT DEFAULT 'pausa'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_estado TEXT;
    v_last TIMESTAMPTZ;
    v_ejecutor UUID;
    v_ot_id UUID;
    v_delta INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT estado, last_event_at, ejecutor_id, ot_id
      INTO v_estado, v_last, v_ejecutor, v_ot_id
      FROM calama_ot_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no encontrada'; END IF;
    IF v_estado <> 'en_ejecucion' THEN RAISE EXCEPTION 'Ejecucion no esta en_ejecucion'; END IF;
    IF v_ejecutor <> v_uid AND NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Solo el ejecutor o un planificador puede pausar';
    END IF;

    v_delta := EXTRACT(EPOCH FROM (NOW() - v_last))::INT;

    UPDATE calama_ot_ejecuciones
       SET estado = 'pausada',
           tiempo_efectivo_segundos = tiempo_efectivo_segundos + v_delta,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;

    INSERT INTO calama_ot_ejecucion_eventos (ejecucion_id, ot_id, tipo, motivo, created_by)
    VALUES (p_ejecucion_id, v_ot_id, 'pause', COALESCE(p_motivo,'pausa'), v_uid);

    UPDATE calama_ordenes_trabajo SET estado = 'en_pausa', updated_at = NOW()
     WHERE id = v_ot_id AND estado = 'en_ejecucion';

    RETURN jsonb_build_object('success', true, 'tiempo_efectivo_acum_seg',
        (SELECT tiempo_efectivo_segundos FROM calama_ot_ejecuciones WHERE id = p_ejecucion_id));
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_pausar_ejecucion_ot(UUID, TEXT) TO authenticated;


-- 6.3 Reanudar
CREATE OR REPLACE FUNCTION rpc_calama_reanudar_ejecucion_ot(p_ejecucion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_estado TEXT;
    v_last TIMESTAMPTZ;
    v_ejecutor UUID;
    v_ot_id UUID;
    v_delta INT;
    v_motivo_anterior TEXT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT estado, last_event_at, ejecutor_id, ot_id
      INTO v_estado, v_last, v_ejecutor, v_ot_id
      FROM calama_ot_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no encontrada'; END IF;
    IF v_estado <> 'pausada' THEN RAISE EXCEPTION 'Ejecucion no esta pausada'; END IF;
    IF v_ejecutor <> v_uid AND NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Solo el ejecutor o un planificador puede reanudar';
    END IF;

    v_delta := EXTRACT(EPOCH FROM (NOW() - v_last))::INT;

    -- Buscar motivo del ultimo pause para clasificar como colacion
    SELECT motivo INTO v_motivo_anterior FROM calama_ot_ejecucion_eventos
     WHERE ejecucion_id = p_ejecucion_id AND tipo = 'pause'
     ORDER BY created_at DESC LIMIT 1;

    UPDATE calama_ot_ejecuciones
       SET estado = 'en_ejecucion',
           tiempo_pausado_segundos = tiempo_pausado_segundos + v_delta,
           tiempo_colacion_segundos = tiempo_colacion_segundos
                + CASE WHEN COALESCE(v_motivo_anterior,'') ILIKE '%colacion%' THEN v_delta ELSE 0 END,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;

    INSERT INTO calama_ot_ejecucion_eventos (ejecucion_id, ot_id, tipo, created_by)
    VALUES (p_ejecucion_id, v_ot_id, 'resume', v_uid);

    UPDATE calama_ordenes_trabajo SET estado = 'en_ejecucion', updated_at = NOW()
     WHERE id = v_ot_id AND estado = 'en_pausa';

    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_reanudar_ejecucion_ot(UUID) TO authenticated;


-- 6.4 Finalizar
CREATE OR REPLACE FUNCTION rpc_calama_finalizar_ejecucion_ot(
    p_ejecucion_id UUID,
    p_avance_final NUMERIC DEFAULT 100,
    p_observacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_estado TEXT;
    v_last TIMESTAMPTZ;
    v_started TIMESTAMPTZ;
    v_ejecutor UUID;
    v_ot_id UUID;
    v_delta_final INT := 0;
    v_total INT;
    v_efectivo INT;
    v_pausado INT;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT estado, last_event_at, started_at, ejecutor_id, ot_id
      INTO v_estado, v_last, v_started, v_ejecutor, v_ot_id
      FROM calama_ot_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Ejecucion no encontrada'; END IF;
    IF v_estado IN ('finalizada','cancelada') THEN
        RAISE EXCEPTION 'Ejecucion ya esta %', v_estado;
    END IF;
    IF v_ejecutor <> v_uid AND NOT fn_calama_puede_planificar() THEN
        RAISE EXCEPTION 'Solo el ejecutor o un planificador puede finalizar';
    END IF;

    -- Si la ejecucion estaba en_ejecucion al finalizar, sumamos el delta a efectivo
    IF v_estado = 'en_ejecucion' THEN
        v_delta_final := EXTRACT(EPOCH FROM (NOW() - v_last))::INT;
    END IF;

    UPDATE calama_ot_ejecuciones
       SET estado = 'finalizada',
           finished_at = NOW(),
           tiempo_efectivo_segundos = tiempo_efectivo_segundos + v_delta_final,
           tiempo_total_segundos = EXTRACT(EPOCH FROM (NOW() - v_started))::INT,
           avance_final = LEAST(GREATEST(p_avance_final, 0), 100),
           observacion_cierre = COALESCE(p_observacion, observacion_cierre),
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id
     RETURNING tiempo_total_segundos, tiempo_efectivo_segundos, tiempo_pausado_segundos
     INTO v_total, v_efectivo, v_pausado;

    INSERT INTO calama_ot_ejecucion_eventos (ejecucion_id, ot_id, tipo, comentario, avance, created_by)
    VALUES (p_ejecucion_id, v_ot_id, 'finish', p_observacion, p_avance_final, v_uid);

    UPDATE calama_ordenes_trabajo
       SET estado = 'finalizada',
           avance_pct = LEAST(GREATEST(p_avance_final, 0), 100),
           fecha_termino_real = NOW(),
           horas_reales = ROUND(v_efectivo::NUMERIC / 3600, 2),
           observaciones_cierre = COALESCE(p_observacion, observaciones_cierre),
           updated_at = NOW()
     WHERE id = v_ot_id;

    UPDATE calama_plan_semanal_ots SET estado_plan = 'finalizada', updated_at = NOW()
     WHERE ot_id = v_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'tiempo_total_seg', v_total,
        'tiempo_efectivo_seg', v_efectivo,
        'tiempo_pausado_seg', v_pausado
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_finalizar_ejecucion_ot(UUID, NUMERIC, TEXT) TO authenticated;


-- ============================================================================
-- ── 7. BITACORA ──────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG20_CALAMA_PLAN_SEMANAL',
        'Plan Semanal Kanban + Ejecucion (PLAY/PAUSA/FINALIZAR)',
        current_user, NOW(), NOW(), 'ok',
        '6 tablas + 3 helpers + 9 RPCs. RLS sin recursion (patron MIG19).'
    );
END $$;


-- ============================================================================
-- ── 8. VERIFICACION FINAL ────────────────────────────────────────────────────
-- ============================================================================
-- Patron defensivo: cada check es un EXISTS escalar dentro de un CTE plano,
-- evitando el patron "ARRAY[CASE WHEN ... FROM unnest(...)]" que da error 42601.
WITH checks AS (
    SELECT
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_planes_semanales')         AS tiene_planes,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_dias')        AS tiene_dias,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_ots')         AS tiene_ots,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_plan_semanal_materiales')  AS tiene_materiales,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_ot_ejecuciones')           AS tiene_ejecuciones,
        EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='calama_ot_ejecucion_eventos')     AS tiene_eventos,
        (to_regprocedure('public.rpc_calama_get_or_create_plan_semanal(uuid,date)') IS NOT NULL)   AS rpc_get_create,
        (to_regprocedure('public.rpc_calama_mover_ot_plan_semanal(uuid,uuid,date,uuid)') IS NOT NULL) AS rpc_mover,
        (to_regprocedure('public.rpc_calama_quitar_ot_plan_semanal(uuid,uuid)') IS NOT NULL)       AS rpc_quitar,
        (to_regprocedure('public.rpc_calama_asignar_responsable_ot_semana(uuid,uuid,uuid)') IS NOT NULL) AS rpc_asignar,
        (to_regprocedure('public.rpc_calama_confirmar_plan_semanal(uuid)') IS NOT NULL)            AS rpc_confirmar,
        (to_regprocedure('public.rpc_calama_iniciar_ejecucion_ot(uuid)') IS NOT NULL)              AS rpc_iniciar,
        (to_regprocedure('public.rpc_calama_pausar_ejecucion_ot(uuid,text)') IS NOT NULL)          AS rpc_pausar,
        (to_regprocedure('public.rpc_calama_reanudar_ejecucion_ot(uuid)') IS NOT NULL)             AS rpc_reanudar,
        (to_regprocedure('public.rpc_calama_finalizar_ejecucion_ot(uuid,numeric,text)') IS NOT NULL) AS rpc_finalizar,
        COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='calama_planes_semanales'), false) AS rls_planes,
        COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='calama_plan_semanal_ots'), false) AS rls_planots,
        COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_ejecuciones'), false)   AS rls_ejec
),
faltantes AS (
    SELECT
        array_remove(ARRAY[
            CASE WHEN NOT tiene_planes        THEN 'calama_planes_semanales' END,
            CASE WHEN NOT tiene_dias          THEN 'calama_plan_semanal_dias' END,
            CASE WHEN NOT tiene_ots           THEN 'calama_plan_semanal_ots' END,
            CASE WHEN NOT tiene_materiales    THEN 'calama_plan_semanal_materiales' END,
            CASE WHEN NOT tiene_ejecuciones   THEN 'calama_ot_ejecuciones' END,
            CASE WHEN NOT tiene_eventos       THEN 'calama_ot_ejecucion_eventos' END
        ]::text[], NULL) AS tablas_faltantes,
        array_remove(ARRAY[
            CASE WHEN NOT rpc_get_create THEN 'rpc_calama_get_or_create_plan_semanal' END,
            CASE WHEN NOT rpc_mover      THEN 'rpc_calama_mover_ot_plan_semanal' END,
            CASE WHEN NOT rpc_quitar     THEN 'rpc_calama_quitar_ot_plan_semanal' END,
            CASE WHEN NOT rpc_asignar    THEN 'rpc_calama_asignar_responsable_ot_semana' END,
            CASE WHEN NOT rpc_confirmar  THEN 'rpc_calama_confirmar_plan_semanal' END,
            CASE WHEN NOT rpc_iniciar    THEN 'rpc_calama_iniciar_ejecucion_ot' END,
            CASE WHEN NOT rpc_pausar     THEN 'rpc_calama_pausar_ejecucion_ot' END,
            CASE WHEN NOT rpc_reanudar   THEN 'rpc_calama_reanudar_ejecucion_ot' END,
            CASE WHEN NOT rpc_finalizar  THEN 'rpc_calama_finalizar_ejecucion_ot' END
        ]::text[], NULL) AS rpcs_faltantes,
        array_remove(ARRAY[
            CASE WHEN NOT rls_planes  THEN 'calama_planes_semanales' END,
            CASE WHEN NOT rls_planots THEN 'calama_plan_semanal_ots' END,
            CASE WHEN NOT rls_ejec    THEN 'calama_ot_ejecuciones' END
        ]::text[], NULL) AS rls_desactivada
    FROM checks
)
SELECT
    CASE
        WHEN cardinality(tablas_faltantes) > 0
          OR cardinality(rpcs_faltantes)   > 0
          OR cardinality(rls_desactivada)  > 0
            THEN 'STOP_OPERACION_CALAMA_PLAN_SEMANAL'
        ELSE 'OK_OPERACION_CALAMA_PLAN_SEMANAL'
    END                                                              AS resultado,
    COALESCE(NULLIF(array_to_string(array_remove(ARRAY[
        CASE WHEN cardinality(tablas_faltantes) > 0
             THEN 'Tablas faltantes: ' || array_to_string(tablas_faltantes, ', ') END,
        CASE WHEN cardinality(rpcs_faltantes) > 0
             THEN 'RPCs faltantes: ' || array_to_string(rpcs_faltantes, ', ') END,
        CASE WHEN cardinality(rls_desactivada) > 0
             THEN 'RLS DESACTIVADA en: ' || array_to_string(rls_desactivada, ', ') END
    ]::text[], NULL), ' | '), ''),
        '6 tablas + 9 RPCs + RLS activa.')                           AS detalle,
    cardinality(tablas_faltantes)                                    AS tablas_faltantes_count,
    cardinality(rpcs_faltantes)                                      AS rpcs_faltantes_count,
    cardinality(rls_desactivada)                                     AS rls_desactivada_count,
    NOW()                                                            AS chequeado_en
FROM faltantes;
