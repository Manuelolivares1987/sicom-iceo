-- ============================================================================
-- SICOM-ICEO | Migracion 49 — Informes de Recepcion (devolucion de arriendo)
-- ============================================================================
-- Cuando un equipo vuelve del cliente (estado R) se inspecciona. Si hay danos
-- imputables al cliente, genera un pre-informe editable con:
--   - Checklist de condicion (reusa template de 55 items + campos nuevos)
--   - Fotos 360 + evidencia de danos
--   - Costos estimados (repuestos del maestro, HH taller, servicios externos)
--   - Firma del tecnico inspector
--   - Edicion del encargado de cobros antes de emitir informe final
--   - PDF con hallazgos y valorizacion al cliente
--
-- Inspirado en Return Condition Report (Hertz, Ryder, Herc Rentals, Cat Rental).
-- ============================================================================

-- ============================================================================
-- 1. EXTENDER ENUMS
-- ============================================================================

-- Nuevo tipo de OT para la inspeccion de recepcion
ALTER TYPE tipo_ot_enum ADD VALUE IF NOT EXISTS 'inspeccion_recepcion';

-- Rol nuevo: encargado de cobros (edita pre-informes y emite el final)
ALTER TYPE rol_usuario_enum ADD VALUE IF NOT EXISTS 'encargado_cobros';

