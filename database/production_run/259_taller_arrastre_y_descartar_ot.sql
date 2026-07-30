-- ============================================================================
-- SICOM-ICEO | 259 — El trabajo que viene de semanas anteriores se ve, y se
--                    puede descartar con motivo
-- ----------------------------------------------------------------------------
-- Pregunta de Manuel sobre el flujo de recepción: «las NC encontradas, que
-- deberían ser otra OT, ¿en qué minuto se vuelven a programar?».
--
-- Respuesta: hoy en ninguno. Se programan UNA vez —cuando el planificador
-- arrastra el chip de «Correctivos de recepción por agendar» a un día— y si no
-- se cierran esa semana desaparecen de la vista:
--   · rpc_taller_get_or_create_plan_semanal crea la semana nueva VACÍA
--   · v_nc_ot_por_agendar excluye toda OT que alguna vez tuvo un día en el plan
--     (sin mirar de qué semana), así que agendada una vez no vuelve nunca
--   · el Kanban solo lee los días de la semana que se está mirando
-- Resultado medido en prod: 23 de 45 OT abiertas tenían su última planificación
-- en una semana pasada — 6 en ejecución y 2 pausadas, las más viejas del 15-jun.
--
-- Manuel eligió: bloque visible «Viene de semanas anteriores» que se arrastra a
-- un día (NO arrastre automático: el planificador decide), y un lugar para
-- descartar la OT que ya no corresponde.
--
-- Descartar ≠ borrar: la OT queda 'cancelada' con motivo obligatorio y su
-- historial intacto, se saca del plan, y sus NC VUELVEN a la bandeja. Si no
-- volvieran, descartar la OT escondería las NC para siempre — exactamente el
-- agujero que tapó MIG258.
--
-- Además alinea qué significa «OT abierta», que estaba distinto en tres lugares
-- y por ahí volvían los duplicados que MIG257 acabó de limpiar.
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_ot_abierta_reutilizable') THEN
        RAISE EXCEPTION 'STOP — falta fn_ot_abierta_reutilizable (MIG256).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='taller_plan_semanal_ots') THEN
        RAISE EXCEPTION 'STOP — falta taller_plan_semanal_ots.';
    END IF;
END $$;


-- ── 1. Qué se arrastra a esta semana ────────────────────────────────────────
-- OT abierta que NO está en el plan que se está viendo. Incluye las que están
-- en ejecución o pausadas (un trabajo empezado que se quedó fuera del plan es
-- justo lo que hay que ver) y las que nunca se planificaron.
-- Excluye lo que ya muestra «Correctivos de recepción por agendar» para no
-- repetir el mismo chip en dos bloques.
CREATE OR REPLACE FUNCTION public.fn_taller_ot_arrastre(p_plan_semanal_id UUID)
RETURNS TABLE (
    ot_id UUID, ot_folio VARCHAR, ot_tipo TEXT, ot_estado TEXT, ot_prioridad TEXT,
    activo_id UUID, patente VARCHAR, codigo VARCHAR,
    plan_mantenimiento_id UUID, pm_nombre TEXT,
    fecha_programada DATE, ultima_semana_en_plan DATE,
    semanas_atraso INT, nunca_planificada BOOLEAN,
    ncs INT, horas_estimadas NUMERIC, grupo_trabajo TEXT,
    tiene_avance BOOLEAN, responsable TEXT, observaciones TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH abiertas AS (
        SELECT o.*
          FROM ordenes_trabajo o
         WHERE o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                                'no_ejecutada','cancelada','cerrada')
           -- no está en el plan de esta semana (una fila cancelada no cuenta)
           AND NOT EXISTS (
                SELECT 1 FROM taller_plan_semanal_ots p
                 WHERE p.ot_id = o.id
                   AND p.plan_semanal_id = p_plan_semanal_id
                   AND COALESCE(p.estado_plan, 'planificada') <> 'cancelada')
           -- ya visible en «Correctivos de recepción por agendar»
           AND NOT EXISTS (SELECT 1 FROM v_nc_ot_por_agendar v WHERE v.ot_id = o.id)
    )
    SELECT o.id, o.folio, o.tipo::text, o.estado::text, o.prioridad::text,
           o.activo_id, a.patente, a.codigo,
           o.plan_mantenimiento_id, pm.nombre::text,
           o.fecha_programada,
           u.ultima_semana,
           GREATEST(0, ((date_trunc('week', CURRENT_DATE)::date - u.ultima_semana) / 7))::int,
           (u.ultima_semana IS NULL),
           (SELECT count(*)::int FROM no_conformidades nc
             WHERE nc.plan_ot_id = o.id AND COALESCE(nc.resuelto, false) = false),
           (SELECT sum(nc.horas_estimadas) FROM no_conformidades nc WHERE nc.plan_ot_id = o.id),
           (SELECT string_agg(DISTINCT nc.grupo_trabajo::text, ', ')
              FROM no_conformidades nc WHERE nc.plan_ot_id = o.id),
           (EXISTS (SELECT 1 FROM taller_ot_ejecuciones e WHERE e.ot_id = o.id)
            OR EXISTS (SELECT 1 FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado IS NOT NULL)),
           up.nombre_completo::text,
           o.observaciones
      FROM abiertas o
      LEFT JOIN activos a  ON a.id = o.activo_id
      LEFT JOIN planes_mantenimiento pm ON pm.id = o.plan_mantenimiento_id
      LEFT JOIN usuarios_perfil up ON up.id = COALESCE(o.responsable_id, o.tecnico_id)
      LEFT JOIN LATERAL (
            SELECT max(ps.fecha_inicio_semana) AS ultima_semana
              FROM taller_plan_semanal_ots p
              JOIN taller_planes_semanales ps ON ps.id = p.plan_semanal_id
             WHERE p.ot_id = o.id
      ) u ON true
     ORDER BY u.ultima_semana NULLS LAST, fn_prioridad_rank(o.prioridad) DESC, a.patente;
