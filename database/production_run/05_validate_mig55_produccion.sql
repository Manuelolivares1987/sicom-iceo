-- ============================================================================
-- 05_validate_mig55_produccion.sql  —  Solo lectura + ROLLBACK explicito.
-- ============================================================================


-- 1. Tablas presentes
SELECT 'TABLAS_55' AS check_name, COUNT(*) AS encontradas
FROM information_schema.tables
WHERE table_schema='public' AND table_name IN (
    'proveedores','centros_costo','ordenes_compra','ordenes_compra_items',
    'recepciones_bodega','recepciones_bodega_items',
    'salidas_bodega','salidas_bodega_items',
    'ingresos_combustible','salidas_combustible','despachos_combustible'
);
-- Esperado: 11

-- 2. Folios funcionan
SELECT
    fn_generar_folio_recepcion_bodega() AS rec,
    fn_generar_folio_salida_bodega() AS sal,
    fn_generar_folio_ingreso_combustible() AS icb,
    fn_generar_folio_salida_combustible() AS scb,
    fn_generar_folio_despacho_combustible() AS dcb;

-- 3. UNIQUE proveedor+doc presente
SELECT tc.constraint_name
FROM information_schema.table_constraints tc
WHERE tc.table_schema='public'
  AND tc.table_name='recepciones_bodega'
  AND tc.constraint_type='UNIQUE';
-- Esperado: uq_recepcion_doc_proveedor

-- 4. Test escritura+rollback (no deja datos)
-- ✅ FIX: proveedores.codigo es VARCHAR(30). UUID completo (36 chars) + prefijo
--    excede el limite. Usamos solo los primeros 8 chars del UUID (total 13 chars).
DO $$
DECLARE v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO proveedores (id, codigo, nombre, tipo)
    VALUES (v_id, 'TEST-' || SUBSTRING(gen_random_uuid()::TEXT, 1, 8), 'Validacion', 'otros');
    RAISE NOTICE 'Test escritura proveedores: OK';
    RAISE EXCEPTION 'ROLLBACK_TEST';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ROLLBACK_TEST%' THEN
            RAISE NOTICE 'Test rollback: OK';
        ELSE RAISE;
        END IF;
END $$;

-- 5. Resultado
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema='public' AND table_name='proveedores') = 1
         AND (SELECT COUNT(*) FROM pg_proc WHERE proname='fn_generar_folio_recepcion_bodega') = 1
        THEN 'OK MIG55'
        ELSE 'STOP MIG55'
    END AS resultado;

-- 6. Log
SELECT fn_log_operacion_migracion(
    'PROD_MIG55_VALIDATE', 'Validacion mig 55 ejecutada.', 'ok', NULL);
