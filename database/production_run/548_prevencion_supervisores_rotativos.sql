-- ============================================================================
-- MIG548 · Prevención: supervisores rotativos (una persona, varias faenas)
-- ============================================================================
-- Manuel (2026-09-14): «Lomas Bayas y Centinela son los supervisores de
-- Calama, los cuales no están en un lado fijo; la dotación puede variar en
-- ambos lados.»
--
-- El problema: rpc_prevencion_supervisores_faena (MIG547) esperaba a los
-- supervisores por usuarios_perfil.faena_id — una sola faena fija. Los de
-- Calama cubren Lomas Y Centinela según la semana, así que no aparecían como
-- «esperados» en ninguna y el monitoreo jamás los marcaría en rojo.
--
-- La solución: asignación explícita supervisor ↔ faenas de prevención
-- (muchos a muchos), editable desde el panel. El RPC ahora une:
--   · los de faena fija (usuarios_perfil.faena_id) — Romeral y Franke quedan
--     igual que hoy, sin tocar nada;
--   · los asignados en prevencion_supervisor_faenas — los rotativos.
--
-- La dotación variable NO necesita nada nuevo: prevencion_indicadores_mes ya
-- es por faena+mes; prevención digita la dotación/HH que efectivamente estuvo
-- en cada faena ese mes (así lo pide el E-200: por instalación).
--
-- Seed: los usuarios reales de Calama con rol de supervisión quedan asignados
-- a Lomas Bayas y Centinela (editable): supcalama@pillado.cl y
-- hcorey@pillado.cl. Los demás se agregan desde el panel (Monitoreo →
-- «Asignar supervisores»).
-- IDEMPOTENTE, ADITIVA.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. ASIGNACIÓN SUPERVISOR ↔ FAENA
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_supervisor_faenas (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id  UUID NOT NULL REFERENCES usuarios_perfil(id) ON DELETE CASCADE,
    faena_id    UUID NOT NULL REFERENCES faenas(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by  UUID REFERENCES auth.users(id),
    CONSTRAINT uq_prev_sup_faena UNIQUE (usuario_id, faena_id)
);

COMMENT ON TABLE prevencion_supervisor_faenas IS
    'Qué faenas cubre cada supervisor PARA EL MONITOREO de prevención (los rotativos de Calama cubren Lomas y Centinela a la vez). No restringe dónde puede cargar: solo define a quién se le cobra la carga del mes. MIG548.';

ALTER TABLE prevencion_supervisor_faenas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_sup_faenas_select ON prevencion_supervisor_faenas;
CREATE POLICY prev_sup_faenas_select ON prevencion_supervisor_faenas
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

DROP POLICY IF EXISTS prev_sup_faenas_admin ON prevencion_supervisor_faenas;
CREATE POLICY prev_sup_faenas_admin ON prevencion_supervisor_faenas
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, DELETE ON prevencion_supervisor_faenas TO authenticated;

-- ── Seed: supervisión real de Calama cubre Lomas Bayas y Centinela ──────────
INSERT INTO prevencion_supervisor_faenas (usuario_id, faena_id)
SELECT up.id, f.id
  FROM usuarios_perfil up
 CROSS JOIN faenas f
 WHERE up.email IN ('supcalama@pillado.cl', 'hcorey@pillado.cl')
   AND up.activo
   AND f.codigo IN ('FAE-LOMASBAYAS', 'FAE-CENTINELA')
ON CONFLICT (usuario_id, faena_id) DO NOTHING;

-- ############################################################################
-- 2. EL RPC DE «ESPERADOS» UNE FIJOS + ASIGNADOS
-- ############################################################################

CREATE OR REPLACE FUNCTION public.rpc_prevencion_supervisores_faena(p_faena_id UUID)
RETURNS TABLE (usuario_id UUID, nombre TEXT, email TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()) THEN
        RAISE EXCEPTION 'Sin permiso';
    END IF;
    IF NOT fn_prevencion_faena_visible(p_faena_id) THEN
        RAISE EXCEPTION 'Sin acceso a esta faena';
    END IF;
    RETURN QUERY
    SELECT DISTINCT up.id, up.nombre_completo::text, up.email::text
      FROM usuarios_perfil up
     WHERE up.activo
       AND up.rol IN ('supervisor','jefe_operaciones','jefe_mantenimiento')
       AND (
            up.faena_id = p_faena_id
            OR EXISTS (
                SELECT 1 FROM prevencion_supervisor_faenas sf
                 WHERE sf.usuario_id = up.id AND sf.faena_id = p_faena_id
            )
       )
     ORDER BY 2;
END $function$;

GRANT EXECUTE ON FUNCTION rpc_prevencion_supervisores_faena(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION rpc_prevencion_supervisores_faena(UUID) FROM anon;

-- ############################################################################
-- 3. CANDIDATOS ASIGNABLES (para el panel: lista con checkbox)
-- ############################################################################
-- Devuelve TODOS los usuarios activos con rol de supervisión, marcando si ya
-- están asignados a la faena (fijo o rotativo). Solo para quien administra.

CREATE OR REPLACE FUNCTION public.rpc_prevencion_supervisores_asignables(p_faena_id UUID)
RETURNS TABLE (
    usuario_id UUID, nombre TEXT, email TEXT, rol TEXT,
    faena_fija BOOLEAN, asignado BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT fn_prevencion_reporta_puede_admin() THEN
        RAISE EXCEPTION 'Solo prevención/jefatura asigna supervisores';
    END IF;
    RETURN QUERY
    SELECT up.id, up.nombre_completo::text, up.email::text, up.rol::text,
           (up.faena_id = p_faena_id) AS faena_fija,
           EXISTS (SELECT 1 FROM prevencion_supervisor_faenas sf
                    WHERE sf.usuario_id = up.id AND sf.faena_id = p_faena_id) AS asignado
      FROM usuarios_perfil up
     WHERE up.activo
       AND up.rol IN ('supervisor','jefe_operaciones','jefe_mantenimiento')
     ORDER BY 2;
END $function$;

GRANT EXECUTE ON FUNCTION rpc_prevencion_supervisores_asignables(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION rpc_prevencion_supervisores_asignables(UUID) FROM anon;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.codigo, COUNT(*) AS asignados
FROM prevencion_supervisor_faenas sf JOIN faenas f ON f.id = sf.faena_id
GROUP BY f.codigo ORDER BY f.codigo;