$function$;

COMMENT ON FUNCTION public.fn_taller_ot_arrastre(UUID) IS
    'OT abiertas que no están en el plan de esta semana: el trabajo que se arrastra y hoy no se veía en ninguna parte. MIG259.';

REVOKE ALL ON FUNCTION public.fn_taller_ot_arrastre(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_taller_ot_arrastre(UUID) TO authenticated;


-- ── 2. Descartar una OT que ya no corresponde ───────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_descartar_ot(
    p_ot_id  UUID,
    p_motivo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_nombre TEXT;
    v_ot     RECORD;
    v_ncs    INT := 0;
    v_dias   INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Tu perfil no puede descartar órdenes de trabajo.';
    END IF;

    IF COALESCE(length(trim(p_motivo)), 0) < 5 THEN
        RAISE EXCEPTION 'Indica el motivo por el que se descarta la OT (mínimo 5 caracteres).';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La OT no existe.'; END IF;

    IF v_ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RAISE EXCEPTION 'La OT % ya está ejecutada/cerrada: no se descarta.', v_ot.folio;
    END IF;
    IF v_ot.estado = 'cancelada' THEN
        RETURN jsonb_build_object('ot_id', p_ot_id, 'folio', v_ot.folio,
                                  'ya_estaba', true, 'mensaje', 'La OT ya estaba cancelada.');
    END IF;

    -- Con costo imputado no se descarta: eso se cierra, no se tira.
    IF EXISTS (SELECT 1 FROM movimientos_inventario WHERE ot_id = p_ot_id)
       OR EXISTS (SELECT 1 FROM salidas_bodega      WHERE ot_id = p_ot_id)
       OR EXISTS (SELECT 1 FROM inventario_consumos_capas WHERE ot_id = p_ot_id) THEN
        RAISE EXCEPTION 'La OT % ya tiene materiales imputados desde bodega: hay que cerrarla, no descartarla.',
            v_ot.folio;
    END IF;

    SELECT nombre_completo INTO v_nombre FROM usuarios_perfil WHERE id = v_user;

    -- 1) Las NC vuelven a la bandeja: si no, descartar la OT las esconde para
    --    siempre (MIG258 tapó ese mismo agujero).
    UPDATE no_conformidades
       SET plan_ot_id = NULL,
           estado_planificacion = CASE
               WHEN grupo_trabajo IS NOT NULL OR horas_estimadas IS NOT NULL
               THEN 'con_recursos' ELSE 'registrada' END,
           updated_at = NOW()
     WHERE plan_ot_id = p_ot_id
       AND COALESCE(resuelto, false) = false;
    GET DIAGNOSTICS v_ncs = ROW_COUNT;

    -- 2) Fuera del plan (lo ya finalizado no se toca: es historia).
    UPDATE taller_plan_semanal_ots
       SET estado_plan = 'cancelada', updated_at = NOW()
     WHERE ot_id = p_ot_id
       AND COALESCE(estado_plan, 'planificada') NOT IN ('finalizada','cancelada');
    GET DIAGNOSTICS v_dias = ROW_COUNT;

    -- 3) Y la OT queda cancelada, diciendo quién y por qué.
    UPDATE ordenes_trabajo
       SET estado = 'cancelada',
           observaciones = trim(COALESCE(observaciones, '') || E'\n[Descartada por ' ||
                                COALESCE(v_nombre, 'usuario') || ' el ' ||
                                to_char(NOW(), 'DD-MM-YYYY') || '] ' || trim(p_motivo) ||
                                CASE WHEN v_ncs > 0
                                     THEN ' · ' || v_ncs || ' NC devueltas a la bandeja.'
                                     ELSE '' END),
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object(
        'ot_id', p_ot_id, 'folio', v_ot.folio,
        'ncs_devueltas', v_ncs, 'dias_sacados_del_plan', v_dias,
        'mensaje', 'OT ' || v_ot.folio || ' descartada' ||
                   CASE WHEN v_ncs > 0
                        THEN ' · ' || v_ncs || ' NC volvieron a la bandeja para replanificar'
                        ELSE '' END
    );
