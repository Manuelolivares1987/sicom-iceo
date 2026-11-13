-- ============================================================================
-- SICOM-ICEO | 685 — Inspección de terreno APR (Prevención Calama)
-- ============================================================================
-- Origen: «Inspección terreno (Prevención de Riesgos) 12-11-26», documento que
-- entregó prevención Calama. Describe el recorrido de verificación del APR en
-- 8 momentos (traslado → ingreso al área → documentos antes de ejecutar →
-- emergencias → durante el trabajo → trabajos cruzados → término → cierre de
-- la ART en Calama) y dice cómo se prueba cada punto: con FOTO o con
-- VERIFICACIÓN DOCUMENTAL desde un portal («TENER UN PORTAL DOCUMENTAL PARA
-- ESTO, Y QUE LA APLICACIÓN TOME DESDE ESTE PORTAL»).
--
-- Decisiones de Manuel (12-11-2026):
--   · Alcance: inspección + portal documental. Las QRA quedan para la fase 2.
--   · Trabajador con curso/acreditación vencida o faltante: se BLOQUEA (NO
--     HABILITADO), el punto queda «no cumple» y se genera una desviación sola.
--   · La hace el APR (prevención) en las faenas de Calama.
--   · Encuesta de fatiga y somnolencia estándar, con regla apto / no apto.
--
-- Piezas:
--   1. Catálogo: cursos del aula virtual Centinela y diploma Pillado entran al
--      MISMO control documental (prevencion_examen_tipos). Así tienen
--      vencimiento, respaldo, historial y alertas sin código nuevo.
--   2. Requisitos por grupo de personal (qué exige Calama a todos y qué solo
--      al conductor), atados al punto de la inspección que verifican.
--   3. Personal de Calama al control documental (hoy solo existía como nómina
--      de nombres; sin RUT ni documentos no hay nada que leer).
--   4. Plantilla de la inspección (los puntos del documento), tablas de la
--      inspección, personas, desviaciones.
--   5. RPC de habilitación y RPC de guardado. El guardado RECALCULA en la base
--      la habilitación documental y la fatiga: el teléfono no puede marcar
--      «cumple» lo que el portal dice que no.
--
-- ADITIVA. No modifica ni borra datos de otros módulos.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. CATÁLOGO: CURSOS Y COMPETENCIAS EN EL CONTROL DOCUMENTAL
-- ############################################################################
-- Sin vencimiento real (diploma): se carga con fecha 31-12-2099, la misma
-- convención que usa el sistema para «no vence».

INSERT INTO prevencion_examen_tipos (codigo, nombre, categoria, orden, descripcion) VALUES
    ('curso_art_centinela',
     'Curso ART — Aula virtual Centinela', 'curso', 20,
     'Curso obligatorio del mandante para elaborar el Análisis de Riesgos del Trabajo. Se verifica en la inspección de terreno APR.'),
    ('curso_emergencia_centinela',
     'Protocolo de emergencias (interno y mandante) — Aula virtual Centinela', 'curso', 21,
     'El trabajador sabe activar el protocolo y a quién llamar. Se verifica en la inspección de terreno APR.'),
    ('diploma_pillado',
     'Diploma de competencia Pillado (capacitación, evaluación y entrenamiento)', 'competencia', 22,
     'Acredita que el trabajador es competente para la tarea. Si no vence, cargar 31-12-2099.')
ON CONFLICT (codigo) DO NOTHING;


-- ############################################################################
-- 2. PLANTILLA DE LA INSPECCIÓN
-- ############################################################################
-- Una fila por punto del documento. `evidencia` dice cómo se prueba:
--   foto       → el APR toma la foto; «cumple» sin foto no se acepta
--   documental → lo decide el portal documental (no se marca a mano)
--   fatiga     → lo decide la encuesta de cada conductor
--   verbal     → verificación en terreno, foto opcional

CREATE TABLE IF NOT EXISTS prevencion_inspeccion_plantilla (
    codigo        VARCHAR(10)  PRIMARY KEY,
    etapa_orden   INTEGER      NOT NULL,
    etapa         VARCHAR(80)  NOT NULL,
    orden         INTEGER      NOT NULL,
    pregunta      TEXT         NOT NULL,
    ayuda         TEXT,
    evidencia     VARCHAR(12)  NOT NULL
                  CHECK (evidencia IN ('foto','documental','fatiga','verbal')),
    -- Puntos que se responden después de volver a Calama (cierre de la ART).
    posterior     BOOLEAN      NOT NULL DEFAULT false,
    -- Solo aplica si hubo trabajos cruzados.
    solo_cruzado  BOOLEAN      NOT NULL DEFAULT false,
    activo        BOOLEAN      NOT NULL DEFAULT true
);

COMMENT ON TABLE prevencion_inspeccion_plantilla IS
    'Puntos de la inspección de terreno APR (documento prevención Calama 12-11-26). MIG685.';

