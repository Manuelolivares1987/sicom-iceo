-- ============================================================================
-- smoke_test_37_bodega_oc_fifo.sql
-- ----------------------------------------------------------------------------
-- Smoke test manual del flujo MIG37: OC -> recepcion FIFO -> salida con
-- CECO/OT y consumo FIFO.
--
-- Hace 1 ciclo completo con valores chicos y auto-descubre los datos
-- (proveedor activo, bodega, producto repuesto/lubricante con stock,
-- CECO activo, OT abierta, usuario admin) para no requerir UUIDs
-- hardcodeados.
--
-- IMPORTANTE — auth.uid() y rol admin:
--   El SQL Editor de Supabase corre como postgres/service_role con
--   auth.uid()=NULL. Las RPCs MIG37 abortan en runtime con "No
--   autenticado". Para el smoke test impostamos un usuario admin via
--   set_config('request.jwt.claim.sub', <uuid>, true). Eso hace que
--   auth.uid() retorne ese UUID durante esta transaccion.
--   Patron es el oficial de Supabase y solo aplica al alcance local.
--
-- Datos generados:
--   - 1 OC con observacion='SMOKE_TEST_MIG37'
--   - 1 recepcion con observacion que contiene 'SMOKE_TEST_MIG37'
--   - 1 capa FIFO ligada a esa recepcion
--   - 1 salida con motivo que contiene 'SMOKE TEST MIG37'
--   - movimientos_inventario legacy (1 entrada + 1 salida) y kardex
--     consistentes
--
-- Cantidad de prueba: 1 unidad. Costo: $1234 CLP (facil de identificar).
--
-- AL FINAL: stock_bodega del producto debe volver al valor inicial.
-- reconciliacion stock vs FIFO debe seguir cuadrada (40/40).
--
-- Identificacion posterior (para limpieza o auditoria):
--   SELECT * FROM ordenes_compra WHERE observacion='SMOKE_TEST_MIG37';
--   SELECT * FROM recepciones_bodega WHERE observacion ILIKE '%SMOKE_TEST_MIG37%';
--   SELECT * FROM salidas_bodega WHERE motivo ILIKE '%SMOKE TEST MIG37%';
-- ============================================================================


-- ============================================================================
-- ── SECCION 1: PRE-DISCOVERY (read-only, opcional) ──────────────────────────
-- Ejecutar y verificar visualmente los candidatos antes del smoke real.
-- Si alguno sale 0 filas, abortar y resolver.
-- ============================================================================

SELECT 'discovery_proveedor' AS dx, id::text AS uuid, codigo, nombre
  FROM proveedores WHERE activo = true ORDER BY codigo LIMIT 3
UNION ALL
SELECT 'discovery_bodega',  id::text, codigo, nombre
  FROM bodegas ORDER BY codigo LIMIT 3
UNION ALL
SELECT 'discovery_ceco',    id::text, codigo, nombre
  FROM centros_costo WHERE activo = true ORDER BY codigo LIMIT 3
UNION ALL
SELECT 'discovery_producto_candidato',
       p.id::text,
       p.codigo,
       p.nombre || ' [' || p.categoria || '] stock=' || sb.cantidad
  FROM productos p
  JOIN stock_bodega sb ON sb.producto_id = p.id
 WHERE p.categoria IN ('repuesto','lubricante','filtro','consumible')
   AND sb.cantidad >= 1
 ORDER BY p.codigo
 LIMIT 5
UNION ALL
SELECT 'discovery_ot_abierta', id::text, folio, estado::text
  FROM ordenes_trabajo
 WHERE estado NOT IN ('cancelada','cerrada')
 ORDER BY created_at DESC LIMIT 3
UNION ALL
SELECT 'discovery_admin', id::text, COALESCE(email, ''), COALESCE(nombre_completo, '')
  FROM usuarios_perfil
 WHERE rol = 'administrador' AND activo = true
 LIMIT 3;


-- ============================================================================
-- ── SECCION 2: SMOKE TEST ATOMICO ───────────────────────────────────────────
-- DO block que impostar admin, descubre datos, ejecuta 3 RPCs y verifica.
-- Si algo no cuadra, RAISE EXCEPTION con mensaje claro y nada queda
-- a medias (todo el DO es 1 transaccion implicita).
-- ============================================================================