END;
$function$;

COMMENT ON FUNCTION public.rpc_taller_descartar_ot(UUID, TEXT) IS
    'Descarta una OT que ya no corresponde: la cancela con motivo, la saca del plan y devuelve sus NC a la bandeja. MIG259.';

REVOKE ALL ON FUNCTION public.rpc_taller_descartar_ot(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_taller_descartar_ot(UUID, TEXT) TO authenticated;


-- ── 3. «OT abierta» tiene que significar lo mismo en todas partes ───────────
-- Estaba distinto en tres lugares y por ahí volvían los duplicados:
--   · v_nc_ot_por_agendar exigía creada/asignada  → si la correctiva se iniciaba
--     o se pausaba, sus NC dejaban de aparecer para agendar
--   · fn_planificar_nc_equipo reutilizaba solo creada/asignada → si estaba en
--     ejecución o pausada abría OTRA OT correctiva
--   · fn_planificar_nc (una NC sola) NUNCA reutilizaba: siempre insertaba

CREATE OR REPLACE VIEW public.v_nc_ot_por_agendar AS
SELECT nc.plan_ot_id AS ot_id,
       o.folio       AS ot_folio,
       nc.activo_id,
       a.patente,
       a.codigo,
       (array_agg(nc.id ORDER BY nc.created_at))[1] AS nc_id,
       count(*)::integer AS n_ncs,
       CASE WHEN count(*) = 1 THEN min(nc.descripcion)
            ELSE (count(*) || ' NC: ') || string_agg(nc.descripcion, ' · ' ORDER BY nc.created_at)
       END AS descripcion,
       (array_agg(nc.severidad ORDER BY (CASE nc.severidad
            WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END)))[1] AS severidad,
       string_agg(DISTINCT nc.grupo_trabajo::text, ', ') AS grupo_trabajo,
       sum(nc.horas_estimadas)      AS horas_estimadas,
       max(nc.tiempo_estimado_dias) AS tiempo_estimado_dias
  FROM no_conformidades nc
  JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
  JOIN activos a         ON a.id = nc.activo_id
 WHERE nc.plan_ot_id IS NOT NULL
   AND nc.estado_planificacion::text = 'planificada'
   AND COALESCE(nc.resuelto, false) = false
   -- [MIG259] abierta = igual que en MIG256/257, no solo creada/asignada
   AND o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                        'no_ejecutada','cancelada','cerrada')
   -- [MIG259] antes bastaba UN día en cualquier semana pasada para que la OT
   -- desapareciera de aquí para siempre. Ahora solo la esconde si ya está en la
   -- semana en curso o en una futura.
   AND NOT EXISTS (
        SELECT 1
          FROM taller_plan_semanal_ots p
          JOIN taller_planes_semanales ps ON ps.id = p.plan_semanal_id
         WHERE p.ot_id = nc.plan_ot_id
           AND COALESCE(p.estado_plan, 'planificada') <> 'cancelada'
           AND ps.fecha_inicio_semana >= date_trunc('week', CURRENT_DATE)::date)
 GROUP BY nc.plan_ot_id, o.folio, nc.activo_id, a.patente, a.codigo;

COMMENT ON VIEW public.v_nc_ot_por_agendar IS
    'NC planificadas cuya OT correctiva todavía no está en la semana en curso ni en una futura. MIG209 + MIG259.';

GRANT SELECT ON public.v_nc_ot_por_agendar TO authenticated;


