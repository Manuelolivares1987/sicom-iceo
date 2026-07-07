-- ============================================================================
-- SICOM-ICEO | 199 — El pedido de insumos nace del hallazgo (NO OK / NC)
-- ============================================================================
-- Pedido Manuel (2026-07-07): si el operador encuentra una NC debe (1) sacar
-- foto del hallazgo, (2) pedir ahí mismo los insumos para repararla (los
-- valida el jefe de taller) y (3) la NC sigue su camino al planificador; el
-- retiro en bodega es el vale QR + firma que ya existe (MIG161/197).
--
-- Lo que ya existía: item NO OK → NC automática con foto y checklist_item_ref
-- (MIG159), bandeja del planificador (v_nc_recepcion), alerta a planificador
-- (MIG175), vale con recursos aprobados (MIG197/198).
--
-- Lo que agrega esta MIG:
--   * ot_recursos_solicitados.instance_item_id: el pedido queda amarrado al
--     ítem NO OK del checklist → y por checklist_item_ref, a la NC que se
--     genera de ese hallazgo.
--   * rpc_ot_recurso_solicitar acepta p_instance_item_id (firma anterior
--     eliminada para no dejar overloads).
--   * v_ot_recursos expone instance_item_id.
--   * v_nc_recepcion expone foto_url, checklist_item_ref y
--     n_recursos_operador (pedidos del operador ligados al hallazgo) para que
--     el planificador los vea al planificar.
-- (La obligatoriedad de la foto en NO OK se exige en la app del operador,
--  que es quien tiene el estado local offline.)
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ot_recursos_solicitados' AND column_name='fotos') THEN
        RAISE EXCEPTION 'STOP — falta MIG198 (fotos en ot_recursos_solicitados).';
    END IF;
END $$;


-- ── 1. Vínculo pedido ↔ ítem NO OK del checklist ─────────────────────────────
ALTER TABLE ot_recursos_solicitados
    ADD COLUMN IF NOT EXISTS instance_item_id UUID REFERENCES checklist_v2_instance_item(id);
COMMENT ON COLUMN ot_recursos_solicitados.instance_item_id IS
    'Item del checklist V03 (hallazgo NO OK) que motivó el pedido; enlaza con no_conformidades.checklist_item_ref. MIG199.';
CREATE INDEX IF NOT EXISTS idx_ot_recursos_item ON ot_recursos_solicitados(instance_item_id)
    WHERE instance_item_id IS NOT NULL;


-- ── 2. RPC con vínculo al hallazgo (reemplaza firma de MIG198) ───────────────
DROP FUNCTION IF EXISTS rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID,TEXT[]);

CREATE OR REPLACE FUNCTION rpc_ot_recurso_solicitar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_solicitado_nombre VARCHAR DEFAULT NULL, p_client_uuid UUID DEFAULT NULL,
    p_fotos TEXT[] DEFAULT NULL, p_instance_item_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_ot RECORD; v_id UUID; v_unidad VARCHAR; v_nombre_prod TEXT; v_u RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para solicitar recursos (rol: %)', v_rol; END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el producto del catálogo o una descripción'; END IF;

    -- Idempotencia del sync offline: mismo client_uuid ⇒ misma solicitud.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM ot_recursos_solicitados WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', true, 'recurso_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    SELECT id, folio, estado, preparacion_ok_at, activo_id INTO v_ot
      FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_ot.id IS NULL THEN RAISE EXCEPTION 'OT no existe'; END IF;
    IF v_ot.preparacion_ok_at IS NULL OR v_ot.estado NOT IN ('asignada','en_ejecucion','pausada') THEN
        RAISE EXCEPTION 'La OT % no está liberada a ejecución', v_ot.folio; END IF;

    IF p_producto_id IS NOT NULL THEN
        SELECT unidad_medida, nombre INTO v_unidad, v_nombre_prod FROM productos WHERE id = p_producto_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        client_uuid, ot_id, producto_id, descripcion, unidad, cantidad,
        comentario, solicitado_por, solicitado_nombre, fotos, instance_item_id)
    VALUES (
        p_client_uuid, p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad), p_cantidad,
        p_comentario, v_user, NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''),
        CASE WHEN p_fotos IS NOT NULL AND array_length(p_fotos,1) > 0 THEN p_fotos ELSE NULL END,
        p_instance_item_id)
    RETURNING id INTO v_id;

    -- Campanita a la jefatura (nunca bloquear la solicitud por la alerta).
    BEGIN
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','jefe_mantenimiento','supervisor')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('recurso_solicitado',
                    'Recursos solicitados: ' || v_ot.folio,
                    COALESCE(NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''), 'Operador de taller')
                      || ' pide ' || p_cantidad || ' ' || COALESCE(v_unidad, p_unidad, 'un')
                      || ' de ' || COALESCE(v_nombre_prod, p_descripcion, 'material')
                      || CASE WHEN p_instance_item_id IS NOT NULL
                              THEN ' por hallazgo NO OK' ELSE ' para reparar' END
                      || CASE WHEN p_fotos IS NOT NULL AND array_length(p_fotos,1) > 0
                              THEN ' (con ' || array_length(p_fotos,1) || ' foto' ||
                                   CASE WHEN array_length(p_fotos,1) > 1 THEN 's' ELSE '' END || ')'
                              ELSE '' END,
                    'info', 'recurso_ot', p_ot_id, v_u.id, false, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID,TEXT[],UUID) TO authenticated;


-- ── 3. Vista de recursos con el vínculo ──────────────────────────────────────
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
       tk.folio AS ticket_folio, tk.estado AS ticket_estado
FROM ot_recursos_solicitados r
LEFT JOIN productos pr        ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil uv  ON uv.id = r.validado_por
LEFT JOIN bodega_tickets tk   ON tk.id = r.ticket_id;
GRANT SELECT ON v_ot_recursos TO authenticated;


-- ── 4. La bandeja del planificador ve los pedidos del hallazgo ───────────────
DROP VIEW IF EXISTS v_nc_recepcion;
CREATE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
       nc.ot_id,
       nc.foto_url,
       nc.checklist_item_ref,
       -- Insumos que el operador pidió desde ese hallazgo (MIG199)
       (SELECT count(*) FROM ot_recursos_solicitados r
         WHERE r.instance_item_id = nc.checklist_item_ref
           AND nc.checklist_item_ref IS NOT NULL)                        AS n_recursos_operador
FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot');
GRANT SELECT ON v_nc_recepcion TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_item', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='ot_recursos_solicitados' AND column_name='instance_item_id')),
    'rpc_una_sola_firma', (SELECT COUNT(*) = 1 FROM pg_proc WHERE proname='rpc_ot_recurso_solicitar'),
    'rpc_con_item', (SELECT prosrc LIKE '%p_instance_item_id%' FROM pg_proc
        WHERE proname='rpc_ot_recurso_solicitar'),
    'vista_recursos_item', (SELECT position('instance_item_id' IN pg_get_viewdef('v_ot_recursos'::regclass)) > 0),
    'vista_nc_recursos', (SELECT position('n_recursos_operador' IN pg_get_viewdef('v_nc_recepcion'::regclass)) > 0)
) AS resultado;

NOTIFY pgrst, 'reload schema';
