-- ============================================================================
-- MIG542 · Copiloto Técnico del taller — auditoría de consultas
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (08-09-2026)
-- «La capacidad de diagnóstico de los mecánicos es bastante mala [...] el
-- camión 42 estuvo con problemas eléctricos varios días y no se sabía el
-- problema. Desconocen partes del camión, no tienen diagramas eléctricos.
-- Quiero que la aplicación del teléfono también sea una ayuda para ellos
-- en el diagnóstico.»
--
-- QUÉ SE HACE
-- Se retoma el proyecto copiloto-taller (mayo 2026) pero INTEGRADO a SICOM:
-- el corpus documental (275 PDFs de manuales) vive en un proyecto Supabase
-- paralelo ("copiloto-corpus", ver database/copiloto/) para no cargar esta
-- base (255/500 MB); acá solo queda la AUDITORÍA: cada pregunta del mecánico,
-- qué respondió Claude, con qué fuentes y si le sirvió. Eso permite a
-- jefatura ver qué se pregunta, detectar vacíos del corpus y medir el costo.
--
--  1. Tabla copiloto_consultas (RLS: cada uno ve lo suyo; jefatura ve todo).
--  2. rpc_copiloto_feedback: el mecánico marca 👍/👎 sin poder tocar el resto
--     del registro (la consulta es auditoría, no se edita).
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS copiloto_consultas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL,
  activo_id     UUID REFERENCES activos(id),
  ot_id         UUID REFERENCES ordenes_trabajo(id),
  pregunta      TEXT NOT NULL,
  respuesta     TEXT,
  fuentes       JSONB NOT NULL DEFAULT '[]'::jsonb,   -- [{titulo, pagina, tipo}]
  con_foto      BOOLEAN NOT NULL DEFAULT FALSE,
  modelo        TEXT,                                  -- modelo de IA usado
  input_tokens  INT,
  output_tokens INT,
  duracion_ms   INT,
  feedback      TEXT CHECK (feedback IN ('util','no_util')),
  feedback_nota TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_copiloto_consultas_usuario ON copiloto_consultas (usuario_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_copiloto_consultas_activo  ON copiloto_consultas (activo_id) WHERE activo_id IS NOT NULL;

ALTER TABLE copiloto_consultas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS copiloto_consultas_select ON copiloto_consultas;
CREATE POLICY copiloto_consultas_select ON copiloto_consultas FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM usuarios_perfil up
                WHERE up.id = auth.uid()
                  AND up.rol IN ('administrador','gerencia','jefe_mantenimiento','planificador'))
  );

DROP POLICY IF EXISTS copiloto_consultas_insert ON copiloto_consultas;
CREATE POLICY copiloto_consultas_insert ON copiloto_consultas FOR INSERT
  WITH CHECK (usuario_id = auth.uid());

-- La respuesta la escribe el servidor (misma sesión del usuario via API):
-- update directo permitido SOLO sobre filas propias.
DROP POLICY IF EXISTS copiloto_consultas_update ON copiloto_consultas;
CREATE POLICY copiloto_consultas_update ON copiloto_consultas FOR UPDATE
  USING (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON copiloto_consultas TO authenticated;

-- ── Feedback del mecánico (👍/👎) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_copiloto_feedback(
    p_consulta_id UUID,
    p_feedback    TEXT,
    p_nota        TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_feedback NOT IN ('util','no_util') THEN
    RAISE EXCEPTION 'feedback debe ser util o no_util';
  END IF;
  UPDATE copiloto_consultas
     SET feedback = p_feedback,
         feedback_nota = COALESCE(p_nota, feedback_nota)
   WHERE id = p_consulta_id AND usuario_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Consulta no encontrada o no es tuya';
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION rpc_copiloto_feedback(UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_copiloto_feedback(UUID,TEXT,TEXT) TO authenticated;

COMMIT;

SELECT 'MIG542 aplicada' AS resultado,
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'copiloto_consultas') AS tabla_ok;
