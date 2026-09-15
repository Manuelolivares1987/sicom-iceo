-- ============================================================================
-- MIG559 · Prevención: el E-200 va POR LUGAR (faena mandante + instalación)
-- ============================================================================
-- Manuel (2026-09-14, fotos E-200 reales en «Fotos e200»): Centinela declara
-- UN E-200 por cada instalación, y cada una pertenece a una faena del
-- mandante (Centinela Sulfuros / Centinela Oxido / Centinela Encuentro).
-- La ficha de la faena ya tenía las 7 instalaciones como texto (MIG557);
-- aquí se les agrega el DETALLE que el formulario estatal pide por lugar:
-- región, provincia, comuna, tipo, datum, huso, cota y coordenadas — leídos
-- de los E-200 históricos fotografiados.
--
-- La clave del detalle es EXACTAMENTE el texto de `instalaciones` (es lo que
-- guarda prevencion_dotacion_diaria.instalacion), no se toca lo existente:
-- el UPDATE solo AGREGA la llave instalaciones_detalle (regla MIG383: la
-- ficha se parcha por línea, no se reescribe).
--
-- Nota: la foto del E-200 de Encuentro dice «74411070» (8 cifras); una
-- coordenada norte UTM de la zona tiene 7 → se corrige a 7441070.
-- ============================================================================

BEGIN;

UPDATE prevencion_faena_config c
   SET datos = c.datos || jsonb_build_object('instalaciones_detalle', $json$
{
  "Centinela Sulfuros — Mina Esperanza": {
    "faena": "CENTINELA SULFUROS", "nombre": "MINA ESPERANZA",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Mina Rajo Abierto", "datum": "PSAD-56", "huso": "19",
    "cota": "2331", "coord_norte": "7464963", "coord_este": "489907",
    "estado": "ACTIVA"
  },
  "Centinela Sulfuros — Mina Esperanza Sur": {
    "faena": "CENTINELA SULFUROS", "nombre": "MINA ESPERANZA SUR",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Mina Rajo Abierto", "datum": "PSAD-56", "huso": "19",
    "cota": "2331", "coord_norte": "7464963", "coord_este": "489907",
    "estado": "ACTIVA"
  },
  "Centinela Sulfuros — Planta Concentradora (Planta)": {
    "faena": "CENTINELA SULFUROS", "nombre": "PLANTA CONCENTRADORA",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Planta Concentradora", "datum": "PSAD-56", "huso": "19",
    "cota": "2340", "coord_norte": "7456849", "coord_este": "490029",
    "estado": "ACTIVA"
  },
  "Centinela Oxido — Mina Rajo Abierto": {
    "faena": "CENTINELA OXIDO", "nombre": "MINA RAJO ABIERTO",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Mina Rajo Abierto", "datum": "PSAD-56", "huso": "19",
    "cota": "2555", "coord_norte": "7462878", "coord_este": "492034",
    "estado": "ACTIVA"
  },
  "Centinela Oxido — Pila de lixiviación (Planta)": {
    "faena": "CENTINELA OXIDO", "nombre": "PILAS DE LIXIVIACIÓN",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Planta extracción por solventes", "datum": "PSAD-56", "huso": "19",
    "cota": "2192", "coord_norte": "7462401", "coord_este": "490254",
    "estado": "ACTIVA"
  },
  "Centinela Sulfuros — Puerto de Embarque (Muelle)": {
    "faena": "CENTINELA SULFUROS", "nombre": "PUERTO DE EMBARQUE (MUELLE)",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Puerto de embarque", "datum": "PSAD-56", "huso": "19",
    "cota": "2555", "coord_norte": "7462878", "coord_este": "492034",
    "estado": "ACTIVA"
  },
  "Centinela Encuentro (DES) — Mina": {
    "faena": "CENTINELA ENCUENTRO", "nombre": "MINA",
    "region": "Segunda", "provincia": "Antofagasta", "comuna": "Sierra Gorda",
    "tipo": "Mina Rajo Abierto", "datum": "PSAD-56", "huso": "19",
    "cota": "1050", "coord_norte": "7441070", "coord_este": "488884",
    "estado": "ACTIVA"
  }
}
$json$::jsonb),
       updated_at = NOW()
  FROM faenas f
 WHERE f.id = c.faena_id
   AND f.codigo = 'FAE-CENTINELA';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.codigo,
       jsonb_object_keys(c.datos->'instalaciones_detalle') AS instalacion
FROM prevencion_faena_config c
JOIN faenas f ON f.id = c.faena_id
WHERE f.codigo = 'FAE-CENTINELA';
