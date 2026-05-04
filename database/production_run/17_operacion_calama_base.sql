-- ============================================================================
-- 17_operacion_calama_base.sql
-- ----------------------------------------------------------------------------
-- Modulo Operacion Calama (FASE 1 — base SQL).
--
-- ALCANCE:
--   - 12 tablas calama_* (planificacion, tareas maestro, OT, subtareas,
--     precheck/liberacion, avances, evidencias, observaciones, no ejecucion,
--     roles proyecto, faenas, lineas de negocio).
--   - 3 vistas (OEE diario, Curva S, OT ejecutables).
--   - 6 RPCs SECURITY DEFINER (listar/iniciar/avance/finalizar/no-ejec/curva-s).
--   - RLS estricta en 12 tablas. anon SIN ACCESO.
--   - Seeds: 3 faenas (Lomas Bayas, Centinela, Spence) + 3 lineas de negocio.
--   - Bitacora + verificacion final con codigo OK / WARNING / STOP.
--
-- DEPENDENCIAS PREVIAS:
--   - usuarios_perfil + faenas + contratos + fn_user_rol() existentes.
--   - operacion_migraciones_log existe (paso 03).
--
-- IDEMPOTENCIA:
--   - CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION/VIEW.
--   - DROP POLICY IF EXISTS antes de cada CREATE POLICY.
--   - Seeds con ON CONFLICT DO NOTHING (codigo UNIQUE).
--   - DDL extra (constraints, triggers) protegido con DO blocks.
--
-- AISLACION (REGLAS USUARIO):
--   - NO toca rol_usuario_enum global.
--   - NO toca QR backend (mig 14, 14B, 14B2, 14C, 14D).
--   - NO toca mig 55, 56, 57.
--   - Crea tabla calama_roles_proyecto (B2) en lugar de extender el enum.
--   - Crea tabla calama_evidencias dedicada (en lugar de extender CHECK
--     constraint de archivos_evidencia → minimiza acoplamiento con QR).
--   - Crea calama_faenas separada con FK opcional a faenas(id).
--
-- RLS RESUMEN:
--   anon                                            → SIN ACCESO.
--   administrador / gerencia / subgerente_operaciones → todo (admin global).
--   jefe_sucursal / planificador_calama /
--     supervisor_calama (calama_roles_proyecto) +
--     planificador / supervisor / jefe_operaciones    → planificacion + lectura total.
--   operador_calama (calama_roles_proyecto)         → solo OTs asignadas.
--   auditor_calama / auditor                        → solo lectura.
-- ============================================================================


