-- ============================================================================
-- SICOM-ICEO | 289 — El recorrido de los jefes es de OPERACIONES, no de seguridad
-- ============================================================================
-- Las plantillas GEMBA-JT y GEMBA-JOP que sembró MIG288 eran, en el fondo, una
-- copia recortada del checklist del prevencionista: EPP, 5S, extintores. Con eso
-- los tres cargos recorrían buscando lo mismo, el jefe duplicaba el trabajo del
-- prevencionista y nadie miraba lo que solo un jefe de operaciones puede mirar.
--
-- Reparto correcto:
--   · Prevención (GEMBA-PREV) → SEGURIDAD. Queda intacta.
--   · Jefe de Taller (GEMBA-JT) → OPERACIÓN Y CALIDAD DEL EQUIPO: que el plan se
--     cumpla, que nada esté frenado, que lo ejecutado tenga pauta y evidencia, y
--     que lo que sale al cliente esté impecable.
--   · Jefe de Operaciones (GEMBA-JOP) → EL SISTEMA: que el compromiso con el
--     cliente se cumpla, que la calidad de lo entregado se sostenga y que los
--     obstáculos del equipo tengan respuesta.
--
-- Los ítems están escritos contra cosas que el sistema YA sabe (plan taller, OT,
-- pauta, vale de bodega, NC, checklist de entrega, certificado, informe de
-- salida): el recorrido se puede contrastar con el dato, no queda en impresión.
--
-- La seguridad no desaparece del recorrido del jefe — queda un ítem de "no se
-- tolera el riesgo evidente". Lo que no hace el jefe es la inspección completa:
-- esa es del prevencionista.
--
-- ADITIVA e IDEMPOTENTE. Reemplaza el contenido de dos plantillas; verificado
-- que no hay recorridos ejecutados (los recorridos congelan sus ítems al
-- iniciar, así que cambiar la plantilla nunca altera un recorrido pasado).
-- ============================================================================

-- ── 1. Jefe de Taller — operación y calidad del equipo ──────────────────────
UPDATE gemba_plantillas SET
  nombre = 'Recorrido Gemba — Jefe de Taller (Operación y Calidad)',
  descripcion = 'Recorrido operativo del Jefe de Taller: cumplimiento del plan, qué está frenando el trabajo, calidad de lo ejecutado y estándar del equipo que sale al cliente. La inspección de seguridad la hace prevención.',
  secciones = '[
  {"titulo": "1. El plan se está cumpliendo", "items": [
    "El plan semanal del taller está publicado y cada técnico sabe qué OT le toca hoy.",
    "Las OT marcadas en ejecución coinciden con lo que se está haciendo en los boxes.",
    "Las OT atrasadas respecto del plan tienen causa registrada, no solo fecha corrida.",
    "No hay técnicos sin trabajo asignado ni trabajos en curso sin responsable."
  ]},
  {"titulo": "2. Qué está frenando el trabajo", "items": [
    "Los equipos detenidos esperando repuesto están identificados y con su vale de bodega emitido.",
    "Los vales pendientes de despacho llevan menos de 24 h; los que llevan más están escalados.",
    "No hay equipos estacionados en el taller sin OT abierta ni fecha de salida comprometida.",
    "Se preguntó a un técnico qué le impide avanzar y quedó registrado como hallazgo.",
    "La cantidad de equipos abiertos a la vez es la que el taller puede terminar."
  ]},
  {"titulo": "3. Calidad de lo ejecutado", "items": [
    "Las OT cerradas del período tienen su pauta completa, no solo marcadas como finalizadas.",
    "Las tareas ejecutadas tienen evidencia fotográfica del antes y el después.",
    "Los hallazgos detectados se registraron como no conformidad, no se resolvieron de palabra.",
    "Ningún equipo volvió al taller por la misma falla dentro del período (retrabajo).",
    "Los apriete, presiones y niveles críticos se verificaron con instrumento, no a criterio."
  ]},
  {"titulo": "4. El equipo sale impecable al cliente", "items": [
    "Los equipos por entregar no tienen no conformidades abiertas.",
    "El checklist de entrega está completo, con fotos y firma.",
    "La documentación del equipo está vigente (revisión técnica, permiso de circulación, certificados).",
    "El equipo sale limpio, sin fugas visibles y con horómetro y combustible registrados.",
    "Los certificados o informes de salida que correspondan están emitidos y firmados."
  ]},
  {"titulo": "5. El taller como herramienta de trabajo", "items": [
    "Cada herramienta tiene un lugar y está en su lugar: se ve de un vistazo lo que falta.",
    "Los repuestos recibidos están identificados con su OT, no sueltos en un rincón.",
    "Las zonas están demarcadas y el estado de cada equipo se entiende sin preguntar.",
    "Los residuos, aceites y filtros usados están segregados y no acumulados.",
    "No se observó ninguna condición o acto de riesgo evidente; si lo hubo, se detuvo en el momento."
  ]},
  {"titulo": "6. Personas y estándar", "items": [
    "Los técnicos tienen la pauta del trabajo a mano y la siguen.",
    "El personal está habilitado para el equipo que está interviniendo.",
    "Si alguien encontró una mejor forma de hacer la tarea, quedó registrada para todos.",
    "Se reconoció en el momento al menos un trabajo bien hecho."
  ]}
 ]'::jsonb
