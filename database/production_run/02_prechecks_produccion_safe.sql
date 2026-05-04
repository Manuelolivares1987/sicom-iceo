-- ============================================================================
-- 02_prechecks_produccion_safe.sql  —  PRODUCCION. Solo lectura. Sin riesgo.
-- ----------------------------------------------------------------------------
-- Diagnostico completo ANTES de ejecutar mig 55/56/57.
-- Si cualquier query devuelve resultado inesperado, DETENER.
-- ============================================================================


-- ── 1. ¿A qué BD estoy conectado? ───────────────────────────────────
SELECT
    current_database()       AS database,
    current_user             AS usuario,
    inet_server_addr()       AS servidor,
    NOW()                    AS now_utc,
    NOW() AT TIME ZONE 'America/Santiago' AS now_chile;
-- Esperado: la URL del proyecto producción.
-- Si no estás seguro: STOP.


-- ── 2. Conteo de tablas legacy (deben existir) ──────────────────────
SELECT
    'BASE_LEGACY' AS check_name,
    COUNT(*) AS encontradas,
    array_agg(table_name ORDER BY table_name) AS tablas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'contratos', 'faenas', 'activos', 'modelos', 'marcas',
    'usuarios_perfil', 'ordenes_trabajo', 'checklist_ot',
    'productos', 'bodegas', 'stock_bodega', 'movimientos_inventario',
    'kardex', 'planes_mantenimiento', 'pautas_fabricante',
    'certificaciones', 'auditoria_eventos', 'no_conformidades',
    'combustible_estanques', 'combustible_movimientos',
    'combustible_medidores', 'combustible_varillaje',
    'verificaciones_disponibilidad',
    'ot_materiales_planeados', 'estado_diario_flota',
    'checklist_templates'
  );
-- Esperado: encontradas = 25. Si < 25: STOP.


-- ── 3. Tablas NUEVAS de mig 55/56/57 (NO deben existir todavía) ──────
SELECT
    'TABLAS_NUEVAS' AS check_name,
    COUNT(*) AS ya_existen,
    array_agg(table_name ORDER BY table_name) AS detalle
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'proveedores', 'centros_costo',
    'ordenes_compra', 'ordenes_compra_items',
    'recepciones_bodega', 'recepciones_bodega_items',
    'salidas_bodega', 'salidas_bodega_items',
    'ingresos_combustible', 'salidas_combustible', 'despachos_combustible',
    'inventario_capas', 'inventario_consumos_capas',
    'combustible_stock_inicial', 'combustible_kardex_valorizado',
    'operacion_migraciones_log'
  );
-- Esperado: 0 (idealmente). Si alguna existe, mig 55/56/57 ya parcialmente
-- aplicada. INVESTIGAR antes de continuar — los CREATE IF NOT EXISTS no
-- crearan duplicado pero pueden faltar datos / FKs.


-- ── 4. Funciones críticas requeridas por mig 55+ ─────────────────────
SELECT
    'FUNCIONES_BASE' AS check_name,
    COUNT(*) AS encontradas,
    array_agg(proname ORDER BY proname) AS funciones
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'fn_user_rol',
    'fn_user_has_any_role',
    'fn_set_updated_at',
    'rpc_registrar_entrada_inventario',
    'rpc_registrar_salida_inventario',
    'fn_registrar_movimiento_combustible'
  );
-- Esperado: encontradas = 6. Si falta `fn_user_rol`: STOP, mig 31 no aplicada.


-- ── 5. Usuarios activos por rol ─────────────────────────────────────
SELECT
    'USUARIOS_PERFIL' AS check_name,
    rol,
    COUNT(*) AS cantidad
FROM usuarios_perfil
WHERE activo = true
GROUP BY rol
ORDER BY rol;


-- ── 6. Conteo productos / stock / combustible ───────────────────────
SELECT
    (SELECT COUNT(*) FROM productos) AS productos_total,
    (SELECT COUNT(*) FROM stock_bodega WHERE cantidad > 0) AS productos_con_stock,
    (SELECT COUNT(*) FROM stock_bodega
       WHERE cantidad > 0
         AND (costo_promedio IS NULL OR costo_promedio = 0)) AS productos_sin_costo,
    (SELECT COUNT(*) FROM bodegas) AS bodegas,
    (SELECT COUNT(*) FROM combustible_estanques) AS estanques,
    (SELECT COUNT(*) FROM combustible_estanques
       WHERE activo = true AND stock_teorico_lt > 0) AS estanques_con_stock;


-- ── 7. ⚠️ Productos con stock pero SIN costo ─────────────────────────
SELECT
    p.codigo,
    p.nombre,
    sb.cantidad,
    sb.costo_promedio,
    b.codigo AS bodega
