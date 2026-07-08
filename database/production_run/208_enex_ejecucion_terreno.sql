-- ============================================================================
-- SICOM-ICEO | 208 — Ejecución de pauta en terreno (ENEX Fase 2 parte 2)
-- ============================================================================
-- El mantenedor ejecuta la pauta de la instalación programada desde el celular:
-- marca cada ítem (OK/NO OK, sí/no, medición con tolerancia, texto), fotos,
-- firma técnico y firma del mandante. La firma del mandante deja la ejecución
-- CUMPLIDA (alimenta el KPI de la Fase 1).
--
--   * enex_ejecuciones += pauta_id, firma_tecnico_url, tecnico_nombre,
--     client_uuid (idempotencia para futura ejecución offline).
--   * enex_ejecucion_items: resultado por ítem de la pauta (con dentro_tolerancia
--     calculado en el servidor para las mediciones).
--   * fn_enex_pauta_de_programacion(): resuelve la pauta de una programación
--     (override de la instalación, o por tipo de instalación + servicio).
--   * v_enex_terreno_pendientes: lo que falta ejecutar por período.
--   * rpc_enex_ejecutar_pauta(): guarda ejecución + ítems en una transacción.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_pautas') THEN
        RAISE EXCEPTION 'STOP — falta MIG207'; END IF;
END $$;

-- ── 1. Quién ejecuta en terreno ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enex_puede_ejecutar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
    SELECT auth.uid() IS NOT NULL AND fn_user_rol() IN (
        'administrador','subgerente_operaciones','jefe_operaciones','supervisor','planificador',
        'jefe_mantenimiento','tecnico_mantenimiento','operador_taller','operador_calama');
$$;
GRANT EXECUTE ON FUNCTION fn_enex_puede_ejecutar() TO authenticated;

-- ── 2. Campos nuevos en ejecuciones + tabla de ítems ─────────────────────────
ALTER TABLE enex_ejecuciones
    ADD COLUMN IF NOT EXISTS pauta_id UUID REFERENCES enex_pautas(id),
    ADD COLUMN IF NOT EXISTS firma_tecnico_url TEXT,
    ADD COLUMN IF NOT EXISTS tecnico_nombre TEXT,
    ADD COLUMN IF NOT EXISTS client_uuid UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uq_enex_ejec_client ON enex_ejecuciones(client_uuid) WHERE client_uuid IS NOT NULL;

CREATE TABLE IF NOT EXISTS enex_ejecucion_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id  UUID NOT NULL REFERENCES enex_ejecuciones(id) ON DELETE CASCADE,
    pauta_item_id UUID NOT NULL REFERENCES enex_pauta_items(id),
    resultado     TEXT,                 -- ok / no_ok / na / si / no
    valor_medicion NUMERIC,
    dentro_tolerancia BOOLEAN,          -- calculado en el servidor (medición)
    foto_url      TEXT,
    observacion   TEXT,
    created_at    TIMESTAMPTZ DEFAULT now(),
    UNIQUE (ejecucion_id, pauta_item_id)
);
CREATE INDEX IF NOT EXISTS idx_enex_ejec_items ON enex_ejecucion_items(ejecucion_id);
COMMENT ON TABLE enex_ejecucion_items IS 'Resultado por ítem de una ejecución de pauta en terreno. MIG208.';

ALTER TABLE enex_ejecucion_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    DROP POLICY IF EXISTS pol_enex_ejec_items_sel ON enex_ejecucion_items;
    CREATE POLICY pol_enex_ejec_items_sel ON enex_ejecucion_items FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);
END $$;

