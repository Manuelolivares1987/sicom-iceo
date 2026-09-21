-- ============================================================================
-- COPILOTO TALLER · Esquema v2 del proyecto "copiloto-corpus" (2026-09-19)
-- ============================================================================
--
-- Va en el proyecto Supabase PARALELO del corpus (NO en SICOM producción).
-- Se aplica con:  node database/scripts/copiloto-ingesta.mjs --schema-v2
-- Idempotente. Requiere corpus_schema.sql (v1) aplicado antes.
--
-- LO QUE PIDIÓ MANUEL (19-09-2026)
-- «Consigue información técnica de toda la flota pesada para mejorar el
-- diagnóstico, ejemplo diagramas eléctricos [...] mejora la app a los mejores
-- estándares mundiales.»
--
-- QUÉ AGREGA
--  1. Fix del filtro por modelo: SICOM entrega "Actros 3336 K" → slug
--     'actros-3336-k' y el corpus guarda la familia 'actros'. Con igualdad
--     estricta, desde el camión NUNCA salían los manuales de Actros, Atego,
--     Axor, Accelo ni FMX. Ahora el modelo del corpus calza como PREFIJO.
--  2. Documentos con URL oficial de origen y confiabilidad (web investigada:
--     'guia_tecnica_web'), para citar y enlazar la fuente.
--  3. copiloto_codigos_falla: códigos estructurados (SPN/FMI, MID/PID, FR/MR,
--     blink, Allison...) con causas y comprobaciones. Búsqueda determinística
--     por número, sin IA: el mecánico escribe "3251 0" y aparece al tiro.
--  4. copiloto_fichas_equipo: la ficha técnica de cada camión por patente
--     (VIN, motor, caja, norma de emisiones, ECUs, implemento) desde la
--     Biblioteca Maestra. El copiloto sabe exactamente qué tiene el equipo.
--  5. copiloto_paginas: imágenes de las páginas de diagramas/tablas (storage
--     de este proyecto) para que el mecánico VEA el diagrama citado y el
--     copiloto lo LEA con visión.
--  6. copiloto_adjuntos: fotos y PDFs que sube el mecánico desde el teléfono.
-- ============================================================================

BEGIN;

-- ── 1+2. Documentos: origen web y confiabilidad ──────────────────────────────
ALTER TABLE copiloto_documentos ADD COLUMN IF NOT EXISTS url_fuente    TEXT;
ALTER TABLE copiloto_documentos ADD COLUMN IF NOT EXISTS confiabilidad TEXT
  CHECK (confiabilidad IN ('oficial','tecnica_terceros','experiencia_campo'));
ALTER TABLE copiloto_documentos ADD COLUMN IF NOT EXISTS idioma TEXT;

ALTER TABLE copiloto_documentos DROP CONSTRAINT IF EXISTS copiloto_documentos_tipo_documento_check;
ALTER TABLE copiloto_documentos ADD CONSTRAINT copiloto_documentos_tipo_documento_check
  CHECK (tipo_documento IN ('manual_oficial','procedimiento_interno','catalogo_partes',
                            'ficha_tecnica','reporte_falla','guia_tecnica_web','otro'));

-- Ficha de conocimiento web: URL propia por chunk (una ficha = un chunk)
ALTER TABLE copiloto_chunks ADD COLUMN IF NOT EXISTS url_fuente TEXT;
ALTER TABLE copiloto_chunks DROP CONSTRAINT IF EXISTS copiloto_chunks_tipo_chunk_check;
ALTER TABLE copiloto_chunks ADD CONSTRAINT copiloto_chunks_tipo_chunk_check
  CHECK (tipo_chunk IN ('general','procedimiento','advertencia','torque_presion',
                        'codigo_falla','tabla','diagrama_electrico','fusibles_reles',
                        'pinout_conector','arquitectura_can','falla_conocida',
                        'especificacion','boletin_recall','lectura_codigos_tablero',
                        'procedimiento_diagnostico'));

