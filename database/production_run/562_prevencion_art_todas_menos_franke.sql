-- ============================================================================
-- MIG562 · Prevención: ART en todas las faenas mapeadas EXCEPTO Franke
-- ============================================================================
-- Manuel (2026-09-14): «ART a todos excepto Franke». MIG561 lo había dejado
-- solo en las dos Lomas; se suma a Centinela, Spence y Romeral. Franke queda
-- fuera a propósito (su mandante no lo pide). Convergente: si ART apareciera
-- en Franke, se quita.
-- ============================================================================

BEGIN;

INSERT INTO prevencion_faena_tipos (faena_id, tipo_codigo)
SELECT ft.faena_id, 'ART'
  FROM (SELECT DISTINCT faena_id FROM prevencion_faena_tipos) ft
  JOIN faenas f ON f.id = ft.faena_id
 WHERE f.codigo <> 'FAE-FRANCKE'
ON CONFLICT DO NOTHING;

DELETE FROM prevencion_faena_tipos ft
 USING faenas f
 WHERE f.id = ft.faena_id
   AND f.codigo = 'FAE-FRANCKE'
   AND ft.tipo_codigo = 'ART';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN — ART en Centinela, Spence, Romeral y las dos Lomas; no en Franke
-- ============================================================================
SELECT f.codigo, bool_or(ft.tipo_codigo = 'ART') AS tiene_art
FROM prevencion_faena_tipos ft
JOIN faenas f ON f.id = ft.faena_id
GROUP BY f.codigo ORDER BY f.codigo;
