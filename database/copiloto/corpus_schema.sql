-- ============================================================================
-- COPILOTO TALLER · Esquema del proyecto Supabase "copiloto-corpus"
-- ============================================================================
--
-- OJO: este SQL NO se aplica a la base de SICOM producción. Va en el proyecto
-- Supabase PARALELO dedicado al corpus documental del copiloto (manuales,
-- diagramas, procedimientos). Decisión 2026-09-08: la DB de SICOM va en
-- 255/500 MB y el storage al 67% — el corpus vive aparte para no arriesgar
-- la operación. La app SICOM le pega solo desde el servidor (service key).
--
-- Se aplica con:  node database/scripts/copiloto-ingesta.mjs --schema
-- (lee COPILOTO_DB_URL de database/.env.copiloto.local)
--
-- Idempotente: se puede correr de nuevo sin romper nada.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Configuración de búsqueda español + sin tildes: el mecánico escribe
-- "neumatico" y el manual dice "neumático" — tienen que encontrarse igual.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_ts_config WHERE cfgname = 'es_unaccent') THEN
    CREATE TEXT SEARCH CONFIGURATION es_unaccent (COPY = spanish);
    ALTER TEXT SEARCH CONFIGURATION es_unaccent
      ALTER MAPPING FOR hword, hword_part, word
      WITH unaccent, spanish_stem;
  END IF;
END $$;