-- ── 5. Páginas renderizadas (diagramas / tablas) ────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_paginas (
  documento_id UUID NOT NULL REFERENCES copiloto_documentos(id) ON DELETE CASCADE,
  pagina       INT  NOT NULL,
  storage_path TEXT NOT NULL,            -- bucket 'paginas'
  ancho        INT,
  alto         INT,
  bytes        INT,
  PRIMARY KEY (documento_id, pagina)
);

-- Bucket privado: las imágenes salen solo por URL firmada desde el servidor
INSERT INTO storage.buckets (id, name, public)
VALUES ('paginas', 'paginas', false)
ON CONFLICT (id) DO NOTHING;

-- Trigramas sobre el título: "diagrama adblue" encuentra el documento aunque
-- el texto de la página sea un plano con puras etiquetas.
CREATE INDEX IF NOT EXISTS idx_copiloto_docs_titulo_trgm
  ON copiloto_documentos USING GIN (titulo gin_trgm_ops);

-- ── Búsqueda v2 ─────────────────────────────────────────────────────────────
-- Cambios vs v1: modelo por PREFIJO (fix), guia_tecnica_web en el ranking,
-- bonus por título que calza (diagramas), filtro opcional por sistema, y
-- devuelve url_fuente + si la página tiene imagen disponible.
DROP FUNCTION IF EXISTS buscar_chunks(TEXT,TEXT,TEXT,INT);
DROP FUNCTION IF EXISTS buscar_chunks(TEXT,TEXT,TEXT,INT,TEXT);
CREATE OR REPLACE FUNCTION buscar_chunks(
    p_query   TEXT,
    p_marca   TEXT DEFAULT NULL,
    p_modelo  TEXT DEFAULT NULL,
    p_limit   INT  DEFAULT 8,
    p_sistema TEXT DEFAULT NULL)
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
  rank           REAL,
  url_fuente     TEXT,
  confiabilidad  TEXT,
  con_imagen     BOOLEAN
) LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_q     TSQUERY;
  v_and   TSQUERY;
  v_or    TEXT;
  v_try   INT := 0;
  v_n     INT := 0;
  v_falta INT := p_limit;
BEGIN
  v_q := websearch_to_tsquery('es_unaccent', p_query);
  v_and := v_q;

  LOOP
    -- 2ª pasada: completa con coincidencias parciales (OR) que NO calzaron
    -- con todas las palabras. Antes solo se hacía si la 1ª no traía nada, y
    -- 2-3 resultados débiles tapaban documentos mejores.
    RETURN QUERY
    SELECT c.id, d.id, d.titulo, d.archivo, d.tipo_documento, d.marca, d.sistema,
           c.pagina, c.tipo_chunk, c.contenido,
           (ts_rank_cd(c.tsv, v_q)
            * CASE d.tipo_documento
                WHEN 'manual_oficial'        THEN 1.00
                WHEN 'procedimiento_interno' THEN 0.85
                WHEN 'guia_tecnica_web'      THEN CASE COALESCE(d.confiabilidad,'tecnica_terceros')
                                                    WHEN 'oficial' THEN 0.90
                                                    WHEN 'tecnica_terceros' THEN 0.75
                                                    ELSE 0.55 END
                WHEN 'catalogo_partes'       THEN 0.70
                WHEN 'ficha_tecnica'         THEN 0.70
                WHEN 'reporte_falla'         THEN 0.60
                ELSE 0.50 END
            * CASE WHEN p_marca IS NOT NULL AND d.marca = p_marca THEN 1.2 ELSE 1.0 END
            * CASE WHEN p_modelo IS NOT NULL AND d.modelo IS NOT NULL THEN 1.15 ELSE 1.0 END
            * CASE WHEN p_sistema IS NOT NULL AND d.sistema = p_sistema THEN 1.15 ELSE 1.0 END
            * CASE WHEN similarity(d.titulo, p_query) > 0.2 THEN 1.3 ELSE 1.0 END
           )::REAL AS rank,
           COALESCE(c.url_fuente, d.url_fuente),
           d.confiabilidad,
           EXISTS (SELECT 1 FROM copiloto_paginas pg
                    WHERE pg.documento_id = d.id AND pg.pagina = c.pagina)
      FROM copiloto_chunks c
      JOIN copiloto_documentos d ON d.id = c.documento_id
     WHERE c.tsv @@ v_q
       AND (p_marca  IS NULL OR d.marca  IS NULL OR d.marca = p_marca)
       -- FIX v2: el modelo del corpus es la FAMILIA ('actros') y el de SICOM
       -- viene completo ('actros-3336-k'): calza por prefijo.
       AND (p_modelo IS NULL OR d.modelo IS NULL OR p_modelo LIKE d.modelo || '%')
       AND (v_try = 0 OR NOT (c.tsv @@ v_and))
     ORDER BY rank DESC
     LIMIT v_falta;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_falta := v_falta - v_n;
    -- Basta si la búsqueda estricta llenó al menos la mitad
    EXIT WHEN v_try > 0 OR v_falta <= p_limit / 2;
    v_try := v_try + 1;

    v_or := ARRAY_TO_STRING(
              ARRAY(SELECT w FROM REGEXP_SPLIT_TO_TABLE(TRIM(p_query), '\s+') w
                     WHERE LENGTH(w) > 2), ' OR ');
    EXIT WHEN v_or = '';
    v_q := websearch_to_tsquery('es_unaccent', v_or);
  END LOOP;
