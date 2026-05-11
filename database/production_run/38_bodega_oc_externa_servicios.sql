-- ============================================================================
-- 38_bodega_oc_externa_servicios.sql
-- ----------------------------------------------------------------------------
-- Bodega — soporte de OC externa + items no inventariables (servicios).
--
-- IDEMPOTENTE. ADITIVA. NO TOCA STOCK NI CAPAS EXISTENTES.
--
-- Decisiones aplicadas (acordadas con el equipo el 2026-05-10):
--   1. OC externa es flujo principal. La OC viene de otra area; la
--      plataforma carga/valida/clasifica/recepciona.
--   2. Crear OC manual queda como flujo secundario (MIG37 intacto).
--   3. Items tipo servicio NO generan stock ni capas FIFO. Solo
--      recepcion documental / conformidad.
--   4. Items inventariables siguen exigiendo producto_id antes de
--      recepcion fisica.
--   5. Centro de costo externo se guarda en texto (centro_costo_codigo
--      _externo) ademas de la FK normalizada (centro_costo_id).
--   6. Documento original en bucket 'documentos' (existe mig 14D) con
--      path bodega-oc/<oc_id>/...
--   7. UNIQUE parcial (proveedor_id, numero_oc_externo) detecta
--      duplicados desde otra fuente.
--   8. Backfill: items existentes -> tipo_item='inventariable',
--      requiere_stock=true (preserva comportamiento MIG37).
--
-- Alcance autorizado:
--   - BLOQUE 1: 11 columnas nuevas en ordenes_compra
--   - BLOQUE 2: 7 columnas nuevas en ordenes_compra_items +
--               ALTER recepciones_bodega_items.producto_id DROP NOT NULL +
--               nueva columna recepciones_bodega_items.recepcion_documental
--   - BLOQUE 3: UNIQUE parcial proveedor_id + numero_oc_externo
--   - BLOQUE 4: rpc_importar_orden_compra_externa (NUEVA)
--   - BLOQUE 5: rpc_registrar_recepcion_bodega (REEMPLAZA — agrega rama
--               documental)
--   - BLOQUE 6: GRANTs
--   - BLOQUE 7: validaciones post + smoke comentado
--
-- NO autorizado en esta mig:
--   - UI / OCR.
--   - Combustible / sellos / vistas finanzas.
--   - Modificar enum global.
--   - Recalcular FIFO / tocar capas existentes.
-- ============================================================================


-- ============================================================================
-- ── BLOQUE 0  PRECHECKS ─────────────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_rol TEXT;
    v_desviados INT;
BEGIN
    -- 1. MIG37 aplicada (3 RPCs base)
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_crear_orden_compra') THEN
        RAISE EXCEPTION 'STOP - rpc_crear_orden_compra no existe (MIG37 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_recepcion_bodega') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_recepcion_bodega no existe (MIG37 no aplicada)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_bodega') THEN
        RAISE EXCEPTION 'STOP - rpc_registrar_salida_bodega no existe (MIG37 no aplicada)';
    END IF;

    -- 2. Tablas base
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='ordenes_compra') THEN
        RAISE EXCEPTION 'STOP - ordenes_compra no existe';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='ordenes_compra_items') THEN
        RAISE EXCEPTION 'STOP - ordenes_compra_items no existe';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='recepciones_bodega_items') THEN
        RAISE EXCEPTION 'STOP - recepciones_bodega_items no existe';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='centros_costo') THEN
        RAISE EXCEPTION 'STOP - centros_costo no existe';
    END IF;

    -- 3. fn_user_rol existe
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - fn_user_rol no existe';
    END IF;

    -- 4. Reconciliacion cuadrada (sanidad antes de extender RPC recepcion)
    SELECT COUNT(*) INTO v_desviados
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados > 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion no cuadrada (% filas con desviacion). Resolver antes de MIG38.', v_desviados;
    END IF;

    -- 5. Usuario admin o rol de sistema (contexto migracion)
    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN
        RAISE NOTICE 'Aplicando MIG38 como rol de sistema (current_user=%). auth.uid() NULL — contexto migracion permitido.', current_user;
    ELSIF v_rol <> 'administrador' THEN
        RAISE EXCEPTION 'STOP - aplicar MIG38 desde sesion autenticada requiere rol administrador. Rol actual: %', v_rol;
    END IF;

    RAISE NOTICE '== MIG38 prechecks OK ==';
