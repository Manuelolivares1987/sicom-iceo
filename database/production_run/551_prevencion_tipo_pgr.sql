-- ============================================================================
-- MIG551 · Prevención: tipo PGR con títulos seleccionables
-- ============================================================================
-- Manuel (2026-09-14): «agrega PGR como tipo de actividad, con el título
-- seleccionable entre: H1: ARTP · H2: Cambio turno Seguro (CtS) ·
-- H3: Confirmación de Rol a CtS · H3: Confirmación de Rol a CdP ·
-- H4: Confirmación de Procesos (CdP) · Programa Trabajo Preventivo».
--
-- Mecanismo GENÉRICO: prevencion_actividad_tipos.titulos_opciones (jsonb
-- array). Si un tipo trae opciones, el formulario muestra un selector en vez
-- de texto libre — sirve para PGR hoy y para cualquier catálogo de otro
-- mandante mañana, sin tocar código. Los tipos existentes quedan NULL =
-- título libre, como siempre.
-- IDEMPOTENTE.
-- ============================================================================

BEGIN;

ALTER TABLE prevencion_actividad_tipos
    ADD COLUMN IF NOT EXISTS titulos_opciones JSONB;

COMMENT ON COLUMN prevencion_actividad_tipos.titulos_opciones IS
    'Array de títulos permitidos para el tipo (["H1: ARTP", ...]). NULL = título libre. El formulario los muestra como selector. MIG551.';

INSERT INTO prevencion_actividad_tipos (codigo, nombre, descripcion, requiere_cierre, orden, titulos_opciones)
VALUES (
    'PGR', 'PGR',
    'Herramientas preventivas PGR (Centinela): el título se elige del catálogo del mandante.',
    false, 35,
    '["H1: ARTP",
      "H2: Cambio turno Seguro (CtS)",
      "H3: Confirmación de Rol a CtS",
      "H3: Confirmación de Rol a CdP",
      "H4: Confirmación de Procesos (CdP)",
      "Programa Trabajo Preventivo"]'::jsonb
)
ON CONFLICT (codigo) DO UPDATE
   SET titulos_opciones = EXCLUDED.titulos_opciones,
       activo = true;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT codigo, nombre, orden, jsonb_array_length(titulos_opciones) AS titulos
FROM prevencion_actividad_tipos WHERE codigo = 'PGR';