INSERT INTO prevencion_inspeccion_plantilla
    (codigo, etapa_orden, etapa, orden, pregunta, ayuda, evidencia, posterior, solo_cruzado) VALUES
 ('T1', 1, 'Traslado a faena', 1,
  'El operador realizó el check list del vehículo en la plataforma Centinela GCC (gestión de controles críticos).',
  'Foto de la pantalla GCC con el check list del día.', 'foto', false, false),
 ('T2', 1, 'Traslado a faena', 2,
  'Cada conductor respondió la encuesta de fatiga y somnolencia y resultó apto.',
  'Se responde en la pestaña Cuadrilla. Un conductor no apto no conduce.', 'fatiga', false, false),
 ('T3', 1, 'Traslado a faena', 3,
  'El conductor es competente: licencias, psicosensotécnico y acreditaciones vigentes.',
  'Lo decide el control documental. No se marca a mano.', 'documental', false, false),
 ('A1', 2, 'Ingreso al área de trabajo', 1,
  'Existen las autorizaciones, coordinaciones y permisos de ingreso al área.',
  'Foto del documento de autorización o permiso.', 'foto', false, false),
 ('A2', 2, 'Ingreso al área de trabajo', 2,
  'El área de trabajo está segregada con barreras duras.',
  'Foto de la segregación instalada.', 'foto', false, false),
 ('D1', 3, 'Documentación para ejecutar', 1,
  'Todos los trabajadores tienen el curso obligatorio ART del aula virtual Centinela.',
  'Lo decide el control documental.', 'documental', false, false),
 ('D2', 3, 'Documentación para ejecutar', 2,
  'Se realizó la difusión de seguridad diaria.',
  'Foto del comprobante de difusión con firmas.', 'foto', false, false),
 ('D3', 3, 'Documentación para ejecutar', 3,
  'La ART (análisis de riesgos del trabajo) está elaborada y firmada por la cuadrilla.',
  'Foto de la ART.', 'foto', false, false),
 ('D4', 3, 'Documentación para ejecutar', 4,
  'Se completó la lista de preexposición a las manos.',
  'Foto de la lista.', 'foto', false, false),
 ('D5', 3, 'Documentación para ejecutar', 5,
  'Se completó el check list de herramientas.',
  'Foto del check list.', 'foto', false, false),
 ('D6', 3, 'Documentación para ejecutar', 6,
  'Se completó el check list de estado y uso de EPP.',
  'Foto del check list de EPP.', 'foto', false, false),
 ('E1', 4, 'Protocolo de emergencias', 1,
  'Los trabajadores están capacitados en el protocolo de emergencias interno y del mandante.',
  'Curso del aula virtual Centinela, desde el control documental.', 'documental', false, false),
 ('E2', 4, 'Protocolo de emergencias', 2,
  'Consultados en terreno, los trabajadores saben activar el protocolo y a quién llamar.',
  'Pregunte a uno o más trabajadores. Foto opcional.', 'verbal', false, false),
 ('J1', 5, 'Durante la ejecución', 1,
  'Los trabajadores aplican los procedimientos e instructivos de trabajo.',
  'Foto del trabajo en ejecución.', 'foto', false, false),
 ('J2', 5, 'Durante la ejecución', 2,
  'Los trabajadores son competentes: capacitados, evaluados y entrenados (diploma Pillado).',
  'Lo decide el control documental.', 'documental', false, false),
 ('C1', 6, 'Trabajos cruzados', 1,
  'Hubo reunión entre empresas y cada una tomó conocimiento firmando la ART de trabajo cruzado.',
  'Foto de la ART de trabajo cruzado firmada.', 'foto', false, true),
 ('F1', 7, 'Término del trabajo', 1,
  'El área se entregó de forma eficaz y segura a su dueño.',
  'Foto del área entregada.', 'foto', false, false),
 ('F2', 7, 'Término del trabajo', 2,
  'Residuos en lugares apropiados, implementos guardados y área limpia y ordenada.',
  'Foto del área limpia.', 'foto', false, false),
 ('R1', 8, 'Cierre de la ART en Calama', 1,
  'La ART se cerró al retornar a Calama y quedó archivada en su carpeta física.',
  'Foto de la ART cerrada. Se responde al volver a Calama.', 'foto', true, false)
ON CONFLICT (codigo) DO UPDATE SET
    etapa_orden = EXCLUDED.etapa_orden, etapa = EXCLUDED.etapa, orden = EXCLUDED.orden,
    pregunta = EXCLUDED.pregunta, ayuda = EXCLUDED.ayuda, evidencia = EXCLUDED.evidencia,
    posterior = EXCLUDED.posterior, solo_cruzado = EXCLUDED.solo_cruzado;


-- ############################################################################
-- 3. REQUISITOS DOCUMENTALES POR GRUPO DE PERSONAL
-- ############################################################################
-- `grupo` = faena_codigo de prevencion_personal ('CALAMA'). Cada requisito
-- dice a quién aplica y qué punto de la inspección verifica.

CREATE TABLE IF NOT EXISTS prevencion_requisitos (
    grupo        VARCHAR(60) NOT NULL,
    tipo_codigo  VARCHAR(40) NOT NULL REFERENCES prevencion_examen_tipos(codigo),
    aplica_a     VARCHAR(10) NOT NULL DEFAULT 'todos'
                 CHECK (aplica_a IN ('todos','conductor')),
    item_codigo  VARCHAR(10) NOT NULL REFERENCES prevencion_inspeccion_plantilla(codigo),
    activo       BOOLEAN     NOT NULL DEFAULT true,
    PRIMARY KEY (grupo, tipo_codigo)
);

COMMENT ON TABLE prevencion_requisitos IS
    'Qué documentos exige cada grupo de personal y qué punto de la inspección APR verifican. MIG685.';

INSERT INTO prevencion_requisitos (grupo, tipo_codigo, aplica_a, item_codigo) VALUES
    ('CALAMA', 'licencia_municipal',         'conductor', 'T3'),
    ('CALAMA', 'licencia_mina',              'conductor', 'T3'),
    ('CALAMA', 'psicosensotecnico',          'conductor', 'T3'),
    ('CALAMA', 'curso_art_centinela',        'todos',     'D1'),
    ('CALAMA', 'curso_emergencia_centinela', 'todos',     'E1'),
    ('CALAMA', 'diploma_pillado',            'todos',     'J2')
ON CONFLICT (grupo, tipo_codigo) DO NOTHING;


-- Faenas donde se hace la inspección y de qué grupo sale su personal.
CREATE TABLE IF NOT EXISTS prevencion_inspeccion_faenas (
    faena_id        UUID        PRIMARY KEY REFERENCES faenas(id) ON DELETE CASCADE,
    grupo_personal  VARCHAR(60) NOT NULL,
    activo          BOOLEAN     NOT NULL DEFAULT true
);

COMMENT ON TABLE prevencion_inspeccion_faenas IS
    'Faenas con inspección de terreno APR y el grupo de personal que las atiende. MIG685.';