END $$;


-- ============================================================================
-- ── BLOQUE 1  ALTER ordenes_compra (+11 columnas) ──────────────────────────
-- ============================================================================

ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS numero_oc_externo VARCHAR(60);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS documento_url TEXT;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS documento_storage_path TEXT;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS origen VARCHAR(20) NOT NULL DEFAULT 'manual';
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS fecha_emision DATE;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS fecha_entrega DATE;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS proveedor_rut_snapshot VARCHAR(20);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS neto_clp NUMERIC(14,0);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS iva_clp NUMERIC(14,0);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS forma_pago VARCHAR(80);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS raw_extracted_json JSONB;

-- CHECK constraint en origen (idempotente)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
         WHERE constraint_schema='public' AND table_name='ordenes_compra'
           AND constraint_name='chk_oc_origen'
    ) THEN
        ALTER TABLE ordenes_compra
            ADD CONSTRAINT chk_oc_origen CHECK (origen IN ('manual','externa'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_oc_origen ON ordenes_compra (origen);
CREATE INDEX IF NOT EXISTS idx_oc_numero_externo ON ordenes_compra (numero_oc_externo) WHERE numero_oc_externo IS NOT NULL;


-- ============================================================================
-- ── BLOQUE 2  ALTER ordenes_compra_items + recepciones_bodega_items ────────
-- ============================================================================

ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS tipo_item VARCHAR(20) NOT NULL DEFAULT 'inventariable';
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS requiere_stock BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS codigo_externo VARCHAR(60);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS unidad_externa VARCHAR(30);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS centro_costo_id UUID REFERENCES centros_costo(id);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS centro_costo_codigo_externo VARCHAR(40);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS raw_item_json JSONB;

-- CHECK tipo_item (idempotente, 8 valores)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
         WHERE constraint_schema='public' AND table_name='ordenes_compra_items'
           AND constraint_name='chk_oci_tipo_item'
    ) THEN
        ALTER TABLE ordenes_compra_items
            ADD CONSTRAINT chk_oci_tipo_item CHECK (tipo_item IN (
                'inventariable','servicio','combustible','lubricante',
                'repuesto','consumible','activo','otro'
            ));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_oci_tipo_item ON ordenes_compra_items (tipo_item);
CREATE INDEX IF NOT EXISTS idx_oci_centro_costo ON ordenes_compra_items (centro_costo_id) WHERE centro_costo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_oci_pendiente_mapeo ON ordenes_compra_items (orden_compra_id)
    WHERE requiere_stock = TRUE AND producto_id IS NULL;

-- recepciones_bodega_items: relajar producto_id para soportar recepcion
-- documental (item servicio). Si ya es nullable, ALTER es no-op.
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='recepciones_bodega_items'
           AND column_name='producto_id' AND is_nullable='NO'
    ) THEN
        ALTER TABLE recepciones_bodega_items ALTER COLUMN producto_id DROP NOT NULL;
        RAISE NOTICE 'recepciones_bodega_items.producto_id ahora permite NULL (recepcion documental)';
    END IF;
END $$;

ALTER TABLE recepciones_bodega_items ADD COLUMN IF NOT EXISTS recepcion_documental BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_rbi_documental ON recepciones_bodega_items (recepcion_id) WHERE recepcion_documental = TRUE;


-- ============================================================================
-- ── BLOQUE 3  UNIQUE parcial (proveedor_id, numero_oc_externo) ─────────────
-- Detecta OC duplicada cuando viene de la misma fuente externa.
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_oc_externa_proveedor
    ON ordenes_compra (proveedor_id, numero_oc_externo)
    WHERE numero_oc_externo IS NOT NULL;


