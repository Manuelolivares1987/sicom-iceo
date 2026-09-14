-- ============================================================================
-- MIG546 · Prevención: reportabilidad por faena (RIT/VAT/VCT + E-200 + informe)
-- ============================================================================
-- Origen: carpeta PREVENCION de Anyulin Cortés (encargada de prevención) con el
-- levantamiento «Estructura de Reportabilidad por Faena»: Centinela, Lomas
-- Bayas, Romeral (CMP) y Franke. El diagnóstico del propio documento:
--
--   «Para el Informe de Gestión Mensual se requiere solicitar a cada
--    supervisor la información de RIT, VAT y VCT, abiertos y cerrados
--    [...] Se propone una plataforma donde cada supervisor cargue
--    directamente sus registros, con recuento y consolidado mensual
--    automático.»  (Oportunidad de mejora — Romeral)
--
-- Lo que crea esta migración (todo nuevo, ADITIVO, IDEMPOTENTE):
--
--   1. prevencion_actividad_tipos ..... catálogo: RIT, VAT, VCT, charla,
--      capacitación, inspección, simulacro, campaña, HS-SAFEWORK, GCOM.
--   2. prevencion_registros ........... EL repositorio central: cada supervisor
--      carga su registro con evidencia (fotos → bucket privado), queda asociado
--      a faena + fecha + responsable. Abierto/cerrado para los que llevan cierre.
--   3. prevencion_programa_mensual .... metas por faena+mes+tipo (lo
--      «planificado» del informe CMP: VCT 143, VAT 35, RIT 51...).
--   4. prevencion_indicadores_mes ..... dotación, HH, accidentes CTP/STP, días
--      perdidos (base del E-200 SERNAGEOMIN y de los índices Ley 16.744).
--      Los índices NO se digitan: los calcula la vista
--      (IF e IG por 1.000.000 HH — estándar SERNAGEOMIN/SUSESO;
--       tasa de accidentabilidad = accidentados x 100 / dotación).
--   5. prevencion_reportabilidad_items/envios ... el checklist mensual de
--      entregas por faena (E-200, Informe Gestión, PGR, SAFEWORK, GCOM,
--      Anexo 10.2, EPP, doc. ambiental) con semáforo y respaldo adjunto.
--      Estructura documental pedida: Faena → Año → Mes → Reportabilidad.
--   6. Vistas de consolidación + RPC rpc_prevencion_consolidado_mes.
--   7. Bucket privado prevencion-evidencias.
--
-- Marco legal de referencia (no se inventa nada en la BD, solo nombres):
--   · DS 132 (Reglamento de Seguridad Minera) art. 36 — declaración mensual
--     de accidentabilidad E-200 al SERNAGEOMIN vía SIMIN, con o sin accidentes.
--   · Ley 16.744 y DS 40/DS 44 — estadísticas e índices de siniestralidad.
--   · DS 54 — CPHS (actividades del comité aparecen en el informe mensual).
--   · Protocolos MINSAL (PLANESI, PREXOR, TMERT, UV) — quedan como tipos de
--     actividad/reportabilidad; sus autoevaluaciones siguen en Excel oficial.
--
-- Reglas de acceso:
--   · Ver: quien tenga el módulo prevención en view (supervisor incluido);
--     si el usuario tiene solo_su_faena, ve únicamente su faena (MIG385).
--   · Cargar registros: supervisor, prevencionista, jefaturas, administrador.
--   · Editar/cerrar un registro: su autor mientras está abierto; prevención y
--     administración siempre. Borrar: solo prevención/administración.
--   · Metas, indicadores y checklist de reportabilidad: prevención, jefaturas
--     y administración.
--   · TEST-01/es_prueba no aplica: este módulo no toca flota.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 0. HELPERS DE PERMISO
-- ############################################################################

CREATE OR REPLACE FUNCTION public.fn_prevencion_reporta_puede_ver()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT fn_tiene_permiso_modulo('prevencion', 'view', ARRAY[
        'administrador','prevencionista','supervisor','jefe_operaciones',
        'jefe_mantenimiento','subgerente_operaciones','gerencia',
        'planificador','auditor_calidad','comercial'
    ]);
$$;

