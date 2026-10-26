-- MIG649 · ENEX: pedido de repuestos desde terreno + correo de la ejecución
-- ============================================================================
-- 26-10, Manuel: en calibración y en mantención, de combustible y de
-- lubricantes, el supervisor tiene que poder dejar observaciones y pedir
-- repuestos. Y al ejecutar, un correo a Hersaly (jefa de los supervisores) y a
-- Manuel con la ejecución, el informe y el detalle de repuestos.
--
-- enex_repuestos_pedido   lo que pide el supervisor, por ejecución. El id lo
--                         genera el teléfono: la app trabaja sin señal y
--                         reenvía la lista completa; reenviar no duplica.
-- rpc_enex_guardar_repuestos   reemplaza la lista de la ejecución (lo que ya
--                              se avisó o pasó a compra no se borra).
-- rpc_enex_reclamar_correo     decide qué correo toca y lo marca, en una sola
--                              transacción: dos teléfonos (o un reintento) no
--                              mandan el mismo correo dos veces.
--   'cierre'    servicio cumplido sin avisar → ejecución + informe + repuestos
--   'repuestos' avance con repuestos nuevos → solo el pedido (no espera al
--               cierre: el repuesto se compra antes de volver)
--   'nada'
-- rpc_enex_liberar_correo      deshace el reclamo si el envío falló.
-- ============================================================================

BEGIN;

ALTER TABLE enex_ejecuciones ADD COLUMN IF NOT EXISTS notificado_at TIMESTAMPTZ;
COMMENT ON COLUMN enex_ejecuciones.notificado_at IS
    'MIG649: cuándo salió el correo de cierre (ejecución + informe + repuestos).';

CREATE TABLE IF NOT EXISTS enex_repuestos_pedido (
    id                UUID PRIMARY KEY,
    ejecucion_id      UUID NOT NULL REFERENCES enex_ejecuciones(id) ON DELETE CASCADE,
    descripcion       TEXT NOT NULL CHECK (length(trim(descripcion)) > 0),
    cantidad          NUMERIC NOT NULL CHECK (cantidad > 0),
    unidad            TEXT NOT NULL DEFAULT 'un',
    urgente           BOOLEAN NOT NULL DEFAULT FALSE,
    nota              TEXT,
    estado            TEXT NOT NULL DEFAULT 'pedido'
                      CHECK (estado IN ('pedido', 'en_compra', 'entregado', 'anulado')),
    pedido_por        UUID DEFAULT auth.uid(),
    pedido_por_nombre TEXT,
    notificado_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_enex_repuestos_pedido_ejec ON enex_repuestos_pedido (ejecucion_id);

ALTER TABLE enex_repuestos_pedido ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_repuestos_pedido_sel ON enex_repuestos_pedido;
CREATE POLICY pol_enex_repuestos_pedido_sel ON enex_repuestos_pedido
    FOR SELECT USING (fn_user_rol() IS NOT NULL);
-- Se escribe solo por las RPC.

-- ── Guardar la lista de repuestos de una programación ───────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_guardar_repuestos(
    p_programacion_id UUID, p_repuestos JSONB, p_pedido_por_nombre TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_ejec UUID;
    v_ids  UUID[];
    r      JSONB;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    SELECT id INTO v_ejec FROM enex_ejecuciones WHERE programacion_id = p_programacion_id;
    IF v_ejec IS NULL THEN RAISE EXCEPTION 'El servicio aún no tiene ejecución registrada'; END IF;

    v_ids := ARRAY(SELECT (x->>'id')::UUID FROM jsonb_array_elements(COALESCE(p_repuestos, '[]'::jsonb)) x);

    FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_repuestos, '[]'::jsonb)) LOOP
        CONTINUE WHEN length(trim(COALESCE(r->>'descripcion', ''))) = 0;
        INSERT INTO enex_repuestos_pedido (id, ejecucion_id, descripcion, cantidad, unidad, urgente, nota, pedido_por_nombre)
        VALUES ((r->>'id')::UUID, v_ejec, trim(r->>'descripcion'),
                GREATEST(COALESCE(NULLIF(r->>'cantidad', '')::NUMERIC, 1), 0.01),
                COALESCE(NULLIF(trim(r->>'unidad'), ''), 'un'),
                COALESCE((r->>'urgente')::BOOLEAN, FALSE),
                NULLIF(trim(COALESCE(r->>'nota', '')), ''),
                p_pedido_por_nombre)
        ON CONFLICT (id) DO UPDATE SET
            descripcion = EXCLUDED.descripcion, cantidad = EXCLUDED.cantidad, unidad = EXCLUDED.unidad,
            urgente = EXCLUDED.urgente, nota = EXCLUDED.nota, updated_at = now()
        -- Lo que ya se avisó sigue editable mientras esté «pedido»; lo que pasó
        -- a compra ya no lo cambia el teléfono.
        WHERE enex_repuestos_pedido.ejecucion_id = v_ejec AND enex_repuestos_pedido.estado = 'pedido';
    END LOOP;

    -- Lo que el supervisor sacó de la lista y nadie alcanzó a ver, se va.
    DELETE FROM enex_repuestos_pedido
     WHERE ejecucion_id = v_ejec AND estado = 'pedido' AND notificado_at IS NULL
       AND NOT (id = ANY (v_ids));

    RETURN jsonb_build_object('ejecucion_id', v_ejec,
        'repuestos', (SELECT count(*) FROM enex_repuestos_pedido WHERE ejecucion_id = v_ejec AND estado <> 'anulado'));
