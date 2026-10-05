-- ============================================================================
-- MIG583 · Copiloto: conversaciones persistentes + solución definitiva
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (05-10-2026)
-- «necesito que mi copiloto se entrene y entienda las fallas, además que quede
-- un chat para el usuario en donde pueda retomar e indicar cuál fue la
-- solución definitiva, quiero que sea una herramienta útil».
--
-- LO QUE PASABA
-- El chat vivía solo en la memoria del teléfono: al cerrar la pantalla se
-- perdía. El ciclo de aprendizaje (MIG543) exigía entrar desde una OT y
-- llenar tres formularios; en un mes de uso real: 27 consultas, CERO
-- diagnósticos, CERO casos, CERO 👍/👎. El copiloto no aprendía nada.
--
-- QUÉ SE HACE
--  1. copiloto_conversaciones: el hilo como objeto (equipo, OT, caso, estado).
--     Cada consulta cuelga de una conversación; se puede retomar días después.
--  2. La solución definitiva: rpc_copiloto_solucion cierra la conversación y
--     crea/resuelve el caso técnico en UN paso (ya no hace falta la OT ni el
--     «diagnóstico guiado»). Si la falla vuelve, rpc_copiloto_reabrir deja la
--     reparación anterior como intento fallido: el próximo mecánico sabe qué
--     NO funcionó. Jefatura puede validar un caso (validado_por).
--  3. El copiloto registra solo lo que el mecánico informa: comprobaciones vía
--     herramienta (rpc_diagnostico_comprobacion ya existía) y una lección
--     destilada por IA (leccion) que entra al índice de búsqueda.
--  4. Búsqueda de casos v2: lexemas en OR (antes AND: una pregunta larga nunca
--     calzaba), toda la flota (no solo mismo modelo), ranking por equipo >
--     modelo > texto, casos sin equipo permitidos.
--  5. rpc_copiloto_historial_fallas: el copiloto busca por texto en el
--     historial REAL de OT y OS legacy del mismo modelo («se entera de las
--     fallas» de la flota, no solo del equipo abierto).
--  6. Relleno: las 27 consultas existentes se agrupan en conversaciones por
--     usuario/equipo/OT/día para que el historial no nazca vacío.
-- ============================================================================

BEGIN;

-- ── 1 · Conversaciones ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS copiloto_conversaciones (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id     UUID NOT NULL,
  activo_id      UUID REFERENCES activos(id),
  ot_id          UUID REFERENCES ordenes_trabajo(id),
  diagnostico_id UUID REFERENCES copiloto_diagnosticos(id),
  titulo         TEXT NOT NULL,
  estado         TEXT NOT NULL DEFAULT 'abierta'
                 CHECK (estado IN ('abierta','resuelta','descartada')),
  mensajes       INT  NOT NULL DEFAULT 0,
  ultimo_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- resuelta solo con caso técnico detrás
  CONSTRAINT chk_conv_resuelta_con_caso CHECK (estado <> 'resuelta' OR diagnostico_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_copiloto_conv_usuario ON copiloto_conversaciones (usuario_id, ultimo_at DESC);
CREATE INDEX IF NOT EXISTS idx_copiloto_conv_activo  ON copiloto_conversaciones (activo_id, ultimo_at DESC) WHERE activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_copiloto_conv_ot      ON copiloto_conversaciones (ot_id) WHERE ot_id IS NOT NULL;

ALTER TABLE copiloto_conversaciones ENABLE ROW LEVEL SECURITY;

-- Lee: el dueño y jefatura (misma lista que copiloto_consultas, MIG581)
DROP POLICY IF EXISTS copiloto_conv_select ON copiloto_conversaciones;
CREATE POLICY copiloto_conv_select ON copiloto_conversaciones FOR SELECT
  USING (usuario_id = auth.uid()
         OR EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                     AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                    'jefe_operaciones','jefe_mantenimiento','planificador')));
DROP POLICY IF EXISTS copiloto_conv_insert ON copiloto_conversaciones;
CREATE POLICY copiloto_conv_insert ON copiloto_conversaciones FOR INSERT
  WITH CHECK (usuario_id = auth.uid());
-- Actualiza: el dueño (título, descartar) y jefatura
DROP POLICY IF EXISTS copiloto_conv_update ON copiloto_conversaciones;
CREATE POLICY copiloto_conv_update ON copiloto_conversaciones FOR UPDATE
  USING (usuario_id = auth.uid()
         OR EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                     AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                    'jefe_operaciones','jefe_mantenimiento','planificador')));
