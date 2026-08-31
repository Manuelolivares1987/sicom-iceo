-- ============================================================================
-- MIG472 · Cerrar con tareas pendientes se puede, pero lo valida el jefe
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- «Necesito que el checklist, si finaliza con tareas pendientes, permita cerrar,
-- pero el jefe de taller debe validar».
--
-- CÓMO ESTABA
-- El cierre se negaba en seco: «Hay 114 de 118 ítems obligatorios sin
-- completar». Sin salida. En terreno eso tiene dos finales, los dos malos: o el
-- equipo se queda con la OT abierta para siempre, o alguien marca 114 ítems que
-- no revisó para poder cerrar. La segunda es la peor, porque además ensucia el
-- historial del equipo con revisiones que nunca ocurrieron.
--
-- CÓMO QUEDA
-- Se puede cerrar, pero no en silencio:
--
--   1. El mecánico tiene que ESCRIBIR por qué quedaron pendientes. Sin motivo,
--      la regla de siempre sigue en pie y el cierre se niega igual.
--   2. La OT queda marcada «por validar», con cuántos ítems faltaron y el
--      motivo. No es un cierre normal y el sistema no la trata como tal.
--   3. El jefe de taller la aprueba o la devuelve. Si la devuelve, la OT vuelve
--      a estar abierta con su comentario, para terminar lo que falta.
--
-- Y LO QUE HACE QUE ESTO NO SE PRESTE PARA NADA
-- Mientras el cierre no esté validado, esa OT NO PAGA BONO. Sin esa regla, la
-- puerta que se abre acá sería la más barata del sistema: cerrar 118 ítems con
-- 4 hechos y cobrar el trabajo completo. Tampoco se puede cerrar un período de
-- bono con cierres sin validar: se listan y frenan.
--
-- POR QUÉ EL PERMISO ES UNA FILA Y NO UNA BANDERA DE SESIÓN
-- La forma fácil de saltarse el control en `rpc_transicion_ot` habría sido una
-- variable de sesión. No: el motivo se escribe en la OT ANTES de la transición,
-- y la regla mira esa fila. Si el motivo no está, no hay excepción que valga —
-- y si está, queda para siempre quién lo escribió y por qué.
-- ============================================================================

BEGIN;

-- ── 1 · El cierre con pendientes deja rastro en la OT ───────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS cierre_pendiente_motivo    TEXT,
  ADD COLUMN IF NOT EXISTS cierre_pendientes          INT,
  ADD COLUMN IF NOT EXISTS cierre_pendientes_total    INT,
  ADD COLUMN IF NOT EXISTS cierre_validacion_estado   TEXT,
  ADD COLUMN IF NOT EXISTS cierre_validado_por        UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS cierre_validado_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cierre_validacion_comentario TEXT;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ot_cierre_validacion') THEN
        ALTER TABLE ordenes_trabajo
          ADD CONSTRAINT chk_ot_cierre_validacion
          CHECK (cierre_validacion_estado IS NULL
                 OR cierre_validacion_estado IN ('por_validar','validado','rechazado'));
    END IF;
END
$c$;

COMMENT ON COLUMN ordenes_trabajo.cierre_pendiente_motivo IS
    'Por qué se cerró con tareas obligatorias sin completar. Es lo que habilita '
    'el cierre excepcional: sin motivo escrito, la regla de siempre bloquea.';
COMMENT ON COLUMN ordenes_trabajo.cierre_validacion_estado IS
    'por_validar / validado / rechazado. Mientras esté «por_validar» la OT no '
    'paga bono.';

CREATE INDEX IF NOT EXISTS idx_ot_cierre_por_validar
    ON ordenes_trabajo (cierre_validacion_estado)
    WHERE cierre_validacion_estado = 'por_validar';

-- ── 2 · La regla del checklist mira la fila, no una bandera ─────────────────
CREATE OR REPLACE FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum DEFAULT NULL::causa_no_ejecucion_enum, p_detalle_no_ejecucion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_responsable_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ot                     RECORD;
    v_count_evidence         INTEGER;
    v_count_checklist_total  INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas   estado_ot_enum[];
    v_rol                    TEXT;
