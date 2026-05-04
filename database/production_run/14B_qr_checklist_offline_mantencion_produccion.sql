-- ============================================================================
-- 14B_qr_checklist_offline_mantencion_produccion.sql
-- ----------------------------------------------------------------------------
-- Modulo QR Checklist offline-first + Mantencion preventiva/correctiva.
-- COMPLEMENTA al 14_optional_mig52_blockA_qr_publico_produccion.sql (no lo
-- reemplaza). El 14 expone ficha publica read-only; este 14B agrega el flujo
-- operacional (checklist publico, alertas tempranas, mantenciones, sync offline).
--
-- DEPENDENCIAS PREVIAS:
--   - mig 55, 56, 57 aplicadas (pasos 04, 07, 10).
--   - usuarios_perfil + fn_user_rol() existentes.
--   - Tablas core: activos, modelos, marcas, ordenes_trabajo, contratos.
--
-- IDEMPOTENCIA:
--   - Todas las tablas con CREATE TABLE IF NOT EXISTS.
--   - Todas las funciones con CREATE OR REPLACE.
--   - Seeds con ON CONFLICT DO NOTHING (codigo UNIQUE).
--
-- COBERTURA:
--   - El sistema asigna checklist a TODOS los activos (fecha_baja IS NULL)
--     mediante resolucion jerarquica:
--       1) activo especifico  2) modelo  3) marca  4) tipo_activo
--       5) familia_operacional  6) universal (fallback)
--   - Vista v_qr_checklist_cobertura_activos verifica cobertura 100%.
-- ============================================================================


-- ── 0. Precheck de dependencias ─────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP — tabla activos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='modelos') THEN
        RAISE EXCEPTION 'STOP — tabla modelos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='ordenes_trabajo') THEN
        RAISE EXCEPTION 'STOP — tabla ordenes_trabajo no existe.';
    END IF;
    IF to_regprocedure('public.fn_user_rol()') IS NULL THEN
        RAISE EXCEPTION 'STOP — fn_user_rol() no existe (ejecutar mig 31 / hotfix 02A).';
    END IF;
END $$;


-- ── 1. Helper functions ─────────────────────────────────────────────

-- 1.1 Familia operacional derivada del tipo_activo
CREATE OR REPLACE FUNCTION fn_qr_familia_operacional(p_tipo tipo_activo_enum)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_tipo
        WHEN 'camion_cisterna'        THEN 'transporte_combustible'
        WHEN 'lubrimovil'             THEN 'transporte_combustible'
        WHEN 'camion'                 THEN 'transporte_pesado'
        WHEN 'camioneta'              THEN 'liviano'
        WHEN 'equipo_menor'           THEN 'soporte_operacional'
        WHEN 'punto_fijo'             THEN 'infraestructura_combustible'
        WHEN 'punto_movil'            THEN 'infraestructura_combustible'
        WHEN 'surtidor'               THEN 'infraestructura_combustible'
        WHEN 'dispensador'            THEN 'infraestructura_combustible'
        WHEN 'estanque'               THEN 'infraestructura_combustible'
        WHEN 'bomba'                  THEN 'infraestructura_combustible'
        WHEN 'manguera'               THEN 'infraestructura_combustible'
        WHEN 'equipo_bombeo'          THEN 'infraestructura_combustible'
        WHEN 'pistola_captura'        THEN 'infraestructura_combustible'
        WHEN 'herramienta_critica'    THEN 'herramienta'
        ELSE                               'general'
    END;
$$;

-- 1.2 Verifica si el rol del caller pertenece a mantencion/admin
CREATE OR REPLACE FUNCTION fn_qr_es_rol_mantencion()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_user_rol() IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'supervisor','planificador','tecnico_mantenimiento','auditor'
    );
$$;
GRANT EXECUTE ON FUNCTION fn_qr_familia_operacional(tipo_activo_enum) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_qr_es_rol_mantencion() TO authenticated;


-- ── 2. Tablas ───────────────────────────────────────────────────────

-- 2.1 Templates
CREATE TABLE IF NOT EXISTS qr_checklist_templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(60) UNIQUE NOT NULL,
    nombre      VARCHAR(200) NOT NULL,
    descripcion TEXT,
    es_universal BOOLEAN NOT NULL DEFAULT false,
    activo      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qr_tpl_activo ON qr_checklist_templates (activo);
-- Solo puede haber un universal activo
CREATE UNIQUE INDEX IF NOT EXISTS uq_qr_tpl_universal_activo
    ON qr_checklist_templates (es_universal) WHERE es_universal = true AND activo = true;

-- 2.2 Items del template
CREATE TABLE IF NOT EXISTS qr_checklist_template_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id         UUID NOT NULL REFERENCES qr_checklist_templates(id) ON DELETE CASCADE,
    seccion             VARCHAR(60) NOT NULL,
    orden               INT NOT NULL,
    codigo_item         VARCHAR(60) NOT NULL,
    descripcion         TEXT NOT NULL,
    tipo_respuesta      VARCHAR(20) NOT NULL DEFAULT 'ok_obs_falla'
                        CHECK (tipo_respuesta IN ('ok_obs_falla','si_no','numerico','texto')),
    criticidad_si_falla VARCHAR(10)
                        CHECK (criticidad_si_falla IN ('amarillo','naranja','rojo')),
    requiere_foto       BOOLEAN NOT NULL DEFAULT false,
    obligatorio         BOOLEAN NOT NULL DEFAULT true,
    valor_min           NUMERIC(14,4),
    valor_max           NUMERIC(14,4),
    unidad              VARCHAR(20),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_qr_tpl_item UNIQUE (template_id, codigo_item)
);
CREATE INDEX IF NOT EXISTS idx_qr_tpl_items_template ON qr_checklist_template_items (template_id, orden);

-- 2.3 Asignaciones jerarquicas
CREATE TABLE IF NOT EXISTS qr_checklist_template_asignaciones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id         UUID NOT NULL REFERENCES qr_checklist_templates(id) ON DELETE CASCADE,
    activo_id           UUID REFERENCES activos(id),
    marca_id            UUID REFERENCES marcas(id),
    modelo_id           UUID REFERENCES modelos(id),
    tipo_activo         tipo_activo_enum,
    familia_operacional VARCHAR(50),
    prioridad           INT NOT NULL DEFAULT 100,
    activo              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_qr_asig_un_solo_nivel CHECK (
        (CASE WHEN activo_id IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN modelo_id IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN marca_id  IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN tipo_activo IS NOT NULL THEN 1 ELSE 0 END
       + CASE WHEN familia_operacional IS NOT NULL THEN 1 ELSE 0 END) <= 1
    )
);
CREATE INDEX IF NOT EXISTS idx_qr_asig_activo  ON qr_checklist_template_asignaciones (activo_id) WHERE activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_asig_modelo  ON qr_checklist_template_asignaciones (modelo_id) WHERE modelo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_asig_marca   ON qr_checklist_template_asignaciones (marca_id)  WHERE marca_id  IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_asig_tipo    ON qr_checklist_template_asignaciones (tipo_activo) WHERE tipo_activo IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_asig_familia ON qr_checklist_template_asignaciones (familia_operacional) WHERE familia_operacional IS NOT NULL;