DO $$
DECLARE
    -- Datos descubiertos
    v_admin_id        UUID;
    v_admin_email     TEXT;
    v_proveedor_id    UUID;
    v_proveedor_cod   VARCHAR;
    v_bodega_id       UUID;
    v_bodega_cod      VARCHAR;
    v_producto_id     UUID;
    v_producto_cod    VARCHAR;
    v_ceco_id         UUID;
    v_ot_id           UUID;
    v_ot_folio        VARCHAR;

    -- Estados iniciales
    v_stock_inicial    NUMERIC;
    v_capas_disp_ini   INT;
    v_capas_total_ini  INT;

    -- Salidas de RPCs
    v_resp            JSONB;
    v_oc_id           UUID;
    v_oc_numero       VARCHAR;
    v_oc_item_id      UUID;
    v_recepcion_id    UUID;
    v_recepcion_folio VARCHAR;
    v_nueva_capa_id   UUID;
    v_salida_id       UUID;
    v_salida_folio    VARCHAR;
    v_costo_test      NUMERIC := 1234;
    v_qty_test        NUMERIC := 1;

    -- Estados post
    v_stock_post_rec   NUMERIC;
    v_stock_post_sal   NUMERIC;
    v_capa_qty_post    NUMERIC;
    v_consumo_count    INT;
    v_oc_estado_post   TEXT;
    v_desviados        INT;
