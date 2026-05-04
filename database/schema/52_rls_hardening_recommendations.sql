-- ============================================================================
-- 52_rls_hardening_recommendations.sql
-- ----------------------------------------------------------------------------
-- ARCHIVO DE RECOMENDACIONES — NO EJECUTAR A CIEGAS.
--
-- Generado en FASE 5 de la auditoria SICOM-ICEO (2026-04-28).
-- Contiene SQL sugerido para cerrar brechas RLS / RPCs / Storage detectadas.
-- Cada bloque esta COMENTADO y aislado. Descomentar y revisar uno por uno
-- antes de aplicar. Probar siempre primero contra una rama / entorno staging.
--
-- Convencion:
--   -- BLOCK X.Y  Titulo                                    Severidad  Status
--   -- BEGIN ... END  delimitan el bloque ejecutable.
--   Las verificaciones (SELECT ... pg_policies) son SAFE: solo leen.
--
-- NO incluye DROP TABLE, DROP COLUMN, TRUNCATE, ni cambio de nombre.
-- ============================================================================


-- ============================================================================
-- BLOCK 0  Verificaciones previas (SAFE — solo lectura)
-- ----------------------------------------------------------------------------
-- Correr antes de cualquier cambio para tener baseline.
-- ============================================================================

-- 0.1 Listar todas las politicas RLS actuales con tabla y comando
-- SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
--   FROM pg_policies
--  WHERE schemaname = 'public'
--  ORDER BY tablename, cmd, policyname;

-- 0.2 Listar tablas con RLS habilitado pero SIN politicas (lockdown total)
-- SELECT n.nspname, c.relname
--   FROM pg_class c
--   JOIN pg_namespace n ON n.oid = c.relnamespace
--  WHERE c.relkind = 'r'
--    AND c.relrowsecurity = true
--    AND NOT EXISTS (
--      SELECT 1 FROM pg_policies p
--       WHERE p.schemaname = n.nspname AND p.tablename = c.relname
--    )
--    AND n.nspname = 'public';

-- 0.3 Listar funciones SECURITY DEFINER en schema public
-- SELECT n.nspname, p.proname, p.prosecdef AS is_security_definer,
--        pg_get_function_identity_arguments(p.oid) AS args
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public'
--    AND p.prosecdef = true
--  ORDER BY p.proname;

-- 0.4 Listar buckets storage y politicas asociadas
-- SELECT id, name, public, file_size_limit, allowed_mime_types FROM storage.buckets;
-- SELECT * FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects';


-- ============================================================================
-- BLOCK A  Endurecer ruta publica /equipo/[id]              Severidad: CRITICA
-- ----------------------------------------------------------------------------
-- Crea una vista publica con columnas no sensibles + flag de habilitacion.
-- Reemplazo seguro de `rpc_ficha_activo` cuando se invoca sin sesion.
--
-- Beneficios:
--   - Excluye costo_acumulado, contrato_id, faena_id, datos comerciales.
--   - Requiere flag por activo para "publicar" la ficha QR.
--   - No rompe el frontend si se mantiene `rpc_ficha_activo` para uso autenticado
--     y se crea un RPC paralelo `rpc_ficha_activo_publica` para el QR.
-- ============================================================================

-- A.1  Agregar flag de habilitacion publica (si no existe).
-- BEGIN;
--   ALTER TABLE public.activos
--     ADD COLUMN IF NOT EXISTS qr_publico_habilitado BOOLEAN NOT NULL DEFAULT false;
-- COMMIT;

-- A.2  Vista publica con columnas seguras (ajustar segun el RPC real).
-- BEGIN;
--   CREATE OR REPLACE VIEW public.public_activos_qr
--   WITH (security_invoker = false) AS
--   SELECT
--     a.id,
--     a.codigo,
--     a.nombre,
--     a.tipo,
--     a.numero_serie,
--     a.criticidad,
--     a.estado,
--     a.kilometraje_actual,
--     a.horas_uso_actual,
--     a.ciclos_actual,
--     a.anio_fabricacion,
--     a.foto_url,
--     a.qr_code,
--     m.nombre AS modelo_nombre,
--     mk.nombre AS marca_nombre
--   FROM public.activos a
--   LEFT JOIN public.modelos m ON m.id = a.modelo_id
--   LEFT JOIN public.marcas mk ON mk.id = m.marca_id
--   WHERE a.qr_publico_habilitado = true;
-- COMMIT;