GRANT SELECT, INSERT, UPDATE ON copiloto_conversaciones TO authenticated;

-- ── 2 · Consultas: cuelgan de la conversación y guardan todo lo que mostró ──
ALTER TABLE copiloto_consultas ADD COLUMN IF NOT EXISTS conversacion_id UUID REFERENCES copiloto_conversaciones(id);
ALTER TABLE copiloto_consultas ADD COLUMN IF NOT EXISTS codigos  JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE copiloto_consultas ADD COLUMN IF NOT EXISTS adjuntos JSONB NOT NULL DEFAULT '[]'::jsonb;
CREATE INDEX IF NOT EXISTS idx_copiloto_consultas_conv ON copiloto_consultas (conversacion_id, created_at) WHERE conversacion_id IS NOT NULL;

-- Quien lee la conversación lee sus mensajes (jefatura puede entrar a ayudar
-- en el hilo de un mecánico y el mecánico ve esa respuesta).
DROP POLICY IF EXISTS copiloto_consultas_select ON copiloto_consultas;
CREATE POLICY copiloto_consultas_select ON copiloto_consultas FOR SELECT
  USING (
    usuario_id = auth.uid()
    OR EXISTS (SELECT 1 FROM copiloto_conversaciones cv WHERE cv.id = conversacion_id AND cv.usuario_id = auth.uid())
    OR EXISTS (SELECT 1 FROM usuarios_perfil up
                WHERE up.id = auth.uid()
                  AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                 'jefe_operaciones','jefe_mantenimiento','planificador'))
  );

-- Contador y «última actividad» de la conversación
CREATE OR REPLACE FUNCTION fn_copiloto_consulta_toca_conversacion()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.conversacion_id IS NOT NULL THEN
    UPDATE copiloto_conversaciones
       SET mensajes = mensajes + 1, ultimo_at = NOW()
     WHERE id = NEW.conversacion_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_copiloto_consulta_conv ON copiloto_consultas;
CREATE TRIGGER trg_copiloto_consulta_conv AFTER INSERT ON copiloto_consultas
  FOR EACH ROW EXECUTE FUNCTION fn_copiloto_consulta_toca_conversacion();

-- ── 3 · Casos técnicos: sin OT, con lección, validación y reaperturas ───────
ALTER TABLE copiloto_diagnosticos ALTER COLUMN activo_id DROP NOT NULL;
ALTER TABLE copiloto_diagnosticos ADD COLUMN IF NOT EXISTS leccion      TEXT;
ALTER TABLE copiloto_diagnosticos ADD COLUMN IF NOT EXISTS validado_por UUID;
ALTER TABLE copiloto_diagnosticos ADD COLUMN IF NOT EXISTS validado_at  TIMESTAMPTZ;
ALTER TABLE copiloto_diagnosticos ADD COLUMN IF NOT EXISTS reaperturas  INT NOT NULL DEFAULT 0;

-- La lección entra al índice: se regenera la columna (es GENERATED)
ALTER TABLE copiloto_diagnosticos DROP COLUMN IF EXISTS tsv;
ALTER TABLE copiloto_diagnosticos ADD COLUMN tsv TSVECTOR GENERATED ALWAYS AS (
  to_tsvector('es_unaccent'::regconfig,
    COALESCE(sintoma,'') || ' ' || COALESCE(causa_raiz,'') || ' ' ||
    COALESCE(reparacion,'') || ' ' || COALESCE(sistema,'') || ' ' || COALESCE(leccion,''))) STORED;
CREATE INDEX IF NOT EXISTS idx_copiloto_dx_tsv ON copiloto_diagnosticos USING GIN (tsv);

-- Insertar casos sin equipo (consulta general) sigue exigiendo ser el autor
DROP POLICY IF EXISTS copiloto_dx_insert ON copiloto_diagnosticos;
CREATE POLICY copiloto_dx_insert ON copiloto_diagnosticos FOR INSERT
  WITH CHECK (usuario_id = auth.uid());

-- ── 5 · Casos similares v2: toda la flota, ranking por cercanía ─────────────
DROP FUNCTION IF EXISTS rpc_copiloto_casos_similares(UUID, TEXT, INT);
CREATE FUNCTION rpc_copiloto_casos_similares(
    p_activo_id UUID,
    p_texto     TEXT,
    p_limit     INT DEFAULT 3)
