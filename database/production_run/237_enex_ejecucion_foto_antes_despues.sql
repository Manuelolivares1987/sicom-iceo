-- ============================================================================
-- SICOM-ICEO | 237 — ENEX terreno: foto de ANTES y DESPUÉS por ejecución
-- ============================================================================
-- Pedido del mandante (2026-07-21): en la app de terreno, cada ejecución debe
-- registrar una foto del ANTES y una del DESPUÉS del servicio (evidencia global,
-- además de las fotos por ítem de la pauta).
--   * enex_ejecuciones += foto_antes_url, foto_despues_url.
--   * rpc_enex_ejecutar_pauta acepta y guarda ambas.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE enex_ejecuciones
    ADD COLUMN IF NOT EXISTS foto_antes_url   TEXT,
    ADD COLUMN IF NOT EXISTS foto_despues_url TEXT;
COMMENT ON COLUMN enex_ejecuciones.foto_antes_url   IS 'Foto del antes del servicio (terreno). MIG237.';
COMMENT ON COLUMN enex_ejecuciones.foto_despues_url IS 'Foto del después del servicio (terreno). MIG237.';

-- Reemplaza el RPC de ejecución para aceptar las dos fotos (params al final,
-- con default NULL). Se elimina la firma anterior para evitar sobrecargas.
DROP FUNCTION IF EXISTS rpc_enex_ejecutar_pauta(UUID,JSONB,TEXT,TEXT,TEXT,DATE,TEXT[],TEXT,TEXT,TEXT,TEXT,UUID);

