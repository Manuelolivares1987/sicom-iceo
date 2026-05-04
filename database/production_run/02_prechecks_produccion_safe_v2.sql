-- ============================================================================
-- 02_prechecks_produccion_safe_v2.sql  —  PRODUCCION. Solo lectura. Sin riesgo.
-- ----------------------------------------------------------------------------
-- VERSION CORREGIDA del archivo `02_prechecks_produccion_safe.sql`.
-- Bug corregido en query (13) DIAGNOSTICO:
--   - El original buscaba `fn_user_rol` en information_schema.tables (TABLAS),
--     lo cual nunca detectaba la función. Resultado: STOP eterno.
--   - Corregido: usar to_regprocedure('public.fn_user_rol()').
--
-- Adicionalmente devuelve un diagnóstico estructurado con flags booleanos.
-- ============================================================================


-- ── 1. ¿A qué BD estoy conectado? ───────────────────────────────────
SELECT
    current_database()       AS database,
    current_user             AS usuario,
    inet_server_addr()       AS servidor,
    NOW()                    AS now_utc,
    NOW() AT TIME ZONE 'America/Santiago' AS now_chile;


-- ── 2. Tablas legacy (deben existir) ─────────────────────────────────
SELECT
    'BASE_LEGACY' AS check_name,
    COUNT(*) AS encontradas,
    array_agg(table_name ORDER BY table_name) AS tablas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'contratos','faenas','activos','modelos','marcas',
    'usuarios_perfil','ordenes_trabajo','checklist_ot',
    'productos','bodegas','stock_bodega','movimientos_inventario',
    'kardex','planes_mantenimiento','pautas_fabricante',
    'certificaciones','auditoria_eventos','no_conformidades',
    'combustible_estanques','combustible_movimientos',
    'combustible_medidores','combustible_varillaje',
    'verificaciones_disponibilidad',
    'ot_materiales_planeados','estado_diario_flota',
    'checklist_templates'
  );


-- ── 3. Tablas NUEVAS de mig 55/56/57 (NO deben existir todavía) ──────
SELECT
    'TABLAS_NUEVAS' AS check_name,
    COUNT(*) AS ya_existen,
    array_agg(table_name ORDER BY table_name) AS detalle
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'proveedores','centros_costo',
    'ordenes_compra','ordenes_compra_items',
    'recepciones_bodega','recepciones_bodega_items',
    'salidas_bodega','salidas_bodega_items',
    'ingresos_combustible','salidas_combustible','despachos_combustible',
    'inventario_capas','inventario_consumos_capas',
    'combustible_stock_inicial','combustible_kardex_valorizado',
    'operacion_migraciones_log'
  );


-- ── 4. Funciones críticas requeridas ─────────────────────────────────
-- ✅ CORREGIDO: usar pg_proc en lugar de information_schema.tables.
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


-- ── 5. Usuarios activos por rol ─────────────────────────────────────
SELECT
    'USUARIOS_PERFIL' AS check_name,
    rol, COUNT(*) AS cantidad
FROM usuarios_perfil
WHERE activo = true
GROUP BY rol ORDER BY rol;


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


-- ── 7. Productos con stock pero SIN costo ───────────────────────────
SELECT
    p.codigo, p.nombre, sb.cantidad, sb.costo_promedio, b.codigo AS bodega
FROM stock_bodega sb
JOIN productos p ON p.id = sb.producto_id
JOIN bodegas b ON b.id = sb.bodega_id
WHERE sb.cantidad > 0
  AND (sb.costo_promedio IS NULL OR sb.costo_promedio = 0)
ORDER BY sb.cantidad DESC LIMIT 20;


-- ── 8. Estanques con stock pero sin partida inicial ──────────────────
SELECT
    e.codigo, e.nombre, e.stock_teorico_lt, e.capacidad_lt, e.faena_id