BEGIN
    -- 1. Descubrir datos
    SELECT id, email INTO v_admin_id, v_admin_email
      FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay usuario_perfil con rol administrador';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_admin_id) THEN
        RAISE EXCEPTION 'STOP - admin % no esta en auth.users (necesario para created_by FK)', v_admin_id;
    END IF;

    -- Impostar admin para que auth.uid() retorne v_admin_id en este alcance
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    -- (verifica que auth.uid() esta funcionando ahora)
    IF auth.uid() IS NULL OR auth.uid() <> v_admin_id THEN
        RAISE EXCEPTION 'STOP - impostor no funciono: auth.uid()=%', auth.uid();
    END IF;

    SELECT id, codigo INTO v_proveedor_id, v_proveedor_cod
      FROM proveedores WHERE activo=true ORDER BY codigo LIMIT 1;
    IF v_proveedor_id IS NULL THEN RAISE EXCEPTION 'STOP - no hay proveedor activo'; END IF;

    SELECT p.id, p.codigo, sb.cantidad, sb.bodega_id
      INTO v_producto_id, v_producto_cod, v_stock_inicial, v_bodega_id
      FROM productos p
      JOIN stock_bodega sb ON sb.producto_id = p.id
     WHERE p.categoria IN ('repuesto','lubricante','filtro','consumible')
       AND sb.cantidad >= 1
     ORDER BY p.codigo LIMIT 1;
    IF v_producto_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay producto repuesto/lubricante/filtro/consumible con stock >= 1';
    END IF;

    SELECT codigo INTO v_bodega_cod FROM bodegas WHERE id = v_bodega_id;

    SELECT id INTO v_ceco_id FROM centros_costo WHERE activo=true ORDER BY codigo LIMIT 1;
    IF v_ceco_id IS NULL THEN RAISE EXCEPTION 'STOP - no hay CECO activo'; END IF;

    SELECT id, folio INTO v_ot_id, v_ot_folio
      FROM ordenes_trabajo WHERE estado NOT IN ('cancelada','cerrada')
      ORDER BY created_at DESC LIMIT 1;
    IF v_ot_id IS NULL THEN RAISE EXCEPTION 'STOP - no hay OT abierta'; END IF;

    SELECT COUNT(*) FILTER (WHERE estado='disponible'),
           COUNT(*)
      INTO v_capas_disp_ini, v_capas_total_ini
      FROM inventario_capas
     WHERE producto_id = v_producto_id AND bodega_id = v_bodega_id;

    RAISE NOTICE '==== SMOKE TEST MIG37 — datos descubiertos ====';
    RAISE NOTICE 'admin......: % (%)',     v_admin_email, v_admin_id;
    RAISE NOTICE 'proveedor..: %',         v_proveedor_cod;
    RAISE NOTICE 'bodega.....: %',         v_bodega_cod;
    RAISE NOTICE 'producto...: % | stock inicial: %', v_producto_cod, v_stock_inicial;
    RAISE NOTICE 'capas disp.: % / total %', v_capas_disp_ini, v_capas_total_ini;
    RAISE NOTICE 'CECO.......: %',         v_ceco_id;
    RAISE NOTICE 'OT.........: % (%)',     v_ot_folio, v_ot_id;
    RAISE NOTICE '';

    -- 2. Crear OC piloto
    v_resp := rpc_crear_orden_compra(
        p_proveedor_id => v_proveedor_id,
        p_items => jsonb_build_array(jsonb_build_object(
            'producto_id', v_producto_id::text,
            'descripcion', 'SMOKE_TEST_MIG37 piloto — eliminar despues',
            'unidad', 'unidad',
            'cantidad_comprada', v_qty_test,
            'precio_unitario_clp', v_costo_test
        )),
        p_observacion => 'SMOKE_TEST_MIG37'
    );
    v_oc_id     := (v_resp->>'orden_compra_id')::UUID;
    v_oc_numero := v_resp->>'numero_oc';
    SELECT id INTO v_oc_item_id FROM ordenes_compra_items
     WHERE orden_compra_id = v_oc_id LIMIT 1;
    IF v_oc_id IS NULL OR v_oc_item_id IS NULL THEN
        RAISE EXCEPTION 'FAIL paso 2: OC o item no creados';
    END IF;
    RAISE NOTICE '[2] OC creada: % (id=%)', v_oc_numero, v_oc_id;

    -- 3. Recepcionar OC completa
    v_resp := rpc_registrar_recepcion_bodega(
        p_proveedor_id => v_proveedor_id,
        p_bodega_id    => v_bodega_id,
        p_doc_tipo     => 'guia'::tipo_documento_proveedor_enum,
        p_doc_numero   => 'SMOKE-' || extract(epoch from now())::bigint::text,
        p_items        => jsonb_build_array(jsonb_build_object(
            'oc_item_id',     v_oc_item_id::text,
            'producto_id',    v_producto_id::text,
            'cantidad',       v_qty_test,
            'costo_unitario', v_costo_test,
            'unidad',         'unidad'
        )),
        p_orden_compra_id => v_oc_id,
        p_observacion     => 'SMOKE_TEST_MIG37 recepcion'
    );
    v_recepcion_id    := (v_resp->>'recepcion_id')::UUID;
    v_recepcion_folio := v_resp->>'folio';
    v_nueva_capa_id   := ((v_resp->'capas_creadas')->0->>'capa_id')::UUID;
    RAISE NOTICE '[3] Recepcion: % (id=%) capa nueva=%',
        v_recepcion_folio, v_recepcion_id, v_nueva_capa_id;

    -- Verificaciones post-recepcion
    SELECT cantidad INTO v_stock_post_rec
      FROM stock_bodega WHERE producto_id = v_producto_id AND bodega_id = v_bodega_id;
    IF v_stock_post_rec <> v_stock_inicial + v_qty_test THEN
        RAISE EXCEPTION 'FAIL post-recepcion: stock_bodega esperado=%, obtenido=%',
            v_stock_inicial + v_qty_test, v_stock_post_rec;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM inventario_capas
         WHERE id = v_nueva_capa_id
           AND cantidad_disponible = v_qty_test
           AND cantidad_inicial = v_qty_test
           AND costo_unitario = v_costo_test
           AND recepcion_bodega_id = v_recepcion_id
           AND orden_compra_id = v_oc_id
           AND estado = 'disponible'
    ) THEN
        RAISE EXCEPTION 'FAIL post-recepcion: capa nueva mal construida';
    END IF;
    SELECT estado::text INTO v_oc_estado_post FROM ordenes_compra WHERE id = v_oc_id;
    IF v_oc_estado_post NOT IN ('cerrada','parcial') THEN
        RAISE EXCEPTION 'FAIL post-recepcion: OC estado=% (esperado cerrada/parcial)', v_oc_estado_post;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM movimientos_inventario
         WHERE producto_id = v_producto_id AND bodega_id = v_bodega_id
           AND tipo = 'entrada' AND documento_referencia = v_recepcion_folio
    ) THEN
        RAISE EXCEPTION 'FAIL post-recepcion: no se creo movimientos_inventario tipo entrada con doc=%',
            v_recepcion_folio;
    END IF;
    RAISE NOTICE '   OK stock %->%  | OC=%  | capa=disp/qty=%  | mov entrada registrado',
        v_stock_inicial, v_stock_post_rec, v_oc_estado_post, v_qty_test;

    -- 4. Salida a OT con CECO (consume FIFO — capa mas antigua disponible)
    v_resp := rpc_registrar_salida_bodega(
        p_tipo_salida => 'ot'::tipo_salida_bodega_enum,
        p_bodega_id   => v_bodega_id,
        p_ceco_id     => v_ceco_id,
        p_ot_id       => v_ot_id,
        p_motivo      => 'SMOKE TEST MIG37 despacho piloto',
        p_items       => jsonb_build_array(jsonb_build_object(
            'producto_id', v_producto_id::text,
            'cantidad',    v_qty_test,
            'unidad',      'unidad'
        )),
        p_observacion => 'SMOKE_TEST_MIG37 salida'
    );
    v_salida_id    := (v_resp->>'salida_id')::UUID;
    v_salida_folio := v_resp->>'folio';
    RAISE NOTICE '[4] Salida: % (id=%)', v_salida_folio, v_salida_id;

    -- Verificaciones post-salida
    SELECT cantidad INTO v_stock_post_sal
      FROM stock_bodega WHERE producto_id = v_producto_id AND bodega_id = v_bodega_id;
    IF v_stock_post_sal <> v_stock_inicial THEN
        RAISE EXCEPTION 'FAIL post-salida: stock_bodega deberia volver a % (inicial), obtenido %',
            v_stock_inicial, v_stock_post_sal;
    END IF;

    SELECT COUNT(*), SUM(cantidad_consumida)
      INTO v_consumo_count, v_capa_qty_post
      FROM inventario_consumos_capas
     WHERE salida_bodega_id = v_salida_id
       AND ot_id = v_ot_id
       AND ceco_id = v_ceco_id
       AND producto_id = v_producto_id;
    IF v_consumo_count = 0 THEN
        RAISE EXCEPTION 'FAIL post-salida: no se registro consumo FIFO con OT y CECO esperados';
    END IF;
    IF v_capa_qty_post <> v_qty_test THEN
        RAISE EXCEPTION 'FAIL post-salida: suma cantidad_consumida=% esperado=%', v_capa_qty_post, v_qty_test;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM movimientos_inventario
         WHERE producto_id = v_producto_id AND bodega_id = v_bodega_id
           AND tipo = 'salida' AND ot_id = v_ot_id
           AND created_at >= NOW() - INTERVAL '5 minutes'
    ) THEN
        RAISE EXCEPTION 'FAIL post-salida: no se registro movimientos_inventario tipo salida con OT %',
            v_ot_id;
    END IF;
    RAISE NOTICE '   OK stock %->%  | consumo capas=%, qty total=%  | mov salida registrado',
        v_stock_post_rec, v_stock_post_sal, v_consumo_count, v_capa_qty_post;

    -- 5. Reconciliacion final
    SELECT COUNT(*) INTO v_desviados
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados <> 0 THEN
        RAISE EXCEPTION 'FAIL reconciliacion: % filas desviadas tras el ciclo', v_desviados;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '==== SMOKE TEST PASS ====';
    RAISE NOTICE 'OC piloto.........: %',  v_oc_numero;
    RAISE NOTICE 'Recepcion.........: %',  v_recepcion_folio;
    RAISE NOTICE 'Salida............: %',  v_salida_folio;
    RAISE NOTICE 'Capa nueva (id)...: %',  v_nueva_capa_id;
    RAISE NOTICE 'stock_bodega vuelta a inicial: %', v_stock_post_sal;
    RAISE NOTICE 'Reconciliacion: 0 desviadas (cuadrado integro)';
