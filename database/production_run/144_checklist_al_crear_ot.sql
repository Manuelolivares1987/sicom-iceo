-- ============================================================================
-- SICOM-ICEO | 144 — El checklist de inspeccion se activa al crear la OT
-- ----------------------------------------------------------------------------
-- Cambia el gatillo del checklist al flujo real del usuario:
--   planifica -> se arma la OT -> se activa el checklist -> nacen las NC.
--
-- Decisiones (Manuel, 2026-06-16):
--   - TODAS las OT activan el checklist al crearse (cualquier tipo).
--   - Se MANTIENE tambien el gatillo de recepcion (estado_comercial=en_recepcion),
--     con dedup: si ya hay un checklist abierto para el equipo no se crea otro;
--     la OT se enlaza al checklist existente.
--   - Equipos hoy 'disponible' pasan por calidad: se les crea una OT de
--     inspeccion (que dispara el checklist) via fn_crear_ot_inspeccion_disponibles.
--
-- Requiere: 142 + 143 aplicados (template CL-INSPECCION-V03 activo).
-- IDEMPOTENTE.
-- ============================================================================

-- ── 0. Precheck ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM checklist_template_v2
                   WHERE momento_uso='recepcion_devolucion' AND activo=true) THEN
        RAISE EXCEPTION 'STOP - no hay template de recepcion/inspeccion activo (aplicar 142+143).';
    END IF;
END $$;