-- ============================================================================
-- ── 0. PRECHECK DE DEPENDENCIAS ──────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='usuarios_perfil') THEN
        RAISE EXCEPTION 'STOP — tabla usuarios_perfil no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='faenas') THEN
        RAISE EXCEPTION 'STOP — tabla faenas no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='contratos') THEN
        RAISE EXCEPTION 'STOP — tabla contratos no existe.';
    END IF;
    IF to_regprocedure('public.fn_user_rol()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_user_rol() no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        RAISE EXCEPTION 'STOP — operacion_migraciones_log no existe (ejecutar paso 03).';
    END IF;
END $$;


-- ============================================================================
-- ── 1. HELPER FUNCTIONS (RLS) ────────────────────────────────────────────────
-- ============================================================================

-- 1.1 Rol global del caller (delega en fn_user_rol existente).
CREATE OR REPLACE FUNCTION fn_calama_rol_global()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_user_rol();
$$;

-- 1.2 Rol especifico del modulo Calama desde calama_roles_proyecto.
--     NULL si el usuario no esta autorizado en el modulo.
CREATE OR REPLACE FUNCTION fn_calama_rol_proyecto()
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_rol TEXT;
BEGIN
    IF v_uid IS NULL THEN RETURN NULL; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_roles_proyecto') THEN
        RETURN NULL;
    END IF;
    SELECT rol_calama INTO v_rol
      FROM calama_roles_proyecto
     WHERE usuario_id = v_uid AND activo = true
     LIMIT 1;
    RETURN v_rol;
END $$;

-- 1.3 Admin global (ve y modifica todo).
CREATE OR REPLACE FUNCTION fn_calama_es_admin_global()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_user_rol() IN ('administrador','gerencia','subgerente_operaciones');
$$;

-- 1.4 Puede planificar (gestionar tareas maestro, OTs, asignaciones).
CREATE OR REPLACE FUNCTION fn_calama_puede_planificar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT
        fn_calama_es_admin_global()
        OR fn_user_rol() IN ('planificador','supervisor','jefe_operaciones')
        OR fn_calama_rol_proyecto() IN ('jefe_sucursal','planificador_calama','supervisor_calama');
$$;

-- 1.5 Puede ver (cualquier rol con acceso al modulo, incluyendo operador y auditor).
CREATE OR REPLACE FUNCTION fn_calama_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT
        fn_calama_es_admin_global()
        OR fn_calama_puede_planificar()
        OR fn_user_rol() IN ('auditor')
        OR fn_calama_rol_proyecto() IN (
            'jefe_sucursal','planificador_calama','supervisor_calama',
            'operador_calama','auditor_calama'
        );
$$;

-- 1.6 Es operador Calama (acceso restringido a OTs propias).
CREATE OR REPLACE FUNCTION fn_calama_es_operador()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_calama_rol_proyecto() = 'operador_calama'
       AND NOT fn_calama_puede_planificar();
$$;

GRANT EXECUTE ON FUNCTION fn_calama_rol_global()        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_rol_proyecto()      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_es_admin_global()   TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_puede_planificar()  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_puede_ver()         TO authenticated;
GRANT EXECUTE ON FUNCTION fn_calama_es_operador()       TO authenticated;


-- ============================================================================
-- ── 2. TABLAS ────────────────────────────────────────────────────────────────
-- ============================================================================

-- 2.1 Lineas de negocio (catalogo)
CREATE TABLE IF NOT EXISTS calama_lineas_negocio (
    codigo          VARCHAR(40) PRIMARY KEY,
    nombre          VARCHAR(120) NOT NULL,
    descripcion     TEXT,
    activo          BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2.2 Faenas Calama (maestro propio del modulo, FK opcional a faenas core)
CREATE TABLE IF NOT EXISTS calama_faenas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo          VARCHAR(40) UNIQUE NOT NULL,
    nombre          VARCHAR(200) NOT NULL,
    mandante        VARCHAR(200),
    region          VARCHAR(100) DEFAULT 'Antofagasta',
    comuna          VARCHAR(100),
    faena_id        UUID REFERENCES faenas(id),
    activo          BOOLEAN NOT NULL DEFAULT true,
    notas           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_faenas_activo ON calama_faenas (activo);

-- 2.3 Roles del modulo (B2: tabla propia, no toca rol_usuario_enum)
CREATE TABLE IF NOT EXISTS calama_roles_proyecto (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    rol_calama      VARCHAR(40) NOT NULL,
    faena_calama_id UUID REFERENCES calama_faenas(id),
    activo          BOOLEAN NOT NULL DEFAULT true,
    asignado_por    UUID REFERENCES auth.users(id),
    asignado_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revocado_at     TIMESTAMPTZ,
    notas           TEXT,
    CONSTRAINT chk_calama_roles_valores CHECK (rol_calama IN (
        'jefe_sucursal','planificador_calama','supervisor_calama',
        'operador_calama','auditor_calama'
    )),
    CONSTRAINT uq_calama_roles_unique_active UNIQUE (usuario_id, rol_calama, faena_calama_id)
);
CREATE INDEX IF NOT EXISTS idx_calama_roles_usuario ON calama_roles_proyecto (usuario_id) WHERE activo = true;
CREATE INDEX IF NOT EXISTS idx_calama_roles_faena   ON calama_roles_proyecto (faena_calama_id) WHERE activo = true;

-- 2.4 Planificaciones (proyectos / paquetes de obra)
CREATE TABLE IF NOT EXISTS calama_planificaciones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              VARCHAR(60) UNIQUE NOT NULL,
    nombre              VARCHAR(250) NOT NULL,
    faena_calama_id     UUID NOT NULL REFERENCES calama_faenas(id),
    contrato_id         UUID REFERENCES contratos(id),
    linea_negocio       VARCHAR(40) NOT NULL REFERENCES calama_lineas_negocio(codigo),
    fecha_inicio_plan   DATE NOT NULL,
    fecha_termino_plan  DATE NOT NULL,
    fecha_inicio_real   DATE,
    fecha_termino_real  DATE,
    monto_estimado      NUMERIC(15,2),
    moneda              VARCHAR(3) NOT NULL DEFAULT 'CLP',
    estado              VARCHAR(20) NOT NULL DEFAULT 'planificada',
    avance_planificado  NUMERIC(5,2) NOT NULL DEFAULT 0,
    avance_real         NUMERIC(5,2) NOT NULL DEFAULT 0,
    responsable_id      UUID REFERENCES usuarios_perfil(id),
    descripcion         TEXT,
    fuente_excel        VARCHAR(250),
    created_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_plan_estado CHECK (estado IN (
        'planificada','en_curso','suspendida','finalizada','cancelada'
    )),
    CONSTRAINT chk_calama_plan_fechas CHECK (fecha_termino_plan >= fecha_inicio_plan),
    CONSTRAINT chk_calama_plan_avance CHECK (
        avance_planificado BETWEEN 0 AND 100
        AND avance_real BETWEEN 0 AND 100
    )
);
CREATE INDEX IF NOT EXISTS idx_calama_plan_faena   ON calama_planificaciones (faena_calama_id);
CREATE INDEX IF NOT EXISTS idx_calama_plan_estado  ON calama_planificaciones (estado);
CREATE INDEX IF NOT EXISTS idx_calama_plan_linea   ON calama_planificaciones (linea_negocio);

-- 2.5 Tareas maestro (catalogo tipificado por linea + sub_linea — D1)
CREATE TABLE IF NOT EXISTS calama_tareas_maestro (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              VARCHAR(60) UNIQUE NOT NULL,
    nombre              VARCHAR(250) NOT NULL,
    linea_negocio       VARCHAR(40) NOT NULL REFERENCES calama_lineas_negocio(codigo),
    sub_linea           VARCHAR(60) NOT NULL,
    descripcion         TEXT,
    unidad              VARCHAR(20) NOT NULL DEFAULT 'gl',
    horas_estimadas     NUMERIC(8,2),
    requiere_vehiculo_especial BOOLEAN NOT NULL DEFAULT false,
    requiere_permiso_trabajo   BOOLEAN NOT NULL DEFAULT false,
    requiere_charla_ods        BOOLEAN NOT NULL DEFAULT true,
    activa              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_tareas_sub_linea_validas CHECK (
        (linea_negocio = 'combustibles'    AND sub_linea IN ('plataforma_fija','plataforma_movil','calibracion'))
     OR (linea_negocio = 'lubricantes'     AND sub_linea IN ('plataforma_fija','plataforma_movil','calibracion_equipos'))
     OR (linea_negocio = 'mejoras_civiles' AND sub_linea IN ('refaccion','pintura','reparaciones','mejoras'))
    )
);
CREATE INDEX IF NOT EXISTS idx_calama_tareas_linea     ON calama_tareas_maestro (linea_negocio, sub_linea);
CREATE INDEX IF NOT EXISTS idx_calama_tareas_activa    ON calama_tareas_maestro (activa);

-- 2.6 Ordenes de trabajo (paralelas a ordenes_trabajo de mantencion — semantica distinta)
CREATE TABLE IF NOT EXISTS calama_ordenes_trabajo (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio               VARCHAR(40) UNIQUE NOT NULL,
    planificacion_id    UUID NOT NULL REFERENCES calama_planificaciones(id),
    tarea_maestro_id    UUID REFERENCES calama_tareas_maestro(id),
    faena_calama_id     UUID NOT NULL REFERENCES calama_faenas(id),
    titulo              VARCHAR(250) NOT NULL,
    descripcion         TEXT,
    fecha_programada    DATE NOT NULL,
    hora_inicio_plan    TIME,
    hora_termino_plan   TIME,
    fecha_inicio_real   TIMESTAMPTZ,
    fecha_termino_real  TIMESTAMPTZ,
    horas_estimadas     NUMERIC(8,2),
    horas_reales        NUMERIC(8,2),
    avance_pct          NUMERIC(5,2) NOT NULL DEFAULT 0,
    estado              VARCHAR(20) NOT NULL DEFAULT 'planificada',
    prioridad           VARCHAR(10) NOT NULL DEFAULT 'normal',
    responsable_id      UUID REFERENCES usuarios_perfil(id),
    jefe_sucursal_id    UUID REFERENCES usuarios_perfil(id),
    requiere_vehiculo_especial BOOLEAN NOT NULL DEFAULT false,
    detalle_vehiculo_especial  TEXT,
    observaciones_apertura     TEXT,
    observaciones_cierre       TEXT,
    firma_responsable_url      TEXT,
    firma_jefe_url             TEXT,
    cliente_uuid        UUID UNIQUE,
    created_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_ot_estado CHECK (estado IN (
        'planificada','liberada','en_ejecucion','en_pausa','finalizada',
        'no_ejecutada','cancelada'
    )),
    CONSTRAINT chk_calama_ot_prioridad CHECK (prioridad IN ('baja','normal','alta','critica')),
    CONSTRAINT chk_calama_ot_avance CHECK (avance_pct BETWEEN 0 AND 100)
);
CREATE INDEX IF NOT EXISTS idx_calama_ot_plan         ON calama_ordenes_trabajo (planificacion_id);
CREATE INDEX IF NOT EXISTS idx_calama_ot_faena_fecha  ON calama_ordenes_trabajo (faena_calama_id, fecha_programada);
CREATE INDEX IF NOT EXISTS idx_calama_ot_responsable  ON calama_ordenes_trabajo (responsable_id);
CREATE INDEX IF NOT EXISTS idx_calama_ot_estado       ON calama_ordenes_trabajo (estado);
CREATE INDEX IF NOT EXISTS idx_calama_ot_fecha_prog   ON calama_ordenes_trabajo (fecha_programada DESC);

-- 2.7 Subtareas dentro de una OT
CREATE TABLE IF NOT EXISTS calama_ot_subtareas (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    orden               INT NOT NULL,
    descripcion         TEXT NOT NULL,
    cantidad_plan       NUMERIC(12,2),
    cantidad_real       NUMERIC(12,2),
    unidad              VARCHAR(20) NOT NULL DEFAULT 'gl',
    avance_pct          NUMERIC(5,2) NOT NULL DEFAULT 0,
    estado              VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    asignado_id         UUID REFERENCES usuarios_perfil(id),
    requiere_evidencia_foto BOOLEAN NOT NULL DEFAULT false,
    completada_at       TIMESTAMPTZ,
    completada_por      UUID REFERENCES usuarios_perfil(id),
    observaciones       TEXT,
    cliente_uuid        UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_calama_subt_orden UNIQUE (ot_id, orden),
    CONSTRAINT chk_calama_subt_estado CHECK (estado IN (
        'pendiente','en_ejecucion','completada','no_aplica'
    )),
    CONSTRAINT chk_calama_subt_avance CHECK (avance_pct BETWEEN 0 AND 100)
);
CREATE INDEX IF NOT EXISTS idx_calama_subt_ot         ON calama_ot_subtareas (ot_id, orden);
CREATE INDEX IF NOT EXISTS idx_calama_subt_estado     ON calama_ot_subtareas (estado);
CREATE INDEX IF NOT EXISTS idx_calama_subt_asignado   ON calama_ot_subtareas (asignado_id) WHERE asignado_id IS NOT NULL;

-- 2.8 Precheck / liberacion (1:1 con OT, GENERATED column)
CREATE TABLE IF NOT EXISTS calama_ot_precheck (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id                       UUID UNIQUE NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    epp_completo                BOOLEAN NOT NULL DEFAULT false,
    herramientas_ok             BOOLEAN NOT NULL DEFAULT false,
    vehiculo_confirmado         BOOLEAN NOT NULL DEFAULT false,
    requiere_vehiculo_especial  BOOLEAN NOT NULL DEFAULT false,
    vehiculo_especial_confirmado BOOLEAN NOT NULL DEFAULT false,
    charla_ods_realizada        BOOLEAN NOT NULL DEFAULT false,
    permisos_trabajo_ok         BOOLEAN NOT NULL DEFAULT false,
    observaciones               TEXT,
    revisado_por                UUID REFERENCES usuarios_perfil(id),
    revisado_at                 TIMESTAMPTZ,
    -- Columna generada: la OT esta liberada cuando todos los gates pasan.
    liberada_para_ejecucion     BOOLEAN GENERATED ALWAYS AS (
        epp_completo = true
        AND herramientas_ok = true
        AND vehiculo_confirmado = true
        AND charla_ods_realizada = true
        AND permisos_trabajo_ok = true
        AND (NOT requiere_vehiculo_especial OR vehiculo_especial_confirmado = true)
    ) STORED,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_calama_precheck_libre ON calama_ot_precheck (liberada_para_ejecucion);

-- 2.9 Avances diarios (granularidad: una fila por avance reportado)
CREATE TABLE IF NOT EXISTS calama_avances (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    subtarea_id         UUID REFERENCES calama_ot_subtareas(id) ON DELETE CASCADE,
    fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
    avance_acumulado    NUMERIC(5,2) NOT NULL,
    delta_avance        NUMERIC(5,2),
    horas_trabajadas    NUMERIC(6,2),
    cantidad_ejecutada  NUMERIC(12,2),
    descripcion         TEXT,
    gps_lat             NUMERIC(10,7),
    gps_lng             NUMERIC(10,7),
    reportado_por       UUID NOT NULL REFERENCES usuarios_perfil(id),
    cliente_uuid        UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_avance_pct CHECK (avance_acumulado BETWEEN 0 AND 100)
);
CREATE INDEX IF NOT EXISTS idx_calama_avance_ot        ON calama_avances (ot_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_calama_avance_subt      ON calama_avances (subtarea_id) WHERE subtarea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_avance_fecha     ON calama_avances (fecha DESC);

-- 2.10 Evidencias (tabla dedicada para aislamiento estricto)
CREATE TABLE IF NOT EXISTS calama_evidencias (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contexto            VARCHAR(20) NOT NULL,
    ot_id               UUID REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    subtarea_id         UUID REFERENCES calama_ot_subtareas(id) ON DELETE CASCADE,
    avance_id           UUID REFERENCES calama_avances(id) ON DELETE CASCADE,
    tipo                VARCHAR(20) NOT NULL,
    archivo_url         TEXT NOT NULL,
    storage_path        TEXT,
    tamano_bytes        BIGINT,
    mime_type           VARCHAR(80),
    descripcion         TEXT,
    gps_lat             NUMERIC(10,7),
    gps_lng             NUMERIC(10,7),
    created_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_evid_contexto CHECK (contexto IN (
        'ot_apertura','ot_avance','ot_cierre','subtarea','observacion','no_ejecucion','firma'
    )),
    CONSTRAINT chk_calama_evid_tipo CHECK (tipo IN ('foto','video','firma','documento','pdf')),
    CONSTRAINT chk_calama_evid_link CHECK (
        ot_id IS NOT NULL OR subtarea_id IS NOT NULL OR avance_id IS NOT NULL
    )
);
CREATE INDEX IF NOT EXISTS idx_calama_evid_ot     ON calama_evidencias (ot_id) WHERE ot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_subt   ON calama_evidencias (subtarea_id) WHERE subtarea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_avance ON calama_evidencias (avance_id) WHERE avance_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_evid_ctx    ON calama_evidencias (contexto);

-- 2.11 Observaciones (no son fallas — son notas operacionales)
CREATE TABLE IF NOT EXISTS calama_observaciones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id               UUID REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    subtarea_id         UUID REFERENCES calama_ot_subtareas(id) ON DELETE CASCADE,
    tipo                VARCHAR(30) NOT NULL DEFAULT 'general',
    severidad           VARCHAR(10) NOT NULL DEFAULT 'info',
    titulo              VARCHAR(200),
    detalle             TEXT NOT NULL,
    requiere_seguimiento BOOLEAN NOT NULL DEFAULT false,
    cerrada             BOOLEAN NOT NULL DEFAULT false,
    cerrada_por         UUID REFERENCES usuarios_perfil(id),
    cerrada_at          TIMESTAMPTZ,
    creada_por          UUID NOT NULL REFERENCES usuarios_perfil(id),
    cliente_uuid        UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_obs_severidad CHECK (severidad IN ('info','baja','media','alta')),
    CONSTRAINT chk_calama_obs_link CHECK (ot_id IS NOT NULL OR subtarea_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_calama_obs_ot       ON calama_observaciones (ot_id) WHERE ot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_obs_subt     ON calama_observaciones (subtarea_id) WHERE subtarea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calama_obs_pend     ON calama_observaciones (cerrada) WHERE cerrada = false;

-- 2.12 Eventos de no ejecucion
CREATE TABLE IF NOT EXISTS calama_eventos_no_ejecucion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id               UUID NOT NULL REFERENCES calama_ordenes_trabajo(id) ON DELETE CASCADE,
    causa               VARCHAR(40) NOT NULL,
    detalle             TEXT,
    fecha_evento        DATE NOT NULL DEFAULT CURRENT_DATE,
    horas_perdidas      NUMERIC(6,2),
    impacto_avance      NUMERIC(5,2),
    reportado_por       UUID NOT NULL REFERENCES usuarios_perfil(id),
    cliente_uuid        UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_calama_no_ejec_causa CHECK (causa IN (
        'falta_personal','falta_materiales','falta_equipo','falta_permiso',
        'condiciones_climaticas','accidente','reprogramacion_mandante',
        'fallo_servicio','otro'
    ))
);
CREATE INDEX IF NOT EXISTS idx_calama_no_ejec_ot     ON calama_eventos_no_ejecucion (ot_id);
CREATE INDEX IF NOT EXISTS idx_calama_no_ejec_fecha  ON calama_eventos_no_ejecucion (fecha_evento DESC);


-- ============================================================================
-- ── 3. TRIGGERS updated_at ──────────────────────────────────────────────────
-- ============================================================================

-- Reusa fn_set_updated_at si existe; si no, la crea local.
DO $$ BEGIN
    IF to_regprocedure('public.fn_set_updated_at()') IS NULL THEN
        EXECUTE $f$
            CREATE OR REPLACE FUNCTION fn_set_updated_at()
            RETURNS TRIGGER LANGUAGE plpgsql AS $body$
            BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
            $body$;
        $f$;
    END IF;
END $$;

DO $$
DECLARE
    v_tabla TEXT;
BEGIN
    FOR v_tabla IN SELECT unnest(ARRAY[
        'calama_faenas','calama_planificaciones','calama_tareas_maestro',
        'calama_ordenes_trabajo','calama_ot_subtareas','calama_ot_precheck'
    ]) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger
             WHERE tgname = 'trg_' || v_tabla || '_updated_at'
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
-- ── 4. RLS — habilitar y crear policies ──────────────────────────────────────
-- ============================================================================

ALTER TABLE calama_lineas_negocio        ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_faenas                ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_roles_proyecto        ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_planificaciones       ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_tareas_maestro        ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_ordenes_trabajo       ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_ot_subtareas          ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_ot_precheck           ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_avances               ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_evidencias            ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_observaciones         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calama_eventos_no_ejecucion  ENABLE ROW LEVEL SECURITY;


-- 4.1 calama_lineas_negocio (catalogo de lectura amplia para el modulo)
DROP POLICY IF EXISTS pol_calama_lineas_select ON calama_lineas_negocio;
CREATE POLICY pol_calama_lineas_select ON calama_lineas_negocio
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_lineas_modif ON calama_lineas_negocio;
CREATE POLICY pol_calama_lineas_modif ON calama_lineas_negocio
    FOR ALL TO authenticated
    USING (fn_calama_es_admin_global())
    WITH CHECK (fn_calama_es_admin_global());

-- 4.2 calama_faenas
DROP POLICY IF EXISTS pol_calama_faenas_select ON calama_faenas;
CREATE POLICY pol_calama_faenas_select ON calama_faenas
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_faenas_modif ON calama_faenas;
CREATE POLICY pol_calama_faenas_modif ON calama_faenas
    FOR ALL TO authenticated
    USING (fn_calama_es_admin_global())
    WITH CHECK (fn_calama_es_admin_global());

-- 4.3 calama_roles_proyecto
--   - Admin global: gestion total.
--   - Usuario: puede ver SU propia fila.
DROP POLICY IF EXISTS pol_calama_roles_select_admin ON calama_roles_proyecto;
CREATE POLICY pol_calama_roles_select_admin ON calama_roles_proyecto
    FOR SELECT TO authenticated
    USING (fn_calama_es_admin_global() OR usuario_id = auth.uid());
DROP POLICY IF EXISTS pol_calama_roles_modif ON calama_roles_proyecto;
CREATE POLICY pol_calama_roles_modif ON calama_roles_proyecto
    FOR ALL TO authenticated
    USING (fn_calama_es_admin_global())
    WITH CHECK (fn_calama_es_admin_global());

-- 4.4 calama_planificaciones
DROP POLICY IF EXISTS pol_calama_plan_select ON calama_planificaciones;
CREATE POLICY pol_calama_plan_select ON calama_planificaciones
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_plan_modif ON calama_planificaciones;
CREATE POLICY pol_calama_plan_modif ON calama_planificaciones
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- 4.5 calama_tareas_maestro
DROP POLICY IF EXISTS pol_calama_tareas_select ON calama_tareas_maestro;
CREATE POLICY pol_calama_tareas_select ON calama_tareas_maestro
    FOR SELECT TO authenticated
    USING (fn_calama_puede_ver());
DROP POLICY IF EXISTS pol_calama_tareas_modif ON calama_tareas_maestro;
CREATE POLICY pol_calama_tareas_modif ON calama_tareas_maestro
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- 4.6 calama_ordenes_trabajo
--   - Admin/planning: SELECT/INSERT/UPDATE/DELETE.
--   - Operador: SELECT solo OTs donde es responsable o tiene subtarea asignada.
--                UPDATE: solo OTs propias y solo en estados de ejecucion.
DROP POLICY IF EXISTS pol_calama_ot_select_planning ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_select_planning ON calama_ordenes_trabajo
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
    );

DROP POLICY IF EXISTS pol_calama_ot_select_operador ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_select_operador ON calama_ordenes_trabajo
    FOR SELECT TO authenticated
    USING (
        fn_calama_es_operador()
        AND (
            responsable_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM calama_ot_subtareas s
                 WHERE s.ot_id = calama_ordenes_trabajo.id
                   AND s.asignado_id = auth.uid()
            )
        )
    );

DROP POLICY IF EXISTS pol_calama_ot_insert_planning ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_insert_planning ON calama_ordenes_trabajo
    FOR INSERT TO authenticated
    WITH CHECK (fn_calama_puede_planificar());

DROP POLICY IF EXISTS pol_calama_ot_update_planning ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_update_planning ON calama_ordenes_trabajo
    FOR UPDATE TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

DROP POLICY IF EXISTS pol_calama_ot_update_operador ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_update_operador ON calama_ordenes_trabajo
    FOR UPDATE TO authenticated
    USING (
        fn_calama_es_operador()
        AND responsable_id = auth.uid()
        AND estado IN ('liberada','en_ejecucion','en_pausa')
    )
    WITH CHECK (
        fn_calama_es_operador()
        AND responsable_id = auth.uid()
        AND estado IN ('liberada','en_ejecucion','en_pausa','finalizada')
    );

DROP POLICY IF EXISTS pol_calama_ot_delete_admin ON calama_ordenes_trabajo;
CREATE POLICY pol_calama_ot_delete_admin ON calama_ordenes_trabajo
    FOR DELETE TO authenticated
    USING (fn_calama_es_admin_global());

-- 4.7 calama_ot_subtareas
DROP POLICY IF EXISTS pol_calama_subt_select ON calama_ot_subtareas;
CREATE POLICY pol_calama_subt_select ON calama_ot_subtareas
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                asignado_id = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM calama_ordenes_trabajo o
                     WHERE o.id = calama_ot_subtareas.ot_id
                       AND o.responsable_id = auth.uid()
                )
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_subt_modif_planning ON calama_ot_subtareas;
CREATE POLICY pol_calama_subt_modif_planning ON calama_ot_subtareas
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());
DROP POLICY IF EXISTS pol_calama_subt_update_op ON calama_ot_subtareas;
CREATE POLICY pol_calama_subt_update_op ON calama_ot_subtareas
    FOR UPDATE TO authenticated
    USING (
        fn_calama_es_operador()
        AND (
            asignado_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM calama_ordenes_trabajo o
                 WHERE o.id = calama_ot_subtareas.ot_id
                   AND o.responsable_id = auth.uid()
            )
        )
    )
    WITH CHECK (
        fn_calama_es_operador()
        AND (
            asignado_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM calama_ordenes_trabajo o
                 WHERE o.id = calama_ot_subtareas.ot_id
                   AND o.responsable_id = auth.uid()
            )
        )
    );