-- 2.4 Respuestas (idempotencia offline via cliente_uuid)
CREATE TABLE IF NOT EXISTS qr_checklist_respuestas (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_uuid             UUID UNIQUE NOT NULL,
    activo_id                UUID NOT NULL REFERENCES activos(id),
    template_id              UUID NOT NULL REFERENCES qr_checklist_templates(id),
    operador_nombre          VARCHAR(200),
    operador_telefono        VARCHAR(40),
    operador_email           VARCHAR(200),
    operador_empresa         VARCHAR(200),
    kilometraje_reportado    NUMERIC(12,1),
    horometro_reportado      NUMERIC(12,1),
    semaforo                 VARCHAR(10) NOT NULL DEFAULT 'verde'
                             CHECK (semaforo IN ('verde','amarillo','naranja','rojo')),
    items_falla_count        INT NOT NULL DEFAULT 0,
    items_observacion_count  INT NOT NULL DEFAULT 0,
    observacion_general      TEXT,
    scan_lat                 NUMERIC(10,7),
    scan_lng                 NUMERIC(10,7),
    ip_address               INET,
    user_agent               TEXT,
    created_offline_at       TIMESTAMPTZ,
    sincronizado_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qr_resp_activo_fecha ON qr_checklist_respuestas (activo_id, sincronizado_at DESC);
CREATE INDEX IF NOT EXISTS idx_qr_resp_semaforo     ON qr_checklist_respuestas (semaforo);

-- 2.5 Items de respuesta
CREATE TABLE IF NOT EXISTS qr_checklist_respuesta_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    respuesta_id        UUID NOT NULL REFERENCES qr_checklist_respuestas(id) ON DELETE CASCADE,
    template_item_id    UUID REFERENCES qr_checklist_template_items(id),
    seccion             VARCHAR(60) NOT NULL,
    orden               INT NOT NULL,
    codigo_item         VARCHAR(60) NOT NULL,
    descripcion         TEXT,
    respuesta_tipo      VARCHAR(20) NOT NULL,
    respuesta_valor     TEXT,
    es_falla            BOOLEAN NOT NULL DEFAULT false,
    es_observacion      BOOLEAN NOT NULL DEFAULT false,
    motivo              TEXT,
    foto_url            TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qr_resp_items_resp ON qr_checklist_respuesta_items (respuesta_id);
CREATE INDEX IF NOT EXISTS idx_qr_resp_items_falla ON qr_checklist_respuesta_items (template_item_id) WHERE es_falla = true;

-- 2.6 Alertas tempranas
CREATE TABLE IF NOT EXISTS alertas_tempranas (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id           UUID NOT NULL REFERENCES activos(id),
    respuesta_id        UUID REFERENCES qr_checklist_respuestas(id),
    template_item_id    UUID REFERENCES qr_checklist_template_items(id),
    codigo_alerta       VARCHAR(60) NOT NULL,
    descripcion         TEXT NOT NULL,
    semaforo            VARCHAR(10) NOT NULL
                        CHECK (semaforo IN ('amarillo','naranja','rojo')),
    estado              VARCHAR(20) NOT NULL DEFAULT 'abierta'
                        CHECK (estado IN ('abierta','en_seguimiento','cerrada','descartada')),
    repeticiones_7d     INT NOT NULL DEFAULT 1,
    ot_id               UUID REFERENCES ordenes_trabajo(id),
    accion_tomada       TEXT,
    cerrada_por         UUID REFERENCES usuarios_perfil(id),
    cerrada_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alertas_temp_activo  ON alertas_tempranas (activo_id, estado, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alertas_temp_estado  ON alertas_tempranas (estado, semaforo);

-- 2.7 Mantenciones registro (FK opcional a OT)
CREATE TABLE IF NOT EXISTS mantenciones_registro (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id           UUID NOT NULL REFERENCES activos(id),
    ot_id               UUID REFERENCES ordenes_trabajo(id),
    tipo                VARCHAR(20) NOT NULL
                        CHECK (tipo IN ('preventiva','correctiva','inspeccion','lubricacion','otro')),
    fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
    kilometraje_al_momento NUMERIC(12,1),
    horometro_al_momento   NUMERIC(12,1),
    descripcion         TEXT NOT NULL,
    repuestos_usados    JSONB NOT NULL DEFAULT '[]',
    costo_total         NUMERIC(14,2),
    observaciones       TEXT,
    registrada_por      UUID REFERENCES usuarios_perfil(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mant_reg_activo ON mantenciones_registro (activo_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_mant_reg_ot     ON mantenciones_registro (ot_id) WHERE ot_id IS NOT NULL;

-- 2.8 Archivos evidencia (genericos por contexto)
CREATE TABLE IF NOT EXISTS archivos_evidencia (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contexto        VARCHAR(30) NOT NULL
                    CHECK (contexto IN ('qr_checklist','mantencion','alerta','otro')),
    contexto_id     UUID NOT NULL,
    tipo            VARCHAR(20) NOT NULL
                    CHECK (tipo IN ('foto','video','firma','documento')),
    archivo_url     TEXT NOT NULL,
    tamano_bytes    BIGINT,
    mime_type       VARCHAR(80),
    descripcion     TEXT,
    created_by      UUID REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_arch_evidencia_ctx ON archivos_evidencia (contexto, contexto_id);

-- 2.9 Sync queue (audit log server-side de eventos sincronizados desde clientes offline)
CREATE TABLE IF NOT EXISTS sync_queue_offline (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_uuid    UUID NOT NULL,
    evento_tipo     VARCHAR(40) NOT NULL,
    payload_resumen JSONB,
    procesado_at    TIMESTAMPTZ,
    error           TEXT,
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sync_queue_cliente ON sync_queue_offline (cliente_uuid);
CREATE INDEX IF NOT EXISTS idx_sync_queue_fecha   ON sync_queue_offline (created_at DESC);


-- ── 3. RLS policies ─────────────────────────────────────────────────

ALTER TABLE qr_checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_checklist_template_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_checklist_template_asignaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_checklist_respuestas ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_checklist_respuesta_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE alertas_tempranas ENABLE ROW LEVEL SECURITY;
ALTER TABLE mantenciones_registro ENABLE ROW LEVEL SECURITY;
ALTER TABLE archivos_evidencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_queue_offline ENABLE ROW LEVEL SECURITY;

-- Templates + items + asignaciones: SELECT abierto a anon (necesario para RPC publica).
DROP POLICY IF EXISTS pol_qr_tpl_select ON qr_checklist_templates;
CREATE POLICY pol_qr_tpl_select ON qr_checklist_templates FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS pol_qr_tpl_modif ON qr_checklist_templates;
CREATE POLICY pol_qr_tpl_modif ON qr_checklist_templates FOR ALL TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());

DROP POLICY IF EXISTS pol_qr_tpl_items_select ON qr_checklist_template_items;
CREATE POLICY pol_qr_tpl_items_select ON qr_checklist_template_items FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS pol_qr_tpl_items_modif ON qr_checklist_template_items;
CREATE POLICY pol_qr_tpl_items_modif ON qr_checklist_template_items FOR ALL TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());

DROP POLICY IF EXISTS pol_qr_asig_select ON qr_checklist_template_asignaciones;
CREATE POLICY pol_qr_asig_select ON qr_checklist_template_asignaciones FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS pol_qr_asig_modif ON qr_checklist_template_asignaciones;
CREATE POLICY pol_qr_asig_modif ON qr_checklist_template_asignaciones FOR ALL TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());

-- Respuestas: anon NO puede SELECT. INSERT solo via RPC SECURITY DEFINER.
DROP POLICY IF EXISTS pol_qr_resp_select ON qr_checklist_respuestas;
CREATE POLICY pol_qr_resp_select ON qr_checklist_respuestas FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());

DROP POLICY IF EXISTS pol_qr_resp_items_select ON qr_checklist_respuesta_items;
CREATE POLICY pol_qr_resp_items_select ON qr_checklist_respuesta_items FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());

-- Alertas tempranas: solo mantencion/admin
DROP POLICY IF EXISTS pol_alertas_temp_select ON alertas_tempranas;
CREATE POLICY pol_alertas_temp_select ON alertas_tempranas FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());
DROP POLICY IF EXISTS pol_alertas_temp_update ON alertas_tempranas;
CREATE POLICY pol_alertas_temp_update ON alertas_tempranas FOR UPDATE TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());

-- Mantenciones registro: solo mantencion/admin
DROP POLICY IF EXISTS pol_mant_reg_select ON mantenciones_registro;
CREATE POLICY pol_mant_reg_select ON mantenciones_registro FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());

-- Archivos evidencia: lectura para mantencion/admin (excepto contexto qr_checklist
-- cuya foto_url ya esta embebida en respuesta y se lee via RPC autenticada)
DROP POLICY IF EXISTS pol_arch_evidencia_select ON archivos_evidencia;
CREATE POLICY pol_arch_evidencia_select ON archivos_evidencia FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());

-- Sync queue: solo administrador
DROP POLICY IF EXISTS pol_sync_queue_admin ON sync_queue_offline;
CREATE POLICY pol_sync_queue_admin ON sync_queue_offline FOR ALL TO authenticated
    USING (fn_user_rol() = 'administrador') WITH CHECK (fn_user_rol() = 'administrador');