-- ── 1. Enlace checklist <-> OT ───────────────────────────────────────────────
ALTER TABLE checklist_v2_instance
    ADD COLUMN IF NOT EXISTS ot_id UUID REFERENCES ordenes_trabajo(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_cl_v2_instance_ot
    ON checklist_v2_instance (ot_id) WHERE ot_id IS NOT NULL;


-- ── 2. Trigger: al crear una OT se activa el checklist (con dedup) ───────────
CREATE OR REPLACE FUNCTION fn_auto_checklist_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
BEGIN
    -- Nunca bloquear la creacion de la OT.
    BEGIN
        -- Template de inspeccion activo
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true
         ORDER BY version DESC LIMIT 1;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        -- Dedup A: esta OT ya tiene checklist
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- Dedup B: ya hay un checklist de inspeccion ABIERTO para el equipo
        -- (p.ej. el de recepcion). Se enlaza a esta OT en vez de crear otro.
        SELECT id INTO v_inst FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id
           AND momento_uso = 'recepcion_devolucion'
           AND estado = 'en_progreso'
         ORDER BY fecha_inicio DESC LIMIT 1;
        IF v_inst IS NOT NULL THEN
            UPDATE checklist_v2_instance SET ot_id = NEW.id
             WHERE id = v_inst AND ot_id IS NULL;
            RETURN NEW;
        END IF;

        -- Crear el checklist para esta OT
        SELECT contrato_id, horas_uso_actual, kilometraje_actual
          INTO v_contrato, v_horas, v_km
          FROM activos WHERE id = NEW.activo_id;

        SELECT id INTO v_entrega FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id AND momento_uso='entrega_arriendo' AND estado='cerrado'
         ORDER BY fecha_cierre DESC LIMIT 1;

        v_inst := fn_inicializar_checklist_v2(
            v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
            NULL, v_horas, v_km, NULL, v_entrega
        );
        UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;

    EXCEPTION WHEN OTHERS THEN
        NULL;  -- defensivo: jamas bloquear la OT
    END;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_auto_checklist_ot ON ordenes_trabajo;
CREATE TRIGGER trg_auto_checklist_ot
    AFTER INSERT ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_auto_checklist_ot();

COMMENT ON FUNCTION fn_auto_checklist_ot() IS
    'Al crear cualquier OT activa el checklist de inspeccion V03 (dedup por equipo). '
    'De sus items no_ok nacen las No Conformidades al cerrar el checklist.';


-- ── 3. Generar NC desde el checklist ligado a una OT (idempotente) ───────────
CREATE OR REPLACE FUNCTION fn_generar_nc_desde_checklist_ot(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_inst   UUID;
    v_activo UUID;
    v_n      INT := 0;
    r        RECORD;
BEGIN
    SELECT id, activo_id INTO v_inst, v_activo
      FROM checklist_v2_instance
     WHERE ot_id = p_ot_id AND momento_uso='recepcion_devolucion'
     ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_inst IS NULL THEN
        RETURN jsonb_build_object('creadas', 0, 'mensaje', 'OT sin checklist de inspeccion.');
    END IF;

    FOR r IN
        SELECT ii.id AS item_id,
               COALESCE(ti.descripcion, 'Item') AS descripcion,
               ii.observacion
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst AND ii.resultado = 'no_ok'
    LOOP
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = r.item_id) THEN
            CONTINUE;  -- idempotente
        END IF;
        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen,
            checklist_item_ref, estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_activo, p_ot_id, 'otra',
            r.descripcion || COALESCE(' — ' || r.observacion, ''),
            CURRENT_DATE, 'media', 'inspeccion_ot',
            r.item_id, 'registrada', v_user, v_user
        );
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('creadas', v_n, 'activo_id', v_activo, 'ot_id', p_ot_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_generar_nc_desde_checklist_ot(UUID) TO authenticated;


-- ── 4. Trigger: al CERRAR el checklist de una OT se generan las NC ───────────
CREATE OR REPLACE FUNCTION fn_trg_nc_al_cerrar_checklist_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.estado='cerrado' AND OLD.estado IS DISTINCT FROM 'cerrado'
       AND NEW.ot_id IS NOT NULL AND NEW.momento_uso='recepcion_devolucion' THEN
        BEGIN
            PERFORM fn_generar_nc_desde_checklist_ot(NEW.ot_id);
        EXCEPTION WHEN OTHERS THEN NULL;  -- nunca bloquear el cierre
        END;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nc_al_cerrar_checklist_ot ON checklist_v2_instance;
CREATE TRIGGER trg_nc_al_cerrar_checklist_ot
    AFTER UPDATE OF estado ON checklist_v2_instance
    FOR EACH ROW EXECUTE FUNCTION fn_trg_nc_al_cerrar_checklist_ot();


-- ── 5. Las NC de inspeccion-OT entran al tablero de NC ───────────────────────
CREATE OR REPLACE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales
FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot');


-- ── 6. Cerrar checklist: firma cliente solo si hay contexto de cliente ───────
-- Una inspeccion interna ligada a OT (sin informe de recepcion) NO requiere
-- firma de cliente para cerrarse. La entrega y la recepcion real del cliente si.
CREATE OR REPLACE FUNCTION rpc_cerrar_checklist_v2(
    p_instance_id UUID,
    p_firma_operador_url TEXT,
    p_firma_cliente_url  TEXT,
    p_operador_rut       VARCHAR DEFAULT NULL,
    p_operador_nombre    VARCHAR DEFAULT NULL,
    p_cliente_rut        VARCHAR DEFAULT NULL,
    p_cliente_nombre     VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inst      RECORD;
    v_pendientes INTEGER;
    v_faltan_obligatorios INTEGER;
    v_requiere_cliente BOOLEAN;
BEGIN
    SELECT * INTO v_inst FROM checklist_v2_instance WHERE id = p_instance_id;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Checklist % no encontrado', p_instance_id;
    END IF;
    IF v_inst.estado = 'cerrado' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Checklist ya esta cerrado');
    END IF;

    IF p_firma_operador_url IS NULL OR length(trim(p_firma_operador_url)) = 0 THEN
        RAISE EXCEPTION 'Firma del operador es obligatoria';
    END IF;

    -- Firma cliente: entrega siempre; recepcion solo si es devolucion real del
    -- cliente (tiene informe). Inspeccion interna ligada a OT -> no requiere.
    v_requiere_cliente := (v_inst.momento_uso = 'entrega_arriendo')
        OR (v_inst.momento_uso = 'recepcion_devolucion' AND v_inst.informe_recepcion_id IS NOT NULL);

    IF v_requiere_cliente
       AND (p_firma_cliente_url IS NULL OR length(trim(p_firma_cliente_url)) = 0) THEN
        RAISE EXCEPTION 'Firma del cliente es obligatoria para recobro (% )', v_inst.momento_uso;
    END IF;

    SELECT COUNT(*) INTO v_faltan_obligatorios
      FROM checklist_v2_instance_item ii
      JOIN checklist_template_v2_item  ti ON ti.id = ii.template_item_id
     WHERE ii.instance_id = p_instance_id AND ti.obligatorio = true AND ii.resultado = 'pendiente';
    IF v_faltan_obligatorios > 0 THEN
        RAISE EXCEPTION 'Faltan % items obligatorios por responder', v_faltan_obligatorios;
    END IF;

    SELECT COUNT(*) INTO v_pendientes
      FROM checklist_v2_instance_item ii
      JOIN checklist_template_v2_item  ti ON ti.id = ii.template_item_id
     WHERE ii.instance_id = p_instance_id AND ti.requiere_foto = true AND ti.obligatorio = true
       AND (ii.foto_url IS NULL OR length(trim(ii.foto_url)) = 0);
    IF v_pendientes > 0 THEN
        RAISE EXCEPTION 'Faltan % fotos obligatorias', v_pendientes;
    END IF;

    UPDATE checklist_v2_instance
       SET estado='cerrado', fecha_cierre=NOW(),
           firma_operador_url=p_firma_operador_url, firma_cliente_url=p_firma_cliente_url,
           operador_rut=COALESCE(p_operador_rut, operador_rut),
           operador_nombre=COALESCE(p_operador_nombre, operador_nombre),
           cliente_rut=COALESCE(p_cliente_rut, cliente_rut),
           cliente_nombre=COALESCE(p_cliente_nombre, cliente_nombre)
     WHERE id = p_instance_id;

    RETURN jsonb_build_object('ok', true, 'instance_id', p_instance_id, 'cerrado_at', NOW());
END $$;
REVOKE ALL ON FUNCTION rpc_cerrar_checklist_v2(UUID,TEXT,TEXT,VARCHAR,VARCHAR,VARCHAR,VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cerrar_checklist_v2(UUID,TEXT,TEXT,VARCHAR,VARCHAR,VARCHAR,VARCHAR) TO authenticated;


-- ── 7. Backfill: OT de inspeccion para equipos hoy disponibles ───────────────
CREATE OR REPLACE FUNCTION fn_crear_ot_inspeccion_disponibles()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    a      RECORD;
    v_creadas    INT := 0;
    v_sin_ctto   INT := 0;
    v_en_proceso INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Solo administracion/jefatura puede generar el chequeo masivo. Rol: %', v_rol;
    END IF;

    FOR a IN
        SELECT id, contrato_id, faena_id
          FROM activos
         WHERE estado_comercial = 'disponible'
    LOOP
        -- Ya tiene un checklist de inspeccion abierto -> no duplicar
        IF EXISTS (SELECT 1 FROM checklist_v2_instance
                    WHERE activo_id = a.id AND momento_uso='recepcion_devolucion'
                      AND estado='en_progreso') THEN
            v_en_proceso := v_en_proceso + 1;
            CONTINUE;
        END IF;
        -- Sin contrato/faena no se puede crear OT
        IF a.contrato_id IS NULL OR a.faena_id IS NULL THEN
            v_sin_ctto := v_sin_ctto + 1;
            CONTINUE;
        END IF;

        INSERT INTO ordenes_trabajo (
            tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by
        ) VALUES (
            'inspeccion', a.contrato_id, a.faena_id, a.id, 'normal', 'creada',
            'Chequeo de calidad — equipo disponible (checklist de inspeccion V03)',
            true, v_user
        );  -- el trigger trg_auto_checklist_ot crea el checklist
        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'ot_creadas', v_creadas,
        'omitidos_ya_en_proceso', v_en_proceso,
        'omitidos_sin_contrato_faena', v_sin_ctto
    );
END $$;
GRANT EXECUTE ON FUNCTION fn_crear_ot_inspeccion_disponibles() TO authenticated;


-- ── 8. VALIDACION ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_ot_id',        (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                          WHERE table_name='checklist_v2_instance' AND column_name='ot_id')),
    'trg_auto_ot',      (SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_auto_checklist_ot')),
    'trg_nc_cierre',    (SELECT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_nc_al_cerrar_checklist_ot')),
    'rpc_nc_ot',        (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_generar_nc_desde_checklist_ot')),
    'rpc_backfill',     (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_crear_ot_inspeccion_disponibles')),
    'disponibles_hoy',  (SELECT COUNT(*) FROM activos WHERE estado_comercial='disponible'),
    'disponibles_sin_ctto', (SELECT COUNT(*) FROM activos WHERE estado_comercial='disponible'
                              AND (contrato_id IS NULL OR faena_id IS NULL))
) AS resultado;

NOTIFY pgrst, 'reload schema';
