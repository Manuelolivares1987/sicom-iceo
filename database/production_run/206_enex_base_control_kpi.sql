-- ============================================================================
-- SICOM-ICEO | 206 — Módulo Calama-ENEX (FASE 1): control + KPI de cumplimiento
-- ============================================================================
-- Manuel (2026-07-08): sistema de control/ejecución/reportabilidad para la
-- sucursal Calama — contrato de mantención de instalaciones de combustibles y
-- lubricantes ENEX/ESM (faenas Centinela, Nueva Centinela DES, Spence,
-- Lomas Bayas). MÓDULO NUEVO AISLADO (no toca flota ni operacion-calama).
--
-- FASE 1 = Control + KPI mensual:
--   * Catálogo de instalaciones por faena (EESS, petroleras, semimóviles,
--     truck shops, camiones).
--   * Programación mensual por instalación × tipo de servicio (mantención /
--     calibración) — replica el "Panel de Control ESM-ENEX".
--   * Ejecución: se marca CUMPLIDA solo con firma del mandante (regla Manuel).
--   * KPI de cumplimiento por faena/mes con tramos de multa (0/10/20%) y
--     monto en riesgo sobre la facturación de la faena.
--
-- Regla KPI Fase 1 (simple, a refinar con "KPI Mantenimiento V8"):
--   cumplimiento% = cumplidas / programadas del período; todas pesan igual.
--   Tramos: ≥96%→0% · 90-95%→10% · 80-89%→20% · <80%→revisión continuidad.
--
-- Autorización: administrador / subgerente_operaciones / jefe_operaciones /
-- supervisor / planificador gestionan ENEX (fn_user_rol()). anon sin acceso.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. Helper de autorización del módulo ─────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enex_puede_gestionar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
    SELECT auth.uid() IS NOT NULL AND fn_user_rol() IN (
        'administrador','subgerente_operaciones','jefe_operaciones',
        'supervisor','planificador','jefe_mantenimiento');
$$;
GRANT EXECUTE ON FUNCTION fn_enex_puede_gestionar() TO authenticated;


-- ── 1. Faenas del contrato ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_faenas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo        TEXT UNIQUE NOT NULL,
    nombre        TEXT NOT NULL,
    cliente_minero TEXT,
    contrato_minero TEXT,
    operador      TEXT,                    -- ENEX / ESM
    lineas        TEXT[],                  -- combustible / lubricante
    vigencia_hasta DATE,
    facturacion_mensual_clp NUMERIC(14,0) DEFAULT 0,
    pct_facturacion NUMERIC(5,2),
    activo        BOOLEAN NOT NULL DEFAULT true,
    orden         INT DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE enex_faenas IS 'Faenas del contrato ENEX/ESM (Calama). MIG206.';

CREATE TABLE IF NOT EXISTS enex_instalaciones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES enex_faenas(id) ON DELETE CASCADE,
    codigo        TEXT,
    nombre        TEXT NOT NULL,
    tipo          TEXT NOT NULL CHECK (tipo IN ('eess','petrolera','semimovil','truck_shop','camion','otro')),
    linea         TEXT CHECK (linea IN ('combustible','lubricante')),
    pauta         TEXT,                    -- pauta aplicable (referencia)
    frecuencia_meses INT NOT NULL DEFAULT 3,
    patente       TEXT,                    -- camiones
    activo        BOOLEAN NOT NULL DEFAULT true,
    orden         INT DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_enex_inst_faena ON enex_instalaciones(faena_id) WHERE activo;
COMMENT ON TABLE enex_instalaciones IS 'Catálogo de instalaciones a mantener por faena. MIG206.';


-- ── 2. Programación (plan) y ejecución (cumplimiento) ────────────────────────
CREATE TABLE IF NOT EXISTS enex_programaciones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instalacion_id UUID NOT NULL REFERENCES enex_instalaciones(id) ON DELETE CASCADE,
    tipo_servicio TEXT NOT NULL CHECK (tipo_servicio IN ('mantencion','calibracion')),
    periodo_anio  INT NOT NULL,
    periodo_mes   INT NOT NULL CHECK (periodo_mes BETWEEN 1 AND 12),
    fecha_programada DATE,
    observacion   TEXT,
    creado_por    UUID REFERENCES usuarios_perfil(id),
    created_at    TIMESTAMPTZ DEFAULT now(),
    UNIQUE (instalacion_id, tipo_servicio, periodo_anio, periodo_mes)
);
CREATE INDEX IF NOT EXISTS idx_enex_prog_periodo ON enex_programaciones(periodo_anio, periodo_mes);
COMMENT ON TABLE enex_programaciones IS 'Plan mensual: instalación × servicio programado en un período. MIG206.';

