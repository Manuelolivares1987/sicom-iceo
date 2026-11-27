-- ============================================================================
-- SICOM-ICEO | 734 — Copiloto Prevención Centinela
-- ============================================================================
-- 26-11-2026. Manuel: «quiero hacer un agente IA como mi copiloto, pero versión
-- prevención para Centinela». Usuarios: supervisores ENEX y prevencionista en
-- el teléfono, oficina en el computador. Lee los datos de prevención de SICOM
-- en SOLO LECTURA.
--
-- 1. rpc_sso_trabajador(texto): busca por nombre o RUT y entrega, por persona,
--    la habilitación de su grupo (fn_prevencion_requisitos_persona, la misma
--    regla del módulo de Prevención) y todos sus exámenes, licencias y cursos
--    con vencimiento y estado. Permiso: fn_prevencion_personal_puede_ver.
-- 2. copiloto_sso_consultas: auditoría de cada consulta (pregunta, respuesta,
--    fuentes, tokens, costo), como copiloto_consultas del taller (MIG542).
-- ADITIVA.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_sso_trabajador(p_texto TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_q TEXT := lower(btrim(coalesce(p_texto, '')));
    v_rut TEXT := regexp_replace(v_q, '[^0-9k]', '', 'g');
BEGIN
    IF NOT fn_prevencion_personal_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver el personal de prevención.' USING ERRCODE = '42501';
    END IF;
    IF length(v_q) < 3 THEN
        RETURN jsonb_build_object('personas', '[]'::jsonb, 'nota', 'Escriba al menos 3 letras del nombre o el RUT.');
    END IF;

    RETURN jsonb_build_object(
        'hoy', current_date,
        'personas', (
        SELECT coalesce(jsonb_agg(x ORDER BY x->>'nombre'), '[]'::jsonb) FROM (
            SELECT jsonb_build_object(
                'nombre', trim(p.nombres || ' ' || coalesce(p.apellidos, '')),
                'rut', p.rut,
                'cargo', p.cargo,
                'empresa', p.empresa,
                'faena', p.faena_codigo,
                'activo', p.activo,
                'requisitos_faena', req,
                'habilitado', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(req) e
                                           WHERE e->>'aplica_a' = 'todos' AND NOT (e->>'ok')::boolean),
                'habilitado_conductor', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(req) e
                                                     WHERE NOT (e->>'ok')::boolean),
                'documentos', (
                    SELECT coalesce(jsonb_agg(jsonb_build_object(
                               'tipo', t.nombre, 'categoria', t.categoria,
                               'aplica', e.aplica, 'motivo_no_aplica', e.motivo_no_aplica,
                               'emision', e.fecha_emision, 'vence', e.fecha_vencimiento,
                               'estado', CASE
                                   WHEN NOT e.aplica THEN 'no aplica'
                                   WHEN e.fecha_vencimiento IS NULL THEN 'sin fecha'
                                   WHEN e.fecha_vencimiento < current_date THEN 'VENCIDO'
                                   WHEN e.fecha_vencimiento < current_date + 30 THEN 'vence en menos de 30 días'
                                   ELSE 'vigente' END,
                               'bloqueante', e.observacion_bloqueante)
                             ORDER BY t.orden), '[]'::jsonb)
                      FROM prevencion_examenes e
                      JOIN prevencion_examen_tipos t ON t.codigo = e.tipo_codigo
                     WHERE e.personal_id = p.id)
            ) AS x
              FROM prevencion_personal p
              CROSS JOIN LATERAL fn_prevencion_requisitos_persona(p.id, true) req
             WHERE p.activo
               AND (lower(trim(p.nombres || ' ' || coalesce(p.apellidos, ''))) LIKE '%' || v_q || '%'
                    OR (length(v_rut) >= 6 AND regexp_replace(lower(p.rut), '[^0-9k]', '', 'g') LIKE v_rut || '%'))
             LIMIT 5) s)
    );
END $$;
REVOKE ALL ON FUNCTION rpc_sso_trabajador(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_sso_trabajador(TEXT) TO authenticated;

CREATE TABLE IF NOT EXISTS copiloto_sso_consultas (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    atajo        TEXT,                         -- 'art' | 'charla' | 'subir' | NULL (pregunta libre)
    pregunta     TEXT NOT NULL,
    respuesta    TEXT,
    fuentes      JSONB NOT NULL DEFAULT '[]',
    herramientas JSONB NOT NULL DEFAULT '[]',
    modelo       TEXT,
    tokens_in    INTEGER,
    tokens_out   INTEGER,
    costo_usd    NUMERIC(10,4),
    duracion_ms  INTEGER,
    error        TEXT,
    util         BOOLEAN,                      -- 👍/👎 del usuario
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_copiloto_sso_consultas_fecha ON copiloto_sso_consultas (created_at DESC);
ALTER TABLE copiloto_sso_consultas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS copiloto_sso_consultas_propias ON copiloto_sso_consultas;
CREATE POLICY copiloto_sso_consultas_propias ON copiloto_sso_consultas
    FOR SELECT TO authenticated
    USING (usuario_id = auth.uid() OR fn_user_rol() IN ('administrador', 'gerencia', 'subgerente_operaciones', 'prevencionista'));
DROP POLICY IF EXISTS copiloto_sso_consultas_insertar ON copiloto_sso_consultas;
CREATE POLICY copiloto_sso_consultas_insertar ON copiloto_sso_consultas
    FOR INSERT TO authenticated WITH CHECK (usuario_id = auth.uid());

-- 👍/👎 solo sobre la consulta propia.
CREATE OR REPLACE FUNCTION rpc_copiloto_sso_feedback(p_id UUID, p_util BOOLEAN)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    UPDATE copiloto_sso_consultas SET util = p_util WHERE id = p_id AND usuario_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION rpc_copiloto_sso_feedback(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_copiloto_sso_feedback(UUID, BOOLEAN) TO authenticated;

COMMIT;
