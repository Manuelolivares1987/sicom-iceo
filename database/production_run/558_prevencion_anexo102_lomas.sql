-- ============================================================================
-- MIG558 · Prevención: Anexo 10.2 Lomas con su estructura de secciones
-- ============================================================================
-- Manuel (2026-09-14): «necesito respetar la estructura de las secciones, esa
-- es la guía; con los datos que tenemos se adjunta y el resto va constante.
-- El supervisor usa fotos y PDF que deben quedar dentro de la PPT.»
--
-- La guía es el PPT real («Respaldos anexo 10.2 Lubricante ARNOL.pptx», 38
-- láminas): 7 secciones y 28 subsecciones numeradas. El mecanismo:
--
--   · Tipo ANEXO102 con titulos_opciones = las 28 subsecciones (mismo
--     mecanismo del PGR): el supervisor registra la actividad eligiendo la
--     subsección y adjunta sus fotos/PDF.
--   · El generador (plantilla 'anexo_102') arma el PPT con la estructura
--     EXACTA: portada, una lámina por subsección con su título; si hay
--     registros del mes en esa subsección van sus evidencias (los PDF se
--     rasterizan e incrustan); si no hay, va el texto constante del formato
--     («No aplica… dotación inferior a 25 trabajadores», etc.).
-- IDEMPOTENTE.
-- ============================================================================

BEGIN;

INSERT INTO prevencion_actividad_tipos (codigo, nombre, descripcion, requiere_cierre, orden, titulos_opciones)
VALUES (
    'ANEXO102', 'Anexo 10.2',
    'Evidencia para el Reporte de Cumplimiento Anexo 10.2 (Lomas Bayas): elija la subsección de la guía y adjunte fotos o PDF — quedan dentro de la lámina correspondiente.',
    false, 95,
    '[
      "1.1.- Cumplimiento mensual programa de liderazgo",
      "1.2.- Se evidencia actividades de liderazgo en terreno por roles",
      "1.3.- Cumplimiento de programa de reconocimiento al personal destacado en seguridad",
      "1.4.- Cumplimiento programa de reforzamiento Conductas que salvan vidas/aplicación de procedimiento de gestión por consecuencia",
      "1.5.- Asistencia a las reuniones mensuales del administrador de contrato de la ESE",
      "1.6.- Asistencia a las reuniones semanales del Asesor HS de la ESE",
      "2.1.- Cumplimiento y actualización QRA (controles críticos, aprendizajes y eventos)",
      "2.2.- Programa de difusión de los riesgos y sus controles y cartillas de controles críticos",
      "2.3.- Matriz legal actualizada (evidencia referencial del documento)",
      "2.4.- Reglamento interno de orden y seguridad",
      "3.1.- Registro completado y aprobado, Anexo 6 LB-RG-SHS-ALL-0013 (acreditación Competencias HS por Rol)",
      "3.2.- Capacitaciones ingresadas a plataforma webcontrol verificables por código QR",
      "3.3.- Cumplimiento de programa de capacitaciones según Anexo 6 LB-RG-SHS-ALL-0013",
      "4.1.- Aspectos y evaluación de riesgos de higiene y salud ocupacional (QRA / Matriz SO)",
      "4.2.- Autoevaluación diagnóstica de protocolos MINSAL y plan de cierre de brechas",
      "4.3.- Proceso de gestión de casos relacionados con alcohol y drogas",
      "4.4.- Plan para gestión de casos contraindicados o con observaciones (exámenes pre y ocupacionales)",
      "4.5.- Programa de higiene y salud ocupacional",
      "5.1.- Acta de constitución CPHS",
      "5.2.- Registro de reuniones mensuales CPHS",
      "5.3.- Cumplimiento de acuerdos de actas CPHS",
      "5.4.- Registro de asistencias a reuniones CPHS de faena",
      "5.5.- Registro de entrega E-200 / HH",
      "5.6.- Registro de estadísticas de siniestralidad OAL",
      "5.7.- Cumplimiento de herramientas preventivas SAFEWORK (GCOM, ART, permisos de trabajo, etc.)",
      "6.1.- Incidentes con lesión y/o cuasi accidentes de alto potencial y/o daño material y/o HPRI",
      "6.2.- Si ocurrieron incidentes: entrega a tiempo de toda la información",
      "6.3.- Difusión de accidentes CAP, boletines de seguridad y aprendizajes Glencore",
      "7.1.- Cumplimiento de programa de auditorías (propias de la empresa)",
      "7.2.- Autoevaluación del desempeño SAFEWORK",
      "7.3.- Seguimiento y verificación de planes de acción (auditorías, inspecciones, incidentes, otros)"
    ]'::jsonb
)
ON CONFLICT (codigo) DO UPDATE
   SET titulos_opciones = EXCLUDED.titulos_opciones, activo = true;

-- Disponible en las dos Lomas
INSERT INTO prevencion_faena_tipos (faena_id, tipo_codigo)
SELECT f.id, 'ANEXO102' FROM faenas f
 WHERE f.codigo IN ('FAE-LOMASBAYAS', 'FAE-LOMASBAYAS-LUB')
ON CONFLICT DO NOTHING;

-- Plantilla nueva para el ítem del Anexo
ALTER TABLE prevencion_reportabilidad_items
    DROP CONSTRAINT IF EXISTS prevencion_reportabilidad_items_plantilla_check;
ALTER TABLE prevencion_reportabilidad_items
    ADD CONSTRAINT prevencion_reportabilidad_items_plantilla_check
    CHECK (plantilla IS NULL OR plantilla IN
        ('e200','grp_cmp','informe_franke','ppt_evidencias',
         'estadistica_esm','franke_insumos','franke_residuos','anexo_102'));

UPDATE prevencion_reportabilidad_items
   SET plantilla = 'anexo_102'
 WHERE nombre = 'PPT Lubricantes y Combustible — Anexo 10.2';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT (SELECT jsonb_array_length(titulos_opciones) FROM prevencion_actividad_tipos WHERE codigo='ANEXO102') AS subsecciones,
       (SELECT COUNT(*) FROM prevencion_faena_tipos WHERE tipo_codigo='ANEXO102') AS faenas_con_anexo,
       (SELECT COUNT(*) FROM prevencion_reportabilidad_items WHERE plantilla='anexo_102') AS items_anexo;
