-- ============================================================================
-- SICOM-ICEO | 201 — Seguimiento de compra de repuestos solicitados sin stock
-- ============================================================================
-- Pedido Manuel (2026-07-07): los repuestos que se piden y NO tienen stock hay
-- que comprarlos, y hoy nadie sabe en qué está cada solicitud (cuello de
-- botella). Se cierra el ciclo completo:
--
--   solicitado → aprobado → EN_COMPRA (OC emitida) → RECIBIDO (recepción FIFO)
--             → en_vale (ticket QR) → entrega bodega
--
--   1. Estados nuevos 'en_compra' y 'recibido' + vínculo a la OC
--      (oc_id / oc_item_id; un ítem de OC por recurso → trazabilidad 1:1).
--   2. rpc_ot_recursos_generar_oc: desde el tablero, los aprobados sin stock
--      se convierten en una OC real (folio OC-YYYY-NNNNN, proveedor, fecha
--      estimada de entrega). Requiere producto de catálogo (la recepción crea
--      la capa FIFO y el vale despacha por producto).
--   3. Trigger en ordenes_compra_items: al RECEPCIONAR la OC (flujo MIG37,
--      que ya alimenta FIFO) el recurso pasa solo a 'recibido' y avisa por
--      campanita al jefe de taller para emitir el vale.
--   4. rpc_ot_recurso_asignar_producto (mapear texto libre a catálogo) y
--      rpc_producto_rapido (crear el producto si no existe — hoy solo admin
--      puede insertar en productos por RLS).
--   5. Al aprobar un recurso sin stock o texto libre → alerta
--      'recurso_por_comprar' a abastecimiento.
--   6. El vale (rpc_crear_ticket_bodega) ahora incluye también los 'recibido'.
--   7. Vista v_ot_recursos_seguimiento (tablero con aging) y v_ot_recursos
--      con los datos de la OC.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ot_recursos_solicitados' AND column_name='instance_item_id') THEN
        RAISE EXCEPTION 'STOP — falta MIG199.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ordenes_compra_items') THEN
        RAISE EXCEPTION 'STOP — falta el módulo OC (MIG37/55).';
    END IF;
END $$;


-- ── 1. Estados nuevos + vínculo a la OC ──────────────────────────────────────
DO $$
DECLARE v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
      FROM pg_constraint
     WHERE conrelid = 'ot_recursos_solicitados'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%en_vale%'
       AND pg_get_constraintdef(oid) NOT LIKE '%en_compra%';
    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE ot_recursos_solicitados DROP CONSTRAINT %I', v_conname);
        ALTER TABLE ot_recursos_solicitados ADD CONSTRAINT chk_ot_recursos_estado
            CHECK (estado IN ('solicitado','aprobado','rechazado','en_compra','recibido','en_vale'));
    END IF;
END $$;

ALTER TABLE ot_recursos_solicitados
    ADD COLUMN IF NOT EXISTS oc_id      UUID REFERENCES ordenes_compra(id),
    ADD COLUMN IF NOT EXISTS oc_item_id UUID REFERENCES ordenes_compra_items(id);
CREATE INDEX IF NOT EXISTS idx_ot_recursos_oc_item ON ot_recursos_solicitados(oc_item_id)
    WHERE oc_item_id IS NOT NULL;
COMMENT ON COLUMN ot_recursos_solicitados.oc_item_id IS
    'Item de la OC que compra este recurso (1:1). La recepción de ese ítem lo pasa a recibido. MIG201.';


-- ── 2. Tipos de alerta nuevos ────────────────────────────────────────────────
DO $$
DECLARE v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
      FROM pg_constraint
     WHERE conrelid = 'alertas'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%recurso_solicitado%'
       AND pg_get_constraintdef(oid) NOT LIKE '%recurso_por_comprar%';
    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE alertas DROP CONSTRAINT %I', v_conname);
        ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo IN (
            'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
            'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
            'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
            'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
            'no_conformidad','recurso_solicitado','recurso_por_comprar','recurso_recibido'));
    END IF;
END $$;


