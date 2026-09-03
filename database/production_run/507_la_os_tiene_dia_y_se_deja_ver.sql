-- ============================================================================
-- MIG507 · La OS se programa con DÍA, y el taller entero la puede VER
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «cuando planifico una orden de servicio, la plataforma me debe
-- solicitar día y yo programar; hoy no pide día y el operador no puede ver la
-- orden de servicio».
--
-- LAS DOS COSAS
--  1. DÍA: taller_os gana fecha_programada. El modal de la bandeja la exige;
--     crear una OS suelta desde la OT la acepta opcional. El teléfono la
--     muestra y ordena por ella.
--  2. VISIBILIDAD: «Mi trabajo» (MIG479) muestra solo LO TUYO y solo si tu
--     cuenta está vinculada a un técnico — la cuenta compartida del taller no
--     ve nada, y así se probó hoy (OS-202609-00007-1 asignada a Felipe López:
--     perfecta en la base, invisible en el teléfono de la cuenta compartida).
--     Se agrega rpc_taller_os_abiertas: TODAS las OS abiertas del taller, de
--     solo lectura, para cualquier cuenta autenticada. El reloj sigue siendo
--     personal; ver el trabajo repartido no tiene por qué serlo.
-- ============================================================================

BEGIN;

-- ── 1 · El día de la OS ─────────────────────────────────────────────────────
ALTER TABLE taller_os
  ADD COLUMN IF NOT EXISTS fecha_programada DATE;

COMMENT ON COLUMN taller_os.fecha_programada IS
'Qué día se programó ejecutar esta OS. Lo fija quien planifica (MIG507).';

-- ── 2 · Crear OS acepta el día (firma nueva → DROP, regla MIG471) ───────────
DROP FUNCTION IF EXISTS rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT, TEXT);

CREATE FUNCTION rpc_taller_os_crear(
    p_ot_id            UUID,
    p_titulo           TEXT,
    p_nc_ids           UUID[] DEFAULT NULL,
    p_responsable_id   UUID   DEFAULT NULL,
    p_horas_estimadas  NUMERIC DEFAULT NULL,
    p_descripcion      TEXT   DEFAULT NULL,
    p_prioridad        TEXT   DEFAULT NULL,
    p_justificacion    TEXT   DEFAULT NULL,
    p_fecha_programada DATE   DEFAULT NULL
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

    -- [MIG498] La NC pertenece a esta OT por origen (ot_id) o correctiva (plan_ot_id).
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

    -- [MIG475] El techo lo pone el planificador. Pasarse se puede; callado, no.
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
                           horas_estimadas, prioridad, creada_por, justificacion_exceso,
                           fecha_programada)
    VALUES (v_folio, p_ot_id, TRIM(p_titulo), NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
            p_responsable_id, p_horas_estimadas, NULLIF(TRIM(COALESCE(p_prioridad,'')),''),
            v_user, CASE WHEN v_techo IS NOT NULL AND v_total > v_techo THEN v_just ELSE NULL END,
            p_fecha_programada)
    RETURNING id INTO v_os;

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        INSERT INTO taller_os_nc (os_id, no_conformidad_id)
        SELECT v_os, x FROM unnest(p_nc_ids) AS x
        ON CONFLICT (no_conformidad_id) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;

    IF p_responsable_id IS NOT NULL THEN
        PERFORM rpc_taller_os_asignar(v_os, p_responsable_id, 'Asignada al crear la OS', FALSE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'os_id', v_os, 'folio', v_folio,
                              'nc_asignadas', v_n,
                              'fecha_programada', p_fecha_programada,
                              'horas_plan', v_techo, 'horas_en_os', v_total,
                              'sin_techo', v_techo IS NULL,
                              'excedida', v_techo IS NOT NULL AND v_total > v_techo);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT, TEXT, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT, TEXT, DATE) TO authenticated;

-- ── 3 · El modal de la bandeja EXIGE el día ─────────────────────────────────
DROP FUNCTION IF EXISTS rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT);

