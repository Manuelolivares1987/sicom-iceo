-- ============================================================================
-- MIG498 · La Orden de Servicio nace de las NC, en la bandeja del jefe
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, cerrando el flujo completo: «después que ha asignado recursos a
-- la NC de repuestos, debe seleccionar cada NC asociada al equipo y ahí debe
-- abrirse un modal de planificación de la orden de servicio, en donde debe
-- colocar qué persona la va a ejecutar (puede ser de a pares) y cuánto tiempo
-- se debe demorar. [...] esa planificación debe llegar a la aplicación de
-- terreno».
--
-- LO QUE YA EXISTE (MIG473-479) Y NO SE REESCRIBE
--   · taller_os + taller_os_nc (una NC vive en UNA OS), reloj por persona.
--   · rpc_taller_os_crear (techo de horas del planificador, MIG475).
--   · rpc_taller_os_asignar: varios técnicos por OS («de a pares»), sacando a
--     cada uno de donde estaba, con el reloj cerrado y el motivo escrito.
--   · rpc_taller_mis_os (MIG479): la OS llega al teléfono del mecánico.
--
-- LO QUE FALTABA
--   1. rpc_taller_os_crear exigía que las NC fueran de la OT que se le pasa,
--      comparando SOLO nc.ot_id (la OT de origen, la revisión). Pero el trabajo
--      correctivo cuelga de nc.plan_ot_id (la OT correctiva). Resultado: no se
--      podía armar una OS con NC ya planificadas. Se acepta cualquiera de las
--      dos.
--   2. Un RPC de una pieza para el modal de la bandeja: asegura la OT
--      correctiva (reutilizando la abierta, MIG259), crea la OS con las NC
--      seleccionadas y asigna a los técnicos elegidos.
-- ============================================================================

BEGIN;

-- ── 1 · La OS acepta NC de la OT de origen O de la correctiva ───────────────
-- Mismo cuerpo de MIG475; cambia solo el chequeo de pertenencia.
CREATE OR REPLACE FUNCTION rpc_taller_os_crear(
    p_ot_id           UUID,
    p_titulo          TEXT,
    p_nc_ids          UUID[] DEFAULT NULL,
    p_responsable_id  UUID   DEFAULT NULL,
    p_horas_estimadas NUMERIC DEFAULT NULL,
    p_descripcion     TEXT   DEFAULT NULL,
    p_prioridad       TEXT   DEFAULT NULL,
    p_justificacion   TEXT   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_os    UUID;
    v_folio TEXT;
    v_n     INT := 0;
    v_ajena TEXT;
    v_techo NUMERIC; v_usadas NUMERIC; v_total NUMERIC;
    v_just  TEXT := NULLIF(TRIM(COALESCE(p_justificacion,'')),'');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Armar una Orden de Servicio es de la jefatura de taller o planificación.';
    END IF;
    IF length(COALESCE(TRIM(p_titulo),'')) < 4 THEN
        RAISE EXCEPTION 'Ponle un título a la OS: es lo que el mecánico va a leer en su teléfono.';
    END IF;

    -- [MIG498] Una NC pertenece a esta OT si es su OT de ORIGEN (nc.ot_id, la
    -- revisión donde salió) o su OT CORRECTIVA (nc.plan_ot_id, donde se
    -- resuelve). Antes solo se miraba la primera y las NC ya planificadas no
    -- podían entrar a una OS.
    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        SELECT string_agg(nc.id::TEXT, ', ') INTO v_ajena
          FROM no_conformidades nc
         WHERE nc.id = ANY(p_nc_ids)
           AND nc.ot_id      IS DISTINCT FROM p_ot_id
           AND nc.plan_ot_id IS DISTINCT FROM p_ot_id;
        IF v_ajena IS NOT NULL THEN
            RAISE EXCEPTION 'Hay no conformidades que no son de esta OT. Una OS resuelve trabajo de un solo equipo.';
        END IF;
    END IF;

    -- [MIG475] El techo lo pone el planificador. Pasarse se puede; hacerlo
    -- callado, no. Si no puso horas, no hay techo que exigir: se avisa, pero no
    -- se inventa un número.
    v_techo  := fn_taller_ot_horas_plan(p_ot_id);
    v_usadas := fn_taller_ot_horas_os(p_ot_id);
    v_total  := v_usadas + COALESCE(p_horas_estimadas, 0);

    IF v_techo IS NOT NULL AND v_total > v_techo AND v_just IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'requiere_justificacion', TRUE,
            'horas_plan', v_techo, 'horas_en_os', v_usadas,
            'horas_con_esta', v_total,
            'motivo', format('El planificador le dio %s h a esta visita y con esta OS las Órdenes '
                             || 'de Servicio suman %s h. Se puede, pero escribe por qué: queda con '
                             || 'tu nombre.', v_techo, v_total));
    END IF;

    v_folio := fn_taller_os_folio(p_ot_id);

    INSERT INTO taller_os (folio, ot_id, titulo, descripcion, responsable_id,
                           horas_estimadas, prioridad, creada_por, justificacion_exceso)
    VALUES (v_folio, p_ot_id, TRIM(p_titulo), NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
            p_responsable_id, p_horas_estimadas, NULLIF(TRIM(COALESCE(p_prioridad,'')),''),
            v_user, CASE WHEN v_techo IS NOT NULL AND v_total > v_techo THEN v_just ELSE NULL END)
    RETURNING id INTO v_os;

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        INSERT INTO taller_os_nc (os_id, no_conformidad_id)
        SELECT v_os, x FROM unnest(p_nc_ids) AS x
        ON CONFLICT (no_conformidad_id) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;

    -- Si esta OS asigna responsable, es una decisión del jefe y queda escrita.
    IF p_responsable_id IS NOT NULL THEN
        PERFORM rpc_taller_os_asignar(v_os, p_responsable_id, 'Asignada al crear la OS', FALSE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'os_id', v_os, 'folio', v_folio,
                              'nc_asignadas', v_n,
                              'horas_plan', v_techo, 'horas_en_os', v_total,
                              'sin_techo', v_techo IS NULL,
                              'excedida', v_techo IS NOT NULL AND v_total > v_techo);
