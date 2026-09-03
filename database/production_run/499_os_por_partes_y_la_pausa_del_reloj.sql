-- ============================================================================
-- MIG499 · El equipo se ataca por partes: varias OS, la pausa y el externo
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, afinando el flujo NC → OS (MIG498):
--   · «Un equipo puede ser atacado por varios, o solo una pareja, o por más de
--     una pareja, o sea se puede atacar en diferentes OS. Incluso puede existir
--     una OS para un externo.»
--   · «¿Puede el reloj estar pausado también?» — al asignar a un técnico a otra
--     OS, hoy se le SACA de la anterior (asignación cerrada). Manuel quiere que
--     el trabajo anterior quede PAUSADO, no perdido.
--
-- QUÉ CAMBIA
--   1. v_nc_recepcion gana os_id/os_folio: la bandeja puede decir qué NC ya
--      está en una OS (y no ofrecerla de nuevo — una NC vive en UNA OS).
--   2. La asignación deja de ser exclusiva: se BORRA el índice único
--      uq_os_asig_vigente_por_persona y rpc_taller_os_asignar ya no cierra la
--      asignación anterior — solo PAUSA el reloj que esté corriendo. El bono
--      sigue protegido por lo que siempre lo protegió: una persona tiene UN
--      reloj corriendo a la vez (uq del tramo abierto), y arrancar otra OS
--      cierra sola la anterior (MIG473).
--   3. rpc_nc_planificar_os acepta OS de EXTERNO: sin técnicos nuestros, con
--      proveedor y motivo; se declara externa al crearla (gerencia la autoriza,
--      MIG477) y no paga bono.
-- ============================================================================

BEGIN;

-- ── 1 · La bandeja sabe en qué OS está cada NC ──────────────────────────────
-- Igual que MIG405: se parcha la definición viva en vez de transcribirla.
DO $r$
DECLARE v_def TEXT; v_pos INT; v_nueva TEXT;
BEGIN
    SELECT pg_get_viewdef('public.v_nc_recepcion'::regclass, true) INTO v_def;

    IF position('os_folio' IN v_def) > 0 THEN
        RAISE NOTICE 'v_nc_recepcion ya expone la OS. Nada que hacer.';
        RETURN;
    END IF;

    -- El FROM de primer nivel: pg_get_viewdef lo sangra con tres espacios.
    v_pos := position(E'\n   FROM ' IN v_def);
    IF v_pos = 0 THEN
        RAISE EXCEPTION 'No se encontró el FROM de primer nivel en v_nc_recepcion: revisar a mano';
    END IF;

    v_nueva := 'CREATE OR REPLACE VIEW public.v_nc_recepcion AS '
            || substr(v_def, 1, v_pos - 1)
            || ',' || E'\n    (SELECT x.os_id FROM taller_os_nc x'
            ||         E'\n       JOIN taller_os o ON o.id = x.os_id AND o.estado <> ''anulada'''
            ||         E'\n      WHERE x.no_conformidad_id = nc.id LIMIT 1) AS os_id,'
            || E'\n    (SELECT o.folio FROM taller_os_nc x'
            ||         E'\n       JOIN taller_os o ON o.id = x.os_id AND o.estado <> ''anulada'''
            ||         E'\n      WHERE x.no_conformidad_id = nc.id LIMIT 1) AS os_folio'
            || substr(v_def, v_pos);
    EXECUTE v_nueva;
    RAISE NOTICE 'v_nc_recepcion ahora expone os_id y os_folio';
END $r$;

-- ── 2 · Asignar ya no saca: pausa ───────────────────────────────────────────
-- Un técnico puede tener VARIAS OS asignadas (las ve todas en su teléfono);
-- lo que sigue siendo único es el reloj corriendo.
DROP INDEX IF EXISTS uq_os_asig_vigente_por_persona;