-- ── 3. Validar: al aprobar sin stock avisa a abastecimiento ──────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_validar(
    p_recurso_id UUID, p_accion TEXT,
    p_cantidad_aprobada NUMERIC DEFAULT NULL, p_nota TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_r RECORD; v_stock NUMERIC; v_folio TEXT; v_u RECORD; v_desc TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Solo la jefatura valida recursos (rol: %)', v_rol; END IF;
    IF p_accion NOT IN ('aprobar','rechazar') THEN
        RAISE EXCEPTION 'Acción inválida: % (aprobar|rechazar)', p_accion; END IF;

    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id FOR UPDATE;
    IF v_r.id IS NULL THEN RAISE EXCEPTION 'Recurso no existe'; END IF;
    IF v_r.estado NOT IN ('solicitado','aprobado','rechazado') THEN
        RAISE EXCEPTION 'El recurso ya está en % — se gestiona desde el seguimiento de compra/vale', v_r.estado; END IF;

    UPDATE ot_recursos_solicitados
       SET estado            = CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END,
           cantidad_aprobada = CASE WHEN p_accion = 'aprobar'
                                    THEN COALESCE(p_cantidad_aprobada, cantidad_aprobada, cantidad)
                                    ELSE NULL END,
           validado_por = v_user, validado_at = NOW(),
           nota_jefe = COALESCE(p_nota, nota_jefe),
           updated_at = NOW()
     WHERE id = p_recurso_id;

    -- [MIG201] Aprobado sin stock (o fuera de catálogo) ⇒ hay que COMPRAR:
    -- alerta a abastecimiento para que aparezca en el seguimiento.
    IF p_accion = 'aprobar' THEN
        SELECT COALESCE(SUM(sb.cantidad),0) INTO v_stock
          FROM stock_bodega sb WHERE sb.producto_id = v_r.producto_id;
        IF v_r.producto_id IS NULL OR COALESCE(v_stock,0) <= 0 THEN
            BEGIN
                SELECT ot.folio INTO v_folio FROM ordenes_trabajo ot WHERE ot.id = v_r.ot_id;
                v_desc := COALESCE(v_r.descripcion, (SELECT nombre FROM productos WHERE id = v_r.producto_id), 'material');
                FOR v_u IN
                    SELECT id FROM usuarios_perfil
                     WHERE activo = true AND rol IN ('administrador','operador_abastecimiento','bodeguero')
                LOOP
                    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                         destinatario_id, leida, created_at)
                    VALUES ('recurso_por_comprar',
                            'Repuesto por comprar: ' || COALESCE(v_folio, 'OT'),
                            'Aprobado sin stock: ' || COALESCE(p_cantidad_aprobada, v_r.cantidad) || ' '
                              || COALESCE(v_r.unidad, 'un') || ' de ' || v_desc
                              || CASE WHEN v_r.producto_id IS NULL THEN ' (fuera de catálogo)' ELSE '' END,
                            'warning', 'recurso_compra', v_r.id, v_u.id, false, NOW());
                END LOOP;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'recurso_id', p_recurso_id,
        'estado', CASE WHEN p_accion = 'aprobar' THEN 'aprobado' ELSE 'rechazado' END);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_validar(UUID,TEXT,NUMERIC,TEXT) TO authenticated;


