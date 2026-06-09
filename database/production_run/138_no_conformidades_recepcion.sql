-- ============================================================================
-- SICOM-ICEO | 138 — No Conformidades de Recepción (mundo 2 de planificación)
-- ----------------------------------------------------------------------------
-- Modelo (de operaciones): la recepción se planifica a un grupo de trabajo, que
-- ejecuta el checklist profundo y encuentra No Conformidades (del checklist y
-- ad-hoc; TODAS se registran para mejora continua). A cada NC se le asignan
-- recursos (materiales + mano de obra=grupo + tiempo) y se vuelve a planificar.
--
-- Se construye sobre no_conformidades (registro único de NC, ya usado por los
-- quality gates) extendido con: origen, link a recepción, recursos y
-- planificación. El recobro (informe_recepcion_hallazgos) queda separado pero
-- enlazable (hallazgo_id).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Extender no_conformidades ────────────────────────────────────────────
ALTER TABLE no_conformidades
    ADD COLUMN IF NOT EXISTS origen               VARCHAR(30) NOT NULL DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS informe_recepcion_id  UUID REFERENCES informes_recepcion(id),
    ADD COLUMN IF NOT EXISTS checklist_item_ref    UUID,   -- item del checklist v2 (sin FK rígido)
    ADD COLUMN IF NOT EXISTS hallazgo_id           UUID REFERENCES informe_recepcion_hallazgos(id),
    ADD COLUMN IF NOT EXISTS grupo_trabajo         VARCHAR(100),
    ADD COLUMN IF NOT EXISTS horas_estimadas       NUMERIC(8,1),
    ADD COLUMN IF NOT EXISTS tiempo_estimado_dias  NUMERIC(6,1),
    ADD COLUMN IF NOT EXISTS estado_planificacion  VARCHAR(20) NOT NULL DEFAULT 'registrada',
    ADD COLUMN IF NOT EXISTS plan_ot_id            UUID REFERENCES ordenes_trabajo(id),
    ADD COLUMN IF NOT EXISTS registrada_por        UUID REFERENCES usuarios_perfil(id);

DO $$ BEGIN
    BEGIN
        ALTER TABLE no_conformidades DROP CONSTRAINT IF EXISTS chk_nc_estado_plan;
        ALTER TABLE no_conformidades ADD CONSTRAINT chk_nc_estado_plan
            CHECK (estado_planificacion IN ('registrada','con_recursos','planificada','en_ejecucion','resuelta','descartada'));
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
CREATE INDEX IF NOT EXISTS idx_nc_origen ON no_conformidades(origen);
CREATE INDEX IF NOT EXISTS idx_nc_estado_plan ON no_conformidades(estado_planificacion);
CREATE INDEX IF NOT EXISTS idx_nc_informe ON no_conformidades(informe_recepcion_id);