-- El que carga en terreno. OJO: se valida por ROL directo (no por acción
-- 'create' del módulo) porque el default del módulo prevención NO da create al
-- supervisor y no queremos abrirle create a todo el módulo (respel, exámenes).
CREATE OR REPLACE FUNCTION public.fn_prevencion_reporta_puede_crear()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(fn_user_rol() = ANY (ARRAY[
        'administrador','prevencionista','supervisor','jefe_operaciones',
        'jefe_mantenimiento','subgerente_operaciones'
    ]), false);
$$;

-- Administración del módulo: metas, indicadores, checklist de reportabilidad.
CREATE OR REPLACE FUNCTION public.fn_prevencion_reporta_puede_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(fn_user_rol() = ANY (ARRAY[
        'administrador','prevencionista','jefe_operaciones','subgerente_operaciones'
    ]), false);
$$;

-- MIG385: si el usuario está restringido a su faena, solo ve la suya.
CREATE OR REPLACE FUNCTION public.fn_prevencion_faena_visible(p_faena UUID)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM usuarios_perfil up
             WHERE up.id = auth.uid() AND up.activo
               AND COALESCE(up.solo_su_faena, false)
        )
        THEN EXISTS (
            SELECT 1 FROM usuarios_perfil up
             WHERE up.id = auth.uid() AND up.faena_id = p_faena
        )
        ELSE true
    END;
$$;

-- ############################################################################
-- 1. CATÁLOGO DE TIPOS DE ACTIVIDAD PREVENTIVA
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_actividad_tipos (
    codigo          VARCHAR(30) PRIMARY KEY,
    nombre          VARCHAR(120) NOT NULL,
    descripcion     TEXT,
    -- Los que se gestionan con estado (el informe CMP pide abiertos/cerrados).
    requiere_cierre BOOLEAN NOT NULL DEFAULT false,
    activo          BOOLEAN NOT NULL DEFAULT true,
    orden           INTEGER NOT NULL DEFAULT 100
);

COMMENT ON TABLE prevencion_actividad_tipos IS
    'Catálogo de actividades preventivas de terreno (herramientas GRP CMP, charlas, capacitaciones, etc.). MIG546.';

INSERT INTO prevencion_actividad_tipos (codigo, nombre, descripcion, requiere_cierre, orden) VALUES
    ('RIT',          'RIT',                  'Herramienta GRP (CMP Romeral). Registro de terreno del supervisor; se informa mensualmente abiertos y cerrados.', true,  10),
    ('VAT',          'VAT',                  'Herramienta GRP (CMP Romeral). Se informa mensualmente abiertos y cerrados.',                                     true,  20),
    ('VCT',          'VCT',                  'Verificación en terreno (herramienta GRP CMP). Semanal sobre actividades críticas; se informan abiertos/cerrados.', true, 30),
    ('CHARLA',       'Charla de seguridad',  'Charla diaria/semanal de seguridad o medioambiente (las ambientales de Franke van aquí con el tema en el título).', false, 40),
    ('CAPACITACION', 'Capacitación',         'Capacitación con duración y asistentes (alimenta la sección 2 del informe de gestión).',                          false, 50),
    ('INSPECCION',   'Inspección',           'Inspección planeada de seguridad (equipos, áreas, EPP, extintores…). Con hallazgos queda abierta hasta cerrar.',   true,  60),
    ('OBSERVACION',  'Observación planeada', 'Observación planeada de conducta/tarea.',                                                                          false, 70),
    ('SIMULACRO',    'Simulacro',            'Simulacro de emergencia (sección Emergencia del informe mensual).',                                                false, 80),
    ('CAMPANA',      'Campaña',              'Campaña preventiva (invierno, UV, manos, etc.) con evidencia fotográfica.',                                        false, 90),
    ('HS_SAFEWORK',  'Actividad HS — SAFEWORK', 'Actividad HS que exige Lomas Bayas; la evidencia luego se carga en SAFEWORK.',                                  false, 100),
    ('GCOM',         'GCOM',                 'Registro GCOM mensual del supervisor (Lomas Bayas). Respaldo local de lo que exige la plataforma GCOM.',           false, 110)
ON CONFLICT (codigo) DO NOTHING;