-- ── 4. Mapear texto libre a producto / crear producto rápido ─────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_asignar_producto(p_recurso_id UUID, p_producto_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol(); v_estado TEXT; v_unidad VARCHAR;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor',
                     'planificador','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    SELECT estado INTO v_estado FROM ot_recursos_solicitados WHERE id = p_recurso_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Recurso no existe'; END IF;
    IF v_estado NOT IN ('solicitado','aprobado') THEN
        RAISE EXCEPTION 'El recurso ya está en % — no se puede cambiar el producto', v_estado; END IF;
    SELECT unidad_medida INTO v_unidad FROM productos WHERE id = p_producto_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;

    UPDATE ot_recursos_solicitados
       SET producto_id = p_producto_id,
           unidad = COALESCE(unidad, v_unidad),
           updated_at = NOW()
     WHERE id = p_recurso_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_asignar_producto(UUID,UUID) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_producto_rapido(
    p_nombre VARCHAR, p_categoria VARCHAR DEFAULT 'repuesto',
    p_unidad VARCHAR DEFAULT 'unidad', p_codigo VARCHAR DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol TEXT := fn_user_rol(); v_codigo VARCHAR; v_id UUID; v_i INT := 0;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor',
                     'operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Sin permiso para crear productos (rol: %)', v_rol; END IF;
    IF NULLIF(TRIM(COALESCE(p_nombre,'')),'') IS NULL THEN
        RAISE EXCEPTION 'El nombre es obligatorio'; END IF;
    IF p_categoria NOT IN ('combustible','lubricante','filtro','repuesto','consumible','epp') THEN
        RAISE EXCEPTION 'Categoría inválida: %', p_categoria; END IF;

    v_codigo := NULLIF(TRIM(COALESCE(p_codigo,'')),'');
    IF v_codigo IS NULL THEN
        LOOP
            v_codigo := 'REP-' || UPPER(LEFT(md5(gen_random_uuid()::text), 6));
            EXIT WHEN NOT EXISTS (SELECT 1 FROM productos WHERE codigo = v_codigo);
            v_i := v_i + 1;
            IF v_i > 5 THEN RAISE EXCEPTION 'No se pudo generar código único'; END IF;
        END LOOP;
    ELSIF EXISTS (SELECT 1 FROM productos WHERE codigo = v_codigo) THEN
        RAISE EXCEPTION 'El código % ya existe', v_codigo;
    END IF;

    INSERT INTO productos (codigo, nombre, categoria, unidad_medida)
    VALUES (v_codigo, TRIM(p_nombre), p_categoria, COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''),'unidad'))
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('success', true, 'producto_id', v_id, 'codigo', v_codigo);
END $$;
GRANT EXECUTE ON FUNCTION rpc_producto_rapido(VARCHAR,VARCHAR,VARCHAR,VARCHAR) TO authenticated;


-- ── 5. Generar la OC desde los recursos aprobados sin stock ──────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recursos_generar_oc(
    p_recurso_ids UUID[], p_proveedor_id UUID,
    p_numero_oc VARCHAR DEFAULT NULL, p_fecha_entrega DATE DEFAULT NULL,
    p_observacion TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_oc UUID; v_numero VARCHAR(40); v_item UUID; v_n INT := 0;
    r RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- Mismos roles que rpc_crear_orden_compra (MIG37)
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para generar OC', v_rol; END IF;
    IF p_recurso_ids IS NULL OR array_length(p_recurso_ids,1) IS NULL THEN
        RAISE EXCEPTION 'Selecciona al menos un recurso'; END IF;
    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id = p_proveedor_id AND activo = true) THEN
        RAISE EXCEPTION 'Proveedor no existe o no está activo'; END IF;

    -- Todos los recursos deben estar aprobados, sin vale/OC, y con producto
    -- de catálogo (la recepción crea la capa FIFO por producto).
    FOR r IN
        SELECT rs.*, pr.nombre AS producto_nombre, pr.unidad_medida
          FROM ot_recursos_solicitados rs
          LEFT JOIN productos pr ON pr.id = rs.producto_id
         WHERE rs.id = ANY(p_recurso_ids)
         FOR UPDATE OF rs
    LOOP
        IF r.estado <> 'aprobado' THEN
            RAISE EXCEPTION 'El recurso "%" está en %, no en aprobado', COALESCE(r.descripcion, r.producto_nombre), r.estado; END IF;
        IF r.oc_item_id IS NOT NULL THEN
            RAISE EXCEPTION 'El recurso "%" ya está en una OC', COALESCE(r.descripcion, r.producto_nombre); END IF;
        IF r.producto_id IS NULL THEN
            RAISE EXCEPTION 'El recurso "%" no tiene producto de catálogo: asígnale uno antes de comprar', r.descripcion; END IF;
    END LOOP;
    IF (SELECT COUNT(*) FROM ot_recursos_solicitados WHERE id = ANY(p_recurso_ids)) <> array_length(p_recurso_ids,1) THEN
        RAISE EXCEPTION 'Hay recursos que no existen'; END IF;

    -- Cabecera OC (mismo folio y semántica que rpc_crear_orden_compra)
    IF p_numero_oc IS NULL OR LENGTH(TRIM(p_numero_oc)) = 0 THEN
        v_numero := 'OC-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' ||
                    LPAD(nextval('seq_numero_oc')::TEXT, 5, '0');
    ELSE
        v_numero := TRIM(p_numero_oc);
        IF EXISTS (SELECT 1 FROM ordenes_compra WHERE numero_oc = v_numero) THEN
            RAISE EXCEPTION 'numero_oc % ya existe', v_numero; END IF;
    END IF;

    v_oc := gen_random_uuid();
    INSERT INTO ordenes_compra (id, numero_oc, proveedor_id, fecha_oc, estado,
                                monto_total_clp, observacion, created_by, fecha_entrega)
    VALUES (v_oc, v_numero, p_proveedor_id, CURRENT_DATE, 'abierta'::estado_oc_enum,
            0, COALESCE(p_observacion, 'Compra de repuestos solicitados por taller'), v_user, p_fecha_entrega);

    -- Un ítem por recurso (trazabilidad 1:1 → la recepción sabe qué recurso llegó)
    FOR r IN
        SELECT rs.id, rs.ot_id, rs.producto_id, rs.cantidad, rs.cantidad_aprobada,
               COALESCE(rs.descripcion, pr.nombre) AS descripcion,
               COALESCE(rs.unidad, pr.unidad_medida, 'unidad') AS unidad,
               (SELECT folio FROM ordenes_trabajo ot WHERE ot.id = rs.ot_id) AS ot_folio
          FROM ot_recursos_solicitados rs
          LEFT JOIN productos pr ON pr.id = rs.producto_id
         WHERE rs.id = ANY(p_recurso_ids)
         ORDER BY rs.created_at
    LOOP
        INSERT INTO ordenes_compra_items (
            orden_compra_id, producto_id, descripcion, unidad,
            cantidad_comprada, precio_unitario_clp, estado, observacion)
        VALUES (v_oc, r.producto_id, r.descripcion, r.unidad,
                COALESCE(r.cantidad_aprobada, r.cantidad), 0,
                'pendiente'::estado_oc_item_enum,
                'Recurso taller ' || COALESCE(r.ot_folio,''))
        RETURNING id INTO v_item;

        UPDATE ot_recursos_solicitados
           SET estado = 'en_compra', oc_id = v_oc, oc_item_id = v_item, updated_at = NOW()
         WHERE id = r.id;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'orden_compra_id', v_oc,
        'numero_oc', v_numero, 'items', v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recursos_generar_oc(UUID[],UUID,VARCHAR,DATE,TEXT) TO authenticated;


