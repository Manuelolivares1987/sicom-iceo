-- ============================================================================
-- smoke_test_38_oc_externa_servicio.sql
-- ----------------------------------------------------------------------------
-- Smoke test runtime de MIG38-A con la OC ejemplo Pillado N°13559
-- (VOLVO CHILE SPA, item SERSEGCER006 — SERVICIO CERTIFICACION
-- OPERATIVIDAD).
--
-- Valida:
--   1. rpc_importar_orden_compra_externa funciona end-to-end.
--   2. UNIQUE parcial bloquea reimport.
--   3. Rama documental de rpc_registrar_recepcion_bodega no toca stock
--      ni crea capas FIFO.
--   4. Reconciliacion stock vs FIFO se mantiene 40/40 cuadrada.
--
-- IDEMPOTENTE: si una corrida previa creo la OC, este script la reusa
-- sin RAISE — solo el sub-test 'duplicado_bloqueado' lo confirma.
--
-- SUPABASE SQL EDITOR: ejecuta como service_role. Para que las RPCs
-- pasen su check 'No autenticado' impostamos un admin con
-- set_config('request.jwt.claim.sub', <uuid>, true).
--
-- NO TOCA STOCK. NO MUEVE CAPAS. NO CREA CAPAS FIFO. NO ACTIVA
-- COMBUSTIBLE NI SELLOS.
-- ============================================================================


-- ── Tabla temporal de resultados ────────────────────────────────────────────
DROP TABLE IF EXISTS smoke_38_resultados;
CREATE TEMP TABLE smoke_38_resultados (
    paso       TEXT PRIMARY KEY,
    ok         BOOLEAN NOT NULL,
    detalle    TEXT,
    extra_json JSONB
);


-- ── Smoke test ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    -- Datos del test
    c_numero_oc_externo CONSTANT VARCHAR := '13559';
    c_rut_volvo         CONSTANT VARCHAR := '76.284.920-8';
    c_codigo_externo    CONSTANT VARCHAR := 'SERSEGCER006';

    -- IDs descubiertos
    v_admin_id      UUID;
    v_admin_email   TEXT;
    v_proveedor_id  UUID;
    v_bodega_id     UUID;
    v_bodega_cod    VARCHAR;
    v_oc_id         UUID;
    v_oc_numero     VARCHAR;
    v_oc_item_id    UUID;

    -- Snapshots
    v_cuadrado_ini  INT; v_desviado_ini  INT;
    v_cuadrado_post INT; v_desviado_post INT;
    v_stock_total_ini  NUMERIC; v_stock_total_post NUMERIC;
    v_capas_total_ini  INT;     v_capas_total_post INT;
    v_valor_fifo_ini   NUMERIC; v_valor_fifo_post  NUMERIC;

    -- Estado
    v_proveedor_creado    BOOLEAN := FALSE;
    v_oc_creada           BOOLEAN := FALSE;
    v_recepcion_creada    BOOLEAN := FALSE;
    v_duplicado_bloqueado BOOLEAN := FALSE;
    v_pendiente_pre       NUMERIC;
    v_pendiente_post      NUMERIC;
    v_cant_recibida_post  NUMERIC;
    v_capas_de_esta_oc    INT;
    v_mov_inv_de_oc       INT;

    -- Buffers
    v_resp          JSONB;
    v_recepcion_id  UUID;
    v_msg           TEXT;
