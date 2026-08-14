-- ============================================================================
-- SICOM-ICEO | 288 — Recorridos Gemba (Prevención · Jefe de Taller · Jefe de Ops)
-- ============================================================================
-- Digitaliza los recorridos de terreno con checklist por cargo, plan de acción
-- con responsable y plazo, y KPIs de cumplimiento. Taller y faenas.
--
-- Reemplaza al borrador `database/schema/58_recorridos_gemba.sql`, que quedó en
-- una carpeta que dejó de usarse hace ~230 migraciones y nunca se aplicó. Lo que
-- cambia respecto de ese borrador:
--
--   1. AUTORIZACIÓN REAL. El borrador dejaba INSERT/UPDATE en `USING (true)`
--      para cualquier autenticado: un operador podía cerrar hallazgos ajenos.
--      Ahora manda `fn_tiene_permiso_modulo('prevencion', ...)` — la misma
--      matriz configurable desde Admin (MIG126), así que agregar o quitar un
--      rol NO requiere otra migración.
--   2. EL RECORRIDO CERRADO ES INMUTABLE EN LA BD. Antes el bloqueo era solo
--      del frontend: por API se seguía editando un checklist ya cerrado. Para
--      un registro que es evidencia ante la mutual o una fiscalización, eso no
--      servía. El plan de acción SÍ sigue vivo después del cierre — las
--      acciones se cierran semanas después, ese es el punto.
--   3. PLANTILLA POR CARGO. El borrador etiquetaba los cargos con texto suelto
--      ('jefe_taller' no es un rol de este sistema: el jefe de taller es
--      `jefe_mantenimiento`). Se agrega `roles TEXT[]` para saber a quién se le
--      propone cada checklist, y así nadie llena el ajeno por descuido.
--   4. IDEMPOTENTE de verdad (el borrador reventaba en la segunda corrida:
--      CREATE TRIGGER y CREATE POLICY sin DROP previo).
--
-- ADITIVA. No toca datos de otros módulos.
-- ============================================================================


