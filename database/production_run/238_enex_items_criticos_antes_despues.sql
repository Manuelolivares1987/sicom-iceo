-- ============================================================================
-- SICOM-ICEO | 238 — ENEX terreno: actividades CRÍTICAS con foto antes/después
-- ============================================================================
-- Refinamiento del mandante (2026-07-21): la evidencia fotográfica es POR
-- ACTIVIDAD (ítem de la pauta):
--   * Actividades CRÍTICAS (ej. sellos) → foto del ANTES y del DESPUÉS.
--   * El resto → una sola foto.
--   * enex_pauta_items += critico (marcable en el editor).
--   * enex_ejecucion_items += foto_antes_url, foto_despues_url (críticos);
--     foto_url sigue siendo la foto única del resto.
--   * rpc_enex_ejecutar_pauta lee foto_antes_url/foto_despues_url por ítem.
-- (MIG237 dejó columnas antes/después a nivel de ejecución; quedan sin uso — la
--  evidencia crítica es por actividad.)
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE enex_pauta_items
    ADD COLUMN IF NOT EXISTS critico BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN enex_pauta_items.critico IS 'Actividad crítica: exige foto del antes y del después en terreno. MIG238.';

ALTER TABLE enex_ejecucion_items
    ADD COLUMN IF NOT EXISTS foto_antes_url   TEXT,
    ADD COLUMN IF NOT EXISTS foto_despues_url TEXT;
COMMENT ON COLUMN enex_ejecucion_items.foto_antes_url   IS 'Foto del antes (actividad crítica). MIG238.';
COMMENT ON COLUMN enex_ejecucion_items.foto_despues_url IS 'Foto del después (actividad crítica). MIG238.';

-- Marcar como críticas las actividades de sellos (arranque; el editor permite ajustar).
UPDATE enex_pauta_items
   SET critico = true
 WHERE critico = false
   AND (descripcion ILIKE '%sello%' OR bloque ILIKE '%sello%');

-- RPC: además de foto_url por ítem, guarda foto_antes_url / foto_despues_url.
-- Misma firma que MIG237 (no se cambia la lista de argumentos).
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
            dentro_tolerancia, foto_url, foto_antes_url, foto_despues_url, observacion)
        VALUES (v_ejec, v_item.id, NULLIF(it->>'resultado',''), v_valor, v_dentro,
            NULLIF(it->>'foto_url',''), NULLIF(it->>'foto_antes_url',''), NULLIF(it->>'foto_despues_url',''),
            NULLIF(it->>'observacion',''))
        ON CONFLICT (ejecucion_id, pauta_item_id) DO UPDATE SET
            resultado = EXCLUDED.resultado, valor_medicion = EXCLUDED.valor_medicion,
            dentro_tolerancia = EXCLUDED.dentro_tolerancia,
            foto_url = COALESCE(EXCLUDED.foto_url, enex_ejecucion_items.foto_url),
            foto_antes_url = COALESCE(EXCLUDED.foto_antes_url, enex_ejecucion_items.foto_antes_url),
            foto_despues_url = COALESCE(EXCLUDED.foto_despues_url, enex_ejecucion_items.foto_despues_url),
            observacion = EXCLUDED.observacion;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_ejec, 'estado', v_estado,
        'cumplida', v_firma_m IS NOT NULL, 'items', v_n, 'pauta_id', v_pauta);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_ejecutar_pauta(UUID,JSONB,TEXT,TEXT,TEXT,DATE,TEXT[],TEXT,TEXT,TEXT,TEXT,UUID,TEXT,TEXT) TO authenticated;

-- Editor de pautas: guardar el flag "crítico".
CREATE OR REPLACE FUNCTION rpc_enex_pauta_item_guardar(
    p_id UUID, p_pauta_id UUID, p_bloque TEXT, p_bloque_orden INT, p_orden INT,
    p_codigo TEXT, p_descripcion TEXT, p_periodicidad TEXT, p_tipo_campo TEXT,
    p_unidad TEXT, p_valor_referencia NUMERIC, p_tolerancia_min NUMERIC, p_tolerancia_max NUMERIC,
    p_requiere_foto BOOLEAN, p_obligatorio BOOLEAN, p_critico BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_id IS NULL THEN
        INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion,
            periodicidad, tipo_campo, unidad, valor_referencia, tolerancia_min, tolerancia_max,
            requiere_foto, obligatorio, critico)
        VALUES (p_pauta_id, p_bloque, p_bloque_orden, p_orden, p_codigo, p_descripcion,
            COALESCE(p_periodicidad,'trimestral'), COALESCE(p_tipo_campo,'ok_nook'), p_unidad,
            p_valor_referencia, p_tolerancia_min, p_tolerancia_max,
            COALESCE(p_requiere_foto,false), COALESCE(p_obligatorio,true), COALESCE(p_critico,false))
        RETURNING id INTO v_id;
    ELSE
        UPDATE enex_pauta_items SET bloque=p_bloque, bloque_orden=p_bloque_orden, orden=p_orden,
            codigo=p_codigo, descripcion=p_descripcion, periodicidad=COALESCE(p_periodicidad,periodicidad),
            tipo_campo=COALESCE(p_tipo_campo,tipo_campo), unidad=p_unidad, valor_referencia=p_valor_referencia,
            tolerancia_min=p_tolerancia_min, tolerancia_max=p_tolerancia_max,
            requiere_foto=COALESCE(p_requiere_foto,requiere_foto), obligatorio=COALESCE(p_obligatorio,obligatorio),
            critico=COALESCE(p_critico,critico)
        WHERE id=p_id RETURNING id INTO v_id;
    END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_pauta_item_guardar(UUID,UUID,TEXT,INT,INT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC,BOOLEAN,BOOLEAN,BOOLEAN) TO authenticated;

-- Vista de ítems de ejecución (recrear para incluir foto_antes/después + critico)
DROP VIEW IF EXISTS v_enex_ejecucion_items;
CREATE VIEW v_enex_ejecucion_items AS
SELECT ei.*, it.bloque, it.bloque_orden, it.orden, it.codigo AS item_codigo, it.descripcion,
       it.periodicidad, it.tipo_campo, it.unidad, it.valor_referencia, it.tolerancia_min,
       it.tolerancia_max, it.requiere_foto, it.critico
FROM enex_ejecucion_items ei
JOIN enex_pauta_items it ON it.id = ei.pauta_item_id;
GRANT SELECT ON v_enex_ejecucion_items TO authenticated;

SELECT jsonb_build_object(
  'items_criticos', (SELECT COUNT(*) FROM enex_pauta_items WHERE critico),
  'ejemplos', (SELECT array_agg(descripcion) FROM (SELECT descripcion FROM enex_pauta_items WHERE critico LIMIT 5) s),
  'cols_ejec_items', (SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns
             WHERE table_name='enex_ejecucion_items' AND column_name IN ('foto_antes_url','foto_despues_url'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
