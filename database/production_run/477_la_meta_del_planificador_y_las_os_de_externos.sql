-- ============================================================================
-- MIG477 · La meta del planificador, y las OS que se van afuera
-- ============================================================================
--
-- DOS COSAS QUE PRECISÓ MANUEL
--
--   1) «Dentro del tipo de tarea está el optimizado y el normal, el planificador
--      decide dentro de esos límites.»
--
--      Tenía razón el reclamo: hasta ahora el sistema mostraba los tres tramos
--      pero no le pedía a nadie que eligiera uno. El plazo salía de contar los
--      días marcados y después se avisaba en qué tramo habían caído — al revés
--      de como se planifica. Ahora el planificador COMPROMETE una meta y los
--      días se miden contra ella.
--
--      Las HORAS no cambian con el tramo, y conviene decir por qué: el trabajo
--      es el mismo, lo que cambia es en cuántos días se hace. Optimizado no es
--      trabajar menos, es terminar antes.
--
--   2) «Las OS pueden ser para externos también. Las crea el jefe de taller, y
--      cuando son para externos debe llevar autorización del gerente.»
--
--      La OT ya tenía esto desde MIG446/447, pero a nivel de visita completa.
--      Con la OS el grano es el correcto: de una misma visita, el motor se manda
--      afuera y los frenos los hace el taller.
--
-- LO QUE UNA OS EXTERNA NO HACE
-- No genera bono. Es la misma regla de la OT externa, y por el mismo motivo: el
-- incentivo paga el trabajo del taller. Y sin la autorización de gerencia no
-- arranca — igual que no se cierra una OT externa sin autorizar.
--
-- QUIÉN AUTORIZA
-- Administración y subgerencia de operaciones. Dejé FUERA a jefe_operaciones a
-- propósito, porque Manuel dijo «gerente»: si en la práctica el jefe de
-- operaciones también debe poder, es agregar un rol a la lista.
-- ============================================================================

BEGIN;

-- ── 1 · La meta que compromete el planificador ──────────────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS meta_tramo TEXT;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ot_meta_tramo') THEN
        ALTER TABLE ordenes_trabajo
          ADD CONSTRAINT chk_ot_meta_tramo
          CHECK (meta_tramo IS NULL OR meta_tramo IN ('optimizado','normal'));
    END IF;
END
$c$;

COMMENT ON COLUMN ordenes_trabajo.meta_tramo IS
    'A qué se comprometió el planificador: optimizado o normal. Los días de la '
    'visita se miden contra esta meta, no contra el tramo que salga al final.';