BEGIN
    ------------------------------------------------------------------ PRECHECK
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_importar_orden_compra_externa') THEN
        RAISE EXCEPTION 'STOP - rpc_importar_orden_compra_externa no existe (MIG38-A no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_recepcion_bodega') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_recepcion_bodega no existe';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='ordenes_compra_items'
                      AND column_name='tipo_item') THEN
        RAISE EXCEPTION 'STOP - ordenes_compra_items.tipo_item no existe (MIG38 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='recepciones_bodega_items'
                      AND column_name='recepcion_documental') THEN
        RAISE EXCEPTION 'STOP - recepciones_bodega_items.recepcion_documental no existe';
    END IF;

    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_ini, v_desviado_ini
      FROM v_bodega_reconciliacion_stock_fifo;
    IF v_desviado_ini > 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion inicial no cuadrada (% desviados)', v_desviado_ini;
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '01_precheck_mig38', TRUE,
        format('MIG38 aplicada. Reconciliacion inicial: %s cuadrado / %s desviado', v_cuadrado_ini, v_desviado_ini),
        jsonb_build_object('cuadrado_ini', v_cuadrado_ini, 'desviado_ini', v_desviado_ini)
    );

    --------------------------------------------------------- SNAPSHOT INICIAL
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_total_ini FROM stock_bodega;
    SELECT COUNT(*), COALESCE(SUM(cantidad_disponible * costo_unitario), 0)
      INTO v_capas_total_ini, v_valor_fifo_ini
      FROM inventario_capas WHERE estado='disponible';

    INSERT INTO smoke_38_resultados VALUES (
        '02_snapshot_inicial', TRUE,
        format('stock_total=%s capas=%s valor_fifo=%s', v_stock_total_ini, v_capas_total_ini, v_valor_fifo_ini),
        jsonb_build_object(
            'stock_total_ini',   v_stock_total_ini,
            'capas_total_ini',   v_capas_total_ini,
            'valor_fifo_ini',    v_valor_fifo_ini
        )
    );

    ----------------------------------------------------- IMPOSTAR ADMIN
    SELECT id, email INTO v_admin_id, v_admin_email
      FROM usuarios_perfil WHERE rol='administrador' AND activo=true LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay usuario admin en usuarios_perfil';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_admin_id) THEN
        RAISE EXCEPTION 'STOP - admin % no esta en auth.users (necesario para FK)', v_admin_id;
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    IF auth.uid() IS NULL OR auth.uid() <> v_admin_id THEN
        RAISE EXCEPTION 'STOP - impostor no funciono: auth.uid()=%', auth.uid();
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '03_admin_impostado', TRUE,
        format('admin=%s auth.uid()=%s', v_admin_email, auth.uid()),
        jsonb_build_object('admin_id', v_admin_id, 'admin_email', v_admin_email)
    );

    ------------------------------------------------------- PROVEEDOR VOLVO
    SELECT id INTO v_proveedor_id FROM proveedores WHERE rut = c_rut_volvo;

    IF v_proveedor_id IS NULL THEN
        INSERT INTO proveedores (codigo, nombre, rut, tipo, activo, observaciones)
        VALUES (
            'VOLVO-' || SUBSTRING(MD5(random()::text), 1, 6),
            'VOLVO CHILE SPA',
            c_rut_volvo,
            'servicios'::tipo_proveedor_enum,
            TRUE,
            'Creado por smoke_test_38_oc_externa_servicio.sql'
        )
        RETURNING id INTO v_proveedor_id;
        v_proveedor_creado := TRUE;
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '04_proveedor_volvo', TRUE,
        format('proveedor_id=%s (creado=%s)', v_proveedor_id, v_proveedor_creado),
        jsonb_build_object('proveedor_id', v_proveedor_id, 'creado', v_proveedor_creado)
    );

    ----------------------------------------- IMPORTAR OC EXTERNA (idempotente)
    -- Si ya existe (corrida previa) la reutilizamos sin reimportar.
    SELECT id, numero_oc INTO v_oc_id, v_oc_numero
      FROM ordenes_compra
     WHERE proveedor_id = v_proveedor_id AND numero_oc_externo = c_numero_oc_externo;

    IF v_oc_id IS NULL THEN
        BEGIN
            v_resp := rpc_importar_orden_compra_externa(
                p_proveedor_id      => v_proveedor_id,
                p_numero_oc_externo => c_numero_oc_externo,
                p_proveedor_rut     => c_rut_volvo,
                p_fecha_emision     => '2026-05-07'::DATE,
                p_fecha_entrega     => '2026-05-07'::DATE,
                p_neto_clp          => 290700,
                p_iva_clp           => 55233,
                p_forma_pago        => '30 dias',
                p_items             => jsonb_build_array(jsonb_build_object(
                    'codigo_externo',    c_codigo_externo,
                    'descripcion',       'SERVICIO CERTIFICACION OPERATIVIDAD',
                    'cantidad_comprada', 1,
                    'unidad',            'unidad',
                    'unidad_externa',    'UN',
                    'precio_unitario_clp', 290700,
                    'tipo_item',         'servicio',
                    'requiere_stock',    false,
                    'centro_costo_codigo_externo', 'CC-15-15'
                )),
                p_observacion       => 'Smoke MIG38 — VOLVO 13559 cert operatividad'
            );
            v_oc_id     := (v_resp->>'orden_compra_id')::UUID;
            v_oc_numero := v_resp->>'numero_oc';
            v_oc_creada := TRUE;
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO smoke_38_resultados VALUES (
                '05_importar_oc_externa', FALSE,
                'Fallo al importar: ' || SQLERRM,
                jsonb_build_object('sqlerrm', SQLERRM, 'sqlstate', SQLSTATE)
            );
            RAISE;
        END;
    ELSE
        v_oc_creada := FALSE;  -- reutilizada
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '05_importar_oc_externa', TRUE,
        CASE WHEN v_oc_creada THEN 'OC creada en esta corrida' ELSE 'OC reutilizada de corrida previa' END
            || ' numero=' || v_oc_numero,
        jsonb_build_object(
            'orden_compra_id', v_oc_id,
            'numero_oc',       v_oc_numero,
            'numero_externo',  c_numero_oc_externo,
            'creada_ahora',    v_oc_creada
        )
    );

    --------------------------------------------------- VALIDAR ITEM SERVICIO
    SELECT id INTO v_oc_item_id
      FROM ordenes_compra_items
     WHERE orden_compra_id = v_oc_id
       AND codigo_externo = c_codigo_externo
     LIMIT 1;

    IF v_oc_item_id IS NULL THEN
        INSERT INTO smoke_38_resultados VALUES (
            '06_validar_item_servicio', FALSE,
            'No se encontro item con codigo_externo=' || c_codigo_externo,
            '{}'::jsonb
        );
        RAISE EXCEPTION 'item servicio no encontrado';
    END IF;

    PERFORM 1 FROM ordenes_compra_items
     WHERE id = v_oc_item_id
       AND tipo_item = 'servicio'
       AND requiere_stock = FALSE
       AND producto_id IS NULL
       AND descripcion = 'SERVICIO CERTIFICACION OPERATIVIDAD'
       AND cantidad_comprada = 1
       AND precio_unitario_clp = 290700
       AND centro_costo_codigo_externo = 'CC-15-15';

    IF NOT FOUND THEN
        INSERT INTO smoke_38_resultados VALUES (
            '06_validar_item_servicio', FALSE,
            'Item existe pero atributos no cuadran',
            (SELECT jsonb_build_object(
                'tipo_item', tipo_item, 'requiere_stock', requiere_stock,
                'producto_id', producto_id, 'descripcion', descripcion,
                'cantidad', cantidad_comprada, 'precio', precio_unitario_clp,
                'cc_externo', centro_costo_codigo_externo
             ) FROM ordenes_compra_items WHERE id = v_oc_item_id)
        );
        RAISE EXCEPTION 'item servicio mal armado';
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '06_validar_item_servicio', TRUE,
        'tipo=servicio requiere_stock=false producto_id=NULL desc/cantidad/precio/CC OK',
        jsonb_build_object('oc_item_id', v_oc_item_id)
    );

    -------------------------------------------- TEST DUPLICADO BLOQUEADO
    v_duplicado_bloqueado := FALSE;
    BEGIN
        PERFORM rpc_importar_orden_compra_externa(
            p_proveedor_id      => v_proveedor_id,
            p_numero_oc_externo => c_numero_oc_externo,
            p_items             => jsonb_build_array(jsonb_build_object(
                'descripcion', 'DUP TEST', 'cantidad_comprada', 1,
                'precio_unitario_clp', 1, 'tipo_item', 'servicio'
            ))
        );
        -- Si llegamos aqui, no bloqueo — FAIL
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF v_msg ILIKE '%OC externa duplicada%' THEN
            v_duplicado_bloqueado := TRUE;
        END IF;
    END;

    INSERT INTO smoke_38_resultados VALUES (
        '07_duplicado_bloqueado', v_duplicado_bloqueado,
        CASE WHEN v_duplicado_bloqueado
             THEN 'UNIQUE bloqueo reimport con: ' || v_msg
             ELSE 'NO bloqueo — riesgo de duplicacion!' END,
        jsonb_build_object('sqlerrm', v_msg)
    );

    ------------------------------------------- RECEPCION DOCUMENTAL (idemp)
    SELECT cantidad_pendiente INTO v_pendiente_pre
      FROM ordenes_compra_items WHERE id = v_oc_item_id;

    SELECT id INTO v_bodega_id FROM bodegas ORDER BY codigo LIMIT 1;
    SELECT codigo INTO v_bodega_cod FROM bodegas WHERE id = v_bodega_id;
    IF v_bodega_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay bodega disponible';
    END IF;

    IF v_pendiente_pre > 0 THEN
        BEGIN
            v_resp := rpc_registrar_recepcion_bodega(
                p_proveedor_id    => v_proveedor_id,
                p_bodega_id       => v_bodega_id,
                p_doc_tipo        => 'factura'::tipo_documento_proveedor_enum,
                p_doc_numero      => 'SMOKE38-' || extract(epoch from now())::bigint::text,
                p_items           => jsonb_build_array(jsonb_build_object(
                    'oc_item_id',  v_oc_item_id::text,
                    'cantidad',    v_pendiente_pre,
                    'observacion', 'Smoke MIG38 — servicio recibido conforme'
                )),
                p_orden_compra_id => v_oc_id,
                p_observacion     => 'Smoke MIG38 documental'
            );
            v_recepcion_id     := (v_resp->>'recepcion_id')::UUID;
            v_recepcion_creada := TRUE;
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO smoke_38_resultados VALUES (
                '08_recepcion_documental', FALSE,
                'Fallo: ' || SQLERRM,
                jsonb_build_object('sqlerrm', SQLERRM, 'sqlstate', SQLSTATE)
            );
            RAISE;
        END;
    ELSE
        v_recepcion_creada := FALSE;  -- ya estaba recibido de corrida previa
    END IF;

    SELECT cantidad_recibida, cantidad_pendiente
      INTO v_cant_recibida_post, v_pendiente_post
      FROM ordenes_compra_items WHERE id = v_oc_item_id;

    INSERT INTO smoke_38_resultados VALUES (
        '08_recepcion_documental',
        v_cant_recibida_post = 1,  -- esperado: recibido completo
        format('recibida_post=%s pendiente_post=%s recepcion_id=%s creada_ahora=%s',
               v_cant_recibida_post, v_pendiente_post,
               COALESCE(v_recepcion_id::text, '—'), v_recepcion_creada),
        jsonb_build_object(
            'recepcion_id',     v_recepcion_id,
            'recibida_post',    v_cant_recibida_post,
            'pendiente_post',   v_pendiente_post,
            'creada_ahora',     v_recepcion_creada,
            'response',         v_resp
        )
    );

    ---------------------------------- VALIDAR QUE LA OC NO CREO CAPA FIFO
    SELECT COUNT(*) INTO v_capas_de_esta_oc
      FROM inventario_capas
     WHERE orden_compra_id = v_oc_id;

    INSERT INTO smoke_38_resultados VALUES (
        '09_validar_no_capa_fifo',
        v_capas_de_esta_oc = 0,
        format('capas asociadas a OC piloto: %s (esperado: 0)', v_capas_de_esta_oc),
        jsonb_build_object('capas_de_esta_oc', v_capas_de_esta_oc)
    );

    -------------------------------- VALIDAR QUE NO HUBO MOVIMIENTO INVENTARIO
    -- La recepcion documental NO debe haber generado movimientos_inventario
    -- via rpc_registrar_entrada_inventario.
    IF v_recepcion_creada AND v_recepcion_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_mov_inv_de_oc
          FROM movimientos_inventario
         WHERE documento_referencia IN (
             SELECT folio_recepcion FROM recepciones_bodega WHERE id = v_recepcion_id
         );
    ELSE
        v_mov_inv_de_oc := 0;
    END IF;

    INSERT INTO smoke_38_resultados VALUES (
        '10_validar_no_movimiento_stock',
        v_mov_inv_de_oc = 0,
        format('movimientos_inventario por la recepcion piloto: %s (esperado: 0)', v_mov_inv_de_oc),
        jsonb_build_object('movs_legacy', v_mov_inv_de_oc)
    );

    ---------------------------------------- SNAPSHOT FINAL + RECONCILIACION
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_total_post FROM stock_bodega;
    SELECT COUNT(*), COALESCE(SUM(cantidad_disponible * costo_unitario), 0)
      INTO v_capas_total_post, v_valor_fifo_post
      FROM inventario_capas WHERE estado='disponible';

    SELECT COUNT(*) FILTER (WHERE estado_reconciliacion='cuadrado'),
           COUNT(*) FILTER (WHERE estado_reconciliacion<>'cuadrado')
      INTO v_cuadrado_post, v_desviado_post
      FROM v_bodega_reconciliacion_stock_fifo;

    INSERT INTO smoke_38_resultados VALUES (
        '11_snapshot_final', TRUE,
        format('stock=%s (delta=%s) capas=%s (delta=%s) valor_fifo=%s (delta=%s)',
               v_stock_total_post, v_stock_total_post - v_stock_total_ini,
               v_capas_total_post, v_capas_total_post - v_capas_total_ini,
               v_valor_fifo_post,  v_valor_fifo_post - v_valor_fifo_ini),
        jsonb_build_object(
            'stock_total_post',   v_stock_total_post,
            'capas_total_post',   v_capas_total_post,
            'valor_fifo_post',    v_valor_fifo_post,
            'delta_stock',        v_stock_total_post - v_stock_total_ini,
            'delta_capas',        v_capas_total_post - v_capas_total_ini,
            'delta_valor',        v_valor_fifo_post - v_valor_fifo_ini
        )
    );

    INSERT INTO smoke_38_resultados VALUES (
        '12_reconciliacion_final',
        v_desviado_post = 0 AND v_cuadrado_post = v_cuadrado_ini,
        format('cuadrado=%s desviado=%s (esperado cuadrado=%s desviado=0)',
               v_cuadrado_post, v_desviado_post, v_cuadrado_ini),
        jsonb_build_object(
            'cuadrado_post', v_cuadrado_post,
            'desviado_post', v_desviado_post,
            'cuadrado_ini',  v_cuadrado_ini,
            'desviado_ini',  v_desviado_ini
        )
    );

    RAISE NOTICE '== Smoke MIG38 finalizado. SELECT * FROM smoke_38_resultados ORDER BY paso; ==';
