-- ============================================================================
-- SICOM-ICEO | Migracion 127 — Checklist semanal del CLIENTE (publico por QR)
-- ----------------------------------------------------------------------------
-- El cliente que arrienda un equipo ejecuta, al menos semanalmente, un checklist
-- de estado del equipo (via QR/link publico, sin login) para que la compania
-- sepa el estado real del equipo en faena.
--
-- Sigue el patron anonimo probado del checklist QR (mig 14B):
--   - RPCs SECURITY DEFINER con GRANT EXECUTE ... TO anon.
--   - Lectura de plantilla abierta a anon; escritura SOLO via RPC.
--   - Storage: prefijo 'checklist-cliente/' en bucket 'documentos' (anon insert).
--
-- Incluye panel de cumplimiento (vista) y RPC para generar OT desde una novedad.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. PLANTILLA ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS checklist_cliente_plantilla_items (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    orden                INT NOT NULL DEFAULT 0,
    categoria            VARCHAR(40) NOT NULL DEFAULT 'general',
    descripcion          TEXT NOT NULL,
    obligatorio          BOOLEAN NOT NULL DEFAULT true,
    requiere_foto_si_falla BOOLEAN NOT NULL DEFAULT true,
    activo               BOOLEAN NOT NULL DEFAULT true,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. INSTANCIA (una por equipo por ejecucion) ─────────────────────────────
CREATE TABLE IF NOT EXISTS checklist_cliente_semanal (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id        UUID NOT NULL REFERENCES activos(id),
    contrato_id      UUID REFERENCES contratos(id),
    cliente_nombre   VARCHAR(200),
    anio             INT NOT NULL,
    semana_iso       INT NOT NULL,
    fecha            DATE NOT NULL DEFAULT CURRENT_DATE,
    operador_nombre  VARCHAR(160),
    operador_rut     VARCHAR(20),
    operador_empresa VARCHAR(160),
    telefono         VARCHAR(30),
    horometro        NUMERIC(12,1),
    kilometraje      NUMERIC(12,1),
    ubicacion        VARCHAR(200),
    lat              NUMERIC(10,6),
    lng              NUMERIC(10,6),
    firma_url        TEXT,
    foto_equipo_url  TEXT,
    items_total      INT NOT NULL DEFAULT 0,
    items_ok         INT NOT NULL DEFAULT 0,
    items_no_ok      INT NOT NULL DEFAULT 0,
    tiene_novedad    BOOLEAN NOT NULL DEFAULT false,
    observaciones    TEXT,
    estado           VARCHAR(20) NOT NULL DEFAULT 'completado',
    ot_generada_id   UUID REFERENCES ordenes_trabajo(id),
    revisado_por     UUID REFERENCES usuarios_perfil(id),
    revisado_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ccs_activo ON checklist_cliente_semanal(activo_id);
CREATE INDEX IF NOT EXISTS idx_ccs_semana ON checklist_cliente_semanal(anio, semana_iso);
CREATE INDEX IF NOT EXISTS idx_ccs_novedad ON checklist_cliente_semanal(tiene_novedad);

CREATE TABLE IF NOT EXISTS checklist_cliente_semanal_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checklist_id  UUID NOT NULL REFERENCES checklist_cliente_semanal(id) ON DELETE CASCADE,
    orden         INT NOT NULL DEFAULT 0,
    categoria     VARCHAR(40),
    descripcion   TEXT NOT NULL,
    resultado     VARCHAR(10) NOT NULL DEFAULT 'na',
    observacion   TEXT,
    foto_url      TEXT,
    CONSTRAINT chk_ccsi_resultado CHECK (resultado IN ('ok','no_ok','na'))
);
CREATE INDEX IF NOT EXISTS idx_ccsi_checklist ON checklist_cliente_semanal_items(checklist_id);

-- ── 3. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE checklist_cliente_plantilla_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_cliente_semanal ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_cliente_semanal_items ENABLE ROW LEVEL SECURITY;

-- Plantilla: lectura abierta (anon la necesita para mostrar el checklist).
DROP POLICY IF EXISTS pol_ccpi_select ON checklist_cliente_plantilla_items;
CREATE POLICY pol_ccpi_select ON checklist_cliente_plantilla_items
    FOR SELECT TO anon, authenticated USING (true);

-- Instancia + items: SELECT solo autenticados (la compania). Escritura via RPC.
DROP POLICY IF EXISTS pol_ccs_select ON checklist_cliente_semanal;
CREATE POLICY pol_ccs_select ON checklist_cliente_semanal
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_ccs_upd ON checklist_cliente_semanal;
CREATE POLICY pol_ccs_upd ON checklist_cliente_semanal
    FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_ccsi_select ON checklist_cliente_semanal_items;
CREATE POLICY pol_ccsi_select ON checklist_cliente_semanal_items
    FOR SELECT TO authenticated USING (true);

-- ── 4. STORAGE — anon puede subir fotos/firma bajo 'checklist-cliente/' ──────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='storage' AND table_name='objects') THEN
        BEGIN
            DROP POLICY IF EXISTS "storage_checklist_cliente_anon_insert" ON storage.objects;
            CREATE POLICY "storage_checklist_cliente_anon_insert" ON storage.objects
                FOR INSERT TO anon
                WITH CHECK (bucket_id = 'documentos'
                           AND (storage.foldername(name))[1] = 'checklist-cliente');
        EXCEPTION WHEN insufficient_privilege OR others THEN
            RAISE NOTICE 'No se pudo crear policy de storage (permiso). Crear manual si hace falta.';
        END;
    END IF;
