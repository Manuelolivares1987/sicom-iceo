-- ============================================================================
-- 09_seed_stock_inicial_combustible.sql  —  Plantilla manual.
-- ----------------------------------------------------------------------------
-- Stock inicial por estanque. NO ejecutar a ciegas.
-- Para CADA estanque con stock_teorico_lt > 0, llamar
-- rpc_registrar_stock_inicial_combustible con los costos historicos validados
-- por Finanzas.
-- ============================================================================


-- ── 1. Listar estanques actuales ─────────────────────────────────────

SELECT
    id,
    codigo,
    nombre,
    capacidad_lt,
    stock_teorico_lt,
    costo_promedio_lt,
    valor_total_stock
FROM combustible_estanques
WHERE activo = true
ORDER BY codigo;


-- ── 2. Verificar que NO haya stock_inicial ya creado ─────────────────

SELECT
    e.codigo,
    si.id  AS stock_inicial_id,
    si.fecha,
    si.litros_iniciales,
    si.costo_unitario_inicial,
    si.anulado
FROM combustible_estanques e
LEFT JOIN combustible_stock_inicial si
       ON si.estanque_id = e.id
      AND si.anulado = false
WHERE e.activo = true
ORDER BY e.codigo;
-- Si stock_inicial_id es NOT NULL, ese estanque ya tiene partida activa.


-- ── 3. PLANTILLA: registrar stock inicial por estanque ───────────────
-- ATENCION: el role-check de la RPC exige rol administrador o
-- subgerente_operaciones. Si ejecutas con rol distinto, fallara.
-- Reemplaza:
--   <ESTANQUE_ID>      por el UUID real
--   <FECHA>            por la fecha de apertura (CURRENT_DATE recomendable)
--   <LITROS_FISICOS>   por los litros medidos por varillaje hoy
--   <COSTO_HISTORICO>  por el costo $/lt validado por Finanzas
--   <DOC_URL>          opcional: URL a documento respaldo (puede ser NULL)
--   <OBS>              observacion (min 5 caracteres)

/*
SELECT rpc_registrar_stock_inicial_combustible(
    p_estanque_id              => '<ESTANQUE_ID>',
    p_fecha                    => CURRENT_DATE,
    p_litros_iniciales         => 1000,        -- ejemplo
    p_costo_unitario_inicial   => 900.0000,    -- ejemplo
    p_documento_respaldo_url   => NULL,
    p_observacion              => 'Apertura piloto staging. Stock varillaje fisico verificado. Costo historico estimado por Finanzas segun ultima compra ENEX.'
);
*/

-- Para multiples estanques, repetir el SELECT arriba con distintos parametros.
-- O crear un loop manual con DO block:

/*
DO $$
DECLARE
    v_estanque RECORD;
BEGIN
    FOR v_estanque IN
        SELECT id, codigo, stock_teorico_lt
          FROM combustible_estanques
         WHERE activo = true
           AND stock_teorico_lt > 0
           AND id NOT IN (SELECT estanque_id FROM combustible_stock_inicial WHERE anulado = false)
    LOOP
        RAISE NOTICE 'Estanque % requiere stock_inicial: % lt actuales.', v_estanque.codigo, v_estanque.stock_teorico_lt;
        -- AGREGAR: PERFORM rpc_registrar_stock_inicial_combustible(...)
        -- con costos especificos validados.
    END LOOP;
END $$;
*/


-- ── 4. Verificacion post-ejecucion ───────────────────────────────────

SELECT * FROM v_combustible_stock_valorizado_actual ORDER BY estanque_codigo;
-- Cada estanque debe tener:
--   - stock_teorico_lt = litros fisicos verificados.
--   - costo_promedio_lt > 0 (no debe ser 0 si hubo stock).
--   - valor_total_stock = stock_teorico_lt * costo_promedio_lt.

SELECT
    'KARDEX_INICIAL' AS check_name,
    COUNT(*) AS movimientos_stock_inicial
FROM combustible_kardex_valorizado
WHERE tipo_movimiento = 'stock_inicial';


-- ============================================================================
-- INSTRUCCIONES PARA OPERADOR
-- ============================================================================
-- 1. Hacer query (1) para listar estanques.
-- 2. Hacer query (2) para confirmar que ningun estanque tiene stock_inicial activo.
-- 3. Coordinar con Finanzas:
--    - litros fisicos por estanque (varillaje del dia de aplicacion).
--    - costo historico $/lt por estanque (ultima compra documentada).
-- 4. Para cada estanque, descomentar la query (3), ajustar valores y ejecutar.
-- 5. Verificar con query (4): la vista debe mostrar valor_total_stock correcto.
-- ============================================================================