ALTER TABLE prevencion_actividad_tipos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_act_tipos_select ON prevencion_actividad_tipos;
CREATE POLICY prev_act_tipos_select ON prevencion_actividad_tipos
    FOR SELECT TO authenticated USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_act_tipos_admin ON prevencion_actividad_tipos;
CREATE POLICY prev_act_tipos_admin ON prevencion_actividad_tipos
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT ON prevencion_actividad_tipos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON prevencion_actividad_tipos TO authenticated;

-- ############################################################################
-- 2. REGISTROS DE TERRENO (el repositorio central)
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_registros (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id         UUID NOT NULL REFERENCES faenas(id),
    tipo_codigo      VARCHAR(30) NOT NULL REFERENCES prevencion_actividad_tipos(codigo),
    fecha_actividad  DATE NOT NULL DEFAULT CURRENT_DATE,

    titulo           VARCHAR(200) NOT NULL,
    descripcion      TEXT,
    area_sector      VARCHAR(120),
    activo_id        UUID REFERENCES activos(id),

    estado           VARCHAR(10) NOT NULL DEFAULT 'cerrado'
                     CONSTRAINT chk_prev_reg_estado CHECK (estado IN ('abierto','cerrado')),
    fecha_cierre     TIMESTAMPTZ,
    cierre_observacion TEXT,
    cerrado_por      UUID REFERENCES auth.users(id),

    -- Para capacitaciones (sección 2 del informe): minutos y asistentes.
    duracion_minutos INTEGER CHECK (duracion_minutos IS NULL OR duracion_minutos > 0),
    asistentes       INTEGER CHECK (asistentes IS NULL OR asistentes >= 0),

    -- [{path, nombre, content_type}] en el bucket prevencion-evidencias.
    evidencias       JSONB NOT NULL DEFAULT '[]'::jsonb,

    creado_por       UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    supervisor_nombre VARCHAR(160),   -- snapshot: quién responde por el registro
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE prevencion_registros IS
    'Registros preventivos cargados directamente por los supervisores (RIT/VAT/VCT, charlas, etc.), con evidencia. Reemplaza la solicitud individual por correo para el consolidado mensual. MIG546.';

CREATE INDEX IF NOT EXISTS idx_prev_reg_faena_fecha ON prevencion_registros (faena_id, fecha_actividad DESC);
CREATE INDEX IF NOT EXISTS idx_prev_reg_tipo        ON prevencion_registros (tipo_codigo, fecha_actividad DESC);
CREATE INDEX IF NOT EXISTS idx_prev_reg_autor       ON prevencion_registros (creado_por, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prev_reg_abiertos    ON prevencion_registros (faena_id) WHERE estado = 'abierto';

-- Coherencia de cierre + snapshot del nombre + updated_at.
CREATE OR REPLACE FUNCTION public.fn_prevencion_registro_biu()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.supervisor_nombre IS NULL THEN
        SELECT nombre_completo INTO NEW.supervisor_nombre
          FROM usuarios_perfil WHERE id = NEW.creado_por;
    END IF;

    IF NEW.estado = 'cerrado' THEN
        NEW.fecha_cierre := COALESCE(NEW.fecha_cierre, NOW());
        NEW.cerrado_por  := COALESCE(NEW.cerrado_por, auth.uid(), NEW.creado_por);
    ELSE
        NEW.fecha_cierre := NULL;
        NEW.cerrado_por  := NULL;
    END IF;

    NEW.updated_at := NOW();
    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_prevencion_registro_biu ON prevencion_registros;
CREATE TRIGGER trg_prevencion_registro_biu
    BEFORE INSERT OR UPDATE ON prevencion_registros
    FOR EACH ROW EXECUTE FUNCTION fn_prevencion_registro_biu();

ALTER TABLE prevencion_registros ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_reg_select ON prevencion_registros;
CREATE POLICY prev_reg_select ON prevencion_registros
    FOR SELECT TO authenticated
    USING (
        (fn_prevencion_reporta_puede_ver() OR creado_por = auth.uid())
        AND fn_prevencion_faena_visible(faena_id)
    );

DROP POLICY IF EXISTS prev_reg_insert ON prevencion_registros;
CREATE POLICY prev_reg_insert ON prevencion_registros
    FOR INSERT TO authenticated
    WITH CHECK (fn_prevencion_reporta_puede_crear() AND creado_por = auth.uid());

-- El autor edita/cierra lo suyo mientras esté abierto (o el mismo día si ya lo
-- cerró: típico «me equivoqué en el título»); prevención/administración siempre.
DROP POLICY IF EXISTS prev_reg_update ON prevencion_registros;
CREATE POLICY prev_reg_update ON prevencion_registros
    FOR UPDATE TO authenticated
    USING (
        fn_prevencion_reporta_puede_admin()
        OR (creado_por = auth.uid()
            AND (estado = 'abierto' OR created_at > NOW() - INTERVAL '24 hours'))
    );

DROP POLICY IF EXISTS prev_reg_delete ON prevencion_registros;
CREATE POLICY prev_reg_delete ON prevencion_registros
    FOR DELETE TO authenticated USING (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_registros TO authenticated;

-- ############################################################################
-- 3. PROGRAMA MENSUAL (metas por faena y tipo)
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_programa_mensual (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES faenas(id),
    anio        INTEGER NOT NULL CHECK (anio BETWEEN 2020 AND 2100),
    mes         INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
    tipo_codigo VARCHAR(30) NOT NULL REFERENCES prevencion_actividad_tipos(codigo),
    meta        INTEGER NOT NULL CHECK (meta >= 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by  UUID REFERENCES auth.users(id),
    CONSTRAINT uq_prev_programa UNIQUE (faena_id, anio, mes, tipo_codigo)
);

COMMENT ON TABLE prevencion_programa_mensual IS
    'Lo planificado del mes por faena y tipo de actividad (el «PLANIFICADO» del informe GRP CMP). MIG546.';

ALTER TABLE prevencion_programa_mensual ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_prog_select ON prevencion_programa_mensual;
CREATE POLICY prev_prog_select ON prevencion_programa_mensual
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear())
           AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_prog_admin ON prevencion_programa_mensual;
CREATE POLICY prev_prog_admin ON prevencion_programa_mensual
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_programa_mensual TO authenticated;

-- ############################################################################
-- 4. INDICADORES MENSUALES (base E-200 / Ley 16.744)
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_indicadores_mes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id            UUID NOT NULL REFERENCES faenas(id),
    anio                INTEGER NOT NULL CHECK (anio BETWEEN 2020 AND 2100),
    mes                 INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),

    -- Dotación y HH separados por género: el E-200 los declara así.
    dotacion_hombres    INTEGER NOT NULL DEFAULT 0 CHECK (dotacion_hombres >= 0),
    dotacion_mujeres    INTEGER NOT NULL DEFAULT 0 CHECK (dotacion_mujeres >= 0),
    hh_hombres          NUMERIC(10,1) NOT NULL DEFAULT 0 CHECK (hh_hombres >= 0),
    hh_mujeres          NUMERIC(10,1) NOT NULL DEFAULT 0 CHECK (hh_mujeres >= 0),

    accidentes_ctp      INTEGER NOT NULL DEFAULT 0 CHECK (accidentes_ctp >= 0),
    accidentes_stp      INTEGER NOT NULL DEFAULT 0 CHECK (accidentes_stp >= 0),
    dias_perdidos       INTEGER NOT NULL DEFAULT 0 CHECK (dias_perdidos >= 0),
    accidentes_trayecto INTEGER NOT NULL DEFAULT 0 CHECK (accidentes_trayecto >= 0),
    enfermedades_prof   INTEGER NOT NULL DEFAULT 0 CHECK (enfermedades_prof >= 0),
    incidentes_alto_potencial INTEGER NOT NULL DEFAULT 0 CHECK (incidentes_alto_potencial >= 0),

    observaciones       TEXT,
    updated_by          UUID REFERENCES auth.users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_prev_indicadores UNIQUE (faena_id, anio, mes)
);

COMMENT ON TABLE prevencion_indicadores_mes IS
    'Datos mensuales por faena para el E-200 (DS 132 art. 36) y los índices Ley 16.744. Los índices IF/IG/tasa NO se digitan: los calcula v_prevencion_indicadores. MIG546.';

ALTER TABLE prevencion_indicadores_mes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_ind_select ON prevencion_indicadores_mes;
CREATE POLICY prev_ind_select ON prevencion_indicadores_mes
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_ind_admin ON prevencion_indicadores_mes;
CREATE POLICY prev_ind_admin ON prevencion_indicadores_mes
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_indicadores_mes TO authenticated;

-- Índices calculados, mensuales y acumulados del año.
--   IF  = accidentes CTP x 1.000.000 / HH        (frecuencia)
--   IG  = días perdidos  x 1.000.000 / HH        (gravedad)
--   Tasa accidentabilidad = accidentados CTP x 100 / dotación promedio
CREATE OR REPLACE VIEW v_prevencion_indicadores
WITH (security_invoker = true) AS
SELECT
    i.*,
    (i.dotacion_hombres + i.dotacion_mujeres)          AS dotacion_total,
    (i.hh_hombres + i.hh_mujeres)                      AS hh_total,
    ROUND(CASE WHEN (i.hh_hombres + i.hh_mujeres) > 0
        THEN i.accidentes_ctp * 1000000.0 / (i.hh_hombres + i.hh_mujeres)
        ELSE 0 END, 2)                                 AS indice_frecuencia,
    ROUND(CASE WHEN (i.hh_hombres + i.hh_mujeres) > 0
        THEN i.dias_perdidos * 1000000.0 / (i.hh_hombres + i.hh_mujeres)
        ELSE 0 END, 2)                                 AS indice_gravedad,
    ROUND(CASE WHEN (i.dotacion_hombres + i.dotacion_mujeres) > 0
        THEN i.accidentes_ctp * 100.0 / (i.dotacion_hombres + i.dotacion_mujeres)
        ELSE 0 END, 2)                                 AS tasa_accidentabilidad,
    SUM(i.accidentes_ctp)   OVER w                     AS acum_ctp,
    SUM(i.accidentes_stp)   OVER w                     AS acum_stp,
    SUM(i.dias_perdidos)    OVER w                     AS acum_dias_perdidos,
    SUM(i.hh_hombres + i.hh_mujeres) OVER w            AS acum_hh,
    ROUND(CASE WHEN SUM(i.hh_hombres + i.hh_mujeres) OVER w > 0
        THEN SUM(i.accidentes_ctp) OVER w * 1000000.0
             / SUM(i.hh_hombres + i.hh_mujeres) OVER w
        ELSE 0 END, 2)                                 AS acum_indice_frecuencia,
    ROUND(CASE WHEN SUM(i.hh_hombres + i.hh_mujeres) OVER w > 0
        THEN SUM(i.dias_perdidos) OVER w * 1000000.0
             / SUM(i.hh_hombres + i.hh_mujeres) OVER w
        ELSE 0 END, 2)                                 AS acum_indice_gravedad
FROM prevencion_indicadores_mes i
WINDOW w AS (PARTITION BY i.faena_id, i.anio ORDER BY i.mes
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

GRANT SELECT ON v_prevencion_indicadores TO authenticated;

-- ############################################################################
-- 5. CHECKLIST DE REPORTABILIDAD MENSUAL POR FAENA
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_reportabilidad_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id    UUID NOT NULL REFERENCES faenas(id),
    nombre      VARCHAR(160) NOT NULL,
    descripcion TEXT,
    fuente      VARCHAR(200),      -- de dónde sale la información (documento Anyulin)
    destino     VARCHAR(160),      -- a quién/dónde se entrega (SIMIN, mandante, plataforma)
    dia_limite  INTEGER CHECK (dia_limite BETWEEN 1 AND 31),  -- del mes siguiente
    activo      BOOLEAN NOT NULL DEFAULT true,
    orden       INTEGER NOT NULL DEFAULT 100,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_prev_repo_item UNIQUE (faena_id, nombre)
);

COMMENT ON TABLE prevencion_reportabilidad_items IS
    'Qué reportabilidad exige cada faena todos los meses (E-200, informe de gestión, PGR, GCOM…), según el levantamiento de prevención. MIG546.';

CREATE TABLE IF NOT EXISTS prevencion_reportabilidad_envios (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id      UUID NOT NULL REFERENCES prevencion_reportabilidad_items(id) ON DELETE CASCADE,
    anio         INTEGER NOT NULL CHECK (anio BETWEEN 2020 AND 2100),
    mes          INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
    fecha_envio  DATE NOT NULL DEFAULT CURRENT_DATE,
    observacion  TEXT,
    -- Respaldo en el bucket: {path, nombre, content_type}
    archivos     JSONB NOT NULL DEFAULT '[]'::jsonb,
    enviado_por  UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_prev_repo_envio UNIQUE (item_id, anio, mes)
);

COMMENT ON TABLE prevencion_reportabilidad_envios IS
    'La entrega efectiva de cada reportabilidad (mes a mes) con su respaldo. Estructura documental: Faena → Año → Mes → Reportabilidad → Evidencia. MIG546.';

ALTER TABLE prevencion_reportabilidad_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_reportabilidad_envios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_repo_items_select ON prevencion_reportabilidad_items;
CREATE POLICY prev_repo_items_select ON prevencion_reportabilidad_items
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_repo_items_admin ON prevencion_reportabilidad_items;
CREATE POLICY prev_repo_items_admin ON prevencion_reportabilidad_items
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

DROP POLICY IF EXISTS prev_repo_envios_select ON prevencion_reportabilidad_envios;
CREATE POLICY prev_repo_envios_select ON prevencion_reportabilidad_envios
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver()
           AND EXISTS (SELECT 1 FROM prevencion_reportabilidad_items it
                        WHERE it.id = item_id AND fn_prevencion_faena_visible(it.faena_id)));