FROM combustible_estanques e
WHERE e.activo = true AND e.stock_teorico_lt > 0
ORDER BY e.codigo;


-- ── 9. Movimientos en últimas 24 horas ──────────────────────────────
SELECT
    'MOVIMIENTOS_24H' AS check_name,
    'movimientos_inventario' AS tabla, COUNT(*) AS cantidad
FROM movimientos_inventario WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 'MOVIMIENTOS_24H','combustible_movimientos',COUNT(*)
FROM combustible_movimientos WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 'MOVIMIENTOS_24H','ordenes_trabajo',COUNT(*)
FROM ordenes_trabajo WHERE created_at >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 'MOVIMIENTOS_24H','auditoria_eventos',COUNT(*)
FROM auditoria_eventos WHERE created_at >= NOW() - INTERVAL '24 hours';


-- ── 10. Storage buckets relevantes ──────────────────────────────────
SELECT id, name, public, file_size_limit
FROM storage.buckets
WHERE name IN (
    'evidencias-verificacion','evidencias-ot','evidencias-combustible',
    'fotos-activos','fotos-certificaciones'
)
ORDER BY name;


-- ── 11. ✅ DIAGNÓSTICO ESTRUCTURADO CON FLAGS ────────────────────────

SELECT
    'DIAGNOSTICO_FLAGS' AS resumen,
    -- ✅ Detección correcta de la función (esto era el bug)
    (to_regprocedure('public.fn_user_rol()') IS NOT NULL) AS fn_user_rol_detectada,
    -- Tablas mig 55/56/57 ya creadas
    EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'proveedores'
    ) AS tabla_proveedores_existe,
    EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'inventario_capas'
    ) AS tabla_inventario_capas_existe,
    EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'combustible_stock_inicial'
    ) AS tabla_combustible_stock_inicial_existe,
    -- Conteos clave
    (SELECT COUNT(*) FROM stock_bodega
       WHERE cantidad > 0 AND (costo_promedio IS NULL OR costo_promedio = 0))
        AS productos_con_costo_null,
    (SELECT COUNT(*) FROM combustible_estanques
       WHERE activo = true AND stock_teorico_lt > 0)
        AS estanques_con_stock,
    (SELECT COUNT(*) FROM movimientos_inventario
       WHERE created_at >= NOW() - INTERVAL '1 hour')
        AS movimientos_inventario_ultima_hora,
    NOW() AS chequeado_en;


-- ── 12. ✅ DIAGNÓSTICO RESUMIDO (texto plano para humanos) ───────────

SELECT
    'DIAGNOSTICO' AS resumen,
    CASE
        -- ✅ CORREGIDO: usar to_regprocedure (función) en lugar de tablas.
        WHEN to_regprocedure('public.fn_user_rol()') IS NULL
        THEN 'STOP — falta función fn_user_rol. Ejecutar 02A_hotfix_fn_user_rol.sql.'
        WHEN (SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema='public' AND table_name='usuarios_perfil') = 0
        THEN 'STOP — tabla usuarios_perfil no existe. Aplicar mig 02 primero.'
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
-- INTERPRETACION
-- ============================================================================
-- Lee el resultado de la query (12).
--
-- Si dice "STOP — falta función fn_user_rol":
--   → ejecutar 02A_hotfix_fn_user_rol.sql.
--   → re-ejecutar este v2.
--
-- Si dice "WARNING — productos con stock sin costo":
--   → manejar en paso 09 con Finanzas.
--
-- Si dice "WARNING — estanques con stock":
--   → manejar en paso 12 con Finanzas + varillaje.
--
-- Si dice "WARNING — alta actividad última hora":
--   → confirmar que NO hay usuarios trabajando antes de continuar.
--
-- Si dice "PRECHECKS OK":
--   → avanzar al paso 03.
--
-- La query (11) DIAGNOSTICO_FLAGS te da los mismos datos en formato booleano
-- para más control programático.
-- ============================================================================
