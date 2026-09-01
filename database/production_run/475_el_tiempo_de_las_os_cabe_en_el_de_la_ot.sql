-- ============================================================================
-- MIG475 · El tiempo de las OS tiene que caber en el de la OT
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- «El paso a paso es checklist, eso da origen a NC, y esas NC se meten en una OS
-- para ejecutar con tiempos definidos. Esos se deben medir en función a lo que
-- dijo el jefe, y la sumatoria de tiempos no puede tomar más que el tiempo total
-- que da la OT para el equipo.»
--
-- Y además: «cuando se ejecuta una OT o una OS, quiero que el "iniciar" se active
-- sólo, en el caso de una OT, cuando guarda los medidores; en el caso de una OS,
-- cuando comienza la primera actividad».
--
-- DE DÓNDE SALE «EL TIEMPO TOTAL DE LA OT»
-- Del PLANIFICADOR. Es lo que el jefe pone en la jornada del plan semanal
-- —`horas_planificadas`— y la suma de las jornadas de esa OT es el presupuesto
-- de la visita. El techo lo pone quien planifica, no una plantilla.
--
-- Y ACÁ HAY UN PROBLEMA QUE HAY QUE DECIR
-- Ese campo existe y NO SE LLENA. Medido hoy: 20 jornadas de 246 tienen horas
-- planificadas, y las veinte son tareas libres. NINGUNA jornada de OT las tiene.
--
-- O sea, el techo que ahora manda está en blanco para toda la flota. Es el mismo
-- patrón de las horas de las NC —10 de 116— y por la misma razón: nadie las pide
-- en el momento de planificar.
--
-- Por eso el techo se comporta así: si el planificador puso horas, manda; si no
-- las puso, no hay techo y el sistema lo dice, en vez de inventarse uno. Poner un
-- techo falso —el del checklist, por ejemplo— haría que el jefe se choque con una
-- justificación por un número que nadie decidió.
--
-- El estimado del checklist se sigue mostrando al lado, como referencia: no
-- manda, pero sirve para que quien planifica sepa qué está prometiendo.
--
-- POR QUÉ ES UN TECHO CON PUERTA Y NO UN MURO
-- Si el jefe reparte 14 horas de OS dentro de una visita presupuestada en 10,6,
-- puede tener toda la razón —apareció algo que el checklist no contemplaba— pero
-- tiene que decirlo. La justificación queda escrita en la OS que se pasó, con su
-- nombre. Un muro se saltaría inflando el checklist; una puerta con registro no.
--
-- Y ESTO HABLA CON EL BONO
-- El incentivo paga por trabajo cerrado y por los días que tomó. Si las horas
-- que el jefe reparte no tienen relación con el estándar de la visita, el bono
-- se calcula sobre una ficción. El techo es lo que ata las dos cosas: lo que se
-- planifica en OS y lo que el estándar dice que cuesta esa visita.
--
-- EL «INICIAR» SE GANA
-- Hasta hoy se podía arrancar el reloj de una OT sin haber anotado el horómetro.
-- Eso deja la visita sin punto de partida: no se sabe con cuánto uso entró el
-- equipo, y sin eso las preventivas por horas se calculan sobre aire. Ahora el
-- medidor es la puerta de entrada — para la OT y para cualquier OS suya.
--
-- Y la OT ya no se arranca a mano: se pone en ejecución sola cuando alguien
-- empieza la primera actividad de la primera OS. Es lo que de verdad pasa.
-- ============================================================================

BEGIN;

