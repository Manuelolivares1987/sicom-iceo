-- ============================================================================
-- 13_validate_roles_dashboards_produccion.sql  —  Solo lectura.
-- ============================================================================

-- 1. Distribución de roles
SELECT rol, COUNT(*) AS cantidad
  FROM usuarios_perfil WHERE activo = true GROUP BY rol ORDER BY rol;

-- 2. Roles del enum sin perfil activo (informativo, no error)
WITH enum_roles AS (
    SELECT unnest(enum_range(NULL::rol_usuario_enum))::TEXT AS rol
), perfil_roles AS (
    SELECT DISTINCT rol::TEXT FROM usuarios_perfil WHERE activo = true
)
SELECT er.rol, (pr.rol IS NOT NULL) AS tiene_perfil_activo
  FROM enum_roles er
  LEFT JOIN perfil_roles pr ON pr.rol = er.rol
  ORDER BY er.rol;

-- 3. Usuarios críticos (Gustavo, Eduardo)
SELECT email, nombre_completo, rol, cargo, activo
  FROM usuarios_perfil
 WHERE email IN ('admin@pillado.cl','bodegacoq@pillado.cl','planificador@pillado.cl')
 ORDER BY email;

-- 4. Faenas asignadas
SELECT up.email, up.rol, f.codigo AS faena
  FROM usuarios_perfil up
  LEFT JOIN faenas f ON f.id = up.faena_id
 WHERE up.activo = true
 ORDER BY up.rol;

-- 5. Permisos críticos: tabla _roles_matriz_permisos
SELECT * FROM _roles_matriz_permisos ORDER BY rol;

-- 6. Eventos auditoría 7 días
SELECT tabla, accion, COUNT(*) AS eventos
  FROM auditoria_eventos
 WHERE created_at >= NOW() - INTERVAL '7 days'
 GROUP BY tabla, accion
 ORDER BY eventos DESC LIMIT 20;

-- 7. Resultado
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM usuarios_perfil
               WHERE email='admin@pillado.cl' AND activo=true) >= 1
         AND (SELECT COUNT(*) FROM usuarios_perfil
               WHERE email='bodegacoq@pillado.cl' AND activo=true) >= 1
         AND (SELECT COUNT(*) FROM usuarios_perfil
               WHERE email='planificador@pillado.cl' AND activo=true) >= 1
        THEN 'OK ROLES'
        ELSE 'WARNING — falta usuario clave del piloto'
    END AS resultado;

-- Log
SELECT fn_log_operacion_migracion('PROD_VALIDATE_ROLES', 'Validacion roles ejecutada.', 'ok', NULL);