-- 4.8 calama_ot_precheck
DROP POLICY IF EXISTS pol_calama_precheck_select ON calama_ot_precheck;
CREATE POLICY pol_calama_precheck_select ON calama_ot_precheck
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND EXISTS (
                SELECT 1 FROM calama_ordenes_trabajo o
                 WHERE o.id = calama_ot_precheck.ot_id
                   AND o.responsable_id = auth.uid()
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_precheck_modif ON calama_ot_precheck;
CREATE POLICY pol_calama_precheck_modif ON calama_ot_precheck
    FOR ALL TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- 4.9 calama_avances
DROP POLICY IF EXISTS pol_calama_avance_select ON calama_avances;
CREATE POLICY pol_calama_avance_select ON calama_avances
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                reportado_por = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM calama_ordenes_trabajo o
                     WHERE o.id = calama_avances.ot_id
                       AND o.responsable_id = auth.uid()
                )
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_avance_insert ON calama_avances;
CREATE POLICY pol_calama_avance_insert ON calama_avances
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR (
            fn_calama_es_operador()
            AND reportado_por = auth.uid()
            AND EXISTS (
                SELECT 1 FROM calama_ordenes_trabajo o
                 WHERE o.id = calama_avances.ot_id
                   AND o.responsable_id = auth.uid()
                   AND o.estado IN ('liberada','en_ejecucion','en_pausa')
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_avance_modif_admin ON calama_avances;
CREATE POLICY pol_calama_avance_modif_admin ON calama_avances
    FOR UPDATE TO authenticated
    USING (fn_calama_es_admin_global())
    WITH CHECK (fn_calama_es_admin_global());
DROP POLICY IF EXISTS pol_calama_avance_delete_admin ON calama_avances;
CREATE POLICY pol_calama_avance_delete_admin ON calama_avances
    FOR DELETE TO authenticated
    USING (fn_calama_es_admin_global());

-- 4.10 calama_evidencias
DROP POLICY IF EXISTS pol_calama_evid_select ON calama_evidencias;
CREATE POLICY pol_calama_evid_select ON calama_evidencias
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                created_by = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM calama_ordenes_trabajo o
                     WHERE o.id = calama_evidencias.ot_id
                       AND o.responsable_id = auth.uid()
                )
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_evid_insert ON calama_evidencias;
CREATE POLICY pol_calama_evid_insert ON calama_evidencias
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR (
            fn_calama_es_operador()
            AND created_by = auth.uid()
        )
    );