-- ── 1 · El presupuesto de la visita ─────────────────────────────────────────
-- EL TECHO: lo que puso el planificador. NULL significa «todavía no hay techo»,
-- no «cero horas».
CREATE OR REPLACE FUNCTION fn_taller_ot_horas_plan(p_ot_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT sum(po.horas_planificadas)
      FROM taller_plan_semanal_ots po
     WHERE po.ot_id = p_ot_id AND po.horas_planificadas IS NOT NULL;
$$;

COMMENT ON FUNCTION fn_taller_ot_horas_plan(UUID) IS
    'El tiempo total que el planificador le dio a esta visita, sumando sus '
    'jornadas. Es el techo de lo que se reparte en Órdenes de Servicio. '
    'NULL = el planificador todavía no lo definió.';

-- LA REFERENCIA: lo que el checklist estima. No manda, se muestra.
CREATE OR REPLACE FUNCTION fn_taller_ot_horas_estimadas(p_ot_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT round(COALESCE(sum(c.tiempo_min), 0)::numeric / 60.0, 2)
      FROM v_taller_ot_checklist_v3 c
     WHERE c.ot_id = p_ot_id AND NOT c.excluido;
$$;

COMMENT ON FUNCTION fn_taller_ot_horas_estimadas(UUID) IS
    'Lo que el checklist estima para esta visita. Es REFERENCIA para quien '
    'planifica: el techo lo pone el planificador (fn_taller_ot_horas_plan).';

CREATE OR REPLACE FUNCTION fn_taller_ot_horas_os(p_ot_id UUID, p_excluir_os UUID DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(sum(o.horas_estimadas), 0)
      FROM taller_os o
     WHERE o.ot_id = p_ot_id
       AND o.estado <> 'anulada'
       AND (p_excluir_os IS NULL OR o.id <> p_excluir_os);
$$;

-- Lo que la pantalla necesita para mostrar el presupuesto sin hacer cuentas.
CREATE OR REPLACE FUNCTION rpc_taller_ot_presupuesto(p_ot_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'horas_plan',      fn_taller_ot_horas_plan(p_ot_id),
        'horas_checklist', fn_taller_ot_horas_estimadas(p_ot_id),
        'sin_techo',       fn_taller_ot_horas_plan(p_ot_id) IS NULL,
        'horas_en_os',     fn_taller_ot_horas_os(p_ot_id),
        'horas_libres',    GREATEST(0, COALESCE(fn_taller_ot_horas_plan(p_ot_id), 0) - fn_taller_ot_horas_os(p_ot_id)),
        'excedida',        fn_taller_ot_horas_plan(p_ot_id) IS NOT NULL
                           AND fn_taller_ot_horas_os(p_ot_id) > fn_taller_ot_horas_plan(p_ot_id),
        'horas_reales',    COALESCE((SELECT round(sum(COALESCE(t.segundos,
                              GREATEST(0, EXTRACT(EPOCH FROM (NOW() - t.inicio))::INT)))::numeric / 3600.0, 2)
                              FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
                             WHERE o.ot_id = p_ot_id), 0));
$$;

-- ── 2 · Pasarse del techo exige decir por qué ───────────────────────────────
ALTER TABLE taller_os
  ADD COLUMN IF NOT EXISTS justificacion_exceso TEXT;

COMMENT ON COLUMN taller_os.justificacion_exceso IS
    'Por qué esta OS hace que la suma de horas pase el tiempo estimado de la OT. '
    'Se pide cuando se pasa; queda con el nombre de quien la escribió.';

-- La firma vieja se borra antes de crear la nueva: dos firmas donde una tiene
-- DEFAULT es la trampa de siempre, «function is not unique». Van tres veces.
DROP FUNCTION IF EXISTS rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT);

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

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        SELECT string_agg(nc.id::TEXT, ', ') INTO v_ajena
          FROM no_conformidades nc
         WHERE nc.id = ANY(p_nc_ids) AND nc.ot_id IS DISTINCT FROM p_ot_id;
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

-- ── 3 · Sin medidores no arranca nada ───────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_medidores_listos(p_ot_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
BEGIN
    SELECT i.id, i.activo_id, i.horometro, i.kilometraje, i.cuenta_litros, i.medidores_por
      INTO v
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id ORDER BY i.created_at DESC LIMIT 1;

    -- Sin checklist no hay medidores que exigir: no se inventa un bloqueo.
    IF v.id IS NULL THEN RETURN NULL; END IF;

    IF v.horometro IS NULL THEN v_falta := array_append(v_falta, 'el horómetro'); END IF;
    IF v.kilometraje IS NULL AND fn_activo_exige_kilometraje(v.activo_id) THEN
        v_falta := array_append(v_falta, 'el kilometraje'); END IF;
    IF v.cuenta_litros IS NULL AND fn_activo_exige_cuenta_litros(v.activo_id) THEN
        v_falta := array_append(v_falta, 'el cuenta litros'); END IF;
    -- El número que trajo el sistema no cuenta: tiene que confirmarlo una persona.
    IF v.medidores_por IS NULL THEN
        v_falta := array_append(v_falta, 'confirmar la lectura real del equipo'); END IF;

    IF array_length(v_falta, 1) IS NULL THEN RETURN NULL; END IF;
    RETURN 'Antes de empezar falta anotar ' || array_to_string(v_falta, ' y ')
           || '. Está arriba de la lista de tareas, en «Medidores del equipo».';
END;
$$;

-- ── 4 · La OS arranca, y con ella la OT ─────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_iniciar(
    p_os_id      UUID,
    p_tecnico_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_estado TEXT;
    v_tramo  UUID;
    v_otra   TEXT;
    v_ot     UUID;
    v_ot_est TEXT;
    v_falta  TEXT;
    v_primera BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_tecnico_id IS NULL THEN
        RAISE EXCEPTION 'Hay que decir quién empieza: el tiempo que se mide decide el bono.';
    END IF;

    SELECT o.estado, o.ot_id INTO v_estado, v_ot FROM taller_os o WHERE o.id = p_os_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_estado IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %.', v_estado;
    END IF;

    -- [MIG475] El medidor es la puerta de entrada de toda la visita.
    v_falta := fn_taller_ot_medidores_listos(v_ot);
    IF v_falta IS NOT NULL THEN RAISE EXCEPTION '%', v_falta; END IF;

    IF NOT fn_taller_es_jefatura()
       AND NOT EXISTS (SELECT 1 FROM taller_os_asignacion
                        WHERE os_id = p_os_id AND tecnico_id = p_tecnico_id AND hasta IS NULL) THEN
        RAISE EXCEPTION 'Esta Orden de Servicio no está asignada a esa persona. '
                        'El jefe de taller es quien reparte el trabajo.';
    END IF;

    IF EXISTS (SELECT 1 FROM taller_os_tiempo
                WHERE tecnico_id = p_tecnico_id AND os_id = p_os_id AND fin IS NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    SELECT o.folio INTO v_otra
      FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
     WHERE t.tecnico_id = p_tecnico_id AND t.fin IS NULL;
    IF v_otra IS NOT NULL THEN
        RAISE EXCEPTION 'Esa persona ya está trabajando en %. Para cambiarla de trabajo, '
                        'el jefe de taller tiene que reasignarla.', v_otra;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM taller_os_asignacion
                    WHERE os_id = p_os_id AND tecnico_id = p_tecnico_id AND hasta IS NULL) THEN
        INSERT INTO taller_os_asignacion (os_id, tecnico_id, asignado_por, motivo)
        VALUES (p_os_id, p_tecnico_id, v_user, 'Asignada al arrancar el trabajo');
        UPDATE taller_os SET responsable_id = p_tecnico_id WHERE id = p_os_id;
    END IF;

    -- ¿Es la primera actividad de toda la visita?
    v_primera := NOT EXISTS (
        SELECT 1 FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
         WHERE o.ot_id = v_ot);

    INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
    VALUES (p_os_id, p_tecnico_id, v_user)
    RETURNING id INTO v_tramo;

    UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;

    -- [MIG475] La OT se pone en ejecución sola con la primera actividad. Nadie
    -- «arranca la OT»: la OT arranca porque alguien empezó a trabajar.
    SELECT estado::TEXT INTO v_ot_est FROM ordenes_trabajo WHERE id = v_ot;
    IF v_ot_est IN ('creada','asignada','pausada') THEN
        UPDATE ordenes_trabajo
           SET estado = 'en_ejecucion',
               fecha_inicio = COALESCE(fecha_inicio, NOW()),
               updated_at = NOW()
         WHERE id = v_ot;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'tramo_id', v_tramo,
                              'ot_arrancada', v_primera);
END;
$$;

-- ── 5 · Y el «iniciar» de la OT también exige medidores ─────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_iniciar_ejecucion_ot(
    p_ot_id       UUID,
    p_observacion TEXT DEFAULT NULL,
    p_tecnico_id  UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_falta TEXT;
BEGIN
    -- [MIG461] Desde una cuenta compartida hay que declarar quién trabaja.
    PERFORM fn_taller_exigir_tecnico_declarado(p_tecnico_id);
    -- [MIG475] Y sin el medidor anotado no se arranca: la visita quedaría sin
    -- punto de partida y las preventivas por horas se calculan sobre aire.
    v_falta := fn_taller_ot_medidores_listos(p_ot_id);
    IF v_falta IS NOT NULL THEN RAISE EXCEPTION '%', v_falta; END IF;

    RETURN rpc_taller_iniciar_ejecucion_ot_base(p_ot_id, p_observacion, p_tecnico_id);
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_ot_horas_plan(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_ot_horas_estimadas(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_ot_horas_os(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_ot_medidores_listos(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_ot_presupuesto(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_ot_horas_plan(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_ot_horas_estimadas(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_ot_medidores_listos(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_ot_presupuesto(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = 'rpc_taller_os_crear';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_os_crear quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = 'rpc_taller_iniciar_ejecucion_ot';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: iniciar_ejecucion_ot quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT NOT IN ('cerrada','cancelada')
       AND fn_taller_ot_horas_plan(ot.id) IS NOT NULL;
    RAISE NOTICE 'OT abiertas CON techo puesto por el planificador: %', v_n;

    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT NOT IN ('cerrada','cancelada')
       AND fn_taller_ot_horas_plan(ot.id) IS NULL;
    RAISE NOTICE 'OT abiertas SIN techo (el planificador no puso horas): %', v_n;

    RAISE NOTICE '=== lo que el checklist estima, como referencia ===';
    FOR r IN SELECT ot.folio, fn_taller_ot_horas_estimadas(ot.id) h
               FROM ordenes_trabajo ot
              WHERE ot.estado::TEXT NOT IN ('cerrada','cancelada')
              ORDER BY 2 DESC NULLS LAST LIMIT 3 LOOP
        RAISE NOTICE '   % · % h estimadas por el checklist', rpad(r.folio,20), r.h;
    END LOOP;

    RAISE NOTICE '=== cuántas OT abiertas NO podrían arrancar hoy por medidores ===';
    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT IN ('creada','asignada','pausada')
       AND fn_taller_ot_medidores_listos(ot.id) IS NOT NULL;
    RAISE NOTICE '   % (les falta anotar o confirmar el medidor)', v_n;
END
$mig$;

COMMIT;