END $$;

-- ── Documentos por título (para "¿qué diagramas hay del Actros?") ───────────
CREATE OR REPLACE FUNCTION buscar_documentos(
    p_texto  TEXT,
    p_marca  TEXT DEFAULT NULL,
    p_limit  INT  DEFAULT 12)
RETURNS TABLE (documento_id UUID, titulo TEXT, marca TEXT, modelo TEXT, sistema TEXT,
               tipo_documento TEXT, paginas INT, url_fuente TEXT, con_imagenes BOOLEAN)
LANGUAGE sql STABLE AS $$
  SELECT d.id, d.titulo, d.marca, d.modelo, d.sistema, d.tipo_documento, d.paginas,
         d.url_fuente,
         EXISTS (SELECT 1 FROM copiloto_paginas pg WHERE pg.documento_id = d.id)
    FROM copiloto_documentos d
   WHERE (p_marca IS NULL OR d.marca IS NULL OR d.marca = p_marca)
     AND (d.titulo % p_texto OR d.titulo ILIKE '%' || p_texto || '%'
          OR to_tsvector('es_unaccent', d.titulo) @@ websearch_to_tsquery('es_unaccent', p_texto))
   ORDER BY similarity(d.titulo, p_texto) DESC
   LIMIT p_limit;
$$;

-- ── 3. Códigos de falla estructurados ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_codigos_falla (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  marca          TEXT,                  -- slug; NULL = genérico J1939
  aplica         TEXT,                  -- "MP8 EPA10 / GU813", "OM541 PLD"...
  ecu            TEXT,
  formato        TEXT NOT NULL,         -- SPN-FMI, MID-PID-FMI, FR/MR/GS, blink, Allison-DTC...
  codigo         TEXT NOT NULL,         -- como lo muestra la fuente
  codigo_norm    TEXT NOT NULL,         -- solo dígitos/letras en mayúscula, sin separadores
  spn            INT,
  fmi            INT,
  descripcion    TEXT NOT NULL,
  causas         JSONB NOT NULL DEFAULT '[]'::jsonb,
  comprobaciones JSONB NOT NULL DEFAULT '[]'::jsonb,
  sistema        TEXT,
  confiabilidad  TEXT NOT NULL DEFAULT 'tecnica_terceros',
  fuente         TEXT,
  origen_archivo TEXT,                  -- codigos/<marca>.json (reingesta idempotente)
  tsv            TSVECTOR GENERATED ALWAYS AS (to_tsvector('es_unaccent'::regconfig,
                   COALESCE(codigo,'') || ' ' || COALESCE(descripcion,'') || ' ' ||
                   COALESCE(aplica,'') || ' ' || COALESCE(ecu,''))) STORED
);
CREATE INDEX IF NOT EXISTS idx_copiloto_cod_norm ON copiloto_codigos_falla (codigo_norm);
CREATE INDEX IF NOT EXISTS idx_copiloto_cod_spn  ON copiloto_codigos_falla (spn, fmi);
CREATE INDEX IF NOT EXISTS idx_copiloto_cod_tsv  ON copiloto_codigos_falla USING GIN (tsv);