CREATE OR REPLACE FUNCTION rpc_taller_os_asignar(
    p_os_id      UUID,
    p_tecnico_id UUID,
    p_motivo     TEXT DEFAULT NULL,
    p_arrancar   BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_tramo RECORD;
    v_est   TEXT;
    v_aviso TEXT := NULL;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Mover a alguien de un trabajo a otro es del jefe de taller. '
                        'El operador ejecuta lo que le asignaron.';
    END IF;

    SELECT estado INTO v_est FROM taller_os WHERE id = p_os_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_est IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %: no se le puede asignar a nadie.', v_est;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM taller_tecnicos WHERE id = p_tecnico_id AND COALESCE(activo, TRUE)) THEN
        RAISE EXCEPTION 'Ese técnico no existe o está inactivo.';
    END IF;

    -- ¿Ya estaba en esta misma OS? No se hace nada.
    IF EXISTS (SELECT 1 FROM taller_os_asignacion
                WHERE tecnico_id = p_tecnico_id AND os_id = p_os_id AND hasta IS NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    -- [MIG499] La asignación anterior NO se cierra: el trabajo queda PAUSADO y
    -- sigue en el teléfono del técnico. Lo único que se corta es el reloj que
    -- tenga corriendo — las mismas dos horas no se pueden cobrar en dos OS.
    SELECT t.id, t.os_id, o.folio INTO v_tramo
      FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
     WHERE t.tecnico_id = p_tecnico_id AND t.fin IS NULL;

    IF v_tramo.id IS NOT NULL THEN
        UPDATE taller_os_tiempo
           SET fin = NOW(),
               segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
               cerrado_por_sistema = TRUE,
               motivo_cierre = 'El jefe le asignó otra OS: esta quedó pausada'
         WHERE id = v_tramo.id;

        UPDATE taller_os o SET estado = 'pausada', updated_at = NOW()
         WHERE o.id = v_tramo.os_id AND o.estado = 'en_ejecucion'
           AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo t WHERE t.os_id = o.id AND t.fin IS NULL);

        v_aviso := 'Su reloj en ' || v_tramo.folio || ' quedó pausado (sigue asignado ahí).';
    END IF;

    INSERT INTO taller_os_asignacion (os_id, tecnico_id, asignado_por, motivo)
    VALUES (p_os_id, p_tecnico_id, v_user, NULLIF(TRIM(COALESCE(p_motivo,'')),''));

    -- El responsable de la OS es el último al que el jefe se la encargó.
    UPDATE taller_os SET responsable_id = p_tecnico_id, updated_at = NOW() WHERE id = p_os_id;

    -- El jefe puede además dejarlo andando: «ándate a esto ahora».
    IF p_arrancar THEN
        INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
        VALUES (p_os_id, p_tecnico_id, v_user);
        UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'aviso', v_aviso, 'arrancada', p_arrancar);
END;
$$;

-- ── 3 · La OS de un externo, desde el mismo modal ───────────────────────────
-- La firma cambia (parámetros nuevos): se borra la vieja para no dejar dos
-- funciones con DEFAULT conviviendo — «function is not unique», la regla de
-- MIG471.
DROP FUNCTION IF EXISTS rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION rpc_nc_planificar_os(
    p_nc_ids         UUID[],
    p_tecnico_ids    UUID[],
    p_horas          NUMERIC,
    p_titulo         TEXT DEFAULT NULL,
    p_descripcion    TEXT DEFAULT NULL,
    p_justificacion  TEXT DEFAULT NULL,
    p_externo        BOOLEAN DEFAULT FALSE,
    p_proveedor      TEXT DEFAULT NULL,
    p_motivo_externo TEXT DEFAULT NULL
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
    -- [MIG499] La OS de un externo no lleva técnicos nuestros; una interna sí.
    IF NOT p_externo AND (p_tecnico_ids IS NULL OR array_length(p_tecnico_ids, 1) IS NULL) THEN
        RAISE EXCEPTION 'Elige quién la va a ejecutar (uno, o de a pares), o márcala como de un externo.'; END IF;
    IF p_externo AND NULLIF(TRIM(COALESCE(p_proveedor,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Di qué proveedor hace el trabajo externo.'; END IF;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Ponle el tiempo (horas): es el compromiso contra el que se mide.'; END IF;

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
                                 p_horas, p_descripcion, NULL, p_justificacion);
    IF NOT COALESCE((v_res->>'success')::BOOLEAN, FALSE) THEN
        RETURN v_res;
    END IF;
    v_os := (v_res->>'os_id')::UUID;

    IF p_externo THEN
        -- Declarada al crearla; la autoriza gerencia y hasta entonces no
        -- arranca (MIG477). No paga bono ni ocupa técnicos del taller.
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

REVOKE ALL ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;

-- ── Verificación + diagnóstico aljibes ──────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    PERFORM os_id, os_folio FROM v_nc_recepcion LIMIT 1;
    RAISE NOTICE 'v_nc_recepcion publica os_id/os_folio';

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_nc_planificar_os';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_nc_planificar_os quedó con % firmas', v_n; END IF;
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_os_asignar';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_os_asignar quedó con % firmas', v_n; END IF;

    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='uq_os_asig_vigente_por_persona') THEN
        RAISE EXCEPTION 'FALLO: el índice de asignación exclusiva sigue vivo';
    END IF;
    RAISE NOTICE 'asignación múltiple habilitada; el reloj corriendo sigue siendo único';

    -- Diagnóstico del cuenta litros: a cuántos equipos se les pide, y si las
    -- OT abiertas de taller incluyen algún aljibe (Manuel no lo vio en pantalla).
    SELECT count(*) INTO v_n FROM activos WHERE tipo_equipamiento = 'aljibe_combustible';
    RAISE NOTICE 'equipos marcados aljibe_combustible (se les pide cuenta litros): %', v_n;
    FOR r IN
        SELECT ot.folio, a.patente, a.tipo_equipamiento
          FROM ordenes_trabajo ot JOIN activos a ON a.id = ot.activo_id
         WHERE ot.estado IN ('asignada','en_ejecucion','pausada')
           AND a.tipo_equipamiento = 'aljibe_combustible'
         LIMIT 5
    LOOP
        RAISE NOTICE '   OT abierta de aljibe: % · %', r.folio, r.patente;
    END LOOP;
END
$mig$;

COMMIT;