-- ============================================================================
-- ── BLOQUE 4  rpc_importar_orden_compra_externa (NUEVA) ────────────────────
-- Carga una OC externa con su documento, cabecera (neto/iva/total/forma
-- pago/fechas/RUT snapshot), items clasificados por tipo y centros de
-- costo. Idempotencia por (proveedor_id, numero_oc_externo).
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_importar_orden_compra_externa(
    p_proveedor_id         UUID,
    p_numero_oc_externo    VARCHAR,
    p_items                JSONB,         -- ver formato abajo
    p_fecha_emision        DATE    DEFAULT NULL,
    p_fecha_entrega        DATE    DEFAULT NULL,
    p_proveedor_rut        VARCHAR DEFAULT NULL,
    p_neto_clp             NUMERIC DEFAULT NULL,
    p_iva_clp              NUMERIC DEFAULT NULL,
    p_forma_pago           VARCHAR DEFAULT NULL,
    p_documento_url        TEXT    DEFAULT NULL,
    p_documento_storage_path TEXT  DEFAULT NULL,
    p_raw_extracted_json   JSONB   DEFAULT NULL,
    p_observacion          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
/*
Item JSON esperado:
{
  "descripcion": "...",                    -- obligatorio
  "cantidad_comprada": 1,                  -- obligatorio > 0
  "precio_unitario_clp": 290700,           -- >= 0
  "unidad": "unidad",                       -- opcional, default 'unidad'
  "unidad_externa": "UN",                   -- opcional, literal del PDF
  "codigo_externo": "SERSEGCER006",         -- opcional, codigo del PDF
  "producto_id": null,                      -- opcional, FK productos
  "tipo_item": "servicio",                  -- opcional, default 'inventariable'
  "requiere_stock": false,                  -- opcional, autocalcula si null
  "centro_costo_codigo_externo": "CC-15-15",
  "observacion": "...",
  "raw_item_json": {...}
}
*/
DECLARE
    v_user_id   UUID := auth.uid();
    v_rol       TEXT;
    v_oc_id     UUID;
    v_numero    VARCHAR(40);
    v_item      JSONB;
    v_monto     NUMERIC(14,0) := 0;
    v_items_count INT := 0;
    v_tipo_item  TEXT;
    v_requiere   BOOLEAN;
    v_cc_id      UUID;
    v_cc_codigo  TEXT;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para importar OC externa', v_rol;
    END IF;

    -- Validaciones cabecera
    IF p_numero_oc_externo IS NULL OR LENGTH(TRIM(p_numero_oc_externo)) = 0 THEN
        RAISE EXCEPTION 'numero_oc_externo es obligatorio';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id = p_proveedor_id AND activo = true) THEN
        RAISE EXCEPTION 'Proveedor % no existe o no esta activo', p_proveedor_id;
    END IF;
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'OC requiere al menos 1 item';
    END IF;

    -- Duplicado por (proveedor, numero_externo)
    IF EXISTS (
        SELECT 1 FROM ordenes_compra
         WHERE proveedor_id = p_proveedor_id
           AND numero_oc_externo = TRIM(p_numero_oc_externo)
    ) THEN
        RAISE EXCEPTION 'OC externa duplicada: proveedor % ya tiene una OC con numero externo %',
            p_proveedor_id, p_numero_oc_externo;
    END IF;

    -- Numero interno autogen
    v_numero := 'OC-' || TO_CHAR(COALESCE(p_fecha_emision, CURRENT_DATE), 'YYYY') || '-' ||
                LPAD(nextval('seq_numero_oc')::TEXT, 5, '0');

    v_oc_id := gen_random_uuid();
    INSERT INTO ordenes_compra (
        id, numero_oc, numero_oc_externo, proveedor_id, proveedor_rut_snapshot,
        fecha_oc, fecha_emision, fecha_entrega, estado, origen,
        monto_total_clp, neto_clp, iva_clp, forma_pago,
        documento_url, documento_storage_path, raw_extracted_json,
        observacion, created_by
    ) VALUES (
        v_oc_id, v_numero, TRIM(p_numero_oc_externo), p_proveedor_id, p_proveedor_rut,
        COALESCE(p_fecha_emision, CURRENT_DATE), p_fecha_emision, p_fecha_entrega,
        'abierta'::estado_oc_enum, 'externa',
        0, p_neto_clp, p_iva_clp, p_forma_pago,
        p_documento_url, p_documento_storage_path, p_raw_extracted_json,
        p_observacion, v_user_id
    );

    -- Items
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

        -- Tipo item (default 'inventariable')
        v_tipo_item := COALESCE(NULLIF(v_item->>'tipo_item',''), 'inventariable');
        IF v_tipo_item NOT IN ('inventariable','servicio','combustible','lubricante',
                                'repuesto','consumible','activo','otro') THEN
            RAISE EXCEPTION 'tipo_item invalido: %', v_tipo_item;
        END IF;

        -- requiere_stock: si viene explicito lo respeta; si no, autocalcula
        -- (servicio/activo/otro = false; resto = true).
        IF (v_item ? 'requiere_stock') AND (v_item->>'requiere_stock') IS NOT NULL THEN
            v_requiere := (v_item->>'requiere_stock')::BOOLEAN;
        ELSE
            v_requiere := v_tipo_item NOT IN ('servicio','activo','otro');
        END IF;

        -- Resolver centro_costo_id si codigo coincide con centros_costo activo
        v_cc_codigo := NULLIF(TRIM(v_item->>'centro_costo_codigo_externo'), '');
        v_cc_id := NULL;
        IF v_cc_codigo IS NOT NULL THEN
            SELECT id INTO v_cc_id FROM centros_costo
             WHERE codigo = v_cc_codigo AND activo = TRUE LIMIT 1;
        END IF;

        INSERT INTO ordenes_compra_items (
            orden_compra_id, producto_id, descripcion, unidad,
            cantidad_comprada, precio_unitario_clp, estado, observacion,
            tipo_item, requiere_stock, codigo_externo, unidad_externa,
            centro_costo_id, centro_costo_codigo_externo, raw_item_json
        ) VALUES (
            v_oc_id,
            NULLIF(v_item->>'producto_id','')::UUID,
            TRIM(v_item->>'descripcion'),
            COALESCE(NULLIF(v_item->>'unidad',''), 'unidad'),
            (v_item->>'cantidad_comprada')::NUMERIC,
            COALESCE((v_item->>'precio_unitario_clp')::NUMERIC, 0),
            'pendiente'::estado_oc_item_enum,
            v_item->>'observacion',
            v_tipo_item, v_requiere,
            NULLIF(v_item->>'codigo_externo',''),
            NULLIF(v_item->>'unidad_externa',''),
            v_cc_id, v_cc_codigo,
            CASE WHEN v_item ? 'raw_item_json' THEN v_item->'raw_item_json' ELSE NULL END
        );

        v_monto := v_monto + ROUND(
            (v_item->>'cantidad_comprada')::NUMERIC *
            COALESCE((v_item->>'precio_unitario_clp')::NUMERIC, 0), 0);
        v_items_count := v_items_count + 1;
    END LOOP;

    -- monto_total_clp = neto si viene, sino suma items (CLP es enteros)
    UPDATE ordenes_compra
       SET monto_total_clp = COALESCE(p_neto_clp, v_monto),
           updated_at = NOW()
     WHERE id = v_oc_id;

    RETURN jsonb_build_object(
        'success', true,
        'orden_compra_id', v_oc_id,
        'numero_oc', v_numero,
        'numero_oc_externo', TRIM(p_numero_oc_externo),
        'origen', 'externa',
        'items_count', v_items_count,
        'monto_total_clp', COALESCE(p_neto_clp, v_monto)
    );