-- A.3  Permisos: la vista debe ser legible por anon y authenticated.
-- BEGIN;
--   GRANT SELECT ON public.public_activos_qr TO anon, authenticated;
--   -- Importante: NO conceder GRANT directo sobre `activos` a `anon`.
-- COMMIT;

-- A.4  RPC publico restringido a la vista (si se prefiere RPC en vez de view).
-- BEGIN;
--   CREATE OR REPLACE FUNCTION public.rpc_ficha_activo_publica(p_activo_id UUID)
--   RETURNS public.public_activos_qr
--   LANGUAGE sql
--   SECURITY DEFINER
--   SET search_path = public
--   AS $$
--     SELECT * FROM public.public_activos_qr WHERE id = p_activo_id;
--   $$;
--   GRANT EXECUTE ON FUNCTION public.rpc_ficha_activo_publica(UUID) TO anon, authenticated;
--   REVOKE EXECUTE ON FUNCTION public.rpc_ficha_activo(UUID) FROM anon;
-- COMMIT;

-- A.5  En el frontend, cambiar la llamada de getFichaActivo() para la ruta /equipo/[id]
--      a invocar `rpc_ficha_activo_publica` en lugar de `rpc_ficha_activo`.
--      (Cambio frontend, no aplicar SQL aqui.)


-- ============================================================================
-- BLOCK B  Plantilla de role-check para RPCs criticas        Severidad: CRITICA
-- ----------------------------------------------------------------------------
-- Las RPCs SECURITY DEFINER que mutan estado deberian validar rol al inicio.
-- Esta plantilla NO recompila las funciones reales (no se conoce el cuerpo
-- exacto). Es para que el DBA agregue el check al inicio de cada RPC sensible.
-- ============================================================================

-- B.1  Helper: obtener rol del usuario actual (si no existe).
-- BEGIN;
--   CREATE OR REPLACE FUNCTION public.fn_user_rol()
--   RETURNS TEXT
--   LANGUAGE sql
--   STABLE
--   SECURITY DEFINER
--   SET search_path = public
--   AS $$
--     SELECT rol::text FROM public.usuarios_perfil WHERE id = auth.uid();
--   $$;
--   GRANT EXECUTE ON FUNCTION public.fn_user_rol() TO authenticated;
-- COMMIT;

-- B.2  Plantilla a insertar al INICIO de cada RPC sensible.
-- ----- COPIAR ESTE BLOQUE DENTRO DE LA FUNCION EXISTENTE -----
-- IF public.fn_user_rol() NOT IN (
--   'administrador', 'subgerente_operaciones', 'jefe_operaciones',
--   'jefe_mantenimiento', 'supervisor', 'planificador'
-- ) THEN
--   RAISE EXCEPTION 'Acceso denegado: rol % no autorizado', public.fn_user_rol()
--     USING ERRCODE = '42501';
-- END IF;
-- ------------------------------------------------------------

-- B.3  RPCs prioritarias para aplicar el check (lista no exhaustiva):
--   - rpc_crear_ot
--   - rpc_transicion_ot
--   - rpc_cerrar_ot_supervisor
--   - rpc_registrar_salida_inventario
--   - rpc_registrar_entrada_inventario
--   - rpc_registrar_ajuste_inventario
--   - rpc_transferir_inventario
--   - rpc_aprobar_conteo_inventario
--   - rpc_calcular_iceo_periodo
--   - rpc_calcular_incentivos_periodo
--   - rpc_cerrar_periodo_kpi
--   - calcular_iceo
--   - calcular_todos_kpi (si existe)
--
-- Para cada una, ajustar la lista de roles permitidos al perfil de la accion.
-- Por ejemplo: rpc_calcular_incentivos_periodo solo deberia permitir
--   'administrador', 'gerencia', 'rrhh_incentivos'.


