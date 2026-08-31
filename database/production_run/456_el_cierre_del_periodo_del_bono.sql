-- ============================================================================
-- MIG456 · El cierre del período del bono, y la cartola del trabajador
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 31-08-2026: «haz la cartola del trabajador, el cierre del período también».
--
-- POR QUÉ UN CIERRE, Y NO SÓLO UNA CONSULTA
-- `fn_taller_bono_resumen` calcula el bono en vivo: pregunta hoy y responde con
-- los datos de hoy. Eso sirve para mirar el mes en curso, y NO sirve para pagar.
-- Si una OT se reabre en octubre, el bono de septiembre cambiaría solo, después
-- de haberse pagado, y nadie se enteraría. Un pago tiene que apoyarse en un
-- número que ya no se mueve.
--
-- El cierre congela: copia línea por línea lo que el motor calculó ese día, con
-- los parámetros de ese día y la disponibilidad de ese día. Después de cerrado,
-- el período responde siempre lo mismo aunque el mundo cambie detrás.
--
-- LAS CUATRO CERRADURAS DEL CIERRE
--
--   1. NO SE CIERRA CON PARÁMETROS EN BORRADOR. Mientras el acta no exista, los
--      topes y la curva son una propuesta. Cerrar sobre una propuesta sería
--      exactamente la discrecionalidad que esto viene a terminar.
--
--   2. NO SE CIERRA CON HUECOS. Si alguna línea dice «falta el cargo de X» o
--      «no se pudo deducir el concepto», el cierre se niega y nombra qué falta.
--      Un bono no se paga a medias: se arregla el dato y se cierra.
--
--   3. NO SE PISAN DOS PERÍODOS. Dos cortes que se solapan pagarían el mismo
--      trabajo dos veces.
--
--   4. REABRIR DEJA RASTRO. Se puede —los errores existen— pero exige motivo
--      escrito, queda quién y cuándo, y el período pasa a 'reabierto' para
--      siempre. No hay forma de volver a un cierre limpio sin que se note.
--
-- LA CARTOLA
-- Es lo que el mecánico ve en su teléfono: sus OT del corte, cuántos días tomó
-- cada una, en qué tramo cayó, cuánto pagó, y las dos mitades sumadas. Si el
-- período está cerrado lee lo congelado; si no, calcula en vivo y se declara
-- borrador. Y trae un acuse de recibo: el trabajador marca que la revisó, con
-- comentario si no está de acuerdo. Eso es lo que hoy no existe y es la razón
-- por la que el sistema es discrecional: nadie firma nada.
--
-- Cada quien ve LO SUYO. Ver la cartola de otro exige rol de jefatura.
-- ============================================================================

BEGIN;

-- ── 1 · El período cerrado ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_bono_periodo (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre                TEXT NOT NULL,
    desde                 DATE NOT NULL,
    hasta                 DATE NOT NULL,
    parametros_id         UUID NOT NULL REFERENCES taller_bono_parametros(id),
    disponibilidad_pct    NUMERIC,
    disponibilidad_fuente TEXT NOT NULL DEFAULT 'medida por el sistema',
    estado                TEXT NOT NULL DEFAULT 'cerrado',
    total_clp             NUMERIC NOT NULL DEFAULT 0,
    notas                 TEXT,
    cerrado_por           UUID REFERENCES usuarios_perfil(id),
    cerrado_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reabierto_por         UUID REFERENCES usuarios_perfil(id),
    reabierto_at          TIMESTAMPTZ,
    motivo_reapertura     TEXT,
    CONSTRAINT chk_bono_periodo_estado CHECK (estado IN ('cerrado','reabierto')),
    CONSTRAINT chk_bono_periodo_fechas CHECK (hasta >= desde)
);

-- La línea del trabajador: una por persona, congelada.
CREATE TABLE IF NOT EXISTS taller_bono_periodo_linea (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    periodo_id       UUID NOT NULL REFERENCES taller_bono_periodo(id) ON DELETE CASCADE,
    tecnico_id       UUID NOT NULL REFERENCES taller_tecnicos(id),
    tecnico          TEXT NOT NULL,
    cargo            TEXT,
    ots              INT  NOT NULL DEFAULT 0,
    plan_formula     NUMERIC,
    plan_calculado   NUMERIC,
    plan_tope        NUMERIC,
    plan_pagado      NUMERIC,
    kpi_pagado       NUMERIC,
    total            NUMERIC,
    dias_cargo       INT,
    dias_corte       INT,
    tramo            TEXT,
    falta            TEXT,
    acuse_at         TIMESTAMPTZ,
    acuse_por        UUID REFERENCES usuarios_perfil(id),
    acuse_comentario TEXT,
    UNIQUE (periodo_id, tecnico_id)
);

