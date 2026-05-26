-- ============================================================================
-- 92_fix_kardex_tipo_traspaso.sql
-- ----------------------------------------------------------------------------
-- BUG: rpc_registrar_traspaso_combustible (MIG76) inserta en
-- combustible_kardex_valorizado con tipo_movimiento 'traspaso_salida' y
-- 'traspaso_entrada', pero el CHECK de la tabla NO los incluye. Resultado:
-- TODO traspaso entre estanques falla (0 traspasos registrados en prod).
--
-- FIX: agregar ambos tipos al constraint. ADITIVO. Instantaneo.
-- (Mismo patron que MIG90/salida_externa: MIG76 introdujo tipos nuevos sin
--  propagarlos al CHECK.)
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
        'salida_externa',
        'traspaso_salida',     -- <-- NUEVO (MIG76: salida del estanque origen)
        'traspaso_entrada',    -- <-- NUEVO (MIG76: entrada al estanque destino)
        'ajuste',
        'varillaje'
    ));

-- Verificacion:
SELECT pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conname = 'combustible_kardex_valorizado_tipo_movimiento_check';