-- ============================================================================
-- BLOCK C  Restringir SELECT abiertos USING (true)            Severidad: ALTA
-- ----------------------------------------------------------------------------
-- Reemplazar politicas USING (true) en tablas sensibles por chequeos por rol.
-- Mantener politicas explicitas para administrador / gerencia / auditor.
-- NO ejecutar sin verificar primero que existe `fn_user_rol()` (Block B.1).
-- ============================================================================

-- C.1  Helper que devuelve TRUE si el rol pertenece al "grupo lectura interna"
--      (roles que pueden leer datos internos no comerciales).
-- BEGIN;
--   CREATE OR REPLACE FUNCTION public.fn_user_lectura_interna()
--   RETURNS BOOLEAN
--   LANGUAGE sql
--   STABLE
--   SECURITY DEFINER
--   SET search_path = public
--   AS $$
--     SELECT public.fn_user_rol() IN (
--       'administrador', 'gerencia', 'subgerente_operaciones',
--       'jefe_operaciones', 'jefe_mantenimiento', 'supervisor',
--       'planificador', 'auditor', 'tecnico_mantenimiento', 'colaborador',
--       'comercial', 'prevencionista', 'bodeguero', 'operador_abastecimiento'
--     );
--   $$;
--   GRANT EXECUTE ON FUNCTION public.fn_user_lectura_interna() TO authenticated;
-- COMMIT;

-- C.2  Tabla `incentivos` — solo roles autorizados leen (CRITICO).
-- BEGIN;
--   DROP POLICY IF EXISTS pol_authenticated_select_incentivos ON public.incentivos;
--   CREATE POLICY pol_lectura_incentivos ON public.incentivos
--     FOR SELECT TO authenticated
--     USING (public.fn_user_rol() IN ('administrador', 'gerencia', 'rrhh_incentivos'));
-- COMMIT;

-- C.3  Tabla `mediciones_kpi` — restringir lectura.
-- BEGIN;
--   DROP POLICY IF EXISTS pol_authenticated_select_mediciones_kpi ON public.mediciones_kpi;
--   CREATE POLICY pol_lectura_mediciones_kpi ON public.mediciones_kpi
--     FOR SELECT TO authenticated
--     USING (public.fn_user_rol() IN (
--       'administrador', 'gerencia', 'subgerente_operaciones',
--       'jefe_operaciones', 'auditor', 'rrhh_incentivos'
--     ));
-- COMMIT;

-- C.4  Tabla `auditoria_eventos` — restringir lectura.
-- BEGIN;
--   DROP POLICY IF EXISTS pol_authenticated_select_auditoria ON public.auditoria_eventos;
--   CREATE POLICY pol_lectura_auditoria ON public.auditoria_eventos
--     FOR SELECT TO authenticated
--     USING (public.fn_user_rol() IN (
--       'administrador', 'gerencia', 'auditor'
--     ));
-- COMMIT;

-- C.5  Tabla `usuarios_perfil` — cada usuario lee su propio perfil + admin todo.
--      (Si la app necesita listar nombres para asignar OT, se puede mantener
--       lectura amplia pero ocultar email/telefono via vista.)
-- BEGIN;
--   DROP POLICY IF EXISTS pol_authenticated_select_all_perfil ON public.usuarios_perfil;
--   CREATE POLICY pol_lectura_perfil_propio ON public.usuarios_perfil
--     FOR SELECT TO authenticated
--     USING (id = auth.uid() OR public.fn_user_rol() IN ('administrador', 'gerencia'));
--
--   -- Vista pseudo-publica para asignaciones (sin email/telefono):
--   CREATE OR REPLACE VIEW public.usuarios_perfil_basico
--   WITH (security_invoker = false) AS
--   SELECT id, nombre_completo, cargo, rol
--     FROM public.usuarios_perfil
--    WHERE activo = true;
--   GRANT SELECT ON public.usuarios_perfil_basico TO authenticated;
-- COMMIT;

