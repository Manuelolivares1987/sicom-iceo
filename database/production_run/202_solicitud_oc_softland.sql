-- ============================================================================
-- SICOM-ICEO | 202 — La "OC" del seguimiento es una SOLICITUD (la emite
--                    Softland) + registro del N° de OC oficial
-- ============================================================================
-- Precisión Manuel (2026-07-07): la orden de compra oficial la emite el área
-- especialista EN SOFTLAND. Lo que hace el tablero de seguimiento (MIG201) es
-- una SOLICITUD de OC: el registro interno en ordenes_compra existe para que
-- la recepción alimente FIFO y el seguimiento funcione, pero el número que
-- manda es el de Softland.
--
--   1. rpc_oc_registrar_numero_externo: cuando Softland emite la OC, se
--      registra su número en ordenes_compra.numero_oc_externo (columna de
--      MIG38). Futuro: integración directa con Softland usará esta llave.
--   2. v_ot_recursos expone oc_numero_externo (el tablero muestra el N°
--      Softland si existe; si no, el folio interno como "solicitud").
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ordenes_compra' AND column_name='numero_oc_externo') THEN
        RAISE EXCEPTION 'STOP — falta ordenes_compra.numero_oc_externo (MIG38).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_ot_recursos_generar_oc') THEN
        RAISE EXCEPTION 'STOP — falta MIG201.';
    END IF;
END $$;


-- ── 1. Registrar el N° de OC oficial (Softland) ──────────────────────────────
CREATE OR REPLACE FUNCTION rpc_oc_registrar_numero_externo(p_oc_id UUID, p_numero VARCHAR)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_estado TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    IF NULLIF(TRIM(COALESCE(p_numero,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el número de OC de Softland'; END IF;
    SELECT estado::text INTO v_estado FROM ordenes_compra WHERE id = p_oc_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'OC no existe'; END IF;
    IF v_estado = 'anulada' THEN RAISE EXCEPTION 'La OC está anulada'; END IF;

    UPDATE ordenes_compra
       SET numero_oc_externo = TRIM(p_numero), updated_at = NOW()
     WHERE id = p_oc_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_oc_registrar_numero_externo(UUID,VARCHAR) TO authenticated;

COMMENT ON FUNCTION rpc_ot_recursos_generar_oc(UUID[],UUID,VARCHAR,DATE,TEXT) IS
    'SOLICITUD de OC desde los recursos aprobados sin stock (MIG201). La OC oficial '
    'la emite el área especialista en Softland; su número se registra con '
    'rpc_oc_registrar_numero_externo. El registro interno permite recepción FIFO y seguimiento.';


-- ── 1b. La solicitud guarda el N° Softland en numero_oc_externo ──────────────
-- (MIG201 ponía p_numero_oc en el folio interno único; el folio interno SIEMPRE
--  se autogenera y lo que digite el usuario es el N° de Softland.)
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
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para solicitar OC', v_rol; END IF;
    IF p_recurso_ids IS NULL OR array_length(p_recurso_ids,1) IS NULL THEN
        RAISE EXCEPTION 'Selecciona al menos un recurso'; END IF;
    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id = p_proveedor_id AND activo = true) THEN
        RAISE EXCEPTION 'Proveedor no existe o no está activo'; END IF;

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
            RAISE EXCEPTION 'El recurso "%" ya está en una solicitud de OC', COALESCE(r.descripcion, r.producto_nombre); END IF;
        IF r.producto_id IS NULL THEN
            RAISE EXCEPTION 'El recurso "%" no tiene producto de catálogo: asígnale uno antes de comprar', r.descripcion; END IF;
    END LOOP;
    IF (SELECT COUNT(*) FROM ot_recursos_solicitados WHERE id = ANY(p_recurso_ids)) <> array_length(p_recurso_ids,1) THEN
        RAISE EXCEPTION 'Hay recursos que no existen'; END IF;

    -- Folio interno SIEMPRE autogenerado; el N° digitado es el de Softland.
    v_numero := 'OC-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' ||
                LPAD(nextval('seq_numero_oc')::TEXT, 5, '0');

    v_oc := gen_random_uuid();
    INSERT INTO ordenes_compra (id, numero_oc, proveedor_id, fecha_oc, estado,
                                monto_total_clp, observacion, created_by, fecha_entrega,
                                numero_oc_externo)
    VALUES (v_oc, v_numero, p_proveedor_id, CURRENT_DATE, 'abierta'::estado_oc_enum,
            0, COALESCE(p_observacion, 'Solicitud de OC — repuestos taller'), v_user, p_fecha_entrega,
            NULLIF(TRIM(COALESCE(p_numero_oc,'')),''));

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


-- ── 2. Vista con el N° Softland ──────────────────────────────────────────────
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
       r.oc_id, r.oc_item_id,
       oc.numero_oc         AS oc_numero,
       oc.numero_oc_externo AS oc_numero_externo,
       oc.estado            AS oc_estado,
       oc.fecha_entrega     AS oc_fecha_entrega,
       prov.nombre          AS oc_proveedor,
       oci.cantidad_recibida AS oc_cantidad_recibida
FROM ot_recursos_solicitados r
LEFT JOIN productos pr             ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil uv       ON uv.id = r.validado_por
LEFT JOIN bodega_tickets tk        ON tk.id = r.ticket_id
LEFT JOIN ordenes_compra oc        ON oc.id = r.oc_id
LEFT JOIN ordenes_compra_items oci ON oci.id = r.oc_item_id
LEFT JOIN proveedores prov         ON prov.id = oc.proveedor_id;
GRANT SELECT ON v_ot_recursos TO authenticated;

CREATE VIEW v_ot_recursos_seguimiento AS
SELECT v.*,
       ot.folio  AS ot_folio,
       a.codigo  AS activo_codigo,
       a.patente AS activo_patente,
       a.nombre  AS activo_nombre,
       GREATEST(0, EXTRACT(DAY FROM NOW() - v.created_at))::int AS dias_desde_solicitud,
       (v.estado = 'aprobado' AND v.oc_item_id IS NULL
        AND (v.producto_id IS NULL OR COALESCE(v.stock_total,0) <= 0)) AS por_comprar
FROM v_ot_recursos v
JOIN ordenes_trabajo ot ON ot.id = v.ot_id
JOIN activos a          ON a.id = ot.activo_id;
GRANT SELECT ON v_ot_recursos_seguimiento TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rpc_num_externo', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_oc_registrar_numero_externo')),
    'vista_con_externo', (SELECT position('numero_oc_externo' IN pg_get_viewdef('v_ot_recursos'::regclass)) > 0),
    'seguimiento_ok', (SELECT EXISTS (SELECT 1 FROM information_schema.views
        WHERE table_name='v_ot_recursos_seguimiento'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