DROP POLICY IF EXISTS prev_repo_envios_admin ON prevencion_reportabilidad_envios;
CREATE POLICY prev_repo_envios_admin ON prevencion_reportabilidad_envios
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_reportabilidad_items  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_reportabilidad_envios TO authenticated;

-- ── Seed: la reportabilidad de cada faena según el levantamiento ────────────
DO $seed$
DECLARE
    v_centinela UUID; v_lomas UUID; v_romeral UUID; v_franke UUID;
BEGIN
    SELECT id INTO v_centinela FROM faenas WHERE codigo = 'FAE-CENTINELA';
    SELECT id INTO v_lomas     FROM faenas WHERE codigo = 'FAE-LOMASBAYAS';
    SELECT id INTO v_romeral   FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL';
    SELECT id INTO v_franke    FROM faenas WHERE codigo = 'FAE-FRANCKE';

    IF v_centinela IS NOT NULL THEN
        INSERT INTO prevencion_reportabilidad_items (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden) VALUES
        (v_centinela, 'E-200 SERNAGEOMIN', 'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.', 'HH y sectores de trabajo informados por supervisores', 'SIMIN — simin.sernageomin.cl', 10, 10),
        (v_centinela, 'Estadísticas RR.HH. y accidentabilidad', 'Consolidado de trabajadores, HH e incidentes/accidentes.', 'Supervisión + RR.HH.', 'Mandante Centinela', 5, 20),
        (v_centinela, 'Plataforma PGR', 'Documentación preventiva y evidencias de gestión.', 'Supervisión / Prevención de Riesgos', 'Plataforma PGR del mandante', 5, 30)
        ON CONFLICT (faena_id, nombre) DO NOTHING;
    END IF;

    IF v_lomas IS NOT NULL THEN
        INSERT INTO prevencion_reportabilidad_items (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden) VALUES
        (v_lomas, 'E-200 SERNAGEOMIN', 'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.', 'HH y antecedentes informados por supervisores', 'SIMIN — simin.sernageomin.cl', 10, 10),
        (v_lomas, 'PPT Lubricantes y Combustible — Anexo 10.2', 'Presentación con evidencias de terreno y documentación de gestión.', 'Evidencias de terreno + gestión preventiva', 'Mandante Lomas Bayas', 5, 20),
        (v_lomas, 'Actividades HS — SAFEWORK', 'Evidencias de actividades HS ejecutadas en terreno.', 'Registros HS_SAFEWORK cargados por supervisores', 'Plataforma SAFEWORK', 5, 30),
        (v_lomas, 'Seguimiento programa GCOM', 'Respaldo de los GCOM mensuales de cada supervisor.', 'Registros GCOM cargados por supervisores', 'Plataforma GCOM', 5, 40)
        ON CONFLICT (faena_id, nombre) DO NOTHING;
    END IF;

    IF v_romeral IS NOT NULL THEN
        INSERT INTO prevencion_reportabilidad_items (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden) VALUES
        (v_romeral, 'E-200 SERNAGEOMIN', 'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.', 'Planilla/calendario de turnos', 'SIMIN — simin.sernageomin.cl', 10, 10),
        (v_romeral, 'Informe de Gestión Mensual GRP', 'Formato CMP: RIT/VAT/VCT planificado vs real, abiertos y cerrados, indicadores, CPHS, campañas.', 'Registros RIT/VAT/VCT del módulo (consolidado automático)', 'CMP — Gerencia SSO', 5, 20),
        (v_romeral, 'Consumo de EPP', 'Consolidado de entrega y consumo de elementos de protección personal.', 'Registros de entrega de EPP', 'CMP', 5, 30)
        ON CONFLICT (faena_id, nombre) DO NOTHING;
    END IF;

    IF v_franke IS NOT NULL THEN
        INSERT INTO prevencion_reportabilidad_items (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden) VALUES
        (v_franke, 'E-200 SERNAGEOMIN', 'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.', 'Calendario de turnos', 'SIMIN — simin.sernageomin.cl', 10, 10),
        (v_franke, 'Informe de Gestión Mensual', 'Formato TA.DPR.IN.SS-0005/F-01-3: indicadores reactivos/proactivos, actividades preventivas, reportabilidad de incidentes.', 'Turnos + registros del módulo (consolidado automático)', 'SCM Franke', 5, 20),
        (v_franke, 'Consumo de EPP', 'Consolidado de entrega y consumo de EPP.', 'Registros de entrega de EPP', 'SCM Franke', 5, 30),
        (v_franke, 'Documentación ambiental', 'Charlas ambientales, insumos mensuales y gestión de residuos (AMFFAL).', 'Charlas de supervisión + antecedentes AMFFAL', 'SCM Franke / AMFFAL', 5, 40)
        ON CONFLICT (faena_id, nombre) DO NOTHING;
    END IF;