END $$;


-- ============================================================================
-- ── SECCION 3: VALIDACION POST (read-only) ──────────────────────────────────
-- Resultset visual de los registros creados por el smoke test.
-- ============================================================================

WITH oc AS (
    SELECT id FROM ordenes_compra WHERE observacion = 'SMOKE_TEST_MIG37'
),
rec AS (
    SELECT id, folio_recepcion FROM recepciones_bodega WHERE observacion ILIKE '%SMOKE_TEST_MIG37%'
),
sal AS (
    SELECT id, folio_salida FROM salidas_bodega WHERE motivo ILIKE '%SMOKE TEST MIG37%'
)
SELECT 'OC' AS tipo, numero_oc AS folio, estado::text AS estado,
       monto_total_clp::text AS monto, observacion AS detalle
  FROM ordenes_compra WHERE id IN (SELECT id FROM oc)
UNION ALL
SELECT 'OC_item', '', estado::text, cantidad_recibida::text || '/' || cantidad_comprada::text,
       descripcion
  FROM ordenes_compra_items WHERE orden_compra_id IN (SELECT id FROM oc)
UNION ALL
SELECT 'Recepcion', folio_recepcion, estado, '', observacion
  FROM recepciones_bodega WHERE id IN (SELECT id FROM rec)
UNION ALL
SELECT 'Recepcion_item', '', '',
       cantidad_recibida::text || ' x ' || costo_unitario_clp::text,
       observacion
  FROM recepciones_bodega_items
 WHERE recepcion_id IN (SELECT id FROM rec)