-- ── 6. Recepción de la OC → recurso 'recibido' + campanita al jefe ───────────
CREATE OR REPLACE FUNCTION fn_trg_recurso_recibido()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r RECORD; v_u RECORD; v_folio TEXT;
BEGIN
    -- Recurso 1:1 con el ítem: recibido cuando llegó lo comprado del ítem.
    IF NEW.cantidad_recibida >= NEW.cantidad_comprada THEN
        FOR r IN
            SELECT rs.id, rs.ot_id, COALESCE(rs.descripcion, pr.nombre) AS descripcion,
                   COALESCE(rs.cantidad_aprobada, rs.cantidad) AS cant, rs.unidad
              FROM ot_recursos_solicitados rs
              LEFT JOIN productos pr ON pr.id = rs.producto_id
             WHERE rs.oc_item_id = NEW.id AND rs.estado = 'en_compra'
        LOOP
            UPDATE ot_recursos_solicitados
               SET estado = 'recibido', updated_at = NOW() WHERE id = r.id;

            BEGIN
                SELECT folio INTO v_folio FROM ordenes_trabajo WHERE id = r.ot_id;
                FOR v_u IN
                    SELECT id FROM usuarios_perfil
                     WHERE activo = true AND rol IN ('administrador','jefe_mantenimiento','supervisor')
                LOOP
                    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                         destinatario_id, leida, created_at)
                    VALUES ('recurso_recibido',
                            'Repuesto recibido: ' || COALESCE(v_folio,'OT'),
                            'Llegó a bodega: ' || r.cant || ' ' || COALESCE(r.unidad,'un') || ' de '
                              || r.descripcion || ' — emitir vale para entregar al taller',
                            'info', 'recurso_ot', r.ot_id, v_u.id, false, NOW());
                END LOOP;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_recurso_recibido ON ordenes_compra_items;
