-- ============================================================================
-- 01_prechecks_safe.sql  —  Solo lectura. Cero riesgo.
-- ----------------------------------------------------------------------------
-- Confirma que la base de staging tiene la estructura legacy esperada
-- (mig 01-51) y NO tiene todavia las tablas nuevas de mig 55/56/57.
-- ============================================================================


-- ── 1. ¿A qué BD estoy conectado? ─────────────────────────────────────
SELECT
    current_database()      AS database,
    current_user            AS usuario,
    inet_server_addr()      AS servidor,
    NOW()                   AS now;


-- ── 2. Tablas base requeridas (legacy, deben existir) ────────────────
SELECT
    'BASE_LEGACY' AS check_name,
    array_agg(t.table_name ORDER BY t.table_name) AS encontradas
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_name IN (
    'contratos', 'faenas', 'activos', 'modelos', 'marcas',
    'usuarios_perfil', 'ordenes_trabajo', 'checklist_ot',
    'productos', 'bodegas', 'stock_bodega', 'movimientos_inventario',
    'kardex', 'planes_mantenimiento', 'pautas_fabricante',
    'certificaciones', 'auditoria_eventos', 'no_conformidades',
    'combustible_estanques', 'combustible_movimientos',
    'combustible_medidores', 'combustible_varillaje',
    'verificaciones_disponibilidad',
    'ot_materiales_planeados',
    'estado_diario_flota',
    'checklist_templates'
  );
-- Esperado: 25 tablas


-- ── 3. Tablas NUEVAS de mig 55/56/57 (NO deben existir todavía) ──────
SELECT
    'TABLAS_NUEVAS_55_56_57' AS check_name,
    array_agg(t.table_name ORDER BY t.table_name) AS ya_existen
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_name IN (
    'proveedores', 'centros_costo',
    'ordenes_compra', 'ordenes_compra_items',
    'recepciones_bodega', 'recepciones_bodega_items',
    'salidas_bodega', 'salidas_bodega_items',
    'ingresos_combustible', 'salidas_combustible', 'despachos_combustible',
    'inventario_capas', 'inventario_consumos_capas',
    'combustible_stock_inicial', 'combustible_kardex_valorizado'
  );
-- Esperado: NULL o array vacio. Si hay alguna, investigar antes de continuar.


-- ── 4. Funciones críticas requeridas ─────────────────────────────────
SELECT
    'FUNCIONES_BASE' AS check_name,
    array_agg(p.proname ORDER BY p.proname) AS encontradas
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'fn_user_rol',
    'fn_user_has_any_role',
    'fn_set_updated_at',
    'rpc_registrar_entrada_inventario',
    'rpc_registrar_salida_inventario',
    'fn_registrar_movimiento_combustible',
    'fn_aplicar_estados_diarios_automaticos'
  );
-- Esperado: las 7 funciones listadas


-- ── 5. Stock actual (preview) ────────────────────────────────────────
SELECT
    'STOCK_BODEGA' AS check_name,
    COUNT(*) AS productos_con_stock,
    SUM(cantidad) AS total_unidades,
    SUM(COALESCE(cantidad * costo_promedio, 0)) AS valor_total_estimado
FROM stock_bodega
WHERE cantidad > 0;


-- ── 6. Estanques de combustible ──────────────────────────────────────
SELECT
    e.codigo,
    e.nombre,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.activo
FROM combustible_estanques e
ORDER BY e.codigo;


-- ── 7. Usuarios y roles ──────────────────────────────────────────────
SELECT
    'USUARIOS_PERFIL' AS check_name,
    rol,
    COUNT(*) AS cantidad
FROM usuarios_perfil
WHERE activo = true
GROUP BY rol
ORDER BY rol;


-- ── 8. Resumen ICEO ──────────────────────────────────────────────────
SELECT
    'CONTRATOS' AS check_name,
    estado,
    COUNT(*) AS cantidad
FROM contratos
GROUP BY estado;


-- ── 9. Activos por estado ────────────────────────────────────────────
SELECT
    'ACTIVOS' AS check_name,
    estado,
    COUNT(*) AS cantidad
FROM activos
GROUP BY estado
ORDER BY cantidad DESC;


-- ── 10. Politicas RLS sobre tablas sensibles (preview) ────────────────
SELECT
    schemaname, tablename, COUNT(*) AS n_policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'activos','ordenes_trabajo','usuarios_perfil','mediciones_kpi',
    'auditoria_eventos','contratos','certificaciones'
  )
GROUP BY schemaname, tablename
ORDER BY tablename;


-- ============================================================================
-- INTERPRETACION DE RESULTADOS
-- ============================================================================
-- (1) database NO debe contener "production" o el nombre de tu proyecto prod.
-- (2) Deben existir las 25 tablas base. Si faltan, mig 01-51 NO aplicada.
-- (3) Las 15 tablas nuevas NO deben existir todavia. Si alguna existe,
--     verificar si ya se aplico mig 55/56/57 (podria estar parcialmente).
-- (4) Las 7 funciones base deben existir. Si falta `fn_user_rol`, mig 31 no
--     aplicada — bloqueante para 55/56/57.
-- (5)-(9) Datos para tener referencia "antes" del cambio.
-- (10) Politicas existentes: solo informativo. No tocar en este script.
-- ============================================================================