DROP POLICY IF EXISTS pol_calama_evid_modif_admin ON calama_evidencias;
CREATE POLICY pol_calama_evid_modif_admin ON calama_evidencias
    FOR UPDATE TO authenticated
    USING (fn_calama_es_admin_global())
    WITH CHECK (fn_calama_es_admin_global());
DROP POLICY IF EXISTS pol_calama_evid_delete_admin ON calama_evidencias;
CREATE POLICY pol_calama_evid_delete_admin ON calama_evidencias
    FOR DELETE TO authenticated
    USING (fn_calama_es_admin_global());

-- 4.11 calama_observaciones
DROP POLICY IF EXISTS pol_calama_obs_select ON calama_observaciones;
CREATE POLICY pol_calama_obs_select ON calama_observaciones
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND (
                creada_por = auth.uid()
                OR EXISTS (
                    SELECT 1 FROM calama_ordenes_trabajo o
                     WHERE o.id = calama_observaciones.ot_id
                       AND o.responsable_id = auth.uid()
                )
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_obs_insert ON calama_observaciones;
CREATE POLICY pol_calama_obs_insert ON calama_observaciones
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR (fn_calama_es_operador() AND creada_por = auth.uid())
    );
DROP POLICY IF EXISTS pol_calama_obs_update ON calama_observaciones;
CREATE POLICY pol_calama_obs_update ON calama_observaciones
    FOR UPDATE TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());