-- C.6  Tabla `contratos` — restringir a roles administrativos / comerciales.
-- BEGIN;
--   DROP POLICY IF EXISTS pol_authenticated_select_contratos ON public.contratos;
--   CREATE POLICY pol_lectura_contratos ON public.contratos
--     FOR SELECT TO authenticated
--     USING (public.fn_user_rol() IN (
--       'administrador', 'gerencia', 'subgerente_operaciones',
--       'jefe_operaciones', 'comercial', 'auditor'
--     ));
-- COMMIT;


-- ============================================================================
-- BLOCK D  Versionar buckets Storage faltantes              Severidad: ALTA
-- ----------------------------------------------------------------------------
-- Plantilla para crear los buckets que el frontend usa pero no tienen migracion.
-- Si los buckets ya existen (creados a mano), el INSERT con ON CONFLICT no rompe.
-- ============================================================================

-- D.1  Bucket `evidencias-ot` (usado en services/ordenes-trabajo.ts y dashboard/[id]).
-- BEGIN;
--   INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
--   VALUES ('evidencias-ot', 'evidencias-ot', true, 10485760,
--           ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
--   ON CONFLICT (id) DO NOTHING;
--
--   CREATE POLICY pol_evidencias_ot_select ON storage.objects
--     FOR SELECT TO authenticated, anon
--     USING (bucket_id = 'evidencias-ot');
--   CREATE POLICY pol_evidencias_ot_insert ON storage.objects
--     FOR INSERT TO authenticated
--     WITH CHECK (bucket_id = 'evidencias-ot');
--   CREATE POLICY pol_evidencias_ot_update ON storage.objects
--     FOR UPDATE TO authenticated
--     USING (bucket_id = 'evidencias-ot' AND owner = auth.uid());
--   CREATE POLICY pol_evidencias_ot_delete ON storage.objects
--     FOR DELETE TO authenticated
--     USING (bucket_id = 'evidencias-ot' AND owner = auth.uid());
-- COMMIT;

-- D.2  Bucket `evidencias-combustible` (services/combustible.ts).
-- BEGIN;
--   INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
--   VALUES ('evidencias-combustible', 'evidencias-combustible', true, 10485760,
--           ARRAY['image/jpeg','image/png','image/webp'])
--   ON CONFLICT (id) DO NOTHING;
--
--   CREATE POLICY pol_evidencias_combustible_select ON storage.objects
--     FOR SELECT TO authenticated
--     USING (bucket_id = 'evidencias-combustible');
--   CREATE POLICY pol_evidencias_combustible_insert ON storage.objects
--     FOR INSERT TO authenticated
--     WITH CHECK (bucket_id = 'evidencias-combustible');
-- COMMIT;

-- D.3  Bucket `fotos-activos` (services/activos.ts:192) y `fotos-certificaciones`
--      (services/certificaciones.ts:41) — ajustar nombres reales.
--      Mismo patron que arriba.


-- ============================================================================
-- BLOCK E  Verificaciones POST-cambio (SAFE — solo lectura)
-- ----------------------------------------------------------------------------
-- Correr despues de aplicar cualquiera de los bloques anteriores.
-- ============================================================================

-- E.1  Confirmar que no existen politicas USING(true) en tablas sensibles.
-- SELECT tablename, policyname, qual
--   FROM pg_policies
--  WHERE schemaname = 'public'
--    AND tablename IN ('incentivos','mediciones_kpi','auditoria_eventos','contratos','usuarios_perfil')
--    AND qual = 'true';

-- E.2  Confirmar que la ruta publica solo expone columnas seguras.
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'public_activos_qr';

-- E.3  Validacion funcional: con anon key, listar registros segun la vista.
-- (Ejecutar desde el cliente Supabase con anon key)
-- SELECT * FROM public.public_activos_qr LIMIT 1;
-- SELECT * FROM public.activos LIMIT 1;       -- debe devolver 0 filas


-- ============================================================================
-- FIN DEL ARCHIVO 52_rls_hardening_recommendations.sql
-- ============================================================================
