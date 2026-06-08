-- ============================================================================
-- SICOM-ICEO | 136 — Checklist cliente: novedades -> Alertas Tempranas
-- ============================================================================
-- El checklist semanal del cliente y el preoperacional (nuestros conductores)
-- tienen el MISMO objetivo: detectar fallas antes de que sean graves. El
-- preoperacional ya genera alertas en alertas_tempranas; el del cliente hasta
-- ahora solo marcaba 'novedad' en su panel.
--
-- Este fix hace que cada item 'no_ok' del checklist del cliente genere una
-- ALERTA TEMPRANA (mismo tablero), para tener un radar unico de fallas de toda
-- la flota (propia + arrendada). Semaforo: rojo para sistemas criticos
-- (frenos/seguridad/estructura/fugas), naranja el resto.
--
-- Reproduce rpc_checklist_cliente_guardar (MIG 127) + insercion de alertas.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_checklist_cliente_guardar(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activo_id  UUID := (p_payload->>'activo_id')::UUID;
    v_act        RECORD;
    v_id         UUID;
    v_item       JSONB;
    v_ok INT := 0; v_no_ok INT := 0; v_tot INT := 0;
    v_novedad    BOOLEAN;
BEGIN
    IF v_activo_id IS NULL THEN RAISE EXCEPTION 'activo_id requerido'; END IF;
    SELECT id, contrato_id, cliente_actual INTO v_act FROM activos WHERE id = v_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', v_activo_id; END IF;

    INSERT INTO checklist_cliente_semanal (
        activo_id, contrato_id, cliente_nombre, anio, semana_iso, fecha,
        operador_nombre, operador_rut, operador_empresa, telefono,
        horometro, kilometraje, ubicacion, lat, lng, firma_url, foto_equipo_url,
        observaciones
    ) VALUES (
        v_activo_id, v_act.contrato_id,
        COALESCE(p_payload->>'cliente_nombre', v_act.cliente_actual),
        EXTRACT(ISOYEAR FROM NOW())::INT, EXTRACT(WEEK FROM NOW())::INT, CURRENT_DATE,
        p_payload->>'operador_nombre', p_payload->>'operador_rut',
        p_payload->>'operador_empresa', p_payload->>'telefono',
        NULLIF(p_payload->>'horometro','')::NUMERIC, NULLIF(p_payload->>'kilometraje','')::NUMERIC,
        p_payload->>'ubicacion', NULLIF(p_payload->>'lat','')::NUMERIC, NULLIF(p_payload->>'lng','')::NUMERIC,
        p_payload->>'firma_url', p_payload->>'foto_equipo_url',
        p_payload->>'observaciones'
    ) RETURNING id INTO v_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'items','[]'::JSONB)) LOOP
        INSERT INTO checklist_cliente_semanal_items
            (checklist_id, orden, categoria, descripcion, resultado, observacion, foto_url)
        VALUES (
            v_id, COALESCE((v_item->>'orden')::INT,0), v_item->>'categoria', v_item->>'descripcion',
            COALESCE(v_item->>'resultado','na'), v_item->>'observacion', v_item->>'foto_url'
        );
        v_tot := v_tot + 1;
        IF v_item->>'resultado' = 'ok' THEN v_ok := v_ok + 1; END IF;
        IF v_item->>'resultado' = 'no_ok' THEN
            v_no_ok := v_no_ok + 1;
            -- Novedad del cliente -> alerta temprana (radar unico de fallas).
            INSERT INTO alertas_tempranas (activo_id, codigo_alerta, descripcion, semaforo, estado)
            VALUES (
                v_activo_id, 'CHK-CLIENTE',
                'Checklist cliente — ' || COALESCE(NULLIF(TRIM(v_item->>'descripcion'),''),'novedad')
                    || COALESCE(': ' || NULLIF(TRIM(v_item->>'observacion'),''), ''),
                CASE WHEN v_item->>'categoria' IN ('frenos','seguridad','estructura','fugas')
                     THEN 'rojo' ELSE 'naranja' END,
                'abierta'
            );
        END IF;
    END LOOP;

    v_novedad := v_no_ok > 0;
    UPDATE checklist_cliente_semanal
       SET items_total = v_tot, items_ok = v_ok, items_no_ok = v_no_ok, tiene_novedad = v_novedad
     WHERE id = v_id;

    RETURN jsonb_build_object('id', v_id, 'items_total', v_tot, 'items_no_ok', v_no_ok,
                              'tiene_novedad', v_novedad);
END $$;
GRANT EXECUTE ON FUNCTION rpc_checklist_cliente_guardar(JSONB) TO anon, authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG136 OK: novedades del checklist cliente -> alertas_tempranas'; END $$;