-- ── 4. Resolver de template (cascada jerarquica) ────────────────────
CREATE OR REPLACE FUNCTION fn_qr_resolver_template_para_activo(p_activo_id UUID)
RETURNS TABLE (template_id UUID, nivel_asignacion TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_modelo_id UUID;
    v_marca_id  UUID;
    v_tipo      tipo_activo_enum;
    v_familia   TEXT;
BEGIN
    SELECT a.modelo_id, m.marca_id, a.tipo, fn_qr_familia_operacional(a.tipo)
      INTO v_modelo_id, v_marca_id, v_tipo, v_familia
      FROM activos a
      LEFT JOIN modelos m ON m.id = a.modelo_id
     WHERE a.id = p_activo_id;

    IF v_tipo IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH candidatos AS (
        SELECT 1 AS nivel_orden, 'activo'::TEXT    AS nivel, ta.template_id, ta.prioridad
          FROM qr_checklist_template_asignaciones ta
          JOIN qr_checklist_templates t ON t.id = ta.template_id
         WHERE ta.activo = true AND t.activo = true AND ta.activo_id = p_activo_id
        UNION ALL
        SELECT 2, 'modelo'::TEXT, ta.template_id, ta.prioridad
          FROM qr_checklist_template_asignaciones ta
          JOIN qr_checklist_templates t ON t.id = ta.template_id
         WHERE ta.activo = true AND t.activo = true AND ta.modelo_id = v_modelo_id
        UNION ALL
        SELECT 3, 'marca'::TEXT, ta.template_id, ta.prioridad
          FROM qr_checklist_template_asignaciones ta
          JOIN qr_checklist_templates t ON t.id = ta.template_id
         WHERE ta.activo = true AND t.activo = true AND ta.marca_id = v_marca_id
        UNION ALL
        SELECT 4, 'tipo'::TEXT, ta.template_id, ta.prioridad
          FROM qr_checklist_template_asignaciones ta
          JOIN qr_checklist_templates t ON t.id = ta.template_id
         WHERE ta.activo = true AND t.activo = true AND ta.tipo_activo = v_tipo
        UNION ALL
        SELECT 5, 'familia'::TEXT, ta.template_id, ta.prioridad
          FROM qr_checklist_template_asignaciones ta
          JOIN qr_checklist_templates t ON t.id = ta.template_id
         WHERE ta.activo = true AND t.activo = true AND ta.familia_operacional = v_familia
        UNION ALL
        SELECT 6, 'universal'::TEXT, t.id, 9999
          FROM qr_checklist_templates t
         WHERE t.activo = true AND t.es_universal = true
    )
    SELECT c.template_id, c.nivel
      FROM candidatos c
     ORDER BY c.nivel_orden ASC, c.prioridad ASC NULLS LAST
     LIMIT 1;
END; $$;
GRANT EXECUTE ON FUNCTION fn_qr_resolver_template_para_activo(UUID) TO anon, authenticated;


-- ── 5. Vista cobertura ──────────────────────────────────────────────
CREATE OR REPLACE VIEW v_qr_checklist_cobertura_activos AS
SELECT
    a.id AS activo_id,
    a.codigo,
    a.nombre,
    mk.nombre AS marca,
    m.nombre  AS modelo,
    a.tipo,
    fn_qr_familia_operacional(a.tipo) AS familia_operacional,
    res.template_id   AS template_resuelto,
    res.nivel_asignacion,
    (res.template_id IS NOT NULL) AS tiene_checklist
FROM activos a
LEFT JOIN modelos m ON m.id = a.modelo_id
LEFT JOIN marcas mk ON mk.id = m.marca_id
LEFT JOIN LATERAL fn_qr_resolver_template_para_activo(a.id) res ON true
WHERE a.fecha_baja IS NULL;
GRANT SELECT ON v_qr_checklist_cobertura_activos TO authenticated;


-- ── 6. Funcion evaluadora de semaforo ───────────────────────────────

-- Helper "GREATEST" para semaforos (rojo > naranja > amarillo > verde)
CREATE OR REPLACE FUNCTION GREATEST_SEM(a TEXT, b TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
      WHEN a = 'rojo'     OR b = 'rojo'     THEN 'rojo'
      WHEN a = 'naranja'  OR b = 'naranja'  THEN 'naranja'
      WHEN a = 'amarillo' OR b = 'amarillo' THEN 'amarillo'
      ELSE 'verde'
    END;
$$;

CREATE OR REPLACE FUNCTION fn_qr_evaluar_semaforo_respuesta(p_respuesta_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_activo_id UUID;
    v_max_sev   TEXT := 'verde';
    v_item RECORD;
    v_repeticiones INT;
BEGIN
    SELECT activo_id INTO v_activo_id FROM qr_checklist_respuestas WHERE id = p_respuesta_id;
    IF v_activo_id IS NULL THEN RETURN 'verde'; END IF;

    FOR v_item IN
        SELECT ri.template_item_id, ri.es_falla, ri.es_observacion,
               ti.criticidad_si_falla, ti.codigo_item
          FROM qr_checklist_respuesta_items ri
          LEFT JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
         WHERE ri.respuesta_id = p_respuesta_id
    LOOP
        IF v_item.es_falla AND v_item.criticidad_si_falla IS NOT NULL THEN
            -- Repetidos en 7 dias?
            SELECT COUNT(*) INTO v_repeticiones
              FROM qr_checklist_respuesta_items ri2
              JOIN qr_checklist_respuestas r2 ON r2.id = ri2.respuesta_id
             WHERE r2.activo_id = v_activo_id
               AND ri2.template_item_id = v_item.template_item_id
               AND ri2.es_falla = true
               AND r2.sincronizado_at >= NOW() - INTERVAL '7 days'
               AND r2.id <> p_respuesta_id;

            IF v_repeticiones >= 1 AND v_item.criticidad_si_falla = 'amarillo' THEN
                v_max_sev := GREATEST_SEM(v_max_sev, 'naranja');
            ELSE
                v_max_sev := GREATEST_SEM(v_max_sev, v_item.criticidad_si_falla);
            END IF;
        ELSIF v_item.es_observacion THEN
            v_max_sev := GREATEST_SEM(v_max_sev, 'amarillo');
        END IF;
    END LOOP;

    RETURN v_max_sev;
END; $$;


-- ── 7. RPC publicas (anon + authenticated) ──────────────────────────

-- 7.1 Obtener checklist por activo (resuelve template aplicable)
CREATE OR REPLACE FUNCTION rpc_obtener_checklist_publico_por_qr(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_template_id UUID;
    v_nivel       TEXT;
    v_activo      RECORD;
    v_template    RECORD;
    v_items       JSONB;
BEGIN
    -- Verificar que el activo exista y este activo (no dado de baja)
    SELECT a.id, a.codigo, a.nombre, a.tipo, a.criticidad,
           a.kilometraje_actual, a.horas_uso_actual,
           m.nombre AS modelo_nombre, mk.nombre AS marca_nombre
      INTO v_activo
      FROM activos a
      LEFT JOIN modelos m ON m.id = a.modelo_id
      LEFT JOIN marcas mk ON mk.id = m.marca_id
     WHERE a.id = p_activo_id AND a.fecha_baja IS NULL;
    IF v_activo.id IS NULL THEN
        RETURN jsonb_build_object('error','activo_no_encontrado_o_baja');
    END IF;

    SELECT template_id, nivel_asignacion
      INTO v_template_id, v_nivel
      FROM fn_qr_resolver_template_para_activo(p_activo_id);
    IF v_template_id IS NULL THEN
        RETURN jsonb_build_object('error','sin_checklist_ni_universal');
    END IF;

    SELECT id, codigo, nombre, descripcion, es_universal
      INTO v_template
      FROM qr_checklist_templates WHERE id = v_template_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', i.id,
        'seccion', i.seccion,
        'orden', i.orden,
        'codigo_item', i.codigo_item,
        'descripcion', i.descripcion,
        'tipo_respuesta', i.tipo_respuesta,
        'criticidad_si_falla', i.criticidad_si_falla,
        'requiere_foto', i.requiere_foto,
        'obligatorio', i.obligatorio,
        'valor_min', i.valor_min,
        'valor_max', i.valor_max,
        'unidad', i.unidad
    ) ORDER BY i.seccion, i.orden), '[]'::jsonb)
      INTO v_items
      FROM qr_checklist_template_items i WHERE i.template_id = v_template_id;

    RETURN jsonb_build_object(
        'activo', jsonb_build_object(
            'id', v_activo.id, 'codigo', v_activo.codigo, 'nombre', v_activo.nombre,
            'tipo', v_activo.tipo, 'criticidad', v_activo.criticidad,
            'kilometraje_actual', v_activo.kilometraje_actual,
            'horometro_actual', v_activo.horas_uso_actual,
            'modelo', v_activo.modelo_nombre, 'marca', v_activo.marca_nombre
        ),
        'template', jsonb_build_object(
            'id', v_template.id, 'codigo', v_template.codigo, 'nombre', v_template.nombre,
            'descripcion', v_template.descripcion, 'es_universal', v_template.es_universal,
            'nivel_asignacion', v_nivel
        ),
        'items', v_items
    );
END; $$;
GRANT EXECUTE ON FUNCTION rpc_obtener_checklist_publico_por_qr(UUID) TO anon, authenticated;


-- 7.2 Guardar checklist publico (idempotente por cliente_uuid)
CREATE OR REPLACE FUNCTION rpc_guardar_checklist_publico(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_cliente_uuid UUID;
    v_activo_id    UUID;
    v_template_id  UUID;
    v_resp_id      UUID;
    v_existente    UUID;
    v_item         JSONB;
    v_items_falla  INT := 0;
    v_items_obs    INT := 0;
    v_semaforo     TEXT;
    v_alertas_gen  INT;
BEGIN
    v_cliente_uuid := (p_payload->>'cliente_uuid')::UUID;
    v_activo_id    := (p_payload->>'activo_id')::UUID;
    v_template_id  := (p_payload->>'template_id')::UUID;

    IF v_cliente_uuid IS NULL OR v_activo_id IS NULL OR v_template_id IS NULL THEN
        RAISE EXCEPTION 'payload invalido: cliente_uuid/activo_id/template_id obligatorios';
    END IF;

    -- Idempotencia
    SELECT id INTO v_existente FROM qr_checklist_respuestas WHERE cliente_uuid = v_cliente_uuid;
    IF v_existente IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'ya_existia', true, 'respuesta_id', v_existente);
    END IF;

    -- Validar activo + template
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = v_activo_id AND fecha_baja IS NULL) THEN
        RAISE EXCEPTION 'activo no encontrado o dado de baja';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM qr_checklist_templates WHERE id = v_template_id AND activo = true) THEN
        RAISE EXCEPTION 'template no encontrado o inactivo';
    END IF;

    INSERT INTO qr_checklist_respuestas (
        cliente_uuid, activo_id, template_id,
        operador_nombre, operador_telefono, operador_email, operador_empresa,
        kilometraje_reportado, horometro_reportado,
        observacion_general, scan_lat, scan_lng, created_offline_at
    ) VALUES (
        v_cliente_uuid, v_activo_id, v_template_id,
        NULLIF(p_payload->>'operador_nombre',''),
        NULLIF(p_payload->>'operador_telefono',''),
        NULLIF(p_payload->>'operador_email',''),
        NULLIF(p_payload->>'operador_empresa',''),
        NULLIF(p_payload->>'kilometraje_reportado','')::NUMERIC,
        NULLIF(p_payload->>'horometro_reportado','')::NUMERIC,
        NULLIF(p_payload->>'observacion_general',''),
        NULLIF(p_payload->>'scan_lat','')::NUMERIC,
        NULLIF(p_payload->>'scan_lng','')::NUMERIC,
        NULLIF(p_payload->>'created_offline_at','')::TIMESTAMPTZ
    ) RETURNING id INTO v_resp_id;

    -- Items
    IF jsonb_typeof(p_payload->'items') = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'items') LOOP
            INSERT INTO qr_checklist_respuesta_items (
                respuesta_id, template_item_id, seccion, orden, codigo_item, descripcion,
                respuesta_tipo, respuesta_valor, es_falla, es_observacion, motivo, foto_url
            ) VALUES (
                v_resp_id,
                NULLIF(v_item->>'template_item_id','')::UUID,
                COALESCE(v_item->>'seccion','SinSeccion'),
                COALESCE((v_item->>'orden')::INT, 0),
                COALESCE(v_item->>'codigo_item','sin_codigo'),
                v_item->>'descripcion',
                COALESCE(v_item->>'respuesta_tipo','ok_obs_falla'),
                v_item->>'respuesta_valor',
                COALESCE((v_item->>'es_falla')::BOOLEAN, false),
                COALESCE((v_item->>'es_observacion')::BOOLEAN, false),
                v_item->>'motivo',
                v_item->>'foto_url'
            );
            IF COALESCE((v_item->>'es_falla')::BOOLEAN, false) THEN v_items_falla := v_items_falla + 1; END IF;
            IF COALESCE((v_item->>'es_observacion')::BOOLEAN, false) THEN v_items_obs := v_items_obs + 1; END IF;
        END LOOP;
    END IF;

    UPDATE qr_checklist_respuestas
       SET items_falla_count = v_items_falla,
           items_observacion_count = v_items_obs
     WHERE id = v_resp_id;

    -- Calcular semaforo + generar alertas
    v_semaforo := fn_qr_evaluar_semaforo_respuesta(v_resp_id);
    UPDATE qr_checklist_respuestas SET semaforo = v_semaforo WHERE id = v_resp_id;
    v_alertas_gen := (rpc_generar_alerta_temprana(v_resp_id)->>'alertas_creadas')::INT;

    -- Audit log de sync
    INSERT INTO sync_queue_offline (cliente_uuid, evento_tipo, payload_resumen, procesado_at)
    VALUES (v_cliente_uuid, 'checklist_guardado',
            jsonb_build_object('respuesta_id', v_resp_id, 'semaforo', v_semaforo,
                               'items_falla', v_items_falla, 'alertas_generadas', v_alertas_gen),
            NOW());

    RETURN jsonb_build_object(
        'success', true, 'ya_existia', false, 'respuesta_id', v_resp_id,
        'semaforo', v_semaforo, 'items_falla', v_items_falla,
        'items_observacion', v_items_obs, 'alertas_generadas', v_alertas_gen
    );