-- ── Documentos ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_documentos (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo           TEXT NOT NULL,
  archivo          TEXT NOT NULL,             -- nombre del archivo original
  ruta_origen      TEXT,                      -- carpeta de origen en el Desktop
  hash             TEXT UNIQUE NOT NULL,      -- sha256 del archivo (evita duplicados)
  tipo_documento   TEXT NOT NULL DEFAULT 'manual_oficial'
                   CHECK (tipo_documento IN ('manual_oficial','procedimiento_interno',
                                             'catalogo_partes','ficha_tecnica',
                                             'reporte_falla','otro')),
  marca            TEXT,                      -- slug: mercedes-benz, mack, volvo... NULL = aplica a todos
  modelo           TEXT,                      -- slug: actros, t310... NULL = toda la marca
  sistema          TEXT,                      -- transmision, electrico, frenos, motor...
  equipo           TEXT,                      -- patente si el manual es de UN equipo (ej: JPZV-22)
  paginas          INT,
  paginas_con_texto INT,
  storage_path     TEXT,                      -- fase 2: PDF subido al storage de este proyecto
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Chunks (texto consultable) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_chunks (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  documento_id  UUID NOT NULL REFERENCES copiloto_documentos(id) ON DELETE CASCADE,
  pagina        INT NOT NULL,
  chunk_index   INT NOT NULL DEFAULT 0,       -- orden dentro de la página
  contenido     TEXT NOT NULL,
  tipo_chunk    TEXT NOT NULL DEFAULT 'general'
                CHECK (tipo_chunk IN ('general','procedimiento','advertencia',
                                      'torque_presion','codigo_falla','tabla')),
  tsv           TSVECTOR GENERATED ALWAYS AS
                (to_tsvector('es_unaccent'::regconfig, LEFT(contenido, 20000))) STORED
);

CREATE INDEX IF NOT EXISTS idx_copiloto_chunks_tsv ON copiloto_chunks USING GIN (tsv);
CREATE INDEX IF NOT EXISTS idx_copiloto_chunks_doc ON copiloto_chunks (documento_id);

-- ── Búsqueda ────────────────────────────────────────────────────────────────
-- Ranking por confiabilidad (diseño copiloto-taller original):
-- manual oficial > procedimiento interno > catálogo > ficha > otro.
-- El filtro de marca es blando: si el equipo es Mercedes trae Mercedes Y los
-- documentos genéricos (marca NULL), nunca manuales de otra marca.
CREATE OR REPLACE FUNCTION buscar_chunks(
    p_query  TEXT,
    p_marca  TEXT DEFAULT NULL,
    p_modelo TEXT DEFAULT NULL,
    p_limit  INT  DEFAULT 8)
RETURNS TABLE (
  chunk_id       BIGINT,
  documento_id   UUID,
  titulo         TEXT,
  archivo        TEXT,
  tipo_documento TEXT,
  marca          TEXT,
  sistema        TEXT,
  pagina         INT,
  tipo_chunk     TEXT,
  contenido      TEXT,
  rank           REAL
) LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_q  TSQUERY;
  v_or TEXT;
BEGIN
  v_q := websearch_to_tsquery('es_unaccent', p_query);

  RETURN QUERY
  SELECT c.id, d.id, d.titulo, d.archivo, d.tipo_documento, d.marca, d.sistema,
         c.pagina, c.tipo_chunk, c.contenido,
         (ts_rank_cd(c.tsv, v_q)
          * CASE d.tipo_documento
              WHEN 'manual_oficial'        THEN 1.00
              WHEN 'procedimiento_interno' THEN 0.85
              WHEN 'catalogo_partes'       THEN 0.70
              WHEN 'ficha_tecnica'         THEN 0.70
              WHEN 'reporte_falla'         THEN 0.60
              ELSE 0.50 END
          * CASE WHEN p_marca IS NOT NULL AND d.marca = p_marca THEN 1.2 ELSE 1.0 END
         )::REAL AS rank
    FROM copiloto_chunks c
    JOIN copiloto_documentos d ON d.id = c.documento_id
   WHERE c.tsv @@ v_q
     AND (p_marca  IS NULL OR d.marca  IS NULL OR d.marca  = p_marca)
     AND (p_modelo IS NULL OR d.modelo IS NULL OR d.modelo = p_modelo)
   ORDER BY rank DESC
   LIMIT p_limit;

  -- Sin resultados con la frase completa: reintenta con OR entre palabras
  -- ("ruido caja cambios" → ruido | caja | cambios).
  IF NOT FOUND THEN
    v_or := ARRAY_TO_STRING(
              ARRAY(SELECT w FROM REGEXP_SPLIT_TO_TABLE(TRIM(p_query), '\s+') w
                     WHERE LENGTH(w) > 2), ' OR ');
    IF v_or = '' THEN RETURN; END IF;
    v_q := websearch_to_tsquery('es_unaccent', v_or);

    RETURN QUERY
    SELECT c.id, d.id, d.titulo, d.archivo, d.tipo_documento, d.marca, d.sistema,
           c.pagina, c.tipo_chunk, c.contenido,
           (ts_rank_cd(c.tsv, v_q)
            * CASE d.tipo_documento
                WHEN 'manual_oficial'        THEN 1.00
                WHEN 'procedimiento_interno' THEN 0.85
                WHEN 'catalogo_partes'       THEN 0.70
                WHEN 'ficha_tecnica'         THEN 0.70
                ELSE 0.50 END
            * CASE WHEN p_marca IS NOT NULL AND d.marca = p_marca THEN 1.2 ELSE 1.0 END
           )::REAL AS rank
      FROM copiloto_chunks c
      JOIN copiloto_documentos d ON d.id = c.documento_id
     WHERE c.tsv @@ v_q
       AND (p_marca  IS NULL OR d.marca  IS NULL OR d.marca  = p_marca)
       AND (p_modelo IS NULL OR d.modelo IS NULL OR d.modelo = p_modelo)
     ORDER BY rank DESC
     LIMIT p_limit;
  END IF;
END $$;

-- ── Seguridad: este proyecto se consulta SOLO desde el servidor ─────────────
-- RLS deny-all para anon/authenticated; el service key (backend) lo salta.
ALTER TABLE copiloto_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE copiloto_chunks     ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON copiloto_documentos, copiloto_chunks FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION buscar_chunks(TEXT,TEXT,TEXT,INT) FROM PUBLIC, anon, authenticated;

COMMIT;

SELECT 'corpus_schema aplicado' AS resultado,
       (SELECT COUNT(*) FROM copiloto_documentos) AS documentos,
       (SELECT COUNT(*) FROM copiloto_chunks)     AS chunks;