-- 4.12 calama_eventos_no_ejecucion
DROP POLICY IF EXISTS pol_calama_no_ejec_select ON calama_eventos_no_ejecucion;
CREATE POLICY pol_calama_no_ejec_select ON calama_eventos_no_ejecucion
    FOR SELECT TO authenticated
    USING (
        fn_calama_puede_planificar()
        OR fn_user_rol() = 'auditor'
        OR fn_calama_rol_proyecto() = 'auditor_calama'
        OR (
            fn_calama_es_operador()
            AND EXISTS (
                SELECT 1 FROM calama_ordenes_trabajo o
                 WHERE o.id = calama_eventos_no_ejecucion.ot_id
                   AND o.responsable_id = auth.uid()
            )
        )
    );
DROP POLICY IF EXISTS pol_calama_no_ejec_insert ON calama_eventos_no_ejecucion;
CREATE POLICY pol_calama_no_ejec_insert ON calama_eventos_no_ejecucion
    FOR INSERT TO authenticated
    WITH CHECK (
        fn_calama_puede_planificar()
        OR (fn_calama_es_operador() AND reportado_por = auth.uid())
    );
DROP POLICY IF EXISTS pol_calama_no_ejec_modif_admin ON calama_eventos_no_ejecucion;
CREATE POLICY pol_calama_no_ejec_modif_admin ON calama_eventos_no_ejecucion
    FOR UPDATE TO authenticated
    USING (fn_calama_puede_planificar())
    WITH CHECK (fn_calama_puede_planificar());


-- ============================================================================
-- ── 5. VISTAS ────────────────────────────────────────────────────────────────
-- ============================================================================

-- 5.1 OT ejecutables hoy/proximo (precheck liberado + estado coherente)
CREATE OR REPLACE VIEW v_calama_ot_ejecutable AS
SELECT
    ot.id                       AS ot_id,
    ot.folio,
    ot.titulo,
    ot.faena_calama_id,
    f.nombre                    AS faena_nombre,
    ot.planificacion_id,
    p.codigo                    AS planificacion_codigo,
    p.linea_negocio,
    ot.fecha_programada,
    ot.responsable_id,
    up.nombre_completo          AS responsable_nombre,
    ot.prioridad,
    ot.estado,
    ot.avance_pct,
    pc.liberada_para_ejecucion,
    pc.epp_completo,
    pc.herramientas_ok,
    pc.vehiculo_confirmado,
    pc.charla_ods_realizada,
    pc.permisos_trabajo_ok,
    ot.requiere_vehiculo_especial,
    pc.vehiculo_especial_confirmado
FROM calama_ordenes_trabajo ot
JOIN calama_faenas f                ON f.id = ot.faena_calama_id
JOIN calama_planificaciones p       ON p.id = ot.planificacion_id
LEFT JOIN calama_ot_precheck pc     ON pc.ot_id = ot.id
LEFT JOIN usuarios_perfil up        ON up.id = ot.responsable_id
WHERE ot.estado IN ('planificada','liberada','en_ejecucion','en_pausa');

-- 5.2 OEE diario por faena/linea (avance promedio + ratio de ejecucion)
CREATE OR REPLACE VIEW v_calama_oee_diario AS
WITH agregado AS (
    SELECT
        ot.faena_calama_id,
        f.nombre                AS faena_nombre,
        p.linea_negocio,
        ot.fecha_programada     AS fecha,
        COUNT(*)                                                         AS ot_total,
        COUNT(*) FILTER (WHERE ot.estado = 'finalizada')                   AS ot_finalizadas,
        COUNT(*) FILTER (WHERE ot.estado = 'en_ejecucion')                 AS ot_en_curso,
        COUNT(*) FILTER (WHERE ot.estado = 'no_ejecutada')                 AS ot_no_ejec,
        COALESCE(AVG(ot.avance_pct) FILTER (WHERE ot.estado <> 'cancelada'), 0)  AS avance_prom,
        COALESCE(SUM(ot.horas_estimadas), 0)                              AS horas_plan,
        COALESCE(SUM(ot.horas_reales), 0)                                 AS horas_real
    FROM calama_ordenes_trabajo ot
    JOIN calama_faenas f          ON f.id = ot.faena_calama_id
    JOIN calama_planificaciones p ON p.id = ot.planificacion_id
    WHERE ot.estado <> 'cancelada'
    GROUP BY ot.faena_calama_id, f.nombre, p.linea_negocio, ot.fecha_programada
)
SELECT
    faena_calama_id,
    faena_nombre,
    linea_negocio,
    fecha,
    ot_total,
    ot_finalizadas,
    ot_en_curso,
    ot_no_ejec,
    ROUND(avance_prom, 2)                                              AS avance_promedio_pct,
    horas_plan,
    horas_real,
    CASE WHEN horas_plan > 0
         THEN ROUND((horas_real / horas_plan) * 100, 2)
         ELSE NULL END                                                  AS ratio_horas_pct,
    CASE WHEN ot_total > 0
         THEN ROUND((ot_finalizadas::NUMERIC / ot_total::NUMERIC) * 100, 2)
         ELSE 0 END                                                     AS ratio_finalizadas_pct
FROM agregado;

-- 5.3 Curva S por planificacion (avance acumulado plan vs real por dia)
CREATE OR REPLACE VIEW v_calama_curva_s AS
WITH dias AS (
    SELECT
        p.id              AS planificacion_id,
        p.codigo          AS planificacion_codigo,
        p.faena_calama_id,
        p.linea_negocio,
        d::date           AS fecha
    FROM calama_planificaciones p
    CROSS JOIN LATERAL generate_series(p.fecha_inicio_plan, p.fecha_termino_plan, '1 day') AS d
    WHERE p.estado <> 'cancelada'
),
plan_diario AS (
    -- Avance plan = lineal entre fechas (simplificacion).
    SELECT
        d.planificacion_id,
        d.fecha,
        ROUND(
            ((d.fecha - p.fecha_inicio_plan)::NUMERIC
              / NULLIF((p.fecha_termino_plan - p.fecha_inicio_plan), 0)) * 100, 2
        ) AS avance_plan_pct
    FROM dias d
    JOIN calama_planificaciones p ON p.id = d.planificacion_id
),
real_diario AS (
    SELECT
        ot.planificacion_id,
        a.fecha,
        AVG(a.avance_acumulado) AS avance_real_pct_dia
    FROM calama_avances a
    JOIN calama_ordenes_trabajo ot ON ot.id = a.ot_id
    GROUP BY ot.planificacion_id, a.fecha
),
real_acumulado AS (
    SELECT
        rd.planificacion_id,
        rd.fecha,
        MAX(rd.avance_real_pct_dia) OVER (
            PARTITION BY rd.planificacion_id ORDER BY rd.fecha
        ) AS avance_real_acum
    FROM real_diario rd
)
SELECT
    d.planificacion_id,
    d.planificacion_codigo,
    d.faena_calama_id,
    d.linea_negocio,
    d.fecha,
    LEAST(GREATEST(pd.avance_plan_pct, 0), 100) AS avance_plan_pct,
    COALESCE(ra.avance_real_acum, 0)            AS avance_real_pct
FROM dias d
LEFT JOIN plan_diario pd  ON pd.planificacion_id = d.planificacion_id AND pd.fecha = d.fecha
LEFT JOIN real_acumulado ra ON ra.planificacion_id = d.planificacion_id AND ra.fecha = d.fecha;


-- ============================================================================
-- ── 6. RPCs ──────────────────────────────────────────────────────────────────
-- ============================================================================