CREATE TRIGGER trg_recurso_recibido
    AFTER UPDATE OF cantidad_recibida ON ordenes_compra_items
    FOR EACH ROW
    WHEN (NEW.cantidad_recibida IS DISTINCT FROM OLD.cantidad_recibida)
    EXECUTE FUNCTION fn_trg_recurso_recibido();


-- ── 7. El vale incluye también los recursos recibidos ────────────────────────
CREATE OR REPLACE FUNCTION rpc_crear_ticket_bodega(
    p_ot_id UUID, p_firma_jefe_url TEXT, p_observacion TEXT DEFAULT NULL, p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_activo UUID; v_folio TEXT; v_periodo TEXT; v_sec INT; v_id UUID; v_qr TEXT; v_n INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Solo el jefe de taller emite tickets (rol: %)', v_rol; END IF;
    IF p_firma_jefe_url IS NULL OR length(trim(p_firma_jefe_url))=0 THEN
        RAISE EXCEPTION 'La firma del jefe es obligatoria'; END IF;

    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id=p_ot_id;
    IF v_activo IS NULL THEN RAISE EXCEPTION 'OT no existe'; END IF;

    IF EXISTS (SELECT 1 FROM bodega_tickets WHERE ot_id=p_ot_id AND estado IN ('emitido','parcial')) THEN
        RAISE EXCEPTION 'Ya existe un ticket abierto para esta OT'; END IF;

    -- Fuentes del vale: materiales de NC y/o recursos aprobados o recibidos (MIG201)
    IF NOT EXISTS (
        SELECT 1 FROM nc_materiales m JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
         WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false)
       AND NOT EXISTS (
        SELECT 1 FROM ot_recursos_solicitados r WHERE r.ot_id=p_ot_id AND r.estado IN ('aprobado','recibido')) THEN
        RAISE EXCEPTION 'No hay materiales de NC ni recursos aprobados para esta OT'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('bodega_ticket_folio'));
    v_periodo := to_char(now(),'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 12 FOR 5) AS INT)),0)+1 INTO v_sec
      FROM bodega_tickets WHERE folio LIKE 'TKT-'||v_periodo||'-%';
    v_folio := 'TKT-'||v_periodo||'-'||LPAD(v_sec::text,5,'0');
    v_id := gen_random_uuid();
    v_qr := 'SICOM-'||v_folio;

    INSERT INTO bodega_tickets(id, folio, qr_code, ot_id, activo_id, bodega_id, estado, emitido_por, firma_jefe_url, observacion)
    VALUES (v_id, v_folio, v_qr, p_ot_id, v_activo, p_bodega_id, 'emitido', v_user, p_firma_jefe_url, p_observacion);

    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, nc_id, nc_material_id, comentario)
    SELECT v_id, m.producto_id, COALESCE(m.descripcion, pr.nombre), pr.unidad_medida,
           m.cantidad, nc.id, m.id, m.comentario
      FROM nc_materiales m
      JOIN no_conformidades nc ON nc.id=m.no_conformidad_id
      LEFT JOIN productos pr ON pr.id=m.producto_id
     WHERE nc.ot_id=p_ot_id AND COALESCE(nc.resuelto,false)=false;

    -- Recursos del operador: aprobados con stock y comprados ya recibidos (MIG201)
    INSERT INTO bodega_ticket_items(ticket_id, producto_id, descripcion, unidad, cantidad_solicitada, recurso_id, comentario)
    SELECT v_id, r.producto_id, COALESCE(r.descripcion, pr.nombre),
           COALESCE(r.unidad, pr.unidad_medida),
           COALESCE(r.cantidad_aprobada, r.cantidad), r.id, r.comentario
      FROM ot_recursos_solicitados r
      LEFT JOIN productos pr ON pr.id=r.producto_id
     WHERE r.ot_id=p_ot_id AND r.estado IN ('aprobado','recibido');

    UPDATE ot_recursos_solicitados
       SET estado='en_vale', ticket_id=v_id, updated_at=NOW()
     WHERE ot_id=p_ot_id AND estado IN ('aprobado','recibido');

    SELECT COUNT(*) INTO v_n FROM bodega_ticket_items WHERE ticket_id=v_id;
    RETURN jsonb_build_object('success',true,'ticket_id',v_id,'folio',v_folio,'qr',v_qr,'items',v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_crear_ticket_bodega(UUID,TEXT,TEXT,UUID) TO authenticated;


-- ── 8. Vistas ────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_ot_recursos_seguimiento;
DROP VIEW IF EXISTS v_ot_recursos;
CREATE VIEW v_ot_recursos AS
SELECT r.id, r.client_uuid, r.ot_id, r.producto_id, r.instance_item_id,
       COALESCE(r.descripcion, pr.nombre)      AS descripcion,
       COALESCE(r.unidad, pr.unidad_medida)    AS unidad,
       r.cantidad, r.cantidad_aprobada, r.comentario, r.estado, r.fotos,
       r.solicitado_por, r.solicitado_nombre, r.agregado_por_jefe,
       r.validado_por, r.validado_at, r.nota_jefe, r.ticket_id, r.created_at,
       pr.codigo AS producto_codigo, pr.nombre AS producto_nombre,
       CASE WHEN r.producto_id IS NULL THEN NULL
            ELSE (SELECT COALESCE(SUM(sb.cantidad),0) FROM stock_bodega sb
                   WHERE sb.producto_id = r.producto_id) END AS stock_total,
       uv.nombre_completo AS validado_por_nombre,
       tk.folio AS ticket_folio, tk.estado AS ticket_estado,
       -- Seguimiento de compra (MIG201)
       r.oc_id, r.oc_item_id,
       oc.numero_oc      AS oc_numero,
       oc.estado         AS oc_estado,
       oc.fecha_entrega  AS oc_fecha_entrega,
       prov.nombre       AS oc_proveedor,
       oci.cantidad_recibida AS oc_cantidad_recibida
FROM ot_recursos_solicitados r
LEFT JOIN productos pr             ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil uv       ON uv.id = r.validado_por
LEFT JOIN bodega_tickets tk        ON tk.id = r.ticket_id
LEFT JOIN ordenes_compra oc        ON oc.id = r.oc_id
LEFT JOIN ordenes_compra_items oci ON oci.id = r.oc_item_id
LEFT JOIN proveedores prov         ON prov.id = oc.proveedor_id;
GRANT SELECT ON v_ot_recursos TO authenticated;

-- Tablero de seguimiento: recurso + OT/equipo + aging por etapa
CREATE VIEW v_ot_recursos_seguimiento AS
SELECT v.*,
       ot.folio  AS ot_folio,
       a.codigo  AS activo_codigo,
       a.patente AS activo_patente,
       a.nombre  AS activo_nombre,
       GREATEST(0, EXTRACT(DAY FROM NOW() - v.created_at))::int AS dias_desde_solicitud,
       -- por comprar = aprobado y (sin stock o fuera de catálogo) y sin OC
       (v.estado = 'aprobado' AND v.oc_item_id IS NULL
        AND (v.producto_id IS NULL OR COALESCE(v.stock_total,0) <= 0)) AS por_comprar
FROM v_ot_recursos v
JOIN ordenes_trabajo ot ON ot.id = v.ot_id
JOIN activos a          ON a.id = ot.activo_id;
GRANT SELECT ON v_ot_recursos_seguimiento TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'estados_ok', (SELECT pg_get_constraintdef(oid) LIKE '%en_compra%' FROM pg_constraint
        WHERE conrelid='ot_recursos_solicitados'::regclass AND conname='chk_ot_recursos_estado'),
    'cols_oc', (SELECT COUNT(*)=2 FROM information_schema.columns
        WHERE table_name='ot_recursos_solicitados' AND column_name IN ('oc_id','oc_item_id')),
    'alertas_ok', (SELECT pg_get_constraintdef(oid) LIKE '%recurso_recibido%' FROM pg_constraint
        WHERE conrelid='alertas'::regclass AND conname='chk_alertas_tipo'),
    'rpcs', (SELECT array_agg(DISTINCT proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_ot_recursos_generar_oc','rpc_ot_recurso_asignar_producto','rpc_producto_rapido')),
    'trigger_ok', (SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_recurso_recibido')),
    'ticket_incluye_recibidos', (SELECT prosrc LIKE '%''aprobado'',''recibido''%' FROM pg_proc
        WHERE proname='rpc_crear_ticket_bodega'),
    'vista_seguimiento', (SELECT EXISTS (SELECT 1 FROM information_schema.views
        WHERE table_name='v_ot_recursos_seguimiento'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