CREATE FUNCTION rpc_nc_planificar_os(
    p_nc_ids           UUID[],
    p_tecnico_ids      UUID[],
    p_horas            NUMERIC,
    p_fecha_programada DATE,
    p_titulo           TEXT DEFAULT NULL,
    p_descripcion      TEXT DEFAULT NULL,
    p_justificacion    TEXT DEFAULT NULL,
    p_externo          BOOLEAN DEFAULT FALSE,
    p_proveedor        TEXT DEFAULT NULL,
    p_motivo_externo   TEXT DEFAULT NULL
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
    IF NOT p_externo AND (p_tecnico_ids IS NULL OR array_length(p_tecnico_ids, 1) IS NULL) THEN
        RAISE EXCEPTION 'Elige quién la va a ejecutar (uno, o de a pares), o márcala como de un externo.'; END IF;
    IF p_externo AND NULLIF(TRIM(COALESCE(p_proveedor,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Di qué proveedor hace el trabajo externo.'; END IF;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Ponle el tiempo (horas): es el compromiso contra el que se mide.'; END IF;
    -- [MIG507] Planificar ES ponerle día.
    IF p_fecha_programada IS NULL THEN
        RAISE EXCEPTION 'Ponle el día: planificar la OS es programar cuándo se hace.'; END IF;
    IF p_fecha_programada < CURRENT_DATE THEN
        RAISE EXCEPTION 'El día programado (%) ya pasó.', p_fecha_programada; END IF;

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

    IF EXISTS (SELECT 1 FROM taller_os_nc x
                 JOIN taller_os o ON o.id = x.os_id AND o.estado <> 'anulada'
                WHERE x.no_conformidad_id = ANY(p_nc_ids)) THEN
        RAISE EXCEPTION 'Alguna de las NC elegidas ya está en otra Orden de Servicio.'; END IF;

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
                         CASE WHEN p_externo THEN 'Trabajo externo · ' ELSE 'Corrección NC · ' END
                         || COALESCE(v_patente, 'equipo'));

    v_res := rpc_taller_os_crear(v_ot, v_titulo, p_nc_ids,
                                 CASE WHEN p_externo THEN NULL ELSE p_tecnico_ids[1] END,
                                 p_horas, p_descripcion, NULL, p_justificacion,
                                 p_fecha_programada);
    IF NOT COALESCE((v_res->>'success')::BOOLEAN, FALSE) THEN
        RETURN v_res;
    END IF;
    v_os := (v_res->>'os_id')::UUID;

    IF p_externo THEN
        PERFORM rpc_taller_os_declarar_externo(v_os, TRUE, p_proveedor, p_motivo_externo);
    ELSE
        FOREACH v_t IN ARRAY p_tecnico_ids LOOP
            v_i := v_i + 1;
            IF v_i = 1 THEN CONTINUE; END IF;
            v_r := rpc_taller_os_asignar(v_os, v_t, 'Asignado al planificar la OS', FALSE);
            IF NULLIF(v_r->>'aviso','') IS NOT NULL THEN
                v_avisos := array_append(v_avisos, v_r->>'aviso');
            END IF;
        END LOOP;
    END IF;

    RETURN v_res || jsonb_build_object(
        'ot_id', v_ot,
        'externo', p_externo,
        'tecnicos', CASE WHEN p_externo THEN 0 ELSE array_length(p_tecnico_ids, 1) END,
        'avisos', to_jsonb(v_avisos));
END;
$$;

REVOKE ALL ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;

-- ── 4 · El teléfono muestra el día (retorno nuevo → DROP) ───────────────────
DROP FUNCTION IF EXISTS rpc_taller_mis_os();

CREATE FUNCTION rpc_taller_mis_os()
RETURNS TABLE (
    os_id           UUID,
    folio           TEXT,
    titulo          TEXT,
    descripcion     TEXT,
    estado          TEXT,
    prioridad       TEXT,
    ot_id           UUID,
    ot_folio        TEXT,
    patente         TEXT,
    equipo          TEXT,
    ncs             BIGINT,
    horas_estimadas NUMERIC,
    mis_horas       NUMERIC,
    trabajando      BOOLEAN,
    asignado_desde  TIMESTAMPTZ,
    asignado_por    TEXT,
    motivo          TEXT,
    bloqueo         TEXT,
    fecha_programada DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tec UUID := fn_taller_mi_tecnico_id();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_tec IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        o.id, o.folio::TEXT, o.titulo::TEXT, o.descripcion::TEXT,
        o.estado::TEXT, o.prioridad::TEXT,
        o.ot_id, ot.folio::TEXT, act.patente::TEXT, act.nombre::TEXT,
        (SELECT count(*) FROM taller_os_nc n WHERE n.os_id = o.id),
        o.horas_estimadas,
        COALESCE((SELECT round(sum(COALESCE(t.segundos,
                    GREATEST(0, EXTRACT(EPOCH FROM (NOW() - t.inicio))::INT)))::numeric / 3600.0, 2)
                    FROM taller_os_tiempo t
                   WHERE t.os_id = o.id AND t.tecnico_id = v_tec), 0),
        EXISTS (SELECT 1 FROM taller_os_tiempo t
                 WHERE t.os_id = o.id AND t.tecnico_id = v_tec AND t.fin IS NULL),
        a.desde,
        (SELECT up.nombre_completo::TEXT FROM usuarios_perfil up WHERE up.id = a.asignado_por),
        a.motivo::TEXT,
        CASE
            WHEN o.es_externo AND o.externo_autorizado_at IS NULL
                THEN 'Es trabajo de un externo y todavía no lo autoriza gerencia.'
            ELSE fn_taller_ot_medidores_listos(o.ot_id)
        END,
        o.fecha_programada
      FROM taller_os_asignacion a
      JOIN taller_os o        ON o.id = a.os_id
      JOIN ordenes_trabajo ot ON ot.id = o.ot_id
      JOIN activos act        ON act.id = ot.activo_id
     WHERE a.tecnico_id = v_tec
       AND a.hasta IS NULL
       AND o.estado NOT IN ('finalizada','anulada')
     ORDER BY
        EXISTS (SELECT 1 FROM taller_os_tiempo t
                 WHERE t.os_id = o.id AND t.tecnico_id = v_tec AND t.fin IS NULL) DESC,
        -- [MIG507] Primero lo de hoy y lo atrasado; el día manda sobre la prioridad.
        o.fecha_programada ASC NULLS LAST,
        CASE lower(COALESCE(o.prioridad,'media'))
            WHEN 'critica' THEN 0 WHEN 'crítica' THEN 0
            WHEN 'alta' THEN 1 WHEN 'media' THEN 2 WHEN 'baja' THEN 3 ELSE 4 END ASC,
        a.desde ASC;
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_mis_os() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_mis_os() TO authenticated;

-- ── 5 · TODAS las OS abiertas, de solo lectura, para cualquier cuenta ───────
CREATE OR REPLACE FUNCTION rpc_taller_os_abiertas()
RETURNS TABLE (
    os_id            UUID,
    folio            TEXT,
    titulo           TEXT,
    estado           TEXT,
    patente          TEXT,
    equipo           TEXT,
    ot_folio         TEXT,
    responsable      TEXT,
    fecha_programada DATE,
    horas_estimadas  NUMERIC,
    ncs              BIGINT,
    es_externo       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT o.id, o.folio::TEXT, o.titulo::TEXT, o.estado::TEXT,
           act.patente::TEXT, act.nombre::TEXT, ot.folio::TEXT,
           tt.nombre::TEXT,
           o.fecha_programada, o.horas_estimadas,
           (SELECT count(*) FROM taller_os_nc n WHERE n.os_id = o.id),
           COALESCE(o.es_externo, FALSE)
      FROM taller_os o
      JOIN ordenes_trabajo ot ON ot.id = o.ot_id
      JOIN activos act        ON act.id = ot.activo_id
      LEFT JOIN taller_tecnicos tt ON tt.id = o.responsable_id
     WHERE auth.uid() IS NOT NULL
       AND o.estado NOT IN ('finalizada','anulada')
     ORDER BY o.fecha_programada ASC NULLS LAST, o.created_at ASC;
$$;

REVOKE ALL ON FUNCTION rpc_taller_os_abiertas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_os_abiertas() TO authenticated;

COMMENT ON FUNCTION rpc_taller_os_abiertas() IS
'Las OS abiertas del taller, de solo lectura, para cualquier cuenta autenticada. '
'Ver el trabajo repartido no es personal; mover el reloj sí (MIG507).';

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    PERFORM fecha_programada FROM taller_os LIMIT 1;
    FOR v_n IN SELECT 1 LOOP NULL; END LOOP;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname IN
       ('rpc_taller_os_crear','rpc_nc_planificar_os','rpc_taller_mis_os','rpc_taller_os_abiertas');
    IF v_n <> 4 THEN RAISE EXCEPTION 'FALLO: quedaron % funciones (esperadas 4, una firma cada una)', v_n; END IF;

    SELECT count(*) INTO v_n FROM taller_os WHERE estado NOT IN ('finalizada','anulada');
    RAISE NOTICE 'MIG507 OK · OS abiertas visibles para el taller: %', v_n;
END
$mig$;

COMMIT;
