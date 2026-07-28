-- ============================================================================
-- SICOM-ICEO | 252 — La nota del operador se convierte en No Conformidad
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-27): «si de las notas del operador se deben hacer
-- tareas, ¿cómo se hacen?». Hoy NO se puede: las notas (MIG249) son un anexo de
-- solo lectura. Si el operador escribe «válvula neumática de la bomba de
-- combustible con falla» y adjunta la foto, el jefe tiene que re-escribirla a
-- mano como NC manual y volver a sacar la foto (el formulario pide un archivo,
-- no acepta la que ya está subida). Se pierde el autor y la trazabilidad.
--
-- Decisión de Manuel: la nota se convierte en NC, así entra al circuito que ya
-- existe (recursos → planificar → recobro).
--
--   1. no_conformidades.nota_evidencia_id: de qué nota nació la NC. Índice
--      único → convertir dos veces la misma nota devuelve la NC existente.
--   2. rpc_nota_a_nc(nota, severidad, descripcion): crea la NC con la foto y el
--      AUTOR de la nota (el operador, no el jefe que aprieta el botón), ligada a
--      la OT donde se escribió. Marca la nota para que la UI no la ofrezca dos
--      veces.
--
-- BONUS — bug encontrado al revisar: fn_planificar_nc_equipo y
-- fn_asignar_recursos_nc_equipo filtran origen IN (...) SIN 'manual'. La MIG220
-- metió las NC manuales a la bandeja pero no a estas dos funciones, así que hoy
-- JTYK-88 (3 NC), KCBY-30 (2) y SVBJ-55 (1) muestran el botón «Planificar
-- equipo (N)» y al apretarlo responde «Sin NC pendientes». Se agrega 'manual'.
-- (La NC nacida de una nota usa origen='ejecucion_ot', que ya está soportado en
-- todas partes; el origen real se lee en nota_evidencia_id.)
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='no_conformidades' AND column_name='recobro_informe_id') THEN
        RAISE EXCEPTION 'STOP — falta MIG251.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname='evidencias_ot_tipo_check'
                     AND pg_get_constraintdef(oid) ILIKE '%nota%') THEN
        RAISE EXCEPTION 'STOP — falta MIG249 (evidencias_ot tipo=nota).';
    END IF;
END $$;


