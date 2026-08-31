-- ============================================================================
-- MIG473 · La Orden de Servicio, y el reloj que sigue a la persona
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- De la reunión de operaciones: falta el escalón entre la OT y la no
-- conformidad. «El camión llega, se le asigna checklist y genera NC. Éstas las
-- analiza el jefe de taller y genera una orden de servicio donde indica quién la
-- va a realizar, la cantidad de horas y los repuestos. Una OT puede tener varias
-- OS.»
--
-- Y después, lo que de verdad decide el diseño:
-- «Ojo: una OS la empieza Joel y después se le asigna una OT o una OS de otro
-- equipo, y continúa otro trabajador. Esto es clave para el cálculo del bono.
-- Tener mapeado qué actividad ha hecho quién.»
--
-- ESO CAMBIA DÓNDE VIVE EL RELOJ
-- Hasta hoy el reloj era de la OT: `uq_taller_ejec_activa_ot` permite UNA
-- ejecución abierta por orden. Esa regla venía de suponer que una orden la hace
-- una persona de corrido, y el taller no funciona así: se cambia de equipo a
-- media mañana y alguien más retoma en la tarde.
--
-- Acá el reloj pasa a ser DE LA PERSONA. Y con eso viene la regla que de verdad
-- protege el bono:
--
--     UNA PERSONA SÓLO PUEDE TENER UN TRABAJO CORRIENDO A LA VEZ.
--
-- No es una restricción burocrática: es lo único que impide que las mismas dos
-- horas se cobren en dos órdenes distintas. Cuando Joel arranca la OS de otro
-- camión, la que tenía abierta se le cierra sola con el tiempo que llevaba, y
-- queda escrito por qué. Nadie tiene que acordarse de apretar pausa —y en un
-- taller nadie se acuerda—.
--
-- LO QUE ESTO ARREGLA DE PASO
-- El problema que MIG462 tuvo que parchear: como sólo una persona podía apretar
-- play por OT, el reparto del bono por tiempo medido era imposible en cuadrilla
-- y hubo que repartir por jornadas planificadas. Con el reloj por persona, dos
-- mecánicos trabajan en paralelo en el mismo camión —en OS distintas— y cada uno
-- acumula lo suyo.
--
-- LO QUE ESTA MIGRACIÓN NO HACE
-- No toca el bono todavía. El motor sigue pagando por OT como está en el acta.
-- Cuando exista tiempo real por persona y por OS, esa decisión se toma con
-- datos y no antes. Tampoco toca el reloj de la OT: convive, porque hay OT
-- abiertas con tiempo corriendo y no se les corta el piso.
-- ============================================================================

BEGIN;

