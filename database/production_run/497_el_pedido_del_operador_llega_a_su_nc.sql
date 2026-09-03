-- ============================================================================
-- MIG497 · El pedido de repuestos del operador llega a la ficha de su NC
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «cuando el operador en la misma vista, por cada NC pide
-- repuestos, toda esa información de la NC y de la ejecución de la OT debería
-- caer en la pantalla de la NC. Hoy la solicitud de insumos llega en la parte
-- de arriba, que está bien, pero debería además estar al revisar cada NC».
--
-- LO QUE PASA
-- La ficha de la NC dice «Sin insumos todavía» aunque el operador pidió
-- repuestos por ese mismo hallazgo. La vista v_nc_insumos (MIG254) sólo lista
-- pedidos con `no_conformidad_id`, y esa columna la escribió UNA vez el
-- backfill de MIG254: `rpc_ot_recurso_solicitar` (MIG199) inserta el pedido
-- con `instance_item_id` pero nunca resuelve la NC. Todo pedido posterior a
-- MIG254 quedó huérfano — visible arriba (v_ot_recursos), invisible en la NC.
--
-- QUÉ SE HACE
--   1. El RPC resuelve la NC del hallazgo al insertar (por checklist_item_ref).
--   2. Si el pedido llega ANTES de que exista la NC (el orden no está
--      garantizado), la NC lo adopta al nacer: trigger sobre no_conformidades.
--   3. Backfill de los huérfanos acumulados desde MIG254.
-- ============================================================================

BEGIN;

-- ── 1 · El RPC amarra el pedido a su NC (reemplaza cuerpo de MIG199) ────────
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
    v_nc UUID;
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

    -- [MIG497] El pedido nace amarrado a la NC de su hallazgo. Antes sólo
    -- guardaba instance_item_id y la ficha de la NC no lo veía nunca.
    IF p_instance_item_id IS NOT NULL THEN
        SELECT id INTO v_nc FROM no_conformidades
         WHERE checklist_item_ref = p_instance_item_id
         ORDER BY created_at DESC LIMIT 1;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        client_uuid, ot_id, producto_id, descripcion, unidad, cantidad,
        comentario, solicitado_por, solicitado_nombre, fotos, instance_item_id,
        no_conformidad_id)
    VALUES (
        p_client_uuid, p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad), p_cantidad,
        p_comentario, v_user, NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''),
        CASE WHEN p_fotos IS NOT NULL AND array_length(p_fotos,1) > 0 THEN p_fotos ELSE NULL END,
        p_instance_item_id, v_nc)
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

-- ── 2 · Si el pedido llega antes que la NC, la NC lo adopta al nacer ────────
CREATE OR REPLACE FUNCTION fn_nc_adopta_recursos_huerfanos()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NEW.checklist_item_ref IS NOT NULL THEN
        UPDATE ot_recursos_solicitados
           SET no_conformidad_id = NEW.id
         WHERE no_conformidad_id IS NULL
           AND instance_item_id = NEW.checklist_item_ref;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nc_adopta_recursos ON no_conformidades;
CREATE TRIGGER trg_nc_adopta_recursos
    AFTER INSERT ON no_conformidades
    FOR EACH ROW EXECUTE FUNCTION fn_nc_adopta_recursos_huerfanos();

-- ── 3 · Backfill: los huérfanos acumulados desde MIG254 ─────────────────────
UPDATE ot_recursos_solicitados r
   SET no_conformidad_id = nc.id
  FROM no_conformidades nc
 WHERE r.no_conformidad_id IS NULL
   AND r.instance_item_id IS NOT NULL
   AND nc.checklist_item_ref = r.instance_item_id;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_huerfanos INT; v_amarrados INT; v_n INT;
BEGIN
    SELECT count(*) INTO v_amarrados FROM ot_recursos_solicitados WHERE no_conformidad_id IS NOT NULL;
    SELECT count(*) INTO v_huerfanos
      FROM ot_recursos_solicitados
     WHERE no_conformidad_id IS NULL AND instance_item_id IS NOT NULL;
    RAISE NOTICE 'pedidos amarrados a su NC: % · con hallazgo pero sin NC (aún no nace): %',
        v_amarrados, v_huerfanos;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_ot_recurso_solicitar';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_ot_recurso_solicitar quedó con % firmas', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_nc_adopta_recursos') THEN
        RAISE EXCEPTION 'FALLO: no quedó el trigger trg_nc_adopta_recursos';
    END IF;
    RAISE NOTICE 'trigger de adopción activo';
END
$mig$;

COMMIT;