-- 6.1 Listar OTs visibles para terreno (operador o supervisor en terreno)
CREATE OR REPLACE FUNCTION rpc_calama_listar_ot_terreno(
    p_fecha DATE DEFAULT CURRENT_DATE,
    p_faena_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_data JSONB;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN
        RAISE EXCEPTION 'Rol no autorizado para Operacion Calama';
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_data
    FROM (
        SELECT
            ot.id, ot.folio, ot.titulo, ot.estado, ot.prioridad,
            ot.fecha_programada, ot.hora_inicio_plan, ot.hora_termino_plan,
            ot.avance_pct,
            ot.faena_calama_id, f.nombre AS faena_nombre,
            ot.planificacion_id, p.linea_negocio,
            ot.responsable_id, up.nombre_completo AS responsable_nombre,
            COALESCE(pc.liberada_para_ejecucion, false) AS liberada,
            ot.requiere_vehiculo_especial,
            (SELECT COUNT(*) FROM calama_ot_subtareas s WHERE s.ot_id = ot.id) AS subtareas_total,
            (SELECT COUNT(*) FROM calama_ot_subtareas s WHERE s.ot_id = ot.id AND s.estado = 'completada') AS subtareas_done
        FROM calama_ordenes_trabajo ot
        JOIN calama_faenas f          ON f.id = ot.faena_calama_id
        JOIN calama_planificaciones p ON p.id = ot.planificacion_id
        LEFT JOIN calama_ot_precheck pc ON pc.ot_id = ot.id
        LEFT JOIN usuarios_perfil up    ON up.id = ot.responsable_id
        WHERE ot.fecha_programada = p_fecha
          AND (p_faena_id IS NULL OR ot.faena_calama_id = p_faena_id)
          AND (
                fn_calama_puede_planificar()
                OR (
                    fn_calama_es_operador()
                    AND (
                        ot.responsable_id = v_uid
                        OR EXISTS (
                            SELECT 1 FROM calama_ot_subtareas s
                             WHERE s.ot_id = ot.id AND s.asignado_id = v_uid
                        )
                    )
                )
              )
        ORDER BY ot.prioridad DESC, ot.hora_inicio_plan NULLS LAST, ot.folio
    ) t;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'ots', v_data);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_listar_ot_terreno(DATE, UUID) TO authenticated;


-- 6.2 Iniciar ejecucion (lock optimista — solo si liberada y aun no iniciada)
CREATE OR REPLACE FUNCTION rpc_calama_iniciar_ejecucion(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_estado TEXT;
    v_libre BOOLEAN;
    v_resp UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    SELECT ot.estado, COALESCE(pc.liberada_para_ejecucion, false), ot.responsable_id
      INTO v_estado, v_libre, v_resp
      FROM calama_ordenes_trabajo ot
      LEFT JOIN calama_ot_precheck pc ON pc.ot_id = ot.id
     WHERE ot.id = p_ot_id
     FOR UPDATE OF ot;

    IF v_estado IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;
    IF NOT v_libre THEN
        RAISE EXCEPTION 'OT no liberada (precheck incompleto)';
    END IF;
    IF v_estado NOT IN ('planificada','liberada','en_pausa') THEN
        RAISE EXCEPTION 'OT en estado % no puede iniciarse', v_estado;
    END IF;
    IF fn_calama_es_operador() AND v_resp <> v_uid THEN
        RAISE EXCEPTION 'Operador solo puede iniciar OTs propias';
    END IF;

    UPDATE calama_ordenes_trabajo
       SET estado = 'en_ejecucion',
           fecha_inicio_real = COALESCE(fecha_inicio_real, NOW()),
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'ot_id', p_ot_id, 'estado', 'en_ejecucion');
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_iniciar_ejecucion(UUID) TO authenticated;


-- 6.3 Registrar avance (idempotente via cliente_uuid)
CREATE OR REPLACE FUNCTION rpc_calama_registrar_avance(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_subt UUID := NULLIF(p_payload->>'subtarea_id','')::UUID;
    v_cli  UUID := NULLIF(p_payload->>'cliente_uuid','')::UUID;
    v_avance NUMERIC := (p_payload->>'avance_acumulado')::NUMERIC;
    v_prev   NUMERIC;
    v_resp   UUID;
    v_estado TEXT;
    v_id     UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF v_ot_id IS NULL OR v_avance IS NULL THEN
        RAISE EXCEPTION 'payload invalido: ot_id y avance_acumulado obligatorios';
    END IF;
    IF v_avance < 0 OR v_avance > 100 THEN
        RAISE EXCEPTION 'avance_acumulado fuera de rango [0,100]';
    END IF;
    IF v_cli IS NULL THEN v_cli := gen_random_uuid(); END IF;

    -- Idempotencia
    SELECT id INTO v_id FROM calama_avances WHERE cliente_uuid = v_cli;
    IF v_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'avance_id', v_id, 'idempotent_hit', true);
    END IF;

    SELECT estado, responsable_id, avance_pct INTO v_estado, v_resp, v_prev
      FROM calama_ordenes_trabajo WHERE id = v_ot_id FOR UPDATE;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;
    IF v_estado NOT IN ('liberada','en_ejecucion','en_pausa') THEN
        RAISE EXCEPTION 'OT en estado % no admite avance', v_estado;
    END IF;
    IF fn_calama_es_operador() AND v_resp <> v_uid THEN
        RAISE EXCEPTION 'Operador solo puede registrar avance en OT propia';
    END IF;
    IF v_avance < v_prev THEN
        RAISE EXCEPTION 'avance % no puede ser menor que el actual %', v_avance, v_prev;
    END IF;

    INSERT INTO calama_avances (
        ot_id, subtarea_id, fecha,
        avance_acumulado, delta_avance, horas_trabajadas, cantidad_ejecutada,
        descripcion, gps_lat, gps_lng, reportado_por, cliente_uuid
    ) VALUES (
        v_ot_id, v_subt,
        COALESCE(NULLIF(p_payload->>'fecha','')::DATE, CURRENT_DATE),
        v_avance,
        v_avance - v_prev,
        NULLIF(p_payload->>'horas_trabajadas','')::NUMERIC,
        NULLIF(p_payload->>'cantidad_ejecutada','')::NUMERIC,
        NULLIF(p_payload->>'descripcion',''),
        NULLIF(p_payload->>'gps_lat','')::NUMERIC,
        NULLIF(p_payload->>'gps_lng','')::NUMERIC,
        v_uid, v_cli
    ) RETURNING id INTO v_id;

    UPDATE calama_ordenes_trabajo
       SET avance_pct = v_avance,
           estado = CASE
               WHEN v_avance >= 100 THEN 'finalizada'
               WHEN estado = 'liberada' THEN 'en_ejecucion'
               ELSE estado END,
           fecha_termino_real = CASE WHEN v_avance >= 100 THEN NOW() ELSE fecha_termino_real END,
           updated_at = NOW()
     WHERE id = v_ot_id;

    IF v_subt IS NOT NULL THEN
        UPDATE calama_ot_subtareas
           SET avance_pct = LEAST(100, GREATEST(avance_pct, v_avance)),
               estado = CASE WHEN v_avance >= 100 THEN 'completada' ELSE 'en_ejecucion' END,
               completada_at = CASE WHEN v_avance >= 100 THEN NOW() ELSE completada_at END,
               completada_por = CASE WHEN v_avance >= 100 THEN v_uid ELSE completada_por END,
               updated_at = NOW()
         WHERE id = v_subt;
    END IF;

    RETURN jsonb_build_object('success', true, 'avance_id', v_id, 'avance_acumulado', v_avance);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_registrar_avance(jsonb) TO authenticated;