END $$;


-- ── Output consolidado ──────────────────────────────────────────────────────
SELECT paso, ok, detalle, extra_json
  FROM smoke_38_resultados
 ORDER BY paso;


-- ── Verificaciones complementarias (SELECTs independientes) ─────────────────

-- A) Detalle de la OC piloto
SELECT 'OC_piloto' AS dx,
       oc.numero_oc, oc.numero_oc_externo, oc.origen, oc.estado::text AS estado,
       oc.fecha_emision, oc.fecha_entrega,
       oc.neto_clp, oc.iva_clp, oc.monto_total_clp, oc.forma_pago,
       p.codigo AS proveedor_codigo, p.nombre AS proveedor_nombre, p.rut
  FROM ordenes_compra oc
  JOIN proveedores p ON p.id = oc.proveedor_id
 WHERE oc.numero_oc_externo = '13559'
 ORDER BY oc.created_at DESC LIMIT 1;

-- B) Item de la OC piloto
SELECT 'OC_item_piloto' AS dx,
       oci.codigo_externo, oci.descripcion, oci.tipo_item, oci.requiere_stock,
       oci.producto_id, oci.cantidad_comprada, oci.cantidad_recibida,
       oci.cantidad_pendiente, oci.precio_unitario_clp,
       oci.centro_costo_codigo_externo, oci.estado::text AS estado_item
  FROM ordenes_compra_items oci
  JOIN ordenes_compra oc ON oc.id = oci.orden_compra_id
 WHERE oc.numero_oc_externo = '13559'
   AND oci.codigo_externo = 'SERSEGCER006';