END $$;

-- ── Reclamar el correo que toca ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_reclamar_correo(p_ejecucion_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_estado TEXT;
    v_notif  TIMESTAMPTZ;
    v_ids    UUID[];
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso'; END IF;
    SELECT estado, notificado_at INTO v_estado, v_notif
      FROM enex_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ejecución no encontrada'; END IF;

    IF v_estado = 'cumplida' AND v_notif IS NULL THEN
        UPDATE enex_ejecuciones SET notificado_at = now() WHERE id = p_ejecucion_id;
        v_ids := ARRAY(SELECT id FROM enex_repuestos_pedido
                        WHERE ejecucion_id = p_ejecucion_id AND notificado_at IS NULL AND estado <> 'anulado');
        UPDATE enex_repuestos_pedido SET notificado_at = now() WHERE id = ANY (v_ids);
        RETURN jsonb_build_object('tipo', 'cierre', 'repuestos_nuevos', to_jsonb(v_ids));
    END IF;

    v_ids := ARRAY(SELECT id FROM enex_repuestos_pedido
                    WHERE ejecucion_id = p_ejecucion_id AND notificado_at IS NULL AND estado = 'pedido');
    -- (El FOR UPDATE de la ejecución, arriba, ya serializa dos reclamos a la vez.)
    IF cardinality(v_ids) = 0 THEN RETURN jsonb_build_object('tipo', 'nada'); END IF;
    UPDATE enex_repuestos_pedido SET notificado_at = now() WHERE id = ANY (v_ids);
    RETURN jsonb_build_object('tipo', 'repuestos', 'repuestos_nuevos', to_jsonb(v_ids));
END $$;

CREATE OR REPLACE FUNCTION rpc_enex_liberar_correo(p_ejecucion_id UUID, p_tipo TEXT, p_repuesto_ids UUID[])
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso'; END IF;
    IF p_tipo = 'cierre' THEN
        UPDATE enex_ejecuciones SET notificado_at = NULL WHERE id = p_ejecucion_id;
    END IF;
    UPDATE enex_repuestos_pedido SET notificado_at = NULL
     WHERE ejecucion_id = p_ejecucion_id AND id = ANY (COALESCE(p_repuesto_ids, '{}'));
END $$;

REVOKE ALL ON FUNCTION rpc_enex_guardar_repuestos(UUID, JSONB, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_reclamar_correo(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_liberar_correo(UUID, TEXT, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_enex_guardar_repuestos(UUID, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_reclamar_correo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_liberar_correo(UUID, TEXT, UUID[]) TO authenticated;

-- Las ejecuciones ya cumplidas antes de hoy no disparan correo retroactivo.
UPDATE enex_ejecuciones SET notificado_at = COALESCE(firmante_mandante_at, updated_at)
 WHERE estado = 'cumplida' AND notificado_at IS NULL;

COMMIT;
