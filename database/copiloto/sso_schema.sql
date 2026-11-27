-- ============================================================================
-- Copiloto Prevención Centinela — corpus (proyecto copiloto-corpus)
-- ----------------------------------------------------------------------------
-- 26-11-2026. Base de conocimiento descargada del Campus Centinela (RECSS AMSA
-- v3, EDC Altura y Energía Eléctrica, Lecciones Aprendidas y Boletines,
-- Directriz de Administración de Contratos, Manual SOFI, plataforma y salud),
-- depurada en Markdown y dividida por sección.
--
-- Tablas PROPIAS (sso_*): no se mezclan con los manuales del taller. La
-- búsqueda del taller (buscar_chunks) toma todo documento sin marca; si los de
-- Centinela vivieran en copiloto_documentos aparecerían en las respuestas del
-- Copiloto Taller.
-- Idempotente.
-- ============================================================================

CREATE TABLE IF NOT EXISTS sso_documentos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      TEXT UNIQUE NOT NULL,          -- '02', '05'…
    titulo      TEXT NOT NULL,                 -- 'RECSS — Reglamento Especial para Empresas Contratistas (AMSA v3, 2022)'
    archivo     TEXT NOT NULL,
    escaneado   BOOLEAN NOT NULL DEFAULT FALSE, -- cifras leídas por OCR: verificar en el PDF original
    sha256      TEXT NOT NULL,
    descargado  DATE NOT NULL DEFAULT DATE '2026-11-26',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sso_chunks (
    id           BIGSERIAL PRIMARY KEY,
    documento_id UUID NOT NULL REFERENCES sso_documentos(id) ON DELETE CASCADE,
    orden        INTEGER NOT NULL,
    seccion      TEXT,                          -- ruta de títulos: «Cap. 9 › Verificación»
    contenido    TEXT NOT NULL,
    tsv          TSVECTOR GENERATED ALWAYS AS (
                   to_tsvector('es_unaccent'::regconfig, coalesce(seccion, '') || ' ' || LEFT(contenido, 20000))) STORED
);
CREATE INDEX IF NOT EXISTS idx_sso_chunks_tsv ON sso_chunks USING GIN (tsv);
CREATE INDEX IF NOT EXISTS idx_sso_chunks_doc ON sso_chunks (documento_id, orden);

ALTER TABLE sso_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE sso_chunks     ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo el servidor (service role) lee.

-- Búsqueda: primero con todas las palabras; si no llena, completa con
-- cualquiera de ellas (las que no calzaron con todas).
CREATE OR REPLACE FUNCTION buscar_sso(p_query TEXT, p_limite INTEGER DEFAULT 8)
RETURNS TABLE (chunk_id BIGINT, codigo TEXT, titulo TEXT, escaneado BOOLEAN,
               seccion TEXT, contenido TEXT, rank REAL)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_and TSQUERY := websearch_to_tsquery('es_unaccent', p_query);
    v_or  TSQUERY;
    v_n   INTEGER;
BEGIN
    RETURN QUERY
    SELECT c.id, d.codigo, d.titulo, d.escaneado, c.seccion, c.contenido,
           ts_rank_cd(c.tsv, v_and)::REAL
      FROM sso_chunks c JOIN sso_documentos d ON d.id = c.documento_id
     WHERE c.tsv @@ v_and
     ORDER BY 7 DESC LIMIT p_limite;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n >= p_limite THEN RETURN; END IF;

    v_or := websearch_to_tsquery('es_unaccent',
              array_to_string(regexp_split_to_array(btrim(p_query), '\s+'), ' or '));
    RETURN QUERY
    SELECT c.id, d.codigo, d.titulo, d.escaneado, c.seccion, c.contenido,
           (ts_rank_cd(c.tsv, v_or) * 0.6)::REAL
      FROM sso_chunks c JOIN sso_documentos d ON d.id = c.documento_id
     WHERE c.tsv @@ v_or AND NOT (c.tsv @@ v_and)
     ORDER BY 7 DESC LIMIT p_limite - v_n;
END $$;
