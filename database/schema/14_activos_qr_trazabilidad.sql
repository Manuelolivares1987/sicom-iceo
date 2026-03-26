-- SICOM-ICEO | Activos QR + Trazabilidad Completa
-- ============================================================================
-- Ejecutar DESPUÉS de 13.
--
-- 1. Agrega campos faltantes a activos (QR, padre, año, foto, responsable)
-- 2. Crea vista completa de historial por activo
-- 3. Crea vista de ficha digital del activo
-- 4. Crea RPC para generar QR de activo
-- 5. Crea índices de performance
-- ============================================================================


-- ############################################################################
-- 1. CAMPOS NUEVOS EN ACTIVOS
-- ############################################################################

-- QR code único por activo
ALTER TABLE activos ADD COLUMN IF NOT EXISTS qr_code VARCHAR(100) UNIQUE;
ALTER TABLE activos ADD COLUMN IF NOT EXISTS qr_url TEXT;

-- Jerarquía de activos (equipo padre)
ALTER TABLE activos ADD COLUMN IF NOT EXISTS activo_padre_id UUID REFERENCES activos(id);

-- Datos adicionales de trazabilidad
ALTER TABLE activos ADD COLUMN IF NOT EXISTS anio_fabricacion INTEGER;
ALTER TABLE activos ADD COLUMN IF NOT EXISTS foto_url TEXT;
ALTER TABLE activos ADD COLUMN IF NOT EXISTS responsable_id UUID REFERENCES usuarios_perfil(id);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS valor_adquisicion NUMERIC(15,2);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS proveedor VARCHAR(200);
ALTER TABLE activos ADD COLUMN IF NOT EXISTS datos_tecnicos JSONB DEFAULT '{}';

-- Índices nuevos
CREATE INDEX IF NOT EXISTS idx_activos_qr_code ON activos (qr_code) WHERE qr_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activos_padre ON activos (activo_padre_id) WHERE activo_padre_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activos_responsable ON activos (responsable_id) WHERE responsable_id IS NOT NULL;


-- ############################################################################
-- 2. RPC GENERAR QR PARA ACTIVO
-- ############################################################################

CREATE OR REPLACE FUNCTION rpc_generar_qr_activo(
    p_activo_id UUID,
    p_base_url  TEXT DEFAULT 'https://pilladoiceo.netlify.app'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_activo RECORD;
    v_qr_code VARCHAR(100);
    v_qr_url TEXT;
BEGIN
    SELECT id, codigo INTO v_activo
    FROM activos WHERE id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado.';
    END IF;

    -- Generar código QR único basado en código del activo
    v_qr_code := 'SICOM-ACT-' || v_activo.codigo || '-' || SUBSTRING(p_activo_id::TEXT, 1, 8);
    v_qr_url := p_base_url || '/equipo/' || p_activo_id;

    -- Actualizar activo
    UPDATE activos
    SET qr_code = v_qr_code,
        qr_url = v_qr_url,
        updated_at = NOW()
    WHERE id = p_activo_id;

    RETURN jsonb_build_object(
        'activo_id', p_activo_id,
        'codigo', v_activo.codigo,
        'qr_code', v_qr_code,
        'qr_url', v_qr_url
    );
END;
$$;

-- Generar QR para todos los activos existentes que no tengan
DO $$
DECLARE
    v_activo RECORD;
BEGIN
    FOR v_activo IN SELECT id FROM activos WHERE qr_code IS NULL
    LOOP
        PERFORM rpc_generar_qr_activo(v_activo.id);
    END LOOP;
END $$;


-- ############################################################################
-- 3. VISTA: HISTORIAL COMPLETO DE MANTENIMIENTO POR ACTIVO
-- ############################################################################

CREATE OR REPLACE VIEW v_historial_mantenimiento_activo AS
SELECT
    ot.activo_id,
    ot.id AS ot_id,
    ot.folio,
    ot.tipo,
    ot.estado,
    ot.prioridad,
    ot.fecha_programada,
    ot.fecha_inicio,
    ot.fecha_termino,
    ot.fecha_cierre_supervisor,
    ot.observaciones,
    ot.observaciones_supervisor,
    ot.causa_no_ejecucion,
    ot.costo_mano_obra,
    ot.costo_materiales,
    (COALESCE(ot.costo_mano_obra, 0) + COALESCE(ot.costo_materiales, 0)) AS costo_total,
    ot.generada_automaticamente,
    -- Responsable
    resp.nombre_completo AS responsable_nombre,
    -- Supervisor
    sup.nombre_completo AS supervisor_nombre,
    -- Checklist resumen
    (SELECT COUNT(*) FROM checklist_ot cl WHERE cl.ot_id = ot.id) AS checklist_total,
    (SELECT COUNT(*) FROM checklist_ot cl WHERE cl.ot_id = ot.id AND cl.resultado = 'ok') AS checklist_ok,
    (SELECT COUNT(*) FROM checklist_ot cl WHERE cl.ot_id = ot.id AND cl.resultado = 'no_ok') AS checklist_no_ok,
    -- Evidencias
    (SELECT COUNT(*) FROM evidencias_ot ev WHERE ev.ot_id = ot.id) AS evidencias_count,
    -- Materiales
    (SELECT COUNT(*) FROM movimientos_inventario mi WHERE mi.ot_id = ot.id AND mi.tipo IN ('salida','merma')) AS materiales_count,
    -- Tiempo fuera de servicio (horas entre inicio y término)
    CASE
        WHEN ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0, 1)
        ELSE NULL
    END AS horas_fuera_servicio,
    -- Faena
    ot.faena_id,
    ot.contrato_id