-- ── 1. La NC recuerda de qué nota nació ──────────────────────────────────────
ALTER TABLE no_conformidades
    ADD COLUMN IF NOT EXISTS nota_evidencia_id UUID REFERENCES evidencias_ot(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_nc_nota_evidencia
    ON no_conformidades(nota_evidencia_id) WHERE nota_evidencia_id IS NOT NULL;

COMMENT ON COLUMN no_conformidades.nota_evidencia_id IS
    'Nota del operador (evidencias_ot tipo=nota) que originó esta NC. MIG252.';


-- ── 2. Convertir la nota en NC ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_nota_a_nc(
    p_evidencia_id UUID,
    p_severidad    TEXT DEFAULT 'media',
    p_descripcion  TEXT DEFAULT NULL   -- NULL = el texto tal cual lo escribió el operador
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT := public.fn_user_rol();
    v_nota   RECORD;
    v_activo UUID;
    v_foto   TEXT;
    v_desc   TEXT;
    v_exist  UUID;
    v_id     UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para convertir notas en NC (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    IF p_severidad NOT IN ('baja','media','alta','critica') THEN
        RAISE EXCEPTION 'Severidad inválida: %', p_severidad;
    END IF;

    SELECT e.id, e.ot_id, e.descripcion, e.archivo_url, e.metadata, e.created_by
      INTO v_nota
      FROM evidencias_ot e
     WHERE e.id = p_evidencia_id AND e.tipo = 'nota';
    IF NOT FOUND THEN RAISE EXCEPTION 'La nota % no existe', p_evidencia_id; END IF;

    -- Idempotente: la misma nota no genera dos NC
    SELECT id INTO v_exist FROM no_conformidades WHERE nota_evidencia_id = p_evidencia_id;
    IF v_exist IS NOT NULL THEN
        RETURN jsonb_build_object('ok', true, 'nc_id', v_exist, 'ya_existia', true);
    END IF;

    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id = v_nota.ot_id;
    IF v_activo IS NULL THEN
        RAISE EXCEPTION 'La OT de la nota no tiene equipo asociado';
    END IF;

    -- Primera evidencia que sea foto (las notas admiten video, que no sirve de portada)
    SELECT f INTO v_foto
      FROM jsonb_array_elements_text(COALESCE(v_nota.metadata->'fotos', '[]'::jsonb)) AS t(f)
     WHERE f <> '' AND f !~* '\.(mp4|mov|webm|m4v|3gp)(\?|$)'
     LIMIT 1;
    v_foto := COALESCE(v_foto, NULLIF(v_nota.archivo_url, ''));

    v_desc := COALESCE(NULLIF(btrim(p_descripcion), ''), btrim(v_nota.descripcion));
    IF v_desc IS NULL OR v_desc = '' THEN RAISE EXCEPTION 'La nota no tiene texto'; END IF;

    INSERT INTO no_conformidades (
        activo_id, tipo, descripcion, fecha_evento, severidad, origen,
        ot_id, foto_url, accion_correctiva,
        estado_planificacion, registrada_por, created_by, nota_evidencia_id
    ) VALUES (
        v_activo, 'otra', v_desc, CURRENT_DATE, p_severidad, 'ejecucion_ot',
        v_nota.ot_id, v_foto,
        'Levantada desde una nota del operador en la OT.',
        'registrada',
        -- El mérito es del operador que la detectó, no del jefe que la convierte
        COALESCE(v_nota.created_by, v_user),
        v_user, p_evidencia_id
    ) RETURNING id INTO v_id;

    -- La nota queda marcada para que la UI no la ofrezca de nuevo
    UPDATE evidencias_ot
       SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('nc_id', v_id)
     WHERE id = p_evidencia_id;

    RETURN jsonb_build_object('ok', true, 'nc_id', v_id, 'activo_id', v_activo, 'ya_existia', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nota_a_nc(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nota_a_nc(UUID, TEXT, TEXT) TO authenticated;


-- ── 3. FIX: las NC manuales también se planifican y reciben recursos ─────────
-- MIG220 las metió a la bandeja pero estas dos funciones quedaron sin 'manual'.
CREATE OR REPLACE FUNCTION public.fn_asignar_recursos_nc_equipo(
    p_activo_id uuid,
    p_grupo character varying DEFAULT NULL::character varying,
    p_horas numeric DEFAULT NULL::numeric,
    p_tiempo_dias numeric DEFAULT NULL::numeric,
    p_materiales jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_ids    UUID[];
    v_ancla  UUID;
    v_m      JSONB;
    v_nc_dest UUID;
    v_nmat   INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT array_agg(id ORDER BY created_at) INTO v_ids
      FROM no_conformidades
     WHERE activo_id = p_activo_id
       -- [MIG252] + 'manual'
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND estado_planificacion IN ('registrada','con_recursos','planificada')
       AND COALESCE(resuelto, false) = false;

    IF v_ids IS NULL THEN
        RAISE EXCEPTION 'El equipo no tiene NC abiertas para asignar recursos.';
    END IF;
    v_ancla := v_ids[1];

    UPDATE no_conformidades SET
        grupo_trabajo = COALESCE(p_grupo, grupo_trabajo),
        horas_estimadas = CASE WHEN p_horas IS NULL THEN horas_estimadas
                               WHEN id = v_ancla THEN p_horas ELSE NULL END,
        tiempo_estimado_dias = CASE WHEN p_tiempo_dias IS NULL THEN tiempo_estimado_dias
                                    WHEN id = v_ancla THEN p_tiempo_dias ELSE NULL END,
        estado_planificacion = CASE WHEN estado_planificacion = 'registrada' THEN 'con_recursos'
                                    ELSE estado_planificacion END,
        updated_at = NOW()
    WHERE id = ANY(v_ids);

    DELETE FROM nc_materiales WHERE no_conformidad_id = ANY(v_ids);
    FOR v_m IN SELECT * FROM jsonb_array_elements(COALESCE(p_materiales, '[]'::JSONB)) LOOP
        v_nc_dest := COALESCE(NULLIF(v_m->>'nc_id','')::UUID, v_ancla);
        IF NOT (v_nc_dest = ANY(v_ids)) THEN v_nc_dest := v_ancla; END IF;
        INSERT INTO nc_materiales (no_conformidad_id, producto_id, descripcion, cantidad, comentario)
        VALUES (v_nc_dest, NULLIF(v_m->>'producto_id','')::UUID, v_m->>'descripcion',
                COALESCE((v_m->>'cantidad')::NUMERIC, 1), v_m->>'comentario');
        v_nmat := v_nmat + 1;
    END LOOP;

    RETURN jsonb_build_object('n_ncs', array_length(v_ids, 1), 'materiales', v_nmat, 'ancla_nc_id', v_ancla);
END $function$;


CREATE OR REPLACE FUNCTION public.fn_planificar_nc_equipo(p_activo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user    UUID := auth.uid();
    v_act     RECORD;
    v_ot      UUID;
    v_reusa   BOOLEAN := false;
    v_n       INT;
    v_sev_max VARCHAR;
    v_grupos  TEXT;
    v_horas   NUMERIC;
    v_lista   TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT count(*),
           (array_agg(severidad ORDER BY CASE severidad
                WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END))[1],
           string_agg(DISTINCT grupo_trabajo, ', '),
           sum(horas_estimadas),
           string_agg('• ' || descripcion, E'\n' ORDER BY created_at)
      INTO v_n, v_sev_max, v_grupos, v_horas, v_lista
      FROM no_conformidades
     WHERE activo_id = p_activo_id
       -- [MIG252] + 'manual'
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    IF v_n = 0 THEN
        RETURN jsonb_build_object('n_ncs', 0, 'mensaje', 'El equipo no tiene NC pendientes de planificar.');
    END IF;

    SELECT id, contrato_id, faena_id, patente, codigo INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    SELECT nc.plan_ot_id INTO v_ot
      FROM no_conformidades nc
      JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
     WHERE nc.activo_id = p_activo_id
       AND o.estado IN ('creada','asignada')
     ORDER BY o.created_at DESC
     LIMIT 1;

    IF v_ot IS NOT NULL THEN
        v_reusa := true;
        UPDATE ordenes_trabajo
           SET observaciones = COALESCE(observaciones || E'\n', '') || v_lista,
               updated_at = NOW()
         WHERE id = v_ot;
    ELSE
        IF v_act.contrato_id IS NULL OR v_act.faena_id IS NULL THEN
            RAISE EXCEPTION 'El equipo % no tiene contrato/faena para crear OT.',
                COALESCE(v_act.patente, v_act.codigo);
        END IF;
        INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by)
        VALUES ('correctivo'::tipo_ot_enum, v_act.contrato_id, v_act.faena_id, p_activo_id,
            (CASE v_sev_max WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END)::prioridad_enum,
            'creada'::estado_ot_enum,
            'Correctivo por ' || v_n || ' NC del equipo ' || COALESCE(v_act.patente, v_act.codigo) || E':\n' || v_lista ||
            COALESCE(E'\nGrupo: ' || v_grupos, '') ||
            COALESCE(' · ' || v_horas || ' h', ''),
            true, v_user)
        RETURNING id INTO v_ot;
    END IF;

    UPDATE no_conformidades
       SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
     WHERE activo_id = p_activo_id
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    RETURN jsonb_build_object('ot_id', v_ot, 'n_ncs', v_n, 'ot_reutilizada', v_reusa);
END $function$;


-- ── 4. La bandeja muestra que la NC vino de una nota ─────────────────────────
-- OJO: esta vista se ha recreado perdiendo columnas (MIG220 borró las de
-- MIG199). Si la vuelves a tocar, PARTE DE ESTA DEFINICIÓN.
DROP VIEW IF EXISTS v_nc_recepcion;
CREATE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
       nc.ot_id,

       -- [MIG199] evidencia y vínculo con el hallazgo del checklist
       nc.foto_url,
       nc.checklist_item_ref,
       (SELECT count(*) FROM ot_recursos_solicitados r
         WHERE r.instance_item_id = nc.checklist_item_ref) AS n_recursos_operador,

       -- [MIG250] contexto para leer la NC sin abrir nada más
       ii.observacion              AS observacion_item,
       ot.folio                    AS ot_folio,
       up.nombre_completo          AS registrada_por_nombre,

       -- [MIG250] ¿se le recobra al cliente?
       COALESCE(
           nc.recobro_override,
           ii.cobrable_override,
           ti.default_cobrable,
           CASE WHEN h.atribuible_cliente IS TRUE  THEN 'cliente'::default_cobrable_enum
                WHEN h.atribuible_cliente IS FALSE THEN 'empresa'::default_cobrable_enum END
       )                           AS recobro,
       CASE WHEN nc.recobro_override  IS NOT NULL THEN 'jefe'
            WHEN ii.cobrable_override IS NOT NULL THEN 'terreno'
            WHEN ti.default_cobrable  IS NOT NULL THEN 'pauta'
            WHEN h.atribuible_cliente IS NOT NULL THEN 'informe'
            ELSE 'sin_definir' END  AS recobro_fuente,
       nc.recobro_nota,

       -- [MIG250] notas/anexos que dejó el operador en la(s) OT de esta NC
       (SELECT count(*) FROM evidencias_ot e
         WHERE e.tipo = 'nota'
           AND (e.ot_id = nc.ot_id OR e.ot_id = nc.plan_ot_id)) AS n_notas_operador,

       -- [MIG251] estado del recobro y plata ya comprometida en materiales
       nc.recobro_informe_id,
       ir.folio                    AS recobro_informe_folio,
       ir.estado::text             AS recobro_informe_estado,
       COALESCE((SELECT sum(m.cantidad * COALESCE(p.costo_unitario_actual, 0))
                   FROM nc_materiales m
                   LEFT JOIN productos p ON p.id = m.producto_id
                  WHERE m.no_conformidad_id = nc.id), 0) AS costo_materiales_estimado,

       -- [MIG252] nació de una nota del operador
       nc.nota_evidencia_id

FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
LEFT JOIN informe_recepcion_hallazgos h  ON h.id = nc.hallazgo_id
LEFT JOIN ordenes_trabajo ot             ON ot.id = COALESCE(nc.plan_ot_id, nc.ot_id)
LEFT JOIN usuarios_perfil up             ON up.id = nc.registrada_por
LEFT JOIN informes_recepcion ir          ON ir.id = nc.recobro_informe_id
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual');

GRANT SELECT ON v_nc_recepcion TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_faltan TEXT;
    v_user UUID; v_nota UUID; v_res JSONB; v_res2 JSONB;
    v_activo UUID; v_n INT;
BEGIN
    SELECT string_agg(c, ', ') INTO v_faltan
      FROM unnest(ARRAY['foto_url','recobro','n_notas_operador','recobro_informe_folio',
                        'costo_materiales_estimado','nota_evidencia_id']) c
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name='v_nc_recepcion' AND column_name=c);
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO — v_nc_recepcion sin columnas: %', v_faltan;
    END IF;

    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    SELECT id INTO v_nota FROM evidencias_ot WHERE tipo='nota' ORDER BY created_at DESC LIMIT 1;
    IF v_user IS NULL OR v_nota IS NULL THEN
        RAISE NOTICE 'MIG252: sin datos para smoke (ok)'; RETURN;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    -- 1. Nota -> NC, con foto y autor del operador
    v_res := public.rpc_nota_a_nc(v_nota, 'alta', NULL);
    IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'FALLO smoke rpc_nota_a_nc'; END IF;
    RAISE NOTICE 'MIG252 OK: nota -> NC % (foto=%, autor=%)',
        v_res->>'nc_id',
        (SELECT foto_url IS NOT NULL FROM no_conformidades WHERE id=(v_res->>'nc_id')::uuid),
        (SELECT registrada_por_nombre FROM v_nc_recepcion WHERE id=(v_res->>'nc_id')::uuid);

    -- 2. Idempotencia: la misma nota no genera otra NC
    v_res2 := public.rpc_nota_a_nc(v_nota, 'alta', NULL);
    IF NOT (v_res2->>'ya_existia')::boolean OR (v_res2->>'nc_id') <> (v_res->>'nc_id') THEN
        RAISE EXCEPTION 'FALLO idempotencia nota -> NC';
    END IF;
    RAISE NOTICE 'MIG252 OK: idempotente (devuelve la misma NC)';

    -- 3. Las NC manuales ya entran a planificar.
    -- Se prueba sobre un equipo QUE TENGA contrato y faena: sin eso la OT no se
    -- puede crear (limitación previa del maestro de activos, no de esta MIG).
    SELECT nc.activo_id, count(*) INTO v_activo, v_n
      FROM no_conformidades nc
      JOIN activos a ON a.id = nc.activo_id
     WHERE nc.origen='manual' AND nc.plan_ot_id IS NULL
       AND nc.estado_planificacion IN ('registrada','con_recursos')
       AND a.contrato_id IS NOT NULL AND a.faena_id IS NOT NULL
     GROUP BY nc.activo_id ORDER BY count(*) DESC LIMIT 1;

    IF v_activo IS NOT NULL THEN
        v_res := public.fn_planificar_nc_equipo(v_activo);
        IF (v_res->>'n_ncs')::int = 0 THEN
            RAISE EXCEPTION 'FALLO — las NC manuales siguen sin planificarse';
        END IF;
        RAISE NOTICE 'MIG252 OK: NC manuales planificables (% NC -> OT)', v_res->>'n_ncs';
    ELSE
        -- Sin equipo apto: se verifica igual que el filtro nuevo las alcanza
        SELECT count(*) INTO v_n
          FROM no_conformidades
         WHERE origen='manual' AND plan_ot_id IS NULL
           AND estado_planificacion IN ('registrada','con_recursos');
        RAISE NOTICE 'MIG252: % NC manuales quedan alcanzables por el filtro nuevo; '
                     'ninguno de sus equipos tiene contrato/faena para crear la OT '
                     '(dato a corregir en el maestro de activos)', v_n;
    END IF;

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