-- Planificar TODAS las NC del equipo: reutiliza la OT correctiva abierta con el
-- mismo criterio de MIG256, no solo si está en creada/asignada.
CREATE OR REPLACE FUNCTION public.fn_planificar_nc_equipo(p_activo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user    UUID := auth.uid();
    v_act     RECORD;
    v_contrato UUID;
    v_faena    UUID;
    v_ot      UUID;
    v_reusa   BOOLEAN := false;
    v_folio   VARCHAR;
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
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    IF v_n = 0 THEN
        RETURN jsonb_build_object('n_ncs', 0, 'mensaje', 'El equipo no tiene NC pendientes de planificar.');
    END IF;

    SELECT id, patente, codigo INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- [MIG259] Mismo criterio que al planificar la semana: una sola OT
    -- correctiva abierta por equipo. Antes exigía creada/asignada y con la OT
    -- en ejecución o pausada abría otra, duplicando el trabajo.
    v_ot := fn_ot_abierta_reutilizable(p_activo_id, 'correctivo'::tipo_ot_enum, NULL);

    IF v_ot IS NOT NULL THEN
        v_reusa := true;
        UPDATE ordenes_trabajo
           SET observaciones = COALESCE(observaciones || E'\n', '') || v_lista,
               prioridad = CASE WHEN fn_prioridad_rank(
                                    (CASE v_sev_max WHEN 'critica' THEN 'urgente'
                                                    WHEN 'alta'    THEN 'alta'
                                                    ELSE 'normal' END)::prioridad_enum)
                                  > fn_prioridad_rank(prioridad)
                                THEN (CASE v_sev_max WHEN 'critica' THEN 'urgente'
                                                     WHEN 'alta'    THEN 'alta'
                                                     ELSE 'normal' END)::prioridad_enum
                                ELSE prioridad END,
               updated_at = NOW()
         WHERE id = v_ot
        RETURNING folio INTO v_folio;
    ELSE
        -- [MIG253] El contrato ya no traba: cascada Sugerencias GPS > último
        -- arriendo > contrato interno.
        v_contrato := fn_contrato_para_ot(p_activo_id);
        v_faena    := fn_faena_para_ot(p_activo_id);
        IF v_contrato IS NULL OR v_faena IS NULL THEN
            RAISE EXCEPTION 'No hay contrato/faena interna configurada para abrir la OT de %',
                COALESCE(v_act.patente, v_act.codigo);
        END IF;

        INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by)
        VALUES ('correctivo'::tipo_ot_enum, v_contrato, v_faena, p_activo_id,
            (CASE v_sev_max WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END)::prioridad_enum,
            'creada'::estado_ot_enum,
            'Correctivo por ' || v_n || ' NC del equipo ' || COALESCE(v_act.patente, v_act.codigo) || E':\n' || v_lista ||
            COALESCE(E'\nGrupo: ' || v_grupos, '') ||
            COALESCE(' · ' || v_horas || ' h', ''),
            true, v_user)
        RETURNING id, folio INTO v_ot, v_folio;
    END IF;

    UPDATE no_conformidades
       SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
     WHERE activo_id = p_activo_id
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    RETURN jsonb_build_object('ot_id', v_ot, 'folio', v_folio, 'n_ncs', v_n,
        'ot_reutilizada', v_reusa,
        'mensaje', CASE WHEN v_reusa
            THEN v_n || ' NC sumadas a la OT abierta ' || v_folio || ' (no se duplicó).'
            ELSE 'OT ' || v_folio || ' creada con ' || v_n || ' NC.' END);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_planificar_nc_equipo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_planificar_nc_equipo(UUID) TO authenticated;