END $seed$;

-- ############################################################################
-- 6. VISTA DE GESTIÓN MENSUAL + RPC CONSOLIDADO
-- ############################################################################

-- Meta vs real por faena/mes/tipo. FULL JOIN: aparece lo planificado sin
-- ejecución (0%) y lo ejecutado sin meta (extra).
CREATE OR REPLACE VIEW v_prevencion_gestion_mensual
WITH (security_invoker = true) AS
WITH reales AS (
    SELECT faena_id,
           EXTRACT(YEAR  FROM fecha_actividad)::int AS anio,
           EXTRACT(MONTH FROM fecha_actividad)::int AS mes,
           tipo_codigo,
           COUNT(*)                                    AS realizados,
           COUNT(*) FILTER (WHERE estado = 'abierto')  AS abiertos,
           COUNT(*) FILTER (WHERE estado = 'cerrado')  AS cerrados
    FROM prevencion_registros
    GROUP BY 1, 2, 3, 4
)
SELECT
    COALESCE(r.faena_id, p.faena_id)       AS faena_id,
    COALESCE(r.anio, p.anio)               AS anio,
    COALESCE(r.mes, p.mes)                 AS mes,
    COALESCE(r.tipo_codigo, p.tipo_codigo) AS tipo_codigo,
    t.nombre                               AS tipo_nombre,
    t.requiere_cierre,
    t.orden                                AS tipo_orden,
    COALESCE(p.meta, 0)                    AS meta,
    COALESCE(r.realizados, 0)              AS realizados,
    COALESCE(r.abiertos, 0)                AS abiertos,
    COALESCE(r.cerrados, 0)                AS cerrados,
    CASE WHEN COALESCE(p.meta, 0) > 0
         THEN ROUND(COALESCE(r.realizados, 0) * 100.0 / p.meta, 1)
         ELSE NULL END                     AS pct_cumplimiento
