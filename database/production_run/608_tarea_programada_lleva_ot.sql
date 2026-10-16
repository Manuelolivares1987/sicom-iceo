-- ============================================================================
-- MIG608 — La tarea programada (terreno / soldadura / externo …) lleva OT
-- ============================================================================
-- 2026-10-16. Manuel: «colocamos programar tarea, en terreno, que está
-- programada el día jueves y no aparece absolutamente nada, ni para liberar,
-- ni en OT, ni siquiera que se pueda visualizar el jefe de taller».
--
-- Causa: la «tarea libre» (MIG182) era solo una fila del plan con ot_id NULL.
-- Liberar a ejecución, el teléfono del mecánico, la lista de OTs y el detalle
-- del jefe (checklist, tareas, recursos) cuelgan TODOS de una OT. Sin OT, la
-- tarea existía solo como tarjeta en el plan del programador.
--
-- Ahora toda tarea programada crea su OT en el mismo acto:
--   · Si nombra la patente de un camión EXTERNO (no flota) → ficha externa de
--     MIG607 (se crea o se reutiliza) con su checklist de inspección.
--   · Si no hay camión, o el camión es de la FLOTA (traslado, entrega,
--     despacho) → ficha de servicio «EXT-SERV-<op>», es_externo. NO se cuelga
--     del camión de la flota: una OT abierta lo marcaría en mantención en el
--     estado del día, y un traslado no es eso. La patente queda en el texto.
--   · La OT de servicio parte con el checklist VACÍO: el jefe le agrega las
--     tareas. La inspección de 181 ítems no corresponde a una soldadura.
--   · El técnico elegido queda en la cuadrilla (bono + teléfono).
-- Además: las tareas sin OT de esta semana en adelante se convierten.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Fichas de servicio (una por operación)
-- ---------------------------------------------------------------------------
INSERT INTO activos (
    codigo, nombre, tipo, modelo_id, patente, operacion, tipo_equipamiento,
    criticidad, estado, fecha_alta, qr_publico_habilitado,
    es_externo, externo_cliente, notas
)
SELECT v.codigo, v.nombre, 'equipo_menor', m.id, NULL, v.op, 'generico',
       'baja', 'operativo', CURRENT_DATE, FALSE,
       TRUE, 'Servicio sin equipo',
       'Ficha de servicio para tareas programadas sin camión propio (MIG608). No es flota Pillado.'
  FROM (VALUES ('EXT-SERV-CQB', 'SERVICIO EN TERRENO · Coquimbo', 'Coquimbo'),
               ('EXT-SERV-CAL', 'SERVICIO EN TERRENO · Calama',   'Calama')) v(codigo, nombre, op)
  JOIN modelos m ON m.tipo_activo = 'equipo_menor'
  JOIN marcas ma ON ma.id = m.marca_id AND ma.nombre = 'EXTERNO'
 WHERE NOT EXISTS (SELECT 1 FROM activos a WHERE a.codigo = v.codigo);

DO $$ BEGIN
    IF (SELECT count(*) FROM activos WHERE codigo IN ('EXT-SERV-CQB','EXT-SERV-CAL')) <> 2 THEN
        RAISE EXCEPTION 'MIG608: no se crearon las 2 fichas de servicio';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. La OT de servicio parte con el checklist vacío
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
    d   TEXT := pg_get_functiondef('public.fn_auto_checklist_ot()'::regprocedure);
    ancla TEXT := E'        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN\n            RETURN NEW;\n        END IF;\n';