END;
$$;

COMMENT ON FUNCTION rpc_importar_orden_compra_externa IS
'Importa OC desde fuente externa con documento adjunto. Detecta duplicados via UNIQUE (proveedor_id, numero_oc_externo). Items soportan tipo_item (8 valores) y requiere_stock (autocalc para servicio/activo/otro=false). centro_costo_codigo_externo resuelve a centros_costo.id si existe. MIG38.';

GRANT EXECUTE ON FUNCTION rpc_importar_orden_compra_externa TO authenticated;


-- ============================================================================
-- ── BLOQUE 5  REEMPLAZAR rpc_registrar_recepcion_bodega (rama documental) ──
-- Si item OC tiene requiere_stock=FALSE:
--   - NO exige producto_id
--   - NO crea capa FIFO
--   - NO invoca rpc_registrar_entrada_inventario
--   - Inserta recepciones_bodega_items con recepcion_documental=true
--   - Actualiza cantidad_recibida del OC item (igual que rama actual)
--
-- Si requiere_stock=TRUE (default cuando no hay OC item asociado):
--   - Comportamiento MIG37 intacto
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_registrar_recepcion_bodega(
    p_proveedor_id              UUID,
    p_bodega_id                 UUID,
    p_doc_tipo                  tipo_documento_proveedor_enum,
    p_doc_numero                VARCHAR,
    p_items                     JSONB,
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
    v_documentales INT := 0;
    v_stock_items  INT := 0;
    v_requiere     BOOLEAN;
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

    -- OC (opcional)
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
        v_oc_item := NULL;
        v_requiere := TRUE;  -- default (recepcion libre sin OC = inventariable)

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

            v_requiere := COALESCE(v_oc_item.requiere_stock, TRUE);
            v_costo_oc := v_oc_item.precio_unitario_clp;

            -- Validacion cantidad pendiente (aplica a ambos tipos)
            IF (v_item->>'cantidad')::NUMERIC > (v_oc_item.cantidad_comprada - v_oc_item.cantidad_recibida)
               AND NOT p_permite_sobrecantidad THEN
                RAISE EXCEPTION 'Cantidad recibida (%) supera pendiente (%) para item %. Use override admin.',
                    v_item->>'cantidad',
                    (v_oc_item.cantidad_comprada - v_oc_item.cantidad_recibida),
                    v_oc_item.id;
            END IF;

            -- Validacion de precio SOLO para items con stock (servicios no costean FIFO)
            IF v_requiere AND v_costo_oc > 0 AND ABS(v_costo_real - v_costo_oc) > 0.01
               AND NOT p_permite_precio_distinto THEN
                RAISE EXCEPTION 'Precio recibido (%) difiere del precio OC (%) para item %. Use override admin con justificacion.',
                    v_costo_real, v_costo_oc, v_oc_item.id;
            END IF;

            -- Actualizar cantidad_recibida y estado del OC item (ambas ramas)
            UPDATE ordenes_compra_items
               SET cantidad_recibida = cantidad_recibida + (v_item->>'cantidad')::NUMERIC,
                   estado = CASE
                       WHEN cantidad_recibida + (v_item->>'cantidad')::NUMERIC >= cantidad_comprada
                           THEN 'completo'::estado_oc_item_enum
                       ELSE 'parcial'::estado_oc_item_enum
                   END
             WHERE id = v_oc_item.id;
        END IF;

        -- ─── RAMA DOCUMENTAL ───
        IF NOT v_requiere THEN
            -- Insertar item de recepcion como documental (producto_id NULL OK)
            v_rec_item_id := gen_random_uuid();
            INSERT INTO recepciones_bodega_items (
                id, recepcion_id, orden_compra_item_id, producto_id, cantidad_recibida,
                unidad, costo_unitario_clp, lote, fecha_vencimiento, observacion,
                recepcion_documental
            ) VALUES (
                v_rec_item_id, v_recepcion_id,
                NULLIF(v_item->>'oc_item_id', '')::UUID,
                NULLIF(v_item->>'producto_id', '')::UUID,  -- opcional
                (v_item->>'cantidad')::NUMERIC,
                COALESCE(NULLIF(v_item->>'unidad',''), COALESCE(v_oc_item.unidad,'unidad')),
                0,  -- servicio no costea FIFO (costo va en OC y monto_total)
                NULL, NULL,
                COALESCE(v_item->>'observacion', 'Recepcion documental (item no inventariable)'),
                TRUE
            );

            v_documentales := v_documentales + 1;
            v_items_count := v_items_count + 1;
            CONTINUE;  -- saltar logica de capa/stock
        END IF;

        -- ─── RAMA INVENTARIABLE (logica MIG37) ───
        IF (v_item->>'producto_id') IS NULL OR (v_item->>'producto_id') = '' THEN
            RAISE EXCEPTION 'item.producto_id es obligatorio para items inventariables (requiere_stock=true)';
        END IF;

        v_rec_item_id := gen_random_uuid();
        INSERT INTO recepciones_bodega_items (
            id, recepcion_id, orden_compra_item_id, producto_id, cantidad_recibida,
            unidad, costo_unitario_clp, lote, fecha_vencimiento, observacion,
            recepcion_documental
        ) VALUES (
            v_rec_item_id, v_recepcion_id,
            NULLIF(v_item->>'oc_item_id', '')::UUID,
            (v_item->>'producto_id')::UUID,
            (v_item->>'cantidad')::NUMERIC,
            COALESCE(v_item->>'unidad', 'unidad'),
            v_costo_real,
            v_item->>'lote',
            NULLIF(v_item->>'vencimiento', '')::DATE,
            v_item->>'observacion',
            FALSE
        );

        -- Capa FIFO
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

        -- Sincronizar stock_bodega + kardex legacy
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
        v_stock_items := v_stock_items + 1;
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
        'items_stock', v_stock_items,
        'items_documentales', v_documentales,
        'capas_creadas', v_capas_creadas
    );