FROM reales r
FULL OUTER JOIN prevencion_programa_mensual p
    ON p.faena_id = r.faena_id AND p.anio = r.anio
   AND p.mes = r.mes AND p.tipo_codigo = r.tipo_codigo
JOIN prevencion_actividad_tipos t
    ON t.codigo = COALESCE(r.tipo_codigo, p.tipo_codigo);

GRANT SELECT ON v_prevencion_gestion_mensual TO authenticated;

-- Todo lo que necesita el informe del mes en UNA llamada.
CREATE OR REPLACE FUNCTION public.rpc_prevencion_consolidado_mes(
    p_faena_id UUID, p_anio INTEGER, p_mes INTEGER
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_out jsonb;
BEGIN
    IF NOT (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()) THEN
        RAISE EXCEPTION 'Sin permiso para ver la reportabilidad de prevención';
    END IF;
    IF NOT fn_prevencion_faena_visible(p_faena_id) THEN
        RAISE EXCEPTION 'Sin acceso a esta faena';
    END IF;

    SELECT jsonb_build_object(
        'gestion', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tipo_codigo', g.tipo_codigo, 'tipo_nombre', g.tipo_nombre,
                'requiere_cierre', g.requiere_cierre,
                'meta', g.meta, 'realizados', g.realizados,
                'abiertos', g.abiertos, 'cerrados', g.cerrados,
                'pct_cumplimiento', g.pct_cumplimiento
            ) ORDER BY g.tipo_orden)
            FROM v_prevencion_gestion_mensual g
            WHERE g.faena_id = p_faena_id AND g.anio = p_anio AND g.mes = p_mes
        ), '[]'::jsonb),
        'indicadores', (
            SELECT to_jsonb(v.*) FROM v_prevencion_indicadores v
            WHERE v.faena_id = p_faena_id AND v.anio = p_anio AND v.mes = p_mes
        ),
        'reportabilidad', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'item_id', it.id, 'nombre', it.nombre, 'destino', it.destino,
                'fuente', it.fuente, 'dia_limite', it.dia_limite,
                'enviado', (e.id IS NOT NULL),
                'fecha_envio', e.fecha_envio, 'archivos', e.archivos,
                'observacion', e.observacion
            ) ORDER BY it.orden)
            FROM prevencion_reportabilidad_items it
            LEFT JOIN prevencion_reportabilidad_envios e
              ON e.item_id = it.id AND e.anio = p_anio AND e.mes = p_mes
            WHERE it.faena_id = p_faena_id AND it.activo
        ), '[]'::jsonb),
        'abiertos_arrastre', COALESCE((
            -- registros abiertos de meses ANTERIORES que siguen sin cierre
            SELECT jsonb_agg(jsonb_build_object(
                'id', r.id, 'tipo_codigo', r.tipo_codigo, 'titulo', r.titulo,
                'fecha_actividad', r.fecha_actividad,
                'supervisor', r.supervisor_nombre
            ) ORDER BY r.fecha_actividad)
            FROM prevencion_registros r
            WHERE r.faena_id = p_faena_id AND r.estado = 'abierto'
              AND r.fecha_actividad < make_date(p_anio, p_mes, 1)
        ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $function$;

GRANT EXECUTE ON FUNCTION rpc_prevencion_consolidado_mes(UUID, INTEGER, INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION rpc_prevencion_consolidado_mes(UUID, INTEGER, INTEGER) FROM anon;

-- ############################################################################
-- 7. BUCKET PRIVADO DE EVIDENCIAS
-- ############################################################################

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('prevencion-evidencias', 'prevencion-evidencias', false, 15728640)
ON CONFLICT (id) DO UPDATE SET public = false;   -- nunca público

DROP POLICY IF EXISTS prev_evid_storage_select ON storage.objects;
CREATE POLICY prev_evid_storage_select ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'prevencion-evidencias'
           AND (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()));

DROP POLICY IF EXISTS prev_evid_storage_insert ON storage.objects;
CREATE POLICY prev_evid_storage_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'prevencion-evidencias'
                AND (fn_prevencion_reporta_puede_crear() OR fn_prevencion_reporta_puede_admin()));

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT
    (SELECT COUNT(*) FROM prevencion_actividad_tipos)                          AS tipos,
    (SELECT COUNT(*) FROM prevencion_reportabilidad_items)                     AS items_reportabilidad,
    (SELECT COUNT(DISTINCT faena_id) FROM prevencion_reportabilidad_items)     AS faenas_con_items,
    (SELECT COUNT(*) FROM storage.buckets WHERE id = 'prevencion-evidencias')  AS bucket;