INSERT INTO prevencion_inspeccion_faenas (faena_id, grupo_personal)
SELECT id, 'CALAMA' FROM faenas
 WHERE codigo IN ('FAE-CENTINELA','FAE-LOMASBAYAS','FAE-LOMASBAYAS-LUB','FAE-SPENCE')
ON CONFLICT (faena_id) DO NOTHING;


-- ############################################################################
-- 4. PERSONAL DE CALAMA AL CONTROL DOCUMENTAL
-- ############################################################################
-- La nómina de Calama (MIG555) son 9 nombres sin RUT. Se crean en el control
-- documental con un RUT PROVISORIO que la pantalla marca para completar. Sin
-- documentos cargados, cada uno aparecerá NO HABILITADO: es lo correcto (sin
-- dato = incumplimiento), y es lo que hay que cargar antes de inspeccionar.

INSERT INTO prevencion_personal (rut, nombres, apellidos, empresa, faena_codigo, observacion)
SELECT 'PEND-CAL-' || lpad(row_number() OVER (ORDER BY n.nombre)::text, 2, '0'),
       split_part(n.nombre, ' ', 1),
       NULLIF(substr(n.nombre, length(split_part(n.nombre, ' ', 1)) + 2), ''),
       'Pillado y Compañía Limitada',
       'CALAMA',
       'RUT provisorio: completar el RUT real.'
  FROM (SELECT DISTINCT pf.nombre
          FROM prevencion_personal_faena pf
          JOIN prevencion_inspeccion_faenas f ON f.faena_id = pf.faena_id
         WHERE pf.activo) n
 WHERE NOT EXISTS (
        SELECT 1 FROM prevencion_personal p
         WHERE p.faena_codigo = 'CALAMA'
           AND lower(p.nombres || ' ' || COALESCE(p.apellidos, '')) = lower(n.nombre));

-- Cada requisito del grupo queda como ítem «sin dato» en la ficha de la
-- persona. Sin esto, alguien sin ningún registro sale «conforme» en el
-- tablero (no tiene nada vencido). Así el control documental muestra qué
-- falta y ofrece «Renovar» para subir el respaldo. A quien no conduce se le
-- marca «No aplica — No conduce en faena» (exención con motivo, MIG298).
CREATE OR REPLACE FUNCTION fn_prevencion_crear_requisitos_persona()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO prevencion_examenes (personal_id, tipo_codigo, aplica)
    SELECT NEW.id, r.tipo_codigo, true
      FROM prevencion_requisitos r
     WHERE r.grupo = NEW.faena_codigo AND r.activo
    ON CONFLICT (personal_id, tipo_codigo) DO NOTHING;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_prev_personal_requisitos ON prevencion_personal;
CREATE TRIGGER trg_prev_personal_requisitos
    AFTER INSERT OR UPDATE OF faena_codigo ON prevencion_personal
    FOR EACH ROW EXECUTE FUNCTION fn_prevencion_crear_requisitos_persona();

INSERT INTO prevencion_examenes (personal_id, tipo_codigo, aplica)
SELECT p.id, r.tipo_codigo, true
  FROM prevencion_personal p
  JOIN prevencion_requisitos r ON r.grupo = p.faena_codigo AND r.activo
ON CONFLICT (personal_id, tipo_codigo) DO NOTHING;


