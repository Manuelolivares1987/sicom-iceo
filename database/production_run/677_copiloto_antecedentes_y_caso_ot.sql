-- 677 — El Copiloto entra a la OT y aprende del cierre, sin gastar IA (Manuel 08-11-2026,
-- informe «Mejor copiloto IA para taller»).
--
-- Lo que hace el mercado (Snap-on, Penske, ServiceMax, MaintainX): el asistente vive DENTRO de
-- la OT, muestra «lo que esta flota ya hizo» con este síntoma, y aprende de cada OT cerrada.
-- El Copiloto de SICOM era un chat aparte: 44 consultas y 6 casos en dos meses, porque el caso
-- sólo nacía si el mecánico cerraba una conversación del chat.
--
--   1. rpc_copiloto_antecedentes_ot(ot): antecedentes para la tarjeta de la OT, sólo SQL:
--      casos confirmados parecidos (mismo equipo > mismo modelo > texto, con la búsqueda que ya
--      usa el chat) + los últimos trabajos del historial del equipo. Cero llamadas a la IA.
--   2. rpc_copiloto_caso_desde_ot(ot, sintoma, causa, reparacion): al finalizar la OT el
--      mecánico confirma «qué encontró y qué hizo» (el borrador sale de la misma OT) y nace un
--      caso resuelto que el Copiloto cita desde la próxima consulta. El jefe lo valida con la
--      función que ya existía (rpc_copiloto_caso_validar).

CREATE OR REPLACE FUNCTION public.rpc_copiloto_antecedentes_ot(p_ot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_activo UUID;
    v_texto  TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_activo IS NULL THEN RETURN jsonb_build_object('casos', '[]'::jsonb, 'historial', '[]'::jsonb); END IF;

    -- El «síntoma» de la OT: sus NO OK y sus NC abiertas.
    SELECT string_agg(t, ' ') INTO v_texto FROM (
        SELECT COALESCE(ii.descripcion_custom, ti.descripcion) || ' ' || COALESCE(ii.observacion, '') AS t
          FROM checklist_v2_instance ci
          JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
          LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ci.ot_id = p_ot_id AND (ii.resultado = 'no_ok' OR ii.observado)
        UNION ALL
        SELECT n.descripcion FROM no_conformidades n
         WHERE (n.ot_id = p_ot_id OR n.plan_ot_id = p_ot_id) AND NOT n.resuelto
        LIMIT 40) s;

    RETURN jsonb_build_object(
        'sintoma', left(COALESCE(v_texto, ''), 600),
        'casos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                     'equipo', c.equipo, 'mismo_equipo', c.mismo_equipo, 'mismo_modelo', c.mismo_modelo,
                     'modelo', c.modelo, 'sintoma', c.sintoma, 'causa', c.causa_raiz,
                     'reparacion', c.reparacion, 'validado', c.validado, 'fecha', c.resuelto_at::date))
              FROM rpc_copiloto_casos_similares(v_activo, COALESCE(v_texto, ''), 3) c), '[]'::jsonb),
        'historial', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT jsonb_build_object('folio', h.folio, 'fecha', h.fecha::date, 'tipo', h.tipo,
                         'trabajo', left(h.trabajo_realizado, 220), 'motivo', left(h.motivo, 120)) x
                  FROM v_historial_mantenimiento_equipo h
                 WHERE h.activo_id = v_activo AND length(COALESCE(h.trabajo_realizado, '')) > 10
                   -- el resumen automático de las OS antiguas no dice qué se hizo
                   AND h.trabajo_realizado NOT ILIKE '%trabajo(s) registrados%'
                   -- ni la revisión de papeles («SOAP vigente; Padrón…»), que no es una reparación
                   AND h.trabajo_realizado NOT ILIKE '%vigente%'
                 ORDER BY h.fecha DESC NULLS LAST LIMIT 4) s), '[]'::jsonb)
    );
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_copiloto_antecedentes_ot(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_copiloto_caso_desde_ot(
    p_ot_id uuid, p_sintoma text, p_causa text, p_reparacion text, p_sistema text DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_activo UUID;
    v_dx     UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'edit', ARRAY['administrador','jefe_mantenimiento',
            'jefe_operaciones','planificador','supervisor','tecnico_mantenimiento','operador_taller']::text[]) THEN
        RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
    END IF;
    IF LENGTH(TRIM(COALESCE(p_causa, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe la causa en una línea: es lo que le sirve al próximo mecánico';
    END IF;
    IF LENGTH(TRIM(COALESCE(p_reparacion, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe qué se hizo';
    END IF;
    SELECT activo_id INTO v_activo FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada'; END IF;

    -- Un caso por OT: si ya hay uno (abierto desde el chat o de un cierre anterior), se completa.
    SELECT id INTO v_dx FROM copiloto_diagnosticos WHERE ot_id = p_ot_id ORDER BY created_at DESC LIMIT 1;
    IF v_dx IS NULL THEN
        INSERT INTO copiloto_diagnosticos (ot_id, activo_id, usuario_id, sintoma, sistema)
        VALUES (p_ot_id, v_activo, auth.uid(),
                COALESCE(NULLIF(TRIM(COALESCE(p_sintoma, '')), ''), 'Sin síntoma descrito'),
                NULLIF(TRIM(COALESCE(p_sistema, '')), ''))
        RETURNING id INTO v_dx;
    END IF;

    UPDATE copiloto_diagnosticos
       SET estado = 'resuelto',
           sintoma = COALESCE(NULLIF(TRIM(COALESCE(p_sintoma, '')), ''), sintoma),
           sistema = COALESCE(NULLIF(TRIM(COALESCE(p_sistema, '')), ''), sistema),
           causa_raiz = TRIM(p_causa),
           reparacion = TRIM(p_reparacion),
           resuelto_por = auth.uid(),
           resuelto_at = NOW(),
           -- una corrección invalida la validación anterior
           validado_por = NULL, validado_at = NULL
     WHERE id = v_dx;
    RETURN v_dx;
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_copiloto_caso_desde_ot(uuid, text, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
