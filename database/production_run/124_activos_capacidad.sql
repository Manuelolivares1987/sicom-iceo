-- ============================================================================
-- 124_activos_capacidad.sql
-- ----------------------------------------------------------------------------
-- Agrega la columna 'capacidad' a activos para la ficha técnica del equipo
-- (planilla "Data Equipo"): ej. "20.000 L 6x4 Agua", "10.000 kg 6x4".
-- El resto de campos de la ficha (potencia, vin_chasis, numero_motor,
-- anio_fabricacion) ya existen. Se pueblan desde la planilla con el script
-- database/scripts/cargar-ficha-equipos.mjs.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE activos ADD COLUMN IF NOT EXISTS capacidad VARCHAR(60);

COMMENT ON COLUMN activos.capacidad IS
    'Capacidad/configuración del equipo (planilla Data Equipo). Ej: "20.000 L 6x4 Agua". MIG124.';

NOTIFY pgrst, 'reload schema';