-- ############################################################################
-- 5. LA INSPECCIÓN
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_inspecciones (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Generado en el teléfono: el guardado es idempotente (sin señal, se
    -- reintenta sin duplicar).
    cliente_uuid     UUID         NOT NULL UNIQUE,
    faena_id         UUID         NOT NULL REFERENCES faenas(id),
    fecha            DATE         NOT NULL,
    hora_inicio      TIME,
    instalacion      VARCHAR(160),
    area_sector      VARCHAR(160),
    trabajo          TEXT         NOT NULL,
    supervisor       VARCHAR(160),
    trabajo_cruzado  BOOLEAN      NOT NULL DEFAULT false,
    empresas_cruzadas TEXT,
    observacion      TEXT,

    -- Calculado en la base al guardar.
    estado           VARCHAR(24)  NOT NULL DEFAULT 'en_curso'
                     CHECK (estado IN ('en_curso','pendiente_cierre_art','cerrada')),
    resultado        VARCHAR(20)  NOT NULL DEFAULT 'conforme'
                     CHECK (resultado IN ('conforme','con_desviaciones','critico')),
    pct_cumplimiento NUMERIC(5,1),
    items_cumple     INTEGER      NOT NULL DEFAULT 0,
    items_no_cumple  INTEGER      NOT NULL DEFAULT 0,
    items_no_aplica  INTEGER      NOT NULL DEFAULT 0,
    items_pendientes INTEGER      NOT NULL DEFAULT 0,
    personas_no_habilitadas INTEGER NOT NULL DEFAULT 0,

    inspector_id     UUID         NOT NULL REFERENCES auth.users(id),
    inspector_nombre VARCHAR(160),
    cerrada_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prev_insp_faena_fecha ON prevencion_inspecciones (faena_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_prev_insp_inspector   ON prevencion_inspecciones (inspector_id, fecha DESC);

DROP TRIGGER IF EXISTS trg_prev_insp_updated_at ON prevencion_inspecciones;
CREATE TRIGGER trg_prev_insp_updated_at
    BEFORE UPDATE ON prevencion_inspecciones
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

COMMENT ON TABLE prevencion_inspecciones IS
    'Inspección de terreno APR: cabecera y resultado calculado en la base. MIG685.';


CREATE TABLE IF NOT EXISTS prevencion_inspeccion_items (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    inspeccion_id  UUID        NOT NULL REFERENCES prevencion_inspecciones(id) ON DELETE CASCADE,
    item_codigo    VARCHAR(10) NOT NULL REFERENCES prevencion_inspeccion_plantilla(codigo),
    -- Copia del texto: si la plantilla cambia, el informe sigue diciendo lo
    -- que se preguntó ese día.
    etapa          VARCHAR(80) NOT NULL,
    pregunta       TEXT        NOT NULL,
    evidencia_tipo VARCHAR(12) NOT NULL,
    respuesta      VARCHAR(12) CHECK (respuesta IN ('cumple','no_cumple','no_aplica')),
    observacion    TEXT,
    evidencias     JSONB       NOT NULL DEFAULT '[]'::jsonb,
    automatico     BOOLEAN     NOT NULL DEFAULT false,
    CONSTRAINT uq_prev_insp_item UNIQUE (inspeccion_id, item_codigo)
);


CREATE TABLE IF NOT EXISTS prevencion_inspeccion_personas (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    inspeccion_id     UUID        NOT NULL REFERENCES prevencion_inspecciones(id) ON DELETE CASCADE,
    personal_id       UUID        NOT NULL REFERENCES prevencion_personal(id),
    nombre            VARCHAR(250) NOT NULL,
    rut               VARCHAR(20),
    es_conductor      BOOLEAN     NOT NULL DEFAULT false,
    -- Foto del estado documental el día de la inspección: la pregunta de una
    -- fiscalización es «¿estaba habilitado ESE día?», no «¿lo está hoy?».
    habilitado        BOOLEAN     NOT NULL,
    requisitos        JSONB       NOT NULL DEFAULT '[]'::jsonb,
    fatiga_respuestas JSONB,
    fatiga_resultado  VARCHAR(20) CHECK (fatiga_resultado IN ('apto','apto_observacion','no_apto')),
    fatiga_motivos    TEXT[],
    CONSTRAINT uq_prev_insp_persona UNIQUE (inspeccion_id, personal_id)
);


CREATE TABLE IF NOT EXISTS prevencion_inspeccion_desviaciones (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    inspeccion_id     UUID        NOT NULL REFERENCES prevencion_inspecciones(id) ON DELETE CASCADE,
    item_codigo       VARCHAR(10),
    personal_id       UUID        REFERENCES prevencion_personal(id),
    origen            VARCHAR(12) NOT NULL CHECK (origen IN ('item','documental','fatiga')),
    criticidad        VARCHAR(8)  NOT NULL DEFAULT 'media' CHECK (criticidad IN ('alta','media','baja')),
    descripcion       TEXT        NOT NULL,
    accion            TEXT,
    responsable       VARCHAR(160),
    fecha_compromiso  DATE,
    estado            VARCHAR(10) NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','cerrada')),
    cierre_observacion TEXT,
    cierre_evidencias JSONB       NOT NULL DEFAULT '[]'::jsonb,
    cerrada_por       UUID        REFERENCES auth.users(id),
    cerrada_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_prev_desv_cierre
        CHECK (estado = 'abierta' OR (cierre_observacion IS NOT NULL AND length(trim(cierre_observacion)) > 0))
);

CREATE INDEX IF NOT EXISTS idx_prev_desv_estado ON prevencion_inspeccion_desviaciones (estado, fecha_compromiso);
CREATE INDEX IF NOT EXISTS idx_prev_desv_insp   ON prevencion_inspeccion_desviaciones (inspeccion_id);


-- ############################################################################
-- 6. RLS
-- ############################################################################
-- Ver: quien ve reportabilidad de prevención (respetando solo_su_faena).
-- Crear/editar: el APR y la administración del módulo
-- (fn_prevencion_reporta_puede_admin = administrador, prevencionista,
-- jefe_operaciones, subgerente_operaciones). Las escrituras de la inspección
-- van por el RPC; directo solo se cierran desviaciones.

ALTER TABLE prevencion_inspeccion_plantilla    ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_requisitos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_inspeccion_faenas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_inspecciones            ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_inspeccion_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_inspeccion_personas     ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_inspeccion_desviaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_insp_plantilla_sel ON prevencion_inspeccion_plantilla;
CREATE POLICY prev_insp_plantilla_sel ON prevencion_inspeccion_plantilla
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_requisitos_sel ON prevencion_requisitos;
CREATE POLICY prev_requisitos_sel ON prevencion_requisitos
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_personal_puede_ver());
DROP POLICY IF EXISTS prev_requisitos_admin ON prevencion_requisitos;
CREATE POLICY prev_requisitos_admin ON prevencion_requisitos
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin()) WITH CHECK (fn_prevencion_reporta_puede_admin());

DROP POLICY IF EXISTS prev_insp_faenas_sel ON prevencion_inspeccion_faenas;
CREATE POLICY prev_insp_faenas_sel ON prevencion_inspeccion_faenas
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_insp_sel ON prevencion_inspecciones;
CREATE POLICY prev_insp_sel ON prevencion_inspecciones
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR inspector_id = auth.uid())
           AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_insp_items_sel ON prevencion_inspeccion_items;
CREATE POLICY prev_insp_items_sel ON prevencion_inspeccion_items
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM prevencion_inspecciones i WHERE i.id = inspeccion_id));

DROP POLICY IF EXISTS prev_insp_pers_sel ON prevencion_inspeccion_personas;
CREATE POLICY prev_insp_pers_sel ON prevencion_inspeccion_personas
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM prevencion_inspecciones i WHERE i.id = inspeccion_id));

DROP POLICY IF EXISTS prev_insp_desv_sel ON prevencion_inspeccion_desviaciones;
CREATE POLICY prev_insp_desv_sel ON prevencion_inspeccion_desviaciones
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM prevencion_inspecciones i WHERE i.id = inspeccion_id));

DROP POLICY IF EXISTS prev_insp_desv_upd ON prevencion_inspeccion_desviaciones;
CREATE POLICY prev_insp_desv_upd ON prevencion_inspeccion_desviaciones
    FOR UPDATE TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT ON prevencion_inspeccion_plantilla, prevencion_requisitos,
               prevencion_inspeccion_faenas, prevencion_inspecciones,
               prevencion_inspeccion_items, prevencion_inspeccion_personas,
               prevencion_inspeccion_desviaciones TO authenticated;
