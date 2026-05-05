-- ============================================================================
-- diag_calama_admin_acceso.sql  —  SOLO LECTURA. Por que el admin no ve OTs.
-- ----------------------------------------------------------------------------
-- Si admin no ve OTs aunque RLS esta activa, hay 3 causas tipicas:
--   A) admin auth no tiene fila en usuarios_perfil
--   B) admin auth tiene fila pero rol NULL o no esta en lista admin
--   C) datos vacios en calama_ordenes_trabajo (ya descartado si check 01 > 0)
--
-- Este script revela cual es el caso. Ejecutar y pegar TODOS los result-sets.
-- ============================================================================


-- A. Conteos clave (para descartar BD vacia)
SELECT 'A1_ots'                AS check_id, COUNT(*)::text AS valor FROM calama_ordenes_trabajo;
SELECT 'A2_planificaciones'    AS check_id, COUNT(*)::text AS valor FROM calama_planificaciones;
SELECT 'A3_zonas'              AS check_id, COUNT(*)::text AS valor FROM calama_zonas_proyecto;
SELECT 'A4_perfiles_total'     AS check_id, COUNT(*)::text AS valor FROM usuarios_perfil;
SELECT 'A5_perfiles_admin'     AS check_id, COUNT(*)::text AS valor FROM usuarios_perfil WHERE rol = 'administrador';


-- B. Usuarios auth.users que se han logueado (cualquiera) vs perfil
-- Si tu email aparece aqui pero "tiene_perfil = false" o "rol = null" -> ese
-- es el bug. RLS no te deja ver OTs porque fn_user_rol() retorna NULL.
SELECT 'B_auth_vs_perfil' AS check_id,
       au.id                    AS auth_uid,
       au.email                 AS auth_email,
       au.last_sign_in_at,
       (up.id IS NOT NULL)      AS tiene_perfil,
       up.rol::text             AS rol,
       up.activo                AS perfil_activo,
       up.nombre_completo
  FROM auth.users au
  LEFT JOIN usuarios_perfil up ON up.id = au.id
 ORDER BY au.last_sign_in_at DESC NULLS LAST
 LIMIT 30;


-- C. Funciones helpers existen?
SELECT 'C_helpers' AS check_id,
       (to_regprocedure('public.fn_user_rol()') IS NOT NULL)              AS fn_user_rol,
       (to_regprocedure('public.fn_calama_puede_ver()') IS NOT NULL)      AS fn_calama_puede_ver,
       (to_regprocedure('public.fn_calama_puede_planificar()') IS NOT NULL) AS fn_calama_puede_planif,
       (to_regprocedure('public.fn_calama_es_admin_global()') IS NOT NULL) AS fn_es_admin;


-- D. Policies SELECT activas en calama_ordenes_trabajo
SELECT 'D_policies_ot' AS check_id,
       policyname, cmd, roles, qual
  FROM pg_policies
 WHERE schemaname='public'
   AND tablename='calama_ordenes_trabajo'
   AND cmd = 'SELECT';


-- E. Sample de 3 OTs (vamos a ver si las hay y avance)
SELECT 'E_sample_ots' AS check_id,
       id, folio, estado, avance_pct, avance_excel_pct, fecha_programada,
       responsable_id IS NOT NULL AS tiene_resp
  FROM calama_ordenes_trabajo
 ORDER BY folio
 LIMIT 3;


-- F. Test directo: simulamos lo que la RLS evalua para una sesion authenticated.
-- En SQL Editor corremos como owner (no authenticated), pero esto evalua los
-- valores de las funciones SECURITY DEFINER tal cual estan definidas.
-- Como aqui no hay auth.uid() valido, las funciones devolveran NULL/false.
-- Sirve para verificar que las funciones EXISTEN y compilan, no su valor real.
SELECT 'F_funcs_compilan' AS check_id,
       fn_user_rol()                AS rol_owner,
       fn_calama_es_admin_global()  AS es_admin_owner,
       fn_calama_puede_planificar() AS puede_planif_owner,
       fn_calama_puede_ver()        AS puede_ver_owner;


-- G. Para cada admin auth.user, ver si calza con condicion de la policy planning
SELECT 'G_admins_que_pasan_rls' AS check_id,
       up.id, up.email, up.rol::text AS rol_global,
       (up.rol::text IN ('administrador','gerencia','subgerente_operaciones',
                         'supervisor','planificador','jefe_operaciones'))
            AS pasa_planning_policy,
       (up.rol::text IN ('administrador','gerencia','subgerente_operaciones'))
            AS es_admin_global
  FROM usuarios_perfil up
  JOIN auth.users au ON au.id = up.id
 WHERE up.activo = true
   AND up.rol IS NOT NULL
 ORDER BY up.rol;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- Si A1 > 0 pero igual no ves OTs -> es problema de PERFIL, no de datos.
-- Si en B aparece tu email con tiene_perfil=false -> falta crear perfil admin.
-- Si en B tienes perfil pero rol=null -> falta UPDATE rol = 'administrador'.
-- Si en G tu email NO aparece o pasa_planning_policy=false -> ese es el bug.
--
-- Fix ejemplo (NO ejecutar sin confirmar):
--   UPDATE usuarios_perfil SET rol='administrador', activo=true
--    WHERE email='Molivares@prefabricadaspremium.cl';
-- O si no existe perfil:
--   INSERT INTO usuarios_perfil (id, email, nombre_completo, rol, activo)
--   SELECT id, email, COALESCE(raw_user_meta_data->>'name', email),
--          'administrador', true
--     FROM auth.users WHERE email='Molivares@prefabricadaspremium.cl';
-- ============================================================================