FROM ordenes_trabajo ot
LEFT JOIN usuarios_perfil resp ON resp.id = ot.responsable_id
LEFT JOIN usuarios_perfil sup ON sup.id = ot.supervisor_cierre_id
ORDER BY ot.fecha_programada DESC NULLS LAST, ot.created_at DESC;

COMMENT ON VIEW v_historial_mantenimiento_activo IS
'Historial completo de mantenimiento por activo: OTs, checklist, evidencias, costos, tiempos.';


-- ############################################################################
-- 4. VISTA: FICHA DIGITAL COMPLETA DEL ACTIVO
-- ############################################################################

CREATE OR REPLACE VIEW v_ficha_activo AS
SELECT
    a.id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.criticidad,
    a.estado,
    a.numero_serie,
    a.fecha_alta,
    a.anio_fabricacion,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.ciclos_actual,
    a.ubicacion_detalle,
    a.foto_url,
    a.qr_code,
    a.qr_url,
    a.valor_adquisicion,
    a.proveedor,
    a.datos_tecnicos,
    a.notas,
    -- Marca / Modelo
    m.nombre AS modelo_nombre,
    ma.nombre AS marca_nombre,
    -- Faena
    f.nombre AS faena_nombre,
    f.codigo AS faena_codigo,
    -- Responsable
    resp.nombre_completo AS responsable_nombre,
    -- Padre
    ap.codigo AS padre_codigo,
    ap.nombre AS padre_nombre,
    -- Contadores
    (SELECT COUNT(*) FROM ordenes_trabajo ot WHERE ot.activo_id = a.id) AS total_ots,
    (SELECT COUNT(*) FROM ordenes_trabajo ot WHERE ot.activo_id = a.id AND ot.tipo = 'preventivo') AS ots_preventivas,
    (SELECT COUNT(*) FROM ordenes_trabajo ot WHERE ot.activo_id = a.id AND ot.tipo = 'correctivo') AS ots_correctivas,
    (SELECT COUNT(*) FROM ordenes_trabajo ot WHERE ot.activo_id = a.id AND ot.estado IN ('creada','asignada','en_ejecucion','pausada')) AS ots_abiertas,
    -- Costo acumulado
    COALESCE((
        SELECT SUM(mi.cantidad * mi.costo_unitario)
        FROM movimientos_inventario mi
        WHERE mi.activo_id = a.id AND mi.tipo IN ('salida','merma')
    ), 0) AS costo_materiales_acumulado,
    -- Última mantención
    (SELECT MAX(ot.fecha_termino) FROM ordenes_trabajo ot
     WHERE ot.activo_id = a.id AND ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')) AS ultima_mantencion,
    -- Próxima mantención
    (SELECT MIN(pm.proxima_ejecucion_fecha) FROM planes_mantenimiento pm
     WHERE pm.activo_id = a.id AND pm.activo_plan = true) AS proxima_mantencion,
    -- Certificaciones vigentes / vencidas
    (SELECT COUNT(*) FROM certificaciones c WHERE c.activo_id = a.id AND c.estado = 'vigente') AS cert_vigentes,
    (SELECT COUNT(*) FROM certificaciones c WHERE c.activo_id = a.id AND c.estado = 'vencido') AS cert_vencidas,
    (SELECT COUNT(*) FROM certificaciones c WHERE c.activo_id = a.id AND c.estado = 'por_vencer') AS cert_por_vencer,
    -- Incidentes
    (SELECT COUNT(*) FROM incidentes i WHERE i.activo_id = a.id) AS total_incidentes,
    -- Planes PM activos
    (SELECT COUNT(*) FROM planes_mantenimiento pm WHERE pm.activo_id = a.id AND pm.activo_plan = true) AS planes_pm_activos,
    -- MTTR (promedio horas reparación correctiva)
    (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (ot.fecha_termino - ot.fecha_inicio)) / 3600.0), 1)
     FROM ordenes_trabajo ot
     WHERE ot.activo_id = a.id AND ot.tipo = 'correctivo'
       AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS mttr_horas,
    -- Timestamps
    a.created_at,
    a.updated_at