-- 6.4 Finalizar OT (cierre con firma + observacion)
CREATE OR REPLACE FUNCTION rpc_calama_finalizar_ot(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_estado TEXT;
    v_resp UUID;
    v_obs   TEXT := NULLIF(p_payload->>'observaciones_cierre','');
    v_firma TEXT := NULLIF(p_payload->>'firma_responsable_url','');
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'ot_id obligatorio'; END IF;

    SELECT estado, responsable_id INTO v_estado, v_resp
      FROM calama_ordenes_trabajo WHERE id = v_ot_id FOR UPDATE;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;
    IF v_estado NOT IN ('en_ejecucion','en_pausa','liberada') THEN
        RAISE EXCEPTION 'OT en estado % no puede finalizarse', v_estado;
    END IF;
    IF fn_calama_es_operador() AND v_resp <> v_uid THEN
        RAISE EXCEPTION 'Operador solo puede finalizar OT propia';
    END IF;

    UPDATE calama_ordenes_trabajo
       SET estado = 'finalizada',
           avance_pct = 100,
           fecha_termino_real = NOW(),
           observaciones_cierre = COALESCE(v_obs, observaciones_cierre),
           firma_responsable_url = COALESCE(v_firma, firma_responsable_url),
           horas_reales = COALESCE(NULLIF(p_payload->>'horas_reales','')::NUMERIC, horas_reales),
           updated_at = NOW()
     WHERE id = v_ot_id;

    RETURN jsonb_build_object('success', true, 'ot_id', v_ot_id, 'estado', 'finalizada');
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_finalizar_ot(jsonb) TO authenticated;


-- 6.5 Reportar no ejecucion (causa controlada)
CREATE OR REPLACE FUNCTION rpc_calama_reportar_no_ejecucion(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ot_id UUID := (p_payload->>'ot_id')::UUID;
    v_causa TEXT := p_payload->>'causa';
    v_cli   UUID := NULLIF(p_payload->>'cliente_uuid','')::UUID;
    v_id    UUID;
    v_resp  UUID;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF v_ot_id IS NULL OR v_causa IS NULL THEN
        RAISE EXCEPTION 'ot_id y causa obligatorios';
    END IF;
    IF v_cli IS NULL THEN v_cli := gen_random_uuid(); END IF;

    SELECT id INTO v_id FROM calama_eventos_no_ejecucion WHERE cliente_uuid = v_cli;
    IF v_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'evento_id', v_id, 'idempotent_hit', true);
    END IF;

    SELECT responsable_id INTO v_resp FROM calama_ordenes_trabajo WHERE id = v_ot_id FOR UPDATE;
    IF v_resp IS NULL THEN RAISE EXCEPTION 'OT no encontrada'; END IF;
    IF fn_calama_es_operador() AND v_resp <> v_uid THEN
        RAISE EXCEPTION 'Operador solo puede reportar no-ejec en OT propia';
    END IF;

    INSERT INTO calama_eventos_no_ejecucion (
        ot_id, causa, detalle, fecha_evento,
        horas_perdidas, impacto_avance, reportado_por, cliente_uuid
    ) VALUES (
        v_ot_id, v_causa, NULLIF(p_payload->>'detalle',''),
        COALESCE(NULLIF(p_payload->>'fecha_evento','')::DATE, CURRENT_DATE),
        NULLIF(p_payload->>'horas_perdidas','')::NUMERIC,
        NULLIF(p_payload->>'impacto_avance','')::NUMERIC,
        v_uid, v_cli
    ) RETURNING id INTO v_id;

    UPDATE calama_ordenes_trabajo
       SET estado = 'no_ejecutada',
           updated_at = NOW()
     WHERE id = v_ot_id
       AND estado IN ('planificada','liberada','en_pausa');

    RETURN jsonb_build_object('success', true, 'evento_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_reportar_no_ejecucion(jsonb) TO authenticated;


-- 6.6 Curva S por planificacion (devuelve serie diaria)
CREATE OR REPLACE FUNCTION rpc_calama_curva_s_faena(
    p_planificacion_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_data JSONB;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_calama_puede_ver() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.fecha), '[]'::jsonb) INTO v_data
    FROM (
        SELECT fecha, avance_plan_pct, avance_real_pct
          FROM v_calama_curva_s
         WHERE planificacion_id = p_planificacion_id
         ORDER BY fecha
    ) t;

    RETURN jsonb_build_object(
        'success', true,
        'planificacion_id', p_planificacion_id,
        'serie', v_data
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_calama_curva_s_faena(UUID) TO authenticated;


-- ============================================================================
-- ── 7. SEEDS ────────────────────────────────────────────────────────────────
-- ============================================================================

-- 7.1 Lineas de negocio
INSERT INTO calama_lineas_negocio (codigo, nombre, descripcion) VALUES
('combustibles',    'Combustibles',    'Plataformas fijas / moviles + calibracion de equipos.'),
('lubricantes',     'Lubricantes',     'Plataformas fijas / moviles + calibracion de equipos.'),
('mejoras_civiles', 'Mejoras Civiles', 'Refaccion / pintura / reparaciones / mejoras de instalaciones.')
ON CONFLICT (codigo) DO NOTHING;

-- 7.2 Faenas Calama (3 mandantes mineras)
INSERT INTO calama_faenas (codigo, nombre, mandante, region, comuna) VALUES
('LOMAS_BAYAS', 'Lomas Bayas',                'Glencore',                       'Antofagasta', 'Calama'),
('CENTINELA',   'Minera Centinela',           'Antofagasta Minerals (AMSA)',    'Antofagasta', 'Sierra Gorda'),
('SPENCE',      'Spence (Pampa Norte)',       'BHP',                            'Antofagasta', 'Sierra Gorda')
ON CONFLICT (codigo) DO NOTHING;


-- ============================================================================
-- ── 8. BITACORA ─────────────────────────────────────────────────────────────
-- ============================================================================

DO $$ BEGIN
    INSERT INTO operacion_migraciones_log (
        codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        'PROD_MIG17_CALAMA_BASE',
        'FASE 1 modulo Operacion Calama: 12 tablas + 3 vistas + 6 RPCs + RLS + seeds.',
        current_user, NOW(), NOW(), 'ok',
        'Tablas calama_*, RLS estricta, anon SIN ACCESO. ' ||
        'Decisiones: A1 (file 17), B2 (calama_roles_proyecto), C1 (calama_faenas separada), ' ||
        'D1 (sub_linea VARCHAR controlado), E (bucket documentos compartido path calama-evidencias/*).'
    );
END $$;


-- ============================================================================
-- ── 9. VERIFICACION FINAL (1 fila: OK / WARNING / STOP) ──────────────────────
-- ============================================================================

WITH
tablas_esperadas AS (
    SELECT ARRAY[
        'calama_lineas_negocio','calama_faenas','calama_roles_proyecto',
        'calama_planificaciones','calama_tareas_maestro','calama_ordenes_trabajo',
        'calama_ot_subtareas','calama_ot_precheck','calama_avances',
        'calama_evidencias','calama_observaciones','calama_eventos_no_ejecucion'
    ]::text[] AS lista
),
tablas_encontradas AS (
    SELECT COALESCE(array_agg(table_name::text ORDER BY table_name::text), ARRAY[]::text[]) AS lista
    FROM information_schema.tables
    WHERE table_schema='public'
      AND table_name::text IN (
        'calama_lineas_negocio','calama_faenas','calama_roles_proyecto',
        'calama_planificaciones','calama_tareas_maestro','calama_ordenes_trabajo',
        'calama_ot_subtareas','calama_ot_precheck','calama_avances',
        'calama_evidencias','calama_observaciones','calama_eventos_no_ejecucion'
      )
),
tablas_faltantes AS (
    SELECT COALESCE(array_agg(x ORDER BY x), ARRAY[]::text[]) AS faltan
    FROM (SELECT unnest((SELECT lista FROM tablas_esperadas)) AS x
          EXCEPT
          SELECT unnest((SELECT lista FROM tablas_encontradas)) AS x) s
),

vistas_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.views
                              WHERE table_schema='public' AND table_name='v_calama_ot_ejecutable')
             THEN 'v_calama_ot_ejecutable' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.views
                              WHERE table_schema='public' AND table_name='v_calama_oee_diario')
             THEN 'v_calama_oee_diario' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.views
                              WHERE table_schema='public' AND table_name='v_calama_curva_s')
             THEN 'v_calama_curva_s' END
    ]::text[], NULL) AS faltan
),