BEGIN

    -- [MIG189] Autorización fail-closed (ordenes_trabajo/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    -- [MIG196] + operador_taller: ejecuta las OTs liberadas (app /m/taller).
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones','planificador','supervisor','tecnico_mantenimiento','operador_taller']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'edit' USING ERRCODE = '42501';
    END IF;

    -- [MIG196] El operador de taller solo EJECUTA: iniciar / pausar / finalizar.
    -- Nada de asignar, cancelar ni no_ejecutada (eso es de la jefatura).
    v_rol := public.fn_user_rol();
    IF v_rol = 'operador_taller'
       AND p_nuevo_estado NOT IN ('en_ejecucion','pausada','ejecutada_ok','ejecutada_con_observaciones') THEN
        RAISE EXCEPTION 'El operador de taller no puede pasar una OT a "%".', p_nuevo_estado
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada: %', p_ot_id; END IF;

    -- [MIG215] Ya está en el estado pedido → no-op exitoso. Hace idempotentes
    -- los reintentos de la cola offline de /m/taller (la 1a llamada se aplicó
    -- pero la respuesta se perdió y el cliente reintenta).
    IF v_ot.estado = p_nuevo_estado THEN
        RETURN jsonb_build_object('ot_id', p_ot_id, 'folio', v_ot.folio,
            'estado_anterior', v_ot.estado, 'estado_nuevo', p_nuevo_estado, 'noop', true);
    END IF;

    -- [MIG196] ... y solo sobre OTs ya liberadas a ejecución (universo MIG193).
    IF v_rol = 'operador_taller' AND v_ot.preparacion_ok_at IS NULL THEN
        RAISE EXCEPTION 'La OT % aun no esta liberada a ejecucion.', v_ot.folio
            USING ERRCODE = '42501';
    END IF;

    -- [MIG215] pausada → ejecutada_*: el mecánico pausa al fin de jornada y
    -- finaliza al otro día sin reanudar. Las exigencias de cierre (evidencia,
    -- checklist, firma) aplican igual más abajo y en validar_cierre_ot.
    v_transiciones_validas := CASE v_ot.estado
        WHEN 'creada'                      THEN ARRAY['asignada','cancelada']::estado_ot_enum[]
        WHEN 'asignada'                    THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'en_ejecucion'                THEN ARRAY['pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada']::estado_ot_enum[]
        WHEN 'pausada'                     THEN ARRAY['en_ejecucion','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'ejecutada_ok'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'ejecutada_con_observaciones' THEN ARRAY[]::estado_ot_enum[]
        WHEN 'no_ejecutada'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cancelada'                   THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cerrada'                     THEN ARRAY[]::estado_ot_enum[]
        ELSE ARRAY[]::estado_ot_enum[]
    END;

    IF NOT (p_nuevo_estado = ANY(v_transiciones_validas)) THEN
        IF p_nuevo_estado = 'cerrada' THEN
            RAISE EXCEPTION 'La transición a "cerrada" solo puede realizarse mediante cierre de supervisor (rpc_cerrar_ot_supervisor).';
        END IF;
        RAISE EXCEPTION 'Transición inválida: "%" → "%". Permitidas: %', v_ot.estado, p_nuevo_estado, v_transiciones_validas;
    END IF;

    -- 3a. → asignada: requiere responsable
    IF p_nuevo_estado = 'asignada' THEN
        IF COALESCE(p_responsable_id, v_ot.responsable_id) IS NULL THEN
            RAISE EXCEPTION 'No se puede asignar OT sin responsable.';
        END IF;
    END IF;

    -- 3b. → en_ejecucion: responsable obligatorio
    IF p_nuevo_estado = 'en_ejecucion' THEN
        IF v_ot.responsable_id IS NULL THEN
            RAISE EXCEPTION 'No se puede iniciar ejecución sin responsable asignado. Asigne un responsable primero.';
        END IF;
    END IF;

    -- 3c. → no_ejecutada: causa obligatoria
    IF p_nuevo_estado = 'no_ejecutada' THEN
        IF p_causa_no_ejecucion IS NULL THEN RAISE EXCEPTION 'Causa de no ejecución es obligatoria.'; END IF;
    END IF;

    -- 3d/3e. → ejecutada_*: evidencia + checklist (cuenta el checklist V03)
    IF p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones') THEN
        -- Evidencia: fotos de evidencias_ot O fotos del checklist V03 O checklist_ot
        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = p_ot_id)
             + (SELECT COUNT(*) FROM checklist_v2_instance ci
                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                 WHERE ci.ot_id = p_ot_id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = p_ot_id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)
          INTO v_count_evidence;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'REGLA: Tarea sin evidencia = tarea no ejecutada. Cargue al menos 1 foto.';
        END IF;

        -- Obligatorios pendientes: primero el V03 (no excluido); si no hay V03, checklist_ot
        SELECT COUNT(*) FILTER (WHERE obligatorio),
               COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
          INTO v_count_checklist_total, v_count_checklist_pending
          FROM v_taller_ot_checklist_v3 WHERE ot_id = p_ot_id AND excluido = false;

        IF COALESCE(v_count_checklist_total,0) = 0 THEN
            SELECT COUNT(*) FILTER (WHERE obligatorio = true),
                   COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
              INTO v_count_checklist_total, v_count_checklist_pending
              FROM checklist_ot WHERE ot_id = p_ot_id;
        END IF;

        -- [MIG472] Cerrar con tareas pendientes ya no es imposible: es EXCEPCIONAL
        -- y queda a la vista. El mecánico escribe por qué —eso deja el motivo
        -- guardado en la OT antes de llegar acá— y el cierre pasa marcado como
        -- «por validar»: el jefe de taller lo aprueba o lo devuelve.
        --
        -- El permiso NO es una bandera de sesión: es una fila. Si el motivo no
        -- está escrito en la OT, la regla de siempre sigue en pie.
        IF COALESCE(v_count_checklist_total,0) > 0 AND COALESCE(v_count_checklist_pending,0) > 0 THEN
            IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo o
                            WHERE o.id = p_ot_id
                              AND NULLIF(TRIM(COALESCE(o.cierre_pendiente_motivo,'')),'') IS NOT NULL) THEN
                RAISE EXCEPTION 'Hay % de % ítems obligatorios sin completar.', v_count_checklist_pending, v_count_checklist_total;
            END IF;
        END IF;

        IF p_nuevo_estado = 'ejecutada_con_observaciones'
           AND COALESCE(p_observaciones, v_ot.observaciones, '') = '' THEN
            RAISE EXCEPTION 'Observaciones obligatorias al finalizar con observaciones.';
        END IF;
    END IF;

    UPDATE ordenes_trabajo
       SET estado = p_nuevo_estado,
           responsable_id = CASE WHEN p_nuevo_estado='asignada' AND p_responsable_id IS NOT NULL THEN p_responsable_id ELSE responsable_id END,
           fecha_inicio = CASE WHEN p_nuevo_estado='en_ejecucion' AND fecha_inicio IS NULL THEN NOW() ELSE fecha_inicio END,
           fecha_termino = CASE WHEN p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada') THEN NOW() ELSE fecha_termino END,
           causa_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_causa_no_ejecucion ELSE causa_no_ejecucion END,
           detalle_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_detalle_no_ejecucion ELSE detalle_no_ejecucion END,
           observaciones = CASE WHEN p_observaciones IS NOT NULL THEN p_observaciones ELSE observaciones END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, p_nuevo_estado,
            COALESCE(p_observaciones, p_detalle_no_ejecucion, v_ot.estado || ' → ' || p_nuevo_estado), p_usuario_id);

    RETURN jsonb_build_object('ot_id', p_ot_id, 'folio', v_ot.folio,
        'estado_anterior', v_ot.estado, 'estado_nuevo', p_nuevo_estado);
