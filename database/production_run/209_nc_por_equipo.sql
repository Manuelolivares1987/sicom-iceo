-- ============================================================================
-- SICOM-ICEO | 209 — No Conformidades POR EQUIPO (patente)
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-09): en el taller se planifica y se piden los
-- recursos POR EQUIPO (patente), nunca NC por NC. La bandeja de NC debe operar
-- igual que la solicitud a bodega: todo el conjunto de la patente junto.
--
--   1. fn_planificar_nc_equipo(activo): toma TODAS las NC pendientes del
--      equipo y crea UNA sola OT correctiva (o reutiliza la OT correctiva
--      abierta ya creada para otras NC del mismo equipo). Prioridad = peor
--      severidad del conjunto.
--   2. fn_asignar_recursos_nc_equipo(activo, ...): grupo de trabajo para todo
--      el conjunto; horas/días y materiales quedan en la NC "ancla" (la más
--      antigua pendiente) para no duplicar totales. Los materiales aceptan
--      nc_id opcional por si se quiere amarrar a un hallazgo puntual.
--   3. v_nc_ot_por_agendar agrupada por OT: el Plan Semanal muestra UNA
--      tarjeta por equipo/OT con el total de NC, no una tarjeta por NC.
--
-- fn_planificar_nc y fn_asignar_recursos_nc (por NC) quedan vigentes por
-- compatibilidad, pero la UI ya no las usa.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Planificar el equipo completo: UNA OT con todas sus NC pendientes ─────
CREATE OR REPLACE FUNCTION fn_planificar_nc_equipo(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

    -- NC pendientes de planificar del equipo (las de la bandeja)
    SELECT count(*),
           (array_agg(severidad ORDER BY CASE severidad
                WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END))[1],
           string_agg(DISTINCT grupo_trabajo, ', '),
           sum(horas_estimadas),
           string_agg('• ' || descripcion, E'\n' ORDER BY created_at)
      INTO v_n, v_sev_max, v_grupos, v_horas, v_lista
      FROM no_conformidades
     WHERE activo_id = p_activo_id
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    IF v_n = 0 THEN
        RETURN jsonb_build_object('n_ncs', 0, 'mensaje', 'El equipo no tiene NC pendientes de planificar.');
    END IF;

    SELECT id, contrato_id, faena_id, patente, codigo INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- ¿Ya hay una OT correctiva abierta creada para NC de este equipo? Se reutiliza.
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
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    RETURN jsonb_build_object('ot_id', v_ot, 'n_ncs', v_n, 'ot_reutilizada', v_reusa);
END $$;
GRANT EXECUTE ON FUNCTION fn_planificar_nc_equipo(UUID) TO authenticated;


-- ── 2. Recursos para el conjunto del equipo ──────────────────────────────────
-- Grupo de trabajo → todas las NC pendientes. Horas/días/materiales → la NC
-- "ancla" (la más antigua), para que las sumas por OT no se dupliquen.
-- Materiales: [{producto_id?, descripcion?, cantidad, comentario?, nc_id?}]
CREATE OR REPLACE FUNCTION fn_asignar_recursos_nc_equipo(
    p_activo_id   UUID,
    p_grupo       VARCHAR DEFAULT NULL,
    p_horas       NUMERIC DEFAULT NULL,
    p_tiempo_dias NUMERIC DEFAULT NULL,
    p_materiales  JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot')
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

    -- Reemplazar los materiales del conjunto (la UI carga y guarda la lista completa)
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
END $$;
GRANT EXECUTE ON FUNCTION fn_asignar_recursos_nc_equipo(UUID, VARCHAR, NUMERIC, NUMERIC, JSONB) TO authenticated;


-- ── 3. Plan Semanal: una tarjeta por equipo/OT (no por NC) ───────────────────
DROP VIEW IF EXISTS v_nc_ot_por_agendar;
CREATE VIEW v_nc_ot_por_agendar AS
SELECT nc.plan_ot_id AS ot_id, o.folio AS ot_folio,
       nc.activo_id, a.patente, a.codigo,
       (array_agg(nc.id ORDER BY nc.created_at))[1] AS nc_id,
       count(*)::INT AS n_ncs,
       CASE WHEN count(*) = 1 THEN min(nc.descripcion)
            ELSE count(*) || ' NC: ' || string_agg(nc.descripcion, ' · ' ORDER BY nc.created_at)
       END AS descripcion,
       (array_agg(nc.severidad ORDER BY CASE nc.severidad
            WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END))[1] AS severidad,
       string_agg(DISTINCT nc.grupo_trabajo, ', ') AS grupo_trabajo,
       sum(nc.horas_estimadas) AS horas_estimadas,
       max(nc.tiempo_estimado_dias) AS tiempo_estimado_dias
FROM no_conformidades nc
JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
JOIN activos a ON a.id = nc.activo_id
WHERE nc.plan_ot_id IS NOT NULL
  AND nc.estado_planificacion = 'planificada'
  AND o.estado IN ('creada','asignada')
  AND NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots tps WHERE tps.ot_id = nc.plan_ot_id)
GROUP BY nc.plan_ot_id, o.folio, nc.activo_id, a.patente, a.codigo;
GRANT SELECT ON v_nc_ot_por_agendar TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'fn_planificar_equipo', (SELECT count(*) = 1 FROM pg_proc WHERE proname = 'fn_planificar_nc_equipo'),
    'fn_recursos_equipo',   (SELECT count(*) = 1 FROM pg_proc WHERE proname = 'fn_asignar_recursos_nc_equipo'),
    'vista_agrupada',       (SELECT position('n_ncs' IN pg_get_viewdef('v_nc_ot_por_agendar'::regclass)) > 0)
) AS resultado;

NOTIFY pgrst, 'reload schema';
