-- ============================================================================
-- MIG474 · Al operador lo mueve el jefe, no él mismo
-- ============================================================================
--
-- LO QUE CORRIGIÓ MANUEL
-- «Ojo: el que mueve a la persona es el jefe de taller, el operador sólo recibe
-- órdenes. Ojo con eso. Y ésa es la clave.»
--
-- Y tiene razón: MIG473 lo hizo al revés. `rpc_taller_os_iniciar` no tenía NINGÚN
-- control de rol —cualquiera con sesión podía arrancar cualquier OS a nombre de
-- cualquier técnico— y, peor que el permiso, el modelo estaba equivocado: daba
-- por hecho que el mecánico elige en qué trabaja. En el taller no elige: le
-- asignan.
--
-- LA DIFERENCIA NO ES DE PERMISOS, ES DE QUIÉN DECIDE
--
--     ASIGNAR   es del jefe. Es «la decisión»: a quién le toca esta OS.
--     EMPEZAR   es del operador, pero SÓLO sobre lo que le asignaron.
--     PAUSAR    es del operador: se fue a colación, se quedó sin repuesto.
--     MOVER     es del jefe. Y mover es reasignar, no «que el otro apriete play».
--
-- EL AUTO-CIERRE ESTABA EN EL LUGAR EQUIVOCADO
-- En MIG473, el tramo abierto se cerraba cuando la persona ARRANCABA otra OS.
-- Eso sólo funciona si la persona se mueve sola. Ahora el cierre automático
-- ocurre cuando el JEFE LA REASIGNA, que es el momento real en que Joel deja los
-- frenos y se va al otro camión. El tramo queda cerrado con su tiempo, con quién
-- lo movió y por qué.
--
-- LO QUE SE MANTIENE
-- La regla que protege el bono no cambia: una persona, un trabajo corriendo a la
-- vez. Sigue siendo un índice único. Lo que cambia es quién puede provocar el
-- movimiento.
--
-- LA CUENTA COMPARTIDA
-- El taller entra con una cuenta de todos (MIG461), así que el operador declara
-- su nombre para empezar. Eso ya no permite inventar nada: sólo puede empezar
-- una OS que el jefe le asignó ANTES. La cuenta compartida deja de ser una
-- llave y pasa a ser un teclado.
-- ============================================================================

BEGIN;

-- ── 1 · La asignación es un hecho con autor y fecha ─────────────────────────
CREATE TABLE IF NOT EXISTS taller_os_asignacion (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    os_id        UUID NOT NULL REFERENCES taller_os(id) ON DELETE CASCADE,
    tecnico_id   UUID NOT NULL REFERENCES taller_tecnicos(id),
    desde        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hasta        TIMESTAMPTZ,
    asignado_por UUID REFERENCES usuarios_perfil(id),
    motivo       TEXT,
    motivo_fin   TEXT,
    CONSTRAINT chk_os_asig_orden CHECK (hasta IS NULL OR hasta >= desde)
);

COMMENT ON TABLE taller_os_asignacion IS
    'A quién le tocó cada OS y desde cuándo. La escribe el jefe: mover a alguien '
    'de un trabajo a otro es una decisión, y las decisiones tienen autor.';

CREATE INDEX IF NOT EXISTS idx_os_asig_os ON taller_os_asignacion (os_id);
CREATE INDEX IF NOT EXISTS idx_os_asig_tecnico ON taller_os_asignacion (tecnico_id, desde DESC);

-- Una persona no puede estar asignada a dos OS a la vez: si lo estuviera, no
-- habría forma de saber en cuál debe estar trabajando.
CREATE UNIQUE INDEX IF NOT EXISTS uq_os_asig_vigente_por_persona
    ON taller_os_asignacion (tecnico_id) WHERE hasta IS NULL;

-- ── 2 · Quién puede mover a quién ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_es_jefatura()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT fn_user_rol() IN ('jefe_mantenimiento','administrador','subgerente_operaciones',
                             'jefe_operaciones','planificador','supervisor');
$$;

-- ── 3 · Asignar / mover: la acción del jefe ─────────────────────────────────
--
-- Es la que cierra el tramo anterior. Mover a alguien es sacarlo de donde
-- estaba, y eso incluye parar su reloj.
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
    v_prev  RECORD;
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

    -- Sacarlo de donde estaba: se cierra la asignación Y el reloj.
    SELECT a.id, a.os_id, o.folio INTO v_prev
      FROM taller_os_asignacion a JOIN taller_os o ON o.id = a.os_id
     WHERE a.tecnico_id = p_tecnico_id AND a.hasta IS NULL;

    IF v_prev.id IS NOT NULL THEN
        UPDATE taller_os_asignacion
           SET hasta = NOW(),
               motivo_fin = 'Reasignado a otra Orden de Servicio'
         WHERE id = v_prev.id;
        v_aviso := 'Se le sacó de ' || v_prev.folio || '.';
    END IF;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           cerrado_por_sistema = TRUE,
           motivo_cierre = 'El jefe lo movió a otro trabajo'
     WHERE tecnico_id = p_tecnico_id AND fin IS NULL;

    UPDATE taller_os o SET estado = 'pausada', updated_at = NOW()
     WHERE o.id = v_prev.os_id AND o.estado = 'en_ejecucion'
       AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo t WHERE t.os_id = o.id AND t.fin IS NULL);

    INSERT INTO taller_os_asignacion (os_id, tecnico_id, asignado_por, motivo)
    VALUES (p_os_id, p_tecnico_id, v_user, NULLIF(TRIM(COALESCE(p_motivo,'')),''));

    -- El responsable de la OS es siempre el que la tiene asignada ahora.
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

