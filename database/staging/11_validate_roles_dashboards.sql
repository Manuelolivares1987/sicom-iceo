-- ============================================================================
-- 11_validate_roles_dashboards.sql  —  Validar usuarios/roles para piloto.
-- Solo lectura. Cero riesgo.
-- ============================================================================


-- ── 1. Distribucion de roles ─────────────────────────────────────────

SELECT rol, COUNT(*) AS cantidad
  FROM usuarios_perfil
 WHERE activo = true
 GROUP BY rol
 ORDER BY rol;


-- ── 2. Roles del enum vs perfiles activos ────────────────────────────

WITH enum_roles AS (
    SELECT unnest(enum_range(NULL::rol_usuario_enum))::TEXT AS rol
),
perfil_roles AS (
    SELECT DISTINCT rol::TEXT FROM usuarios_perfil WHERE activo = true
)
SELECT
    er.rol,
    (pr.rol IS NOT NULL) AS tiene_perfil_activo
  FROM enum_roles er
  LEFT JOIN perfil_roles pr ON pr.rol = er.rol
 ORDER BY er.rol;


-- ── 3. Usuarios criticos del piloto ──────────────────────────────────

SELECT
    email,
    nombre_completo,
    rol,
    cargo,
    activo
  FROM usuarios_perfil
 WHERE email IN (
    'admin@pillado.cl',
    'bodegacoq@pillado.cl',
    'planificador@pillado.cl'
 )
 ORDER BY email;


-- ── 4. Faenas asignadas a perfiles ───────────────────────────────────

SELECT
    up.email,
    up.rol,
    f.codigo AS faena_codigo,
    f.nombre AS faena_nombre
  FROM usuarios_perfil up
  LEFT JOIN faenas f ON f.id = up.faena_id
 WHERE up.activo = true
 ORDER BY up.rol;


-- ── 5. Permisos por rol — sanity check (matriz informativa) ──────────
-- (La matriz real esta en frontend/src/hooks/use-permissions.ts.
--  Esta query solo lista roles del enum y la tabla _roles_matriz_permisos
--  poblada por mig 31, que es documental.)

SELECT * FROM _roles_matriz_permisos ORDER BY rol;


-- ── 6. Eventos de auditoria recientes ────────────────────────────────

SELECT
    tabla, accion, COUNT(*) AS eventos
  FROM auditoria_eventos
 WHERE created_at >= NOW() - INTERVAL '7 days'
 GROUP BY tabla, accion
 ORDER BY eventos DESC
 LIMIT 20;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- (1) Esperado: al menos administrador + bodeguero + planificador (piloto FASE 5.1).
-- (2) Roles del enum sin perfil activo: aceptable (no todos los roles tienen
--     que estar usados). Pero no debe haber rol en perfil activo que NO este
--     en el enum (consistencia).
-- (3) Confirmar que admin@, bodegacoq@ y planificador@ existen y estan activos.
-- (4) Cada perfil deberia tener faena asignada (excepto admin/gerencia que pueden
--     ser sin faena).
-- (5) Documental — debe estar poblada (mig 31).
-- (6) Si hay 0 eventos en 7 dias, el sistema no se esta usando o el trigger de
--     auditoria no esta activo.
-- ============================================================================