RETURNS TABLE (
  id UUID, equipo TEXT, mismo_equipo BOOLEAN, sintoma TEXT, causa_raiz TEXT,
  reparacion TEXT, sistema TEXT, resuelto_at TIMESTAMPTZ, comprobaciones JSONB,
  mismo_modelo BOOLEAN, modelo TEXT, leccion TEXT, validado BOOLEAN, reaperturas INT, coincidencias INT
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mi AS (
    SELECT a.modelo_id FROM activos a WHERE a.id = p_activo_id
  ), lex AS (
    SELECT DISTINCT l FROM unnest(tsvector_to_array(to_tsvector('es_unaccent', COALESCE(p_texto,'')))) AS l
  ), n_lex AS (SELECT count(*) AS n FROM lex),
  base AS (
    SELECT d.id, COALESCE(a.patente, a.codigo, 'consulta general') AS equipo,
           (p_activo_id IS NOT NULL AND d.activo_id = p_activo_id) AS mismo_equipo,
           d.sintoma, d.causa_raiz, d.reparacion, d.sistema, d.resuelto_at, d.comprobaciones,
           (a.modelo_id IS NOT NULL AND a.modelo_id = (SELECT modelo_id FROM mi)) AS mismo_modelo,
           TRIM(COALESCE(ma.nombre,'') || ' ' || COALESCE(mo.nombre,'')) AS modelo,
           d.leccion, (d.validado_at IS NOT NULL) AS validado, d.reaperturas,
           (SELECT count(*)::int FROM lex WHERE d.tsv @@ to_tsquery('simple', quote_literal(lex.l))) AS coincidencias
      FROM copiloto_diagnosticos d
      LEFT JOIN activos a ON a.id = d.activo_id
      LEFT JOIN modelos mo ON mo.id = a.modelo_id
      LEFT JOIN marcas  ma ON ma.id = mo.marca_id
     WHERE d.estado = 'resuelto'
       AND COALESCE(a.es_prueba, false) = false
  )
  SELECT b.id, b.equipo, b.mismo_equipo, b.sintoma, b.causa_raiz, b.reparacion, b.sistema,
         b.resuelto_at, b.comprobaciones, b.mismo_modelo, b.modelo, b.leccion, b.validado,
         b.reaperturas, b.coincidencias
    FROM base b, n_lex
   -- calza el texto (≥2 lexemas, o todos si la pregunta es muy corta) o es del
   -- mismo equipo/modelo
   WHERE (b.coincidencias >= LEAST(2, n_lex.n) AND n_lex.n > 0)
      OR b.mismo_equipo OR b.mismo_modelo
   ORDER BY
     CASE WHEN b.coincidencias >= LEAST(2, n_lex.n) AND n_lex.n > 0 AND b.mismo_equipo THEN 0
          WHEN b.coincidencias >= LEAST(2, n_lex.n) AND n_lex.n > 0 AND b.mismo_modelo THEN 1
          WHEN b.mismo_equipo THEN 2
          WHEN b.coincidencias >= LEAST(2, n_lex.n) AND n_lex.n > 0 THEN 3
          ELSE 4 END,
     b.coincidencias DESC, b.validado DESC, b.resuelto_at DESC
   LIMIT p_limit;
$$;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_casos_similares(UUID,TEXT,INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION rpc_copiloto_casos_similares(UUID,TEXT,INT) TO authenticated;

-- ── 6 · Historial de fallas de la flota (OT + OS legacy del mismo modelo) ───
-- Solo lo ejecutado (trabajo realizado / detalle), sin costos. SECURITY
-- DEFINER porque el operador de taller solo ve sus OT por RLS, y acá lo que
-- importa es «qué le pasó a los otros camiones iguales».
CREATE OR REPLACE FUNCTION rpc_copiloto_historial_fallas(
    p_activo_id UUID,
    p_texto     TEXT,
    p_limit     INT DEFAULT 8)
RETURNS TABLE (
  equipo TEXT, mismo_equipo BOOLEAN, fecha DATE, origen TEXT, folio TEXT, tipo TEXT,
  motivo TEXT, trabajo TEXT, coincidencias INT
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mi AS (SELECT a.modelo_id FROM activos a WHERE a.id = p_activo_id),
  lex AS (
    SELECT DISTINCT l FROM unnest(tsvector_to_array(to_tsvector('es_unaccent', COALESCE(p_texto,'')))) AS l
  ), n_lex AS (SELECT count(*) AS n FROM lex),
  filas AS (
    SELECT o.activo_id, COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio)::date AS fecha,
           'ot'::text AS origen, o.folio::text AS folio, o.tipo::text AS tipo,
           NULLIF(o.observaciones,'') AS motivo, o.trabajo_realizado AS trabajo
      FROM ordenes_trabajo o
      JOIN activos a ON a.id = o.activo_id
     WHERE (o.activo_id = p_activo_id OR a.modelo_id = (SELECT modelo_id FROM mi))
       AND o.estado::text IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
    UNION ALL
    SELECT h.activo_id, h.fecha_recepcion, 'os_legacy', 'OS ' || COALESCE(h.os_cqbo, h.os_numero, ''),
           CASE WHEN h.flag_correctivo THEN 'correctivo' ELSE 'servicio' END,
           NULLIF(h.observacion,''), h.detalle_trabajos
      FROM historial_os_legacy h
      JOIN activos a ON a.id = h.activo_id
     WHERE (h.activo_id = p_activo_id OR a.modelo_id = (SELECT modelo_id FROM mi))
  ), puntuadas AS (
    SELECT f.*, to_tsvector('es_unaccent', COALESCE(f.motivo,'') || ' ' || COALESCE(f.trabajo,'')) AS tsv
      FROM filas f
     WHERE COALESCE(f.motivo, f.trabajo) IS NOT NULL
  )
  , con_puntaje AS (
    SELECT COALESCE(a.patente, a.codigo) AS equipo, (p.activo_id = p_activo_id) AS mismo_equipo,
           p.fecha, p.origen, p.folio, p.tipo,
           left(p.motivo, 300) AS motivo, left(p.trabajo, 600) AS trabajo,
           (SELECT count(*)::int FROM lex WHERE p.tsv @@ to_tsquery('simple', quote_literal(lex.l))) AS coincidencias
      FROM puntuadas p
      JOIN activos a ON a.id = p.activo_id
     WHERE COALESCE(a.es_prueba, false) = false
  )
  SELECT c.equipo, c.mismo_equipo, c.fecha, c.origen, c.folio, c.tipo, c.motivo, c.trabajo, c.coincidencias
    FROM con_puntaje c, n_lex
   WHERE n_lex.n > 0 AND c.coincidencias >= LEAST(2, n_lex.n)
   ORDER BY c.mismo_equipo DESC, c.coincidencias DESC, c.fecha DESC
   LIMIT p_limit;
$$;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_historial_fallas(UUID,TEXT,INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION rpc_copiloto_historial_fallas(UUID,TEXT,INT) TO authenticated;

-- ── 7 · La solución definitiva, en un paso ──────────────────────────────────
-- Crea el caso si la conversación no tenía (sin OT), lo resuelve y cierra la
-- conversación. Si el caso ya estaba resuelto, corrige causa/reparación.
CREATE OR REPLACE FUNCTION rpc_copiloto_solucion(
    p_conversacion_id UUID,
    p_causa_raiz      TEXT,
    p_reparacion      TEXT,
    p_sistema         TEXT DEFAULT NULL,
    p_sintoma         TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_conv copiloto_conversaciones%ROWTYPE;
  v_dx   UUID;
  v_jefatura BOOLEAN;
BEGIN
  IF LENGTH(TRIM(COALESCE(p_causa_raiz,''))) < 5 THEN
    RAISE EXCEPTION 'Describe la causa raíz: es lo que le sirve al próximo mecánico';
  END IF;
  IF LENGTH(TRIM(COALESCE(p_reparacion,''))) < 5 THEN
    RAISE EXCEPTION 'Describe la solución definitiva (qué se hizo para que no vuelva)';
  END IF;
  SELECT * INTO v_conv FROM copiloto_conversaciones WHERE id = p_conversacion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Conversación no encontrada'; END IF;
  SELECT EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                   AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                  'jefe_operaciones','jefe_mantenimiento','planificador'))
    INTO v_jefatura;
  IF v_conv.usuario_id <> auth.uid() AND NOT v_jefatura THEN
    RAISE EXCEPTION 'Solo quien abrió la conversación o jefatura puede cerrarla';
  END IF;

  v_dx := v_conv.diagnostico_id;
  -- Caso abierto de la misma OT (flujo «diagnóstico guiado» de MIG543)
  IF v_dx IS NULL AND v_conv.ot_id IS NOT NULL THEN
    SELECT d.id INTO v_dx FROM copiloto_diagnosticos d
     WHERE d.ot_id = v_conv.ot_id AND d.estado = 'abierto'
     ORDER BY d.created_at DESC LIMIT 1;
  END IF;
  IF v_dx IS NULL THEN
    INSERT INTO copiloto_diagnosticos (ot_id, activo_id, usuario_id, sintoma, sistema)
    VALUES (v_conv.ot_id, v_conv.activo_id, v_conv.usuario_id,
            COALESCE(NULLIF(TRIM(COALESCE(p_sintoma,'')),''), v_conv.titulo),
            NULLIF(TRIM(COALESCE(p_sistema,'')),''))
    RETURNING id INTO v_dx;
  END IF;

  UPDATE copiloto_diagnosticos
     SET estado       = 'resuelto',
         causa_raiz   = TRIM(p_causa_raiz),
         reparacion   = TRIM(p_reparacion),
         sistema      = COALESCE(NULLIF(TRIM(COALESCE(p_sistema,'')),''), sistema),
         sintoma      = COALESCE(NULLIF(TRIM(COALESCE(p_sintoma,'')),''), sintoma),
         resuelto_por = auth.uid(),
         resuelto_at  = NOW(),
         -- una corrección posterior invalida la lección y la validación anteriores
         leccion      = CASE WHEN estado = 'resuelto' THEN NULL ELSE leccion END,
         validado_por = CASE WHEN estado = 'resuelto' THEN NULL ELSE validado_por END,
         validado_at  = CASE WHEN estado = 'resuelto' THEN NULL ELSE validado_at END
   WHERE id = v_dx;

  UPDATE copiloto_conversaciones
     SET estado = 'resuelta', diagnostico_id = v_dx, ultimo_at = NOW()
   WHERE id = p_conversacion_id;
  RETURN v_dx;
END $$;

-- La falla volvió: la reparación anterior queda como intento fallido
CREATE OR REPLACE FUNCTION rpc_copiloto_reabrir(
    p_conversacion_id UUID,
    p_motivo          TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_conv copiloto_conversaciones%ROWTYPE;
  v_dx   copiloto_diagnosticos%ROWTYPE;
  v_jefatura BOOLEAN;
BEGIN
  SELECT * INTO v_conv FROM copiloto_conversaciones WHERE id = p_conversacion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Conversación no encontrada'; END IF;
  SELECT EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                   AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                  'jefe_operaciones','jefe_mantenimiento','planificador'))
    INTO v_jefatura;
  IF v_conv.usuario_id <> auth.uid() AND NOT v_jefatura THEN
    RAISE EXCEPTION 'Solo quien abrió la conversación o jefatura puede reabrirla';
  END IF;
  IF v_conv.diagnostico_id IS NOT NULL THEN
    SELECT * INTO v_dx FROM copiloto_diagnosticos WHERE id = v_conv.diagnostico_id FOR UPDATE;
    IF v_dx.estado = 'resuelto' THEN
      UPDATE copiloto_diagnosticos
         SET estado = 'abierto',
             comprobaciones = comprobaciones || jsonb_build_array(jsonb_build_object(
               'descripcion', 'Reparación anterior NO resolvió la falla: ' || COALESCE(v_dx.reparacion,'—')
                              || ' (causa supuesta: ' || COALESCE(v_dx.causa_raiz,'—') || ')',
               'resultado', 'no_ok',
               'valor', NULLIF(TRIM(COALESCE(p_motivo,'')),''),
               'tipo', 'reparacion_fallida',
               'at', NOW(), 'por', auth.uid())),
             causa_raiz = NULL, reparacion = NULL, leccion = NULL,
             resuelto_por = NULL, resuelto_at = NULL,
             validado_por = NULL, validado_at = NULL,
             reaperturas = reaperturas + 1
       WHERE id = v_dx.id;
    END IF;
  END IF;
  UPDATE copiloto_conversaciones SET estado = 'abierta', ultimo_at = NOW() WHERE id = p_conversacion_id;
END $$;

-- Lección destilada por IA (la escribe el servidor tras resolver, con el
-- token del usuario): solo quien resolvió o jefatura.
CREATE OR REPLACE FUNCTION rpc_copiloto_caso_leccion(p_diagnostico_id UUID, p_leccion TEXT, p_sistema TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE copiloto_diagnosticos
     SET leccion = NULLIF(LEFT(TRIM(COALESCE(p_leccion,'')), 2000), ''),
         sistema = COALESCE(sistema, NULLIF(TRIM(COALESCE(p_sistema,'')),''))
   WHERE id = p_diagnostico_id AND estado = 'resuelto'
     AND (resuelto_por = auth.uid() OR usuario_id = auth.uid()
          OR EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                       AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                      'jefe_operaciones','jefe_mantenimiento','planificador')));
  IF NOT FOUND THEN RAISE EXCEPTION 'Caso no encontrado o sin permiso'; END IF;