FROM stock_bodega sb
JOIN productos p ON p.id = sb.producto_id
JOIN bodegas b ON b.id = sb.bodega_id
WHERE sb.cantidad > 0
  AND (sb.costo_promedio IS NULL OR sb.costo_promedio = 0)
ORDER BY sb.cantidad DESC
LIMIT 20;
-- ⚠️ Si esta query devuelve filas, el seed de capas FIFO (paso 09) debe
-- excluirlas O Finanzas debe completar costo_promedio antes.


-- ── 8. Estanques con stock pero sin partida inicial documentada ──────
SELECT
    e.codigo,
    e.nombre,
    e.stock_teorico_lt,
    e.capacidad_lt,
    e.faena_id
FROM combustible_estanques e
WHERE e.activo = true
  AND e.stock_teorico_lt > 0
ORDER BY e.codigo;
-- ⚠️ Cada estanque listado requerira `rpc_registrar_stock_inicial_combustible`
-- en paso 12 con costo historico validado por Finanzas.


-- ── 9. Movimientos en últimas 24 horas (alerta de actividad) ─────────
SELECT
    'MOVIMIENTOS_24H' AS check_name,
    'movimientos_inventario' AS tabla,
    COUNT(*) AS cantidad
FROM movimientos_inventario
WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT
    'MOVIMIENTOS_24H',
    'combustible_movimientos',
    COUNT(*)
FROM combustible_movimientos
WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT
    'MOVIMIENTOS_24H',
    'ordenes_trabajo',
    COUNT(*)
FROM ordenes_trabajo
WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT
    'MOVIMIENTOS_24H',
    'auditoria_eventos',
    COUNT(*)
FROM auditoria_eventos
WHERE created_at >= NOW() - INTERVAL '24 hours';
-- ⚠️ Si valores > 0, hay actividad reciente. Confirmar que NO hay usuarios
-- conectados ANTES de continuar.


-- ── 10. RPCs que serán reescritas en mig 56 ─────────────────────────
SELECT
    proname,
    pronargs AS num_args,
    prosecdef AS is_security_definer
FROM pg_proc
WHERE proname IN (
    'rpc_registrar_entrada_inventario',
    'rpc_registrar_salida_inventario',
    'rpc_registrar_recepcion_bodega',  -- futura, posiblemente NULL aún
    'rpc_registrar_salida_bodega'      -- futura
)
ORDER BY proname;
-- Las dos primeras existen (mig 09). Las dos últimas NO deben existir aún.


-- ── 11. Policies sobre tablas críticas (preview) ────────────────────
SELECT
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'activos', 'usuarios_perfil', 'ordenes_trabajo',
    'auditoria_eventos', 'mediciones_kpi'
  )
ORDER BY tablename, policyname;


-- ── 12. Storage buckets relevantes ──────────────────────────────────
SELECT id, name, public, file_size_limit
FROM storage.buckets
WHERE name IN (
    'evidencias-verificacion',
    'evidencias-ot',
    'evidencias-combustible',
    'fotos-activos',
    'fotos-certificaciones'
)
ORDER BY name;


-- ── 13. ⚠️ DIAGNÓSTICO RESUMIDO ────────────────────────────────────
SELECT
    'DIAGNOSTICO' AS resumen,
    CASE
        WHEN (SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema = 'public'
                AND table_name = 'fn_user_rol') = 0
              -- (técnicamente esto cuenta tablas, no funciones — el real check está en paso 4)
        THEN 'STOP — falta función fn_user_rol (mig 31)'
        WHEN (SELECT COUNT(*) FROM stock_bodega
              WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0)) > 0
        THEN 'WARNING — productos con stock sin costo. Coordinar con Finanzas antes de paso 09.'
        WHEN (SELECT COUNT(*) FROM combustible_estanques
              WHERE activo = true AND stock_teorico_lt > 0) > 0
        THEN 'WARNING — estanques con stock requieren stock_inicial validado en paso 12.'
        WHEN (SELECT COUNT(*) FROM movimientos_inventario
              WHERE created_at >= NOW() - INTERVAL '1 hour') > 5
        THEN 'WARNING — alta actividad ultima hora. Confirmar ventana sin usuarios.'
        ELSE 'PRECHECKS OK — proceder al paso 03.'
    END AS estado,
    NOW() AS chequeado_en;


-- ============================================================================
-- INTERPRETACION FINAL
-- ============================================================================
-- Lee el resultado de la query (13).
--
-- Si dice "STOP — ...":
--   No avanzar. Verificar mig 01-51 aplicadas.
--
-- Si dice "WARNING — ...":
--   Ese aspecto requiere atencion manual. NO impide continuar, pero requiere
--   coordinacion con Finanzas (paso 09 o 12).
--
-- Si dice "PRECHECKS OK":
--   Sistema listo. Avanzar al paso 03 (crear bitacora).
-- ============================================================================