-- ── 2. Materiales por NC (recurso) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nc_materiales (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    no_conformidad_id UUID NOT NULL REFERENCES no_conformidades(id) ON DELETE CASCADE,
    producto_id       UUID REFERENCES productos(id),
    descripcion       VARCHAR(200),   -- si no está en catálogo
    cantidad          NUMERIC(12,2) NOT NULL DEFAULT 1,
    comentario        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ncmat_nc ON nc_materiales(no_conformidad_id);

ALTER TABLE nc_materiales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ncmat_sel ON nc_materiales;
CREATE POLICY pol_ncmat_sel ON nc_materiales FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_ncmat_wr ON nc_materiales;
CREATE POLICY pol_ncmat_wr ON nc_materiales FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ── 3. RPC — generar NC desde el checklist de recepción (items no_ok) ───────
CREATE OR REPLACE FUNCTION fn_generar_nc_desde_recepcion(p_informe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_activo UUID;
    v_inst   UUID;
    v_n      INT := 0;
    r        RECORD;
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
               ii.observacion
        FROM checklist_v2_instance_item ii
        JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
        WHERE ii.instance_id = v_inst AND ii.resultado = 'no_ok'
    LOOP
        -- idempotente: no duplicar si ya hay NC para ese item
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = r.item_id) THEN
            CONTINUE;
        END IF;
        INSERT INTO no_conformidades (
            activo_id, tipo, descripcion, fecha_evento, severidad, origen,
            informe_recepcion_id, checklist_item_ref, estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_activo, 'otra',
            r.descripcion || COALESCE(' — ' || r.observacion, ''),
            CURRENT_DATE, 'media', 'recepcion_checklist',
            p_informe_id, r.item_id, 'registrada', v_user, v_user
        );
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('creadas', v_n, 'activo_id', v_activo);
END $$;
GRANT EXECUTE ON FUNCTION fn_generar_nc_desde_recepcion(UUID) TO authenticated;

-- ── 4. RPC — registrar NC ad-hoc (no estaba en el checklist) ────────────────
CREATE OR REPLACE FUNCTION fn_registrar_nc_recepcion(
    p_activo_id    UUID,
    p_descripcion  TEXT,
    p_severidad    VARCHAR DEFAULT 'media',
    p_informe_id   UUID DEFAULT NULL,
    p_sistema      VARCHAR DEFAULT NULL,
    p_observacion  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_user UUID := auth.uid(); v_id UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF p_severidad NOT IN ('baja','media','alta','critica') THEN
        RAISE EXCEPTION 'Severidad invalida: %', p_severidad; END IF;
    INSERT INTO no_conformidades (
        activo_id, tipo, descripcion, fecha_evento, severidad, origen,
        informe_recepcion_id, accion_correctiva, estado_planificacion, registrada_por, created_by
    ) VALUES (
        p_activo_id, 'otra', p_descripcion, CURRENT_DATE, p_severidad, 'recepcion_adhoc',
        p_informe_id, p_observacion, 'registrada', v_user, v_user
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('nc_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_registrar_nc_recepcion TO authenticated;

-- ── 5. RPC — asignar recursos a una NC (grupo MO + horas + tiempo + mats) ──
CREATE OR REPLACE FUNCTION fn_asignar_recursos_nc(
    p_nc_id          UUID,
    p_grupo_trabajo  VARCHAR DEFAULT NULL,
    p_horas          NUMERIC DEFAULT NULL,
    p_tiempo_dias    NUMERIC DEFAULT NULL,
    p_materiales     JSONB DEFAULT '[]'::JSONB   -- [{producto_id?, descripcion?, cantidad, comentario?}]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_user UUID := auth.uid(); v_m JSONB; v_nmat INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    UPDATE no_conformidades SET
        grupo_trabajo = COALESCE(p_grupo_trabajo, grupo_trabajo),
        horas_estimadas = COALESCE(p_horas, horas_estimadas),
        tiempo_estimado_dias = COALESCE(p_tiempo_dias, tiempo_estimado_dias),
        estado_planificacion = CASE WHEN estado_planificacion = 'registrada' THEN 'con_recursos'
                                    ELSE estado_planificacion END,
        updated_at = NOW()
    WHERE id = p_nc_id;

    -- Reemplazar materiales
    DELETE FROM nc_materiales WHERE no_conformidad_id = p_nc_id;
    FOR v_m IN SELECT * FROM jsonb_array_elements(COALESCE(p_materiales,'[]'::JSONB)) LOOP
        INSERT INTO nc_materiales (no_conformidad_id, producto_id, descripcion, cantidad, comentario)
        VALUES (p_nc_id, NULLIF(v_m->>'producto_id','')::UUID, v_m->>'descripcion',
                COALESCE((v_m->>'cantidad')::NUMERIC, 1), v_m->>'comentario');
        v_nmat := v_nmat + 1;
    END LOOP;

    RETURN jsonb_build_object('nc_id', p_nc_id, 'materiales', v_nmat);
END $$;
GRANT EXECUTE ON FUNCTION fn_asignar_recursos_nc TO authenticated;

-- ── 6. RPC — planificar la NC (crea OT correctiva y la deja lista para el plan)
CREATE OR REPLACE FUNCTION fn_planificar_nc(p_nc_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_act  RECORD;
    v_ot   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT * INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'NC % no existe', p_nc_id; END IF;
    IF v_nc.plan_ot_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', v_nc.plan_ot_id, 'mensaje', 'Ya tenía OT'); END IF;

    SELECT id, contrato_id, faena_id, patente, codigo INTO v_act FROM activos WHERE id = v_nc.activo_id;
    IF v_act.contrato_id IS NULL OR v_act.faena_id IS NULL THEN
        RAISE EXCEPTION 'El equipo no tiene contrato/faena para crear OT.'; END IF;

    INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
        observaciones, generada_automaticamente, created_by)
    VALUES ('correctivo', v_act.contrato_id, v_act.faena_id, v_nc.activo_id,
        CASE v_nc.severidad WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END,
        'creada',
        'NC de recepción: ' || v_nc.descripcion ||
        COALESCE(E'\nGrupo: ' || v_nc.grupo_trabajo, '') ||
        COALESCE(' · ' || v_nc.horas_estimadas || ' h', ''),
        true, v_user)
    RETURNING id INTO v_ot;

    UPDATE no_conformidades SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
    WHERE id = p_nc_id;

    RETURN jsonb_build_object('ot_id', v_ot, 'nc_id', p_nc_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_planificar_nc(UUID) TO authenticated;

-- ── 7. VISTA — tablero de NC de recepción ───────────────────────────────────
CREATE OR REPLACE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales
FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc');

-- ── 8. VALIDACION ───────────────────────────────────────────────────────────
SELECT
    (SELECT count(*) FROM information_schema.columns WHERE table_name='no_conformidades' AND column_name='estado_planificacion') AS col_ok,
    (SELECT count(*) FROM information_schema.tables WHERE table_name='nc_materiales') AS tabla_mat,
    (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_generar_nc_desde_recepcion','fn_registrar_nc_recepcion','fn_asignar_recursos_nc','fn_planificar_nc')) AS rpcs,
    (SELECT count(*) FROM pg_views WHERE viewname='v_nc_recepcion') AS vista;