END;
$$;

COMMENT ON FUNCTION rpc_registrar_recepcion_bodega IS
'Recepcion contra OC con dos ramas. Si item OC tiene requiere_stock=FALSE: rama documental (no exige producto_id, no crea capa FIFO, no toca stock_bodega; flag recepcion_documental=true). Si requiere_stock=TRUE: rama MIG37 (capa FIFO + sincroniza stock via rpc_registrar_entrada_inventario). MIG38.';


-- ============================================================================
-- ── BLOQUE 6  GRANTs ────────────────────────────────────────────────────────
-- ============================================================================
GRANT EXECUTE ON FUNCTION rpc_importar_orden_compra_externa TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_registrar_recepcion_bodega TO authenticated;


-- ============================================================================
-- ── BLOQUE 7  VALIDACIONES POST ─────────────────────────────────────────────
-- ============================================================================
DO $$
DECLARE
    v_n INT;
    v_desviados INT;
    v_items_inv INT;
    v_rbi_nullable TEXT;
    v_n_funcs INT;
BEGIN
    -- 1. 11 columnas en ordenes_compra
    SELECT COUNT(*) INTO v_n FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ordenes_compra'
       AND column_name IN ('numero_oc_externo','documento_url','documento_storage_path',
                           'origen','fecha_emision','fecha_entrega','proveedor_rut_snapshot',
                           'neto_clp','iva_clp','forma_pago','raw_extracted_json');
    IF v_n <> 11 THEN
        RAISE EXCEPTION 'STOP - solo % de 11 columnas nuevas en ordenes_compra', v_n;
    END IF;

    -- 2. 7 columnas en ordenes_compra_items
    SELECT COUNT(*) INTO v_n FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ordenes_compra_items'
       AND column_name IN ('tipo_item','requiere_stock','codigo_externo','unidad_externa',
                           'centro_costo_id','centro_costo_codigo_externo','raw_item_json');
    IF v_n <> 7 THEN
        RAISE EXCEPTION 'STOP - solo % de 7 columnas nuevas en ordenes_compra_items', v_n;
    END IF;

    -- 3. recepciones_bodega_items.producto_id nullable + recepcion_documental
    SELECT is_nullable INTO v_rbi_nullable FROM information_schema.columns
     WHERE table_schema='public' AND table_name='recepciones_bodega_items'
       AND column_name='producto_id';
    IF v_rbi_nullable <> 'YES' THEN
        RAISE EXCEPTION 'STOP - recepciones_bodega_items.producto_id no es nullable';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='recepciones_bodega_items'
                      AND column_name='recepcion_documental') THEN
        RAISE EXCEPTION 'STOP - recepciones_bodega_items.recepcion_documental no existe';
    END IF;

    -- 4. UNIQUE parcial
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND indexname='uq_oc_externa_proveedor') THEN
        RAISE EXCEPTION 'STOP - UNIQUE index uq_oc_externa_proveedor no existe';
    END IF;

    -- 5. RPCs
    SELECT COUNT(*) INTO v_n_funcs FROM pg_proc
     WHERE proname IN ('rpc_importar_orden_compra_externa','rpc_registrar_recepcion_bodega');
    IF v_n_funcs <> 2 THEN
        RAISE EXCEPTION 'STOP - esperaba 2 RPCs, encontre %', v_n_funcs;
    END IF;

    -- 6. Backfill conservador OK: todos los items existentes son
    --    inventariable + requiere_stock=true (default del ALTER).
    SELECT COUNT(*) INTO v_items_inv FROM ordenes_compra_items
     WHERE tipo_item = 'inventariable' AND requiere_stock = TRUE;
    RAISE NOTICE 'Items existentes con backfill default: % (inventariable + requiere_stock)', v_items_inv;

    -- 7. Reconciliacion intacta
    SELECT COUNT(*) INTO v_desviados
      FROM v_bodega_reconciliacion_stock_fifo
     WHERE estado_reconciliacion <> 'cuadrado';
    IF v_desviados <> 0 THEN
        RAISE EXCEPTION 'STOP - reconciliacion ya no esta cuadrada tras mig (% desviados)', v_desviados;
    END IF;

    RAISE NOTICE '== MIG38 aplicada OK ==';
    RAISE NOTICE '   Columnas nuevas: 11 en OC, 7 en OC_items + recepcion_documental';
    RAISE NOTICE '   UNIQUE (proveedor_id, numero_oc_externo) activo';
    RAISE NOTICE '   2 RPCs (importar externa, recepcion extendida)';
    RAISE NOTICE '   Backfill: % items existentes con tipo=inventariable y requiere_stock=true', v_items_inv;
    RAISE NOTICE '   Reconciliacion: 0 desviados (intacta)';
