-- ============================================================================
-- MIG668 · Actividades del camión con evidencia + Gantt del taller + pantalla TV
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (05-11-2026): al taller se le pasó sacar una revisión técnica.
-- Quiere un televisor con un Gantt por camión donde aparezca lo que indique el
-- planificador (lavado, mantención, RT) y que cada cosa exija evidencia.
--
-- POR QUÉ NO ES UNA FILA MÁS DEL PLAN SEMANAL
-- Las 6 RT planificadas hasta hoy son tareas libres con la patente escrita a mano
-- (5 sin OT y 1 colgada de la ficha genérica EXT-SERV-CQB). Ninguna quedó ligada
-- al camión ni al papel, y todas siguen «planificada». Tampoco se pueden colgar de
-- una OT del camión: el trigger de estado por OT lo marcaría en mantención (MIG608).
-- Por eso la actividad va directo al activo, sin OT.
--
-- REGLAS (decididas por Manuel el 05-11-2026)
--  · Sin evidencia no queda cerrada. Lavado: basta la foto. Papeles: aprueba el
--    jefe de taller, y al aprobar se renueva el papel por la puerta de siempre
--    (rpc_renovar_certificacion), así la ficha y el QR lo ven al tiro.
--  · Una actividad atrasada NO se mueve sola: queda roja hasta que el planificador
--    la reprograme con motivo.
--  · Si alguien sube el papel directo desde la ficha, la actividad se cierra sola.
--
-- La pantalla entra con un token revocable y sin sesión: dar una sesión de Supabase
-- a un PC parado en el taller abriría casi todo el sistema (ver MIG609).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_taller_hoy()
RETURNS DATE LANGUAGE sql STABLE AS $$
    SELECT (NOW() AT TIME ZONE 'America/Santiago')::date
$$;

-- Jefe de taller: Rodrigo usa una cuenta genérica de uno de estos dos roles.
CREATE OR REPLACE FUNCTION public.fn_taller_actividad_aprueba()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_user_rol() IN ('jefe_mantenimiento','jefe_operaciones','administrador','subgerente_operaciones')
$$;
GRANT EXECUTE ON FUNCTION public.fn_taller_actividad_aprueba() TO authenticated;

CREATE TABLE IF NOT EXISTS public.taller_actividad_tipos (
    codigo              TEXT PRIMARY KEY,
    nombre              TEXT NOT NULL,
    corto               TEXT NOT NULL,
    evidencia           TEXT NOT NULL CHECK (evidencia IN ('foto','certificado')),
    cert_tipo           public.tipo_certificacion_enum,
    requiere_aprobacion BOOLEAN NOT NULL DEFAULT FALSE,
    orden               INT NOT NULL DEFAULT 100,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK ((evidencia = 'certificado') = (cert_tipo IS NOT NULL))
);

INSERT INTO public.taller_actividad_tipos (codigo, nombre, corto, evidencia, cert_tipo, requiere_aprobacion, orden) VALUES
    ('lavado',           'Lavado',            'Lavado',  'foto',        NULL,               FALSE, 10),
    ('revision_tecnica', 'Revisión técnica',  'RT',      'certificado', 'revision_tecnica', TRUE,  20),
    ('analisis_gases',   'Análisis de gases', 'Gases',   'certificado', 'analisis_gases',   TRUE,  30),
    ('hermeticidad',     'Hermeticidad',      'Hermet.', 'certificado', 'hermeticidad',     TRUE,  40),
    ('tc8_sec',          'TC8',               'TC8',     'certificado', 'tc8_sec',          TRUE,  50)
