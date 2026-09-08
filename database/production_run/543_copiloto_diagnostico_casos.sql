-- ============================================================================
-- MIG543 · Copiloto: diagnóstico guiado + casos técnicos (el ciclo se cierra)
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (08-09-2026)
-- «Esta aplicación tiene que ir orientada a mejorar la capacidad de
-- diagnóstico del taller y de reparación. [...] Construye todo para que sea
-- de clase mundial y ayude a los mecánicos a mejorar su diagnóstico.»
--
-- EL PROBLEMA QUE RESUELVE
-- Hoy el copiloto responde y la conversación muere ahí: el diagnóstico no
-- queda registrado, y lo aprendido no se acumula. El equipo vuelve al taller
-- y el próximo mecánico parte de cero — exactamente la queja original del
-- camión 42.
--
-- QUÉ SE HACE
--  1. copiloto_diagnosticos: el diagnóstico como OBJETO — síntoma,
--     comprobaciones hechas (con resultado), causa raíz y reparación.
--     Nace desde la OT en /m/taller/copiloto y se resuelve ahí mismo.
--  2. Un caso RESUELTO se vuelve conocimiento consultable: FTS en español
--     sobre síntoma+causa+reparación, y rpc_copiloto_casos_similares lo
--     entrega para equipos del mismo modelo. La próxima falla eléctrica de
--     un GU813 parte por "así se resolvió la vez anterior".
--  3. copiloto_consultas.diagnostico_id: el chat queda amarrado al
--     diagnóstico que acompañó.
--  4. Todo el taller LEE todos los casos (así se aprende); escribe el autor
--     y jefatura.
-- ============================================================================

BEGIN;

-- Español sin tildes para buscar casos ("neumatico" encuentra "neumático")
CREATE EXTENSION IF NOT EXISTS unaccent;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_ts_config WHERE cfgname = 'es_unaccent') THEN
    CREATE TEXT SEARCH CONFIGURATION es_unaccent (COPY = spanish);
    ALTER TEXT SEARCH CONFIGURATION es_unaccent
      ALTER MAPPING FOR hword, hword_part, word WITH unaccent, spanish_stem;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS copiloto_diagnosticos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id          UUID REFERENCES ordenes_trabajo(id),
  activo_id      UUID NOT NULL REFERENCES activos(id),
  usuario_id     UUID NOT NULL,
  sintoma        TEXT NOT NULL,
  sistema        TEXT,                          -- electrico, transmision, frenos...
  estado         TEXT NOT NULL DEFAULT 'abierto'
                 CHECK (estado IN ('abierto','resuelto','descartado')),
  -- [{descripcion, resultado: 'ok'|'no_ok'|'valor', valor?, at, por}]
  comprobaciones JSONB NOT NULL DEFAULT '[]'::jsonb,
  causa_raiz     TEXT,
  reparacion     TEXT,
  resuelto_por   UUID,
  resuelto_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tsv            TSVECTOR GENERATED ALWAYS AS (to_tsvector('es_unaccent'::regconfig,
                   COALESCE(sintoma,'') || ' ' || COALESCE(causa_raiz,'') || ' ' ||
                   COALESCE(reparacion,'') || ' ' || COALESCE(sistema,''))) STORED
);

CREATE INDEX IF NOT EXISTS idx_copiloto_dx_activo ON copiloto_diagnosticos (activo_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_copiloto_dx_ot     ON copiloto_diagnosticos (ot_id) WHERE ot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_copiloto_dx_tsv    ON copiloto_diagnosticos USING GIN (tsv);

ALTER TABLE copiloto_consultas ADD COLUMN IF NOT EXISTS diagnostico_id UUID REFERENCES copiloto_diagnosticos(id);

ALTER TABLE copiloto_diagnosticos ENABLE ROW LEVEL SECURITY;

-- Leer: TODO el taller. Los casos resueltos son la biblioteca de experiencia
-- interna; esconderlos mataría el propósito.
DROP POLICY IF EXISTS copiloto_dx_select ON copiloto_diagnosticos;
CREATE POLICY copiloto_dx_select ON copiloto_diagnosticos FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS copiloto_dx_insert ON copiloto_diagnosticos;
CREATE POLICY copiloto_dx_insert ON copiloto_diagnosticos FOR INSERT
  WITH CHECK (usuario_id = auth.uid());

DROP POLICY IF EXISTS copiloto_dx_update ON copiloto_diagnosticos;
CREATE POLICY copiloto_dx_update ON copiloto_diagnosticos FOR UPDATE
  USING (usuario_id = auth.uid()
         OR EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                     AND up.rol IN ('administrador','gerencia','jefe_mantenimiento','planificador')));