GRANT INSERT, UPDATE, DELETE ON prevencion_requisitos TO authenticated;
GRANT UPDATE ON prevencion_inspeccion_desviaciones TO authenticated;


-- ############################################################################
-- 7. HABILITACIÓN DOCUMENTAL
-- ############################################################################
-- Una fila por requisito de la persona. Sin registro = 'sin_dato' (silencio =
-- incumplimiento, regla de MIG298). Habilita: vigente, por vencer o exento.

CREATE OR REPLACE FUNCTION fn_prevencion_requisitos_persona(
    p_personal_id UUID, p_es_conductor BOOLEAN)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'tipo_codigo', r.tipo_codigo,
               'nombre',      t.nombre,
               'categoria',   t.categoria,
               'item_codigo', r.item_codigo,
               'aplica_a',    r.aplica_a,
               'estado',      COALESCE(v.estado, 'sin_dato'),
               'vence',       v.fecha_vencimiento,
               'ok',          COALESCE(v.estado, 'sin_dato') NOT IN ('vencido','sin_dato','observado'))
             ORDER BY t.orden), '[]'::jsonb)
      FROM prevencion_personal p
      JOIN prevencion_requisitos r   ON r.grupo = p.faena_codigo AND r.activo
      JOIN prevencion_examen_tipos t ON t.codigo = r.tipo_codigo
      LEFT JOIN v_prevencion_examenes_estado v
             ON v.personal_id = p.id AND v.tipo_codigo = r.tipo_codigo
     WHERE p.id = p_personal_id
       AND (r.aplica_a = 'todos' OR p_es_conductor);
$$;


-- Habilitación de todo el grupo, para la pantalla (cuadrilla y portal).
CREATE OR REPLACE FUNCTION fn_prevencion_habilitacion(p_grupo TEXT DEFAULT 'CALAMA')
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()
            OR fn_prevencion_personal_puede_ver()) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'generado_at', NOW(),
        'grupo', p_grupo,
        'requisitos', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'tipo_codigo', r.tipo_codigo, 'nombre', t.nombre,
                       'aplica_a', r.aplica_a, 'item_codigo', r.item_codigo)
                     ORDER BY t.orden), '[]'::jsonb)
              FROM prevencion_requisitos r
              JOIN prevencion_examen_tipos t ON t.codigo = r.tipo_codigo
             WHERE r.grupo = p_grupo AND r.activo),
        'personas', (
            SELECT COALESCE(jsonb_agg(x ORDER BY x->>'nombre'), '[]'::jsonb)
              FROM (
                SELECT jsonb_build_object(
                         'personal_id', p.id,
                         'nombre', trim(p.nombres || ' ' || COALESCE(p.apellidos, '')),
                         'rut', p.rut,
                         'rut_provisorio', p.rut LIKE 'PEND-%',
                         'cargo', p.cargo,
                         'requisitos', req,
                         'habilitado', NOT EXISTS (
                             SELECT 1 FROM jsonb_array_elements(req) e
                              WHERE e->>'aplica_a' = 'todos' AND NOT (e->>'ok')::boolean),
                         'habilitado_conductor', NOT EXISTS (
                             SELECT 1 FROM jsonb_array_elements(req) e
                              WHERE NOT (e->>'ok')::boolean)) AS x
                  FROM prevencion_personal p
                  CROSS JOIN LATERAL fn_prevencion_requisitos_persona(p.id, true) req
                 WHERE p.faena_codigo = p_grupo AND p.activo) s)
    );
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_habilitacion(TEXT) TO authenticated;


-- ############################################################################
-- 8. FATIGA Y SOMNOLENCIA
-- ############################################################################
-- Regla estándar (criterio de probabilidad de fatiga usado en minería):
--   NO APTO si: durmió < 5 h en las últimas 24 h, < 12 h en las últimas 48 h,
--   lleva más horas despierto que las dormidas en 48 h, consumió alcohol en
--   las últimas 12 h, tomó medicamentos que dan sueño, se siente enfermo o
--   presenta señales de somnolencia.
--   APTO CON OBSERVACIÓN si: durmió < 6 h en 24 h o declara preocupaciones
--   que le impiden concentrarse.

CREATE OR REPLACE FUNCTION fn_prevencion_evaluar_fatiga(p JSONB)
RETURNS TABLE (resultado TEXT, motivos TEXT[])
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    h24  NUMERIC := NULLIF(p->>'horas_24', '')::numeric;
    h48  NUMERIC := NULLIF(p->>'horas_48', '')::numeric;
    hdes NUMERIC := NULLIF(p->>'horas_despierto', '')::numeric;
    m    TEXT[]  := ARRAY[]::text[];
    obs  TEXT[]  := ARRAY[]::text[];
BEGIN
    IF h24 IS NULL OR h48 IS NULL OR hdes IS NULL THEN
        m := m || 'Encuesta incompleta (horas de sueño)';
    ELSE
        IF h24 < 5  THEN m := m || format('Durmió %s h en 24 h (mínimo 5)', h24); END IF;
        IF h48 < 12 THEN m := m || format('Durmió %s h en 48 h (mínimo 12)', h48); END IF;
        IF hdes > h48 THEN m := m || format('Lleva %s h despierto, más que lo dormido en 48 h', hdes); END IF;
        IF h24 >= 5 AND h24 < 6 THEN obs := obs || format('Durmió %s h en 24 h', h24); END IF;
    END IF;
    IF COALESCE((p->>'alcohol')::boolean, false)      THEN m := m || 'Consumió alcohol en las últimas 12 h'; END IF;
    IF COALESCE((p->>'medicamentos')::boolean, false) THEN m := m || 'Medicamentos que producen somnolencia'; END IF;
    IF COALESCE((p->>'malestar')::boolean, false)     THEN m := m || 'Se siente enfermo o con malestar'; END IF;
    IF COALESCE((p->>'somnolencia')::boolean, false)  THEN m := m || 'Señales de somnolencia'; END IF;
    IF COALESCE((p->>'preocupaciones')::boolean, false) THEN obs := obs || 'Preocupaciones que afectan su concentración'; END IF;

    IF array_length(m, 1) > 0 THEN
        RETURN QUERY SELECT 'no_apto'::text, m;
    ELSIF array_length(obs, 1) > 0 THEN
        RETURN QUERY SELECT 'apto_observacion'::text, obs;
    ELSE
        RETURN QUERY SELECT 'apto'::text, ARRAY[]::text[];
    END IF;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_evaluar_fatiga(JSONB) TO authenticated;