BEGIN
    IF position(ancla IN d) = 0 THEN RAISE EXCEPTION 'MIG608: fn_auto_checklist_ot cambió, no calza el ancla'; END IF;
    d := replace(d, ancla, ancla || E'
        -- [MIG608] Tarea de servicio sin camión: checklist VACÍO, el jefe de
        -- taller le agrega las tareas. La inspección no le corresponde.
        IF EXISTS (SELECT 1 FROM activos WHERE id = NEW.activo_id AND codigo LIKE ''EXT-SERV-%'') THEN
            SELECT id INTO v_tpl FROM checklist_template_v2
             WHERE momento_uso=''recepcion_devolucion'' AND activo=true
             ORDER BY version DESC LIMIT 1;
            IF v_tpl IS NOT NULL THEN
                INSERT INTO checklist_v2_instance (template_id, momento_uso, activo_id, contrato_id, estado, ot_id)
                VALUES (v_tpl, ''recepcion_devolucion'', NEW.activo_id, NEW.contrato_id, ''en_progreso'', NEW.id);
            END IF;
            RETURN NEW;
        END IF;
');
    EXECUTE d;
END $mig$;

-- ---------------------------------------------------------------------------
-- 3. Crear la OT de una fila de tarea del plan
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_taller_tarea_crear_ot(p_plan_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    t          RECORD;
    v_op       TEXT;
    v_txt      TEXT;
    m          TEXT[];
    v_norm     TEXT;
    v_flota    RECORD;
    v_activo   UUID;
    v_cliente  TEXT;
    v_tipo     tipo_ot_enum;
    v_ot       JSONB;
    v_ot_id    UUID;
    v_cat      TEXT;
BEGIN
    SELECT po.*, d.fecha INTO t
      FROM taller_plan_semanal_ots po
      JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
     WHERE po.id = p_plan_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La tarea % no existe', p_plan_ot_id; END IF;
    IF t.ot_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', t.ot_id, 'ya_tenia', true);
    END IF;

    v_op := CASE WHEN t.operacion = 'Calama' THEN 'Calama' ELSE 'Coquimbo' END;

    -- ¿Nombra una patente? (ABCD-12 nueva o AB-1234 antigua)
    v_txt := upper(COALESCE(t.equipo_externo, '') || ' ' || COALESCE(t.titulo, ''));
    m := regexp_match(v_txt, '(?:^|[^A-Z0-9])([A-Z]{4})[- ]?([0-9]{2})(?:[^A-Z0-9]|$)');
    IF m IS NULL THEN
        m := regexp_match(v_txt, '(?:^|[^A-Z0-9])([A-Z]{2})[- ]?([0-9]{4})(?:[^A-Z0-9]|$)');
    END IF;

    IF m IS NOT NULL THEN
        v_norm := m[1] || m[2];
        SELECT id, es_externo INTO v_flota
          FROM activos
         WHERE upper(regexp_replace(COALESCE(patente, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
         ORDER BY es_externo DESC, created_at
         LIMIT 1;

        IF v_flota.id IS NOT NULL AND v_flota.es_externo THEN
            v_activo := v_flota.id;                       -- externo que ya vino
        ELSIF v_flota.id IS NULL THEN
            -- Externo nuevo: el cliente es lo que queda del texto sin la patente.
            v_cliente := btrim(regexp_replace(
                regexp_replace(COALESCE(t.equipo_externo, ''), m[1] || '[- ]?' || m[2], '', 'i'),
                '^[\s/·,;-]+|[\s/·,;-]+$', '', 'g'));
            IF length(COALESCE(v_cliente, '')) < 2 THEN v_cliente := 'Sin informar'; END IF;
            v_activo := (rpc_registrar_equipo_externo(v_norm, v_cliente, NULL, 'generico', v_op)->>'activo_id')::UUID;
        END IF;
        -- Patente de la flota: queda en v_activo NULL → ficha de servicio.
    END IF;

    IF v_activo IS NULL THEN
        SELECT id INTO v_activo FROM activos
         WHERE codigo = CASE v_op WHEN 'Calama' THEN 'EXT-SERV-CAL' ELSE 'EXT-SERV-CQB' END;
    END IF;

    v_tipo := CASE
        WHEN t.categoria = 'preventiva'  THEN 'preventivo'
        WHEN t.categoria = 'calibracion' THEN 'inspeccion'
        WHEN t.titulo ILIKE 'inspecc%'   THEN 'inspeccion'
        ELSE 'correctivo' END::tipo_ot_enum;

    v_ot := rpc_crear_ot(
        v_tipo, fn_contrato_interno_id(),
        COALESCE(fn_faena_taller_para_activo(v_activo), fn_faena_interna_id()),
        v_activo, 'normal', t.fecha, NULL, NULL, auth.uid(), t.tecnico_id);
    v_ot_id := (v_ot->>'id')::UUID;

    v_cat := upper(replace(COALESCE(t.categoria::TEXT, 'tarea'), '_', ' '));
    UPDATE ordenes_trabajo
       SET observaciones = left(format('[%s] %s%s%s', v_cat, t.titulo,
                              CASE WHEN t.equipo_externo IS NOT NULL THEN ' · ' || t.equipo_externo ELSE '' END,
                              CASE WHEN t.descripcion   IS NOT NULL THEN E'\n' || t.descripcion   ELSE '' END), 2000),
           updated_at = NOW()
     WHERE id = v_ot_id;

    UPDATE taller_plan_semanal_ots
       SET ot_id = v_ot_id, secuencia_jornada = 1, updated_at = NOW()
     WHERE id = p_plan_ot_id;

    -- El técnico elegido es la cuadrilla (de eso dependen el bono y el teléfono).
    IF t.tecnico_id IS NOT NULL THEN
        INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol, declarada_por, origen)
        VALUES (p_plan_ot_id, t.tecnico_id, 'titular', auth.uid(), 'manual')
        ON CONFLICT (plan_ot_id, tecnico_id) DO NOTHING;
    END IF;
    PERFORM fn_taller_sync_personal_ot(v_ot_id);

    RETURN jsonb_build_object('ot_id', v_ot_id, 'folio', v_ot->>'folio', 'activo_id', v_activo, 'ya_tenia', false);
END $function$;

REVOKE ALL ON FUNCTION public.fn_taller_tarea_crear_ot(UUID) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Programar tarea = fila del plan + su OT
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_taller_agregar_tarea_libre(p_plan_semanal_id uuid, p_fecha date, p_categoria categoria_tarea_taller, p_titulo text, p_descripcion text DEFAULT NULL::text, p_equipo_externo text DEFAULT NULL::text, p_operacion text DEFAULT NULL::text, p_tecnico_id uuid DEFAULT NULL::uuid, p_cuadrilla character varying DEFAULT NULL::character varying, p_horas numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_rol     TEXT := fn_user_rol();
    v_dia_id  UUID;
    v_id      UUID;
    v_ot      JSONB;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para programar tareas (rol: %)', v_rol; END IF;
    IF NULLIF(btrim(p_titulo),'') IS NULL THEN RAISE EXCEPTION 'El título de la tarea es obligatorio'; END IF;

    SELECT id INTO v_dia_id FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha;
    IF v_dia_id IS NULL THEN
        RAISE EXCEPTION 'No existe el día % en el plan %', p_fecha, p_plan_semanal_id;
    END IF;

    INSERT INTO taller_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id,
        categoria, titulo, descripcion, equipo_externo, operacion,
        tecnico_id, cuadrilla, horas_planificadas, estado_plan, created_by
    ) VALUES (
        p_plan_semanal_id, v_dia_id, NULL,
        p_categoria, btrim(p_titulo), NULLIF(btrim(p_descripcion),''),
        NULLIF(btrim(p_equipo_externo),''), NULLIF(btrim(p_operacion),''),
        p_tecnico_id, p_cuadrilla, p_horas, 'planificada', auth.uid()
    )
    RETURNING id INTO v_id;

    -- [MIG608] Sin OT, la tarea no se podía liberar ni la veía el jefe de taller.
    v_ot := fn_taller_tarea_crear_ot(v_id);

    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_id,
                              'ot_id', v_ot->>'ot_id', 'folio', v_ot->>'folio');
END $function$;

-- ---------------------------------------------------------------------------
-- 5. El mecánico ve en su teléfono QUÉ tarea es (la ficha de servicio sola
--    dice «SERVICIO EN TERRENO»). Columna nueva al final de la vista.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
    d TEXT := pg_get_viewdef('public.v_taller_mecanico_ots'::regclass);
    ancla TEXT := ' AS fecha_grupo
   FROM';
BEGIN
    IF position(ancla IN d) = 0 THEN RAISE EXCEPTION 'MIG608: v_taller_mecanico_ots cambió'; END IF;
    d := replace(d, ancla, ' AS fecha_grupo,
    ( SELECT string_agg(DISTINCT po.titulo, '' · '') FROM taller_plan_semanal_ots po
       WHERE po.ot_id = sub.ot_id AND po.titulo IS NOT NULL) AS tarea_titulo
   FROM');
    EXECUTE 'CREATE OR REPLACE VIEW public.v_taller_mecanico_ots AS ' || rtrim(d, '; ');
END $mig$;

-- ---------------------------------------------------------------------------
-- 6. Las tareas sin OT de esta semana en adelante se convierten
--    (como el Jefe de Taller: rpc_crear_ot y el registro de externos piden rol)
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE r RECORD; v JSONB; n INT := 0;
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', 'b3e47022-488f-48b6-99f0-7d9e2648b2f3', 'role', 'authenticated')::TEXT, true);
    FOR r IN
        SELECT po.id, po.titulo FROM taller_plan_semanal_ots po
          JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
         WHERE po.ot_id IS NULL
           AND d.fecha >= date_trunc('week', CURRENT_DATE)::DATE
           AND COALESCE(po.estado_plan, 'planificada') NOT IN ('cancelada', 'finalizada')
    LOOP
        v := fn_taller_tarea_crear_ot(r.id);
        n := n + 1;
        RAISE NOTICE 'MIG608: % → %', r.titulo, v->>'folio';
    END LOOP;
    RAISE NOTICE 'MIG608: % tarea(s) convertidas', n;
    PERFORM set_config('request.jwt.claims', '', true);
END $mig$;

COMMIT;