CREATE OR REPLACE FUNCTION rpc_enex_ejecutar_pauta(
    p_programacion_id UUID, p_items JSONB,
    p_ot_numero TEXT DEFAULT NULL, p_ejecutor TEXT DEFAULT NULL, p_observacion TEXT DEFAULT NULL,
    p_fecha DATE DEFAULT NULL, p_evidencia_urls TEXT[] DEFAULT NULL,
    p_firma_tecnico_url TEXT DEFAULT NULL, p_tecnico_nombre TEXT DEFAULT NULL,
    p_firma_mandante_url TEXT DEFAULT NULL, p_firmante_mandante TEXT DEFAULT NULL,
    p_client_uuid UUID DEFAULT NULL,
    p_foto_antes_url TEXT DEFAULT NULL, p_foto_despues_url TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_pauta UUID; v_ejec UUID; v_firma_m TEXT; v_estado TEXT; it JSONB;
    v_item RECORD; v_dentro BOOLEAN; v_valor NUMERIC; v_n INT := 0;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_programaciones WHERE id = p_programacion_id) THEN
        RAISE EXCEPTION 'Programación no existe'; END IF;

    v_pauta := fn_enex_pauta_de_programacion(p_programacion_id);
    v_firma_m := NULLIF(TRIM(COALESCE(p_firma_mandante_url,'')),'');
    v_estado := CASE WHEN v_firma_m IS NOT NULL THEN 'cumplida' ELSE 'ejecutada' END;

    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion, ot_numero, ejecutor,
        observacion, evidencia_urls, firma_tecnico_url, tecnico_nombre,
        firma_mandante_url, firmante_mandante_nombre, firmante_mandante_at, registrado_por, client_uuid,
        foto_antes_url, foto_despues_url)
    VALUES (p_programacion_id, v_pauta, v_estado, COALESCE(p_fecha, CURRENT_DATE), p_ot_numero, p_ejecutor,
        p_observacion, p_evidencia_urls, NULLIF(TRIM(COALESCE(p_firma_tecnico_url,'')),''),
        NULLIF(TRIM(COALESCE(p_tecnico_nombre,'')),''), v_firma_m,
        NULLIF(TRIM(COALESCE(p_firmante_mandante,'')),''),
        CASE WHEN v_firma_m IS NOT NULL THEN NOW() END, auth.uid(), p_client_uuid,
        NULLIF(TRIM(COALESCE(p_foto_antes_url,'')),''), NULLIF(TRIM(COALESCE(p_foto_despues_url,'')),''))
    ON CONFLICT (programacion_id) DO UPDATE SET
        pauta_id = EXCLUDED.pauta_id, estado = v_estado,
        fecha_ejecucion = COALESCE(EXCLUDED.fecha_ejecucion, enex_ejecuciones.fecha_ejecucion),
        ot_numero = COALESCE(EXCLUDED.ot_numero, enex_ejecuciones.ot_numero),
        ejecutor = COALESCE(EXCLUDED.ejecutor, enex_ejecuciones.ejecutor),
        observacion = COALESCE(EXCLUDED.observacion, enex_ejecuciones.observacion),
        evidencia_urls = COALESCE(EXCLUDED.evidencia_urls, enex_ejecuciones.evidencia_urls),
        firma_tecnico_url = COALESCE(EXCLUDED.firma_tecnico_url, enex_ejecuciones.firma_tecnico_url),
        tecnico_nombre = COALESCE(EXCLUDED.tecnico_nombre, enex_ejecuciones.tecnico_nombre),
        firma_mandante_url = COALESCE(EXCLUDED.firma_mandante_url, enex_ejecuciones.firma_mandante_url),
        firmante_mandante_nombre = COALESCE(EXCLUDED.firmante_mandante_nombre, enex_ejecuciones.firmante_mandante_nombre),
        firmante_mandante_at = COALESCE(enex_ejecuciones.firmante_mandante_at, EXCLUDED.firmante_mandante_at),
        foto_antes_url = COALESCE(EXCLUDED.foto_antes_url, enex_ejecuciones.foto_antes_url),
        foto_despues_url = COALESCE(EXCLUDED.foto_despues_url, enex_ejecuciones.foto_despues_url),
        updated_at = NOW()
    RETURNING id INTO v_ejec;

    FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
        SELECT * INTO v_item FROM enex_pauta_items WHERE id = (it->>'pauta_item_id')::UUID;
        IF v_item.id IS NULL THEN CONTINUE; END IF;
        v_valor := NULLIF(it->>'valor_medicion','')::NUMERIC;
        v_dentro := NULL;
        IF v_item.tipo_campo = 'medicion' AND v_valor IS NOT NULL
           AND (v_item.tolerancia_min IS NOT NULL OR v_item.tolerancia_max IS NOT NULL) THEN
            v_dentro := (v_item.tolerancia_min IS NULL OR v_valor >= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_min)
                    AND (v_item.tolerancia_max IS NULL OR v_valor <= COALESCE(v_item.valor_referencia,0) + v_item.tolerancia_max);
        END IF;

        INSERT INTO enex_ejecucion_items (ejecucion_id, pauta_item_id, resultado, valor_medicion,
            dentro_tolerancia, foto_url, observacion)
        VALUES (v_ejec, v_item.id, NULLIF(it->>'resultado',''), v_valor, v_dentro,
            NULLIF(it->>'foto_url',''), NULLIF(it->>'observacion',''))
        ON CONFLICT (ejecucion_id, pauta_item_id) DO UPDATE SET
            resultado = EXCLUDED.resultado, valor_medicion = EXCLUDED.valor_medicion,
            dentro_tolerancia = EXCLUDED.dentro_tolerancia,
            foto_url = COALESCE(EXCLUDED.foto_url, enex_ejecucion_items.foto_url),
            observacion = EXCLUDED.observacion;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec, 'estado', v_estado,
        'cumplida', v_firma_m IS NOT NULL, 'items', v_n, 'pauta_id', v_pauta);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_ejecutar_pauta(UUID,JSONB,TEXT,TEXT,TEXT,DATE,TEXT[],TEXT,TEXT,TEXT,TEXT,UUID,TEXT,TEXT) TO authenticated;

-- Exponer las fotos en la vista de reporte para el informe PDF (si se usa)
DROP VIEW IF EXISTS v_enex_ejecucion_items;
CREATE VIEW v_enex_ejecucion_items AS
SELECT ei.*, it.bloque, it.bloque_orden, it.orden, it.codigo AS item_codigo, it.descripcion,
       it.periodicidad, it.tipo_campo, it.unidad, it.valor_referencia, it.tolerancia_min,
       it.tolerancia_max, it.requiere_foto
FROM enex_ejecucion_items ei
JOIN enex_pauta_items it ON it.id = ei.pauta_item_id;
GRANT SELECT ON v_enex_ejecucion_items TO authenticated;

SELECT jsonb_build_object(
  'cols', (SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns
             WHERE table_name='enex_ejecuciones' AND column_name IN ('foto_antes_url','foto_despues_url')),
  'rpc_args', (SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname='rpc_enex_ejecutar_pauta')
) AS resultado;

NOTIFY pgrst, 'reload schema';