END $$;

-- ── 5. RPC publico — obtener checklist (equipo + plantilla) ─────────────────
CREATE OR REPLACE FUNCTION rpc_checklist_cliente_obtener(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_act   RECORD;
    v_items JSONB;
BEGIN
    SELECT a.id, a.codigo, a.patente, a.nombre, a.contrato_id,
           a.cliente_actual, a.estado_comercial::TEXT AS estado_comercial,
           c.cliente AS contrato_cliente, c.codigo AS contrato_codigo
      INTO v_act
      FROM activos a
      LEFT JOIN contratos c ON c.id = a.contrato_id
     WHERE a.id = p_activo_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Equipo no encontrado');
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'orden', orden, 'categoria', categoria, 'descripcion', descripcion,
        'obligatorio', obligatorio, 'requiere_foto_si_falla', requiere_foto_si_falla
    ) ORDER BY orden)
      INTO v_items
      FROM checklist_cliente_plantilla_items WHERE activo = true;

    RETURN jsonb_build_object(
        'activo', jsonb_build_object(
            'id', v_act.id, 'codigo', v_act.codigo, 'patente', v_act.patente,
            'nombre', v_act.nombre, 'cliente', COALESCE(v_act.cliente_actual, v_act.contrato_cliente),
            'contrato_id', v_act.contrato_id, 'contrato_codigo', v_act.contrato_codigo,
            'estado_comercial', v_act.estado_comercial),
        'items', COALESCE(v_items, '[]'::JSONB)
    );
END $$;
GRANT EXECUTE ON FUNCTION rpc_checklist_cliente_obtener(UUID) TO anon, authenticated;

-- ── 6. RPC publico — guardar checklist ──────────────────────────────────────
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
        IF v_item->>'resultado' = 'no_ok' THEN v_no_ok := v_no_ok + 1; END IF;
    END LOOP;

    v_novedad := v_no_ok > 0;
    UPDATE checklist_cliente_semanal
       SET items_total = v_tot, items_ok = v_ok, items_no_ok = v_no_ok, tiene_novedad = v_novedad
     WHERE id = v_id;

    RETURN jsonb_build_object('id', v_id, 'items_total', v_tot, 'items_no_ok', v_no_ok,
                              'tiene_novedad', v_novedad);
END $$;
GRANT EXECUTE ON FUNCTION rpc_checklist_cliente_guardar(JSONB) TO anon, authenticated;

-- ── 7. VISTA — cumplimiento semanal por equipo arrendado ────────────────────
CREATE OR REPLACE VIEW v_checklist_cliente_cumplimiento AS
WITH arrendados AS (
    SELECT a.id AS activo_id, a.patente, a.codigo, a.nombre,
           COALESCE(a.cliente_actual, c.cliente) AS cliente, a.contrato_id
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
    WHERE a.estado_comercial = 'arrendado' AND a.fecha_baja IS NULL
),
ult AS (
    SELECT DISTINCT ON (activo_id) activo_id, id AS ultimo_id, fecha AS ultima_fecha,
           anio, semana_iso, tiene_novedad, items_no_ok, ot_generada_id
    FROM checklist_cliente_semanal
    ORDER BY activo_id, fecha DESC, created_at DESC
)
SELECT ar.activo_id, ar.patente, ar.codigo, ar.nombre, ar.cliente, ar.contrato_id,
       u.ultimo_id, u.ultima_fecha, u.tiene_novedad, u.items_no_ok, u.ot_generada_id,
       (u.activo_id IS NOT NULL
        AND u.anio = EXTRACT(ISOYEAR FROM NOW())::INT
        AND u.semana_iso = EXTRACT(WEEK FROM NOW())::INT) AS check_esta_semana,
       (CURRENT_DATE - u.ultima_fecha) AS dias_desde_ultimo,
       CASE
         WHEN u.activo_id IS NULL THEN 'sin_check'
         WHEN (CURRENT_DATE - u.ultima_fecha) > 7 THEN 'atrasado'
         ELSE 'al_dia'
       END AS estado_cumplimiento