END;
$function$
;

-- ── 2b · La cerradura de verdad está en el trigger ──────────────────────────
--
-- El chequeo de `rpc_transicion_ot` es la puerta; el que de verdad impide el
-- cierre es este trigger sobre la tabla. Es la misma lección de MIG437: si la
-- excepción se declara sólo en el RPC, la tabla la sigue negando. Así que la
-- excepción va en los dos lados, y con la misma condición: que el motivo esté
-- escrito en la fila.
CREATE OR REPLACE FUNCTION public.validar_cierre_ot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_evidencias_count    INTEGER;
    v_checklist_total     INTEGER;
    v_checklist_pendiente INTEGER;
BEGIN
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        -- 1. Evidencia: evidencias_ot + fotos del checklist V03 + fotos checklist_ot
        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = NEW.id)
             + (SELECT COUNT(*) FROM checklist_v2_instance ci
                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                 WHERE ci.ot_id = NEW.id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = NEW.id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)
          INTO v_evidencias_count;
        IF v_evidencias_count = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere al menos 1 evidencia fotografica o documental.', NEW.folio;
        END IF;

        -- 2. Obligatorios del checklist: V03 (no excluido); si no hay V03, checklist_ot
        SELECT COUNT(*) FILTER (WHERE obligatorio),
               COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
          INTO v_checklist_total, v_checklist_pendiente
          FROM v_taller_ot_checklist_v3 WHERE ot_id = NEW.id AND excluido = false;
        IF COALESCE(v_checklist_total,0) = 0 THEN
            SELECT COUNT(*) FILTER (WHERE obligatorio = true),
                   COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
              INTO v_checklist_total, v_checklist_pendiente
              FROM checklist_ot WHERE ot_id = NEW.id;
        END IF;
        -- [MIG472] Acá vive la cerradura de verdad —el RPC es sólo la puerta— y
        -- por eso la excepción se declara acá también: se puede cerrar con
        -- tareas pendientes SI el mecánico escribió por qué. Ese motivo queda
        -- en la fila, la OT sale marcada «por validar», y hasta que la jefatura
        -- la apruebe no paga bono.
        IF COALESCE(v_checklist_pendiente,0) > 0
           AND NULLIF(TRIM(COALESCE(NEW.cierre_pendiente_motivo,'')),'') IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Existen % items obligatorios del checklist sin completar.',
                NEW.folio, v_checklist_pendiente;
        END IF;

        -- 3. Firma del técnico
        IF NEW.firma_tecnico_url IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere la firma del tecnico responsable.', NEW.folio;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- ── 3 · Finalizar desde el teléfono, con o sin pendientes ───────────────────