END;
$$;

-- ── 2 · El modal de la bandeja, en una sola llamada ─────────────────────────
CREATE OR REPLACE FUNCTION rpc_nc_planificar_os(
    p_nc_ids        UUID[],
    p_tecnico_ids   UUID[],
    p_horas         NUMERIC,
    p_titulo        TEXT DEFAULT NULL,
    p_descripcion   TEXT DEFAULT NULL,
    p_justificacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_activo   UUID; v_n_act INT; v_patente TEXT;
    v_sin_plan INT;  v_n_ot INT; v_ot UUID;
    v_titulo   TEXT;
    v_res      JSONB; v_os UUID;
    v_t        UUID; v_i INT := 0; v_r JSONB;
    v_avisos   TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Planificar una Orden de Servicio es de la jefatura de taller o planificación.';
    END IF;
    IF p_nc_ids IS NULL OR array_length(p_nc_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Elige al menos una no conformidad.'; END IF;
    IF p_tecnico_ids IS NULL OR array_length(p_tecnico_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Elige quién la va a ejecutar (uno o de a pares).'; END IF;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Ponle el tiempo (horas): el operador trabaja contra ese número.'; END IF;

    -- Un solo equipo por OS.
    SELECT count(DISTINCT nc.activo_id) INTO v_n_act
      FROM no_conformidades nc WHERE nc.id = ANY(p_nc_ids);
    IF v_n_act <> 1 THEN
        RAISE EXCEPTION 'Las NC elegidas son de % equipos distintos: una OS resuelve trabajo de UN equipo.', v_n_act;
    END IF;
    SELECT nc.activo_id INTO v_activo FROM no_conformidades nc WHERE nc.id = ANY(p_nc_ids) LIMIT 1;
    SELECT COALESCE(a.patente, a.codigo) INTO v_patente FROM activos a WHERE a.id = v_activo;

    IF EXISTS (SELECT 1 FROM no_conformidades
                WHERE id = ANY(p_nc_ids) AND estado_planificacion IN ('resuelta','descartada')) THEN
        RAISE EXCEPTION 'Hay NC ya resueltas o descartadas entre las elegidas.'; END IF;

    -- Una NC vive en UNA OS (uq_os_nc_una_sola_os): decirlo antes, con nombre.
    IF EXISTS (SELECT 1 FROM taller_os_nc x
                 JOIN taller_os o ON o.id = x.os_id AND o.estado <> 'anulada'
                WHERE x.no_conformidad_id = ANY(p_nc_ids)) THEN
        RAISE EXCEPTION 'Alguna de las NC elegidas ya está en otra Orden de Servicio.'; END IF;

    -- Asegurar la OT correctiva. fn_planificar_nc_equipo reutiliza la abierta
    -- del equipo (MIG259) y planifica TODAS las pendientes — que es exactamente
    -- la consolidación que ya rige: una OT correctiva por equipo.
    SELECT count(*) INTO v_sin_plan
      FROM no_conformidades WHERE id = ANY(p_nc_ids) AND plan_ot_id IS NULL;
    IF v_sin_plan > 0 THEN
        PERFORM fn_planificar_nc_equipo(v_activo);
    END IF;

    SELECT count(DISTINCT plan_ot_id) INTO v_n_ot
      FROM no_conformidades WHERE id = ANY(p_nc_ids);
    IF v_n_ot <> 1 OR EXISTS (SELECT 1 FROM no_conformidades
                               WHERE id = ANY(p_nc_ids) AND plan_ot_id IS NULL) THEN
        RAISE EXCEPTION 'Las NC elegidas quedaron en OT correctivas distintas: planifícalas por separado.';
    END IF;
    SELECT plan_ot_id INTO v_ot FROM no_conformidades WHERE id = ANY(p_nc_ids) LIMIT 1;

    v_titulo := COALESCE(NULLIF(TRIM(COALESCE(p_titulo,'')),''),
                         'Corrección NC · ' || COALESCE(v_patente, 'equipo'));

    -- La OS, con el primer técnico como responsable. Si el techo del
    -- planificador exige justificación, la respuesta se devuelve tal cual y el
    -- modal la pide — nada se crea a medias.
    v_res := rpc_taller_os_crear(v_ot, v_titulo, p_nc_ids, p_tecnico_ids[1],
                                 p_horas, p_descripcion, NULL, p_justificacion);
    IF NOT COALESCE((v_res->>'success')::BOOLEAN, FALSE) THEN
        RETURN v_res;
    END IF;
    v_os := (v_res->>'os_id')::UUID;

    -- Los demás técnicos («de a pares»). Asignar saca a cada uno de donde
    -- estaba, con su reloj cerrado y el motivo escrito — regla de MIG474.
    FOREACH v_t IN ARRAY p_tecnico_ids LOOP
        v_i := v_i + 1;
        IF v_i = 1 THEN CONTINUE; END IF;
        v_r := rpc_taller_os_asignar(v_os, v_t, 'Asignado al planificar la OS', FALSE);
        IF NULLIF(v_r->>'aviso','') IS NOT NULL THEN
            v_avisos := array_append(v_avisos, v_r->>'aviso');
        END IF;
    END LOOP;

    RETURN v_res || jsonb_build_object(
        'ot_id', v_ot,
        'tecnicos', array_length(p_tecnico_ids, 1),
        'avisos', to_jsonb(v_avisos));
END;
$$;

REVOKE ALL ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_os_crear';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_os_crear quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_nc_planificar_os';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_nc_planificar_os quedó con % firmas', v_n; END IF;

    -- El chequeo nuevo no puede haber roto la creación normal: el cuerpo debe
    -- mencionar plan_ot_id.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='rpc_taller_os_crear'
                      AND p.prosrc LIKE '%plan_ot_id%') THEN
        RAISE EXCEPTION 'FALLO: rpc_taller_os_crear no quedó con el chequeo de plan_ot_id';
    END IF;

    RAISE NOTICE 'rpc_nc_planificar_os listo: NC → OT correctiva (reutilizada) → OS con técnicos y horas';
END
$mig$;

COMMIT;