GRANT SELECT, INSERT, UPDATE ON copiloto_diagnosticos TO authenticated;

-- ── Agregar comprobación (append atómico, sin pisar las de otro) ────────────
CREATE OR REPLACE FUNCTION rpc_diagnostico_comprobacion(
    p_diagnostico_id UUID,
    p_descripcion    TEXT,
    p_resultado      TEXT,          -- 'ok' | 'no_ok' | 'valor'
    p_valor          TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out JSONB;
BEGIN
  IF p_resultado NOT IN ('ok','no_ok','valor') THEN
    RAISE EXCEPTION 'resultado debe ser ok, no_ok o valor';
  END IF;
  IF LENGTH(TRIM(COALESCE(p_descripcion,''))) < 3 THEN
    RAISE EXCEPTION 'Describe qué comprobaste';
  END IF;
  UPDATE copiloto_diagnosticos
     SET comprobaciones = comprobaciones || jsonb_build_array(jsonb_build_object(
           'descripcion', TRIM(p_descripcion),
           'resultado', p_resultado,
           'valor', p_valor,
           'at', NOW(),
           'por', auth.uid()))
   WHERE id = p_diagnostico_id AND estado = 'abierto'
   RETURNING comprobaciones INTO v_out;
  IF v_out IS NULL THEN
    RAISE EXCEPTION 'Diagnóstico no encontrado o ya cerrado';
  END IF;
  RETURN v_out;
END $$;

-- ── Resolver: acá nace el caso técnico ──────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_diagnostico_resolver(
    p_diagnostico_id UUID,
    p_causa_raiz     TEXT,
    p_reparacion     TEXT,
    p_sistema        TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF LENGTH(TRIM(COALESCE(p_causa_raiz,''))) < 5 THEN
    RAISE EXCEPTION 'La causa raíz es lo que le sirve al próximo mecánico: descríbela';
  END IF;
  UPDATE copiloto_diagnosticos
     SET estado = 'resuelto',
         causa_raiz = TRIM(p_causa_raiz),
         reparacion = NULLIF(TRIM(COALESCE(p_reparacion,'')), ''),
         sistema = COALESCE(NULLIF(TRIM(COALESCE(p_sistema,'')),''), sistema),
         resuelto_por = auth.uid(),
         resuelto_at = NOW()
   WHERE id = p_diagnostico_id AND estado = 'abierto';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Diagnóstico no encontrado o ya cerrado';
  END IF;
END $$;

-- ── Casos similares: la experiencia interna del mismo modelo ────────────────
-- Prioriza el MISMO EQUIPO (recurrencia), luego el mismo modelo, luego FTS.
CREATE OR REPLACE FUNCTION rpc_copiloto_casos_similares(
    p_activo_id UUID,
    p_texto     TEXT,
    p_limit     INT DEFAULT 3)
RETURNS TABLE (
  id UUID, equipo TEXT, mismo_equipo BOOLEAN, sintoma TEXT, causa_raiz TEXT,
  reparacion TEXT, sistema TEXT, resuelto_at TIMESTAMPTZ, comprobaciones JSONB
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mi AS (SELECT modelo_id FROM activos WHERE id = p_activo_id)
  SELECT d.id,
         COALESCE(a.patente, a.codigo) AS equipo,
         d.activo_id = p_activo_id AS mismo_equipo,
         d.sintoma, d.causa_raiz, d.reparacion, d.sistema, d.resuelto_at,
         d.comprobaciones
    FROM copiloto_diagnosticos d
    JOIN activos a ON a.id = d.activo_id
   WHERE d.estado = 'resuelto'
     AND (d.activo_id = p_activo_id OR a.modelo_id = (SELECT modelo_id FROM mi))
   ORDER BY (d.activo_id = p_activo_id) DESC,
            CASE WHEN d.tsv @@ websearch_to_tsquery('es_unaccent', p_texto)
                 THEN ts_rank_cd(d.tsv, websearch_to_tsquery('es_unaccent', p_texto)) ELSE 0 END DESC,
            d.resuelto_at DESC
   LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION rpc_diagnostico_comprobacion(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION rpc_diagnostico_resolver(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_casos_similares(UUID,TEXT,INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_diagnostico_comprobacion(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_diagnostico_resolver(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_copiloto_casos_similares(UUID,TEXT,INT) TO authenticated;

COMMIT;

SELECT 'MIG543 aplicada' AS resultado,
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='copiloto_diagnosticos') AS tabla_ok,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_copiloto_casos_similares') AS rpc_ok;
