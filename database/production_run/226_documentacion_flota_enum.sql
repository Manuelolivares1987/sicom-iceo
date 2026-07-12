-- ============================================================================
-- SICOM-ICEO | 226 — Tipos de documento de flota (carga documental 2026-07)
-- ============================================================================
-- La carpeta "DOCUMENTACIÓN VIGENTE" maneja ~30 tipos de documento por camión.
-- Se agregan al enum los que faltaban para no perder la identidad de cada
-- documento (el panel de vencimientos agrupa por tipo).
-- NOTA: solo ALTER TYPE ADD VALUE; el uso de los valores va en scripts/migs
-- posteriores (regla de Postgres para valores nuevos en la misma transacción).
-- ============================================================================

ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'analisis_gases';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'padron';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'inscripcion_rnvm';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'homologacion';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'optico_sobrellenado';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'flujo_descarga';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'sist_riego';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'cert_cabina';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'laminas_seguridad';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'barra_antivuelco';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'operatividad';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'grilletes_eslingas';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'mant_hidraulico';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'mantencion';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'aire_acondicionado';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'tacografo';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'torque_ruedas';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'ausencia_falla_ecm';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'gps';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'inventario_neumaticos';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'ficha_tecnica';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'factura_compra';
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'manual';

DO $$ BEGIN RAISE NOTICE 'MIG226 OK: tipos de documento de flota agregados al enum'; END $$;