END $$;


-- ── Resultset visual ────────────────────────────────────────────────────────
SELECT 'cols_oc'                AS dx, COUNT(*)::text AS val FROM information_schema.columns
 WHERE table_schema='public' AND table_name='ordenes_compra'
   AND column_name IN ('numero_oc_externo','documento_url','documento_storage_path',
                       'origen','fecha_emision','fecha_entrega','proveedor_rut_snapshot',
                       'neto_clp','iva_clp','forma_pago','raw_extracted_json')
UNION ALL
SELECT 'cols_oc_items',          COUNT(*)::text FROM information_schema.columns
 WHERE table_schema='public' AND table_name='ordenes_compra_items'
   AND column_name IN ('tipo_item','requiere_stock','codigo_externo','unidad_externa',
                       'centro_costo_id','centro_costo_codigo_externo','raw_item_json')
UNION ALL
SELECT 'rpc_importar_externa',   COUNT(*)::text FROM pg_proc WHERE proname='rpc_importar_orden_compra_externa'
UNION ALL
SELECT 'rpc_recepcion_extendida',COUNT(*)::text FROM pg_proc WHERE proname='rpc_registrar_recepcion_bodega'
UNION ALL
SELECT 'unique_oc_externa',      COUNT(*)::text FROM pg_indexes
 WHERE schemaname='public' AND indexname='uq_oc_externa_proveedor'