-- Búsqueda por código: entiende "SPN 3251 FMI 0", "3251-0", "3251/0", "P0420",
-- "MR 0123", "PID 100"... Orden: coincidencia exacta de SPN+FMI > mismo SPN >
-- código normalizado > texto. La marca del equipo primero, luego genéricos.
CREATE OR REPLACE FUNCTION buscar_codigo_falla(
    p_texto TEXT,
    p_marca TEXT DEFAULT NULL,
    p_limit INT  DEFAULT 10)
RETURNS TABLE (id BIGINT, marca TEXT, aplica TEXT, ecu TEXT, formato TEXT, codigo TEXT,
               spn INT, fmi INT, descripcion TEXT, causas JSONB, comprobaciones JSONB,
               sistema TEXT, confiabilidad TEXT, fuente TEXT, coincidencia TEXT)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_nums INT[];
  v_spn  INT;
  v_fmi  INT;
  v_norm TEXT;
BEGIN
  v_norm := UPPER(REGEXP_REPLACE(COALESCE(p_texto,''), '[^A-Za-z0-9]', '', 'g'));
  v_nums := ARRAY(SELECT (m[1])::INT FROM REGEXP_MATCHES(COALESCE(p_texto,''), '(\d{1,7})', 'g') m);
  IF p_texto ~* 'spn' OR array_length(v_nums,1) = 2 THEN
    v_spn := v_nums[1];
    v_fmi := CASE WHEN array_length(v_nums,1) >= 2 AND v_nums[2] <= 31 THEN v_nums[2] END;
  ELSIF array_length(v_nums,1) = 1 AND v_nums[1] > 31 THEN
    v_spn := v_nums[1];
  END IF;

  RETURN QUERY
  SELECT c.id, c.marca, c.aplica, c.ecu, c.formato, c.codigo, c.spn, c.fmi, c.descripcion,
         c.causas, c.comprobaciones, c.sistema, c.confiabilidad, c.fuente,
         CASE WHEN v_spn IS NOT NULL AND c.spn = v_spn AND c.fmi IS NOT DISTINCT FROM v_fmi THEN 'exacta'
              WHEN c.codigo_norm = v_norm THEN 'exacta'
              WHEN v_spn IS NOT NULL AND c.spn = v_spn THEN 'mismo_spn'
              ELSE 'texto' END
    FROM copiloto_codigos_falla c
   WHERE (p_marca IS NULL OR c.marca IS NULL OR c.marca = p_marca)
     AND ((v_spn IS NOT NULL AND c.spn = v_spn)
          OR (LENGTH(v_norm) >= 3 AND c.codigo_norm = v_norm)
          OR (LENGTH(v_norm) >= 4 AND c.codigo_norm LIKE '%' || v_norm || '%')
          OR c.tsv @@ websearch_to_tsquery('es_unaccent', p_texto))
   ORDER BY
     (v_spn IS NOT NULL AND c.spn = v_spn AND c.fmi IS NOT DISTINCT FROM v_fmi) DESC,
     (c.codigo_norm = v_norm) DESC,
     (v_spn IS NOT NULL AND c.spn = v_spn) DESC,
     (p_marca IS NOT NULL AND c.marca = p_marca) DESC,
     CASE c.confiabilidad WHEN 'oficial' THEN 0 WHEN 'tecnica_terceros' THEN 1 ELSE 2 END,
     c.fmi NULLS LAST
   LIMIT p_limit;