-- Planificar UNA NC: también se cuelga de la OT correctiva abierta si existe.
CREATE OR REPLACE FUNCTION public.fn_planificar_nc(p_nc_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_act  RECORD;
    v_contrato UUID;
    v_faena    UUID;
    v_ot   UUID;
    v_folio VARCHAR;
    v_reusa BOOLEAN := false;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT * INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'NC % no existe', p_nc_id; END IF;
    IF v_nc.plan_ot_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', v_nc.plan_ot_id, 'mensaje', 'Ya tenía OT'); END IF;

    SELECT id, patente, codigo INTO v_act FROM activos WHERE id = v_nc.activo_id;

    -- [MIG259] Una sola OT correctiva abierta por equipo, igual que al
    -- planificar por equipo o desde el plan semanal.
    v_ot := fn_ot_abierta_reutilizable(v_nc.activo_id, 'correctivo'::tipo_ot_enum, NULL);

    IF v_ot IS NOT NULL THEN
        v_reusa := true;
        UPDATE ordenes_trabajo
           SET observaciones = COALESCE(observaciones || E'\n', '') || '• ' || v_nc.descripcion,
               updated_at = NOW()
         WHERE id = v_ot
        RETURNING folio INTO v_folio;
    ELSE
        -- [MIG253] Cascada de contrato: la falta de contrato ya no aborta.
        v_contrato := fn_contrato_para_ot(v_nc.activo_id);
        v_faena    := fn_faena_para_ot(v_nc.activo_id);
        IF v_contrato IS NULL OR v_faena IS NULL THEN
            RAISE EXCEPTION 'No hay contrato/faena interna configurada para abrir la OT de %',
                COALESCE(v_act.patente, v_act.codigo);
        END IF;

        INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by)
        VALUES ('correctivo', v_contrato, v_faena, v_nc.activo_id,
            CASE v_nc.severidad WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END,
            'creada',
            'NC de recepción: ' || v_nc.descripcion ||
            COALESCE(E'\nGrupo: ' || v_nc.grupo_trabajo, '') ||
            COALESCE(' · ' || v_nc.horas_estimadas || ' h', ''),
            true, v_user)
        RETURNING id, folio INTO v_ot, v_folio;
    END IF;

    UPDATE no_conformidades SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
    WHERE id = p_nc_id;

    RETURN jsonb_build_object('ot_id', v_ot, 'folio', v_folio, 'nc_id', p_nc_id,
        'ot_reutilizada', v_reusa);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_planificar_nc(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_planificar_nc(UUID) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_plan UUID; v_n INT; v_arrastre INT; v_ot UUID; v_nc UUID; v_activo UUID;
    v_user UUID; v_r JSONB; v_estado TEXT; v_nc_estado TEXT;
BEGIN
    -- El bloque de arrastre tiene que ver lo que hoy no se veía.
    SELECT id INTO v_plan FROM taller_planes_semanales
     WHERE fecha_inicio_semana = date_trunc('week', CURRENT_DATE)::date
     ORDER BY created_at LIMIT 1;

    IF v_plan IS NULL THEN
        RAISE NOTICE 'MIG259: no hay plan de la semana en curso; se omite el conteo de arrastre';
    ELSE
        SELECT count(*) INTO v_arrastre FROM fn_taller_ot_arrastre(v_plan);
        SELECT count(*) INTO v_n FROM ordenes_trabajo
         WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                              'no_ejecutada','cancelada','cerrada');
        RAISE NOTICE 'MIG259: % OT abiertas, % aparecen en «Viene de semanas anteriores»', v_n, v_arrastre;
        IF v_arrastre = 0 THEN
            RAISE WARNING 'MIG259: el bloque de arrastre salió vacío — revisar';
        END IF;
    END IF;

    -- Descartar: cancela, saca del plan y DEVUELVE las NC. Todo en un smoke que
    -- se revierte al final.
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    IF v_user IS NULL THEN RAISE NOTICE 'MIG259: sin jefe_mantenimiento para el smoke'; RETURN; END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    SELECT a.id INTO v_activo FROM activos a WHERE a.fecha_baja IS NULL LIMIT 1;

    INSERT INTO no_conformidades (activo_id, tipo, descripcion, fecha_evento, severidad,
        origen, estado_planificacion, registrada_por, created_by)
    VALUES (v_activo, 'otra', 'MIG259 smoke — NC de prueba', CURRENT_DATE, 'media',
        'manual', 'registrada', v_user, v_user)
    RETURNING id INTO v_nc;

    v_r  := fn_planificar_nc_equipo(v_activo);
    v_ot := (v_r->>'ot_id')::uuid;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'FALLO — no se pudo planificar la NC de prueba: %', v_r; END IF;

    v_r := rpc_taller_descartar_ot(v_ot, 'Smoke MIG259: ya no corresponde');
    IF (v_r->>'ncs_devueltas')::int < 1 THEN
        RAISE EXCEPTION 'FALLO — descartar no devolvió las NC a la bandeja: %', v_r;
    END IF;

    SELECT estado::text INTO v_estado FROM ordenes_trabajo WHERE id = v_ot;
    IF v_estado <> 'cancelada' THEN RAISE EXCEPTION 'FALLO — la OT no quedó cancelada (%)', v_estado; END IF;

    SELECT estado_planificacion, plan_ot_id::text INTO v_nc_estado, v_estado
      FROM no_conformidades WHERE id = v_nc;
    IF v_nc_estado NOT IN ('registrada','con_recursos') OR v_estado IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO — la NC no volvió a la bandeja (estado %, plan_ot_id %)', v_nc_estado, v_estado;
    END IF;

    -- Motivo corto: tiene que rechazarse
    BEGIN
        PERFORM rpc_taller_descartar_ot(v_ot, 'no');
        RAISE EXCEPTION 'FALLO — aceptó un motivo de 2 caracteres';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
    END;

    RAISE NOTICE 'MIG259 OK — descartar cancela la OT, la saca del plan y devuelve sus NC';
    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