FROM activos a
LEFT JOIN modelos m ON m.id = a.modelo_id
LEFT JOIN marcas ma ON ma.id = m.marca_id
LEFT JOIN faenas f ON f.id = a.faena_id
LEFT JOIN usuarios_perfil resp ON resp.id = a.responsable_id
LEFT JOIN activos ap ON ap.id = a.activo_padre_id;

COMMENT ON VIEW v_ficha_activo IS
'Ficha digital completa del activo: datos, contadores, costos, certificaciones, KPIs.';


-- ############################################################################
-- 5. RPC: OBTENER FICHA COMPLETA DE ACTIVO (para QR scan)
-- ############################################################################

CREATE OR REPLACE FUNCTION rpc_ficha_activo(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_ficha RECORD;
    v_result JSONB;
BEGIN
    SELECT * INTO v_ficha
    FROM v_ficha_activo
    WHERE id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado.';
    END IF;

    RETURN to_jsonb(v_ficha);
END;
$$;

-- También buscar por código QR
CREATE OR REPLACE FUNCTION rpc_ficha_activo_por_qr(p_qr_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_activo_id UUID;
BEGIN
    SELECT id INTO v_activo_id
    FROM activos WHERE qr_code = p_qr_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró activo con QR: %', p_qr_code;
    END IF;

    RETURN rpc_ficha_activo(v_activo_id);
END;
$$;


-- ############################################################################
-- RESUMEN
-- ############################################################################
--
-- CAMPOS NUEVOS EN ACTIVOS:
-- ├── qr_code          → código QR único
-- ├── qr_url           → URL de la ficha digital
-- ├── activo_padre_id  → jerarquía de componentes
-- ├── anio_fabricacion  → año de fabricación
-- ├── foto_url         → foto del activo
-- ├── responsable_id   → responsable asignado
-- ├── valor_adquisicion → valor de compra
-- ├── proveedor        → proveedor del equipo
-- └── datos_tecnicos   → JSONB para specs técnicos
--
-- VISTAS:
-- ├── v_historial_mantenimiento_activo → timeline completo
-- └── v_ficha_activo                   → dashboard de activo
--
-- RPCs:
-- ├── rpc_generar_qr_activo(id)        → genera QR + URL
-- ├── rpc_ficha_activo(id)             → ficha completa
-- └── rpc_ficha_activo_por_qr(code)    → ficha por escaneo QR
--
-- ============================================================================
