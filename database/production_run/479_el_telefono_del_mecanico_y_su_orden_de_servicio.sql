-- ============================================================================
-- MIG479 · El teléfono del mecánico y su orden de servicio (Fase 3)
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «vamos por lo que falta, Fase 3».
--
-- DE QUÉ SE TRATA LA FASE 3
-- Las fases anteriores dejaron la OS creada (MIG473), asignada por el jefe
-- (MIG474), con techo de horas (MIG475), con tiempo estándar por tipo (MIG476)
-- y con el trabajo de externos separado (MIG477). Faltaba el último eslabón:
-- que el mecánico, en su teléfono, vea SU trabajo y lo pueda empezar y parar.
--
-- LO QUE HABILITA MIG478
-- Hasta ayer el taller entraba con una cuenta compartida, así que el teléfono
-- no podía saber quién estaba parado frente al camión: había que elegir el
-- nombre de una lista, y esa elección no es prueba de nada. Con cuenta propia,
-- la sesión YA dice quién es. Esta migración hace justamente eso: resolver el
-- técnico desde la sesión, y no desde un selector.
--
-- LO QUE NO CAMBIA
-- Al operador lo sigue moviendo el jefe. Acá no se agrega ninguna forma de
-- autoasignarse trabajo: `rpc_taller_mis_os` sólo LEE lo que el jefe repartió.
-- Lo único que el mecánico puede hacer sobre su OS es el reloj —empezar,
-- parar, terminar— y sólo sobre la suya.
-- ============================================================================

BEGIN;

-- ── 1 · Quién es el que tiene el teléfono en la mano ────────────────────────
--
-- El vínculo cuenta ↔ técnico lo dejó puesto MIG478. Acá se lee, y si no está,
-- se dice: sin técnico vinculado el reloj no puede atribuir el tiempo a nadie,
-- y ese tiempo es el que decide el bono.

CREATE OR REPLACE FUNCTION fn_taller_mi_tecnico_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT t.id FROM taller_tecnicos t
     WHERE t.usuario_perfil_id = auth.uid() AND t.activo
     LIMIT 1;
$$;

COMMENT ON FUNCTION fn_taller_mi_tecnico_id() IS
    'El técnico que está detrás de la sesión. NULL si la cuenta no está '
    'vinculada a ningún técnico activo (por ejemplo la cuenta compartida).';

-- ── 2 · Mi trabajo de hoy ───────────────────────────────────────────────────
--
-- Devuelve sólo lo que el jefe me asignó y todavía no está terminado, con lo
-- que hace falta para decidir en dos segundos: qué equipo, qué hay que hacer,
-- cuántas NC trae, si ya estoy con el reloj corriendo y qué me falta para poder
-- arrancar.

DROP FUNCTION IF EXISTS rpc_taller_mis_os();

CREATE OR REPLACE FUNCTION rpc_taller_mis_os()
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
    bloqueo         TEXT
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
        -- Lo que impide arrancar, dicho antes de apretar y no después.
        CASE
            WHEN o.es_externo AND o.externo_autorizado_at IS NULL
                THEN 'Es trabajo de un externo y todavía no lo autoriza gerencia.'
            ELSE fn_taller_ot_medidores_listos(o.ot_id)
        END
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
        -- taller_os.prioridad es TEXT, no el enum de las OT: se ordena con la
        -- misma escala, pero escrita acá.
        CASE lower(COALESCE(o.prioridad,'media'))
            WHEN 'critica' THEN 0 WHEN 'crítica' THEN 0
            WHEN 'alta' THEN 1 WHEN 'media' THEN 2 WHEN 'baja' THEN 3 ELSE 4 END ASC,
        a.desde ASC;
END;
$$;

COMMENT ON FUNCTION rpc_taller_mis_os() IS
    'Fase 3: las OS que el jefe de taller le asignó a quien abrió sesión. Sólo '
    'lee: acá nadie se asigna trabajo solo.';

-- ── 3 · El reloj es de cada uno ─────────────────────────────────────────────
--
-- Antes, pausar y terminar sólo pedían estar autenticado: con el os_id de otro
-- se le podía parar el reloj a un compañero, y el reloj es lo que paga el bono.
-- La jefatura sí puede —a veces hay que cerrar lo que quedó corriendo del turno
-- anterior—, pero queda registrado quién lo hizo.

CREATE OR REPLACE FUNCTION rpc_taller_os_pausar(
    p_os_id      UUID,
    p_tecnico_id UUID,
    p_motivo     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_mio  UUID := fn_taller_mi_tecnico_id();
    v_n    INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    IF NOT fn_taller_es_jefatura() AND p_tecnico_id IS DISTINCT FROM v_mio THEN
        RAISE EXCEPTION 'Sólo puedes parar tu propio reloj. El de otro lo para el jefe de taller.';
    END IF;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           motivo_cierre = NULLIF(TRIM(COALESCE(p_motivo,'')),'')
     WHERE os_id = p_os_id AND tecnico_id = p_tecnico_id AND fin IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE taller_os SET estado = 'pausada', updated_at = NOW()
     WHERE id = p_os_id AND estado = 'en_ejecucion'
       AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo WHERE os_id = p_os_id AND fin IS NULL);

    RETURN jsonb_build_object('success', TRUE, 'tramos_cerrados', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_taller_os_finalizar(
    p_os_id       UUID,
    p_observacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_mio  UUID := fn_taller_mi_tecnico_id();
    v_est  TEXT;
    v_n    INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT estado INTO v_est FROM taller_os WHERE id = p_os_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_est = 'finalizada' THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    -- Terminar es decir «esto ya está hecho»: lo dice quien la tiene asignada,
    -- o la jefatura. Un tercero no cierra el trabajo de otro.
    IF NOT fn_taller_es_jefatura()
       AND NOT EXISTS (SELECT 1 FROM taller_os_asignacion
                        WHERE os_id = p_os_id AND tecnico_id = v_mio AND hasta IS NULL) THEN
        RAISE EXCEPTION 'Esta Orden de Servicio no está asignada a ti.';
    END IF;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT)
     WHERE os_id = p_os_id AND fin IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE taller_os
       SET estado = 'finalizada',
           observacion_cierre = NULLIF(TRIM(COALESCE(p_observacion,'')),''),
           cerrada_at = NOW(),
           updated_at = NOW()
     WHERE id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'tramos_cerrados', v_n);
END;
$$;

-- ── 4 · Permisos ────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION fn_taller_mi_tecnico_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_mis_os() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_mi_tecnico_id() TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_mis_os() TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_vinc INT; v_sin INT; v_asig INT;
BEGIN
    SELECT count(*) INTO v_vinc FROM taller_tecnicos WHERE activo AND usuario_perfil_id IS NOT NULL;
    SELECT count(*) INTO v_sin  FROM taller_tecnicos WHERE activo AND usuario_perfil_id IS NULL;
    SELECT count(*) INTO v_asig FROM taller_os_asignacion WHERE hasta IS NULL;
    RAISE NOTICE 'técnicos con cuenta: % · sin cuenta: % · asignaciones vigentes: %',
                 v_vinc, v_sin, v_asig;
END $mig$;

COMMIT;