UNION ALL
SELECT 'items_backfill_inv',     COUNT(*)::text FROM ordenes_compra_items
 WHERE tipo_item='inventariable' AND requiere_stock=TRUE
UNION ALL
SELECT 'reconciliacion_cuadrado',COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo
 WHERE estado_reconciliacion='cuadrado'
UNION ALL
SELECT 'reconciliacion_desviado',COUNT(*)::text FROM v_bodega_reconciliacion_stock_fifo
 WHERE estado_reconciliacion<>'cuadrado';


-- ── Log a operacion_migraciones_log si existe ───────────────────────────────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_log_operacion_migracion') THEN
        PERFORM fn_log_operacion_migracion(
            'PROD_MIG38_END',
            'MIG38 OC externa + items servicios aplicada (aditiva)',
            'ok',
            'Smoke manual recomendado con OC ejemplo 13559 VOLVO CHILE SPA / SERSEGCER006'
        );
    END IF;
END $$;


-- ============================================================================
-- ROLLBACK MANUAL (si nadie ejecuto rpc_importar_orden_compra_externa)
-- ----------------------------------------------------------------------------
-- DROP FUNCTION IF EXISTS rpc_importar_orden_compra_externa CASCADE;
-- -- restaurar version MIG37 de rpc_registrar_recepcion_bodega (re-ejecutar
-- -- la mig 37 o aplicar version anterior desde control de versiones).
-- DROP INDEX IF EXISTS uq_oc_externa_proveedor;
-- ALTER TABLE recepciones_bodega_items DROP COLUMN IF EXISTS recepcion_documental;
-- -- ALTER TABLE recepciones_bodega_items ALTER COLUMN producto_id SET NOT NULL;  -- solo si NO se cargo ningun item documental
-- ALTER TABLE ordenes_compra_items
--   DROP COLUMN IF EXISTS tipo_item, DROP COLUMN IF EXISTS requiere_stock,
--   DROP COLUMN IF EXISTS codigo_externo, DROP COLUMN IF EXISTS unidad_externa,
--   DROP COLUMN IF EXISTS centro_costo_id, DROP COLUMN IF EXISTS centro_costo_codigo_externo,
--   DROP COLUMN IF EXISTS raw_item_json;
-- ALTER TABLE ordenes_compra
--   DROP COLUMN IF EXISTS numero_oc_externo, DROP COLUMN IF EXISTS documento_url,
--   DROP COLUMN IF EXISTS documento_storage_path, DROP COLUMN IF EXISTS origen,
--   DROP COLUMN IF EXISTS fecha_emision, DROP COLUMN IF EXISTS fecha_entrega,
--   DROP COLUMN IF EXISTS proveedor_rut_snapshot, DROP COLUMN IF EXISTS neto_clp,
--   DROP COLUMN IF EXISTS iva_clp, DROP COLUMN IF EXISTS forma_pago,
--   DROP COLUMN IF EXISTS raw_extracted_json;
-- ============================================================================