ON CONFLICT (codigo) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.taller_actividades (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id        UUID NOT NULL REFERENCES public.activos(id),
    tipo             TEXT NOT NULL REFERENCES public.taller_actividad_tipos(codigo),
    fecha_inicio     DATE NOT NULL,
    fecha_fin        DATE NOT NULL,
    tecnico_id       UUID NOT NULL REFERENCES public.taller_tecnicos(id),
    notas            TEXT,
    estado           TEXT NOT NULL DEFAULT 'programada'
                     CHECK (estado IN ('programada','hecha','por_aprobar','cerrada','cancelada')),
    hecha_at         TIMESTAMPTZ,
    hecha_por        UUID,
    fotos            JSONB NOT NULL DEFAULT '[]'::jsonb,
    cert_archivo_url TEXT,
    cert_emision     DATE,
    cert_vencimiento DATE,
    cert_numero      TEXT,
    evidencia_at     TIMESTAMPTZ,
    evidencia_por    UUID,
    rechazo_motivo   TEXT,
    aprobada_at      TIMESTAMPTZ,
    aprobada_por     UUID,
    certificacion_id UUID REFERENCES public.certificaciones(id),
    created_by       UUID DEFAULT auth.uid(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (fecha_fin >= fecha_inicio)
);
CREATE INDEX IF NOT EXISTS ix_taller_actividades_activo ON public.taller_actividades (activo_id, fecha_inicio);
CREATE INDEX IF NOT EXISTS ix_taller_actividades_tecnico ON public.taller_actividades (tecnico_id)
    WHERE estado IN ('programada','hecha','por_aprobar');
-- Dos RT abiertas para el mismo camión es la forma de que nadie sepa cuál manda.
CREATE UNIQUE INDEX IF NOT EXISTS uq_taller_actividad_abierta ON public.taller_actividades (activo_id, tipo)
    WHERE estado IN ('programada','hecha','por_aprobar');

CREATE TABLE IF NOT EXISTS public.taller_actividad_eventos (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actividad_id UUID NOT NULL REFERENCES public.taller_actividades(id) ON DELETE CASCADE,
    evento       TEXT NOT NULL,
    detalle      TEXT,
    por          UUID DEFAULT auth.uid(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_taller_actividad_eventos ON public.taller_actividad_eventos (actividad_id, created_at);

CREATE TABLE IF NOT EXISTS public.pantalla_taller_accesos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token       TEXT NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
    nombre      TEXT NOT NULL,
    operacion   TEXT NOT NULL,
    created_by  UUID DEFAULT auth.uid(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revocado_at TIMESTAMPTZ
);

-- Todo se escribe y se lee por funciones: sin acceso directo a estas tablas.
ALTER TABLE public.taller_actividad_tipos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taller_actividades       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taller_actividad_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pantalla_taller_accesos  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.taller_actividades, public.taller_actividad_eventos, public.pantalla_taller_accesos FROM anon, authenticated;
REVOKE ALL ON public.taller_actividad_tipos FROM anon, authenticated;
GRANT SELECT ON public.taller_actividad_tipos TO authenticated;
DROP POLICY IF EXISTS pol_taller_actividad_tipos_sel ON public.taller_actividad_tipos;
CREATE POLICY pol_taller_actividad_tipos_sel ON public.taller_actividad_tipos FOR SELECT TO authenticated USING (TRUE);

-- ── Planificar ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_crear(
    p_activo_id UUID, p_tipo TEXT, p_inicio DATE, p_fin DATE, p_tecnico_id UUID,
    p_notas TEXT DEFAULT NULL, p_motivo TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_id UUID;
    v_motivo TEXT := NULLIF(btrim(COALESCE(p_motivo, '')), '');
BEGIN
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Planificar actividades es de la jefatura de taller o planificación.' USING ERRCODE = '42501';
    END IF;
    IF p_inicio IS NULL OR p_fin IS NULL OR p_fin < p_inicio THEN
        RAISE EXCEPTION 'Revisa las fechas: el término no puede ser anterior al inicio.';
    END IF;
    -- La RT del SVCZ-38 se cargó el 05-11 con fecha 04-11: cuando ya no servía de aviso.
    IF p_inicio < fn_taller_hoy() AND (v_motivo IS NULL OR length(v_motivo) < 5) THEN
        RAISE EXCEPTION 'Para planificar en una fecha pasada hay que escribir el motivo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM taller_actividad_tipos WHERE codigo = p_tipo AND activo) THEN
        RAISE EXCEPTION 'Tipo de actividad no válido.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM taller_tecnicos WHERE id = p_tecnico_id AND activo) THEN
        RAISE EXCEPTION 'Elige quién es el responsable.';
    END IF;
    IF EXISTS (SELECT 1 FROM taller_actividades WHERE activo_id = p_activo_id AND tipo = p_tipo
                  AND estado IN ('programada','hecha','por_aprobar')) THEN
        RAISE EXCEPTION 'Este camión ya tiene esa actividad abierta. Reprográmala en vez de crear otra.';
    END IF;
    INSERT INTO taller_actividades (activo_id, tipo, fecha_inicio, fecha_fin, tecnico_id, notas)
    VALUES (p_activo_id, p_tipo, p_inicio, p_fin, p_tecnico_id, NULLIF(btrim(COALESCE(p_notas, '')), ''))
    RETURNING id INTO v_id;
    INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle) VALUES (v_id, 'creada', v_motivo);
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_reprogramar(
    p_id UUID, p_inicio DATE, p_fin DATE, p_tecnico_id UUID DEFAULT NULL, p_motivo TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    a taller_actividades%ROWTYPE;
    v_motivo TEXT := NULLIF(btrim(COALESCE(p_motivo, '')), '');
BEGIN
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Reprogramar es de la jefatura de taller o planificación.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO a FROM taller_actividades WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada.'; END IF;
    IF a.estado <> 'programada' THEN RAISE EXCEPTION 'Solo se reprograma lo que aún no se ha hecho.'; END IF;
    IF p_inicio IS NULL OR p_fin IS NULL OR p_fin < p_inicio THEN
        RAISE EXCEPTION 'Revisa las fechas: el término no puede ser anterior al inicio.';
    END IF;
    -- Lo que ya partió o ya se atrasó no se mueve en silencio.
    IF a.fecha_inicio <= fn_taller_hoy() AND (v_motivo IS NULL OR length(v_motivo) < 5) THEN
        RAISE EXCEPTION 'Esta actividad ya partió o está atrasada: escribe el motivo para moverla.';
    END IF;
    UPDATE taller_actividades
       SET fecha_inicio = p_inicio, fecha_fin = p_fin,
           tecnico_id = COALESCE(p_tecnico_id, tecnico_id), updated_at = NOW()
     WHERE id = p_id;
    INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle)
    VALUES (p_id, 'reprogramada', a.fecha_inicio || ' → ' || p_inicio || COALESCE(' · ' || v_motivo, ''));
END $$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_cancelar(p_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Cancelar es de la jefatura de taller o planificación.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(COALESCE(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
    UPDATE taller_actividades SET estado = 'cancelada', updated_at = NOW()
     WHERE id = p_id AND estado IN ('programada','hecha','por_aprobar');
    IF NOT FOUND THEN RAISE EXCEPTION 'Esta actividad ya está cerrada o cancelada.'; END IF;
    INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle) VALUES (p_id, 'cancelada', btrim(p_motivo));
END $$;

-- ── Ejecutar: quien la tiene asignada, o la jefatura ────────────────────────
CREATE OR REPLACE FUNCTION public.fn_taller_actividad_puede_ejecutar(p_tecnico_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_taller_es_jefatura() OR fn_taller_mi_tecnico_id() = p_tecnico_id
$$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_marcar_hecha(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE a taller_actividades%ROWTYPE;
BEGIN
    SELECT * INTO a FROM taller_actividades WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada.'; END IF;
    IF NOT fn_taller_actividad_puede_ejecutar(a.tecnico_id) THEN
        RAISE EXCEPTION 'Esta actividad está asignada a otra persona.' USING ERRCODE = '42501';
    END IF;
    IF a.estado <> 'programada' THEN RAISE EXCEPTION 'Esta actividad ya no está pendiente.'; END IF;
    UPDATE taller_actividades SET estado = 'hecha', hecha_at = NOW(), hecha_por = auth.uid(), updated_at = NOW()
     WHERE id = p_id;
    INSERT INTO taller_actividad_eventos (actividad_id, evento) VALUES (p_id, 'hecha_sin_evidencia');
END $$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_evidencia_foto(p_id UUID, p_fotos JSONB)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    a taller_actividades%ROWTYPE;
    t taller_actividad_tipos%ROWTYPE;
    v_estado TEXT;
BEGIN
    SELECT * INTO a FROM taller_actividades WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada.'; END IF;
    IF NOT fn_taller_actividad_puede_ejecutar(a.tecnico_id) THEN
        RAISE EXCEPTION 'Esta actividad está asignada a otra persona.' USING ERRCODE = '42501';
    END IF;
    IF a.estado NOT IN ('programada','hecha') THEN RAISE EXCEPTION 'Esta actividad ya tiene evidencia o está cerrada.'; END IF;
    SELECT * INTO t FROM taller_actividad_tipos WHERE codigo = a.tipo;
    IF t.evidencia <> 'foto' THEN RAISE EXCEPTION 'Esta actividad se cierra con el certificado, no con una foto.'; END IF;
    IF jsonb_typeof(p_fotos) <> 'array' OR jsonb_array_length(p_fotos) = 0 THEN
        RAISE EXCEPTION 'Sube al menos una foto.';
    END IF;
    v_estado := CASE WHEN t.requiere_aprobacion THEN 'por_aprobar' ELSE 'cerrada' END;
    UPDATE taller_actividades
       SET estado = v_estado, fotos = p_fotos, evidencia_at = NOW(), evidencia_por = auth.uid(),
           hecha_at = COALESCE(hecha_at, NOW()), hecha_por = COALESCE(hecha_por, auth.uid()),
           rechazo_motivo = NULL, updated_at = NOW()
     WHERE id = p_id;
    INSERT INTO taller_actividad_eventos (actividad_id, evento) VALUES (p_id, 'evidencia_foto');
    RETURN v_estado;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_evidencia_cert(
    p_id UUID, p_archivo_url TEXT, p_emision DATE, p_vencimiento DATE, p_numero TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    a taller_actividades%ROWTYPE;
    t taller_actividad_tipos%ROWTYPE;
BEGIN
    SELECT * INTO a FROM taller_actividades WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada.'; END IF;
    IF NOT fn_taller_actividad_puede_ejecutar(a.tecnico_id) THEN
        RAISE EXCEPTION 'Esta actividad está asignada a otra persona.' USING ERRCODE = '42501';
    END IF;
    IF a.estado NOT IN ('programada','hecha') THEN RAISE EXCEPTION 'Esta actividad ya tiene evidencia o está cerrada.'; END IF;
    SELECT * INTO t FROM taller_actividad_tipos WHERE codigo = a.tipo;
    IF t.evidencia <> 'certificado' THEN RAISE EXCEPTION 'Esta actividad se cierra con una foto.'; END IF;
    IF COALESCE(p_archivo_url, '') = '' THEN RAISE EXCEPTION 'Sube el certificado.'; END IF;
    IF p_emision IS NULL OR p_vencimiento IS NULL THEN RAISE EXCEPTION 'Faltan las fechas del certificado.'; END IF;
    -- El SVCZ-38 quedó con emisión = vencimiento = 04-11: un papel así no debe entrar.
    IF p_emision > fn_taller_hoy() THEN RAISE EXCEPTION 'La emisión no puede ser una fecha futura.'; END IF;
    IF p_vencimiento <= p_emision THEN RAISE EXCEPTION 'El vencimiento debe ser posterior a la emisión.'; END IF;
    IF p_vencimiento <= fn_taller_hoy() THEN RAISE EXCEPTION 'Ese certificado ya está vencido.'; END IF;
    UPDATE taller_actividades
       SET estado = 'por_aprobar', cert_archivo_url = p_archivo_url, cert_emision = p_emision,
           cert_vencimiento = p_vencimiento, cert_numero = NULLIF(btrim(COALESCE(p_numero, '')), ''),
           evidencia_at = NOW(), evidencia_por = auth.uid(),
           hecha_at = COALESCE(hecha_at, NOW()), hecha_por = COALESCE(hecha_por, auth.uid()),
           rechazo_motivo = NULL, updated_at = NOW()
     WHERE id = p_id;
    INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle)
    VALUES (p_id, 'evidencia_certificado', 'Vence ' || p_vencimiento);
END $$;

-- ── Aprobar ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_aprobar(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    a taller_actividades%ROWTYPE;
    t taller_actividad_tipos%ROWTYPE;
    v_bloq BOOLEAN;
BEGIN
    IF NOT fn_taller_actividad_aprueba() THEN
        RAISE EXCEPTION 'Aprobar la evidencia es del jefe de taller.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO a FROM taller_actividades WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada.'; END IF;
    IF a.estado <> 'por_aprobar' THEN RAISE EXCEPTION 'Esta actividad no está esperando aprobación.'; END IF;
    SELECT * INTO t FROM taller_actividad_tipos WHERE codigo = a.tipo;

    UPDATE taller_actividades SET aprobada_at = NOW(), aprobada_por = auth.uid(), updated_at = NOW() WHERE id = p_id;
    IF t.evidencia = 'certificado' THEN
        -- Conserva si el papel de ese camión era bloqueante: la RPC solo asume
        -- bloqueantes RT, SOAP y permiso, y una hermeticidad dejaría de bloquear.
        SELECT c.bloqueante INTO v_bloq FROM certificaciones c
         WHERE c.activo_id = a.activo_id AND c.tipo = t.cert_tipo AND c.anulado_at IS NULL
         ORDER BY c.fecha_vencimiento DESC LIMIT 1;
        -- El trigger de certificaciones cierra la actividad.
        PERFORM rpc_renovar_certificacion(
            p_activo_id => a.activo_id, p_tipo => t.cert_tipo,
            p_fecha_emision => a.cert_emision, p_fecha_vencimiento => a.cert_vencimiento,
            p_archivo_url => a.cert_archivo_url, p_numero => a.cert_numero,
            p_bloqueante => v_bloq, p_notas => 'Actividad del taller aprobada', p_origen => 'manual');
    ELSE
        UPDATE taller_actividades SET estado = 'cerrada', updated_at = NOW() WHERE id = p_id;
        INSERT INTO taller_actividad_eventos (actividad_id, evento) VALUES (p_id, 'aprobada');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_taller_actividad_rechazar(p_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_taller_actividad_aprueba() THEN
        RAISE EXCEPTION 'Rechazar la evidencia es del jefe de taller.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(COALESCE(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Escribe por qué se rechaza.'; END IF;
    UPDATE taller_actividades
       SET estado = 'hecha', rechazo_motivo = btrim(p_motivo), fotos = '[]'::jsonb,
           cert_archivo_url = NULL, cert_emision = NULL, cert_vencimiento = NULL, cert_numero = NULL,
           evidencia_at = NULL, evidencia_por = NULL, updated_at = NOW()
     WHERE id = p_id AND estado = 'por_aprobar';
    IF NOT FOUND THEN RAISE EXCEPTION 'Esta actividad no está esperando aprobación.'; END IF;
    INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle) VALUES (p_id, 'rechazada', btrim(p_motivo));
END $$;

-- Un papel vigente que entra por cualquier puerta cierra la actividad abierta.
CREATE OR REPLACE FUNCTION public.fn_certificacion_cierra_actividad()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r RECORD;
BEGIN
    IF NEW.anulado_at IS NOT NULL OR NEW.fecha_vencimiento <= fn_taller_hoy() THEN RETURN NEW; END IF;
    FOR r IN
        UPDATE taller_actividades a
           SET estado = 'cerrada', certificacion_id = NEW.id, updated_at = NOW(),
               evidencia_at = COALESCE(a.evidencia_at, NOW()),
               cert_archivo_url = COALESCE(a.cert_archivo_url, NEW.archivo_url),
               cert_emision = COALESCE(a.cert_emision, NEW.fecha_emision),
               cert_vencimiento = COALESCE(a.cert_vencimiento, NEW.fecha_vencimiento)
          FROM taller_actividad_tipos t
         WHERE t.codigo = a.tipo AND t.cert_tipo = NEW.tipo AND a.activo_id = NEW.activo_id
           AND a.estado IN ('programada','hecha','por_aprobar')
        RETURNING a.id
    LOOP
        INSERT INTO taller_actividad_eventos (actividad_id, evento, detalle)
        VALUES (r.id, 'cerrada_por_papel', 'Vence ' || NEW.fecha_vencimiento);
    END LOOP;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_certificacion_cierra_actividad ON public.certificaciones;
CREATE TRIGGER trg_certificacion_cierra_actividad
    AFTER INSERT ON public.certificaciones
    FOR EACH ROW EXECUTE FUNCTION public.fn_certificacion_cierra_actividad();

-- ── Lo que ve el mecánico en su teléfono ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_mis_actividades()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', a.id, 'activo_id', a.activo_id, 'patente', x.patente, 'tipo', a.tipo,
               'nombre', t.nombre, 'evidencia', t.evidencia, 'estado', a.estado,
               'fecha_inicio', a.fecha_inicio, 'fecha_fin', a.fecha_fin, 'notas', a.notas,
               'responsable', tc.nombre, 'rechazo_motivo', a.rechazo_motivo,
               'cert_tipo', t.cert_tipo
           ) ORDER BY a.fecha_inicio, x.patente), '[]'::jsonb)
      FROM taller_actividades a
      JOIN taller_actividad_tipos t ON t.codigo = a.tipo
      JOIN activos x ON x.id = a.activo_id
      JOIN taller_tecnicos tc ON tc.id = a.tecnico_id
     WHERE a.estado IN ('programada','hecha')
       AND (a.tecnico_id = fn_taller_mi_tecnico_id() OR fn_taller_es_jefatura())
$$;

-- ── El Gantt: una sola función para el planificador y para la TV ────────────
-- Filas: lo que está en M/T/F y todo camión con una actividad en la ventana.
-- Barras: actividades y jornadas del plan de sus OT, sin inventar otra verdad.
CREATE OR REPLACE FUNCTION public.fn_taller_gantt_json(p_desde DATE, p_hasta DATE, p_operacion TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
WITH hoy AS (SELECT fn_taller_hoy() AS d),
taller AS (
    SELECT m.activo_id, m.estado_codigo, m.dias_mantencion
      FROM fn_flota_en_mantenimiento() m
      JOIN activos a ON a.id = m.activo_id
     WHERE a.operacion = p_operacion AND NOT COALESCE(a.es_prueba, FALSE)
),
act AS (
    SELECT a.*, t.nombre AS tipo_nombre, t.corto, t.evidencia AS tipo_evidencia, t.requiere_aprobacion,
           tc.nombre AS responsable
      FROM taller_actividades a
      JOIN taller_actividad_tipos t ON t.codigo = a.tipo
      JOIN taller_tecnicos tc ON tc.id = a.tecnico_id
      JOIN activos x ON x.id = a.activo_id
     WHERE x.operacion = p_operacion AND a.estado <> 'cancelada'
       AND (a.estado IN ('programada','hecha','por_aprobar')
            OR (a.fecha_inicio <= p_hasta AND a.fecha_fin >= p_desde))
),
filas AS (
    SELECT t.activo_id, t.estado_codigo, t.dias_mantencion, TRUE AS en_taller FROM taller t
    UNION ALL
    SELECT DISTINCT a.activo_id, e.estado_codigo, NULL::int, FALSE
      FROM act a
      LEFT JOIN v_activos_estado_planificador e ON e.activo_id = a.activo_id
     WHERE a.activo_id NOT IN (SELECT activo_id FROM taller)
),
papeles AS (
    SELECT c.activo_id,
           jsonb_agg(jsonb_build_object('tipo', c.tipo, 'etiqueta', COALESCE(c.etiqueta, c.tipo::text),
                                        'estado', c.estado, 'dias', c.dias_restantes,
                                        'vence', c.fecha_vencimiento)
                     ORDER BY CASE c.estado::text WHEN 'vencido' THEN 0 WHEN 'por_vencer' THEN 1 ELSE 2 END,
                              c.dias_restantes NULLS LAST) AS lista,
           bool_or(c.estado::text = 'vencido') AS hay_vencido,
           bool_or(c.estado::text IN ('por_vencer','sin_fecha')) AS hay_por_vencer
      FROM v_control_documental c
     WHERE c.activo_id IN (SELECT activo_id FROM filas) AND c.bloqueante
       AND c.estado::text IN ('vencido','por_vencer','sin_fecha')
     GROUP BY c.activo_id
),
barras_act AS (
    SELECT a.activo_id, jsonb_build_object(
               'id', a.id, 'origen', 'actividad', 'tipo', a.tipo, 'titulo', a.tipo_nombre, 'corto', a.corto,
               'inicio', a.fecha_inicio, 'fin', a.fecha_fin, 'responsable', a.responsable,
               'tecnico_id', a.tecnico_id, 'estado', a.estado, 'evidencia', a.tipo_evidencia,
               'notas', a.notas, 'rechazo_motivo', a.rechazo_motivo,
               'fotos', a.fotos, 'cert_archivo_url', a.cert_archivo_url,
               'cert_emision', a.cert_emision, 'cert_vencimiento', a.cert_vencimiento, 'cert_numero', a.cert_numero,
               'vista', CASE
                   WHEN a.estado = 'cerrada' THEN 'ok'
                   WHEN a.estado = 'por_aprobar' THEN 'por_aprobar'
                   WHEN a.estado = 'hecha' THEN 'falta'
                   WHEN a.fecha_fin < (SELECT d FROM hoy) THEN 'atraso'
                   WHEN a.fecha_inicio <= (SELECT d FROM hoy) THEN 'hoy'
                   ELSE 'plan' END) AS barra
      FROM act a
),
jornadas AS (
    SELECT o.id AS ot_id, o.activo_id, o.folio, o.tipo::text AS ot_tipo, o.estado::text AS ot_estado,
           min(d.fecha)::date AS inicio, max(d.fecha)::date AS fin,
           (SELECT t.nombre FROM taller_tecnicos t WHERE t.id = o.tecnico_id) AS responsable
      FROM taller_plan_semanal_ots x
      JOIN taller_plan_semanal_dias d ON d.id = x.plan_dia_id
      JOIN ordenes_trabajo o ON o.id = x.ot_id
     WHERE d.fecha BETWEEN p_desde AND p_hasta
       AND x.estado_plan NOT IN ('cancelada','reprogramada','no_ejecutada')
       AND o.estado::text <> 'cancelada' AND o.archivado_at IS NULL
       AND o.activo_id IN (SELECT activo_id FROM filas)
     GROUP BY o.id
),
barras_ot AS (
    SELECT j.activo_id, jsonb_build_object(
               'id', j.ot_id, 'origen', 'ot', 'tipo', j.ot_tipo, 'folio', j.folio,
               'titulo', CASE j.ot_tipo WHEN 'preventivo' THEN 'Preventiva' WHEN 'correctivo' THEN 'Correctivo'
                                        WHEN 'inspeccion' THEN 'Inspección' ELSE initcap(j.ot_tipo) END,
               'corto', CASE j.ot_tipo WHEN 'preventivo' THEN 'Prevent.' WHEN 'correctivo' THEN 'Correct.'
                                       WHEN 'inspeccion' THEN 'Inspec.' ELSE initcap(j.ot_tipo) END,
               'inicio', j.inicio, 'fin', j.fin, 'responsable', j.responsable, 'estado', j.ot_estado,
               'vista', CASE
                   WHEN j.ot_estado = 'cerrada' THEN 'ok'
                   WHEN j.ot_estado IN ('ejecutada_ok','ejecutada_con_observaciones') THEN 'falta'
                   WHEN j.fin < (SELECT d FROM hoy) THEN 'atraso'
                   WHEN j.ot_estado IN ('en_ejecucion','pausada') THEN 'hoy'
                   WHEN j.inicio <= (SELECT d FROM hoy) THEN 'hoy'
                   ELSE 'plan' END) AS barra
      FROM jornadas j
),
barras AS (
    SELECT activo_id, jsonb_agg(barra ORDER BY barra->>'inicio', barra->>'fin') AS lista
      FROM (SELECT * FROM barras_act UNION ALL SELECT * FROM barras_ot) b
     GROUP BY activo_id
),
sin_agendar AS (
    SELECT c.activo_id, c.patente, c.dias_restantes, e.estado_codigo
      FROM v_control_documental c
      JOIN activos a ON a.id = c.activo_id
      JOIN v_activos_estado_planificador e ON e.activo_id = c.activo_id
     WHERE c.tipo::text = 'revision_tecnica' AND c.estado::text IN ('vencido','por_vencer')
       AND c.dias_restantes <= 14
       AND a.operacion = p_operacion AND NOT COALESCE(a.es_prueba, FALSE)
       AND e.estado_codigo NOT IN ('S','V','F')
       AND c.activo_id NOT IN (SELECT activo_id FROM filas)
       AND NOT EXISTS (SELECT 1 FROM taller_actividades x WHERE x.activo_id = c.activo_id
                        AND x.tipo = 'revision_tecnica' AND x.estado IN ('programada','hecha','por_aprobar'))
)
SELECT jsonb_build_object(
    'hoy', (SELECT d FROM hoy), 'desde', p_desde, 'hasta', p_hasta, 'operacion', p_operacion,
    'camiones', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'activo_id', f.activo_id, 'patente', a.patente, 'estado_codigo', f.estado_codigo,
                   'dias', f.dias_mantencion, 'en_taller', f.en_taller,
                   'papeles', COALESCE(p.lista, '[]'::jsonb), 'barras', COALESCE(b.lista, '[]'::jsonb))
                 ORDER BY
                   -- Fuera de servicio sin plan va al final y sin apuro.
                   CASE WHEN f.estado_codigo = 'F' AND b.lista IS NULL THEN 2 WHEN f.en_taller THEN 0 ELSE 1 END,
                   CASE WHEN COALESCE(p.hay_vencido, FALSE) THEN 0 WHEN COALESCE(p.hay_por_vencer, FALSE) THEN 1 ELSE 2 END,
                   f.dias_mantencion DESC NULLS LAST, a.patente)
          FROM filas f
          JOIN activos a ON a.id = f.activo_id
          LEFT JOIN papeles p ON p.activo_id = f.activo_id
          LEFT JOIN barras b ON b.activo_id = f.activo_id), '[]'::jsonb),
    'sin_agendar', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('activo_id', s.activo_id, 'patente', s.patente,
                                            'dias', s.dias_restantes, 'estado_codigo', s.estado_codigo)
                         ORDER BY s.dias_restantes)
          FROM sin_agendar s), '[]'::jsonb)
)
$$;
REVOKE ALL ON FUNCTION public.fn_taller_gantt_json(DATE, DATE, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_taller_gantt(p_desde DATE, p_hasta DATE, p_operacion TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT (fn_taller_es_jefatura() OR fn_tiene_permiso_modulo('mantenimiento', 'view')) THEN
        RAISE EXCEPTION 'Sin permiso para ver el plan del taller.' USING ERRCODE = '42501';
    END IF;
    IF p_hasta - p_desde > 62 THEN RAISE EXCEPTION 'El rango máximo es de 2 meses.'; END IF;
    RETURN fn_taller_gantt_json(p_desde, p_hasta, p_operacion);
END $$;

-- ── La pantalla: 2 semanas desde el lunes, solo con su token ────────────────
CREATE OR REPLACE FUNCTION public.rpc_pantalla_taller(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v pantalla_taller_accesos%ROWTYPE;
    v_lunes DATE := date_trunc('week', fn_taller_hoy())::date;
BEGIN
    SELECT * INTO v FROM pantalla_taller_accesos WHERE token = p_token AND revocado_at IS NULL;
    IF NOT FOUND THEN RETURN jsonb_build_object('valido', FALSE); END IF;
    RETURN fn_taller_gantt_json(v_lunes, v_lunes + 12, v.operacion)
           || jsonb_build_object('valido', TRUE, 'nombre', v.nombre);
END $$;

CREATE OR REPLACE FUNCTION public.rpc_pantalla_taller_listar()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_taller_actividad_aprueba() THEN RETURN '[]'::jsonb; END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'token', token, 'nombre', nombre, 'operacion', operacion)
                                      ORDER BY created_at)
                       FROM pantalla_taller_accesos WHERE revocado_at IS NULL), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.rpc_pantalla_taller_crear(p_nombre TEXT, p_operacion TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_taller_actividad_aprueba() THEN
        RAISE EXCEPTION 'Sin permiso para crear pantallas.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(COALESCE(p_nombre, ''))) < 3 THEN RAISE EXCEPTION 'Ponle un nombre a la pantalla.'; END IF;
    INSERT INTO pantalla_taller_accesos (nombre, operacion) VALUES (btrim(p_nombre), p_operacion) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_pantalla_taller_revocar(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_taller_actividad_aprueba() THEN
        RAISE EXCEPTION 'Sin permiso para revocar pantallas.' USING ERRCODE = '42501';
    END IF;
    UPDATE pantalla_taller_accesos SET revocado_at = NOW() WHERE id = p_id;
END $$;

-- ── Permisos ────────────────────────────────────────────────────────────────
DO $$
DECLARE f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'rpc_taller_actividad_crear(UUID,TEXT,DATE,DATE,UUID,TEXT,TEXT)',
        'rpc_taller_actividad_reprogramar(UUID,DATE,DATE,UUID,TEXT)',
        'rpc_taller_actividad_cancelar(UUID,TEXT)',
        'rpc_taller_actividad_marcar_hecha(UUID)',
        'rpc_taller_actividad_evidencia_foto(UUID,JSONB)',
        'rpc_taller_actividad_evidencia_cert(UUID,TEXT,DATE,DATE,TEXT)',
        'rpc_taller_actividad_aprobar(UUID)',
        'rpc_taller_actividad_rechazar(UUID,TEXT)',
        'rpc_taller_mis_actividades()',
        'rpc_taller_gantt(DATE,DATE,TEXT)',
        'rpc_pantalla_taller_listar()',
        'rpc_pantalla_taller_crear(TEXT,TEXT)',
        'rpc_pantalla_taller_revocar(UUID)'
    ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', f);
    END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.rpc_pantalla_taller(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_pantalla_taller(TEXT) TO anon, authenticated;

-- Fotos en evidencias-verificacion/actividades/ (bucket público, MIG166).
DROP POLICY IF EXISTS "storage_actividades_auth_insert" ON storage.objects;
CREATE POLICY "storage_actividades_auth_insert" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'evidencias-verificacion' AND (storage.foldername(name))[1] = 'actividades');

SELECT count(*) AS tipos FROM public.taller_actividad_tipos;
