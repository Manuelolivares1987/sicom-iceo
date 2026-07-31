-- ============================================================================
-- SICOM-ICEO | 264 — Los hallazgos de la auditoría llegan al taller
-- ----------------------------------------------------------------------------
-- Manuel: «las NC de Felipe, ¿les llegan al jefe de taller?».
--
-- No llegaban. Dos agujeros:
--
-- 1) Los hallazgos NO OK de una auditoría APROBADA no generaban ninguna NC.
--    fn_resolver_auditoria_calidad solo creaba UNA NC de resumen cuando la
--    auditoría se RECHAZABA. Si Felipe aprobaba con observaciones y dejaba tres
--    puntos en NO OK, esos tres quedaban dentro del informe de salida y el
--    taller no se enteraba nunca: no entraban a la bandeja de NC, no se
--    planificaban, no llegaban a una OT correctiva.
--
-- 2) La campanita de una NC nueva (fn_nc_crear_alertas) avisa a
--    'administrador', 'supervisor' y 'planificador'. El jefe de mantenimiento
--    —que es quien tiene que repararla— NO estaba en la lista.
--
-- Esta migración:
--   · cada ítem NO OK de la auditoría genera su NC, con su foto y su
--     observación, se apruebe o se rechace. Idempotente por auditoria_item_id.
--   · el jefe de mantenimiento y el subgerente de operaciones reciben la alerta
--   · origen nuevo 'auditoria_calidad' propagado a las funciones y la vista que
--     filtran por origen (fn_planificar_nc_equipo, fn_asignar_recursos_nc_equipo
--     y v_nc_recepcion). Es el patrón de regresión que ya mordió dos veces:
--     un origen nuevo que no se agrega a esos filtros deja NC imposibles de
--     planificar.
--
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_resolver_auditoria_calidad') THEN
        RAISE EXCEPTION 'STOP — falta fn_resolver_auditoria_calidad.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_nc_crear_alertas') THEN
        RAISE EXCEPTION 'STOP — falta fn_nc_crear_alertas.';
    END IF;
END $$;


-- ── 1. De qué ítem de auditoría viene la NC ─────────────────────────────────
ALTER TABLE public.no_conformidades
    ADD COLUMN IF NOT EXISTS auditoria_item_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_nc_auditoria_item
    ON public.no_conformidades (auditoria_item_id) WHERE auditoria_item_id IS NOT NULL;

COMMENT ON COLUMN public.no_conformidades.auditoria_item_id IS
    'Ítem de auditoría de calidad que originó la NC. Único: una NC por hallazgo. MIG264.';


-- ── 2. La campanita también para quien tiene que repararlo ──────────────────
CREATE OR REPLACE FUNCTION public.fn_nc_crear_alertas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_patente TEXT;
    v_codigo  TEXT;
    v_sev     TEXT;
    v_titulo  TEXT;
    v_msg     TEXT;
    v_u       RECORD;
BEGIN
    SELECT a.patente, a.codigo INTO v_patente, v_codigo
      FROM activos a WHERE a.id = NEW.activo_id;

    v_sev := CASE LOWER(COALESCE(NEW.severidad, ''))
                  WHEN 'critica' THEN 'critical'
                  WHEN 'alta'    THEN 'warning'
                  ELSE 'info' END;

    v_titulo := 'No conformidad'
        || CASE WHEN v_patente IS NOT NULL THEN ': ' || v_patente
                WHEN v_codigo  IS NOT NULL THEN ': ' || v_codigo
                ELSE '' END;
    v_msg := COALESCE(NEW.descripcion, 'Nueva no conformidad registrada')
        || CASE WHEN NEW.origen IS NOT NULL THEN ' · origen: ' || NEW.origen ELSE '' END
        || CASE WHEN NEW.severidad IS NOT NULL THEN ' · severidad: ' || NEW.severidad ELSE '' END;

    -- [MIG264] jefe_mantenimiento y subgerente_operaciones agregados: el jefe de
    -- taller es quien repara la NC y no estaba recibiendo el aviso.
    FOR v_u IN
        SELECT id FROM usuarios_perfil
         WHERE activo = true
           AND rol IN ('administrador','supervisor','planificador',
                       'jefe_mantenimiento','subgerente_operaciones')
    LOOP
        INSERT INTO alertas (
            tipo, titulo, mensaje, severidad,
            entidad_tipo, entidad_id, destinatario_id, leida, created_at
        ) VALUES (
            'no_conformidad', v_titulo, v_msg, v_sev,
            'no_conformidad', NEW.id, v_u.id, false, NOW()
        );
    END LOOP;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Nunca bloquear la creacion de la NC por un fallo en la notificacion.
    RETURN NEW;
