-- ============================================================================
-- SICOM-ICEO | 290 — Cadencia: taller diario, operaciones quincenal
-- ============================================================================
-- El Jefe de Taller recorre TODOS LOS DÍAS y el Jefe de Operaciones cada dos
-- semanas. Un checklist de 28 ítems no se hace a diario: se hace la primera
-- semana, después se marca todo "cumple" sin mirar, y a los dos meses nadie lo
-- abre. El recorrido diario tiene que durar 10-15 minutos o no existe.
--
-- Solución: el checklist del Jefe de Taller se parte en dos.
--   · NÚCLEO FIJO (7 ítems) — lo que hay que mirar todos los días: si el plan
--     se está ejecutando, qué está frenado, qué sale hoy al cliente, y qué le
--     impide avanzar a un técnico.
--   · BLOQUE DEL DÍA (4-5 ítems) — rota de lunes a viernes. Cada día se mira a
--     fondo una cosa distinta; en la semana se cubre todo el taller.
--
-- Resultado: 11-12 ítems por día, cobertura semanal completa de 29 ítems.
--
-- Las secciones rotativas se marcan con "dia" (1 = lunes … 5 = viernes) dentro
-- del propio JSONB. Las que no lo llevan son fijas. Al iniciar el recorrido, la
-- app pre-carga las fijas + la del día de la fecha; si es fin de semana y no hay
-- bloque, quedan solo las fijas.
--
-- El Jefe de Operaciones mantiene sus 23 ítems: cada dos semanas sí se pueden
-- mirar todos, y su recorrido es de revisión del sistema, no de ronda.
--
-- ADITIVA e IDEMPOTENTE.
-- ============================================================================

-- ── 1. Cadencia esperada de cada checklist ──────────────────────────────────
ALTER TABLE gemba_plantillas ADD COLUMN IF NOT EXISTS cadencia TEXT;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_gemba_plantillas_cadencia') THEN
        ALTER TABLE gemba_plantillas ADD CONSTRAINT chk_gemba_plantillas_cadencia
            CHECK (cadencia IS NULL OR cadencia IN ('diaria','semanal','quincenal','mensual'));
    END IF;
END $$;

COMMENT ON COLUMN gemba_plantillas.cadencia IS
    'Con qué frecuencia se espera este recorrido. Base para el programa y los recordatorios. MIG290.';

COMMENT ON COLUMN gemba_plantillas.secciones IS
    'Secciones del checklist. Una sección con "dia" (1=lunes..5=viernes) solo se carga ese día del la semana; sin "dia" es fija y va todos los recorridos. MIG290.';