END $$;

-- Jefatura valida (o quita la validación) un caso
CREATE OR REPLACE FUNCTION rpc_copiloto_caso_validar(p_diagnostico_id UUID, p_validado BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM usuarios_perfil up WHERE up.id = auth.uid()
                   AND up.rol IN ('administrador','gerencia','subgerente_operaciones',
                                  'jefe_operaciones','jefe_mantenimiento','planificador')) THEN
    RAISE EXCEPTION 'Solo jefatura valida casos';
  END IF;
  UPDATE copiloto_diagnosticos
     SET validado_por = CASE WHEN p_validado THEN auth.uid() ELSE NULL END,
         validado_at  = CASE WHEN p_validado THEN NOW() ELSE NULL END
   WHERE id = p_diagnostico_id AND estado = 'resuelto';
  IF NOT FOUND THEN RAISE EXCEPTION 'Caso no encontrado o no está resuelto'; END IF;
END $$;

REVOKE EXECUTE ON FUNCTION rpc_copiloto_solucion(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_reabrir(UUID,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_caso_leccion(UUID,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION rpc_copiloto_caso_validar(UUID,BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_copiloto_solucion(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_copiloto_reabrir(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_copiloto_caso_leccion(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_copiloto_caso_validar(UUID,BOOLEAN) TO authenticated;

-- ── 8 · Relleno: consultas existentes → conversaciones por usuario/equipo/OT/día
CREATE TEMP TABLE _conv_relleno ON COMMIT DROP AS
SELECT gen_random_uuid() AS conv_id, usuario_id, activo_id, ot_id, diagnostico_id,
       (created_at AT TIME ZONE 'America/Santiago')::date AS dia,
       min(created_at) AS desde, max(created_at) AS hasta, count(*)::int AS n,
       (array_agg(pregunta ORDER BY created_at))[1] AS primera
  FROM copiloto_consultas
 WHERE conversacion_id IS NULL
 GROUP BY usuario_id, activo_id, ot_id, diagnostico_id, (created_at AT TIME ZONE 'America/Santiago')::date;

INSERT INTO copiloto_conversaciones (id, usuario_id, activo_id, ot_id, diagnostico_id, titulo, estado, mensajes, ultimo_at, created_at)
SELECT r.conv_id, r.usuario_id, r.activo_id, r.ot_id, r.diagnostico_id,
       LEFT(regexp_replace(r.primera, '\s+', ' ', 'g'), 90),
       CASE WHEN d.estado = 'resuelto' THEN 'resuelta' ELSE 'abierta' END,
       r.n, r.hasta, r.desde
  FROM _conv_relleno r
  LEFT JOIN copiloto_diagnosticos d ON d.id = r.diagnostico_id;

UPDATE copiloto_consultas c
   SET conversacion_id = r.conv_id
  FROM _conv_relleno r
 WHERE c.conversacion_id IS NULL
   AND c.usuario_id = r.usuario_id
   AND c.activo_id IS NOT DISTINCT FROM r.activo_id
   AND c.ot_id IS NOT DISTINCT FROM r.ot_id
   AND c.diagnostico_id IS NOT DISTINCT FROM r.diagnostico_id
   AND (c.created_at AT TIME ZONE 'America/Santiago')::date = r.dia;

COMMIT;

SELECT 'MIG583 aplicada' AS resultado,
       (SELECT count(*) FROM copiloto_conversaciones) AS conversaciones,
       (SELECT count(*) FROM copiloto_consultas WHERE conversacion_id IS NULL) AS consultas_sueltas,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_copiloto_solucion') AS rpc_solucion_ok,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_copiloto_historial_fallas') AS rpc_historial_ok;
