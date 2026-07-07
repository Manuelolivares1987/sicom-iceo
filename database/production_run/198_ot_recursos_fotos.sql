-- ============================================================================
-- SICOM-ICEO | 198 — Fotos en la solicitud de recursos del operador
-- ============================================================================
-- Pedido Manuel (2026-07-07): muchas veces el repuesto NO existe en el
-- catálogo de bodega y hay que comprarlo — el operador lo pide con texto
-- libre + FOTOS (la pieza, la placa, el desgaste) para que el jefe sepa qué
-- validar/comprar.
--
--   * ot_recursos_solicitados.fotos TEXT[] (URLs en evidencias-verificacion).
--   * rpc_ot_recurso_solicitar acepta p_fotos (se reemplaza la firma vieja
--     para no dejar overloads que confundan a PostgREST).
--   * v_ot_recursos expone fotos.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ot_recursos_solicitados') THEN
        RAISE EXCEPTION 'STOP — falta ot_recursos_solicitados (MIG197).';
    END IF;
END $$;


-- ── 1. Columna ───────────────────────────────────────────────────────────────
ALTER TABLE ot_recursos_solicitados ADD COLUMN IF NOT EXISTS fotos TEXT[];
COMMENT ON COLUMN ot_recursos_solicitados.fotos IS
    'Fotos del repuesto/pieza que respaldan la solicitud (URLs storage). MIG198.';


-- ── 2. RPC con fotos (reemplaza la firma de MIG197) ──────────────────────────
DROP FUNCTION IF EXISTS rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID);

CREATE OR REPLACE FUNCTION rpc_ot_recurso_solicitar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_solicitado_nombre VARCHAR DEFAULT NULL, p_client_uuid UUID DEFAULT NULL,
    p_fotos TEXT[] DEFAULT NULL
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
        comentario, solicitado_por, solicitado_nombre, fotos)
    VALUES (
        p_client_uuid, p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad), p_cantidad,
        p_comentario, v_user, NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''),
        CASE WHEN p_fotos IS NOT NULL AND array_length(p_fotos,1) > 0 THEN p_fotos ELSE NULL END)
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
                      || ' para reparar'
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
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID,TEXT[]) TO authenticated;


-- ── 3. Vista con fotos ───────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_ot_recursos;
CREATE VIEW v_ot_recursos AS
SELECT r.id, r.client_uuid, r.ot_id, r.producto_id,
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


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_fotos', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='ot_recursos_solicitados' AND column_name='fotos')),
    'rpc_una_sola_firma', (SELECT COUNT(*) = 1 FROM pg_proc WHERE proname='rpc_ot_recurso_solicitar'),
    'rpc_con_fotos', (SELECT prosrc LIKE '%p_fotos%' FROM pg_proc
        WHERE proname='rpc_ot_recurso_solicitar'),
    'vista_con_fotos', (SELECT position('fotos' IN pg_get_viewdef('v_ot_recursos'::regclass)) > 0)
) AS resultado;

NOTIFY pgrst, 'reload schema';
