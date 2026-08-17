-- ============================================================================
-- SICOM-ICEO | 298 — Control documental de personal (Prevención de Riesgos)
-- ============================================================================
-- Exámenes ocupacionales y licencias del personal, con vencimiento y semáforo.
-- Pedido por AUDITORÍA. Hoy el control vive en una planilla Excel
-- ("Planilla Exámenes Personal ACTUALIZADO_V2.xlsx") y nadie se entera de un
-- vencimiento hasta que alguien la abre.
--
-- ── LO QUE LA PLANILLA MUESTRA HOY (17-ago-2026) ──────────────────────────
-- Personas trabajando con exámenes VENCIDOS: alcohol y drogas de Joel Coo
-- (11-abr), Yusdel Sarduy (01-abr) y Pablo Astorga (17-jun, con la nota
-- "falta AyD actual"); y Nicolás Rojas con LOS CINCO vencidos el 11-ago.
-- Eso es exactamente lo que una auditoría busca, y es lo que este módulo hace
-- visible sin abrir un archivo.
--
-- ── TRES DISTINCIONES QUE LA AUDITORÍA EXIGE ──────────────────────────────
--
--  1. EXENTO ≠ FALTANTE. La planilla usa texto donde debería ir una fecha:
--     "Sin trabajo en altura física", "No conduce en faena", "N/A". Eso NO es
--     un dato faltante: es una exención legítima y hay que poder demostrarlo.
--     Por eso `aplica = false` + `motivo_no_aplica`, y el semáforo lo muestra
--     como "No aplica", no como brecha.
--
--  2. FECHA VIGENTE ≠ EXAMEN VÁLIDO. Cuatro personas tienen el
--     psicosensotécnico con fecha futura pero la nota "Proveedor no aceptado
--     por CMP". Ante el mandante ese examen NO sirve. `observacion_bloqueante`
--     lo marca como observado aunque la fecha esté al día — si no, el tablero
--     diría verde sobre algo que el cliente rechaza.
--
--  3. SIN DATO ≠ VIGENTE. Una celda vacía se cuenta como brecha, nunca como
--     conforme. En control documental el silencio es incumplimiento.
--
-- ADITIVA. No modifica ni borra datos de otros módulos.
-- ============================================================================


-- ############################################################################
-- 0. AUTORIZACIÓN
-- ############################################################################
-- Prevención gestiona; el jefe de operaciones ve todo (es quien responde por
-- la gente en faena) y también puede corregir. Se engancha a la matriz
-- configurable de MIG126, módulo 'prevencion'.