END;
$function$;


-- ── 3. Cada hallazgo de la auditoría se convierte en NC ─────────────────────
CREATE OR REPLACE FUNCTION public.fn_generar_nc_desde_auditoria(p_auditoria_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_aud   RECORD;
    r       RECORD;
    v_n     INT := 0;
    v_sev   TEXT;
BEGIN
    SELECT ac.*, COALESCE(ac.auditor_id, ac.iniciada_por) AS quien
      INTO v_aud FROM auditorias_calidad ac WHERE ac.id = p_auditoria_id;
    IF NOT FOUND THEN RETURN 0; END IF;

    FOR r IN
        SELECT i.* FROM auditoria_calidad_items i
         WHERE i.auditoria_id = p_auditoria_id
           AND i.resultado = 'no_ok'
           AND NOT EXISTS (SELECT 1 FROM no_conformidades nc
                            WHERE nc.auditoria_item_id = i.id)
         ORDER BY i.orden
    LOOP
        -- Un crítico no debería llegar aprobado; si llega (rechazo), va como tal.
        v_sev := CASE WHEN r.critico THEN 'critica'
                      WHEN r.obligatorio THEN 'alta'
                      ELSE 'media' END;

        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad,
            origen, foto_url, estado_planificacion, auditoria_item_id,
            registrada_por, created_by
        ) VALUES (
            v_aud.activo_id, v_aud.ot_id, 'otra',
            r.descripcion || COALESCE(' — ' || r.observacion, ''),
            CURRENT_DATE, v_sev,
            'auditoria_calidad', r.foto_url, 'registrada', r.id,
            v_aud.quien, v_aud.quien
        );
        v_n := v_n + 1;
    END LOOP;

    RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.fn_generar_nc_desde_auditoria(UUID) IS
    'Una NC por cada hallazgo NO OK de la auditoría de calidad, con su foto. Idempotente. MIG264.';