-- El detalle: por qué esa línea da ese número. Sin esto la cartola es un monto
-- sin explicación, que es justo lo que hoy recibe el trabajador.
CREATE TABLE IF NOT EXISTS taller_bono_periodo_detalle (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    periodo_id      UUID NOT NULL REFERENCES taller_bono_periodo(id) ON DELETE CASCADE,
    tecnico_id      UUID NOT NULL REFERENCES taller_tecnicos(id),
    ot_id           UUID,
    ot_folio        TEXT,
    concepto        TEXT,
    dias            NUMERIC,
    tramo           TEXT,
    participacion   NUMERIC,
    base_reparto    TEXT,
    monto_formula   NUMERIC,
    monto_propuesto NUMERIC,
    falta           TEXT
);

CREATE INDEX IF NOT EXISTS idx_bono_periodo_linea_tecnico
    ON taller_bono_periodo_linea (tecnico_id);
CREATE INDEX IF NOT EXISTS idx_bono_periodo_detalle_tecnico
    ON taller_bono_periodo_detalle (periodo_id, tecnico_id);

COMMENT ON TABLE taller_bono_periodo IS
    'Corte de bono congelado. Se cierra una vez, con los parámetros y la '
    'disponibilidad de ese día. Reabrir exige motivo y deja rastro.';