-- ── 3. Resolver la pauta de una programación ─────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enex_pauta_de_programacion(p_programacion_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
    SELECT COALESCE(
        CASE WHEN pr.tipo_servicio='mantencion' THEN i.pauta_mantencion_id ELSE i.pauta_calibracion_id END,
        (SELECT p.id FROM enex_pautas p
          WHERE p.activo AND p.tipo_servicio = pr.tipo_servicio
            AND i.tipo = ANY(p.aplica_tipos)
          ORDER BY p.es_borrador ASC, p.version DESC
          LIMIT 1)
    )
    FROM enex_programaciones pr
    JOIN enex_instalaciones i ON i.id = pr.instalacion_id
    WHERE pr.id = p_programacion_id;
$$;
GRANT EXECUTE ON FUNCTION fn_enex_pauta_de_programacion(UUID) TO authenticated;

-- ── 4. Vista: pendientes de ejecución en terreno ─────────────────────────────
DROP VIEW IF EXISTS v_enex_terreno_pendientes;
CREATE VIEW v_enex_terreno_pendientes AS
SELECT pr.id AS programacion_id, pr.periodo_anio, pr.periodo_mes, pr.tipo_servicio, pr.fecha_programada,
       i.id AS instalacion_id, i.nombre AS instalacion, i.tipo AS instalacion_tipo, i.patente, i.linea,
       f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
       fn_enex_pauta_de_programacion(pr.id) AS pauta_id,
       (SELECT p.nombre FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_nombre,
       (SELECT p.es_borrador FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_borrador,
       (SELECT COUNT(*) FROM enex_pauta_items it WHERE it.pauta_id = fn_enex_pauta_de_programacion(pr.id) AND it.activo) AS pauta_items,
       e.id AS ejecucion_id, e.estado, e.firma_mandante_url,
       (e.firma_mandante_url IS NOT NULL) AS cumplida
FROM enex_programaciones pr
JOIN enex_instalaciones i ON i.id = pr.instalacion_id
JOIN enex_faenas f        ON f.id = i.faena_id
LEFT JOIN enex_ejecuciones e ON e.programacion_id = pr.id;
GRANT SELECT ON v_enex_terreno_pendientes TO authenticated;

-- Detalle de una ejecución con sus ítems (para ver/editar)
DROP VIEW IF EXISTS v_enex_ejecucion_items;
CREATE VIEW v_enex_ejecucion_items AS
SELECT ei.*, it.bloque, it.bloque_orden, it.orden, it.codigo AS item_codigo, it.descripcion,
       it.periodicidad, it.tipo_campo, it.unidad, it.valor_referencia, it.tolerancia_min,
       it.tolerancia_max, it.requiere_foto
FROM enex_ejecucion_items ei
JOIN enex_pauta_items it ON it.id = ei.pauta_item_id;
GRANT SELECT ON v_enex_ejecucion_items TO authenticated;

-- ── 5. RPC: ejecutar la pauta (ejecución + ítems) ────────────────────────────
-- p_items: [{pauta_item_id, resultado, valor_medicion, foto_url, observacion}]
CREATE OR REPLACE FUNCTION rpc_enex_ejecutar_pauta(
    p_programacion_id UUID, p_items JSONB,
    p_ot_numero TEXT DEFAULT NULL, p_ejecutor TEXT DEFAULT NULL, p_observacion TEXT DEFAULT NULL,
    p_fecha DATE DEFAULT NULL, p_evidencia_urls TEXT[] DEFAULT NULL,
    p_firma_tecnico_url TEXT DEFAULT NULL, p_tecnico_nombre TEXT DEFAULT NULL,
    p_firma_mandante_url TEXT DEFAULT NULL, p_firmante_mandante TEXT DEFAULT NULL,
    p_client_uuid UUID DEFAULT NULL
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

    -- Cabecera (upsert por programación; una ejecución por programación)
    INSERT INTO enex_ejecuciones (programacion_id, pauta_id, estado, fecha_ejecucion, ot_numero, ejecutor,
        observacion, evidencia_urls, firma_tecnico_url, tecnico_nombre,
        firma_mandante_url, firmante_mandante_nombre, firmante_mandante_at, registrado_por, client_uuid)
    VALUES (p_programacion_id, v_pauta, v_estado, COALESCE(p_fecha, CURRENT_DATE), p_ot_numero, p_ejecutor,
        p_observacion, p_evidencia_urls, NULLIF(TRIM(COALESCE(p_firma_tecnico_url,'')),''),
        NULLIF(TRIM(COALESCE(p_tecnico_nombre,'')),''), v_firma_m,
        NULLIF(TRIM(COALESCE(p_firmante_mandante,'')),''),
        CASE WHEN v_firma_m IS NOT NULL THEN NOW() END, auth.uid(), p_client_uuid)
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

    -- Ítems: upsert con cálculo de tolerancia
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
GRANT EXECUTE ON FUNCTION rpc_enex_ejecutar_pauta(UUID,JSONB,TEXT,TEXT,TEXT,DATE,TEXT[],TEXT,TEXT,TEXT,TEXT,UUID) TO authenticated;

-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tabla_items', (SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_ejecucion_items')),
    'cols_ejec', (SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns
        WHERE table_name='enex_ejecuciones' AND column_name IN ('pauta_id','firma_tecnico_url','client_uuid')),
    'fn_pauta', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_enex_pauta_de_programacion')),
    'rpc_ejecutar', (SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_enex_ejecutar_pauta')),
    'vista_pend', (SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_enex_terreno_pendientes'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