-- ── 4 · Sacar a alguien sin ponerlo en otra ─────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_desasignar(
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
    v_n INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Sacar a alguien de un trabajo es del jefe de taller.';
    END IF;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           cerrado_por_sistema = TRUE,
           motivo_cierre = COALESCE(NULLIF(TRIM(COALESCE(p_motivo,'')),''), 'El jefe lo sacó del trabajo')
     WHERE tecnico_id = p_tecnico_id AND fin IS NULL;

    UPDATE taller_os_asignacion
       SET hasta = NOW(), motivo_fin = NULLIF(TRIM(COALESCE(p_motivo,'')),'')
     WHERE tecnico_id = p_tecnico_id AND hasta IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    RETURN jsonb_build_object('success', TRUE, 'sacado_de', v_n);
END;
$$;

-- ── 5 · Empezar: sólo lo que te asignaron ───────────────────────────────────
--
-- Acá estaba el agujero de MIG473. Ahora:
--   · la jefatura puede arrancar a nombre de quien sea (está al lado del equipo);
--   · el operador sólo puede arrancar una OS que le asignaron ANTES.
--
-- Y ya no cierra el tramo de otra OS: si el operador estuviera en otra, es que
-- el jefe no lo ha movido, y moverlo no es decisión suya.
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
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_tecnico_id IS NULL THEN
        RAISE EXCEPTION 'Hay que decir quién empieza: el tiempo que se mide decide el bono.';
    END IF;

    SELECT estado INTO v_estado FROM taller_os WHERE id = p_os_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_estado IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %.', v_estado;
    END IF;

    -- El operador sólo trabaja en lo que le asignaron. La jefatura no necesita
    -- asignación previa: está parada al lado del equipo.
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

    -- Si está andando en otra, el que lo saca es el jefe. Acá se avisa y se
    -- para: dejar que el propio operador se mueva es justo lo que se corrige.
    SELECT o.folio INTO v_otra
      FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
     WHERE t.tecnico_id = p_tecnico_id AND t.fin IS NULL;
    IF v_otra IS NOT NULL THEN
        RAISE EXCEPTION 'Esa persona ya está trabajando en %. Para cambiarla de trabajo, '
                        'el jefe de taller tiene que reasignarla.', v_otra;
    END IF;

    -- Asignación implícita cuando arranca la jefatura sin haber asignado antes.
    IF NOT EXISTS (SELECT 1 FROM taller_os_asignacion
                    WHERE os_id = p_os_id AND tecnico_id = p_tecnico_id AND hasta IS NULL) THEN
        INSERT INTO taller_os_asignacion (os_id, tecnico_id, asignado_por, motivo)
        VALUES (p_os_id, p_tecnico_id, v_user, 'Asignada al arrancar el trabajo');
        UPDATE taller_os SET responsable_id = p_tecnico_id WHERE id = p_os_id;
    END IF;

    INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
    VALUES (p_os_id, p_tecnico_id, v_user)
    RETURNING id INTO v_tramo;

    UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'tramo_id', v_tramo);
END;
$$;

-- ── 6 · En qué anda cada uno, y a qué está asignado ─────────────────────────
CREATE OR REPLACE VIEW v_taller_os_asignacion_vigente AS
SELECT
    a.tecnico_id,
    tc.nombre        AS tecnico,
    a.os_id,
    o.folio          AS os_folio,
    o.titulo,
    ot.folio         AS ot_folio,
    act.patente,
    a.desde          AS asignado_desde,
    (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = a.asignado_por) AS asignado_por,
    a.motivo,
    EXISTS (SELECT 1 FROM taller_os_tiempo t
             WHERE t.tecnico_id = a.tecnico_id AND t.os_id = a.os_id AND t.fin IS NULL) AS trabajando
  FROM taller_os_asignacion a
  JOIN taller_tecnicos tc ON tc.id = a.tecnico_id
  JOIN taller_os o ON o.id = a.os_id
  JOIN ordenes_trabajo ot ON ot.id = o.ot_id
  JOIN activos act ON act.id = ot.activo_id
 WHERE a.hasta IS NULL;

COMMENT ON VIEW v_taller_os_asignacion_vigente IS
    'A qué está asignado cada mecánico ahora y si está trabajando o no. '
    'Asignado sin trabajar es una pregunta legítima del jefe.';

REVOKE ALL ON FUNCTION fn_taller_es_jefatura() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_asignar(UUID, UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_desasignar(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_es_jefatura() TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_asignar(UUID, UUID, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_desasignar(UUID, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public'
       AND p.proname IN ('rpc_taller_os_asignar','rpc_taller_os_desasignar','fn_taller_es_jefatura');
    IF v_n <> 3 THEN RAISE EXCEPTION 'FALLO: faltan funciones de asignación (%)', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_os_asig_vigente_por_persona') THEN
        RAISE EXCEPTION 'FALLO: falta el índice de una asignación vigente por persona';
    END IF;
    RAISE NOTICE 'una persona no puede estar asignada a dos OS a la vez';

    -- `iniciar` ya no puede quedar sin control de rol.
    IF position('fn_taller_es_jefatura' in
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='rpc_taller_os_iniciar')) = 0 THEN
        RAISE EXCEPTION 'FALLO: rpc_taller_os_iniciar quedó sin control de quién puede arrancar';
    END IF;
    RAISE NOTICE 'el operador sólo puede empezar lo que el jefe le asignó';

    SELECT count(*) INTO v_n FROM taller_os_asignacion WHERE hasta IS NULL;
    RAISE NOTICE 'asignaciones vigentes: % (arranca en cero)', v_n;
END
$mig$;

COMMIT;