DROP FUNCTION IF EXISTS rpc_taller_finalizar_mecanico(UUID, TEXT, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION rpc_taller_finalizar_mecanico(
    p_ot_id             UUID,
    p_firma_tecnico_url TEXT,
    p_con_observaciones BOOLEAN DEFAULT FALSE,
    p_observaciones     TEXT DEFAULT NULL,
    p_motivo_pendientes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
    v_trabajo JSONB;
    v_res JSONB;
    v_total INT; v_pend INT;
    v_motivo TEXT := NULLIF(TRIM(COALESCE(p_motivo_pendientes,'')),'');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_firma_tecnico_url IS NULL OR length(trim(p_firma_tecnico_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del técnico es obligatoria para finalizar'; END IF;

    -- [MIG445] Sin trabajo registrado no hay OT que cerrar. Esto NO se relaja:
    -- cerrar con pendientes sigue exigiendo que algo se haya hecho.
    v_trabajo := fn_taller_ot_tiene_trabajo(p_ot_id);
    IF NOT (v_trabajo->>'tiene')::BOOLEAN THEN
        RAISE EXCEPTION 'Esta OT no tiene trabajo registrado: no hay ningún ítem respondido ni tiempo de ejecución. Marca el checklist o usa el cronómetro antes de finalizar.';
    END IF;

    -- [MIG397/471] Con cuánto uso volvió el equipo se anota antes de cerrar.
    SELECT i.id, i.activo_id, i.horometro, i.kilometraje, i.cuenta_litros
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;

    IF v_inst.id IS NOT NULL THEN
        IF v_inst.horometro IS NULL THEN
            v_falta := array_append(v_falta, 'el horómetro'::TEXT);
        END IF;
        IF v_inst.kilometraje IS NULL AND fn_activo_exige_kilometraje(v_inst.activo_id) THEN
            v_falta := array_append(v_falta, 'el kilometraje'::TEXT);
        END IF;
        IF v_inst.cuenta_litros IS NULL AND fn_activo_exige_cuenta_litros(v_inst.activo_id) THEN
            v_falta := array_append(v_falta, 'el cuenta litros'::TEXT);
        END IF;
        IF array_length(v_falta, 1) > 0 THEN
            RAISE EXCEPTION 'Falta anotar % del equipo. Está arriba de la lista de tareas, en «Medidores del equipo».',
                array_to_string(v_falta, ' y ');
        END IF;
    END IF;

    -- [MIG472] ¿Quedaron obligatorios sin hacer?
    SELECT COUNT(*) FILTER (WHERE obligatorio),
           COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
      INTO v_total, v_pend
      FROM v_taller_ot_checklist_v3 WHERE ot_id = p_ot_id AND excluido = false;

    IF COALESCE(v_total,0) > 0 AND COALESCE(v_pend,0) > 0 THEN
        IF v_motivo IS NULL THEN
            RETURN jsonb_build_object(
                'success', FALSE,
                'requiere_motivo_pendientes', TRUE,
                'pendientes', v_pend, 'total', v_total,
                'motivo', format('Quedan %s de %s tareas obligatorias sin hacer. Se puede cerrar igual, '
                                 || 'pero hay que escribir por qué: el jefe de taller lo va a revisar.',
                                 v_pend, v_total));
        END IF;

        UPDATE ordenes_trabajo
           SET cierre_pendiente_motivo  = v_motivo,
               cierre_pendientes        = v_pend,
               cierre_pendientes_total  = v_total,
               cierre_validacion_estado = 'por_validar',
               cierre_validado_por      = NULL,
               cierre_validado_at       = NULL,
               updated_at = NOW()
         WHERE id = p_ot_id;
    END IF;

    UPDATE ordenes_trabajo SET firma_tecnico_url = p_firma_tecnico_url, updated_at = NOW() WHERE id = p_ot_id;

    -- [MIG450] El reloj se cierra con la OT.
    PERFORM fn_taller_cerrar_ejecuciones_abiertas(p_ot_id, p_observaciones);

    v_res := rpc_transicion_ot(
        p_ot_id,
        (CASE WHEN p_con_observaciones THEN 'ejecutada_con_observaciones' ELSE 'ejecutada_ok' END)::estado_ot_enum,
        v_user, NULL, NULL,
        CASE WHEN v_motivo IS NOT NULL
             THEN COALESCE(p_observaciones || ' · ', '') || 'Cerrada con ' || v_pend
                  || ' tarea(s) pendiente(s): ' || v_motivo
             ELSE p_observaciones END,
        NULL);

    PERFORM fn_taller_marcar_cierre(p_ot_id, 'terreno');

    RETURN v_res || jsonb_build_object(
        'por_validar', v_motivo IS NOT NULL,
        'pendientes', COALESCE(v_pend, 0));
END;
$$;

-- ── 4 · El jefe valida o devuelve ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_validar_cierre(
    p_ot_id      UUID,
    p_aprueba    BOOLEAN,
    p_comentario TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_est  TEXT;
    v_folio TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('jefe_mantenimiento','administrador','subgerente_operaciones','jefe_operaciones') THEN
        RAISE EXCEPTION 'Validar un cierre con tareas pendientes es de la jefatura de taller.';
    END IF;

    SELECT cierre_validacion_estado, folio::TEXT INTO v_est, v_folio
      FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_folio IS NULL THEN RAISE EXCEPTION 'Esa OT no existe.'; END IF;
    IF v_est IS DISTINCT FROM 'por_validar' THEN
        RAISE EXCEPTION 'La % no está esperando validación (estado: %).', v_folio, COALESCE(v_est,'sin marcar');
    END IF;

    IF NOT p_aprueba AND length(COALESCE(TRIM(p_comentario),'')) < 10 THEN
        RAISE EXCEPTION 'Para devolverla hay que decir qué falta: el mecánico tiene que saber a qué volver.';
    END IF;

    UPDATE ordenes_trabajo
       SET cierre_validacion_estado     = CASE WHEN p_aprueba THEN 'validado' ELSE 'rechazado' END,
           cierre_validado_por          = v_user,
           cierre_validado_at           = NOW(),
           cierre_validacion_comentario = NULLIF(TRIM(COALESCE(p_comentario,'')),''),
           updated_at = NOW()
     WHERE id = p_ot_id;

    -- Devuelta = la OT vuelve a estar abierta. El motivo se limpia para que el
    -- próximo cierre tenga que justificarse de nuevo si vuelve con pendientes.
    IF NOT p_aprueba THEN
        UPDATE ordenes_trabajo
           SET estado = 'pausada',
               cierre_pendiente_motivo = NULL,
               fecha_termino = NULL,
               updated_at = NOW()
         WHERE id = p_ot_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'folio', v_folio,
                              'estado', CASE WHEN p_aprueba THEN 'validado' ELSE 'rechazado' END);
END;
$$;

-- ── 5 · La bandeja del jefe ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_cierres_por_validar()
RETURNS TABLE (
    ot_id          UUID,
    folio          TEXT,
    patente        TEXT,
    equipo         TEXT,
    fecha_termino  TIMESTAMPTZ,
    pendientes     INT,
    total          INT,
    motivo         TEXT,
    cerro          TEXT,
    cuadrilla      TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT ot.id, ot.folio::TEXT, a.patente::TEXT, a.nombre::TEXT, ot.fecha_termino,
           ot.cierre_pendientes, ot.cierre_pendientes_total, ot.cierre_pendiente_motivo,
           (SELECT up.nombre_completo::TEXT FROM usuarios_perfil up WHERE up.id = ot.cerrada_por),
           (SELECT string_agg(DISTINCT t.nombre, ', ')
              FROM taller_plan_semanal_ots po
              JOIN taller_ot_cuadrilla c ON c.plan_ot_id = po.id
              JOIN taller_tecnicos t ON t.id = c.tecnico_id
             WHERE po.ot_id = ot.id)
      FROM ordenes_trabajo ot
      JOIN activos a ON a.id = ot.activo_id
     WHERE ot.cierre_validacion_estado = 'por_validar'
     ORDER BY ot.fecha_termino DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION rpc_taller_finalizar_mecanico(UUID, TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_validar_cierre(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_cierres_por_validar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_finalizar_mecanico(UUID, TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_validar_cierre(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_cierres_por_validar() TO authenticated;

-- ── 6 · Y lo que hace que esto no se preste para nada ───────────────────────
--
-- Un cierre «por validar» no paga bono, y un período no se puede cerrar con
-- cierres sin validar. Esto es lo que convierte la excepción en una excepción y
-- no en el camino más corto.
CREATE OR REPLACE FUNCTION public.fn_taller_bono_periodo_calc(p_desde date, p_hasta date)
 RETURNS TABLE(tecnico_id uuid, tecnico text, cargo text, ot_id uuid, ot_folio text, concepto text, dias numeric, tramo text, participacion numeric, base_reparto text, monto_formula numeric, monto_propuesto numeric, falta text, aviso text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_par UUID;
BEGIN
    SELECT id INTO v_par FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran el período % a %.', p_desde, p_hasta;
    END IF;

    RETURN QUERY
    WITH cerradas AS (
        -- El trabajo que el período paga: OT ejecutadas dentro del corte, que
        -- no sean de externo.
        SELECT ot.id, ot.folio::TEXT AS folio,
               ot.fecha_inicio, ot.fecha_termino,
               fn_taller_ot_concepto(ot.id) AS concepto,
               GREATEST(1, CEIL(EXTRACT(EPOCH FROM (
                   ot.fecha_termino - COALESCE(ot.fecha_inicio, ot.created_at)
               )) / 86400.0))::NUMERIC AS dias
          FROM ordenes_trabajo ot
         WHERE ot.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
           AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta
           AND NOT COALESCE(ot.ejecutada_por_externo, FALSE)
           -- [MIG472] Un cierre con tareas pendientes no paga hasta que la
           -- jefatura lo valide. Sin esto, la puerta que abre MIG472 sería la
           -- más barata del sistema: cerrar 118 items con 4 hechos y cobrar el
           -- trabajo completo.
           AND COALESCE(ot.cierre_validacion_estado, 'validado') <> 'por_validar'
    ),
    reparto AS (
        SELECT r.ot_id, r.tecnico_id, r.tecnico, r.participacion, r.base_reparto
          FROM v_taller_bono_reparto r
    )
    SELECT
        rp.tecnico_id,
        rp.tecnico::TEXT,
        tc.cargo,
        c.id,
        c.folio,
        c.concepto,
        c.dias,
        CASE
            WHEN co.concepto IS NULL THEN NULL
            WHEN c.dias <= co.dias_optimizado THEN 'optimizado'
            WHEN c.dias <= co.dias_normal     THEN 'normal'
            WHEN c.dias <= co.dias_demora     THEN 'con demora'
            ELSE 'fuera de plazo'
        END,
        rp.participacion,
        rp.base_reparto,
        -- La fórmula tal como está hoy en la planilla, sin corregir.
        CASE WHEN cg.plan_tope_clp IS NULL OR co.concepto IS NULL THEN NULL
             ELSE round(rp.participacion * cg.plan_tope_clp * CASE
                 WHEN c.dias <= co.dias_optimizado THEN co.coef_optimizado * co.dias_optimizado
                 WHEN c.dias <= co.dias_normal     THEN c.dias * co.coef_por_dia
                 ELSE (co.dias_demora - c.dias) * co.coef_por_dia
             END)
        END,
        -- La versión corregida: monótona, nunca negativa. Cerrar antes siempre
        -- paga más o igual.
        CASE WHEN cg.plan_tope_clp IS NULL OR co.concepto IS NULL THEN NULL
             ELSE round(rp.participacion * cg.plan_tope_clp * co.coef_optimizado * co.dias_optimizado * GREATEST(0, CASE
                 WHEN c.dias <= co.dias_optimizado THEN 1.0
                 WHEN c.dias <= co.dias_normal
                     THEN 1.0 - 0.4 * (c.dias - co.dias_optimizado)
                                    / NULLIF(co.dias_normal - co.dias_optimizado, 0)
                 WHEN c.dias <= co.dias_demora
                     THEN 0.6 - 0.6 * (c.dias - co.dias_normal)
                                    / NULLIF(co.dias_demora - co.dias_normal, 0)
                 ELSE 0.0
             END))
        END,
        -- `falta` es lo que IMPIDE pagar. Bloquea el cierre del período.
        NULLIF(concat_ws(' · ',
            CASE WHEN tc.cargo IS NULL THEN 'falta el cargo del técnico' END,
            CASE WHEN c.concepto IS NULL THEN 'no se pudo deducir el concepto' END
        ), ''),
        -- `aviso` es lo que hay que SABER. No bloquea nada.
        NULLIF(concat_ws(' · ',
            -- [MIG462] Tres formas de repartir, no dos. Cualquiera que no sea el
            -- tiempo medido de todos merece quedar dicho en la cartola.
            CASE WHEN rp.base_reparto <> 'tiempo medido'
                 THEN 'reparto por ' || rp.base_reparto END
        ), '')
      FROM cerradas c
      JOIN reparto rp ON rp.ot_id = c.id
      LEFT JOIN taller_tecnico_cargo tc
             ON tc.tecnico_id = rp.tecnico_id
            AND tc.desde <= p_hasta AND (tc.hasta IS NULL OR tc.hasta >= p_desde)
      LEFT JOIN taller_bono_cargo cg ON cg.parametros_id = v_par AND cg.cargo = tc.cargo
      LEFT JOIN taller_bono_concepto co ON co.parametros_id = v_par AND co.concepto = c.concepto
      -- [MIG463] Quien ya no está en el taller y nunca tuvo cargo no genera línea.
      -- No es un dato que falte: es alguien que se fue. Bloquear el cierre de un
      -- corte por el cargo de un ex trabajador sería una traba sin sentido.
      -- El que SÍ está activo y no tiene cargo sigue apareciendo como `falta`,
      -- porque ahí la pregunta está abierta de verdad.
      JOIN taller_tecnicos tt ON tt.id = rp.tecnico_id
     WHERE COALESCE(tt.activo, TRUE) OR tc.cargo IS NOT NULL
     ORDER BY rp.tecnico, c.folio;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_taller_bono_cerrar_periodo(p_nombre text, p_desde date, p_hasta date, p_disponibilidad numeric DEFAULT NULL::numeric, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_par    UUID;
    v_estado TEXT;
    v_faltan TEXT;
    v_solapa TEXT;
    v_huerf  TEXT;
    v_per    UUID;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Tu perfil no puede cerrar un período de bono.';
    END IF;

    IF p_hasta < p_desde THEN
        RAISE EXCEPTION 'El corte termina antes de empezar.';
    END IF;

    SELECT string_agg(nombre || ' (' || desde || ' a ' || hasta || ')', ', ')
      INTO v_solapa
      FROM taller_bono_periodo
     WHERE desde <= p_hasta AND hasta >= p_desde;
    IF v_solapa IS NOT NULL THEN
        RAISE EXCEPTION 'Este corte se pisa con otro que ya está cerrado: %.', v_solapa;
    END IF;

    SELECT id, estado INTO v_par, v_estado
      FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran % a %.', p_desde, p_hasta;
    END IF;
    IF v_estado <> 'vigente' THEN
        RAISE EXCEPTION 'Los parámetros de este corte están en «%». Un período no se '
                        'cierra sobre una propuesta: primero el acta que fija topes y '
                        'curva, después el cierre.', v_estado;
    END IF;

    SELECT string_agg(DISTINCT r.tecnico || ': ' || r.falta, ' · ')
      INTO v_faltan
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r
     WHERE r.falta IS NOT NULL;
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta información para cerrar. %', v_faltan;
    END IF;

    -- [MIG464] Trabajo cerrado en el corte que no le paga a nadie. Dejarlo pasar
    -- sería perder plata en silencio.
    SELECT string_agg(o.ot_folio || ' (' || o.motivo || ')', ' · ')
      INTO v_huerf
      FROM fn_taller_bono_ot_sin_dueno(p_desde, p_hasta) o;
    IF v_huerf IS NOT NULL THEN
        RAISE EXCEPTION 'Hay trabajo cerrado en el corte que no le paga a nadie: %. '
                        'Asígnales cuadrilla en el Plan Semanal, o confirma que no '
                        'corresponde pagarlas.', v_huerf;
    END IF;

    -- [MIG472] Cierres con pendientes que nadie validó. No se pagan y no se
    -- pueden dejar pasar: o se validan o se devuelven, pero se deciden.
    SELECT string_agg(ot.folio || ' (' || ot.cierre_pendientes || ' de '
                      || ot.cierre_pendientes_total || ' tareas sin hacer)', ' · ')
      INTO v_huerf
      FROM ordenes_trabajo ot
     WHERE ot.cierre_validacion_estado = 'por_validar'
       AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta;
    IF v_huerf IS NOT NULL THEN
        RAISE EXCEPTION 'Hay cierres con tareas pendientes que la jefatura no ha validado: %. '
                        'Valídalos o devuélvelos antes de cerrar el período.', v_huerf;
    END IF;

    INSERT INTO taller_bono_periodo (
        nombre, desde, hasta, parametros_id, disponibilidad_pct,
        disponibilidad_fuente, notas, cerrado_por)
    VALUES (
        p_nombre, p_desde, p_hasta, v_par,
        COALESCE(p_disponibilidad,
                 (SELECT d.disponibilidad_pct FROM fn_taller_disponibilidad_periodo(p_desde, p_hasta) d)),
        CASE WHEN p_disponibilidad IS NULL THEN 'medida por el sistema'
             ELSE 'fijada al cerrar' END,
        p_notas, v_user)
    RETURNING id INTO v_per;

    INSERT INTO taller_bono_periodo_linea (
        periodo_id, tecnico_id, tecnico, cargo, ots, plan_formula, plan_calculado,
        plan_tope, plan_pagado, kpi_pagado, total, dias_cargo, dias_corte, tramo,
        falta, aviso)
    SELECT v_per, r.tecnico_id, r.tecnico, r.cargo, r.ots, r.plan_formula,
           r.plan_calculado, r.plan_tope, r.plan_pagado, r.kpi_pagado, r.total,
           r.dias_cargo, r.dias_corte, r.tramo, r.falta, r.aviso
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r;

    INSERT INTO taller_bono_periodo_detalle (
        periodo_id, tecnico_id, ot_id, ot_folio, concepto, dias, tramo,
        participacion, base_reparto, monto_formula, monto_propuesto, falta, aviso)
    SELECT v_per, b.tecnico_id, b.ot_id, b.ot_folio, b.concepto, b.dias, b.tramo,
           b.participacion, b.base_reparto, b.monto_formula, b.monto_propuesto,
           b.falta, b.aviso
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b;

    SELECT COALESCE(sum(total), 0), count(*) INTO v_total, v_n
      FROM taller_bono_periodo_linea WHERE periodo_id = v_per;

    UPDATE taller_bono_periodo SET total_clp = v_total WHERE id = v_per;

    RETURN jsonb_build_object('success', true, 'periodo_id', v_per,
                              'personas', v_n, 'total_clp', v_total);
END;
$function$;

REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_finalizar_mecanico';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: finalizar_mecanico quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname IN ('rpc_taller_validar_cierre','rpc_taller_cierres_por_validar');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FALLO: faltan funciones de validación (%)', v_n; END IF;

    SELECT count(*) INTO v_n FROM rpc_taller_cierres_por_validar();
    RAISE NOTICE 'cierres esperando validación hoy: % (arranca en cero)', v_n;

    SELECT count(*) INTO v_n FROM ordenes_trabajo WHERE cierre_validacion_estado IS NOT NULL;
    RAISE NOTICE 'OT con marca de validación: %', v_n;
    RAISE NOTICE 'una OT «por_validar» no paga bono hasta que la jefatura la apruebe';
END
$mig$;

COMMIT;
