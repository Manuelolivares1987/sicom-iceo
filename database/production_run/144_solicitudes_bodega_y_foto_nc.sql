-- ============================================================================
-- SICOM-ICEO | 144 — Foto en NC + Solicitudes de material a Bodega
-- ----------------------------------------------------------------------------
-- (1) no_conformidades.foto_url: la NC lleva foto. Las generadas del checklist
--     copian la foto del ítem (checklist_v2_instance_item.foto_url).
-- (2) Cuando un material que necesita una NC NO existe en bodega, se envía una
--     SOLICITUD a bodega con la foto + observación de la NC. Bodega la ve en su
--     bandeja y la atiende (crea el producto / la marca atendida).
-- IDEMPOTENTE.
-- ============================================================================

-- (1) Foto en la NC ----------------------------------------------------------
ALTER TABLE no_conformidades ADD COLUMN IF NOT EXISTS foto_url TEXT;

-- Regenerar fn_generar_nc_desde_recepcion para copiar la foto del ítem.
CREATE OR REPLACE FUNCTION fn_generar_nc_desde_recepcion(p_informe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_activo UUID;
    v_inst UUID;
    v_n INT := 0;
    r RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT activo_id INTO v_activo FROM informes_recepcion WHERE id = p_informe_id;
    IF v_activo IS NULL THEN RAISE EXCEPTION 'Informe % no existe', p_informe_id; END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE informe_recepcion_id = p_informe_id ORDER BY created_at DESC LIMIT 1;
    IF v_inst IS NULL THEN
        RETURN jsonb_build_object('creadas', 0, 'mensaje', 'Sin checklist de recepción asociado.');
    END IF;

    FOR r IN
        SELECT ii.id AS item_id,
               COALESCE(ti.descripcion, ti.nombre, 'Ítem') AS descripcion,
               ii.observacion, ii.foto_url
        FROM checklist_v2_instance_item ii
        JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
        WHERE ii.instance_id = v_inst AND ii.resultado = 'no_ok'
    LOOP
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = r.item_id) THEN
            CONTINUE;
        END IF;
        INSERT INTO no_conformidades (
            activo_id, tipo, descripcion, fecha_evento, severidad, origen,
            informe_recepcion_id, checklist_item_ref, foto_url,
            estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_activo, 'otra',
            r.descripcion || COALESCE(' — ' || r.observacion, ''),
            CURRENT_DATE, 'media', 'recepcion_checklist',
            p_informe_id, r.item_id, r.foto_url,
            'registrada', v_user, v_user
        );
        v_n := v_n + 1;
    END LOOP;
    RETURN jsonb_build_object('creadas', v_n, 'activo_id', v_activo);
END $$;
GRANT EXECUTE ON FUNCTION fn_generar_nc_desde_recepcion(UUID) TO authenticated;

-- (2) Solicitudes de material a bodega ---------------------------------------
CREATE TABLE IF NOT EXISTS bodega_solicitudes (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    descripcion       VARCHAR(200) NOT NULL,
    cantidad          NUMERIC(12,2) NOT NULL DEFAULT 1,
    unidad            VARCHAR(20),
    foto_url          TEXT,
    observacion       TEXT,
    no_conformidad_id UUID REFERENCES no_conformidades(id) ON DELETE SET NULL,
    activo_id         UUID REFERENCES activos(id),
    estado            VARCHAR(20) NOT NULL DEFAULT 'pendiente',  -- pendiente/atendida/rechazada
    solicitado_por    UUID REFERENCES usuarios_perfil(id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atendida_por      UUID REFERENCES usuarios_perfil(id),
    atendida_en       TIMESTAMPTZ,
    nota_bodega       TEXT,
    producto_id       UUID REFERENCES productos(id)
);
CREATE INDEX IF NOT EXISTS idx_bsol_estado ON bodega_solicitudes(estado);
CREATE INDEX IF NOT EXISTS idx_bsol_nc ON bodega_solicitudes(no_conformidad_id);

ALTER TABLE bodega_solicitudes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_bsol_sel ON bodega_solicitudes;
CREATE POLICY pol_bsol_sel ON bodega_solicitudes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_bsol_wr ON bodega_solicitudes;
CREATE POLICY pol_bsol_wr ON bodega_solicitudes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Crear solicitud (si viene de una NC, hereda foto + equipo + observación).
CREATE OR REPLACE FUNCTION fn_solicitar_material_bodega(
    p_descripcion VARCHAR,
    p_cantidad    NUMERIC DEFAULT 1,
    p_nc_id       UUID DEFAULT NULL,
    p_observacion TEXT DEFAULT NULL,
    p_foto_url    TEXT DEFAULT NULL,
    p_unidad      VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_foto TEXT := p_foto_url;
    v_obs  TEXT := p_observacion;
    v_act  UUID;
    v_id   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF COALESCE(TRIM(p_descripcion),'') = '' THEN RAISE EXCEPTION 'Descripción obligatoria.'; END IF;

    IF p_nc_id IS NOT NULL THEN
        SELECT activo_id, foto_url, descripcion INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
        v_act  := v_nc.activo_id;
        v_foto := COALESCE(v_foto, v_nc.foto_url);
        v_obs  := COALESCE(v_obs, v_nc.descripcion);
    END IF;

    INSERT INTO bodega_solicitudes (descripcion, cantidad, unidad, foto_url, observacion,
        no_conformidad_id, activo_id, solicitado_por)
    VALUES (p_descripcion, COALESCE(p_cantidad,1), p_unidad, v_foto, v_obs,
        p_nc_id, v_act, v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('solicitud_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_solicitar_material_bodega TO authenticated;

-- Atender / rechazar solicitud (bodega).
CREATE OR REPLACE FUNCTION fn_atender_solicitud_bodega(
    p_id          UUID,
    p_estado      VARCHAR DEFAULT 'atendida',  -- atendida/rechazada/pendiente
    p_nota        TEXT DEFAULT NULL,
    p_producto_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_user UUID := auth.uid();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF p_estado NOT IN ('atendida','rechazada','pendiente') THEN
        RAISE EXCEPTION 'Estado inválido: %', p_estado; END IF;
    UPDATE bodega_solicitudes SET
        estado = p_estado,
        nota_bodega = COALESCE(p_nota, nota_bodega),
        producto_id = COALESCE(p_producto_id, producto_id),
        atendida_por = CASE WHEN p_estado = 'pendiente' THEN NULL ELSE v_user END,
        atendida_en  = CASE WHEN p_estado = 'pendiente' THEN NULL ELSE NOW() END
    WHERE id = p_id;
    RETURN jsonb_build_object('ok', true);
END $$;
GRANT EXECUTE ON FUNCTION fn_atender_solicitud_bodega TO authenticated;

-- Vista — bandeja de solicitudes con datos del equipo.
CREATE OR REPLACE VIEW v_bodega_solicitudes AS
SELECT s.*, a.patente, a.codigo AS activo_codigo,
       up.nombre_completo AS solicitado_por_nombre
FROM bodega_solicitudes s
LEFT JOIN activos a ON a.id = s.activo_id
LEFT JOIN usuarios_perfil up ON up.id = s.solicitado_por;

SELECT (SELECT count(*) FROM information_schema.columns WHERE table_name='no_conformidades' AND column_name='foto_url') AS nc_foto,
       (SELECT count(*) FROM information_schema.tables WHERE table_name='bodega_solicitudes') AS tabla,
       (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_solicitar_material_bodega','fn_atender_solicitud_bodega')) AS rpcs;