END $$;

-- ── 4. Ficha técnica por equipo ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_fichas_equipo (
  patente        TEXT PRIMARY KEY,      -- normalizada: 'DJKL-18'
  marca          TEXT,                  -- slug
  modelo         TEXT,
  anio           INT,
  vin            TEXT,
  numero_motor   TEXT,
  motor          TEXT,                  -- "OM541 LA (Actros MP3)", "Volvo D13K 420"
  transmision    TEXT,
  emisiones      TEXT,
  ecus           TEXT,                  -- arquitectura: "MR/PLD, FR, GS, EBS, INS"
  equipamiento   TEXT,                  -- aljibe 15 kL, riego, pluma...
  implemento     TEXT,                  -- lo que hay que documentar del implemento
  zona           TEXT,
  fuente_oem     TEXT,
  lectura_codigos TEXT,                 -- cómo sacar códigos en el tablero de ESTE modelo
  notas          TEXT,
  datos          JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 6. Adjuntos del mecánico (fotos y PDFs desde el teléfono) ───────────────
-- El teléfono sube DIRECTO al storage de este proyecto con una URL firmada
-- (evita el límite de ~6 MB por request de Netlify). Si el mecánico sube un
-- manual (o una foto: etiqueta de fusibles, placa) y la propone a la biblioteca
-- con una descripción, jefatura la revisa y la ingiere
-- (copiloto-conocimiento.mjs --aportes).
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('adjuntos', 'adjuntos', false, 26214400)   -- 25 MB por archivo
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS copiloto_adjuntos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id   UUID NOT NULL,                 -- auth.uid() de SICOM (no de este proyecto)
  activo_id    UUID,                          -- equipo de SICOM, si había
  consulta_id  UUID,                          -- copiloto_consultas de SICOM
  storage_path TEXT NOT NULL UNIQUE,
  nombre       TEXT NOT NULL,
  tipo         TEXT NOT NULL,                 -- image/jpeg, application/pdf...
  bytes        INT,
  propuesto_biblioteca BOOLEAN NOT NULL DEFAULT FALSE,
  descripcion  TEXT,                          -- qué es (aporte: "etiqueta fusibles tapa central TRSS-13")
  estado       TEXT NOT NULL DEFAULT 'subido'
               CHECK (estado IN ('subido','usado','ingerido','descartado')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE copiloto_adjuntos ADD COLUMN IF NOT EXISTS descripcion TEXT;
CREATE INDEX IF NOT EXISTS idx_copiloto_adj_prop ON copiloto_adjuntos (propuesto_biblioteca, estado);

-- ── Seguridad: solo servidor (service key) ──────────────────────────────────
ALTER TABLE copiloto_codigos_falla ENABLE ROW LEVEL SECURITY;
ALTER TABLE copiloto_fichas_equipo ENABLE ROW LEVEL SECURITY;
ALTER TABLE copiloto_paginas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE copiloto_adjuntos      ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON copiloto_codigos_falla, copiloto_fichas_equipo, copiloto_paginas, copiloto_adjuntos FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION buscar_chunks(TEXT,TEXT,TEXT,INT,TEXT)  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION buscar_documentos(TEXT,TEXT,INT)       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION buscar_codigo_falla(TEXT,TEXT,INT)     FROM PUBLIC, anon, authenticated;

COMMIT;

SELECT 'corpus_schema_v2 aplicado' AS resultado,
       (SELECT COUNT(*) FROM copiloto_documentos)    AS documentos,
       (SELECT COUNT(*) FROM copiloto_chunks)        AS chunks,
       (SELECT COUNT(*) FROM copiloto_codigos_falla) AS codigos,
       (SELECT COUNT(*) FROM copiloto_fichas_equipo) AS fichas,
       (SELECT COUNT(*) FROM copiloto_paginas)       AS paginas;