-- ############################################################################
-- 9. GUARDAR LA INSPECCIÓN (idempotente por cliente_uuid)
-- ############################################################################
-- Payload:
-- { cliente_uuid, faena_id, fecha, hora_inicio, instalacion, area_sector,
--   trabajo, supervisor, trabajo_cruzado, empresas_cruzadas, observacion,
--   personas: [{personal_id, es_conductor, fatiga:{...}}],
--   items: [{item_codigo, respuesta, observacion, evidencias:[...]}],
--   desviaciones: [{item_codigo, descripcion, accion, responsable,
--                   fecha_compromiso, criticidad}] }
--
-- Lo que la base decide (no el teléfono): habilitación documental, fatiga,
-- respuesta de los puntos 'documental' y 'fatiga', desviaciones automáticas,
-- % de cumplimiento, resultado y estado.

CREATE OR REPLACE FUNCTION fn_prevencion_inspeccion_guardar(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id        UUID;
    v_prev      prevencion_inspecciones%ROWTYPE;
    v_cruzado   BOOLEAN := COALESCE((p->>'trabajo_cruzado')::boolean, false);
    v_pers      JSONB;
    v_req       JSONB;
    v_hab       BOOLEAN;
    v_fat_res   TEXT;
    v_fat_mot   TEXT[];
    v_nombre    TEXT;
    v_rut       TEXT;
    v_it        RECORD;
    v_resp      TEXT;
    v_obs       TEXT;
    v_evid      JSONB;
    v_cumple    INT;
    v_nocumple  INT;
    v_noaplica  INT;
    v_pend      INT;
    v_pend_post INT;
    v_nohab     INT;
    v_criticos  INT;
    v_estado    TEXT;
    v_resultado TEXT;
BEGIN
    IF NOT fn_prevencion_reporta_puede_admin() THEN
        RAISE EXCEPTION 'Solo prevención (APR) registra inspecciones de terreno.'
            USING ERRCODE = '42501';
    END IF;
    IF NULLIF(trim(p->>'trabajo'), '') IS NULL THEN
        RAISE EXCEPTION 'Describa el trabajo inspeccionado.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM prevencion_inspeccion_faenas
                    WHERE faena_id = (p->>'faena_id')::uuid AND activo) THEN
        RAISE EXCEPTION 'La faena no tiene inspección de terreno APR configurada.';
    END IF;
    IF jsonb_array_length(COALESCE(p->'personas', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Indique la cuadrilla inspeccionada (al menos un trabajador).';
    END IF;

    SELECT * INTO v_prev FROM prevencion_inspecciones
     WHERE cliente_uuid = (p->>'cliente_uuid')::uuid;

    IF FOUND THEN
        IF v_prev.inspector_id <> auth.uid()
           AND NOT (fn_user_rol() = ANY (ARRAY['administrador','prevencionista'])) THEN
            RAISE EXCEPTION 'Esta inspección es de otro inspector.' USING ERRCODE = '42501';
        END IF;
        IF v_prev.estado = 'cerrada' THEN
            RAISE EXCEPTION 'La inspección ya está cerrada.';
        END IF;
        v_id := v_prev.id;
        UPDATE prevencion_inspecciones SET
            faena_id = (p->>'faena_id')::uuid,
            fecha = (p->>'fecha')::date,
            hora_inicio = NULLIF(p->>'hora_inicio', '')::time,
            instalacion = NULLIF(trim(p->>'instalacion'), ''),
            area_sector = NULLIF(trim(p->>'area_sector'), ''),
            trabajo = trim(p->>'trabajo'),
            supervisor = NULLIF(trim(p->>'supervisor'), ''),
            trabajo_cruzado = v_cruzado,
            empresas_cruzadas = NULLIF(trim(p->>'empresas_cruzadas'), ''),
            observacion = NULLIF(trim(p->>'observacion'), '')
         WHERE id = v_id;
        DELETE FROM prevencion_inspeccion_items    WHERE inspeccion_id = v_id;
        DELETE FROM prevencion_inspeccion_personas WHERE inspeccion_id = v_id;
        -- Las desviaciones ya cerradas se conservan; las abiertas se rehacen.
        DELETE FROM prevencion_inspeccion_desviaciones
         WHERE inspeccion_id = v_id AND estado = 'abierta';
    ELSE
        INSERT INTO prevencion_inspecciones (
            cliente_uuid, faena_id, fecha, hora_inicio, instalacion, area_sector,
            trabajo, supervisor, trabajo_cruzado, empresas_cruzadas, observacion,
            inspector_id, inspector_nombre)
        VALUES (
            (p->>'cliente_uuid')::uuid, (p->>'faena_id')::uuid, (p->>'fecha')::date,
            NULLIF(p->>'hora_inicio', '')::time,
            NULLIF(trim(p->>'instalacion'), ''), NULLIF(trim(p->>'area_sector'), ''),
            trim(p->>'trabajo'), NULLIF(trim(p->>'supervisor'), ''),
            v_cruzado, NULLIF(trim(p->>'empresas_cruzadas'), ''),
            NULLIF(trim(p->>'observacion'), ''),
            auth.uid(),
            (SELECT nombre_completo FROM usuarios_perfil WHERE id = auth.uid()))
        RETURNING id INTO v_id;
    END IF;

    -- ── Cuadrilla: habilitación y fatiga calculadas acá ─────────────────────
    FOR v_pers IN SELECT * FROM jsonb_array_elements(p->'personas') LOOP
        SELECT trim(pp.nombres || ' ' || COALESCE(pp.apellidos, '')), pp.rut
          INTO v_nombre, v_rut
          FROM prevencion_personal pp WHERE pp.id = (v_pers->>'personal_id')::uuid;
        IF v_nombre IS NULL THEN
            RAISE EXCEPTION 'Trabajador no encontrado en el control documental.';
        END IF;

        v_req := fn_prevencion_requisitos_persona(
                     (v_pers->>'personal_id')::uuid,
                     COALESCE((v_pers->>'es_conductor')::boolean, false));
        v_hab := NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_req) e
                              WHERE NOT (e->>'ok')::boolean);

        v_fat_res := NULL; v_fat_mot := NULL;
        IF COALESCE((v_pers->>'es_conductor')::boolean, false) THEN
            SELECT f.resultado, f.motivos INTO v_fat_res, v_fat_mot
              FROM fn_prevencion_evaluar_fatiga(COALESCE(v_pers->'fatiga', '{}'::jsonb)) f;
        END IF;

        INSERT INTO prevencion_inspeccion_personas (
            inspeccion_id, personal_id, nombre, rut, es_conductor, habilitado,
            requisitos, fatiga_respuestas, fatiga_resultado, fatiga_motivos)
        VALUES (
            v_id, (v_pers->>'personal_id')::uuid, v_nombre, v_rut,
            COALESCE((v_pers->>'es_conductor')::boolean, false), v_hab, v_req,
            CASE WHEN COALESCE((v_pers->>'es_conductor')::boolean, false) THEN v_pers->'fatiga' END,
            v_fat_res, v_fat_mot);

        -- Desviación por cada requisito que no cumple: el trabajador NO estaba
        -- habilitado para ejecutar.
        INSERT INTO prevencion_inspeccion_desviaciones (
            inspeccion_id, item_codigo, personal_id, origen, criticidad,
            descripcion, accion, responsable, fecha_compromiso)
        SELECT v_id, e->>'item_codigo', (v_pers->>'personal_id')::uuid, 'documental', 'alta',
               format('%s NO HABILITADO: %s %s.', v_nombre, e->>'nombre',
                      CASE e->>'estado'
                          WHEN 'vencido'   THEN 'vencido'
                          WHEN 'observado' THEN 'observado (no aceptado)'
                          ELSE 'sin registro en el control documental' END),
               'Retirar de la tarea hasta regularizar y cargar el respaldo en el control documental.',
               NULL, (p->>'fecha')::date + 1
          FROM jsonb_array_elements(v_req) e
         WHERE NOT (e->>'ok')::boolean
           AND NOT EXISTS (
                 SELECT 1 FROM prevencion_inspeccion_desviaciones d
                  WHERE d.inspeccion_id = v_id AND d.estado = 'cerrada'
                    AND d.personal_id = (v_pers->>'personal_id')::uuid
                    AND d.origen = 'documental' AND d.item_codigo = e->>'item_codigo');

        IF v_fat_res = 'no_apto' AND NOT EXISTS (
               SELECT 1 FROM prevencion_inspeccion_desviaciones d
                WHERE d.inspeccion_id = v_id AND d.estado = 'cerrada'
                  AND d.personal_id = (v_pers->>'personal_id')::uuid AND d.origen = 'fatiga') THEN
            INSERT INTO prevencion_inspeccion_desviaciones (
                inspeccion_id, item_codigo, personal_id, origen, criticidad,
                descripcion, accion, fecha_compromiso)
            VALUES (v_id, 'T2', (v_pers->>'personal_id')::uuid, 'fatiga', 'alta',
                    format('%s NO APTO para conducir: %s.', v_nombre, array_to_string(v_fat_mot, '; ')),
                    'No conduce. Reasignar conductor y reportar a la supervisión.',
                    (p->>'fecha')::date);
        END IF;
    END LOOP;

    -- ── Puntos de la inspección ─────────────────────────────────────────────
    FOR v_it IN SELECT * FROM prevencion_inspeccion_plantilla WHERE activo
                 ORDER BY etapa_orden, orden LOOP
        SELECT x INTO v_pers FROM jsonb_array_elements(COALESCE(p->'items', '[]'::jsonb)) x
         WHERE x->>'item_codigo' = v_it.codigo LIMIT 1;
        v_obs  := NULLIF(trim(v_pers->>'observacion'), '');
        v_evid := COALESCE(v_pers->'evidencias', '[]'::jsonb);
        v_resp := NULLIF(v_pers->>'respuesta', '');

        IF v_it.solo_cruzado AND NOT v_cruzado THEN
            v_resp := 'no_aplica';
        ELSIF v_it.evidencia = 'documental' THEN
            IF NOT EXISTS (
                SELECT 1 FROM prevencion_inspeccion_personas ip,
                              jsonb_array_elements(ip.requisitos) e
                 WHERE ip.inspeccion_id = v_id AND e->>'item_codigo' = v_it.codigo) THEN
                v_resp := 'no_aplica';
            ELSIF EXISTS (
                SELECT 1 FROM prevencion_inspeccion_personas ip,
                              jsonb_array_elements(ip.requisitos) e
                 WHERE ip.inspeccion_id = v_id AND e->>'item_codigo' = v_it.codigo
                   AND NOT (e->>'ok')::boolean) THEN
                v_resp := 'no_cumple';
            ELSE
                v_resp := 'cumple';
            END IF;
        ELSIF v_it.evidencia = 'fatiga' THEN
            IF NOT EXISTS (SELECT 1 FROM prevencion_inspeccion_personas
                            WHERE inspeccion_id = v_id AND es_conductor) THEN
                v_resp := 'no_aplica';
            ELSIF EXISTS (SELECT 1 FROM prevencion_inspeccion_personas
                           WHERE inspeccion_id = v_id AND es_conductor
                             AND fatiga_resultado = 'no_apto') THEN
                v_resp := 'no_cumple';
            ELSE
                v_resp := 'cumple';
            END IF;
        ELSIF v_resp = 'cumple' AND v_it.evidencia = 'foto'
              AND jsonb_array_length(v_evid) = 0 THEN
            RAISE EXCEPTION 'El punto % (%) exige foto para marcarlo como cumple.',
                v_it.codigo, v_it.pregunta;
        END IF;

        INSERT INTO prevencion_inspeccion_items (
            inspeccion_id, item_codigo, etapa, pregunta, evidencia_tipo,
            respuesta, observacion, evidencias, automatico)
        VALUES (v_id, v_it.codigo, v_it.etapa, v_it.pregunta, v_it.evidencia,
                v_resp, v_obs, v_evid,
                v_it.evidencia IN ('documental','fatiga') OR (v_it.solo_cruzado AND NOT v_cruzado));
    END LOOP;

    -- ── Desviaciones de los puntos «no cumple» marcados por el APR ──────────
    INSERT INTO prevencion_inspeccion_desviaciones (
        inspeccion_id, item_codigo, origen, criticidad, descripcion, accion,
        responsable, fecha_compromiso)
    SELECT v_id, d->>'item_codigo', 'item',
           COALESCE(NULLIF(d->>'criticidad', ''), 'media'),
           trim(d->>'descripcion'), NULLIF(trim(d->>'accion'), ''),
           NULLIF(trim(d->>'responsable'), ''),
           NULLIF(d->>'fecha_compromiso', '')::date
      FROM jsonb_array_elements(COALESCE(p->'desviaciones', '[]'::jsonb)) d
     WHERE NULLIF(trim(d->>'descripcion'), '') IS NOT NULL
       AND EXISTS (SELECT 1 FROM prevencion_inspeccion_items i
                    WHERE i.inspeccion_id = v_id AND i.item_codigo = d->>'item_codigo'
                      AND i.respuesta = 'no_cumple' AND NOT i.automatico);

    IF EXISTS (SELECT 1 FROM prevencion_inspeccion_items i
                WHERE i.inspeccion_id = v_id AND i.respuesta = 'no_cumple' AND NOT i.automatico
                  AND NOT EXISTS (SELECT 1 FROM prevencion_inspeccion_desviaciones d
                                   WHERE d.inspeccion_id = v_id AND d.item_codigo = i.item_codigo)) THEN
        RAISE EXCEPTION 'Cada punto «no cumple» debe llevar su desviación (qué se encontró, responsable y plazo).';
    END IF;

    -- ── Resultado ───────────────────────────────────────────────────────────
    SELECT count(*) FILTER (WHERE i.respuesta = 'cumple'),
           count(*) FILTER (WHERE i.respuesta = 'no_cumple'),
           count(*) FILTER (WHERE i.respuesta = 'no_aplica'),
           count(*) FILTER (WHERE i.respuesta IS NULL AND NOT pl.posterior),
           count(*) FILTER (WHERE i.respuesta IS NULL AND pl.posterior)
      INTO v_cumple, v_nocumple, v_noaplica, v_pend, v_pend_post
      FROM prevencion_inspeccion_items i
      JOIN prevencion_inspeccion_plantilla pl ON pl.codigo = i.item_codigo
     WHERE i.inspeccion_id = v_id;

    SELECT count(*) FILTER (WHERE NOT habilitado),
           count(*) FILTER (WHERE NOT habilitado OR fatiga_resultado = 'no_apto')
      INTO v_nohab, v_criticos
      FROM prevencion_inspeccion_personas WHERE inspeccion_id = v_id;

    v_estado := CASE WHEN v_pend > 0 THEN 'en_curso'
                     WHEN v_pend_post > 0 THEN 'pendiente_cierre_art'
                     ELSE 'cerrada' END;
    v_resultado := CASE WHEN v_criticos > 0 THEN 'critico'
                        WHEN v_nocumple > 0 THEN 'con_desviaciones'
                        ELSE 'conforme' END;

    UPDATE prevencion_inspecciones SET
        estado = v_estado,
        resultado = v_resultado,
        pct_cumplimiento = CASE WHEN v_cumple + v_nocumple > 0
                                THEN round(100.0 * v_cumple / (v_cumple + v_nocumple), 1) END,
        items_cumple = v_cumple, items_no_cumple = v_nocumple,
        items_no_aplica = v_noaplica, items_pendientes = v_pend + v_pend_post,
        personas_no_habilitadas = v_nohab,
        cerrada_at = CASE WHEN v_estado = 'cerrada' THEN NOW() END
     WHERE id = v_id;

    RETURN jsonb_build_object(
        'id', v_id, 'estado', v_estado, 'resultado', v_resultado,
        'cumple', v_cumple, 'no_cumple', v_nocumple, 'no_aplica', v_noaplica,
        'pendientes', v_pend + v_pend_post, 'no_habilitados', v_nohab);
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_inspeccion_guardar(JSONB) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_inspeccion_guardar(JSONB) IS
    'Guarda la inspección APR completa (idempotente por cliente_uuid). La base calcula habilitación, fatiga, puntos automáticos, desviaciones y resultado. MIG685.';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT
    (SELECT count(*) FROM prevencion_inspeccion_plantilla)                 AS puntos,
    (SELECT count(*) FROM prevencion_requisitos WHERE grupo = 'CALAMA')    AS requisitos_calama,
    (SELECT count(*) FROM prevencion_inspeccion_faenas)                    AS faenas,
    (SELECT count(*) FROM prevencion_personal WHERE faena_codigo = 'CALAMA') AS personal_calama,
    (SELECT count(*) FROM prevencion_examen_tipos
      WHERE codigo IN ('curso_art_centinela','curso_emergencia_centinela','diploma_pillado')) AS tipos_nuevos;