END; $$;
GRANT EXECUTE ON FUNCTION rpc_guardar_checklist_publico(jsonb) TO anon, authenticated;


-- 7.3 Generar alertas tempranas a partir de checklist
CREATE OR REPLACE FUNCTION rpc_generar_alerta_temprana(p_checklist_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_resp RECORD;
    v_item RECORD;
    v_repeticiones INT;
    v_semaforo_alerta TEXT;
    v_creadas INT := 0;
BEGIN
    SELECT id, activo_id INTO v_resp FROM qr_checklist_respuestas WHERE id = p_checklist_id;
    IF v_resp.id IS NULL THEN
        RETURN jsonb_build_object('error','checklist_no_encontrado');
    END IF;

    FOR v_item IN
        SELECT ri.id AS resp_item_id, ri.template_item_id, ri.codigo_item, ri.descripcion,
               ri.motivo, ti.criticidad_si_falla
          FROM qr_checklist_respuesta_items ri
          LEFT JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
         WHERE ri.respuesta_id = p_checklist_id
           AND ri.es_falla = true
    LOOP
        IF v_item.criticidad_si_falla IS NULL THEN CONTINUE; END IF;

        SELECT COUNT(*) INTO v_repeticiones
          FROM qr_checklist_respuesta_items ri2
          JOIN qr_checklist_respuestas r2 ON r2.id = ri2.respuesta_id
         WHERE r2.activo_id = v_resp.activo_id
           AND ri2.template_item_id = v_item.template_item_id
           AND ri2.es_falla = true
           AND r2.sincronizado_at >= NOW() - INTERVAL '7 days';

        v_semaforo_alerta := v_item.criticidad_si_falla;
        IF v_repeticiones >= 2 AND v_semaforo_alerta = 'amarillo' THEN
            v_semaforo_alerta := 'naranja';
        END IF;

        INSERT INTO alertas_tempranas (
            activo_id, respuesta_id, template_item_id, codigo_alerta,
            descripcion, semaforo, repeticiones_7d
        ) VALUES (
            v_resp.activo_id, p_checklist_id, v_item.template_item_id,
            COALESCE(v_item.codigo_item, 'item_falla'),
            COALESCE(v_item.descripcion, '') ||
              CASE WHEN v_item.motivo IS NOT NULL AND v_item.motivo <> ''
                   THEN ' | ' || v_item.motivo ELSE '' END,
            v_semaforo_alerta, v_repeticiones
        );
        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'alertas_creadas', v_creadas);
END; $$;
GRANT EXECUTE ON FUNCTION rpc_generar_alerta_temprana(UUID) TO anon, authenticated;