-- Estado del informe
DO $$ BEGIN
    CREATE TYPE estado_informe_recepcion_enum AS ENUM (
        'en_inspeccion',  -- Tecnico ejecutando checklist
        'borrador',       -- Pre-informe listo, editable por encargado
        'emitido',        -- Informe final generado, PDF listo
        'cancelado'       -- Anulado
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE gravedad_hallazgo_enum AS ENUM ('menor','mayor','critica');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE tipo_costo_recepcion_enum AS ENUM (
        'repuesto',           -- Producto del maestro
        'mano_obra',          -- HH de taller
        'servicio_externo',   -- Servicio contratado (lavado, soldadura externa)
        'otro'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ============================================================================
-- 2. TABLA tarifas_hh — HH de taller configurables
-- ============================================================================

CREATE TABLE IF NOT EXISTS tarifas_hh (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo         VARCHAR(30) UNIQUE NOT NULL,
    nombre         VARCHAR(100) NOT NULL,          -- "Mecánico Diesel", "Soldador", "Eléctrico"
    tarifa_clp     NUMERIC(10,0) NOT NULL,
    activo         BOOLEAN NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_tarifas_hh_updated_at
    BEFORE UPDATE ON tarifas_hh
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Seeds defaults (editables luego desde admin)
INSERT INTO tarifas_hh (codigo, nombre, tarifa_clp)
VALUES
    ('MEC_DIESEL',  'Mecánico Diesel',       25000),
    ('SOLDADOR',    'Soldador',              30000),
    ('ELECTRICO',   'Eléctrico automotriz',  28000),
    ('AYUDANTE',    'Ayudante de taller',    15000),
    ('LUBRICADOR',  'Lubricador',            18000)
ON CONFLICT (codigo) DO NOTHING;


-- ============================================================================
-- 3. TABLA informes_recepcion
-- ============================================================================

CREATE TABLE IF NOT EXISTS informes_recepcion (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id                UUID NOT NULL REFERENCES activos(id),
    contrato_id              UUID REFERENCES contratos(id),
    cliente_nombre           VARCHAR(200),         -- Snapshot del cliente al que se le cobrará

    fecha_entrega_arriendo   DATE,                  -- Cuando salio al cliente
    fecha_recepcion          DATE NOT NULL,         -- Hoy al recibir

    -- Linkeos con OTs
    ot_inspeccion_id         UUID REFERENCES ordenes_trabajo(id),
    ot_correctiva_id         UUID REFERENCES ordenes_trabajo(id),   -- reparacion derivada
    verificacion_entrega_id  UUID REFERENCES verificaciones_disponibilidad(id), -- ready-to-rent previo

    -- Responsables
    inspector_id             UUID REFERENCES usuarios_perfil(id),
    inspector_firma_url      TEXT,
    encargado_cobros_id      UUID REFERENCES usuarios_perfil(id),
    encargado_firma_url      TEXT,

    -- Resumen
    estado                   estado_informe_recepcion_enum NOT NULL DEFAULT 'en_inspeccion',
    subtotal_neto            NUMERIC(14,0) NOT NULL DEFAULT 0,
    iva                      NUMERIC(14,0) NOT NULL DEFAULT 0,
    total                    NUMERIC(14,0) NOT NULL DEFAULT 0,
    total_no_cobrable        NUMERIC(14,0) NOT NULL DEFAULT 0,
    total_cobrable_cliente   NUMERIC(14,0) NOT NULL DEFAULT 0,

    -- Salida
    pdf_url                  TEXT,
    folio                    VARCHAR(20),                   -- IR-YYYYMM-NNNNN
    observaciones_finales    TEXT,

    emitido_en               TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ir_activo     ON informes_recepcion (activo_id);
CREATE INDEX IF NOT EXISTS idx_ir_estado     ON informes_recepcion (estado);
CREATE INDEX IF NOT EXISTS idx_ir_contrato   ON informes_recepcion (contrato_id);
CREATE INDEX IF NOT EXISTS idx_ir_emitido    ON informes_recepcion (emitido_en DESC)
    WHERE estado = 'emitido';

CREATE TRIGGER trg_ir_updated_at
    BEFORE UPDATE ON informes_recepcion
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 4. TABLA informe_recepcion_hallazgos
-- ============================================================================

CREATE TABLE IF NOT EXISTS informe_recepcion_hallazgos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id          UUID NOT NULL REFERENCES informes_recepcion(id) ON DELETE CASCADE,
    checklist_item_id   UUID REFERENCES checklist_ot(id),      -- opcional: item del checklist origen
    seccion             VARCHAR(100),
    descripcion         TEXT NOT NULL,
    gravedad            gravedad_hallazgo_enum NOT NULL DEFAULT 'menor',
    atribuible_cliente  BOOLEAN NOT NULL DEFAULT true,
    fotos               JSONB NOT NULL DEFAULT '[]'::jsonb,   -- ["url1","url2"]
    observacion         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_irh_informe ON informe_recepcion_hallazgos (informe_id);


-- ============================================================================
-- 5. TABLA informe_recepcion_costos
-- ============================================================================

CREATE TABLE IF NOT EXISTS informe_recepcion_costos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id          UUID NOT NULL REFERENCES informes_recepcion(id) ON DELETE CASCADE,
    tipo                tipo_costo_recepcion_enum NOT NULL,
    producto_id         UUID REFERENCES productos(id),        -- si tipo=repuesto
    tarifa_hh_id        UUID REFERENCES tarifas_hh(id),       -- si tipo=mano_obra
    descripcion         VARCHAR(300) NOT NULL,
    cantidad            NUMERIC(10,2) NOT NULL CHECK (cantidad > 0),
    unidad              VARCHAR(20),
    precio_unitario     NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    total               NUMERIC(14,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    cobrable_cliente    BOOLEAN NOT NULL DEFAULT true,
    hallazgo_id         UUID REFERENCES informe_recepcion_hallazgos(id),  -- opcional link
    editado_por         UUID REFERENCES usuarios_perfil(id),
    editado_en          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_irc_informe ON informe_recepcion_costos (informe_id);


-- ============================================================================
-- 6. TRIGGER — recalcular totales del informe al cambiar costos
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_recalcular_totales_informe_recepcion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_informe_id UUID;
    v_subtotal   NUMERIC;
    v_cobrable   NUMERIC;
    v_no_cobr    NUMERIC;
    v_iva_rate   NUMERIC := 0.19;
BEGIN
    v_informe_id := COALESCE(NEW.informe_id, OLD.informe_id);
    IF v_informe_id IS NULL THEN RETURN NEW; END IF;

    SELECT
        COALESCE(SUM(total), 0),
        COALESCE(SUM(total) FILTER (WHERE cobrable_cliente = true), 0),
        COALESCE(SUM(total) FILTER (WHERE cobrable_cliente = false), 0)
      INTO v_subtotal, v_cobrable, v_no_cobr
      FROM informe_recepcion_costos
     WHERE informe_id = v_informe_id;

    UPDATE informes_recepcion
       SET subtotal_neto          = v_subtotal,
           total_cobrable_cliente = v_cobrable,
           total_no_cobrable      = v_no_cobr,
           iva                    = ROUND(v_cobrable * v_iva_rate, 0),
           total                  = ROUND(v_cobrable * (1 + v_iva_rate), 0),
           updated_at             = NOW()
     WHERE id = v_informe_id
       AND estado != 'emitido';   -- informe emitido es inmutable

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalc_totales_informe ON informe_recepcion_costos;
CREATE TRIGGER trg_recalc_totales_informe
    AFTER INSERT OR UPDATE OR DELETE ON informe_recepcion_costos
    FOR EACH ROW EXECUTE FUNCTION fn_recalcular_totales_informe_recepcion();


-- ============================================================================
-- 7. RPC — iniciar informe de recepcion
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_iniciar_informe_recepcion(
    p_activo_id   UUID,
    p_motivo      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id         UUID;
    v_activo          RECORD;
    v_verif_prev      UUID;
    v_contrato_id     UUID;
    v_faena_id        UUID;
    v_ot_id           UUID;
    v_ot_folio        VARCHAR;
    v_periodo         VARCHAR(6);
    v_secuencia       INTEGER;
    v_informe_id      UUID;
    v_informe_folio   VARCHAR;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- Ultima verificacion ready-to-rent aprobada (snapshot de entrega)
    SELECT id INTO v_verif_prev
      FROM verificaciones_disponibilidad
     WHERE activo_id = p_activo_id
       AND resultado = 'aprobado'
     ORDER BY aprobado_en DESC
     LIMIT 1;

    v_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
    v_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

    -- Folio OT estandar
    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));
    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
      INTO v_secuencia
      FROM ordenes_trabajo
     WHERE folio LIKE 'OT-' || v_periodo || '-%';
    v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

    -- Crear OT de inspeccion (el trigger de mig 46 copia el checklist)
    INSERT INTO ordenes_trabajo (
        folio, tipo, contrato_id, faena_id, activo_id,
        prioridad, estado, fecha_programada, observaciones,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_folio, 'inspeccion_recepcion'::tipo_ot_enum,
        v_contrato_id, v_faena_id, p_activo_id,
        'alta'::prioridad_enum, 'creada'::estado_ot_enum,
        CURRENT_DATE,
        COALESCE(p_motivo, 'Inspeccion de recepcion devolucion arriendo'),
        true, v_user_id
    )
    RETURNING id INTO v_ot_id;

    -- Folio del informe IR-YYYYMM-NNNNN
    PERFORM pg_advisory_xact_lock(hashtext('ir_folio_lock'));
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
      INTO v_secuencia
      FROM informes_recepcion
     WHERE folio LIKE 'IR-' || v_periodo || '-%';
    v_informe_folio := 'IR-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

    INSERT INTO informes_recepcion (
        activo_id, contrato_id, cliente_nombre,
        fecha_recepcion, ot_inspeccion_id, verificacion_entrega_id,
        inspector_id, estado, folio,
        fecha_entrega_arriendo
    ) VALUES (
        p_activo_id, v_contrato_id, v_activo.cliente_actual,
        CURRENT_DATE, v_ot_id, v_verif_prev,
        v_user_id, 'en_inspeccion', v_informe_folio,
        (SELECT aprobado_en::date FROM verificaciones_disponibilidad WHERE id = v_verif_prev)
    )
    RETURNING id INTO v_informe_id;

    RETURN jsonb_build_object(
        'success',     true,
        'informe_id',  v_informe_id,
        'ot_id',       v_ot_id,
        'ot_folio',    v_ot_folio,
        'informe_folio', v_informe_folio,
        'activo_id',   p_activo_id,
        'patente',     v_activo.patente
    );
END;
$$;


-- ============================================================================
-- 8. RPC — cerrar inspeccion y pasar a borrador (tecnico listo)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_cerrar_inspeccion_recepcion(
    p_informe_id         UUID,
    p_firma_tecnico_url  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id  UUID;
    v_informe  RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = p_informe_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Informe % no existe', p_informe_id;
    END IF;

    IF v_informe.estado NOT IN ('en_inspeccion') THEN
        RAISE EXCEPTION 'Informe en estado % no puede cerrarse como inspeccion', v_informe.estado;
    END IF;

    UPDATE informes_recepcion
       SET estado              = 'borrador',
           inspector_id        = COALESCE(inspector_id, v_user_id),
           inspector_firma_url = p_firma_tecnico_url,
           updated_at          = NOW()
     WHERE id = p_informe_id;

    -- Cerrar OT de inspeccion
    UPDATE ordenes_trabajo
       SET estado        = 'ejecutada_ok',
           fecha_termino = NOW(),
           updated_at    = NOW()
     WHERE id = v_informe.ot_inspeccion_id;

    RETURN jsonb_build_object('success', true, 'informe_id', p_informe_id, 'estado', 'borrador');
END;
$$;


-- ============================================================================
-- 9. RPC — emitir informe final (encargado de cobros)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_emitir_informe_recepcion(
    p_informe_id           UUID,
    p_firma_encargado_url  TEXT,
    p_pdf_url              TEXT,
    p_observaciones        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id  UUID;
    v_informe  RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = p_informe_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Informe % no existe', p_informe_id;
    END IF;

    IF v_informe.estado != 'borrador' THEN
        RAISE EXCEPTION 'Solo se puede emitir un informe en estado borrador (actual: %)', v_informe.estado;
    END IF;

    -- Doble firma: no el mismo usuario que inspecciono
    IF v_informe.inspector_id = v_user_id THEN
        RAISE EXCEPTION 'El encargado de cobros no puede ser el mismo tecnico inspector.';
    END IF;

    UPDATE informes_recepcion
       SET estado               = 'emitido',
           encargado_cobros_id  = v_user_id,
           encargado_firma_url  = p_firma_encargado_url,
           pdf_url              = p_pdf_url,
           observaciones_finales = COALESCE(p_observaciones, observaciones_finales),
           emitido_en           = NOW(),
           updated_at           = NOW()
     WHERE id = p_informe_id;

    RETURN jsonb_build_object('success', true, 'informe_id', p_informe_id, 'estado', 'emitido');
END;
$$;


-- ============================================================================
-- 10. RLS
-- ============================================================================

ALTER TABLE informes_recepcion              ENABLE ROW LEVEL SECURITY;
ALTER TABLE informe_recepcion_hallazgos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE informe_recepcion_costos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tarifas_hh                      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ir_all ON informes_recepcion;
CREATE POLICY pol_ir_all ON informes_recepcion FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_irh_all ON informe_recepcion_hallazgos;
CREATE POLICY pol_irh_all ON informe_recepcion_hallazgos FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_irc_all ON informe_recepcion_costos;
CREATE POLICY pol_irc_all ON informe_recepcion_costos FOR ALL TO authenticated
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_thh_all ON tarifas_hh;
CREATE POLICY pol_thh_all ON tarifas_hh FOR ALL TO authenticated
    USING (true) WITH CHECK (true);


-- ============================================================================
-- 11. VISTA — informes por estado (list view)
-- ============================================================================

CREATE OR REPLACE VIEW v_informes_recepcion_lista AS
SELECT
    ir.id,
    ir.folio,
    ir.estado,
    ir.activo_id,
    a.patente,
    a.codigo           AS activo_codigo,
    a.nombre           AS activo_nombre,
    ir.cliente_nombre,
    ir.fecha_recepcion,
    ir.fecha_entrega_arriendo,
    ir.total,
    ir.total_cobrable_cliente,
    ir.total_no_cobrable,
    ir.inspector_id,
    up_insp.nombre_completo AS inspector_nombre,
    ir.encargado_cobros_id,
    up_enc.nombre_completo  AS encargado_nombre,
    ir.emitido_en,
    ir.pdf_url,
    (SELECT COUNT(*) FROM informe_recepcion_hallazgos WHERE informe_id = ir.id) AS n_hallazgos,
    (SELECT COUNT(*) FROM informe_recepcion_hallazgos
       WHERE informe_id = ir.id AND atribuible_cliente = true) AS n_atrib_cliente,
    (SELECT COUNT(*) FROM informe_recepcion_costos WHERE informe_id = ir.id) AS n_costos,
    ir.created_at
FROM informes_recepcion ir
JOIN activos a              ON a.id = ir.activo_id
LEFT JOIN usuarios_perfil up_insp ON up_insp.id = ir.inspector_id
LEFT JOIN usuarios_perfil up_enc  ON up_enc.id  = ir.encargado_cobros_id;

COMMENT ON VIEW v_informes_recepcion_lista IS
    'Listado de informes de recepcion con resumen para tabla maestra.';


-- ============================================================================
-- 12. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_tabla_ok   BOOLEAN;
    v_fn1_ok     BOOLEAN;
    v_fn2_ok     BOOLEAN;
    v_fn3_ok     BOOLEAN;
    v_vista_ok   BOOLEAN;
    v_tarifas_n  INTEGER;
BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_name = 'informes_recepcion') INTO v_tabla_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_iniciar_informe_recepcion') INTO v_fn1_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_cerrar_inspeccion_recepcion') INTO v_fn2_ok;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_emitir_informe_recepcion') INTO v_fn3_ok;
    SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'v_informes_recepcion_lista') INTO v_vista_ok;
    SELECT COUNT(*) INTO v_tarifas_n FROM tarifas_hh WHERE activo = true;

    RAISE NOTICE '== Migracion 49 ==';
    RAISE NOTICE 'Tabla informes_recepcion ................. %', v_tabla_ok;
    RAISE NOTICE 'fn_iniciar_informe_recepcion ............. %', v_fn1_ok;
    RAISE NOTICE 'fn_cerrar_inspeccion_recepcion ........... %', v_fn2_ok;
    RAISE NOTICE 'fn_emitir_informe_recepcion .............. %', v_fn3_ok;
    RAISE NOTICE 'v_informes_recepcion_lista ............... %', v_vista_ok;
    RAISE NOTICE 'Tarifas HH activas ....................... %', v_tarifas_n;

    IF NOT (v_tabla_ok AND v_fn1_ok AND v_fn2_ok AND v_fn3_ok AND v_vista_ok) THEN
        RAISE EXCEPTION 'Migracion 49 incompleta.';
    END IF;
END $$;