CREATE OR REPLACE FUNCTION fn_prevencion_personal_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('prevencion', 'view', ARRAY[
        'administrador','gerencia','subgerente_operaciones','prevencionista',
        'jefe_operaciones','jefe_mantenimiento','supervisor','auditor','rrhh_incentivos'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_personal_puede_ver() TO authenticated;

CREATE OR REPLACE FUNCTION fn_prevencion_personal_puede_editar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('prevencion', 'edit', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'prevencionista','jefe_operaciones'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_personal_puede_editar() TO authenticated;

COMMENT ON FUNCTION fn_prevencion_personal_puede_ver() IS
    'Quién ve el control documental de personal. Incluye auditor. MIG298.';


-- ############################################################################
-- 1. CATÁLOGO DE TIPOS DE EXAMEN / DOCUMENTO
-- ############################################################################
-- Configurable: cada mandante exige su propio set. Agregar uno nuevo es un
-- INSERT, no una migración.

CREATE TABLE IF NOT EXISTS prevencion_examen_tipos (
    codigo      VARCHAR(40)  PRIMARY KEY,
    nombre      VARCHAR(160) NOT NULL,
    categoria   VARCHAR(30)  NOT NULL DEFAULT 'examen',  -- examen | licencia
    orden       INTEGER      NOT NULL DEFAULT 0,
    activo      BOOLEAN      NOT NULL DEFAULT true,
    descripcion TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE prevencion_examen_tipos IS
    'Catálogo de exámenes ocupacionales y licencias exigidos al personal. MIG298.';

INSERT INTO prevencion_examen_tipos (codigo, nombre, categoria, orden) VALUES
    ('ocupacional',   'Ocupacional / Preocupacional',   'examen',   1),
    ('alcohol_drogas','Alcohol y drogas',               'examen',   2),
    ('ruido',         'Ruido',                          'examen',   3),
    ('altura_fisica', 'Altura física',                  'examen',   4),
    ('psicosensotecnico', 'Psicosensotécnico Riguroso', 'examen',   5),
    ('licencia_municipal','Licencia municipal',         'licencia', 6),
    ('licencia_planta',   'Licencia interna de planta', 'licencia', 7),
    ('licencia_mina',     'Licencia interna de mina',   'licencia', 8)
ON CONFLICT (codigo) DO NOTHING;


-- ############################################################################
-- 2. PERSONAL
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_personal (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- RUT normalizado (sin puntos, con guion, DV en mayúscula). Es la llave
    -- natural: la planilla no tiene ningún otro identificador estable.
    rut           VARCHAR(20)  NOT NULL UNIQUE,
    nombres       VARCHAR(120) NOT NULL,
    apellidos     VARCHAR(120),
    empresa       VARCHAR(160),
    nro_contrato  VARCHAR(60),

    -- Faena donde presta servicios. Texto y no FK a `faenas` a propósito: el
    -- control documental parte por Romeral y hay personal que todavía no está
    -- asociado a una faena del maestro.
    faena_codigo  VARCHAR(60),
    cargo         VARCHAR(120),

    -- Enlace opcional al usuario del sistema, cuando la persona además tiene
    -- cuenta (por ejemplo la prevencionista).
    usuario_id    UUID REFERENCES usuarios_perfil(id) ON DELETE SET NULL,

    activo        BOOLEAN      NOT NULL DEFAULT true,
    observacion   TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_prev_personal_rut CHECK (length(trim(rut)) > 0)
);

COMMENT ON TABLE prevencion_personal IS
    'Personal bajo control documental de prevención. Llave natural: RUT. MIG298.';

CREATE INDEX IF NOT EXISTS idx_prev_personal_faena
    ON prevencion_personal (faena_codigo, activo);

DROP TRIGGER IF EXISTS trg_prev_personal_updated_at ON prevencion_personal;
CREATE TRIGGER trg_prev_personal_updated_at
    BEFORE UPDATE ON prevencion_personal
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 3. EXÁMENES
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_examenes (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    personal_id   UUID        NOT NULL REFERENCES prevencion_personal(id) ON DELETE CASCADE,
    tipo_codigo   VARCHAR(40) NOT NULL REFERENCES prevencion_examen_tipos(codigo),

    laboratorio        VARCHAR(160),
    fecha_emision      DATE,
    fecha_vencimiento  DATE,

    -- Exención: la persona no requiere este examen. NO es un dato faltante y
    -- el semáforo no lo cuenta como brecha, pero exige decir por qué.
    aplica             BOOLEAN NOT NULL DEFAULT true,
    motivo_no_aplica   TEXT,

    observacion        TEXT,
    -- Invalida el examen aunque la fecha esté vigente. Caso real: cuatro
    -- personas con psicosensotécnico al día pero de un laboratorio que CMP no
    -- acepta. Ante el mandante ese examen no sirve.
    observacion_bloqueante BOOLEAN NOT NULL DEFAULT false,

    archivo_url        TEXT,
    actualizado_por    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_prev_examen UNIQUE (personal_id, tipo_codigo),
    -- Una exención sin motivo es indefendible ante auditoría.
    CONSTRAINT chk_prev_examen_exencion
        CHECK (aplica OR (motivo_no_aplica IS NOT NULL AND length(trim(motivo_no_aplica)) > 0))
);

COMMENT ON TABLE prevencion_examenes IS
    'Exámenes y licencias por persona, con vencimiento, exención y observación bloqueante. MIG298.';

CREATE INDEX IF NOT EXISTS idx_prev_examenes_venc
    ON prevencion_examenes (fecha_vencimiento) WHERE aplica;

DROP TRIGGER IF EXISTS trg_prev_examenes_updated_at ON prevencion_examenes;
CREATE TRIGGER trg_prev_examenes_updated_at
    BEFORE UPDATE ON prevencion_examenes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 4. RLS
-- ############################################################################

ALTER TABLE prevencion_examen_tipos ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_personal     ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_examenes     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_tipos_select ON prevencion_examen_tipos;
CREATE POLICY prev_tipos_select ON prevencion_examen_tipos
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

DROP POLICY IF EXISTS prev_personal_select ON prevencion_personal;
CREATE POLICY prev_personal_select ON prevencion_personal
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

DROP POLICY IF EXISTS prev_personal_write ON prevencion_personal;
CREATE POLICY prev_personal_write ON prevencion_personal
    FOR ALL TO authenticated
    USING (fn_prevencion_personal_puede_editar())
    WITH CHECK (fn_prevencion_personal_puede_editar());

DROP POLICY IF EXISTS prev_examenes_select ON prevencion_examenes;
CREATE POLICY prev_examenes_select ON prevencion_examenes
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

DROP POLICY IF EXISTS prev_examenes_write ON prevencion_examenes;
CREATE POLICY prev_examenes_write ON prevencion_examenes
    FOR ALL TO authenticated
    USING (fn_prevencion_personal_puede_editar())
    WITH CHECK (fn_prevencion_personal_puede_editar());

GRANT SELECT ON prevencion_examen_tipos TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_personal TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_examenes TO authenticated;


-- ############################################################################
-- 5. SEMÁFORO
-- ############################################################################
-- Un solo lugar define qué es "vencido", "por vencer" y "observado", para que
-- la pantalla, el correo y el informe de auditoría no puedan discrepar.

CREATE OR REPLACE VIEW v_prevencion_examenes_estado AS
SELECT e.id,
       e.personal_id,
       p.rut, p.nombres, p.apellidos, p.empresa, p.nro_contrato,
       p.faena_codigo, p.activo AS persona_activa,
       e.tipo_codigo, t.nombre AS tipo_nombre, t.categoria, t.orden,
       e.laboratorio, e.fecha_vencimiento, e.aplica, e.motivo_no_aplica,
       e.observacion, e.observacion_bloqueante, e.archivo_url,
       (e.fecha_vencimiento - CURRENT_DATE) AS dias_restantes,
       CASE
           WHEN NOT e.aplica                          THEN 'no_aplica'
           -- El bloqueo del mandante manda sobre la fecha: un examen que el
           -- cliente no acepta no está vigente aunque el papel diga 2029.
           WHEN e.observacion_bloqueante              THEN 'observado'
           WHEN e.fecha_vencimiento IS NULL           THEN 'sin_dato'
           WHEN e.fecha_vencimiento <  CURRENT_DATE   THEN 'vencido'
           WHEN e.fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer_30'
           WHEN e.fecha_vencimiento <= CURRENT_DATE + 60 THEN 'por_vencer_60'
           ELSE 'vigente'
       END AS estado
  FROM prevencion_examenes e
  JOIN prevencion_personal p    ON p.id = e.personal_id
  JOIN prevencion_examen_tipos t ON t.codigo = e.tipo_codigo;

COMMENT ON VIEW v_prevencion_examenes_estado IS
    'Semáforo de cada examen. Fuente única para pantalla, correo e informe. MIG298.';


-- Una fila por persona con su peor estado: es como se lee en una reunión
-- ("¿quién no puede entrar a faena mañana?").
CREATE OR REPLACE VIEW v_prevencion_personal_estado AS
SELECT p.id AS personal_id, p.rut, p.nombres, p.apellidos, p.empresa,
       p.nro_contrato, p.faena_codigo, p.cargo, p.activo, p.observacion,
       count(*) FILTER (WHERE v.estado = 'vencido')::INTEGER       AS vencidos,
       count(*) FILTER (WHERE v.estado = 'observado')::INTEGER     AS observados,
       count(*) FILTER (WHERE v.estado = 'sin_dato')::INTEGER      AS sin_dato,
       count(*) FILTER (WHERE v.estado = 'por_vencer_30')::INTEGER AS por_vencer_30,
       count(*) FILTER (WHERE v.estado = 'por_vencer_60')::INTEGER AS por_vencer_60,
       count(*) FILTER (WHERE v.estado = 'vigente')::INTEGER       AS vigentes,
       count(*) FILTER (WHERE v.estado = 'no_aplica')::INTEGER     AS no_aplica,
       min(v.fecha_vencimiento) FILTER (WHERE v.aplica AND NOT v.observacion_bloqueante)
                                                                   AS proximo_vencimiento,
       CASE
           WHEN count(*) FILTER (WHERE v.estado IN ('vencido','sin_dato')) > 0 THEN 'no_conforme'
           WHEN count(*) FILTER (WHERE v.estado = 'observado') > 0             THEN 'observado'
           WHEN count(*) FILTER (WHERE v.estado = 'por_vencer_30') > 0         THEN 'por_vencer'
           ELSE 'conforme'
       END AS estado_general
  FROM prevencion_personal p
  LEFT JOIN v_prevencion_examenes_estado v ON v.personal_id = p.id
 GROUP BY p.id;

COMMENT ON VIEW v_prevencion_personal_estado IS
    'Una fila por persona con su peor estado documental. MIG298.';


-- ############################################################################
-- 6. EL TABLERO EN UNA LLAMADA
-- ############################################################################

DROP FUNCTION IF EXISTS fn_prevencion_control_documental(TEXT);
CREATE FUNCTION fn_prevencion_control_documental(p_faena TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out JSONB;
BEGIN
    IF NOT fn_prevencion_personal_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado para ver el control documental de personal.'
            USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'generado_at', NOW(),
        'faena', p_faena,
        'resumen', (
            SELECT jsonb_build_object(
                'personas',      count(*),
                'no_conformes',  count(*) FILTER (WHERE estado_general = 'no_conforme'),
                'observados',    count(*) FILTER (WHERE estado_general = 'observado'),
                'por_vencer',    count(*) FILTER (WHERE estado_general = 'por_vencer'),
                'conformes',     count(*) FILTER (WHERE estado_general = 'conforme'),
                'examenes_vencidos', COALESCE(SUM(vencidos), 0),
                'examenes_sin_dato', COALESCE(SUM(sin_dato), 0),
                'examenes_observados', COALESCE(SUM(observados), 0))
              FROM v_prevencion_personal_estado
             WHERE activo AND (p_faena IS NULL OR faena_codigo = p_faena)),

        'personas', COALESCE((
            SELECT jsonb_agg(to_jsonb(x) || jsonb_build_object(
                       'examenes', (
                           SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.orden), '[]'::JSONB)
                             FROM v_prevencion_examenes_estado e
                            WHERE e.personal_id = x.personal_id))
                   ORDER BY
                       -- Primero lo que bloquea el ingreso a faena.
                       CASE x.estado_general WHEN 'no_conforme' THEN 1 WHEN 'observado' THEN 2
                                             WHEN 'por_vencer'  THEN 3 ELSE 4 END,
                       x.proximo_vencimiento NULLS FIRST,
                       x.apellidos, x.nombres)
              FROM v_prevencion_personal_estado x
             WHERE x.activo AND (p_faena IS NULL OR x.faena_codigo = p_faena)), '[]'::JSONB),

        'faenas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('faena', faena_codigo, 'personas', n)
                             ORDER BY faena_codigo)
              FROM (SELECT COALESCE(faena_codigo, '(sin faena)') AS faena_codigo, count(*) n
                      FROM v_prevencion_personal_estado WHERE activo
                     GROUP BY 1) s), '[]'::JSONB)
    ) INTO v_out;

    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_control_documental(TEXT) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_control_documental(TEXT) IS
    'Control documental de personal completo en una llamada: resumen, personas y sus exámenes. MIG298.';
