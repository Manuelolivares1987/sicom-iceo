-- ============================================================================
-- diag_calama_estado_actual.sql  —  SOLO LECTURA. Diagnostico de estado.
-- ----------------------------------------------------------------------------
-- Ejecutar como owner (SQL Editor) para ver estado real de la BD Calama.
-- NO modifica datos. Devuelve multiples result-sets, pegar todos.
-- ============================================================================


-- 1. Conteos generales
SELECT '01_total_ots' AS check_id, COUNT(*)::text AS valor FROM calama_ordenes_trabajo;

SELECT '02_total_planificaciones' AS check_id, COUNT(*)::text AS valor FROM calama_planificaciones;

SELECT '03_total_zonas' AS check_id, COUNT(*)::text AS valor FROM calama_zonas_proyecto;

SELECT '04_total_planes_semanales' AS check_id, COUNT(*)::text AS valor FROM calama_planes_semanales;

SELECT '05_total_plan_ots' AS check_id, COUNT(*)::text AS valor FROM calama_plan_semanal_ots;

SELECT '06_total_avance_eventos' AS check_id, COUNT(*)::text AS valor FROM calama_ot_avance_eventos;


-- 2. OTs por estado
SELECT '07_ots_por_estado' AS check_id, estado, COUNT(*) AS total
  FROM calama_ordenes_trabajo
 GROUP BY estado
 ORDER BY estado;


-- 3. Planificaciones existentes
SELECT '08_planificaciones' AS check_id, codigo, nombre, estado, faena_calama_id,
       fecha_inicio_plan, fecha_termino_plan, created_at
  FROM calama_planificaciones
 ORDER BY created_at DESC
 LIMIT 5;


-- 4. Zonas (lugares fisicos) por planificacion
SELECT '09_zonas_por_plan' AS check_id, p.codigo AS plan, z.codigo_zona, z.nombre
  FROM calama_zonas_proyecto z
  JOIN calama_planificaciones p ON p.id = z.planificacion_id
 ORDER BY p.codigo, z.codigo_zona
 LIMIT 25;


-- 5. Planes semanales existentes
SELECT '10_planes_semanales' AS check_id,
       ps.id, p.codigo AS plan, ps.fecha_inicio_semana, ps.fecha_fin_semana,
       ps.estado, ps.creado_por, ps.created_at,
       (SELECT COUNT(*) FROM calama_plan_semanal_ots WHERE plan_semanal_id = ps.id) AS ots_planificadas
  FROM calama_planes_semanales ps
  JOIN calama_planificaciones p ON p.id = ps.planificacion_id
 ORDER BY ps.created_at DESC
 LIMIT 10;


-- 6. Distribucion plan_semanal_ots por estado y responsable
SELECT '11_plan_ots_por_responsable' AS check_id,
       po.estado_plan,
       COALESCE(up.nombre_completo, up.email, '(sin perfil)') AS responsable,
       COUNT(*) AS total
  FROM calama_plan_semanal_ots po
  LEFT JOIN usuarios_perfil up ON up.id = po.responsable_id
 GROUP BY po.estado_plan, COALESCE(up.nombre_completo, up.email, '(sin perfil)')
 ORDER BY total DESC;


-- 7. Usuarios MIG23: perfiles
SELECT '12_perfiles_calama' AS check_id,
       id, email, nombre_completo, rol, cargo, activo
  FROM usuarios_perfil
 WHERE id IN (
    'b6160090-4d00-42f6-b50e-b4a811ab584a',
    '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
 );


-- 8. Usuarios MIG23: roles Calama
SELECT '13_roles_calama_proyecto' AS check_id,
       crp.usuario_id, crp.rol_calama, crp.faena_calama_id, crp.activo,
       up.email
  FROM calama_roles_proyecto crp
  LEFT JOIN usuarios_perfil up ON up.id = crp.usuario_id
 WHERE crp.usuario_id IN (
    'b6160090-4d00-42f6-b50e-b4a811ab584a',
    '6ee0a371-d8d5-4617-83f7-7d4a28066f07'
 );


-- 9. Total perfiles activos (los que veran el selector responsable)
SELECT '14_perfiles_activos_total' AS check_id, COUNT(*)::text AS valor
  FROM usuarios_perfil WHERE activo = true;


-- 10. Lista compacta de perfiles activos (top 20)
SELECT '15_perfiles_activos' AS check_id,
       email, nombre_completo, rol, cargo
  FROM usuarios_perfil
 WHERE activo = true
 ORDER BY nombre_completo NULLS LAST, email
 LIMIT 20;


-- 11. Sample OTs con avance Excel/Real
SELECT '16_sample_ots_avance' AS check_id,
       folio, estado,
       avance_pct AS avance_real,
       avance_excel_pct AS avance_excel,
       responsable_id IS NOT NULL AS tiene_responsable
  FROM calama_ordenes_trabajo
 ORDER BY avance_excel_pct DESC NULLS LAST, folio
 LIMIT 10;


-- 12. Funciones helper criticas existen
SELECT '17_helpers_existen' AS check_id,
       (to_regprocedure('public.fn_calama_puede_ver()') IS NOT NULL)::text         AS puede_ver,
       (to_regprocedure('public.fn_calama_puede_planificar()') IS NOT NULL)::text   AS puede_planificar,
       (to_regprocedure('public.fn_calama_es_admin_global()') IS NOT NULL)::text    AS es_admin_global,
       (to_regprocedure('public.fn_calama_es_operador()') IS NOT NULL)::text        AS es_operador,
       (to_regprocedure('public.fn_user_rol()') IS NOT NULL)::text                  AS fn_user_rol;


-- 13. RLS activa en tablas criticas
SELECT '18_rls_estado' AS check_id,
       tablename,
       rowsecurity AS rls_activa,
       (SELECT COUNT(*) FROM pg_policies WHERE schemaname='public' AND tablename = pt.tablename) AS num_policies
  FROM pg_tables pt
 WHERE schemaname = 'public'
   AND tablename IN ('calama_ordenes_trabajo', 'calama_plan_semanal_ots',
                     'calama_planificaciones', 'calama_planes_semanales',
                     'calama_ot_avance_eventos', 'calama_zonas_proyecto');


-- ============================================================================
-- INTERPRETACION RAPIDA
-- ----------------------------------------------------------------------------
-- 01_total_ots         : debe ser 112 si solo importaste el Excel Centinela
-- 04_total_planes_sem  : 0 si nunca abriste plan-semanal; 1+ si entraste
-- 05_total_plan_ots    : >0 solo si arrastraste OTs en el Kanban
-- 12_perfiles_calama   : DEBE devolver 2 filas (sup + oocc)
-- 13_roles_calama_proy : DEBE devolver 2 filas (supervisor_calama + operador_calama)
-- 14_perfiles_activos  : numero total de personas en el selector "Asignar resp."
-- 18_rls_estado        : rls_activa=true en todas las tablas calama_*
--
-- Si 01_total_ots = 0 -> el problema es que la importacion no se aplico.
-- Si 14_perfiles_activos = 2 -> solo se ven los 2 nuevos en selector
--   (correcto si vaciaste otros, pero quiza falten los admin que ya usan
--    la app — verificar 15_perfiles_activos).
-- ============================================================================