-- ── 2 · Quién soy yo en el taller ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_tecnico_de_usuario(p_user UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT t.id FROM taller_tecnicos t
     WHERE t.usuario_perfil_id = p_user AND COALESCE(t.activo, TRUE)
     LIMIT 1;
$$;

-- ── 3 · Cerrar el período ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_cerrar_periodo(
    p_nombre         TEXT,
    p_desde          DATE,
    p_hasta          DATE,
    p_disponibilidad NUMERIC DEFAULT NULL,
    p_notas          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_par    UUID;
    v_estado TEXT;
    v_faltan TEXT;
    v_solapa TEXT;
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

    -- Cerradura 3: dos cortes que se pisan pagarían el mismo trabajo dos veces.
    SELECT string_agg(nombre || ' (' || desde || ' a ' || hasta || ')', ', ')
      INTO v_solapa
      FROM taller_bono_periodo
     WHERE desde <= p_hasta AND hasta >= p_desde;
    IF v_solapa IS NOT NULL THEN
        RAISE EXCEPTION 'Este corte se pisa con otro que ya está cerrado: %.', v_solapa;
    END IF;

    -- Cerradura 1: no se cierra sobre una propuesta.
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

    -- Cerradura 2: no se cierra con huecos.
    SELECT string_agg(DISTINCT r.tecnico || ': ' || r.falta, ' · ')
      INTO v_faltan
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r
     WHERE r.falta IS NOT NULL;
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta información para cerrar. %', v_faltan;
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
        plan_tope, plan_pagado, kpi_pagado, total, dias_cargo, dias_corte, tramo, falta)
    SELECT v_per, r.tecnico_id, r.tecnico, r.cargo, r.ots, r.plan_formula,
           r.plan_calculado, r.plan_tope, r.plan_pagado, r.kpi_pagado, r.total,
           r.dias_cargo, r.dias_corte, r.tramo, r.falta
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r;

    INSERT INTO taller_bono_periodo_detalle (
        periodo_id, tecnico_id, ot_id, ot_folio, concepto, dias, tramo,
        participacion, base_reparto, monto_formula, monto_propuesto, falta)
    SELECT v_per, b.tecnico_id, b.ot_id, b.ot_folio, b.concepto, b.dias, b.tramo,
           b.participacion, b.base_reparto, b.monto_formula, b.monto_propuesto, b.falta
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b;

    SELECT COALESCE(sum(total), 0), count(*) INTO v_total, v_n
      FROM taller_bono_periodo_linea WHERE periodo_id = v_per;

    UPDATE taller_bono_periodo SET total_clp = v_total WHERE id = v_per;

    RETURN jsonb_build_object('success', true, 'periodo_id', v_per,
                              'personas', v_n, 'total_clp', v_total);
END;
$$;

-- ── 4 · Reabrir, dejando rastro ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_reabrir_periodo(
    p_periodo_id UUID,
    p_motivo     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Reabrir un período pagado es de gerencia, no de jefatura de taller.';
    END IF;

    IF length(COALESCE(TRIM(p_motivo), '')) < 10 THEN
        RAISE EXCEPTION 'Escribe por qué se reabre este período. Queda en el registro.';
    END IF;

    UPDATE taller_bono_periodo
       SET estado = 'reabierto', reabierto_por = v_user, reabierto_at = NOW(),
           motivo_reapertura = TRIM(p_motivo)
     WHERE id = p_periodo_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Ese período no existe.'; END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 5 · La cartola ──────────────────────────────────────────────────────────
--
-- Sin argumentos devuelve la del que pregunta. Con `p_tecnico_id` exige rol de
-- jefatura: el bono de otro no es información de pasillo.
CREATE OR REPLACE FUNCTION rpc_taller_bono_cartola(
    p_desde      DATE,
    p_hasta      DATE,
    p_tecnico_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT;
    v_tec   UUID;
    v_per   RECORD;
    v_lin   JSONB;
    v_det   JSONB;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();

    IF p_tecnico_id IS NULL THEN
        v_tec := fn_taller_tecnico_de_usuario(v_user);
        IF v_tec IS NULL THEN
            RAISE EXCEPTION 'Tu cuenta no está vinculada a un técnico del taller, '
                            'así que no tiene cartola. Lo vincula Admin → Perfiles y roles.';
        END IF;
    ELSE
        IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                         'jefe_mantenimiento','planificador') THEN
            RAISE EXCEPTION 'No puedes ver la cartola de otra persona.';
        END IF;
        v_tec := p_tecnico_id;
    END IF;

    -- ¿Hay un corte cerrado que cubra exactamente estas fechas?
    SELECT * INTO v_per FROM taller_bono_periodo
     WHERE desde = p_desde AND hasta = p_hasta
     ORDER BY cerrado_at DESC LIMIT 1;

    IF v_per.id IS NOT NULL THEN
        SELECT to_jsonb(l) INTO v_lin
          FROM taller_bono_periodo_linea l
         WHERE l.periodo_id = v_per.id AND l.tecnico_id = v_tec;

        SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.ot_folio), '[]'::jsonb) INTO v_det
          FROM taller_bono_periodo_detalle d
         WHERE d.periodo_id = v_per.id AND d.tecnico_id = v_tec;

        RETURN jsonb_build_object(
            'cerrado', true,
            'borrador', false,
            'periodo', jsonb_build_object(
                'id', v_per.id, 'nombre', v_per.nombre,
                'desde', v_per.desde, 'hasta', v_per.hasta,
                'estado', v_per.estado,
                'disponibilidad_pct', v_per.disponibilidad_pct,
                'disponibilidad_fuente', v_per.disponibilidad_fuente,
                'cerrado_at', v_per.cerrado_at,
                'cerrado_por', (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = v_per.cerrado_por),
                'motivo_reapertura', v_per.motivo_reapertura),
            'linea', v_lin,
            'detalle', v_det);
    END IF;

    -- Sin cierre: se calcula en vivo y se dice que es borrador.
    SELECT to_jsonb(r) INTO v_lin
      FROM fn_taller_bono_resumen(p_desde, p_hasta) r
     WHERE r.tecnico_id = v_tec;

    SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.ot_folio), '[]'::jsonb) INTO v_det
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b
     WHERE b.tecnico_id = v_tec;

    RETURN jsonb_build_object(
        'cerrado', false,
        'borrador', true,
        'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),
        'linea', v_lin,
        'detalle', v_det);
END;
$$;