rpcs_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.rpc_calama_listar_ot_terreno(date,uuid)') IS NULL
             THEN 'rpc_calama_listar_ot_terreno' END,
        CASE WHEN to_regprocedure('public.rpc_calama_iniciar_ejecucion(uuid)') IS NULL
             THEN 'rpc_calama_iniciar_ejecucion' END,
        CASE WHEN to_regprocedure('public.rpc_calama_registrar_avance(jsonb)') IS NULL
             THEN 'rpc_calama_registrar_avance' END,
        CASE WHEN to_regprocedure('public.rpc_calama_finalizar_ot(jsonb)') IS NULL
             THEN 'rpc_calama_finalizar_ot' END,
        CASE WHEN to_regprocedure('public.rpc_calama_reportar_no_ejecucion(jsonb)') IS NULL
             THEN 'rpc_calama_reportar_no_ejecucion' END,
        CASE WHEN to_regprocedure('public.rpc_calama_curva_s_faena(uuid)') IS NULL
             THEN 'rpc_calama_curva_s_faena' END
    ]::text[], NULL) AS faltan
),

helpers_faltantes AS (
    SELECT array_remove(ARRAY[
        CASE WHEN to_regprocedure('public.fn_calama_rol_global()') IS NULL
             THEN 'fn_calama_rol_global' END,
        CASE WHEN to_regprocedure('public.fn_calama_rol_proyecto()') IS NULL
             THEN 'fn_calama_rol_proyecto' END,
        CASE WHEN to_regprocedure('public.fn_calama_es_admin_global()') IS NULL
             THEN 'fn_calama_es_admin_global' END,
        CASE WHEN to_regprocedure('public.fn_calama_puede_planificar()') IS NULL
             THEN 'fn_calama_puede_planificar' END,
        CASE WHEN to_regprocedure('public.fn_calama_puede_ver()') IS NULL
             THEN 'fn_calama_puede_ver' END,
        CASE WHEN to_regprocedure('public.fn_calama_es_operador()') IS NULL
             THEN 'fn_calama_es_operador' END
    ]::text[], NULL) AS faltan
),

rls_faltante AS (
    SELECT array_remove(ARRAY[
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ordenes_trabajo')
             THEN 'calama_ordenes_trabajo' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_planificaciones')
             THEN 'calama_planificaciones' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_avances')
             THEN 'calama_avances' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_evidencias')
             THEN 'calama_evidencias' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_roles_proyecto')
             THEN 'calama_roles_proyecto' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_subtareas')
             THEN 'calama_ot_subtareas' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_ot_precheck')
             THEN 'calama_ot_precheck' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_observaciones')
             THEN 'calama_observaciones' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_eventos_no_ejecucion')
             THEN 'calama_eventos_no_ejecucion' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_tareas_maestro')
             THEN 'calama_tareas_maestro' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_faenas')
             THEN 'calama_faenas' END,
        CASE WHEN NOT (SELECT relrowsecurity FROM pg_class WHERE relname='calama_lineas_negocio')
             THEN 'calama_lineas_negocio' END
    ]::text[], NULL) AS sin_rls
),

anon_lee_calama AS (
    -- Verifica que NINGUNA policy permita acceso a anon en tablas calama_*.
    SELECT COALESCE(array_agg(DISTINCT tablename::text ORDER BY tablename::text), ARRAY[]::text[]) AS tablas
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename::text LIKE 'calama_%'
      AND 'anon' = ANY(roles)
),

seeds_lineas AS (
    SELECT COUNT(*)::int AS total FROM calama_lineas_negocio WHERE activo = true
),
seeds_faenas AS (
    SELECT COUNT(*)::int AS total FROM calama_faenas WHERE activo = true
),

generated_libre AS (
    -- Confirma que liberada_para_ejecucion sea columna GENERATED.
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public'
           AND table_name='calama_ot_precheck'
           AND column_name='liberada_para_ejecucion'
           AND is_generated = 'ALWAYS'
    ) AS v
),

bitacora_ok AS (
    SELECT EXISTS (
        SELECT 1 FROM operacion_migraciones_log
         WHERE codigo_paso = 'PROD_MIG17_CALAMA_BASE'
    ) AS v
),

detalle AS (
    SELECT array_to_string(array_remove(ARRAY[
        CASE WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
             THEN 'Tablas faltantes: ' || array_to_string((SELECT faltan FROM tablas_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM vistas_faltantes),1) > 0
             THEN 'Vistas faltantes: ' || array_to_string((SELECT faltan FROM vistas_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM rpcs_faltantes),1) > 0
             THEN 'RPCs faltantes: ' || array_to_string((SELECT faltan FROM rpcs_faltantes), ', ') END,
        CASE WHEN array_length((SELECT faltan FROM helpers_faltantes),1) > 0
             THEN 'Helpers faltantes: ' || array_to_string((SELECT faltan FROM helpers_faltantes), ', ') END,
        CASE WHEN array_length((SELECT sin_rls FROM rls_faltante),1) > 0
             THEN 'RLS DESHABILITADA en: ' || array_to_string((SELECT sin_rls FROM rls_faltante), ', ') END,
        CASE WHEN array_length((SELECT tablas FROM anon_lee_calama),1) > 0
             THEN 'ANON tiene acceso a tablas calama_*: ' || array_to_string((SELECT tablas FROM anon_lee_calama), ', ') END,
        CASE WHEN (SELECT total FROM seeds_lineas) < 3
             THEN 'Lineas de negocio insuficientes (' || (SELECT total FROM seeds_lineas)::text || '/3).' END,
        CASE WHEN (SELECT total FROM seeds_faenas) < 3
             THEN 'Faenas Calama insuficientes (' || (SELECT total FROM seeds_faenas)::text || '/3).' END,
        CASE WHEN NOT (SELECT v FROM generated_libre)
             THEN 'liberada_para_ejecucion no es columna GENERATED.' END,
        CASE WHEN NOT (SELECT v FROM bitacora_ok)
             THEN 'Bitacora PROD_MIG17_CALAMA_BASE no registrada.' END
    ]::text[], NULL), ' | ') AS texto
)

SELECT
    CASE
        WHEN COALESCE((SELECT texto FROM detalle), '') = ''
        THEN 'OK_OPERACION_CALAMA_BASE'
        WHEN array_length((SELECT faltan FROM tablas_faltantes),1) > 0
          OR array_length((SELECT faltan FROM rpcs_faltantes),1) > 0
          OR array_length((SELECT faltan FROM helpers_faltantes),1) > 0
          OR array_length((SELECT sin_rls FROM rls_faltante),1) > 0
          OR array_length((SELECT tablas FROM anon_lee_calama),1) > 0
          OR NOT (SELECT v FROM generated_libre)
        THEN 'STOP_OPERACION_CALAMA_BASE'
        ELSE 'WARNING_OPERACION_CALAMA_BASE'
    END                                                                    AS resultado,
    COALESCE(NULLIF((SELECT texto FROM detalle), ''),
        '12 tablas + 3 vistas + 6 RPCs + 6 helpers + RLS + anon sin acceso + ' ||
        'liberada_para_ejecucion GENERATED + 3 lineas + 3 faenas + bitacora.'
    )                                                                      AS detalle,
    COALESCE(array_length((SELECT lista FROM tablas_encontradas),1), 0)    AS tablas_encontradas,
    (SELECT total FROM seeds_lineas)                                       AS lineas_negocio,
    (SELECT total FROM seeds_faenas)                                       AS faenas_calama,
    (SELECT v FROM generated_libre)                                        AS columna_generada_ok,
    (SELECT v FROM bitacora_ok)                                            AS bitacora_registrada,
    NOW()                                                                  AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - resultado = OK_OPERACION_CALAMA_BASE
--     → estructura completa y correcta. Frontend puede consumir.
-- - resultado = WARNING_OPERACION_CALAMA_BASE
--     → revisar columna `detalle` (faltan seeds, vistas, etc.).
-- - resultado = STOP_OPERACION_CALAMA_BASE
--     → ESTRUCTURA INCOMPLETA o ANON tiene acceso. Resolver antes de avanzar
--       a FASE 2 (importer Excel) y FASE 3 (frontend).
--
-- PROXIMOS PASOS:
--   - FASE 2: parser Excel (Carta Gantt VA 25_042 Mejoras Centinela 3003.xlsx).
--   - FASE 3: dashboard ejecutivo + planificacion + precheck + ejecucion.
--   - FASE 4: ejecucion movil offline-first (cliente_uuid ya preparado).
--   - FASE 5: reportes mandante PDF.
-- ============================================================================
