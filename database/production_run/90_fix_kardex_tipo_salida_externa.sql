-- ============================================================================
-- 90_fix_kardex_tipo_salida_externa.sql
-- ----------------------------------------------------------------------------
-- BUG: MIG64 (salida a vehiculo externo) inserta en combustible_kardex_valorizado
-- con tipo_movimiento = 'salida_externa', pero el CHECK de la tabla (de MIG57)
-- NO incluye ese valor. Resultado: TODA salida externa de combustible falla con
--   "new row ... violates check constraint
--    combustible_kardex_valorizado_tipo_movimiento_check"
--
-- FIX: agregar 'salida_externa' a la lista de valores permitidos.
-- ADITIVO. No migra datos. Instantaneo.
-- ============================================================================

ALTER TABLE combustible_kardex_valorizado
    DROP CONSTRAINT IF EXISTS combustible_kardex_valorizado_tipo_movimiento_check;

ALTER TABLE combustible_kardex_valorizado
    ADD CONSTRAINT combustible_kardex_valorizado_tipo_movimiento_check
    CHECK (tipo_movimiento IN (
        'stock_inicial',
        'ingreso_compra',
        'salida_venta',
        'salida_equipo',
        'salida_despacho',
        'salida_externa',   -- <-- NUEVO (MIG64 lo usa para despacho a vehiculo externo)
        'ajuste',
        'varillaje'
    ));

-- Verificacion:
SELECT pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conname = 'combustible_kardex_valorizado_tipo_movimiento_check';