WHERE codigo = 'GEMBA-JT';


-- ── 2. Jefe de Operaciones — el sistema entrega calidad y cumple ────────────
UPDATE gemba_plantillas SET
  nombre = 'Recorrido Gemba — Jefe de Operaciones (Sistema y Cliente)',
  descripcion = 'Recorrido de gestión del Jefe de Operaciones: cumplimiento del compromiso con el cliente, calidad de lo que sale del taller, funcionamiento del sistema y obstáculos del equipo. Taller y faenas — la última sección solo aplica en faena.',
  secciones = '[
  {"titulo": "1. El compromiso con el cliente se cumple", "items": [
    "Los equipos comprometidos para entrega o arriendo del período están listos o con fecha firme.",
    "Los servicios comprometidos con el mandante están ejecutados y firmados por quien recibe.",
    "Los equipos en faena están operativos; los detenidos tienen causa conocida y plan de salida.",
    "Los reclamos o reportes del cliente del período tienen respuesta y cierre."
  ]},
  {"titulo": "2. Calidad de lo que sale del taller", "items": [
    "Se revisaron en terreno 2 o 3 equipos entregados y cumplen el estándar (sin fugas, sin NC, documentación vigente).",
    "Los equipos entregados en el período no tuvieron devoluciones ni fallas tempranas.",
    "Los certificados e informes de salida del período están emitidos y firmados.",
    "Las auditorías de calidad del período se realizaron y sus hallazgos están cerrados o en plazo."
  ]},
  {"titulo": "3. El taller funciona como sistema", "items": [
    "El plan semanal se cumple; las desviaciones tienen causa registrada.",
    "Las mantenciones preventivas vencidas están bajo control y no crecen mes a mes.",
    "Las no conformidades abiertas están dentro de plazo y las vencidas están escaladas.",
    "Los repuestos no están frenando trabajos: vales pendientes y quiebres de stock bajo control.",
    "Los recorridos del Jefe de Taller se realizan con la frecuencia definida y sus hallazgos se cierran."
  ]},
  {"titulo": "4. Personas y obstáculos", "items": [
    "Se conversó directamente con técnicos y operadores, no solo con jefaturas.",
    "Se preguntó qué les impide hacer bien su trabajo y quedó registrado con compromiso de respuesta.",
    "Los obstáculos levantados en recorridos anteriores tuvieron respuesta concreta.",
    "El equipo está habilitado y acreditado para lo que opera.",
    "Se reconocieron avances o buenas prácticas del equipo."
  ]},
  {"titulo": "5. En faena (No Aplica si el recorrido es en taller)", "items": [
    "La instalación y los equipos cumplen el estándar exigido por el mandante (acreditaciones, permisos, requisitos del contrato).",
    "El trabajo realizado en faena queda registrado con su evidencia en el sistema el mismo día.",
    "Los equipos en faena tienen documentación y mantención al día.",
    "La coordinación con el supervisor del mandante es fluida y sin temas pendientes.",
    "El personal en faena conoce el plan de emergencia del lugar y los puntos de encuentro."
  ]}
 ]'::jsonb
WHERE codigo = 'GEMBA-JOP';


-- El cargo del JT deja de llamarse por un rol que no existe.
UPDATE gemba_plantillas SET cargo = 'jefe_taller' WHERE codigo = 'GEMBA-JT' AND cargo <> 'jefe_taller';

NOTIFY pgrst, 'reload schema';


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE r RECORD; v_seg INT;
BEGIN
    FOR r IN SELECT codigo,
                    jsonb_array_length(secciones) AS secs,
                    (SELECT sum(jsonb_array_length(s->'items')) FROM jsonb_array_elements(secciones) s) AS items
               FROM gemba_plantillas WHERE codigo IN ('GEMBA-JT','GEMBA-JOP') ORDER BY codigo LOOP
        RAISE NOTICE 'MIG289 — % : % secciones, % ítems', r.codigo, r.secs, r.items;
    END LOOP;

    -- Los checklists de los jefes ya no pueden ser una copia del de seguridad.
    SELECT count(*) INTO v_seg FROM gemba_plantillas
     WHERE codigo IN ('GEMBA-JT','GEMBA-JOP')
       AND secciones::text ILIKE '%extintor%';
    IF v_seg > 0 THEN
        RAISE EXCEPTION 'FALLO — el recorrido de los jefes quedó orientado a seguridad';
    END IF;
    RAISE NOTICE 'MIG289 OK — jefes orientados a operación y calidad; prevención conserva seguridad';
END $$;
