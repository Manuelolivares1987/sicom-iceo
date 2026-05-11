-- ============================================================================
-- 37_bodega_oc_recepcion_fifo_seguro.sql
-- ----------------------------------------------------------------------------
-- Frente #2 — Activa el flujo transaccional de bodega para repuestos/
-- materiales: Orden de Compra, Recepcion contra OC (con FIFO) y Salida
-- a OT con CECO + consumo FIFO.
--
-- IDEMPOTENTE. ADITIVA. NO TOCA DATOS EXISTENTES.
--
-- Decisiones aplicadas (acordadas con el equipo el 2026-05-10):
--   D1 — Rol "bodeguero" mapeado a operador_abastecimiento. NO se modifica
--        rol_usuario_enum. Roles permitidos en este modulo:
--          administrador, supervisor, subgerente_operaciones,
--          jefe_mantenimiento, operador_abastecimiento (+ planificador
--          para salidas a OT).
--   D2 — Combustible NO entra en MIG37 (diferido a MIG38). Solo repuestos
--        /materiales/lubricantes. Override admin permitido con
--        justificacion >= 10 caracteres.
--   D3 — Sin staging operativo. Mig es solo CREATE OR REPLACE FUNCTION
--        + sequence opcional. Sin DML. Smoke test es manual y opcional.
--   D4 — Despacho combustible con 3 sellos: diferido a MIG38.
--   D5 — Vistas de finanzas (mig 56 BLOCK G, mig 57 BLOCK J): diferidas
--        a MIG38.
--
-- Alcance autorizado:
--   1. rpc_crear_orden_compra
--   2. rpc_registrar_recepcion_bodega  (FIFO-aware; convive con legacy)
--   3. rpc_registrar_salida_bodega     (solo tipo 'ot'; consume FIFO)
--   4. Prechecks obligatorios + validaciones post.
--   5. NO crea OC reales, NO genera recepciones automaticas, NO toca
--      capas existentes, NO recalcula stock.
--
-- Convivencia con legacy:
--   Las RPCs nuevas invocan internamente rpc_registrar_entrada_inventario
--   y rpc_registrar_salida_inventario (mig 09) para mantener stock_bodega
--   y kardex sincronizados con inventario_capas. Sin doble descuento.
--
-- Limitacion conocida (a resolver en MIG38):
--   La constraint legacy chk_mov_salida_requiere_ot impide salidas tipo
--   'salida' o 'merma' en movimientos_inventario sin ot_id. Por eso esta
--   mig solo admite tipo_salida = 'ot'. Los tipos persona/ceco/venta/
--   ajuste_autorizado requieren rediseno de la constraint y se dejan
--   explicitamente para MIG38.
-- ============================================================================


-- ============================================================================
-- ── BLOCK 0  PRECHECKS OBLIGATORIOS ─────────────────────────────────────────
-- Aborta si falta cualquier dependencia o si el inventario no esta cuadrado.
-- ============================================================================

DO $$
DECLARE
    v_n INT;
    v_desviados INT;
    v_capas_negativas INT;
    v_stock_sin_costo INT;
    v_rol TEXT;