FROM arrendados ar
LEFT JOIN ult u ON u.activo_id = ar.activo_id;

-- ── 8. RPC — generar OT correctiva desde una novedad (compania) ─────────────
CREATE OR REPLACE FUNCTION fn_generar_ot_desde_checklist_cliente(p_checklist_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_ck   RECORD;
    v_act  RECORD;
    v_ot   UUID;
    v_lista TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para generar OT. Rol: %', v_rol;
    END IF;

    SELECT * INTO v_ck FROM checklist_cliente_semanal WHERE id = p_checklist_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Checklist % no existe', p_checklist_id; END IF;
    IF v_ck.ot_generada_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', v_ck.ot_generada_id, 'mensaje', 'Ya tenia OT generada');
    END IF;

    SELECT id, contrato_id, faena_id, patente, codigo INTO v_act FROM activos WHERE id = v_ck.activo_id;
    IF v_act.contrato_id IS NULL OR v_act.faena_id IS NULL THEN
        RAISE EXCEPTION 'El equipo no tiene contrato/faena para crear OT.';
    END IF;

    SELECT string_agg('- ' || descripcion || COALESCE(': '||observacion,''), E'\n')
      INTO v_lista FROM checklist_cliente_semanal_items
     WHERE checklist_id = p_checklist_id AND resultado = 'no_ok';

    INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
        observaciones, generada_automaticamente, created_by)
    VALUES ('correctivo', v_act.contrato_id, v_act.faena_id, v_ck.activo_id, 'alta', 'creada',
        'OT desde checklist semanal del CLIENTE (' || COALESCE(v_ck.cliente_nombre,'') || '). Novedades:' ||
        E'\n' || COALESCE(v_lista,'(sin detalle)'), true, v_user)
    RETURNING id INTO v_ot;

    UPDATE checklist_cliente_semanal
       SET ot_generada_id = v_ot, revisado_por = v_user, revisado_at = NOW()
     WHERE id = p_checklist_id;

    RETURN jsonb_build_object('ot_id', v_ot);
END $$;

-- ── 9. SEED plantilla (estado del equipo, lenguaje de cliente) ──────────────
INSERT INTO checklist_cliente_plantilla_items (orden, categoria, descripcion, obligatorio, requiere_foto_si_falla)
SELECT * FROM (VALUES
    (1, 'fluidos',   'Nivel de aceite de motor correcto (sin testigo encendido)', true, true),
    (2, 'fluidos',   'Nivel de refrigerante correcto', true, true),
    (3, 'fluidos',   'Nivel de aceite hidráulico correcto (si aplica)', false, true),
    (4, 'fugas',     'Sin fugas visibles bajo el equipo (aceite, combustible, hidráulico)', true, true),
    (5, 'neumaticos','Neumáticos en buen estado: presión y sin daños/cortes', true, true),
    (6, 'luces',     'Luces, bocina y alarma de retroceso funcionando', true, true),
    (7, 'frenos',    'Frenos responden normal (servicio y estacionamiento)', true, true),
    (8, 'tablero',   'Tablero sin alarmas ni testigos de falla encendidos', true, true),
    (9, 'estructura','Estructura/carrocería sin daños nuevos (golpes, grietas)', true, true),
    (10,'seguridad', 'Extintor presente y cargado; cinturón en buen estado', true, true),
    (11,'limpieza',  'Equipo limpio y en condiciones de operación', false, false)
) AS v(orden, categoria, descripcion, obligatorio, requiere_foto_si_falla)
WHERE NOT EXISTS (SELECT 1 FROM checklist_cliente_plantilla_items);

-- ── 10. VALIDACION ──────────────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM checklist_cliente_plantilla_items) AS plantilla_items,
    (SELECT count(*) FROM pg_proc WHERE proname IN
       ('rpc_checklist_cliente_obtener','rpc_checklist_cliente_guardar','fn_generar_ot_desde_checklist_cliente')) AS rpcs,
    (SELECT count(*) FROM pg_views WHERE viewname='v_checklist_cliente_cumplimiento') AS vista;
