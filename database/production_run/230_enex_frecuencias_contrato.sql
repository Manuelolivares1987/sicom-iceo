-- ============================================================================
-- SICOM-ICEO | 230 — ENEX: frecuencias del contrato como referencia
-- ============================================================================
-- Pedido de Manuel: tener a la vista las frecuencias que exige el contrato
-- (VA_24_068: mantención trimestral, calibración NCh 1436:2001) al armar el
-- plan mensual/trimestral. Se guardan POR instalación (editable, porque los
-- anexos pueden fijar frecuencias distintas por punto).
-- destructivo-ok: UPDATE masivo intencional — solo siembra el valor por defecto
-- del contrato en las columnas recién creadas (COALESCE respeta valores previos).
-- ============================================================================

ALTER TABLE enex_instalaciones
  ADD COLUMN IF NOT EXISTS frecuencia_mantencion  TEXT,
  ADD COLUMN IF NOT EXISTS frecuencia_calibracion TEXT;

-- Semilla desde el contrato marco (ajustable por instalación en el panel)
UPDATE enex_instalaciones
   SET frecuencia_mantencion  = COALESCE(frecuencia_mantencion, 'Trimestral'),
       frecuencia_calibracion = COALESCE(frecuencia_calibracion, 'Trimestral · NCh 1436:2001');

DO $$ BEGIN RAISE NOTICE 'MIG230 OK: frecuencias del contrato por instalación'; END $$;