REVOKE ALL ON FUNCTION public.fn_generar_nc_desde_auditoria(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generar_nc_desde_auditoria(UUID) TO authenticated;


-- ── 4. Resolver la auditoría genera las NC ──────────────────────────────────
-- Se reescribe solo el tramo final: el resto es idéntico a MIG263.
CREATE OR REPLACE FUNCTION public.fn_resolver_auditoria_calidad(
    p_auditoria_id uuid,
    p_resultado character varying,
    p_items jsonb DEFAULT '[]'::jsonb,
    p_motivo_rechazo text DEFAULT NULL::text,
    p_observaciones text DEFAULT NULL::text,
    p_firma_url text DEFAULT NULL::text,
    p_evidencias jsonb DEFAULT '[]'::jsonb,
    p_dias_vigencia integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_aud  RECORD;
    v_item JSONB;
    v_ok INT; v_no_ok INT; v_na INT; v_tot INT;
    v_crit_fail INT;
    v_tec_ok BOOLEAN; v_doc_ok BOOLEAN;
    v_pend_crit INT;
    v_verif_id UUID;
    v_nc_id UUID;
    v_vig TIMESTAMPTZ;
    v_falta INT;
    v_falta_txt TEXT;
    v_folio TEXT;
    v_firma TEXT;
    v_ncs_hallazgos INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador') THEN
        RAISE EXCEPTION 'Solo el rol auditor_calidad puede resolver la auditoria. Rol: %', v_rol;
    END IF;
    IF p_resultado NOT IN ('aprobado','aprobado_con_observaciones','rechazado') THEN
        RAISE EXCEPTION 'Resultado invalido: %', p_resultado;
    END IF;

    SELECT * INTO v_aud FROM auditorias_calidad WHERE id = p_auditoria_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Auditoria % no existe', p_auditoria_id; END IF;
    IF v_aud.resultado <> 'pendiente' THEN
        RAISE EXCEPTION 'La auditoria ya fue resuelta (estado %).', v_aud.resultado;
    END IF;
    IF COALESCE(v_aud.anulada, false) THEN
        RAISE EXCEPTION 'La auditoria esta anulada.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM taller_ot_ejecuciones e
        JOIN ordenes_trabajo o ON o.id = e.ot_id
        WHERE o.activo_id = v_aud.activo_id AND e.ejecutor_id = v_user
    ) THEN
        RAISE EXCEPTION 'SEGREGACION DE FUNCIONES: el auditor no puede haber ejecutado '
            'trabajo en este equipo. La auditoria debe ser independiente.';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::JSONB)) LOOP
        UPDATE auditoria_calidad_items SET
            resultado = COALESCE(v_item->>'resultado', resultado),
            observacion = COALESCE(v_item->>'observacion', observacion),
            foto_url = COALESCE(v_item->>'foto_url', foto_url),
            completado_at = NOW(), completado_por = v_user
        WHERE id = (v_item->>'id')::UUID AND auditoria_id = p_auditoria_id;
    END LOOP;

    SELECT COUNT(*) FILTER (WHERE resultado='ok'),
           COUNT(*) FILTER (WHERE resultado='no_ok'),
           COUNT(*) FILTER (WHERE resultado='na'),
           COUNT(*),
           COUNT(*) FILTER (WHERE resultado='no_ok' AND critico),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='tecnica'),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='documentacion')
      INTO v_ok, v_no_ok, v_na, v_tot, v_crit_fail, v_tec_ok, v_doc_ok
      FROM auditoria_calidad_items WHERE auditoria_id = p_auditoria_id;

    -- [MIG263] Sin la foto del hallazgo no hay informe que valga.
    SELECT count(*), string_agg('• ' || descripcion || ' (' || motivo || ')', E'\n')
      INTO v_falta, v_falta_txt
      FROM (SELECT * FROM fn_auditoria_evidencia_faltante(p_auditoria_id) LIMIT 12) f;
    IF v_falta > 0 THEN
        RAISE EXCEPTION 'Falta la foto de % punto(s). El informe de salida se emite con la evidencia:%s%',
            (SELECT count(*) FROM fn_auditoria_evidencia_faltante(p_auditoria_id)),
            E'\n', v_falta_txt;
    END IF;

    IF p_resultado IN ('aprobado','aprobado_con_observaciones') THEN
        IF COALESCE(v_crit_fail,0) > 0 THEN
            RAISE EXCEPTION 'No se puede aprobar: % item(es) CRITICO(s) en no_ok.', v_crit_fail;
        END IF;
        SELECT COUNT(*) INTO v_pend_crit FROM items_diferidos
        WHERE activo_id = v_aud.activo_id AND estado='pendiente' AND diferible=false;
        IF v_pend_crit > 0 THEN
            RAISE EXCEPTION 'No se puede liberar: % pendiente(s) critico(s)/seguridad sin '
                'resolver (no diferibles).', v_pend_crit;
        END IF;

        v_firma := COALESCE(p_firma_url, v_aud.firma_auditor_url);
        IF COALESCE(length(trim(v_firma)),0) = 0 THEN
            RAISE EXCEPTION 'Falta la firma del auditor de calidad: es la que respalda el informe de salida.';
        END IF;

        v_vig := NOW() + (COALESCE(p_dias_vigencia,3) || ' days')::INTERVAL;

        SELECT 'INF-SAL-' || to_char(NOW(),'YYYYMM') || '-' ||
               lpad((COALESCE(count(*),0) + 1)::text, 4, '0')
          INTO v_folio
          FROM auditorias_calidad
         WHERE folio LIKE 'INF-SAL-' || to_char(NOW(),'YYYYMM') || '-%';

        INSERT INTO verificaciones_disponibilidad (
            activo_id, ot_id, resultado, fecha_verificacion, vigente_hasta,
            dias_vigencia, aprobado_por, aprobado_en, firma_aprobador_url,
            items_total, items_ok, items_no_ok, items_na, puntaje_total
        ) VALUES (
            v_aud.activo_id, v_aud.ot_id, 'aprobado', NOW(), v_vig,
            COALESCE(p_dias_vigencia,3), v_user, NOW(), v_firma,
            v_tot, v_ok, v_no_ok, v_na,
            CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END
        ) RETURNING id INTO v_verif_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = p_resultado::resultado_verificacion_enum,
            calidad_tecnica_ok = COALESCE(v_tec_ok,true),
            documentacion_ok = COALESCE(v_doc_ok,true),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), vigente_hasta = v_vig, dias_vigencia = COALESCE(p_dias_vigencia,3),
            verificacion_id = v_verif_id, observaciones = p_observaciones,
            firma_auditor_url = v_firma, evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            folio = v_folio, updated_at = NOW()
        WHERE id = p_auditoria_id;

        UPDATE activos SET estado = 'operativo',
            ultima_verificacion_id = v_verif_id, verificacion_vigente_hasta = v_vig,
            updated_at = NOW()
        WHERE id = v_aud.activo_id;

    ELSE  -- rechazado
        INSERT INTO no_conformidades (activo_id, ot_id, tipo, descripcion, fecha_evento,
                                      severidad, origen, created_by, registrada_por)
        VALUES (v_aud.activo_id, v_aud.ot_id, 'otra',
                'Auditoria de calidad RECHAZADA (Gate 2). ' || COALESCE(p_motivo_rechazo,''),
                CURRENT_DATE, 'alta', 'auditoria_calidad', v_user, v_user)
        RETURNING id INTO v_nc_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = 'rechazado',
            calidad_tecnica_ok = COALESCE(v_tec_ok,false),
            documentacion_ok = COALESCE(v_doc_ok,false),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), motivo_rechazo = p_motivo_rechazo,
            observaciones = p_observaciones, firma_auditor_url = COALESCE(p_firma_url, firma_auditor_url),
            evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            no_conformidad_id = v_nc_id, updated_at = NOW()
        WHERE id = p_auditoria_id;
    END IF;

    -- [MIG264] Cada hallazgo NO OK pasa al taller como NC propia, se haya
    -- aprobado o rechazado. Antes, aprobar con observaciones dejaba los
    -- hallazgos encerrados en el informe.
    v_ncs_hallazgos := fn_generar_nc_desde_auditoria(p_auditoria_id);

    RETURN jsonb_build_object('auditoria_id', p_auditoria_id, 'resultado', p_resultado,
        'verificacion_id', v_verif_id, 'no_conformidad_id', v_nc_id,
        'vigente_hasta', v_vig, 'items_ok', v_ok, 'items_no_ok', v_no_ok,
        'folio', v_folio, 'ncs_generadas', v_ncs_hallazgos);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_resolver_auditoria_calidad(uuid, character varying, jsonb, text, text, text, jsonb, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolver_auditoria_calidad(uuid, character varying, jsonb, text, text, text, jsonb, integer) TO authenticated;


-- ── 5. El origen nuevo, propagado a TODO lo que filtra por origen ───────────
-- (el patrón de regresión que ya mordió en MIG220 y MIG252)

CREATE OR REPLACE VIEW public.v_nc_recepcion AS
 SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
    nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
    nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
    nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
    ( SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
    nc.ot_id, nc.foto_url, nc.checklist_item_ref,
    ( SELECT count(*) FROM ot_recursos_solicitados r
       WHERE r.instance_item_id = nc.checklist_item_ref) AS n_recursos_operador,
    ii.observacion AS observacion_item,
    ot.folio AS ot_folio,
    up.nombre_completo AS registrada_por_nombre,
    COALESCE(nc.recobro_override, ii.cobrable_override, ti.default_cobrable,
        CASE WHEN h.atribuible_cliente IS TRUE  THEN 'cliente'::default_cobrable_enum
             WHEN h.atribuible_cliente IS FALSE THEN 'empresa'::default_cobrable_enum
             ELSE NULL::default_cobrable_enum END) AS recobro,
    CASE WHEN nc.recobro_override IS NOT NULL THEN 'jefe'::text
         WHEN ii.cobrable_override IS NOT NULL THEN 'terreno'::text
         WHEN ti.default_cobrable IS NOT NULL THEN 'pauta'::text
         WHEN h.atribuible_cliente IS NOT NULL THEN 'informe'::text
         ELSE 'sin_definir'::text END AS recobro_fuente,
    nc.recobro_nota,
    ( SELECT count(*) FROM evidencias_ot e
       WHERE e.tipo::text = 'nota'::text AND (e.ot_id = nc.ot_id OR e.ot_id = nc.plan_ot_id)) AS n_notas_operador,
    nc.recobro_informe_id, ir.folio AS recobro_informe_folio, ir.estado::text AS recobro_informe_estado,
    COALESCE(( SELECT sum(m.cantidad * COALESCE(p.costo_unitario_actual, 0::numeric))
           FROM nc_materiales m LEFT JOIN productos p ON p.id = m.producto_id
          WHERE m.no_conformidad_id = nc.id), 0::numeric) AS costo_materiales_estimado,
    nc.nota_evidencia_id
   FROM no_conformidades nc
     JOIN activos a ON a.id = nc.activo_id
     LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     LEFT JOIN informe_recepcion_hallazgos h ON h.id = nc.hallazgo_id
     LEFT JOIN ordenes_trabajo ot ON ot.id = COALESCE(nc.plan_ot_id, nc.ot_id)
     LEFT JOIN usuarios_perfil up ON up.id = nc.registrada_por
     LEFT JOIN informes_recepcion ir ON ir.id = nc.recobro_informe_id
  WHERE nc.origen::text = ANY (ARRAY['recepcion_checklist','recepcion_adhoc','inspeccion_ot',
                                     'ejecucion_ot','manual','auditoria_calidad']::text[]);

GRANT SELECT ON public.v_nc_recepcion TO authenticated;


CREATE OR REPLACE FUNCTION public.fn_asignar_recursos_nc_equipo(
    p_activo_id uuid,
    p_grupo character varying DEFAULT NULL::character varying,
    p_horas numeric DEFAULT NULL::numeric,
    p_tiempo_dias numeric DEFAULT NULL::numeric,
    p_materiales jsonb DEFAULT '[]'::jsonb
)
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
       -- [MIG252] + 'manual' · [MIG264] + 'auditoria_calidad'
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot',
                      'ejecucion_ot','manual','auditoria_calidad')
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

REVOKE ALL ON FUNCTION public.fn_asignar_recursos_nc_equipo(uuid, character varying, numeric, numeric, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_asignar_recursos_nc_equipo(uuid, character varying, numeric, numeric, jsonb) TO authenticated;


-- fn_planificar_nc_equipo: mismo cuerpo de MIG259, con el origen nuevo.
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
    v_origenes CONSTANT TEXT[] := ARRAY['recepcion_checklist','recepcion_adhoc','inspeccion_ot',
                                        'ejecucion_ot','manual','auditoria_calidad'];
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
       AND origen = ANY(v_origenes)
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    IF v_n = 0 THEN
        RETURN jsonb_build_object('n_ncs', 0, 'mensaje', 'El equipo no tiene NC pendientes de planificar.');
    END IF;

    SELECT id, patente, codigo INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- [MIG259] Una sola OT correctiva abierta por equipo.
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
       AND origen = ANY(v_origenes)
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


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_activo UUID; v_id UUID; v_r JSONB; v_item UUID;
    v_ncs INT; v_alertas_jefe INT; v_nc UUID; v_plan JSONB; v_en_vista INT;
BEGIN
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='auditor_calidad' AND activo LIMIT 1;
    IF v_user IS NULL THEN
        SELECT id INTO v_user FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    END IF;
    IF v_user IS NULL THEN RAISE NOTICE 'MIG264: sin auditor para el smoke'; RETURN; END IF;

    SELECT a.id INTO v_activo FROM activos a
     WHERE a.fecha_baja IS NULL
       AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones e
                        JOIN ordenes_trabajo o ON o.id=e.ot_id
                       WHERE o.activo_id=a.id AND e.ejecutor_id=v_user)
     LIMIT 1;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    v_r  := fn_iniciar_auditoria_calidad(v_activo, NULL);
    v_id := (v_r->>'auditoria_id')::uuid;

    UPDATE auditoria_calidad_items SET resultado='ok', foto_url='https://x/f.jpg'
     WHERE auditoria_id=v_id;
    SELECT id INTO v_item FROM auditoria_calidad_items
     WHERE auditoria_id=v_id AND critico=false ORDER BY orden LIMIT 1;
    UPDATE auditoria_calidad_items
       SET resultado='no_ok', observacion='Fuga leve detectada', foto_url='https://x/hallazgo.jpg'
     WHERE id=v_item;

    v_r := fn_resolver_auditoria_calidad(v_id, 'aprobado_con_observaciones', '[]'::jsonb,
              NULL, 'Smoke MIG264', 'https://x/firma.png', '[]'::jsonb, 3);

    IF (v_r->>'ncs_generadas')::int < 1 THEN
        RAISE EXCEPTION 'FALLO — aprobar con hallazgos no generó la NC: %', v_r;
    END IF;

    SELECT id INTO v_nc FROM no_conformidades WHERE auditoria_item_id = v_item;
    IF v_nc IS NULL THEN RAISE EXCEPTION 'FALLO — no quedó NC ligada al hallazgo'; END IF;
    IF (SELECT foto_url FROM no_conformidades WHERE id=v_nc) IS NULL THEN
        RAISE EXCEPTION 'FALLO — la NC del hallazgo perdió la foto';
    END IF;

    -- El jefe de taller recibe la campanita
    SELECT count(*) INTO v_alertas_jefe
      FROM alertas al JOIN usuarios_perfil up ON up.id = al.destinatario_id
     WHERE al.entidad_id = v_nc AND up.rol = 'jefe_mantenimiento';
    IF v_alertas_jefe = 0 THEN
        RAISE EXCEPTION 'FALLO — el jefe de mantenimiento no recibió la alerta de la NC';
    END IF;

    -- Y la NC es visible y planificable
    SELECT count(*) INTO v_en_vista FROM v_nc_recepcion WHERE id = v_nc;
    IF v_en_vista = 0 THEN RAISE EXCEPTION 'FALLO — la NC no aparece en la bandeja'; END IF;

    v_plan := fn_planificar_nc_equipo(v_activo);
    IF (v_plan->>'n_ncs')::int < 1 THEN
        RAISE EXCEPTION 'FALLO — la NC de auditoría no se pudo planificar: %', v_plan;
    END IF;

    -- Idempotencia: resolver de nuevo no duplica (la auditoría ya está resuelta,
    -- se prueba llamando directo al generador)
    IF fn_generar_nc_desde_auditoria(v_id) <> 0 THEN
        RAISE EXCEPTION 'FALLO — se duplicarían las NC del mismo hallazgo';
    END IF;

    RAISE NOTICE 'MIG264 OK — % NC generada(s) del hallazgo, con foto, notificada al jefe de taller y planificada en %',
        v_r->>'ncs_generadas', v_plan->>'folio';

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
