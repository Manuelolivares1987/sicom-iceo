-- ============================================================================
-- MIG372 · El JGBY-10 no era un dato de demo: vuelve
-- ----------------------------------------------------------------------------
-- MIG355 desactivó dos estanques dándolos por sembrado de la demo de MIG133.
-- Para el JGBY-10 la conclusión estaba mal, y el error fue de método: se miró
-- el Informe de Gestión de julio —que lista los camiones DEL CONTRATO Franke— y
-- se dio por hecho que lo que no estaba ahí no existía. El JGBY-10 no está en
-- ese informe porque no es un camión del contrato; se usa para venta de
-- combustible, que es otra cosa.
--
-- Lo que había que mirar era el kardex, y ahí está todo:
--
--     35.000 L de compras en 5 ingresos      07-jul a 19-ago
--     16.965 L vendidos en 2 salidas         10-ago y 19-ago
--      5.000 L de traspaso de salida         07-jul
--      2.000 L de traspaso de entrada        20-ago
--         35 L de despacho                   19-ago
--
-- El último movimiento es del 20 de agosto: cuatro días antes de que una
-- migración lo declarara inexistente. Y quedó con 15.000 L de saldo que se le
-- habían traspasado para una venta, invisibles desde entonces — no se podían
-- rebajar porque el estanque ya no aparecía en ninguna pantalla.
--
-- LA REGLA QUE FALTÓ, Y QUE QUEDA ESCRITA
-- Un estanque con movimientos en el kardex NO es un dato de demostración,
-- aunque no aparezca en ningún informe. El kardex es el registro de lo que de
-- verdad pasó; un informe es un recorte con un propósito.
--
-- EL KVWD-27 SE QUEDA DESACTIVADO
-- Ése sí: cero movimientos en el kardex, cero litros, creado en el mismo lote
-- de junio y nunca usado. Si mañana aparece, se reactiva con este mismo UPDATE.
-- ============================================================================

BEGIN;

UPDATE public.combustible_estanques e
   SET activo = TRUE,
       observaciones = 'Reactivado en MIG372: NO era un dato de demo. Tiene movimientos '
                    || 'reales en el kardex desde julio 2026 y saldo pendiente de rebajar. '
                    || 'Se usa para venta de combustible, por eso no figura en el informe '
                    || 'del contrato Franke.',
       updated_at = NOW()
 WHERE e.patente = 'JGBY-10'
   AND EXISTS (SELECT 1 FROM public.combustible_kardex_valorizado k
                WHERE k.estanque_id = e.id);

-- Un estanque que no aparece es un estanque cuyo saldo nadie puede corregir.
-- Si el UPDATE de arriba no encontró nada, algo cambió y hay que mirarlo.
DO $v$
DECLARE v_ok BOOLEAN;
BEGIN
    SELECT activo INTO v_ok FROM public.combustible_estanques WHERE patente = 'JGBY-10';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'MIG372: el JGBY-10 sigue desactivado — revisar a mano';
    END IF;
    RAISE NOTICE 'MIG372 · JGBY-10 activo de nuevo, con % L de saldo por rebajar',
        (SELECT stock_teorico_lt FROM public.combustible_estanques WHERE patente = 'JGBY-10');
END
$v$;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT codigo, patente, activo, stock_teorico_lt,
--        (SELECT count(*) FROM combustible_kardex_valorizado k WHERE k.estanque_id = e.id) AS movimientos
--   FROM combustible_estanques e WHERE patente IN ('JGBY-10','KVWD-27');