-- ============================================================================
-- SMOKE TEST MANUAL (documentado, NO ejecutado)
-- ----------------------------------------------------------------------------
-- Ejecutar como service_role o impostar admin con
--   PERFORM set_config('request.jwt.claim.sub', '<uuid_admin>', true);
--
-- TEST 1 — OC ejemplo Pillado 13559 VOLVO CHILE SPA (item servicio):
--
-- WITH v AS (
--   SELECT (SELECT id FROM proveedores WHERE rut='76.284.920-8' AND activo=true LIMIT 1) AS prov_id
-- )
-- SELECT rpc_importar_orden_compra_externa(
--   p_proveedor_id      => (SELECT prov_id FROM v),
--   p_numero_oc_externo => '13559',
--   p_proveedor_rut     => '76.284.920-8',
--   p_fecha_emision     => '2026-05-07'::DATE,
--   p_fecha_entrega     => '2026-05-07'::DATE,
--   p_neto_clp          => 290700,
--   p_iva_clp           => 55233,
--   p_forma_pago        => '30 dias',
--   p_items             => jsonb_build_array(jsonb_build_object(
--     'codigo_externo',  'SERSEGCER006',
--     'descripcion',     'SERVICIO CERTIFICACION OPERATIVIDAD',
--     'cantidad_comprada', 1,
--     'unidad',          'unidad',
--     'unidad_externa',  'UN',
--     'precio_unitario_clp', 290700,
--     'tipo_item',       'servicio',
--     'requiere_stock',  false,
--     'centro_costo_codigo_externo', 'CC-15-15'
--   ))
-- );
--
-- Esperado: success=true, items_count=1, origen=externa
-- En ordenes_compra_items: 1 fila con tipo_item='servicio', requiere_stock=false,
-- producto_id NULL, codigo_externo='SERSEGCER006', centro_costo_codigo_externo='CC-15-15'.
-- No se creo capa FIFO. Reconciliacion sigue 40/40.
--
-- Re-ejecutar misma RPC con mismo numero_oc_externo + proveedor:
--   ERROR: 'OC externa duplicada: proveedor X ya tiene una OC con numero externo 13559'
--
-- TEST 2 — recepcion documental contra ese OC:
--
-- (Impostar admin; obtener oc_id y oc_item_id del test 1)
-- SELECT rpc_registrar_recepcion_bodega(
--   p_proveedor_id    => <prov_id>,
--   p_bodega_id       => <bodega_id>,
--   p_doc_tipo        => 'factura'::tipo_documento_proveedor_enum,
--   p_doc_numero      => 'DOC-CERT-001',
--   p_items           => jsonb_build_array(jsonb_build_object(
--     'oc_item_id', '<oc_item_id_servicio>',
--     'producto_id', NULL,
--     'cantidad',    1,
--     'observacion', 'Certificacion recibida conforme'
--   )),
--   p_orden_compra_id => <oc_id>
-- );
--
-- Esperado: success=true, items_documentales=1, items_stock=0, capas_creadas=[].
-- En recepciones_bodega_items: 1 fila con recepcion_documental=true,
-- producto_id NULL, costo_unitario_clp=0.
-- stock_bodega NO cambio. Reconciliacion 40/40.
-- OC pasa a 'parcial' o 'cerrada' segun completitud.
--
-- TEST 3 — OC inventariable sigue funcionando exactamente igual que MIG37
-- (no requiere prueba nueva — comportamiento intacto).
-- ============================================================================