UNION ALL
SELECT 'Capa', folio_recepcion, estado,
       cantidad_disponible::text || '/' || cantidad_inicial::text,
       'costo_unit=' || costo_unitario::text
  FROM inventario_capas
 WHERE recepcion_bodega_id IN (SELECT id FROM rec)
UNION ALL
SELECT 'Salida', folio_salida, tipo_salida::text, '', motivo
  FROM salidas_bodega WHERE id IN (SELECT id FROM sal)
UNION ALL
SELECT 'Salida_item', '', '',
       cantidad::text || ' x ' || costo_unitario_clp::text, ''
  FROM salidas_bodega_items WHERE salida_id IN (SELECT id FROM sal)
UNION ALL
SELECT 'Consumo_FIFO', '', '',
       cantidad_consumida::text || ' x ' || costo_unitario_capa::text,
       'ot=' || COALESCE(ot_id::text,'-') || ' ceco=' || COALESCE(ceco_id::text,'-')
  FROM inventario_consumos_capas
 WHERE salida_bodega_id IN (SELECT id FROM sal);


-- Reconciliacion post-test
SELECT 'reconciliacion_post_smoke' AS dx,
       estado_reconciliacion       AS estado,
       COUNT(*)::text               AS productos
  FROM v_bodega_reconciliacion_stock_fifo
 GROUP BY estado_reconciliacion
 ORDER BY estado_reconciliacion;


-- ============================================================================
-- ── SECCION 4: CLEANUP MANUAL (comentado — no ejecutar automaticamente) ─────
-- ----------------------------------------------------------------------------
-- Si quieres eliminar la huella del smoke test, ejecutar en orden:
-- (ATENCION: tambien tendrias que reversar el movimiento legacy y el stock,
--  lo cual es mas complejo. Mejor dejar los datos piloto como evidencia.)
--
-- BEGIN;
-- DELETE FROM inventario_consumos_capas
--  WHERE salida_bodega_id IN (SELECT id FROM salidas_bodega WHERE motivo ILIKE '%SMOKE TEST MIG37%');
-- DELETE FROM salidas_bodega_items
--  WHERE salida_id IN (SELECT id FROM salidas_bodega WHERE motivo ILIKE '%SMOKE TEST MIG37%');
-- DELETE FROM salidas_bodega WHERE motivo ILIKE '%SMOKE TEST MIG37%';
-- DELETE FROM inventario_capas
--  WHERE recepcion_bodega_id IN (SELECT id FROM recepciones_bodega WHERE observacion ILIKE '%SMOKE_TEST_MIG37%');
-- DELETE FROM recepciones_bodega_items
--  WHERE recepcion_id IN (SELECT id FROM recepciones_bodega WHERE observacion ILIKE '%SMOKE_TEST_MIG37%');
-- DELETE FROM recepciones_bodega WHERE observacion ILIKE '%SMOKE_TEST_MIG37%';
-- DELETE FROM ordenes_compra_items WHERE orden_compra_id IN (SELECT id FROM ordenes_compra WHERE observacion='SMOKE_TEST_MIG37');
-- DELETE FROM ordenes_compra WHERE observacion='SMOKE_TEST_MIG37';
-- -- Aun queda: movimientos_inventario (1 entrada + 1 salida), kardex, stock_bodega
-- --           se neutralizan entre si pero quedan registrados como evidencia.
-- ROLLBACK; -- cambiar a COMMIT si confirmas
-- ============================================================================