-- ── 6 · El acuse: el trabajador firma que la revisó ─────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_acusar_recibo(
    p_linea_id   UUID,
    p_comentario TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_tec  UUID;
    v_due  UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT tecnico_id INTO v_due FROM taller_bono_periodo_linea WHERE id = p_linea_id;
    IF v_due IS NULL THEN RAISE EXCEPTION 'Esa cartola no existe.'; END IF;

    v_tec := fn_taller_tecnico_de_usuario(v_user);
    IF v_tec IS DISTINCT FROM v_due THEN
        RAISE EXCEPTION 'Sólo el dueño de la cartola puede acusar recibo.';
    END IF;

    UPDATE taller_bono_periodo_linea
       SET acuse_at = NOW(), acuse_por = v_user,
           acuse_comentario = NULLIF(TRIM(COALESCE(p_comentario, '')), '')
     WHERE id = p_linea_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 7 · Listar los cortes ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_periodos()
RETURNS TABLE (
    id            UUID,
    nombre        TEXT,
    desde         DATE,
    hasta         DATE,
    estado        TEXT,
    total_clp     NUMERIC,
    personas      INT,
    acusadas      INT,
    disponibilidad_pct NUMERIC,
    cerrado_at    TIMESTAMPTZ,
    cerrado_por   TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p.id, p.nombre, p.desde, p.hasta, p.estado, p.total_clp,
           (SELECT count(*)::INT FROM taller_bono_periodo_linea l WHERE l.periodo_id = p.id),
           (SELECT count(*)::INT FROM taller_bono_periodo_linea l WHERE l.periodo_id = p.id AND l.acuse_at IS NOT NULL),
           p.disponibilidad_pct, p.cerrado_at,
           (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = p.cerrado_por)
      FROM taller_bono_periodo p
     ORDER BY p.desde DESC;
$$;

-- ── Permisos ────────────────────────────────────────────────────────────────
ALTER TABLE taller_bono_periodo          ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_bono_periodo_linea    ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_bono_periodo_detalle  ENABLE ROW LEVEL SECURITY;
-- Sin políticas: se llega sólo por los RPC, que son SECURITY DEFINER y filtran
-- por persona. Es lo mismo que hace el resto del módulo.

REVOKE ALL ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_reabrir_periodo(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_cartola(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_acusar_recibo(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_periodos() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_tecnico_de_usuario(UUID) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION rpc_taller_bono_cerrar_periodo(TEXT, DATE, DATE, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_reabrir_periodo(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_cartola(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_acusar_recibo(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_periodos() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_tecnico_de_usuario(UUID) TO authenticated;

-- ── Verificación (sólo lectura: escribir acá haría rollback de todo) ────────
DO $mig$
DECLARE
    v_n INT; v_sin INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('rpc_taller_bono_cerrar_periodo','rpc_taller_bono_reabrir_periodo',
                         'rpc_taller_bono_cartola','rpc_taller_bono_acusar_recibo',
                         'rpc_taller_bono_periodos','fn_taller_tecnico_de_usuario');
    IF v_n <> 6 THEN RAISE EXCEPTION 'FALLO: faltan funciones del cierre (%)', v_n; END IF;

    -- Quién podría abrir su cartola hoy: hace falta la cuenta vinculada al técnico.
    SELECT count(*) FILTER (WHERE t.usuario_perfil_id IS NOT NULL),
           count(*) FILTER (WHERE t.usuario_perfil_id IS NULL)
      INTO v_n, v_sin
      FROM taller_tecnicos t WHERE COALESCE(t.activo, TRUE);
    RAISE NOTICE 'técnicos con cuenta vinculada (verán su cartola): %', v_n;
    RAISE NOTICE 'técnicos SIN cuenta vinculada (no podrán entrar):  %', v_sin;

    IF v_sin > 0 THEN
        SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre) INTO r
          FROM taller_tecnicos t
         WHERE COALESCE(t.activo, TRUE) AND t.usuario_perfil_id IS NULL;
        RAISE NOTICE '   son: %', r;
    END IF;

    -- El estado en que quedan los parámetros decide si hoy se puede cerrar algo.
    SELECT count(*) INTO v_n FROM taller_bono_parametros WHERE estado = 'vigente';
    IF v_n = 0 THEN
        RAISE NOTICE 'ningún juego de parámetros está vigente: hoy el cierre se niega, '
                     'como corresponde hasta que exista el acta';
    END IF;
END
$mig$;

COMMIT;