CREATE TABLE IF NOT EXISTS enex_ejecuciones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    programacion_id UUID NOT NULL UNIQUE REFERENCES enex_programaciones(id) ON DELETE CASCADE,
    estado        TEXT NOT NULL DEFAULT 'ejecutada'
                     CHECK (estado IN ('ejecutada','cumplida','no_realizada')),
    fecha_ejecucion DATE,
    ot_numero     TEXT,                    -- N° OT del mandante
    ejecutor      TEXT,                    -- mantenedor(es)
    observacion   TEXT,
    evidencia_urls TEXT[],
    -- CUMPLIDA (KPI): requiere firma del mandante
    firma_mandante_url TEXT,
    firmante_mandante_nombre TEXT,
    firmante_mandante_at TIMESTAMPTZ,
    registrado_por UUID REFERENCES usuarios_perfil(id),
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE enex_ejecuciones IS 'Ejecución de una programación; cumplida = con firma del mandante (KPI). MIG206.';


-- ── 3. RLS: lectura a autenticados internos; escritura solo por RPC ──────────
ALTER TABLE enex_faenas        ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_instalaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_programaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_ejecuciones   ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['enex_faenas','enex_instalaciones','enex_programaciones','enex_ejecuciones'] LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_sel ON %I', t, t);
        EXECUTE format('CREATE POLICY pol_%s_sel ON %I FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL)', t, t);
    END LOOP;
END $$;
-- catálogo (faenas/instalaciones): admin/gestor puede escribir directo desde la UI
DROP POLICY IF EXISTS pol_enex_inst_wr ON enex_instalaciones;
CREATE POLICY pol_enex_inst_wr ON enex_instalaciones FOR ALL TO authenticated
    USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());
DROP POLICY IF EXISTS pol_enex_faena_wr ON enex_faenas;
CREATE POLICY pol_enex_faena_wr ON enex_faenas FOR ALL TO authenticated
    USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());