-- ── 8. RPC autenticadas ─────────────────────────────────────────────

-- 8.1 Historial mantencion del activo
CREATE OR REPLACE FUNCTION rpc_historial_mantencion_activo(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_checklists JSONB; v_mant JSONB; v_alertas JSONB; v_ots JSONB;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_qr_es_rol_mantencion() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', r.id, 'fecha', r.sincronizado_at, 'semaforo', r.semaforo,
        'items_falla', r.items_falla_count, 'items_observacion', r.items_observacion_count,
        'operador', r.operador_nombre, 'observacion', r.observacion_general
    ) ORDER BY r.sincronizado_at DESC), '[]'::jsonb)
      INTO v_checklists
      FROM (SELECT * FROM qr_checklist_respuestas WHERE activo_id = p_activo_id
             ORDER BY sincronizado_at DESC LIMIT 50) r;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'fecha', m.fecha, 'tipo', m.tipo,
        'descripcion', m.descripcion, 'costo_total', m.costo_total,
        'kilometraje', m.kilometraje_al_momento, 'horometro', m.horometro_al_momento,
        'ot_id', m.ot_id, 'repuestos_usados', m.repuestos_usados
    ) ORDER BY m.fecha DESC), '[]'::jsonb)
      INTO v_mant
      FROM (SELECT * FROM mantenciones_registro WHERE activo_id = p_activo_id
             ORDER BY fecha DESC LIMIT 100) m;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a.id, 'codigo', a.codigo_alerta, 'descripcion', a.descripcion,
        'semaforo', a.semaforo, 'estado', a.estado,
        'created_at', a.created_at, 'repeticiones_7d', a.repeticiones_7d
    ) ORDER BY a.created_at DESC), '[]'::jsonb)
      INTO v_alertas
      FROM alertas_tempranas a WHERE a.activo_id = p_activo_id AND a.estado IN ('abierta','en_seguimiento');

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', o.id, 'folio', o.folio, 'tipo', o.tipo, 'estado', o.estado,
        'fecha_programada', o.fecha_programada, 'created_at', o.created_at
    ) ORDER BY o.created_at DESC), '[]'::jsonb)
      INTO v_ots
      FROM (SELECT * FROM ordenes_trabajo WHERE activo_id = p_activo_id
             ORDER BY created_at DESC LIMIT 30) o;

    RETURN jsonb_build_object(
        'activo_id', p_activo_id,
        'checklists_recientes', v_checklists,
        'mantenciones', v_mant,
        'alertas_abiertas', v_alertas,
        'ordenes_trabajo', v_ots
    );
END; $$;
GRANT EXECUTE ON FUNCTION rpc_historial_mantencion_activo(UUID) TO authenticated;


-- 8.2 Registrar mantencion preventiva
CREATE OR REPLACE FUNCTION rpc_registrar_mantencion_preventiva(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_activo_id UUID;
    v_id UUID;
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_qr_es_rol_mantencion() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;

    v_activo_id := (p_payload->>'activo_id')::UUID;
    IF v_activo_id IS NULL OR (p_payload->>'descripcion') IS NULL
       OR LENGTH(TRIM(p_payload->>'descripcion')) < 5 THEN
        RAISE EXCEPTION 'payload invalido: activo_id + descripcion (min 5 chars) obligatorios';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = v_activo_id AND fecha_baja IS NULL) THEN
        RAISE EXCEPTION 'activo no encontrado o dado de baja';
    END IF;

    INSERT INTO mantenciones_registro (
        activo_id, ot_id, tipo, fecha,
        kilometraje_al_momento, horometro_al_momento,
        descripcion, repuestos_usados, costo_total, observaciones, registrada_por
    ) VALUES (
        v_activo_id,
        NULLIF(p_payload->>'ot_id','')::UUID,
        COALESCE(p_payload->>'tipo','preventiva'),
        COALESCE(NULLIF(p_payload->>'fecha','')::DATE, CURRENT_DATE),
        NULLIF(p_payload->>'kilometraje_al_momento','')::NUMERIC,
        NULLIF(p_payload->>'horometro_al_momento','')::NUMERIC,
        TRIM(p_payload->>'descripcion'),
        COALESCE(p_payload->'repuestos_usados', '[]'::jsonb),
        NULLIF(p_payload->>'costo_total','')::NUMERIC,
        NULLIF(p_payload->>'observaciones',''),
        v_uid
    ) RETURNING id INTO v_id;

    -- Cerrar alertas resueltas si vienen en el payload
    IF jsonb_typeof(p_payload->'alertas_resueltas') = 'array' THEN
        UPDATE alertas_tempranas
           SET estado = 'cerrada', cerrada_at = NOW(),
               cerrada_por = v_uid,
               accion_tomada = 'Resuelta por mantencion ' || v_id::TEXT
         WHERE id IN (
            SELECT (jsonb_array_elements_text(p_payload->'alertas_resueltas'))::UUID
         ) AND activo_id = v_activo_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'mantencion_id', v_id);
END; $$;
GRANT EXECUTE ON FUNCTION rpc_registrar_mantencion_preventiva(jsonb) TO authenticated;