BEGIN
    -- 1. Tablas base mig 55 (OC, recepciones, salidas)
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='ordenes_compra') THEN
        RAISE EXCEPTION 'STOP - ordenes_compra no existe (mig 55 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='recepciones_bodega') THEN
        RAISE EXCEPTION 'STOP - recepciones_bodega no existe (mig 55 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='salidas_bodega') THEN
        RAISE EXCEPTION 'STOP - salidas_bodega no existe (mig 55 no aplicada)';
    END IF;

    -- 2. Tablas FIFO mig 56
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='inventario_capas') THEN
        RAISE EXCEPTION 'STOP - inventario_capas no existe (mig 56 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='inventario_consumos_capas') THEN
        RAISE EXCEPTION 'STOP - inventario_consumos_capas no existe (mig 56 no aplicada)';
    END IF;

    -- 3. Funciones legacy invocadas internamente
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_entrada_inventario') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_entrada_inventario no existe (mig 09)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_inventario') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_salida_inventario no existe (mig 09 / 18)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_consumir_inventario_fifo') THEN
        RAISE EXCEPTION 'STOP - fn_consumir_inventario_fifo no existe (mig 56)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - fn_user_rol no existe';
    END IF;

    -- 4. Funciones de folio
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_recepcion_bodega') THEN
        RAISE EXCEPTION 'STOP - fn_generar_folio_recepcion_bodega no existe (mig 55 BLOCK J)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_salida_bodega') THEN
        RAISE EXCEPTION 'STOP - fn_generar_folio_salida_bodega no existe (mig 55 BLOCK J)';
    END IF;

    -- 5. Vista reconciliacion (mig 36)
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname='public'
                    AND viewname='v_bodega_reconciliacion_stock_fifo') THEN
        RAISE EXCEPTION 'STOP - v_bodega_reconciliacion_stock_fifo no existe (mig 36)';
    END IF;

    -- 6. Reconciliacion stock vs FIFO cuadrada (CRITICO)
    SELECT COUNT(*) INTO v_desviados
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados > 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion stock vs FIFO no esta cuadrada (% filas con desviacion). Resolver antes de activar transaccional.', v_desviados;
    END IF;

    -- 7. No hay capas con cantidad_disponible negativa
    SELECT COUNT(*) INTO v_capas_negativas
      FROM inventario_capas WHERE cantidad_disponible < 0;
    IF v_capas_negativas > 0 THEN
        RAISE EXCEPTION 'STOP - hay % capas con cantidad_disponible negativa', v_capas_negativas;
    END IF;

    -- 8. No hay productos con stock > 0 y costo 0
    SELECT COUNT(*) INTO v_stock_sin_costo
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE cantidad_legacy > 0 AND COALESCE(costo_promedio_legacy, 0) = 0;
    IF v_stock_sin_costo > 0 THEN
        RAISE EXCEPTION 'STOP - hay % productos con stock > 0 y costo 0. Resolver antes de activar transaccional.', v_stock_sin_costo;
    END IF;

    -- 9. Usuario ejecutor admin
    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'STOP - fn_user_rol() retorno NULL (sin auth.uid())';
    END IF;
    IF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar mig 37 requiere rol administrador. Rol actual: %', v_rol;
    END IF;

    RAISE NOTICE '== MIG37 prechecks OK ==';
END $$;


-- ── Sequence opcional para numerar OCs autogeneradas (idempotente) ──────────
CREATE SEQUENCE IF NOT EXISTS seq_numero_oc START 1;