-- ── 4. RPCs de programación y ejecución ──────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_programar(
    p_instalacion_id UUID, p_tipo_servicio TEXT,
    p_anio INT, p_mes INT, p_fecha DATE DEFAULT NULL, p_observacion TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_tipo_servicio NOT IN ('mantencion','calibracion') THEN
        RAISE EXCEPTION 'tipo_servicio inválido'; END IF;
    INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
    VALUES (p_instalacion_id, p_tipo_servicio, p_anio, p_mes, p_fecha, p_observacion, auth.uid())
    ON CONFLICT (instalacion_id, tipo_servicio, periodo_anio, periodo_mes)
      DO UPDATE SET fecha_programada = COALESCE(EXCLUDED.fecha_programada, enex_programaciones.fecha_programada),
                    observacion = COALESCE(EXCLUDED.observacion, enex_programaciones.observacion)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('success', true, 'programacion_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_programar(UUID,TEXT,INT,INT,DATE,TEXT) TO authenticated;

-- Quitar del plan (solo si no tiene ejecución registrada)
CREATE OR REPLACE FUNCTION rpc_enex_desprogramar(p_programacion_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = p_programacion_id) THEN
        RAISE EXCEPTION 'No se puede quitar: ya tiene ejecución registrada'; END IF;
    DELETE FROM enex_programaciones WHERE id = p_programacion_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_desprogramar(UUID) TO authenticated;

-- Registrar/actualizar ejecución. Cumplida = con firma del mandante.
CREATE OR REPLACE FUNCTION rpc_enex_registrar_ejecucion(
    p_programacion_id UUID,
    p_fecha DATE DEFAULT NULL, p_ot_numero TEXT DEFAULT NULL, p_ejecutor TEXT DEFAULT NULL,
    p_observacion TEXT DEFAULT NULL, p_evidencia_urls TEXT[] DEFAULT NULL,
    p_firma_mandante_url TEXT DEFAULT NULL, p_firmante_mandante TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_estado TEXT; v_firma TEXT;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_programaciones WHERE id = p_programacion_id) THEN
        RAISE EXCEPTION 'Programación no existe'; END IF;
    v_firma := NULLIF(TRIM(COALESCE(p_firma_mandante_url,'')),'');
    v_estado := CASE WHEN v_firma IS NOT NULL THEN 'cumplida' ELSE 'ejecutada' END;

    INSERT INTO enex_ejecuciones (programacion_id, estado, fecha_ejecucion, ot_numero, ejecutor,
        observacion, evidencia_urls, firma_mandante_url, firmante_mandante_nombre,
        firmante_mandante_at, registrado_por)
    VALUES (p_programacion_id, v_estado, p_fecha, p_ot_numero, p_ejecutor, p_observacion,
        p_evidencia_urls, v_firma, NULLIF(TRIM(COALESCE(p_firmante_mandante,'')),''),
        CASE WHEN v_firma IS NOT NULL THEN NOW() END, auth.uid())
    ON CONFLICT (programacion_id) DO UPDATE SET
        estado = v_estado,
        fecha_ejecucion = COALESCE(EXCLUDED.fecha_ejecucion, enex_ejecuciones.fecha_ejecucion),
        ot_numero = COALESCE(EXCLUDED.ot_numero, enex_ejecuciones.ot_numero),
        ejecutor = COALESCE(EXCLUDED.ejecutor, enex_ejecuciones.ejecutor),
        observacion = COALESCE(EXCLUDED.observacion, enex_ejecuciones.observacion),
        evidencia_urls = COALESCE(EXCLUDED.evidencia_urls, enex_ejecuciones.evidencia_urls),
        firma_mandante_url = COALESCE(EXCLUDED.firma_mandante_url, enex_ejecuciones.firma_mandante_url),
        firmante_mandante_nombre = COALESCE(EXCLUDED.firmante_mandante_nombre, enex_ejecuciones.firmante_mandante_nombre),
        firmante_mandante_at = COALESCE(enex_ejecuciones.firmante_mandante_at, EXCLUDED.firmante_mandante_at),
        updated_at = NOW();

    RETURN jsonb_build_object('success', true, 'estado', v_estado, 'cumplida', v_firma IS NOT NULL);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_registrar_ejecucion(UUID,DATE,TEXT,TEXT,TEXT,TEXT[],TEXT,TEXT) TO authenticated;

-- Marcar "no realizada" (para KPI: cuenta como programada no cumplida con motivo)
CREATE OR REPLACE FUNCTION rpc_enex_marcar_no_realizada(p_programacion_id UUID, p_motivo TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF NULLIF(TRIM(COALESCE(p_motivo,'')),'') IS NULL THEN RAISE EXCEPTION 'Motivo obligatorio'; END IF;
    INSERT INTO enex_ejecuciones (programacion_id, estado, observacion, registrado_por)
    VALUES (p_programacion_id, 'no_realizada', p_motivo, auth.uid())
    ON CONFLICT (programacion_id) DO UPDATE SET estado='no_realizada',
        observacion = p_motivo, updated_at = NOW();
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_marcar_no_realizada(UUID,TEXT) TO authenticated;

-- Copiar el plan de un período a otro (misma instalación × servicio)
CREATE OR REPLACE FUNCTION rpc_enex_duplicar_periodo(
    p_anio_origen INT, p_mes_origen INT, p_anio_dest INT, p_mes_dest INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n INT;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, creado_por)
    SELECT instalacion_id, tipo_servicio, p_anio_dest, p_mes_dest, auth.uid()
      FROM enex_programaciones
     WHERE periodo_anio = p_anio_origen AND periodo_mes = p_mes_origen
    ON CONFLICT (instalacion_id, tipo_servicio, periodo_anio, periodo_mes) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN jsonb_build_object('success', true, 'copiadas', v_n);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_duplicar_periodo(INT,INT,INT,INT) TO authenticated;


-- ── 5. Vistas: panel mensual + KPI ───────────────────────────────────────────
DROP VIEW IF EXISTS v_enex_panel_mensual;
CREATE VIEW v_enex_panel_mensual AS
SELECT p.id AS programacion_id, p.periodo_anio, p.periodo_mes, p.tipo_servicio,
       p.fecha_programada, p.observacion AS prog_observacion,
       i.id AS instalacion_id, i.nombre AS instalacion, i.tipo AS instalacion_tipo,
       i.codigo AS instalacion_codigo, i.linea, i.patente,
       f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
       e.id AS ejecucion_id, e.estado, e.fecha_ejecucion, e.ot_numero, e.ejecutor,
       e.observacion AS ejec_observacion, e.evidencia_urls,
       e.firma_mandante_url, e.firmante_mandante_nombre, e.firmante_mandante_at,
       (e.firma_mandante_url IS NOT NULL) AS cumplida
FROM enex_programaciones p
JOIN enex_instalaciones i ON i.id = p.instalacion_id
JOIN enex_faenas f        ON f.id = i.faena_id
LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id;
GRANT SELECT ON v_enex_panel_mensual TO authenticated;

-- KPI por faena/período: cumplimiento, tramo de multa y monto en riesgo
DROP VIEW IF EXISTS v_enex_kpi_mensual;
CREATE VIEW v_enex_kpi_mensual AS
WITH base AS (
    SELECT f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
           f.facturacion_mensual_clp, p.periodo_anio, p.periodo_mes,
           COUNT(*)::int AS programadas,
           COUNT(*) FILTER (WHERE e.firma_mandante_url IS NOT NULL)::int AS cumplidas
    FROM enex_programaciones p
    JOIN enex_instalaciones i ON i.id = p.instalacion_id
    JOIN enex_faenas f        ON f.id = i.faena_id
    LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id
    GROUP BY f.id, f.codigo, f.nombre, f.facturacion_mensual_clp, p.periodo_anio, p.periodo_mes
)
SELECT b.*,
       CASE WHEN programadas = 0 THEN NULL
            ELSE ROUND(cumplidas::numeric / programadas * 100, 1) END AS cumplimiento_pct,
       CASE WHEN programadas = 0 THEN 0
            WHEN cumplidas::numeric / programadas >= 0.96 THEN 0
            WHEN cumplidas::numeric / programadas >= 0.90 THEN 10
            WHEN cumplidas::numeric / programadas >= 0.80 THEN 20
            ELSE 100 END AS tramo_multa_pct,
       CASE WHEN programadas = 0 THEN 0
            WHEN cumplidas::numeric / programadas >= 0.96 THEN 0
            WHEN cumplidas::numeric / programadas >= 0.90 THEN ROUND(facturacion_mensual_clp * 0.10, 0)
            WHEN cumplidas::numeric / programadas >= 0.80 THEN ROUND(facturacion_mensual_clp * 0.20, 0)
            ELSE ROUND(facturacion_mensual_clp * 0.20, 0) END AS monto_riesgo_clp,
       (programadas > 0 AND cumplidas::numeric / programadas < 0.80) AS en_revision_continuidad
FROM base b;
GRANT SELECT ON v_enex_kpi_mensual TO authenticated;


-- ── 6. SEED faenas + instalaciones Centinela (del contrato) ──────────────────
INSERT INTO enex_faenas (codigo, nombre, cliente_minero, contrato_minero, operador, lineas, vigencia_hasta, facturacion_mensual_clp, pct_facturacion, orden)
VALUES
 ('CENTINELA','Centinela','Minera Centinela','N°4540007011','ENEX', ARRAY['combustible','lubricante'], '2028-11-30', 17270839, 60, 1),
 ('NCEN_DES','Nueva Centinela (DES)','Minera Centinela','N°4540008239','ESM', ARRAY['combustible'], '2028-08-31', 3047795, 11, 2),
 ('SPENCE','Spence','Minera Spence','VA_24_068','ESM', ARRAY['combustible'], '2027-04-30', 3000240, 10, 3),
 ('LB_COMB','Lomas Bayas — Combustibles','Lomas Bayas','VA_24_068','ESM', ARRAY['combustible'], '2027-07-31', 2500200, 9, 4),
 ('LB_LUB','Lomas Bayas — Lubricantes','Lomas Bayas','LB-AG-GAD-SCT-2791','ESM', ARRAY['lubricante'], '2030-10-30', 2833560, 10, 5)
ON CONFLICT (codigo) DO NOTHING;

-- Instalaciones Centinela (las del contrato; el resto se completa en la app / Excel)
DO $$
DECLARE v_cen UUID;
BEGIN
    SELECT id INTO v_cen FROM enex_faenas WHERE codigo='CENTINELA';
    IF v_cen IS NOT NULL AND NOT EXISTS (SELECT 1 FROM enex_instalaciones WHERE faena_id=v_cen) THEN
        INSERT INTO enex_instalaciones (faena_id, nombre, tipo, linea, orden) VALUES
         (v_cen,'EESS Muelle','eess','combustible',1),
         (v_cen,'EESS Sulfuro','eess','combustible',2),
         (v_cen,'EESS Óxido','eess','combustible',3),
         (v_cen,'EESS Encuentro','eess','combustible',4),
         (v_cen,'Petrolera Óxido','petrolera','combustible',5),
         (v_cen,'Semimóvil 1','semimovil','combustible',6),
         (v_cen,'Semimóvil 2','semimovil','combustible',7),
         (v_cen,'Semimóvil Esperanza Sur','semimovil','combustible',8),
         (v_cen,'Semimóvil Sulfuros 3','semimovil','combustible',9),
         (v_cen,'Semimóvil Encuentro','semimovil','combustible',10),
         (v_cen,'Truck Shop Óxido','truck_shop','lubricante',11),
         (v_cen,'Truck Shop Sulfuros','truck_shop','lubricante',12),
         (v_cen,'Truck Shop Esperanza Sur','truck_shop','lubricante',13);
    END IF;
END $$;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tablas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.tables
        WHERE table_name IN ('enex_faenas','enex_instalaciones','enex_programaciones','enex_ejecuciones')),
    'faenas', (SELECT COUNT(*) FROM enex_faenas),
    'instalaciones_cen', (SELECT COUNT(*) FROM enex_instalaciones),
    'vistas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.views
        WHERE table_name IN ('v_enex_panel_mensual','v_enex_kpi_mensual')),
    'rpcs', (SELECT COUNT(*) FROM pg_proc WHERE proname LIKE 'rpc_enex_%')
) AS resultado;

NOTIFY pgrst, 'reload schema';
