-- ============================================================================
-- SICOM-ICEO | 735 — Inicio Seguro en Terreno ENEX (Calama)
-- ============================================================================
-- 27-11-2026. Manuel: «si o si, antes de empezar los trabajos se saque una foto
-- a los bloqueos y de su visto bueno Hersaly, y además sea un apoyo para
-- realizar la ART». Decisiones:
--   · Aprueba SIEMPRE Hersaly (decisión de Manuel; se le advirtió que según el
--     Campus tiene pendiente el AULA Reglamento General de Aislación y Bloqueo).
--   · Sin visto bueno NO se inicia; a los 10 min sin respuesta se escala.
--   · v1 completa: cuadrilla habilitada + ART (asistida por el copiloto) +
--     PSGCC de las EDC que aplican + fotos de bloqueo y de energía cero +
--     visto bueno + «Detener tarea» + retiro de bloqueos al cierre.
-- Nace de la investigación CAP 576822 (18-11-2026): energía hidráulica no
-- bloqueada en sala de bombas.
--
-- Una fila por programación (servicio) y día de trabajo. Las fotos viven en
-- el bucket de evidencias; aquí van sus URL.
-- ADITIVA.
-- ============================================================================

BEGIN;

-- Quién aprueba (editable sin migración).
CREATE TABLE IF NOT EXISTS enex_inicio_seguro_config (
    id                  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    aprobadores         UUID[] NOT NULL,           -- usuarios_perfil.id
    minutos_escalamiento INTEGER NOT NULL DEFAULT 10,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO enex_inicio_seguro_config (aprobadores)
VALUES (ARRAY['6e6bfdfd-5920-4aa5-8f39-dd587f9d3450'::UUID])   -- Hersaly Corey
ON CONFLICT (id) DO NOTHING;
ALTER TABLE enex_inicio_seguro_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS enex_inicio_seguro_config_leer ON enex_inicio_seguro_config;
CREATE POLICY enex_inicio_seguro_config_leer ON enex_inicio_seguro_config FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS enex_inicio_seguro (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      UUID UNIQUE NOT NULL,          -- idempotencia desde el teléfono
    programacion_id  UUID NOT NULL REFERENCES enex_programaciones(id) ON DELETE CASCADE,
    fecha            DATE NOT NULL DEFAULT (now() AT TIME ZONE 'America/Santiago')::date,
    tarea            TEXT NOT NULL,
    cuadrilla        JSONB NOT NULL DEFAULT '[]',   -- [{personal_id, nombre, habilitado, pendientes[]}]
    art              JSONB NOT NULL DEFAULT '{}',   -- {texto, asistida, confirmada_por[]}
    psgcc            JSONB NOT NULL DEFAULT '[]',   -- [{edc, control, pregunta, respuesta}]
    bloqueos         JSONB NOT NULL DEFAULT '[]',   -- [{energia, punto, foto_bloqueo, foto_energia_cero}]
    sin_bloqueo_motivo TEXT,                        -- si la tarea no interviene energías
    estado           TEXT NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','aprobado','rechazado','detenido','cerrado')),
    solicitado_por   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    solicitado_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decidido_por     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    decidido_at      TIMESTAMPTZ,
    comentario       TEXT,
    avisado_at       TIMESTAMPTZ,                   -- correo de solicitud enviado
    escalado_at      TIMESTAMPTZ,                   -- correo de escalamiento enviado
    detenido_motivo  TEXT,
    detenido_por     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    detenido_at      TIMESTAMPTZ,
    retiro_bloqueos  JSONB NOT NULL DEFAULT '[]',   -- [{punto, foto_retiro}]
    cerrado_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE enex_inicio_seguro ADD COLUMN IF NOT EXISTS detencion_avisada_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_enex_inicio_seguro_prog ON enex_inicio_seguro (programacion_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_enex_inicio_seguro_pend ON enex_inicio_seguro (estado) WHERE estado = 'pendiente';
ALTER TABLE enex_inicio_seguro ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS enex_inicio_seguro_leer ON enex_inicio_seguro;
CREATE POLICY enex_inicio_seguro_leer ON enex_inicio_seguro FOR SELECT TO authenticated
    USING (fn_enex_puede_ejecutar() OR fn_prevencion_personal_puede_ver()
           OR EXISTS (SELECT 1 FROM enex_inicio_seguro_config c WHERE auth.uid() = ANY (c.aprobadores)));
-- Escritura solo por las RPC.

CREATE OR REPLACE FUNCTION fn_inicio_seguro_es_aprobador()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM enex_inicio_seguro_config c WHERE auth.uid() = ANY (c.aprobadores));
$$;
GRANT EXECUTE ON FUNCTION fn_inicio_seguro_es_aprobador() TO authenticated;

-- El teléfono envía la solicitud (idempotente por client_uuid). Reenviar la
-- misma solicitud no cambia una decisión ya tomada.
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_solicitar(p JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r enex_inicio_seguro;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso.' USING ERRCODE = '42501'; END IF;
    IF coalesce(btrim(p->>'tarea'), '') = '' THEN RAISE EXCEPTION 'Falta la descripción de la tarea.'; END IF;
    IF jsonb_array_length(coalesce(p->'bloqueos', '[]')) = 0 AND coalesce(btrim(p->>'sin_bloqueo_motivo'), '') = '' THEN
        RAISE EXCEPTION 'Faltan los bloqueos (con foto) o el motivo de por qué la tarea no interviene energías.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p->'psgcc', '[]')) x WHERE x->>'respuesta' = 'no') THEN
        RAISE EXCEPTION 'Hay un control crítico sin implementar: la tarea se detiene, no se pide visto bueno.';
    END IF;
    INSERT INTO enex_inicio_seguro (client_uuid, programacion_id, tarea, cuadrilla, art, psgcc, bloqueos,
                                    sin_bloqueo_motivo, solicitado_por)
    VALUES ((p->>'client_uuid')::UUID, (p->>'programacion_id')::UUID, btrim(p->>'tarea'),
            coalesce(p->'cuadrilla', '[]'), coalesce(p->'art', '{}'), coalesce(p->'psgcc', '[]'),
            coalesce(p->'bloqueos', '[]'), nullif(btrim(p->>'sin_bloqueo_motivo'), ''), auth.uid())
    ON CONFLICT (client_uuid) DO UPDATE SET client_uuid = EXCLUDED.client_uuid
    RETURNING * INTO r;
    RETURN to_jsonb(r);
END $$;

-- Estado para el teléfono que espera (y para retomar al reabrir el servicio).
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_estado(p_programacion_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT to_jsonb(i) || jsonb_build_object(
             'decidido_por_nombre', (SELECT nombre_completo FROM usuarios_perfil WHERE id = i.decidido_por),
             'minutos_escalamiento', (SELECT minutos_escalamiento FROM enex_inicio_seguro_config))
      FROM enex_inicio_seguro i
     WHERE i.programacion_id = p_programacion_id
       AND i.fecha = (now() AT TIME ZONE 'America/Santiago')::date
       AND (fn_enex_puede_ejecutar() OR fn_inicio_seguro_es_aprobador())
     ORDER BY i.solicitado_at DESC LIMIT 1;
$$;

-- Hersaly decide.
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_decidir(p_id UUID, p_aprobar BOOLEAN, p_comentario TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r enex_inicio_seguro;
BEGIN
    IF NOT fn_inicio_seguro_es_aprobador() THEN
        RAISE EXCEPTION 'Solo el aprobador designado puede dar el visto bueno.' USING ERRCODE = '42501';
    END IF;
    IF NOT p_aprobar AND coalesce(btrim(p_comentario), '') = '' THEN
        RAISE EXCEPTION 'Para rechazar, escriba qué hay que corregir.';
    END IF;
    UPDATE enex_inicio_seguro
       SET estado = CASE WHEN p_aprobar THEN 'aprobado' ELSE 'rechazado' END,
           decidido_por = auth.uid(), decidido_at = now(), comentario = nullif(btrim(p_comentario), '')
     WHERE id = p_id AND estado = 'pendiente'
    RETURNING * INTO r;
    IF r.id IS NULL THEN RAISE EXCEPTION 'Esta solicitud ya fue decidida o detenida.'; END IF;
    RETURN to_jsonb(r);
END $$;

-- Cualquiera de la cuadrilla detiene la tarea, en cualquier momento.
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_detener(p_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso.' USING ERRCODE = '42501'; END IF;
    IF coalesce(btrim(p_motivo), '') = '' THEN RAISE EXCEPTION 'Indique por qué se detiene.'; END IF;
    UPDATE enex_inicio_seguro
       SET estado = 'detenido', detenido_motivo = btrim(p_motivo), detenido_por = auth.uid(), detenido_at = now()
     WHERE id = p_id AND estado IN ('pendiente', 'aprobado');
END $$;

-- Cierre: retiro de bloqueos con foto.
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_cerrar(p_id UUID, p_retiro JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso.' USING ERRCODE = '42501'; END IF;
    UPDATE enex_inicio_seguro
       SET estado = 'cerrado', retiro_bloqueos = coalesce(p_retiro, '[]'), cerrado_at = now()
     WHERE id = p_id AND estado = 'aprobado';
END $$;

-- Correo: reclamar el aviso (una vez) y el escalamiento (una vez, tras N minutos).
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_reclamar_correo(p_id UUID, p_tipo TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INTEGER;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso.' USING ERRCODE = '42501'; END IF;
    IF p_tipo = 'solicitud' THEN
        UPDATE enex_inicio_seguro SET avisado_at = now() WHERE id = p_id AND avisado_at IS NULL AND estado = 'pendiente';
    ELSIF p_tipo = 'escalamiento' THEN
        UPDATE enex_inicio_seguro SET escalado_at = now()
         WHERE id = p_id AND escalado_at IS NULL AND estado = 'pendiente'
           AND solicitado_at < now() - make_interval(mins => (SELECT minutos_escalamiento FROM enex_inicio_seguro_config));
    ELSIF p_tipo = 'detencion' THEN
        UPDATE enex_inicio_seguro SET detencion_avisada_at = now()
         WHERE id = p_id AND detencion_avisada_at IS NULL AND estado = 'detenido';
    ELSE RAISE EXCEPTION 'Tipo inválido.';
    END IF;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n > 0;
END $$;

-- Bandeja del aprobador.
CREATE OR REPLACE FUNCTION rpc_inicio_seguro_bandeja()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT coalesce(jsonb_agg(x ORDER BY (x->>'estado') <> 'pendiente', x->>'solicitado_at' DESC), '[]') FROM (
        SELECT to_jsonb(i) || jsonb_build_object(
                 'instalacion', inst.nombre, 'faena', f.nombre, 'tipo_servicio', p.tipo_servicio,
                 'solicitado_por_nombre', (SELECT nombre_completo FROM usuarios_perfil WHERE id = i.solicitado_por)) AS x
          FROM enex_inicio_seguro i
          JOIN enex_programaciones p ON p.id = i.programacion_id
          LEFT JOIN enex_instalaciones inst ON inst.id = p.instalacion_id
          LEFT JOIN enex_faenas f ON f.id = inst.faena_id
         WHERE (fn_inicio_seguro_es_aprobador() OR fn_prevencion_personal_puede_ver())
           AND (i.estado = 'pendiente' OR i.solicitado_at > now() - interval '7 days')) s;
$$;

REVOKE ALL ON FUNCTION rpc_inicio_seguro_solicitar(JSONB), rpc_inicio_seguro_estado(UUID),
    rpc_inicio_seguro_decidir(UUID, BOOLEAN, TEXT), rpc_inicio_seguro_detener(UUID, TEXT),
    rpc_inicio_seguro_cerrar(UUID, JSONB), rpc_inicio_seguro_reclamar_correo(UUID, TEXT),
    rpc_inicio_seguro_bandeja() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_inicio_seguro_solicitar(JSONB), rpc_inicio_seguro_estado(UUID),
    rpc_inicio_seguro_decidir(UUID, BOOLEAN, TEXT), rpc_inicio_seguro_detener(UUID, TEXT),
    rpc_inicio_seguro_cerrar(UUID, JSONB), rpc_inicio_seguro_reclamar_correo(UUID, TEXT),
    rpc_inicio_seguro_bandeja() TO authenticated;

COMMIT;
