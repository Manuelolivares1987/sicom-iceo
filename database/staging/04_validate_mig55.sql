-- ============================================================================
-- 04_validate_mig55.sql  —  Solo lectura + transaccion ROLLBACK.
-- ----------------------------------------------------------------------------
-- Confirma que mig 55 quedo aplicada y que las tablas/RPCs basicas funcionan.
-- ============================================================================


-- ── 1. Tablas creadas ────────────────────────────────────────────────
SELECT
    'TABLAS_55' AS check_name,
    array_agg(table_name ORDER BY table_name) AS encontradas
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'proveedores','centros_costo','ordenes_compra','ordenes_compra_items',
    'recepciones_bodega','recepciones_bodega_items',
    'salidas_bodega','salidas_bodega_items',
    'ingresos_combustible','salidas_combustible','despachos_combustible'
  );
-- Esperado: 11 tablas


-- ── 2. Folios secuenciales funcionan ─────────────────────────────────
SELECT
    fn_generar_folio_recepcion_bodega() AS folio_recepcion,
    fn_generar_folio_salida_bodega()    AS folio_salida_bodega,
    fn_generar_folio_ingreso_combustible() AS folio_ingreso_comb,
    fn_generar_folio_salida_combustible()  AS folio_salida_comb,
    fn_generar_folio_despacho_combustible() AS folio_despacho;
-- Esperado: 5 folios formato XXX-YYYYMM-00001


-- ── 3. Test de simulacion: crear OC + recepcion + salida (con ROLLBACK) ──
DO $$
DECLARE
    v_proveedor_id   UUID;
    v_ceco_id        UUID;
    v_bodega_id      UUID;
    v_producto_id    UUID;
    v_oc_id          UUID := gen_random_uuid();
    v_oc_item_id     UUID := gen_random_uuid();
    v_recepcion_id   UUID := gen_random_uuid();
    v_salida_id      UUID := gen_random_uuid();
BEGIN
    -- Cargar maestros
    SELECT id INTO v_proveedor_id FROM proveedores WHERE codigo='ENEX' LIMIT 1;
    SELECT id INTO v_ceco_id      FROM centros_costo WHERE codigo LIKE 'CECO-%' LIMIT 1;
    SELECT id INTO v_bodega_id    FROM bodegas LIMIT 1;
    SELECT id INTO v_producto_id  FROM productos LIMIT 1;

    IF v_proveedor_id IS NULL OR v_ceco_id IS NULL OR v_bodega_id IS NULL OR v_producto_id IS NULL THEN
        RAISE NOTICE 'TEST OMITIDO: faltan datos maestros (proveedor=%, ceco=%, bodega=%, producto=%)',
            v_proveedor_id, v_ceco_id, v_bodega_id, v_producto_id;
        RETURN;
    END IF;

    -- Crear OC (no commit — se hara rollback al final del DO block)
    INSERT INTO ordenes_compra (id, numero_oc, proveedor_id, fecha_oc, monto_total_clp, observacion)
    VALUES (v_oc_id, 'TEST-OC-VAL-' || gen_random_uuid()::TEXT, v_proveedor_id, CURRENT_DATE, 100000, 'Test validacion');

    INSERT INTO ordenes_compra_items (id, orden_compra_id, producto_id, descripcion, cantidad_comprada, precio_unitario_clp)
    VALUES (v_oc_item_id, v_oc_id, v_producto_id, 'Item test', 10, 10000);

    -- Crear recepcion
    INSERT INTO recepciones_bodega (
        id, folio_recepcion, orden_compra_id, proveedor_id, bodega_id,
        documento_proveedor_tipo, documento_proveedor_numero, observacion
    ) VALUES (
        v_recepcion_id, fn_generar_folio_recepcion_bodega(),
        v_oc_id, v_proveedor_id, v_bodega_id,
        'guia', 'TEST-' || gen_random_uuid()::TEXT, 'Test'
    );

    INSERT INTO recepciones_bodega_items (
        recepcion_id, orden_compra_item_id, producto_id, cantidad_recibida, costo_unitario_clp
    ) VALUES (
        v_recepcion_id, v_oc_item_id, v_producto_id, 5, 10000
    );

    -- Crear salida tipo CECO
    INSERT INTO salidas_bodega (
        id, folio_salida, tipo_salida, ceco_id, bodega_id, motivo
    ) VALUES (
        v_salida_id, fn_generar_folio_salida_bodega(),
        'ceco', v_ceco_id, v_bodega_id, 'Test validacion mig 55'
    );

    INSERT INTO salidas_bodega_items (salida_id, producto_id, cantidad)
    VALUES (v_salida_id, v_producto_id, 2);

    RAISE NOTICE 'TEST OK: OC + recepcion + salida creados (en transaccion).';

    -- Rollback explicito para no contaminar staging
    RAISE EXCEPTION 'ROLLBACK_INTENCIONAL_TEST';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ROLLBACK_INTENCIONAL_TEST%' THEN
            RAISE NOTICE 'TEST COMPLETADO (rollback intencional ejecutado).';
        ELSE
            RAISE NOTICE 'TEST FALLO: %', SQLERRM;
            RAISE;
        END IF;
END $$;


-- ── 4. Constraint UNIQUE proveedor+doc funciona ──────────────────────
-- (No se ejecuta — solo para revision visual)
SELECT
    tc.constraint_name, tc.table_name, kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name = 'recepciones_bodega'
  AND tc.constraint_type = 'UNIQUE'
ORDER BY tc.constraint_name, kcu.ordinal_position;
-- Esperado: uq_recepcion_doc_proveedor con (proveedor_id, documento_proveedor_tipo, documento_proveedor_numero)


-- ── 5. CHECK constraints despacho con sellos ─────────────────────────
SELECT
    cc.constraint_name, cc.check_clause
FROM information_schema.check_constraints cc
JOIN information_schema.constraint_column_usage ccu
  ON cc.constraint_name = ccu.constraint_name
WHERE ccu.table_name = 'despachos_combustible'
  AND cc.constraint_name LIKE 'chk_despacho_%'
ORDER BY cc.constraint_name;
-- Esperado: 2 CHECK (sellos_salida + sellos_entrega)


-- ── 6. Resumen final ─────────────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM proveedores WHERE activo=true) AS proveedores_activos,
    (SELECT COUNT(*) FROM centros_costo WHERE activo=true) AS ceco_activos,
    (SELECT COUNT(*) FROM ordenes_compra) AS ocs_existentes,
    (SELECT COUNT(*) FROM recepciones_bodega) AS recepciones,
    (SELECT COUNT(*) FROM salidas_bodega) AS salidas;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- Si los tests del DO block dicen "TEST OK" y "TEST COMPLETADO", todo bien.
-- Si dice "TEST OMITIDO", verificar que existan datos maestros minimos:
--   - 1 proveedor activo (tras 02_seed)
--   - 1 CECO activo (tras 02_seed)
--   - 1 bodega
--   - 1 producto
-- ============================================================================