-- ============================================================================
-- ── BLOCK 1  rpc_crear_orden_compra ─────────────────────────────────────────
-- Crea una OC con sus items. Sin afectar stock. Sin tocar capas.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_crear_orden_compra(
    p_proveedor_id   UUID,
    p_items          JSONB,         -- array {producto_id?, descripcion, unidad, cantidad_comprada, precio_unitario_clp, observacion?}
    p_numero_oc      VARCHAR DEFAULT NULL,    -- si NULL, autogenerada
    p_fecha_oc       DATE    DEFAULT CURRENT_DATE,
    p_observacion    TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_rol     TEXT;
    v_oc_id   UUID;
    v_numero  VARCHAR(40);
    v_item    JSONB;
    v_monto   NUMERIC(14,0) := 0;
    v_items_count INT := 0;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    -- D1: bodeguero mapeado a operador_abastecimiento
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para crear OC', v_rol;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id = p_proveedor_id AND activo = true) THEN
        RAISE EXCEPTION 'Proveedor % no existe o no esta activo', p_proveedor_id;
    END IF;
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'OC requiere al menos 1 item';
    END IF;

    -- Numero_oc: el provisto o autogenerado OC-YYYY-NNNNN
    IF p_numero_oc IS NULL OR LENGTH(TRIM(p_numero_oc)) = 0 THEN
        v_numero := 'OC-' || TO_CHAR(p_fecha_oc, 'YYYY') || '-' ||
                    LPAD(nextval('seq_numero_oc')::TEXT, 5, '0');
    ELSE
        v_numero := TRIM(p_numero_oc);
        IF EXISTS (SELECT 1 FROM ordenes_compra WHERE numero_oc = v_numero) THEN
            RAISE EXCEPTION 'numero_oc % ya existe', v_numero;
        END IF;
    END IF;

    v_oc_id := gen_random_uuid();
    INSERT INTO ordenes_compra (
        id, numero_oc, proveedor_id, fecha_oc, estado,
        monto_total_clp, observacion, created_by
    ) VALUES (
        v_oc_id, v_numero, p_proveedor_id, p_fecha_oc, 'abierta'::estado_oc_enum,
        0, p_observacion, v_user_id
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'descripcion') IS NULL OR LENGTH(TRIM(v_item->>'descripcion')) = 0 THEN
            RAISE EXCEPTION 'item.descripcion es obligatoria';
        END IF;
        IF COALESCE((v_item->>'cantidad_comprada')::NUMERIC, 0) <= 0 THEN
            RAISE EXCEPTION 'item.cantidad_comprada debe ser > 0';
        END IF;
        IF COALESCE((v_item->>'precio_unitario_clp')::NUMERIC, 0) < 0 THEN
            RAISE EXCEPTION 'item.precio_unitario_clp debe ser >= 0';
        END IF;

        INSERT INTO ordenes_compra_items (
            orden_compra_id, producto_id, descripcion, unidad,
            cantidad_comprada, precio_unitario_clp, estado, observacion
        ) VALUES (
            v_oc_id,
            NULLIF(v_item->>'producto_id', '')::UUID,
            TRIM(v_item->>'descripcion'),
            COALESCE(v_item->>'unidad', 'unidad'),
            (v_item->>'cantidad_comprada')::NUMERIC,
            COALESCE((v_item->>'precio_unitario_clp')::NUMERIC, 0),
            'pendiente'::estado_oc_item_enum,
            v_item->>'observacion'
        );

        v_monto := v_monto + ROUND(
            (v_item->>'cantidad_comprada')::NUMERIC *
            COALESCE((v_item->>'precio_unitario_clp')::NUMERIC, 0), 0);
        v_items_count := v_items_count + 1;
    END LOOP;

    UPDATE ordenes_compra
       SET monto_total_clp = v_monto, updated_at = NOW()
     WHERE id = v_oc_id;

    RETURN jsonb_build_object(
        'success', true,
        'orden_compra_id', v_oc_id,
        'numero_oc', v_numero,
        'items_count', v_items_count,
        'monto_total_clp', v_monto
    );
END;
$$;

COMMENT ON FUNCTION rpc_crear_orden_compra IS
'Crea OC + items. Sin afectar stock ni capas. Rol bodeguero mapeado a operador_abastecimiento (D1 MIG37).';


-- ============================================================================
-- ── BLOCK 2  rpc_registrar_recepcion_bodega ─────────────────────────────────
-- Adaptacion de mig 56 BLOCK E. Recepciona contra OC, crea capa FIFO,
-- e invoca rpc_registrar_entrada_inventario para mantener stock_bodega/kardex.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_registrar_recepcion_bodega(
    p_proveedor_id              UUID,
    p_bodega_id                 UUID,
    p_doc_tipo                  tipo_documento_proveedor_enum,
    p_doc_numero                VARCHAR,
    p_items                     JSONB,         -- {oc_item_id?, producto_id, cantidad, costo_unitario, unidad?, lote?, vencimiento?, observacion?}
    p_orden_compra_id           UUID    DEFAULT NULL,
    p_evidencia_url             TEXT    DEFAULT NULL,
    p_observacion               TEXT    DEFAULT NULL,
    p_permite_sobrecantidad     BOOLEAN DEFAULT FALSE,
    p_permite_precio_distinto   BOOLEAN DEFAULT FALSE,
    p_justificacion_override    TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_folio        VARCHAR;
    v_recepcion_id UUID;
    v_oc_record    RECORD;
    v_oc_item      RECORD;
    v_item         JSONB;
    v_costo_oc     NUMERIC;
    v_costo_real   NUMERIC;
    v_capas_creadas JSONB := '[]'::JSONB;
    v_capa_id      UUID;
    v_rec_item_id  UUID;
    v_observacion_final TEXT;
    v_items_count  INT := 0;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para registrar recepciones', v_rol;
    END IF;

    IF (p_permite_sobrecantidad OR p_permite_precio_distinto) AND v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'Solo administrador puede recibir sobrecantidad o precio distinto';
    END IF;
    IF (p_permite_sobrecantidad OR p_permite_precio_distinto)
       AND (p_justificacion_override IS NULL OR LENGTH(TRIM(p_justificacion_override)) < 10) THEN
        RAISE EXCEPTION 'Override admin requiere justificacion (min 10 caracteres)';
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Recepcion requiere al menos 1 item';
    END IF;

    -- Cargar OC para validar proveedor
    IF p_orden_compra_id IS NOT NULL THEN
        SELECT * INTO v_oc_record FROM ordenes_compra
         WHERE id = p_orden_compra_id FOR UPDATE;
        IF v_oc_record.id IS NULL THEN
            RAISE EXCEPTION 'OC % no existe', p_orden_compra_id;
        END IF;
        IF v_oc_record.proveedor_id <> p_proveedor_id THEN
            RAISE EXCEPTION 'Proveedor de la recepcion (%) no coincide con OC (%)',
                p_proveedor_id, v_oc_record.proveedor_id;
        END IF;
        IF v_oc_record.estado = 'anulada' THEN
            RAISE EXCEPTION 'OC % esta anulada', p_orden_compra_id;
        END IF;
        IF v_oc_record.estado = 'cerrada' THEN
            RAISE EXCEPTION 'OC % ya esta cerrada', p_orden_compra_id;
        END IF;
    END IF;

    v_folio := fn_generar_folio_recepcion_bodega();
    v_recepcion_id := gen_random_uuid();

    v_observacion_final := CASE
        WHEN p_permite_sobrecantidad OR p_permite_precio_distinto
            THEN COALESCE(p_observacion || E'\n', '') || 'OVERRIDE ADMIN: ' || p_justificacion_override
        ELSE p_observacion
    END;

    INSERT INTO recepciones_bodega (
        id, folio_recepcion, orden_compra_id, proveedor_id, bodega_id,
        documento_proveedor_tipo, documento_proveedor_numero,
        recibido_por, observacion, evidencia_url, created_by
    ) VALUES (
        v_recepcion_id, v_folio, p_orden_compra_id, p_proveedor_id, p_bodega_id,
        p_doc_tipo, p_doc_numero,
        v_user_id, v_observacion_final, p_evidencia_url, v_user_id
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'producto_id') IS NULL THEN
            RAISE EXCEPTION 'item.producto_id es obligatorio';
        END IF;
        IF COALESCE((v_item->>'cantidad')::NUMERIC, 0) <= 0 THEN
            RAISE EXCEPTION 'item.cantidad debe ser > 0';
        END IF;

        v_costo_real := COALESCE((v_item->>'costo_unitario')::NUMERIC, 0);
        v_costo_oc := NULL;

        IF (v_item->>'oc_item_id') IS NOT NULL AND (v_item->>'oc_item_id') <> '' THEN
            SELECT * INTO v_oc_item FROM ordenes_compra_items
             WHERE id = (v_item->>'oc_item_id')::UUID FOR UPDATE;

            IF v_oc_item.id IS NULL THEN
                RAISE EXCEPTION 'OC item % no existe', v_item->>'oc_item_id';
            END IF;
            IF v_oc_item.orden_compra_id <> p_orden_compra_id THEN
                RAISE EXCEPTION 'OC item % no pertenece a OC %', v_oc_item.id, p_orden_compra_id;
            END IF;

            v_costo_oc := v_oc_item.precio_unitario_clp;

            IF (v_item->>'cantidad')::NUMERIC > (v_oc_item.cantidad_comprada - v_oc_item.cantidad_recibida)
               AND NOT p_permite_sobrecantidad THEN
                RAISE EXCEPTION 'Cantidad recibida (%) supera pendiente (%) para item %. Use override admin.',
                    v_item->>'cantidad',
                    (v_oc_item.cantidad_comprada - v_oc_item.cantidad_recibida),
                    v_oc_item.id;
            END IF;
            IF v_costo_oc > 0 AND ABS(v_costo_real - v_costo_oc) > 0.01
               AND NOT p_permite_precio_distinto THEN
                RAISE EXCEPTION 'Precio recibido (%) difiere del precio OC (%) para item %. Use override admin con justificacion.',
                    v_costo_real, v_costo_oc, v_oc_item.id;
            END IF;

            UPDATE ordenes_compra_items
               SET cantidad_recibida = cantidad_recibida + (v_item->>'cantidad')::NUMERIC,
                   estado = CASE
                       WHEN cantidad_recibida + (v_item->>'cantidad')::NUMERIC >= cantidad_comprada
                           THEN 'completo'::estado_oc_item_enum
                       ELSE 'parcial'::estado_oc_item_enum
                   END
             WHERE id = v_oc_item.id;
        END IF;

        -- Item de recepcion
        v_rec_item_id := gen_random_uuid();
        INSERT INTO recepciones_bodega_items (
            id, recepcion_id, orden_compra_item_id, producto_id, cantidad_recibida,
            unidad, costo_unitario_clp, lote, fecha_vencimiento, observacion
        ) VALUES (
            v_rec_item_id, v_recepcion_id,
            NULLIF(v_item->>'oc_item_id', '')::UUID,
            (v_item->>'producto_id')::UUID,
            (v_item->>'cantidad')::NUMERIC,
            COALESCE(v_item->>'unidad', 'unidad'),
            v_costo_real,
            v_item->>'lote',
            NULLIF(v_item->>'vencimiento', '')::DATE,
            v_item->>'observacion'
        );

        -- Capa FIFO (la rastrea por recepcion y OC)
        v_capa_id := gen_random_uuid();
        INSERT INTO inventario_capas (
            id, producto_id, bodega_id,
            recepcion_bodega_id, recepcion_bodega_item_id,
            orden_compra_id, orden_compra_item_id, proveedor_id,
            fecha_recepcion, folio_recepcion, numero_oc,
            cantidad_inicial, cantidad_disponible, unidad, costo_unitario,
            lote, vencimiento, estado, created_by
        ) VALUES (
            v_capa_id, (v_item->>'producto_id')::UUID, p_bodega_id,
            v_recepcion_id, v_rec_item_id,
            p_orden_compra_id, NULLIF(v_item->>'oc_item_id', '')::UUID, p_proveedor_id,
            CURRENT_DATE, v_folio,
            CASE WHEN p_orden_compra_id IS NOT NULL THEN v_oc_record.numero_oc ELSE NULL END,
            (v_item->>'cantidad')::NUMERIC, (v_item->>'cantidad')::NUMERIC,
            COALESCE(v_item->>'unidad', 'unidad'), v_costo_real,
            v_item->>'lote', NULLIF(v_item->>'vencimiento', '')::DATE,
            'disponible', v_user_id
        );

        -- Sincronizar stock_bodega y kardex legacy. Idempotente por recepcion
        -- (cada recepcion genera 1 entrada legacy y 1 capa FIFO de igual cantidad).
        PERFORM rpc_registrar_entrada_inventario(
            p_bodega_id            => p_bodega_id,
            p_producto_id          => (v_item->>'producto_id')::UUID,
            p_cantidad             => (v_item->>'cantidad')::NUMERIC,
            p_costo_unitario       => v_costo_real,
            p_documento_referencia => v_folio,
            p_usuario_id           => v_user_id,
            p_lote                 => v_item->>'lote',
            p_fecha_vencimiento    => NULLIF(v_item->>'vencimiento', '')::DATE
        );

        v_capas_creadas := v_capas_creadas || jsonb_build_object(
            'capa_id', v_capa_id,
            'producto_id', v_item->>'producto_id',
            'cantidad', v_item->>'cantidad',
            'costo_unitario', v_costo_real
        );
        v_items_count := v_items_count + 1;
    END LOOP;

    -- Estado OC global
    IF p_orden_compra_id IS NOT NULL THEN
        UPDATE ordenes_compra
           SET estado = CASE
                 WHEN NOT EXISTS (SELECT 1 FROM ordenes_compra_items
                                   WHERE orden_compra_id = p_orden_compra_id
                                     AND estado <> 'completo')
                     THEN 'cerrada'::estado_oc_enum
                 WHEN EXISTS (SELECT 1 FROM ordenes_compra_items
                               WHERE orden_compra_id = p_orden_compra_id
                                 AND cantidad_recibida > 0)
                     THEN 'parcial'::estado_oc_enum
                 ELSE 'abierta'::estado_oc_enum
               END,
               updated_at = NOW()
         WHERE id = p_orden_compra_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'folio', v_folio,
        'recepcion_id', v_recepcion_id,
        'items_count', v_items_count,
        'capas_creadas', v_capas_creadas
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_recepcion_bodega IS
'Recepcion contra OC (opcional). Crea capa FIFO y sincroniza stock_bodega via rpc_registrar_entrada_inventario. Override admin permite sobrecantidad/precio distinto con justificacion >= 10 caracteres (D2 MIG37). Combustible NO usar — diferido a MIG38.';


-- ============================================================================
-- ── BLOCK 3  rpc_registrar_salida_bodega (solo tipo 'ot') ───────────────────
-- Adaptacion de mig 56 BLOCK F. Salida con CECO obligatorio, consume capas
-- FIFO y sincroniza stock_bodega via rpc_registrar_salida_inventario.
--
-- Limitacion MIG37: solo tipo_salida = 'ot'. Constraint legacy
-- chk_mov_salida_requiere_ot impide tipo 'salida'/'merma' sin ot_id.
-- Los otros tipos (persona/ceco/venta/ajuste_autorizado) -> MIG38.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_registrar_salida_bodega(
    p_tipo_salida           tipo_salida_bodega_enum,
    p_bodega_id             UUID,
    p_ceco_id               UUID,
    p_ot_id                 UUID,            -- obligatorio en MIG37 (solo tipo 'ot')
    p_motivo                TEXT,
    p_items                 JSONB,
    p_entregado_a           VARCHAR DEFAULT NULL,
    p_entregado_a_perfil_id UUID    DEFAULT NULL,
    p_autorizado_por        UUID    DEFAULT NULL,
    p_evidencia_url         TEXT    DEFAULT NULL,
    p_observacion           TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_folio        VARCHAR;
    v_salida_id    UUID;
    v_item         JSONB;
    v_item_id      UUID;
    v_fifo_result  JSONB;
    v_costo_unit   NUMERIC;
    v_costo_total  NUMERIC;
    v_resumen      JSONB := '[]'::JSONB;
    v_items_count  INT := 0;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado para registrar salidas', v_rol;
    END IF;

    -- Validaciones D2 / limitacion mig 37
    IF p_tipo_salida <> 'ot' THEN
        RAISE EXCEPTION 'MIG37 solo soporta salidas tipo ot. Tipos persona/ceco/venta/ajuste_autorizado se habilitan en MIG38.';
    END IF;
    IF p_ot_id IS NULL THEN
        RAISE EXCEPTION 'p_ot_id es obligatorio para salidas tipo ot';
    END IF;
    IF p_ceco_id IS NULL THEN
        RAISE EXCEPTION 'CECO es obligatorio para toda salida';
    END IF;
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Motivo es obligatorio (min 5 caracteres)';
    END IF;
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Salida requiere al menos 1 item';
    END IF;

    -- Validar existencia de CECO y OT
    IF NOT EXISTS (SELECT 1 FROM centros_costo WHERE id = p_ceco_id AND activo = true) THEN
        RAISE EXCEPTION 'CECO % no existe o no esta activo', p_ceco_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN
        RAISE EXCEPTION 'OT % no existe', p_ot_id;
    END IF;

    v_folio := fn_generar_folio_salida_bodega();
    v_salida_id := gen_random_uuid();

    INSERT INTO salidas_bodega (
        id, folio_salida, tipo_salida, ot_id, ceco_id, bodega_id,
        solicitado_por, entregado_a, entregado_a_perfil_id, autorizado_por,
        motivo, observacion, evidencia_url, created_by
    ) VALUES (
        v_salida_id, v_folio, p_tipo_salida, p_ot_id, p_ceco_id, p_bodega_id,
        v_user_id, p_entregado_a, p_entregado_a_perfil_id, p_autorizado_por,
        p_motivo, p_observacion, p_evidencia_url, v_user_id
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'producto_id') IS NULL THEN
            RAISE EXCEPTION 'item.producto_id es obligatorio';
        END IF;
        IF COALESCE((v_item->>'cantidad')::NUMERIC, 0) <= 0 THEN
            RAISE EXCEPTION 'item.cantidad debe ser > 0';
        END IF;

        v_item_id := gen_random_uuid();
        INSERT INTO salidas_bodega_items (
            id, salida_id, producto_id, cantidad, unidad
        ) VALUES (
            v_item_id, v_salida_id,
            (v_item->>'producto_id')::UUID,
            (v_item->>'cantidad')::NUMERIC,
            COALESCE(v_item->>'unidad', 'unidad')
        );

        -- Consumo FIFO (RAISE interno si stock insuficiente)
        v_fifo_result := fn_consumir_inventario_fifo(
            p_producto_id           => (v_item->>'producto_id')::UUID,
            p_bodega_id             => p_bodega_id,
            p_cantidad              => (v_item->>'cantidad')::NUMERIC,
            p_salida_bodega_id      => v_salida_id,
            p_salida_bodega_item_id => v_item_id,
            p_movimiento_id         => NULL,
            p_ot_id                 => p_ot_id,
            p_ceco_id               => p_ceco_id,
            p_consumido_por         => v_user_id
        );

        v_costo_unit  := (v_fifo_result->>'costo_unitario_promedio')::NUMERIC;
        v_costo_total := (v_fifo_result->>'costo_total')::NUMERIC;

        UPDATE salidas_bodega_items
           SET costo_unitario_clp = v_costo_unit
         WHERE id = v_item_id;

        -- Sincronizar stock_bodega y kardex legacy
        PERFORM rpc_registrar_salida_inventario(
            p_bodega_id   => p_bodega_id,
            p_producto_id => (v_item->>'producto_id')::UUID,
            p_cantidad    => (v_item->>'cantidad')::NUMERIC,
            p_ot_id       => p_ot_id,
            p_usuario_id  => v_user_id,
            p_lote        => NULL,
            p_motivo      => p_motivo
        );

        v_resumen := v_resumen || jsonb_build_object(
            'salida_item_id', v_item_id,
            'producto_id', v_item->>'producto_id',
            'cantidad', v_item->>'cantidad',
            'costo_unitario_promedio', v_costo_unit,
            'costo_total', v_costo_total,
            'capas_consumidas', v_fifo_result->'capas_consumidas'
        );
        v_items_count := v_items_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'folio', v_folio,
        'salida_id', v_salida_id,
        'metodo_costeo', 'fifo',
        'items_count', v_items_count,
        'items', v_resumen
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_salida_bodega IS
'Salida tipo ot con CECO obligatorio. Consume capas FIFO via fn_consumir_inventario_fifo. Sincroniza stock_bodega via rpc_registrar_salida_inventario. MIG37: limitado a tipo ot (constraint legacy chk_mov_salida_requiere_ot). Otros tipos en MIG38.';


-- ============================================================================
-- ── BLOCK 4  GRANTs ─────────────────────────────────────────────────────────
-- Las RPCs son SECURITY DEFINER. La validacion de rol esta dentro del
-- cuerpo (fn_user_rol). authenticated puede invocar; la RPC decide.
-- ============================================================================

GRANT EXECUTE ON FUNCTION rpc_crear_orden_compra TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_registrar_recepcion_bodega TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_registrar_salida_bodega TO authenticated;


-- ============================================================================
-- ── BLOCK 5  VALIDACIONES POST ──────────────────────────────────────────────
-- ============================================================================

DO $$
DECLARE
    v_n_fns INT;
    v_desviados INT;
    v_capas_neg INT;
BEGIN
    SELECT COUNT(*) INTO v_n_fns FROM pg_proc
     WHERE proname IN ('rpc_crear_orden_compra',
                       'rpc_registrar_recepcion_bodega',
                       'rpc_registrar_salida_bodega');
    IF v_n_fns <> 3 THEN
        RAISE EXCEPTION 'STOP - se esperaban 3 funciones nuevas, se encontraron %', v_n_fns;
    END IF;

    SELECT COUNT(*) INTO v_desviados
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados <> 0 THEN
        RAISE EXCEPTION 'STOP - tras aplicar mig 37 la reconciliacion ya no esta cuadrada (% desviados)', v_desviados;
    END IF;

    SELECT COUNT(*) INTO v_capas_neg
      FROM inventario_capas WHERE cantidad_disponible < 0;
    IF v_capas_neg <> 0 THEN
        RAISE EXCEPTION 'STOP - hay % capas con cantidad negativa', v_capas_neg;
    END IF;

    -- Confirmar que las RPCs legacy NO se borraron
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_entrada_inventario') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_entrada_inventario ya no existe';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_inventario') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_salida_inventario ya no existe';
    END IF;

    RAISE NOTICE '== MIG37 aplicada OK ==';
    RAISE NOTICE '   RPCs nuevas: rpc_crear_orden_compra, rpc_registrar_recepcion_bodega, rpc_registrar_salida_bodega';
    RAISE NOTICE '   Reconciliacion stock vs FIFO sigue cuadrada';
    RAISE NOTICE '   RPCs legacy intactas';
END $$;


-- ── Resultset final para verificacion visual ────────────────────────────────
SELECT 'rpc_crear_orden_compra'           AS funcion, COUNT(*) AS existe FROM pg_proc WHERE proname='rpc_crear_orden_compra'
UNION ALL
SELECT 'rpc_registrar_recepcion_bodega',  COUNT(*)                          FROM pg_proc WHERE proname='rpc_registrar_recepcion_bodega'
UNION ALL
SELECT 'rpc_registrar_salida_bodega',     COUNT(*)                          FROM pg_proc WHERE proname='rpc_registrar_salida_bodega'
UNION ALL
SELECT 'reconciliacion_cuadrada',         (SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion='cuadrado')
UNION ALL
SELECT 'reconciliacion_desviada',         (SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion<>'cuadrado');


-- ============================================================================
-- ── BLOCK 6  LOG ────────────────────────────────────────────────────────────
-- ============================================================================
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG37_END',
            'MIG37 OC + recepcion FIFO + salida OT-CECO aplicada',
            'ok',
            'Smoke test manual recomendado: OC piloto -> recepcion -> verificar capa + stock_bodega -> salida -> verificar consumo capa + stock_bodega -> reconciliacion cuadrada.'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK MANUAL (si nadie ejecuto las RPCs todavia)
-- ----------------------------------------------------------------------------
-- DROP FUNCTION IF EXISTS rpc_crear_orden_compra(UUID, JSONB, VARCHAR, DATE, TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_registrar_recepcion_bodega(UUID, UUID, tipo_documento_proveedor_enum, VARCHAR, JSONB, UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_registrar_salida_bodega(tipo_salida_bodega_enum, UUID, UUID, UUID, TEXT, JSONB, VARCHAR, UUID, UUID, TEXT, TEXT) CASCADE;
--
-- Si se ejecutaron RPCs y se quiere borrar los datos generados, ver
-- "Rollback de datos" en 37_PROPUESTA_BODEGA_OC_FIFO.md. NO automatizado.
-- ============================================================================


-- ============================================================================
-- SMOKE TEST MANUAL (no ejecutado automaticamente — para validacion humana)
-- ----------------------------------------------------------------------------
-- 1) Crear OC piloto:
--   SELECT rpc_crear_orden_compra(
--     p_proveedor_id => '<uuid_proveedor_test>'::UUID,
--     p_items => '[{"descripcion":"Test producto","unidad":"un","cantidad_comprada":1,"precio_unitario_clp":1000}]'::JSONB
--   );
-- 2) Tomar orden_compra_id, oc_item_id (SELECT id FROM ordenes_compra_items WHERE orden_compra_id=...).
-- 3) Recepcionar:
--   SELECT rpc_registrar_recepcion_bodega(
--     p_proveedor_id => '<uuid_proveedor_test>'::UUID,
--     p_bodega_id    => '<uuid_bodega_test>'::UUID,
--     p_doc_tipo     => 'guia'::tipo_documento_proveedor_enum,
--     p_doc_numero   => 'TEST-001',
--     p_items        => '[{"oc_item_id":"<uuid_oc_item>","producto_id":"<uuid_producto>","cantidad":1,"costo_unitario":1000}]'::JSONB,
--     p_orden_compra_id => '<uuid_oc>'::UUID
--   );
-- 4) Verificar:
--   - stock_bodega.cantidad incremento en 1 para ese producto/bodega
--   - inventario_capas tiene nueva capa con recepcion_bodega_id no nulo
--   - ordenes_compra_items.estado = 'completo'
--   - ordenes_compra.estado = 'cerrada'
--   - reconciliacion sigue cuadrada (Q1 del diag consolidado)
-- 5) Hacer salida a OT:
--   SELECT rpc_registrar_salida_bodega(
--     p_tipo_salida => 'ot'::tipo_salida_bodega_enum,
--     p_bodega_id   => '<uuid_bodega_test>'::UUID,
--     p_ceco_id     => '<uuid_ceco_test>'::UUID,
--     p_ot_id       => '<uuid_ot_test>'::UUID,
--     p_motivo      => 'Smoke test MIG37',
--     p_items       => '[{"producto_id":"<uuid_producto>","cantidad":1}]'::JSONB
--   );
-- 6) Verificar:
--   - capa creada en paso 3 con cantidad_disponible=0 y estado='agotada'
--   - inventario_consumos_capas tiene nueva fila con ot_id y ceco_id
--   - stock_bodega.cantidad volvio al valor original
--   - salidas_bodega_items.costo_unitario_clp = 1000
--   - reconciliacion sigue cuadrada
-- ============================================================================