-- ── 1 · La Orden de Servicio ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_os (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio           TEXT UNIQUE NOT NULL,
    ot_id           UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    titulo          TEXT NOT NULL,
    descripcion     TEXT,
    -- A quién se le encarga. NO es quién la hace: eso lo dice el reloj, que
    -- puede tener a varias personas distintas.
    responsable_id  UUID REFERENCES taller_tecnicos(id),
    horas_estimadas NUMERIC,
    estado          TEXT NOT NULL DEFAULT 'abierta',
    prioridad       TEXT,
    creada_por      UUID REFERENCES usuarios_perfil(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cerrada_por     UUID REFERENCES usuarios_perfil(id),
    cerrada_at      TIMESTAMPTZ,
    observacion_cierre TEXT,
    CONSTRAINT chk_os_estado CHECK (estado IN ('abierta','en_ejecucion','pausada','finalizada','anulada')),
    CONSTRAINT chk_os_horas  CHECK (horas_estimadas IS NULL OR horas_estimadas > 0)
);

COMMENT ON TABLE taller_os IS
    'Orden de Servicio: el paquete de ejecución dentro de una OT. Responde quién '
    'lo hace, en cuántas horas y con qué repuestos. Una OT puede tener varias.';
COMMENT ON COLUMN taller_os.responsable_id IS
    'A quién se le encarga. Quién lo hizo de verdad sale de taller_os_tiempo, '
    'que puede tener varias personas.';

CREATE INDEX IF NOT EXISTS idx_taller_os_ot ON taller_os (ot_id);
CREATE INDEX IF NOT EXISTS idx_taller_os_estado ON taller_os (estado)
    WHERE estado IN ('abierta','en_ejecucion','pausada');

-- ── 2 · Qué no conformidades resuelve ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_os_nc (
    os_id             UUID NOT NULL REFERENCES taller_os(id) ON DELETE CASCADE,
    no_conformidad_id UUID NOT NULL REFERENCES no_conformidades(id) ON DELETE CASCADE,
    PRIMARY KEY (os_id, no_conformidad_id)
);

COMMENT ON TABLE taller_os_nc IS
    'Las NC que resuelve cada OS. Una OS agrupa varias: 32 NC no son 32 OS, son '
    'tres o cuatro paquetes por sistema.';

-- Una NC no puede estar en dos OS: si no, dos personas cobran el mismo arreglo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_os_nc_una_sola_os
    ON taller_os_nc (no_conformidad_id);

-- ── 3 · El reloj, por persona ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_os_tiempo (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    os_id        UUID NOT NULL REFERENCES taller_os(id) ON DELETE CASCADE,
    tecnico_id   UUID NOT NULL REFERENCES taller_tecnicos(id),
    inicio       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fin          TIMESTAMPTZ,
    segundos     INT,
    cerrado_por_sistema BOOLEAN NOT NULL DEFAULT FALSE,
    motivo_cierre TEXT,
    registrado_por UUID REFERENCES usuarios_perfil(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_os_tiempo_orden CHECK (fin IS NULL OR fin >= inicio)
);

COMMENT ON TABLE taller_os_tiempo IS
    'Quién trabajó en qué OS y cuánto. Un tramo por persona y por vez: si Joel '
    'empieza, se va a otro equipo y vuelve, son dos tramos suyos.';
COMMENT ON COLUMN taller_os_tiempo.cerrado_por_sistema IS
    'TRUE cuando el tramo lo cerró el sistema porque la persona arrancó otro '
    'trabajo. En el taller nadie se acuerda de apretar pausa.';

CREATE INDEX IF NOT EXISTS idx_os_tiempo_os ON taller_os_tiempo (os_id);
CREATE INDEX IF NOT EXISTS idx_os_tiempo_tecnico ON taller_os_tiempo (tecnico_id, inicio DESC);

-- LA REGLA QUE PROTEGE EL BONO: una persona, un trabajo abierto a la vez.
-- Sin esto, las mismas dos horas se pueden cobrar en dos órdenes distintas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_os_tiempo_abierto_por_persona
    ON taller_os_tiempo (tecnico_id) WHERE fin IS NULL;

-- ── 4 · El folio de la OS ───────────────────────────────────────────────────
--
-- Cuelga del folio de la OT: OS-202608-00014-1, -2, -3. Se lee de un vistazo a
-- qué visita pertenece, que es justo lo que el papel viejo no dejaba ver.
CREATE OR REPLACE FUNCTION fn_taller_os_folio(p_ot_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_folio_ot TEXT;
    v_n INT;
BEGIN
    SELECT folio::TEXT INTO v_folio_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_folio_ot IS NULL THEN RAISE EXCEPTION 'Esa OT no existe.'; END IF;
    SELECT COUNT(*) + 1 INTO v_n FROM taller_os WHERE ot_id = p_ot_id;
    RETURN 'OS-' || substring(v_folio_ot from 4) || '-' || v_n;
END;
$$;

-- ── 5 · Crear la OS desde las no conformidades ──────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_crear(
    p_ot_id           UUID,
    p_titulo          TEXT,
    p_nc_ids          UUID[] DEFAULT NULL,
    p_responsable_id  UUID   DEFAULT NULL,
    p_horas_estimadas NUMERIC DEFAULT NULL,
    p_descripcion     TEXT   DEFAULT NULL,
    p_prioridad       TEXT   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT;
    v_os    UUID;
    v_folio TEXT;
    v_n     INT := 0;
    v_ajena TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('jefe_mantenimiento','administrador','subgerente_operaciones',
                     'jefe_operaciones','planificador','supervisor') THEN
        RAISE EXCEPTION 'Armar una Orden de Servicio es de la jefatura de taller o planificación.';
    END IF;

    IF length(COALESCE(TRIM(p_titulo),'')) < 4 THEN
        RAISE EXCEPTION 'Ponle un título a la OS: es lo que el mecánico va a leer en su teléfono.';
    END IF;

    -- Las NC tienen que ser de esta misma OT: una OS no cruza equipos.
    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        SELECT string_agg(nc.id::TEXT, ', ') INTO v_ajena
          FROM no_conformidades nc
         WHERE nc.id = ANY(p_nc_ids) AND nc.ot_id IS DISTINCT FROM p_ot_id;
        IF v_ajena IS NOT NULL THEN
            RAISE EXCEPTION 'Hay no conformidades que no son de esta OT. Una OS resuelve trabajo de un solo equipo.';
        END IF;
    END IF;

    v_folio := fn_taller_os_folio(p_ot_id);

    INSERT INTO taller_os (folio, ot_id, titulo, descripcion, responsable_id,
                           horas_estimadas, prioridad, creada_por)
    VALUES (v_folio, p_ot_id, TRIM(p_titulo), NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
            p_responsable_id, p_horas_estimadas, NULLIF(TRIM(COALESCE(p_prioridad,'')),''), v_user)
    RETURNING id INTO v_os;

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        INSERT INTO taller_os_nc (os_id, no_conformidad_id)
        SELECT v_os, x FROM unnest(p_nc_ids) AS x
        ON CONFLICT (no_conformidad_id) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'os_id', v_os, 'folio', v_folio,
                              'nc_asignadas', v_n);
END;
$$;

-- ── 6 · Empezar: y lo que la persona tenía abierto se cierra solo ───────────
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
    v_prev   RECORD;
    v_tramo  UUID;
    v_msg    TEXT := NULL;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_tecnico_id IS NULL THEN
        RAISE EXCEPTION 'Hay que decir quién empieza: el tiempo que se mide decide el bono.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM taller_tecnicos WHERE id = p_tecnico_id AND COALESCE(activo, TRUE)) THEN
        RAISE EXCEPTION 'Ese técnico no existe o está inactivo.';
    END IF;

    SELECT estado INTO v_estado FROM taller_os WHERE id = p_os_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_estado IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %.', v_estado;
    END IF;

    -- Si ya está trabajando en esta misma OS, no se abre otro tramo.
    IF EXISTS (SELECT 1 FROM taller_os_tiempo
                WHERE tecnico_id = p_tecnico_id AND os_id = p_os_id AND fin IS NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    -- Lo que tenía abierto en OTRA OS se cierra con su tiempo. Es la regla que
    -- impide que las mismas horas se cobren dos veces.
    SELECT t.id, t.os_id, t.inicio, o.folio
      INTO v_prev
      FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
     WHERE t.tecnico_id = p_tecnico_id AND t.fin IS NULL;

    IF v_prev.id IS NOT NULL THEN
        UPDATE taller_os_tiempo
           SET fin = NOW(),
               segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
               cerrado_por_sistema = TRUE,
               motivo_cierre = 'Se fue a trabajar en otra Orden de Servicio'
         WHERE id = v_prev.id;

        UPDATE taller_os SET estado = 'pausada', updated_at = NOW()
         WHERE id = v_prev.os_id
           AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo WHERE os_id = v_prev.os_id AND fin IS NULL);

        v_msg := 'Se cerró tu tramo abierto en ' || v_prev.folio || '.';
    END IF;

    INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
    VALUES (p_os_id, p_tecnico_id, v_user)
    RETURNING id INTO v_tramo;

    UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'tramo_id', v_tramo, 'aviso', v_msg);
END;
$$;

-- ── 7 · Parar ───────────────────────────────────────────────────────────────
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
    v_n INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

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

-- ── 8 · Terminar la OS ──────────────────────────────────────────────────────
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
    v_seg  NUMERIC;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    -- Los tramos abiertos se cierran con la OS: una OS terminada no puede
    -- seguir sumando horas.
    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           cerrado_por_sistema = TRUE,
           motivo_cierre = 'La OS se dio por terminada'
     WHERE os_id = p_os_id AND fin IS NULL;

    UPDATE taller_os
       SET estado = 'finalizada', cerrada_por = v_user, cerrada_at = NOW(),
           observacion_cierre = NULLIF(TRIM(COALESCE(p_observacion,'')),''),
           updated_at = NOW()
     WHERE id = p_os_id;

    SELECT COALESCE(sum(segundos),0)/3600.0 INTO v_seg
      FROM taller_os_tiempo WHERE os_id = p_os_id;

    RETURN jsonb_build_object('success', TRUE, 'horas_reales', round(v_seg, 2));
END;
$$;

-- ── 9 · Qué hizo cada quién ─────────────────────────────────────────────────
--
-- Es la respuesta a «tener mapeado qué actividad ha hecho quién». Una fila por
-- persona y por OS, con las horas que puso.
CREATE OR REPLACE VIEW v_taller_os_personas AS
SELECT
    o.id            AS os_id,
    o.folio         AS os_folio,
    o.ot_id,
    ot.folio        AS ot_folio,
    a.patente,
    o.titulo,
    o.estado,
    o.horas_estimadas,
    t.tecnico_id,
    tc.nombre       AS tecnico,
    count(*)                          AS tramos,
    min(t.inicio)                     AS primer_inicio,
    max(COALESCE(t.fin, NOW()))       AS ultimo_movimiento,
    round(SUM(COALESCE(t.segundos,
        GREATEST(0, EXTRACT(EPOCH FROM (NOW() - t.inicio))::INT)))::numeric / 3600.0, 2) AS horas,
    bool_or(t.fin IS NULL)            AS trabajando_ahora
  FROM taller_os o
  JOIN ordenes_trabajo ot ON ot.id = o.ot_id
  JOIN activos a ON a.id = ot.activo_id
  JOIN taller_os_tiempo t ON t.os_id = o.id
  JOIN taller_tecnicos tc ON tc.id = t.tecnico_id
 GROUP BY o.id, o.folio, o.ot_id, ot.folio, a.patente, o.titulo, o.estado,
          o.horas_estimadas, t.tecnico_id, tc.nombre;

COMMENT ON VIEW v_taller_os_personas IS
    'Qué actividad hizo quién y por cuántas horas. Es la base para medir '
    'estimado contra real, y para el día en que el bono se mida por OS.';

-- ── 10 · La OS con su resumen ───────────────────────────────────────────────
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
      WHERE t.os_id = o.id)                                                          AS quienes
  FROM taller_os o
  JOIN ordenes_trabajo ot ON ot.id = o.ot_id
  JOIN activos a ON a.id = ot.activo_id
  LEFT JOIN taller_tecnicos tr ON tr.id = o.responsable_id;

-- ── 11 · En qué anda cada mecánico ahora mismo ──────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_en_curso()
RETURNS TABLE (
    tecnico_id UUID,
    tecnico    TEXT,
    os_id      UUID,
    os_folio   TEXT,
    titulo     TEXT,
    patente    TEXT,
    desde      TIMESTAMPTZ,
    horas      NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT tc.id, tc.nombre::TEXT, o.id, o.folio, o.titulo, a.patente::TEXT, t.inicio,
           round(EXTRACT(EPOCH FROM (NOW() - t.inicio))::numeric / 3600.0, 2)
      FROM taller_os_tiempo t
      JOIN taller_tecnicos tc ON tc.id = t.tecnico_id
      JOIN taller_os o ON o.id = t.os_id
      JOIN ordenes_trabajo ot ON ot.id = o.ot_id
      JOIN activos a ON a.id = ot.activo_id
     WHERE t.fin IS NULL
     ORDER BY t.inicio;
$$;

ALTER TABLE taller_os        ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_os_nc     ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_os_tiempo ENABLE ROW LEVEL SECURITY;
-- Sin políticas: se llega por los RPC, que son SECURITY DEFINER.

REVOKE ALL ON FUNCTION fn_taller_os_folio(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_iniciar(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_pausar(UUID, UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_finalizar(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_os_en_curso() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_os_crear(UUID, TEXT, UUID[], UUID, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_iniciar(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_pausar(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_finalizar(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_os_en_curso() TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname IN
       ('rpc_taller_os_crear','rpc_taller_os_iniciar','rpc_taller_os_pausar',
        'rpc_taller_os_finalizar','rpc_taller_os_en_curso','fn_taller_os_folio');
    IF v_n <> 6 THEN RAISE EXCEPTION 'FALLO: faltan funciones de la OS (%)', v_n; END IF;

    -- La regla que protege el bono tiene que existir como índice, no como buena
    -- intención en el código.
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_os_tiempo_abierto_por_persona') THEN
        RAISE EXCEPTION 'FALLO: falta el índice que impide dos trabajos abiertos por persona';
    END IF;
    RAISE NOTICE 'una persona no puede tener dos trabajos corriendo: está en un índice único';

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_os_nc_una_sola_os') THEN
        RAISE EXCEPTION 'FALLO: falta el índice que impide una NC en dos OS';
    END IF;
    RAISE NOTICE 'una NC no puede estar en dos OS: nadie cobra dos veces el mismo arreglo';

    SELECT count(*) INTO v_n FROM taller_os;
    RAISE NOTICE 'órdenes de servicio: % (arranca en cero)', v_n;

    -- El material sobre el que se va a trabajar.
    SELECT count(*) INTO v_n FROM no_conformidades WHERE NOT COALESCE(resuelto,FALSE);
    RAISE NOTICE 'no conformidades abiertas esperando ser agrupadas: %', v_n;
    FOR r IN SELECT ot.folio, count(nc.id) n
               FROM ordenes_trabajo ot JOIN no_conformidades nc ON nc.ot_id = ot.id
              WHERE NOT COALESCE(nc.resuelto,FALSE)
              GROUP BY ot.folio ORDER BY 2 DESC LIMIT 3 LOOP
        RAISE NOTICE '   % tiene % NC abiertas', r.folio, r.n;
    END LOOP;
END
$mig$;

COMMIT;
