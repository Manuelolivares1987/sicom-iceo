-- ============================================================================
-- MIG556 · Prevención: la nómina es para los ASISTENTES de la actividad
-- ============================================================================
-- Corrección de Manuel (2026-09-14) sobre MIG555: «los asistentes son cuando
-- ejecutan una charla o actividad; para las HH, la subida a faena del
-- supervisor debe quedar tal cual» (cantidad simple).
--
--   · prevencion_registros.asistentes_nombres (jsonb): en faenas con nómina
--     (Calama), al registrar una charla/capacitación el supervisor MARCA
--     quiénes asistieron; el número `asistentes` se calcula de los marcados
--     (sigue alimentando las HH de capacitación del informe). Sin nómina,
--     el número se digita como siempre.
--   · La subida a faena vuelve al conteo simple en el formulario (el campo
--     dotacion_diaria.asistentes de MIG555 queda sin uso, se conserva por
--     compatibilidad de datos).
-- IDEMPOTENTE, ADITIVA.
-- ============================================================================

BEGIN;

ALTER TABLE prevencion_registros
    ADD COLUMN IF NOT EXISTS asistentes_nombres JSONB;

COMMENT ON COLUMN prevencion_registros.asistentes_nombres IS
    'Nombres marcados de la nómina que asistieron a la charla/actividad (["Arnold Ossandón",…]). NULL si se digitó solo la cantidad. MIG556.';

COMMENT ON COLUMN prevencion_dotacion_diaria.asistentes IS
    'SIN USO desde MIG556 (la subida volvió a conteo simple; la nómina se usa en los asistentes de actividades). Se conserva por compatibilidad.';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT column_name FROM information_schema.columns
WHERE table_name = 'prevencion_registros' AND column_name = 'asistentes_nombres';
