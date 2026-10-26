-- 656 — Permisos extra por persona: operaciones Calama gestiona su flota (2026-10-26).
--
-- Manuel: «quiero que operaciones Calama pueda ver todo lo de Calama, además
-- del control documental, las mantenciones preventivas de flota y los equipos,
-- para hacer gestión completa de Calama». Decidió: jefaturas + supervisores,
-- solo equipos de Calama (filtro de pantalla), ver y editar.
--
-- Los permisos son por ROL (MIG126). Subir el rol «supervisor» a editar
-- equipos y mantenimiento se lo daría también a los supervisores de Coquimbo.
-- Por eso: usuario_permisos_extra, que SUMA acciones a una persona sobre un
-- módulo (nunca quita). fn_tiene_permiso_modulo la consulta antes del rol, así
-- que todo RPC que ya valida por módulo (registrar preventiva, cambiar la
-- próxima, programa de servicio, ficha y QR del equipo) la respeta sin tocarlo.
--
-- Jefe de Operaciones Calama y Hersaly Corey (jefe_operaciones) ya tienen todo
-- por su rol. Se les da el extra a Supervisor Calama y Supervisor Operación
-- Calama.

CREATE TABLE IF NOT EXISTS usuario_permisos_extra (
    usuario_id UUID NOT NULL REFERENCES usuarios_perfil(id) ON DELETE CASCADE,
    modulo     TEXT NOT NULL,
    permisos   TEXT[] NOT NULL CHECK (permisos <@ ARRAY['view','create','edit','delete','approve','export']::text[]),
    motivo     TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (usuario_id, modulo)
);
ALTER TABLE usuario_permisos_extra ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_permisos_extra_sel ON usuario_permisos_extra;
CREATE POLICY pol_permisos_extra_sel ON usuario_permisos_extra FOR SELECT
    USING (usuario_id = auth.uid() OR fn_user_rol() = 'administrador');
-- Escritura solo por SQL/administrador (no hay pantalla todavía).
DROP POLICY IF EXISTS pol_permisos_extra_adm ON usuario_permisos_extra;
CREATE POLICY pol_permisos_extra_adm ON usuario_permisos_extra FOR ALL
    USING (fn_user_rol() = 'administrador') WITH CHECK (fn_user_rol() = 'administrador');
GRANT SELECT ON usuario_permisos_extra TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_tiene_permiso_modulo(p_modulo text, p_accion text, p_roles_default text[] DEFAULT '{}'::text[])
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rol      TEXT;
    v_permisos TEXT[];
BEGIN
    -- Fail-closed: acción o módulo desconocidos ⇒ denegar (no depender de que el
    -- caller pase valores válidos). Acciones canónicas = las de MIG126.
    IF p_accion IS NULL OR p_accion NOT IN ('view','create','edit','delete','approve','export') THEN
        RETURN false;
    END IF;
    IF p_modulo IS NULL OR length(trim(p_modulo)) = 0 THEN
        RETURN false;
    END IF;
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    -- Bloqueo PERMANENTE del portal cliente (regla, no accidente de datos):
    -- un usuario asociado al portal NUNCA autoriza acciones internas, aun si
    -- tuviera además fila en usuarios_perfil (perfil dual ⇒ denegado por defecto).
    IF EXISTS (
        SELECT 1 FROM public.cliente_portal_perfil cpp
         WHERE cpp.user_id = auth.uid() AND cpp.activo
    ) THEN
        RETURN false;
    END IF;
    v_rol := public.fn_user_rol();   -- NULL si no hay perfil o usuario inactivo ⇒ deniega
    IF v_rol IS NULL THEN
        RETURN false;
    END IF;
    -- Anti-lockout: mismo criterio que MIG126 (administrador no es degradable).
    IF v_rol = 'administrador' THEN
        RETURN true;
    END IF;
    -- [MIG656] Permiso extra de la persona: suma, nunca quita.
    IF EXISTS (SELECT 1 FROM public.usuario_permisos_extra x
                WHERE x.usuario_id = auth.uid() AND x.modulo = p_modulo AND p_accion = ANY(x.permisos)) THEN
        RETURN true;
    END IF;
    -- Override configurado en Admin (rol_permisos_modulo) manda sobre el default.
    SELECT permisos INTO v_permisos
      FROM public.rol_permisos_modulo
     WHERE rol = v_rol AND modulo = p_modulo;
    IF FOUND THEN
        RETURN p_accion = ANY(v_permisos);   -- override negativo también deniega
    END IF;
    RETURN v_rol = ANY(p_roles_default);
END $function$;

INSERT INTO usuario_permisos_extra (usuario_id, modulo, permisos, motivo)
SELECT u.id, m.modulo, ARRAY['view','create','edit'], 'Operaciones Calama gestiona su flota (Manuel 26-10-2026)'
  FROM usuarios_perfil u
 CROSS JOIN (VALUES ('activos'), ('flota'), ('mantenimiento'), ('ordenes_trabajo')) m(modulo)
 WHERE u.email IN ('supcalama@pillado.cl', 'supervisor.pc@sicom-iceo.cl') AND u.activo
ON CONFLICT (usuario_id, modulo) DO UPDATE SET permisos = EXCLUDED.permisos, motivo = EXCLUDED.motivo;

SELECT json_agg(json_build_object('usuario', u.email, 'modulo', x.modulo, 'permisos', x.permisos)) AS resultado
  FROM usuario_permisos_extra x JOIN usuarios_perfil u ON u.id = x.usuario_id;