-- ── 2. Jefe de Taller — diario: núcleo fijo + bloque rotativo ───────────────
UPDATE gemba_plantillas SET
  cadencia = 'diaria',
  nombre = 'Recorrido Gemba diario — Jefe de Taller (Operación y Calidad)',
  descripcion = 'Recorrido diario de 10-15 minutos: un núcleo fijo de 7 ítems (flujo, frenos y lo que sale hoy al cliente) más el bloque del día, que rota de lunes a viernes. En la semana se cubre el taller completo.',
  secciones = '[
  {"titulo": "Todos los días · Flujo del trabajo de hoy", "items": [
    "El plan de hoy está publicado y cada técnico sabe en qué OT parte.",
    "Las OT marcadas en ejecución coinciden con lo que se está haciendo en los boxes.",
    "Los equipos detenidos esperando repuesto están identificados y con su vale de bodega emitido.",
    "Ningún vale pendiente de despacho lleva más de 24 h sin escalar.",
    "Ningún equipo está estacionado en el taller sin OT abierta ni fecha de salida comprometida.",
    "Se le preguntó a un técnico qué le impide avanzar y quedó registrado.",
    "No se observó ninguna condición o acto de riesgo evidente; si lo hubo, se detuvo en el momento."
  ]},
  {"titulo": "Lunes · Plan y carga de la semana", "dia": 1, "items": [
    "El plan semanal del taller está publicado y cada técnico conoce sus OT de la semana.",
    "Las OT atrasadas de la semana anterior tienen causa registrada y nueva fecha.",
    "Las preventivas programadas para esta semana tienen sus repuestos asegurados.",
    "No hay técnicos sin carga asignada ni OT en curso sin responsable.",
    "La cantidad de equipos abiertos a la vez es la que el taller puede terminar esta semana."
  ]},
  {"titulo": "Martes · Calidad de lo ejecutado", "dia": 2, "items": [
    "Las OT cerradas desde el último recorrido tienen su pauta completa, no solo marcadas como finalizadas.",
    "Las tareas ejecutadas tienen evidencia fotográfica del antes y el después.",
    "Los hallazgos detectados quedaron registrados como no conformidad, no resueltos de palabra.",
    "Los aprietes, presiones y niveles críticos se verificaron con instrumento, no a criterio."
  ]},
  {"titulo": "Miércoles · El equipo que sale al cliente", "dia": 3, "items": [
    "Los equipos por entregar esta semana tienen su documentación vigente (revisión técnica, permiso de circulación, certificados).",
    "Los equipos listos salen limpios, sin fugas visibles y con horómetro y combustible registrados.",
    "Los certificados e informes de salida que correspondan están emitidos y firmados.",
    "Ningún equipo volvió al taller por la misma falla (retrabajo).",
    "Los equipos devueltos por el cliente tienen su recepción y checklist hechos el mismo día."
  ]},
  {"titulo": "Jueves · El taller como herramienta de trabajo", "dia": 4, "items": [
    "Cada herramienta tiene un lugar y está en su lugar: se ve de un vistazo lo que falta.",
    "Los repuestos recibidos están identificados con su OT, no sueltos en un rincón.",
    "Las zonas están demarcadas y el estado de cada equipo se entiende sin preguntar.",
    "Los residuos, aceites y filtros usados están segregados y no acumulados."
  ]},
  {"titulo": "Viernes · Personas, estándar y cierre de semana", "dia": 5, "items": [
    "Los técnicos tienen la pauta del trabajo a mano y la siguen.",
    "El personal está habilitado para el equipo que está interviniendo.",
    "Si alguien encontró una mejor forma de hacer la tarea, quedó registrada para todos.",
    "Se reconoció en el momento al menos un trabajo bien hecho.",
    "Los hallazgos de los recorridos de esta semana están cerrados o dentro de plazo."
  ]}
 ]'::jsonb
WHERE codigo = 'GEMBA-JT';


-- ── 3. Jefe de Operaciones — quincenal ──────────────────────────────────────
UPDATE gemba_plantillas SET
  cadencia = 'quincenal',
  nombre = 'Recorrido Gemba quincenal — Jefe de Operaciones (Sistema y Cliente)',
  descripcion = 'Recorrido cada dos semanas: cumplimiento del compromiso con el cliente, calidad de lo que sale del taller, funcionamiento del sistema y obstáculos del equipo. Taller y faenas — la última sección solo aplica en faena.'
WHERE codigo = 'GEMBA-JOP';


-- ── 4. Prevención — según su programa ───────────────────────────────────────
UPDATE gemba_plantillas SET cadencia = 'semanal' WHERE codigo = 'GEMBA-PREV' AND cadencia IS NULL;

NOTIFY pgrst, 'reload schema';


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE r RECORD; v_dia INT; v_items INT; v_fijos INT;
BEGIN
    SELECT sum(jsonb_array_length(s->'items')) INTO v_fijos
      FROM gemba_plantillas p, jsonb_array_elements(p.secciones) s
     WHERE p.codigo = 'GEMBA-JT' AND s->'dia' IS NULL;

    FOR v_dia IN 1..5 LOOP
        SELECT COALESCE(sum(jsonb_array_length(s->'items')), 0) INTO v_items
          FROM gemba_plantillas p, jsonb_array_elements(p.secciones) s
         WHERE p.codigo = 'GEMBA-JT' AND (s->>'dia')::int = v_dia;
        IF v_items = 0 THEN
            RAISE EXCEPTION 'FALLO — el día % quedó sin bloque rotativo', v_dia;
        END IF;
        RAISE NOTICE 'MIG290 — día %: % fijos + % del día = % ítems', v_dia, v_fijos, v_items, v_fijos + v_items;
    END LOOP;

    FOR r IN SELECT codigo, cadencia FROM gemba_plantillas ORDER BY codigo LOOP
        RAISE NOTICE 'MIG290 — % → cadencia %', r.codigo, r.cadencia;
    END LOOP;
END $$;