-- 8.3 Cerrar alerta temprana
CREATE OR REPLACE FUNCTION rpc_cerrar_alerta_temprana(p_alerta_id UUID, p_accion TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_qr_es_rol_mantencion() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF p_accion IS NULL OR LENGTH(TRIM(p_accion)) < 5 THEN
        RAISE EXCEPTION 'accion debe tener al menos 5 caracteres';
    END IF;

    UPDATE alertas_tempranas
       SET estado = 'cerrada', cerrada_at = NOW(), cerrada_por = v_uid,
           accion_tomada = TRIM(p_accion)
     WHERE id = p_alerta_id AND estado IN ('abierta','en_seguimiento');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'alerta no encontrada o ya cerrada';
    END IF;
    RETURN jsonb_build_object('success', true, 'alerta_id', p_alerta_id);
END; $$;
GRANT EXECUTE ON FUNCTION rpc_cerrar_alerta_temprana(UUID, TEXT) TO authenticated;


-- ── 9. SEED de templates (13 templates) ─────────────────────────────

INSERT INTO qr_checklist_templates (codigo, nombre, descripcion, es_universal, activo) VALUES
('CL_UNIVERSAL',         'Checklist Universal Inspeccion Diaria', 'Fallback aplicable a cualquier activo sin asignacion especifica.', true,  true),
('CL_CAMION_PESADO',     'Checklist Camion Pesado',                'Camiones de carga (no aljibe / no tolva especifica).',           false, true),
('CL_CAMION_ALJIBE',     'Checklist Camion Aljibe Combustible/Agua','Camion cisterna (combustible o agua).',                          false, true),
('CL_CAMION_TOLVA',      'Checklist Camion Tolva',                 'Camiones tolva.',                                                 false, true),
('CL_CAMION_CARRETERA',  'Checklist Tracto/Camion Carretera',      'Tractocamion o camion ruta carretera.',                          false, true),
('CL_CAMIONETA_LIVIANO', 'Checklist Camioneta/Liviano',            'Camionetas y vehiculos livianos.',                                false, true),
('CL_FURGON_TALLER',     'Checklist Furgon/Taller Movil',          'Furgones taller movil y lubrimoviles.',                           false, true),
('CL_GRUA_HORQUILLA',    'Checklist Grua Horquilla/Equipo Apoyo',  'Equipos menores de soporte operacional.',                         false, true),
('CL_MB_ACTROS_3336K',   'Checklist M.Benz Actros 3336K',          'Foco: transmision/sincronizadores, suspension, frenos, neumaticos.', false, true),
('CL_MB_ACTROS_3341',    'Checklist M.Benz Actros 3341',           'Foco: transmision, suspension, frenos, neumaticos.',              false, true),
('CL_MACK_GR64BX',       'Checklist Mack GR64BX',                  'Foco: suspension, paquete resortes, tren motriz, frenos.',        false, true),
('CL_SCANIA_P450B',      'Checklist Scania P450B',                 'Foco: preventiva, frenos, neumaticos, tablero/emisiones.',        false, true),
('CL_VOLVO_VM',          'Checklist Volvo VM',                     'Foco: frenos, PTO si aplica, neumaticos.',                        false, true),
('CL_TOYOTA_HILUX',      'Checklist Toyota Hilux/Livianos',        'Foco: seguridad, neumaticos, fluidos.',                           false, true)
ON CONFLICT (codigo) DO NOTHING;


-- 9.1 Items para templates (en lote via JSONB)
DO $$
DECLARE v_tpl_id UUID;
BEGIN
    -- ── UNIVERSAL ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_UNIVERSAL';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion', 1,'IDENT_OPERADOR','Nombre del operador / responsable','texto',NULL,false,true),
          ('Identificacion', 2,'IDENT_KM','Lectura odometro (km)','numerico',NULL,false,false),
          ('Identificacion', 3,'IDENT_HOROM','Lectura horometro','numerico',NULL,false,false),
          ('Motor/Fluidos',  4,'NIVEL_ACEITE','Nivel de aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos',  5,'NIVEL_REFRIG','Nivel de refrigerante','ok_obs_falla','amarillo',false,true),
          ('Motor/Fluidos',  6,'FUGAS_VISIBLES','Fugas visibles bajo el equipo','ok_obs_falla','rojo',true,true),
          ('Frenos',         7,'PEDAL_FRENO','Recorrido y firmeza pedal de freno','ok_obs_falla','rojo',false,true),
          ('Neumaticos',     8,'NEUM_ESTADO','Estado general de neumaticos (cortes, desgaste, presion)','ok_obs_falla','naranja',true,true),
          ('Suspension',     9,'SUSP_ESTADO','Suspension (golpes, ruidos, paquete resortes)','ok_obs_falla','amarillo',false,true),
          ('Seguridad',     10,'LUCES','Luces (alta/baja/freno/intermitentes)','ok_obs_falla','naranja',false,true),
          ('Seguridad',     11,'EXTINTOR','Extintor presente y vigente','si_no','rojo',false,true),
          ('Seguridad',     12,'CINTURON','Cinturones de seguridad operativos','ok_obs_falla','rojo',false,true),
          ('Seguridad',     13,'EQUIPO_SEGURO','Equipo seguro para operar','si_no','rojo',false,true),
          ('Observaciones', 14,'OBS_GRAL','Observacion general libre','texto',NULL,false,false),
          ('Observaciones', 15,'EVIDENCIA','Foto general del equipo','ok_obs_falla',NULL,true,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── CAMION ALJIBE (combustible/agua) ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_CAMION_ALJIBE';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion', 1,'IDENT_OPERADOR','Nombre operador','texto',NULL,false,true),
          ('Identificacion', 2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Identificacion', 3,'IDENT_HOROM','Horometro','numerico',NULL,false,false),
          ('Motor/Fluidos',  4,'NIVEL_ACEITE','Nivel aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos',  5,'NIVEL_REFRIG','Nivel refrigerante','ok_obs_falla','amarillo',false,true),
          ('Motor/Fluidos',  6,'FUGAS_BAJO','Fugas bajo cabina/motor','ok_obs_falla','rojo',true,true),
          ('Frenos',         7,'PEDAL_FRENO','Pedal de freno (recorrido)','ok_obs_falla','rojo',false,true),
          ('Frenos',         8,'PRESION_AIRE','Presion sistema aire (bar)','numerico','rojo',false,true),
          ('Frenos',         9,'FRENO_MOTOR','Funcionamiento freno motor','ok_obs_falla','naranja',false,true),
          ('Neumaticos',    10,'NEUM_DELANT','Neumaticos delanteros (12R22.5)','ok_obs_falla','naranja',true,true),
          ('Neumaticos',    11,'NEUM_TRAS','Neumaticos traseros (par/dual)','ok_obs_falla','naranja',true,true),
          ('Suspension',    12,'PAQ_RESORTES','Paquete de resortes (grietas/ruidos)','ok_obs_falla','naranja',true,true),
          ('Transmision',   13,'CAMBIOS','Cambios suaves / sincronizadores','ok_obs_falla','naranja',false,true),
          ('Transmision',   14,'EMBRAGUE','Embrague (recorrido, ruido)','ok_obs_falla','amarillo',false,true),
          ('Sistema Aljibe',15,'VALVULAS','Valvulas de descarga sin fugas','ok_obs_falla','rojo',true,true),
          ('Sistema Aljibe',16,'BOMBA','Bomba de transferencia','ok_obs_falla','naranja',false,true),
          ('Sistema Aljibe',17,'MANGUERAS','Mangueras (cortes/abrasion)','ok_obs_falla','rojo',true,true),
          ('Sistema Aljibe',18,'MEDIDOR','Lectura medidor totalizador','numerico',NULL,true,false),
          ('Seguridad',     19,'LUCES','Luces operativas','ok_obs_falla','naranja',false,true),
          ('Seguridad',     20,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',     21,'EQUIPO_SEGURO','Equipo seguro para operar','si_no','rojo',false,true),
          ('Observaciones', 22,'OBS_GRAL','Observaciones','texto',NULL,false,false),
          ('Observaciones', 23,'EVIDENCIA','Foto general','ok_obs_falla',NULL,true,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── CAMION PESADO ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_CAMION_PESADO';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion', 1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion', 2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos',  3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos',  4,'NIVEL_REFRIG','Refrigerante','ok_obs_falla','amarillo',false,true),
          ('Motor/Fluidos',  5,'FUGAS','Fugas visibles','ok_obs_falla','rojo',true,true),
          ('Frenos',         6,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',         7,'PRESION_AIRE','Presion aire (bar)','numerico','rojo',false,true),
          ('Neumaticos',     8,'NEUM_GRAL','Neumaticos (estado/presion)','ok_obs_falla','naranja',true,true),
          ('Suspension',     9,'PAQ_RESORTES','Paquete resortes','ok_obs_falla','naranja',true,true),
          ('Transmision',   10,'CAMBIOS','Cambios','ok_obs_falla','naranja',false,true),
          ('Seguridad',     11,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',     12,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',     13,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones', 14,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── CAMION TOLVA ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_CAMION_TOLVA';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas visibles','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos','ok_obs_falla','naranja',true,true),
          ('Suspension',    8,'PAQ_RESORTES','Resortes','ok_obs_falla','naranja',true,true),
          ('Transmision',   9,'CAMBIOS','Cambios','ok_obs_falla','naranja',false,true),
          ('Sistema Tolva',10,'PISTON','Piston / cilindro de levante','ok_obs_falla','naranja',true,true),
          ('Sistema Tolva',11,'BLOQUEO','Bloqueo de seguridad de tolva','si_no','rojo',false,true),
          ('Seguridad',    12,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    13,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    14,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',15,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── CAMION CARRETERA / TRACTO ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_CAMION_CARRETERA';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Frenos',        7,'FRENO_MOTOR','Freno motor','ok_obs_falla','naranja',false,true),
          ('Neumaticos',    8,'NEUM_GRAL','Neumaticos','ok_obs_falla','naranja',true,true),
          ('Suspension',    9,'AMORTIGUADORES','Amortiguadores','ok_obs_falla','amarillo',false,true),
          ('Transmision',  10,'CAMBIOS','Cambios','ok_obs_falla','naranja',false,true),
          ('Acoplamiento', 11,'QUINTA_RUEDA','Quinta rueda / king pin (si tracto)','ok_obs_falla','rojo',true,false),
          ('Seguridad',    12,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    13,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    14,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',15,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── CAMIONETA / LIVIANO ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_CAMIONETA_LIVIANO';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'NIVEL_REFRIG','Refrigerante','ok_obs_falla','amarillo',false,true),
          ('Motor/Fluidos', 5,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        6,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        7,'FRENO_MANO','Freno de mano','ok_obs_falla','naranja',false,true),
          ('Neumaticos',    8,'NEUM_PRESION','Presion neumaticos (psi/bar)','numerico','naranja',false,true),
          ('Neumaticos',    9,'NEUM_RUEDA_REP','Rueda repuesto + gata + llave','si_no','amarillo',false,true),
          ('Seguridad',    10,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    11,'CINTURON','Cinturones de seguridad','ok_obs_falla','rojo',false,true),
          ('Seguridad',    12,'BOTIQUIN','Botiquin + triangulos','si_no','amarillo',false,true),
          ('Seguridad',    13,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    14,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',15,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── FURGON / TALLER MOVIL ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_FURGON_TALLER';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Neumaticos',    6,'NEUM_GRAL','Neumaticos','ok_obs_falla','naranja',true,true),
          ('Equipamiento',  7,'COMPRESOR','Compresor de aire (si aplica)','ok_obs_falla','amarillo',false,false),
          ('Equipamiento',  8,'GRUPO_ELECT','Grupo electrogeno (si aplica)','ok_obs_falla','amarillo',false,false),
          ('Equipamiento',  9,'HERRAMIENTAS','Herramientas critical inventario','ok_obs_falla','amarillo',true,true),
          ('Equipamiento', 10,'LUBRICANTES','Stock lubricantes / filtros','ok_obs_falla','amarillo',false,false),
          ('Seguridad',    11,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    12,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',13,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── GRUA HORQUILLA / EQUIPO APOYO ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_GRUA_HORQUILLA';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_HOROM','Horometro','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite hidraulico','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas hidraulicas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'FRENO_ESTAC','Freno estacionamiento','si_no','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos / ruedas','ok_obs_falla','naranja',true,true),
          ('Mastil/Carga',  8,'CADENAS','Cadenas mastil (desgaste)','ok_obs_falla','rojo',true,true),
          ('Mastil/Carga',  9,'HORQUILLAS','Horquillas (grietas/desgaste)','ok_obs_falla','rojo',true,true),
          ('Mastil/Carga', 10,'HIDRAULICO','Cilindros hidraulicos','ok_obs_falla','rojo',true,true),
          ('Seguridad',    11,'CINTURON','Cinturon operador','ok_obs_falla','rojo',false,true),
          ('Seguridad',    12,'BOCINA','Bocina retroceso','si_no','naranja',false,true),
          ('Seguridad',    13,'BALIZA','Baliza superior','si_no','naranja',false,true),
          ('Seguridad',    14,'EXTINTOR','Extintor','si_no','rojo',false,true),
          ('Seguridad',    15,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',16,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── M.BENZ ACTROS 3336K (foco trans/susp/frenos/neumaticos) ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_MB_ACTROS_3336K';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire (bar)','numerico','rojo',false,true),
          ('Frenos',        7,'FRENO_MOTOR','Freno motor M.Benz','ok_obs_falla','naranja',false,true),
          ('Neumaticos',    8,'NEUM_12R225','Neumaticos 12R22.5 (presion/desgaste)','ok_obs_falla','naranja',true,true),
          ('Suspension',    9,'PAQ_RESORTES_MB','Paquete resortes M.Benz (grietas/golpes)','ok_obs_falla','naranja',true,true),
          ('Suspension',   10,'AMORTIGUADORES','Amortiguadores','ok_obs_falla','amarillo',false,true),
          ('Transmision',  11,'CAMBIOS_SINC','Cambios sincronizadores M.Benz','ok_obs_falla','naranja',false,true),
          ('Transmision',  12,'EMBRAGUE','Embrague (recorrido/ruido)','ok_obs_falla','amarillo',false,true),
          ('Transmision',  13,'PALANCA','Palanca (juego anormal)','ok_obs_falla','amarillo',false,true),
          ('Sistema Aljibe',14,'VALVULAS','Valvulas descarga','ok_obs_falla','rojo',true,false),
          ('Sistema Aljibe',15,'BOMBA','Bomba transferencia','ok_obs_falla','naranja',false,false),
          ('Seguridad',    16,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    17,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    18,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',19,'OBS_GRAL','Observaciones','texto',NULL,false,false),
          ('Observaciones',20,'EVIDENCIA','Foto evidencia','ok_obs_falla',NULL,true,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── M.BENZ ACTROS 3341 ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_MB_ACTROS_3341';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos (12R22.5/1200R24)','ok_obs_falla','naranja',true,true),
          ('Suspension',    8,'PAQ_RESORTES_MB','Paquete resortes M.Benz','ok_obs_falla','naranja',true,true),
          ('Transmision',   9,'CAMBIOS_SINC','Cambios / sincronizadores','ok_obs_falla','naranja',false,true),
          ('Transmision',  10,'EMBRAGUE','Embrague','ok_obs_falla','amarillo',false,true),
          ('Seguridad',    11,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    12,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    13,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',14,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── MACK GR64BX ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_MACK_GR64BX';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos pesado','ok_obs_falla','naranja',true,true),
          ('Suspension',    8,'PAQ_RESORTES_MACK','Paquete resortes Mack (foco historico)','ok_obs_falla','naranja',true,true),
          ('Suspension',    9,'AMORTIGUADORES','Amortiguadores','ok_obs_falla','amarillo',false,true),
          ('Tren Motriz',  10,'CARDAN','Cardan / cruceta','ok_obs_falla','naranja',false,true),
          ('Tren Motriz',  11,'DIFERENCIAL','Diferencial (ruido)','ok_obs_falla','naranja',false,true),
          ('Transmision',  12,'CAMBIOS','Cambios','ok_obs_falla','naranja',false,true),
          ('Seguridad',    13,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    14,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    15,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',16,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── SCANIA P450B ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_SCANIA_P450B';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos','ok_obs_falla','naranja',true,true),
          ('Tablero',       8,'TESTIGOS','Testigos tablero (engine/ABS/EGR)','ok_obs_falla','naranja',true,true),
          ('Emisiones',     9,'ADBLUE','Nivel AdBlue','ok_obs_falla','amarillo',false,true),
          ('Emisiones',    10,'EGR_DPF','Indicador EGR/DPF','ok_obs_falla','amarillo',false,true),
          ('Suspension',   11,'AMORTIGUADORES','Amortiguadores','ok_obs_falla','amarillo',false,true),
          ('Transmision',  12,'CAMBIOS','Cambios (Opticruise si aplica)','ok_obs_falla','naranja',false,true),
          ('Seguridad',    13,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    14,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    15,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',16,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── VOLVO VM ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_VOLVO_VM';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        5,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        6,'PRESION_AIRE','Presion aire','numerico','rojo',false,true),
          ('Neumaticos',    7,'NEUM_GRAL','Neumaticos','ok_obs_falla','naranja',true,true),
          ('PTO',           8,'PTO_FUNC','Toma de fuerza PTO (si aplica)','ok_obs_falla','naranja',false,false),
          ('Suspension',    9,'AMORTIGUADORES','Amortiguadores','ok_obs_falla','amarillo',false,true),
          ('Transmision',  10,'CAMBIOS','Cambios','ok_obs_falla','naranja',false,true),
          ('Seguridad',    11,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    12,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    13,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',14,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;

    -- ── TOYOTA HILUX / LIVIANOS ──
    SELECT id INTO v_tpl_id FROM qr_checklist_templates WHERE codigo='CL_TOYOTA_HILUX';
    IF v_tpl_id IS NOT NULL THEN
        INSERT INTO qr_checklist_template_items (template_id, seccion, orden, codigo_item, descripcion, tipo_respuesta, criticidad_si_falla, requiere_foto, obligatorio)
        SELECT v_tpl_id, x.seccion, x.orden, x.codigo, x.descr, x.tipo, x.crit, x.foto, x.obli
        FROM (VALUES
          ('Identificacion',1,'IDENT_OPERADOR','Operador','texto',NULL,false,true),
          ('Identificacion',2,'IDENT_KM','Lectura km','numerico',NULL,false,true),
          ('Motor/Fluidos', 3,'NIVEL_ACEITE','Aceite motor','ok_obs_falla','amarillo',true,true),
          ('Motor/Fluidos', 4,'NIVEL_REFRIG','Refrigerante','ok_obs_falla','amarillo',false,true),
          ('Motor/Fluidos', 5,'FUGAS','Fugas','ok_obs_falla','rojo',true,true),
          ('Frenos',        6,'PEDAL_FRENO','Pedal freno','ok_obs_falla','rojo',false,true),
          ('Frenos',        7,'FRENO_MANO','Freno mano','ok_obs_falla','naranja',false,true),
          ('Neumaticos',    8,'NEUM_PRESION','Presion neumaticos','numerico','naranja',false,true),
          ('Neumaticos',    9,'NEUM_REPUESTO','Rueda repuesto + gata','si_no','amarillo',false,true),
          ('Seguridad',    10,'LUCES','Luces','ok_obs_falla','naranja',false,true),
          ('Seguridad',    11,'CINTURON','Cinturones','ok_obs_falla','rojo',false,true),
          ('Seguridad',    12,'BOTIQUIN','Botiquin + triangulos','si_no','amarillo',false,true),
          ('Seguridad',    13,'EXTINTOR','Extintor vigente','si_no','rojo',false,true),
          ('Seguridad',    14,'EQUIPO_SEGURO','Equipo seguro','si_no','rojo',false,true),
          ('Observaciones',15,'OBS_GRAL','Observaciones','texto',NULL,false,false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto, obli)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END IF;
END $$;


-- ── 10. SEED de asignaciones jerarquicas ────────────────────────────
-- Universal NO requiere asignacion (se aplica por defecto via es_universal=true).
-- Asignaciones por TIPO (cubre toda la flota por tipo_activo).
INSERT INTO qr_checklist_template_asignaciones (template_id, tipo_activo, prioridad)
SELECT t.id, 'camion'::tipo_activo_enum, 400 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMION_PESADO'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, tipo_activo, prioridad)
SELECT t.id, 'camion_cisterna'::tipo_activo_enum, 400 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMION_ALJIBE'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, tipo_activo, prioridad)
SELECT t.id, 'camioneta'::tipo_activo_enum, 400 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMIONETA_LIVIANO'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, tipo_activo, prioridad)
SELECT t.id, 'lubrimovil'::tipo_activo_enum, 400 FROM qr_checklist_templates t WHERE t.codigo='CL_FURGON_TALLER'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, tipo_activo, prioridad)
SELECT t.id, 'equipo_menor'::tipo_activo_enum, 400 FROM qr_checklist_templates t WHERE t.codigo='CL_GRUA_HORQUILLA'
ON CONFLICT DO NOTHING;

-- Asignaciones por FAMILIA (fallback antes del universal)
INSERT INTO qr_checklist_template_asignaciones (template_id, familia_operacional, prioridad)
SELECT t.id, 'transporte_combustible', 500 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMION_ALJIBE'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, familia_operacional, prioridad)
SELECT t.id, 'transporte_pesado', 500 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMION_PESADO'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, familia_operacional, prioridad)
SELECT t.id, 'liviano', 500 FROM qr_checklist_templates t WHERE t.codigo='CL_CAMIONETA_LIVIANO'
ON CONFLICT DO NOTHING;
INSERT INTO qr_checklist_template_asignaciones (template_id, familia_operacional, prioridad)
SELECT t.id, 'soporte_operacional', 500 FROM qr_checklist_templates t WHERE t.codigo='CL_GRUA_HORQUILLA'
ON CONFLICT DO NOTHING;

-- Asignaciones por MODELO (lookup tolerante por nombre)
DO $$
DECLARE v_tpl UUID; v_mod UUID;
BEGIN
    -- M.Benz Actros 3336
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_MB_ACTROS_3336K';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Mercedes%' AND m.nombre ILIKE '%3336%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
    -- M.Benz Actros 3341
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_MB_ACTROS_3341';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Mercedes%' AND m.nombre ILIKE '%3341%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
    -- Mack GR64BX
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_MACK_GR64BX';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Mack%' AND m.nombre ILIKE '%GR64%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
    -- Scania P450B
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_SCANIA_P450B';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Scania%' AND m.nombre ILIKE '%P450%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
    -- Volvo VM (cualquier VM)
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_VOLVO_VM';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Volvo%' AND m.nombre ILIKE 'VM%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
    -- Toyota Hilux
    SELECT id INTO v_tpl FROM qr_checklist_templates WHERE codigo='CL_TOYOTA_HILUX';
    SELECT m.id INTO v_mod FROM modelos m JOIN marcas mk ON mk.id=m.marca_id
     WHERE mk.nombre ILIKE 'Toyota%' AND m.nombre ILIKE '%Hilux%' LIMIT 1;
    IF v_tpl IS NOT NULL AND v_mod IS NOT NULL THEN
        INSERT INTO qr_checklist_template_asignaciones (template_id, modelo_id, prioridad) VALUES (v_tpl, v_mod, 200) ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- Asignaciones por ACTIVO (6 patentes piloto criticas — solo si existen)
-- Idempotente: si la patente no existe en la BD, simplemente no se inserta nada.

INSERT INTO qr_checklist_template_asignaciones (template_id, activo_id, prioridad)
SELECT t.id, a.id, 100
  FROM activos a
  JOIN qr_checklist_templates t ON t.codigo = 'CL_MB_ACTROS_3336K'
 WHERE a.codigo IN ('KVWW-68','KVWW-69','JTYK-88')
ON CONFLICT DO NOTHING;

INSERT INTO qr_checklist_template_asignaciones (template_id, activo_id, prioridad)
SELECT t.id, a.id, 100
  FROM activos a
  JOIN qr_checklist_templates t ON t.codigo = 'CL_MB_ACTROS_3341'
 WHERE a.codigo = 'FSLZ-67'
ON CONFLICT DO NOTHING;

INSERT INTO qr_checklist_template_asignaciones (template_id, activo_id, prioridad)
SELECT t.id, a.id, 100
  FROM activos a
  JOIN qr_checklist_templates t ON t.codigo = 'CL_MACK_GR64BX'
 WHERE a.codigo = 'LKPY-18'
ON CONFLICT DO NOTHING;

INSERT INTO qr_checklist_template_asignaciones (template_id, activo_id, prioridad)
SELECT t.id, a.id, 100
  FROM activos a
  JOIN qr_checklist_templates t ON t.codigo = 'CL_SCANIA_P450B'
 WHERE a.codigo = 'TRST-58'
ON CONFLICT DO NOTHING;


-- ── 11. Bitacora ────────────────────────────────────────────────────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG14B_QR_CHECKLIST',
            'Modulo QR Checklist offline-first + Mantencion (paso 14B).',
            current_user, NOW(), NOW(), 'ok',
            '9 tablas + 6 RPCs + RLS + 13 templates + asignaciones jerarquicas. Frontend pendiente.'
        );
    END IF;
END $$;


-- ── 12. Verificacion estructural ────────────────────────────────────
SELECT 'TABLAS_14B' AS check_name,
       array_agg(table_name::text ORDER BY table_name::text) AS encontradas
  FROM information_schema.tables WHERE table_schema='public'
   AND table_name IN ('qr_checklist_templates','qr_checklist_template_items','qr_checklist_template_asignaciones',
                      'qr_checklist_respuestas','qr_checklist_respuesta_items','alertas_tempranas',
                      'mantenciones_registro','archivos_evidencia','sync_queue_offline');

SELECT 'RPCS_14B' AS check_name,
       array_agg(p.proname::text ORDER BY p.proname::text) AS encontradas
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('rpc_obtener_checklist_publico_por_qr','rpc_guardar_checklist_publico',
                     'rpc_generar_alerta_temprana','rpc_historial_mantencion_activo',
                     'rpc_registrar_mantencion_preventiva','rpc_cerrar_alerta_temprana');

SELECT 'TEMPLATES_14B' AS check_name, COUNT(*)::int AS total FROM qr_checklist_templates WHERE activo=true;

-- ============================================================================
-- ROLLBACK MANUAL
-- DROP FUNCTION IF EXISTS rpc_cerrar_alerta_temprana(UUID,TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_registrar_mantencion_preventiva(jsonb) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_historial_mantencion_activo(UUID) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_generar_alerta_temprana(UUID) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_guardar_checklist_publico(jsonb) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_obtener_checklist_publico_por_qr(UUID) CASCADE;
-- DROP VIEW IF EXISTS v_qr_checklist_cobertura_activos;
-- DROP FUNCTION IF EXISTS fn_qr_resolver_template_para_activo(UUID) CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_evaluar_semaforo_respuesta(UUID) CASCADE;
-- DROP FUNCTION IF EXISTS GREATEST_SEM(TEXT,TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_es_rol_mantencion() CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_familia_operacional(tipo_activo_enum) CASCADE;
-- DROP TABLE IF EXISTS sync_queue_offline CASCADE;
-- DROP TABLE IF EXISTS archivos_evidencia CASCADE;
-- DROP TABLE IF EXISTS mantenciones_registro CASCADE;
-- DROP TABLE IF EXISTS alertas_tempranas CASCADE;
-- DROP TABLE IF EXISTS qr_checklist_respuesta_items CASCADE;
-- DROP TABLE IF EXISTS qr_checklist_respuestas CASCADE;
-- DROP TABLE IF EXISTS qr_checklist_template_asignaciones CASCADE;
-- DROP TABLE IF EXISTS qr_checklist_template_items CASCADE;
-- DROP TABLE IF EXISTS qr_checklist_templates CASCADE;
-- ============================================================================