-- C) Confirmar que NO existe capa FIFO ligada a la OC piloto
SELECT 'capas_de_oc_piloto' AS dx,
       COUNT(*)::text AS total_capas
  FROM inventario_capas ic
  JOIN ordenes_compra oc ON oc.id = ic.orden_compra_id
 WHERE oc.numero_oc_externo = '13559';
-- Esperado: 0

-- D) Recepcion documental piloto (1 fila)
SELECT 'recepcion_piloto' AS dx,
       rb.folio_recepcion, rb.observacion,
       rbi.cantidad_recibida, rbi.costo_unitario_clp,
       rbi.producto_id, rbi.recepcion_documental
  FROM recepciones_bodega rb
  JOIN recepciones_bodega_items rbi ON rbi.recepcion_id = rb.id
 WHERE rb.observacion ILIKE '%Smoke MIG38%';

-- E) Reconciliacion final
SELECT 'reconciliacion_final' AS dx,
       estado_reconciliacion AS estado,
       COUNT(*)::text AS productos
  FROM v_bodega_reconciliacion_stock_fifo
 GROUP BY estado_reconciliacion;


-- ============================================================================
-- INSTRUCCIONES DE EJECUCION
-- ----------------------------------------------------------------------------
-- 1. Abrir Supabase SQL Editor (rol service_role).
-- 2. Ejecutar el archivo completo.
-- 3. La query principal devuelve la tabla smoke_38_resultados con 12 pasos.
-- 4. Las queries A-E al final devuelven detalles para inspeccion manual.
--
-- RESULTADO ESPERADO en smoke_38_resultados:
--   01_precheck_mig38           ok=true  cuadrado=40 desviado=0
--   02_snapshot_inicial         ok=true  stock_total / capas / valor FIFO
--   03_admin_impostado          ok=true
--   04_proveedor_volvo          ok=true  (creado en 1ra corrida, reusado luego)
--   05_importar_oc_externa      ok=true
--   06_validar_item_servicio    ok=true  tipo=servicio requiere_stock=false
--   07_duplicado_bloqueado      ok=true  UNIQUE bloqueo reimport
--   08_recepcion_documental     ok=true  recibida=1 pendiente=0
--   09_validar_no_capa_fifo     ok=true  capas asociadas a OC = 0
--   10_validar_no_movimiento_stock ok=true  movs_legacy = 0
--   11_snapshot_final           ok=true  delta_stock=0 delta_capas=0 delta_valor=0
--   12_reconciliacion_final     ok=true  cuadrado=40 desviado=0
--
-- Si CUALQUIER paso devuelve ok=false: el detalle indica que fallo y por que.
-- ============================================================================


-- ============================================================================
-- CLEANUP MANUAL (no ejecutar automaticamente — solo si se desea limpiar)
-- ----------------------------------------------------------------------------
-- BEGIN;
-- DELETE FROM recepciones_bodega_items
--  WHERE recepcion_id IN (SELECT id FROM recepciones_bodega WHERE observacion ILIKE '%Smoke MIG38%');
-- DELETE FROM recepciones_bodega WHERE observacion ILIKE '%Smoke MIG38%';
-- DELETE FROM ordenes_compra_items
--  WHERE orden_compra_id IN (SELECT id FROM ordenes_compra WHERE numero_oc_externo='13559');
-- DELETE FROM ordenes_compra WHERE numero_oc_externo='13559';
-- -- Proveedor VOLVO opcional (puede usarse para futuras OC reales):
-- -- DELETE FROM proveedores WHERE rut='76.284.920-8' AND observaciones LIKE '%smoke%';
-- ROLLBACK;  -- cambiar a COMMIT si confirmas
-- ============================================================================