-- Cuántos días le da la meta elegida a esta visita.
CREATE OR REPLACE FUNCTION fn_taller_ot_dias_meta(p_ot_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE ot.meta_tramo
             WHEN 'optimizado' THEN co.dias_optimizado
             WHEN 'normal'     THEN co.dias_normal
             ELSE NULL
           END
      FROM ordenes_trabajo ot
      LEFT JOIN taller_bono_concepto co
             ON co.concepto = fn_taller_ot_concepto(ot.id)
            AND co.parametros_id = (SELECT id FROM taller_bono_parametros
                                     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC LIMIT 1)
     WHERE ot.id = p_ot_id;
$$;

CREATE OR REPLACE FUNCTION rpc_taller_ot_set_meta(p_ot_id UUID, p_meta TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_est TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'La meta de la visita la fija quien planifica.';
    END IF;
    IF p_meta IS NOT NULL AND p_meta NOT IN ('optimizado','normal') THEN
        RAISE EXCEPTION 'La meta es «optimizado» o «normal».';
    END IF;

    SELECT estado::TEXT INTO v_est FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Esa OT no existe.'; END IF;
    IF v_est IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RAISE EXCEPTION 'La visita ya está cerrada: la meta no se cambia después.';
    END IF;

    UPDATE ordenes_trabajo SET meta_tramo = p_meta, updated_at = NOW() WHERE id = p_ot_id;
    RETURN jsonb_build_object('success', TRUE, 'meta', p_meta,
                              'dias', fn_taller_ot_dias_meta(p_ot_id));
END;
$$;

-- ── 2 · La OS que se va afuera ──────────────────────────────────────────────
ALTER TABLE taller_os
  ADD COLUMN IF NOT EXISTS es_externo         BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS proveedor_externo  TEXT,
  ADD COLUMN IF NOT EXISTS motivo_externo     TEXT,
  ADD COLUMN IF NOT EXISTS externo_autorizado_por UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS externo_autorizado_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS externo_solicitado_por UUID REFERENCES usuarios_perfil(id);

COMMENT ON COLUMN taller_os.es_externo IS
    'El trabajo se manda a un tercero. Necesita autorización de gerencia para '
    'arrancar, y no genera bono: el incentivo paga el trabajo del taller.';

CREATE OR REPLACE FUNCTION rpc_taller_os_declarar_externo(
    p_os_id     UUID,
    p_externo   BOOLEAN,
    p_proveedor TEXT DEFAULT NULL,
    p_motivo    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_est  TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Mandar un trabajo afuera lo declara la jefatura de taller.';
    END IF;

    SELECT estado INTO v_est FROM taller_os WHERE id = p_os_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_est = 'finalizada' THEN
        RAISE EXCEPTION 'Esa OS ya está terminada.';
    END IF;

    IF p_externo THEN
        IF length(COALESCE(TRIM(p_proveedor),'')) < 3 THEN
            RAISE EXCEPTION 'Escribe qué empresa va a hacer el trabajo.';
        END IF;
        IF length(COALESCE(TRIM(p_motivo),'')) < 10 THEN
            RAISE EXCEPTION 'Escribe por qué sale del taller: es lo que va a leer quien autoriza.';
        END IF;
    END IF;

    UPDATE taller_os
       SET es_externo = p_externo,
           proveedor_externo = CASE WHEN p_externo THEN TRIM(p_proveedor) END,
           motivo_externo    = CASE WHEN p_externo THEN TRIM(p_motivo) END,
           externo_solicitado_por = CASE WHEN p_externo THEN v_user END,
           -- Cambiar la declaración borra la autorización: lo que se autorizó
           -- fue este proveedor y este motivo, no cualquier otro.
           externo_autorizado_por = NULL,
           externo_autorizado_at  = NULL,
           updated_at = NOW()
     WHERE id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'es_externo', p_externo);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_taller_os_autorizar_externo(p_os_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_os   RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Autorizar trabajo de terceros es de gerencia.';
    END IF;

    SELECT folio, es_externo, externo_solicitado_por INTO v_os
      FROM taller_os WHERE id = p_os_id;
    IF v_os.folio IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF NOT v_os.es_externo THEN
        RAISE EXCEPTION 'La % no está declarada como trabajo de externo.', v_os.folio;
    END IF;
    -- Quien lo pide no lo autoriza. Es la misma regla de MIG447.
    IF v_os.externo_solicitado_por = v_user THEN
        RAISE EXCEPTION 'No puedes autorizar un trabajo externo que declaraste tú.';
    END IF;

    UPDATE taller_os
       SET externo_autorizado_por = v_user, externo_autorizado_at = NOW(), updated_at = NOW()
     WHERE id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'folio', v_os.folio);
END;
$$;

-- ── 3 · Una OS externa sin autorizar no arranca ─────────────────────────────
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
    v_os     RECORD;
    v_tramo  UUID;
    v_otra   TEXT;
    v_ot_est TEXT;
    v_falta  TEXT;
    v_primera BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_tecnico_id IS NULL THEN
        RAISE EXCEPTION 'Hay que decir quién empieza: el tiempo que se mide decide el bono.';
    END IF;

    SELECT o.estado, o.ot_id, o.es_externo, o.externo_autorizado_at, o.folio
      INTO v_os FROM taller_os o WHERE o.id = p_os_id;
    IF v_os.estado IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_os.estado IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %.', v_os.estado;
    END IF;

    -- [MIG477] Trabajo de terceros: sin el visto bueno de gerencia no empieza.
    IF v_os.es_externo AND v_os.externo_autorizado_at IS NULL THEN
        RAISE EXCEPTION 'La % es trabajo de un externo y todavía no la autoriza gerencia.', v_os.folio;
    END IF;

    v_falta := fn_taller_ot_medidores_listos(v_os.ot_id);
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

    v_primera := NOT EXISTS (
        SELECT 1 FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
         WHERE o.ot_id = v_os.ot_id);

    INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
    VALUES (p_os_id, p_tecnico_id, v_user)
    RETURNING id INTO v_tramo;

    UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;

    SELECT estado::TEXT INTO v_ot_est FROM ordenes_trabajo WHERE id = v_os.ot_id;
    IF v_ot_est IN ('creada','asignada','pausada') THEN
        UPDATE ordenes_trabajo
           SET estado = 'en_ejecucion',
               fecha_inicio = COALESCE(fecha_inicio, NOW()),
               updated_at = NOW()
         WHERE id = v_os.ot_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'tramo_id', v_tramo, 'ot_arrancada', v_primera);
END;
$$;

-- ── 4 · Y una OS externa no cuenta para el bono ─────────────────────────────
--
-- Las horas de un tercero no son horas del taller. Se excluyen del reparto y del
-- techo, para que mandar trabajo afuera no infle ni el bono ni el presupuesto.
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
       AND NOT o.es_externo
       AND (p_excluir_os IS NULL OR o.id <> p_excluir_os);
$$;

-- Las columnas nuevas van AL FINAL: CREATE OR REPLACE VIEW no deja insertarlas
-- al medio, y renombrar en cascada rompería a quien ya lee la vista.
CREATE OR REPLACE VIEW v_taller_os AS
SELECT
    o.id, o.folio, o.ot_id, ot.folio AS ot_folio, a.patente, a.nombre AS equipo,
    o.titulo, o.descripcion, o.estado, o.prioridad, o.horas_estimadas,
    o.responsable_id, tr.nombre AS responsable,
    o.created_at, o.cerrada_at,
    (SELECT count(*) FROM taller_os_nc n WHERE n.os_id = o.id)                       AS ncs,
    (SELECT count(*) FROM taller_os_tiempo t WHERE t.os_id = o.id AND t.fin IS NULL) AS tramos_abiertos,
    COALESCE((SELECT round(sum(COALESCE(t.segundos,
                GREATEST(0, EXTRACT(EPOCH FROM (NOW() - t.inicio))::INT)))::numeric / 3600.0, 2)
                FROM taller_os_tiempo t WHERE t.os_id = o.id), 0)                    AS horas_reales,
    (SELECT string_agg(DISTINCT tc.nombre, ', ')
       FROM taller_os_tiempo t JOIN taller_tecnicos tc ON tc.id = t.tecnico_id
      WHERE t.os_id = o.id)                                                          AS quienes,
    o.es_externo, o.proveedor_externo, o.motivo_externo, o.externo_autorizado_at,
    (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = o.externo_autorizado_por)
        AS externo_autorizado_por
  FROM taller_os o
  JOIN ordenes_trabajo ot ON ot.id = o.ot_id
  JOIN activos a ON a.id = ot.activo_id
  LEFT JOIN taller_tecnicos tr ON tr.id = o.responsable_id;

REVOKE ALL ON FUNCTION fn_taller_ot_dias_meta(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_ot_set_meta(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_declarar_externo(UUID, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_autorizar_externo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_ot_dias_meta(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_ot_set_meta(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_declarar_externo(UUID, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_autorizar_externo(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public'
       AND p.proname IN ('rpc_taller_ot_set_meta','rpc_taller_os_declarar_externo',
                         'rpc_taller_os_autorizar_externo','fn_taller_ot_dias_meta');
    IF v_n <> 4 THEN RAISE EXCEPTION 'FALLO: faltan funciones (%)', v_n; END IF;

    RAISE NOTICE '=== los dos límites entre los que decide el planificador ===';
    FOR r IN SELECT concepto, horas_estandar, dias_optimizado, dias_normal
               FROM rpc_taller_conceptos_bono() LOOP
        RAISE NOTICE '  % · % h · optimizado en % día(s) · normal en % día(s)',
            r.concepto, r.horas_estandar, r.dias_optimizado, r.dias_normal;
    END LOOP;

    SELECT count(*) INTO v_n FROM ordenes_trabajo WHERE meta_tramo IS NOT NULL;
    RAISE NOTICE 'OT con meta comprometida: % (arranca en cero)', v_n;

    SELECT count(*) INTO v_n FROM taller_os WHERE es_externo;
    RAISE NOTICE 'OS declaradas de externo: %', v_n;
    RAISE NOTICE 'una OS externa no arranca sin gerencia, y no cuenta para el bono ni para el techo';
END
$mig$;

COMMIT;