-- ── 0. Autorización del módulo ──────────────────────────────────────────────
-- Quién puede hacer recorridos y gestionar hallazgos. Los defaults son el punto
-- de partida; la última palabra la tiene la matriz de permisos de Admin
-- (/dashboard/admin/perfiles-roles → módulo "prevencion", acción "create").
--
-- Esta lista es EXACTAMENTE la misma que la del frontend (use-permissions.ts,
-- prevencion.create). Si se separan, aparece el peor de los errores: el botón
-- se ve, el usuario llena el recorrido y la base lo rechaza al guardar.
--
-- El rol `prevencionista` existe en el sistema pero hoy no lo tiene nadie
-- asignado: hay que asignárselo a quien haga prevención (Admin → usuarios).
CREATE OR REPLACE FUNCTION fn_gemba_puede_gestionar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('prevencion', 'create', ARRAY[
        'administrador','prevencionista','jefe_mantenimiento','jefe_operaciones'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_gemba_puede_gestionar() TO authenticated;

COMMENT ON FUNCTION fn_gemba_puede_gestionar() IS
    'Autorización de Recorridos Gemba: permiso create del módulo prevencion, con overrides de MIG126. MIG288.';


-- ############################################################################
-- 1. PLANTILLAS DE CHECKLIST
-- ############################################################################

CREATE TABLE IF NOT EXISTS gemba_plantillas (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(50)  UNIQUE NOT NULL,
    nombre      VARCHAR(200) NOT NULL,
    cargo       VARCHAR(100) NOT NULL,   -- etiqueta del cargo (texto, no es el rol)
    ambito      VARCHAR(20)  NOT NULL DEFAULT 'taller',  -- taller | faena | ambos
    descripcion TEXT,
    -- [{ "titulo": "1. EPP", "items": ["...", "..."] }, ...]
    secciones   JSONB        NOT NULL DEFAULT '[]',
    activo      BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_gemba_plantillas_ambito
        CHECK (ambito IN ('taller', 'faena', 'ambos'))
);

-- Roles del sistema a los que se les propone este checklist por defecto.
ALTER TABLE gemba_plantillas ADD COLUMN IF NOT EXISTS roles TEXT[] NOT NULL DEFAULT '{}';
COMMENT ON COLUMN gemba_plantillas.roles IS
    'Roles a los que se les preselecciona este checklist. Vacío = no se propone a nadie en particular. MIG288.';

CREATE INDEX IF NOT EXISTS idx_gemba_plantillas_activo ON gemba_plantillas (activo, cargo);

DROP TRIGGER IF EXISTS trg_gemba_plantillas_updated_at ON gemba_plantillas;
CREATE TRIGGER trg_gemba_plantillas_updated_at
    BEFORE UPDATE ON gemba_plantillas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 2. RECORRIDOS
-- ############################################################################

CREATE TABLE IF NOT EXISTS gemba_recorridos (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    plantilla_id    UUID        NOT NULL REFERENCES gemba_plantillas(id),
    fecha           DATE        NOT NULL DEFAULT CURRENT_DATE,
    hora_inicio     TIME,
    hora_termino    TIME,
    lugar_tipo      VARCHAR(20) NOT NULL DEFAULT 'taller',   -- taller | faena
    faena_id        UUID        REFERENCES faenas(id),        -- NULL si es taller
    sector          VARCHAR(200),
    responsable_id  UUID        REFERENCES usuarios_perfil(id),
    acompanantes    TEXT,
    foco            TEXT,
    observaciones   TEXT,
    estado          VARCHAR(20) NOT NULL DEFAULT 'en_curso',  -- en_curso | cerrado
    created_by      UUID        REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_gemba_recorridos_lugar
        CHECK (lugar_tipo IN ('taller', 'faena')),
    CONSTRAINT chk_gemba_recorridos_estado
        CHECK (estado IN ('en_curso', 'cerrado')),
    CONSTRAINT chk_gemba_recorridos_faena
        CHECK (lugar_tipo <> 'faena' OR faena_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_gemba_recorridos_fecha    ON gemba_recorridos (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_gemba_recorridos_estado   ON gemba_recorridos (estado);
CREATE INDEX IF NOT EXISTS idx_gemba_recorridos_faena_id ON gemba_recorridos (faena_id);
CREATE INDEX IF NOT EXISTS idx_gemba_recorridos_resp     ON gemba_recorridos (responsable_id, fecha DESC);

DROP TRIGGER IF EXISTS trg_gemba_recorridos_updated_at ON gemba_recorridos;
CREATE TRIGGER trg_gemba_recorridos_updated_at
    BEFORE UPDATE ON gemba_recorridos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 3. RESPUESTAS (ítems evaluados)
-- ############################################################################

CREATE TABLE IF NOT EXISTS gemba_respuestas (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    recorrido_id  UUID         NOT NULL REFERENCES gemba_recorridos(id) ON DELETE CASCADE,
    seccion       VARCHAR(300) NOT NULL,
    orden         INTEGER      NOT NULL,
    item          TEXT         NOT NULL,
    evaluacion    VARCHAR(20),             -- cumple | no_cumple | no_aplica | NULL
    observacion   TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_gemba_respuestas_eval
        CHECK (evaluacion IS NULL OR evaluacion IN ('cumple', 'no_cumple', 'no_aplica'))
);

CREATE INDEX IF NOT EXISTS idx_gemba_respuestas_recorrido ON gemba_respuestas (recorrido_id, orden);

DROP TRIGGER IF EXISTS trg_gemba_respuestas_updated_at ON gemba_respuestas;
CREATE TRIGGER trg_gemba_respuestas_updated_at
    BEFORE UPDATE ON gemba_respuestas
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 4. HALLAZGOS — PLAN DE ACCIÓN
-- ############################################################################

CREATE TABLE IF NOT EXISTS gemba_hallazgos (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    recorrido_id      UUID        NOT NULL REFERENCES gemba_recorridos(id) ON DELETE CASCADE,
    respuesta_id      UUID        REFERENCES gemba_respuestas(id) ON DELETE SET NULL,
    descripcion       TEXT        NOT NULL,
    accion_correctiva TEXT,
    responsable_id    UUID        REFERENCES usuarios_perfil(id),
    responsable_texto VARCHAR(200),
    fecha_compromiso  DATE,
    estado            VARCHAR(20) NOT NULL DEFAULT 'abierta',  -- abierta | en_proceso | cerrada
    fecha_cierre      DATE,
    created_by        UUID        REFERENCES auth.users(id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_gemba_hallazgos_estado
        CHECK (estado IN ('abierta', 'en_proceso', 'cerrada'))
);

CREATE INDEX IF NOT EXISTS idx_gemba_hallazgos_recorrido ON gemba_hallazgos (recorrido_id);
CREATE INDEX IF NOT EXISTS idx_gemba_hallazgos_estado    ON gemba_hallazgos (estado, fecha_compromiso);

DROP TRIGGER IF EXISTS trg_gemba_hallazgos_updated_at ON gemba_hallazgos;
CREATE TRIGGER trg_gemba_hallazgos_updated_at
    BEFORE UPDATE ON gemba_hallazgos
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ############################################################################
-- 5. RLS
-- ############################################################################

ALTER TABLE gemba_plantillas ENABLE ROW LEVEL SECURITY;
ALTER TABLE gemba_recorridos ENABLE ROW LEVEL SECURITY;
ALTER TABLE gemba_respuestas ENABLE ROW LEVEL SECURITY;
ALTER TABLE gemba_hallazgos  ENABLE ROW LEVEL SECURITY;

-- ── Lectura: cualquiera con rol. El recorrido es información de gestión, y que
--    se pueda mirar es parte de la transparencia que el método busca.
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['gemba_plantillas','gemba_recorridos','gemba_respuestas','gemba_hallazgos'] LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_sel_%s ON %I', t, t);
        EXECUTE format(
            'CREATE POLICY pol_sel_%s ON %I FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL)',
            t, t);
    END LOOP;
END $$;

-- ── Recorridos: los abre y ejecuta quien tiene el permiso del módulo.
DROP POLICY IF EXISTS pol_ins_gemba_recorridos ON gemba_recorridos;
CREATE POLICY pol_ins_gemba_recorridos ON gemba_recorridos
    FOR INSERT TO authenticated
    WITH CHECK (fn_gemba_puede_gestionar() AND estado = 'en_curso');

-- Un recorrido cerrado no se reabre ni se edita: es el registro de lo que se
-- vio ese día. Solo el administrador puede tocarlo (corregir un cierre por
-- error), y queda en updated_at.
DROP POLICY IF EXISTS pol_upd_gemba_recorridos ON gemba_recorridos;
CREATE POLICY pol_upd_gemba_recorridos ON gemba_recorridos
    FOR UPDATE TO authenticated
    USING (fn_gemba_puede_gestionar() AND (estado = 'en_curso' OR fn_user_rol() = 'administrador'))
    WITH CHECK (fn_gemba_puede_gestionar());

-- ── Respuestas: solo mientras el recorrido esté en curso.
DROP POLICY IF EXISTS pol_ins_gemba_respuestas ON gemba_respuestas;
CREATE POLICY pol_ins_gemba_respuestas ON gemba_respuestas
    FOR INSERT TO authenticated
    WITH CHECK (fn_gemba_puede_gestionar() AND EXISTS (
        SELECT 1 FROM gemba_recorridos r
         WHERE r.id = gemba_respuestas.recorrido_id AND r.estado = 'en_curso'));

DROP POLICY IF EXISTS pol_upd_gemba_respuestas ON gemba_respuestas;
CREATE POLICY pol_upd_gemba_respuestas ON gemba_respuestas
    FOR UPDATE TO authenticated
    USING (fn_gemba_puede_gestionar() AND EXISTS (
        SELECT 1 FROM gemba_recorridos r
         WHERE r.id = gemba_respuestas.recorrido_id AND r.estado = 'en_curso'))
    WITH CHECK (fn_gemba_puede_gestionar());

-- ── Hallazgos: el plan de acción SIGUE VIVO después de cerrar el recorrido.
--    Una acción se cierra semanas después; ese es justamente el punto del
--    método. Por eso acá no se mira el estado del recorrido.
DROP POLICY IF EXISTS pol_ins_gemba_hallazgos ON gemba_hallazgos;
CREATE POLICY pol_ins_gemba_hallazgos ON gemba_hallazgos
    FOR INSERT TO authenticated
    WITH CHECK (fn_gemba_puede_gestionar());

-- El responsable de una acción puede avanzarla aunque no gestione el módulo:
-- si no, tiene que pedirle a otro que marque lo que él ya hizo.
DROP POLICY IF EXISTS pol_upd_gemba_hallazgos ON gemba_hallazgos;
CREATE POLICY pol_upd_gemba_hallazgos ON gemba_hallazgos
    FOR UPDATE TO authenticated
    USING (fn_gemba_puede_gestionar() OR responsable_id = auth.uid())
    WITH CHECK (fn_gemba_puede_gestionar() OR responsable_id = auth.uid());

-- Sin policy de DELETE en ninguna tabla: un recorrido no se borra.
-- Las plantillas se administran por SQL (o se desactivan con activo = false).


-- ############################################################################
-- 6. VISTAS DE RESUMEN
-- ############################################################################

CREATE OR REPLACE VIEW vw_gemba_recorrido_resumen AS
SELECT
    r.id                                                       AS recorrido_id,
    COUNT(x.id)                                                AS total_items,
    COUNT(x.id) FILTER (WHERE x.evaluacion = 'cumple')         AS cumple,
    COUNT(x.id) FILTER (WHERE x.evaluacion = 'no_cumple')      AS no_cumple,
    COUNT(x.id) FILTER (WHERE x.evaluacion = 'no_aplica')      AS no_aplica,
    COUNT(x.id) FILTER (WHERE x.evaluacion IS NULL)            AS pendientes,
    CASE
        WHEN COUNT(x.id) FILTER (WHERE x.evaluacion IN ('cumple', 'no_cumple')) = 0 THEN NULL
        ELSE ROUND(
            100.0 * COUNT(x.id) FILTER (WHERE x.evaluacion = 'cumple')
                  / COUNT(x.id) FILTER (WHERE x.evaluacion IN ('cumple', 'no_cumple')), 1)
    END                                                        AS pct_cumplimiento
FROM gemba_recorridos r
LEFT JOIN gemba_respuestas x ON x.recorrido_id = r.id
GROUP BY r.id;
GRANT SELECT ON vw_gemba_recorrido_resumen TO authenticated;

CREATE OR REPLACE VIEW vw_gemba_kpi AS
SELECT
    (SELECT COUNT(*) FROM gemba_recorridos
      WHERE fecha >= date_trunc('month', CURRENT_DATE))                  AS recorridos_mes,
    (SELECT COUNT(*) FROM gemba_recorridos WHERE estado = 'en_curso')    AS recorridos_en_curso,
    (SELECT COUNT(*) FROM gemba_hallazgos WHERE estado <> 'cerrada')     AS hallazgos_abiertos,
    (SELECT COUNT(*) FROM gemba_hallazgos
      WHERE estado <> 'cerrada'
        AND fecha_compromiso IS NOT NULL
        AND fecha_compromiso < CURRENT_DATE)                             AS hallazgos_vencidos,
    -- Cumplimiento ponderado por ítem, no promedio de promedios: un recorrido
    -- de 4 ítems no puede pesar lo mismo que uno de 36.
    (SELECT CASE WHEN SUM(res.cumple + res.no_cumple) = 0 THEN NULL
                 ELSE ROUND(100.0 * SUM(res.cumple) / SUM(res.cumple + res.no_cumple), 1) END
       FROM vw_gemba_recorrido_resumen res
       JOIN gemba_recorridos rec ON rec.id = res.recorrido_id
      WHERE rec.fecha >= CURRENT_DATE - 90)                              AS pct_cumplimiento_90d;
GRANT SELECT ON vw_gemba_kpi TO authenticated;


-- ############################################################################
-- 7. SEEDS — PLANTILLAS POR CARGO
-- ############################################################################

-- ── 7.1 Prevención de Riesgos — inspección planificada del taller ──
INSERT INTO gemba_plantillas (codigo, nombre, cargo, ambito, roles, descripcion, secciones) VALUES
('GEMBA-PREV', 'Recorrido Gemba — Prevención de Riesgos (Taller)', 'prevencionista', 'taller',
 ARRAY['prevencionista'],
 'Checklist operativo completo del taller: EPP, 5S, máquinas, riesgo eléctrico, SUSPEL, emergencias, ergonomía y comportamientos.',
 '[
  {"titulo": "1. Elementos de Protección Personal (EPP)", "items": [
    "Los trabajadores usan casco y calzado de seguridad en las zonas donde se exige.",
    "Se usan lentes o protección facial en tareas de corte, esmerilado o proyección de partículas.",
    "Se usan guantes adecuados al tipo de tarea (mecánica, corte, químicos).",
    "Se usa protección auditiva en zonas o tareas con ruido elevado.",
    "Se usa protección respiratoria en tareas con polvo, humos de soldadura o vapores.",
    "Los EPP están en buen estado, limpios y dentro de su vida útil."
  ]},
  {"titulo": "2. Orden y Aseo (5S)", "items": [
    "Pasillos, vías de tránsito y salidas se encuentran despejados y demarcados.",
    "Herramientas y materiales están ordenados en sus lugares designados.",
    "No hay derrames de aceite, grasa o líquidos en el piso; se limpian de inmediato.",
    "Los residuos se segregan y depositan en contenedores identificados.",
    "Los materiales y repuestos están apilados de forma estable y a altura segura."
  ]},
  {"titulo": "3. Máquinas, Equipos y Herramientas", "items": [
    "Las máquinas cuentan con sus protecciones y resguardos instalados y operativos.",
    "Las paradas de emergencia están accesibles, señalizadas y funcionando.",
    "Las herramientas manuales y eléctricas están en buen estado.",
    "Los equipos cuentan con mantención al día (registro o etiqueta visible).",
    "No se dejan equipos energizados o en movimiento sin supervisión."
  ]},
  {"titulo": "4. Riesgo Eléctrico", "items": [
    "Tableros eléctricos cerrados, señalizados y libres de obstrucciones.",
    "Cables y enchufes sin deterioro; no hay conexiones improvisadas.",
    "Extensiones y alargadores usados de forma segura, sin sobrecarga.",
    "Se aplica bloqueo y etiquetado (LOTO) en intervención de equipos energizados."
  ]},
  {"titulo": "5. Sustancias Peligrosas", "items": [
    "Envases de químicos rotulados y en buen estado (sin trasvasije a botellas sin rótulo).",
    "Hojas de datos de seguridad (HDS) disponibles y conocidas por el personal.",
    "Sustancias inflamables almacenadas en zona autorizada, ventilada y señalizada.",
    "Se usan los EPP indicados en la HDS al manipular químicos."
  ]},
  {"titulo": "6. Preparación para Emergencias", "items": [
    "Extintores accesibles, señalizados, con carga vigente e inspección al día.",
    "Vías de evacuación y zonas de seguridad despejadas y señalizadas.",
    "Botiquín de primeros auxilios disponible y con insumos vigentes.",
    "El personal conoce el procedimiento de emergencia y los puntos de encuentro."
  ]},
  {"titulo": "7. Ergonomía y Entorno de Trabajo", "items": [
    "El manejo manual de carga se realiza con técnica correcta o con ayudas mecánicas.",
    "Los puestos de trabajo permiten posturas adecuadas (altura, alcance, apoyo).",
    "La iluminación de las zonas de trabajo es suficiente para la tarea.",
    "El nivel de ruido y ventilación del sector es adecuado o está controlado."
  ]},
  {"titulo": "8. Comportamientos y Procedimientos", "items": [
    "Los procedimientos de trabajo seguro están disponibles y se aplican en la tarea observada.",
    "Trabajos de alto riesgo (en caliente, altura, espacios confinados) cuentan con permiso vigente.",
    "Los trabajadores conocen los riesgos de su tarea y su capacitación está al día.",
    "No se observan actos inseguros (bromas, atajos, uso de celular en operación, etc.)."
  ]}
 ]'::jsonb)
ON CONFLICT (codigo) DO NOTHING;

-- ── 7.2 Jefe de Taller (rol del sistema: jefe_mantenimiento) ──
INSERT INTO gemba_plantillas (codigo, nombre, cargo, ambito, roles, descripcion, secciones) VALUES
('GEMBA-JT', 'Recorrido Gemba — Jefe de Taller', 'jefe_taller', 'taller',
 ARRAY['jefe_mantenimiento'],
 'Recorrido operativo semanal del Jefe de Taller: condiciones de terreno más gestión y liderazgo del sector.',
 '[
  {"titulo": "1. Elementos de Protección Personal (EPP)", "items": [
    "Los trabajadores usan casco, calzado de seguridad y lentes en las zonas donde se exige.",
    "Se usan guantes, protección auditiva y respiratoria según la tarea.",
    "Los EPP están en buen estado, limpios y dentro de su vida útil.",
    "El propio Jefe de Taller y las visitas usan su EPP completo durante el recorrido."
  ]},
  {"titulo": "2. Orden y Aseo (5S)", "items": [
    "Pasillos, vías de tránsito y salidas despejados y demarcados.",
    "Herramientas y materiales ordenados en sus lugares designados.",
    "Pisos sin derrames de aceite, grasa o líquidos; limpieza inmediata ante derrames.",
    "Residuos segregados en contenedores identificados.",
    "Materiales y repuestos apilados de forma estable y a altura segura."
  ]},
  {"titulo": "3. Máquinas, Equipos y Herramientas", "items": [
    "Máquinas con protecciones y resguardos instalados y operativos.",
    "Paradas de emergencia accesibles, señalizadas y funcionando.",
    "Herramientas manuales y eléctricas en buen estado.",
    "Equipos con mantención al día (registro o etiqueta visible).",
    "Se aplica bloqueo y etiquetado (LOTO) en intervención de equipos energizados."
  ]},
  {"titulo": "4. Riesgo Eléctrico, Sustancias y Emergencias", "items": [
    "Tableros eléctricos cerrados, señalizados y sin conexiones improvisadas.",
    "Químicos rotulados, con HDS disponible y almacenados en zona autorizada.",
    "Extintores accesibles, con carga vigente e inspección al día.",
    "Vías de evacuación y zonas de seguridad despejadas y señalizadas.",
    "Botiquín disponible y personal conoce el procedimiento de emergencia."
  ]},
  {"titulo": "5. Comportamientos y Procedimientos", "items": [
    "Las tareas observadas se ejecutan según el procedimiento de trabajo seguro.",
    "Trabajos de alto riesgo cuentan con permiso vigente.",
    "No se observan actos inseguros (atajos, bromas, uso de celular en operación).",
    "El manejo manual de carga se realiza con técnica correcta o ayudas mecánicas."
  ]},
  {"titulo": "6. Gestión del Sector (liderazgo del Jefe de Taller)", "items": [
    "La charla diaria de seguridad del sector se realizó y quedó registrada.",
    "Los análisis de riesgo de la tarea (ART/AST) están aplicados en los trabajos en curso.",
    "Las acciones correctivas de recorridos anteriores del sector están cerradas o en plazo.",
    "Se conversó con al menos 2 trabajadores sobre los riesgos de su tarea.",
    "Se reconoció en el momento al menos una conducta o práctica segura observada."
  ]}
 ]'::jsonb)
ON CONFLICT (codigo) DO NOTHING;

-- ── 7.3 Jefe de Operaciones (taller + faenas) ──
INSERT INTO gemba_plantillas (codigo, nombre, cargo, ambito, roles, descripcion, secciones) VALUES
('GEMBA-JOP', 'Recorrido Gemba — Jefe de Operaciones (Taller y Faenas)', 'jefe_operaciones', 'ambos',
 ARRAY['jefe_operaciones'],
 'Recorrido de gestión y liderazgo preventivo: verificación del sistema, muestreo de condiciones y voz de los trabajadores. La sección de faena se marca No Aplica cuando el recorrido es en taller.',
 '[
  {"titulo": "1. Liderazgo Visible y Cultura Preventiva", "items": [
    "Se conversó directamente con trabajadores (no solo con jefaturas) durante el recorrido.",
    "Los trabajadores consultados conocen los riesgos de su tarea y sus medidas de control.",
    "Los trabajadores señalan que sus reportes de peligro tienen respuesta y seguimiento.",
    "Se reconocieron públicamente avances o buenas prácticas del equipo.",
    "Las jefaturas predican con el ejemplo (EPP, respeto a estándares)."
  ]},
  {"titulo": "2. Funcionamiento del Sistema de Recorridos", "items": [
    "Los recorridos Gemba del Jefe de Taller se realizan con la frecuencia definida y están registrados.",
    "Los recorridos del prevencionista están al día y con hallazgos documentados.",
    "Los checklists completados se archivan y se analizan tendencias de cumplimiento.",
    "Los hallazgos No Cumple se traspasan efectivamente a planes de acción."
  ]},
  {"titulo": "3. Gestión de Hallazgos y Planes de Acción", "items": [
    "Las acciones correctivas se cierran dentro del plazo comprometido.",
    "Se verificaron en terreno 2 o 3 acciones cerradas y la solución existe y funciona.",
    "Las acciones detenidas por falta de recursos están identificadas y escaladas.",
    "Los incidentes del período cuentan con investigación y medidas implementadas."
  ]},
  {"titulo": "4. Cumplimiento del Programa Preventivo", "items": [
    "El programa de capacitación del personal está al día.",
    "El Comité Paritario sesiona según programa y sus acuerdos se gestionan.",
    "Las mantenciones preventivas de equipos críticos están al día.",
    "Los simulacros de emergencia del período se realizaron según programa.",
    "Los indicadores preventivos del mes están disponibles y se analizan."
  ]},
  {"titulo": "5. Muestreo de Condiciones en Terreno (taller o faena)", "items": [
    "Muestreo general: uso de EPP correcto en los sectores recorridos.",
    "Muestreo general: orden y aseo (5S) del lugar en estándar aceptable.",
    "Muestreo general: extintores, vías de evacuación y señalización operativos.",
    "Muestreo general: no se observan condiciones de peligro grave e inminente."
  ]},
  {"titulo": "6. Condiciones Específicas en Faena (No Aplica si es taller)", "items": [
    "La charla de inicio de jornada y el análisis de riesgo (ART/AST) están realizados y registrados en la faena.",
    "El equipo cumple los requisitos del mandante (reglamento, acreditaciones, EPP exigidos, permisos del cliente).",
    "Vehículos y equipos de la faena en buen estado, con revisiones al día y operadores habilitados.",
    "El personal conoce el plan de emergencia del lugar (puntos de encuentro, comunicación con el mandante).",
    "Herramientas, materiales y zona de trabajo en faena ordenados, demarcados y sin exposición a terceros.",
    "La coordinación con el supervisor de la faena y el mandante es fluida."
  ]},
  {"titulo": "7. Voz de los Trabajadores", "items": [
    "Se preguntó a los trabajadores qué necesitan para trabajar más seguros.",
    "Las necesidades levantadas quedaron registradas con compromiso de respuesta.",
    "Existen canales conocidos y usados para reportar peligros y sugerencias."
  ]}
 ]'::jsonb)
ON CONFLICT (codigo) DO NOTHING;

-- El mapeo checklist→rol se re-afirma en cada corrida: es el dato que decide
-- qué se le propone a cada quien y tiene que poder corregirse re-aplicando.
UPDATE gemba_plantillas SET roles = ARRAY['prevencionista']
 WHERE codigo = 'GEMBA-PREV' AND roles IS DISTINCT FROM ARRAY['prevencionista'];
UPDATE gemba_plantillas SET roles = ARRAY['jefe_mantenimiento']
 WHERE codigo = 'GEMBA-JT' AND roles IS DISTINCT FROM ARRAY['jefe_mantenimiento'];
UPDATE gemba_plantillas SET roles = ARRAY['jefe_operaciones']
 WHERE codigo = 'GEMBA-JOP' AND roles IS DISTINCT FROM ARRAY['jefe_operaciones'];

NOTIFY pgrst, 'reload schema';


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_pol INT; v_pla INT; v_abiertas INT;
BEGIN
    SELECT count(*) INTO v_pol FROM pg_policies
     WHERE tablename LIKE 'gemba_%';
    -- Ninguna policy de escritura puede haber quedado en "true" pelado.
    SELECT count(*) INTO v_abiertas FROM pg_policies
     WHERE tablename LIKE 'gemba_%' AND cmd IN ('INSERT','UPDATE')
       AND COALESCE(with_check, qual, 'true') = 'true';
    SELECT count(*) INTO v_pla FROM gemba_plantillas WHERE activo;

    IF v_abiertas > 0 THEN
        RAISE EXCEPTION 'FALLO — quedaron % policies de escritura abiertas', v_abiertas;
    END IF;
    RAISE NOTICE 'MIG288 OK — % policies, % plantillas activas, escritura cerrada por permiso del módulo prevencion',
                 v_pol, v_pla;
END $$;
